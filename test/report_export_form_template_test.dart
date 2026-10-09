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
      includeEpc: true,
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
      includeEpc: true,
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
      includeEpc: true,
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
      includeEpc: true,
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
      includeEpc: true,
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
      includeEpc: true,
    );
    expect(await xlsxFile.exists(), isTrue);

    // Clean up
    await repo.deleteInventorySession(testSession.sessionId);
    if (await csvFile.exists()) await csvFile.delete();
    if (await xlsxFile.exists()) await xlsxFile.delete();
  });

  test('ReportExportService exports open Excel files allowing easy copy and modifications', () async {
    final testItem = Item(
      itemId: 'ITEM-OPEN-01',
      productId: 'P-OPEN-01',
      sku: 'SKU-OPEN-01',
      productName: 'Mặt Hàng Cho Phép Copy',
      serialNumber: 'SN-OPEN-999',
      epc: 'E2801160600002198000OPEN',
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
    bool hasFileSharingReadOnly = false;
    bool hasWorkbookProtection = false;

    for (final f in archive) {
      if (f.name.startsWith('xl/worksheets/sheet') && f.name.endsWith('.xml')) {
        final xml = utf8.decode(f.content as List<int>);
        if (xml.contains('<sheetProtection')) {
          hasSheetProtection = true;
        }
      }
      if (f.name == 'xl/workbook.xml') {
        final xml = utf8.decode(f.content as List<int>);
        if (xml.contains('readOnlyRecommended="1"')) {
          hasFileSharingReadOnly = true;
        }
        if (xml.contains('<workbookProtection')) {
          hasWorkbookProtection = true;
        }
      }
    }

    // Xác nhận không bị khóa bảo vệ: cho phép người dùng copy và chỉnh sửa tự do
    expect(hasSheetProtection, isFalse, reason: 'File Excel phải mở tự do, không bị khóa sheetProtection để người dùng thoải mái copy');
    expect(hasFileSharingReadOnly, isFalse, reason: 'Không kích hoạt cờ readOnlyRecommended để không làm phiền người dùng khi copy');
    expect(hasWorkbookProtection, isFalse, reason: 'Không khóa workbookProtection');

    // Clean up
    await repo.deleteItem(testItem.epc);
    if (await xlsxFile.exists()) await xlsxFile.delete();
  });

  test('ReportExportService exports Inventory Report grouped by SKU with quantity in XLSX and CSV', () async {
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

    // 4. Xuất Báo Cáo Tồn Kho (CSV): Gom nhóm theo SKU và hiển thị số lượng hàng tồn
    final csvFile = await exportService.exportInventoryReport(ReportFormat.csv, items: [testItem]);
    expect(await csvFile.exists(), isTrue);
    final csvContent = await csvFile.readAsString();
    expect(csvContent.contains('BÁO CÁO TỒN KHO THEO MÃ SKU'), isTrue);
    expect(csvContent.contains('SKU-LIFECYCLE-COL'), isTrue);
    expect(csvContent.contains('Số Lượng'), isTrue);

    // 5. Xuất Báo Cáo Tồn Kho (XLSX): Sheet 1 gộp SKU & Sheet 2 chi tiết các chip
    final xlsxFile = await exportService.exportInventoryReport(ReportFormat.xlsx, items: [testItem]);
    expect(await xlsxFile.exists(), isTrue);
    final xlsxBytes = await xlsxFile.readAsBytes();
    final excel = Excel.decodeBytes(xlsxBytes);

    // Sheet 1: Ton_Kho_SKU
    expect(excel.sheets.containsKey('Ton_Kho_SKU'), isTrue);
    final skuSheet = excel['Ton_Kho_SKU'];
    bool foundSkuHeader = false;
    bool foundQtyHeader = false;
    bool foundSkuRow = false;
    for (var row in skuSheet.rows) {
      for (var cell in row) {
        final val = cell?.value?.toString() ?? '';
        if (val.contains('Mã SKU')) foundSkuHeader = true;
        if (val.contains('Số Lượng')) foundQtyHeader = true;
        if (val.contains('SKU-LIFECYCLE-COL')) foundSkuRow = true;
      }
    }
    expect(foundSkuHeader, isTrue);
    expect(foundQtyHeader, isTrue);
    expect(foundSkuRow, isTrue);

    // Dọn dẹp
    await repo.deleteItem(epc);
    await repo.deleteLocation('LOC-A1');
    await repo.deleteLocation('LOC-B2');
    if (await csvFile.exists()) await csvFile.delete();
    if (await xlsxFile.exists()) await xlsxFile.delete();
  });

  test('WarehouseRepository and ReportExportService normalize SKU product name to generic category name', () async {
    // 1. Kiểm tra hàm getSkuProductName xử lý bỏ số đuôi của chip cá thể
    expect(repo.getSkuProductName('SKU-CHUNG TU', 'Chứng từ 14'), equals('Chứng từ'));
    expect(repo.getSkuProductName('SKU-CHUNG TU', 'Chứng từ - 14'), equals('Chứng từ'));
    expect(repo.getSkuProductName('SKU-CHUNG TU', 'Chứng từ #01'), equals('Chứng từ'));
    expect(repo.getSkuProductName('SKU-A4', 'Giấy in A4'), equals('Giấy in A4'));
    expect(repo.getSkuProductName('SKU-IPHONE', 'iPhone 15 Pro'), equals('iPhone 15 Pro'));

    // 2. Thêm các chip có tên cá thể (Chứng từ 14, Chứng từ 15) thuộc cùng SKU
    final item1 = Item(
      itemId: 'ITEM-CT-14',
      productId: 'PROD-CT',
      sku: 'SKU-CHUNG-TU-NORM',
      productName: 'Chứng từ 14',
      serialNumber: '810000000014',
      epc: '810000000014000000000000',
      status: ItemStatus.inStock,
    );
    final item2 = Item(
      itemId: 'ITEM-CT-15',
      productId: 'PROD-CT',
      sku: 'SKU-CHUNG-TU-NORM',
      productName: 'Chứng từ 15',
      serialNumber: '810000000015',
      epc: '810000000015000000000000',
      status: ItemStatus.inStock,
    );
    await repo.addItem(item1);
    await repo.addItem(item2);

    // 3. Xuất báo cáo tồn kho XLSX
    final xlsxFile = await exportService.exportInventoryReport(ReportFormat.xlsx, items: [item1, item2]);
    expect(await xlsxFile.exists(), isTrue);
    final bytes = await xlsxFile.readAsBytes();
    final excel = Excel.decodeBytes(bytes);
    final skuSheet = excel['Ton_Kho_SKU'];

    bool foundNormalizedName = false;
    bool foundOldRawName = false;
    for (var row in skuSheet.rows) {
      for (var cell in row) {
        final val = cell?.value?.toString() ?? '';
        if (val == 'Chứng từ') foundNormalizedName = true;
        if (val == 'Chứng từ 14') foundOldRawName = true;
      }
    }
    expect(foundNormalizedName, isTrue, reason: 'Tên hàng hóa của nhóm SKU phải được chuẩn hóa thành "Chứng từ"');
    expect(foundOldRawName, isFalse, reason: 'Không được hiển thị tên gắn số lẻ của từng chip như "Chứng từ 14"');

    // Dọn dẹp
    await repo.deleteItem(item1.epc);
    await repo.deleteItem(item2.epc);
    if (await xlsxFile.exists()) await xlsxFile.delete();
  });

  test('Xuat bao cao co/khong kem ma EPC va dinh dang ma chip moi dong 1 ma', () async {
    final itemA = Item(
      itemId: 'ITEM-EPC-01',
      productId: 'PROD-EPC',
      sku: 'SKU-EPC-STACK',
      productName: 'Sản phẩm thử nghiệm EPC',
      serialNumber: 'EPC01',
      epc: 'E28011900000000000000001',
      status: ItemStatus.inStock,
    );
    final itemB = Item(
      itemId: 'ITEM-EPC-02',
      productId: 'PROD-EPC',
      sku: 'SKU-EPC-STACK',
      productName: 'Sản phẩm thử nghiệm EPC',
      serialNumber: 'EPC02',
      epc: 'E28011900000000000000002',
      status: ItemStatus.inStock,
    );

    // 1. Xuất có EPC (mặc định includeEpc = true)
    final fileWithEpc = await exportService.exportInventoryReport(
      ReportFormat.xlsx,
      items: [itemA, itemB],
      includeEpc: true,
    );
    expect(await fileWithEpc.exists(), isTrue);
    final bytesWithEpc = await fileWithEpc.readAsBytes();
    final excelWithEpc = Excel.decodeBytes(bytesWithEpc);
    final sheetWith = excelWithEpc['Ton_Kho_SKU'];

    bool hasEpcHeaderWith = false;
    bool hasMultilineEpc = false;
    for (var row in sheetWith.rows) {
      for (var cell in row) {
        final val = cell?.value?.toString() ?? '';
        if (val.contains('Mã Chip RFID (EPC)')) hasEpcHeaderWith = true;
        if (val.contains('E28011900000000000000001') && val.contains('E28011900000000000000002')) {
          hasMultilineEpc = true;
        }
      }
    }
    expect(hasEpcHeaderWith, isTrue, reason: 'Phải có cột Mã Chip RFID (EPC) khi includeEpc = true');
    expect(hasMultilineEpc, isTrue, reason: 'Các mã chip EPC phải được lưu trong ô dữ liệu');

    // 2. Xuất KHÔNG có EPC (includeEpc = false)
    final fileWithoutEpc = await exportService.exportInventoryReport(
      ReportFormat.xlsx,
      items: [itemA, itemB],
      includeEpc: false,
    );
    expect(await fileWithoutEpc.exists(), isTrue);
    final bytesWithoutEpc = await fileWithoutEpc.readAsBytes();
    final excelWithoutEpc = Excel.decodeBytes(bytesWithoutEpc);
    final sheetWithout = excelWithoutEpc['Ton_Kho_SKU'];

    bool hasEpcHeaderWithout = false;
    bool hasEpcValueWithout = false;
    for (var row in sheetWithout.rows) {
      for (var cell in row) {
        final val = cell?.value?.toString() ?? '';
        if (val.contains('Mã Chip RFID (EPC)')) hasEpcHeaderWithout = true;
        if (val.contains('E28011900000000000000001')) hasEpcValueWithout = true;
      }
    }
    expect(hasEpcHeaderWithout, isFalse, reason: 'Không được có cột Mã Chip RFID (EPC) khi includeEpc = false');
    expect(hasEpcValueWithout, isFalse, reason: 'Không được chứa mã chip EPC khi includeEpc = false');

    if (await fileWithEpc.exists()) await fileWithEpc.delete();
    if (await fileWithoutEpc.exists()) await fileWithoutEpc.delete();

    // 3. Xuất mặc định KHÔNG truyền includeEpc (chuẩn doanh nghiệp: Không xuất cột EPC)
    final fileDefault = await exportService.exportInventoryReport(
      ReportFormat.xlsx,
      items: [itemA, itemB],
    );
    expect(await fileDefault.exists(), isTrue);
    final bytesDefault = await fileDefault.readAsBytes();
    final excelDefault = Excel.decodeBytes(bytesDefault);
    final sheetDefault = excelDefault['Ton_Kho_SKU'];

    bool hasEpcHeaderDefault = false;
    bool hasEpcValueDefault = false;
    for (var row in sheetDefault.rows) {
      for (var cell in row) {
        final val = cell?.value?.toString() ?? '';
        if (val.contains('Mã Chip RFID (EPC)')) hasEpcHeaderDefault = true;
        if (val.contains('E28011900000000000000001')) hasEpcValueDefault = true;
      }
    }
    expect(hasEpcHeaderDefault, isFalse, reason: 'Mặc định KHÔNG được có cột Mã Chip RFID (EPC)');
    expect(hasEpcValueDefault, isFalse, reason: 'Mặc định KHÔNG được chứa mã chip EPC');

    if (await fileDefault.exists()) await fileDefault.delete();
  });

  test('Outbound Report exports serial numbers with line breaks and center/mid alignment for all cells and supports single order export', () async {
    final testOutOrder = OutboundOrder(
      outboundOrderId: 'TEST-ORD-SN-ALIGN-01',
      poNo: 'PO-SN-ALIGN-TEST',
      customer: 'Khách Hàng Test Alignment',
      createdAt: DateTime(2026, 10, 9, 10, 0),
      status: OutboundOrderStatus.shipped,
      details: [
        OutboundOrderDetail(
          productId: 'P-SN-01',
          sku: 'SKU-SN-01',
          productName: 'Sản Phẩm Test SN',
          requiredQty: 2,
          pickedQty: 2,
          snList: ['SN-TEST-001', 'SN-TEST-002'],
          epcList: ['E2801160600002198000SN01', 'E2801160600002198000SN02'],
        ),
      ],
    );
    await repo.addOutboundOrder(testOutOrder);

    // 1. Test exportSingleOutboundOrder
    final singleFile = await exportService.exportSingleOutboundOrder(testOutOrder, format: ReportFormat.xlsx);
    expect(await singleFile.exists(), isTrue);
    final singleBytes = await singleFile.readAsBytes();
    final singleExcel = Excel.decodeBytes(singleBytes);
    final sheetName = singleExcel.tables.keys.first;
    final singleSheet = singleExcel.tables[sheetName]!;

    bool foundSnMultiline = false;
    for (final row in singleSheet.rows) {
      for (final cell in row) {
        final val = cell?.value?.toString() ?? '';
        if (val.contains('SN-TEST-001')) {
          foundSnMultiline = true;
          expect(val.contains('SN-TEST-002'), isTrue);
          expect(val.contains('\r\n') || val.contains('\n'), isTrue);

          // Verify xl/styles.xml contains horizontal="center" and vertical="center"
          final archive = ZipDecoder().decodeBytes(singleBytes);
          final stylesXmlFile = archive.findFile('xl/styles.xml');
          expect(stylesXmlFile, isNotNull);
          final stylesXml = utf8.decode(stylesXmlFile!.content as List<int>);
          expect(stylesXml.contains('horizontal="center"'), isTrue);
          expect(stylesXml.contains('vertical="center"'), isTrue);
        }
      }
    }
    expect(foundSnMultiline, isTrue, reason: 'Mỗi SN phải xuống 1 dòng và căn center, mid align');

    // 2. Test summary sheet export
    final summaryFile = await exportService.exportReportSelected(
      ReportType.outbound,
      ReportFormat.xlsx,
      selectedKeys: ['PO-SN-ALIGN-TEST'],
    );
    expect(await summaryFile.exists(), isTrue);

    // Clean up
    await DatabaseService().deleteOutboundOrder(testOutOrder.outboundOrderId);
    await repo.reloadFromDatabase();
    if (await singleFile.exists()) await singleFile.delete();
    if (await summaryFile.exists()) await summaryFile.delete();
  });
}


