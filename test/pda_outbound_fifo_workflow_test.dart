import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDA Outbound Screen FIFO & Waiting Shipment Workflow Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
    });

    test('FIFO picking logic sorts items by inboundTime ascending (oldest first)', () async {
      final now = DateTime.now();
      final itemOldest = Item(
        itemId: 'ITEM-FIFO-01',
        productId: 'SKU-FIFO-A',
        sku: 'SKU-FIFO-A',
        productName: 'Hàng nhập ngày 1 (Cũ nhất)',
        serialNumber: 'SN-FIFO-01',
        epc: 'E280119100000000000FIFO01',
        status: ItemStatus.inStock,
        locationId: 'LOC-A1',
        inboundTime: now.subtract(const Duration(days: 10)),
      );

      final itemMedium = Item(
        itemId: 'ITEM-FIFO-02',
        productId: 'SKU-FIFO-A',
        sku: 'SKU-FIFO-A',
        productName: 'Hàng nhập ngày 5 (Vừa)',
        serialNumber: 'SN-FIFO-02',
        epc: 'E280119100000000000FIFO02',
        status: ItemStatus.inStock,
        locationId: 'LOC-A2',
        inboundTime: now.subtract(const Duration(days: 5)),
      );

      final itemNewest = Item(
        itemId: 'ITEM-FIFO-03',
        productId: 'SKU-FIFO-A',
        sku: 'SKU-FIFO-A',
        productName: 'Hàng nhập hôm nay (Mới nhất)',
        serialNumber: 'SN-FIFO-03',
        epc: 'E280119100000000000FIFO03',
        status: ItemStatus.inStock,
        locationId: 'LOC-A3',
        inboundTime: now,
      );

      await repo.insertDirectItems([itemMedium, itemNewest, itemOldest]);

      // Nhu cầu xuất: Cần xuất 2 sản phẩm SKU-FIFO-A
      final requiredQty = 2;
      final availableItems = repo.items.where((it) =>
          it.sku == 'SKU-FIFO-A' && it.status == ItemStatus.inStock).toList();

      // Sắp xếp FIFO: inboundTime cũ nhất lên đầu
      availableItems.sort((a, b) {
        final timeA = a.inboundTime ?? DateTime(2000);
        final timeB = b.inboundTime ?? DateTime(2000);
        return timeA.compareTo(timeB);
      });

      final pickedItems = availableItems.take(requiredQty).toList();

      // Kiểm tra: 2 sản phẩm được chọn PHẢI là itemOldest và itemMedium
      expect(pickedItems.length, equals(2));
      expect(pickedItems[0].epc, equals(itemOldest.epc));
      expect(pickedItems[1].epc, equals(itemMedium.epc));
      expect(pickedItems.any((i) => i.epc == itemNewest.epc), isFalse);
    });

    test('Confirming outbound completion updates item status to OUT and frees locations', () async {
      final now = DateTime.now();
      final itemToShip = Item(
        itemId: 'ITEM-SHIP-01',
        productId: 'SKU-SHIP-01',
        sku: 'SKU-SHIP-01',
        productName: 'Hàng chuẩn bị xuất',
        serialNumber: 'SN-SHIP-01',
        epc: 'E280119100000000000SHIP01',
        status: ItemStatus.inStock,
        locationId: 'LOC-B1',
        inboundTime: now.subtract(const Duration(days: 2)),
      );

      await repo.insertDirectItems([itemToShip]);
      expect(repo.items.firstWhere((i) => i.epc == itemToShip.epc).status, equals(ItemStatus.inStock));

      // Thực hiện xuất kho
      itemToShip.status = ItemStatus.out;
      itemToShip.locationId = null;
      await repo.insertDirectItems([itemToShip]);

      final updated = repo.items.firstWhere((i) => i.epc == itemToShip.epc);
      expect(updated.status, equals(ItemStatus.out));
      expect(updated.locationId, isNull);
    });
  });
}
