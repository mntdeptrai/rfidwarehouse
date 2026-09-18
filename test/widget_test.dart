import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/main.dart';
import 'package:uhf/screens/desktop/desktop_inventory_view.dart';
import 'package:uhf/screens/desktop/desktop_goods_receive_view.dart';
import 'package:uhf/screens/desktop/desktop_goods_delivery_view.dart';
import 'package:uhf/screens/desktop/desktop_lookup_view.dart';
import 'package:uhf/screens/desktop/desktop_uhf_studio_view.dart';
import 'package:uhf/screens/desktop/desktop_main_layout.dart';
import 'package:uhf/screens/storage_screen.dart';
import 'package:uhf/screens/pda/pda_home_screen.dart';
import 'package:uhf/screens/inbound_screen.dart';
import 'package:uhf/screens/desktop/desktop_warehouse_management_view.dart';
import 'package:uhf/screens/outbound_screen.dart';
import 'package:uhf/screens/pda/pda_putaway_screen.dart';
import 'package:uhf/screens/pda/pda_warehouse_management_screen.dart';
import 'package:uhf/screens/pda/pda_drawer.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/models/tag_info.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/database_service.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/screens/desktop/desktop_location_management_view.dart';
import 'package:uhf/screens/desktop/desktop_report_view.dart';
import 'package:uhf/screens/splash/splash_screen.dart';
import 'package:uhf/models/inventory_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RFID WMS App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RfidWmsApp());
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.byType(RfidWmsApp), findsOneWidget);
  });

  testWidgets('SplashScreen renders Nhat Minh logo and navigates smoothly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(
          duration: Duration(milliseconds: 200),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.text('BỎ QUA'), findsNothing);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  });

  testWidgets('SplashScreen tap on screen transitions immediately', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SplashScreen(
          duration: Duration(seconds: 5),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(Image), findsOneWidget);
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
  });

  testWidgets('DesktopInventoryView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopInventoryView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopInventoryView), findsOneWidget);
  });

  testWidgets('DesktopGoodsReceiveView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopGoodsReceiveView(isActive: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopGoodsReceiveView), findsOneWidget);
  });

  testWidgets('DesktopGoodsDeliveryView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
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
    expect(find.byType(DesktopGoodsDeliveryView), findsOneWidget);
  });

  testWidgets('StorageScreen renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StorageScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(StorageScreen), findsOneWidget);
  });

  testWidgets('DesktopLookupView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopLookupView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopLookupView), findsOneWidget);
  });

  testWidgets('DesktopUhfStudioView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopUhfStudioView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopUhfStudioView), findsOneWidget);
  });

  testWidgets('DesktopWarehouseManagementView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopWarehouseManagementView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopWarehouseManagementView), findsOneWidget);
  });

  testWidgets('DesktopMainLayout renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: DesktopMainLayout(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopMainLayout), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('PdaHomeScreen renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: PdaHomeScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PdaHomeScreen), findsOneWidget);
  });

  testWidgets('PdaWarehouseManagementScreen renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: PdaWarehouseManagementScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PdaWarehouseManagementScreen), findsOneWidget);
  });

  testWidgets('InboundScreen renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: InboundScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(InboundScreen), findsOneWidget);
  });

  testWidgets('OutboundScreen renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: OutboundScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(OutboundScreen), findsOneWidget);
  });

  testWidgets('PdaPutawayScreen renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: PdaPutawayScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PdaPutawayScreen), findsOneWidget);
  });

  testWidgets('PdaPutawayScreen 2-box flow: Item info box and location selection with barcode scan', (WidgetTester tester) async {
    final repo = WarehouseRepository();
    await repo.ensureDefault10Locations();

    // Thêm sản phẩm chờ cất
    await repo.addItem(Item(
      itemId: 'ITEM-PUTAWAY-01',
      productId: 'PROD-01',
      sku: 'SKU-PUTAWAY-01',
      productName: 'Hàng Chờ Cất Kệ',
      serialNumber: 'SN-PA-01',
      epc: 'E280119100000000PA00001',
      status: ItemStatus.waitingPutaway,
      palletId: 'PAL-TEST-99',
    ));

    await tester.pumpWidget(
      const MaterialApp(
        home: PdaPutawayScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Ô 1: Hiện thanh chọn pallet
    expect(find.textContaining('PALLET ĐÃ CHỌN: PAL-TEST-99'), findsOneWidget);
    expect(find.textContaining('PAL-TEST-99 (1 sản phẩm)'), findsWidgets);
    expect(find.textContaining('Hàng Chờ Cất Kệ'), findsNothing);

    // Ô 2: Dòng 1 chọn vị trí kệ
    expect(find.textContaining('CHỌN VỊ TRÍ KỆ'), findsOneWidget);

    // Chọn vị trí bằng initialLocationId hoặc giả lập chọn vị trí
    await tester.pumpWidget(
      const MaterialApp(
        home: PdaPutawayScreen(initialLocationId: 'A-01'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Sau khi chọn vị trí: Dòng 2 quét barcode xuất hiện, nút thừa BẬT QUÉT BARCODE đã được xóa bỏ
    expect(find.textContaining('DÒNG 2: QUÉT BARCODE ĐỂ CẤT HÀNG'), findsOneWidget);
    expect(find.textContaining('BẬT QUÉT BARCODE (CÒ PDA)'), findsNothing);
    expect(find.textContaining('Bóp cò PDA hoặc nhập mã quét...'), findsOneWidget);
  });

  testWidgets('PdaPutawayScreen supports pallet dropdown selection and barcode scanning', (WidgetTester tester) async {
    final repo = WarehouseRepository();
    await repo.ensureDefault10Locations();

    await repo.addItem(Item(
      itemId: 'ITEM-PUTAWAY-BC-01',
      productId: 'PROD-01',
      sku: 'SKU-PUTAWAY-01',
      productName: 'SP Xe 1',
      serialNumber: 'SN-BC-01',
      epc: 'E280119100000000BC00001',
      status: ItemStatus.waitingPutaway,
      palletId: 'PAL-BARCODE-01',
    ));
    await repo.addItem(Item(
      itemId: 'ITEM-PUTAWAY-BC-02',
      productId: 'PROD-02',
      sku: 'SKU-PUTAWAY-02',
      productName: 'SP Xe 2',
      serialNumber: 'SN-BC-02',
      epc: 'E280119100000000BC00002',
      status: ItemStatus.waitingPutaway,
      palletId: 'PAL-BARCODE-02',
    ));

    await tester.pumpWidget(
      const MaterialApp(
        home: PdaPutawayScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Hiển thị thanh chọn pallet với số lượng xe
    expect(find.textContaining('CHỌN PALLET CẦN CẤT'), findsOneWidget);
    expect(find.textContaining('Bấm để chọn Pallet / Xe hàng'), findsOneWidget);

    // Không còn nút quét thừa thãi trong ô 1
    expect(find.textContaining('BẬT TIA QUÉT BARCODE XE (CÒ PDA)'), findsNothing);

    // Giả lập quét barcode tay cầm PDA cho PAL-BARCODE-02
    UhfService().simulateBarcode('PAL-BARCODE-02');
    await tester.pump(const Duration(milliseconds: 500));

    // Xe 2 được tự động chọn sau khi quét barcode
    expect(find.textContaining('PALLET ĐÃ CHỌN: PAL-BARCODE-02'), findsOneWidget);
  });

  testWidgets('DesktopGoodsReceiveView shows 3 metric boxes, 9 columns, and right-aligned controls without CHƯA ĐỌC ĐỦ', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final repo = WarehouseRepository();
    // Thêm hàng chờ qua cổng
    await repo.addItem(Item(
      itemId: 'ITEM-GATE-IN-01',
      productId: 'PROD-01',
      sku: 'SKU-GATE-01',
      productName: 'Sản phẩm Nhập Cổng',
      serialNumber: 'SN-G-01',
      epc: 'E280119100000000G0000001',
      status: ItemStatus.pendingInbound,
      cartonCode: 'BOX-001',
      palletId: 'PAL-001',
    ));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopGoodsReceiveView(isActive: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // 3 ô chỉ số: ĐÃ QUÉT, THIẾU, LẠ đều nhau và mang 3 màu Xanh - Vàng - Đỏ
    expect(find.text('ĐÃ QUÉT'), findsOneWidget);
    expect(find.text('THIẾU'), findsOneWidget);
    expect(find.text('LẠ'), findsOneWidget);

    final daQuetText = tester.widget<Text>(find.text('ĐÃ QUÉT'));
    final thieuText = tester.widget<Text>(find.text('THIẾU'));
    final laText = tester.widget<Text>(find.text('LẠ'));
    expect(daQuetText.style?.color, const Color(0xFF10B981)); // Xanh
    expect(thieuText.style?.color, const Color(0xFFF59E0B));  // Vàng
    expect(laText.style?.color, const Color(0xFFEF4444));     // Đỏ

    // 9 Cột bảng thông tin
    expect(find.text('STT'), findsOneWidget);
    expect(find.text('MÃ SKU'), findsOneWidget);
    expect(find.text('MÃ THÙNG'), findsOneWidget);
    expect(find.text('MÃ PALLET'), findsOneWidget);
    expect(find.text('NHÀ CUNG CẤP'), findsOneWidget);
    expect(find.text('TÊN SẢN PHẨM'), findsOneWidget);
    expect(find.text('EPC PALLET'), findsOneWidget);
    expect(find.text('EPC HÀNG'), findsOneWidget);
    expect(find.text('ATEN ĐÃ QUÉT'), findsOneWidget);

    // Tiến độ đối soát qua cổng hiển thị định dạng (scanned / expected chip) giống xuất kho
    expect(find.textContaining('TIẾN ĐỘ ĐỐI SOÁT QUA CỔNG: (0 / 1 chip)'), findsOneWidget);

    // Các nút quét được dạt sang phải, nút CHƯA ĐỌC ĐỦ và ô ĐÃ LỌC/bật lọc bị loại bỏ hoàn toàn
    expect(find.textContaining('CHƯA ĐỌC ĐỦ'), findsNothing);
    expect(find.text('ĐÃ LỌC'), findsNothing);
    expect(find.textContaining('Lọc chip đã qua'), findsNothing);
    expect(find.textContaining('Làm Mới Quét'), findsOneWidget);
    expect(find.textContaining('BẮT ĐẦU QUÉT'), findsOneWidget);
  });

  testWidgets('DesktopGoodsReceiveView displays unified full list across multiple pallets without splitting', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final repo = WarehouseRepository();
    final oldPending = repo.items.where((it) => it.status == ItemStatus.pendingInbound).map((it) => it.epc).toList();
    await repo.deleteItemsByEpcs(oldPending);
    // Tạo 2 pallet khác nhau với 5 món và 7 món (tổng 12 món)
    for (int i = 1; i <= 5; i++) {
      await repo.addItem(Item(
        itemId: 'ITEM-TEST-P1-$i',
        productId: 'SKU-001',
        sku: 'SKU-001',
        productName: 'Sản phẩm P1',
        serialNumber: 'SN-P1-$i',
        epc: 'E280119100000000P10000$i',
        status: ItemStatus.pendingInbound,
        orderNo: 'INBOUND-MULTI-01',
        palletId: 'PAL-945321545',
      ));
    }
    for (int i = 1; i <= 7; i++) {
      await repo.addItem(Item(
        itemId: 'ITEM-TEST-P2-$i',
        productId: 'SKU-002',
        sku: 'SKU-002',
        productName: 'Sản phẩm P2',
        serialNumber: 'SN-P2-$i',
        epc: 'E280119100000000P20000$i',
        status: ItemStatus.pendingInbound,
        orderNo: 'INBOUND-MULTI-01',
        palletId: 'PAL-945321988',
      ));
    }

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopGoodsReceiveView(isActive: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Hiển thị đầy đủ tổng 12 chip trong 1 danh sách, không chia thành 2 lượt
    expect(find.textContaining('TIẾN ĐỘ ĐỐI SOÁT QUA CỔNG: (0 / 12 chip)'), findsOneWidget);
    expect(find.text('12'), findsWidgets); // THIẾU 12
    expect(find.text('PAL-945321545'), findsWidgets);
    expect(find.text('PAL-945321988'), findsWidgets);
  });

  testWidgets('DesktopGoodsReceiveView preserves full list when gate is complete and locks scan', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final repo = WarehouseRepository();
    final oldPending = repo.items.where((it) => it.status == ItemStatus.pendingInbound).map((it) => it.epc).toList();
    await repo.deleteItemsByEpcs(oldPending);

    // Thêm 2 sản phẩm chờ nhập
    final epc1 = 'E280119100000000AUTO001';
    final epc2 = 'E280119100000000AUTO002';
    await repo.addItem(Item(
      itemId: 'ITEM-TEST-AUTO-1',
      productId: 'SKU-A1',
      sku: 'SKU-A1',
      productName: 'Sản phẩm Test 1',
      serialNumber: 'SN-A1',
      epc: epc1,
      status: ItemStatus.pendingInbound,
      orderNo: 'INBOUND-AUTO-01',
      palletId: 'PAL-999',
    ));
    await repo.addItem(Item(
      itemId: 'ITEM-TEST-AUTO-2',
      productId: 'SKU-A2',
      sku: 'SKU-A2',
      productName: 'Sản phẩm Test 2',
      serialNumber: 'SN-A2',
      epc: epc2,
      status: ItemStatus.pendingInbound,
      orderNo: 'INBOUND-AUTO-01',
      palletId: 'PAL-999',
    ));

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const Scaffold(
          body: DesktopGoodsReceiveView(isActive: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));


    // Ban đầu: 0 / 2 chip
    expect(find.textContaining('TIẾN ĐỘ ĐỐI SOÁT QUA CỔNG: (0 / 2 chip)'), findsOneWidget);
    expect(find.text('SKU-A1'), findsOneWidget);
    expect(find.text('SKU-A2'), findsOneWidget);

    // Bấm bắt đầu quét
    await tester.tap(find.textContaining('BẮT ĐẦU QUÉT'));
    await tester.pump();

    // Mô phỏng nhận 2 chip từ đầu đọc
    UhfService().simulateTag(epc1);
    UhfService().simulateTag(epc2);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));

    // Sau khi quét đủ: danh sách VẪN HIỂN THỊ ĐẦY ĐỦ, không bị biến mất!
    expect(find.text('SKU-A1'), findsOneWidget);
    expect(find.text('SKU-A2'), findsOneWidget);
    expect(find.textContaining('ĐÃ ĐỐI SOÁT ĐỦ (KHOÁ QUÉT)'), findsOneWidget);

    // Xả hết timer của đèn tháp (4s) để tránh lỗi pending timer
    await tester.pump(const Duration(seconds: 5));
  });

  testWidgets('DesktopGoodsReceiveView shows functional DỪNG QUÉT button while scanning and never locks idle screen', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final repo = WarehouseRepository();
    final oldPending = repo.items.where((it) => it.status == ItemStatus.pendingInbound).map((it) => it.epc).toList();
    await repo.deleteItemsByEpcs(oldPending);

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const Scaffold(
          body: DesktopGoodsReceiveView(isActive: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // 1. Màn hình chờ rỗng (idle): Phải có nút BẮT ĐẦU QUÉT, KHÔNG ĐƯỢC khoá nút
    expect(find.textContaining('CỔNG RFID ĐANG SẴN SÀNG TIẾP NHẬN HÀNG'), findsOneWidget);
    expect(find.textContaining('BẮT ĐẦU QUÉT'), findsOneWidget);
    expect(find.textContaining('ĐÃ ĐỐI SOÁT ĐỦ (KHOÁ QUÉT)'), findsNothing);

    // 2. Bấm BẮT ĐẦU QUÉT -> Chuyển thành DỪNG QUÉT màu đỏ
    await tester.tap(find.textContaining('BẮT ĐẦU QUÉT'));
    await tester.pump();

    expect(find.textContaining('DỪNG QUÉT'), findsOneWidget);
    expect(find.textContaining('BẮT ĐẦU QUÉT'), findsNothing);

    // 3. Bấm DỪNG QUÉT -> Dừng quét và chuyển lại BẮT ĐẦU QUÉT
    await tester.tap(find.textContaining('DỪNG QUÉT'));
    await tester.pump();

    expect(find.textContaining('BẮT ĐẦU QUÉT'), findsOneWidget);
    expect(find.textContaining('DỪNG QUÉT'), findsNothing);
  });

  testWidgets('DesktopGoodsDeliveryView matches Inbound style: cyan dropdown XUẤT HÀNG, idle gate monitor, and history toggle', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const Scaffold(
          body: DesktopGoodsDeliveryView(isActive: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));


    // Nút XUẤT HÀNG dạng dropdown màu cyan trên header & nút LÀM MỚI
    expect(find.text('XUẤT HÀNG'), findsOneWidget);
    expect(find.text('LÀM MỚI'), findsOneWidget);

    // Nút LỊCH SỬ XUẤT KHO đã được loại bỏ hoàn toàn khỏi giao diện Cổng xuất kho
    expect(find.text('LỊCH SỬ XUẤT KHO'), findsNothing);

    // Màn hình chờ tiếp nhận hàng xuất khi chưa nạp file
    expect(find.textContaining('CỔNG RFID ĐANG SẴN SÀNG TIẾP NHẬN HÀNG XUẤT'), findsOneWidget);

    // Không còn nút đỏ báo lỗi sai sót
    expect(find.text('BÁO LỖI SAI SÓT'), findsNothing);
  });

  testWidgets('InboundScreen (PDA) displays 3 metric boxes (ĐÃ QUÉT, THIẾU, LẠ), compact buttons, and removes search bar', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: InboundScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // 1. Header có 3 nút thu gọn: NHẬP HÀNG, LÀM MỚI
    expect(find.text('NHẬP HÀNG'), findsOneWidget);
    expect(find.text('LÀM MỚI'), findsOneWidget);

    // 2. Không còn ô tìm kiếm
    expect(find.byType(TextField), findsNothing);

    // 3. Trước khi nạp file sẽ không hiện các ô quét ĐÃ QUÉT, THIẾU, LẠ
    expect(find.text('ĐÃ QUÉT'), findsNothing);
    expect(find.text('THIẾU'), findsNothing);
    expect(find.text('LẠ'), findsNothing);
    expect(find.text('Chưa có dữ liệu hàng nhập'), findsOneWidget);
    expect(find.text('FILE THÙNG (.XLSX)'), findsNothing);

    // 4. Không có cột ATEN ĐÃ QUÉT trên tay cầm PDA
    expect(find.text('ATEN ĐÃ QUÉT'), findsNothing);
  });

  testWidgets('OutboundScreen (PDA) follows Desktop flow: idle gate monitor, removes search, FIFO, and old bottom bar', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: OutboundScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // 1. Header có nút XUẤT HÀNG (cyan) và LÀM MỚI
    expect(find.text('XUẤT HÀNG'), findsOneWidget);
    expect(find.text('LÀM MỚI'), findsOneWidget);

    // 2. Màn hình chờ tiếp nhận xuất kho (giống Desktop)
    expect(find.textContaining('CỔNG RFID ĐANG SẴN SÀNG TIẾP NHẬN HÀNG XUẤT'), findsOneWidget);

    // 3. Đã loại bỏ hoàn toàn ô tìm kiếm
    expect(find.byType(TextField), findsNothing);

    // 4. Đã loại bỏ hoàn toàn chữ/gợi ý FIFO
    expect(find.textContaining('FIFO'), findsNothing);

    // 5. Đã loại bỏ 2 nút nạp file ở giữa
    expect(find.text('NẠP FILE EXCEL'), findsNothing);
    expect(find.text('CHỌN ĐƠN CÓ SẴN'), findsNothing);

    // 6. Đã loại bỏ thanh bottom bar cũ 'ĐÃ CHỌN: 0 / 0 SP' và 'TIẾP TỤC: QUÉT TAY CẦM'
    expect(find.textContaining('ĐÃ CHỌN:'), findsNothing);
    expect(find.textContaining('TIẾP TỤC: QUÉT TAY CẦM'), findsNothing);

    // 7. Không có cột ATEN ĐÃ QUÉT trên tay cầm PDA
    expect(find.text('ATEN ĐÃ QUÉT'), findsNothing);

    // 8. Đã loại bỏ 'BÓP CÒ ĐỂ QUÉT' và dòng đỏ chặn nút làm mới quét
    expect(find.text('BÓP CÒ ĐỂ QUÉT'), findsNothing);
    expect(find.textContaining('VUI LÒNG LOẠI BỎ'), findsNothing);
  });

  testWidgets('InboundScreen preserves 100% list and locks scanning when batch is completed', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // Set InboundActiveSession to simulate completed batch
    InboundActiveSession.receiptCartons = [
      {
        'code': 'BOX01',
        'cartonBox': 'BOX01',
        'palletCode': 'PAL01',
        'sku': 'SKU01',
        'productName': 'Item 1',
        'serial': 'EPC0000000000001',
        'serials': ['EPC0000000000001'],
      }
    ];
    InboundActiveSession.selectedEpcs = {'EPC0000000000001'};
    InboundActiveSession.scannedTags = {
      'EPC0000000000001': TagInfo(epc: 'EPC0000000000001', rssi: '-50'),
    };
    InboundActiveSession.isBatchCompleted = true;

    await tester.pumpWidget(
      const MaterialApp(
        home: InboundScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Must show 100% full: ĐÃ QUÉT 1, THIẾU 0
    expect(find.text('ĐÃ QUÉT'), findsOneWidget);
    expect(find.text('THIẾU'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(find.text('0'), findsNWidgets(2));

    // Scan button is locked / shows "Đã Quét Đủ 100%"
    expect(find.text('Đã Quét Đủ 100%'), findsOneWidget);

    // Putaway button is visible
    expect(find.text('📦 CẤT HÀNG VÀO KỆ'), findsOneWidget);

    // Clean up session
    InboundActiveSession.clear();
  });

  testWidgets('DesktopGoodsReceiveView displays pending orders list with XÓA ĐƠN and transitions on CHỌN ĐỐI SOÁT', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final repo = WarehouseRepository();
    final testOrdNo = 'PO-TEST-ORDER-VIEW';
    await repo.wipeAllPendingInboundOrdersAndItems();

    await repo.addInboundOrder(
      InboundOrder(
        inboundOrderId: testOrdNo,
        orderNo: testOrdNo,
        sourceSupplier: 'Nhà cung cấp Kiểm Thử',
        status: InboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: 'SKU-TEST-01',
            sku: 'SKU-TEST-01',
            productName: 'Sản phẩm Test',
            requiredQty: 2,
          ),
        ],
      ),
      autoGenerateEpcs: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const Scaffold(
          body: DesktopGoodsReceiveView(isActive: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Hiển thị danh sách đơn hàng chờ qua cổng kèm nút XÓA ĐƠN & CHỌN ĐỐI SOÁT
    expect(find.textContaining('DANH SÁCH ĐƠN HÀNG CHỜ QUA CỔNG'), findsOneWidget);
    expect(find.text(testOrdNo), findsOneWidget);
    expect(find.text('XÓA ĐƠN'), findsOneWidget);
    expect(find.text('CHỌN ĐỐI SOÁT'), findsOneWidget);

    // Bấm CHỌN ĐỐI SOÁT -> chuyển sang màn hình quét đối soát có nút quay lại & nút XÓA ĐƠN NÀY
    await tester.tap(find.text('CHỌN ĐỐI SOÁT'));
    await tester.pumpAndSettle();

    expect(find.text('DANH SÁCH ĐƠN'), findsOneWidget);
    expect(find.text('XÓA ĐƠN NÀY'), findsOneWidget);
    expect(find.textContaining('ĐANG ĐỐI SOÁT ĐƠN: $testOrdNo'), findsOneWidget);

    // Bấm DANH SÁCH ĐƠN -> quay lại danh sách
    await tester.tap(find.text('DANH SÁCH ĐƠN'));
    await tester.pumpAndSettle();

    expect(find.textContaining('DANH SÁCH ĐƠN HÀNG CHỜ QUA CỔNG'), findsOneWidget);

    // Dọn dẹp
    await repo.wipeAllPendingInboundOrdersAndItems();
  });

  testWidgets('InboundScreen (PDA) displays delete icon on pending order cards', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    InboundActiveSession.clear();
    final repo = WarehouseRepository();
    final pdaOrdNo = 'PO-PDA-TEST-DELETE';
    await repo.wipeAllPendingInboundOrdersAndItems();

    await repo.addInboundOrder(
      InboundOrder(
        inboundOrderId: pdaOrdNo,
        orderNo: pdaOrdNo,
        sourceSupplier: 'Nhà cung cấp PDA Test',
        status: InboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: 'SKU-PDA-01',
            sku: 'SKU-PDA-01',
            productName: 'Sản phẩm PDA',
            requiredQty: 5,
          ),
        ],
      ),
      autoGenerateEpcs: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const InboundScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text(pdaOrdNo), findsOneWidget);
    expect(find.text('CHỌN'), findsOneWidget);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);

    // Dọn dẹp
    await repo.wipeAllPendingInboundOrdersAndItems();
    InboundActiveSession.clear();
  });

  testWidgets('PdaDrawer does not render the 4 removed items', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          drawer: PdaDrawer(),
          body: Center(child: Text('Home')),
        ),
      ),
    );

    // Mở drawer
    final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
    scaffoldState.openDrawer();
    await tester.pumpAndSettle();

    // Xác nhận 4 mục đã bị gỡ hoàn toàn khỏi drawer
    expect(find.text('Gộp 2 Pallet (PDA)'), findsNothing);
    expect(find.text('Quản Lý Kho (PDA)'), findsNothing);
    expect(find.text('Định Vị Thẻ RFID (Radar)'), findsNothing);
    expect(find.text('Tra Cứu Mã & Serial'), findsNothing);
  });

  testWidgets('PdaDrawer allows adjusting antenna power for PDA users', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          drawer: PdaDrawer(),
          body: Center(child: Text('Home')),
        ),
      ),
    );

    // Mở drawer
    final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
    scaffoldState.openDrawer();
    await tester.pumpAndSettle();

    // Tìm và bấm vào mục Công Suất Ăng-ten
    final antennaTile = find.text('Công Suất Ăng-ten (UHF)');
    expect(antennaTile, findsOneWidget);
    await tester.tap(antennaTile);
    await tester.pumpAndSettle();

    // Hộp thoại điều chỉnh công suất xuất hiện, KHÔNG bị chặn QUYỀN BỊ TỪ CHỐI
    expect(find.text('QUYỀN BỊ TỪ CHỐI'), findsNothing);
    expect(find.text('Mức phát RF:'), findsOneWidget);
    expect(find.text('LƯU & ÁP DỤNG'), findsOneWidget);

    // Bấm lưu
    await tester.tap(find.text('LƯU & ÁP DỤNG'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Đã cài đặt công suất phát ăng-ten'), findsOneWidget);
  });

  test('UhfService scan authorization gate: allows scanning only when enabled for authorized module', () async {
    final uhf = UhfService();

    // 1. Mặc định hoặc khi bị khóa: không được quét
    uhf.disableScanning();
    expect(uhf.isScanAllowed, isFalse);

    // 2. Kích hoạt quét cho Nhập kho
    uhf.enableScanning('nhap_kho');
    expect(uhf.isScanAllowed, isTrue);
    expect(uhf.activeScanModule, 'nhap_kho');

    // 3. Khóa lại
    uhf.disableScanning();
    expect(uhf.isScanAllowed, isFalse);
    expect(uhf.activeScanModule, '');

    // 4. Kích hoạt quét cho Xuất kho
    uhf.enableScanning('xuat_kho');
    expect(uhf.isScanAllowed, isTrue);

    // 5. Kích hoạt quét cho Kiểm kho
    uhf.enableScanning('kiem_kho');
    expect(uhf.isScanAllowed, isTrue);

    uhf.disableScanning();
    expect(uhf.isScanAllowed, isFalse);
  });

  testWidgets('PdaWarehouseManagementScreen disables scan on entry and pallet card shows delete button', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final uhf = UhfService();
    // Giả lập trạng thái scan đang bật trước khi vào Quản lý kho
    uhf.enableScanning('test');
    expect(uhf.isScanAllowed, isTrue);

    await tester.pumpWidget(
      const MaterialApp(
        home: PdaWarehouseManagementScreen(),
      ),
    );
    await tester.pump();

    // Khi vào Quản lý kho: scan bị tắt ngay lập tức
    expect(uhf.isScanAllowed, isFalse);

    // Thêm 1 pallet giả lập để kiểm tra hiển thị nút xóa
    final repo = WarehouseRepository();
    repo.createOrAssignPallet(
      palletCode: 'PAL-TEST-99',
      newItems: [],
      placedBy: 'Tester',
    );
    await tester.pump();

    expect(find.text('PAL-TEST-99'), findsWidgets);
    expect(find.byIcon(Icons.delete_outline), findsWidgets);

    // Dọn dẹp
    await repo.deletePallet('PAL-TEST-99');
  });

  testWidgets('Inbound and Outbound dropdown menus strictly contain Excel/CSV and Nhập từ PO options', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // 1. Kiểm tra PDA InboundScreen
    await tester.pumpWidget(
      const MaterialApp(
        home: InboundScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final inboundBtn = find.text('NHẬP HÀNG');
    expect(inboundBtn, findsOneWidget);
    await tester.tap(inboundBtn);
    await tester.pumpAndSettle();

    expect(find.text('Nhập File Excel / CSV (.xlsx, .csv)'), findsOneWidget);
    expect(find.text('Nhập Từ PO'), findsOneWidget);
    expect(find.text('Tạo Đơn Thủ Công'), findsNothing);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();

    // 2. Kiểm tra PDA OutboundScreen
    await tester.pumpWidget(
      const MaterialApp(
        home: OutboundScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final outboundBtn = find.text('XUẤT HÀNG');
    expect(outboundBtn, findsOneWidget);
    await tester.tap(outboundBtn);
    await tester.pumpAndSettle();

    expect(find.text('Nhập File Excel / CSV (.xlsx, .csv)'), findsOneWidget);
    expect(find.text('Nhập Từ PO'), findsOneWidget);
    expect(find.text('Tạo Nhanh Đơn Xuất'), findsNothing);
    expect(find.text('Chọn Đơn Xuất Có Sẵn'), findsNothing);
  });

  testWidgets('DesktopWarehouseManagementView shows only 3 pallet metric tiles without subtitles', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopWarehouseManagementView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Must show exactly the 3 metric boxes
    expect(find.text('TỔNG SỐ PALLET'), findsOneWidget);
    expect(find.text('ĐANG CÓ HÀNG'), findsOneWidget);
    expect(find.text('PALLET TRỐNG'), findsOneWidget);

    // Removed box must not exist
    expect(find.text('ĐÃ GẮN CHIP RFID'), findsNothing);

    // Subtitles must not exist
    expect(find.text('Đã đăng ký trong CSDL'), findsNothing);
    expect(find.text('Đang xếp hàng trong kho'), findsNothing);
    expect(find.text('Sẵn sàng nhận hàng mới'), findsNothing);
  });

  testWidgets('InboundScreen hides ĐỔI ĐƠN when only 1 order exists and shows when multiple exist', (WidgetTester tester) async {
    final repo = WarehouseRepository();

    // Create 1 order
    final order1 = InboundOrder(
      inboundOrderId: 'TEST-ORD-01',
      orderNo: 'TEST-ORD-01',
      sourceSupplier: 'Supplier 1',
      status: InboundOrderStatus.newOrder,
      createdAt: DateTime.now(),
      details: [
        InboundOrderDetail(productId: 'PROD-01', sku: 'SKU-01', productName: 'Prod 1', requiredQty: 5),
      ],
    );
    await repo.addInboundOrder(order1, autoGenerateEpcs: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: InboundScreen(initialOrderNo: 'TEST-ORD-01'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // When only 1 order exists: ĐỔI ĐƠN must NOT be visible
    expect(find.text('ĐỔI ĐƠN'), findsNothing);

    // Add a second order
    final order2 = InboundOrder(
      inboundOrderId: 'TEST-ORD-02',
      orderNo: 'TEST-ORD-02',
      sourceSupplier: 'Supplier 2',
      status: InboundOrderStatus.newOrder,
      createdAt: DateTime.now(),
      details: [
        InboundOrderDetail(productId: 'PROD-02', sku: 'SKU-02', productName: 'Prod 2', requiredQty: 3),
      ],
    );
    await repo.addInboundOrder(order2, autoGenerateEpcs: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: InboundScreen(initialOrderNo: 'TEST-ORD-01'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // When second order exists: ĐỔI ĐƠN must be visible
    expect(find.text('ĐỔI ĐƠN'), findsOneWidget);

    // Clean up
    await repo.deleteInboundOrder('TEST-ORD-01');
    await repo.deleteInboundOrder('TEST-ORD-02');
  });

  testWidgets('DesktopLocationManagementView shelf pallet card displays product breakdown table (Mã, Tên, Số lượng, Ngày nhập)', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final repo = WarehouseRepository();

    // Add a test location
    final testLoc = Location(
      locationId: 'TEST-SHELF-01',
      locationCode: 'TEST-SHELF-01',
      zone: 'Zone A',
      shelf: 'Kệ 1',
      level: 'Tầng 1',
      status: 'AVAILABLE',
      maxPalletCapacity: 10,
    );
    await repo.addLocation(testLoc);

    // Add a test pallet placed on this shelf
    await repo.registerOrUpdatePallet(
      palletCode: 'PL-TEST-01',
      palletName: 'Pallet Test 1',
      rfidEpc: 'E28011902000TEST01',
      locationId: 'TEST-SHELF-01',
    );

    // Add items for this pallet
    final testItem1 = Item(
      itemId: 'ITEM-TEST-01',
      productId: 'PROD-ABC-99',
      sku: 'SKU-ABC-99',
      productName: 'Cảm Biến Quang Học',
      serialNumber: 'SN-001',
      epc: 'E28011902000000000000101',
      status: ItemStatus.inStock,
      locationId: 'TEST-SHELF-01',
      palletId: 'PL-TEST-01',
      inboundTime: DateTime(2026, 9, 16, 10, 30),
    );
    final testItem2 = Item(
      itemId: 'ITEM-TEST-02',
      productId: 'PROD-ABC-99',
      sku: 'SKU-ABC-99',
      productName: 'Cảm Biến Quang Học',
      serialNumber: 'SN-002',
      epc: 'E28011902000000000000102',
      status: ItemStatus.inStock,
      locationId: 'TEST-SHELF-01',
      palletId: 'PL-TEST-01',
      inboundTime: DateTime(2026, 9, 16, 10, 30),
    );
    await repo.addItem(testItem1);
    await repo.addItem(testItem2);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopLocationManagementView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Filter specifically for the test location
    await tester.enterText(find.byType(TextField), 'TEST-SHELF-01');
    await tester.pump(const Duration(milliseconds: 300));

    // Tap on "Chi tiết →" for the test location
    final detailButton = find.text('Chi tiết →');
    expect(detailButton, findsOneWidget);
    await tester.tap(detailButton);
    await tester.pump(const Duration(milliseconds: 500));

    // Verify the shelf detail page is shown with Pallet card and strictly 3 clean KPI boxes
    expect(find.text('DANH SÁCH PALLET ĐANG ĐẶT TẠI KỆ (1)'), findsOneWidget);
    expect(find.text('PALLET: PL-TEST-01'), findsOneWidget);
    expect(find.text('SỐ PALLET TRÊN KỆ'), findsOneWidget);
    expect(find.text('SỐ HÀNG TRÊN KỆ'), findsOneWidget);
    expect(find.text('CHỦNG LOẠI SKU'), findsOneWidget);
    expect(find.textContaining('Sức chứa tối đa'), findsNothing);
    expect(find.textContaining('lối đi'), findsNothing);
    expect(find.textContaining('Thứ tự lối đi'), findsNothing);

    // Verify the product breakdown table has the 4 columns: Số lượng, Tên, Mã, Ngày nhập
    expect(find.text('MÃ SẢN PHẨM'), findsWidgets);
    expect(find.text('TÊN SẢN PHẨM'), findsWidgets);
    expect(find.text('SỐ LƯỢNG'), findsWidgets);
    expect(find.text('NGÀY NHẬP'), findsWidgets);

    // Verify the grouped values:
    expect(find.text('SKU-ABC-99'), findsWidgets);
    expect(find.text('Cảm Biến Quang Học'), findsOneWidget);
    expect(find.text('2 cái'), findsOneWidget);
    expect(find.text('16/09/2026 10:30'), findsOneWidget);

    // Clean up
    await repo.deleteItem(testItem1.epc);
    await repo.deleteItem(testItem2.epc);
    await repo.deletePalletFromMaster('PL-TEST-01');
    await repo.deleteLocation('TEST-SHELF-01');
  });

  testWidgets('DesktopWarehouseManagementView unified history view removes audit log sub-tab and consolidates all transactions', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopWarehouseManagementView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to "Quản Lý Lịch Sử" tab
    final historyTab = find.text('Quản Lý Lịch Sử');
    expect(historyTab, findsOneWidget);
    await tester.tap(historyTab);
    await tester.pumpAndSettle();

    // Assert "Nhật Ký Biến Động CSDL" and sub-tab bar are completely removed
    expect(find.text('Nhật Ký Biến Động CSDL'), findsNothing);
    expect(find.text('DANH MỤC LỊCH SỬ:'), findsNothing);
    expect(find.text('Lịch Sử Giao Dịch Nhập Xuất'), findsNothing);

    // Assert unified 4 metrics are present (Nhập, Xuất, Điều chuyển, Kiểm kê)
    expect(find.text('ĐƠN NHẬP KHO'), findsOneWidget);
    expect(find.text('ĐƠN XUẤT KHO'), findsOneWidget);
    expect(find.text('ĐIỀU CHUYỂN KHO'), findsOneWidget);
    expect(find.text('KIỂM KÊ KHO'), findsOneWidget);

    // Assert unified table column and 5-category switcher bar are present
    expect(find.text('NGHIỆP VỤ'), findsOneWidget);
    expect(find.textContaining('TẤT CẢ'), findsWidgets);
    expect(find.textContaining('NHẬP KHO'), findsWidgets);
    expect(find.textContaining('XUẤT KHO'), findsWidgets);
    expect(find.textContaining('ĐIỀU CHUYỂN'), findsWidgets);
    expect(find.textContaining('KIỂM KÊ'), findsWidgets);
    expect(find.text('Tất cả trạng thái'), findsOneWidget);
  });

  testWidgets('DesktopReportView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopReportView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopReportView), findsOneWidget);
  });

  testWidgets('DesktopReportView allows searching inventory by Serial Number (SN) and exporting report', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopReportView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify header
    expect(find.text('BÁO CÁO TỒN KHO'), findsOneWidget);

    // Verify search input in action toolbar
    expect(find.byType(TextField), findsOneWidget);
    expect(find.textContaining('Hiển thị:'), findsNothing);

    // Verify table headers include SỐ SERI (SN)
    expect(find.text('SỐ SERI (SN)'), findsOneWidget);
    expect(find.text('MÃ SKU'), findsOneWidget);
    expect(find.text('TÊN HÀNG HÓA'), findsOneWidget);
    expect(find.text('MÃ CHIP RFID (EPC)'), findsOneWidget);

    // Verify export button
    expect(find.textContaining('XUẤT BÁO CÁO'), findsOneWidget);

    // Test searching by non-existent SN
    await tester.enterText(find.byType(TextField), 'SN_NON_EXISTING_9999');
    await tester.pumpAndSettle();

    // Verify empty search result notice
    expect(find.textContaining('Không tìm thấy sản phẩm tồn kho nào khớp với Số Seri'), findsOneWidget);
    expect(find.text('XÓA BỘ LỌC TÌM KIẾM'), findsOneWidget);

    // Clear search filter
    await tester.tap(find.text('XÓA BỘ LỌC TÌM KIẾM'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Không tìm thấy sản phẩm tồn kho nào khớp với Số Seri'), findsNothing);
  });

  testWidgets('DesktopWarehouseManagementView includes Outbound and Transfer transactions in history tab', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final repo = WarehouseRepository();
    final now = DateTime.now();

    final moveTx = InventoryTransaction(
      transactionId: 'TX-TEST-MOVE-1',
      type: TransactionType.movement,
      documentNo: 'PALLET-TEST-01',
      sku: 'PALLET_PALLET-TEST-01',
      productName: 'Chuyển kho 10 Items',
      quantity: 10,
      fromLocation: 'KHO_TONG-A1',
      toLocation: 'KHO_TONG-B2',
      palletCode: 'PALLET-TEST-01',
      performedBy: 'Thủ kho Test',
      timestamp: now,
      notes: 'Test chuyển kho',
    );
    final outTx = InventoryTransaction(
      transactionId: 'TX-TEST-OUT-1',
      type: TransactionType.outbound,
      documentNo: 'PO-OUT-TEST-888',
      sku: 'SKU-OUT-888',
      productName: 'Xuất hàng đối soát test',
      quantity: 5,
      fromLocation: 'KHO_TONG',
      toLocation: 'Khách hàng Đại Lý ABC',
      performedBy: 'Cổng RFID Gate Outbound',
      timestamp: now,
      notes: 'Test xuất kho cổng RFID',
    );

    await DatabaseService().insertTransaction(moveTx);
    await DatabaseService().insertTransaction(outTx);
    await repo.reloadFromSqlite();

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopWarehouseManagementView(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Switch to History Tab (Tab 3: Quản Lý Lịch Sử)
    await tester.tap(find.text('Quản Lý Lịch Sử'));
    await tester.pumpAndSettle();

    expect(find.text('ĐIỀU CHUYỂN KHO'), findsOneWidget);
    expect(find.text('PO-OUT-TEST-888'), findsOneWidget);
    expect(find.text('PALLET-TEST-01'), findsOneWidget);
  });
}


