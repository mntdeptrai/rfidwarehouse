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
    await repo.reloadFromSqlite();
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
}
