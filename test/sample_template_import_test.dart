import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/services/excel_import_service.dart';

void main() {
  test('Verify Mau_Nhap_Hang_Cung_Loai_Nhieu_EPC.xlsx parses 60 items, 6 cartons and 3 distinct pallets with separate pallet EPCs', () {
    final file = File('Mau_Nhap_Hang_Cung_Loai_Nhieu_EPC.xlsx');
    expect(file.existsSync(), isTrue, reason: 'File must exist on disk');

    final bytes = file.readAsBytesSync();
    expect(bytes.isNotEmpty, isTrue);

    final service = ExcelImportService();
    final (cartons, totalRows) = service.parseBytes(bytes);

    expect(cartons.isNotEmpty, isTrue);
    expect(cartons.length, equals(6), reason: 'There should be 6 cartons (CARTON-POLO-001 to 006)');

    int totalSerials = 0;
    final allItemEpcs = <String>{};
    final allPalletIds = <String>{};
    final allPalletEpcs = <String>{};

    for (final c in cartons) {
      expect(c['supplier'], equals('Tổng Công Ty May Việt Tiến'));
      expect(c['productName'], equals('Áo Polo Nam Thể Thao RFID Coolmax'));
      expect(c['productCode'], equals('SKU-POLO-COOLMAX-01'));

      final palletId = c['palletId'] as String;
      final palletEpc = c['palletEpc'] as String;
      allPalletIds.add(palletId);
      allPalletEpcs.add(palletEpc);

      final serials = c['serials'] as List<String>;
      expect(serials.length, equals(10), reason: 'Each carton contains 10 items');
      totalSerials += serials.length;

      for (final epc in serials) {
        expect(allItemEpcs.contains(epc), isFalse, reason: 'Item EPC $epc must be unique');
        allItemEpcs.add(epc);
      }
    }

    // 1. Kiểm tra 60 sản phẩm cùng loại với 60 EPC riêng biệt
    expect(totalSerials, equals(60), reason: 'Total items imported must be 60');
    expect(allItemEpcs.length, equals(60), reason: 'All 60 item EPCs must be distinct');

    // 2. Kiểm tra nhiều Pallet riêng biệt (3 Pallet khác nhau)
    expect(allPalletIds.length, equals(3), reason: 'Must have 3 distinct Pallet IDs');
    expect(allPalletIds, containsAll(['PL-01', 'PL-02', 'PL-03']));

    // 3. Kiểm tra nhiều EPC Pallet riêng biệt (3 EPC Pallet khác nhau)
    expect(allPalletEpcs.length, equals(3), reason: 'Must have 3 distinct Pallet EPCs');
    expect(allPalletEpcs, containsAll([
      'AB2600100000000000000201',
      'AB2600100000000000000202',
      'AB2600100000000000000203',
    ]));
  });

  test('Verify Mau_Nhap_Hang_2_Loai_Hang_2_Pallet_Nhieu_EPC.xlsx parses 2 products, 2 pallets and 40 distinct item EPCs', () {
    final file = File('Mau_Nhap_Hang_2_Loai_Hang_2_Pallet_Nhieu_EPC.xlsx');
    expect(file.existsSync(), isTrue, reason: 'File must exist on disk');

    final bytes = file.readAsBytesSync();
    expect(bytes.isNotEmpty, isTrue);

    final service = ExcelImportService();
    final (cartons, totalRows) = service.parseBytes(bytes);

    expect(cartons.isNotEmpty, isTrue);
    expect(cartons.length, equals(4), reason: 'There should be 4 cartons (2 for Polo, 2 for Short)');

    int totalSerials = 0;
    final allItemEpcs = <String>{};
    final allPalletIds = <String>{};
    final allPalletEpcs = <String>{};
    final allSkus = <String>{};
    final allProductNames = <String>{};

    for (final c in cartons) {
      expect(c['supplier'], equals('Tổng Công Ty May Việt Tiến'));

      final sku = c['productCode'] as String;
      final name = c['productName'] as String;
      final palletId = c['palletId'] as String;
      final palletEpc = c['palletEpc'] as String;

      allSkus.add(sku);
      allProductNames.add(name);
      allPalletIds.add(palletId);
      allPalletEpcs.add(palletEpc);

      final serials = c['serials'] as List<String>;
      expect(serials.length, equals(10), reason: 'Each carton contains 10 items');
      totalSerials += serials.length;

      for (final epc in serials) {
        expect(allItemEpcs.contains(epc), isFalse, reason: 'Item EPC $epc must be unique');
        allItemEpcs.add(epc);
      }
    }

    // 1. Kiểm tra 2 loại mặt hàng riêng biệt
    expect(allSkus.length, equals(2), reason: 'Must have exactly 2 distinct SKUs');
    expect(allSkus, containsAll(['SKU-POLO-COOLMAX-01', 'SKU-SHORT-FLEX-02']));
    expect(allProductNames.length, equals(2), reason: 'Must have exactly 2 distinct product names');
    expect(allProductNames, containsAll([
      'Áo Polo Nam Thể Thao RFID Coolmax',
      'Quần Short Thể Thao RFID Co Giãn',
    ]));

    // 2. Kiểm tra 2 Pallet riêng biệt và 2 EPC Pallet riêng biệt
    expect(allPalletIds.length, equals(2), reason: 'Must have 2 distinct Pallets');
    expect(allPalletIds, containsAll(['PL-01', 'PL-02']));
    expect(allPalletEpcs.length, equals(2), reason: 'Must have 2 distinct Pallet EPCs');
    expect(allPalletEpcs, containsAll([
      'AB2600100000000000000201',
      'AB2600100000000000000202',
    ]));

    // 3. Kiểm tra 40 mã EPC sản phẩm riêng biệt 100%
    expect(totalSerials, equals(40));
    expect(allItemEpcs.length, equals(40));
  });
}
