import 'dart:io';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'warehouse_repository.dart';

enum ReportFormat { xlsx, csv }

enum ReportType {
  inbound('Nhập Kho', 'inbound'),
  outbound('Xuất Kho', 'outbound'),
  inventory('Tồn Kho', 'inventory'),
  audit('Kiểm Kê', 'audit'),
  transactionLog('Biến Động Kho', 'transactions');

  final String label;
  final String filePrefix;
  const ReportType(this.label, this.filePrefix);
}

class ReportExportService {
  static final ReportExportService _instance = ReportExportService._internal();
  factory ReportExportService() => _instance;
  ReportExportService._internal();

  final WarehouseRepository _repo = WarehouseRepository();
  final DateFormat _dtFmt = DateFormat('dd/MM/yyyy HH:mm');
  final DateFormat _fileFmt = DateFormat('yyyyMMdd_HHmmss');

  /// Thư mục lưu báo cáo
  Future<Directory> _getReportDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final reportDir = Directory('${appDir.path}${Platform.pathSeparator}WMS_Reports');
    if (!await reportDir.exists()) {
      await reportDir.create(recursive: true);
    }
    return reportDir;
  }

  /// Xuất báo cáo theo loại và định dạng
  Future<File> exportReport(ReportType type, ReportFormat format) async {
    switch (type) {
      case ReportType.inbound:
        return _exportInbound(format);
      case ReportType.outbound:
        return _exportOutbound(format);
      case ReportType.inventory:
        return _exportInventory(format);
      case ReportType.audit:
        return _exportAudit(format);
      case ReportType.transactionLog:
        return _exportTransactionLog(format);
    }
  }

  /// Số lượng bản ghi hiện có cho mỗi loại báo cáo
  int getRecordCount(ReportType type) {
    switch (type) {
      case ReportType.inbound:
        return _repo.inboundOrders.length;
      case ReportType.outbound:
        return _repo.outboundOrders.length;
      case ReportType.inventory:
        return _repo.items.where((i) => i.status.code == 'IN_STOCK').length;
      case ReportType.audit:
        return _repo.inventorySessions.length;
      case ReportType.transactionLog:
        return _repo.transactions.length;
    }
  }

  // ─────────────────────────── INBOUND ───────────────────────────

  Future<File> _exportInbound(ReportFormat format) async {
    final orders = _repo.inboundOrders;
    final allItems = _repo.items;

    final headers = [
      'Mã Đơn', 'Nhà Cung Cấp', 'Trạng Thái', 'Ngày Tạo',
      'Tổng SKU', 'Tổng Chip RFID', 'Chi Tiết SKU (SKU × SL)',
    ];

    final rows = <List<String>>[];
    for (final ord in orders) {
      final orderItems = allItems.where((i) => i.orderNo == ord.orderNo).toList();
      final skuMap = <String, int>{};
      for (final it in orderItems) {
        skuMap[it.sku] = (skuMap[it.sku] ?? 0) + 1;
      }
      final skuSummary = skuMap.entries.map((e) => '${e.key} × ${e.value}').join('; ');

      rows.add([
        ord.orderNo,
        ord.sourceSupplier,
        ord.status.label,
        _dtFmt.format(ord.createdAt),
        ord.details.length.toString(),
        orderItems.length.toString(),
        skuSummary,
      ]);
    }

    return _writeFile(ReportType.inbound, format, headers, rows);
  }

  // ─────────────────────────── OUTBOUND ───────────────────────────

  Future<File> _exportOutbound(ReportFormat format) async {
    final orders = _repo.outboundOrders;
    final deliveries = _repo.deliveryNotes;

    final headers = [
      'Mã PO', 'Khách Hàng', 'Trạng Thái', 'Ngày Tạo',
      'Tổng SKU', 'Tổng SL Yêu Cầu', 'Mã Vận Đơn',
    ];

    final rows = <List<String>>[];
    for (final ord in orders) {
      final totalReq = ord.details.fold<int>(0, (s, d) => s + d.requiredQty);
      final delivery = deliveries.where((d) => d.poNo == ord.poNo).toList();
      final deliveryNos = delivery.map((d) => d.deliveryNo).join(', ');

      rows.add([
        ord.poNo,
        ord.customer,
        ord.status.label,
        _dtFmt.format(ord.createdAt),
        ord.details.length.toString(),
        totalReq.toString(),
        deliveryNos.isEmpty ? '--' : deliveryNos,
      ]);
    }

    return _writeFile(ReportType.outbound, format, headers, rows);
  }

  // ─────────────────────────── INVENTORY ───────────────────────────

  Future<File> _exportInventory(ReportFormat format) async {
    final inStockItems = _repo.items.where((i) => i.status.code == 'IN_STOCK').toList();

    final headers = [
      'EPC', 'SKU', 'Tên Sản Phẩm', 'Nhà Cung Cấp', 'Mã Thùng',
      'Pallet', 'Vị Trí Kệ', 'Ngày Nhập Kho',
    ];

    final rows = <List<String>>[];
    for (final it in inStockItems) {
      // Tìm pallet name
      String palletDisplay = '--';
      if (it.palletId != null && it.palletId!.isNotEmpty) {
        final pallet = _repo.pallets.where((p) => p.palletId == it.palletId || p.palletCode == it.palletId).toList();
        palletDisplay = pallet.isNotEmpty ? pallet.first.displayName : it.palletId!;
      }

      // Tìm location code
      String locationDisplay = '--';
      if (it.locationId != null && it.locationId!.isNotEmpty) {
        locationDisplay = it.locationId!;
      }

      rows.add([
        it.epc,
        it.sku,
        it.productName,
        it.supplierDisplay,
        it.cartonDisplay,
        palletDisplay,
        locationDisplay,
        it.inboundTime != null ? _dtFmt.format(it.inboundTime!) : '--',
      ]);
    }

    return _writeFile(ReportType.inventory, format, headers, rows);
  }

  // ─────────────────────────── AUDIT ───────────────────────────

  Future<File> _exportAudit(ReportFormat format) async {
    final sessions = _repo.inventorySessions;

    final headers = [
      'Mã Phiên', 'Khu Vực', 'Vị Trí', 'Ngày Bắt Đầu', 'Hoàn Thành',
      'Tổng Quét', 'Khớp', 'Thiếu', 'Sai Vị Trí', 'Thẻ Lạ',
    ];

    final rows = <List<String>>[];
    for (final s in sessions) {
      rows.add([
        s.sessionCode,
        s.zone,
        s.locationCode ?? '--',
        _dtFmt.format(s.startedAt),
        s.isCompleted ? 'Đã hoàn thành' : 'Đang thực hiện',
        s.actualScannedCount.toString(),
        s.matchCount.toString(),
        s.missingCount.toString(),
        s.wrongLocationCount.toString(),
        s.unknownEpcCount.toString(),
      ]);
    }

    return _writeFile(ReportType.audit, format, headers, rows);
  }

  // ─────────────────────────── TRANSACTION LOG ───────────────────────────

  Future<File> _exportTransactionLog(ReportFormat format) async {
    final txs = _repo.transactions;

    final headers = [
      'Loại', 'Mã Chứng Từ', 'SKU', 'Tên Sản Phẩm', 'Số Lượng',
      'Từ Vị Trí', 'Đến Vị Trí', 'Pallet', 'Người Thực Hiện', 'Thời Gian',
    ];

    final rows = <List<String>>[];
    for (final t in txs) {
      rows.add([
        t.type.label,
        t.documentNo,
        t.sku,
        t.productName,
        t.quantity.toString(),
        t.fromLocation ?? '--',
        t.toLocation ?? '--',
        t.palletCode ?? '--',
        t.performedBy,
        _dtFmt.format(t.timestamp),
      ]);
    }

    return _writeFile(ReportType.transactionLog, format, headers, rows);
  }

  // ─────────────────────────── FILE WRITER ───────────────────────────

  Future<File> _writeFile(
    ReportType type,
    ReportFormat format,
    List<String> headers,
    List<List<String>> rows,
  ) async {
    final dir = await _getReportDir();
    final timestamp = _fileFmt.format(DateTime.now());
    final fileName = '${type.filePrefix}_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    if (format == ReportFormat.csv) {
      return _writeCsv(filePath, headers, rows);
    } else {
      return _writeXlsx(filePath, type.label, headers, rows);
    }
  }

  Future<File> _writeCsv(String path, List<String> headers, List<List<String>> rows) async {
    final allRows = [headers, ...rows];
    // BOM UTF-8 để Excel mở đúng tiếng Việt
    final csvString = '\uFEFF${Csv().encode(allRows)}';
    final file = File(path);
    await file.writeAsString(csvString);
    return file;
  }

  Future<File> _writeXlsx(String path, String sheetName, List<String> headers, List<List<String>> rows) async {
    final excel = Excel.createExcel();
    final sheet = excel[sheetName];
    // Xóa sheet mặc định nếu có
    if (excel.sheets.containsKey('Sheet1')) {
      excel.delete('Sheet1');
    }

    // Header style
    final headerStyle = CellStyle(
      bold: true,
      fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
      backgroundColorHex: ExcelColor.fromHexString('#0284C7'),
      horizontalAlign: HorizontalAlign.Center,
      verticalAlign: VerticalAlign.Center,
    );

    // Ghi header
    for (int col = 0; col < headers.length; col++) {
      final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 0));
      cell.value = TextCellValue(headers[col]);
      cell.cellStyle = headerStyle;
    }

    // Ghi data rows
    for (int row = 0; row < rows.length; row++) {
      for (int col = 0; col < rows[row].length; col++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row + 1));
        cell.value = TextCellValue(rows[row][col]);
      }
    }

    // Auto-width (approximate)
    for (int col = 0; col < headers.length; col++) {
      double maxLen = headers[col].length.toDouble();
      for (final row in rows) {
        if (col < row.length && row[col].length > maxLen) {
          maxLen = row[col].length.toDouble();
        }
      }
      sheet.setColumnWidth(col, maxLen < 12 ? 14 : (maxLen > 50 ? 50 : maxLen + 4));
    }

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Excel encode failed');

    final file = File(path);
    await file.writeAsBytes(bytes);
    return file;
  }
}
