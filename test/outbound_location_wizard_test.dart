import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_delivery_view.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/widgets/warehouse_location_grid_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Outbound 10 Locations & Guided Table Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureDefault10Locations();
    });

    test('ensureDefault10Locations creates at least 10 locations', () {
      expect(repo.locations.length, greaterThanOrEqualTo(10));
      final codes = repo.locations.map((l) => l.locationCode).toSet();
      expect(codes.contains('A-01'), isTrue);
      expect(codes.contains('A-02'), isTrue);
      expect(codes.contains('B-01'), isTrue);
    });

    test('updateLocationStatus updates location status between EMPTY, AVAILABLE, FULL', () async {
      final loc = repo.locations.first;
      await repo.updateLocationStatus(loc.locationId, 'FULL');
      expect(loc.status, equals('FULL'));

      await repo.updateLocationStatus(loc.locationId, 'EMPTY');
      expect(loc.status, equals('EMPTY'));

      await repo.updateLocationStatus(loc.locationId, 'AVAILABLE');
      expect(loc.status, equals('AVAILABLE'));
    });

    test('updateLocationDetails updates name, capacity, zone, level', () async {
      final loc = repo.locations.first;
      await repo.updateLocationDetails(
        locationId: loc.locationId,
        locationCode: 'A-99',
        zone: 'Khu VIP',
        shelf: 'Kệ 99',
        level: 'Tầng 3',
        maxCapacity: 100,
        status: 'AVAILABLE',
      );

      final updated = repo.locations.firstWhere((l) => l.locationId == loc.locationId);
      expect(updated.locationCode, equals('A-99'));
      expect(updated.zone, equals('Khu VIP'));
      expect(updated.maxPalletCapacity, equals(100));
    });

    test('getItemsAtLocation finds items stored at specific location', () async {
      final loc = repo.locations.first;
      final testItem = Item(
        itemId: 'ITEM-TEST-LOC-01',
        productId: 'PROD-01',
        sku: 'SKU-TEST-LOC',
        productName: 'Sản phẩm Test Vị Trí',
        serialNumber: 'SN-LOC-01',
        epc: 'E280119100000000LOC00001',
        status: ItemStatus.inStock,
        locationId: loc.locationId,
      );

      await repo.addItem(testItem);

      final itemsAtLoc = repo.getItemsAtLocation(loc);
      expect(itemsAtLoc.any((i) => i.epc == testItem.epc), isTrue);
    });

    test('confirmDirectOutbound deducts items and marks them as out', () async {
      final loc = repo.locations.first;
      final testItem = Item(
        itemId: 'ITEM-DIRECT-OUT-01',
        productId: 'PROD-OUT',
        sku: 'SKU-OUT-01',
        productName: 'Sản phẩm Xuất Trực Tiếp',
        serialNumber: 'SN-OUT-01',
        epc: 'E280119100000000OUT00001',
        status: ItemStatus.inStock,
        locationId: loc.locationId,
      );

      await repo.addItem(testItem);

      final shipped = await repo.confirmDirectOutbound(
        poNo: 'TEST-OUT-PO-01',
        scannedEpcs: [testItem.epc],
        performedBy: 'Test Runner',
      );

      expect(shipped, equals(1));
      expect(testItem.status, equals(ItemStatus.out));
      expect(testItem.locationId, isNull);
    });

    testWidgets('DesktopGoodsDeliveryView displays 10 locations and table', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DesktopGoodsDeliveryView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Sơ đồ vị trí hiển thị
      expect(find.textContaining('SƠ ĐỒ 10 VỊ TRÍ'), findsOneWidget);
      // Nút tiếp tục qua cổng RFID xuất kho ở góc phải
      expect(find.textContaining('TIẾP TỤC: QUA CỔNG RFID XUẤT KHO'), findsOneWidget);
    });

    testWidgets('WarehouseLocationGridWidget uses GridView, scrolls smoothly and supports collapse/expand', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: WarehouseLocationGridWidget(),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // GridView is used instead of Column/Wrap
      expect(find.byType(GridView), findsOneWidget);

      // Verify cards exist in the grid
      expect(find.textContaining('KỆ 01'), findsOneWidget);

      // Tap collapse button
      final collapseBtn = find.byTooltip('Thu gọn lưới ô kệ');
      expect(collapseBtn, findsOneWidget);
      await tester.tap(collapseBtn);
      await tester.pump(const Duration(milliseconds: 200));

      // Now GridView is hidden
      expect(find.byType(GridView), findsNothing);

      // Tap expand button
      final expandBtn = find.byTooltip('Mở rộng lưới ô kệ');
      expect(expandBtn, findsOneWidget);
      await tester.tap(expandBtn);
      await tester.pump(const Duration(milliseconds: 200));

      // GridView is restored
      expect(find.byType(GridView), findsOneWidget);
    });
  });
}
