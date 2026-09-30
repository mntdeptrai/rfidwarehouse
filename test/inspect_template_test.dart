import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/excel_import_service.dart';
import 'package:uhf/services/report_export_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Verify Template-Goods-Receive-v3 (1).xlsx parses supplier PEPSICO correctly', () {
    final file = File('Template-Goods-Receive-v3 (1).xlsx');
    expect(file.existsSync(), isTrue);
    final bytes = file.readAsBytesSync();

    final parsed = ExcelImportService().parseBytes(bytes);
    final cartons = parsed.$1;
    expect(cartons.length, equals(10));
    for (var c in cartons) {
      expect(c['supplier'], equals('PEPSICO'));
    }
  });

  test('Verify Inventory Report export retains supplier from Inbound Order and Item', () async {
    final repo = WarehouseRepository();
    await repo.ensureInitialized();

    final now = DateTime.now();
    final order = InboundOrder(
      inboundOrderId: 'ORD-TEST-PEPSICO',
      orderNo: 'PO-PEPSICO-001',
      sourceSupplier: 'PEPSICO VIETNAM',
      status: InboundOrderStatus.completed,
      createdAt: now,
      details: [],
    );
    await repo.addInboundOrder(order);

    final item = Item(
      itemId: 'ITEM-TEST-PEP-01',
      productId: 'PROD-PEP-01',
      sku: 'SKU-PEP-01',
      productName: 'Nước ngọt Pepsi lon',
      serialNumber: 'SN-PEP-01',
      epc: 'E280689400005024B0765C99',
      status: ItemStatus.inStock,
      orderNo: 'PO-PEPSICO-001',
      supplier: 'PEPSICO VIETNAM',
      inboundTime: now,
    );
    await repo.insertDirectItems([item]);

    // Test getItemSupplier
    final supp = repo.getItemSupplier(item);
    expect(supp, equals('PEPSICO VIETNAM'));

    // Test exportInventoryReport
    final exportService = ReportExportService();
    final csvFile = await exportService.exportInventoryReport(ReportFormat.csv, items: [item]);
    expect(csvFile.existsSync(), isTrue);
    final csvContent = csvFile.readAsStringSync();
    expect(csvContent.contains('PEPSICO VIETNAM'), isTrue);

    // Test XLSX export
    final xlsxFile = await exportService.exportInventoryReport(ReportFormat.xlsx, items: [item]);
    expect(xlsxFile.existsSync(), isTrue);
    final xlsxBytes = xlsxFile.readAsBytesSync();
    final excel = Excel.decodeBytes(xlsxBytes);
    final sheet = excel['Ton_Kho_RFID'];
    bool foundSupplier = false;
    for (var row in sheet.rows) {
      for (var cell in row) {
        if (cell?.value?.toString().contains('PEPSICO VIETNAM') == true) {
          foundSupplier = true;
          break;
        }
      }
    }
    expect(foundSupplier, isTrue);
  });

  test('Verify Stock Reconciliation Report generates 3 sheets with excess EPC listing in Sheet 3', () async {
    final repo = WarehouseRepository();
    await repo.ensureInitialized();

    final reconciliationRows = [
      SkuStockReconciliationRow(
        sku: 'SKU-RECON-MATCH',
        productName: 'Bia Heineken 330ml',
        unit: 'Thùng',
        zoneOrLocation: 'Kệ A1-01',
        expectedQty: 5,
        actualQty: 5,
        matchedCount: 5,
        missingCount: 0,
        itemResults: [
          InventoryItemResult(
            epc: 'EPC-MATCH-001',
            sku: 'SKU-RECON-MATCH',
            productName: 'Bia Heineken 330ml',
            expectedLocation: 'Kệ A1-01',
            actualLocation: 'Kệ A1-01',
            resultType: InventoryVarianceType.match,
            readAt: DateTime.now(),
          ),
        ],
      ),
      SkuStockReconciliationRow(
        sku: 'SKU-RECON-MISS',
        productName: 'Sữa Milo hộp',
        unit: 'Lốc',
        zoneOrLocation: 'Kệ B2-05',
        expectedQty: 4,
        actualQty: 2,
        matchedCount: 2,
        missingCount: 2,
        itemResults: [
          InventoryItemResult(
            epc: 'EPC-MISS-001',
            sku: 'SKU-RECON-MISS',
            productName: 'Sữa Milo hộp',
            expectedLocation: 'Kệ B2-05',
            actualLocation: 'Chưa quét thấy',
            resultType: InventoryVarianceType.missing,
            readAt: DateTime.now(),
          ),
        ],
      ),
      SkuStockReconciliationRow(
        sku: 'THẺ_LẠ',
        productName: 'Thẻ RFID lạ chưa khai báo',
        unit: 'Cái',
        zoneOrLocation: 'Toàn bộ kho',
        expectedQty: 0,
        actualQty: 2,
        unknownCount: 2,
        itemResults: [
          InventoryItemResult(
            epc: 'EPC-EXTRA-UNKNOWN-999',
            sku: 'THẺ_LẠ',
            productName: 'Thẻ RFID lạ chưa khai báo',
            expectedLocation: 'Chưa khai báo',
            actualLocation: 'Cửa Kho G1',
            resultType: InventoryVarianceType.unknownEpc,
            readAt: DateTime.now(),
          ),
          InventoryItemResult(
            epc: 'EPC-EXTRA-UNKNOWN-888',
            sku: 'THẺ_LẠ',
            productName: 'Thẻ RFID lạ chưa khai báo',
            expectedLocation: 'Chưa khai báo',
            actualLocation: 'Cửa Kho G1',
            resultType: InventoryVarianceType.unknownEpc,
            readAt: DateTime.now(),
          ),
        ],
      ),
    ];

    final exportService = ReportExportService();
    final file = await exportService.exportStockReconciliationReport(
      ReportFormat.xlsx,
      rows: reconciliationRows,
      scopeTitle: 'Toàn bộ kho - Test 3 Sheets',
      sessionCode: 'KK-3SHEET-01',
    );

    expect(file.existsSync(), isTrue);
    final bytes = file.readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);

    // 1. Kiểm tra chính xác 3 sheets
    expect(excel.sheets.containsKey('Tong_Hop_Doi_Soat'), isTrue);
    expect(excel.sheets.containsKey('Doi_Chieu_Thieu_Va_Du'), isTrue);
    expect(excel.sheets.containsKey('Doi_Chieu_Thua_EPC'), isTrue);
    expect(excel.sheets.containsKey('Sheet1'), isFalse);

    // 2. Kiểm tra Sheet 1 có thông tin tổng hợp
    final sheet1 = excel['Tong_Hop_Doi_Soat'];
    bool foundSheet1Title = false;
    for (var row in sheet1.rows) {
      for (var cell in row) {
        if (cell?.value?.toString().contains('BẢNG TỔNG HỢP ĐỐI CHIẾU KIỂM KHO') == true) {
          foundSheet1Title = true;
          break;
        }
      }
    }
    expect(foundSheet1Title, isTrue);

    // 3. Kiểm tra Sheet 2 có thông tin thiếu và đủ
    final sheet2 = excel['Doi_Chieu_Thieu_Va_Du'];
    bool foundSheet2Title = false;
    bool foundMissingItem = false;
    for (var row in sheet2.rows) {
      for (var cell in row) {
        final val = cell?.value?.toString() ?? '';
        if (val.contains('BẢNG ĐỐI CHIẾU THIẾU VÀ ĐỦ')) {
          foundSheet2Title = true;
        }
        if (val.contains('EPC-MISS-001')) {
          foundMissingItem = true;
        }
      }
    }
    expect(foundSheet2Title, isTrue);
    expect(foundMissingItem, isTrue);

    // 4. Kiểm tra Sheet 3 có danh sách liệt kê mã EPC thừa
    final sheet3 = excel['Doi_Chieu_Thua_EPC'];
    bool foundSheet3Title = false;
    bool foundEpc999 = false;
    bool foundEpc888 = false;
    for (var row in sheet3.rows) {
      for (var cell in row) {
        final val = cell?.value?.toString() ?? '';
        if (val.contains('BẢNG ĐỐI CHIẾU THỪA & LIỆT KÊ MÃ CHIP RFID (EPC) THỪA')) {
          foundSheet3Title = true;
        }
        if (val.contains('EPC-EXTRA-UNKNOWN-999')) {
          foundEpc999 = true;
        }
        if (val.contains('EPC-EXTRA-UNKNOWN-888')) {
          foundEpc888 = true;
        }
      }
    }
    expect(foundSheet3Title, isTrue);
    expect(foundEpc999, isTrue);
    expect(foundEpc888, isTrue);
  });
}
