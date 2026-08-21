import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
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

      // 2. GIAI ĐOẠN 1: Kiện hàng đi qua Cổng RFID Gate
      final gateReceivedCount = await repo.confirmGateReceiveToWaitingPutaway(
        orderNo: testOrderNo,
        scannedEpcs: scannedEpcs,
        performedBy: 'Trạm Cổng RFID Desktop',
      );

      expect(gateReceivedCount, equals(5));

      // Kiểm tra trạng thái sau khi qua cổng: Chờ xếp kho (WAITING_PUTAWAY), chưa có vị trí hay pallet
      final itemsAfterGate = repo.getItemsByOrderNo(testOrderNo);
      expect(itemsAfterGate.length, equals(5));
      expect(itemsAfterGate.every((i) => i.status == ItemStatus.waitingPutaway), isTrue);
      expect(itemsAfterGate.every((i) => i.locationId == null), isTrue);
      expect(itemsAfterGate.every((i) => i.palletId == null), isTrue);

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
      await repo.clearAllData(alsoClearMySql: false);
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

      await repo.clearAllData(alsoClearMySql: false);
    });
  });
}

