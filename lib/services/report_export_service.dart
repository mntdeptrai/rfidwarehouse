import 'dart:io';
import 'package:excel/excel.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/wms_models.dart';
import 'warehouse_repository.dart';

enum ReportFormat { xlsx, csv }

enum ReportType {
  inbound('Nhập Kho', 'phieu_nhap_kho'),
  outbound('Xuất Kho', 'phieu_xuat_kho'),
  inventory('Tồn Kho', 'bao_cao_ton_kho'),
  audit('Kiểm Kê', 'bien_ban_kiem_ke'),
  transactionLog('Biến Động Kho', 'so_bien_dong_kho');

  final String label;
  final String filePrefix;
  const ReportType(this.label, this.filePrefix);
}

/// Dịch vụ kết xuất Báo Cáo & Form Mẫu Phiếu Kho Chuẩn Doanh Nghiệp (Excel / CSV)
/// Tự động điền dữ liệu thực tế từ hệ thống vào biểu mẫu phiếu (không cần nạp file mẫu thủ công)
class ReportExportService {
  static final ReportExportService _instance = ReportExportService._internal();
  factory ReportExportService() => _instance;
  ReportExportService._internal();

  final WarehouseRepository _repo = WarehouseRepository();
  final DateFormat _dtFmt = DateFormat('dd/MM/yyyy HH:mm');
  final DateFormat _fileFmt = DateFormat('yyyyMMdd_HHmmss');

  /// Thư mục lưu báo cáo (hỗ trợ fallback an toàn cho môi trường test/headless)
  Future<Directory> _getReportDir() async {
    Directory baseDir;
    try {
      baseDir = await getApplicationDocumentsDirectory();
    } catch (_) {
      baseDir = Directory.systemTemp;
    }
    final reportDir = Directory('${baseDir.path}${Platform.pathSeparator}WMS_Reports');
    if (!await reportDir.exists()) {
      await reportDir.create(recursive: true);
    }
    return reportDir;
  }

  /// Format khoảng thời gian báo cáo
  String formatPeriodSubtitle(DateTime? fromDate, DateTime? toDate) {
    final df = DateFormat('dd/MM/yyyy');
    if (fromDate != null && toDate != null) {
      if (fromDate.year == toDate.year && fromDate.month == toDate.month && fromDate.day == toDate.day) {
        return 'Thời điểm: Ngày ${df.format(fromDate)}';
      }
      return 'Giai đoạn: ${df.format(fromDate)} - ${df.format(toDate)}';
    } else if (fromDate != null) {
      return 'Từ ngày: ${df.format(fromDate)}';
    } else if (toDate != null) {
      return 'Thời điểm: Tính đến ${df.format(toDate)}';
    }
    return 'Toàn thời gian (Thời điểm xuất: ${_dtFmt.format(DateTime.now())})';
  }

  /// Xuất báo cáo theo loại và định dạng (hỗ trợ lọc theo thời điểm / giai đoạn)
  Future<File> exportReport(
    ReportType type,
    ReportFormat format, {
    DateTime? fromDate,
    DateTime? toDate,
    bool includeEpc = false,
  }) async {
    return exportReportSelected(type, format, fromDate: fromDate, toDate: toDate, includeEpc: includeEpc);
  }

  /// Xuất báo cáo chọn lọc theo danh sách ID/Mã đơn được tick chọn và khoảng thời gian
  Future<File> exportReportSelected(
    ReportType type,
    ReportFormat format, {
    List<String>? selectedKeys,
    DateTime? fromDate,
    DateTime? toDate,
    bool includeEpc = false,
  }) async {
    switch (type) {
      case ReportType.inbound:
        return _exportInboundForm(format, selectedOrderNos: selectedKeys, fromDate: fromDate, toDate: toDate, includeEpc: includeEpc);
      case ReportType.outbound:
        return _exportOutboundForm(format, selectedPoNos: selectedKeys, fromDate: fromDate, toDate: toDate, includeEpc: includeEpc);
      case ReportType.inventory:
        return _exportInventoryForm(format, selectedEpcs: selectedKeys, fromDate: fromDate, toDate: toDate, includeEpc: includeEpc);
      case ReportType.audit:
        return _exportAuditForm(format, selectedSessionCodes: selectedKeys, includeEpc: includeEpc);
      case ReportType.transactionLog:
        return _exportTransactionLogForm(format, selectedDocNos: selectedKeys, fromDate: fromDate, toDate: toDate);
    }
  }

  /// Xuất file phiếu xuất kho cho 1 đơn cụ thể
  Future<File> exportSingleOutboundOrder(
    OutboundOrder order, {
    ReportFormat format = ReportFormat.xlsx,
    bool includeEpc = false,
  }) async {
    return _exportOutboundForm(
      format,
      selectedPoNos: [order.poNo],
      includeEpc: includeEpc,
    );
  }

  /// Số lượng bản ghi hiện có cho mỗi loại báo cáo (hỗ trợ lọc theo giai đoạn)
  int getRecordCount(ReportType type, {DateTime? fromDate, DateTime? toDate}) {
    final start = fromDate != null ? DateTime(fromDate.year, fromDate.month, fromDate.day, 0, 0, 0) : null;
    final end = toDate != null ? DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59, 999) : null;

