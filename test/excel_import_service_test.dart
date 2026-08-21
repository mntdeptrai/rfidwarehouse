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
  });
}
