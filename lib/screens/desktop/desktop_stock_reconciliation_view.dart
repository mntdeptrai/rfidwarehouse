import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import '../../models/wms_models.dart';
import '../../services/report_export_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';

/// Màn hình Xem Tồn Kho Dự Kiến & Tồn Kho Kiểm Kê Theo Thực Tế (Desktop Stock Reconciliation)
/// Cung cấp đối chiếu toàn diện giữa số liệu sổ sách (dự kiến trong CSDL) và thực tế kiểm kê đọc qua sóng UHF RFID.
class DesktopStockReconciliationView extends StatefulWidget {
  final Function(InventorySession)? onOpenSessionDetail;

  const DesktopStockReconciliationView({
    super.key,
    this.onOpenSessionDetail,
  });

  @override
  State<DesktopStockReconciliationView> createState() => _DesktopStockReconciliationViewState();
}

class _DesktopStockReconciliationViewState extends State<DesktopStockReconciliationView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final ReportExportService _exportService = ReportExportService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  // Phiên kiểm kê đang chọn (null = Phiên mới nhất nếu có, 'ALL' = Toàn kho tổng hợp)
  String? _selectedSessionId;

  // Lọc theo phân khu
  String _selectedZone = 'ALL';

  // Lọc theo chênh lệch: ALL, DISCREPANCY, MATCH, SHORTAGE, SURPLUS
  String _discrepancyFilter = 'ALL';

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onDataChanged);
    _eyeCare.addListener(_onDataChanged);

    // Mặc định tự động chọn phiên kiểm kê mới nhất đã hoàn thành
    final latestSession = _repo.inventorySessions.where((s) => s.isCompleted).firstOrNull 
        ?? _repo.inventorySessions.firstOrNull;
    if (latestSession != null) {
      _selectedSessionId = latestSession.sessionId;
    }

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      unawaited(_repo.reloadFromDatabase());
    }
  }

  void _onDataChanged() {
    if (mounted) {
      final sessions = _repo.inventorySessions;
      final latestSession = sessions.where((s) => s.isCompleted).firstOrNull ?? sessions.firstOrNull;
      // Tự động đối soát: nếu chưa chọn hoặc phiên cũ không còn hợp lệ thì chọn ngay phiên mới nhất đã hoàn tất
      if ((_selectedSessionId == null || !sessions.any((s) => s.sessionId == _selectedSessionId)) && latestSession != null) {
        _selectedSessionId = latestSession.sessionId;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _repo.removeListener(_onDataChanged);
    _eyeCare.removeListener(_onDataChanged);
    super.dispose();
  }

  List<SkuStockReconciliationRow> _getReconciliationData() {
    final sessions = _repo.inventorySessions;
    final latestSession = sessions.where((s) => s.isCompleted).firstOrNull ?? sessions.firstOrNull;
    final effectiveSessionId = (_selectedSessionId != null &&
            (_selectedSessionId == 'ALL' || sessions.any((s) => s.sessionId == _selectedSessionId)))
        ? _selectedSessionId
        : latestSession?.sessionId;

    return _repo.getStockReconciliation(
      sessionId: effectiveSessionId,
      zone: _selectedZone == 'ALL' ? null : _selectedZone,
    );
  }

  String _getScopeTitle() {
    final sessions = _repo.inventorySessions;
    final latestSession = sessions.where((s) => s.isCompleted).firstOrNull ?? sessions.firstOrNull;
    final effectiveSessionId = (_selectedSessionId != null &&
            (_selectedSessionId == 'ALL' || sessions.any((s) => s.sessionId == _selectedSessionId)))
        ? _selectedSessionId
        : latestSession?.sessionId;

    if (effectiveSessionId != null && effectiveSessionId != 'ALL') {
      final s = sessions.where((sess) => sess.sessionId == effectiveSessionId).firstOrNull;
      if (s != null) {
        return 'Phiếu kiểm kê ${s.sessionCode} (${s.zone}${s.locationCode != null ? " • ${s.locationCode}" : ""})';
      }
    }
    return 'Toàn bộ kho hàng (${_selectedZone == "ALL" ? "Tất cả khu vực" : _selectedZone})';
  }

  Future<void> _exportToExcel(List<SkuStockReconciliationRow> rows) async {
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ Không có dữ liệu để xuất báo cáo đối soát.')),
      );
      return;
    }

    setState(() => _isExporting = true);
    try {
      final scopeTitle = _getScopeTitle();
      final session = _selectedSessionId != null && _selectedSessionId != 'ALL'
          ? _repo.inventorySessions.where((s) => s.sessionId == _selectedSessionId).firstOrNull
          : null;

      final file = await _exportService.exportStockReconciliationReport(
        ReportFormat.xlsx,
        rows: rows,
        scopeTitle: scopeTitle,
        sessionCode: session?.sessionCode,
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
                  '✓ Đã xuất bảng đối soát tồn kho thành công (${rows.length} mặt hàng)!',
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
          content: Text('Lỗi xuất báo cáo đối soát: $e'),
        ),
      );
    }
  }

  void _showSkuItemTagsDialog(SkuStockReconciliationRow row, EyeCareColors c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
        title: Row(
          children: [
            Icon(Icons.nfc_rounded, color: c.rfidCyan, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Chi Tiết Chip RFID: ${row.sku}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text(row.productName, style: TextStyle(color: c.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 680,
          height: 380,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Summary Row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: c.bgCardElevated, borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Text('Dự kiến: ${row.expectedQty}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 14),
                    Text('Thực tế: ${row.actualQty}', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 14),
                    Text('Khớp: ${row.matchedCount}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 14),
                    Text('Thiếu: ${row.missingCount}', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(width: 14),
                    Text('Sai vị trí: ${row.wrongLocationCount}', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: c.bgCardElevated, borderRadius: const BorderRadius.vertical(top: Radius.circular(6))),
                child: Row(
                  children: [
                    SizedBox(width: 35, child: Text('STT', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    Expanded(flex: 3, child: Text('MÃ CHIP EPC', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    Expanded(flex: 2, child: Text('VỊ TRÍ SỔ SÁCH', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    Expanded(flex: 2, child: Text('VỊ TRÍ QUÉT', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    SizedBox(width: 110, child: Text('KẾT QUẢ', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),

              // List of chips
              Expanded(
                child: row.itemResults.isEmpty
                    ? Center(child: Text('Không có dữ liệu chip chi tiết.', style: TextStyle(color: c.textSecondary)))
                    : ListView.builder(
                        itemCount: row.itemResults.length,
                        itemBuilder: (ctx, idx) {
                          final it = row.itemResults[idx];
                          Color resColor = const Color(0xFF10B981);
                          String resLabel = 'Khớp chuẩn';
                          if (it.resultType == InventoryVarianceType.missing) {
                            resColor = const Color(0xFFEF4444);
                            resLabel = 'Thiếu';
                          } else if (it.resultType == InventoryVarianceType.wrongLocation) {
                            resColor = const Color(0xFFF59E0B);
                            resLabel = 'Sai vị trí';
                          } else if (it.resultType == InventoryVarianceType.unknownEpc) {
                            resColor = const Color(0xFF8B5CF6);
                            resLabel = 'Thẻ lạ';
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.5)))),
                            child: Row(
                              children: [
                                SizedBox(width: 35, child: Text('${idx + 1}', style: TextStyle(color: c.textMuted, fontSize: 11))),
                                Expanded(flex: 3, child: Text(it.epc, style: TextStyle(color: c.textPrimary, fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text(it.expectedLocation ?? '--', style: TextStyle(color: c.textSecondary, fontSize: 11.5))),
                                Expanded(flex: 2, child: Text(it.actualLocation ?? '--', style: TextStyle(color: c.textSecondary, fontSize: 11.5))),
                                SizedBox(
                                  width: 110,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: resColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                      child: Text(resLabel, style: TextStyle(color: resColor, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ĐÓNG')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final allRows = _getReconciliationData();

    // 1. Thống kê KPI tổng
    final totalExpected = allRows.fold<int>(0, (sum, r) => sum + r.expectedQty);
    final totalActual = allRows.fold<int>(0, (sum, r) => sum + r.actualQty);
    final totalMatched = allRows.fold<int>(0, (sum, r) => sum + r.matchedCount);
    final totalMissing = allRows.fold<int>(0, (sum, r) => sum + r.missingCount);
    final totalSurplus = allRows.fold<int>(0, (sum, r) => sum + (r.difference > 0 ? r.difference : 0));
    final totalWrongLoc = allRows.fold<int>(0, (sum, r) => sum + r.wrongLocationCount);
    final accuracyPercent = totalExpected > 0 ? (totalMatched / totalExpected * 100).toStringAsFixed(1) : '100.0';

    // 2. Lọc dữ liệu theo từ khóa tìm kiếm và chênh lệch
    var filtered = allRows;
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      filtered = filtered.where((r) {
        return r.sku.toLowerCase().contains(q) ||
            r.productName.toLowerCase().contains(q) ||
            r.zoneOrLocation.toLowerCase().contains(q);
      }).toList();
    }

    if (_discrepancyFilter == 'DISCREPANCY') {
      filtered = filtered.where((r) => r.difference != 0 || r.wrongLocationCount > 0).toList();
    } else if (_discrepancyFilter == 'MATCH') {
      filtered = filtered.where((r) => r.difference == 0 && r.wrongLocationCount == 0).toList();
    } else if (_discrepancyFilter == 'SHORTAGE') {
      filtered = filtered.where((r) => r.difference < 0).toList();
    } else if (_discrepancyFilter == 'SURPLUS') {
      filtered = filtered.where((r) => r.difference > 0).toList();
    }

    final totalDiscrepancies = allRows.where((r) => r.difference != 0 || r.wrongLocationCount > 0).length;
    final totalMatches = allRows.where((r) => r.difference == 0 && r.wrongLocationCount == 0).length;
    final totalShortages = allRows.where((r) => r.difference < 0).length;
    final totalSurpluses = allRows.where((r) => r.difference > 0).length;

    // Lấy danh sách zones
    final allZones = _repo.locations.map((l) => l.zone.trim()).where((z) => z.isNotEmpty).toSet().toList();
    if (allZones.isEmpty) allZones.addAll(['Khu A', 'Khu B', 'Khu C']);

    final currentSession = _selectedSessionId != null && _selectedSessionId != 'ALL'
        ? _repo.inventorySessions.where((s) => s.sessionId == _selectedSessionId).firstOrNull
        : null;

    return Container(
      color: c.bgDeep,
      child: Column(
        children: [
          // 1. HEADER BAR
          _buildHeaderBar(c, currentSession, allRows),

          // 2. MAIN SCROLLABLE CONTENT
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // THẺ KPI SCORECARD (6 METRICS)
                  _buildScorecard(
                    c,
                    totalExpected: totalExpected,
                    totalActual: totalActual,
                    totalMatched: totalMatched,
                    totalMissing: totalMissing,
                    totalSurplus: totalSurplus,
                    totalWrongLoc: totalWrongLoc,
                    accuracyPercent: accuracyPercent,
                  ),
                  const SizedBox(height: 16),

                  // TOOLBAR: CHỌN PHIẾU KIỂM KÊ & BỘ LỌC CHÊNH LỆCH
                  _buildFilterToolbar(
                    c,
                    allZones: allZones,
                    totalAll: allRows.length,
                    totalDiscrepancies: totalDiscrepancies,
                    totalMatches: totalMatches,
                    totalShortages: totalShortages,
                    totalSurpluses: totalSurpluses,
                  ),
                  const SizedBox(height: 14),

                  // BẢNG DỮ LIỆU ĐỐI SOÁT CHI TIẾT
                  _buildReconciliationTable(c, filtered, currentSession),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. HEADER BAR
  // ===========================================================================
  Widget _buildHeaderBar(EyeCareColors c, InventorySession? currentSession, List<SkuStockReconciliationRow> allRows) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: c.rfidCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.balance_rounded, color: c.rfidCyan, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              'ĐỐI SOÁT TỒN KHO: DỰ KIẾN (SỔ SÁCH) VS THỰC TẾ KIỂM KÊ',
                              style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.3),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('UHF RFID', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Đối chiếu số lượng tồn kho trên hệ thống với kết quả đọc chip UHF RFID thực tế tại kho',
                        style: TextStyle(color: c.textSecondary, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          Wrap(
            spacing: 10,
            children: [
              if (currentSession != null && widget.onOpenSessionDetail != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.receipt_long_rounded, size: 16),
                  label: Text('XEM PHIẾU ${currentSession.sessionCode}'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.rfidCyan,
                    side: BorderSide(color: c.rfidCyan.withValues(alpha: 0.5)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  onPressed: () => widget.onOpenSessionDetail!(currentSession),
                ),
              ElevatedButton.icon(
                icon: _isExporting
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.file_download_rounded, size: 16),
                label: const Text('XUẤT BẢNG ĐỐI SOÁT (.XLSX)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  elevation: 0,
                ),
                onPressed: _isExporting ? null : () => _exportToExcel(allRows),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2. SCORECARD (6 METRIC TILES)
  // ===========================================================================
  Widget _buildScorecard(
    EyeCareColors c, {
    required int totalExpected,
    required int totalActual,
    required int totalMatched,
    required int totalMissing,
    required int totalSurplus,
    required int totalWrongLoc,
    required String accuracyPercent,
  }) {
    return Row(
      children: [
        Expanded(
          child: _metricCard(
            title: 'TỒN DỰ KIẾN (SỔ SÁCH)',
            value: '$totalExpected SP',
            icon: Icons.inventory_2_outlined,
            color: c.textPrimary,
            bg: c.bgCardElevated,
            borderColor: c.border,
            c: c,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            title: 'THỰC TẾ KIỂM KÊ (RFID)',
            value: '$totalActual Chip',
            icon: Icons.radar_rounded,
            color: c.rfidCyan,
            bg: c.rfidCyan.withValues(alpha: 0.1),
            borderColor: c.rfidCyan.withValues(alpha: 0.3),
            c: c,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            title: '✓ KHỚP CHUẨN XÁC',
            value: '$totalMatched SP',
            icon: Icons.check_circle_outline_rounded,
            color: const Color(0xFF10B981),
            bg: const Color(0xFF10B981).withValues(alpha: 0.1),
            borderColor: const Color(0xFF10B981).withValues(alpha: 0.3),
            c: c,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            title: '🔻 TỔNG LỆCH THIẾU',
            value: '-$totalMissing SP',
            icon: Icons.remove_circle_outline_rounded,
            color: const Color(0xFFEF4444),
            bg: const Color(0xFFEF4444).withValues(alpha: 0.1),
            borderColor: const Color(0xFFEF4444).withValues(alpha: 0.3),
            c: c,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            title: '🔺 TỔNG LỆCH THỪA / LẠ',
            value: '+$totalSurplus Chip',
            icon: Icons.add_circle_outline_rounded,
            color: const Color(0xFF8B5CF6),
            bg: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
            borderColor: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
            c: c,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _metricCard(
            title: '🎯 ĐỘ CHÍNH XÁC KHO',
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
  }

  Widget _metricCard({
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
              Flexible(child: Text(title, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3), overflow: TextOverflow.ellipsis)),
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
  // 3. FILTER TOOLBAR
  // ===========================================================================
  Widget _buildFilterToolbar(
    EyeCareColors c, {
    required List<String> allZones,
    required int totalAll,
    required int totalDiscrepancies,
    required int totalMatches,
    required int totalShortages,
    required int totalSurpluses,
  }) {
    final sessions = _repo.inventorySessions;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          // Row 1: Dropdown đợt kiểm kê & phân khu + Search
          Row(
            children: [
              // Dropdown Chọn Đợt Kiểm Kê
              Text('Đợt kiểm kê:', style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: (_selectedSessionId != null &&
                            (_selectedSessionId == 'ALL' || sessions.any((s) => s.sessionId == _selectedSessionId)))
                        ? _selectedSessionId!
                        : (sessions.where((s) => s.isCompleted).firstOrNull?.sessionId ?? sessions.firstOrNull?.sessionId ?? 'ALL'),
                    dropdownColor: c.bgCardElevated,
                    style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    items: [
                      if (sessions.isEmpty)
                        const DropdownMenuItem(value: 'ALL', child: Text('Chưa có đợt kiểm kê (Toàn kho CSDL)'))
                      else ...[
                        DropdownMenuItem(
                          value: 'ALL',
                          child: Text('🌐 Toàn bộ các đợt kiểm kê đã chốt (${sessions.where((s) => s.isCompleted).length}/${sessions.length} đợt)'),
                        ),
                        ...sessions.map((s) {
                          return DropdownMenuItem(
                            value: s.sessionId,
                            child: Text('📋 ${s.sessionCode} • ${s.zone} (${s.startedAt.day}/${s.startedAt.month}/${s.startedAt.year})${s.isCompleted ? " ✓" : " (Đang kiểm)"}'),
                          );
                        }),
                      ],
                    ],
                    onChanged: (val) {
                      setState(() => _selectedSessionId = val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 14),

              // Dropdown Chọn Khu Vực
              Text('Khu vực:', style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedZone,
                    dropdownColor: c.bgCardElevated,
                    style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    items: [
                      const DropdownMenuItem(value: 'ALL', child: Text('Tất cả khu vực')),
                      ...allZones.map((z) => DropdownMenuItem(value: z, child: Text(z))),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedZone = val);
                    },
                  ),
                ),
              ),
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
                    hintText: 'Tìm theo SKU, tên sản phẩm...',
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
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Row 2: Filter chips theo trạng thái chênh lệch
          Row(
            children: [
              Text('Bộ lọc trạng thái:', style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.bold)),
              const SizedBox(width: 10),
              _filterChip('Tất cả ($totalAll)', 'ALL', _discrepancyFilter, (v) => setState(() => _discrepancyFilter = v), c),
              const SizedBox(width: 8),
              _filterChip('⚠️ Có chênh lệch ($totalDiscrepancies)', 'DISCREPANCY', _discrepancyFilter, (v) => setState(() => _discrepancyFilter = v), c, activeColor: const Color(0xFFEF4444)),
              const SizedBox(width: 8),
              _filterChip('✓ Khớp đủ ($totalMatches)', 'MATCH', _discrepancyFilter, (v) => setState(() => _discrepancyFilter = v), c, activeColor: const Color(0xFF10B981)),
              const SizedBox(width: 8),
              _filterChip('🔻 Lệch thiếu ($totalShortages)', 'SHORTAGE', _discrepancyFilter, (v) => setState(() => _discrepancyFilter = v), c, activeColor: const Color(0xFFEF4444)),
              const SizedBox(width: 8),
              _filterChip('🔺 Lệch thừa ($totalSurpluses)', 'SURPLUS', _discrepancyFilter, (v) => setState(() => _discrepancyFilter = v), c, activeColor: const Color(0xFF8B5CF6)),
            ],
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 4. RECONCILIATION TABLE (BẢNG ĐỐI SOÁT CHI TIẾT)
  // ===========================================================================
  Widget _buildReconciliationTable(EyeCareColors c, List<SkuStockReconciliationRow> rows, InventorySession? currentSession) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.inventory_2_outlined, size: 40, color: c.textMuted),
              const SizedBox(height: 10),
              Text('Không có dữ liệu mặt hàng đối soát.', style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text('Hãy chọn một đợt kiểm kê khác hoặc thực hiện kiểm kê kho để ghi nhận số liệu thực tế.', style: TextStyle(color: c.textSecondary, fontSize: 12)),
            ],
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Table(
          border: TableBorder(horizontalInside: BorderSide(color: c.border.withValues(alpha: 0.5), width: 0.8)),
          columnWidths: const {
            0: FlexColumnWidth(0.5), // STT
            1: FlexColumnWidth(1.3), // SKU
            2: FlexColumnWidth(2.6), // Tên sản phẩm
            3: FlexColumnWidth(0.7), // ĐVT
            4: FlexColumnWidth(1.5), // Vị trí kho
            5: FlexColumnWidth(1.2), // Tồn dự kiến (Sổ sách)
            6: FlexColumnWidth(1.2), // Tồn thực tế (Kiểm kê)
            7: FlexColumnWidth(1.1), // Chênh lệch
            8: FlexColumnWidth(1.0), // Tỷ lệ (%)
            9: FlexColumnWidth(1.3), // Trạng thái đối soát
            10: FlexColumnWidth(0.8), // Thao tác
          },
          children: [
            // Table Header
            TableRow(
              decoration: BoxDecoration(color: c.bgCardElevated),
              children: [
                _headerCell('STT', c, align: TextAlign.center),
                _headerCell('MÃ SKU', c),
                _headerCell('TÊN SẢN PHẨM / QUY CÁCH', c),
                _headerCell('ĐVT', c, align: TextAlign.center),
                _headerCell('VỊ TRÍ LƯU KHO', c),
                _headerCell('DỰ KIẾN (SỔ SÁCH)', c, align: TextAlign.center),
                _headerCell('THỰC TẾ (KIỂM KÊ)', c, align: TextAlign.center),
                _headerCell('CHÊNH LỆCH', c, align: TextAlign.center),
                _headerCell('TỶ LỆ', c, align: TextAlign.center),
                _headerCell('TRẠNG THÁI', c, align: TextAlign.center),
                _headerCell('CHIP', c, align: TextAlign.center),
              ],
            ),

            // Rows
            ...rows.asMap().entries.map((entry) {
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
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
                    child: Center(child: _buildStatusPill(r.statusLabel, diffColor)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
                    child: Center(
                      child: IconButton(
                        tooltip: 'Xem danh sách thẻ chip RFID của mặt hàng này',
                        icon: Icon(Icons.nfc_rounded, size: 18, color: c.rfidCyan),
                        onPressed: () => _showSkuItemTagsDialog(r, c),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
