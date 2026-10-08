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
  final String? customerName;

  ExcelImportResult({
    required this.fileName,
    required this.totalRows,
    required this.totalCartons,
    required this.totalSerials,
    required this.cartons,
    this.customerName,
  });
}

/// Dòng sản phẩm cần xuất kho đọc từ file Excel/CSV (Mã SKU, Mã Hàng, Số lượng)
class OutboundImportRow {
  final String sku;
  final String productId;
  final int quantity;
  final String productName;
  final String customer;
  final String orderNo;
  final String cartonCode;
  final String palletCode;
  final String? epc;

  OutboundImportRow({
    required this.sku,
    required this.productId,
    required this.quantity,
    this.productName = '',
    this.customer = '',
    this.orderNo = '',
    this.cartonCode = '',
    this.palletCode = '',
    this.epc,
  });

  Map<String, dynamic> toMap() => {
    'sku': sku,
    'productId': productId,
    'itemId': productId,
    'productName': productName,
    'quantity': quantity,
    'customer': customer,
    'orderNo': orderNo,
    'cartonCode': cartonCode,
    'palletCode': palletCode,
    'epc': epc ?? '',
  };
}

/// Kết quả nạp file xuất kho từ Excel/CSV
class OutboundExcelImportResult {
  final String fileName;
  final String orderNo;
  final String customer;
  final List<OutboundImportRow> rows;
  final int totalRequestedQuantity;

