import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/desktop/desktop_report_view.dart';
import 'package:uhf/services/report_export_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WarehouseRepository repo;
  late ReportExportService exportService;

  setUp(() async {
    repo = WarehouseRepository();
    exportService = ReportExportService();
    await repo.ensureInitialized();
  });

  group('ReportExportService - Báo cáo theo thời điểm & giai đoạn', () {
    test('Lọc và đếm số lượng bản ghi chính xác theo giai đoạn', () async {
      final orderPast = InboundOrder(
        inboundOrderId: 'ORD-IN-PAST-01',
        orderNo: 'ORD-IN-PAST-01',
        sourceSupplier: 'NCC Quá Khứ',
        createdAt: DateTime(2026, 1, 10, 8, 0),
        status: InboundOrderStatus.completed,
        details: [],
      );
      final orderCurrent = InboundOrder(
        inboundOrderId: 'ORD-IN-CURR-01',
        orderNo: 'ORD-IN-CURR-01',
        sourceSupplier: 'NCC Hiện Tại',
        createdAt: DateTime(2026, 9, 20, 14, 0),
        status: InboundOrderStatus.completed,
        details: [],
      );

      await repo.addInboundOrder(orderPast);
      await repo.addInboundOrder(orderCurrent);

      // Đếm không giới hạn ngày
      final countAll = exportService.getRecordCount(ReportType.inbound);
      expect(countAll >= 2, isTrue);

      // Đếm theo giai đoạn tháng 9/2026
      final fromDate = DateTime(2026, 9, 1);
      final toDate = DateTime(2026, 9, 30);
      final countSep = exportService.getRecordCount(
        ReportType.inbound,
        fromDate: fromDate,
        toDate: toDate,
      );
      expect(countSep >= 1, isTrue);

      // Đếm theo giai đoạn tháng 1/2026
      final countJan = exportService.getRecordCount(
        ReportType.inbound,
        fromDate: DateTime(2026, 1, 1),
        toDate: DateTime(2026, 1, 31),
      );
      expect(countJan >= 1, isTrue);

      // Clean up
      await repo.deleteInboundOrder(orderPast.inboundOrderId);
      await repo.deleteInboundOrder(orderCurrent.inboundOrderId);
    });

    test('Trích xuất báo cáo nhập kho và xuất kho theo giai đoạn ra CSV và Excel', () async {
      final testInbound = InboundOrder(
        inboundOrderId: 'ORD-IN-PERIOD-TEST',
        orderNo: 'ORD-IN-PERIOD-TEST',
        sourceSupplier: 'NCC Giai Đoạn A',
        createdAt: DateTime(2026, 8, 15, 9, 30),
        status: InboundOrderStatus.completed,
        details: [
          InboundOrderDetail(
            productId: 'P-PER-01',
            sku: 'SKU-PER-01',
            productName: 'Sản Phẩm Giai Đoạn Test',
            requiredQty: 50,
            receivedQty: 50,
          ),
        ],
      );
      await repo.addInboundOrder(testInbound);

      // Xuất CSV theo giai đoạn tháng 8/2026
      final csvFile = await exportService.exportReportSelected(
        ReportType.inbound,
        ReportFormat.csv,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );
      expect(await csvFile.exists(), isTrue);
      final csvText = await csvFile.readAsString();
      expect(csvText.contains('ORD-IN-PERIOD-TEST'), isTrue);
      expect(csvText.contains('NCC Giai Đoạn A'), isTrue);

      // Xuất Excel theo giai đoạn tháng 8/2026
      final xlsxFile = await exportService.exportReportSelected(
        ReportType.inbound,
        ReportFormat.xlsx,
        fromDate: DateTime(2026, 8, 1),
        toDate: DateTime(2026, 8, 31),
      );
      expect(await xlsxFile.exists(), isTrue);
      final bytes = await xlsxFile.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      expect(excel.sheets.isNotEmpty, isTrue);

      // Clean up
      await repo.deleteInboundOrder(testInbound.inboundOrderId);
      if (await csvFile.exists()) await csvFile.delete();
      if (await xlsxFile.exists()) await xlsxFile.delete();
    });

    test('formatPeriodSubtitle định dạng đúng văn bản phụ đề giai đoạn', () {
      final subAll = exportService.formatPeriodSubtitle(null, null);
      expect(subAll.contains('Toàn thời gian'), isTrue);

      final subPoint = exportService.formatPeriodSubtitle(DateTime(2026, 9, 30), DateTime(2026, 9, 30));
      expect(subPoint.contains('Ngày 30/09/2026'), isTrue);

      final subRange = exportService.formatPeriodSubtitle(DateTime(2026, 9, 1), DateTime(2026, 9, 30));
      expect(subRange.contains('01/09/2026') && subRange.contains('30/09/2026'), isTrue);
    });
  });

  group('DesktopReportView - Widget Test Tab Báo Cáo Nghiệp Vụ Trên PC', () {
    testWidgets('Chuyển sang Tab Báo Cáo Nghiệp Vụ, hiển thị 4 nghiệp vụ và các bộ lọc thời gian', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: DesktopReportView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Tìm nút Tab "Báo Cáo Nghiệp Vụ" trên Header Bar và bấm vào
      final tabButton = find.text('Báo Cáo Nghiệp Vụ');
      expect(tabButton, findsOneWidget);
      await tester.tap(tabButton);
      await tester.pumpAndSettle();

      // 2. Kiểm tra thanh chọn 4 nghiệp vụ: Nhập Kho, Xuất Kho, Tồn Kho, Biến Động Kho
      expect(find.text('Nhập Kho'), findsWidgets);
      expect(find.text('Xuất Kho'), findsWidgets);
      expect(find.text('Tồn Kho'), findsWidgets);
      expect(find.text('Biến Động Kho'), findsWidgets);

      // 3. Kiểm tra các nút Preset thời gian
      expect(find.text('Hôm nay'), findsOneWidget);
      expect(find.text('7 ngày qua'), findsOneWidget);
      expect(find.text('30 ngày qua'), findsOneWidget);
      expect(find.text('Tháng này'), findsOneWidget);
      expect(find.text('Tất cả'), findsOneWidget);

      // 4. Kiểm tra nút Trích Xuất Báo Cáo
      expect(find.text('TRÍCH XUẤT BÁO CÁO'), findsOneWidget);

      // 5. Thử chuyển sang nghiệp vụ "Xuất Kho"
      await tester.tap(find.text('Xuất Kho').first);
      await tester.pumpAndSettle();

      // 6. Thử chuyển sang nghiệp vụ "Tồn Kho"
      await tester.tap(find.text('Tồn Kho').first);
      await tester.pumpAndSettle();

      // 7. Thử chuyển sang nghiệp vụ "Biến Động Kho"
      await tester.tap(find.text('Biến Động Kho').first);
      await tester.pumpAndSettle();
    });
  });
}
