import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
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
  }) async {
    return exportReportSelected(type, format, fromDate: fromDate, toDate: toDate);
  }

  /// Xuất báo cáo chọn lọc theo danh sách ID/Mã đơn được tick chọn và khoảng thời gian
  Future<File> exportReportSelected(
    ReportType type,
    ReportFormat format, {
    List<String>? selectedKeys,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    switch (type) {
      case ReportType.inbound:
        return _exportInboundForm(format, selectedOrderNos: selectedKeys, fromDate: fromDate, toDate: toDate);
      case ReportType.outbound:
        return _exportOutboundForm(format, selectedPoNos: selectedKeys, fromDate: fromDate, toDate: toDate);
      case ReportType.inventory:
        return _exportInventoryForm(format, selectedEpcs: selectedKeys, fromDate: fromDate, toDate: toDate);
      case ReportType.audit:
        return _exportAuditForm(format, selectedSessionCodes: selectedKeys);
      case ReportType.transactionLog:
        return _exportTransactionLogForm(format, selectedDocNos: selectedKeys, fromDate: fromDate, toDate: toDate);
    }
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
  Future<File> _exportInboundForm(
    ReportFormat format, {
    List<String>? selectedOrderNos,
    DateTime? fromDate,
    DateTime? toDate,
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
      // Xuất CSV dạng Form có cấu trúc chuẩn
      final buffer = StringBuffer();
      buffer.writeln('\uFEFFHỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)');
      buffer.writeln('TRUNG TÂM XUẤT BIỂU MẪU PHIẾU NHẬP KHO');
      buffer.writeln('Ngày kết xuất: ${_dtFmt.format(DateTime.now())};Tổng số đơn xuất: ${orders.length}');
      buffer.writeln();

      for (int i = 0; i < orders.length; i++) {
        final ord = orders[i];
        final ordItems = allItems.where((it) => it.orderNo == ord.orderNo || it.orderNo == ord.inboundOrderId).toList();

        buffer.writeln('================================================================================');
        buffer.writeln('PHIẾU NHẬP KHO: ${ord.orderNo}');
        buffer.writeln('Nhà cung cấp: ${ord.sourceSupplier};Ngày tạo: ${_dtFmt.format(ord.createdAt)};Trạng thái: ${ord.status.label}');
        buffer.writeln('Kho tiếp nhận: Kho Tổng RFID;Đơn vị: RFID WMS Platform;Người lập: Quản lý kho');
        buffer.writeln();

        buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,Mã Thùng,Mã Pallet,Vị Trí Kệ,Số Lượng,Mã Chip RFID (EPC),Ghi Chú');

        if (ordItems.isNotEmpty) {
          for (int r = 0; r < ordItems.length; r++) {
            final it = ordItems[r];
            buffer.writeln('${r + 1},${it.sku},"${it.productName}",${it.cartonDisplay},${it.palletId ?? "--"},${it.locationId ?? "--"},1,${it.epc},${it.status.label}');
          }
        } else if (ord.details.isNotEmpty) {
          for (int r = 0; r < ord.details.length; r++) {
            final d = ord.details[r];
            buffer.writeln('${r + 1},${d.sku},"${d.productName}",--,--,--,${d.requiredQty},--,Chờ đối soát chip');
          }
        } else {
          buffer.writeln('1,--,Chưa có dữ liệu chi tiết hàng hóa,--,--,--,0,--,--');
        }

        final totalQty = ordItems.isNotEmpty ? ordItems.length : ord.details.fold<int>(0, (s, d) => s + d.requiredQty);
        buffer.writeln('TỔNG CỘNG,,,,,,"Tổng SL: $totalQty","Tổng Chip: ${ordItems.length}",Hoàn tất đối soát');
        buffer.writeln();
        buffer.writeln('NGƯỜI LẬP PHIẾU,NGƯỜI GIAO HÀNG,THỦ KHO NHẬN,KẾ TOÁN TRƯỞNG');
        buffer.writeln('(Ký ghi rõ họ tên),(Ký ghi rõ họ tên),(Ký ghi rõ họ tên),(Ký ghi rõ họ tên)');
        buffer.writeln();
      }

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      return file;
    } else {
      // Xuất Excel .xlsx chuẩn Form Doanh Nghiệp
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
        _buildSingleInboundOrderSheet(sheet, ord, allItems);
      }

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      return _saveProtectedExcelFile(excel, filePath);
    }
  }

  void _buildSingleInboundOrderSheet(Sheet sheet, InboundOrder ord, List<Item> allItems) {
    final ordItems = allItems.where((it) => it.orderNo == ord.orderNo || it.orderNo == ord.inboundOrderId).toList();
    final totalQty = ordItems.isNotEmpty ? ordItems.length : ord.details.fold<int>(0, (s, d) => s + d.requiredQty);
    final skuCount = ord.details.isNotEmpty ? ord.details.length : ordItems.map((i) => i.sku).toSet().length;

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
    final headers = ['STT', 'Mã SKU', 'Tên Sản Phẩm', 'Mã Thùng', 'Mã Pallet', 'Vị Trí Kệ', 'Số Lượng', 'Mã Chip RFID (EPC)', 'Trạng Thái'];
    const startRow = 8;
    for (int col = 0; col < headers.length; col++) {
      _setCell(sheet, col: col, row: startRow, value: headers[col], style: _tableHeaderStyle('#0284C7'));
    }

    int currentRow = startRow + 1;
    if (ordItems.isNotEmpty) {
      for (int i = 0; i < ordItems.length; i++) {
        final it = ordItems[i];
        _setCell(sheet, col: 0, row: currentRow, value: '${i + 1}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 1, row: currentRow, value: it.sku);
        _setCell(sheet, col: 2, row: currentRow, value: it.productName);
        _setCell(sheet, col: 3, row: currentRow, value: it.cartonDisplay, style: _dataCellCenterStyle);
        _setCell(sheet, col: 4, row: currentRow, value: it.palletId ?? '--', style: _dataCellCenterStyle);
        _setCell(sheet, col: 5, row: currentRow, value: it.locationId ?? '--', style: _dataCellCenterStyle);
        _setCell(sheet, col: 6, row: currentRow, value: '1', style: _dataCellCenterStyle);
        _setCell(sheet, col: 7, row: currentRow, value: it.epc);
        _setCell(sheet, col: 8, row: currentRow, value: it.status.label, style: _dataCellCenterStyle);
        currentRow++;
      }
    } else if (ord.details.isNotEmpty) {
      for (int i = 0; i < ord.details.length; i++) {
        final d = ord.details[i];
        _setCell(sheet, col: 0, row: currentRow, value: '${i + 1}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 1, row: currentRow, value: d.sku);
        _setCell(sheet, col: 2, row: currentRow, value: d.productName);
        _setCell(sheet, col: 3, row: currentRow, value: '--', style: _dataCellCenterStyle);
        _setCell(sheet, col: 4, row: currentRow, value: '--', style: _dataCellCenterStyle);
        _setCell(sheet, col: 5, row: currentRow, value: '--', style: _dataCellCenterStyle);
        _setCell(sheet, col: 6, row: currentRow, value: '${d.requiredQty}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 7, row: currentRow, value: '--');
        _setCell(sheet, col: 8, row: currentRow, value: 'Chờ đối soát chip', style: _dataCellCenterStyle);
        currentRow++;
      }
    } else {
      _setCell(sheet, col: 0, row: currentRow, value: '1', style: _dataCellCenterStyle);
      _setCell(sheet, col: 1, row: currentRow, value: '--');
      _setCell(sheet, col: 2, row: currentRow, value: 'Chưa có chi tiết mặt hàng trong đơn');
      for (int c = 3; c < headers.length; c++) {
        _setCell(sheet, col: c, row: currentRow, value: '--', style: _dataCellCenterStyle);
      }
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
    _setCell(sheet, col: 7, row: currentRow, value: 'Tổng Chip: ${ordItems.length}', style: _totalRowStyle);
    _setCell(sheet, col: 8, row: currentRow, value: 'Hoàn tất đối soát', style: _totalRowStyle);

    // Signatures
    final signRow = currentRow + 3;
    _setCell(sheet, col: 0, row: signRow, value: 'NGƯỜI LẬP PHIẾU', style: _signTitleStyle);
    _setCell(sheet, col: 2, row: signRow, value: 'NGƯỜI GIAO HÀNG', style: _signTitleStyle);
    _setCell(sheet, col: 5, row: signRow, value: 'THỦ KHO NHẬN', style: _signTitleStyle);
    _setCell(sheet, col: 7, row: signRow, value: 'KẾ TOÁN TRƯỞNG', style: _signTitleStyle);

    _setCell(sheet, col: 0, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: 2, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: 5, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: 7, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);

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
      final ordItems = allItems.where((it) => it.orderNo == ord.orderNo || it.orderNo == ord.inboundOrderId).toList();
      final totalQty = ordItems.isNotEmpty ? ordItems.length : ord.details.fold<int>(0, (s, d) => s + d.requiredQty);
      final skuCount = ord.details.isNotEmpty ? ord.details.length : ordItems.map((it) => it.sku).toSet().length;

      grandTotalItems += totalQty;
      grandTotalChips += ordItems.length;

      _setCell(sheet, col: 0, row: row, value: '${i + 1}', style: _dataCellCenterStyle);
      _setCell(sheet, col: 1, row: row, value: ord.orderNo);
      _setCell(sheet, col: 2, row: row, value: ord.sourceSupplier);
      _setCell(sheet, col: 3, row: row, value: _dtFmt.format(ord.createdAt), style: _dataCellCenterStyle);
      _setCell(sheet, col: 4, row: row, value: '$skuCount', style: _dataCellCenterStyle);
      _setCell(sheet, col: 5, row: row, value: '$totalQty', style: _dataCellCenterStyle);
      _setCell(sheet, col: 6, row: row, value: '${ordItems.length}', style: _dataCellCenterStyle);
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
  Future<File> _exportOutboundForm(
    ReportFormat format, {
    List<String>? selectedPoNos,
    DateTime? fromDate,
    DateTime? toDate,
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
    final fileName = '${ReportType.outbound.filePrefix}_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    if (format == ReportFormat.csv) {
      final buffer = StringBuffer();
      buffer.writeln('\uFEFFHỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)');
      buffer.writeln('TRUNG TÂM XUẤT BIỂU MẪU PHIẾU XUẤT KHO & GIAO HÀNG');
      buffer.writeln('Ngày kết xuất: ${_dtFmt.format(DateTime.now())};Tổng số đơn xuất: ${orders.length}');
      buffer.writeln();

      for (final ord in orders) {
        var effectiveDetails = ord.details;
        if (effectiveDetails.isEmpty) {
          final txs = _repo.transactions.where((t) =>
              t.type == TransactionType.outbound &&
              (t.documentNo.trim().toUpperCase() == ord.poNo.trim().toUpperCase() ||
               t.documentNo.trim().toUpperCase() == ord.outboundOrderId.trim().toUpperCase() ||
               (ord.poNo.isNotEmpty && t.transactionId.contains(ord.poNo)) ||
               (ord.outboundOrderId.isNotEmpty && t.transactionId.contains(ord.outboundOrderId)))).toList();
          if (txs.isNotEmpty) {
            effectiveDetails = txs.map((t) => OutboundOrderDetail(
              productId: t.sku,
              sku: t.sku,
              productName: t.productName.isNotEmpty ? t.productName : 'Sản phẩm xuất kho',
              requiredQty: t.quantity,
              pickedQty: t.quantity,
            )).toList();
          }
        }

        var totalReq = effectiveDetails.fold<int>(0, (s, d) => s + d.requiredQty);
        var totalPicked = effectiveDetails.fold<int>(0, (s, d) => s + d.pickedQty);
        if (totalReq > 0 && totalPicked == 0 && ord.status == OutboundOrderStatus.shipped) {
          totalPicked = totalReq;
        }

        final delivery = deliveries.where((d) => d.poNo == ord.poNo).toList();
        final deliveryNos = delivery.map((d) => d.deliveryNo).join(', ');

        buffer.writeln('================================================================================');
        buffer.writeln('PHIẾU XUẤT KHO KIÊM BÀN GIAO: ${ord.poNo}');
        buffer.writeln('Khách hàng: ${ord.customer};Ngày tạo: ${_dtFmt.format(ord.createdAt)};Trạng thái: ${ord.status.label}');
        buffer.writeln('Mã vận đơn: ${deliveryNos.isEmpty ? "--" : deliveryNos};Kho xuất: Kho Tổng RFID;Quy tắc: Chuẩn FIFO');
        buffer.writeln();

        buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,SL Yêu Cầu,SL Thực Xuất,Vị Trí Lấy Hàng,Mã Pallet,Mã Chip RFID (EPC),Ghi Chú');

        if (effectiveDetails.isNotEmpty) {
          for (int r = 0; r < effectiveDetails.length; r++) {
            final d = effectiveDetails[r];
            final epcs = d.epcList != null && d.epcList!.isNotEmpty ? d.epcList!.join('; ') : '--';
            buffer.writeln('${r + 1},${d.sku},"${d.productName}",${d.requiredQty},${d.pickedQty},Kho Tổng,Pallet xuất,"$epcs",Đạt chuẩn FIFO');
          }
        }

        buffer.writeln('TỔNG CỘNG,,,"Tổng YC: $totalReq","Tổng Xuất: $totalPicked",,,,Đạt chuẩn xuất kho');
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
        _buildSingleOutboundOrderSheet(sheet, ord, deliveries);
      }

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      return _saveProtectedExcelFile(excel, filePath);
    }
  }

  void _buildSingleOutboundOrderSheet(Sheet sheet, OutboundOrder ord, List<DeliveryNote> deliveries) {
    var effectiveDetails = ord.details;
    if (effectiveDetails.isEmpty) {
      final txs = _repo.transactions.where((t) =>
          t.type == TransactionType.outbound &&
          (t.documentNo.trim().toUpperCase() == ord.poNo.trim().toUpperCase() ||
           t.documentNo.trim().toUpperCase() == ord.outboundOrderId.trim().toUpperCase() ||
           (ord.poNo.isNotEmpty && t.transactionId.contains(ord.poNo)) ||
           (ord.outboundOrderId.isNotEmpty && t.transactionId.contains(ord.outboundOrderId)))).toList();
      if (txs.isNotEmpty) {
        effectiveDetails = txs.map((t) => OutboundOrderDetail(
          productId: t.sku,
          sku: t.sku,
          productName: t.productName.isNotEmpty ? t.productName : 'Sản phẩm xuất kho',
          requiredQty: t.quantity,
          pickedQty: t.quantity,
        )).toList();
      }
    }

    var totalReq = effectiveDetails.fold<int>(0, (s, d) => s + d.requiredQty);
    var totalPicked = effectiveDetails.fold<int>(0, (s, d) => s + d.pickedQty);
    if (totalReq > 0 && totalPicked == 0 && ord.status == OutboundOrderStatus.shipped) {
      totalPicked = totalReq;
    }
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

    final headers = ['STT', 'Mã SKU', 'Tên Sản Phẩm', 'SL Yêu Cầu', 'SL Thực Xuất', 'Vị Trí Lấy Hàng', 'Mã Pallet', 'Mã Chip RFID (EPC)', 'Ghi Chú'];
    const startRow = 8;
    for (int col = 0; col < headers.length; col++) {
      _setCell(sheet, col: col, row: startRow, value: headers[col], style: _tableHeaderStyle('#3B82F6'));
    }

    int currentRow = startRow + 1;
    if (effectiveDetails.isNotEmpty) {
      for (int i = 0; i < effectiveDetails.length; i++) {
        final d = effectiveDetails[i];
        final epcs = d.epcList != null && d.epcList!.isNotEmpty ? d.epcList!.join('; ') : '--';

        _setCell(sheet, col: 0, row: currentRow, value: '${i + 1}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 1, row: currentRow, value: d.sku);
        _setCell(sheet, col: 2, row: currentRow, value: d.productName);
        _setCell(sheet, col: 3, row: currentRow, value: '${d.requiredQty}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 4, row: currentRow, value: '${d.pickedQty}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 5, row: currentRow, value: 'Kho Tổng RFID', style: _dataCellCenterStyle);
        _setCell(sheet, col: 6, row: currentRow, value: 'Pallet Xuất', style: _dataCellCenterStyle);
        _setCell(sheet, col: 7, row: currentRow, value: epcs);
        _setCell(sheet, col: 8, row: currentRow, value: 'Đạt chuẩn FIFO', style: _dataCellCenterStyle);
        currentRow++;
      }
    } else {
      _setCell(sheet, col: 0, row: currentRow, value: '1', style: _dataCellCenterStyle);
      _setCell(sheet, col: 1, row: currentRow, value: '--');
      _setCell(sheet, col: 2, row: currentRow, value: 'Chưa có chi tiết mặt hàng');
      for (int c = 3; c < headers.length; c++) {
        _setCell(sheet, col: c, row: currentRow, value: '--', style: _dataCellCenterStyle);
      }
      currentRow++;
    }

    _setCell(sheet, col: 0, row: currentRow, value: 'TỔNG CỘNG', style: _totalRowStyle);
    _setCell(sheet, col: 1, row: currentRow, value: 'Tổng SKU: ${ord.details.length}', style: _totalRowStyle);
    _setCell(sheet, col: 2, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 3, row: currentRow, value: 'Tổng YC: $totalReq', style: _totalRowStyle);
    _setCell(sheet, col: 4, row: currentRow, value: 'Tổng Xuất: $totalPicked', style: _totalRowStyle);
    _setCell(sheet, col: 5, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 6, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 7, row: currentRow, value: '', style: _totalRowStyle);
    _setCell(sheet, col: 8, row: currentRow, value: 'Đạt chuẩn xuất', style: _totalRowStyle);

    final signRow = currentRow + 3;
    _setCell(sheet, col: 0, row: signRow, value: 'NGƯỜI LẬP PHIẾU', style: _signTitleStyle);
    _setCell(sheet, col: 2, row: signRow, value: 'NGƯỜI NHẬN HÀNG', style: _signTitleStyle);
    _setCell(sheet, col: 5, row: signRow, value: 'THỦ KHO XUẤT', style: _signTitleStyle);
    _setCell(sheet, col: 7, row: signRow, value: 'GIÁM ĐỐC / KẾ TOÁN', style: _signTitleStyle);

    _setCell(sheet, col: 0, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: 2, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: 5, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
    _setCell(sheet, col: 7, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);

    _autoFitColumns(sheet, headers.length, signRow + 3);
  }

  void _buildOutboundSummarySheet(Sheet sheet, List<OutboundOrder> orders, List<DeliveryNote> deliveries) {
    _setCell(sheet, col: 0, row: 0, value: 'HỆ THỐNG KHO VẬN THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
    _setCell(sheet, col: 0, row: 1, value: 'BẢNG TỔNG HỢP CÁC ĐƠN XUẤT KHO ĐÃ CHỌN', style: _titleStyle);
    _setCell(sheet, col: 0, row: 2, value: 'Thời điểm xuất: ${_dtFmt.format(DateTime.now())}   |   Số lượng đơn: ${orders.length}', style: _subTitleStyle);

    final headers = ['STT', 'Mã PO / Đơn Xuất', 'Khách Hàng', 'Ngày Tạo', 'Số Loại SKU', 'SL Yêu Cầu', 'SL Đã Xuất', 'Mã Vận Đơn', 'Trạng Thái'];
    const startRow = 4;
    for (int c = 0; c < headers.length; c++) {
      _setCell(sheet, col: c, row: startRow, value: headers[c], style: _tableHeaderStyle('#3B82F6'));
    }

    int row = startRow + 1;
    int grandReq = 0;
    int grandPicked = 0;

    for (int i = 0; i < orders.length; i++) {
      final ord = orders[i];
      final totalReq = ord.details.fold<int>(0, (s, d) => s + d.requiredQty);
      final totalPicked = ord.details.fold<int>(0, (s, d) => s + d.pickedQty);
      final delivery = deliveries.where((d) => d.poNo == ord.poNo).toList();
      final deliveryNos = delivery.map((d) => d.deliveryNo).join(', ');

      grandReq += totalReq;
      grandPicked += totalPicked;

      _setCell(sheet, col: 0, row: row, value: '${i + 1}', style: _dataCellCenterStyle);
      _setCell(sheet, col: 1, row: row, value: ord.poNo);
      _setCell(sheet, col: 2, row: row, value: ord.customer);
      _setCell(sheet, col: 3, row: row, value: _dtFmt.format(ord.createdAt), style: _dataCellCenterStyle);
      _setCell(sheet, col: 4, row: row, value: '${ord.details.length}', style: _dataCellCenterStyle);
      _setCell(sheet, col: 5, row: row, value: '$totalReq', style: _dataCellCenterStyle);
      _setCell(sheet, col: 6, row: row, value: '$totalPicked', style: _dataCellCenterStyle);
      _setCell(sheet, col: 7, row: row, value: deliveryNos.isEmpty ? '--' : deliveryNos, style: _dataCellCenterStyle);
      _setCell(sheet, col: 8, row: row, value: ord.status.label, style: _dataCellCenterStyle);
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

    _autoFitColumns(sheet, headers.length, row + 2);
  }

  // =========================================================================
  // 3. FORM MẪU: BIÊN BẢN KIỂM KÊ KHO HÀNG RFID (AUDIT REPORT)
  // =========================================================================
  Future<File> _exportAuditForm(ReportFormat format, {List<String>? selectedSessionCodes}) async {
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
        buffer.writeln('================================================================================');
        buffer.writeln('BIÊN BẢN KIỂM KÊ KHO: ${s.sessionCode}');
        buffer.writeln('Khu vực: ${s.zone};Vị trí: ${s.locationCode ?? "--"};Bắt đầu: ${_dtFmt.format(s.startedAt)}');
        buffer.writeln('Hoàn thành: ${s.completedAt != null ? _dtFmt.format(s.completedAt!) : "Đang kiểm"};Trạng thái: ${s.isCompleted ? "ĐÃ HOÀN TẤT" : "ĐANG KIỂM KÊ"}');
        buffer.writeln('Tổng quét: ${s.actualScannedCount};Khớp: ${s.matchCount};Thiếu: ${s.missingCount};Sai vị trí: ${s.wrongLocationCount};Thẻ lạ: ${s.unknownEpcCount}');
        buffer.writeln();

        buffer.writeln('STT,Mã Chip RFID (EPC),Mã SKU,Tên Sản Phẩm,Vị Trí Dự Kiến,Vị Trí Thực Tế,Kết Quả Đối Soát');
        if (s.results.isNotEmpty) {
          for (int r = 0; r < s.results.length; r++) {
            final res = s.results[r];
            buffer.writeln('${r + 1},${res.epc},${res.sku ?? "--"},"${res.productName ?? "--"}",${res.expectedLocation ?? "--"},${res.actualLocation ?? "--"},${res.resultType.label}');
          }
        } else {
          buffer.writeln('1,--,--,Chưa ghi nhận chi tiết thẻ đối soát,--,--,--');
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
        _buildSingleAuditSessionSheet(sheet, s);
      }

      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      return _saveProtectedExcelFile(excel, filePath);
    }
  }

  void _buildSingleAuditSessionSheet(Sheet sheet, InventorySession s) {
    _setCell(sheet, col: 0, row: 0, value: 'HỆ THỐNG KHO VẬN THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
    _setCell(sheet, col: 0, row: 1, value: 'BIÊN BẢN KIỂM KÊ KHO HÀNG RFID', style: _titleStyle);
    _setCell(sheet, col: 0, row: 2, value: '(Đối soát số dư thực tế tại ô kệ với cơ sở dữ liệu hệ thống)', style: _subTitleStyle);

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
    _setCell(sheet, col: 5, row: 8, value: 'Thẻ lạ: ${s.unknownEpcCount}', style: _metaValueStyle);

    final headers = ['STT', 'Mã Chip RFID (EPC)', 'Mã SKU', 'Tên Sản Phẩm', 'Vị Trí Dự Kiến', 'Vị Trí Thực Tế', 'Kết Quả Đối Soát'];
    const startRow = 10;
    for (int col = 0; col < headers.length; col++) {
      _setCell(sheet, col: col, row: startRow, value: headers[col], style: _tableHeaderStyle('#8B5CF6'));
    }

    int currentRow = startRow + 1;
    if (s.results.isNotEmpty) {
      for (int i = 0; i < s.results.length; i++) {
        final res = s.results[i];
        _setCell(sheet, col: 0, row: currentRow, value: '${i + 1}', style: _dataCellCenterStyle);
        _setCell(sheet, col: 1, row: currentRow, value: res.epc);
        _setCell(sheet, col: 2, row: currentRow, value: res.sku ?? '--');
        _setCell(sheet, col: 3, row: currentRow, value: res.productName ?? '--');
        _setCell(sheet, col: 4, row: currentRow, value: res.expectedLocation ?? '--', style: _dataCellCenterStyle);
        _setCell(sheet, col: 5, row: currentRow, value: res.actualLocation ?? '--', style: _dataCellCenterStyle);
        _setCell(sheet, col: 6, row: currentRow, value: res.resultType.label, style: _dataCellCenterStyle);
        currentRow++;
      }
    } else {
      _setCell(sheet, col: 0, row: currentRow, value: '1', style: _dataCellCenterStyle);
      _setCell(sheet, col: 1, row: currentRow, value: '--');
      _setCell(sheet, col: 2, row: currentRow, value: '--');
      _setCell(sheet, col: 3, row: currentRow, value: 'Chưa có bản ghi thẻ đối soát');
      _setCell(sheet, col: 4, row: currentRow, value: '--', style: _dataCellCenterStyle);
      _setCell(sheet, col: 5, row: currentRow, value: '--', style: _dataCellCenterStyle);
      _setCell(sheet, col: 6, row: currentRow, value: '--', style: _dataCellCenterStyle);
      currentRow++;
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

    final headers = ['STT', 'Mã Phiên', 'Khu Vực', 'Vị Trí Kệ', 'Bắt Đầu', 'Tổng Quét', 'Khớp', 'Thiếu', 'Lệch Vị Trí', 'Thẻ Lạ', 'Trạng Thái'];
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
      _setCell(sheet, col: 9, row: row, value: '${s.unknownEpcCount}', style: _dataCellCenterStyle);
      _setCell(sheet, col: 10, row: row, value: s.isCompleted ? 'Hoàn tất' : 'Đang thực hiện', style: _dataCellCenterStyle);
      row++;
    }

    _autoFitColumns(sheet, headers.length, row + 2);
  }

  /// Xuất Báo Cáo Đối Soát Tồn Kho Chuẩn Doanh Nghiệp (3 Sheet: Tổng Hợp, Thiếu & Đủ, Thừa & EPC Thừa)
  Future<File> exportStockReconciliationReport(
    ReportFormat format, {
    required List<SkuStockReconciliationRow> rows,
    required String scopeTitle,
    String? sessionCode,
  }) async {
    final dir = await _getReportDir();
    final timestamp = _fileFmt.format(DateTime.now());
    final fileName = 'doi_soat_ton_kho_${sessionCode ?? "tong_hop"}_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    final totalExp = rows.fold<int>(0, (s, r) => s + r.expectedQty);
    final totalAct = rows.fold<int>(0, (s, r) => s + r.actualQty);
    final totalMatched = rows.fold<int>(0, (s, r) => s + r.matchedCount);
    final totalMissing = rows.fold<int>(0, (s, r) => s + r.missingCount);
    final totalWrongLoc = rows.fold<int>(0, (s, r) => s + r.wrongLocationCount);
    final totalUnknown = rows.fold<int>(0, (s, r) => s + r.unknownCount);
    final totalSurplus = rows.fold<int>(0, (s, r) => s + (r.difference > 0 ? r.difference : (r.unknownCount > 0 ? r.unknownCount : 0)));
    final acc = totalExp > 0 ? (totalMatched / totalExp * 100).toStringAsFixed(1) : '100.0';

    // Dữ liệu Sheet 2: Danh mục đối chiếu thiếu và đủ
    final sheet2SkuRows = rows.where((r) => r.expectedQty > 0 || r.matchedCount > 0 || r.missingCount > 0).toList();
    final List<Map<String, String>> sheet2DetailItems = [];
    for (final r in rows) {
      for (final it in r.itemResults) {
        if (it.resultType == InventoryVarianceType.match ||
            it.resultType == InventoryVarianceType.wrongLocation ||
            it.resultType == InventoryVarianceType.missing) {
          final resLabel = it.resultType == InventoryVarianceType.match
              ? 'Khớp đủ'
              : (it.resultType == InventoryVarianceType.wrongLocation ? 'Đủ (Sai vị trí kệ)' : 'THIẾU HỤT (Chưa quét)');
          sheet2DetailItems.add({
            'epc': it.epc,
            'sku': (it.sku != null && it.sku!.isNotEmpty) ? it.sku! : r.sku,
            'name': (it.productName != null && it.productName!.isNotEmpty) ? it.productName! : r.productName,
            'expectedLoc': it.expectedLocation ?? r.zoneOrLocation,
            'actualLoc': it.actualLocation ?? (it.resultType == InventoryVarianceType.missing ? 'Chưa quét thấy' : r.zoneOrLocation),
            'status': resLabel,
            'time': it.readAt.year > 2000 ? _dtFmt.format(it.readAt) : '--',
          });
        }
      }
    }

    // Dữ liệu Sheet 3: Danh mục đối chiếu thừa và danh sách mã EPC thừa
    final sheet3SkuRows = rows.where((r) => r.difference > 0 || r.unknownCount > 0).toList();
    final List<Map<String, String>> surplusEpcList = [];
    for (final r in rows) {
      if (r.difference > 0 || r.unknownCount > 0) {
        // 1. Toàn bộ chip lạ ngoài danh mục
        final unknowns = r.itemResults.where((it) => it.resultType == InventoryVarianceType.unknownEpc).toList();
        for (final u in unknowns) {
          surplusEpcList.add({
            'epc': u.epc,
            'sku': (u.sku != null && u.sku!.isNotEmpty) ? u.sku! : r.sku,
            'name': (u.productName != null && u.productName!.isNotEmpty) ? u.productName! : r.productName,
            'location': u.actualLocation ?? r.zoneOrLocation,
            'time': u.readAt.year > 2000 ? _dtFmt.format(u.readAt) : '--',
            'type': 'Thẻ RFID lạ ngoài danh mục',
            'note': 'Cần kiểm tra nguồn gốc, chưa có trong CSDL kho',
          });
        }
        // 2. Các chip thừa số lượng của SKU đã định danh
        if (r.difference > 0 && r.sku != 'THẺ_LẠ') {
          final scannedForSku = r.itemResults.where((it) =>
            it.resultType == InventoryVarianceType.match ||
            it.resultType == InventoryVarianceType.wrongLocation
          ).toList();
          if (scannedForSku.length > r.expectedQty) {
            final excessItems = scannedForSku.sublist(r.expectedQty);
            for (final ex in excessItems) {
              surplusEpcList.add({
                'epc': ex.epc,
                'sku': r.sku,
                'name': r.productName,
                'location': ex.actualLocation ?? ex.expectedLocation ?? r.zoneOrLocation,
                'time': ex.readAt.year > 2000 ? _dtFmt.format(ex.readAt) : '--',
                'type': 'Thừa số lượng theo SKU',
                'note': 'Mã thẻ hợp lệ nhưng số lượng quét thực tế vượt số dư sổ sách',
              });
            }
          }
        }
      }
    }

    if (format == ReportFormat.csv) {
      final buffer = StringBuffer();
      buffer.writeln('\uFEFFHỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)');
      buffer.writeln('BÁO CÁO ĐỐI SOÁT KIỂM KHO (DỰ KIẾN VS THỰC TẾ)');
      buffer.writeln('Phạm vi: $scopeTitle;Phiếu kiểm kê: ${sessionCode ?? "Toàn bộ kho"};Ngày xuất: ${_dtFmt.format(DateTime.now())}');
      buffer.writeln('Tổng dự kiến: $totalExp;Tổng thực tế: $totalAct;Khớp đủ: $totalMatched;Thiếu hụt: $totalMissing;Thừa/Lạ: $totalSurplus;Độ chính xác: $acc%');
      buffer.writeln();
      buffer.writeln('=== PHẦN 1: BẢNG TỔNG HỢP ĐỐI CHIẾU (THỪA - THIẾU - ĐỦ) ===');
      buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,ĐVT,Vị Trí Lưu Kho,Tồn Sổ Sách,Thực Tế Quét,Khớp Đủ,Thiếu Hụt,Thừa/Lạ,Chênh Lệch,Tỷ Lệ Đạt (%),Trạng Thái');
      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];
        final diffStr = r.difference == 0 ? '0' : (r.difference > 0 ? '+${r.difference}' : '${r.difference}');
        final surplusCount = r.difference > 0 ? r.difference : (r.unknownCount > 0 ? r.unknownCount : 0);
        buffer.writeln('${i + 1},${r.sku},"${r.productName}",${r.unit},"${r.zoneOrLocation}",${r.expectedQty},${r.actualQty},${r.matchedCount},${r.missingCount},$surplusCount,$diffStr,${r.accuracyPercent.toStringAsFixed(1)}%,${r.statusLabel}');
      }
      buffer.writeln();
      buffer.writeln('=== PHẦN 2: BẢNG ĐỐI CHIẾU THIẾU VÀ ĐỦ ===');
      buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,ĐVT,Vị Trí Sổ Sách,Dự Kiến,Khớp Đủ,Thiếu Hụt,Sai Vị Trí,Tỷ Lệ Đủ (%),Kết Luận');
      for (int i = 0; i < sheet2SkuRows.length; i++) {
        final r = sheet2SkuRows[i];
        final conclusion = r.missingCount == 0 ? (r.wrongLocationCount > 0 ? 'Đủ (Sai vị trí kệ)' : 'Khớp đủ 100%') : 'Thiếu ${r.missingCount} SP';
        buffer.writeln('${i + 1},${r.sku},"${r.productName}",${r.unit},"${r.zoneOrLocation}",${r.expectedQty},${r.matchedCount},${r.missingCount},${r.wrongLocationCount},${r.accuracyPercent.toStringAsFixed(1)}%,$conclusion');
      }
      buffer.writeln();
      buffer.writeln('=== PHẦN 3: BẢNG ĐỐI CHIẾU THỪA VÀ LIỆT KÊ MÃ CHIP RFID (EPC) THỪA ===');
      buffer.writeln('STT,Mã Chip RFID (EPC),Mã SKU,Tên Sản Phẩm,Vị Trí Quét Thấy,Thời Điểm Quét,Phân Loại Thừa,Ghi Chú Đề Xuất');
      if (surplusEpcList.isEmpty) {
        buffer.writeln('1,KHONG_CO_EPC_THUA,--,Không phát sinh mã chip RFID thừa,--,--,Khớp đúng,--');
      } else {
        for (int i = 0; i < surplusEpcList.length; i++) {
          final s = surplusEpcList[i];
          buffer.writeln('${i + 1},${s['epc']},${s['sku']},"${s['name']}","${s['location']}","${s['time']}","${s['type']}","${s['note']}"');
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
      // SHEET 1: TỔNG HỢP ĐỐI SOÁT (TỔNG HỢP THỪA - THIẾU - ĐỦ)
      // =======================================================================
      final sheet1 = excel['Tong_Hop_Doi_Soat'];

      _setCell(sheet1, col: 0, row: 0, value: 'HỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
      _setCell(sheet1, col: 0, row: 1, value: 'BẢNG TỔNG HỢP ĐỐI CHIẾU KIỂM KHO (DỰ KIẾN VS THỰC TẾ)', style: _titleStyle);
      _setCell(sheet1, col: 0, row: 2, value: '(Bảng tổng hợp đối chiếu số lượng Khớp đủ - Thiếu hụt - Thừa từ Sheet 2 và Sheet 3)', style: _subTitleStyle);

      _setCell(sheet1, col: 0, row: 4, value: 'Phạm Vi Kiểm Kê:', style: _metaLabelStyle);
      _setCell(sheet1, col: 1, row: 4, value: scopeTitle, style: _metaValueStyle);
      _setCell(sheet1, col: 5, row: 4, value: 'Ngày Xuất Báo Cáo:', style: _metaLabelStyle);
      _setCell(sheet1, col: 6, row: 4, value: _dtFmt.format(DateTime.now()), style: _metaValueStyle);

      _setCell(sheet1, col: 0, row: 5, value: 'Mã Phiếu Kiểm Kê:', style: _metaLabelStyle);
      _setCell(sheet1, col: 1, row: 5, value: sessionCode ?? 'Toàn bộ kho', style: _metaValueStyle);
      _setCell(sheet1, col: 5, row: 5, value: 'Độ Chính Xác Kho:', style: _metaLabelStyle);
      _setCell(sheet1, col: 6, row: 5, value: '$acc%', style: _metaValueStyle);

      _setCell(sheet1, col: 0, row: 7, value: 'Tồn Dự Kiến (Sổ Sách):', style: _metaLabelStyle);
      _setCell(sheet1, col: 1, row: 7, value: '$totalExp SP', style: _metaValueStyle);
      _setCell(sheet1, col: 3, row: 7, value: 'Thực Tế Quét (RFID):', style: _metaLabelStyle);
      _setCell(sheet1, col: 4, row: 7, value: '$totalAct Chip', style: _metaValueStyle);
      _setCell(sheet1, col: 6, row: 7, value: 'Khớp Đủ (Sheet 2):', style: _metaLabelStyle);
      _setCell(sheet1, col: 7, row: 7, value: '$totalMatched SP', style: _metaValueStyle);
      _setCell(sheet1, col: 9, row: 7, value: 'Thiếu Hụt (Sheet 2):', style: _metaLabelStyle);
      _setCell(sheet1, col: 10, row: 7, value: '-$totalMissing SP', style: _metaValueStyle);
      _setCell(sheet1, col: 11, row: 7, value: 'Thừa / Lạ (Sheet 3):', style: _metaLabelStyle);
      _setCell(sheet1, col: 12, row: 7, value: '+$totalSurplus Chip', style: _metaValueStyle);

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
      for (int i = 0; i < rows.length; i++) {
        final r = rows[i];
        final diffStr = r.difference == 0 ? '0' : (r.difference > 0 ? '+${r.difference}' : '${r.difference}');
        final surplusCount = r.difference > 0 ? r.difference : (r.unknownCount > 0 ? r.unknownCount : 0);
        final surplusStr = surplusCount > 0 ? '+$surplusCount' : '0';

        _setCell(sheet1, col: 0, row: r1, value: '${i + 1}', style: _dataCellCenterStyle);
        _setCell(sheet1, col: 1, row: r1, value: r.sku);
        _setCell(sheet1, col: 2, row: r1, value: r.productName);
        _setCell(sheet1, col: 3, row: r1, value: r.unit, style: _dataCellCenterStyle);
        _setCell(sheet1, col: 4, row: r1, value: r.zoneOrLocation);
        _setCell(sheet1, col: 5, row: r1, value: '${r.expectedQty}', style: _dataCellCenterStyle);
        _setCell(sheet1, col: 6, row: r1, value: '${r.actualQty}', style: _dataCellCenterStyle);
        _setCell(sheet1, col: 7, row: r1, value: '${r.matchedCount}', style: _dataCellCenterStyle);
        _setCell(sheet1, col: 8, row: r1, value: r.missingCount > 0 ? '-${r.missingCount}' : '0', style: _dataCellCenterStyle);
        _setCell(sheet1, col: 9, row: r1, value: surplusStr, style: _dataCellCenterStyle);
        _setCell(sheet1, col: 10, row: r1, value: diffStr, style: _dataCellCenterStyle);
        _setCell(sheet1, col: 11, row: r1, value: '${r.accuracyPercent.toStringAsFixed(1)}%', style: _dataCellCenterStyle);
        _setCell(sheet1, col: 12, row: r1, value: r.statusLabel, style: _dataCellCenterStyle);
        r1++;
      }

      // Dòng TỔNG CỘNG Sheet 1
      _setCell(sheet1, col: 0, row: r1, value: 'TỔNG CỘNG', style: _totalRowStyle);
      _setCell(sheet1, col: 1, row: r1, value: '${rows.length} SKU', style: _totalRowStyle);
      _setCell(sheet1, col: 2, row: r1, value: '', style: _totalRowStyle);
      _setCell(sheet1, col: 3, row: r1, value: '', style: _totalRowStyle);
      _setCell(sheet1, col: 4, row: r1, value: '', style: _totalRowStyle);
      _setCell(sheet1, col: 5, row: r1, value: '$totalExp SP', style: _totalRowStyle);
      _setCell(sheet1, col: 6, row: r1, value: '$totalAct Chip', style: _totalRowStyle);
      _setCell(sheet1, col: 7, row: r1, value: '$totalMatched SP', style: _totalRowStyle);
      _setCell(sheet1, col: 8, row: r1, value: '-$totalMissing SP', style: _totalRowStyle);
      _setCell(sheet1, col: 9, row: r1, value: '+$totalSurplus Chip', style: _totalRowStyle);
      final netDiff = totalAct - totalExp;
      _setCell(sheet1, col: 10, row: r1, value: '${netDiff >= 0 ? "+" : ""}$netDiff SP', style: _totalRowStyle);
      _setCell(sheet1, col: 11, row: r1, value: '$acc%', style: _totalRowStyle);
      _setCell(sheet1, col: 12, row: r1, value: totalMissing == 0 && totalSurplus == 0 ? 'Khớp 100%' : 'Chênh lệch', style: _totalRowStyle);

      final signRow1 = r1 + 3;
      _setCell(sheet1, col: 1, row: signRow1, value: 'TRƯỞNG BAN KIỂM KÊ', style: _signTitleStyle);
      _setCell(sheet1, col: 6, row: signRow1, value: 'THỦ KHO', style: _signTitleStyle);
      _setCell(sheet1, col: 10, row: signRow1, value: 'ĐẠI DIỆN KẾ TOÁN', style: _signTitleStyle);

      _setCell(sheet1, col: 1, row: signRow1 + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
      _setCell(sheet1, col: 6, row: signRow1 + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
      _setCell(sheet1, col: 10, row: signRow1 + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);

      _autoFitColumns(sheet1, headers1.length, signRow1 + 3);

      // =======================================================================
      // SHEET 2: ĐỐI CHIẾU THIẾU VÀ ĐỦ
      // =======================================================================
      final sheet2 = excel['Doi_Chieu_Thieu_Va_Du'];

      _setCell(sheet2, col: 0, row: 0, value: 'HỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
      _setCell(sheet2, col: 0, row: 1, value: 'BẢNG ĐỐI CHIẾU THIẾU VÀ ĐỦ (DANH MỤC SỔ SÁCH & THỰC TẾ)', style: _titleStyle);
      _setCell(sheet2, col: 0, row: 2, value: '(Chi tiết đối chiếu số lượng và danh sách mã chip RFID Khớp Đủ và Thiếu Hụt)', style: _subTitleStyle);

      _setCell(sheet2, col: 0, row: 4, value: 'Phạm Vi:', style: _metaLabelStyle);
      _setCell(sheet2, col: 1, row: 4, value: scopeTitle, style: _metaValueStyle);
      _setCell(sheet2, col: 4, row: 4, value: 'Phiếu Kiểm Kê:', style: _metaLabelStyle);
      _setCell(sheet2, col: 5, row: 4, value: sessionCode ?? 'Toàn bộ kho', style: _metaValueStyle);

      _setCell(sheet2, col: 0, row: 5, value: 'Tổng Sổ Sách:', style: _metaLabelStyle);
      _setCell(sheet2, col: 1, row: 5, value: '$totalExp SP', style: _metaValueStyle);
      _setCell(sheet2, col: 3, row: 5, value: 'Khớp Đủ:', style: _metaLabelStyle);
      _setCell(sheet2, col: 4, row: 5, value: '$totalMatched SP', style: _metaValueStyle);
      _setCell(sheet2, col: 6, row: 5, value: 'Thiếu Hụt:', style: _metaLabelStyle);
      _setCell(sheet2, col: 7, row: 5, value: '-$totalMissing SP', style: _metaValueStyle);

      _setCell(sheet2, col: 0, row: 7, value: '1. BẢNG ĐỐI CHIẾU THIẾU VÀ ĐỦ THEO MẶT HÀNG (SKU)', style: _titleStyle);

      final headers2Sku = [
        'STT', 'Mã SKU', 'Tên Sản Phẩm', 'ĐVT', 'Vị Trí Sổ Sách',
        'Tồn Sổ Sách (Dự Kiến)', 'Số Lượng Đủ (Khớp)', 'Số Lượng Thiếu',
        'Sai Vị Trí Kệ', 'Tỷ Lệ Đủ (%)', 'Kết Luận Đối Chiếu',
      ];
      const startRow2Sku = 8;
      for (int c = 0; c < headers2Sku.length; c++) {
        _setCell(sheet2, col: c, row: startRow2Sku, value: headers2Sku[c], style: _tableHeaderStyle('#059669'));
      }

      int r2 = startRow2Sku + 1;
      for (int i = 0; i < sheet2SkuRows.length; i++) {
        final r = sheet2SkuRows[i];
        final conclusion = r.missingCount == 0
            ? (r.wrongLocationCount > 0 ? 'Đủ (Sai vị trí kệ)' : 'Khớp đủ 100%')
            : 'Thiếu ${r.missingCount} SP';

        _setCell(sheet2, col: 0, row: r2, value: '${i + 1}', style: _dataCellCenterStyle);
        _setCell(sheet2, col: 1, row: r2, value: r.sku);
        _setCell(sheet2, col: 2, row: r2, value: r.productName);
        _setCell(sheet2, col: 3, row: r2, value: r.unit, style: _dataCellCenterStyle);
        _setCell(sheet2, col: 4, row: r2, value: r.zoneOrLocation);
        _setCell(sheet2, col: 5, row: r2, value: '${r.expectedQty}', style: _dataCellCenterStyle);
        _setCell(sheet2, col: 6, row: r2, value: '${r.matchedCount}', style: _dataCellCenterStyle);
        _setCell(sheet2, col: 7, row: r2, value: r.missingCount > 0 ? '-${r.missingCount}' : '0', style: _dataCellCenterStyle);
        _setCell(sheet2, col: 8, row: r2, value: '${r.wrongLocationCount}', style: _dataCellCenterStyle);
        _setCell(sheet2, col: 9, row: r2, value: '${r.accuracyPercent.toStringAsFixed(1)}%', style: _dataCellCenterStyle);
        _setCell(sheet2, col: 10, row: r2, value: conclusion, style: _dataCellCenterStyle);
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
      _setCell(sheet2, col: 7, row: r2, value: '-$totalMissing SP', style: _totalRowStyle);
      _setCell(sheet2, col: 8, row: r2, value: '$totalWrongLoc SP', style: _totalRowStyle);
      _setCell(sheet2, col: 9, row: r2, value: '$acc%', style: _totalRowStyle);
      _setCell(sheet2, col: 10, row: r2, value: totalMissing == 0 ? 'Đủ 100%' : 'Thiếu $totalMissing SP', style: _totalRowStyle);
      r2 += 3;

      // Phần 2 Sheet 2: Danh sách chi tiết mã chip RFID (EPC) đối chiếu Thiếu và Đủ
      _setCell(sheet2, col: 0, row: r2, value: '2. DANH SÁCH CHI TIẾT MÃ CHIP RFID (EPC) ĐỐI CHIẾU THIẾU VÀ ĐỦ', style: _titleStyle);
      r2++;

      final headers2Epc = [
        'STT', 'Mã Chip RFID (EPC)', 'Mã SKU', 'Tên Sản Phẩm',
        'Vị Trí Sổ Sách (Dự Kiến)', 'Vị Trí Quét Thấy (Thực Tế)',
        'Trạng Thái Đối Chiếu', 'Thời Điểm Quét / Ghi Nhận',
      ];
      for (int c = 0; c < headers2Epc.length; c++) {
        _setCell(sheet2, col: c, row: r2, value: headers2Epc[c], style: _tableHeaderStyle('#334155'));
      }
      r2++;

      if (sheet2DetailItems.isEmpty) {
        _setCell(sheet2, col: 0, row: r2, value: 'Không có dữ liệu thẻ RFID chi tiết cho danh mục này.', style: _signNoteStyle);
        r2++;
      } else {
        for (int i = 0; i < sheet2DetailItems.length; i++) {
          final it = sheet2DetailItems[i];
          _setCell(sheet2, col: 0, row: r2, value: '${i + 1}', style: _dataCellCenterStyle);
          _setCell(sheet2, col: 1, row: r2, value: it['epc'] ?? '--');
          _setCell(sheet2, col: 2, row: r2, value: it['sku'] ?? '--');
          _setCell(sheet2, col: 3, row: r2, value: it['name'] ?? '--');
          _setCell(sheet2, col: 4, row: r2, value: it['expectedLoc'] ?? '--');
          _setCell(sheet2, col: 5, row: r2, value: it['actualLoc'] ?? '--');
          _setCell(sheet2, col: 6, row: r2, value: it['status'] ?? '--', style: _dataCellCenterStyle);
          _setCell(sheet2, col: 7, row: r2, value: it['time'] ?? '--', style: _dataCellCenterStyle);
          r2++;
        }
      }

      _autoFitColumns(sheet2, headers2Sku.length, r2 + 2);

      // =======================================================================
      // SHEET 3: ĐỐI CHIẾU THỪA VÀ LIỆT KÊ MÃ CHIP RFID (EPC) THỪA
      // =======================================================================
      final sheet3 = excel['Doi_Chieu_Thua_EPC'];

      _setCell(sheet3, col: 0, row: 0, value: 'HỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
      _setCell(sheet3, col: 0, row: 1, value: 'BẢNG ĐỐI CHIẾU THỪA & LIỆT KÊ MÃ CHIP RFID (EPC) THỪA', style: _titleStyle);
      _setCell(sheet3, col: 0, row: 2, value: '(Liệt kê chi tiết toàn bộ các mặt hàng phát sinh thừa và mã chip RFID thừa / lạ ngoài sổ sách)', style: _subTitleStyle);

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

      _setCell(sheet3, col: 0, row: 7, value: '1. BẢNG TỔNG HỢP CÁC MẶT HÀNG PHÁT SINH THỪA (SKU)', style: _titleStyle);

      final headers3Sku = [
        'STT', 'Mã SKU', 'Tên Sản Phẩm / Phân Loại', 'ĐVT', 'Vị Trí Quét Thấy',
        'Tồn Sổ Sách', 'Thực Tế Quét', 'Số Lượng Thừa (+)', 'Phân Loại Thừa', 'Đề Xuất Xử Lý',
      ];
      const startRow3Sku = 8;
      for (int c = 0; c < headers3Sku.length; c++) {
        _setCell(sheet3, col: c, row: startRow3Sku, value: headers3Sku[c], style: _tableHeaderStyle('#D97706'));
      }

      int r3 = startRow3Sku + 1;
      if (sheet3SkuRows.isEmpty) {
        _setCell(sheet3, col: 0, row: r3, value: '✓ Không có mặt hàng nào phát sinh thừa trong đợt kiểm kê này.', style: _signNoteStyle);
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
          _setCell(sheet3, col: 8, row: r3, value: typeDesc);
          _setCell(sheet3, col: 9, row: r3, value: actionDesc);
          r3++;
        }
      }

      r3 += 2;
      // Phần 2 Sheet 3: Danh sách liệt kê tường minh các mã chip RFID (EPC) thừa
      _setCell(sheet3, col: 0, row: r3, value: '2. BẢNG LIỆT KÊ TƯỜNG MINH CÁC MÃ CHIP RFID (EPC) THỪA', style: _titleStyle);
      r3++;

      final headers3Epc = [
        'STT', 'Mã Chip RFID (EPC)', 'Mã SKU Nhận Diện', 'Tên Sản Phẩm',
        'Vị Trí Quét Thấy (Thực Tế)', 'Thời Điểm Quét', 'Phân Loại Thừa',
        'Ghi Chú Đề Xuất Xử Lý',
      ];
      for (int c = 0; c < headers3Epc.length; c++) {
        _setCell(sheet3, col: c, row: r3, value: headers3Epc[c], style: _tableHeaderStyle('#DC2626'));
      }
      r3++;

      if (surplusEpcList.isEmpty) {
        _setCell(sheet3, col: 0, row: r3, value: '✓ Không phát hiện mã chip RFID (EPC) thừa nào trong đợt kiểm kê này. Toàn bộ chip quét thấy đều nằm trong danh mục sổ sách dự kiến.', style: _signNoteStyle);
        r3++;
      } else {
        for (int i = 0; i < surplusEpcList.length; i++) {
          final s = surplusEpcList[i];
          _setCell(sheet3, col: 0, row: r3, value: '${i + 1}', style: _dataCellCenterStyle);
          _setCell(sheet3, col: 1, row: r3, value: s['epc'] ?? '--', style: _dataCellCenterStyle);
          _setCell(sheet3, col: 2, row: r3, value: s['sku'] ?? '--');
          _setCell(sheet3, col: 3, row: r3, value: s['name'] ?? '--');
          _setCell(sheet3, col: 4, row: r3, value: s['location'] ?? '--');
          _setCell(sheet3, col: 5, row: r3, value: s['time'] ?? '--', style: _dataCellCenterStyle);
          _setCell(sheet3, col: 6, row: r3, value: s['type'] ?? '--');
          _setCell(sheet3, col: 7, row: r3, value: s['note'] ?? '--');
          r3++;
        }
      }

      _autoFitColumns(sheet3, headers3Sku.length, r3 + 2);

      // Xóa sheet mặc định 'Sheet1' của thư viện excel nếu có
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      return _saveProtectedExcelFile(excel, filePath);
    }
  }

  // =========================================================================
  // 4. FORM MẪU: BÁO CÁO TỒN KHO CHI TIẾT THEO SỐ SERI (SN), VỊ TRÍ & RFID
  // =========================================================================
  /// Xuất Báo Cáo Tồn Kho trực tiếp (hỗ trợ danh sách hàng lọc theo Số Seri - SN hoặc theo giai đoạn)
  Future<File> exportInventoryReport(
    ReportFormat format, {
    List<Item>? items,
    DateTime? fromDate,
    DateTime? toDate,
  }) async {
    return _exportInventoryForm(format, customItems: items, fromDate: fromDate, toDate: toDate);
  }

  Future<File> _exportInventoryForm(
    ReportFormat format, {
    List<String>? selectedEpcs,
    List<Item>? customItems,
    DateTime? fromDate,
    DateTime? toDate,
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

    final dir = await _getReportDir();
    final timestamp = _fileFmt.format(DateTime.now());
    final fileName = '${ReportType.inventory.filePrefix}_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    final headers = [
      'STT', 'Số Seri (SN)', 'Mã SKU', 'Tên Sản Phẩm', 'Mã Chip RFID (EPC)',
      'Vị Trí Kệ', 'Mã Pallet', 'Nhà Cung Cấp', 'Ngày Nhập Kho', 'Trạng Thái',
      'Vòng Đời Thẻ',
    ];

    final rows = <List<String>>[];
    for (int i = 0; i < inStockItems.length; i++) {
      final it = inStockItems[i];
      String palletDisplay = '--';
      if (it.palletId != null && it.palletId!.isNotEmpty) {
        final pallet = _repo.pallets.where((p) => p.palletId == it.palletId || p.palletCode == it.palletId).toList();
        palletDisplay = pallet.isNotEmpty ? pallet.first.displayName : it.palletId!;
      }

      final lifecycleSummary = _repo.getTagLifecycleSummary(it.epc, multiline: true);

      rows.add([
        '${i + 1}',
        it.serialNumber.isNotEmpty ? it.serialNumber : '--',
        it.sku,
        it.productName,
        it.epc,
        it.locationId ?? '--',
        palletDisplay,
        _repo.getItemSupplier(it),
        it.inboundTime != null ? _dtFmt.format(it.inboundTime!) : '--',
        it.status.label,
        lifecycleSummary,
      ]);
    }

    if (format == ReportFormat.csv) {
      final buffer = StringBuffer();
      buffer.writeln('\uFEFFHỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)');
      buffer.writeln('BÁO CÁO TỒN KHO THEO SỐ SERI (SN) VÀ THẺ RFID');
      buffer.writeln('Thời điểm xuất: ${_dtFmt.format(DateTime.now())};Tổng số sản phẩm tồn: ${inStockItems.length}');
      buffer.writeln();
      buffer.writeln(headers.join(','));
      for (final r in rows) {
        buffer.writeln(r.map((c) => '"$c"').join(','));
      }
      buffer.writeln();
      buffer.writeln('TỔNG CỘNG,,,"Tổng sản phẩm tồn: ${inStockItems.length}",,,,,,,');
      buffer.writeln();
      buffer.writeln('NGƯỜI LẬP BÁO CÁO,THỦ KHO,KẾ TOÁN KHO');
      buffer.writeln('(Ký ghi rõ họ tên),(Ký ghi rõ họ tên),(Ký ghi rõ họ tên)');

      final file = File(filePath);
      await file.writeAsString(buffer.toString());
      return file;
    } else {
      final excel = Excel.createExcel();
      final sheet = excel['Ton_Kho_RFID'];
      if (excel.sheets.containsKey('Sheet1')) {
        excel.delete('Sheet1');
      }

      _setCell(sheet, col: 0, row: 0, value: 'HỆ THỐNG KHO VẬN THÔNG MINH RFID (RFID WMS)', style: _companyHeaderStyle);
      _setCell(sheet, col: 0, row: 1, value: 'BÁO CÁO TỒN KHO THEO SỐ SERI (SN) & RFID', style: _titleStyle);
      _setCell(sheet, col: 0, row: 2, value: 'Thời điểm xuất: ${_dtFmt.format(DateTime.now())}   |   Tổng sản phẩm tồn: ${inStockItems.length}', style: _subTitleStyle);

      const startRow = 4;
      for (int c = 0; c < headers.length; c++) {
        _setCell(sheet, col: c, row: startRow, value: headers[c], style: _tableHeaderStyle('#047857'));
      }

      int r = startRow + 1;
      for (final rowData in rows) {
        double maxLinesInRow = 1;
        for (int c = 0; c < rowData.length; c++) {
          final text = rowData[c];
          CellStyle? s;
          if (c == 0 || c == 1 || c == 2 || c == 5 || c == 8 || c == 9) {
            s = _dataCellCenterStyle;
          } else if (c == 10) {
            // Cột Vòng Đời Thẻ: tự động căn chỉnh xuống dòng
            s = _dataCellWrapStyle;
          }
          _setCell(sheet, col: c, row: r, value: text, style: s);

          // Tính toán số dòng để tự động chỉnh độ cao hàng Excel
          if (c == 10 && text.isNotEmpty) {
            final lines = text.split(RegExp(r'\r?\n'));
            double linesCount = 0;
            for (final line in lines) {
              final wrapFactor = (line.length / 55).ceil();
              linesCount += wrapFactor > 0 ? wrapFactor : 1;
            }
            if (linesCount > maxLinesInRow) {
              maxLinesInRow = linesCount;
            }
          }
        }

        // Tự động căn chỉnh độ cao dòng (Row Height) dựa trên số dòng hiển thị
        if (maxLinesInRow > 1) {
          final rowHeight = (20.0 + (maxLinesInRow - 1) * 16.0).clamp(24.0, 220.0);
          sheet.setRowHeight(r, rowHeight);
        } else {
          sheet.setRowHeight(r, 22.0);
        }
        r++;
      }

      _setCell(sheet, col: 0, row: r, value: 'TỔNG CỘNG', style: _totalRowStyle);
      _setCell(sheet, col: 1, row: r, value: '${inStockItems.length} Sản phẩm', style: _totalRowStyle);
      for (int c = 2; c < headers.length; c++) {
        _setCell(sheet, col: c, row: r, value: '', style: _totalRowStyle);
      }

      final signRow = r + 3;
      _setCell(sheet, col: 1, row: signRow, value: 'NGƯỜI LẬP BÁO CÁO', style: _signTitleStyle);
      _setCell(sheet, col: 4, row: signRow, value: 'THỦ KHO', style: _signTitleStyle);
      _setCell(sheet, col: 7, row: signRow, value: 'KẾ TOÁN KHO', style: _signTitleStyle);

      _setCell(sheet, col: 1, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
      _setCell(sheet, col: 4, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);
      _setCell(sheet, col: 7, row: signRow + 1, value: '(Ký, ghi rõ họ tên)', style: _signNoteStyle);

      _autoFitColumns(sheet, headers.length, signRow + 3);

      return _saveProtectedExcelFile(excel, filePath);
    }
  }

  // =========================================================================
  // 4b. FORM MẪU: BÁO CÁO TỔNG HỢP TỒN KHO THEO MẶT HÀNG (SKU SUMMARY)
  // =========================================================================
  Future<File> exportInventorySkuSummary(ReportFormat format, {List<String>? selectedSkus}) async {
    final inStockItems = _repo.items.where((i) => i.status.code == 'IN_STOCK').toList();

    // Gom nhóm theo SKU
    final Map<String, List<Item>> skuMap = {};
    for (final it in inStockItems) {
      skuMap.putIfAbsent(it.sku, () => []).add(it);
    }

    var skus = skuMap.keys.toList()..sort();
    if (selectedSkus != null && selectedSkus.isNotEmpty) {
      skus = skus.where((s) => selectedSkus.contains(s)).toList();
    }

    final dir = await _getReportDir();
    final timestamp = _fileFmt.format(DateTime.now());
    final fileName = 'bao_cao_ton_kho_tong_hop_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    final headers = [
      'STT', 'Mã SKU', 'Tên Sản Phẩm', 'Nhà Cung Cấp',
      'Số Lượng Tồn', 'Vị Trí Kệ Lưu Trữ', 'Mã Pallet',
    ];

    final rows = <List<String>>[];
    int totalQty = 0;
    for (int i = 0; i < skus.length; i++) {
      final sku = skus[i];
      final items = skuMap[sku] ?? [];
      totalQty += items.length;
      final productName = items.isNotEmpty ? items.first.productName : sku;
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
        sku,
        productName,
        supplier,
        '${items.length}',
        locations.isNotEmpty ? locations : '--',
        pallets.isNotEmpty ? pallets : '--',
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
      buffer.writeln('TỔNG CỘNG,,,"Tổng số SKU: ${skus.length}","Tổng tồn: $totalQty",,');
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
          _setCell(sheet, col: c, row: r, value: rowData[c], style: (c == 0 || c == 4) ? _dataCellCenterStyle : null);
        }
        r++;
      }

      _setCell(sheet, col: 0, row: r, value: 'TỔNG CỘNG', style: _totalRowStyle);
      _setCell(sheet, col: 1, row: r, value: '${skus.length} SKU', style: _totalRowStyle);
      _setCell(sheet, col: 2, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 3, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 4, row: r, value: '$totalQty Sản phẩm', style: _totalRowStyle);
      _setCell(sheet, col: 5, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 6, row: r, value: '', style: _totalRowStyle);

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

    final dir = await _getReportDir();
    final timestamp = _fileFmt.format(DateTime.now());
    final fileName = '${ReportType.transactionLog.filePrefix}_$timestamp.${format.name}';
    final filePath = '${dir.path}${Platform.pathSeparator}$fileName';

    final headers = [
      'STT', 'Thời Gian', 'Mã Chứng Từ', 'Nghiệp Vụ', 'Mã SKU',
      'Tên Sản Phẩm', 'Số Lượng', 'Từ Vị Trí', 'Đến Vị Trí', 'Mã Pallet', 'Người Thực Hiện',
    ];

    final rows = <List<String>>[];
    for (int i = 0; i < txs.length; i++) {
      final t = txs[i];
      rows.add([
        '${i + 1}',
        _dtFmt.format(t.timestamp),
        t.documentNo,
        t.type.label,
        t.sku,
        t.productName,
        t.quantity.toString(),
        t.fromLocation ?? '--',
        t.toLocation ?? '--',
        t.palletCode ?? '--',
        t.performedBy,
      ]);
    }

    if (format == ReportFormat.csv) {
      final buffer = StringBuffer();
      buffer.writeln('\uFEFFHỆ THỐNG QUẢN LÝ KHO THÔNG MINH RFID (RFID WMS)');
      buffer.writeln('SỔ NHẬT KÝ BIẾN ĐỘNG VÀ ĐIỀU CHUYỂN KHO');
      buffer.writeln('Thời điểm xuất: ${_dtFmt.format(DateTime.now())};Tổng số giao dịch: ${txs.length}');
      buffer.writeln();
      buffer.writeln(headers.join(','));
      for (final r in rows) {
        buffer.writeln(r.map((c) => '"$c"').join(','));
      }
      buffer.writeln();
      final totalQty = txs.fold<int>(0, (s, t) => s + t.quantity);
      buffer.writeln('TỔNG CỘNG,,,,,,"Tổng SL: $totalQty",,,,');
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
      _setCell(sheet, col: 0, row: 1, value: 'SỔ NHẬT KÝ BIẾN ĐỘNG & ĐIỀU CHUYỂN KHO', style: _titleStyle);
      _setCell(sheet, col: 0, row: 2, value: 'Thời điểm xuất: ${_dtFmt.format(DateTime.now())}   |   Tổng giao dịch: ${txs.length}', style: _subTitleStyle);

      const startRow = 4;
      for (int c = 0; c < headers.length; c++) {
        _setCell(sheet, col: c, row: startRow, value: headers[c], style: _tableHeaderStyle('#F59E0B'));
      }

      int r = startRow + 1;
      int totalQty = 0;
      for (final rowData in rows) {
        totalQty += int.tryParse(rowData[6]) ?? 0;
        for (int c = 0; c < rowData.length; c++) {
          _setCell(sheet, col: c, row: r, value: rowData[c], style: (c == 0 || c == 1 || c == 3 || c == 6 || c == 7 || c == 8 || c == 9) ? _dataCellCenterStyle : null);
        }
        r++;
      }

      _setCell(sheet, col: 0, row: r, value: 'TỔNG CỘNG', style: _totalRowStyle);
      _setCell(sheet, col: 1, row: r, value: '${txs.length} Giao dịch', style: _totalRowStyle);
      _setCell(sheet, col: 2, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 3, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 4, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 5, row: r, value: '', style: _totalRowStyle);
      _setCell(sheet, col: 6, row: r, value: '$totalQty SP', style: _totalRowStyle);
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

  CellStyle get _dataCellWrapStyle => CellStyle(
        fontSize: 9,
        fontColorHex: ExcelColor.fromHexString('#0F172A'),
        verticalAlign: VerticalAlign.Center,
        textWrapping: TextWrapping.WrapText,
      );

  CellStyle get _totalRowStyle => CellStyle(
        bold: true,
        fontSize: 10,
        fontColorHex: ExcelColor.fromHexString('#0F172A'),
        backgroundColorHex: ExcelColor.fromHexString('#F1F5F9'),
        verticalAlign: VerticalAlign.Center,
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
  // BẢO VỆ TẬP TIN EXCEL CHỐNG CHỈNH SỬA (EXCEL ANTI-TAMPER & SHEET PROTECTION)
  // =========================================================================

  /// Lưu file Excel có áp dụng cơ chế khóa bảo vệ chống chỉnh sửa (Read-Only / Sheet Protection)
  Future<File> _saveProtectedExcelFile(Excel excel, String filePath) async {
    final rawBytes = excel.encode();
    if (rawBytes == null) throw Exception('Không thể tạo file Excel.');

    final protectedBytes = _protectExcelBytes(rawBytes);
    final file = File(filePath);
    await file.writeAsBytes(protectedBytes);
    return file;
  }

  /// Áp dụng bảo vệ chống chỉnh sửa cho file Excel chuẩn OpenXML (ECMA-376)
  /// - Khóa toàn bộ các sheet: không cho sửa ô, không chèn/xóa dòng/cột, không đổi định dạng
  /// - Khóa cấu trúc workbook: không thêm/xóa/đổi tên/ẩn sheet
  /// - Bật cờ readOnlyRecommended để Excel tự động khuyến nghị mở chế độ Chỉ Đọc
  /// - Mật khẩu mở khóa (nếu cần quản trị unprotect): WMS2026 (hash: DFEE)
  List<int> _protectExcelBytes(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final newArchive = Archive();

      for (final file in archive) {
        if (!file.isFile) continue;

        if (file.name.startsWith('xl/worksheets/sheet') && file.name.endsWith('.xml')) {
          var content = utf8.decode(file.content as List<int>);
          if (!content.contains('<sheetProtection')) {
            // Theo chuẩn OpenXML ECMA-376 Part 4:
            // sheetProtection phải nằm ngay sau sheetData (và sheetCalcPr)
            // trước mergeCells, dataValidations, pageMargins...
            const protectionXml = '<sheetProtection sheet="true" objects="true" scenarios="true" '
                'password="DFEE" selectLockedCells="true" selectUnlockedCells="true" '
                'formatCells="false" formatColumns="false" formatRows="false" '
                'insertColumns="false" insertRows="false" insertHyperlinks="false" '
                'deleteColumns="false" deleteRows="false" sort="false" autoFilter="false" pivotTables="false"/>';
            if (content.contains('</sheetData>')) {
              content = content.replaceFirst('</sheetData>', '</sheetData>$protectionXml');
            } else if (content.contains('<sheetData/>')) {
              content = content.replaceFirst('<sheetData/>', '<sheetData/>$protectionXml');
            } else if (content.contains('</worksheet>')) {
              content = content.replaceFirst('</worksheet>', '$protectionXml</worksheet>');
            }
          }
          final newBytes = utf8.encode(content);
          newArchive.addFile(ArchiveFile(file.name, newBytes.length, newBytes));
        } else if (file.name == 'xl/workbook.xml') {
          var content = utf8.decode(file.content as List<int>);
          // Thêm fileSharing (khuyến nghị chỉ đọc)
          if (!content.contains('<fileSharing')) {
            const fileSharingXml = '<fileSharing readOnlyRecommended="1"/>';
            if (content.contains('<workbookPr')) {
              content = content.replaceFirst('<workbookPr', '$fileSharingXml<workbookPr');
            } else if (content.contains('</workbook>')) {
              content = content.replaceFirst('</workbook>', '$fileSharingXml</workbook>');
            }
          }
          // Thêm workbookProtection (khóa cấu trúc bảng tính)
          if (!content.contains('<workbookProtection')) {
            const wbProtectionXml = '<workbookProtection lockStructure="true" lockWindows="true" workbookPassword="DFEE"/>';
            if (content.contains('<workbookPr/>')) {
              content = content.replaceFirst('<workbookPr/>', '<workbookPr/>$wbProtectionXml');
            } else if (content.contains('</workbookPr>')) {
              content = content.replaceFirst('</workbookPr>', '</workbookPr>$wbProtectionXml');
            } else if (content.contains('<sheets>')) {
              content = content.replaceFirst('<sheets>', '$wbProtectionXml<sheets>');
            } else if (content.contains('</workbook>')) {
              content = content.replaceFirst('</workbook>', '$wbProtectionXml</workbook>');
            }
          }
          final newBytes = utf8.encode(content);
          newArchive.addFile(ArchiveFile(file.name, newBytes.length, newBytes));
        } else {
          newArchive.addFile(file);
        }
      }

      return ZipEncoder().encode(newArchive) ?? bytes;
    } catch (_) {
      // Fallback an toàn nếu có lỗi
      return bytes;
    }
  }
}