  OutboundExcelImportResult({
    required this.fileName,
    required this.orderNo,
    required this.customer,
    required this.rows,
    required this.totalRequestedQuantity,
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
      String? topCustomer;
      for (final c in cartons) {
        final list = (c['serials'] as List<dynamic>?) ?? [];
        totalSerials += list.length;
        if (topCustomer == null || topCustomer.isEmpty) {
          final cust = c['customer']?.toString().trim();
          if (cust != null && cust.isNotEmpty) {
            topCustomer = cust;
          }
        }
      }

      return ExcelImportResult(
        fileName: file.name,
        totalRows: rawRowsCount,
        totalCartons: cartons.length,
        totalSerials: totalSerials,
        cartons: cartons,
        customerName: topCustomer,
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
    int? customerCol;
    int startRow = 0;

    String fileCustomer = '';
    for (int r = 0; r < rawGrid.length && r < 10; r++) {
      for (int c = 0; c < rawGrid[r].length; c++) {
        final cell = rawGrid[r][c];
        final lower = _normalizeHeader(cell);
        // TH1: Nhãn và tên khách hàng nằm chung 1 ô (vd: "Khách hàng: Công ty ABC")
        if (lower.startsWith('khach hang:') ||
            lower.startsWith('khach hang :') ||
            lower.startsWith('customer:') ||
            lower.startsWith('don vi nhan:') ||
            lower.startsWith('nguoi nhan:') ||
            lower.startsWith('khach mua:')) {
          final parts = cell.split(RegExp(r'[:：]'));
          if (parts.length > 1 && parts.sublist(1).join(':').trim().isNotEmpty) {
            fileCustomer = parts.sublist(1).join(':').trim();
            break;
          }
        }
        // TH2: Nhãn ở ô này, tên khách hàng ở ô kế bên (vd: ô A1 là "Khách hàng", ô B1 là "Công ty ABC")
        if (lower == 'khach hang' ||
            lower == 'khách hàng' ||
            lower == 'customer' ||
            lower == 'don vi nhan' ||
            lower == 'nguoi nhan' ||
            lower == 'khach mua') {
          if (c + 1 < rawGrid[r].length && rawGrid[r][c + 1].trim().isNotEmpty) {
            fileCustomer = rawGrid[r][c + 1].trim();
            break;
          }
        }
      }
      if (fileCustomer.isNotEmpty) break;
    }

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
      // 8. Cột Khách hàng / Customer / Đơn vị nhận / Người nhận
      else if (h.contains('khach hang') ||
          h.contains('khách hàng') ||
          h.contains('customer') ||
          h.contains('don vi nhan') ||
          h.contains('nguoi nhan') ||
          h.contains('khach mua') ||
          h.contains('client')) {
        customerCol = i;
        hasHeader = true;
      }
    }

    // Nếu file có cột Pallet và cột RFID/EPC nhưng cột RFID chưa có chữ 'pallet' (Ví dụ: cột 1 là "Pallet", cột 2 là "RFID")
    if (palletCol != null && palletEpcCol == null && serialCol != null) {
      palletEpcCol = serialCol;
      serialCol = null;
    }

    // Nếu bảng dữ liệu có cột "KHÁCH HÀNG" nhưng không có cột Nhà Cung Cấp riêng,
    // dữ liệu thực tế tại kho lưu trong cột đó là Nhà Cung Cấp (như PEPSICO).
    if (supplierCol == null && customerCol != null) {
      supplierCol = customerCol;
      customerCol = null;
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
      debugPrint('📋 EXCEL ROW $r: serialCol=$serialCol → serial="$serial" (len=${serial.length})');
      final barcode = (barcodeCol != null && barcodeCol < row.length) ? row[barcodeCol].trim() : '';
      final name = (nameCol < row.length) ? row[nameCol].trim() : '';
      final supplier = (supplierCol != null && supplierCol < row.length) ? row[supplierCol].trim() : '';
      final customer = (customerCol != null && customerCol < row.length) ? row[customerCol].trim() : '';
      final effectiveCustomer = customer.isNotEmpty ? customer : (fileCustomer.isNotEmpty ? fileCustomer : '');

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
          // Tra cứu xem trong kho đã có sản phẩm này chưa (theo EPC hoặc theo tên) để tái sử dụng SKU
          final repoItems = WarehouseRepository().items;
          final existingItem = repoItems.where((it) =>
              (serial.isNotEmpty && it.epc.toUpperCase() == serial.toUpperCase()) ||
              (it.productName.trim().isNotEmpty && it.productName.trim().toLowerCase() == effectiveName.trim().toLowerCase())
          ).firstOrNull;

          if (existingItem != null && existingItem.sku.isNotEmpty && existingItem.sku != '--') {
            rowBarcode = existingItem.sku;
          } else {
            // Tra cứu thêm trong danh mục sản phẩm đã có để tái sử dụng đúng SKU, tránh sinh mã trùng lặp
            final existingProd = WarehouseRepository().products.where((p) =>
              p.productName.trim().isNotEmpty && p.productName.trim().toLowerCase() == effectiveName.trim().toLowerCase()
            ).firstOrNull;
            if (existingProd != null && existingProd.sku.isNotEmpty && existingProd.sku != '--') {
              rowBarcode = existingProd.sku;
            } else {
              rowBarcode = WarehouseRepository().generateHexBarcode128();
            }
          }
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
          'customer': effectiveCustomer,
          'quantity': 0,
          'serials': <String>[],
          'serialItems': <Map<String, dynamic>>[],
        };
      } else {
        if (supplier.isNotEmpty && cartonMap[groupKey]!['supplier'] == 'Nhà cung cấp tổng hợp') {
          cartonMap[groupKey]!['supplier'] = supplier;
        }
        if (effectiveCustomer.isNotEmpty && (cartonMap[groupKey]!['customer'] == null || (cartonMap[groupKey]!['customer'] as String).isEmpty)) {
          cartonMap[groupKey]!['customer'] = effectiveCustomer;
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
            'customer': effectiveCustomer.isNotEmpty ? effectiveCustomer : entry['customer'],
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
            'customer': effectiveCustomer.isNotEmpty ? effectiveCustomer : entry['customer'],
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

  /// Mở hộp thoại chọn file Excel / CSV nạp danh sách yêu cầu xuất kho:
  /// Cấu trúc: Mã SKU, Mã Hàng (Product ID/Item ID), Số lượng.
  /// KHÔNG cần khai báo mã EPC. Khi quét tại trạm/cổng RFID, hệ thống tự động
  /// đối chiếu mã chip EPC trong CSDL tồn kho để xuất.
  Future<OutboundExcelImportResult?> pickAndParseOutboundExcel() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (files.isEmpty) return null;

      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw Exception('Tệp đã chọn rỗng.');

      final isCsv = file.name.toLowerCase().endsWith('.csv');
      return parseOutboundExcelBytes(bytes, isCsv: isCsv, fileName: file.name);
    } catch (e) {
      debugPrint('ExcelImportService Outbound error: $e');
      rethrow;
    }
  }

  /// Phân tích nội dung bytes file Excel/CSV xuất kho (hỗ trợ cả headless/unit test)
  OutboundExcelImportResult parseOutboundExcelBytes(
    Uint8List bytes, {
    bool isCsv = false,
    String? fileName,
  }) {
    final List<List<String>> rawGrid = [];

    if (isCsv) {
      String content;
      try {
        content = utf8.decode(bytes);
      } catch (_) {
        content = String.fromCharCodes(bytes);
      }
      final lines = content.split(RegExp(r'\r\n|\n|\r'));
      for (final line in lines) {
        if (line.trim().isEmpty) continue;
        rawGrid.add(line.split(RegExp(r',|\t|;')).map((c) => c.trim()).toList());
      }
    } else {
      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) throw Exception('Tệp Excel rỗng hoặc không có bảng dữ liệu.');
      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName]!;
      for (final row in sheet.rows) {
        rawGrid.add(row.map((c) => _cellToString(c?.value)).toList());
      }
    }

