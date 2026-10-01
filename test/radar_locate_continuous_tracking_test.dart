import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/screens/radar_locate_screen.dart';
import 'package:uhf/widgets/direction_arrow_widget.dart';

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
      productId: 'PROD-CONTINUOUS-01',
      sku: 'SKU-CONT-01',
      productName: 'Mặt Hàng Dò Sóng Liên Tục',
      unit: 'Cuộn',
      category: 'Linh kiện',
    ));

    await repo.addItem(Item(
      itemId: 'ITEM-CONT-01',
      epc: '20260401000000000001',
      productId: 'PROD-CONTINUOUS-01',
      sku: 'SKU-CONT-01',
      productName: 'Mặt Hàng Dò Sóng Liên Tục',
      serialNumber: 'SN-CONT-001',
      status: ItemStatus.inStock,
    ));
  });

  tearDown(() async {
    uhf.stopInventory();
    uhf.disableScanning();
    await repo.clearAllData();
  });

  final testTheme = ThemeData(useMaterial3: false, splashFactory: NoSplash.splashFactory);

  testWidgets('RadarLocateScreen: Cập nhật hướng và cự ly liên tục không cần bóp cò lại', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const RadarLocateScreen(initialEpc: '20260401000000000001'),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Kiểm tra đã nạp mục tiêu trực tiếp và hiển thị Radar
    expect(find.byType(DirectionArrowWidget), findsOneWidget);
    expect(find.text('Mặt Hàng Dò Sóng Liên Tục'), findsOneWidget);

    // 2. Bắt đầu dò sóng
    await tester.tap(find.text('BẬT QUÉT ĐỊNH VỊ (BÓP CÒ SÚNG)'));
    await tester.pump(const Duration(milliseconds: 100));

    // 3. Mô phỏng gói tin đầu tiên: RSSI = -60 dBm (khoảng cách xa ~ 4.0m)
    uhf.simulateTag('20260401000000000001'); // UhfService simulateTag gửi RSSI -50 mặc định
    await tester.pump(const Duration(milliseconds: 150));

    // 4. Mô phỏng các gói tin liên tiếp cùng 1 mã EPC đến dồn dập (Realtime Stream)
    // Khi người dùng tiến lại gần: các gói tin liên tiếp vẫn được tiếp nhận mà không bị filter chặn
    uhf.simulateTag('20260401000000000001');
    await tester.pump(const Duration(milliseconds: 150));

    uhf.simulateTag('20260401000000000001');
    await tester.pump(const Duration(milliseconds: 150));

    // Hệ thống vẫn đang trong trạng thái quét liên tục (isTracking = true)
    expect(find.text('DỪNG QUÉT ĐỊNH VỊ'), findsOneWidget);

    // 5. Chờ 800ms không có gói tin nào: cơ chế Signal Decay kích hoạt tự động cảnh báo lệch hướng
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.byType(DirectionArrowWidget), findsOneWidget);

    // 6. Dừng quét
    await tester.tap(find.text('DỪNG QUÉT ĐỊNH VỊ'));
    await tester.pumpAndSettle();
    expect(find.text('BẬT QUÉT ĐỊNH VỊ (BÓP CÒ SÚNG)'), findsOneWidget);
  });

  testWidgets('RadarLocateScreen: Kích hoạt bằng bóp cò và cảnh báo khi quét thấy chip khác', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 950);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const RadarLocateScreen(initialEpc: '20260401000000000001'),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Kiểm tra scanMode đã được cưỡng chế là RFID
    expect(uhf.scanMode, equals(PdaScanMode.rfid));

    // 2. Bóp cò súng PDA (isPressed = true, sau đó nhả ra isPressed = false trong chế độ toggle)
    uhf.simulateTrigger(true);
    await tester.pump(const Duration(milliseconds: 50));
    uhf.simulateTrigger(false);
    await tester.pump(const Duration(milliseconds: 100));

    // Hệ thống vẫn giữ trạng thái DÒ LIÊN TỤC (Hands-free continuous lock)
    expect(find.text('DỪNG QUÉT ĐỊNH VỊ'), findsOneWidget);

    // 3. Quét một chip KHÁC mã mục tiêu (ví dụ để nhầm chip khác sát máy)
    uhf.simulateTag('DIFFERENT_EPC_NEARBY_999');
    await tester.pump(const Duration(milliseconds: 100));

    // Kiểm tra hiển thị banner chip khác gần máy
    expect(find.textContaining('ĐANG ĐỌC ĐƯỢC CHIP KHÁC GẦN MÁY:'), findsOneWidget);
    expect(find.textContaining('DIFFERENT_EPC_NEARBY_999'), findsOneWidget);
    expect(find.text('ĐỊNH VỊ THEO MÃ EPC NÀY'), findsOneWidget);

    // 4. Bấm chuyển sang định vị mã này
    await tester.tap(find.text('ĐỊNH VỊ THEO MÃ EPC NÀY'));
    await tester.pump(const Duration(milliseconds: 100));

    // Mục tiêu mới được chọn và hiển thị ngay
    expect(find.text('Mã EPC: DIFFERENT_EPC_NEARBY_999'), findsWidgets);
  });
}
