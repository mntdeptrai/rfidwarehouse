import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/pda/pda_lookup_screen.dart';
import 'package:uhf/screens/pda/pda_transfer_screen.dart';
import 'package:uhf/screens/storage_screen.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Individual Item Movement & Handheld Lookup Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
    });

    test('WarehouseRepository.moveItemIndividual transfers item and updates pallet links', () async {
      final loc1 = Location(locationId: 'TEST-LOC-1', locationCode: 'LOC-001', zone: 'A', shelf: 'Kệ 1', level: '1');
      final loc2 = Location(locationId: 'TEST-LOC-2', locationCode: 'LOC-002', zone: 'B', shelf: 'Kệ 2', level: '1');
      await repo.addLocation(loc1);
      await repo.addLocation(loc2);

      const testEpc = 'E28068940000TEST001';
      final testItem = Item(
        itemId: 'ITEM-TEST-001',
        productId: 'PROD-TEST-001',
        sku: 'SKU-TEST-001',
        productName: 'Thiết bị Test Vô Tuyến',
        serialNumber: 'SN-TEST-VT-001',
        epc: testEpc,
        status: ItemStatus.inStock,
        locationId: 'TEST-LOC-1',
      );

      final pallet1 = repo.createOrAssignPallet(
        palletCode: 'PL-TEST-001',
        locationId: 'TEST-LOC-1',
        newItems: [testItem],
      );

      final pallet2 = repo.createOrAssignPallet(
        palletCode: 'PL-TEST-002',
        locationId: 'TEST-LOC-2',
        newItems: [],
      );

      expect(pallet1.itemIds.contains(testItem.itemId), isTrue);

      // Move item individually to loc2 and pallet2
      final success = await repo.moveItemIndividual(
        epc: testEpc,
        newLocationId: 'TEST-LOC-2',
        newPalletId: pallet2.palletId,
        performedBy: 'Kỹ thuật viên Test',
      );

      expect(success, isTrue);
      expect(testItem.locationId, equals('TEST-LOC-2'));
      expect(testItem.palletId, equals(pallet2.palletId));
      expect(pallet1.itemIds.contains(testItem.itemId), isFalse, reason: 'Must be detached from old pallet');
      expect(pallet2.itemIds.contains(testItem.itemId), isTrue, reason: 'Must be added to new pallet');

      // Now move item to loc1 without pallet (loose item on shelf)
      final successLoose = await repo.moveItemIndividual(
        epc: testEpc,
        newLocationId: 'TEST-LOC-1',
        newPalletId: null,
        performedBy: 'Kỹ thuật viên Test',
      );

      expect(successLoose, isTrue);
      expect(testItem.locationId, equals('TEST-LOC-1'));
      expect(testItem.palletId, isNull);
      expect(pallet2.itemIds.contains(testItem.itemId), isFalse, reason: 'Detached from pallet2');

      // Check transaction logged
      final tx = repo.transactions.where((t) => t.sku == testItem.sku).firstOrNull;
      expect(tx, isNotNull);
      expect(tx!.type, equals(TransactionType.movement));
    });

    testWidgets('PdaLookupScreen searches by S/N, Product ID, SKU and provides move option', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));

      const testEpc = 'E28068940000LOOKUP99';
      final lookupItem = Item(
        itemId: 'ITEM-LOOKUP-99',
        productId: 'PROD-LOOKUP-99',
        sku: 'SKU-LOOKUP-99',
        productName: 'Điều hòa Daikin Test',
        serialNumber: 'SN-LOOKUP-DK-99',
        epc: testEpc,
        status: ItemStatus.inStock,
        locationId: 'LOC-001',
      );

      repo.createOrAssignPallet(
        palletCode: 'PL-LOOKUP-01',
        locationId: 'LOC-001',
        newItems: [lookupItem],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const PdaLookupScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Enter serial number in search box
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);

      await tester.enterText(searchField, 'SN-LOOKUP-DK-99');
      await tester.pumpAndSettle();

      // Should find the item
      expect(find.textContaining('Điều hòa Daikin Test'), findsOneWidget);
      expect(find.textContaining('ĐỔI KỆ / CHUYỂN VỊ TRÍ'), findsOneWidget);

      // Search with prefix S/N:
      await tester.enterText(searchField, 'S/N: SN-LOOKUP-DK-99');
      await tester.pumpAndSettle();
      expect(find.textContaining('Điều hòa Daikin Test'), findsOneWidget);

      // Search by Product ID
      await tester.enterText(searchField, 'PROD-LOOKUP-99');
      await tester.pumpAndSettle();
      expect(find.textContaining('Điều hòa Daikin Test'), findsOneWidget);

      // Search by SKU
      await tester.enterText(searchField, 'SKU-LOOKUP-99');
      await tester.pumpAndSettle();
      expect(find.textContaining('Điều hòa Daikin Test'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('PdaTransferScreen initializes with initialItem and shows details', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 800));

      final testItem = Item(
        itemId: 'ITEM-XFER-01',
        productId: 'PROD-XFER-01',
        sku: 'SKU-XFER-01',
        productName: 'Server CNTT Test',
        serialNumber: 'SN-XFER-SRV-01',
        epc: 'E28068940000XFER01',
        status: ItemStatus.inStock,
        locationId: 'LOC-001',
      );

      repo.createOrAssignPallet(
        palletCode: 'PL-XFER-01',
        locationId: 'LOC-001',
        newItems: [testItem],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: PdaTransferScreen(initialItem: testItem),
        ),
      );
      await tester.pumpAndSettle();

      // Should show in Items mode with preloaded item
      expect(find.textContaining('Server CNTT Test'), findsOneWidget);
      expect(find.textContaining('Sản phẩm riêng lẻ'), findsOneWidget);
      expect(find.textContaining('XÁC NHẬN CẬP NHẬT VỊ TRÍ'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('StorageScreen renders CHUYỂN SẢN PHẨM button in toolbar and dialog opens', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const StorageScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final moveBtn = find.widgetWithText(ElevatedButton, 'CHUYỂN SẢN PHẨM');
      expect(moveBtn, findsOneWidget);

      await tester.tap(moveBtn);
      await tester.pumpAndSettle();

      expect(find.text('Di Chuyển Sản Phẩm Riêng Lẻ'), findsOneWidget);
      expect(find.text('1. Chọn kho đến (Vị trí kệ kho đích):'), findsOneWidget);
      expect(find.text('2. Quét mã RFID EPC của sản phẩm đó:'), findsOneWidget);
      expect(find.text('XÁC NHẬN CẬP NHẬT VỊ TRÍ'), findsOneWidget);

      // Tap cancel
      await tester.tap(find.text('HỦY'));
      await tester.pumpAndSettle();

      await tester.binding.setSurfaceSize(null);
    });
  });
}