    if (rawGrid.isEmpty) {
      throw Exception('Không có dữ liệu trong tệp.');
    }

    int? skuCol;
    int? productIdCol;
    int? qtyCol;
    int? nameCol;
    int? orderNoCol;
    int? customerCol;
    int? epcCol;
    int? cartonCol;
    int? palletCol;
    int startRow = 0;

    // Tìm kiếm khách hàng hoặc số phiếu ở các dòng đầu tiên nếu có ghi chú
    String detectedCustomer = '';
    String detectedOrderNo = '';
    for (int r = 0; r < rawGrid.length && r < 10; r++) {
      for (int c = 0; c < rawGrid[r].length; c++) {
        final cell = rawGrid[r][c];
        final lower = _normalizeHeader(cell);
        if (lower.startsWith('khach hang:') || lower.startsWith('customer:')) {
          final parts = cell.split(RegExp(r'[:：]'));
          if (parts.length > 1 && parts.sublist(1).join(':').trim().isNotEmpty) {
            detectedCustomer = parts.sublist(1).join(':').trim();
          }
        } else if (lower.startsWith('so phieu:') || lower.startsWith('ma don:') || lower.startsWith('order:')) {
          final parts = cell.split(RegExp(r'[:：]'));
          if (parts.length > 1 && parts.sublist(1).join(':').trim().isNotEmpty) {
            detectedOrderNo = parts.sublist(1).join(':').trim();
          }
        }
      }
    }

    final firstRow = rawGrid.first;
    final headers = firstRow.map((c) => _normalizeHeader(c)).toList();
    bool hasHeader = false;

    for (int i = 0; i < headers.length; i++) {
      final h = headers[i];
      if (h.isEmpty) continue;

      if (h.contains('sku') || h.contains('barcode') || h.contains('ma vach')) {
        skuCol = i;
        hasHeader = true;
      } else if (h.contains('ma hang') || h.contains('item id') || h.contains('item_id') ||
                 h.contains('product id') || h.contains('product_id') || h.contains('ma sp') ||
                 h.contains('ma san pham') || h.contains('item code') || h.contains('product code')) {
        productIdCol = i;
        hasHeader = true;
      } else if (h.contains('so luong') || h.contains('quantity') || h.contains('qty') || h.contains('sl')) {
        qtyCol = i;
        hasHeader = true;
      } else if (h.contains('ten') || h.contains('name') || h.contains('mo ta') || h.contains('description')) {
        nameCol = i;
        hasHeader = true;
      } else if (h.contains('order') || h.contains('don hang') || h.contains('ma don') || h.contains('po') || h.contains('phieu') || h.contains('so phieu')) {
        orderNoCol = i;
        hasHeader = true;
      } else if (h.contains('khach hang') || h.contains('customer') || h.contains('nguoi nhan') || h.contains('don vi nhan') || h.contains('nha cung cap') || h.contains('supplier') || h.contains('ncc')) {
        customerCol = i;
        hasHeader = true;
      } else if (h.contains('epc') || h.contains('serial') || h.contains('chip') || h.contains('rfid') || h.contains('tag')) {
        epcCol = i;
        hasHeader = true;
      } else if (h.contains('carton') || h.contains('thung') || h.contains('box') || h.contains('kien')) {
        cartonCol = i;
        hasHeader = true;
      } else if (h.contains('pallet') || h.contains('palet')) {
        palletCol = i;
        hasHeader = true;
      }
    }

    if (hasHeader) {
      startRow = 1;
    }

    // Tự động gán vị trí cột nếu không tìm thấy tiêu đề rõ ràng
    if (skuCol == null && productIdCol == null) {
      skuCol = 0;
      if (firstRow.length >= 3) {
        productIdCol = 1;
        qtyCol ??= 2;
      } else if (firstRow.length == 2) {
        productIdCol = 0;
        qtyCol ??= 1;
      }
    } else if (skuCol == null && productIdCol != null) {
      skuCol = productIdCol;
    } else if (productIdCol == null && skuCol != null) {
      productIdCol = skuCol;
    }

    final List<OutboundImportRow> rows = [];
    final repoProducts = WarehouseRepository().products;

