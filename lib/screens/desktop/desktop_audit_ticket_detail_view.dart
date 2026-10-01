import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/wms_models.dart';
import '../../services/report_export_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';

/// Màn hình Xem Chi Tiết Phiếu Kiểm Kê Kho (Agency-grade Industrial Design)
/// Hiển thị đầy đủ thông tin phiếu, Scorecard đối chiếu, Bảng SKU dự kiến vs thực tế,
/// và Chi tiết từng mã chip RFID EPC kèm trích xuất Biên bản kiểm kê chuẩn (.xlsx / In ấn).
class DesktopAuditTicketDetailView extends StatefulWidget {
  final InventorySession session;
  final VoidCallback onBack;
  final VoidCallback? onContinueScanning;
  final bool isDialogMode;

  const DesktopAuditTicketDetailView({
    super.key,
    required this.session,
    required this.onBack,
    this.onContinueScanning,
    this.isDialogMode = false,
  });

  @override
  State<DesktopAuditTicketDetailView> createState() => _DesktopAuditTicketDetailViewState();
}

class _DesktopAuditTicketDetailViewState extends State<DesktopAuditTicketDetailView>
    with SingleTickerProviderStateMixin {
  final WarehouseRepository _repo = WarehouseRepository();
  final ReportExportService _exportService = ReportExportService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  late TabController _tabController;
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Bộ lọc Tab 1 (SKU): ALL, DISCREPANCY, MATCH
  String _skuFilter = 'ALL';

  // Bộ lọc Tab 2 (RFID): ALL, MATCH, MISSING, WRONG_LOC, UNKNOWN
  String _rfidFilter = 'ALL';

  // SKU được chọn để lọc nhanh ở Tab 2
  String? _selectedFilterSku;

  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _formatDateTime(DateTime? dt) {
    if (dt == null) return '--';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  Future<void> _exportAuditExcel() async {
    setState(() => _isExporting = true);
    try {
      final file = await _exportService.exportReportSelected(
        ReportType.audit,
        ReportFormat.xlsx,
        selectedKeys: [widget.session.sessionCode],
      );

      if (!mounted) return;
      setState(() => _isExporting = false);

      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '✓ Đã xuất Biên bản kiểm kê ${widget.session.sessionCode} thành công!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              TextButton(
                onPressed: () {
                  if (Platform.isWindows) {
                    Process.run('explorer.exe', ['/select,', file.path]);
                  }
                },
                child: const Text('MỞ THƯ MỤC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text('Lỗi xuất biên bản kiểm kê: $e'),
        ),
      );
    }
  }

  void _showPrintPreviewDialog(EyeCareColors c) {
    final s = widget.session;
    final skuBreakdowns = _repo.buildSessionSkuBreakdown(s);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
        title: Row(
          children: [
            Icon(Icons.print_rounded, color: c.rfidCyan, size: 22),
            const SizedBox(width: 10),
            Text('Xem Trước Biên Bản Kiểm Kê', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: SizedBox(
          width: 720,
          height: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      Text('HỆ THỐNG KHO THÔNG MINH RFID (RFID WMS)', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text('BIÊN BẢN KIỂM KÊ KHO HÀNG HÓA', style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
                      Text('Số: ${s.sessionCode} • Ngày kiểm: ${_formatDateTime(s.startedAt)}', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: c.bgCardElevated, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    children: [
                      Expanded(child: Text('Phạm vi: ${s.isSkuSpecific ? "Theo mặt hàng: ${s.targetSkus.join(', ')}" : (s.locationCode != null ? "${s.locationCode} (${s.zone})" : s.zone)}', style: TextStyle(color: c.textPrimary, fontSize: 12))),
                      Expanded(child: Text('Trạng thái: ${s.isCompleted ? "ĐÃ HOÀN TẤT" : "ĐANG KIỂM KÊ"}', style: TextStyle(color: c.textPrimary, fontSize: 12))),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Text('TỔNG HỢP THEO MẶT HÀNG / SKU (${skuBreakdowns.length} mặt hàng)', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 8),
                Table(
                  border: TableBorder.all(color: c.border, width: 0.8),
                  columnWidths: const {
                    0: FlexColumnWidth(1.2),
                    1: FlexColumnWidth(2.5),
                    2: FlexColumnWidth(1.2),
                    3: FlexColumnWidth(1.2),
                    4: FlexColumnWidth(1.2),
                    5: FlexColumnWidth(1.4),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: c.bgCardElevated),
                      children: [
                        _pdfCell('Mã SKU', isBold: true, c: c),
                        _pdfCell('Tên Sản Phẩm', isBold: true, c: c),
                        _pdfCell('Tồn Sổ Sách', isBold: true, align: TextAlign.center, c: c),
                        _pdfCell('Thực Tế Quét', isBold: true, align: TextAlign.center, c: c),
                        _pdfCell('Chênh Lệch', isBold: true, align: TextAlign.center, c: c),
                        _pdfCell('Đánh Giá', isBold: true, align: TextAlign.center, c: c),
                      ],
                    ),
                    ...skuBreakdowns.map((row) {
                      final diff = row.difference;
                      return TableRow(
                        children: [
                          _pdfCell(row.sku, c: c),
                          _pdfCell(row.productName, c: c),
                          _pdfCell('${row.expectedQty}', align: TextAlign.center, c: c),
                          _pdfCell('${row.actualQty}', align: TextAlign.center, c: c),
                          _pdfCell(diff == 0 ? '0' : (diff > 0 ? '+$diff' : '$diff'), align: TextAlign.center, c: c),
                          _pdfCell(row.statusLabel, align: TextAlign.center, c: c),
                        ],
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _signatureBox('TRƯỞNG BAN KIỂM KÊ', '(Ký, ghi rõ họ tên)', c),
                    _signatureBox('THỦ KHO', '(Ký, ghi rõ họ tên)', c),
                    _signatureBox('KẾ TOÁN TRƯỞNG', '(Ký, ghi rõ họ tên)', c),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ĐÓNG')),
          ElevatedButton.icon(
            icon: const Icon(Icons.download, size: 16),
            label: const Text('XUẤT FILE EXCEL'),
            style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(ctx);
              _exportAuditExcel();
            },
          ),
        ],
      ),
    );
  }

  Widget _pdfCell(String text, {bool isBold = false, TextAlign align = TextAlign.left, required EyeCareColors c}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          color: isBold ? c.textPrimary : c.textSecondary,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontSize: 11,
        ),
      ),
    );
  }

  Widget _signatureBox(String title, String note, EyeCareColors c) {
    return Column(
      children: [
        Text(title, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11)),
        const SizedBox(height: 2),
        Text(note, style: TextStyle(color: c.textMuted, fontSize: 10, fontStyle: FontStyle.italic)),
        const SizedBox(height: 40),
        Container(width: 100, height: 1, color: c.border),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final s = widget.session;
    final skuBreakdowns = _repo.buildSessionSkuBreakdown(s);

    final totalExpected = s.matchCount + s.missingCount;
    final accuracyPercent = totalExpected > 0 ? (s.matchCount / totalExpected * 100).toStringAsFixed(1) : '100.0';

    return Container(
      color: c.bgDeep,
      child: Column(
        children: [
          // 1. TOP HEADER BAR
          _buildHeaderBar(c, accuracyPercent),

          // 2. MAIN SCROLLABLE CONTENT
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // THẺ THÔNG TIN PHIẾU KIỂM KÊ (METADATA CARD)
                  _buildTicketMetadataCard(c, s),
                  const SizedBox(height: 16),

                  // 6 THẺ KPI ĐỐI CHIẾU THỰC TẾ VS DỰ KIẾN (SCORECARD)
                  _buildScorecard(c, s, totalExpected, accuracyPercent),
                  const SizedBox(height: 20),

                  // TAB BAR CHUYỂN ĐỔI: TỔNG HỢP SKU vs CHI TIẾT CHIP EPC
                  _buildTabBarContainer(c, skuBreakdowns.length, s.effectiveResults.length),
                  const SizedBox(height: 14),

                  // NỘI DUNG TAB ĐƯỢC CHỌN
                  AnimatedBuilder(
                    animation: _tabController,
                    builder: (context, _) {
                      if (_tabController.index == 0) {
                        return _buildSkuBreakdownSection(c, skuBreakdowns);
                      } else {
                        return _buildEpcTagsSection(c, s.effectiveResults);
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. TOP HEADER BAR
  // ===========================================================================
  Widget _buildHeaderBar(EyeCareColors c, String accuracyPercent) {
    final s = widget.session;
    final isDone = s.isCompleted;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left: Back button & Breadcrumb Title
          Row(
            children: [
              IconButton(
                tooltip: 'Quay lại danh sách',
                icon: Icon(Icons.arrow_back_rounded, color: c.textPrimary, size: 22),
                onPressed: widget.onBack,
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 13, color: c.textMuted),
                      const SizedBox(width: 4),
                      Text('Kiểm Kê Kho', style: TextStyle(color: c.textMuted, fontSize: 11)),
                      Text(' / ', style: TextStyle(color: c.textMuted, fontSize: 11)),
                      Text('Chi Tiết Phiếu Kiểm Kê', style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        'PHIẾU KIỂM KÊ: ${s.sessionCode}',
                        style: TextStyle(color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDone
                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                              : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDone ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(isDone ? Icons.check_circle_rounded : Icons.sync_rounded, size: 12, color: isDone ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                            const SizedBox(width: 4),
                            Text(
                              isDone ? 'ĐÃ HOÀN TẤT' : 'ĐANG DỞ DANG',
                              style: TextStyle(
                                color: isDone ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),

          // Right: Action Buttons
          Wrap(
            spacing: 10,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.print_rounded, size: 16),
                label: const Text('IN BIÊN BẢN'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.textPrimary,
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: () => _showPrintPreviewDialog(c),
              ),
              ElevatedButton.icon(
                icon: _isExporting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.file_download_rounded, size: 16),
                label: const Text('XUẤT BIÊN BẢN (.XLSX)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  elevation: 0,
                ),
                onPressed: _isExporting ? null : _exportAuditExcel,
              ),
              if (!isDone && widget.onContinueScanning != null)
                ElevatedButton.icon(
                  icon: const Icon(Icons.radar_rounded, size: 16),
                  label: const Text('TIẾP TỤC QUÉT'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.rfidCyan,
                    foregroundColor: const Color(0xFF2C251E),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    elevation: 0,
                  ),
                  onPressed: widget.onContinueScanning,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. METADATA CARD (THÔNG TIN CHUNG PHIẾU KIỂM KÊ)
  // ===========================================================================
  Widget _buildTicketMetadataCard(EyeCareColors c, InventorySession s) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 800;

          final col1 = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _metadataRow('Mã Phiếu:', s.sessionCode, isBold: true, c: c),
              const SizedBox(height: 8),
              _metadataRow(
                'Phạm Vi:',
                s.isSkuSpecific
                    ? 'Theo mặt hàng: ${s.targetSkus.join(", ")}'
                    : (s.locationCode != null ? '${s.locationCode} (${s.zone})' : s.zone),
                c: c,
              ),
            ],
          );

          final col2 = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _metadataRow('Thời Gian Bắt Đầu:', _formatDateTime(s.startedAt), c: c),
              const SizedBox(height: 8),
              _metadataRow('Thời Gian Chốt:', s.completedAt != null ? _formatDateTime(s.completedAt!) : 'Chưa hoàn tất', c: c),
            ],
          );

          final col3 = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _metadataRow('Phương Thức:', 'Đầu đọc sóng UHF RFID', c: c),
              const SizedBox(height: 8),
              _metadataRow('Người Thực Hiện:', 'Thủ kho (Admin)', c: c),
            ],
          );

          if (isNarrow) {
            return Column(
              children: [
                col1,
                const Divider(height: 16),
                col2,
                const Divider(height: 16),
                col3,
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: col1),
              Container(width: 1, height: 48, color: c.border, margin: const EdgeInsets.symmetric(horizontal: 16)),
              Expanded(child: col2),
              Container(width: 1, height: 48, color: c.border, margin: const EdgeInsets.symmetric(horizontal: 16)),
              Expanded(child: col3),
            ],
          );
        },
      ),
    );
  }

  Widget _metadataRow(String label, String value, {bool isBold = false, required EyeCareColors c}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 12)),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              color: isBold ? c.rfidCyan : c.textPrimary,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              fontSize: 12.5,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // 3. SCORECARD 6 THẺ KPI ĐỐI SOÁT
  // ===========================================================================
  Widget _buildScorecard(EyeCareColors c, InventorySession s, int totalExpected, String accuracyPercent) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            // Thẻ 1: Tổng dự kiến (Sổ sách)
            Expanded(
              child: _buildMetricTile(
                title: 'TỒN DỰ KIẾN',
                value: '$totalExpected SP',
                icon: Icons.inventory_2_outlined,
                color: c.textPrimary,
                bg: c.bgCardElevated,
                borderColor: c.border,
                c: c,
              ),
            ),
            const SizedBox(width: 10),

            // Thẻ 2: Thực tế quét RFID
            Expanded(
              child: _buildMetricTile(
                title: 'THỰC TẾ QUÉT',
                value: '${s.actualScannedCount} Chip',
                icon: Icons.radar_rounded,
                color: c.rfidCyan,
                bg: c.rfidCyan.withValues(alpha: 0.1),
                borderColor: c.rfidCyan.withValues(alpha: 0.3),
                c: c,
              ),
            ),
            const SizedBox(width: 10),

            // Thẻ 3: Khớp hoàn toàn
            Expanded(
              child: _buildMetricTile(
                title: '✓ KHỚP CHUẨN',
                value: '${s.matchCount} SP',
                icon: Icons.check_circle_outline_rounded,
                color: const Color(0xFF10B981),
                bg: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderColor: const Color(0xFF10B981).withValues(alpha: 0.3),
                c: c,
              ),
            ),
            const SizedBox(width: 10),

            // Thẻ 4: Thiếu thực tế
            Expanded(
              child: _buildMetricTile(
                title: '⚠️ LỆCH THIẾU',
                value: '-${s.missingCount} SP',
                icon: Icons.error_outline_rounded,
                color: const Color(0xFFEF4444),
                bg: const Color(0xFFEF4444).withValues(alpha: 0.1),
                borderColor: const Color(0xFFEF4444).withValues(alpha: 0.3),
                c: c,
              ),
            ),
            const SizedBox(width: 10),

            if (!s.isSkuSpecific) ...[
              // Thẻ 5: Sai vị trí
              Expanded(
                child: _buildMetricTile(
                  title: '🔀 SAI VỊ TRÍ',
                  value: '${s.wrongLocationCount} SP',
                  icon: Icons.alt_route_rounded,
                  color: const Color(0xFFF59E0B),
                  bg: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  borderColor: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                  c: c,
                ),
              ),
              const SizedBox(width: 10),

              // Thẻ 6: Thẻ lạ ngoài đơn
              Expanded(
                child: _buildMetricTile(
                  title: '❓ THẺ LẠ',
                  value: '+${s.unknownEpcCount} Chip',
                  icon: Icons.help_outline_rounded,
                  color: const Color(0xFF8B5CF6),
                  bg: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                  borderColor: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                  c: c,
                ),
              ),
              const SizedBox(width: 10),
            ],

            // Thẻ 7: Tỷ lệ chính xác
            Expanded(
              child: _buildMetricTile(
                title: 'ĐỘ CHÍNH XÁC',
                value: '$accuracyPercent%',
                icon: Icons.verified_rounded,
                color: double.parse(accuracyPercent) >= 95 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                bg: (double.parse(accuracyPercent) >= 95 ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.1),
                borderColor: (double.parse(accuracyPercent) >= 95 ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.3),
                c: c,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMetricTile({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bg,
    required Color borderColor,
    required EyeCareColors c,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              Icon(icon, size: 14, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(color: color, fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // ===========================================================================
  // 4. TAB BAR CONTAINER
  // ===========================================================================
  Widget _buildTabBarContainer(EyeCareColors c, int skuCount, int epcCount) {
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorColor: c.rfidCyan,
        indicatorWeight: 3,
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: c.rfidCyan,
        unselectedLabelColor: c.textSecondary,
        labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.analytics_outlined, size: 18),
                const SizedBox(width: 8),
                Text('BẢNG TỔNG HỢP THEO MẶT HÀNG / SKU ($skuCount)'),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.nfc_rounded, size: 18),
                const SizedBox(width: 8),
                Text('CHI TIẾT DANH SÁCH CHIP RFID EPC ($epcCount)'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 5. TAB 1: BẢNG TỔNG HỢP THEO MẶT HÀNG / SKU
  // ===========================================================================
  Widget _buildSkuBreakdownSection(EyeCareColors c, List<SkuStockReconciliationRow> allRows) {
    // Lọc theo từ khóa tìm kiếm
    var filtered = allRows;
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = filtered.where((r) {
        return r.sku.toLowerCase().contains(q) ||
            r.productName.toLowerCase().contains(q) ||
            r.zoneOrLocation.toLowerCase().contains(q);
      }).toList();
    }

    // Lọc theo trạng thái chênh lệch
    if (_skuFilter == 'DISCREPANCY') {
      filtered = filtered.where((r) => r.difference != 0 || r.wrongLocationCount > 0).toList();
    } else if (_skuFilter == 'MATCH') {
      filtered = filtered.where((r) => r.difference == 0 && r.wrongLocationCount == 0).toList();
    }

    final discrepancyCount = allRows.where((r) => r.difference != 0 || r.wrongLocationCount > 0).length;
    final matchCount = allRows.where((r) => r.difference == 0 && r.wrongLocationCount == 0).length;

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Toolbar
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Filter chips
                _filterChip('Tất cả (${allRows.length})', 'ALL', _skuFilter, (val) => setState(() => _skuFilter = val), c),
                const SizedBox(width: 8),
                _filterChip('⚠️ Có sai lệch ($discrepancyCount)', 'DISCREPANCY', _skuFilter, (val) => setState(() => _skuFilter = val), c, activeColor: const Color(0xFFEF4444)),
                const SizedBox(width: 8),
                _filterChip('✓ Khớp 100% ($matchCount)', 'MATCH', _skuFilter, (val) => setState(() => _skuFilter = val), c, activeColor: const Color(0xFF10B981)),
                const Spacer(),

                // Search field
                SizedBox(
                  width: 260,
                  height: 36,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: TextStyle(color: c.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Tìm SKU, tên sản phẩm...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                      prefixIcon: Icon(Icons.search, size: 16, color: c.textSecondary),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.clear, size: 14), onPressed: () => setState(() { _searchCtrl.clear(); _searchQuery = ''; }))
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      filled: true,
                      fillColor: c.bgCardElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Table
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 36, color: c.textMuted),
                    const SizedBox(height: 8),
                    Text('Không tìm thấy mặt hàng nào phù hợp với bộ lọc.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            Table(
              border: TableBorder(horizontalInside: BorderSide(color: c.border.withValues(alpha: 0.5), width: 0.8)),
              columnWidths: const {
                0: FlexColumnWidth(0.5), // STT
                1: FlexColumnWidth(1.4), // SKU
                2: FlexColumnWidth(2.6), // Tên sản phẩm
                3: FlexColumnWidth(0.7), // ĐVT
                4: FlexColumnWidth(1.4), // Vị trí
                5: FlexColumnWidth(1.1), // Tồn dự kiến
                6: FlexColumnWidth(1.1), // Tồn thực tế
                7: FlexColumnWidth(1.1), // Chênh lệch
                8: FlexColumnWidth(1.1), // Tỷ lệ
                9: FlexColumnWidth(1.2), // Trạng thái
                10: FlexColumnWidth(0.9), // Chi tiết chip
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: c.bgCardElevated),
                  children: [
                    _headerCell('STT', c, align: TextAlign.center),
                    _headerCell('MÃ SKU', c),
                    _headerCell('TÊN SẢN PHẨM / QUY CÁCH', c),
                    _headerCell('ĐVT', c, align: TextAlign.center),
                    _headerCell('VỊ TRÍ KHO', c),
                    _headerCell('DỰ KIẾN', c, align: TextAlign.center),
                    _headerCell('THỰC TẾ', c, align: TextAlign.center),
                    _headerCell('CHÊNH LỆCH', c, align: TextAlign.center),
                    _headerCell('TỶ LỆ', c, align: TextAlign.center),
                    _headerCell('ĐỐI SOÁT', c, align: TextAlign.center),
                    _headerCell('XEM CHIP', c, align: TextAlign.center),
                  ],
                ),
                ...filtered.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final r = entry.value;
                  final diff = r.difference;

                  Color diffColor = const Color(0xFF10B981);
                  String diffStr = '0';
                  if (diff < 0) {
                    diffColor = const Color(0xFFEF4444);
                    diffStr = '$diff';
                  } else if (diff > 0) {
                    diffColor = const Color(0xFF8B5CF6);
                    diffStr = '+$diff';
                  } else if (r.wrongLocationCount > 0) {
                    diffColor = const Color(0xFFF59E0B);
                  }

                  return TableRow(
                    children: [
                      _dataCell('${idx + 1}', c, align: TextAlign.center, isMuted: true),
                      _dataCell(r.sku, c, isBold: true, color: c.rfidCyan),
                      _dataCell(r.productName, c),
                      _dataCell(r.unit, c, align: TextAlign.center),
                      _dataCell(r.zoneOrLocation, c, isSecondary: true),
                      _dataCell('${r.expectedQty}', c, align: TextAlign.center, isBold: true),
                      _dataCell('${r.actualQty}', c, align: TextAlign.center, isBold: true),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: diffColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              diffStr,
                              style: TextStyle(color: diffColor, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                        ),
                      ),
                      _dataCell('${r.accuracyPercent.toStringAsFixed(1)}%', c, align: TextAlign.center, isBold: true),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                        child: Center(child: _buildStatusPill(r.statusLabel, diffColor)),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                        child: Center(
                          child: IconButton(
                            tooltip: 'Xem danh sách chip RFID của SKU này',
                            icon: Icon(Icons.nfc_rounded, size: 18, color: c.rfidCyan),
                            onPressed: () {
                              setState(() {
                                _selectedFilterSku = r.sku;
                                _rfidFilter = 'ALL';
                                _tabController.animateTo(1);
                              });
                            },
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 6. TAB 2: DANH SÁCH CHI TIẾT TỪNG CHIP RFID EPC
  // ===========================================================================
  Widget _buildEpcTagsSection(EyeCareColors c, List<InventoryItemResult> allResults) {
    var filtered = allResults;

    // Lọc theo SKU nếu được chọn từ Tab 1
    if (_selectedFilterSku != null) {
      filtered = filtered.where((r) => r.sku == _selectedFilterSku).toList();
    }

    // Lọc theo từ khóa tìm kiếm
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = filtered.where((r) {
        return r.epc.toLowerCase().contains(q) ||
            (r.sku ?? '').toLowerCase().contains(q) ||
            (r.productName ?? '').toLowerCase().contains(q) ||
            (r.expectedLocation ?? '').toLowerCase().contains(q) ||
            (r.actualLocation ?? '').toLowerCase().contains(q);
      }).toList();
    }

    // Lọc theo loại kết quả đối soát
    if (_rfidFilter == 'MATCH') {
      filtered = filtered.where((r) => r.resultType == InventoryVarianceType.match).toList();
    } else if (_rfidFilter == 'MISSING') {
      filtered = filtered.where((r) => r.resultType == InventoryVarianceType.missing).toList();
    } else if (_rfidFilter == 'WRONG_LOC') {
      filtered = filtered.where((r) => r.resultType == InventoryVarianceType.wrongLocation).toList();
    } else if (_rfidFilter == 'UNKNOWN') {
      filtered = filtered.where((r) => r.resultType == InventoryVarianceType.unknownEpc).toList();
    }

    final matchCount = allResults.where((r) => r.resultType == InventoryVarianceType.match).length;
    final missingCount = allResults.where((r) => r.resultType == InventoryVarianceType.missing).length;
    final wrongLocCount = allResults.where((r) => r.resultType == InventoryVarianceType.wrongLocation).length;
    final unknownCount = allResults.where((r) => r.resultType == InventoryVarianceType.unknownEpc).length;

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Filter Toolbar
          Padding(
            padding: const EdgeInsets.all(14),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (_selectedFilterSku != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: c.rfidCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.rfidCyan),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('SKU: ${_selectedFilterSku!}', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5)),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () => setState(() => _selectedFilterSku = null),
                          child: Icon(Icons.close, size: 14, color: c.rfidCyan),
                        ),
                      ],
                    ),
                  ),

                _filterChip('Tất cả (${allResults.length})', 'ALL', _rfidFilter, (val) => setState(() => _rfidFilter = val), c),
                _filterChip('✓ Khớp ($matchCount)', 'MATCH', _rfidFilter, (val) => setState(() => _rfidFilter = val), c, activeColor: const Color(0xFF10B981)),
                _filterChip('⚠️ Thiếu ($missingCount)', 'MISSING', _rfidFilter, (val) => setState(() => _rfidFilter = val), c, activeColor: const Color(0xFFEF4444)),
                if (!widget.session.isSkuSpecific) ...[
                  _filterChip('🔀 Sai vị trí ($wrongLocCount)', 'WRONG_LOC', _rfidFilter, (val) => setState(() => _rfidFilter = val), c, activeColor: const Color(0xFFF59E0B)),
                  _filterChip('❓ Thẻ lạ ($unknownCount)', 'UNKNOWN', _rfidFilter, (val) => setState(() => _rfidFilter = val), c, activeColor: const Color(0xFF8B5CF6)),
                ],

                SizedBox(
                  width: 240,
                  height: 36,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: TextStyle(color: c.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Tìm EPC, SKU, vị trí...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                      prefixIcon: Icon(Icons.search, size: 16, color: c.textSecondary),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      filled: true,
                      fillColor: c.bgCardElevated,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Table
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.nfc_rounded, size: 36, color: c.textMuted),
                    const SizedBox(height: 8),
                    Text('Không tìm thấy thẻ chip RFID nào phù hợp với bộ lọc.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                  ],
                ),
              ),
            )
          else
            Table(
              border: TableBorder(horizontalInside: BorderSide(color: c.border.withValues(alpha: 0.5), width: 0.8)),
              columnWidths: const {
                0: FlexColumnWidth(0.5), // STT
                1: FlexColumnWidth(2.6), // Mã Chip EPC
                2: FlexColumnWidth(1.4), // SKU
                3: FlexColumnWidth(2.5), // Tên sản phẩm
                4: FlexColumnWidth(1.6), // Vị trí sổ sách
                5: FlexColumnWidth(1.6), // Vị trí quét
                6: FlexColumnWidth(1.4), // Kết quả đối soát
                7: FlexColumnWidth(1.2), // Thời gian
              },
              children: [
                TableRow(
                  decoration: BoxDecoration(color: c.bgCardElevated),
                  children: [
                    _headerCell('STT', c, align: TextAlign.center),
                    _headerCell('MÃ CHIP RFID EPC', c),
                    _headerCell('MÃ SKU', c),
                    _headerCell('TÊN SẢN PHẨM', c),
                    _headerCell('VỊ TRÍ SỔ SÁCH', c),
                    _headerCell('VỊ TRÍ THỰC TẾ', c),
                    _headerCell('KẾT QUẢ', c, align: TextAlign.center),
                    _headerCell('THỜI GIAN', c, align: TextAlign.center),
                  ],
                ),
                ...filtered.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final r = entry.value;

                  Color resColor = const Color(0xFF10B981);
                  String resLabel = 'Khớp chuẩn';
                  if (r.resultType == InventoryVarianceType.missing) {
                    resColor = const Color(0xFFEF4444);
                    resLabel = 'Thiếu thực tế';
                  } else if (r.resultType == InventoryVarianceType.wrongLocation) {
                    resColor = const Color(0xFFF59E0B);
                    resLabel = 'Sai vị trí';
                  } else if (r.resultType == InventoryVarianceType.unknownEpc) {
                    resColor = const Color(0xFF8B5CF6);
                    resLabel = 'Thẻ lạ ngoài DS';
                  }

                  return TableRow(
                    children: [
                      _dataCell('${idx + 1}', c, align: TextAlign.center, isMuted: true),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Text(
                          r.epc,
                          style: TextStyle(color: c.textPrimary, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11.5),
                        ),
                      ),
                      _dataCell(r.sku ?? '--', c, color: c.rfidCyan),
                      _dataCell(r.productName ?? '--', c),
                      _dataCell(r.expectedLocation ?? '--', c, isSecondary: true),
                      _dataCell(r.actualLocation ?? '--', c, isSecondary: true),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
                        child: Center(child: _buildStatusPill(resLabel, resColor)),
                      ),
                      _dataCell(_formatDateTime(r.readAt), c, align: TextAlign.center, isMuted: true, fontSize: 11),
                    ],
                  );
                }),
              ],
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // HELPER WIDGETS
  // ===========================================================================
  Widget _filterChip(String label, String value, String current, Function(String) onSelect, EyeCareColors c, {Color? activeColor}) {
    final isSelected = current == value;
    final actColor = activeColor ?? c.rfidCyan;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => onSelect(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? actColor.withValues(alpha: 0.15) : c.bgCardElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? actColor : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? actColor : c.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String title, EyeCareColors c, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Text(
        title,
        textAlign: align,
        style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.3),
      ),
    );
  }

  Widget _dataCell(
    String text,
    EyeCareColors c, {
    TextAlign align = TextAlign.left,
    bool isBold = false,
    bool isSecondary = false,
    bool isMuted = false,
    Color? color,
    double fontSize = 12,
  }) {
    Color col = c.textPrimary;
    if (color != null) {
      col = color;
    } else if (isMuted) {
      col = c.textMuted;
    } else if (isSecondary) {
      col = c.textSecondary;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          color: col,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          fontSize: fontSize,
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildStatusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.bold),
      ),
    );
  }
}
