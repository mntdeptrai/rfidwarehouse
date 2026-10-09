import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_delivery_view.dart';
import 'package:uhf/screens/desktop/desktop_audit_ticket_detail_view.dart';
import 'package:uhf/screens/pda/pda_goods_delivery_screen.dart';
import 'package:uhf/screens/pda/pda_inventory_screen.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/tower_light_service.dart';
import 'package:uhf/services/report_export_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testTheme = ThemeData(
    useMaterial3: false,
    splashFactory: InkRipple.splashFactory,
  );

  group('Duplicate Shipped EPC / SN Detection Tests (Báo lỗi trùng lặp khi quét chip đã xuất kho)', () {
    late WarehouseRepository repo;
    late UhfService uhf;
    late TowerLightService towerLight;

    setUp(() async {
      repo = WarehouseRepository();
      uhf = UhfService();
      towerLight = TowerLightService();
      towerLight.hardwareControlEnabled = false;
      await towerLight.turnOffAll();
      await repo.clearAllData(alsoClearCloud: false);
    });

    tearDown(() async {
      await towerLight.turnOffAll();
    });

    test('1. WarehouseRepository: findShippedItem và validateOutboundInventoryAndFifo phát hiện chính xác hàng đã xuất', () async {
      final shippedItem = Item(
        itemId: 'ITEM-SHIPPED-01',
        productId: 'PROD-01',
        sku: 'SKU-SHIPPED-01',
        productName: 'Tủ Rack 42U Đã Xuất',
        serialNumber: 'SN-SHIPPED-888',
        epc: 'E280119100000000SHIPPED1',
        status: ItemStatus.out,
      );
      await repo.insertDirectItems([shippedItem]);

      // 1.1 Tìm kiếm theo EPC
      final foundByEpc = repo.findShippedItem(epc: 'E280119100000000SHIPPED1');
      expect(foundByEpc, isNotNull);
      expect(foundByEpc!.productName, 'Tủ Rack 42U Đã Xuất');

      // 1.2 Tìm kiếm theo Serial Number (SN)
      final foundBySn = repo.findShippedItem(serialNumber: 'SN-SHIPPED-888');
      expect(foundBySn, isNotNull);
      expect(foundBySn!.itemId, 'ITEM-SHIPPED-01');

      // 1.3 Chip chưa xuất kho -> null
      expect(repo.findShippedItem(epc: 'E280119100000000NOTSHIPPED'), isNull);

      // 1.4 validateOutboundInventoryAndFifo với mã chip đã xuất
      final validation = repo.validateOutboundInventoryAndFifo(
        requestedItems: [
          {
            'sku': 'SKU-SHIPPED-01',
            'productId': 'PROD-01',
            'epc': 'E280119100000000SHIPPED1',
            'serialNumber': 'SN-SHIPPED-888',
          }
        ],
      );
      expect(validation.hasShippedConflict, isTrue);
      expect(validation.isStockSufficient, isFalse);
      expect(validation.items.first.isAlreadyShipped, isTrue);
      expect(validation.items.first.fifoWarning, contains('ĐÃ ĐƯỢC XUẤT KHO TRƯỚC ĐÓ'));
    });

    testWidgets('2. Desktop Outbound: Quét lại chip đã xuất kho -> Báo lỗi còi hú, đèn đỏ, hủy auto-confirm và khóa xuất', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Hàng hợp lệ trong kho
      final validItem = Item(
        itemId: 'ITEM-VALID-01',
        productId: 'PROD-VALID-01',
        sku: 'SKU-VALID-01',
        productName: 'Switch Mạng 24 Cổng',
        serialNumber: 'SN-VALID-01',
        epc: 'E280119100000000VALID001',
        status: ItemStatus.inStock,
        locationId: 'LOC-A1',
      );

      // Hàng đã xuất kho trước đó
      final shippedItem = Item(
        itemId: 'ITEM-OLD-SHIPPED',
        productId: 'PROD-VALID-01',
        sku: 'SKU-VALID-01',
        productName: 'Switch Mạng 24 Cổng (Đã Giao Hôm Qua)',
        serialNumber: 'SN-SHIPPED-999',
        epc: 'E280119100000000SHIPPED9',
        status: ItemStatus.out,
      );

      await repo.insertDirectItems([validItem, shippedItem]);

      const orderNo = 'XK-TEST-DUP-01';
      final outboundOrder = OutboundOrder(
        outboundOrderId: orderNo,
        poNo: orderNo,
        customer: 'Khách Hàng Kiểm Thử',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-VALID-01',
            sku: 'SKU-VALID-01',
            productName: 'Switch Mạng 24 Cổng',
            requiredQty: 1,
          ),
        ],
      );
      await repo.addOutboundOrder(outboundOrder);

      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: const Scaffold(
            body: DesktopGoodsDeliveryView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Nạp đơn từ DB vào màn hình Desktop
      final selectOrderBtn = find.text('XUẤT HÀNG');
      await tester.tap(selectOrderBtn);
      await tester.pumpAndSettle();

      final fromDbOption = find.textContaining('Chọn Đơn Xuất Có Sẵn');
      await tester.tap(fromDbOption);
      await tester.pumpAndSettle();

      final pickBtn = find.widgetWithText(ElevatedButton, 'CHỌN');
      await tester.tap(pickBtn);
      await tester.pumpAndSettle();

      // Quét trúng mã EPC của hàng ĐÃ XUẤT KHO TRƯỚC ĐÓ
      uhf.simulateTag('E280119100000000SHIPPED9');
      await tester.pump(const Duration(milliseconds: 200));

      // Đèn tháp phải chuyển ĐỎ + CÒI HÚ và có lý do báo động
      expect(towerLight.currentStatus.isRed, isTrue);
      expect(towerLight.currentStatus.reason, contains('LỖI TRÙNG EPC/SN'));
      expect(towerLight.currentStatus.reason, contains('ĐÃ ĐƯỢC XUẤT KHO TRƯỚC ĐÓ'));

      // Giao diện phải hiện banner cảnh báo màu đỏ
      expect(find.textContaining('LỖI TRÙNG EPC/SN: PHÁT HIỆN 1 CHIP ĐÃ XUẤT KHO TRƯỚC ĐÓ!'), findsOneWidget);

      // Quét thêm hàng hợp lệ
      uhf.simulateTag('E280119100000000VALID001');
      await tester.pump(const Duration(milliseconds: 300));

      // Vì có chip trùng đã xuất nên TUYỆT ĐỐI KHÔNG ĐƯỢC tự động xuất kho hay cho phép xuất kho!
      final confirmBtn = find.textContaining('XÁC NHẬN XUẤT KHO');
      expect(confirmBtn, findsNothing);

      await towerLight.turnOffAll();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('3. PDA Outbound: Quét lại chip đã xuất kho -> Khóa nút xuất kho với nhãn lỗi trùng và báo động', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final validItem = Item(
        itemId: 'ITEM-VALID-02',
        productId: 'PROD-PDA-01',
        sku: 'SKU-PDA-01',
        productName: 'Camera Giám Sát',
        serialNumber: 'SN-PDA-01',
        epc: 'E280119100000000PDAVAL01',
        status: ItemStatus.inStock,
        locationId: 'LOC-C1',
      );

      final shippedItem = Item(
        itemId: 'ITEM-PDA-SHIPPED',
        productId: 'PROD-PDA-01',
        sku: 'SKU-PDA-01',
        productName: 'Camera Giám Sát Cũ',
        serialNumber: 'SN-PDA-OLD-99',
        epc: 'E280119100000000PDASHIP9',
        status: ItemStatus.out,
      );

      await repo.insertDirectItems([validItem, shippedItem]);

      const orderNo = 'XK-PDA-DUP-01';
      final outboundOrder = OutboundOrder(
        outboundOrderId: orderNo,
        poNo: orderNo,
        customer: 'Khách PDA Test',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-PDA-01',
            sku: 'SKU-PDA-01',
            productName: 'Camera Giám Sát',
            requiredQty: 1,
          ),
        ],
      );
      await repo.addOutboundOrder(outboundOrder);

      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: const Scaffold(
            body: OutboundScreen(initialOrderNo: orderNo),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Xóa snackbar nạp đơn để không che nút dưới đáy màn hình
      ScaffoldMessenger.of(tester.element(find.byType(OutboundScreen))).clearSnackBars();
      await tester.pump(const Duration(milliseconds: 100));

      // Quét trúng mã EPC của hàng ĐÃ XUẤT KHO
      uhf.simulateTag('E280119100000000PDASHIP9');
      await tester.pump(const Duration(milliseconds: 200));

      // Đèn tháp chuyển đỏ cảnh báo
      expect(towerLight.currentStatus.isRed, isTrue);
      expect(towerLight.currentStatus.reason, contains('LỖI TRÙNG EPC/SN'));

      // Nút dưới đáy hiển thị trạng thái lỗi
      expect(find.textContaining('LỖI: TRÙNG EPC ĐÃ XUẤT (1)'), findsOneWidget);

      // Thử bấm vào nút lỗi -> Phải hiện SnackBar cảnh báo và chặn xuất kho
      await tester.tap(find.textContaining('LỖI: TRÙNG EPC ĐÃ XUẤT (1)'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.textContaining('ĐÃ ĐƯỢC XUẤT KHO TRƯỚC ĐÓ'), findsAtLeastNWidgets(1));

      await towerLight.turnOffAll();
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('4. PDA Inventory: Chip của hàng đã xuất kho được nhận diện rõ ràng là "HÀNG ĐÃ XUẤT KHO (TRÙNG EPC/SN)"', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final shippedItem = Item(
        itemId: 'ITEM-AUDIT-SHIPPED',
        productId: 'PROD-AUDIT-01',
        sku: 'SKU-AUDIT-01',
        productName: 'Máy Tính Bảng Barcode',
        serialNumber: 'SN-TABLET-888',
        epc: 'E280119100000000AUDITSH9',
        status: ItemStatus.out,
      );
      await repo.insertDirectItems([shippedItem]);

      // Tạo một phiên kiểm kê
      final session = repo.startInventorySession(zone: 'Toàn bộ kho');

      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: const Scaffold(
            body: PdaInventoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Mở phiên kiểm kê
      final sessionCard = find.text(session.sessionCode);
      await tester.tap(sessionCard);
      await tester.pumpAndSettle();

      // Quét chip của hàng đã xuất kho
      uhf.simulateTag('E280119100000000AUDITSH9');
      await tester.pump(const Duration(milliseconds: 300));

      // Thẻ hiển thị phải ghi rõ: HÀNG ĐÃ XUẤT KHO (TRÙNG EPC/SN)
      expect(find.textContaining('HÀNG ĐÃ XUẤT KHO (TRÙNG EPC/SN)'), findsOneWidget);
      expect(find.textContaining('Máy Tính Bảng Barcode'), findsOneWidget);
      expect(find.textContaining('SN-TABLET-888'), findsOneWidget);
      expect(find.textContaining('CÓ 1 CHIP ĐÃ XUẤT KHO TRƯỚC ĐÓ'), findsOneWidget);
      expect(find.textContaining('🚨 Đã xuất (1)'), findsOneWidget);

      // Chốt phiếu kiểm kê và kiểm tra không bị RenderFlex overflow trên màn hình hẹp (360x640)
      session.isCompleted = true;
      session.completedAt = DateTime.now();
      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: const Scaffold(
            body: PdaInventoryScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(session.sessionCode));
      await tester.pumpAndSettle();

      expect(find.text('ĐÃ CHỐT SỐ LIỆU'), findsOneWidget);
      expect(find.textContaining('CÓ 1 CHIP ĐÃ XUẤT KHO TRƯỚC ĐÓ'), findsOneWidget);
      expect(find.textContaining('QUAY LẠI DANH SÁCH'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('5. Desktop Audit Detail: Quét trúng chip đã xuất kho -> Hiển thị pill đỏ và filter chip riêng', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final shippedItem = Item(
        itemId: 'ITEM-DESK-SHIPPED',
        productId: 'PROD-DESK-01',
        sku: 'SKU-DESK-01',
        productName: 'Server Dell R740 Đã Xuất',
        serialNumber: 'SN-SERVER-777',
        epc: 'E280119100000000DESKSHP1',
        status: ItemStatus.out,
      );
      await repo.insertDirectItems([shippedItem]);

      final session = repo.startInventorySession(zone: 'Toàn bộ kho');
      repo.processAuditScan(sessionId: session.sessionId, scannedEpcs: ['E280119100000000DESKSHP1']);

      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: Scaffold(
            body: DesktopAuditTicketDetailView(
              session: session,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ban đầu ở Tab 0: Kiểm tra Scorecard và Trạng thái SKU
      expect(find.textContaining('🚨 ĐÃ XUẤT KHO'), findsOneWidget);
      expect(find.textContaining('1 Chip'), findsWidgets);
      expect(find.textContaining('Có 1 chip đã xuất'), findsOneWidget);

      // Chuyển sang Tab 1: Chi tiết chip RFID EPC
      await tester.tap(find.textContaining('CHI TIẾT DANH SÁCH CHIP'));
      await tester.pumpAndSettle();

      expect(find.textContaining('🚨 Đã xuất kho'), findsWidgets);
      expect(find.textContaining('🚨 Đã xuất kho (1)'), findsOneWidget);
      expect(find.textContaining('E280119100000000DESKSHP1'), findsOneWidget);
    });

    test('6. ReportExportService: Báo cáo kiểm kê (Audit) & Đối soát tồn kho (XLSX & CSV) có cảnh báo hàng đã xuất kho', () async {
      final exportService = ReportExportService();

      final shippedItem = Item(
        itemId: 'ITEM-REP-SHIPPED-01',
        productId: 'PROD-REP-01',
        sku: 'SKU-REP-01',
        productName: 'Cảm Biến Quang Đã Xuất',
        serialNumber: 'SN-SENSOR-555',
        epc: 'E280119100000000REPSHP01',
        status: ItemStatus.out,
      );
      await repo.insertDirectItems([shippedItem]);

      final session = repo.startInventorySession(zone: 'Toàn bộ kho');
      repo.processAuditScan(sessionId: session.sessionId, scannedEpcs: ['E280119100000000REPSHP01']);
      await repo.completeInventorySession(session.sessionId, 'Tester');

      // 6.1 Xuất Biên bản kiểm kê kho (Audit Form) định dạng CSV
      final csvAudit = await exportService.exportReportSelected(
        ReportType.audit,
        ReportFormat.csv,
        selectedKeys: [session.sessionCode],
        includeEpc: true,
      );
      final csvAuditContent = await csvAudit.readAsString();
      expect(csvAuditContent.contains('Đã xuất kho: 1'), isTrue);
      expect(csvAuditContent.contains('CẢNH BÁO BẤT THƯỜNG: DANH SÁCH CHIP ĐÃ XUẤT KHO TRƯỚC ĐÓ PHÁT HIỆN TRONG KHO (1 CHIP)'), isTrue);
      expect(csvAuditContent.contains('ĐÃ XUẤT KHO (CẦN TRUY VẾT)'), isTrue);
      expect(csvAuditContent.contains('E280119100000000REPSHP01'), isTrue);

      // 6.2 Xuất Biên bản kiểm kê kho (Audit Form) định dạng XLSX
      final xlsxAudit = await exportService.exportReportSelected(
        ReportType.audit,
        ReportFormat.xlsx,
        selectedKeys: [session.sessionCode],
        includeEpc: true,
      );
      final auditBytes = await xlsxAudit.readAsBytes();
      final auditExcel = Excel.decodeBytes(auditBytes);
      final auditSheet = auditExcel.tables.values.first;

      String cellStr(dynamic val) {
        if (val == null) return '';
        if (val is TextCellValue) return val.value.text ?? '';
        return val.toString();
      }

      bool foundShippedHeader = false;
      bool foundShippedTag = false;
      for (final row in auditSheet.rows) {
        for (final cell in row) {
          final text = cellStr(cell?.value);
          if (text.contains('Đã xuất kho: 1') || text.contains('CẢNH BÁO BẤT THƯỜNG: DANH SÁCH CHIP ĐÃ XUẤT KHO')) {
            foundShippedHeader = true;
          }
          if (text.contains('E280119100000000REPSHP01') || text.contains('ĐÃ XUẤT KHO (CẦN TRUY VẾT)')) {
            foundShippedTag = true;
          }
        }
      }
      expect(foundShippedHeader, isTrue);
      expect(foundShippedTag, isTrue);

      // 6.3 Xuất Báo cáo đối soát tồn kho theo SKU (Stock Reconciliation) định dạng CSV
      final reconRows = repo.buildSessionSkuBreakdown(session);
      final csvRecon = await exportService.exportStockReconciliationReport(
        ReportFormat.csv,
        rows: reconRows,
        scopeTitle: 'Toàn bộ kho hàng',
        sessionCode: session.sessionCode,
        includeEpc: true,
      );
      final csvReconContent = await csvRecon.readAsString();
      expect(csvReconContent.contains('Đã xuất kho: 1'), isTrue);
      expect(csvReconContent.contains('PHẦN 4: CẢNH BÁO BẤT THƯỜNG - DANH SÁCH CHIP ĐÃ XUẤT KHO PHÁT HIỆN TRONG KHO (1 CHIP)'), isTrue);
      expect(csvReconContent.contains('E280119100000000REPSHP01'), isTrue);

      // 6.4 Xuất Báo cáo đối soát tồn kho định dạng XLSX (Có Sheet 4 Canh_Bao_Da_Xuat)
      final xlsxRecon = await exportService.exportStockReconciliationReport(
        ReportFormat.xlsx,
        rows: reconRows,
        scopeTitle: 'Toàn bộ kho hàng',
        sessionCode: session.sessionCode,
        includeEpc: true,
      );
      final reconBytes = await xlsxRecon.readAsBytes();
      final reconExcel = Excel.decodeBytes(reconBytes);
      expect(reconExcel.tables.containsKey('Canh_Bao_Da_Xuat'), isTrue);

      final sheet4 = reconExcel.tables['Canh_Bao_Da_Xuat']!;
      bool foundInSheet4 = false;
      for (final row in sheet4.rows) {
        for (final cell in row) {
          final text = cellStr(cell?.value);
          if (text.contains('E280119100000000REPSHP01') || text.contains('CẢNH BÁO BẤT THƯỜNG')) {
            foundInSheet4 = true;
          }
        }
      }
      expect(foundInSheet4, isTrue);
    });
  });
}