    for (int r = startRow; r < rawGrid.length; r++) {
      final row = rawGrid[r];
      if (row.isEmpty) continue;

      final sku = (skuCol != null && skuCol < row.length) ? row[skuCol].trim() : '';
      final productId = (productIdCol != null && productIdCol < row.length) ? row[productIdCol].trim() : '';
      final qtyStr = (qtyCol != null && qtyCol < row.length) ? row[qtyCol].trim() : '1';
      final name = (nameCol != null && nameCol < row.length) ? row[nameCol].trim() : '';
      final orderNo = (orderNoCol != null && orderNoCol < row.length) ? row[orderNoCol].trim() : '';
      final customer = (customerCol != null && customerCol < row.length) ? row[customerCol].trim() : '';
      final carton = (cartonCol != null && cartonCol < row.length) ? row[cartonCol].trim() : '';
      final pallet = (palletCol != null && palletCol < row.length) ? row[palletCol].trim() : '';
      final epc = (epcCol != null && epcCol < row.length) ? row[epcCol].trim().toUpperCase() : '';

      if (sku.isEmpty && productId.isEmpty && name.isEmpty && epc.isEmpty) continue;

      final effectiveSku = sku.isNotEmpty ? sku : productId;
      final effectiveProdId = productId.isNotEmpty ? productId : effectiveSku;

      // Tra cứu tên sản phẩm nếu file không cung cấp
      String effectiveName = name;
      if (effectiveName.isEmpty) {
        final foundProd = repoProducts.where((p) =>
          p.sku.toUpperCase() == effectiveSku.toUpperCase() ||
          p.productId.toUpperCase() == effectiveProdId.toUpperCase()
        ).firstOrNull;
        effectiveName = foundProd?.productName ?? 'Sản phẩm $effectiveSku';
      }

      final parsedQty = int.tryParse(qtyStr) ?? 1;
      final finalQty = parsedQty > 0 ? parsedQty : 1;

      if (detectedCustomer.isEmpty && customer.isNotEmpty) {
        detectedCustomer = customer;
      }
      if (detectedOrderNo.isEmpty && orderNo.isNotEmpty) {
        detectedOrderNo = orderNo;
      }

      rows.add(OutboundImportRow(
        sku: effectiveSku,
        productId: effectiveProdId,
        quantity: finalQty,
        productName: effectiveName,
        customer: customer.isNotEmpty ? customer : detectedCustomer,
        orderNo: orderNo.isNotEmpty ? orderNo : detectedOrderNo,
        cartonCode: carton,
        palletCode: pallet,
        epc: epc.isNotEmpty ? epc : null,
      ));
    }

    if (rows.isEmpty) {
      throw Exception('Không tìm thấy dòng mặt hàng xuất hợp lệ nào trong tệp!');
    }

    final totalQty = rows.fold<int>(0, (sum, r) => sum + r.quantity);
    final now = DateTime.now();
    final effectiveOrderNo = detectedOrderNo.isNotEmpty
        ? detectedOrderNo
        : 'XK-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

