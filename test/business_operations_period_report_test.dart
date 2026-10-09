import 'dart:io';
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

    test('Tất cả báo cáo xuất ra gộp chung Mã SKU thành 1 hàng và ghi rõ tổng số lượng', () async {
      final orderNo = 'NK-GROUP-SKU-TEST';
      final testInbound = InboundOrder(
        inboundOrderId: orderNo,
        orderNo: orderNo,
        sourceSupplier: 'Kho Nội Bộ Test',
        createdAt: DateTime(2026, 10, 8, 16, 28),
        status: InboundOrderStatus.completed,
        details: [
          InboundOrderDetail(
            productId: 'P-CT',
            sku: 'SKU-CHUNG-TU-GRP',
            productName: 'Chứng từ',
            requiredQty: 5,
            receivedQty: 5,
          ),
        ],
      );
      await repo.addInboundOrder(testInbound, autoGenerateEpcs: false);

      final createdEpcs = <String>[];
      File? inCsvFile;
      File? inXlsxFile;
      File? invXlsxFile;
      addTearDown(() async {
        for (final epc in createdEpcs) {
          await repo.deleteItem(epc);
        }
        await repo.deleteInboundOrder(orderNo);
        if (inCsvFile != null && await inCsvFile.exists()) await inCsvFile.delete();
        if (inXlsxFile != null && await inXlsxFile.exists()) await inXlsxFile.delete();
        if (invXlsxFile != null && await invXlsxFile.exists()) await invXlsxFile.delete();
      });

      for (int i = 1; i <= 5; i++) {
        final epc = '81000000001$i';
        createdEpcs.add(epc);
        await repo.addItem(
          Item(
            itemId: 'IT-GRP-$i',
            productId: 'P-CT',
            sku: 'SKU-CHUNG-TU-GRP',
            productName: 'Chứng từ $i',
            serialNumber: 'SN-GRP-0$i',
            epc: epc,
            status: ItemStatus.inStock,
            locationId: 'A-01-01',
            orderNo: orderNo,
            inboundTime: DateTime(2026, 10, 8, 16, 28),
          ),
        );
      }

      // 1. Kiểm tra xuất CSV Phiếu Nhập Kho: chỉ có 1 dòng dữ liệu cho SKU-CHUNG-TU-GRP với số lượng = 5
      inCsvFile = await exportService.exportReportSelected(
        ReportType.inbound,
        ReportFormat.csv,
        selectedKeys: [orderNo],
      );
      final inCsvText = await inCsvFile.readAsString();
      final skuLinesInCsv = inCsvText
          .split(RegExp(r'\r?\n'))
          .where((line) => line.contains('SKU-CHUNG-TU-GRP'))
          .toList();
      expect(skuLinesInCsv.length, 1);
      expect(skuLinesInCsv.first.contains(',5,'), isTrue);
      expect(skuLinesInCsv.first.contains('Đã nhập kho'), isTrue);
      expect(inCsvText.contains('Đã lưu vào vị trí'), isFalse);

      // 2. Kiểm tra xuất Excel Phiếu Nhập Kho: chỉ có 1 hàng cho SKU-CHUNG-TU-GRP và cột Số Lượng = 5
      inXlsxFile = await exportService.exportReportSelected(
        ReportType.inbound,
        ReportFormat.xlsx,
        selectedKeys: [orderNo],
      );
      final inExcel = Excel.decodeBytes(await inXlsxFile.readAsBytes());
      final inSheet = inExcel.sheets.values.first;
      int skuRowCountInExcel = 0;
      String? qtyCellVal;
      for (int r = 0; r < inSheet.maxRows; r++) {
        final skuVal = inSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value?.toString() ?? '';
        if (skuVal == 'SKU-CHUNG-TU-GRP') {
          skuRowCountInExcel++;
          qtyCellVal = inSheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: r)).value?.toString();
        }
      }
      expect(skuRowCountInExcel, 1);
      expect(qtyCellVal, '5');

      // 3. Kiểm tra xuất Excel Báo Cáo Tồn Kho: chỉ có 1 sheet gộp theo SKU và Số Lượng = 5
      invXlsxFile = await exportService.exportInventoryReport(
        ReportFormat.xlsx,
        items: repo.items.where((i) => i.orderNo == orderNo).toList(),
      );
      final invExcel = Excel.decodeBytes(await invXlsxFile.readAsBytes());
      expect(invExcel.sheets.containsKey('Chi_Tiet_Cac_Chip'), isFalse);
      final invSheet = invExcel['Ton_Kho_SKU'];
      int invSkuRows = 0;
      String? invQtyVal;
      for (int r = 0; r < invSheet.maxRows; r++) {
        final skuVal = invSheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: r)).value?.toString() ?? '';
        if (skuVal == 'SKU-CHUNG-TU-GRP') {
          invSkuRows++;
          invQtyVal = invSheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: r)).value?.toString();
        }
      }
      expect(invSkuRows, 1);
      expect(invQtyVal, '5');
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

    testWidgets('Nhập Kho hiển thị cột TÊN SẢN PHẨM và SL; Tồn Kho gộp chung theo mã SKU', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final testOrder = InboundOrder(
        inboundOrderId: 'IN-PREVIEW-001',
        orderNo: 'IN-PREVIEW-001',
        sourceSupplier: 'Kho Nội Bộ Test',
        createdAt: DateTime.now(),
        status: InboundOrderStatus.completed,
        details: [
          InboundOrderDetail(
            productId: 'PROD-CT-01',
            sku: 'SKU-CHUNG-TU-TEST',
            productName: 'Chứng từ kế toán',
            requiredQty: 2,
            receivedQty: 0,
          ),
        ],
      );
      final item1 = Item(
        itemId: 'IT-PREV-1',
        productId: 'PROD-CT-01',
        sku: 'SKU-CHUNG-TU-TEST',
        productName: 'Chứng từ kế toán',
        serialNumber: 'SN-CT-001',
        epc: 'E200691500004020039901AA',
        status: ItemStatus.inStock,
        locationId: 'B1-02',
        palletId: 'PL-01',
        orderNo: 'IN-PREVIEW-001',
        inboundTime: DateTime.now(),
      );
      final item2 = Item(
        itemId: 'IT-PREV-2',
        productId: 'PROD-CT-01',
        sku: 'SKU-CHUNG-TU-TEST',
        productName: 'Chứng từ kế toán',
        serialNumber: 'SN-CT-002',
        epc: 'E200691500004020039902BB',
        status: ItemStatus.inStock,
        locationId: 'B1-02',
        palletId: 'PL-01',
        orderNo: 'IN-PREVIEW-001',
        inboundTime: DateTime.now(),
      );

      await repo.addInboundOrder(testOrder);
      await repo.addItem(item1);
      await repo.addItem(item2);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: DesktopReportView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Chuyển sang Tab "Báo Cáo Nghiệp Vụ"
      await tester.tap(find.text('Báo Cáo Nghiệp Vụ'));
      await tester.pumpAndSettle();

      // Kiểm tra bảng Nhập Kho: có cột TÊN SẢN PHẨM, SL, trạng thái Đã nhập kho và nút XEM CHI TIẾT
      expect(find.text('TÊN SẢN PHẨM'), findsOneWidget);
      expect(find.text('SL'), findsOneWidget);
      expect(find.text('SL KỲ VỌNG'), findsNothing);
      expect(find.text('Đã lưu vào vị trí'), findsNothing);
      expect(find.text('Đã nhập kho'), findsWidgets);
      expect(find.text('Chứng từ kế toán'), findsWidgets);
      expect(find.text('XEM CHI TIẾT'), findsWidgets);

      // Bấm nút XEM CHI TIẾT trên dòng đơn nhập
      await tester.tap(find.text('XEM CHI TIẾT').first);
      await tester.pumpAndSettle();
      expect(find.text('CHI TIẾT ĐƠN NHẬP KHO: IN-PREVIEW-001'), findsOneWidget);
      expect(find.text('SN-CT-001'), findsOneWidget);
      expect(find.text('SN-CT-002'), findsOneWidget);
      await tester.tap(find.text('ĐÓNG'));
      await tester.pumpAndSettle();

      // Chuyển sang nghiệp vụ "Tồn Kho" trong Báo Cáo Nghiệp Vụ
      await tester.tap(find.text('Tồn Kho').first);
      await tester.pumpAndSettle();

      // Kiểm tra đã gộp chung mã SKU thành 1 dòng giống bên Danh Sách Hàng Tồn
      expect(find.text('SKU-CHUNG-TU-TEST'), findsOneWidget);
      expect(find.text('2 sản phẩm'), findsWidgets);
      expect(find.text('XEM CHI TIẾT'), findsWidgets);

      // Clean up
      await repo.deleteItem(item1.epc);
      await repo.deleteItem(item2.epc);
      await repo.deleteInboundOrder(testOrder.inboundOrderId);
    });

    testWidgets('Xuất Kho hiển thị cột MÃ SN ĐÃ QUÉT và nút XUẤT PHIẾU cho từng đơn', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final outItem = Item(
        itemId: 'IT-OUT-W-1',
        productId: 'P-OUT-01',
        epc: 'EPC-OUT-WIDGET-01',
        sku: 'SKU-OUT-WIDGET',
        productName: 'Tủ rack mạng 42U xuất kho',
        serialNumber: 'SN-OUT-WIDGET-999',
        status: ItemStatus.out,
        locationId: 'A1-01',
      );
      await repo.addItem(outItem);

      final outboundOrder = OutboundOrder(
        outboundOrderId: 'ORD-OUT-TEST-WIDGET',
        poNo: 'PO-OUT-TEST-WIDGET',
        customer: 'Khách hàng Thử Nghiệm Xuất',
        createdAt: DateTime.now(),
        status: OutboundOrderStatus.shipped,
        details: [
          OutboundOrderDetail(
            productId: 'P-OUT-01',
            sku: 'SKU-OUT-WIDGET',
            productName: 'Tủ rack mạng 42U xuất kho',
            requiredQty: 1,
            pickedQty: 1,
            epcList: ['EPC-OUT-WIDGET-01'],
            snList: ['SN-OUT-WIDGET-999'],
          ),
        ],
      );
      await repo.addOutboundOrder(outboundOrder);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: DesktopReportView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Chuyển sang Tab "Báo Cáo Nghiệp Vụ"
      await tester.tap(find.text('Báo Cáo Nghiệp Vụ'));
      await tester.pumpAndSettle();

      // Chuyển sang nghiệp vụ "Xuất Kho"
      await tester.tap(find.text('Xuất Kho').first);
      await tester.pumpAndSettle();

      // Kiểm tra sự hiện diện của cột "MÃ SN ĐÃ QUÉT" và "THAO TÁC"
      expect(find.text('MÃ SN ĐÃ QUÉT'), findsOneWidget);
      expect(find.text('THAO TÁC'), findsOneWidget);
      expect(find.text('XUẤT PHIẾU'), findsWidgets);
      expect(find.textContaining('SN-OUT-WIDGET-999'), findsWidgets);

      // Clean up
      await repo.deleteItem(outItem.epc);
      await repo.deleteOutboundOrder(outboundOrder.outboundOrderId);
    });
  });
}

