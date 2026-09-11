import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:excel/excel.dart';
import 'package:uhf/services/excel_import_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExcelImportService Tests', () {
    test('ExcelImportService singleton instance exists', () {
      final service1 = ExcelImportService();
      final service2 = ExcelImportService();
      expect(identical(service1, service2), isTrue);
    });

    test('Creates and exports Template-Goods-Receive Excel bytes correctly', () async {
      final excel = Excel.createExcel();
      final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
      final sheet = excel[sheetName];

      final headers = ['CARTON CODE', 'EPC', 'BARCODE', 'NAME'];
      for (int col = 0; col < headers.length; col++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0)).value = TextCellValue(headers[col]);
      }

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('CARTON01');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value = TextCellValue('EPC000000000000000000001');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).value = TextCellValue('8930000000001');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1)).value = TextCellValue('Product A');

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('CARTON01');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)).value = TextCellValue('EPC000000000000000000002');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 2)).value = TextCellValue('8930000000001');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 2)).value = TextCellValue('Product A');

      final bytes = Uint8List.fromList(excel.encode()!);
      expect(bytes.isNotEmpty, isTrue);

      final decoded = Excel.decodeBytes(bytes);
      expect(decoded.tables.containsKey(sheetName), isTrue);
      expect(decoded.tables[sheetName]!.rows.length, equals(3));
    });

    test('Reconciliation EPC filtering validates expected file EPCs', () {
      final expectedEpcs = {'E28011600000000000000001', 'E28011600000000000000002'};
      
      bool isTagValid(String epc, bool filterEnabled) {
        if (!filterEnabled) return true;
        return expectedEpcs.contains(epc.toUpperCase());
      }

      expect(isTagValid('E28011600000000000000001', true), isTrue);
      expect(isTagValid('E28011600000000000000002', true), isTrue);
      expect(isTagValid('E28099999999999999999999', true), isFalse); // External tag filtered out
      expect(isTagValid('E28099999999999999999999', false), isTrue); // Accepted when filter is OFF
    });

    test('Parses Excel with multiple distinct products in same carton correctly', () {
      final service = ExcelImportService();
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('THÙNG');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('MÃ CHIP EPC');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = TextCellValue('TÊN SẢN PHẨM');

      // Row 1: Áo Polo
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('THUNG-01');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value = TextCellValue('E28011910000000000000001');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).value = TextCellValue('Áo Polo Cotton');

      // Row 2: Quần Jeans (same carton, different product name!)
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('THUNG-01');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)).value = TextCellValue('E28011910000000000000002');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 2)).value = TextCellValue('Quần Jeans Slimfit');

      final bytes = Uint8List.fromList(excel.encode()!);
      final (cartons, rowCount) = service.parseBytes(bytes);

      expect(rowCount, equals(2));
      expect(cartons.length, equals(1));

      final c1 = cartons.first;
      expect(c1['cartonBox'], equals('THUNG-01'));
      // Carton summary must mention both products
      expect(c1['productName'].contains('Áo Polo Cotton'), isTrue);
      expect(c1['productName'].contains('Quần Jeans Slimfit'), isTrue);

      final serialItems = (c1['serialItems'] as List<Map<String, dynamic>>);
      expect(serialItems.length, equals(2));
      // First chip has Áo Polo
      expect(serialItems[0]['serial'], equals('E28011910000000000000001'));
      expect(serialItems[0]['name'], equals('Áo Polo Cotton'));
      // Second chip has Quần Jeans (NOT duplicated Áo Polo!)
      expect(serialItems[1]['serial'], equals('E28011910000000000000002'));
      expect(serialItems[1]['name'], equals('Quần Jeans Slimfit'));
    });

    test('Correctly distinguishes Mã sản phẩm and Tên sản phẩm without stealing column index', () {
      final service = ExcelImportService();
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      // Header: Mã sản phẩm (has "sản phẩm"), Tên sản phẩm, Mã EPC
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Mã sản phẩm');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('Tên sản phẩm');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = TextCellValue('Mã EPC');

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('SKU-POLO-01');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value = TextCellValue('Áo Polo Thể Thao');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).value = TextCellValue('E28011910000000000000001');

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('SKU-JEAN-02');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)).value = TextCellValue('Quần Jean Ống Đứng');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 2)).value = TextCellValue('E28011910000000000000002');

      final bytes = Uint8List.fromList(excel.encode()!);
      final (cartons, rowCount) = service.parseBytes(bytes);

      expect(rowCount, equals(2));
      final c = cartons.first;
      final serialItems = (c['serialItems'] as List<Map<String, dynamic>>);

      expect(serialItems[0]['barcode'], equals('SKU-POLO-01'));
      expect(serialItems[0]['name'], equals('Áo Polo Thể Thao'));

      expect(serialItems[1]['barcode'], equals('SKU-JEAN-02'));
      expect(serialItems[1]['name'], equals('Quần Jean Ống Đứng'));
    });

    test('Parses Excel file with 2 distinct Pallets and their respective RFIDs correctly without dropping either', () {
      final service = ExcelImportService();
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      // Header: MÃ PALLET | RFID PALLET | THÙNG | MÃ EPC | TÊN SẢN PHẨM
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('MÃ PALLET');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('RFID PALLET');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = TextCellValue('THÙNG');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0)).value = TextCellValue('MÃ EPC');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0)).value = TextCellValue('TÊN SẢN PHẨM');

      // Pallet 1: PL-01 with RFID E28011111111111111111111
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('PL-01');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value = TextCellValue('E28011111111111111111111');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).value = TextCellValue('THUNG-01');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1)).value = TextCellValue('EPC000000000000000000001');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1)).value = TextCellValue('Áo Polo');

      // Pallet 2: PL-02 with RFID E28022222222222222222222
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('PL-02');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)).value = TextCellValue('E28022222222222222222222');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 2)).value = TextCellValue('THUNG-02');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 2)).value = TextCellValue('EPC000000000000000000002');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 2)).value = TextCellValue('Quần Jeans');

      final bytes = Uint8List.fromList(excel.encode()!);
      final (cartons, rowCount) = service.parseBytes(bytes);

      expect(rowCount, equals(2));
      expect(cartons.length, equals(2)); // Both cartons/pallets preserved!

      final c1 = cartons.firstWhere((c) => c['palletId'] == 'PL-01');
      expect(c1['palletRfid'], equals('E28011111111111111111111'));
      expect((c1['serialItems'] as List).first['palletId'], equals('PL-01'));
      expect((c1['serialItems'] as List).first['palletRfid'], equals('E28011111111111111111111'));

      final c2 = cartons.firstWhere((c) => c['palletId'] == 'PL-02');
      expect(c2['palletRfid'], equals('E28022222222222222222222'));
      expect((c2['serialItems'] as List).first['palletId'], equals('PL-02'));
      expect((c2['serialItems'] as List).first['palletRfid'], equals('E28022222222222222222222'));
    });

    test('Parses exact user format: CARTON CODE, EPC, NAME, NCC, BARCODE PALET, EPC PALLET', () {
      final service = ExcelImportService();
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];

      // Exact user header
      final headers = ['CARTON CODE', 'EPC', 'NAME', 'NCC', 'BARCODE PALET', 'EPC PALLET'];
      for (int c = 0; c < headers.length; c++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0)).value = TextCellValue(headers[c]);
      }

      // 10 rows: rows 1-5 have Pallet 945321545, rows 6-10 have Pallet 945321988
      final rowsData = [
        ['CARTONTEST0001', 'E280689400005024B0765C56', 'Điều hoà Daikin', 'PEPSICO', '945321545', 'AB2600100000000000000200'],
        ['CARTONTEST0002', 'E280689400005024B0765C55', 'Điều hoà Daikin 2', 'PEPSICO', '945321545', 'AB2600100000000000000200'],
        ['CARTONTEST0003', 'E280689400004024B0765C57', 'Server', 'PEPSICO', '945321545', 'AB2600100000000000000200'],
        ['CARTONTEST0004', 'B00000000003', 'Server 2', 'PEPSICO', '945321545', 'AB2600100000000000000200'],
        ['CARTONTEST0005', 'B00000000002', 'Cuộn cáp quang', 'PEPSICO', '945321545', 'AB2600100000000000000200'],
        ['CARTONTEST0006', '202604010000000000000001', 'Cuộn cáp quang', 'PEPSICO', '945321988', 'E2806A960000502C4760454E'],
        ['CARTONTEST0007', '202604010000000000000002', 'Tủ nguồn', 'PEPSICO', '945321988', 'E2806A960000502C4760454E'],
        ['CARTONTEST0008', '2024011814546A01105001BC', 'Tủ nguồn 2', 'PEPSICO', '945321988', 'E2806A960000502C4760454E'],
        ['CARTONTEST0009', 'FFFFFAFF0000000000000005', 'Tủ nguồn 3', 'PEPSICO', '945321988', 'E2806A960000502C4760454E'],
        ['CARTONTEST0010', '2024102610306A031A904F10', 'Tủ nguồn 4', 'PEPSICO', '945321988', 'E2806A960000502C4760454E'],
      ];

      for (int r = 0; r < rowsData.length; r++) {
        for (int c = 0; c < rowsData[r].length; c++) {
          sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1)).value = TextCellValue(rowsData[r][c]);
        }
      }

      final bytes = Uint8List.fromList(excel.encode()!);
      final (cartons, rowCount) = service.parseBytes(bytes);

      expect(rowCount, equals(10));
      // Extract unique pallets
      final uniquePallets = cartons.map((c) => c['palletCode']?.toString()).toSet();
      expect(uniquePallets.contains('945321545'), isTrue);
      expect(uniquePallets.contains('945321988'), isTrue);
      expect(uniquePallets.length, equals(2));

      // Extract unique pallet RFIDs
      final uniquePalletRfids = cartons.map((c) => c['palletEpc']?.toString()).toSet();
      expect(uniquePalletRfids.contains('AB2600100000000000000200'), isTrue);
      expect(uniquePalletRfids.contains('E2806A960000502C4760454E'), isTrue);
      expect(uniquePalletRfids.length, equals(2));
    });
  });
}
