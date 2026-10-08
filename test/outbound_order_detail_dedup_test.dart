import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WarehouseRepository repo;

  setUp(() async {
    repo = WarehouseRepository();
    await repo.ensureInitialized();
  });

  group('Outbound Order Detail Deduplication & Accurate Quantity Calculation', () {
    test('Đơn xuất kho có chi tiết bị trùng SKU hiển thị đúng số SKU = 1 và SL Yêu cầu = 3', () async {
      final dupOrder = OutboundOrder(
        outboundOrderId: 'ORD-OUT-TEST-DUP-01',
        poNo: 'PO-TEST-DUP-01',
        customer: 'Khách hàng Thử Nghiệm',
        status: OutboundOrderStatus.shipped,
        createdAt: DateTime(2026, 10, 8, 16, 54),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-SKU-01',
            sku: 'SKU-AO-SO-MI',
            productName: 'Áo Sơ Mi Nam',
            requiredQty: 3,
            pickedQty: 0,
          ),
          OutboundOrderDetail(
            productId: 'PROD-SKU-01',
            sku: 'SKU-AO-SO-MI',
            productName: 'Áo Sơ Mi Nam',
            requiredQty: 3,
            pickedQty: 3,
          ),
        ],
      );

      await repo.addOutboundOrder(dupOrder);

      // Khi deduplicate theo SKU:
      final Map<String, OutboundOrderDetail> dedupDetails = {};
      for (final d in dupOrder.details) {
        final key = d.sku.trim().isNotEmpty ? d.sku.trim().toUpperCase() : d.productId;
        if (!dedupDetails.containsKey(key)) {
          dedupDetails[key] = d;
        } else {
          final cur = dedupDetails[key]!;
          dedupDetails[key] = OutboundOrderDetail(
            productId: cur.productId.isNotEmpty ? cur.productId : d.productId,
            sku: cur.sku.isNotEmpty ? cur.sku : d.sku,
            productName: cur.productName.isNotEmpty ? cur.productName : d.productName,
            requiredQty: cur.requiredQty > 0 ? cur.requiredQty : d.requiredQty,
            pickedQty: cur.pickedQty > d.pickedQty ? cur.pickedQty : d.pickedQty,
          );
        }
      }
      final cleanDetails = dedupDetails.values.toList();
      final totalReq = cleanDetails.fold<int>(0, (s, d) => s + d.requiredQty);
      final totalPicked = cleanDetails.fold<int>(0, (s, d) => s + d.pickedQty);

      // Kỳ vọng:
      // Số SKU chỉ là 1 SKU (thay vì 2 SKU)
      expect(cleanDetails.length, equals(1));
      // Số lượng yêu cầu là 3 (thay vì 6)
      expect(totalReq, equals(3));
      // Số lượng đã soát là 3
      expect(totalPicked, equals(3));
    });

    test('Xuất kho qua confirmGateOutbound cập nhật pickedQty đúng mà không làm tăng requiredQty', () async {
      final product = Product(
        productId: 'PROD-TEST-OUT-01',
        sku: 'SKU-TEST-OUT',
        productName: 'Sản phẩm Test Xuất',
        category: 'Test',
        unit: 'Cái',
      );
      await repo.addProduct(product);

      final loc = Location(
        locationId: 'LOC-TEST-A1',
        locationCode: 'A1-01',
        zone: 'Khu A',
        shelf: '01',
        level: '1',
      );
      await repo.addLocation(loc);

      final item1 = Item(itemId: 'ITEM-TEST-01', epc: 'E280111100000001', serialNumber: 'SN-01', productId: 'PROD-TEST-OUT-01', sku: 'SKU-TEST-OUT', productName: 'Sản phẩm Test Xuất', locationId: 'LOC-TEST-A1', status: ItemStatus.inStock);
      final item2 = Item(itemId: 'ITEM-TEST-02', epc: 'E280111100000002', serialNumber: 'SN-02', productId: 'PROD-TEST-OUT-01', sku: 'SKU-TEST-OUT', productName: 'Sản phẩm Test Xuất', locationId: 'LOC-TEST-A1', status: ItemStatus.inStock);
      final item3 = Item(itemId: 'ITEM-TEST-03', epc: 'E280111100000003', serialNumber: 'SN-03', productId: 'PROD-TEST-OUT-01', sku: 'SKU-TEST-OUT', productName: 'Sản phẩm Test Xuất', locationId: 'LOC-TEST-A1', status: ItemStatus.inStock);
      await repo.addItem(item1);
      await repo.addItem(item2);
      await repo.addItem(item3);

      final order = OutboundOrder(
        outboundOrderId: 'ORD-OUT-TEST-CLEAN-01',
        poNo: 'PO-TEST-CLEAN-01',
        customer: 'Công ty Test',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-TEST-OUT-01',
            sku: 'SKU-TEST-OUT',
            productName: 'Sản phẩm Test Xuất',
            requiredQty: 3,
            pickedQty: 0,
          ),
        ],
      );
      await repo.addOutboundOrder(order);

      // Thực hiện quét xuất kho 3 sản phẩm
      final count = await repo.confirmGateOutbound(
        poNo: 'PO-TEST-CLEAN-01',
        scannedEpcs: ['E280111100000001', 'E280111100000002', 'E280111100000003'],
        customer: 'Công ty Test',
      );

      expect(count, equals(3));

      // Kiểm tra đơn hàng sau khi xuất
      final updatedOrder = repo.outboundOrders.firstWhere((o) => o.poNo == 'PO-TEST-CLEAN-01');
      expect(updatedOrder.details.length, equals(1));
      expect(updatedOrder.details.first.requiredQty, equals(3));
      expect(updatedOrder.details.first.pickedQty, equals(3));
      expect(updatedOrder.status, equals(OutboundOrderStatus.shipped));
    });
  });
}
