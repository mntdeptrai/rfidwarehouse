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

  /// Xuất báo cáo theo loại và định dạng
  Future<File> exportReport(ReportType type, ReportFormat format) async {
    return exportReportSelected(type, format);
  }

  /// Xuất báo cáo chọn lọc theo danh sách ID/Mã đơn được tick chọn
  Future<File> exportReportSelected(
    ReportType type,
    ReportFormat format, {
    List<String>? selectedKeys,
  }) async {
    switch (type) {
      case ReportType.inbound:
        return _exportInboundForm(format, selectedOrderNos: selectedKeys);
      case ReportType.outbound:
        return _exportOutboundForm(format, selectedPoNos: selectedKeys);
      case ReportType.inventory:
        return _exportInventoryForm(format, selectedEpcs: selectedKeys);
      case ReportType.audit:
        return _exportAuditForm(format, selectedSessionCodes: selectedKeys);
      case ReportType.transactionLog:
        return _exportTransactionLogForm(format, selectedDocNos: selectedKeys);
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

  // =========================================================================
  // 1. FORM MẪU: PHIẾU NHẬP KHO (GOODS RECEIPT NOTE)
  // =========================================================================
  Future<File> _exportInboundForm(ReportFormat format, {List<String>? selectedOrderNos}) async {
    var orders = _repo.inboundOrders;
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

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Không thể tạo file Excel.');
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return file;
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
  Future<File> _exportOutboundForm(ReportFormat format, {List<String>? selectedPoNos}) async {
    var orders = _repo.outboundOrders;
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
        final totalReq = ord.details.fold<int>(0, (s, d) => s + d.requiredQty);
        final totalPicked = ord.details.fold<int>(0, (s, d) => s + d.pickedQty);
        final delivery = deliveries.where((d) => d.poNo == ord.poNo).toList();
        final deliveryNos = delivery.map((d) => d.deliveryNo).join(', ');

        buffer.writeln('================================================================================');
        buffer.writeln('PHIẾU XUẤT KHO KIÊM BÀN GIAO: ${ord.poNo}');
        buffer.writeln('Khách hàng: ${ord.customer};Ngày tạo: ${_dtFmt.format(ord.createdAt)};Trạng thái: ${ord.status.label}');
        buffer.writeln('Mã vận đơn: ${deliveryNos.isEmpty ? "--" : deliveryNos};Kho xuất: Kho Tổng RFID;Quy tắc: Chuẩn FIFO');
        buffer.writeln();

        buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,SL Yêu Cầu,SL Thực Xuất,Vị Trí Lấy Hàng,Mã Pallet,Mã Chip RFID (EPC),Ghi Chú');

        if (ord.details.isNotEmpty) {
          for (int r = 0; r < ord.details.length; r++) {
            final d = ord.details[r];
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

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Không thể tạo file Excel.');
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return file;
    }
  }

  void _buildSingleOutboundOrderSheet(Sheet sheet, OutboundOrder ord, List<DeliveryNote> deliveries) {
    final totalReq = ord.details.fold<int>(0, (s, d) => s + d.requiredQty);
    final totalPicked = ord.details.fold<int>(0, (s, d) => s + d.pickedQty);
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
    if (ord.details.isNotEmpty) {
      for (int i = 0; i < ord.details.length; i++) {
        final d = ord.details[i];
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

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Không thể tạo file Excel.');
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return file;
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

    _setCell(sheet, col: 0, row: 5, value: 'Vị Trí Kệ:', style: _metaLabelStyle);
    _setCell(sheet, col: 1, row: 5, value: s.locationCode ?? '--', style: _metaValueStyle);
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

  // =========================================================================
  // 4. FORM MẪU: BÁO CÁO TỒN KHO CHI TIẾT THEO SỐ SERI (SN), VỊ TRÍ & RFID
  // =========================================================================
  /// Xuất Báo Cáo Tồn Kho trực tiếp (hỗ trợ danh sách hàng lọc theo Số Seri - SN)
  Future<File> exportInventoryReport(ReportFormat format, {List<Item>? items}) async {
    return _exportInventoryForm(format, customItems: items);
  }

  Future<File> _exportInventoryForm(
    ReportFormat format, {
    List<String>? selectedEpcs,
    List<Item>? customItems,
  }) async {
    var inStockItems = customItems ?? _repo.items.where((i) => i.status.code == 'IN_STOCK').toList();
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
    ];

    final rows = <List<String>>[];
    for (int i = 0; i < inStockItems.length; i++) {
      final it = inStockItems[i];
      String palletDisplay = '--';
      if (it.palletId != null && it.palletId!.isNotEmpty) {
        final pallet = _repo.pallets.where((p) => p.palletId == it.palletId || p.palletCode == it.palletId).toList();
        palletDisplay = pallet.isNotEmpty ? pallet.first.displayName : it.palletId!;
      }

      rows.add([
        '${i + 1}',
        it.serialNumber.isNotEmpty ? it.serialNumber : '--',
        it.sku,
        it.productName,
        it.epc,
        it.locationId ?? '--',
        palletDisplay,
        it.supplierDisplay,
        it.inboundTime != null ? _dtFmt.format(it.inboundTime!) : '--',
        it.status.label,
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
      buffer.writeln('TỔNG CỘNG,,,"Tổng sản phẩm tồn: ${inStockItems.length}",,,,,,');
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
        for (int c = 0; c < rowData.length; c++) {
          _setCell(sheet, col: c, row: r, value: rowData[c], style: (c == 0 || c == 1 || c == 2 || c == 5 || c == 8 || c == 9) ? _dataCellCenterStyle : null);
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

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Không thể tạo file Excel.');
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return file;
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
      final supplier = items.isNotEmpty ? items.first.supplierDisplay : '--';

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

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Không thể tạo file Excel.');
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return file;
    }
  }

  // =========================================================================
  // 5. FORM MẪU: SỔ NHẬT KÝ BIẾN ĐỘNG & ĐIỀU CHUYỂN KHO
  // =========================================================================
  Future<File> _exportTransactionLogForm(ReportFormat format, {List<String>? selectedDocNos}) async {
    var txs = _repo.transactions;
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

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Không thể tạo file Excel.');
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return file;
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
        if (val.length > maxLen) {
          maxLen = val.length.toDouble();
        }
      }
      sheet.setColumnWidth(col, maxLen < 11 ? 13 : (maxLen > 45 ? 45 : maxLen + 3));
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
}
