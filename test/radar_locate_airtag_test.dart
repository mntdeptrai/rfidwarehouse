import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/screens/radar_locate_screen.dart';
import 'package:uhf/widgets/direction_arrow_widget.dart';
import 'package:uhf/screens/pda/pda_home_screen.dart';
import 'package:uhf/screens/pda/pda_warehouse_management_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WarehouseRepository repo;
  late UhfService uhf;

  setUp(() async {
    repo = WarehouseRepository();
    uhf = UhfService();
    await repo.ensureInitialized();
    await repo.clearAllData();

    // Thêm dữ liệu kiểm thử qua repository methods
    await repo.addProduct(const Product(
      productId: 'PROD-AIRTAG-01',
      sku: 'SKU-AIRTAG',
      productName: 'Mặt Hàng Thử Nghiệm AirTag',
      unit: 'Cái',
      category: 'Linh kiện',
    ));

    await repo.addLocation(Location(
      locationId: 'LOC-A01-01',
      locationCode: 'A01-01',
      zone: 'Zone A',
      shelf: 'A01',
      level: 'Tầng 1',
    ));

    await repo.registerOrUpdatePallet(
      palletCode: 'PAL-001',
      rfidEpc: 'E28011700000020ECA501234',
      locationId: 'LOC-A01-01',
    );

    await repo.addItem(Item(
      itemId: 'ITEM-AIRTAG-01',
      epc: 'E280119000000000000000AA',
      productId: 'PROD-AIRTAG-01',
      sku: 'SKU-AIRTAG',
      productName: 'Mặt Hàng Thử Nghiệm AirTag',
      serialNumber: 'SN-AIRTAG-999',
      status: ItemStatus.inStock,
      palletId: 'PAL-AIRTAG-01',
      locationId: 'LOC-A01-01',
    ));

    await repo.addItem(Item(
      itemId: 'ITEM-OTHER-02',
      epc: 'E280119000000000000000BB',
      productId: 'PROD-AIRTAG-01',
      sku: 'SKU-OTHER',
      productName: 'Mặt Hàng Khác Không Định Vị',
      serialNumber: 'SN-OTHER-888',
      status: ItemStatus.inStock,
    ));
  });

  tearDown(() async {
    uhf.stopInventory();
    uhf.disableScanning();
    await repo.clearAllData();
  });

  final testTheme = ThemeData(useMaterial3: false, splashFactory: NoSplash.splashFactory);

  testWidgets('1. DirectionArrowWidget: Hiển thị đúng cự ly từng cm và mũi tên chỉ hướng theo sóng RSSI', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // 1.1 Trường hợp cự ly gần (< 1m): RSSI = -36 dBm, tín hiệu tăng (+4.0 dBm) -> Mũi tên chỉ đúng hướng & hiển thị đơn vị cm
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const Scaffold(
          body: DirectionArrowWidget(
            rssi: -36.0,
            previousRssi: -40.0,
            isTracking: true,
            targetEpc: 'E280119000000000000000AA',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Xác nhận hiển thị số đo cự ly theo đơn vị cm (25 cm)
    expect(find.text('25 cm'), findsOneWidget);
    // Xác nhận mũi tên chỉ đúng hướng
    expect(find.byIcon(Icons.trending_up_rounded), findsWidgets);
    expect(find.textContaining('ĐÚNG HƯỚNG'), findsOneWidget);

    // 1.2 Trường hợp lia súng lệch hướng: previousRssi = -36.0, rssi = -42.0 (-6.0 dBm) -> Biểu tượng cảnh báo lệch hướng
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const Scaffold(
          body: DirectionArrowWidget(
            rssi: -42.0,
            previousRssi: -36.0,
            isTracking: true,
            targetEpc: 'E280119000000000000000AA',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('50 cm'), findsOneWidget);
    expect(find.byIcon(Icons.trending_down_rounded), findsWidgets);
    expect(find.textContaining('LỆCH HƯỚNG'), findsOneWidget);
  });

  testWidgets('2. RadarLocateScreen: Tìm kiếm theo mã SKU / Serial / EPC và hiển thị kết quả', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const RadarLocateScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Kiểm tra màn hình render đầy đủ thanh tìm kiếm và tiêu đề
    expect(find.text('🎯 TÌM KIẾM & ĐỊNH VỊ'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);

    // 2. Tìm kiếm theo SKU
    await tester.enterText(find.byType(TextField), 'SKU-AIRTAG');
    await tester.pumpAndSettle();

    expect(find.text('Mặt Hàng Thử Nghiệm AirTag'), findsOneWidget);
    expect(find.textContaining('SN-AIRTAG-999'), findsOneWidget);
    expect(find.text('ĐỊNH VỊ'), findsOneWidget);

    // 3. Bấm nút ĐỊNH VỊ để chuyển sang chế độ Precision Finding
    await tester.tap(find.text('ĐỊNH VỊ'));
    await tester.pumpAndSettle();

    // Xác nhận đã vào màn hình AirTag với DirectionArrowWidget
    expect(find.byType(DirectionArrowWidget), findsOneWidget);
    expect(find.text('ĐỔI MÃ'), findsOneWidget);
    expect(find.text('BẬT QUÉT ĐỊNH VỊ (BÓP CÒ SÚNG)'), findsOneWidget);

    // 4. Bấm bắt đầu quét định vị
    await tester.tap(find.text('BẬT QUÉT ĐỊNH VỊ (BÓP CÒ SÚNG)'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('DỪNG QUÉT ĐỊNH VỊ'), findsOneWidget);

    // Dừng quét
    await tester.tap(find.text('DỪNG QUÉT ĐỊNH VỊ'));
    await tester.pumpAndSettle();
  });

  testWidgets('3. PdaHomeScreen: Có phím tắt Tìm & Định vị và mở màn hình RadarLocateScreen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const PdaHomeScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Kiểm tra tile 'Tìm & Định vị' xuất hiện trên lưới trang chủ
    final tileFinder = find.text('Tìm & Định vị');
    expect(tileFinder, findsOneWidget);

    // Chạm vào tile (cuộn nếu màn hình nhỏ)
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -200));
    await tester.pumpAndSettle();
    await tester.tap(tileFinder);
    await tester.pumpAndSettle();

    // Xác nhận đã chuyển sang RadarLocateScreen
    expect(find.byType(RadarLocateScreen), findsOneWidget);
  });

  testWidgets('4. PdaWarehouseManagementScreen: Tab Sản Phẩm hiển thị nút Định vị (AirTag)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const PdaWarehouseManagementScreen(initialTabIndex: 3), // Tab 3: Sản phẩm
      ),
    );
    await tester.pumpAndSettle();

    // Xác nhận có nút Định vị (AirTag) trên thẻ sản phẩm
    expect(find.text('Định vị (AirTag)'), findsWidgets);

    // Bấm vào nút Định vị (AirTag) của sản phẩm đầu tiên
    await tester.tap(find.text('Định vị (AirTag)').first);
    await tester.pumpAndSettle();

    // Xác nhận mở màn hình RadarLocateScreen với mục tiêu đã nạp sẵn
    expect(find.byType(RadarLocateScreen), findsOneWidget);
    expect(find.byType(DirectionArrowWidget), findsOneWidget);
  });
}
