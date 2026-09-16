import 'dart:io';
import 'package:flutter/material.dart';
import '../../services/report_export_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';

/// Màn hình Báo Cáo Kho — Trung tâm xuất 5 loại báo cáo (Excel / CSV)
class DesktopReportView extends StatefulWidget {
  const DesktopReportView({super.key});

  @override
  State<DesktopReportView> createState() => _DesktopReportViewState();
}

class _DesktopReportViewState extends State<DesktopReportView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final ReportExportService _exportService = ReportExportService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  final Map<ReportType, ReportFormat> _selectedFormats = {
    for (final t in ReportType.values) t: ReportFormat.xlsx,
  };
  final Map<ReportType, bool> _isExporting = {
    for (final t in ReportType.values) t: false,
  };
  final Map<ReportType, String?> _lastExportPath = {};

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onDataChanged);
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _repo.removeListener(_onDataChanged);
    super.dispose();
  }

  Future<void> _exportReport(ReportType type) async {
    setState(() => _isExporting[type] = true);

    try {
      final file = await _exportService.exportReport(type, _selectedFormats[type]!);
      if (mounted) {
        setState(() {
          _isExporting[type] = false;
          _lastExportPath[type] = file.path;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF047857),
            content: Text('✅ Xuất báo cáo ${type.label} thành công!'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting[type] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('❌ Lỗi xuất báo cáo: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _openFileInExplorer(String filePath) async {
    if (Platform.isWindows) {
      await Process.run('explorer.exe', ['/select,', filePath]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.rfidCyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
                ),
                child: Icon(Icons.assessment_rounded, color: c.rfidCyan, size: 24),
              ),
              const SizedBox(width: 14),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trung Tâm Báo Cáo',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Xuất dữ liệu kho sang Excel (.xlsx) hoặc CSV (.csv)',
                    style: TextStyle(color: c.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Report Cards Grid
          Expanded(
            child: SingleChildScrollView(
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: ReportType.values.map((type) => _buildReportCard(type, c)).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(ReportType type, EyeCareColors c) {
    final recordCount = _exportService.getRecordCount(type);
    final isExporting = _isExporting[type] ?? false;
    final lastPath = _lastExportPath[type];
    final selectedFormat = _selectedFormats[type]!;

    final cardInfo = _getCardInfo(type);

    return Container(
      width: 380,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon + Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: cardInfo.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: cardInfo.color.withValues(alpha: 0.3)),
                ),
                child: Icon(cardInfo.icon, color: cardInfo.color, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Báo Cáo ${type.label}',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cardInfo.description,
                      style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Record count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storage_rounded, color: c.textMuted, size: 13),
                const SizedBox(width: 6),
                Text(
                  '$recordCount bản ghi',
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Format selector + Export button
          Row(
            children: [
              // Format dropdown
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ReportFormat>(
                    value: selectedFormat,
                    dropdownColor: c.bgCard,
                    style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    icon: Icon(Icons.arrow_drop_down, color: c.textSecondary, size: 18),
                    isDense: true,
                    items: const [
                      DropdownMenuItem(value: ReportFormat.xlsx, child: Text('Excel (.xlsx)')),
                      DropdownMenuItem(value: ReportFormat.csv, child: Text('CSV (.csv)')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _selectedFormats[type] = v);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Export button
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: isExporting || recordCount == 0 ? null : () => _exportReport(type),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.rfidCyan,
                    disabledBackgroundColor: c.bgCardElevated,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: isExporting
                      ? const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.file_download_rounded, size: 16),
                  label: Text(
                    isExporting ? 'ĐANG XUẤT...' : 'XUẤT BÁO CÁO',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.5),
                  ),
                ),
              ),
            ],
          ),

          // Last export path
          if (lastPath != null) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => _openFileInExplorer(lastPath),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: const Color(0xFF047857).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF047857).withValues(alpha: 0.25)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: Color(0xFF047857), size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        lastPath.split(Platform.pathSeparator).last,
                        style: const TextStyle(
                          color: Color(0xFF047857),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.folder_open_rounded, color: c.textMuted, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      'Mở',
                      style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  _ReportCardInfo _getCardInfo(ReportType type) {
    switch (type) {
      case ReportType.inbound:
        return _ReportCardInfo(
          icon: Icons.input_rounded,
          color: const Color(0xFF0284C7),
          description: 'Danh sách đơn nhập, chi tiết RFID, trạng thái đối soát',
        );
      case ReportType.outbound:
        return _ReportCardInfo(
          icon: Icons.output_rounded,
          color: const Color(0xFF7C3AED),
          description: 'Danh sách đơn xuất, phiếu giao hàng, đối soát FIFO',
        );
      case ReportType.inventory:
        return _ReportCardInfo(
          icon: Icons.inventory_2_outlined,
          color: const Color(0xFF047857),
          description: 'Toàn bộ hàng tồn kho theo SKU / Pallet / Vị trí kệ',
        );
      case ReportType.audit:
        return _ReportCardInfo(
          icon: Icons.fact_check_outlined,
          color: const Color(0xFFB45309),
          description: 'Kết quả phiên kiểm kê, sai lệch, thẻ lạ',
        );
      case ReportType.transactionLog:
        return _ReportCardInfo(
          icon: Icons.history_rounded,
          color: const Color(0xFF64748B),
          description: 'Lịch sử nhập / xuất / di chuyển kho',
        );
    }
  }
}

class _ReportCardInfo {
  final IconData icon;
  final Color color;
  final String description;

  const _ReportCardInfo({
    required this.icon,
    required this.color,
    required this.description,
  });
}
