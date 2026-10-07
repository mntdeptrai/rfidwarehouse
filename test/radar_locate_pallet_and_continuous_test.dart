import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/screens/radar_locate_screen.dart';
import 'package:uhf/widgets/direction_arrow_widget.dart';
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

    await repo.addProduct(const Product(
      productId: 'PROD-PAL-TEST',
      sku: 'SKU-PAL-01',
      productName: 'Hàng Trên Pallet Tìm Kiếm',
      unit: 'Thùng',
      category: 'Gia dụng',
    ));

    await repo.addLocation(Location(
      locationId: 'LOC-PAL-01',
      locationCode: 'KỆ-B02',
      zone: 'Zone B',
      shelf: 'B02',
      level: 'Tầng 2',
    ));

    await repo.registerOrUpdatePallet(
      palletCode: 'PALLET-AIRTAG-99',
      palletName: 'Pallet Hàng Xuất Khẩu',
      rfidEpc: 'E28011700000020ECA509999',
      locationId: 'LOC-PAL-01',
    );

    await repo.addItem(Item(
      itemId: 'ITEM-ON-PALLET-01',
      epc: 'E280119000000000000000C1',
      productId: 'PROD-PAL-TEST',
      sku: 'SKU-PAL-01',
      productName: 'Hàng Trên Pallet Tìm Kiếm',
      serialNumber: 'SN-PAL-001',
      status: ItemStatus.inStock,
      palletId: 'PALLET-AIRTAG-99',
      locationId: 'LOC-PAL-01',
    ));
  });

  tearDown(() async {
    uhf.stopInventory();
    uhf.disableScanning();
    await repo.clearAllData();
  });

  final testTheme = ThemeData(useMaterial3: false, splashFactory: NoSplash.splashFactory);

  testWidgets('1. Tìm kiếm Pallet và định vị Pallet bằng sóng RFID', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const RadarLocateScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Tìm kiếm theo mã Pallet
    await tester.enterText(find.byType(TextField), 'PALLET-AIRTAG-99');
    await tester.pumpAndSettle();

    expect(find.text('Pallet Hàng Xuất Khẩu'), findsOneWidget);
    expect(find.text('ĐỊNH VỊ'), findsWidgets);

    // 2. Chạm vào nút ĐỊNH VỊ của Pallet
    await tester.tap(find.text('ĐỊNH VỊ').first);
    await tester.pumpAndSettle();

    // Xác nhận đã vào màn hình DirectionArrowWidget với mục tiêu Pallet
    expect(find.byType(DirectionArrowWidget), findsOneWidget);
    expect(find.text('ĐỔI MÃ'), findsOneWidget);
    expect(find.text('BẬT QUÉT ĐỊNH VỊ (BÓP CÒ SÚNG)'), findsOneWidget);

    // 3. Bắt đầu quét định vị Pallet
    await tester.tap(find.text('BẬT QUÉT ĐỊNH VỊ (BÓP CÒ SÚNG)'));
    await tester.pump(const Duration(milliseconds: 100));

    // 4. Mô phỏng đọc chip của chính Pallet hoặc của hàng hóa trên Pallet đó
    uhf.simulateTag('E28011700000020ECA509999');
    await tester.pump(const Duration(milliseconds: 150));

    // Thẻ của pallet được nhận dạng liên tục
    expect(find.text('DỪNG QUÉT ĐỊNH VỊ'), findsOneWidget);

    // 5. Mô phỏng tiếp nhận thẻ sản phẩm nằm trên Pallet đó (cũng tính là vị trí Pallet)
    uhf.simulateTag('E280119000000000000000C1');
    await tester.pump(const Duration(milliseconds: 150));

    // Dừng quét
    await tester.tap(find.text('DỪNG QUÉT ĐỊNH VỊ'));
    await tester.pumpAndSettle();
    expect(find.text('BẬT QUÉT ĐỊNH VỊ (BÓP CÒ SÚNG)'), findsOneWidget);
  });

  testWidgets('2. Tab Quản lý Pallet (PDA): Có nút Định vị mở trực tiếp Radar định vị Pallet', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const PdaWarehouseManagementScreen(initialTabIndex: 0),
      ),
    );
    await tester.pumpAndSettle();

    // Kiểm tra có nút Định vị trên thẻ Pallet
    final locateButton = find.widgetWithText(OutlinedButton, 'Định vị');
    expect(locateButton, findsOneWidget);

    // Bấm vào nút Định vị
    await tester.tap(locateButton);
    await tester.pumpAndSettle();

    // Mở ra màn hình RadarLocateScreen với mục tiêu là Pallet được chọn sẵn
    expect(find.byType(RadarLocateScreen), findsOneWidget);
    expect(find.byType(DirectionArrowWidget), findsOneWidget);
    expect(find.text('Pallet Hàng Xuất Khẩu'), findsOneWidget);
  });

  testWidgets('3. AirTag Precision Finding: Cập nhật cự ly và trạng thái liên tục khi sóng tăng/giảm', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // Cự ly cực gần (< 35cm, -32 dBm) kích hoạt chế độ "NGAY TẠI ĐÂY"
    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const Scaffold(
          body: DirectionArrowWidget(
            rssi: -32.0,
            previousRssi: -40.0,
            isTracking: true,
            targetEpc: 'E28011700000020ECA509999',
            isPallet: true,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // Hiển thị vòng tròn Apple AirTag NGAY TẠI ĐÂY
    expect(find.text('NGAY TẠI ĐÂY'), findsOneWidget);
    expect(find.text('16 cm'), findsOneWidget);
    expect(find.textContaining('ĐÃ TÌM THẤY'), findsWidgets);
  });
}
