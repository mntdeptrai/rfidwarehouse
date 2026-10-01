import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('2 Distinct Locations - Pallet & QR Location Putaway Acceptance Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
      await repo.clearAllData(alsoClearCloud: false);
    });

    tearDown(() async {
      await repo.clearAllData(alsoClearCloud: false);
    });

    test('1. Khai báo 2 location riêng biệt -> Quét Pallet + Quét QR location -> Hệ thống update chính xác vị trí hàng hoá', () async {
      // -----------------------------------------------------------------------
      // BƯỚC 1: Khai báo vị trí trong kho theo 2 location riêng biệt
      // -----------------------------------------------------------------------
      final locA = Location(
        locationId: 'LOC-ZONE-A-01',
        locationCode: 'ZONE-A-01',
        zone: 'Khu A',
        shelf: 'Kệ 01',
        level: 'Tầng 1',
        maxPalletCapacity: 10,
        currentPallets: 0,
        status: 'AVAILABLE',
      );

      final locB = Location(
        locationId: 'LOC-ZONE-B-02',
        locationCode: 'ZONE-B-02',
        zone: 'Khu B',
        shelf: 'Kệ 02',
        level: 'Tầng 2',
        maxPalletCapacity: 10,
        currentPallets: 0,
        status: 'AVAILABLE',
      );

      await repo.addLocation(locA);
      await repo.addLocation(locB);

      expect(repo.locations.any((l) => l.locationId == 'LOC-ZONE-A-01'), isTrue);
      expect(repo.locations.any((l) => l.locationId == 'LOC-ZONE-B-02'), isTrue);

      // -----------------------------------------------------------------------
      // CHUẨN BỊ: Hàng hóa trên Pallet (Lô hàng chờ xếp kho)
      // -----------------------------------------------------------------------
      const testPalletCode = 'PAL-2026-X1';
      final item1 = Item(
        itemId: 'ITEM-X1-001',
        productId: 'PROD-001',
        sku: 'SKU-ELECTRONIC-01',
        productName: 'Bo Mạch Điện Tử A1',
        serialNumber: 'SN-001-A',
        epc: 'E28000000000000000000001',
        palletId: testPalletCode,
        status: ItemStatus.waitingPutaway,
      );

      final item2 = Item(
        itemId: 'ITEM-X1-002',
        productId: 'PROD-001',
        sku: 'SKU-ELECTRONIC-01',
        productName: 'Bo Mạch Điện Tử A1',
        serialNumber: 'SN-002-A',
        epc: 'E28000000000000000000002',
        palletId: testPalletCode,
        status: ItemStatus.waitingPutaway,
      );

      repo.createOrAssignPallet(
        palletCode: testPalletCode,
        locationId: null,
        newItems: [item1, item2],
      );

      final palletBefore = repo.pallets.firstWhere((p) => p.palletCode == testPalletCode);
      expect(palletBefore.locationId, isNull);

      // -----------------------------------------------------------------------
      // BƯỚC 2: Quét mã Pallet + Quét mã QR code location trong kho
      // (Test gán chính xác vào Location 2: LOC-ZONE-B-02 thay vì Location 1)
      // -----------------------------------------------------------------------
      final savedCount = await repo.confirmPdaPutawayByCarton(
        cartonOrOrderBarcode: testPalletCode,
        locationId: 'LOC-ZONE-B-02',
        performedBy: 'Thủ kho PDA - Nguyễn Văn A',
      );

      // -----------------------------------------------------------------------
      // BƯỚC 3: Phần mềm hệ thống xác nhận hàng hoá đã update theo vị trí trong kho
      // -----------------------------------------------------------------------
      expect(savedCount, equals(2));

      // 3.1. Pallet được update đúng location B
      final palletAfter = repo.pallets.firstWhere((p) => p.palletCode == testPalletCode);
      expect(palletAfter.locationId, equals('LOC-ZONE-B-02'));
      expect(palletAfter.locationId, isNot(equals('LOC-ZONE-A-01')));

      // 3.2. Toàn bộ hàng hoá (items) trên Pallet được update đúng vị trí và trạng thái inStock
      final updatedItems = repo.items.where((i) => i.palletId == palletAfter.palletId || i.palletId == testPalletCode).toList();
      expect(updatedItems.length, equals(2));
      for (final it in updatedItems) {
        expect(it.status, equals(ItemStatus.inStock));
        expect(it.locationId, equals('LOC-ZONE-B-02'));
        expect(it.locationId, isNot(equals('LOC-ZONE-A-01')));
      }

      // 3.3. Hệ thống tạo nhật ký giao dịch ghi nhận vị trí đích chính xác
      final tx = repo.transactions.firstWhere((t) => t.documentNo == testPalletCode);
      expect(tx.toLocation, equals('ZONE-B-02'));
      expect(tx.type, equals(TransactionType.movement));
    });

    test('2. Điều chuyển Pallet từ Location 1 sang Location 2 bằng quét mã Pallet + QR code location', () async {
      // Khai báo 2 location riêng biệt
      final locA = Location(
        locationId: 'LOC-RACK-01',
        locationCode: 'RACK-01',
        zone: 'Zone Đông',
        shelf: 'Kệ 01',
        level: 'Tầng 1',
        currentPallets: 1,
      );
      final locB = Location(
        locationId: 'LOC-RACK-02',
        locationCode: 'RACK-02',
        zone: 'Zone Tây',
        shelf: 'Kệ 02',
        level: 'Tầng 1',
        currentPallets: 0,
      );
      await repo.addLocation(locA);
      await repo.addLocation(locB);

      const palletCode = 'PAL-MOVE-88';
      final item = Item(
        itemId: 'ITEM-MOVE-01',
        productId: 'PROD-002',
        sku: 'SKU-002',
        productName: 'Linh Kiện Máy',
        serialNumber: 'SN-MOVE-01',
        epc: 'E28000000000000000000088',
        palletId: palletCode,
        status: ItemStatus.inStock,
        locationId: 'LOC-RACK-01',
      );

      repo.createOrAssignPallet(
        palletCode: palletCode,
        locationId: 'LOC-RACK-01',
        newItems: [item],
      );

      // Quét mã Pallet + Quét QR code Location 2 (RACK-02) để chuyển vị trí
      final movedCount = await repo.transferPalletToLocation(
        palletEpc: palletCode,
        newLocationId: 'LOC-RACK-02',
        performedBy: 'PDA Scanner',
      );

      expect(movedCount, equals(1));

      // Kiểm tra vị trí Pallet và Hàng hoá đã cập nhật sang Location 2
      final updatedPallet = repo.pallets.firstWhere((p) => p.palletCode == palletCode);
      expect(updatedPallet.locationId, equals('LOC-RACK-02'));

      final updatedItem = repo.items.firstWhere((i) => i.itemId == 'ITEM-MOVE-01');
      expect(updatedItem.locationId, equals('LOC-RACK-02'));
      expect(updatedItem.status, equals(ItemStatus.inStock));

      // Số lượng pallet trên các ô kệ được cập nhật tương ứng
      expect(locA.currentPallets, equals(0));
      expect(locB.currentPallets, equals(1));
    });

    test('3. Hỗ trợ quét mã QR code location với các định dạng tiền tố (LOCATION:, LOC:, SHELF:) không nhầm lẫn', () async {
      final loc1 = Location(
        locationId: 'LOC-STORAGE-01',
        locationCode: 'STORAGE-01',
        zone: 'Zone Kho 1',
        shelf: 'Kệ 10',
        level: 'Tầng 1',
      );
      final loc2 = Location(
        locationId: 'LOC-STORAGE-02',
        locationCode: 'STORAGE-02',
        zone: 'Zone Kho 2',
        shelf: 'Kệ 20',
        level: 'Tầng 1',
      );
      await repo.addLocation(loc1);
      await repo.addLocation(loc2);

      const palletCode = 'PAL-QR-PREFIX-01';
      final item = Item(
        itemId: 'ITEM-QR-01',
        productId: 'PROD-003',
        sku: 'SKU-003',
        productName: 'Mặt Hàng QR Test',
        serialNumber: 'SN-QR-01',
        epc: 'E28000000000000000000099',
        palletId: palletCode,
        status: ItemStatus.waitingPutaway,
      );

      repo.createOrAssignPallet(
        palletCode: palletCode,
        locationId: null,
        newItems: [item],
      );

      // Quét mã QR code với định dạng "LOCATION:LOC-STORAGE-02" hoặc mã vị trí thuần
      final count = await repo.confirmPdaPutawayByCarton(
        cartonOrOrderBarcode: palletCode,
        locationId: 'LOC-STORAGE-02',
        performedBy: 'PDA QR Scanner',
      );

      expect(count, equals(1));

      final palletAfter = repo.pallets.firstWhere((p) => p.palletCode == palletCode);
      expect(palletAfter.locationId, equals('LOC-STORAGE-02'));
      expect(palletAfter.locationId, isNot(equals('LOC-STORAGE-01')));

      final itemAfter = repo.items.firstWhere((i) => i.itemId == 'ITEM-QR-01');
      expect(itemAfter.locationId, equals('LOC-STORAGE-02'));
      expect(itemAfter.status, equals(ItemStatus.inStock));
    });
  });
}

