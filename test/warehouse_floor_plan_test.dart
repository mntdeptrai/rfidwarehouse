import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/widgets/warehouse_floor_plan_widget.dart';
import 'package:uhf/widgets/warehouse_floor_plan_editor_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Warehouse Floor Plan & Pallet Navigation Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
      await repo.ensureDefault10Locations();
    });

    test('WarehouseFloorPlanConfig serialization and presets work properly', () {
      const config = WarehouseFloorPlanConfig(
        layoutType: WarehouseLayoutType.uShape,
        warehouseName: 'KHO TỔNG MIỀN BẮC',
        entryGateName: 'CỔNG VÀO SỐ 1',
        exitGateName: 'CỔNG RA SỐ 2',
        isSingleGate: false,
        mainAisleLabel: 'LỐI ĐI XE NÂNG 4M',
      );

      final json = config.toJson();
      expect(json['layoutType'], 'uShape');
      expect(json['warehouseName'], 'KHO TỔNG MIỀN BẮC');
      expect(json['entryGateName'], 'CỔNG VÀO SỐ 1');
      expect(json['exitGateName'], 'CỔNG RA SỐ 2');

      final fromJson = WarehouseFloorPlanConfig.fromJson(json);
      expect(fromJson.layoutType, WarehouseLayoutType.uShape);
      expect(fromJson.warehouseName, 'KHO TỔNG MIỀN BẮC');
      expect(fromJson.entryGateName, 'CỔNG VÀO SỐ 1');
      expect(fromJson.isSingleGate, false);
    });

    test('Location model supports aisleSide and sortOrder', () {
      final loc = Location(
        locationId: 'LOC-A-01',
        locationCode: 'A-01',
        zone: 'Khu A',
        shelf: 'Kệ 01',
        level: 'Tầng 1',
        maxPalletCapacity: 60,
        aisleSide: 'LEFT',
        sortOrder: 1,
      );

      expect(loc.aisleSide, 'LEFT');
      expect(loc.sortOrder, 1);
      expect(loc.displayName, 'KỆ 01');

      final map = loc.toMap();
      expect(map['aisle_side'], 'LEFT');
      expect(map['sort_order'], 1);

      final copy = loc.copyWith(aisleSide: 'RIGHT', sortOrder: 5);
      expect(copy.aisleSide, 'RIGHT');
      expect(copy.sortOrder, 5);
    });

    test('WarehouseRepository manages customer layout configuration and presets', () async {
      const customConfig = WarehouseFloorPlanConfig(
        layoutType: WarehouseLayoutType.parallelAisles,
        warehouseName: 'KHO KHÁCH HÀNG THỰC TẾ',
        entryGateName: 'CỔNG NHẬP XE PALLET',
        exitGateName: 'CỔNG XUẤT THÀNH PHẨM',
        isSingleGate: true,
        mainAisleLabel: 'ĐƯỜNG CHẠY XE NÂNG CHÍNH',
      );

      await repo.saveWarehouseLayoutConfig(customConfig);
      expect(repo.floorPlanConfig.warehouseName, 'KHO KHÁCH HÀNG THỰC TẾ');
      expect(repo.floorPlanConfig.entryGateName, 'CỔNG NHẬP XE PALLET');
      expect(repo.floorPlanConfig.isSingleGate, true);

      // Reset to U-Shape
      await repo.resetLayoutToPreset(WarehouseLayoutType.uShape);
      expect(repo.floorPlanConfig.layoutType, WarehouseLayoutType.uShape);
      expect(repo.locations.any((l) => l.aisleSide == 'LEFT'), isTrue);
      expect(repo.locations.any((l) => l.aisleSide == 'BACK'), isTrue);
      expect(repo.locations.any((l) => l.aisleSide == 'RIGHT'), isTrue);
    });

    test('WarehouseRepository can add, update and delete custom customer racks', () async {
      final customRack = Location(
        locationId: 'LOC-CUSTOM-99',
        locationCode: 'C-99',
        zone: 'Khu Hóa Chất',
        shelf: 'Kệ Đặc Biệt',
        level: 'Tầng Trệt',
        maxPalletCapacity: 100,
        aisleSide: 'RIGHT',
        sortOrder: 10,
      );

      await repo.addCustomLocation(customRack);
      expect(repo.locations.any((l) => l.locationCode == 'C-99'), isTrue);

      await repo.updateLocationDetails(
        locationId: 'LOC-CUSTOM-99',
        locationCode: 'C-99-UPDATED',
        zone: 'Khu Hóa Chất An Toàn',
        shelf: 'Kệ Đặc Biệt VIP',
        level: 'Tầng 2',
        maxCapacity: 120,
        aisleSide: 'LEFT',
        sortOrder: 2,
      );

      final updated = repo.locations.firstWhere((l) => l.locationId == 'LOC-CUSTOM-99');
      expect(updated.locationCode, 'C-99-UPDATED');
      expect(updated.shelf, 'Kệ Đặc Biệt VIP');
      expect(updated.maxPalletCapacity, 120);
      expect(updated.aisleSide, 'LEFT');

      await repo.deleteCustomLocation('LOC-CUSTOM-99');
      expect(repo.locations.any((l) => l.locationId == 'LOC-CUSTOM-99'), isFalse);
    });

    testWidgets('WarehouseFloorPlanWidget renders 2D map, gates, and navigation banner without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? selectedLoc;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) => SingleChildScrollView(
                child: WarehouseFloorPlanWidget(
                  mode: WarehouseFloorPlanMode.outbound,
                  selectedLocationId: selectedLoc,
                  onLocationSelected: (locId) {
                    setState(() => selectedLoc = locId);
                  },
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      // Sơ đồ hiển thị đầy đủ
      expect(find.textContaining('SƠ ĐỒ 10 VỊ TRÍ & MẶT BẰNG KHO'), findsOneWidget);
      expect(find.textContaining('CẤU HÌNH SƠ ĐỒ KHO'), findsOneWidget);

      // Chạm vào một kệ để kích hoạt lộ trình dẫn đường cho xe nâng
      final targetRackFinder = find.textContaining('KỆ 01').first;
      await tester.tap(targetRackFinder);
      await tester.pump(const Duration(milliseconds: 300));

      // Breadcrumb điều hướng xe nâng xuất hiện
      expect(find.textContaining('LỘ TRÌNH LẤY HÀNG XUẤT:'), findsOneWidget);
      expect(find.textContaining('Đi thẳng theo Lối Chính'), findsOneWidget);
    });

    testWidgets('WarehouseFloorPlanEditorDialog opens and displays customization tabs', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const Scaffold(
            body: WarehouseFloorPlanEditorDialog(),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('CẤU HÌNH SƠ ĐỒ MẶT BẰNG KHO THỰC TẾ'), findsOneWidget);
      expect(find.text('1. MẪU MẶT BẰNG KHO'), findsOneWidget);
      expect(find.text('2. CỔNG VÀO / RA & LỐI XE'), findsOneWidget);
      expect(find.text('3. QUẢN LÝ CÁC DÃY KỆ'), findsOneWidget);

      // Chuyển sang Tab 2
      await tester.tap(find.text('2. CỔNG VÀO / RA & LỐI XE'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tên Kho Hàng / Khách Hàng'), findsOneWidget);

      // Chuyển sang Tab 3
      await tester.tap(find.text('3. QUẢN LÝ CÁC DÃY KỆ'));
      await tester.pumpAndSettle();
      expect(find.text('THÊM KỆ MỚI'), findsOneWidget);
    });
  });
}
