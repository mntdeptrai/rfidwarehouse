import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/models/inventory_models.dart';
import 'package:uhf/models/catalog_models.dart';
import 'package:uhf/models/tag_info.dart';
import 'package:uhf/services/desktop_uhf_tcp_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Master Pallet RFID Recognition Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
    });

    test('Database starts clean with no mock pallets', () {
      final pl1 = repo.pallets.where((p) => p.palletCode == 'PL-001').firstOrNull;
      expect(pl1, isNull);
    });

    test('findPalletByRfid correctly matches registered Pallet by RFID EPC', () async {
      await repo.registerOrUpdatePallet(
        palletCode: 'PALLET-A1',
        rfidEpc: 'E28011700000020ECA501234',
      );

      final found1 = repo.findPalletByRfid('E28011700000020ECA501234');
      expect(found1, isNotNull);
      expect(found1?.palletCode, equals('PALLET-A1'));

      final notFound = repo.findPalletByRfid('FFFFFFFFFFFFFFFFFFFFFFFF');
      expect(notFound, isNull);
    });

    test('Registers new pallet and matches it', () async {
      await repo.registerOrUpdatePallet(
        palletCode: 'PL-099',
        rfidEpc: 'E28011910000000000000099',
      );

      final found = repo.findPalletByRfid('E28011910000000000000099');
      expect(found, isNotNull);
      expect(found?.palletCode, equals('PL-099'));
    });

    test('assignItemsToPallet directly binds items to recognized pallet', () async {
      final item1 = Item(
        itemId: 'ITEM-T1',
        productId: 'SKU1',
        sku: 'SKU1',
        productName: 'Áo Thun',
        serialNumber: 'EPC001',
        epc: 'EPC001',
        status: ItemStatus.pendingInbound,
      );
      final item2 = Item(
        itemId: 'ITEM-T2',
        productId: 'SKU2',
        sku: 'SKU2',
        productName: 'Quần Kaki',
        serialNumber: 'EPC002',
        epc: 'EPC002',
        status: ItemStatus.pendingInbound,
      );
      await repo.insertDirectItem(item1);
      await repo.insertDirectItem(item2);

      await repo.assignItemsToPallet(
        palletCode: 'PL-001',
        itemEpcs: ['EPC001', 'EPC002'],
      );

      final updated1 = repo.items.where((i) => i.epc == 'EPC001').first;
      final updated2 = repo.items.where((i) => i.epc == 'EPC002').first;

      expect(updated1.palletId, equals('PL-001'));
      expect(updated2.palletId, equals('PL-001'));
    });

    test('insertDirectItems inserts multiple items in batch without overhead', () async {
      final batchItems = List.generate(
        10,
        (i) => Item(
          itemId: 'BATCH-ITEM-$i',
          productId: 'SKU-BATCH',
          sku: 'SKU-BATCH',
          productName: 'Sản phẩm Batch $i',
          serialNumber: 'BATCH-EPC-$i',
          epc: 'BATCH-EPC-$i',
          status: ItemStatus.pendingInbound,
        ),
      );

      await repo.insertDirectItems(batchItems);

      for (int i = 0; i < 10; i++) {
        final found = repo.items.where((it) => it.epc == 'BATCH-EPC-$i').firstOrNull;
        expect(found, isNotNull);
        expect(found?.productName, equals('Sản phẩm Batch $i'));
      }
    });

    test('DesktopUhfTcpService continuously emits tags to onTagRead even for repeated reads', () async {
      final uhf = DesktopUhfTcpService();
      // Bật chế độ quét ảo
      await uhf.startInventory();

      final emittedEpcs = <String>[];
      final sub = uhf.onTagRead.listen((t) {
        emittedEpcs.add(t.epc);
      });

      // Ghi thẻ lần 1
      uhf.recordTag(TagInfo(epc: 'E280TEST0001'));
      // Ghi thẻ lần 2 (thẻ đã tồn tại trong _tagsMap)
      uhf.recordTag(TagInfo(epc: 'E280TEST0001'));
      // Ghi thẻ lạ
      uhf.recordTag(TagInfo(epc: 'E280STRANGER99'));

      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      await uhf.stopInventory();

      expect(emittedEpcs.length, equals(3));
      expect(emittedEpcs, contains('E280TEST0001'));
      expect(emittedEpcs, contains('E280STRANGER99'));
    });

    test('Pallet PL-001 declared once is persisted and NEVER deleted across multiple init cycles', () async {
      await repo.registerOrUpdatePallet(
        palletCode: 'PL-001',
        rfidEpc: 'E2806A960000402C4760454A',
      );

      expect(repo.pallets.where((p) => p.palletCode == 'PL-001').isNotEmpty, isTrue);

      // Re-run initialization (simulating app restart or sync)
      await repo.ensureInitialized();

      final preserved = repo.findPalletByRfid('E2806A960000402C4760454A');
      expect(preserved, isNotNull);
      expect(preserved?.palletCode, equals('PL-001'));
      expect(preserved?.rfidEpc, equals('E2806A960000402C4760454A'));
    });

    test('Pallet code and RFID can be edited/renamed and persists correctly', () async {
      await repo.registerOrUpdatePallet(
        palletCode: 'PL-OLD',
        rfidEpc: 'E280OLD00000000000000001',
      );

      expect(repo.findPalletByRfid('E280OLD00000000000000001')?.palletCode, equals('PL-OLD'));

      // Edit pallet code and change chip
      await repo.registerOrUpdatePallet(
        palletCode: 'PL-RENAMED',
        rfidEpc: 'E280NEW00000000000000002',
        oldPalletCode: 'PL-OLD',
      );

      // Old code and old chip should not match PL-OLD
      expect(repo.findPalletByRfid('E280OLD00000000000000001'), isNull);
      expect(repo.pallets.where((p) => p.palletCode == 'PL-OLD'), isEmpty);

      // New code and chip must match
      final updated = repo.findPalletByRfid('E280NEW00000000000000002');
      expect(updated, isNotNull);
      expect(updated?.palletCode, equals('PL-RENAMED'));
    });

    test('deletePalletFromMaster completely deletes pallet from DB, memory, and survives reload', () async {
      await repo.registerOrUpdatePallet(
        palletCode: 'PL-TO-DELETE',
        rfidEpc: 'E280DEL00000000000000099',
      );

      expect(repo.findPalletByRfid('E280DEL00000000000000099'), isNotNull);

      // Delete the pallet
      await repo.deletePalletFromMaster('PL-TO-DELETE');

      expect(repo.findPalletByRfid('E280DEL00000000000000099'), isNull);
      expect(repo.pallets.where((p) => p.palletCode == 'PL-TO-DELETE'), isEmpty);

      // Reload from SQLite to simulate app restart
      await repo.reloadFromSqlite();

      expect(repo.findPalletByRfid('E280DEL00000000000000099'), isNull);
      expect(repo.pallets.where((p) => p.palletCode == 'PL-TO-DELETE'), isEmpty);
    });

    test('addLocation, deleteLocation, and generateSampleWarehouseLayout manage racks correctly', () async {
      // Initially no locations
      expect(repo.locations, isEmpty);

      // Generate sample layout
      await repo.generateSampleWarehouseLayout();
      expect(repo.locations.length, equals(12)); // 2 zones x 2 shelves x 3 levels

      final locA11 = repo.locations.firstWhere((l) => l.locationCode == 'A-01-01');
      expect(locA11.zone, equals('Khu A'));
      expect(locA11.shelf, equals('Kệ 01'));
      expect(locA11.level, equals('Tầng 1'));
      expect(locA11.maxPalletCapacity, equals(2));

      // Capacity status check: initially empty
      expect(repo.getPalletCountForLocation(locA11), equals(0));

      // Register a pallet and place it in A-01-01
      await repo.registerOrUpdatePallet(palletCode: 'PL-TEST-01', rfidEpc: 'E280LOC00000000000000001');
      await repo.putawayPalletToLocation(palletCodeOrId: 'PL-TEST-01', locationId: 'A-01-01');

      // Now 1/2 pallets -> Còn chỗ (has space)
      expect(repo.getPalletCountForLocation(locA11), equals(1));
      expect(repo.getPalletsForLocation(locA11).map((p) => p.palletCode), contains('PL-TEST-01'));

      // Put second pallet into A-01-01 -> Đã đầy (full)
      await repo.registerOrUpdatePallet(palletCode: 'PL-TEST-02', rfidEpc: 'E280LOC00000000000000002');
      await repo.putawayPalletToLocation(palletCodeOrId: 'PL-TEST-02', locationId: 'A-01-01');
      expect(repo.getPalletCountForLocation(locA11), equals(2));

      // Add a custom location
      await repo.addLocation(Location(
        locationId: 'LOC-C-05-01',
        locationCode: 'C-05-01',
        zone: 'Khu C',
        shelf: 'Kệ 05',
        level: 'Tầng 01',
        maxPalletCapacity: 4,
      ));
      expect(repo.locations.where((l) => l.locationCode == 'C-05-01').isNotEmpty, isTrue);

      // Delete custom location
      await repo.deleteLocation('C-05-01');
      expect(repo.locations.where((l) => l.locationCode == 'C-05-01').isEmpty, isTrue);
    });
  });
}

