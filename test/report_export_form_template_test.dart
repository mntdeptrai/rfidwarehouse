import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/database_service.dart';
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

  test('ReportExportService exports Inbound Form template with standard voucher layout in XLSX and CSV', () async {
    final testOrder = InboundOrder(
      inboundOrderId: 'TEST-ORD-IN-01',
      orderNo: 'ORD-IN-FORM-TEST',
      sourceSupplier: 'Công Ty Điện Tử Test VN',
      createdAt: DateTime(2026, 9, 16, 10, 0),
      status: InboundOrderStatus.completed,
      details: [
        InboundOrderDetail(
          productId: 'P01',
          sku: 'SKU-TEST-01',
          productName: 'Bo Mạch RFID Sensor',
          requiredQty: 10,
          receivedQty: 10,
        ),
      ],
    );
    await repo.addInboundOrder(testOrder);

    final testItem = Item(
      itemId: 'ITEM-TEST-01',
      productId: 'P01',
      sku: 'SKU-TEST-01',
      productName: 'Bo Mạch RFID Sensor',
      serialNumber: 'SN001',
      epc: 'E2801160600002198000ABCD',
      orderNo: 'ORD-IN-FORM-TEST',
      palletId: 'PL-TEST-01',
      locationId: 'K01-01',
    );
    await repo.addItem(testItem);

    // Test CSV Export
    final csvFile = await exportService.exportReportSelected(
      ReportType.inbound,
      ReportFormat.csv,
      selectedKeys: ['ORD-IN-FORM-TEST'],
    );
    expect(await csvFile.exists(), isTrue);
    final csvContent = await csvFile.readAsString();
    expect(csvContent.contains('PHIẾU NHẬP KHO'), isTrue);
    expect(csvContent.contains('Công Ty Điện Tử Test VN'), isTrue);
    expect(csvContent.contains('E2801160600002198000ABCD'), isTrue);
    expect(csvContent.contains('NGƯỜI LẬP PHIẾU'), isTrue);
    expect(csvContent.contains('THỦ KHO NHẬN'), isTrue);

    // Test XLSX Export
    final xlsxFile = await exportService.exportReportSelected(
      ReportType.inbound,
      ReportFormat.xlsx,
      selectedKeys: ['ORD-IN-FORM-TEST'],
    );
    expect(await xlsxFile.exists(), isTrue);
    final bytes = await xlsxFile.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;

    String cellToString(dynamic val) {
      if (val == null) return '';
      if (val is TextCellValue) return val.value.text ?? '';
      return val.toString();
    }

    bool foundVoucherTitle = false;
    bool foundSupplier = false;
    bool foundEpc = false;
    for (final row in sheet.rows) {
      for (final cell in row) {
        final val = cellToString(cell?.value);
        if (val.contains('PHIẾU NHẬP KHO')) foundVoucherTitle = true;
        if (val.contains('Công Ty Điện Tử Test VN')) foundSupplier = true;
        if (val.contains('E2801160600002198000ABCD')) foundEpc = true;
      }
    }
    expect(foundVoucherTitle, isTrue);
    expect(foundSupplier, isTrue);
    expect(foundEpc, isTrue);

    // Clean up
    await repo.deleteInboundOrder(testOrder.inboundOrderId);
    await repo.deleteItem(testItem.epc);
    if (await csvFile.exists()) await csvFile.delete();
    if (await xlsxFile.exists()) await xlsxFile.delete();
  });

  test('ReportExportService exports Outbound Form template with standard delivery note in XLSX and CSV', () async {
    final testOutOrder = OutboundOrder(
      outboundOrderId: 'TEST-ORD-OUT-01',
      poNo: 'PO-OUT-FORM-TEST',
      customer: 'Tập Đoàn Logistics ABC',
      createdAt: DateTime(2026, 9, 16, 14, 0),
      status: OutboundOrderStatus.shipped,
      details: [
        OutboundOrderDetail(
          productId: 'P02',
          sku: 'SKU-OUT-01',
          productName: 'Áo Khoác RFID Smart',
          requiredQty: 5,
          pickedQty: 5,
          epcList: ['E2801160600002198000OUT1'],
        ),
      ],
    );
    await repo.addOutboundOrder(testOutOrder);

    // Test CSV Export
    final csvFile = await exportService.exportReportSelected(
      ReportType.outbound,
      ReportFormat.csv,
      selectedKeys: ['PO-OUT-FORM-TEST'],
    );
    expect(await csvFile.exists(), isTrue);
    final csvContent = await csvFile.readAsString();
    expect(csvContent.contains('PHIẾU XUẤT KHO KIÊM BÀN GIAO'), isTrue);
    expect(csvContent.contains('Tập Đoàn Logistics ABC'), isTrue);
    expect(csvContent.contains('E2801160600002198000OUT1'), isTrue);
    expect(csvContent.contains('THỦ KHO XUẤT'), isTrue);

    // Test XLSX Export
    final xlsxFile = await exportService.exportReportSelected(
      ReportType.outbound,
      ReportFormat.xlsx,
      selectedKeys: ['PO-OUT-FORM-TEST'],
    );
    expect(await xlsxFile.exists(), isTrue);
    final bytes = await xlsxFile.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;

    String cellToString(dynamic val) {
      if (val == null) return '';
      if (val is TextCellValue) return val.value.text ?? '';
      return val.toString();
    }

    bool foundVoucherTitle = false;
    bool foundCustomer = false;
    for (final row in sheet.rows) {
      for (final cell in row) {
        final val = cellToString(cell?.value);
        if (val.contains('PHIẾU XUẤT KHO')) foundVoucherTitle = true;
        if (val.contains('Tập Đoàn Logistics ABC')) foundCustomer = true;
      }
    }
    expect(foundVoucherTitle, isTrue);
    expect(foundCustomer, isTrue);

    // Clean up
    await DatabaseService().deleteOutboundOrder(testOutOrder.outboundOrderId);
    await repo.reloadFromDatabase();
    if (await csvFile.exists()) await csvFile.delete();
    if (await xlsxFile.exists()) await xlsxFile.delete();
  });

  test('ReportExportService exports Audit Form template with standard audit sheet in XLSX and CSV', () async {
    final testSession = InventorySession(
      sessionId: 'TEST-SESS-01',
      sessionCode: 'AUDIT-FORM-TEST',
      zone: 'Khu A',
      locationCode: 'K01-01',
      startedAt: DateTime(2026, 9, 16, 9, 0),
      completedAt: DateTime(2026, 9, 16, 10, 0),
      isCompleted: true,
      results: [
        InventoryItemResult(
          epc: 'E2801160600002198000AUD1',
          sku: 'SKU-AUDIT-01',
          productName: 'Sản Phẩm Kiểm Kê',
          expectedLocation: 'K01-01',
          actualLocation: 'K01-01',
          resultType: InventoryVarianceType.match,
          readAt: DateTime(2026, 9, 16, 9, 30),
        ),
      ],
    );
    await repo.saveInventorySession(testSession);

    // Test CSV Export
    final csvFile = await exportService.exportReportSelected(
      ReportType.audit,
      ReportFormat.csv,
      selectedKeys: ['AUDIT-FORM-TEST'],
    );
    expect(await csvFile.exists(), isTrue);
    final csvContent = await csvFile.readAsString();
    expect(csvContent.contains('BIÊN BẢN KIỂM KÊ KHO'), isTrue);
    expect(csvContent.contains('TRƯỞNG BAN KIỂM KÊ'), isTrue);
    expect(csvContent.contains('E2801160600002198000AUD1'), isTrue);

    // Test XLSX Export
    final xlsxFile = await exportService.exportReportSelected(
      ReportType.audit,
      ReportFormat.xlsx,
      selectedKeys: ['AUDIT-FORM-TEST'],
    );
    expect(await xlsxFile.exists(), isTrue);

    // Clean up
    await repo.deleteInventorySession(testSession.sessionId);
    if (await csvFile.exists()) await csvFile.delete();
    if (await xlsxFile.exists()) await xlsxFile.delete();
  });

  test('ReportExportService exports Excel files with anti-tamper sheet protection and read-only recommendation', () async {
    final testItem = Item(
      itemId: 'ITEM-PROT-01',
      productId: 'P-PROT-01',
      sku: 'SKU-PROT-01',
      productName: 'Mặt Hàng Khóa Chống Sửa',
      serialNumber: 'SN-PROT-999',
      epc: 'E2801160600002198000PROT',
      status: ItemStatus.inStock,
    );
    await repo.addItem(testItem);

    final xlsxFile = await exportService.exportInventoryReport(
      ReportFormat.xlsx,
      items: [testItem],
    );
    expect(await xlsxFile.exists(), isTrue);

    final bytes = await xlsxFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    bool hasSheetProtection = false;
    bool hasFileSharing = false;
    bool hasWorkbookProtection = false;

    for (final f in archive) {
      if (f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml')) {
        final xml = utf8.decode(f.content as List<int>);
        if (xml.contains('<sheetProtection sheet="true"') && xml.contains('password="DFEE"')) {
          hasSheetProtection = true;
        }
      }
      if (f.name == 'xl/workbook.xml') {
        final xml = utf8.decode(f.content as List<int>);
        if (xml.contains('<fileSharing readOnlyRecommended="1"')) {
          hasFileSharing = true;
        }
        if (xml.contains('<workbookProtection lockStructure="true"') && xml.contains('workbookPassword="DFEE"')) {
          hasWorkbookProtection = true;
        }
      }
    }

    expect(hasSheetProtection, isTrue, reason: 'Mọi sheet trong file Excel phải có khóa sheetProtection chống sửa');
    expect(hasFileSharing, isTrue, reason: 'Workbook phải có cờ fileSharing khuyến nghị mở Chỉ Đọc');
    expect(hasWorkbookProtection, isTrue, reason: 'Workbook phải có khóa workbookProtection chống sửa cấu trúc');

    // Clean up
    await repo.deleteItem(testItem.epc);
    if (await xlsxFile.exists()) await xlsxFile.delete();
  });

  test('ReportExportService exports Inventory Report with Vòng Đời Thẻ column in XLSX and CSV', () async {
    final repo = WarehouseRepository();
    final exportService = ReportExportService();
    await repo.ensureInitialized();

    const epc = 'E2806894TESTLIFECYCLECOL01';
    final now = DateTime.now();

    final testItem = Item(
      itemId: 'ITEM-LIFECYCLE-COL-01',
      productId: 'PROD-LC-COL-1',
      sku: 'SKU-LIFECYCLE-COL',
      productName: 'Mặt Hàng Thử Nghiệm Vòng Đời',
      serialNumber: 'SN-LC-COL-001',
      epc: epc,
      status: ItemStatus.inStock,
      inboundTime: now.subtract(const Duration(hours: 1)),
      locationId: 'KỆ A1',
      palletId: 'PL-TEST-01',
      orderNo: 'PO-LC-COL-999',
    );
    await repo.addItem(testItem);

    // Ghi nhận thêm 1 sự kiện kiểm kê
    await repo.recordTagLifecycle(
      epc: epc,
      itemId: testItem.itemId,
      sku: testItem.sku,
      productName: testItem.productName,
      serialNumber: testItem.serialNumber,
      action: TagLifecycleAction.auditMatch,
      newStatus: ItemStatus.inStock.label,
      toLocation: 'KỆ A1',
      performedBy: 'Thủ kho Kiểm Kê',
    );

    // 1. Kiểm tra chuỗi tóm tắt có ngày giờ đầy đủ
    final summary1 = repo.getTagLifecycleSummary(epc);
    expect(summary1.contains('Khởi tạo mã'), isTrue);
    expect(summary1.contains('Nhập kho'), isTrue);
    expect(summary1.contains('Kiểm kê khớp'), isTrue);
    expect(RegExp(r'\[\d{2}/\d{2}/\d{4} \d{2}:\d{2}\]').hasMatch(summary1), isTrue, reason: 'Mọi mốc sự kiện phải có ngày giờ [dd/MM/yyyy HH:mm]');

    // 2. Thao tác điều chuyển vị trí từ KỆ A1 sang KỆ B2
    final locA = Location(locationId: 'LOC-A1', locationCode: 'KỆ A1', zone: 'A', shelf: '1', level: '1');
    final locB = Location(locationId: 'LOC-B2', locationCode: 'KỆ B2', zone: 'B', shelf: '2', level: '1');
    await repo.addLocation(locA);
    await repo.addLocation(locB);

    await repo.moveItemIndividual(
      epc: epc,
      newLocationId: 'LOC-B2',
      performedBy: 'Thủ kho Điều Chuyển',
    );

    final summaryAfterMove = repo.getTagLifecycleSummary(epc);
    expect(summaryAfterMove.contains('Chuyển vị trí [KỆ A1 → KỆ B2]'), isTrue, reason: 'Sau khi di chuyển phải thể hiện vị trí chuyển đi/đến có ngày giờ');
    expect(summaryAfterMove.contains('PL-TEST-01'), isTrue, reason: 'Phải ghi nhận chi tiết Pallet');

    // 3. Thao tác ghi nhận gửi đi sửa chữa / bảo hành
    await repo.recordItemRepair(
      epc: epc,
      reason: 'Lỗi cảm biến nhiệt',
      performedBy: 'Kỹ thuật viên',
    );

    final summaryAfterRepair = repo.getTagLifecycleSummary(epc);
    expect(summaryAfterRepair.contains('Gửi sửa chữa / Bảo hành [Lỗi cảm biến nhiệt]'), isTrue, reason: 'Phải ghi nhận sự kiện sửa chữa/thu hồi có ngày giờ');
    expect(summaryAfterRepair.contains('KỆ B2'), isTrue, reason: 'Phải ghi nhận chi tiết Kệ khi sửa chữa');
    expect(summaryAfterRepair.contains('PL-TEST-01'), isTrue, reason: 'Phải ghi nhận chi tiết Pallet khi sửa chữa');

    // 4. Xuất Báo Cáo Tồn Kho (CSV) và xác thực dữ liệu cập nhật
    final csvFile = await exportService.exportInventoryReport(ReportFormat.csv, items: [testItem]);
    expect(await csvFile.exists(), isTrue);
    final csvContent = await csvFile.readAsString();
    expect(csvContent.contains('Vòng Đời Thẻ'), isTrue);
    expect(csvContent.contains('Chuyển vị trí [KỆ A1 → KỆ B2]'), isTrue);
    expect(csvContent.contains('Gửi sửa chữa / Bảo hành'), isTrue);

    // 5. Xuất Báo Cáo Tồn Kho (XLSX) và xác thực dữ liệu cập nhật
    final xlsxFile = await exportService.exportInventoryReport(ReportFormat.xlsx, items: [testItem]);
    expect(await xlsxFile.exists(), isTrue);
    final xlsxBytes = await xlsxFile.readAsBytes();
    final excel = Excel.decodeBytes(xlsxBytes);
    final sheet = excel['Ton_Kho_RFID'];
    bool foundHeader = false;
    bool foundMove = false;
    bool foundRepair = false;
    for (var row in sheet.rows) {
      for (var cell in row) {
        final val = cell?.value?.toString() ?? '';
        if (val.contains('Vòng Đời Thẻ')) foundHeader = true;
        if (val.contains('Chuyển vị trí [KỆ A1 → KỆ B2]')) foundMove = true;
        if (val.contains('Gửi sửa chữa / Bảo hành')) foundRepair = true;
      }
    }
    expect(foundHeader, isTrue);
    expect(foundMove, isTrue);
    expect(foundRepair, isTrue);

    // Xác thực tự động căn chỉnh độ cao dòng (Row Height) cho dữ liệu nhiều dòng
    final heights = sheet.getRowHeights;
    expect(heights.values.any((h) => h > 22.0), isTrue, reason: 'Hàng có vòng đời nhiều dòng phải được tự động tăng độ cao');

    // Dọn dẹp
    await repo.deleteItem(epc);
    await repo.deleteLocation('LOC-A1');
    await repo.deleteLocation('LOC-B2');
    if (await csvFile.exists()) await csvFile.delete();
    if (await xlsxFile.exists()) await xlsxFile.delete();
  });
}
