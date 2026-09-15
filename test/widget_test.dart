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
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/models/tag_info.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/uhf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RFID WMS App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RfidWmsApp());
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.byType(RfidWmsApp), findsOneWidget);
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

    // Ô 1: Hiện thông tin hàng cần cất
    expect(find.textContaining('HÀNG CẦN CẤT'), findsOneWidget);
    expect(find.textContaining('PAL-TEST-99'), findsWidgets);
    expect(find.textContaining('Số lượng sản phẩm: 1'), findsOneWidget);
    expect(find.text('1 SP'), findsNothing);
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

    // Sau khi chọn vị trí: Dòng 2 quét barcode xuất hiện
    expect(find.textContaining('DÒNG 2: QUÉT BARCODE ĐỂ CẤT HÀNG'), findsOneWidget);
    expect(find.textContaining('BẬT QUÉT BARCODE (CÒ PDA)'), findsOneWidget);
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


    // Nút XUẤT HÀNG dạng dropdown màu cyan trên header
    expect(find.text('XUẤT HÀNG'), findsOneWidget);
    expect(find.text('LỊCH SỬ XUẤT KHO'), findsOneWidget);
    expect(find.text('LÀM MỚI'), findsOneWidget);

    // Màn hình chờ tiếp nhận hàng xuất khi chưa nạp file
    expect(find.textContaining('CỔNG RFID ĐANG SẴN SÀNG TIẾP NHẬN HÀNG XUẤT'), findsOneWidget);

    // Bấm xem Lịch sử xuất kho
    await tester.tap(find.text('LỊCH SỬ XUẤT KHO'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('LỊCH SỬ GIAO DỊCH XUẤT KHO'), findsOneWidget);
    expect(find.text('CỔNG XUẤT KHO'), findsOneWidget);

    // Bấm quay lại Cổng xuất kho
    await tester.tap(find.text('CỔNG XUẤT KHO'));
    await tester.pump(const Duration(milliseconds: 300));
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
}

