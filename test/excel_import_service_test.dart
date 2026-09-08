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
  });
}
