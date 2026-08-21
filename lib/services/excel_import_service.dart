import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';

class ExcelImportResult {
  final String fileName;
  final int totalRows;
  final int totalCartons;
  final int totalSerials;
  final List<Map<String, dynamic>> cartons;

  ExcelImportResult({
    required this.fileName,
    required this.totalRows,
    required this.totalCartons,
    required this.totalSerials,
    required this.cartons,
  });
}

class ExcelImportService {
  static final ExcelImportService _instance = ExcelImportService._internal();
  factory ExcelImportService() => _instance;
  ExcelImportService._internal();

  String _cellToString(dynamic val) {
    if (val == null) return '';
    if (val is TextCellValue) {
      return val.value.text ?? '';
    }
    if (val is IntCellValue) {
      return val.value.toString();
    }
    if (val is DoubleCellValue) {
      if (val.value == val.value.toInt()) {
        return val.value.toInt().toString();
      }
      return val.value.toString();
    }
    if (val is BoolCellValue) {
      return val.value.toString();
    }
    if (val is DateTimeCellValue) {
      return '${val.year}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')}';
    }
    if (val is DateCellValue) {
      return '${val.year}-${val.month.toString().padLeft(2, '0')}-${val.day.toString().padLeft(2, '0')}';
    }
    // Fallback
    final str = val.toString().trim();
    if (str.startsWith('TextCellValue(')) {
      final match = RegExp(r'text:\s*([^,\)]+)').firstMatch(str);
      if (match != null) return match.group(1)?.trim() ?? str;
    }
    return str;
  }

  /// Mở hộp thoại chọn file Excel/CSV và parse danh sách Thùng hàng + Serial/EPC
  /// Cấu trúc chuẩn 4 cột: CARTON CODE, SERIAL/EPC, BARCODE/SKU, NAME
  Future<ExcelImportResult?> pickAndParseGoodsReceiveExcel() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (files.isEmpty) {
        return null; // Người dùng hủy chọn
      }

      final file = files.first;
      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        throw Exception('Không thể đọc nội dung tệp đã chọn hoặc tệp rỗng.');
      }

      final isCsv = file.name.toLowerCase().endsWith('.csv');
      final List<Map<String, dynamic>> cartons;
      int rawRowsCount = 0;

      if (isCsv) {
        final parsed = _parseGoodsReceiveCsv(bytes);
        cartons = parsed.$1;
        rawRowsCount = parsed.$2;
      } else {
        final parsed = _parseGoodsReceiveXlsx(bytes);
        cartons = parsed.$1;
        rawRowsCount = parsed.$2;
      }

      int totalSerials = 0;
      for (final c in cartons) {
        final list = (c['serials'] as List<dynamic>?) ?? [];
        totalSerials += list.length;
      }

      return ExcelImportResult(
        fileName: file.name,
        totalRows: rawRowsCount,
        totalCartons: cartons.length,
        totalSerials: totalSerials,
        cartons: cartons,
      );
    } catch (e) {
      debugPrint('ExcelImportService error: $e');
      rethrow;
    }
  }

  (List<Map<String, dynamic>>, int) _parseGoodsReceiveXlsx(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) {
      throw Exception('Tệp Excel rỗng hoặc không có bảng dữ liệu.');
    }

    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;
    final rows = sheet.rows;

    if (rows.isEmpty) {
      throw Exception('Sheet "$sheetName" không có dữ liệu.');
    }

    int cartonCol = 0;
    int serialCol = 1;
    int barcodeCol = 2;
    int nameCol = 3;
    int startRow = 0;

    // Kiểm tra dòng tiêu đề
    final firstRow = rows.first;
    final headers = firstRow.map((c) => _cellToString(c?.value).toLowerCase()).toList();

    bool hasHeader = false;
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (h.contains('carton') || h.contains('thung') || h.contains('thùng') || h.contains('box') || h.contains('pallet')) {
        cartonCol = i;
        hasHeader = true;
      } else if (h.contains('serial') || h.contains('epc') || h.contains('chip')) {
        serialCol = i;
        hasHeader = true;
      } else if (h.contains('barcode') || h.contains('sku') || h.contains('mã sp') || h.contains('mã hàng') || h.contains('code')) {
        barcodeCol = i;
        hasHeader = true;
      } else if (h.contains('name') || h.contains('tên') || h.contains('ten') || h.contains('product')) {
        nameCol = i;
        hasHeader = true;
      }
    }

    if (hasHeader) {
      startRow = 1;
    }

    final Map<String, Map<String, dynamic>> cartonMap = {};
    int validDataRows = 0;

    for (int r = startRow; r < rows.length; r++) {
      final row = rows[r];
      if (row.isEmpty) continue;

      final carton = cartonCol < row.length ? _cellToString(row[cartonCol]?.value).trim() : '';
      final serial = serialCol < row.length ? _cellToString(row[serialCol]?.value).trim() : '';
      final barcode = barcodeCol < row.length ? _cellToString(row[barcodeCol]?.value).trim() : '';
      final name = nameCol < row.length ? _cellToString(row[nameCol]?.value).trim() : '';

      if (carton.isEmpty && serial.isEmpty && barcode.isEmpty && name.isEmpty) {
        continue;
      }

      validDataRows++;

      final effectiveCarton = carton.isNotEmpty ? carton : 'CARTON-DEFAULT';
      final effectiveBarcode = barcode.isNotEmpty ? barcode : (serial.isNotEmpty ? 'SKU-${serial.substring(0, (serial.length > 8 ? 8 : serial.length))}' : 'SKU-001');
      final effectiveName = name.isNotEmpty ? name : 'Sản phẩm $effectiveBarcode';

      final groupKey = '$effectiveCarton||$effectiveBarcode';

      if (!cartonMap.containsKey(groupKey)) {
        cartonMap[groupKey] = {
          'cartonBox': effectiveCarton,
          'productCode': effectiveBarcode,
          'productName': effectiveName,
          'quantity': 0,
          'serials': <String>[],
          'serialItems': <Map<String, dynamic>>[],
        };
      }

      final entry = cartonMap[groupKey]!;
      if (serial.isNotEmpty) {
        final serialsList = entry['serials'] as List<String>;
        if (!serialsList.contains(serial)) {
          serialsList.add(serial);
          entry['quantity'] = serialsList.length;
          (entry['serialItems'] as List<Map<String, dynamic>>).add({
            'serial': serial,
            'barcode': effectiveBarcode,
            'name': effectiveName,
            'carton': effectiveCarton,
          });
        }
      } else {
        entry['quantity'] = (entry['quantity'] as int) + 1;
      }
    }

    if (cartonMap.isEmpty) {
      throw Exception('Không tìm thấy dòng dữ liệu hợp lệ nào trong file Excel.');
    }

    return (cartonMap.values.toList(), validDataRows);
  }

  (List<Map<String, dynamic>>, int) _parseGoodsReceiveCsv(Uint8List bytes) {
    final content = String.fromCharCodes(bytes);
    final lines = content.split(RegExp(r'\r\n|\n|\r'));
    if (lines.isEmpty) {
      throw Exception('Tệp CSV rỗng.');
    }

    int cartonCol = 0;
    int serialCol = 1;
    int barcodeCol = 2;
    int nameCol = 3;
    int startRow = 0;

    final firstLine = lines.first.split(RegExp(r',|\t|;'));
    final headers = firstLine.map((c) => c.trim().toLowerCase()).toList();

    bool hasHeader = false;
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (h.contains('carton') || h.contains('thung') || h.contains('thùng') || h.contains('box') || h.contains('pallet')) {
        cartonCol = i;
        hasHeader = true;
      } else if (h.contains('serial') || h.contains('epc') || h.contains('chip')) {
        serialCol = i;
        hasHeader = true;
      } else if (h.contains('barcode') || h.contains('sku') || h.contains('mã sp') || h.contains('mã hàng') || h.contains('code')) {
        barcodeCol = i;
        hasHeader = true;
      } else if (h.contains('name') || h.contains('tên') || h.contains('ten') || h.contains('product')) {
        nameCol = i;
        hasHeader = true;
      }
    }

    if (hasHeader) {
      startRow = 1;
    }

    final Map<String, Map<String, dynamic>> cartonMap = {};
    int validDataRows = 0;

    for (int r = startRow; r < lines.length; r++) {
      final line = lines[r].trim();
      if (line.isEmpty) continue;

      final cols = line.split(RegExp(r',|\t|;')).map((s) => s.trim().replaceAll('"', '')).toList();
      final carton = cartonCol < cols.length ? cols[cartonCol] : '';
      final serial = serialCol < cols.length ? cols[serialCol] : '';
      final barcode = barcodeCol < cols.length ? cols[barcodeCol] : '';
      final name = nameCol < cols.length ? cols[nameCol] : '';

      if (carton.isEmpty && serial.isEmpty && barcode.isEmpty && name.isEmpty) continue;

      validDataRows++;

      final effectiveCarton = carton.isNotEmpty ? carton : 'CARTON-DEFAULT';
      final effectiveBarcode = barcode.isNotEmpty ? barcode : (serial.isNotEmpty ? 'SKU-${serial.substring(0, (serial.length > 8 ? 8 : serial.length))}' : 'SKU-001');
      final effectiveName = name.isNotEmpty ? name : 'Sản phẩm $effectiveBarcode';

      final groupKey = '$effectiveCarton||$effectiveBarcode';

      if (!cartonMap.containsKey(groupKey)) {
        cartonMap[groupKey] = {
          'cartonBox': effectiveCarton,
          'productCode': effectiveBarcode,
          'productName': effectiveName,
          'quantity': 0,
          'serials': <String>[],
          'serialItems': <Map<String, dynamic>>[],
        };
      }

      final entry = cartonMap[groupKey]!;
      if (serial.isNotEmpty) {
        final serialsList = entry['serials'] as List<String>;
        if (!serialsList.contains(serial)) {
          serialsList.add(serial);
          entry['quantity'] = serialsList.length;
          (entry['serialItems'] as List<Map<String, dynamic>>).add({
            'serial': serial,
            'barcode': effectiveBarcode,
            'name': effectiveName,
            'carton': effectiveCarton,
          });
        }
      } else {
        entry['quantity'] = (entry['quantity'] as int) + 1;
      }
    }

    if (cartonMap.isEmpty) {
      throw Exception('Không tìm thấy dòng dữ liệu hợp lệ nào trong file CSV.');
    }

    return (cartonMap.values.toList(), validDataRows);
  }

  /// Mở hộp thoại chọn file Excel và parse danh sách nhiều Đơn Nhập Hàng (PO)
  /// Cột: ORDER NO, SUPPLIER, SKU, PRODUCT NAME, QUANTITY
  Future<List<Map<String, dynamic>>?> pickAndParseBatchOrdersExcel() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (files.isEmpty) return null;

      final file = files.first;
      final bytes = await file.readAsBytes();

      if (bytes.isEmpty) {
        throw Exception('Không thể đọc nội dung tệp.');
      }

      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) throw Exception('Tệp Excel rỗng.');

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName]!;
      final rows = sheet.rows;
      if (rows.isEmpty) throw Exception('Sheet "$sheetName" không có dữ liệu.');

      int? orderNoCol;
      int? epcCol;
      int? supplierCol;
      int? skuCol;
      int? nameCol;
      int? qtyCol;
      int startRow = 0;

      final firstRow = rows.first;
      final headers = firstRow.map((c) => _cellToString(c?.value).toLowerCase()).toList();
      bool hasHeader = false;

      for (int i = 0; i < headers.length; i++) {
        final h = headers[i];
        if (h.contains('carton') || h.contains('order') || h.contains('đơn') || h.contains('po') || h.contains('phiếu') || h.contains('thung') || h.contains('thùng') || h.contains('box') || h.contains('pallet')) {
          orderNoCol = i;
          hasHeader = true;
        } else if (h.contains('epc') || h.contains('serial') || h.contains('chip') || h.contains('rfid') || h.contains('tag')) {
          epcCol = i;
          hasHeader = true;
        } else if (h.contains('supplier') || h.contains('ncc') || h.contains('nhà cung cấp')) {
          supplierCol = i;
          hasHeader = true;
        } else if (h.contains('sku') || h.contains('mã sp') || h.contains('mã hàng') || h.contains('barcode') || h.contains('code')) {
          skuCol = i;
          hasHeader = true;
        } else if (h.contains('name') || h.contains('tên') || h.contains('ten') || h.contains('sản phẩm') || h.contains('product')) {
          nameCol = i;
          hasHeader = true;
        } else if (h.contains('quantity') || h.contains('qty') || h.contains('số lượng') || h.contains('sl')) {
          qtyCol = i;
          hasHeader = true;
        }
      }

      if (hasHeader) startRow = 1;

      // Default fallback
      orderNoCol ??= 0;
      if (epcCol == null && supplierCol == null) {
        if (headers.length == 4) {
          epcCol = 1;
          skuCol ??= 2;
          nameCol ??= 3;
        } else {
          supplierCol = 1;
          skuCol ??= 2;
          nameCol ??= 3;
          qtyCol ??= 4;
        }
      } else {
        skuCol ??= 2;
        nameCol ??= 3;
      }

      final List<Map<String, dynamic>> parsedRows = [];

      for (int r = startRow; r < rows.length; r++) {
        final row = rows[r];
        if (row.isEmpty) continue;

        final orderNo = orderNoCol < row.length ? _cellToString(row[orderNoCol]?.value).trim() : '';
        final epc = (epcCol != null && epcCol < row.length) ? _cellToString(row[epcCol]?.value).trim() : '';
        final supplier = (supplierCol != null && supplierCol < row.length) ? _cellToString(row[supplierCol]?.value).trim() : '';
        final sku = skuCol < row.length ? _cellToString(row[skuCol]?.value).trim() : '';
        final name = nameCol < row.length ? _cellToString(row[nameCol]?.value).trim() : '';
        final qtyStr = (qtyCol != null && qtyCol < row.length) ? _cellToString(row[qtyCol]?.value).trim() : '1';

        if (orderNo.isEmpty && sku.isEmpty && name.isEmpty && epc.isEmpty) continue;

        final qty = int.tryParse(qtyStr) ?? 1;

        parsedRows.add({
          'orderNo': orderNo.isNotEmpty ? orderNo : 'CARTON-DEFAULT',
          'supplier': supplier.isNotEmpty ? supplier : (epc.isNotEmpty ? 'Nhà cung cấp' : 'Nhà Cung Cấp Mặc Định'),
          'sku': sku.isNotEmpty ? sku : (epc.isNotEmpty ? 'SKU-${epc.substring(0, (epc.length > 8 ? 8 : epc.length))}' : 'SKU-${parsedRows.length + 1}'),
          'productName': name.isNotEmpty ? name : (sku.isNotEmpty ? 'Sản phẩm $sku' : 'Sản phẩm ${parsedRows.length + 1}'),
          'quantity': qty > 0 ? qty : 1,
          'epc': epc, // Gán trực tiếp mã EPC từ cột 2 của Excel
        });
      }

      if (parsedRows.isEmpty) {
        throw Exception('Không tìm thấy dòng đơn hàng hợp lệ nào trong file.');
      }

      return parsedRows;
    } catch (e) {
      debugPrint('ExcelImportService Batch error: $e');
      rethrow;
    }
  }

  /// Xuất file Excel mẫu chuẩn 4 cột: Template-Goods-Receive.xlsx
  Future<String> exportGoodsReceiveTemplate() async {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];

    final headers = ['CARTON CODE', 'EPC', 'BARCODE', 'NAME'];
    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headers[col]);
    }

    // Sample Data
    final sampleData = [
      ['CARTONTEST0001', 'ABCDEF000000000000000001', '8930000000001', 'Product Test 01'],
      ['CARTONTEST0001', 'ABCDEF000000000000000002', '8930000000001', 'Product Test 02'],
      ['CARTONTEST0001', 'ABCDEF000000000000000003', '8930000000001', 'Product Test 03'],
      ['CARTONTEST0001', 'ABCDEF000000000000000004', '8930000000001', 'Product Test 04'],
      ['CARTONTEST0001', 'ABCDEF000000000000000005', '8930000000001', 'Product Test 05'],
      ['CARTONTEST0002', 'ABCDEF000000000000000011', '8930000000002', 'Product Test 11'],
      ['CARTONTEST0002', 'ABCDEF000000000000000012', '8930000000002', 'Product Test 12'],
      ['CARTONTEST0002', 'ABCDEF000000000000000013', '8930000000002', 'Product Test 13'],
      ['CARTONTEST0002', 'ABCDEF000000000000000014', '8930000000002', 'Product Test 14'],
      ['CARTONTEST0002', 'ABCDEF000000000000000015', '8930000000002', 'Product Test 15'],
    ];

    for (int r = 0; r < sampleData.length; r++) {
      final rowData = sampleData[r];
      for (int c = 0; c < rowData.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
        cell.value = TextCellValue(rowData[c]);
      }
    }

    final bytes = Uint8List.fromList(excel.encode() ?? []);
    if (bytes.isEmpty) throw Exception('Không thể tạo file Excel.');

    String? savePath;
    try {
      final savedUri = await FilePicker.saveFile(
        fileName: 'Template-Goods-Receive.xlsx',
        bytes: bytes,
      );
      if (savedUri != null) {
        savePath = savedUri.toFilePath();
      }
    } catch (e) {
      debugPrint('Save file via picker failed, fallback to direct path: $e');
    }

    if (savePath == null || savePath.isEmpty) {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      savePath = '${dir.path}${Platform.pathSeparator}Template-Goods-Receive.xlsx';
      final file = File(savePath);
      await file.writeAsBytes(bytes);
    }

    return savePath;
  }

  /// Xuất file Excel mẫu danh sách nhiều đơn hàng PO: Template-Batch-Orders.xlsx
  Future<String> exportBatchOrdersTemplate() async {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];

    final headers = ['ORDER NO', 'SUPPLIER', 'SKU', 'PRODUCT NAME', 'QUANTITY'];
    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headers[col]);
    }

    final sampleData = [
      ['PO-2026-001', 'Samsung Electronics VN', 'SKU-ELEC-01', 'Bo mạch IoT RFID', '50'],
      ['PO-2026-001', 'Samsung Electronics VN', 'SKU-ELEC-02', 'Cảm biến nhiệt độ RFID', '30'],
      ['PO-2026-002', 'May Mặc Việt Tiến', 'SKU-TEXT-01', 'Áo Sơ Mi Nam Công Sở', '100'],
      ['PO-2026-003', 'Dược phẩm Sanofi', 'SKU-PHARM-01', 'Hộp Thuốc Kháng Sinh', '70'],
    ];

    for (int r = 0; r < sampleData.length; r++) {
      final rowData = sampleData[r];
      for (int c = 0; c < rowData.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
        cell.value = TextCellValue(rowData[c]);
      }
    }

    final bytes = Uint8List.fromList(excel.encode() ?? []);
    if (bytes.isEmpty) throw Exception('Không thể tạo file Excel.');

    String? savePath;
    try {
      final savedUri = await FilePicker.saveFile(
        fileName: 'Template-Batch-Orders.xlsx',
        bytes: bytes,
      );
      if (savedUri != null) {
        savePath = savedUri.toFilePath();
      }
    } catch (e) {
      debugPrint('Save batch template failed, fallback: $e');
    }

    if (savePath == null || savePath.isEmpty) {
      final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
      savePath = '${dir.path}${Platform.pathSeparator}Template-Batch-Orders.xlsx';
      final file = File(savePath);
      await file.writeAsBytes(bytes);
    }

    return savePath;
  }
}