    return OutboundExcelImportResult(
      fileName: fileName ?? 'Xuat_Kho.xlsx',
      orderNo: effectiveOrderNo,
      customer: detectedCustomer.isNotEmpty ? detectedCustomer : 'Khách mua xuất kho',
      rows: rows,
      totalRequestedQuantity: totalQty,
    );
  }

  /// Xuất file Excel mẫu chuẩn nhập kho RFID WMS: cùng 1 loại sản phẩm, số lượng nhiều, khác EPC
  Future<String> exportGoodsReceiveTemplate({String fileName = 'Mau_Nhap_Hang_Cung_Loai_Nhieu_EPC.xlsx'}) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, 'Goods_Receive');
    final sheet = excel['Goods_Receive'];

    final headers = [
      'CARTON CODE',
      'EPC',
      'NAME',
      'SKU',
      'NCC',
      'BARCODE PALET',
      'EPC PALLET',
    ];

    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#0F766E'),
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

    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = headerStyle;
    }

    const productName = 'Áo Polo Nam Thể Thao RFID Coolmax';
    const sku = 'SKU-POLO-COOLMAX-01';
    const supplier = 'Tổng Công Ty May Việt Tiến';

    // 60 sản phẩm, chia đều 6 thùng (10 sp/thùng), phân bố trên 3 Pallet (2 thùng/pallet)
    const totalItems = 60;
    const itemsPerCarton = 10;
    const cartonsPerPallet = 2;

    final palletConfigs = [
      {'barcode': 'PL-01', 'epc': 'AB2600100000000000000201'},
      {'barcode': 'PL-02', 'epc': 'AB2600100000000000000202'},
      {'barcode': 'PL-03', 'epc': 'AB2600100000000000000203'},
    ];

    for (int i = 1; i <= totalItems; i++) {
      final cartonNum = ((i - 1) ~/ itemsPerCarton) + 1;
      final cartonCode = 'CARTON-POLO-${cartonNum.toString().padLeft(3, '0')}';

      final palletIndex = (cartonNum - 1) ~/ cartonsPerPallet;
      final palletConfig = palletConfigs[palletIndex % palletConfigs.length];
      final palletBarcode = palletConfig['barcode']!;
      final palletEpc = palletConfig['epc']!;

      final epc = 'E280689400005024B076${i.toString().padLeft(4, '0')}';
      final rowIndex = i;

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

    sheet.setColumnWidth(0, 22.0);
    sheet.setColumnWidth(1, 34.0);
    sheet.setColumnWidth(2, 42.0);
    sheet.setColumnWidth(3, 24.0);
    sheet.setColumnWidth(4, 34.0);
    sheet.setColumnWidth(5, 20.0);
    sheet.setColumnWidth(6, 32.0);

    final bytes = Uint8List.fromList(excel.encode() ?? []);
    if (bytes.isEmpty) throw Exception('Không thể tạo file Excel.');

    String? savePath;
    try {
      final savedUri = await FilePicker.saveFile(
        fileName: fileName,
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
      savePath = '${dir.path}${Platform.pathSeparator}$fileName';
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

  /// Xuất file Excel mẫu chuẩn xuất kho WMS: MÃ SKU, MÃ HÀNG, SỐ LƯỢNG (Không cần cột EPC)
  Future<String> exportOutboundTemplate({String fileName = 'Mau_Xuat_Kho_SKU_MaHang_SoLuong.xlsx'}) async {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet() ?? 'Sheet1';
    excel.rename(defaultSheet, 'Xuat_Kho');
    final sheet = excel['Xuat_Kho'];

    final headers = [
      'MÃ SKU',
      'MÃ HÀNG',
      'SỐ LƯỢNG',
      'TÊN SẢN PHẨM',
      'KHÁCH HÀNG',
      'GHI CHÚ',
    ];

    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#0284C7'),
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

    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = headerStyle;
    }

    final sampleData = [
      ['SKU-POLO-COOLMAX-01', 'PROD-POLO-01', '10', 'Áo Polo Nam Thể Thao RFID Coolmax', 'Công ty Thời Trang An Nam', 'Xuất theo đơn đặt hàng'],
      ['SKU-JEAN-SLIM-02', 'PROD-JEAN-02', '5', 'Quần Jean Nam Co Giãn Form Slimfit', 'Công ty Thời Trang An Nam', 'Xuất giao đại lý'],
      ['SKU-SHIRT-OXFORD-03', 'PROD-SHIRT-03', '8', 'Áo Sơ Mi Nam Tay Dài Vải Oxford', 'Đại lý Thời Trang Phố Huế', 'Xuất kho giao ngay'],
    ];

    for (int r = 0; r < sampleData.length; r++) {
      final rowData = sampleData[r];
      for (int c = 0; c < rowData.length; c++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
        cell.value = TextCellValue(rowData[c]);
        cell.cellStyle = (c == 0 || c == 1 || c == 2) ? codeStyle : textStyle;
      }
    }

    sheet.setColumnWidth(0, 26.0);
    sheet.setColumnWidth(1, 22.0);
    sheet.setColumnWidth(2, 14.0);
    sheet.setColumnWidth(3, 40.0);
    sheet.setColumnWidth(4, 32.0);
    sheet.setColumnWidth(5, 28.0);

    final bytes = Uint8List.fromList(excel.encode() ?? []);
    if (bytes.isEmpty) throw Exception('Không thể tạo file Excel.');

    String? savePath;
    try {
      final savedUri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
      );
      if (savedUri != null) {
        savePath = savedUri.toFilePath();
      }
    } catch (e) {
      debugPrint('Save outbound template via picker failed: $e');
    }

    if (savePath == null || savePath.isEmpty) {
      Directory? dir;
      try {
        dir = await getDownloadsDirectory();
      } catch (_) {}
      try {
        dir ??= await getApplicationDocumentsDirectory();
      } catch (_) {}
      dir ??= Directory.systemTemp;
      savePath = '${dir.path}${Platform.pathSeparator}$fileName';
      final file = File(savePath);
      await file.writeAsBytes(bytes);
    }

    return savePath;
  }
}