    switch (type) {
      case ReportType.inbound:
        var list = _repo.inboundOrders;
        if (start != null) list = list.where((o) => o.createdAt.isAfter(start) || o.createdAt.isAtSameMomentAs(start)).toList();
        if (end != null) list = list.where((o) => o.createdAt.isBefore(end) || o.createdAt.isAtSameMomentAs(end)).toList();
        return list.length;
      case ReportType.outbound:
        var list = _repo.outboundOrders;
        if (start != null) list = list.where((o) => o.createdAt.isAfter(start) || o.createdAt.isAtSameMomentAs(start)).toList();
        if (end != null) list = list.where((o) => o.createdAt.isBefore(end) || o.createdAt.isAtSameMomentAs(end)).toList();
        return list.length;
      case ReportType.inventory:
        var list = _repo.items.where((i) => i.status.code == 'IN_STOCK');
        if (start != null) list = list.where((i) => i.inboundTime != null && (i.inboundTime!.isAfter(start) || i.inboundTime!.isAtSameMomentAs(start)));
        if (end != null) list = list.where((i) => i.inboundTime != null && (i.inboundTime!.isBefore(end) || i.inboundTime!.isAtSameMomentAs(end)));
        return list.length;
      case ReportType.audit:
        var list = _repo.inventorySessions;
        if (start != null) list = list.where((s) => s.startedAt.isAfter(start) || s.startedAt.isAtSameMomentAs(start)).toList();
        if (end != null) list = list.where((s) => s.startedAt.isBefore(end) || s.startedAt.isAtSameMomentAs(end)).toList();
        return list.length;
      case ReportType.transactionLog:
        var list = _repo.transactions;
        if (start != null) list = list.where((t) => t.timestamp.isAfter(start) || t.timestamp.isAtSameMomentAs(start)).toList();
        if (end != null) list = list.where((t) => t.timestamp.isBefore(end) || t.timestamp.isAtSameMomentAs(end)).toList();
        return list.length;
    }
  }

  // =========================================================================
  // 1. FORM MẪU: PHIẾU NHẬP KHO (GOODS RECEIPT NOTE)
  // =========================================================================
  List<Map<String, dynamic>> _getGroupedInboundSkuRows(InboundOrder ord, List<Item> allItems) {
    final ordItems = allItems.where((it) => it.orderNo == ord.orderNo || it.orderNo == ord.inboundOrderId).toList();
    final Map<String, InboundOrderDetail> detailMap = {};
    for (final d in ord.details) {
      final key = d.sku.trim().isNotEmpty ? d.sku.trim().toUpperCase() : d.productId.trim().toUpperCase();
      if (key.isEmpty) continue;
      if (!detailMap.containsKey(key)) {
        detailMap[key] = d;
      } else {
        final cur = detailMap[key]!;
        detailMap[key] = InboundOrderDetail(
          productId: cur.productId.isNotEmpty ? cur.productId : d.productId,
          sku: cur.sku.isNotEmpty ? cur.sku : d.sku,
          productName: cur.productName.isNotEmpty ? cur.productName : d.productName,
          requiredQty: cur.requiredQty > 0 ? cur.requiredQty : d.requiredQty,
          receivedQty: cur.receivedQty > d.receivedQty ? cur.receivedQty : d.receivedQty,
        );
      }
    }

    final List<Map<String, dynamic>> rows = [];
    if (ordItems.isNotEmpty) {
      final Map<String, List<Item>> skuGroups = {};
      for (final it in ordItems) {
        final key = it.sku.trim().isNotEmpty ? it.sku.trim().toUpperCase() : 'CHƯA CÓ SKU';
        skuGroups.putIfAbsent(key, () => []).add(it);
      }
      // Bổ sung các SKU có trong ord.details nhưng chưa có trong ordItems (nếu có)
      for (final entry in detailMap.entries) {
        if (!skuGroups.containsKey(entry.key)) {
          skuGroups[entry.key] = const [];
        }
      }

      for (final entry in skuGroups.entries) {
        final rawGroupItems = entry.value;
        final receivedGroupItems = rawGroupItems.where((i) => i.status != ItemStatus.pendingInbound).toList();
        final groupItems = receivedGroupItems.isNotEmpty ? receivedGroupItems : rawGroupItems;
        final matchedDetail = detailMap[entry.key];
        final displaySku = groupItems.isNotEmpty
            ? (groupItems.first.sku.trim().isNotEmpty ? groupItems.first.sku.trim() : entry.key)
            : (matchedDetail?.sku.trim().isNotEmpty == true ? matchedDetail!.sku.trim() : entry.key);
        final rawName = matchedDetail != null && matchedDetail.productName.trim().isNotEmpty
            ? matchedDetail.productName
            : (groupItems.isNotEmpty ? groupItems.first.productName : displaySku);
        final cleanProductName = _repo.getSkuProductName(displaySku, rawName);

        final cartons = groupItems
            .map((i) => i.cartonDisplay.trim())
            .where((c) => c.isNotEmpty && c != '--')
            .toSet()
            .join(', ');
        final pallets = groupItems
            .map((i) => (i.palletId ?? '').trim())
            .where((p) => p.isNotEmpty && p != '--')
            .toSet()
            .join(', ');
        final locations = groupItems
            .map((i) => (i.locationId ?? '').trim())
            .where((l) => l.isNotEmpty && l != '--')
            .toSet()
            .join(', ');
        final epcs = groupItems
            .map((i) => i.epc.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();

        final int qty = groupItems.isNotEmpty
            ? groupItems.length
            : (matchedDetail != null
                ? (matchedDetail.receivedQty > 0 ? matchedDetail.receivedQty : matchedDetail.requiredQty)
                : 0);

        rows.add({
          'sku': displaySku,
          'productName': cleanProductName,
          'carton': cartons.isNotEmpty ? cartons : '--',
          'pallet': pallets.isNotEmpty ? pallets : '--',
          'location': locations.isNotEmpty ? locations : '--',
          'qty': qty,
          'epcCount': epcs.length,
          'epcs': epcs.isNotEmpty ? epcs.join('\r\n') : '--',
          'epcsCsv': epcs.isNotEmpty ? epcs.join('; ') : '--',
          'status': groupItems.isNotEmpty ? 'Đã nhập kho' : ord.status.label,
        });
      }
    } else if (detailMap.isNotEmpty) {
      for (final d in detailMap.values) {
        final displaySku = d.sku.trim().isNotEmpty ? d.sku.trim() : d.productId;
        final cleanProductName = _repo.getSkuProductName(displaySku, d.productName);
        final int qty = d.receivedQty > 0 ? d.receivedQty : d.requiredQty;
        final statusLabel = (ord.status == InboundOrderStatus.completed || ord.status == InboundOrderStatus.waitingPutaway)
            ? 'Đã nhập kho'
            : ord.status.label;
        rows.add({
          'sku': displaySku,
          'productName': cleanProductName,
          'carton': '--',
          'pallet': '--',
          'location': '--',
          'qty': qty,
          'epcCount': 0,
          'epcs': '--',
          'epcsCsv': '--',
          'status': statusLabel,
        });
      }
    }
    return rows;
  }

  Future<File> _exportInboundForm(
    ReportFormat format, {
    List<String>? selectedOrderNos,
    DateTime? fromDate,
    DateTime? toDate,
    bool includeEpc = false,
  }) async {
    var orders = _repo.inboundOrders;
    if (fromDate != null) {
      final start = DateTime(fromDate.year, fromDate.month, fromDate.day, 0, 0, 0);
      orders = orders.where((o) => o.createdAt.isAfter(start) || o.createdAt.isAtSameMomentAs(start)).toList();
    }
    if (toDate != null) {
      final end = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59, 999);
      orders = orders.where((o) => o.createdAt.isBefore(end) || o.createdAt.isAtSameMomentAs(end)).toList();
    }
    if (selectedOrderNos != null && selectedOrderNos.isNotEmpty) {
      orders = orders.where((o) => selectedOrderNos.contains(o.orderNo)).toList();
    }
    final allItems = _repo.items;

    final dir = await _getReportDir();
    final timestamp = _fileFmt.format(DateTime.now());
    final fileName = '${ReportType.inbound.filePrefix}_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    if (format == ReportFormat.csv) {
      // Xuất CSV dạng Form có cấu trúc chuẩn (Gộp 1 hàng / Mã SKU)
      final buffer = StringBuffer();
      buffer.writeln('\uFEFFHỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)');
      buffer.writeln('TRUNG TÂM XUẤT BIỂU MẪU PHIẾU NHẬP KHO');
      buffer.writeln('Ngày kết xuất: ${_dtFmt.format(DateTime.now())};Tổng số đơn xuất: ${orders.length}');
      buffer.writeln();

      for (int i = 0; i < orders.length; i++) {
        final ord = orders[i];
        final groupedRows = _getGroupedInboundSkuRows(ord, allItems);
        final totalQty = groupedRows.fold<int>(0, (s, r) => s + (r['qty'] as int));
        final totalChips = groupedRows.fold<int>(0, (s, r) => s + (r['epcCount'] as int));

        buffer.writeln('================================================================================');
        buffer.writeln('PHIẾU NHẬP KHO: ${ord.orderNo}');
        buffer.writeln('Nhà cung cấp: ${ord.sourceSupplier};Ngày tạo: ${_dtFmt.format(ord.createdAt)};Trạng thái: ${ord.status.label}');
        buffer.writeln('Kho tiếp nhận: Kho Tổng RFID;Đơn vị: RFID WMS Platform;Người lập: Quản lý kho');
        buffer.writeln();

        if (includeEpc) {
          buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,Mã Thùng,Mã Pallet,Vị Trí Kệ,Số Lượng,Mã Chip RFID (EPC),Trạng Thái');
          if (groupedRows.isNotEmpty) {
            for (int r = 0; r < groupedRows.length; r++) {
              final row = groupedRows[r];
              final epcVal = row['epcsCsv'] ?? (row['epcs'] as String).replaceAll('\r\n', '; ');
              buffer.writeln(
                '${r + 1},${row['sku']},"${row['productName']}","${row['carton']}","${row['pallet']}","${row['location']}",${row['qty']},"$epcVal",${row['status']}',
              );
            }
          } else {
            buffer.writeln('1,--,Chưa có dữ liệu chi tiết hàng hóa,--,--,--,0,--,--');
          }
          buffer.writeln('TỔNG CỘNG,"Tổng SKU: ${groupedRows.length}",,,,,"Tổng SL: $totalQty","Tổng Chip: $totalChips",Đã nhập kho');
        } else {
          buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,Mã Thùng,Mã Pallet,Vị Trí Kệ,Số Lượng,Trạng Thái');
          if (groupedRows.isNotEmpty) {
            for (int r = 0; r < groupedRows.length; r++) {
              final row = groupedRows[r];
              buffer.writeln(
                '${r + 1},${row['sku']},"${row['productName']}","${row['carton']}","${row['pallet']}","${row['location']}",${row['qty']},${row['status']}',
              );
            }
          } else {
            buffer.writeln('1,--,Chưa có dữ liệu chi tiết hàng hóa,--,--,--,0,--');
          }
          buffer.writeln('TỔNG CỘNG,"Tổng SKU: ${groupedRows.length}",,,,,"Tổng SL: $totalQty",Đã nhập kho');
        }

        buffer.writeln();
        buffer.writeln('NGƯỜI LẬP PHIẾU,NGƯỜI GIAO HÀNG,THỦ KHO NHẬN,KẾ TOÁN TRƯỞNG');
        buffer.writeln('(Ký ghi rõ họ tên),(Ký ghi rõ họ tên),(Ký ghi rõ họ tên),(Ký ghi rõ họ tên)');
        buffer.writeln();
      }

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      return file;
    } else {
      // Xuất Excel .xlsx chuẩn Form Doanh Nghiệp (Gộp 1 hàng / Mã SKU)
      final excel = Excel.createExcel();

      // Nếu có nhiều đơn: Tạo Sheet 1 là Bảng Tổng Hợp
      if (orders.length > 1) {
        final summarySheet = excel['Tong_Hop_Don_Nhap'];
        _buildInboundSummarySheet(summarySheet, orders, allItems);
      }

      // Tạo từng Sheet phiếu cho mỗi đơn hàng được chọn
      for (final ord in orders) {
        final sheetName = _safeSheetName('Don', ord.orderNo);
        final sheet = excel[sheetName];
        _buildSingleInboundOrderSheet(sheet, ord, allItems, includeEpc: includeEpc);
      }

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      return _saveProtectedExcelFile(excel, filePath);
    }
  }

  void _buildSingleInboundOrderSheet(Sheet sheet, InboundOrder ord, List<Item> allItems, {bool includeEpc = true}) {
    final groupedRows = _getGroupedInboundSkuRows(ord, allItems);
    final totalQty = groupedRows.fold<int>(0, (s, r) => s + (r['qty'] as int));
    final totalChips = groupedRows.fold<int>(0, (s, r) => s + (r['epcCount'] as int));
    final skuCount = groupedRows.length;

    // Header Form
    _setCell(sheet, col: 0, row: 0, value: 'HỆ THỐNG KHO VẬN THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
    _setCell(sheet, col: 0, row: 1, value: 'PHIẾU NHẬP KHO (GOODS RECEIPT NOTE)', style: _titleStyle);
    _setCell(sheet, col: 0, row: 2, value: '(Ban hành theo quy trình vận hành kho RFID Gate tự động)', style: _subTitleStyle);

    // Meta Info
    _setCell(sheet, col: 0, row: 4, value: 'Mã Đơn Nhập:', style: _metaLabelStyle);
    _setCell(sheet, col: 1, row: 4, value: ord.orderNo, style: _metaValueStyle);
    _setCell(sheet, col: 3, row: 4, value: 'Ngày Nhập Kho:', style: _metaLabelStyle);
    _setCell(sheet, col: 4, row: 4, value: _dtFmt.format(ord.createdAt), style: _metaValueStyle);

    _setCell(sheet, col: 0, row: 5, value: 'Nhà Cung Cấp:', style: _metaLabelStyle);
    _setCell(sheet, col: 1, row: 5, value: ord.sourceSupplier.isNotEmpty ? ord.sourceSupplier : 'Nhà cung cấp', style: _metaValueStyle);
    _setCell(sheet, col: 3, row: 5, value: 'Trạng Thái:', style: _metaLabelStyle);
    _setCell(sheet, col: 4, row: 5, value: ord.status.label, style: _metaValueStyle);

    _setCell(sheet, col: 0, row: 6, value: 'Kho Tiếp Nhận:', style: _metaLabelStyle);
    _setCell(sheet, col: 1, row: 6, value: 'Kho Tổng RFID', style: _metaValueStyle);
    _setCell(sheet, col: 3, row: 6, value: 'Người Lập Phiếu:', style: _metaLabelStyle);
    _setCell(sheet, col: 4, row: 6, value: 'Thủ Kho Quản Trị', style: _metaValueStyle);

    // Table Header
    final headers = includeEpc
        ? ['STT', 'Mã SKU', 'Tên Sản Phẩm', 'Mã Thùng', 'Mã Pallet', 'Vị Trí Kệ', 'Số Lượng', 'Mã Chip RFID (EPC)', 'Trạng Thái']
        : ['STT', 'Mã SKU', 'Tên Sản Phẩm', 'Mã Thùng', 'Mã Pallet', 'Vị Trí Kệ', 'Số Lượng', 'Trạng Thái'];
    const startRow = 8;
    for (int col = 0; col < headers.length; col++) {
      _setCell(sheet, col: col, row: startRow, value: headers[col], style: _tableHeaderStyle('#0284C7'));
    }

    int currentRow = startRow + 1;
    if (groupedRows.isNotEmpty) {
      for (int i = 0; i < groupedRows.length; i++) {
        final row = groupedRows[i];
        _setCell(sheet, col: 0, row: currentRow, value: '${i + 1}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 1, row: currentRow, value: row['sku'] as String);
        _setCell(sheet, col: 2, row: currentRow, value: row['productName'] as String);
        _setCell(sheet, col: 3, row: currentRow, value: row['carton'] as String, style: _dataCellCenterStyle);
        _setCell(sheet, col: 4, row: currentRow, value: row['pallet'] as String, style: _dataCellCenterStyle);
        _setCell(sheet, col: 5, row: currentRow, value: row['location'] as String, style: _dataCellCenterStyle);
        _setCell(sheet, col: 6, row: currentRow, value: '${row['qty']}', style: _dataCellCenterStyle);
        if (includeEpc) {
          _setCell(sheet, col: 7, row: currentRow, value: row['epcs'] as String, style: _epcCellStyle);
          _setCell(sheet, col: 8, row: currentRow, value: row['status'] as String, style: _dataCellCenterStyle);
          final epcCount = row['epcCount'] as int? ?? 1;
          sheet.setRowHeight(currentRow, epcCount > 1 ? (epcCount * 17.0).clamp(24.0, 400.0) : 24.0);
        } else {
          _setCell(sheet, col: 7, row: currentRow, value: row['status'] as String, style: _dataCellCenterStyle);
          sheet.setRowHeight(currentRow, 24.0);
        }
        currentRow++;
      }
    } else {
      _setCell(sheet, col: 0, row: currentRow, value: '1', style: _dataCellCenterStyle);
      _setCell(sheet, col: 1, row: currentRow, value: '--');
      _setCell(sheet, col: 2, row: currentRow, value: 'Chưa có chi tiết mặt hàng trong đơn');
      for (int c = 3; c < headers.length; c++) {
        _setCell(sheet, col: c, row: currentRow, value: '--', style: _dataCellCenterStyle);
      }
      sheet.setRowHeight(currentRow, 24.0);
      currentRow++;
    }

    // Total Row
    _setCell(sheet, col: 0, row: currentRow, value: 'TỔNG CỘNG', style: _totalRowStyle);
    _setCell(sheet, col: 1, row: currentRow, value: 'Tổng SKU: $skuCount', style: _totalRowStyle);
    _setCell(sheet, col: 2, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 3, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 4, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 5, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 6, row: currentRow, value: 'Tổng SL: $totalQty', style: _totalRowStyle);
    if (includeEpc) {
      _setCell(sheet, col: 7, row: currentRow, value: 'Tổng Chip: $totalChips', style: _totalRowStyle);
      _setCell(sheet, col: 8, row: currentRow, value: 'Đã nhập kho', style: _totalRowStyle);
    } else {
      _setCell(sheet, col: 7, row: currentRow, value: 'Đã nhập kho', style: _totalRowStyle);
    }

    // Signatures
    final signRow = currentRow + 3;
    _setCell(sheet, col: 0, row: signRow, value: 'NGƯỜI LẬP PHIẾU', style: _signTitleStyle);
    _setCell(sheet, col: 2, row: signRow, value: 'NGƯỜI GIAO HÀNG', style: _signTitleStyle);
    _setCell(sheet, col: includeEpc ? 5 : 4, row: signRow, value: 'THỦ KHO NHẬN', style: _signTitleStyle);
    _setCell(sheet, col: includeEpc ? 7 : 6, row: signRow, value: 'KẾ TOÁN TRƯỞNG', style: _signTitleStyle);

    _setCell(sheet, col: 0, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: 2, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: includeEpc ? 5 : 4, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: includeEpc ? 7 : 6, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);

    _autoFitColumns(sheet, headers.length, signRow + 3);
  }

  void _buildInboundSummarySheet(Sheet sheet, List<InboundOrder> orders, List<Item> allItems) {
    _setCell(sheet, col: 0, row: 0, value: 'HỆ THỐNG KHO VẬN THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
    _setCell(sheet, col: 0, row: 1, value: 'BẢNG TỔNG HỢP CÁC ĐƠN NHẬP KHO ĐÃ CHỌN', style: _titleStyle);
    _setCell(sheet, col: 0, row: 2, value: 'Thời điểm xuất: ${_dtFmt.format(DateTime.now())}   |   Số lượng đơn: ${orders.length}', style: _subTitleStyle);

    final headers = ['STT', 'Mã Đơn Nhập', 'Nhà Cung Cấp', 'Ngày Tạo', 'Số Chủng Loại SKU', 'Tổng Số Lượng', 'Tổng Chip RFID', 'Trạng Thái'];
    const startRow = 4;
    for (int c = 0; c < headers.length; c++) {
      _setCell(sheet, col: c, row: startRow, value: headers[c], style: _tableHeaderStyle('#0284C7'));
    }

    int row = startRow + 1;
    int grandTotalItems = 0;
    int grandTotalChips = 0;

    for (int i = 0; i < orders.length; i++) {
      final ord = orders[i];
      final groupedRows = _getGroupedInboundSkuRows(ord, allItems);
      final totalQty = groupedRows.fold<int>(0, (s, r) => s + (r['qty'] as int));
      final totalChips = groupedRows.fold<int>(0, (s, r) => s + (r['epcCount'] as int));
      final skuCount = groupedRows.length;

      grandTotalItems += totalQty;
      grandTotalChips += totalChips;

      _setCell(sheet, col: 0, row: row, value: '${i + 1}', style: _dataCellCenterStyle);
      _setCell(sheet, col: 1, row: row, value: ord.orderNo);
      _setCell(sheet, col: 2, row: row, value: ord.sourceSupplier);
      _setCell(sheet, col: 3, row: row, value: _dtFmt.format(ord.createdAt), style: _dataCellCenterStyle);
      _setCell(sheet, col: 4, row: row, value: '$skuCount', style: _dataCellCenterStyle);
      _setCell(sheet, col: 5, row: row, value: '$totalQty', style: _dataCellCenterStyle);
      _setCell(sheet, col: 6, row: row, value: '$totalChips', style: _dataCellCenterStyle);
      _setCell(sheet, col: 7, row: row, value: ord.status.label, style: _dataCellCenterStyle);
      row++;
    }

    // Grand total
    _setCell(sheet, col: 0, row: row, value: 'TỔNG CỘNG', style: _totalRowStyle);
    _setCell(sheet, col: 1, row: row, value: '${orders.length} Đơn nhập', style: _totalRowStyle);
    _setCell(sheet, col: 2, row: row, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 3, row: row, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 4, row: row, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 5, row: row, value: '$grandTotalItems sản phẩm', style: _totalRowStyle);
    _setCell(sheet, col: 6, row: row, value: '$grandTotalChips chip RFID', style: _totalRowStyle);
    _setCell(sheet, col: 7, row: row, value: '', style: _totalRowStyle);

    _autoFitColumns(sheet, headers.length, row + 2);
  }

  // =========================================================================
  // 2. FORM MẪU: PHIẾU XUẤT KHO KIÊM BÀN GIAO (GOODS DELIVERY NOTE)
  // =========================================================================
  List<OutboundOrderDetail> _getGroupedOutboundDetails(OutboundOrder ord) {
    final Map<String, OutboundOrderDetail> dedupDetails = {};
    for (final d in ord.details) {
      final key = d.sku.trim().isNotEmpty ? d.sku.trim().toUpperCase() : d.productId.trim().toUpperCase();
      if (key.isEmpty) continue;
      final cleanName = _repo.getSkuProductName(d.sku, d.productName);
      if (!dedupDetails.containsKey(key)) {
        dedupDetails[key] = OutboundOrderDetail(
          productId: d.productId,
          sku: d.sku.trim().isNotEmpty ? d.sku.trim() : d.productId,
          productName: cleanName,
          requiredQty: d.requiredQty,
          pickedQty: d.pickedQty,
          epcList: d.epcList != null ? {...d.epcList!}.toList() : null,
          snList: d.snList != null ? {...d.snList!}.toList() : null,
        );
      } else {
        final cur = dedupDetails[key]!;
        dedupDetails[key] = OutboundOrderDetail(
          productId: cur.productId.isNotEmpty ? cur.productId : d.productId,
          sku: cur.sku.isNotEmpty ? cur.sku : d.sku,
          productName: cur.productName.isNotEmpty ? cur.productName : cleanName,
          requiredQty: cur.requiredQty > 0 ? cur.requiredQty : d.requiredQty,
          pickedQty: cur.pickedQty > d.pickedQty ? cur.pickedQty : d.pickedQty,
          epcList: {...?cur.epcList, ...?d.epcList}.toList(),
          snList: {...?cur.snList, ...?d.snList}.toList(),
        );
      }
    }

    if (dedupDetails.isEmpty) {
      final txs = _repo.transactions.where((t) =>
          t.type == TransactionType.outbound &&
          (t.documentNo.trim().toUpperCase() == ord.poNo.trim().toUpperCase() ||
           t.documentNo.trim().toUpperCase() == ord.outboundOrderId.trim().toUpperCase() ||
           (ord.poNo.isNotEmpty && t.transactionId.contains(ord.poNo)) ||
           (ord.outboundOrderId.isNotEmpty && t.transactionId.contains(ord.outboundOrderId)))).toList();
      for (final t in txs) {
        final key = t.sku.trim().isNotEmpty ? t.sku.trim().toUpperCase() : 'CHƯA CÓ SKU';
        final cleanName = _repo.getSkuProductName(
          t.sku,
          t.productName.isNotEmpty ? t.productName : 'Sản phẩm xuất kho',
        );
        if (!dedupDetails.containsKey(key)) {
          dedupDetails[key] = OutboundOrderDetail(
            productId: t.sku,
            sku: t.sku.trim().isNotEmpty ? t.sku.trim() : key,
            productName: cleanName,
            requiredQty: t.quantity,
            pickedQty: t.quantity,
          );
        } else {
          final cur = dedupDetails[key]!;
          dedupDetails[key] = OutboundOrderDetail(
            productId: cur.productId,
            sku: cur.sku,
            productName: cur.productName,
            requiredQty: cur.requiredQty + t.quantity,
            pickedQty: cur.pickedQty + t.quantity,
          );
        }
      }
    }

    return dedupDetails.values.map((d) {
      final picked = (d.pickedQty == 0 && d.requiredQty > 0 && ord.status == OutboundOrderStatus.shipped)
          ? d.requiredQty
          : d.pickedQty;
      return OutboundOrderDetail(
        productId: d.productId,
        sku: d.sku,
        productName: _repo.getSkuProductName(d.sku, d.productName),
        requiredQty: d.requiredQty,
        pickedQty: picked,
        epcList: d.epcList,
        snList: d.snList,
      );
    }).toList();
  }

  Future<File> _exportOutboundForm(
    ReportFormat format, {
    List<String>? selectedPoNos,
    DateTime? fromDate,
    DateTime? toDate,
    bool includeEpc = false,
  }) async {
    var orders = _repo.outboundOrders;
    if (fromDate != null) {
      final start = DateTime(fromDate.year, fromDate.month, fromDate.day, 0, 0, 0);
      orders = orders.where((o) => o.createdAt.isAfter(start) || o.createdAt.isAtSameMomentAs(start)).toList();
    }
    if (toDate != null) {
      final end = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59, 999);
      orders = orders.where((o) => o.createdAt.isBefore(end) || o.createdAt.isAtSameMomentAs(end)).toList();
    }
    if (selectedPoNos != null && selectedPoNos.isNotEmpty) {
      orders = orders.where((o) => selectedPoNos.contains(o.poNo)).toList();
    }
    final deliveries = _repo.deliveryNotes;

    final dir = await _getReportDir();
    final timestamp = _fileFmt.format(DateTime.now());
    final isSingle = orders.length == 1;
    final filePo = isSingle ? orders.first.poNo.replaceAll(RegExp(r'[\\/?*:[\]]'), '_') : '';
    final fileName = isSingle
        ? 'phieu_xuat_kho_${filePo}_$timestamp.${format.name}'
        : '${ReportType.outbound.filePrefix}_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    if (format == ReportFormat.csv) {
      final buffer = StringBuffer();
      buffer.writeln('\uFEFFHỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)');
      buffer.writeln('TRUNG TÂM XUẤT BIỂU MẪU PHIẾU XUẤT KHO & GIAO HÀNG');
      buffer.writeln('Ngày kết xuất: ${_dtFmt.format(DateTime.now())};Tổng số đơn xuất: ${orders.length}');
      buffer.writeln();

      for (final ord in orders) {
        final effectiveDetails = _getGroupedOutboundDetails(ord);
        final totalReq = effectiveDetails.fold<int>(0, (s, d) => s + d.requiredQty);
        final totalPicked = effectiveDetails.fold<int>(0, (s, d) => s + d.pickedQty);

        final delivery = deliveries.where((d) => d.poNo == ord.poNo).toList();
        final deliveryNos = delivery.map((d) => d.deliveryNo).join(', ');

        buffer.writeln('================================================================================');
        buffer.writeln('PHIẾU XUẤT KHO KIÊM BÀN GIAO: ${ord.poNo}');
        buffer.writeln('Khách hàng: ${ord.customer};Ngày tạo: ${_dtFmt.format(ord.createdAt)};Trạng thái: ${ord.status.label}');
        buffer.writeln('Mã vận đơn: ${deliveryNos.isEmpty ? "--" : deliveryNos};Kho xuất: Kho Tổng RFID;Quy tắc: Chuẩn FIFO');
        buffer.writeln();

        if (includeEpc) {
          buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,SL Yêu Cầu,SL Thực Xuất,Vị Trí Lấy Hàng,Mã Pallet,Mã Sê-ri (SN),Mã Chip RFID (EPC),Ghi Chú');
          if (effectiveDetails.isNotEmpty) {
            for (int r = 0; r < effectiveDetails.length; r++) {
              final d = effectiveDetails[r];
              final skuSns = _repo.getOrderSkuShippedSerialNumbers(ord, d.sku);
              final sns = skuSns.isNotEmpty ? skuSns.join('; ') : (d.snList != null && d.snList!.isNotEmpty ? d.snList!.join('; ') : '--');
              final epcs = d.epcList != null && d.epcList!.isNotEmpty ? d.epcList!.join('; ') : '--';
              buffer.writeln('${r + 1},${d.sku},"${d.productName}",${d.requiredQty},${d.pickedQty},Kho Tổng,Pallet xuất,"$sns","$epcs",Đạt chuẩn FIFO');
            }
          }
          buffer.writeln('TỔNG CỘNG,"Tổng SKU: ${effectiveDetails.length}",,"Tổng YC: $totalReq","Tổng Xuất: $totalPicked",,,,,Đạt chuẩn xuất kho');
        } else {
          buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,SL Yêu Cầu,SL Thực Xuất,Vị Trí Lấy Hàng,Mã Pallet,Mã Sê-ri (SN),Ghi Chú');
          if (effectiveDetails.isNotEmpty) {
            for (int r = 0; r < effectiveDetails.length; r++) {
              final d = effectiveDetails[r];
              final skuSns = _repo.getOrderSkuShippedSerialNumbers(ord, d.sku);
              final sns = skuSns.isNotEmpty ? skuSns.join('; ') : (d.snList != null && d.snList!.isNotEmpty ? d.snList!.join('; ') : '--');
              buffer.writeln('${r + 1},${d.sku},"${d.productName}",${d.requiredQty},${d.pickedQty},Kho Tổng,Pallet xuất,"$sns",Đạt chuẩn FIFO');
            }
          }
          buffer.writeln('TỔNG CỘNG,"Tổng SKU: ${effectiveDetails.length}",,"Tổng YC: $totalReq","Tổng Xuất: $totalPicked",,,,Đạt chuẩn xuất kho');
        }

        buffer.writeln();
        buffer.writeln('NGƯỜI LẬP PHIẾU,NGƯỜI NHẬN HÀNG,THỦ KHO XUẤT,GIÁM ĐỐC / KẾ TOÁN');
        buffer.writeln('(Ký ghi rõ họ tên),(Ký ghi rõ họ tên),(Ký ghi rõ họ tên),(Ký ghi rõ họ tên)');
        buffer.writeln();
      }

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      return file;
    } else {
      final excel = Excel.createExcel();

      if (orders.length > 1) {
        final summarySheet = excel['Tong_Hop_Don_Xuat'];
        _buildOutboundSummarySheet(summarySheet, orders, deliveries);
      }

      for (final ord in orders) {
        final sheetName = _safeSheetName('Don', ord.poNo);
        final sheet = excel[sheetName];
        _buildSingleOutboundOrderSheet(sheet, ord, deliveries, includeEpc: includeEpc);
      }

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      return _saveProtectedExcelFile(excel, filePath);
    }
  }

  void _buildSingleOutboundOrderSheet(Sheet sheet, OutboundOrder ord, List<DeliveryNote> deliveries, {bool includeEpc = true}) {
    final effectiveDetails = _getGroupedOutboundDetails(ord);
    final totalReq = effectiveDetails.fold<int>(0, (s, d) => s + d.requiredQty);
    final totalPicked = effectiveDetails.fold<int>(0, (s, d) => s + d.pickedQty);
    final delivery = deliveries.where((d) => d.poNo == ord.poNo).toList();
    final deliveryNos = delivery.map((d) => d.deliveryNo).join(', ');

    _setCell(sheet, col: 0, row: 0, value: 'HỆ THỐNG KHO VẬN THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
    _setCell(sheet, col: 0, row: 1, value: 'PHIẾU XUẤT KHO KIÊM BÀN GIAO HÀNG HÓA', style: _titleStyle);
    _setCell(sheet, col: 0, row: 2, value: '(Ban hành theo quy trình kiểm soát xuất kho RFID Gate & FIFO)', style: _subTitleStyle);

    _setCell(sheet, col: 0, row: 4, value: 'Mã Đơn / PO:', style: _metaLabelStyle);
    _setCell(sheet, col: 1, row: 4, value: ord.poNo, style: _metaValueStyle);
    _setCell(sheet, col: 3, row: 4, value: 'Ngày Xuất Kho:', style: _metaLabelStyle);
    _setCell(sheet, col: 4, row: 4, value: _dtFmt.format(ord.createdAt), style: _metaValueStyle);

    _setCell(sheet, col: 0, row: 5, value: 'Khách Hàng:', style: _metaLabelStyle);
    _setCell(sheet, col: 1, row: 5, value: ord.customer.isNotEmpty ? ord.customer : 'Khách hàng', style: _metaValueStyle);
    _setCell(sheet, col: 3, row: 5, value: 'Trạng Thái:', style: _metaLabelStyle);
    _setCell(sheet, col: 4, row: 5, value: ord.status.label, style: _metaValueStyle);

    _setCell(sheet, col: 0, row: 6, value: 'Mã Vận Đơn:', style: _metaLabelStyle);
    _setCell(sheet, col: 1, row: 6, value: deliveryNos.isEmpty ? '--' : deliveryNos, style: _metaValueStyle);
    _setCell(sheet, col: 3, row: 6, value: 'Quy Tắc Đối Soát:', style: _metaLabelStyle);
    _setCell(sheet, col: 4, row: 6, value: 'Chuẩn FIFO Date xa nhất', style: _metaValueStyle);

    final headers = includeEpc
        ? ['STT', 'Mã SKU', 'Tên Sản Phẩm', 'SL Yêu Cầu', 'SL Thực Xuất', 'Vị Trí Lấy Hàng', 'Mã Pallet', 'Mã Sê-ri (SN)', 'Mã Chip RFID (EPC)', 'Ghi Chú']
        : ['STT', 'Mã SKU', 'Tên Sản Phẩm', 'SL Yêu Cầu', 'SL Thực Xuất', 'Vị Trí Lấy Hàng', 'Mã Pallet', 'Mã Sê-ri (SN)', 'Ghi Chú'];
    const startRow = 8;
    for (int col = 0; col < headers.length; col++) {
      _setCell(sheet, col: col, row: startRow, value: headers[col], style: _tableHeaderStyle('#3B82F6'));
    }

    int currentRow = startRow + 1;
    if (effectiveDetails.isNotEmpty) {
      for (int i = 0; i < effectiveDetails.length; i++) {
        final d = effectiveDetails[i];
        final allOrderSns = _repo.getOrderShippedSerialNumbers(ord);
        final skuSns = _repo.getOrderSkuShippedSerialNumbers(ord, d.sku);
        final effectiveSns = skuSns.isNotEmpty
            ? skuSns
            : (d.snList != null && d.snList!.isNotEmpty
                ? d.snList!
                : (effectiveDetails.length == 1 ? allOrderSns : <String>[]));
        final snDisplay = effectiveSns.isNotEmpty ? effectiveSns.join('\r\n') : '--';
        final epcs = d.epcList != null && d.epcList!.isNotEmpty ? d.epcList!.join('\r\n') : '--';

        _setCell(sheet, col: 0, row: currentRow, value: '${i + 1}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 1, row: currentRow, value: d.sku, style: _dataCellCenterStyle);
        _setCell(sheet, col: 2, row: currentRow, value: d.productName, style: _dataCellCenterStyle);
        _setCell(sheet, col: 3, row: currentRow, value: '${d.requiredQty}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 4, row: currentRow, value: '${d.pickedQty}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 5, row: currentRow, value: 'Kho Tổng RFID', style: _dataCellCenterStyle);
        _setCell(sheet, col: 6, row: currentRow, value: 'Pallet Xuất', style: _dataCellCenterStyle);
        _setCell(sheet, col: 7, row: currentRow, value: snDisplay, style: _multiLineCenterCellStyle);

        if (includeEpc) {
          _setCell(sheet, col: 8, row: currentRow, value: epcs, style: _multiLineCenterCellStyle);
          _setCell(sheet, col: 9, row: currentRow, value: 'Đạt chuẩn FIFO', style: _dataCellCenterStyle);
        } else {
          _setCell(sheet, col: 8, row: currentRow, value: 'Đạt chuẩn FIFO', style: _dataCellCenterStyle);
        }

        final lineCount = [
          effectiveSns.isNotEmpty ? effectiveSns.length : 1,
          d.epcList?.length ?? 1,
        ].reduce((a, b) => a > b ? a : b);
        sheet.setRowHeight(currentRow, lineCount > 1 ? (lineCount * 18.0).clamp(26.0, 500.0) : 26.0);
        currentRow++;
      }
    } else {
      _setCell(sheet, col: 0, row: currentRow, value: '1', style: _dataCellCenterStyle);
      _setCell(sheet, col: 1, row: currentRow, value: '--', style: _dataCellCenterStyle);
      _setCell(sheet, col: 2, row: currentRow, value: 'Chưa có chi tiết mặt hàng', style: _dataCellCenterStyle);
      for (int c = 3; c < headers.length; c++) {
        _setCell(sheet, col: c, row: currentRow, value: '--', style: _dataCellCenterStyle);
      }
      sheet.setRowHeight(currentRow, 26.0);
      currentRow++;
    }

    _setCell(sheet, col: 0, row: currentRow, value: 'TỔNG CỘNG', style: _totalRowStyle);
    _setCell(sheet, col: 1, row: currentRow, value: 'Tổng SKU: ${effectiveDetails.length}', style: _totalRowStyle);
    _setCell(sheet, col: 2, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 3, row: currentRow, value: 'Tổng YC: $totalReq', style: _totalRowStyle);
    _setCell(sheet, col: 4, row: currentRow, value: 'Tổng Xuất: $totalPicked', style: _totalRowStyle);
    _setCell(sheet, col: 5, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 6, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 7, row: currentRow, value: '', style: _totalRowStyle);
    if (includeEpc) {
      _setCell(sheet, col: 8, row: currentRow, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 9, row: currentRow, value: 'Đạt chuẩn xuất', style: _totalRowStyle);
    } else {
      _setCell(sheet, col: 8, row: currentRow, value: 'Đạt chuẩn xuất', style: _totalRowStyle);
    }
    sheet.setRowHeight(currentRow, 26.0);

    final signRow = currentRow + 3;
    _setCell(sheet, col: 0, row: signRow, value: 'NGƯỜI LẬP PHIẾU', style: _signTitleStyle);
    _setCell(sheet, col: 2, row: signRow, value: 'NGƯỜI NHẬN HÀNG', style: _signTitleStyle);
    _setCell(sheet, col: includeEpc ? 5 : 4, row: signRow, value: 'THỦ KHO XUẤT', style: _signTitleStyle);
    _setCell(sheet, col: includeEpc ? 7 : 6, row: signRow, value: 'GIÁM ĐỐC / KẾ TOÁN', style: _signTitleStyle);

    _setCell(sheet, col: 0, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: 2, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: includeEpc ? 5 : 4, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: includeEpc ? 7 : 6, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);

    _autoFitColumns(sheet, headers.length, signRow + 3);
  }

  void _buildOutboundSummarySheet(Sheet sheet, List<OutboundOrder> orders, List<DeliveryNote> deliveries) {
    _setCell(sheet, col: 0, row: 0, value: 'HỆ THỐNG KHO VẬN THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
    _setCell(sheet, col: 0, row: 1, value: 'BẢNG TỔNG HỢP CÁC ĐƠN XUẤT KHO ĐÃ CHỌN', style: _titleStyle);
    _setCell(sheet, col: 0, row: 2, value: 'Thời điểm xuất: ${_dtFmt.format(DateTime.now())}   |   Số lượng đơn: ${orders.length}', style: _subTitleStyle);

    final headers = [
      'STT',
      'Mã PO / Đơn Xuất',
      'Khách Hàng',
      'Ngày Tạo',
      'Số Loại SKU',
      'SL Yêu Cầu',
      'SL Đã Xuất',
      'Mã Sê-ri (SN) Đã Xuất',
      'Mã Vận Đơn',
      'Trạng Thái',
    ];
    const startRow = 4;
    for (int c = 0; c < headers.length; c++) {
      _setCell(sheet, col: c, row: startRow, value: headers[c], style: _tableHeaderStyle('#3B82F6'));
    }

    int row = startRow + 1;
    int grandReq = 0;
    int grandPicked = 0;

    for (int i = 0; i < orders.length; i++) {
      final ord = orders[i];
      final cleanDetails = _getGroupedOutboundDetails(ord);
      final totalReq = cleanDetails.fold<int>(0, (s, d) => s + d.requiredQty);
      final totalPicked = cleanDetails.fold<int>(0, (s, d) => s + d.pickedQty);
      final delivery = deliveries.where((d) => d.poNo == ord.poNo).toList();
      final deliveryNos = delivery.map((d) => d.deliveryNo).join(', ');

      grandReq += totalReq;
      grandPicked += totalPicked;

      final snList = _repo.getOrderShippedSerialNumbers(ord);
      final snDisplay = snList.isNotEmpty ? snList.join('\r\n') : '--';

      _setCell(sheet, col: 0, row: row, value: '${i + 1}', style: _dataCellCenterStyle);
      _setCell(sheet, col: 1, row: row, value: ord.poNo, style: _dataCellCenterStyle);
      _setCell(sheet, col: 2, row: row, value: ord.customer.isNotEmpty ? ord.customer : 'Khách mua xuất kho', style: _dataCellCenterStyle);
      _setCell(sheet, col: 3, row: row, value: _dtFmt.format(ord.createdAt), style: _dataCellCenterStyle);
      _setCell(sheet, col: 4, row: row, value: '${cleanDetails.length}', style: _dataCellCenterStyle);
      _setCell(sheet, col: 5, row: row, value: '$totalReq', style: _dataCellCenterStyle);
      _setCell(sheet, col: 6, row: row, value: '$totalPicked', style: _dataCellCenterStyle);
      _setCell(sheet, col: 7, row: row, value: snDisplay, style: _multiLineCenterCellStyle);
      _setCell(sheet, col: 8, row: row, value: deliveryNos.isEmpty ? '--' : deliveryNos, style: _dataCellCenterStyle);
      _setCell(sheet, col: 9, row: row, value: ord.status.label, style: _dataCellCenterStyle);

      final lineCount = snList.isNotEmpty ? snList.length : 1;
      sheet.setRowHeight(row, lineCount > 1 ? (lineCount * 18.0).clamp(26.0, 500.0) : 26.0);
      row++;
    }

    _setCell(sheet, col: 0, row: row, value: 'TỔNG CỘNG', style: _totalRowStyle);
    _setCell(sheet, col: 1, row: row, value: '${orders.length} Đơn xuất', style: _totalRowStyle);
    _setCell(sheet, col: 2, row: row, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 3, row: row, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 4, row: row, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 5, row: row, value: '$grandReq SP', style: _totalRowStyle);
    _setCell(sheet, col: 6, row: row, value: '$grandPicked SP', style: _totalRowStyle);
    _setCell(sheet, col: 7, row: row, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 8, row: row, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 9, row: row, value: '', style: _totalRowStyle);
    sheet.setRowHeight(row, 26.0);

    _autoFitColumns(sheet, headers.length, row + 2);
  }

  // =========================================================================
  // 3. FORM MẪU: BIÊN BẢN KIỂM KÊ KHO HÀNG RFID (AUDIT REPORT)
  // =========================================================================
  List<Map<String, dynamic>> _getGroupedAuditSessionRows(InventorySession s) {
    final breakdown = _repo.buildSessionSkuBreakdown(s);
    if (breakdown.isNotEmpty) {
      return breakdown.map((r) {
        final epcs = r.itemResults
            .map((it) => it.epc.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
        final surplusQty = r.difference > 0 ? r.difference : r.unknownCount;
        return {
          'sku': r.sku,
          'productName': _repo.getSkuProductName(r.sku, r.productName),
          'location': r.zoneOrLocation,
          'expectedQty': r.expectedQty,
          'actualQty': r.actualQty,
          'matchedQty': r.matchedCount,
          'missingQty': r.missingCount,
          'surplusQty': surplusQty,
          'shippedQty': r.shippedCount,
          'epcs': epcs.isNotEmpty ? epcs.join('\r\n') : '--',
          'epcsCsv': epcs.isNotEmpty ? epcs.join('; ') : '--',
          'status': r.statusLabel,
        };
      }).toList();
    }

    if (s.results.isEmpty) return [];
    final Map<String, List<InventoryItemResult>> grouped = {};
    for (final res in s.results) {
      final key = (res.sku != null && res.sku!.trim().isNotEmpty) ? res.sku!.trim().toUpperCase() : 'THẺ_LẠ';
      grouped.putIfAbsent(key, () => []).add(res);
    }
    return grouped.entries.map((entry) {
      final list = entry.value;
      final first = list.first;
      final displaySku = (first.sku != null && first.sku!.trim().isNotEmpty) ? first.sku!.trim() : entry.key;
      final cleanName = _repo.getSkuProductName(displaySku, first.productName ?? displaySku);
      final matched = list.where((x) => x.resultType == InventoryVarianceType.match).length;
      final missing = list.where((x) => x.resultType == InventoryVarianceType.missing).length;
      final wrongLoc = list.where((x) => x.resultType == InventoryVarianceType.wrongLocation).length;
      final unknown = list.where((x) => x.resultType == InventoryVarianceType.unknownEpc).length;
      final shipped = list.where((x) => x.expectedLocation == 'ĐÃ XUẤT KHO').length;
      final expected = matched + missing + wrongLoc;
      final actual = matched + wrongLoc + unknown;
      final locs = list
          .map((x) => x.actualLocation ?? x.expectedLocation ?? '')
          .where((l) => l.isNotEmpty)
          .toSet()
          .join(', ');
      final epcs = list.map((x) => x.epc).where((e) => e.isNotEmpty).toSet().join('\r\n');
      final epcsCsv = list.map((x) => x.epc).where((e) => e.isNotEmpty).toSet().join('; ');

      String statusStr = 'Khớp đủ';
      if (shipped > 0) {
        statusStr = '🚨 Có $shipped chip đã xuất';
      } else if (missing > 0) {
        statusStr = 'Lệch thiếu';
      } else if (unknown > 0) {
        statusStr = 'Phát hiện thẻ lạ';
      }

      return {
        'sku': displaySku,
        'productName': cleanName,
        'location': locs.isNotEmpty ? locs : (s.locationCode ?? s.zone),
        'expectedQty': expected,
        'actualQty': actual,
        'matchedQty': matched,
        'missingQty': missing,
        'surplusQty': unknown,
        'shippedQty': shipped,
        'epcs': epcs.isNotEmpty ? epcs : '--',
        'epcsCsv': epcsCsv.isNotEmpty ? epcsCsv : '--',
        'status': statusStr,
      };
    }).toList();
  }

  Future<File> _exportAuditForm(ReportFormat format, {List<String>? selectedSessionCodes, bool includeEpc = false}) async {
    var sessions = _repo.inventorySessions;
    if (selectedSessionCodes != null && selectedSessionCodes.isNotEmpty) {
      sessions = sessions.where((s) => selectedSessionCodes.contains(s.sessionCode) || selectedSessionCodes.contains(s.sessionId)).toList();
    }

    final dir = await _getReportDir();
    final timestamp = _fileFmt.format(DateTime.now());
    final fileName = '${ReportType.audit.filePrefix}_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    if (format == ReportFormat.csv) {
      final buffer = StringBuffer();
      buffer.writeln('\uFEFFHỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)');
      buffer.writeln('TRUNG TÂM XUẤT BIÊN BẢN KIỂM KÊ KHO HÀNG');
      buffer.writeln('Ngày kết xuất: ${_dtFmt.format(DateTime.now())};Số phiên kiểm kê: ${sessions.length}');
      buffer.writeln();

      for (final s in sessions) {
        final groupedRows = _getGroupedAuditSessionRows(s);
        final totalExp = groupedRows.fold<int>(0, (sum, r) => sum + (r['expectedQty'] as int));
        final totalAct = groupedRows.fold<int>(0, (sum, r) => sum + (r['actualQty'] as int));

        buffer.writeln('================================================================================');
        buffer.writeln('BIÊN BẢN KIỂM KÊ KHO: ${s.sessionCode}');
        buffer.writeln('Khu vực: ${s.zone};Vị trí: ${s.locationCode ?? "--"};Bắt đầu: ${_dtFmt.format(s.startedAt)}');
        buffer.writeln('Hoàn thành: ${s.completedAt != null ? _dtFmt.format(s.completedAt!) : "Đang kiểm"};Trạng thái: ${s.isCompleted ? "ĐÃ HOÀN TẤT" : "ĐANG KIỂM KÊ"}');
        buffer.writeln('Tổng quét: ${s.actualScannedCount};Khớp: ${s.matchCount};Thiếu: ${s.missingCount};Sai vị trí: ${s.wrongLocationCount};Thẻ lạ: ${s.trueUnknownEpcCount};Đã xuất kho: ${s.shippedItemCount}');
        buffer.writeln();

        if (includeEpc) {
          buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,Vị Trí Kệ,SL Dự Kiến,SL Thực Tế,SL Khớp,SL Thiếu,SL Thừa/Lạ,Mã Chip RFID (EPC),Kết Quả Đối Soát');
          if (groupedRows.isNotEmpty) {
            for (int r = 0; r < groupedRows.length; r++) {
              final row = groupedRows[r];
              final epcVal = row['epcsCsv'] ?? (row['epcs'] as String).replaceAll('\r\n', '; ');
              buffer.writeln(
                '${r + 1},${row['sku']},"${row['productName']}","${row['location']}",${row['expectedQty']},${row['actualQty']},${row['matchedQty']},${row['missingQty']},${row['surplusQty']},"$epcVal",${row['status']}',
              );
            }
            buffer.writeln('TỔNG CỘNG,"Tổng SKU: ${groupedRows.length}",,,"Tổng DK: $totalExp","Tổng TT: $totalAct",,,,,Hoàn tất đối soát');
          } else {
            buffer.writeln('1,--,Chưa ghi nhận chi tiết thẻ đối soát,--,0,0,0,0,0,--,--');
          }
        } else {
          buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,Vị Trí Kệ,SL Dự Kiến,SL Thực Tế,SL Khớp,SL Thiếu,SL Thừa/Lạ,Kết Quả Đối Soát');
          if (groupedRows.isNotEmpty) {
            for (int r = 0; r < groupedRows.length; r++) {
              final row = groupedRows[r];
              buffer.writeln(
                '${r + 1},${row['sku']},"${row['productName']}","${row['location']}",${row['expectedQty']},${row['actualQty']},${row['matchedQty']},${row['missingQty']},${row['surplusQty']},${row['status']}',
              );
            }
            buffer.writeln('TỔNG CỘNG,"Tổng SKU: ${groupedRows.length}",,,"Tổng DK: $totalExp","Tổng TT: $totalAct",,,,Hoàn tất đối soát');
          } else {
            buffer.writeln('1,--,Chưa ghi nhận chi tiết thẻ đối soát,--,0,0,0,0,0,--');
          }
        }

        if (s.shippedItemCount > 0) {
          buffer.writeln();
          buffer.writeln('CẢNH BÁO BẤT THƯỜNG: DANH SÁCH CHIP ĐÃ XUẤT KHO TRƯỚC ĐÓ PHÁT HIỆN TRONG KHO (${s.shippedItemCount} CHIP)');
          if (includeEpc) {
            buffer.writeln('STT,Mã Chip RFID (EPC),Mã SKU,Tên Sản Phẩm,Vị Trí Phát Hiện,Trạng Thái Cảnh Báo,Thời Gian Quét');
            final shippedList = s.shippedResults;
            for (int i = 0; i < shippedList.length; i++) {
              final it = shippedList[i];
              buffer.writeln(
                '${i + 1},${it.epc},${it.sku ?? "--"},"${it.productName ?? "--"}","${it.actualLocation ?? "--"}",ĐÃ XUẤT KHO (CẦN TRUY VẾT),${_dtFmt.format(it.readAt)}',
              );
            }
          } else {
            buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,Vị Trí Phát Hiện,Trạng Thái Cảnh Báo,Thời Gian Quét');
            final shippedList = s.shippedResults;
            for (int i = 0; i < shippedList.length; i++) {
              final it = shippedList[i];
              buffer.writeln(
                '${i + 1},${it.sku ?? "--"},"${it.productName ?? "--"}","${it.actualLocation ?? "--"}",ĐÃ XUẤT KHO (CẦN TRUY VẾT),${_dtFmt.format(it.readAt)}',
              );
            }
          }
        }

        buffer.writeln();
        buffer.writeln('TRƯỞNG BAN KIỂM KÊ,THỦ KHO,ĐẠI DIỆN KẾ TOÁN');
        buffer.writeln('(Ký ghi rõ họ tên),(Ký ghi rõ họ tên),(Ký ghi rõ họ tên)');
        buffer.writeln();
      }

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      return file;
    } else {
      final excel = Excel.createExcel();

      if (sessions.length > 1) {
        final summarySheet = excel['Tong_Hop_Kiem_Ke'];
        _buildAuditSummarySheet(summarySheet, sessions);
      }

      for (final s in sessions) {
        final sheetName = _safeSheetName('Phien', s.sessionCode);
        final sheet = excel[sheetName];
        _buildSingleAuditSessionSheet(sheet, s, includeEpc: includeEpc);
      }

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      return _saveProtectedExcelFile(excel, filePath);
    }
  }

  void _buildSingleAuditSessionSheet(Sheet sheet, InventorySession s, {bool includeEpc = true}) {
    final groupedRows = _getGroupedAuditSessionRows(s);
    final totalExp = groupedRows.fold<int>(0, (sum, r) => sum + (r['expectedQty'] as int));
    final totalAct = groupedRows.fold<int>(0, (sum, r) => sum + (r['actualQty'] as int));
    final totalMatched = groupedRows.fold<int>(0, (sum, r) => sum + (r['matchedQty'] as int));
    final totalMissing = groupedRows.fold<int>(0, (sum, r) => sum + (r['missingQty'] as int));
    final totalSurplus = groupedRows.fold<int>(0, (sum, r) => sum + (r['surplusQty'] as int));

    _setCell(sheet, col: 0, row: 0, value: 'HỆ THỐNG KHO VẬN THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
    _setCell(sheet, col: 0, row: 1, value: 'BIÊN BẢN KIỂM KÊ KHO HÀNG RFID', style: _titleStyle);
    _setCell(sheet, col: 0, row: 2, value: '(Đối soát số dư thực tế theo Mã SKU tại ô kệ với cơ sở dữ liệu hệ thống)', style: _subTitleStyle);

    _setCell(sheet, col: 0, row: 4, value: 'Mã Phiên Kiểm:', style: _metaLabelStyle);
    _setCell(sheet, col: 1, row: 4, value: s.sessionCode, style: _metaValueStyle);
    _setCell(sheet, col: 3, row: 4, value: 'Khu Vực:', style: _metaLabelStyle);
    _setCell(sheet, col: 4, row: 4, value: s.zone, style: _metaValueStyle);

    _setCell(sheet, col: 0, row: 5, value: s.isSkuSpecific ? 'Mặt Hàng (SKU):' : 'Vị Trí Kệ:', style: _metaLabelStyle);
    _setCell(sheet, col: 1, row: 5, value: s.isSkuSpecific ? s.targetSkus.join(', ') : (s.locationCode ?? '--'), style: _metaValueStyle);
    _setCell(sheet, col: 3, row: 5, value: 'Trạng Thái:', style: _metaLabelStyle);
    _setCell(sheet, col: 4, row: 5, value: s.isCompleted ? 'ĐÃ HOÀN TẤT' : 'ĐANG THỰC HIỆN', style: _metaValueStyle);

    _setCell(sheet, col: 0, row: 6, value: 'Bắt Đầu:', style: _metaLabelStyle);
    _setCell(sheet, col: 1, row: 6, value: _dtFmt.format(s.startedAt), style: _metaValueStyle);
    _setCell(sheet, col: 3, row: 6, value: 'Hoàn Thành:', style: _metaLabelStyle);
    _setCell(sheet, col: 4, row: 6, value: s.completedAt != null ? _dtFmt.format(s.completedAt!) : '--', style: _metaValueStyle);

    // Summary Box
    _setCell(sheet, col: 0, row: 8, value: 'TỔNG HỢP:', style: _metaLabelStyle);
    _setCell(sheet, col: 1, row: 8, value: 'Quét: ${s.actualScannedCount}', style: _metaValueStyle);
    _setCell(sheet, col: 2, row: 8, value: 'Khớp: ${s.matchCount}', style: _metaValueStyle);
    _setCell(sheet, col: 3, row: 8, value: 'Thiếu: ${s.missingCount}', style: _metaValueStyle);
    _setCell(sheet, col: 4, row: 8, value: 'Lệch vị trí: ${s.wrongLocationCount}', style: _metaValueStyle);
    _setCell(sheet, col: 5, row: 8, value: 'Thẻ lạ: ${s.trueUnknownEpcCount}', style: _metaValueStyle);
    _setCell(
      sheet,
      col: 6,
      row: 8,
      value: 'Đã xuất kho: ${s.shippedItemCount}',
      style: s.shippedItemCount > 0 ? _alertMetaValueStyle : _metaValueStyle,
    );

    final headers = includeEpc
        ? [
            'STT',
            'Mã SKU',
            'Tên Sản Phẩm',
            'Vị Trí Kệ',
            'SL Dự Kiến',
            'SL Thực Tế',
            'SL Khớp',
            'SL Thiếu',
            'SL Thừa / Lạ',
            'Mã Chip RFID (EPC)',
            'Kết Quả Đối Soát',
          ]
        : [
            'STT',
            'Mã SKU',
            'Tên Sản Phẩm',
            'Vị Trí Kệ',
            'SL Dự Kiến',
            'SL Thực Tế',
            'SL Khớp',
            'SL Thiếu',
            'SL Thừa / Lạ',
            'Kết Quả Đối Soát',
          ];
    const startRow = 10;
    for (int col = 0; col < headers.length; col++) {
      _setCell(sheet, col: col, row: startRow, value: headers[col], style: _tableHeaderStyle('#8B5CF6'));
    }

    int currentRow = startRow + 1;
    if (groupedRows.isNotEmpty) {
      for (int i = 0; i < groupedRows.length; i++) {
        final row = groupedRows[i];
        _setCell(sheet, col: 0, row: currentRow, value: '${i + 1}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 1, row: currentRow, value: row['sku'] as String);
        _setCell(sheet, col: 2, row: currentRow, value: row['productName'] as String);
        _setCell(sheet, col: 3, row: currentRow, value: row['location'] as String, style: _dataCellCenterStyle);
        _setCell(sheet, col: 4, row: currentRow, value: '${row['expectedQty']}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 5, row: currentRow, value: '${row['actualQty']}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 6, row: currentRow, value: '${row['matchedQty']}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 7, row: currentRow, value: '${row['missingQty']}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 8, row: currentRow, value: '${row['surplusQty']}', style: _dataCellCenterStyle);
        if (includeEpc) {
          _setCell(sheet, col: 9, row: currentRow, value: row['epcs'] as String, style: _epcCellStyle);
          _setCell(sheet, col: 10, row: currentRow, value: row['status'] as String, style: _dataCellCenterStyle);
          final epcList = (row['epcs'] as String).split(RegExp(r'\r?\n'));
          final epcCount = (row['epcs'] as String != '--') ? epcList.length : 1;
          sheet.setRowHeight(currentRow, epcCount > 1 ? (epcCount * 17.0).clamp(24.0, 400.0) : 24.0);
        } else {
          _setCell(sheet, col: 9, row: currentRow, value: row['status'] as String, style: _dataCellCenterStyle);
          sheet.setRowHeight(currentRow, 24.0);
        }
        currentRow++;
      }
    } else {
      _setCell(sheet, col: 0, row: currentRow, value: '1', style: _dataCellCenterStyle);
      _setCell(sheet, col: 1, row: currentRow, value: '--');
      _setCell(sheet, col: 2, row: currentRow, value: 'Chưa có bản ghi đối soát theo SKU');
      for (int c = 3; c < headers.length; c++) {
        _setCell(sheet, col: c, row: currentRow, value: '--', style: _dataCellCenterStyle);
      }
      sheet.setRowHeight(currentRow, 24.0);
      currentRow++;
    }

    // Total Row
    _setCell(sheet, col: 0, row: currentRow, value: 'TỔNG CỘNG', style: _totalRowStyle);
    _setCell(sheet, col: 1, row: currentRow, value: '${groupedRows.length} SKU', style: _totalRowStyle);
    _setCell(sheet, col: 2, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 3, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 4, row: currentRow, value: 'Tổng DK: $totalExp', style: _totalRowStyle);
    _setCell(sheet, col: 5, row: currentRow, value: 'Tổng TT: $totalAct', style: _totalRowStyle);
    _setCell(sheet, col: 6, row: currentRow, value: '$totalMatched', style: _totalRowStyle);
    _setCell(sheet, col: 7, row: currentRow, value: '$totalMissing', style: _totalRowStyle);
    _setCell(sheet, col: 8, row: currentRow, value: '$totalSurplus', style: _totalRowStyle);
    if (includeEpc) {
      _setCell(sheet, col: 9, row: currentRow, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 10, row: currentRow, value: 'Hoàn tất đối soát', style: _totalRowStyle);
    } else {
      _setCell(sheet, col: 9, row: currentRow, value: 'Hoàn tất đối soát', style: _totalRowStyle);
    }

    // Bảng Cảnh Báo Vi Phạm Hàng Đã Xuất Kho (nếu có phát hiện)
    if (s.shippedItemCount > 0) {
      currentRow += 2;
      _setCell(
        sheet,
        col: 0,
        row: currentRow,
        value: '🚨 CẢNH BÁO BẤT THƯỜNG: DANH SÁCH CHIP ĐÃ XUẤT KHO TRƯỚC ĐÓ PHÁT HIỆN TRONG KHO (${s.shippedItemCount} CHIP)',
        style: CellStyle(
          bold: true,
          fontSize: 11,
          fontColorHex: ExcelColor.fromHexString('#DC2626'),
        ),
      );
      currentRow++;

      final alertHeaders = includeEpc
          ? ['STT', 'Mã Chip RFID (EPC)', 'Mã SKU', 'Tên Sản Phẩm', 'Vị Trí Phát Hiện', 'Trạng Thái Cảnh Báo', 'Thời Gian Quét']
          : ['STT', 'Mã SKU', 'Tên Sản Phẩm', 'Vị Trí Phát Hiện', 'Trạng Thái Cảnh Báo', 'Thời Gian Quét'];

      for (int col = 0; col < alertHeaders.length; col++) {
        _setCell(sheet, col: col, row: currentRow, value: alertHeaders[col], style: _tableHeaderStyle('#DC2626'));
      }
      currentRow++;

      final shippedList = s.shippedResults;
      for (int i = 0; i < shippedList.length; i++) {
        final it = shippedList[i];
        _setCell(sheet, col: 0, row: currentRow, value: '${i + 1}', style: _dataCellCenterStyle);
        if (includeEpc) {
          _setCell(sheet, col: 1, row: currentRow, value: it.epc, style: _epcCellStyle);
          _setCell(sheet, col: 2, row: currentRow, value: it.sku ?? '--', style: _dataCellCenterStyle);
          _setCell(sheet, col: 3, row: currentRow, value: it.productName ?? '--');
          _setCell(sheet, col: 4, row: currentRow, value: it.actualLocation ?? '--', style: _dataCellCenterStyle);
          _setCell(
            sheet,
            col: 5,
            row: currentRow,
            value: 'ĐÃ XUẤT KHO (CẦN TRUY VẾT)',
            style: CellStyle(
              bold: true,
              fontSize: 10,
              fontColorHex: ExcelColor.fromHexString('#DC2626'),
              horizontalAlign: HorizontalAlign.Center,
              verticalAlign: VerticalAlign.Center,
            ),
          );
          _setCell(sheet, col: 6, row: currentRow, value: _dtFmt.format(it.readAt), style: _dataCellCenterStyle);
        } else {
          _setCell(sheet, col: 1, row: currentRow, value: it.sku ?? '--', style: _dataCellCenterStyle);
          _setCell(sheet, col: 2, row: currentRow, value: it.productName ?? '--');
          _setCell(sheet, col: 3, row: currentRow, value: it.actualLocation ?? '--', style: _dataCellCenterStyle);
          _setCell(
            sheet,
            col: 4,
            row: currentRow,
            value: 'ĐÃ XUẤT KHO (CẦN TRUY VẾT)',
            style: CellStyle(
              bold: true,
              fontSize: 10,
              fontColorHex: ExcelColor.fromHexString('#DC2626'),
              horizontalAlign: HorizontalAlign.Center,
              verticalAlign: VerticalAlign.Center,
            ),
          );
          _setCell(sheet, col: 5, row: currentRow, value: _dtFmt.format(it.readAt), style: _dataCellCenterStyle);
        }
        sheet.setRowHeight(currentRow, 22.0);
        currentRow++;
      }
    }

    final signRow = currentRow + 3;
    _setCell(sheet, col: 0, row: signRow, value: 'TRƯỞNG BAN KIỂM KÊ', style: _signTitleStyle);
    _setCell(sheet, col: 3, row: signRow, value: 'THỦ KHO', style: _signTitleStyle);
    _setCell(sheet, col: 5, row: signRow, value: 'ĐẠI DIỆN KẾ TOÁN', style: _signTitleStyle);

    _setCell(sheet, col: 0, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: 3, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: 5, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);

    _autoFitColumns(sheet, headers.length, signRow + 3);
  }

  void _buildAuditSummarySheet(Sheet sheet, List<InventorySession> sessions) {
    _setCell(sheet, col: 0, row: 0, value: 'HỆ THỐNG KHO VẬN THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
    _setCell(sheet, col: 0, row: 1, value: 'BẢNG TỔNG HỢP CÁC PHIÊN KIỂM KÊ KHO', style: _titleStyle);
    _setCell(sheet, col: 0, row: 2, value: 'Thời điểm xuất: ${_dtFmt.format(DateTime.now())}   |   Số phiên: ${sessions.length}', style: _subTitleStyle);

    final headers = ['STT', 'Mã Phiên', 'Khu Vực', 'Vị Trí Kệ', 'Bắt Đầu', 'Tổng Quét', 'Khớp', 'Thiếu', 'Lệch Vị Trí', 'Thẻ Lạ', 'Đã Xuất Kho', 'Trạng Thái'];
    const startRow = 4;
    for (int c = 0; c < headers.length; c++) {
      _setCell(sheet, col: c, row: startRow, value: headers[c], style: _tableHeaderStyle('#8B5CF6'));
    }

    int row = startRow + 1;
    for (int i = 0; i < sessions.length; i++) {
      final s = sessions[i];
      _setCell(sheet, col: 0, row: row, value: '${i + 1}', style: _dataCellCenterStyle);
      _setCell(sheet, col: 1, row: row, value: s.sessionCode);
      _setCell(sheet, col: 2, row: row, value: s.zone);
      _setCell(sheet, col: 3, row: row, value: s.locationCode ?? '--', style: _dataCellCenterStyle);
      _setCell(sheet, col: 4, row: row, value: _dtFmt.format(s.startedAt), style: _dataCellCenterStyle);
      _setCell(sheet, col: 5, row: row, value: '${s.actualScannedCount}', style: _dataCellCenterStyle);
      _setCell(sheet, col: 6, row: row, value: '${s.matchCount}', style: _dataCellCenterStyle);
      _setCell(sheet, col: 7, row: row, value: '${s.missingCount}', style: _dataCellCenterStyle);
      _setCell(sheet, col: 8, row: row, value: '${s.wrongLocationCount}', style: _dataCellCenterStyle);
      _setCell(sheet, col: 9, row: row, value: '${s.trueUnknownEpcCount}', style: _dataCellCenterStyle);
      _setCell(
        sheet,
        col: 10,
        row: row,
        value: '${s.shippedItemCount}',
        style: s.shippedItemCount > 0
            ? CellStyle(
                bold: true,
                fontSize: 10,
                fontColorHex: ExcelColor.fromHexString('#DC2626'),
                horizontalAlign: HorizontalAlign.Center,
                verticalAlign: VerticalAlign.Center,
              )
            : _dataCellCenterStyle,
      );
      _setCell(sheet, col: 11, row: row, value: s.isCompleted ? 'Hoàn tất' : 'Đang thực hiện', style: _dataCellCenterStyle);
      row++;
    }

    _autoFitColumns(sheet, headers.length, row + 2);
  }

  /// Xuất Báo Cáo Đối Soát Tồn Kho Chuẩn Doanh Nghiệp (3 Sheet: Tổng Hợp, Thiếu & Đủ, Thừa & EPC Thừa - Gộp 1 hàng / Mã SKU)
  Future<File> exportStockReconciliationReport(
    ReportFormat format, {
    required List<SkuStockReconciliationRow> rows,
    required String scopeTitle,
    String? sessionCode,
    bool includeEpc = false,
  }) async {
    final dir = await _getReportDir();
    final timestamp = _fileFmt.format(DateTime.now());
    final fileName = 'doi_soat_ton_kho_${sessionCode ?? "tong_hop"}_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    // Gộp chung theo Mã SKU (1 hàng / SKU) và chuẩn hóa tên sản phẩm
    final Map<String, SkuStockReconciliationRow> mergedMap = {};
    for (final r in rows) {
      final key = r.sku.trim().isNotEmpty ? r.sku.trim().toUpperCase() : 'CHƯA CÓ SKU';
      final displaySku = r.sku.trim().isNotEmpty ? r.sku.trim() : key;
      final cleanName = _repo.getSkuProductName(displaySku, r.productName);
      if (!mergedMap.containsKey(key)) {
        mergedMap[key] = SkuStockReconciliationRow(
          sku: displaySku,
          productName: cleanName,
          unit: r.unit,
          zoneOrLocation: r.zoneOrLocation,
          expectedQty: r.expectedQty,
          actualQty: r.actualQty,
          matchedCount: r.matchedCount,
          missingCount: r.missingCount,
          wrongLocationCount: r.wrongLocationCount,
          unknownCount: r.unknownCount,
          isAudited: r.isAudited,
          itemResults: r.itemResults,
        );
      } else {
        final cur = mergedMap[key]!;
        final locs = {
          ...cur.zoneOrLocation.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty && s != '--'),
          ...r.zoneOrLocation.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty && s != '--'),
        }.join(', ');
        mergedMap[key] = SkuStockReconciliationRow(
          sku: cur.sku,
          productName: cur.productName.isNotEmpty ? cur.productName : cleanName,
          unit: cur.unit,
          zoneOrLocation: locs.isNotEmpty ? locs : cur.zoneOrLocation,
          expectedQty: cur.expectedQty + r.expectedQty,
          actualQty: cur.actualQty + r.actualQty,
          matchedCount: cur.matchedCount + r.matchedCount,
          missingCount: cur.missingCount + r.missingCount,
          wrongLocationCount: cur.wrongLocationCount + r.wrongLocationCount,
          unknownCount: cur.unknownCount + r.unknownCount,
          isAudited: cur.isAudited || r.isAudited,
          itemResults: [...cur.itemResults, ...r.itemResults],
        );
      }
    }
    final mergedRows = mergedMap.values.toList();

    final hasAuditedData = mergedRows.any((r) => r.isAudited);
    final totalExp = mergedRows.fold<int>(0, (s, r) => s + r.expectedQty);
    final totalAct = hasAuditedData ? mergedRows.fold<int>(0, (s, r) => s + r.actualQty) : 0;
    final totalMatched = hasAuditedData ? mergedRows.fold<int>(0, (s, r) => s + r.matchedCount) : 0;
    final totalMissing = hasAuditedData ? mergedRows.fold<int>(0, (s, r) => s + r.missingCount) : 0;
    final totalWrongLoc = hasAuditedData ? mergedRows.fold<int>(0, (s, r) => s + r.wrongLocationCount) : 0;
    final totalUnknown = hasAuditedData ? mergedRows.fold<int>(0, (s, r) => s + r.unknownCount) : 0;
    final totalShipped = hasAuditedData ? mergedRows.fold<int>(0, (s, r) => s + r.shippedCount) : 0;
    final allShippedItems = mergedRows
        .expand((r) => r.itemResults)
        .where((it) => it.expectedLocation == 'ĐÃ XUẤT KHO')
        .toList();
    final totalSurplus = hasAuditedData ? mergedRows.fold<int>(0, (s, r) => s + (r.difference > 0 ? r.difference : (r.unknownCount > 0 ? r.unknownCount : 0))) : 0;
    final acc = !hasAuditedData ? '--' : (totalExp > 0 ? (totalMatched / totalExp * 100).toStringAsFixed(1) : '100.0');

    // Dữ liệu Sheet 2: Danh mục đối chiếu thiếu và đủ (1 hàng / SKU)
    final sheet2SkuRows = mergedRows.where((r) => r.expectedQty > 0 || r.matchedCount > 0 || r.missingCount > 0).toList();

    // Dữ liệu Sheet 3: Danh mục đối chiếu thừa (1 hàng / SKU)
    final sheet3SkuRows = mergedRows.where((r) => r.isAudited && (r.difference > 0 || r.unknownCount > 0)).toList();

    String getRowEpcs(SkuStockReconciliationRow r, {bool surplusOnly = false}) {
      if (surplusOnly) {
        final unknowns = r.itemResults
            .where((it) => it.resultType == InventoryVarianceType.unknownEpc)
            .map((it) => it.epc.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (unknowns.isNotEmpty) {
          return unknowns.toSet().join('\r\n');
        }
        final scanned = r.itemResults
            .where((it) => it.resultType == InventoryVarianceType.match || it.resultType == InventoryVarianceType.wrongLocation)
            .map((it) => it.epc.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (scanned.length > r.expectedQty) {
          return scanned.sublist(r.expectedQty).toSet().join('\r\n');
        }
        return scanned.isNotEmpty ? scanned.toSet().join('\r\n') : '--';
      }
      final epcs = r.itemResults.map((it) => it.epc.trim()).where((e) => e.isNotEmpty).toSet().toList();
      return epcs.isNotEmpty ? epcs.join('\r\n') : '--';
    }

    if (format == ReportFormat.csv) {
      final buffer = StringBuffer();
      buffer.writeln('\uFEFFHỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)');
      buffer.writeln('BÁO CÁO ĐỐI SOÁT KIỂM KHO (DỰ KIẾN VS THỰC TẾ)');
      buffer.writeln('Phạm vi: $scopeTitle;Phiếu kiểm kê: ${sessionCode ?? "Toàn bộ kho"};Ngày xuất: ${_dtFmt.format(DateTime.now())}');
      buffer.writeln('Tổng dự kiến: $totalExp;Tổng thực tế: ${hasAuditedData ? totalAct : "--"};Khớp đủ: $totalMatched;Thiếu hụt: $totalMissing;Thừa/Lạ: $totalSurplus;Đã xuất kho: $totalShipped;Độ chính xác: ${hasAuditedData ? "$acc%" : "Chưa kiểm kê"}');
      buffer.writeln();
      buffer.writeln('=== PHẦN 1: BẢNG TỔNG HỢP ĐỐI CHIẾU THEO MÃ SKU (THỪA - THIẾU - ĐỦ) ===');
      buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,ĐVT,Vị Trí Lưu Kho,Tồn Sổ Sách,Thực Tế Quét,Khớp Đủ,Thiếu Hụt,Thừa/Lạ,Chênh Lệch,Tỷ Lệ Đạt (%),Trạng Thái');
      for (int i = 0; i < mergedRows.length; i++) {
        final r = mergedRows[i];
        final diffStr = !r.isAudited ? '--' : (r.difference == 0 ? '0' : (r.difference > 0 ? '+${r.difference}' : '${r.difference}'));
        final surplusCount = !r.isAudited ? 0 : (r.difference > 0 ? r.difference : (r.unknownCount > 0 ? r.unknownCount : 0));
        final actStr = r.isAudited ? '${r.actualQty}' : '--';
        final accStr = r.isAudited ? '${r.accuracyPercent.toStringAsFixed(1)}%' : '--';
        buffer.writeln('${i + 1},${r.sku},"${r.productName}",${r.unit},"${r.zoneOrLocation}",${r.expectedQty},$actStr,${r.matchedCount},${r.missingCount},$surplusCount,$diffStr,$accStr,${r.statusLabel}');
      }
      buffer.writeln();
      buffer.writeln('=== PHẦN 2: BẢNG ĐỐI CHIẾU THIẾU VÀ ĐỦ THEO MÃ SKU ===');
      if (includeEpc) {
        buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,ĐVT,Vị Trí Sổ Sách,Số Lượng Dự Kiến,Số Lượng Khớp Đủ,Số Lượng Thiếu,Sai Vị Trí,Tỷ Lệ Đủ (%),Mã Chip RFID (EPC),Kết Luận');
        for (int i = 0; i < sheet2SkuRows.length; i++) {
          final r = sheet2SkuRows[i];
          final conclusion = !r.isAudited
              ? 'Chưa kiểm kê'
              : (r.missingCount == 0 ? (r.wrongLocationCount > 0 ? 'Đủ (Sai vị trí kệ)' : 'Khớp đủ 100%') : 'Thiếu ${r.missingCount} SP');
          final accStr = r.isAudited ? '${r.accuracyPercent.toStringAsFixed(1)}%' : '--';
          final epcVal = getRowEpcs(r).replaceAll('\r\n', '; ');
          buffer.writeln('${i + 1},${r.sku},"${r.productName}",${r.unit},"${r.zoneOrLocation}",${r.expectedQty},${r.matchedCount},${r.missingCount},${r.wrongLocationCount},$accStr,"$epcVal",$conclusion');
        }
      } else {
        buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,ĐVT,Vị Trí Sổ Sách,Số Lượng Dự Kiến,Số Lượng Khớp Đủ,Số Lượng Thiếu,Sai Vị Trí,Tỷ Lệ Đủ (%),Kết Luận');
        for (int i = 0; i < sheet2SkuRows.length; i++) {
          final r = sheet2SkuRows[i];
          final conclusion = !r.isAudited
              ? 'Chưa kiểm kê'
              : (r.missingCount == 0 ? (r.wrongLocationCount > 0 ? 'Đủ (Sai vị trí kệ)' : 'Khớp đủ 100%') : 'Thiếu ${r.missingCount} SP');
          final accStr = r.isAudited ? '${r.accuracyPercent.toStringAsFixed(1)}%' : '--';
          buffer.writeln('${i + 1},${r.sku},"${r.productName}",${r.unit},"${r.zoneOrLocation}",${r.expectedQty},${r.matchedCount},${r.missingCount},${r.wrongLocationCount},$accStr,$conclusion');
        }
      }
      buffer.writeln();
      buffer.writeln('=== PHẦN 3: BẢNG ĐỐI CHIẾU THỪA THEO MÃ SKU ===');
      if (sheet3SkuRows.isEmpty) {
        buffer.writeln('1,KHONG_CO_EPC_THUA,Không phát sinh mã hàng thừa,--,--,0,0,0,--,Khớp đúng,--');
      } else {
        if (includeEpc) {
          buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,ĐVT,Vị Trí Quét Thấy,Tồn Sổ Sách,Thực Tế Quét,Số Lượng Thừa (+),Mã Chip RFID (EPC) Thừa,Phân Loại Thừa,Đề Xuất Xử Lý');
          for (int i = 0; i < sheet3SkuRows.length; i++) {
            final r = sheet3SkuRows[i];
            final surplusQty = r.difference > 0 ? r.difference : (r.unknownCount > 0 ? r.unknownCount : 0);
            final typeDesc = r.sku == 'THẺ_LẠ'
                ? 'Thẻ RFID lạ ngoài danh mục'
                : 'Thừa số lượng theo SKU';
            final actionDesc = r.sku == 'THẺ_LẠ'
                ? 'Cách ly kiểm tra mã thẻ, lập biên bản thẻ lạ'
                : 'Kiểm tra phiếu nhập hoặc hàng chưa cất kệ';
            final epcVal = getRowEpcs(r, surplusOnly: true).replaceAll('\r\n', '; ');
            buffer.writeln('${i + 1},${r.sku},"${r.productName}",${r.unit},"${r.zoneOrLocation}",${r.expectedQty},${r.actualQty},+$surplusQty,"$epcVal","$typeDesc","$actionDesc"');
          }
        } else {
          buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,ĐVT,Vị Trí Quét Thấy,Tồn Sổ Sách,Thực Tế Quét,Số Lượng Thừa (+),Phân Loại Thừa,Đề Xuất Xử Lý');
          for (int i = 0; i < sheet3SkuRows.length; i++) {
            final r = sheet3SkuRows[i];
            final surplusQty = r.difference > 0 ? r.difference : (r.unknownCount > 0 ? r.unknownCount : 0);
            final typeDesc = r.sku == 'THẺ_LẠ'
                ? 'Thẻ RFID lạ ngoài danh mục'
                : 'Thừa số lượng theo SKU';
            final actionDesc = r.sku == 'THẺ_LẠ'
                ? 'Cách ly kiểm tra mã thẻ, lập biên bản thẻ lạ'
                : 'Kiểm tra phiếu nhập hoặc hàng chưa cất kệ';
            buffer.writeln('${i + 1},${r.sku},"${r.productName}",${r.unit},"${r.zoneOrLocation}",${r.expectedQty},${r.actualQty},+$surplusQty,"$typeDesc","$actionDesc"');
          }
        }
      }

      if (allShippedItems.isNotEmpty) {
        buffer.writeln();
        buffer.writeln('=== PHẦN 4: CẢNH BÁO BẤT THƯỜNG - DANH SÁCH CHIP ĐÃ XUẤT KHO PHÁT HIỆN TRONG KHO (${allShippedItems.length} CHIP) ===');
        if (includeEpc) {
          buffer.writeln('STT,Mã Chip RFID (EPC),Mã SKU,Tên Sản Phẩm,Vị Trí Quét Thấy,Trạng Thái Sổ Sách,Cảnh Báo');
          for (int i = 0; i < allShippedItems.length; i++) {
            final it = allShippedItems[i];
            buffer.writeln('${i + 1},${it.epc},${it.sku ?? "--"},"${it.productName ?? "Hàng đã xuất kho"}",${it.actualLocation ?? "--"},ĐÃ XUẤT KHO,🚨 ĐÃ LÀM THỦ TỤC XUẤT KHO NHƯNG VẪN CÒN TRONG KHO');
          }
        } else {
          buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,Vị Trí Quét Thấy,Trạng Thái Sổ Sách,Cảnh Báo');
          for (int i = 0; i < allShippedItems.length; i++) {
            final it = allShippedItems[i];
            buffer.writeln('${i + 1},${it.sku ?? "--"},"${it.productName ?? "Hàng đã xuất kho"}",${it.actualLocation ?? "--"},ĐÃ XUẤT KHO,🚨 ĐÃ LÀM THỦ TỤC XUẤT KHO NHƯNG VẪN CÒN TRONG KHO');
          }
        }
      }

      buffer.writeln();
      buffer.writeln('TRƯỞNG BAN KIỂM KÊ,THỦ KHO,ĐẠI DIỆN KẾ TOÁN');
      buffer.writeln('(Ký ghi rõ họ tên),(Ký ghi rõ họ tên),(Ký ghi rõ họ tên)');
      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      return file;
    } else {
      final excel = Excel.createExcel();

      // =======================================================================
      // SHEET 1: TỔNG HỢP ĐỐI SOÁT (TỔNG HỢP THỪA - THIẾU - ĐỦ THEO MÃ SKU)
      // =======================================================================
      final sheet1 = excel['Tong_Hop_Doi_Soat'];

      _setCell(sheet1, col: 0, row: 0, value: 'HỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
      _setCell(sheet1, col: 0, row: 1, value: 'BẢNG TỔNG HỢP ĐỐI CHIẾU KIỂM KHO THEO MÃ SKU (DỰ KIẾN VS THỰC TẾ)', style: _titleStyle);
      _setCell(sheet1, col: 0, row: 2, value: '(Bảng tổng hợp gộp theo Mã SKU: đối chiếu số lượng Khớp đủ - Thiếu hụt - Thừa)', style: _subTitleStyle);

      _setCell(sheet1, col: 0, row: 4, value: 'Phạm Vi Kiểm Kê:', style: _metaLabelStyle);
      _setCell(sheet1, col: 1, row: 4, value: scopeTitle, style: _metaValueStyle);
      _setCell(sheet1, col: 5, row: 4, value: 'Ngày Xuất Báo Cáo:', style: _metaLabelStyle);
      _setCell(sheet1, col: 6, row: 4, value: _dtFmt.format(DateTime.now()), style: _metaValueStyle);

      _setCell(sheet1, col: 0, row: 5, value: 'Mã Phiếu Kiểm Kê:', style: _metaLabelStyle);
      _setCell(sheet1, col: 1, row: 5, value: sessionCode ?? 'Toàn bộ kho', style: _metaValueStyle);
      _setCell(sheet1, col: 5, row: 5, value: 'Độ Chính Xác Kho:', style: _metaLabelStyle);
      _setCell(sheet1, col: 6, row: 5, value: hasAuditedData ? '$acc%' : 'Chưa kiểm kê', style: _metaValueStyle);

      _setCell(sheet1, col: 0, row: 7, value: 'Tồn Dự Kiến (Sổ Sách):', style: _metaLabelStyle);
      _setCell(sheet1, col: 1, row: 7, value: '$totalExp SP', style: _metaValueStyle);
      _setCell(sheet1, col: 3, row: 7, value: 'Thực Tế Quét (RFID):', style: _metaLabelStyle);
      _setCell(sheet1, col: 4, row: 7, value: hasAuditedData ? '$totalAct Chip' : 'Chưa kiểm kê', style: _metaValueStyle);
      _setCell(sheet1, col: 6, row: 7, value: 'Khớp Đủ (Sheet 2):', style: _metaLabelStyle);
      _setCell(sheet1, col: 7, row: 7, value: '$totalMatched SP', style: _metaValueStyle);
      _setCell(sheet1, col: 9, row: 7, value: 'Thiếu Hụt (Sheet 2):', style: _metaLabelStyle);
      _setCell(sheet1, col: 10, row: 7, value: totalMissing > 0 ? '-$totalMissing SP' : '0 SP', style: _metaValueStyle);
      _setCell(sheet1, col: 11, row: 7, value: 'Thừa / Lạ (Sheet 3):', style: _metaLabelStyle);
      _setCell(sheet1, col: 12, row: 7, value: totalSurplus > 0 ? '+$totalSurplus Chip' : '0 Chip', style: _metaValueStyle);
      if (totalShipped > 0) {
        _setCell(sheet1, col: 13, row: 7, value: 'Đã Xuất Kho:', style: _metaLabelStyle);
        _setCell(sheet1, col: 14, row: 7, value: '$totalShipped Chip', style: _alertMetaValueStyle);
      }

      final headers1 = [
        'STT', 'Mã SKU', 'Tên Sản Phẩm / Quy Cách', 'ĐVT', 'Vị Trí Lưu Kho',
        'Tồn Sổ Sách (Dự Kiến)', 'Thực Tế Quét (RFID)', 'Khớp Đủ (Sheet 2)',
        'Thiếu Hụt (Sheet 2)', 'Thừa / Lạ (Sheet 3)', 'Chênh Lệch (±)',
        'Tỷ Lệ Đạt (%)', 'Trạng Thái Đối Soát',
      ];
      const startRow1 = 9;
      for (int c = 0; c < headers1.length; c++) {
        _setCell(sheet1, col: c, row: startRow1, value: headers1[c], style: _tableHeaderStyle('#0891B2'));
      }

      int r1 = startRow1 + 1;
      for (int i = 0; i < mergedRows.length; i++) {
        final r = mergedRows[i];
        final diffStr = !r.isAudited ? '--' : (r.difference == 0 ? '0' : (r.difference > 0 ? '+${r.difference}' : '${r.difference}'));
        final surplusCount = !r.isAudited ? 0 : (r.difference > 0 ? r.difference : (r.unknownCount > 0 ? r.unknownCount : 0));
        final surplusStr = surplusCount > 0 ? '+$surplusCount' : '0';

        _setCell(sheet1, col: 0, row: r1, value: '${i + 1}', style: _dataCellCenterStyle);
        _setCell(sheet1, col: 1, row: r1, value: r.sku);
        _setCell(sheet1, col: 2, row: r1, value: r.productName);
        _setCell(sheet1, col: 3, row: r1, value: r.unit, style: _dataCellCenterStyle);
        _setCell(sheet1, col: 4, row: r1, value: r.zoneOrLocation);
        _setCell(sheet1, col: 5, row: r1, value: '${r.expectedQty}', style: _dataCellCenterStyle);
        _setCell(sheet1, col: 6, row: r1, value: r.isAudited ? '${r.actualQty}' : '--', style: _dataCellCenterStyle);
        _setCell(sheet1, col: 7, row: r1, value: '${r.matchedCount}', style: _dataCellCenterStyle);
        _setCell(sheet1, col: 8, row: r1, value: r.missingCount > 0 ? '-${r.missingCount}' : '0', style: _dataCellCenterStyle);
        _setCell(sheet1, col: 9, row: r1, value: surplusStr, style: _dataCellCenterStyle);
        _setCell(sheet1, col: 10, row: r1, value: diffStr, style: _dataCellCenterStyle);
        _setCell(sheet1, col: 11, row: r1, value: r.isAudited ? '${r.accuracyPercent.toStringAsFixed(1)}%' : '--', style: _dataCellCenterStyle);
        _setCell(sheet1, col: 12, row: r1, value: r.statusLabel, style: _dataCellCenterStyle);
        r1++;
      }

      // Dòng TỔNG CỘNG Sheet 1
      _setCell(sheet1, col: 0, row: r1, value: 'TỔNG CỘNG', style: _totalRowStyle);
      _setCell(sheet1, col: 1, row: r1, value: '${mergedRows.length} SKU', style: _totalRowStyle);
      _setCell(sheet1, col: 2, row: r1, value: '', style: _totalRowStyle);
      _setCell(sheet1, col: 3, row: r1, value: '', style: _totalRowStyle);
      _setCell(sheet1, col: 4, row: r1, value: '', style: _totalRowStyle);
      _setCell(sheet1, col: 5, row: r1, value: '$totalExp SP', style: _totalRowStyle);
      _setCell(sheet1, col: 6, row: r1, value: hasAuditedData ? '$totalAct Chip' : '--', style: _totalRowStyle);
      _setCell(sheet1, col: 7, row: r1, value: '$totalMatched SP', style: _totalRowStyle);
      _setCell(sheet1, col: 8, row: r1, value: totalMissing > 0 ? '-$totalMissing SP' : '0 SP', style: _totalRowStyle);
      _setCell(sheet1, col: 9, row: r1, value: totalSurplus > 0 ? '+$totalSurplus Chip' : '0 Chip', style: _totalRowStyle);
      final netDiff = hasAuditedData ? (totalAct - totalExp) : 0;
      _setCell(sheet1, col: 10, row: r1, value: !hasAuditedData ? '--' : '${netDiff >= 0 ? "+" : ""}$netDiff SP', style: _totalRowStyle);
      _setCell(sheet1, col: 11, row: r1, value: hasAuditedData ? '$acc%' : '--', style: _totalRowStyle);
      _setCell(sheet1, col: 12, row: r1, value: !hasAuditedData ? 'Chưa kiểm kê' : (totalMissing == 0 && totalSurplus == 0 ? 'Khớp 100%' : 'Chênh lệch'), style: _totalRowStyle);

      final signRow1 = r1 + 3;
      _setCell(sheet1, col: 1, row: signRow1, value: 'TRƯỞNG BAN KIỂM KÊ', style: _signTitleStyle);
      _setCell(sheet1, col: 6, row: signRow1, value: 'THỦ KHO', style: _signTitleStyle);
      _setCell(sheet1, col: 10, row: signRow1, value: 'ĐẠI DIỆN KẾ TOÁN', style: _signTitleStyle);

      _setCell(sheet1, col: 1, row: signRow1 + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
      _setCell(sheet1, col: 6, row: signRow1 + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
      _setCell(sheet1, col: 10, row: signRow1 + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);

      _autoFitColumns(sheet1, headers1.length, signRow1 + 3);

      // =======================================================================
      // SHEET 2: ĐỐI CHIẾU THIẾU VÀ ĐỦ (GỘP 1 HÀNG / MÃ SKU)
      // =======================================================================
      final sheet2 = excel['Doi_Chieu_Thieu_Va_Du'];

      _setCell(sheet2, col: 0, row: 0, value: 'HỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
      _setCell(sheet2, col: 0, row: 1, value: 'BẢNG ĐỐI CHIẾU THIẾU VÀ ĐỦ THEO MÃ SKU', style: _titleStyle);
      _setCell(sheet2, col: 0, row: 2, value: '(Gộp theo Mã SKU: ghi rõ số lượng Sổ sách, Số lượng Đủ, Số lượng Thiếu và danh sách chip RFID)', style: _subTitleStyle);

      _setCell(sheet2, col: 0, row: 4, value: 'Phạm Vi:', style: _metaLabelStyle);
      _setCell(sheet2, col: 1, row: 4, value: scopeTitle, style: _metaValueStyle);
      _setCell(sheet2, col: 4, row: 4, value: 'Phiếu Kiểm Kê:', style: _metaLabelStyle);
      _setCell(sheet2, col: 5, row: 4, value: sessionCode ?? 'Toàn bộ kho', style: _metaValueStyle);

      _setCell(sheet2, col: 0, row: 5, value: 'Tổng Sổ Sách:', style: _metaLabelStyle);
      _setCell(sheet2, col: 1, row: 5, value: '$totalExp SP', style: _metaValueStyle);
      _setCell(sheet2, col: 3, row: 5, value: 'Khớp Đủ:', style: _metaLabelStyle);
      _setCell(sheet2, col: 4, row: 5, value: '$totalMatched SP', style: _metaValueStyle);
      _setCell(sheet2, col: 6, row: 5, value: 'Thiếu Hụt:', style: _metaLabelStyle);
      _setCell(sheet2, col: 7, row: 5, value: totalMissing > 0 ? '-$totalMissing SP' : '0 SP', style: _metaValueStyle);

      final headers2Sku = includeEpc
          ? [
              'STT', 'Mã SKU', 'Tên Sản Phẩm', 'ĐVT', 'Vị Trí Sổ Sách',
              'Tồn Sổ Sách (Dự Kiến)', 'Số Lượng Đủ (Khớp)', 'Số Lượng Thiếu',
              'Sai Vị Trí Kệ', 'Tỷ Lệ Đủ (%)', 'Mã Chip RFID (EPC)', 'Kết Luận Đối Chiếu',
            ]
          : [
              'STT', 'Mã SKU', 'Tên Sản Phẩm', 'ĐVT', 'Vị Trí Sổ Sách',
              'Tồn Sổ Sách (Dự Kiến)', 'Số Lượng Đủ (Khớp)', 'Số Lượng Thiếu',
              'Sai Vị Trí Kệ', 'Tỷ Lệ Đủ (%)', 'Kết Luận Đối Chiếu',
            ];
      const startRow2Sku = 7;
      for (int c = 0; c < headers2Sku.length; c++) {
        _setCell(sheet2, col: c, row: startRow2Sku, value: headers2Sku[c], style: _tableHeaderStyle('#059669'));
      }

      int r2 = startRow2Sku + 1;
      for (int i = 0; i < sheet2SkuRows.length; i++) {
        final r = sheet2SkuRows[i];
        final conclusion = !r.isAudited
            ? 'Chưa kiểm kê'
            : (r.missingCount == 0
                ? (r.wrongLocationCount > 0 ? 'Đủ (Sai vị trí kệ)' : 'Khớp đủ 100%')
                : 'Thiếu ${r.missingCount} SP');

        _setCell(sheet2, col: 0, row: r2, value: '${i + 1}', style: _dataCellCenterStyle);
        _setCell(sheet2, col: 1, row: r2, value: r.sku);
        _setCell(sheet2, col: 2, row: r2, value: r.productName);
        _setCell(sheet2, col: 3, row: r2, value: r.unit, style: _dataCellCenterStyle);
        _setCell(sheet2, col: 4, row: r2, value: r.zoneOrLocation);
        _setCell(sheet2, col: 5, row: r2, value: '${r.expectedQty}', style: _dataCellCenterStyle);
        _setCell(sheet2, col: 6, row: r2, value: '${r.matchedCount}', style: _dataCellCenterStyle);
        _setCell(sheet2, col: 7, row: r2, value: r.missingCount > 0 ? '-${r.missingCount}' : '0', style: _dataCellCenterStyle);
        _setCell(sheet2, col: 8, row: r2, value: '${r.wrongLocationCount}', style: _dataCellCenterStyle);
        _setCell(sheet2, col: 9, row: r2, value: r.isAudited ? '${r.accuracyPercent.toStringAsFixed(1)}%' : '--', style: _dataCellCenterStyle);
        if (includeEpc) {
          _setCell(sheet2, col: 10, row: r2, value: getRowEpcs(r), style: _epcCellStyle);
          _setCell(sheet2, col: 11, row: r2, value: conclusion, style: _dataCellCenterStyle);
          final epcList = getRowEpcs(r).split(RegExp(r'\r?\n'));
          final epcCount = (getRowEpcs(r) != '--') ? epcList.length : 1;
          sheet2.setRowHeight(r2, epcCount > 1 ? (epcCount * 17.0).clamp(24.0, 400.0) : 24.0);
        } else {
          _setCell(sheet2, col: 10, row: r2, value: conclusion, style: _dataCellCenterStyle);
          sheet2.setRowHeight(r2, 24.0);
        }
        r2++;
      }

      // Dòng Tổng Cộng Bảng SKU
      _setCell(sheet2, col: 0, row: r2, value: 'TỔNG CỘNG', style: _totalRowStyle);
      _setCell(sheet2, col: 1, row: r2, value: '${sheet2SkuRows.length} SKU', style: _totalRowStyle);
      _setCell(sheet2, col: 2, row: r2, value: '', style: _totalRowStyle);
      _setCell(sheet2, col: 3, row: r2, value: '', style: _totalRowStyle);
      _setCell(sheet2, col: 4, row: r2, value: '', style: _totalRowStyle);
      _setCell(sheet2, col: 5, row: r2, value: '$totalExp SP', style: _totalRowStyle);
      _setCell(sheet2, col: 6, row: r2, value: '$totalMatched SP', style: _totalRowStyle);
      _setCell(sheet2, col: 7, row: r2, value: totalMissing > 0 ? '-$totalMissing SP' : '0 SP', style: _totalRowStyle);
      _setCell(sheet2, col: 8, row: r2, value: '$totalWrongLoc SP', style: _totalRowStyle);
      _setCell(sheet2, col: 9, row: r2, value: hasAuditedData ? '$acc%' : '--', style: _totalRowStyle);
      if (includeEpc) {
        _setCell(sheet2, col: 10, row: r2, value: '', style: _totalRowStyle);
        _setCell(sheet2, col: 11, row: r2, value: !hasAuditedData ? 'Chưa kiểm kê' : (totalMissing == 0 ? 'Đủ 100%' : 'Thiếu $totalMissing SP'), style: _totalRowStyle);
      } else {
        _setCell(sheet2, col: 10, row: r2, value: !hasAuditedData ? 'Chưa kiểm kê' : (totalMissing == 0 ? 'Đủ 100%' : 'Thiếu $totalMissing SP'), style: _totalRowStyle);
      }

      _autoFitColumns(sheet2, headers2Sku.length, r2 + 2);

      // =======================================================================
      // SHEET 3: ĐỐI CHIẾU THỪA THEO MÃ SKU
      // =======================================================================
      final sheet3 = excel['Doi_Chieu_Thua_EPC'];

      _setCell(sheet3, col: 0, row: 0, value: 'HỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
      _setCell(sheet3, col: 0, row: 1, value: 'BẢNG ĐỐI CHIẾU HÀNG THỪA THEO MÃ SKU', style: _titleStyle);
      _setCell(sheet3, col: 0, row: 2, value: '(Gộp 1 hàng / Mã SKU phát sinh thừa và ghi rõ số lượng thừa kèm mã chip RFID)', style: _subTitleStyle);

      _setCell(sheet3, col: 0, row: 4, value: 'Phạm Vi:', style: _metaLabelStyle);
      _setCell(sheet3, col: 1, row: 4, value: scopeTitle, style: _metaValueStyle);
      _setCell(sheet3, col: 4, row: 4, value: 'Phiếu Kiểm Kê:', style: _metaLabelStyle);
      _setCell(sheet3, col: 5, row: 4, value: sessionCode ?? 'Toàn bộ kho', style: _metaValueStyle);

      _setCell(sheet3, col: 0, row: 5, value: 'Tổng Hàng Thừa / Lạ:', style: _metaLabelStyle);
      _setCell(sheet3, col: 1, row: 5, value: '+$totalSurplus Chip', style: _metaValueStyle);
      _setCell(sheet3, col: 3, row: 5, value: 'Thẻ Lạ Ngoài Sổ Sách:', style: _metaLabelStyle);
      _setCell(sheet3, col: 4, row: 5, value: '$totalUnknown Chip', style: _metaValueStyle);
      _setCell(sheet3, col: 6, row: 5, value: 'Hướng Xử Lý:', style: _metaLabelStyle);
      _setCell(sheet3, col: 7, row: 5, value: totalSurplus > 0 ? 'Cách ly chip thừa, rà soát nguồn gốc lô hàng' : 'Kho chuẩn, không phát sinh thừa', style: _metaValueStyle);

      final headers3Sku = includeEpc
          ? [
              'STT', 'Mã SKU', 'Tên Sản Phẩm / Phân Loại', 'ĐVT', 'Vị Trí Quét Thấy',
              'Tồn Sổ Sách', 'Thực Tế Quét', 'Số Lượng Thừa (+)', 'Mã Chip RFID (EPC) Thừa', 'Phân Loại Thừa', 'Đề Xuất Xử Lý',
            ]
          : [
              'STT', 'Mã SKU', 'Tên Sản Phẩm / Phân Loại', 'ĐVT', 'Vị Trí Quét Thấy',
              'Tồn Sổ Sách', 'Thực Tế Quét', 'Số Lượng Thừa (+)', 'Phân Loại Thừa', 'Đề Xuất Xử Lý',
            ];
      const startRow3Sku = 7;
      for (int c = 0; c < headers3Sku.length; c++) {
        _setCell(sheet3, col: c, row: startRow3Sku, value: headers3Sku[c], style: _tableHeaderStyle('#D97706'));
      }

      int r3 = startRow3Sku + 1;
      if (sheet3SkuRows.isEmpty) {
        _setCell(sheet3, col: 0, row: r3, value: '✓ Không có mặt hàng (SKU) nào phát sinh thừa trong đợt kiểm kê này.', style: _signNoteStyle);
        sheet3.setRowHeight(r3, 24.0);
        r3++;
      } else {
        for (int i = 0; i < sheet3SkuRows.length; i++) {
          final r = sheet3SkuRows[i];
          final surplusQty = r.difference > 0 ? r.difference : (r.unknownCount > 0 ? r.unknownCount : 0);
          final typeDesc = r.sku == 'THẺ_LẠ'
              ? 'Thẻ RFID lạ chưa khai báo trong hệ thống'
              : 'Thừa số lượng so với định mức sổ sách';
          final actionDesc = r.sku == 'THẺ_LẠ'
              ? 'Cách ly kiểm tra mã thẻ, lập biên bản thẻ lạ'
              : 'Kiểm tra phiếu nhập hoặc hàng chưa cất kệ';

          _setCell(sheet3, col: 0, row: r3, value: '${i + 1}', style: _dataCellCenterStyle);
          _setCell(sheet3, col: 1, row: r3, value: r.sku);
          _setCell(sheet3, col: 2, row: r3, value: r.productName);
          _setCell(sheet3, col: 3, row: r3, value: r.unit, style: _dataCellCenterStyle);
          _setCell(sheet3, col: 4, row: r3, value: r.zoneOrLocation);
          _setCell(sheet3, col: 5, row: r3, value: '${r.expectedQty}', style: _dataCellCenterStyle);
          _setCell(sheet3, col: 6, row: r3, value: '${r.actualQty}', style: _dataCellCenterStyle);
          _setCell(sheet3, col: 7, row: r3, value: '+$surplusQty', style: _dataCellCenterStyle);
          if (includeEpc) {
            _setCell(sheet3, col: 8, row: r3, value: getRowEpcs(r, surplusOnly: true), style: _epcCellStyle);
            _setCell(sheet3, col: 9, row: r3, value: typeDesc);
            _setCell(sheet3, col: 10, row: r3, value: actionDesc);
            final epcList = getRowEpcs(r, surplusOnly: true).split(RegExp(r'\r?\n'));
            final epcCount = (getRowEpcs(r, surplusOnly: true) != '--') ? epcList.length : 1;
            sheet3.setRowHeight(r3, epcCount > 1 ? (epcCount * 17.0).clamp(24.0, 400.0) : 24.0);
          } else {
            _setCell(sheet3, col: 8, row: r3, value: typeDesc);
            _setCell(sheet3, col: 9, row: r3, value: actionDesc);
            sheet3.setRowHeight(r3, 24.0);
          }
          r3++;
        }
      }

      _autoFitColumns(sheet3, headers3Sku.length, r3 + 2);

      // =======================================================================
      // SHEET 4: CẢNH BÁO BẤT THƯỜNG - CHIP ĐÃ XUẤT KHO (NẾU CÓ PHÁT HIỆN)
      // =======================================================================
      if (allShippedItems.isNotEmpty) {
        final sheet4 = excel['Canh_Bao_Da_Xuat'];

        _setCell(sheet4, col: 0, row: 0, value: 'HỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
        _setCell(sheet4, col: 0, row: 1, value: '🚨 BẢNG CẢNH BÁO BẤT THƯỜNG: CHIP ĐÃ XUẤT KHO TRƯỚC ĐÓ PHÁT HIỆN TRONG KHO', style: CellStyle(
          bold: true,
          fontSize: 13,
          fontColorHex: ExcelColor.fromHexString('#DC2626'),
        ));
        _setCell(sheet4, col: 0, row: 2, value: '(Danh sách chip RFID thuộc hàng hóa đã làm thủ tục xuất kho nhưng vẫn quét thấy chip trong kho)', style: _subTitleStyle);

        _setCell(sheet4, col: 0, row: 4, value: 'Phạm Vi:', style: _metaLabelStyle);
        _setCell(sheet4, col: 1, row: 4, value: scopeTitle, style: _metaValueStyle);
        _setCell(sheet4, col: 4, row: 4, value: 'Phiếu Kiểm Kê:', style: _metaLabelStyle);
        _setCell(sheet4, col: 5, row: 4, value: sessionCode ?? 'Toàn bộ kho', style: _metaValueStyle);

        _setCell(sheet4, col: 0, row: 5, value: 'Tổng Chip Vi Phạm:', style: _metaLabelStyle);
        _setCell(sheet4, col: 1, row: 5, value: '${allShippedItems.length} Chip', style: _alertMetaValueStyle);
        _setCell(sheet4, col: 4, row: 5, value: 'Mức Độ Cảnh Báo:', style: _metaLabelStyle);
        _setCell(sheet4, col: 5, row: 5, value: 'NGHIÊM TRỌNG (Nguy cơ thất thoát / gian lận)', style: _alertMetaValueStyle);

        final headers4 = includeEpc
            ? ['STT', 'Mã Chip RFID (EPC)', 'Mã SKU', 'Tên Sản Phẩm', 'Vị Trí Phát Hiện', 'Trạng Thái Sổ Sách', 'Cảnh Báo & Hướng Xử Lý', 'Thời Gian Quét']
            : ['STT', 'Mã SKU', 'Tên Sản Phẩm', 'Vị Trí Phát Hiện', 'Trạng Thái Sổ Sách', 'Cảnh Báo & Hướng Xử Lý', 'Thời Gian Quét'];
        const startRow4 = 7;
        for (int c = 0; c < headers4.length; c++) {
          _setCell(sheet4, col: c, row: startRow4, value: headers4[c], style: _tableHeaderStyle('#DC2626'));
        }

        int r4 = startRow4 + 1;
        for (int i = 0; i < allShippedItems.length; i++) {
          final it = allShippedItems[i];
          _setCell(sheet4, col: 0, row: r4, value: '${i + 1}', style: _dataCellCenterStyle);
          if (includeEpc) {
            _setCell(sheet4, col: 1, row: r4, value: it.epc, style: _epcCellStyle);
            _setCell(sheet4, col: 2, row: r4, value: it.sku ?? '--', style: _dataCellCenterStyle);
            _setCell(sheet4, col: 3, row: r4, value: it.productName ?? 'Hàng đã xuất kho');
            _setCell(sheet4, col: 4, row: r4, value: it.actualLocation ?? '--', style: _dataCellCenterStyle);
            _setCell(sheet4, col: 5, row: r4, value: 'ĐÃ XUẤT KHO', style: CellStyle(
              bold: true,
              fontSize: 10,
              fontColorHex: ExcelColor.fromHexString('#DC2626'),
              horizontalAlign: HorizontalAlign.Center,
              verticalAlign: VerticalAlign.Center,
            ));
            _setCell(sheet4, col: 6, row: r4, value: '🚨 ĐÃ XUẤT KHO NHƯNG VẪN CÒN TRONG KHO - CẦN TRUY VẾT');
            _setCell(sheet4, col: 7, row: r4, value: _dtFmt.format(it.readAt), style: _dataCellCenterStyle);
          } else {
            _setCell(sheet4, col: 1, row: r4, value: it.sku ?? '--', style: _dataCellCenterStyle);
            _setCell(sheet4, col: 2, row: r4, value: it.productName ?? 'Hàng đã xuất kho');
            _setCell(sheet4, col: 3, row: r4, value: it.actualLocation ?? '--', style: _dataCellCenterStyle);
            _setCell(sheet4, col: 4, row: r4, value: 'ĐÃ XUẤT KHO', style: CellStyle(
              bold: true,
              fontSize: 10,
              fontColorHex: ExcelColor.fromHexString('#DC2626'),
              horizontalAlign: HorizontalAlign.Center,
              verticalAlign: VerticalAlign.Center,
            ));
            _setCell(sheet4, col: 5, row: r4, value: '🚨 ĐÃ XUẤT KHO NHƯNG VẪN CÒN TRONG KHO - CẦN TRUY VẾT');
            _setCell(sheet4, col: 6, row: r4, value: _dtFmt.format(it.readAt), style: _dataCellCenterStyle);
          }
          sheet4.setRowHeight(r4, 22.0);
          r4++;
        }

        final signRow4 = r4 + 3;
        _setCell(sheet4, col: 0, row: signRow4, value: 'TRƯỞNG BAN KIỂM KÊ', style: _signTitleStyle);
        _setCell(sheet4, col: 3, row: signRow4, value: 'THỦ KHO', style: _signTitleStyle);
        _setCell(sheet4, col: 5, row: signRow4, value: 'ĐẠI DIỆN KẾ TOÁN', style: _signTitleStyle);

        _setCell(sheet4, col: 0, row: signRow4 + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
        _setCell(sheet4, col: 3, row: signRow4 + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
        _setCell(sheet4, col: 5, row: signRow4 + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);

        _autoFitColumns(sheet4, headers4.length, signRow4 + 3);
      }

      // Xóa sheet mặc định 'Sheet1' của thư viện excel nếu có
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      return _saveProtectedExcelFile(excel, filePath);
    }
  }

  // =========================================================================
  // 4. FORM MẪU: BÁO CÁO TỒN KHO THEO MÃ SKU (GỘP 1 HÀNG / MÃ SKU)
  // =========================================================================
  /// Xuất Báo Cáo Tồn Kho trực tiếp (gộp chung 1 hàng / Mã SKU và ghi rõ số lượng tồn)
  Future<File> exportInventoryReport(
    ReportFormat format, {
    List<Item>? items,
    DateTime? fromDate,
    DateTime? toDate,
    bool includeEpc = false,
  }) async {
    return _exportInventoryForm(format, customItems: items, fromDate: fromDate, toDate: toDate, includeEpc: includeEpc);
  }

  Future<File> _exportInventoryForm(
    ReportFormat format, {
    List<String>? selectedEpcs,
    List<Item>? customItems,
    DateTime? fromDate,
    DateTime? toDate,
    bool includeEpc = false,
  }) async {
    var inStockItems = customItems ?? _repo.items.where((i) => i.status.code == 'IN_STOCK').toList();
    if (fromDate != null) {
      final start = DateTime(fromDate.year, fromDate.month, fromDate.day, 0, 0, 0);
      inStockItems = inStockItems.where((i) => i.inboundTime != null && (i.inboundTime!.isAfter(start) || i.inboundTime!.isAtSameMomentAs(start))).toList();
    }
    if (toDate != null) {
      final end = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59, 999);
      inStockItems = inStockItems.where((i) => i.inboundTime != null && (i.inboundTime!.isBefore(end) || i.inboundTime!.isAtSameMomentAs(end))).toList();
    }
    if (customItems == null && selectedEpcs != null && selectedEpcs.isNotEmpty) {
      inStockItems = inStockItems.where((i) => selectedEpcs.contains(i.epc) || selectedEpcs.contains(i.itemId) || selectedEpcs.contains(i.serialNumber)).toList();
    }

    // Gom nhóm danh sách sản phẩm theo mã SKU (1 dòng / Mã SKU)
    final Map<String, List<Item>> skuMap = {};
    for (final it in inStockItems) {
      final key = it.sku.trim().isNotEmpty ? it.sku.trim().toUpperCase() : 'CHƯA CÓ SKU';
      skuMap.putIfAbsent(key, () => []).add(it);
    }
    final skus = skuMap.keys.toList()..sort();

    final dir = await _getReportDir();
    final timestamp = _fileFmt.format(DateTime.now());
    final fileName = '${ReportType.inventory.filePrefix}_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    final skuHeaders = includeEpc
        ? [
            'STT', 'Mã SKU', 'Tên Sản Phẩm', 'Số Lượng',
            'Vị Trí Kệ', 'Mã Pallet', 'Nhà Cung Cấp', 'Mã Chip RFID (EPC)', 'Trạng Thái',
          ]
        : [
            'STT', 'Mã SKU', 'Tên Sản Phẩm', 'Số Lượng',
            'Vị Trí Kệ', 'Mã Pallet', 'Nhà Cung Cấp', 'Trạng Thái',
          ];

    final skuRows = <List<String>>[];
    int totalQty = 0;
    for (int i = 0; i < skus.length; i++) {
      final skuKey = skus[i];
      final items = skuMap[skuKey] ?? [];
      totalQty += items.length;
      final displaySku = items.isNotEmpty && items.first.sku.trim().isNotEmpty ? items.first.sku.trim() : skuKey;
      final rawProductName = items.isNotEmpty ? items.first.productName : displaySku;
      final productName = _repo.getSkuProductName(displaySku, rawProductName);

      final locations = items
          .map((it) => it.locationId ?? '')
          .where((l) => l.isNotEmpty)
          .toSet()
          .join(', ');

      final pallets = items
          .map((it) => it.palletId ?? '')
          .where((p) => p.isNotEmpty)
          .toSet()
          .map((pid) {
            final p = _repo.pallets.where((x) => x.palletId == pid || x.palletCode == pid).toList();
            return p.isNotEmpty ? p.first.displayName : pid;
          })
          .join(', ');

      final suppliers = items
          .map((it) => _repo.getItemSupplier(it))
          .where((s) => s.isNotEmpty && s != '--')
          .toSet()
          .toList();
      final supplierDisplay = suppliers.isNotEmpty ? suppliers.join(', ') : '--';

      final epcs = items
          .map((it) => it.epc.trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();
      final epcText = epcs.isNotEmpty ? epcs.join('\r\n') : '--';

      if (includeEpc) {
        skuRows.add([
          '${i + 1}',
          displaySku,
          productName,
          '${items.length}',
          locations.isNotEmpty ? locations : 'Chưa xếp kệ',
          pallets.isNotEmpty ? pallets : '--',
          supplierDisplay,
          epcText,
          'Đã nhập kho',
        ]);
      } else {
        skuRows.add([
          '${i + 1}',
          displaySku,
          productName,
          '${items.length}',
          locations.isNotEmpty ? locations : 'Chưa xếp kệ',
          pallets.isNotEmpty ? pallets : '--',
          supplierDisplay,
          'Đã nhập kho',
        ]);
      }
    }

    if (format == ReportFormat.csv) {
      final buffer = StringBuffer();
      buffer.writeln('\uFEFFHỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)');
      buffer.writeln('BÁO CÁO TỒN KHO THEO MÃ SKU');
      buffer.writeln('Thời điểm xuất: ${_dtFmt.format(DateTime.now())};Tổng số SKU: ${skus.length};Tổng sản phẩm tồn: $totalQty');
      buffer.writeln();
      buffer.writeln(skuHeaders.join(','));
      for (final r in skuRows) {
        buffer.writeln(r.map((c) => '"${c.replaceAll('\r\n', '; ')}"').join(','));
      }
      buffer.writeln();
      if (includeEpc) {
        buffer.writeln('TỔNG CỘNG,"Tổng SKU: ${skus.length}",,"Tổng SL: $totalQty",,,,,Đã nhập kho');
      } else {
        buffer.writeln('TỔNG CỘNG,"Tổng SKU: ${skus.length}",,"Tổng SL: $totalQty",,,,Đã nhập kho');
      }
      buffer.writeln();
      buffer.writeln('NGƯỜI LẬP BÁO CÁO,THỦ KHO,KẾ TOÁN KHO');
      buffer.writeln('(Ký ghi rõ họ tên),(Ký ghi rõ họ tên),(Ký ghi rõ họ tên)');

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      return file;
    } else {
      final excel = Excel.createExcel();
      final skuSheet = excel['Ton_Kho_SKU'];
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      _setCell(skuSheet, col: 0, row: 0, value: 'HỆ THỐNG KHO VẬN THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
      _setCell(skuSheet, col: 0, row: 1, value: 'BÁO CÁO TỒN KHO THEO MÃ SKU', style: _titleStyle);
      _setCell(skuSheet, col: 0, row: 2, value: 'Thời điểm xuất: ${_dtFmt.format(DateTime.now())}   |   Tổng SKU: ${skus.length}   |   Tổng số lượng tồn: $totalQty sản phẩm', style: _subTitleStyle);

      const startRow = 4;
      for (int c = 0; c < skuHeaders.length; c++) {
        _setCell(skuSheet, col: c, row: startRow, value: skuHeaders[c], style: _tableHeaderStyle('#047857'));
      }

      int r = startRow + 1;
      for (int i = 0; i < skuRows.length; i++) {
        final rowData = skuRows[i];
        final skuItems = skuMap[skus[i]] ?? [];
        for (int c = 0; c < rowData.length; c++) {
          final text = rowData[c];
          CellStyle? s;
          if (c == 0 || c == 3) {
            s = _dataCellCenterStyle;
          } else if (includeEpc && c == 7) {
            s = _epcCellStyle;
          } else if ((includeEpc && c == 8) || (!includeEpc && c == 7)) {
            s = _dataCellCenterStyle;
          }
          _setCell(skuSheet, col: c, row: r, value: text, style: s);
        }
        if (includeEpc) {
          final epcCount = skuItems.map((e) => e.epc.trim()).where((e) => e.isNotEmpty).toSet().length;
          skuSheet.setRowHeight(r, epcCount > 1 ? (epcCount * 17.0).clamp(24.0, 400.0) : 24.0);
        } else {
          skuSheet.setRowHeight(r, 24.0);
        }
        r++;
      }

      _setCell(skuSheet, col: 0, row: r, value: 'TỔNG CỘNG', style: _totalRowStyle);
      _setCell(skuSheet, col: 1, row: r, value: '${skus.length} Mã SKU', style: _totalRowStyle);
      _setCell(skuSheet, col: 2, row: r, value: '', style: _totalRowStyle);
      _setCell(skuSheet, col: 3, row: r, value: 'Tổng SL: $totalQty', style: _totalRowStyle);
      for (int c = 4; c < skuHeaders.length; c++) {
        _setCell(skuSheet, col: c, row: r, value: c == (skuHeaders.length - 1) ? 'Đã nhập kho' : '', style: _totalRowStyle);
      }

      final signRow = r + 3;
      _setCell(skuSheet, col: 1, row: signRow, value: 'NGƯỜI LẬP BÁO CÁO', style: _signTitleStyle);
      _setCell(skuSheet, col: 3, row: signRow, value: 'THỦ KHO', style: _signTitleStyle);
      _setCell(skuSheet, col: includeEpc ? 5 : 4, row: signRow, value: 'KẾ TOÁN KHO', style: _signTitleStyle);

      _setCell(skuSheet, col: 1, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
      _setCell(skuSheet, col: 3, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
      _setCell(skuSheet, col: includeEpc ? 5 : 4, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);

      _autoFitColumns(skuSheet, skuHeaders.length, signRow + 3);

      return _saveProtectedExcelFile(excel, filePath);
    }
  }

  // =========================================================================
  // 4b. FORM MẪU: BÁO CÁO TỔNG HỢP TỒN KHO THEO MẶT HÀNG (SKU SUMMARY)
  // =========================================================================
  Future<File> exportInventorySkuSummary(ReportFormat format, {List<String>? selectedSkus}) async {
    final inStockItems = _repo.items.where((i) => i.status.code == 'IN_STOCK').toList();

    // Gom nhóm theo SKU (chuẩn hóa)
    final Map<String, List<Item>> skuMap = {};
    for (final it in inStockItems) {
      final key = it.sku.trim().isNotEmpty ? it.sku.trim().toUpperCase() : 'CHƯA CÓ SKU';
      skuMap.putIfAbsent(key, () => []).add(it);
    }

    var skus = skuMap.keys.toList()..sort();
    if (selectedSkus != null && selectedSkus.isNotEmpty) {
      final upperSelected = selectedSkus.map((s) => s.trim().toUpperCase()).toSet();
      skus = skus.where((s) => upperSelected.contains(s)).toList();
    }

    final dir = await _getReportDir();
    final timestamp = _fileFmt.format(DateTime.now());
    final fileName = 'bao_cao_ton_kho_tong_hop_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    final headers = [
      'STT', 'Mã SKU', 'Tên Sản Phẩm', 'Nhà Cung Cấp',
      'Số Lượng', 'Vị Trí Kệ Lưu Trữ', 'Mã Pallet', 'Trạng Thái',
    ];

    final rows = <List<String>>[];
    int totalQty = 0;
    for (int i = 0; i < skus.length; i++) {
      final skuKey = skus[i];
      final items = skuMap[skuKey] ?? [];
      totalQty += items.length;
      final displaySku = items.isNotEmpty && items.first.sku.trim().isNotEmpty ? items.first.sku.trim() : skuKey;
      final rawProductName = items.isNotEmpty ? items.first.productName : displaySku;
      final productName = _repo.getSkuProductName(displaySku, rawProductName);
      final supplier = items.isNotEmpty ? _repo.getItemSupplier(items.first) : '--';

      final locations = items
          .map((it) => it.locationId ?? '')
          .where((l) => l.isNotEmpty)
          .toSet()
          .join(', ');

      final pallets = items
          .map((it) => it.palletId ?? '')
          .where((p) => p.isNotEmpty)
          .toSet()
          .map((pid) {
            final p = _repo.pallets.where((x) => x.palletId == pid || x.palletCode == pid).toList();
            return p.isNotEmpty ? p.first.displayName : pid;
          })
          .join(', ');

      rows.add([
        '${i + 1}',
        displaySku,
        productName,
        supplier,
        '${items.length}',
        locations.isNotEmpty ? locations : '--',
        pallets.isNotEmpty ? pallets : '--',
        'Đã nhập kho',
      ]);
    }

    if (format == ReportFormat.csv) {
      final buffer = StringBuffer();
      buffer.writeln('\uFEFFHỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)');
      buffer.writeln('BÁO CÁO TỔNG HỢP TỒN KHO THEO MẶT HÀNG (SKU)');
      buffer.writeln('Thời điểm xuất: ${_dtFmt.format(DateTime.now())};Tổng số SKU: ${skus.length};Tổng sản phẩm tồn: $totalQty');
      buffer.writeln();
      buffer.writeln(headers.join(','));
      for (final r in rows) {
        buffer.writeln(r.map((c) => '"$c"').join(','));
      }
      buffer.writeln();
      buffer.writeln('TỔNG CỘNG,"Tổng số SKU: ${skus.length}",,,"Tổng SL: $totalQty",,,Đã nhập kho');
      buffer.writeln();
      buffer.writeln('NGƯỜI LẬP BÁO CÁO,THỦ KHO,KẾ TOÁN KHO');
      buffer.writeln('(Ký ghi rõ họ tên),(Ký ghi rõ họ tên),(Ký ghi rõ họ tên)');

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      return file;
    } else {
      final excel = Excel.createExcel();
      final sheet = excel['Tong_Hop_Ton_Kho'];
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      _setCell(sheet, col: 0, row: 0, value: 'HỆ THỐNG KHO VẬN THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
      _setCell(sheet, col: 0, row: 1, value: 'BÁO CÁO TỔNG HỢP TỒN KHO THEO MẶT HÀNG (SKU)', style: _titleStyle);
      _setCell(sheet, col: 0, row: 2, value: 'Thời điểm xuất: ${_dtFmt.format(DateTime.now())}   |   Tổng SKU: ${skus.length}   |   Tổng tồn: $totalQty sản phẩm', style: _subTitleStyle);

      const startRow = 4;
      for (int c = 0; c < headers.length; c++) {
        _setCell(sheet, col: c, row: startRow, value: headers[c], style: _tableHeaderStyle('#047857'));
      }

      int r = startRow + 1;
      for (final rowData in rows) {
        for (int c = 0; c < rowData.length; c++) {
          _setCell(sheet, col: c, row: r, value: rowData[c], style: (c == 0 || c == 4 || c == 7) ? _dataCellCenterStyle : null);
        }
        r++;
      }

      _setCell(sheet, col: 0, row: r, value: 'TỔNG CỘNG', style: _totalRowStyle);
      _setCell(sheet, col: 1, row: r, value: '${skus.length} SKU', style: _totalRowStyle);
      _setCell(sheet, col: 2, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 3, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 4, row: r, value: 'Tổng SL: $totalQty', style: _totalRowStyle);
      _setCell(sheet, col: 5, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 6, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 7, row: r, value: 'Đã nhập kho', style: _totalRowStyle);

      final signRow = r + 3;
      _setCell(sheet, col: 1, row: signRow, value: 'NGƯỜI LẬP BÁO CÁO', style: _signTitleStyle);
      _setCell(sheet, col: 3, row: signRow, value: 'THỦ KHO', style: _signTitleStyle);
      _setCell(sheet, col: 5, row: signRow, value: 'KẾ TOÁN KHO', style: _signTitleStyle);

      _setCell(sheet, col: 1, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
      _setCell(sheet, col: 3, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
      _setCell(sheet, col: 5, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);

      _autoFitColumns(sheet, headers.length, signRow + 3);

      return _saveProtectedExcelFile(excel, filePath);
    }
  }

  Future<File> _exportTransactionLogForm(
    ReportFormat format, {
    List<String>? selectedDocNos,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    var txs = _repo.transactions;
    if (fromDate != null) {
      final start = DateTime(fromDate.year, fromDate.month, fromDate.day, 0, 0, 0);
      txs = txs.where((t) => t.timestamp.isAfter(start) || t.timestamp.isAtSameMomentAs(start)).toList();
    }
    if (toDate != null) {
      final end = DateTime(toDate.year, toDate.month, toDate.day, 23, 59, 59, 999);
      txs = txs.where((t) => t.timestamp.isBefore(end) || t.timestamp.isAtSameMomentAs(end)).toList();
    }
    if (selectedDocNos != null && selectedDocNos.isNotEmpty) {
      txs = txs.where((t) => selectedDocNos.contains(t.documentNo) || selectedDocNos.contains(t.transactionId)).toList();
    }

    // Gộp chung các giao dịch theo Mã SKU trong cùng chứng từ / nghiệp vụ (1 hàng / SKU)
    final Map<String, Map<String, dynamic>> groupedTxMap = {};
    for (final t in txs) {
      final docKey = t.documentNo.trim().isNotEmpty && t.documentNo.trim() != '--'
          ? t.documentNo.trim().toUpperCase()
          : _dtFmt.format(t.timestamp);
      final skuKey = t.sku.trim().isNotEmpty ? t.sku.trim().toUpperCase() : 'CHƯA CÓ SKU';
      final groupKey = '$docKey|${t.type.name}|$skuKey';

      if (!groupedTxMap.containsKey(groupKey)) {
        final displaySku = t.sku.trim().isNotEmpty ? t.sku.trim() : skuKey;
        groupedTxMap[groupKey] = {
          'timestamp': t.timestamp,
          'documentNo': t.documentNo,
          'typeLabel': t.type.label,
          'sku': displaySku,
          'productName': _repo.getSkuProductName(displaySku, t.productName),
          'quantity': t.quantity,
          'fromLocations': <String>{if (t.fromLocation != null && t.fromLocation!.trim().isNotEmpty) t.fromLocation!.trim()},
          'toLocations': <String>{if (t.toLocation != null && t.toLocation!.trim().isNotEmpty) t.toLocation!.trim()},
          'pallets': <String>{if (t.palletCode != null && t.palletCode!.trim().isNotEmpty) t.palletCode!.trim()},
          'performedBy': t.performedBy,
        };
      } else {
        final cur = groupedTxMap[groupKey]!;
        cur['quantity'] = (cur['quantity'] as int) + t.quantity;
        if (t.fromLocation != null && t.fromLocation!.trim().isNotEmpty) {
          (cur['fromLocations'] as Set<String>).add(t.fromLocation!.trim());
        }
        if (t.toLocation != null && t.toLocation!.trim().isNotEmpty) {
          (cur['toLocations'] as Set<String>).add(t.toLocation!.trim());
        }
        if (t.palletCode != null && t.palletCode!.trim().isNotEmpty) {
          (cur['pallets'] as Set<String>).add(t.palletCode!.trim());
        }
      }
    }

    final groupedList = groupedTxMap.values.toList();

    final dir = await _getReportDir();
    final timestamp = _fileFmt.format(DateTime.now());
    final fileName = '${ReportType.transactionLog.filePrefix}_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    final headers = [
      'STT', 'Thời Gian', 'Mã Chứng Từ', 'Nghiệp Vụ', 'Mã SKU',
      'Tên Sản Phẩm', 'Số Lượng', 'Từ Vị Trí', 'Đến Vị Trí', 'Mã Pallet', 'Người Thực Hiện',
    ];

    final rows = <List<String>>[];
    for (int i = 0; i < groupedList.length; i++) {
      final g = groupedList[i];
      final fromLocs = (g['fromLocations'] as Set<String>).join(', ');
      final toLocs = (g['toLocations'] as Set<String>).join(', ');
      final pallets = (g['pallets'] as Set<String>).join(', ');
      rows.add([
        '${i + 1}',
        _dtFmt.format(g['timestamp'] as DateTime),
        g['documentNo'] as String,
        g['typeLabel'] as String,
        g['sku'] as String,
        g['productName'] as String,
        '${g['quantity']}',
        fromLocs.isNotEmpty ? fromLocs : '--',
        toLocs.isNotEmpty ? toLocs : '--',
        pallets.isNotEmpty ? pallets : '--',
        g['performedBy'] as String,
      ]);
    }

    final totalQty = groupedList.fold<int>(0, (s, g) => s + (g['quantity'] as int));

    if (format == ReportFormat.csv) {
      final buffer = StringBuffer();
      buffer.writeln('\uFEFFHỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)');
      buffer.writeln('SỔ NHẬT KÝ BIẾN ĐỘNG VÀ ĐIỀU CHUYỂN KHO');
      buffer.writeln('Thời điểm xuất: ${_dtFmt.format(DateTime.now())};Tổng số dòng SKU: ${groupedList.length};Tổng số lượng: $totalQty');
      buffer.writeln();
      buffer.writeln(headers.join(','));
      for (final r in rows) {
        buffer.writeln(r.map((c) => '"$c"').join(','));
      }
      buffer.writeln();
      buffer.writeln('TỔNG CỘNG,"${groupedList.length} dòng SKU",,,,,"Tổng SL: $totalQty",,,,');
      buffer.writeln();
      buffer.writeln('NGƯỜI LẬP SỔ,THỦ KHO,KẾ TOÁN TRƯỞNG');
      buffer.writeln('(Ký ghi rõ họ tên),(Ký ghi rõ họ tên),(Ký ghi rõ họ tên)');

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      return file;
    } else {
      final excel = Excel.createExcel();
      final sheet = excel['Bien_Dong_Kho'];
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      _setCell(sheet, col: 0, row: 0, value: 'HỆ THỐNG KHO VẬN THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
      _setCell(sheet, col: 0, row: 1, value: 'SỔ NHẬT KÝ BIẾN ĐỘNG & ĐIỀU CHUYỂN KHO (GỘP THEO MÃ SKU)', style: _titleStyle);
      _setCell(sheet, col: 0, row: 2, value: 'Thời điểm xuất: ${_dtFmt.format(DateTime.now())}   |   Tổng dòng SKU: ${groupedList.length}   |   Tổng SL: $totalQty', style: _subTitleStyle);

      const startRow = 4;
      for (int c = 0; c < headers.length; c++) {
        _setCell(sheet, col: c, row: startRow, value: headers[c], style: _tableHeaderStyle('#F59E0B'));
      }

      int r = startRow + 1;
      for (final rowData in rows) {
        for (int c = 0; c < rowData.length; c++) {
          _setCell(sheet, col: c, row: r, value: rowData[c], style: (c == 0 || c == 1 || c == 3 || c == 6 || c == 7 || c == 8 || c == 9) ? _dataCellCenterStyle : null);
        }
        r++;
      }

      _setCell(sheet, col: 0, row: r, value: 'TỔNG CỘNG', style: _totalRowStyle);
      _setCell(sheet, col: 1, row: r, value: '${groupedList.length} Dòng SKU', style: _totalRowStyle);
      _setCell(sheet, col: 2, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 3, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 4, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 5, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 6, row: r, value: 'Tổng SL: $totalQty', style: _totalRowStyle);
      for (int c = 7; c < headers.length; c++) {
        _setCell(sheet, col: c, row: r, value: '', style: _totalRowStyle);
      }

      final signRow = r + 3;
      _setCell(sheet, col: 1, row: signRow, value: 'NGƯỜI LẬP SỔ', style: _signTitleStyle);
      _setCell(sheet, col: 4, row: signRow, value: 'THỦ KHO', style: _signTitleStyle);
      _setCell(sheet, col: 8, row: signRow, value: 'KẾ TOÁN TRƯỞNG', style: _signTitleStyle);

      _setCell(sheet, col: 1, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
      _setCell(sheet, col: 4, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
      _setCell(sheet, col: 8, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);

      _autoFitColumns(sheet, headers.length, signRow + 3);

      return _saveProtectedExcelFile(excel, filePath);
    }
  }

  // =========================================================================
  // CELL & STYLE HELPERS
  // =========================================================================

  void _setCell(
    Sheet sheet, {
    required int col,
    required int row,
    required String value,
    CellStyle? style,
  }) {
    final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(value);
    if (style != null) {
      cell.cellStyle = style;
    }
  }

  void _autoFitColumns(Sheet sheet, int colCount, int maxRows) {
    for (int col = 0; col < colCount; col++) {
      double maxLen = 8.0;
      for (int row = 0; row < maxRows; row++) {
        final cell = sheet.cell(CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
        final val = cell.value?.toString() ?? '';
        // Bỏ qua các dòng tiêu đề dài ở cột 0 khi tính chiều rộng cột
        if (col == 0 && row < 3) continue;
        // Nếu ô có xuống dòng (như cột Vòng Đời Thẻ), tính chiều dài dòng dài nhất
        final lines = val.split(RegExp(r'\r?\n'));
        for (final line in lines) {
          if (line.length > maxLen) {
            maxLen = line.length.toDouble();
          }
        }
      }
      if (col == 10) {
        // Cột Vòng Đời Thẻ: Giới hạn độ rộng tối ưu để hiển thị xuống dòng thoáng đãng, dễ đọc
        sheet.setColumnWidth(col, maxLen < 45 ? 45 : (maxLen > 65 ? 65 : maxLen + 3));
      } else {
        sheet.setColumnWidth(col, maxLen < 11 ? 13 : (maxLen > 70 ? 70 : maxLen + 3));
      }
    }
  }

  String _safeSheetName(String prefix, String code) {
    final clean = code.replaceAll(RegExp(r'[\\/?*:[\]]'), '_').trim();
    final full = '${prefix}_$clean';
    return full.length <= 30 ? full : full.substring(0, 30);
  }

  CellStyle get _titleStyle => CellStyle(
        bold: true,
        fontSize: 14,
        fontColorHex: ExcelColor.fromHexString('#0F172A'),
        verticalAlign: VerticalAlign.Center,
      );

  CellStyle get _subTitleStyle => CellStyle(
        italic: true,
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString('#475569'),
        verticalAlign: VerticalAlign.Center,
      );

  CellStyle get _companyHeaderStyle => CellStyle(
        bold: true,
        fontSize: 9,
        fontColorHex: ExcelColor.fromHexString('#64748B'),
      );

  CellStyle get _metaLabelStyle => CellStyle(
        bold: true,
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString('#334155'),
      );

  CellStyle get _metaValueStyle => CellStyle(
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString('#0F172A'),
      );

  CellStyle get _alertMetaValueStyle => CellStyle(
        bold: true,
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString('#DC2626'),
      );

  CellStyle _tableHeaderStyle(String hexBg) => CellStyle(
        bold: true,
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString('#FFFFFF'),
        backgroundColorHex: ExcelColor.fromHexString(hexBg),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

  CellStyle get _dataCellCenterStyle => CellStyle(
        fontSize: 10,
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

  CellStyle get _epcCellStyle => CellStyle(
        fontSize: 9,
        fontColorHex: ExcelColor.fromHexString('#1E293B'),
        verticalAlign: VerticalAlign.Center,
        horizontalAlign: HorizontalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );

  CellStyle get _multiLineCenterCellStyle => CellStyle(
        fontSize: 9,
        fontColorHex: ExcelColor.fromHexString('#1E293B'),
        verticalAlign: VerticalAlign.Center,
        horizontalAlign: HorizontalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );

  CellStyle get _totalRowStyle => CellStyle(
        bold: true,
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString('#0F172A'),
        backgroundColorHex: ExcelColor.fromHexString('#F1F5F9'),
        verticalAlign: VerticalAlign.Center,
        horizontalAlign: HorizontalAlign.Center,
      );

  CellStyle get _signTitleStyle => CellStyle(
        bold: true,
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString('#0F172A'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

  CellStyle get _signNoteStyle => CellStyle(
        italic: true,
        fontSize: 9,
        fontColorHex: ExcelColor.fromHexString('#64748B'),
        horizontalAlign: HorizontalAlign.Center,
        verticalAlign: VerticalAlign.Center,
      );

  // =========================================================================
  // XUẤT TẬP TIN EXCEL MỞ (CHO PHÉP COPY VÀ CHỈNH SỬA DỮ LIỆU TỰ DO)
  // =========================================================================

  /// Lưu file Excel chuẩn mở, cho phép người dùng tự do sao chép (copy), chỉnh sửa và chia sẻ dữ liệu
  Future<File> _saveProtectedExcelFile(Excel excel, String filePath) async {
    final rawBytes = excel.encode();
    if (rawBytes == null) throw Exception('Không thể tạo file Excel.');

    final file = File(filePath);
    await file.writeAsBytes(rawBytes);
    return file;
  }
}
