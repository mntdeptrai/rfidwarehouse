import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/excel_import_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-End Carton Gate Receive & PDA Putaway Workflow Tests', () {
    test('Gate Read -> WAITING_PUTAWAY -> PDA Barcode Putaway -> IN_STOCK at Location', () async {
      final repo = WarehouseRepository();
      await repo.ensureInitialized();

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final testOrderNo = 'CARTON-WF-$timestamp';
      final testSku = 'SKU-WF-$timestamp';
      const testLocationId = 'LOC-A1-02-01';

      // 1. Tạo đơn hàng hoặc kiện hàng chờ nhập
      final order = InboundOrder(
        inboundOrderId: 'INB-$testOrderNo',
        orderNo: testOrderNo,
        sourceSupplier: 'Nhà Cung Cấp Tổng',
        status: InboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: 'PROD-WF-001',
            sku: testSku,
            productName: 'Sản Phẩm Test Luồng',
            requiredQty: 5,
          ),
        ],
      );

      final generatedItems = await repo.addInboundOrder(order, autoGenerateEpcs: true);
      expect(generatedItems.length, equals(5));
      expect(generatedItems.every((i) => i.status == ItemStatus.pendingInbound), isTrue);

      final scannedEpcs = generatedItems.map((i) => i.epc).toList();

      // 2. GIAI ĐOẠN 1: Kiện hàng đi qua Cổng RFID Gate trên xe Pallet
      final gateReceivedCount = await repo.confirmGateReceiveToWaitingPutaway(
        orderNo: testOrderNo,
        scannedEpcs: scannedEpcs,
        palletCode: 'PAL-$testOrderNo',
        performedBy: 'Trạm Cổng RFID Desktop',
      );

      expect(gateReceivedCount, equals(5));

      // Kiểm tra trạng thái sau khi qua cổng: Chờ xếp kho (WAITING_PUTAWAY), đã được gán mã Barcode thùng/pallet
      final itemsAfterGate = repo.getItemsByOrderNo(testOrderNo);
      expect(itemsAfterGate.length, equals(5));
      expect(itemsAfterGate.every((i) => i.status == ItemStatus.waitingPutaway), isTrue);
      expect(itemsAfterGate.every((i) => i.locationId == null), isTrue);
      expect(itemsAfterGate.every((i) => i.palletId != null && i.palletId!.isNotEmpty), isTrue);

      final orderAfterGate = repo.inboundOrders.where((o) => o.orderNo == testOrderNo).first;
      expect(orderAfterGate.status, equals(InboundOrderStatus.waitingPutaway));

      // 3. GIAI ĐOẠN 2: Thủ kho cầm PDA quét Barcode Vị trí kệ và quét Barcode Thùng hàng
      final putawayCount = await repo.confirmPdaPutawayByCarton(
        cartonOrOrderBarcode: testOrderNo,
        locationId: testLocationId,
        performedBy: 'Thủ kho PDA',
      );

      expect(putawayCount, equals(5));

      // Kiểm tra trạng thái sau khi cất lên kệ: Đang lưu kho (IN_STOCK) và tại đúng vị trí đích
      final itemsAfterPutaway = repo.getItemsByOrderNo(testOrderNo);
      expect(itemsAfterPutaway.every((i) => i.status == ItemStatus.inStock), isTrue);
      expect(itemsAfterPutaway.every((i) => i.locationId == testLocationId), isTrue);

      final orderAfterPutaway = repo.inboundOrders.where((o) => o.orderNo == testOrderNo).first;
      expect(orderAfterPutaway.status, equals(InboundOrderStatus.completed));

      // Kiểm tra nhật ký giao dịch
      final tx = repo.transactions.where((t) => t.documentNo == testOrderNo).firstOrNull;
      expect(tx, isNotNull);
      expect(tx!.type, equals(TransactionType.movement));

      // Dọn dẹp dữ liệu test khỏi SQLite sau khi test xong
      await repo.clearAllData(alsoClearCloud: false);
    });

    test('Excel 4-Column (CARTON CODE, EPC, BARCODE, NAME) -> Putaway via Outer Carton Barcode', () async {
      final repo = WarehouseRepository();
      await repo.ensureInitialized();

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final cartonCode = 'CARTONTEST-$timestamp';
      final outerCartonBarcode = '89300000$timestamp';
      const putawayLocationId = 'LOC-B02-03';

      // 1. Tạo đơn hàng và các item nạp từ file Excel có mã barcode ngoài thùng
      final order = InboundOrder(
        inboundOrderId: 'INB-$cartonCode',
        orderNo: cartonCode,
        sourceSupplier: 'Nhà Cung Cấp',
        status: InboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: outerCartonBarcode,
            sku: outerCartonBarcode,
            productName: 'Product Test 01',
            requiredQty: 3,
          ),
        ],
      );

      await repo.addInboundOrder(order, autoGenerateEpcs: false);

      // Thêm 3 items tương ứng với 3 EPC trong file Excel cho thùng này
      final epc1 = 'ABCDEF${timestamp}01';
      final epc2 = 'ABCDEF${timestamp}02';
      final epc3 = 'ABCDEF${timestamp}03';

      await repo.insertDirectItem(Item(
        itemId: 'ITEM-$epc1',
        productId: outerCartonBarcode,
        sku: outerCartonBarcode,
        productName: 'Product Test 01',
        serialNumber: epc1,
        epc: epc1,
        status: ItemStatus.pendingInbound,
        orderNo: cartonCode,
      ));

      await repo.insertDirectItem(Item(
        itemId: 'ITEM-$epc2',
        productId: outerCartonBarcode,
        sku: outerCartonBarcode,
        productName: 'Product Test 02',
        serialNumber: epc2,
        epc: epc2,
        status: ItemStatus.pendingInbound,
        orderNo: cartonCode,
      ));

      await repo.insertDirectItem(Item(
        itemId: 'ITEM-$epc3',
        productId: outerCartonBarcode,
        sku: outerCartonBarcode,
        productName: 'Product Test 03',
        serialNumber: epc3,
        epc: epc3,
        status: ItemStatus.pendingInbound,
        orderNo: cartonCode,
      ));

      // 2. Giai đoạn 1: Quét qua cổng RFID Gate
      await repo.confirmGateReceiveToWaitingPutaway(
        orderNo: cartonCode,
        scannedEpcs: [epc1, epc2, epc3],
        cartonCode: outerCartonBarcode,
        performedBy: 'Trạm Cổng RFID Desktop',
      );

      // 3. Giai đoạn 2: Thủ kho cầm PDA quét Barcode Vị trí kệ và quét Mã Barcode Ngoài Thùng (8930000000001)
      final putawayCount = await repo.confirmPdaPutawayByCarton(
        cartonOrOrderBarcode: outerCartonBarcode,
        locationId: putawayLocationId,
        performedBy: 'Thủ kho PDA',
      );

      expect(putawayCount, equals(3));

      // Kiểm tra toàn bộ các item trong thùng đã được cất vào đúng vị trí kệ đích và chuyển sang IN_STOCK
      final items = repo.getItemsByOrderNo(cartonCode);
      expect(items.length, equals(3));
      expect(items.every((i) => i.status == ItemStatus.inStock), isTrue);
      expect(items.every((i) => i.locationId == putawayLocationId), isTrue);

      await repo.clearAllData(alsoClearCloud: false);
    });

    test('generateHexBarcode128 generates valid Code 128 Hex strings (0-9 and A-F only) and PDA putaway works seamlessly', () async {
      final repo = WarehouseRepository();
      
      // 1. Kiểm tra định dạng Barcode 128 Hex
      for (int i = 0; i < 50; i++) {
        final hexBarcode = repo.generateHexBarcode128(length: 16);
        expect(hexBarcode.length, equals(16));
        expect(RegExp(r'^[0-9A-F]+$').hasMatch(hexBarcode), isTrue, reason: 'Barcode phải chỉ chứa các ký tự 0-9 và A-F');
      }

      // 2. Kiểm tra quy trình quét cất kho bằng mã Barcode Hex 128 vừa sinh
      const orderNo = 'ORD-HEX-2026';
      const epc1 = 'E2801160HEX0001';
      const epc2 = 'E2801160HEX0002';
      const locationId = 'LOC-A01-01';

      await repo.addInboundOrder(InboundOrder(
        inboundOrderId: 'INB-HEX-01',
        orderNo: orderNo,
        sourceSupplier: 'Nhà cung cấp Hex',
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: 'SKU-HEX-01',
            sku: 'SKU-HEX-01',
            productName: 'Sản phẩm Test Hex',
            requiredQty: 2,
          ),
        ],
      ), autoGenerateEpcs: false);

      await repo.insertDirectItem(Item(
        itemId: 'ITEM-HEX-1',
        productId: 'SKU-HEX-01',
        sku: 'SKU-HEX-01',
        productName: 'Sản phẩm Test Hex',
        serialNumber: epc1,
        epc: epc1,
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
      ));

      await repo.insertDirectItem(Item(
        itemId: 'ITEM-HEX-2',
        productId: 'SKU-HEX-01',
        sku: 'SKU-HEX-01',
        productName: 'Sản phẩm Test Hex',
        serialNumber: epc2,
        epc: epc2,
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
      ));

      final hexBarcode = repo.generateHexBarcode128(length: 16);

      // Đi qua cổng quét và gán mã Barcode 128 Hex
      await repo.confirmGateReceiveToWaitingPutaway(
        orderNo: orderNo,
        scannedEpcs: [epc1, epc2],
        palletCode: hexBarcode,
        cartonCode: hexBarcode,
        performedBy: 'Trạm Cổng RFID Desktop',
      );

      // Xác nhận các item đã được gán palletId = hexBarcode và chuyển sang WAITING_PUTAWAY
      final itemsWaiting = repo.items.where((i) => i.palletId == hexBarcode).toList();
      expect(itemsWaiting.length, equals(2));
      expect(itemsWaiting.every((i) => i.status == ItemStatus.waitingPutaway), isTrue);

      // Thủ kho PDA quét trực tiếp mã Barcode 128 Hex để cất hàng vào kệ
      final putawayCount = await repo.confirmPdaPutawayByCarton(
        cartonOrOrderBarcode: hexBarcode,
        locationId: locationId,
        performedBy: 'Thủ kho PDA',
      );

      expect(putawayCount, equals(2));

      // Kiểm tra trạng thái đã chuyển sang IN_STOCK tại đúng locationId
      final itemsInStock = repo.items.where((i) => i.palletId == hexBarcode).toList();
      expect(itemsInStock.every((i) => i.status == ItemStatus.inStock), isTrue);
      expect(itemsInStock.every((i) => i.locationId == locationId), isTrue);

      await repo.clearAllData(alsoClearCloud: false);
    });

    test('Inventory Session created, scanned, and completed is persisted in SQLite and survives reloadFromSqlite', () async {
      final repo = WarehouseRepository();
      await repo.clearAllData(alsoClearCloud: false);

      final session = repo.startInventorySession(zone: 'KHO_A', locationCode: 'LOC-A-01');
      expect(repo.inventorySessions.length, equals(1));

      repo.processAuditScan(sessionId: session.sessionId, scannedEpcs: ['ABCDEF000000000000000001']);
      await repo.completeInventorySession(session.sessionId, 'Thủ kho PDA');

      expect(repo.inventorySessions.first.isCompleted, isTrue);

      // Giả lập làm mới từ SQLite
      await repo.reloadFromSqlite();

      expect(repo.inventorySessions.length, equals(1));
      expect(repo.inventorySessions.first.sessionId, equals(session.sessionId));
      expect(repo.inventorySessions.first.isCompleted, isTrue);

      await repo.clearAllData(alsoClearCloud: false);
    });

    test('3-Step State Flow: No Pallet in Import -> WAITING_PALLETIZE -> Palletize to WAITING_PUTAWAY -> Putaway to IN_STOCK', () async {
      final repo = WarehouseRepository();
      await repo.ensureInitialized();
      await repo.clearAllData(alsoClearCloud: false);

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final orderNo = 'NO-PALLET-$timestamp';

      // 1. Nhập hàng KHÔNG có mã pallet trong file
      final order = InboundOrder(
        inboundOrderId: 'INB-$orderNo',
        orderNo: orderNo,
        sourceSupplier: 'Nhà Cung Cấp Hàng Lẻ',
        status: InboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: 'PROD-NOPAL-01',
            sku: 'SKU-NOPAL-01',
            productName: 'Hàng chưa có pallet',
            requiredQty: 3,
          ),
        ],
      );

      final generatedItems = await repo.addInboundOrder(order, autoGenerateEpcs: true);
      expect(generatedItems.length, equals(3));
      expect(generatedItems.every((i) => i.status == ItemStatus.pendingInbound), isTrue);
      expect(generatedItems.every((i) => i.palletId == null), isTrue);

      final scannedEpcs = generatedItems.map((i) => i.epc).toList();

      // 2. Đi qua cổng RFID quét đối soát (Không có xe Pallet)
      final gateCount = await repo.confirmGateReceiveToWaitingPutaway(
        orderNo: orderNo,
        scannedEpcs: scannedEpcs,
        performedBy: 'Trạm Cổng RFID Desktop',
      );
      expect(gateCount, equals(3));

      // Kiểm tra trạng thái: Xếp vào pallet (WAITING_PALLETIZE)
      final itemsAfterGate = repo.getItemsByOrderNo(orderNo);
      expect(itemsAfterGate.every((i) => i.status == ItemStatus.waitingPalletize), isTrue);
      expect(itemsAfterGate.every((i) => i.palletId == null), isTrue);

      final orderAfterGate = repo.inboundOrders.firstWhere((o) => o.orderNo == orderNo);
      expect(orderAfterGate.status, equals(InboundOrderStatus.waitingPalletize));

      // 3. Nhân viên xếp hàng vào Pallet (PAL-AUTO-01)
      final assignedPallet = await repo.assignItemsToPallet(
        palletCode: 'PAL-AUTO-01',
        itemEpcs: scannedEpcs,
      );
      expect(assignedPallet.palletCode, equals('PAL-AUTO-01'));

      // Kiểm tra trạng thái đã chuyển tiếp sang: Chờ xếp kệ (WAITING_PUTAWAY)
      final itemsAfterPalletize = repo.getItemsByOrderNo(orderNo);
      expect(itemsAfterPalletize.every((i) => i.status == ItemStatus.waitingPutaway), isTrue);
      expect(itemsAfterPalletize.every((i) => i.palletId == 'PAL-AUTO-01'), isTrue);

      final orderAfterPalletize = repo.inboundOrders.firstWhere((o) => o.orderNo == orderNo);
      expect(orderAfterPalletize.status, equals(InboundOrderStatus.waitingPutaway));

      // 4. Máy cầm tay PDA quét xếp vào kệ LOC-A01-01
      const shelfLocation = 'LOC-A01-01';
      final putawayCount = await repo.confirmPdaPutawayByCarton(
        cartonOrOrderBarcode: 'PAL-AUTO-01',
        locationId: shelfLocation,
        performedBy: 'Thủ kho PDA',
      );
      expect(putawayCount, equals(3));

      // Kiểm tra trạng thái: Đã lưu vào vị trí (IN_STOCK)
      final itemsFinal = repo.getItemsByOrderNo(orderNo);
      expect(itemsFinal.every((i) => i.status == ItemStatus.inStock), isTrue);
      expect(itemsFinal.every((i) => i.locationId == shelfLocation), isTrue);
      expect(itemsFinal.every((i) => i.statusDisplay == 'Đã lưu vào vị trí $shelfLocation'), isTrue);

      final orderFinal = repo.inboundOrders.firstWhere((o) => o.orderNo == orderNo);
      expect(orderFinal.status, equals(InboundOrderStatus.completed));

      await repo.clearAllData(alsoClearCloud: false);
    });

    test('Excel with [CARTON CODE, EPC, NAME, NCC, BARCODE PALET, EPC PALLET] parses correctly and puts away by Pallet', () async {
      final repo = WarehouseRepository();
      await repo.ensureInitialized();

      // 1. Kiểm tra parse file CSV/Excel chứa đúng định dạng như trong hình ảnh của người dùng:
      // CARTON CODE | EPC | NAME | NCC | BARCODE PALET | EPC PALLET
      const csvContent =
          'CARTON CODE,EPC,NAME,NCC,BARCODE PALET,EPC PALLET\r\n'
          'CARTONTEST0001,ABCDEF000000000000000001,áo hồng,PEPSICO,945321545,AB2600100000000000000200\r\n'
          'CARTONTEST0002,ABCDEF000000000000000002,áo tím,PEPSICO,945321545,AB2600100000000000000200\r\n';

      final parsed = ExcelImportService().parseBytes(Uint8List.fromList(utf8.encode(csvContent)), isCsv: true);
      final cartons = parsed.$1;
      expect(cartons.length, equals(2));

      final c1 = cartons[0];
      expect(c1['cartonBox'], equals('CARTONTEST0001'));
      expect(c1['palletCode'], equals('945321545'));
      expect(c1['palletEpc'], equals('AB2600100000000000000200'));
      expect(c1['supplier'], equals('PEPSICO'));
      expect(c1['productName'], equals('áo hồng'));

      final sItems1 = (c1['serialItems'] as List<Map<String, dynamic>>);
      expect(sItems1.length, equals(1));
      expect(sItems1[0]['serial'], equals('ABCDEF000000000000000001'));
      expect(sItems1[0]['pallet'], equals('945321545'));
      expect(sItems1[0]['palletEpc'], equals('AB2600100000000000000200'));

      final c2 = cartons[1];
      expect(c2['cartonBox'], equals('CARTONTEST0002'));
      expect(c2['palletCode'], equals('945321545'));
      expect(c2['palletEpc'], equals('AB2600100000000000000200'));
      expect(c2['productName'], equals('áo tím'));

      // 2. Đăng ký Pallet vào hệ thống từ file Excel
      await repo.registerOrUpdatePallet(
        palletCode: '945321545',
        rfidEpc: 'AB2600100000000000000200',
      );

      // Nhận diện Pallet qua chip RFID tại Cổng
      final foundPallet = repo.findPalletByRfid('AB2600100000000000000200');
      expect(foundPallet, isNotNull);
      expect(foundPallet!.palletCode, equals('945321545'));

      // 3. Giả lập đơn nhập hàng được nạp từ file Excel vào Database
      const orderNo = 'NK-PALLET-TEST-001';
      final order = InboundOrder(
        inboundOrderId: 'INB-$orderNo',
        orderNo: orderNo,
        sourceSupplier: 'PEPSICO',
        status: InboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: c1['productCode'],
            sku: c1['productCode'],
            productName: 'áo hồng',
            requiredQty: 1,
          ),
          InboundOrderDetail(
            productId: c2['productCode'],
            sku: c2['productCode'],
            productName: 'áo tím',
            requiredQty: 1,
          ),
        ],
      );
      await repo.addInboundOrder(order, autoGenerateEpcs: false);

      final item1 = Item(
        itemId: 'ITEM-TEST-001',
        productId: c1['productCode'],
        sku: c1['productCode'],
        productName: 'áo hồng',
        serialNumber: 'ABCDEF000000000000000001',
        epc: 'ABCDEF000000000000000001',
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
        palletId: 'PAL-945321545',
        cartonCode: 'CARTONTEST0001',
        supplier: 'PEPSICO',
      );
      final item2 = Item(
        itemId: 'ITEM-TEST-002',
        productId: c2['productCode'],
        sku: c2['productCode'],
        productName: 'áo tím',
        serialNumber: 'ABCDEF000000000000000002',
        epc: 'ABCDEF000000000000000002',
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
        palletId: 'PAL-945321545',
        cartonCode: 'CARTONTEST0002',
        supplier: 'PEPSICO',
      );
      await repo.insertDirectItem(item1);
      await repo.insertDirectItem(item2);

      // 4. Qua Cổng RFID Gate: Vì đơn đã có mã Pallet trong file nên chuyển thẳng sang Chờ xếp kệ (WAITING_PUTAWAY)
      final scannedEpcs = ['ABCDEF000000000000000001', 'ABCDEF000000000000000002'];
      final gateCount = await repo.confirmGateReceiveToWaitingPutaway(
        orderNo: orderNo,
        scannedEpcs: scannedEpcs,
        palletCode: '945321545',
        performedBy: 'Cổng RFID Gate',
      );
      expect(gateCount, equals(2));

      final itemsAfterGate = repo.getItemsByOrderNo(orderNo);
      expect(itemsAfterGate.every((i) => i.status == ItemStatus.waitingPutaway), isTrue);
      expect(itemsAfterGate.every((i) => i.palletId == 'PAL-945321545'), isTrue);

      final orderAfterGate = repo.inboundOrders.firstWhere((o) => o.orderNo == orderNo);
      expect(orderAfterGate.status, equals(InboundOrderStatus.waitingPutaway));

      // 5. Thủ kho cầm PDA quét Barcode Pallet 945321545 và quét Kệ LOC-K02-05
      const shelfLocation = 'LOC-K02-05';
      final putawayCount = await repo.confirmPdaPutawayByCarton(
        cartonOrOrderBarcode: '945321545', // Quét mã Pallet Barcode
        locationId: shelfLocation,
        performedBy: 'Thủ kho PDA',
      );
      expect(putawayCount, equals(2));

      // Kiểm tra trạng thái đã chuyển thành IN_STOCK tại đúng kệ
      final itemsAfterPutaway = repo.getItemsByOrderNo(orderNo);
      expect(itemsAfterPutaway.every((i) => i.status == ItemStatus.inStock), isTrue);
      expect(itemsAfterPutaway.every((i) => i.locationId == shelfLocation), isTrue);
      expect(itemsAfterPutaway.every((i) => i.statusDisplay == 'Đã lưu vào vị trí $shelfLocation'), isTrue);

      // Pallet cũng được cập nhật vị trí lên kệ kho
      final palAfter = repo.pallets.where((p) => p.palletCode == '945321545').first;
      expect(palAfter.locationId, equals(shelfLocation));

      await repo.clearAllData(alsoClearCloud: false);
    });
  });
}


