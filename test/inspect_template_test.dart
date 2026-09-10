import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/services/excel_import_service.dart';

void main() {
  test('Verify Template-Goods-Receive-v3.xlsx parses pallet code and pallet epc correctly', () {
    final file = File('Template-Goods-Receive-v3.xlsx');
    expect(file.existsSync(), isTrue);
    final bytes = file.readAsBytesSync();

    final parsed = ExcelImportService().parseBytes(bytes);
    final cartons = parsed.$1;
    expect(cartons.length, equals(10));
    expect(cartons.first['palletCode'], equals('945321545'));
    expect(cartons.first['palletEpc'], equals('AB2600100000000000000200'));
    expect(cartons.first['supplier'], equals('PEPSICO'));
  });
}
