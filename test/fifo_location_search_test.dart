import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/screens/fifo_search_screen.dart';
import 'package:uhf/widgets/warehouse_floor_plan_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WarehouseRepository repo;
  late UhfService uhf;

  final testTheme = ThemeData(
    useMaterial3: false,
    splashFactory: NoSplash.splashFactory,
  );

  setUp(() async {
    repo = WarehouseRepository();
    uhf = UhfService();
    await repo.ensureInitialized();
    await repo.clearAllData();

    // 1. Thêm 3 vị trí kệ: Kệ A1 (Trái), Kệ B1 (Phải), Kệ C1 (Cuối kho)
    await repo.addLocation(Location(
      locationId: 'LOC-A01',
      locationCode: 'RACK-A01',
      zone: 'Khu A',
      shelf: 'A1',
      level: 'Tầng 1',
      aisleSide: 'LEFT',
      sortOrder: 1,
    ));

    await repo.addLocation(Location(
      locationId: 'LOC-B01',
      locationCode: 'RACK-B01',
      zone: 'Khu B',
      shelf: 'B1',
      level: 'Tầng 1',
      aisleSide: 'RIGHT',
      sortOrder: 1,
    ));

    await repo.addLocation(Location(
      locationId: 'LOC-C01',
      locationCode: 'RACK-C01',
      zone: 'Khu C',
      shelf: 'C1',
      level: 'Tầng 1',
      aisleSide: 'BACK',
      sortOrder: 1,
    ));

    // 2. Thêm danh mục sản phẩm SKU-TEST-FIFO
    await repo.addProduct(const Product(
      productId: 'PROD-FIFO-01',
      sku: 'SKU-TEST-FIFO',
      productName: 'Linh Kiện Điện Tử ABC',
      unit: 'Thùng',
      category: 'Điện tử',
    ));

    // 3. Thêm 3 sản phẩm cùng SKU nhưng ngày nhập khác nhau:
    // Item 1: Nhập ngày 01/10/2026 tại Kệ A1 (CŨ NHẤT -> FIFO PHẢI LẤY ĐẦU TIÊN)
    await repo.addItem(Item(
      itemId: 'ITEM-FIFO-001',
      productId: 'PROD-FIFO-01',
      sku: 'SKU-TEST-FIFO',
      productName: 'Linh Kiện Điện Tử ABC',
      serialNumber: 'SN-001',
      epc: 'EPC_FIFO_001',
      locationId: 'LOC-A01',
      status: ItemStatus.inStock,
      inboundTime: DateTime(2026, 10, 1, 8, 30),
    ));

    // Item 2: Nhập ngày 03/10/2026 tại Kệ B1 (Nhập sau)
    await repo.addItem(Item(
      itemId: 'ITEM-FIFO-002',
      productId: 'PROD-FIFO-01',
      sku: 'SKU-TEST-FIFO',
      productName: 'Linh Kiện Điện Tử ABC',
      serialNumber: 'SN-002',
      epc: 'EPC_FIFO_002',
      locationId: 'LOC-B01',
      status: ItemStatus.inStock,
      inboundTime: DateTime(2026, 10, 3, 10, 0),
    ));

    // Item 3: Nhập ngày 05/10/2026 tại Kệ C1 (Mới nhất)
    await repo.addItem(Item(
      itemId: 'ITEM-FIFO-003',
      productId: 'PROD-FIFO-01',
      sku: 'SKU-TEST-FIFO',
      productName: 'Linh Kiện Điện Tử ABC',
      serialNumber: 'SN-003',
      epc: 'EPC_FIFO_003',
      locationId: 'LOC-C01',
      status: ItemStatus.inStock,
      inboundTime: DateTime(2026, 10, 5, 14, 15),
    ));
  });

  tearDown(() async {
    uhf.disableScanning();
    await repo.clearAllData();
  });

  testWidgets('1. Tìm kiếm bằng SKU: Tự động sắp xếp theo FIFO và làm sáng ô Kệ A1 cần lấy trước nhất', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const FifoSearchScreen(initialSku: 'SKU-TEST-FIFO'),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Kiểm tra tiêu đề và thanh tìm kiếm
    expect(find.text('TÌM VỊ TRÍ 2D (FIFO)'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'SKU-TEST-FIFO'), findsOneWidget);

    // 2. Kiểm tra thẻ tóm tắt FIFO: Chỉ hiển thị ô cần lấy là Kệ A1 (không cần liệt kê danh sách mã item)
    expect(find.text('⭐ CẦN LẤY THEO FIFO'), findsOneWidget);
    expect(find.textContaining('KỆ A1'), findsAtLeastNWidgets(1));

    // 3. Kiểm tra Bản đồ 2D được hiển thị
    expect(find.byType(WarehouseFloorPlanWidget), findsOneWidget);

    // 4. Ô Kệ A1 trên bản đồ 2D được làm sáng với huy hiệu ⭐ CẦN LẤY (FIFO)
    expect(find.text('⭐ CẦN LẤY (FIFO)'), findsAtLeastNWidgets(1));

    // 5. Các ô kệ khác (B1, C1) được đánh dấu có hàng
    expect(find.textContaining('Có hàng'), findsAtLeastNWidgets(1));
  });

  testWidgets('2. Khi chưa tìm kiếm thì không hiển thị sẵn ô cần lấy; khi nhập mã hàng/SKU mới làm sáng ô', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const FifoSearchScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Khi chưa tìm kiếm: KHÔNG hiển thị thẻ FIFO hay huy hiệu CẦN LẤY (FIFO)
    expect(find.text('⭐ CẦN LẤY THEO FIFO'), findsNothing);
    expect(find.text('⭐ CẦN LẤY (FIFO)'), findsNothing);
    expect(find.textContaining('Nhập mã hàng/SKU'), findsOneWidget);

    // Nhập mã hàng ITEM-FIFO-002 để tìm kiếm
    await tester.enterText(find.byType(TextField), 'ITEM-FIFO-002');
    await tester.pumpAndSettle();

    // Sau khi tìm kiếm: Làm sáng ô Kệ B1 cần lấy
    expect(find.text('⭐ CẦN LẤY THEO FIFO'), findsOneWidget);
    expect(find.textContaining('KỆ B1'), findsAtLeastNWidgets(1));
    expect(find.text('⭐ CẦN LẤY (FIFO)'), findsAtLeastNWidgets(1));
  });

  testWidgets('3. Hiển thị mượt mà trên Desktop không bị lỗi RenderFlex overflow', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const FifoSearchScreen(initialSku: 'SKU-TEST-FIFO'),
      ),
    );
    await tester.pumpAndSettle();

    // Xác nhận giao diện Desktop render thanh tiêu đề chuẩn
    expect(find.text('TÌM KIẾM VỊ TRÍ HÀNG 2D (FIFO)'), findsOneWidget);
    expect(find.byType(WarehouseFloorPlanWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('4. Hiển thị mượt mà trên tay cầm PDA (360x640) không bị tràn màn hình', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      MaterialApp(
        theme: testTheme,
        home: const FifoSearchScreen(initialSku: 'SKU-TEST-FIFO'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('TÌM VỊ TRÍ 2D (FIFO)'), findsOneWidget);
    expect(find.byType(WarehouseFloorPlanWidget), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
