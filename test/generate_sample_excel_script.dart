// ignore_for_file: avoid_print
import 'dart:io';
import 'dart:typed_data';
import 'package:excel/excel.dart';

void main() async {
  final excel = Excel.createExcel();
  final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
  excel.rename(defaultSheet, 'Goods_Receive');
  final sheet = excel['Goods_Receive'];

  // Cấu trúc 7 cột chuẩn của WMS
  final headers = [
    'CARTON CODE',
    'EPC',
    'NAME',
    'SKU',
    'NCC',
    'BARCODE PALET',
    'EPC PALLET',
  ];

  // Header style
  final headerStyle = CellStyle(
    bold: true,
    fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
    backgroundColorHex: ExcelColor.fromHexString('#0F766E'), // Emerald/Teal đậm
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );

  final codeStyle = CellStyle(
    fontColorHex: ExcelColor.fromHexString('#0F172A'),
    horizontalAlign: HorizontalAlign.Center,
    verticalAlign: VerticalAlign.Center,
  );

  final textStyle = CellStyle(
    fontColorHex: ExcelColor.fromHexString('#1E293B'),
    horizontalAlign: HorizontalAlign.Left,
    verticalAlign: VerticalAlign.Center,
  );

  // Ghi Headers
  for (int c = 0; c < headers.length; c++) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: 0));
    cell.value = TextCellValue(headers[c]);
    cell.cellStyle = headerStyle;
  }

  // Thông tin sản phẩm CÙNG LOẠI
  const productName = 'Áo Polo Nam Thể Thao RFID Coolmax';
  const sku = 'SKU-POLO-COOLMAX-01';
  const supplier = 'Tổng Công Ty May Việt Tiến';

  // 60 sản phẩm, chia đều 6 thùng (10 sp/thùng), phân bố trên 3 Pallet (2 thùng/pallet)
  const totalItems = 60;
  const itemsPerCarton = 10;
  const cartonsPerPallet = 2;

  // Danh sách các Pallet kèm mã RFID EPC Pallet riêng biệt
  final palletConfigs = [
    {'barcode': 'PL-01', 'epc': 'AB2600100000000000000201'},
    {'barcode': 'PL-02', 'epc': 'AB2600100000000000000202'},
    {'barcode': 'PL-03', 'epc': 'AB2600100000000000000203'},
  ];

  for (int i = 1; i <= totalItems; i++) {
    final cartonNum = ((i - 1) ~/ itemsPerCarton) + 1;
    final cartonCode = 'CARTON-POLO-${cartonNum.toString().padLeft(3, '0')}';

    // Xác định Pallet tương ứng (cứ 2 thùng xếp lên 1 Pallet riêng biệt)
    final palletIndex = (cartonNum - 1) ~/ cartonsPerPallet;
    final palletConfig = palletConfigs[palletIndex % palletConfigs.length];
    final palletBarcode = palletConfig['barcode']!;
    final palletEpc = palletConfig['epc']!;

    // Mã chip RFID UHF EPC duy nhất khác nhau cho từng sản phẩm
    final epc = 'E280689400005024B076${i.toString().padLeft(4, '0')}';
    final rowIndex = i;

    // Ghi từng cột
    final c0 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: rowIndex));
    c0.value = TextCellValue(cartonCode);
    c0.cellStyle = codeStyle;

    final c1 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndex));
    c1.value = TextCellValue(epc);
    c1.cellStyle = codeStyle;

    final c2 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: rowIndex));
    c2.value = TextCellValue(productName);
    c2.cellStyle = textStyle;

    final c3 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: rowIndex));
    c3.value = TextCellValue(sku);
    c3.cellStyle = codeStyle;

    final c4 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: rowIndex));
    c4.value = TextCellValue(supplier);
    c4.cellStyle = textStyle;

    final c5 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: rowIndex));
    c5.value = TextCellValue(palletBarcode);
    c5.cellStyle = codeStyle;

    final c6 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: rowIndex));
    c6.value = TextCellValue(palletEpc);
    c6.cellStyle = codeStyle;
  }

  // Đặt độ rộng các cột
  sheet.setColumnWidth(0, 22.0); // CARTON CODE
  sheet.setColumnWidth(1, 34.0); // EPC
  sheet.setColumnWidth(2, 42.0); // NAME
  sheet.setColumnWidth(3, 24.0); // SKU
  sheet.setColumnWidth(4, 34.0); // NCC
  sheet.setColumnWidth(5, 20.0); // BARCODE PALET
  sheet.setColumnWidth(6, 32.0); // EPC PALLET

  final bytes = Uint8List.fromList(excel.encode() ?? []);
  if (bytes.isEmpty) {
    print('Error: Failed to encode excel');
    exit(1);
  }

  final targetPaths = [
    'Mau_Nhap_Hang_Cung_Loai_Nhieu_EPC.xlsx',
    r'c:\Users\MNT\Documents\uhf\Mau_Nhap_Hang_Cung_Loai_Nhieu_EPC.xlsx',
    r'c:\Users\MNT\Documents\WMS_Reports\Mau_Nhap_Hang_Cung_Loai_Nhieu_EPC.xlsx',
    r'c:\Users\MNT\Documents\uhf\Mau_Nhap_Hang_Cung_Loai_Nhieu_Pallet_Nhieu_EPC.xlsx',
    r'c:\Users\MNT\Documents\WMS_Reports\Mau_Nhap_Hang_Cung_Loai_Nhieu_Pallet_Nhieu_EPC.xlsx',
    r'c:\Users\MNT\Downloads\Mau_Nhap_Hang_Cung_Loai_Nhieu_Pallet_Nhieu_EPC.xlsx',
  ];

  for (final path in targetPaths) {
    try {
      final file = File(path);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes);
      print('Saved: ${file.absolute.path}');
    } catch (e) {
      print('Warning saving to $path: $e');
    }
  }
  print('Done! Total rows: $totalItems items generated.');
}
