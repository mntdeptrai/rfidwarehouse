import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Outbound Inventory Sufficiency & FIFO Location Validation Tests', () {
    late WarehouseRepository repo;

    Future<void> cleanupTestData() async {
      final testEpcs = repo.items
          .where((i) => i.sku.startsWith('TEST-SKU-'))
          .map((i) => i.epc)
          .toList();
      for (final epc in testEpcs) {
        await repo.deleteItem(epc);
      }

      final testPallets = repo.pallets
          .where((p) => p.palletCode.startsWith('TEST-PAL-'))
          .map((p) => p.palletCode)
          .toList();
      for (final code in testPallets) {
        await repo.deletePallet(code);
      }
    }

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
      await repo.ensureDefault10Locations();
      await cleanupTestData();
    });

    tearDown(() async {
      await cleanupTestData();
    });

    test('Block export when stock is insufficient and calculate shortage count', () async {
      final loc = repo.locations.first;
      // Thêm 2 sản phẩm tồn kho của SKU TEST-SKU-A
      await repo.addItem(
        Item(
          itemId: 'ITEM-TEST-01',
          productId: 'PROD-TEST-A',
          sku: 'TEST-SKU-A',
          productName: 'Sản phẩm Test A',
          serialNumber: 'SN-01',
          epc: 'EPC-TEST-A-01',
          status: ItemStatus.inStock,
          locationId: loc.locationId,
          inboundTime: DateTime(2026, 1, 1),
        ),
      );
      await repo.addItem(
        Item(
          itemId: 'ITEM-TEST-02',
          productId: 'PROD-TEST-A',
          sku: 'TEST-SKU-A',
          productName: 'Sản phẩm Test A',
          serialNumber: 'SN-02',
          epc: 'EPC-TEST-A-02',
          status: ItemStatus.inStock,
          locationId: loc.locationId,
          inboundTime: DateTime(2026, 1, 2),
        ),
      );

      // Yêu cầu xuất 4 sản phẩm SKU TEST-SKU-A (kho chỉ có 2 -> thiếu 2)
      final requested = [
        {'sku': 'TEST-SKU-A', 'productName': 'Sản phẩm Test A'},
        {'sku': 'TEST-SKU-A', 'productName': 'Sản phẩm Test A'},
        {'sku': 'TEST-SKU-A', 'productName': 'Sản phẩm Test A'},
        {'sku': 'TEST-SKU-A', 'productName': 'Sản phẩm Test A'},
      ];

      final result = repo.validateOutboundInventoryAndFifo(requestedItems: requested);

      expect(result.isStockSufficient, isFalse, reason: 'Phải khóa xuất khi không đủ tồn kho');
      expect(result.totalRequested, equals(4));
      expect(result.shortageCount, equals(2));
      expect(result.shortageBySku['TEST-SKU-A'], equals(2));

      // 2 món đầu phải có hàng và vị trí, 2 món sau báo hết tồn
      expect(result.items[0].isInStock, isTrue);
      expect(result.items[0].locationCode, equals(loc.locationCode));
      expect(result.items[1].isInStock, isTrue);
      expect(result.items[2].isInStock, isFalse);
      expect(result.items[3].isInStock, isFalse);
    });

    test('Correctly sort FIFO priority and resolve shelf locations', () async {
      final locA = repo.locations[0];
      final locB = repo.locations[1];

      // 3 sản phẩm với 3 ngày nhập khác nhau
      final dateOld = DateTime(2026, 1, 1);
      final dateMid = DateTime(2026, 2, 1);
      final dateNew = DateTime(2026, 3, 1);

      await repo.addItem(
        Item(
          itemId: 'ITEM-FIFO-03',
          productId: 'PROD-FIFO-01',
          sku: 'TEST-SKU-FIFO',
          productName: 'Sản phẩm FIFO',
          serialNumber: 'SN-F03',
          epc: 'EPC-FIFO-03',
          status: ItemStatus.inStock,
          locationId: locB.locationId,
          inboundTime: dateNew,
        ),
      );
      await repo.addItem(
        Item(
          itemId: 'ITEM-FIFO-01',
          productId: 'PROD-FIFO-01',
          sku: 'TEST-SKU-FIFO',
          productName: 'Sản phẩm FIFO',
          serialNumber: 'SN-F01',
          epc: 'EPC-FIFO-01',
          status: ItemStatus.inStock,
          locationId: locA.locationId,
          inboundTime: dateOld,
        ),
      );
      await repo.addItem(
        Item(
          itemId: 'ITEM-FIFO-02',
          productId: 'PROD-FIFO-01',
          sku: 'TEST-SKU-FIFO',
          productName: 'Sản phẩm FIFO',
          serialNumber: 'SN-F02',
          epc: 'EPC-FIFO-02',
          status: ItemStatus.inStock,
          locationId: locA.locationId,
          inboundTime: dateMid,
        ),
      );

      // Yêu cầu xuất 3 sản phẩm không chỉ định EPC
      final requested = [
        {'sku': 'TEST-SKU-FIFO', 'productName': 'Sản phẩm FIFO'},
        {'sku': 'TEST-SKU-FIFO', 'productName': 'Sản phẩm FIFO'},
        {'sku': 'TEST-SKU-FIFO', 'productName': 'Sản phẩm FIFO'},
      ];

      final result = repo.validateOutboundInventoryAndFifo(requestedItems: requested);

      expect(result.isStockSufficient, isTrue);
      expect(result.shortageCount, equals(0));
      expect(result.items.length, equals(3));

      // Kiểm tra thứ tự FIFO: Cũ nhất phải được ưu tiên xuất trước (FIFO #1)
      expect(result.items[0].epc, equals('EPC-FIFO-01'));
      expect(result.items[0].fifoPriority, equals(1));
      expect(result.items[0].locationCode, equals(locA.locationCode));

      expect(result.items[1].epc, equals('EPC-FIFO-02'));
      expect(result.items[1].fifoPriority, equals(2));
      expect(result.items[1].locationCode, equals(locA.locationCode));

      expect(result.items[2].epc, equals('EPC-FIFO-03'));
      expect(result.items[2].fifoPriority, equals(3));
      expect(result.items[2].locationCode, equals(locB.locationCode));
    });

    test('Resolve shelf location via pallet location when item locationId is null', () async {
      final locShelf = repo.locations[2];

      // Lưu pallet được xếp lên kệ locShelf
      await repo.registerOrUpdatePallet(
        palletCode: 'TEST-PAL-01',
        rfidEpc: 'EPC-PALLET-01',
        locationId: locShelf.locationId,
      );

      final createdPallet = repo.pallets.firstWhere((p) => p.palletCode == 'TEST-PAL-01');

      // Sản phẩm nằm trên pallet nhưng chưa gán locationId trực tiếp
      await repo.addItem(
        Item(
          itemId: 'ITEM-PAL-01',
          productId: 'PROD-PAL-01',
          sku: 'TEST-SKU-PALLET',
          productName: 'Sản phẩm trên Pallet',
          serialNumber: 'SN-P01',
          epc: 'EPC-ITEM-PAL-01',
          palletId: createdPallet.palletId,
          locationId: null,
          status: ItemStatus.inStock,
          inboundTime: DateTime(2026, 1, 5),
        ),
      );

      final result = repo.validateOutboundInventoryAndFifo(
        requestedItems: [
          {'sku': 'TEST-SKU-PALLET', 'epc': 'EPC-ITEM-PAL-01'},
        ],
      );

      expect(result.isStockSufficient, isTrue);
      expect(result.items.first.isInStock, isTrue);
      expect(result.items.first.locationCode, equals(locShelf.locationCode),
          reason: 'Phải giải quyết được vị trí kệ từ pallet chứa sản phẩm');
    });

    test('Generate FIFO warning when a newer item EPC is requested while older stock remains', () async {
      final loc = repo.locations.first;

      await repo.addItem(
        Item(
          itemId: 'ITEM-WARN-01',
          productId: 'PROD-WARN-01',
          sku: 'TEST-SKU-WARN',
          productName: 'Sản phẩm Cũ',
          serialNumber: 'SN-W01',
          epc: 'EPC-WARN-OLD',
          status: ItemStatus.inStock,
          locationId: loc.locationId,
          inboundTime: DateTime(2026, 1, 1),
        ),
      );
      await repo.addItem(
        Item(
          itemId: 'ITEM-WARN-02',
          productId: 'PROD-WARN-01',
          sku: 'TEST-SKU-WARN',
          productName: 'Sản phẩm Mới',
          serialNumber: 'SN-W02',
          epc: 'EPC-WARN-NEW',
          status: ItemStatus.inStock,
          locationId: loc.locationId,
          inboundTime: DateTime(2026, 2, 1),
        ),
      );

      // Yêu cầu xuất đích danh chip MỚI
      final result = repo.validateOutboundInventoryAndFifo(
        requestedItems: [
          {'sku': 'TEST-SKU-WARN', 'epc': 'EPC-WARN-NEW'},
        ],
      );

      expect(result.items.first.isInStock, isTrue);
      expect(result.items.first.fifoPriority, equals(2));
      expect(result.items.first.fifoWarning, isNotNull,
          reason: 'Phải có cảnh báo FIFO khi xuất chip mới mà kho còn chip cũ hơn');
    });

    test('Exact EPC match succeeds with zero shortage even when requested SKU is different or auto-generated', () async {
      final loc = repo.locations.first;

      // Giả lập hàng đã nhập vào kho với SKU A
      await repo.addItem(
        Item(
          itemId: 'ITEM-DIFF-01',
          productId: 'PROD-DIFF-01',
          sku: 'SKU-ORIGINAL-HEX123',
          productName: 'Nước ngọt Pepsi 330ml',
          serialNumber: 'SN-PEPSI-01',
          epc: 'EPC-PEPSI-EXACT-01',
          status: ItemStatus.inStock,
          locationId: loc.locationId,
          inboundTime: DateTime(2026, 1, 10),
        ),
      );

      // Yêu cầu xuất bằng file Excel sinh ra SKU tạm khác (SKU-AUTO-HEX999) nhưng đúng EPC
      final result = repo.validateOutboundInventoryAndFifo(
        requestedItems: [
          {
            'sku': 'SKU-AUTO-HEX999',
            'productName': 'Nước ngọt Pepsi 330ml',
            'epc': 'EPC-PEPSI-EXACT-01',
          },
        ],
      );

      expect(result.isStockSufficient, isTrue,
          reason: 'Khớp chính xác EPC thì không được báo thiếu dù SKU file nạp tạm thời bị lệch');
      expect(result.shortageCount, equals(0));
      expect(result.items.first.isInStock, isTrue);
      expect(result.items.first.sku, equals('SKU-ORIGINAL-HEX123'),
          reason: 'SKU phải được cập nhật chuẩn theo SKU thực tế trong kho');
      expect(result.items.first.locationCode, equals(loc.locationCode));
    });

    test('Include waitingPutaway status as available warehouse stock during outbound validation', () async {
      final loc = repo.locations.first;

      // Hàng vừa qua cổng nhập có trạng thái waitingPutaway
      await repo.addItem(
        Item(
          itemId: 'ITEM-WAIT-01',
          productId: 'PROD-WAIT-01',
          sku: 'TEST-SKU-WAIT',
          productName: 'Hàng Chờ Xếp Kệ',
          serialNumber: 'SN-WAIT-01',
          epc: 'EPC-WAITING-PUTAWAY-01',
          status: ItemStatus.waitingPutaway,
          locationId: loc.locationId,
          inboundTime: DateTime(2026, 2, 20),
        ),
      );

      final result = repo.validateOutboundInventoryAndFifo(
        requestedItems: [
          {
            'sku': 'TEST-SKU-WAIT',
            'epc': 'EPC-WAITING-PUTAWAY-01',
          },
        ],
      );

      expect(result.isStockSufficient, isTrue,
          reason: 'Hàng waitingPutaway đã ở trong kho nên được công nhận là tồn kho khả dụng');
      expect(result.shortageCount, equals(0));
      expect(result.items.first.isInStock, isTrue);
    });

    test('Items are sorted with oldest date (furthest date in past) first', () async {
      final loc = repo.locations.first;

      final dateFarPast = DateTime(2025, 12, 1);
      final dateMidPast = DateTime(2026, 1, 15);
      final dateRecent = DateTime(2026, 3, 1);

      await repo.addItem(
        Item(
          itemId: 'ITEM-DATE-NEW',
          productId: 'P-DATE',
          sku: 'TEST-SKU-DATE',
          productName: 'Hàng Mới',
          serialNumber: 'SN-D3',
          epc: 'EPC-D3',
          status: ItemStatus.inStock,
          locationId: loc.locationId,
          inboundTime: dateRecent,
        ),
      );
      await repo.addItem(
        Item(
          itemId: 'ITEM-DATE-MID',
          productId: 'P-DATE',
          sku: 'TEST-SKU-DATE',
          productName: 'Hàng Vừa',
          serialNumber: 'SN-D2',
          epc: 'EPC-D2',
          status: ItemStatus.inStock,
          locationId: loc.locationId,
          inboundTime: dateMidPast,
        ),
      );
      await repo.addItem(
        Item(
          itemId: 'ITEM-DATE-FAR',
          productId: 'P-DATE',
          sku: 'TEST-SKU-DATE',
          productName: 'Hàng Cũ Xa Nhất',
          serialNumber: 'SN-D1',
          epc: 'EPC-D1',
          status: ItemStatus.inStock,
          locationId: loc.locationId,
          inboundTime: dateFarPast,
        ),
      );

      // Nạp danh sách theo thứ tự lộn xộn
      final result = repo.validateOutboundInventoryAndFifo(
        requestedItems: [
          {'sku': 'TEST-SKU-DATE', 'epc': 'EPC-D3'},
          {'sku': 'TEST-SKU-DATE', 'epc': 'EPC-D1'},
          {'sku': 'TEST-SKU-DATE', 'epc': 'EPC-D2'},
        ],
      );

      expect(result.isStockSufficient, isTrue);
      // Kiểm tra sắp xếp theo date xa nhất lên đầu (2025-12-01 trước 2026-01-15 trước 2026-03-01)
      expect(result.items[0].epc, equals('EPC-D1'));
      expect(result.items[0].inboundTime, equals(dateFarPast));

      expect(result.items[1].epc, equals('EPC-D2'));
      expect(result.items[1].inboundTime, equals(dateMidPast));

      expect(result.items[2].epc, equals('EPC-D3'));
      expect(result.items[2].inboundTime, equals(dateRecent));
    });
  });
}
