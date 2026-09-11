import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'warehouse_repository.dart';

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
  /// Cấu trúc chuẩn: CARTON CODE, SERIAL/EPC, NAME (hoặc BARCODE)
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

  String _normalizeHeader(String input) {
    String s = input.trim().toLowerCase();
    const map = {
      'á': 'a', 'à': 'a', 'ả': 'a', 'ã': 'a', 'ạ': 'a',
      'ă': 'a', 'ắ': 'a', 'ằ': 'a', 'ẳ': 'a', 'ẵ': 'a', 'ặ': 'a',
      'â': 'a', 'ấ': 'a', 'ầ': 'a', 'ẩ': 'a', 'ẫ': 'a', 'ậ': 'a',
      'é': 'e', 'è': 'e', 'ẻ': 'e', 'ẽ': 'e', 'ẹ': 'e',
      'ê': 'e', 'ế': 'e', 'ề': 'e', 'ể': 'e', 'ễ': 'e', 'ệ': 'e',
      'í': 'i', 'ì': 'i', 'ỉ': 'i', 'ĩ': 'i', 'ị': 'i',
      'ó': 'o', 'ò': 'o', 'ỏ': 'o', 'õ': 'o', 'ọ': 'o',
      'ô': 'o', 'ố': 'o', 'ồ': 'o', 'ổ': 'o', 'ỗ': 'o', 'ộ': 'o',
      'ơ': 'o', 'ớ': 'o', 'ờ': 'o', 'ở': 'o', 'ỡ': 'o', 'ợ': 'o',
      'ú': 'u', 'ù': 'u', 'ủ': 'u', 'ũ': 'u', 'ụ': 'u',
      'ư': 'u', 'ứ': 'u', 'ừ': 'u', 'ử': 'u', 'ữ': 'u', 'ự': 'u',
      'ý': 'y', 'ỳ': 'y', 'ỷ': 'y', 'ỹ': 'y', 'ỵ': 'y',
      'đ': 'd',
    };
    final buffer = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      final char = s[i];
      buffer.write(map[char] ?? char);
    }
    return buffer.toString();
  }

  (List<Map<String, dynamic>>, int) parseBytes(Uint8List bytes, {bool isCsv = false}) {
    return isCsv ? _parseGoodsReceiveCsv(bytes) : _parseGoodsReceiveXlsx(bytes);
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

    final List<List<String>> rawGrid = [];
    for (final row in rows) {
      rawGrid.add(row.map((c) => _cellToString(c?.value)).toList());
    }

    return _processRawRows(rawGrid);
  }

  (List<Map<String, dynamic>>, int) _parseGoodsReceiveCsv(Uint8List bytes) {
    String content;
    try {
      content = utf8.decode(bytes);
    } catch (_) {
      content = String.fromCharCodes(bytes);
    }
    final lines = content.split(RegExp(r'\r\n|\n|\r'));
    if (lines.isEmpty) {
      throw Exception('Tệp CSV rỗng.');
    }

    final List<List<String>> rawGrid = [];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      rawGrid.add(line.split(RegExp(r',|\t|;')).map((c) => c.trim()).toList());
    }

    return _processRawRows(rawGrid);
  }

  (List<Map<String, dynamic>>, int) _processRawRows(List<List<String>> rawGrid) {
    if (rawGrid.isEmpty) {
      throw Exception('Không có dữ liệu trong tệp.');
    }

    int? cartonCol;
    int? palletCol;
    int? palletEpcCol;
    int? serialCol;
    int? barcodeCol;
    int? nameCol;
    int? supplierCol;
    int startRow = 0;

    final firstRow = rawGrid.first;
    final headers = firstRow.map((c) => _normalizeHeader(c)).toList();

    bool hasHeader = false;
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (h.isEmpty) continue;

      final isPalletHeader = h.contains('pallet') || h.contains('palet');
      final isEpcOrRfid = h.contains('epc') ||
          h.contains('rfid') ||
          h.contains('serial') ||
          h.contains('chip') ||
          h.contains('ma the') ||
          h.contains('tag') ||
          h.contains('tid');

      // 1. Cột Thẻ RFID / EPC của xe Pallet (Ví dụ: EPC PALLET, EPC PALET, RFID PALLET, CHIP PALLET, TAG PALET)
      if (isPalletHeader && isEpcOrRfid) {
        palletEpcCol = i;
        hasHeader = true;
      }
      // 2. Cột Mã xe / Barcode Pallet (Ví dụ: BARCODE PALET, BARCODE PALLET, MA PALLET, MA PALET, PALLET, PALET)
      else if (isPalletHeader) {
        palletCol = i;
        hasHeader = true;
      }
      // 3. Cột mã Thẻ RFID / EPC / Chip / Serial của SẢN PHẨM (không phải của Pallet)
      else if (isEpcOrRfid) {
        serialCol = i;
        hasHeader = true;
      }
      // 4. Cột Thùng hàng / Kiện / Box / Hộp (không phải Pallet)
      else if (h.contains('carton') ||
          h.contains('thung') ||
          h.contains('box') ||
          h.contains('kien') ||
          h.contains('hop')) {
        cartonCol = i;
        hasHeader = true;
      }
      // 5. Cột Mã sản phẩm / SKU / Barcode / Mã hàng (không phải Pallet)
      else if (h.contains('barcode') ||
          h.contains('sku') ||
          h.contains('ma sp') ||
          h.contains('ma san pham') ||
          h.contains('ma hang') ||
          h.contains('ma vt') ||
          h.contains('ma vach') ||
          h.contains('item code') ||
          h.contains('product code') ||
          (h.startsWith('ma') && !h.contains('the') && !h.contains('chip'))) {
        barcodeCol = i;
        hasHeader = true;
      }
      // 6. Cột Tên sản phẩm / Tên hàng
      else if (h.contains('ten') ||
          h.contains('name') ||
          h.contains('mo ta') ||
          h.contains('dien giai') ||
          h.contains('description') ||
          (h.contains('san pham') && !h.contains('ma')) ||
          (h.contains('product') && !h.contains('code'))) {
        nameCol = i;
        hasHeader = true;
      }
      // 7. Cột Nhà cung cấp / Supplier / NCC / Vendor
      else if (h.contains('supplier') ||
          h.contains('ncc') ||
          h.contains('nha cung cap') ||
          h.contains('nhà cung cấp') ||
          h.contains('vendor')) {
        supplierCol = i;
        hasHeader = true;
      }
    }

    // Nếu file có cột Pallet và cột RFID/EPC nhưng cột RFID chưa có chữ 'pallet' (Ví dụ: cột 1 là "Pallet", cột 2 là "RFID")
    if (palletCol != null && palletEpcCol == null && serialCol != null) {
      palletEpcCol = serialCol;
      serialCol = null;
    }

    if (hasHeader) {
      startRow = 1;
    } else {
      // Tự động suy luận cột nếu không có tiêu đề
      for (int i = 0; i < firstRow.length; i++) {
        final val = firstRow[i].trim();
        if (RegExp(r'^[0-9A-Fa-f]{16,32}$').hasMatch(val) || val.toUpperCase().startsWith('E280')) {
          serialCol ??= i;
        }
      }
      serialCol ??= (firstRow.length > 1 ? 1 : 0);
      nameCol ??= (firstRow.length > 2 ? 2 : (serialCol == 0 ? 1 : 0));
    }

    // Default fallback cho serialCol và nameCol nếu chưa khớp
    if (serialCol == null) {
      if (palletCol != null && palletEpcCol != null) {
        // File chỉ tập trung vào Pallet + RFID Pallet (không có cột serial riêng)
        // Tìm xem có cột nào khác làm serial hay không
        for (int i = 0; i < headers.length; i++) {
          if (i != palletCol && i != palletEpcCol && i != cartonCol && i != barcodeCol && i != nameCol) {
            serialCol = i;
            break;
          }
        }
      } else {
        if (headers.length >= 3) {
          serialCol = 1;
          nameCol ??= 2;
        } else if (headers.length == 2) {
          serialCol = 0;
          nameCol ??= 1;
        } else {
          serialCol = 0;
        }
      }
    }
    nameCol ??= (serialCol == 1 ? 2 : 1);

    final Map<String, Map<String, dynamic>> cartonMap = {};
    final Map<String, String> nameToBarcodeMap = {};
    int validDataRows = 0;

    for (int r = startRow; r < rawGrid.length; r++) {
      final row = rawGrid[r];
      if (row.isEmpty) continue;

      final carton = (cartonCol != null && cartonCol < row.length) ? row[cartonCol].trim() : '';
      final pallet = (palletCol != null && palletCol < row.length) ? row[palletCol].trim() : '';
      final palletEpc = (palletEpcCol != null && palletEpcCol < row.length) ? row[palletEpcCol].trim() : '';
      final serial = (serialCol != null && serialCol < row.length) ? row[serialCol].trim() : '';
      final barcode = (barcodeCol != null && barcodeCol < row.length) ? row[barcodeCol].trim() : '';
      final name = (nameCol < row.length) ? row[nameCol].trim() : '';
      final supplier = (supplierCol != null && supplierCol < row.length) ? row[supplierCol].trim() : '';

      if (carton.isEmpty && pallet.isEmpty && palletEpc.isEmpty && serial.isEmpty && barcode.isEmpty && name.isEmpty) {
        continue;
      }

      validDataRows++;

      final effectiveCarton = carton.isNotEmpty ? carton : (pallet.isNotEmpty ? pallet : 'KIỆN-CHUNG');
      final effectivePallet = pallet.isNotEmpty ? pallet : (palletEpc.isNotEmpty ? palletEpc : null);
      final effectivePalletEpc = palletEpc.isNotEmpty ? palletEpc : null;
      final effectiveName = name.isNotEmpty
          ? name
          : (serial.isNotEmpty ? 'Sản phẩm $serial' : (effectivePallet != null ? 'Pallet $effectivePallet' : 'Sản phẩm mới'));

      // Xác định SKU/Barcode riêng cho từng dòng sản phẩm
      String rowBarcode = barcode;
      if (rowBarcode.isEmpty) {
        if (nameToBarcodeMap.containsKey(effectiveName)) {
          rowBarcode = nameToBarcodeMap[effectiveName]!;
        } else {
          rowBarcode = WarehouseRepository().generateHexBarcode128();
          nameToBarcodeMap[effectiveName] = rowBarcode;
        }
      } else if (!RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(rowBarcode)) {
        rowBarcode = rowBarcode.toUpperCase();
      }

      // Đảm bảo không gộp chung 2 Pallet khác nhau vào cùng 1 key để tránh thất lạc Pallet
      final groupKey = (effectivePallet != null && effectivePallet.isNotEmpty)
          ? '$effectiveCarton-PL-$effectivePallet'
          : effectiveCarton;

      if (!cartonMap.containsKey(groupKey)) {
        cartonMap[groupKey] = {
          'cartonBox': effectiveCarton,
          'palletCode': effectivePallet,
          'palletId': effectivePallet,
          'palletEpc': effectivePalletEpc,
          'palletRfid': effectivePalletEpc,
          'productCode': rowBarcode,
          'productName': effectiveName,
          'supplier': supplier.isNotEmpty ? supplier : 'Nhà cung cấp tổng hợp',
          'quantity': 0,
          'serials': <String>[],
          'serialItems': <Map<String, dynamic>>[],
        };
      } else {
        if (supplier.isNotEmpty && cartonMap[groupKey]!['supplier'] == 'Nhà cung cấp tổng hợp') {
          cartonMap[groupKey]!['supplier'] = supplier;
        }
        if (cartonMap[groupKey]!['palletCode'] == null && effectivePallet != null) {
          cartonMap[groupKey]!['palletCode'] = effectivePallet;
          cartonMap[groupKey]!['palletId'] = effectivePallet;
        }
        if (cartonMap[groupKey]!['palletEpc'] == null && effectivePalletEpc != null) {
          cartonMap[groupKey]!['palletEpc'] = effectivePalletEpc;
          cartonMap[groupKey]!['palletRfid'] = effectivePalletEpc;
        }
      }

      final entry = cartonMap[groupKey]!;

      if (serial.isNotEmpty) {
        final serialsList = entry['serials'] as List<String>;
        if (!serialsList.contains(serial)) {
          serialsList.add(serial);
          entry['quantity'] = serialsList.length;
          (entry['serialItems'] as List<Map<String, dynamic>>).add({
            'serial': serial,
            'barcode': rowBarcode,
            'name': effectiveName,
            'carton': effectiveCarton,
            'pallet': effectivePallet,
            'palletId': effectivePallet,
            'palletEpc': effectivePalletEpc,
            'palletRfid': effectivePalletEpc,
            'supplier': supplier.isNotEmpty ? supplier : entry['supplier'],
          });
        }
      } else {
        entry['quantity'] = (entry['quantity'] as int) + 1;
        // Nếu dòng không có serial riêng lẻ (ví dụ chỉ có Pallet & RFID Pallet)
        // Vẫn ghi nhận vào serialItems để downstream nhận diện được pallet và chip
        final serialItemsList = entry['serialItems'] as List<Map<String, dynamic>>;
        final effectiveItemSerial = effectivePalletEpc ?? effectivePallet ?? 'PL-ITEM-$validDataRows';
        if (!serialItemsList.any((it) => it['serial'] == effectiveItemSerial)) {
          serialItemsList.add({
            'serial': effectiveItemSerial,
            'barcode': rowBarcode,
            'name': effectiveName,
            'carton': effectiveCarton,
            'pallet': effectivePallet,
            'palletId': effectivePallet,
            'palletEpc': effectivePalletEpc,
            'palletRfid': effectivePalletEpc,
            'supplier': supplier.isNotEmpty ? supplier : entry['supplier'],
          });
          final serialsList = entry['serials'] as List<String>;
          if (!serialsList.contains(effectiveItemSerial)) {
            serialsList.add(effectiveItemSerial);
          }
        }
      }
    }

    if (cartonMap.isEmpty) {
      throw Exception('Không tìm thấy dòng dữ liệu hợp lệ nào trong file.');
    }

    // Cập nhật tóm tắt productName và productCode cho từng thùng dựa trên tất cả các mặt hàng bên trong
    for (final entry in cartonMap.values) {
      final sItems = (entry['serialItems'] as List<Map<String, dynamic>>);
      if (sItems.isEmpty) continue;

      final nameCounts = <String, int>{};
      for (final it in sItems) {
        final pName = (it['name'] ?? '').toString().trim();
        if (pName.isNotEmpty) {
          nameCounts[pName] = (nameCounts[pName] ?? 0) + 1;
        }
      }

      if (nameCounts.length == 1) {
        entry['productName'] = nameCounts.keys.first;
      } else if (nameCounts.length > 1) {
        entry['productName'] = nameCounts.entries.map((e) => '${e.key} (${e.value})').join(' • ');
      }

      final uniqueSkus = sItems.map((e) => (e['barcode'] ?? '').toString().trim()).where((s) => s.isNotEmpty).toSet().toList();
      if (uniqueSkus.length == 1) {
        entry['productCode'] = uniqueSkus.first;
      } else if (uniqueSkus.length > 1) {
        entry['productCode'] = uniqueSkus.join(', ');
      }
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

  /// Xuất file Excel mẫu chuẩn 3 cột: Template-Goods-Receive.xlsx
  Future<String> exportGoodsReceiveTemplate() async {
    final excel = Excel.createExcel();
    final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
    final sheet = excel[sheetName];

    final headers = ['CARTON CODE', 'EPC', 'NAME'];
    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headers[col]);
    }

    // Sample Data chuẩn 3 cột: Mã thùng, Mã chip EPC RFID, Tên sản phẩm
    final sampleData = [
      ['CARTONTEST0001', 'ABCDEF000000000000000001', 'Áo Polo RFID Cotton Standard'],
      ['CARTONTEST0001', 'ABCDEF000000000000000002', 'Áo Polo RFID Cotton Standard'],
      ['CARTONTEST0001', 'ABCDEF000000000000000003', 'Áo Polo RFID Cotton Standard'],
      ['CARTONTEST0001', 'ABCDEF000000000000000004', 'Áo Polo RFID Cotton Standard'],
      ['CARTONTEST0001', 'ABCDEF000000000000000005', 'Áo Polo RFID Cotton Standard'],
      ['CARTONTEST0001', 'ABCDEF000000000000000006', 'Áo Polo RFID Cotton Standard'],
      ['CARTONTEST0001', 'ABCDEF000000000000000007', 'Áo Polo RFID Cotton Standard'],
      ['CARTONTEST0001', 'ABCDEF000000000000000008', 'Áo Polo RFID Cotton Standard'],
      ['CARTONTEST0001', 'ABCDEF000000000000000009', 'Áo Polo RFID Cotton Standard'],
      ['CARTONTEST0001', 'ABCDEF000000000000000010', 'Áo Polo RFID Cotton Standard'],
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
