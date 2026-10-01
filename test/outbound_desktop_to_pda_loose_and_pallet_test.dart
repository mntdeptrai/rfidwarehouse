import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/inventory_models.dart';
import 'package:uhf/models/order_models.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Desktop Import to PDA Loose & Pallet Outbound Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureDefault10Locations();
    });

    test('1. Đơn xuất kho tạo từ Desktop được lưu vào repository và sẵn sàng cho PDA', () async {
      final order = OutboundOrder(
        outboundOrderId: 'ORD-OUT-TEST-001',
        poNo: 'PO-TEST-001',
        customer: 'Công ty Đối Tác ABC',
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'P-001',
            sku: 'SKU-TEST-A',
            productName: 'Sản phẩm Test A',
            requiredQty: 5,
            pickedQty: 0,
          ),
        ],
      );

      await repo.addOutboundOrder(order);

      final found = repo.outboundOrders.where((o) => o.poNo == 'PO-TEST-001').firstOrNull;
      expect(found, isNotNull);
      expect(found!.customer, equals('Công ty Đối Tác ABC'));
      expect(found.details.first.requiredQty, equals(5));
      expect(found.details.first.pickedQty, equals(0));
      expect(found.status, equals(OutboundOrderStatus.newOrder));
    });

    test('2. Xuất hàng lẻ bằng PDA: Trừ tồn kho theo đúng vị trí kệ và tách sản phẩm khỏi Pallet', () async {
      final loc = repo.locations.firstWhere((l) => l.locationCode == 'A-01');
      loc.currentPallets = 1;

      await repo.registerOrUpdatePallet(
        palletCode: 'PAL-01',
        rfidEpc: 'E28011912000000000PAL01',
        locationId: loc.locationId,
      );
      final pal = repo.pallets.firstWhere((p) => p.palletCode == 'PAL-01');

      final item1 = Item(
        productId: 'P-001',
        itemId: 'ITEM-01',
        sku: 'SKU-TEST-A',
        productName: 'Sản phẩm Test A',
        serialNumber: 'SN-01',
        epc: 'E28011912000000000ITM01',
        locationId: loc.locationId,
        palletId: pal.palletId,
        status: ItemStatus.inStock,
      );
      final item2 = Item(
        productId: 'P-001',
        itemId: 'ITEM-02',
        sku: 'SKU-TEST-A',
        productName: 'Sản phẩm Test A',
        serialNumber: 'SN-02',
        epc: 'E28011912000000000ITM02',
        locationId: loc.locationId,
        palletId: pal.palletId,
        status: ItemStatus.inStock,
      );
      final item3 = Item(
        productId: 'P-001',
        itemId: 'ITEM-03',
        sku: 'SKU-TEST-A',
        productName: 'Sản phẩm Test A',
        serialNumber: 'SN-03',
        epc: 'E28011912000000000ITM03',
        locationId: loc.locationId,
        palletId: pal.palletId,
        status: ItemStatus.inStock,
      );

      await repo.addItem(item1);
      await repo.addItem(item2);
      await repo.addItem(item3);

      pal.itemIds.addAll(['ITEM-01', 'ITEM-02', 'ITEM-03']);

      final order = OutboundOrder(
        outboundOrderId: 'ORD-OUT-LOOSE-01',
        poNo: 'PO-LOOSE-01',
        customer: 'Khách Xuất Lẻ',
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'P-001',
            sku: 'SKU-TEST-A',
            productName: 'Sản phẩm Test A',
            requiredQty: 3,
            pickedQty: 0,
          ),
        ],
      );
      await repo.addOutboundOrder(order);

      // Nhân viên cầm PDA nhặt lẻ 1 sản phẩm (ITEM-01) tại kệ A-01
      final shippedCount = await repo.confirmGateOutbound(
        poNo: 'PO-LOOSE-01',
        customer: 'Khách Xuất Lẻ',
        scannedEpcs: ['E28011912000000000ITM01'],
        performedBy: 'PDA Picker',
      );

      expect(shippedCount, equals(1));

      // Kiểm tra sản phẩm đã xuất kho
      expect(item1.status, equals(ItemStatus.out));
      expect(item1.locationId, isNull);

      // Kiểm tra pallet vẫn còn trên kệ A-01 vì còn ITEM-02 và ITEM-03
      expect(pal.itemIds.contains('ITEM-01'), isFalse);
      expect(pal.itemIds.length, equals(2));
      expect(pal.locationId, equals(loc.locationId));
      expect(loc.currentPallets, equals(1));

      // Kiểm tra đơn hàng được cập nhật trạng thái xuất dở (processing)
      final updatedOrder = repo.outboundOrders.firstWhere((o) => o.poNo == 'PO-LOOSE-01');
      expect(updatedOrder.details.first.pickedQty, equals(1));
      expect(updatedOrder.status, equals(OutboundOrderStatus.processing));
    });

    test('3. Xuất toàn bộ Pallet qua Cổng RFID Gate: Giải phóng pallet và trừ tồn kho kệ', () async {
      final loc = repo.locations.firstWhere((l) => l.locationCode == 'A-02');
      loc.currentPallets = 1;

      await repo.registerOrUpdatePallet(
        palletCode: 'PAL-FULL-01',
        rfidEpc: 'E28011912000000000PAL99',
        locationId: loc.locationId,
      );
      final pal = repo.pallets.firstWhere((p) => p.palletCode == 'PAL-FULL-01');

      final itemF1 = Item(
        productId: 'P-FULL',
        itemId: 'ITEM-F1',
        sku: 'SKU-FULL',
        productName: 'SP Pallet 1',
        serialNumber: 'SN-F1',
        epc: 'E28011912000000000ITMF1',
        locationId: loc.locationId,
        palletId: pal.palletId,
        status: ItemStatus.inStock,
      );
      final itemF2 = Item(
        productId: 'P-FULL',
        itemId: 'ITEM-F2',
        sku: 'SKU-FULL',
        productName: 'SP Pallet 2',
        serialNumber: 'SN-F2',
        epc: 'E28011912000000000ITMF2',
        locationId: loc.locationId,
        palletId: pal.palletId,
        status: ItemStatus.inStock,
      );

      await repo.addItem(itemF1);
      await repo.addItem(itemF2);

      pal.itemIds.addAll(['ITEM-F1', 'ITEM-F2']);

      final order = OutboundOrder(
        outboundOrderId: 'ORD-OUT-FULL-01',
        poNo: 'PO-FULL-01',
        customer: 'Khách Hàng Pallet',
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'P-FULL',
            sku: 'SKU-FULL',
            productName: 'SP Pallet Full',
            requiredQty: 2,
            pickedQty: 0,
          ),
        ],
      );
      await repo.addOutboundOrder(order);

      // Quét xuất cả pallet (cả 2 EPC)
      final shippedCount = await repo.confirmGateOutbound(
        poNo: 'PO-FULL-01',
        customer: 'Khách Hàng Pallet',
        scannedEpcs: ['E28011912000000000ITMF1', 'E28011912000000000ITMF2'],
        performedBy: 'RFID Gate HF340',
      );

      expect(shippedCount, equals(2));
      expect(itemF1.status, equals(ItemStatus.out));
      expect(itemF2.status, equals(ItemStatus.out));

      // Pallet trống và được giải phóng khỏi kệ A-02
      expect(pal.itemIds.isEmpty, isTrue);
      expect(pal.locationId, isNull);
      expect(loc.currentPallets, equals(0));

      // Đơn hàng hoàn tất (shipped)
      final updatedOrder = repo.outboundOrders.firstWhere((o) => o.poNo == 'PO-FULL-01');
      expect(updatedOrder.details.first.pickedQty, equals(2));
      expect(updatedOrder.status, equals(OutboundOrderStatus.shipped));
    });

    test('4. Đơn xuất kho import từ Desktop đồng bộ đầy đủ chi tiết mã hàng và sẵn sàng hiển thị trên PDA', () async {
      bool listenerTriggered = false;
      repo.addListener(() {
        listenerTriggered = true;
      });

      final importedOrder = OutboundOrder(
        outboundOrderId: 'ORD-DESK-IMPORT-99',
        poNo: 'XK-20261001-IMPORT-99',
        customer: 'Công ty May Mặc Đông Á',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'P-POLO-01',
            sku: 'SKU-POLO-01',
            productName: 'Áo Polo Coolmax Nam',
            requiredQty: 10,
            pickedQty: 0,
            epcList: ['E2801190000000000000101', 'E2801190000000000000102'],
          ),
          OutboundOrderDetail(
            productId: 'P-JEAN-02',
            sku: 'SKU-JEAN-02',
            productName: 'Quần Jean Slimfit',
            requiredQty: 5,
            pickedQty: 0,
          ),
        ],
      );

      await repo.addOutboundOrder(importedOrder);

      expect(listenerTriggered, isTrue);

      final pdaPending = repo.outboundOrders.where((o) => o.status != OutboundOrderStatus.shipped).toList();
      final pdaOrder = pdaPending.firstWhere((o) => o.poNo == 'XK-20261001-IMPORT-99');
      expect(pdaOrder, isNotNull);
      expect(pdaOrder.details.length, equals(2));

      final totalQty = pdaOrder.details.fold(0, (s, d) => s + d.requiredQty);
      expect(totalQty, equals(15));
      expect(pdaOrder.details.first.epcList?.length, equals(2));
    });
  });
}
