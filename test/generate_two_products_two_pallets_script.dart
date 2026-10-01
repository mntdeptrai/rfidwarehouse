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

  // 2 LOẠI HÀNG HÓA & 2 PALLET
  final productBatches = [
    // LOẠI HÀNG 1 - XẾP TRÊN PALLET 1 (PL-01)
    {
      'productName': 'Áo Polo Nam Thể Thao RFID Coolmax',
      'sku': 'SKU-POLO-COOLMAX-01',
      'supplier': 'Tổng Công Ty May Việt Tiến',
      'palletBarcode': 'PL-01',
      'palletEpc': 'AB2600100000000000000201',
      'cartonPrefix': 'CARTON-POLO',
      'epcPrefix': 'E280689400005024B076',
      'cartons': 2,
      'itemsPerCarton': 10,
    },
    // LOẠI HÀNG 2 - XẾP TRÊN PALLET 2 (PL-02)
    {
      'productName': 'Quần Short Thể Thao RFID Co Giãn',
      'sku': 'SKU-SHORT-FLEX-02',
      'supplier': 'Tổng Công Ty May Việt Tiến',
      'palletBarcode': 'PL-02',
      'palletEpc': 'AB2600100000000000000202',
      'cartonPrefix': 'CARTON-SHORT',
      'epcPrefix': 'E280689400005024C088',
      'cartons': 2,
      'itemsPerCarton': 10,
    },
  ];

  int currentRow = 1;

  for (final batch in productBatches) {
    final productName = batch['productName'] as String;
    final sku = batch['sku'] as String;
    final supplier = batch['supplier'] as String;
    final palletBarcode = batch['palletBarcode'] as String;
    final palletEpc = batch['palletEpc'] as String;
    final cartonPrefix = batch['cartonPrefix'] as String;
    final epcPrefix = batch['epcPrefix'] as String;
    final cartons = batch['cartons'] as int;
    final itemsPerCarton = batch['itemsPerCarton'] as int;

    int itemIndexInBatch = 1;
    for (int c = 1; c <= cartons; c++) {
      final cartonCode = '$cartonPrefix-${c.toString().padLeft(3, '0')}';
      for (int i = 1; i <= itemsPerCarton; i++) {
        final epc = '$epcPrefix${itemIndexInBatch.toString().padLeft(4, '0')}';

        final c0 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: currentRow));
        c0.value = TextCellValue(cartonCode);
        c0.cellStyle = codeStyle;

        final c1 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: rowIndexToRow(currentRow)));
        c1.value = TextCellValue(epc);
        c1.cellStyle = codeStyle;

        final c2 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: currentRow));
        c2.value = TextCellValue(productName);
        c2.cellStyle = textStyle;

        final c3 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: currentRow));
        c3.value = TextCellValue(sku);
        c3.cellStyle = codeStyle;

        final c4 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: currentRow));
        c4.value = TextCellValue(supplier);
        c4.cellStyle = textStyle;

        final c5 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: currentRow));
        c5.value = TextCellValue(palletBarcode);
        c5.cellStyle = codeStyle;

        final c6 = sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: currentRow));
        c6.value = TextCellValue(palletEpc);
        c6.cellStyle = codeStyle;

        currentRow++;
        itemIndexInBatch++;
      }
    }
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
    'Mau_Nhap_Hang_2_Loai_Hang_2_Pallet_Nhieu_EPC.xlsx',
    r'c:\Users\MNT\Documents\uhf\Mau_Nhap_Hang_2_Loai_Hang_2_Pallet_Nhieu_EPC.xlsx',
    r'c:\Users\MNT\Documents\WMS_Reports\Mau_Nhap_Hang_2_Loai_Hang_2_Pallet_Nhieu_EPC.xlsx',
    r'c:\Users\MNT\Downloads\Mau_Nhap_Hang_2_Loai_Hang_2_Pallet_Nhieu_EPC.xlsx',
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
  print('Done! Total rows: ${currentRow - 1} items generated across 2 products and 2 pallets.');
}

int rowIndexToRow(int r) => r;
