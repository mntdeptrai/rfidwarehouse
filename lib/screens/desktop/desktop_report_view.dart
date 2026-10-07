import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/wms_models.dart';
import '../../services/report_export_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';
import 'desktop_stock_reconciliation_view.dart';
import 'desktop_audit_ticket_detail_view.dart';
import '../../widgets/tag_lifecycle_timeline_dialog.dart';

/// Màn hình Báo Cáo Tồn Kho RFID — Tra cứu và trích xuất danh sách tồn kho theo Số Seri (SN)
class DesktopReportView extends StatefulWidget {
  const DesktopReportView({super.key});

  @override
  State<DesktopReportView> createState() => _DesktopReportViewState();
}

class _DesktopReportViewState extends State<DesktopReportView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final ReportExportService _exportService = ReportExportService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  // Tab chuyển đổi: 0 = Danh Sách Hàng Tồn (IN_STOCK), 1 = Đối Soát Tồn Kho (Dự Kiến vs Thực Tế)
  int _selectedReportTab = 0;
  InventorySession? _selectedSessionDetail;

  ReportFormat _selectedFormat = ReportFormat.xlsx;
  bool _isExporting = false;
  String? _lastExportPath;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // Business operation report state
  ReportType _selectedBusinessType = ReportType.inbound;
  DateTime? _filterFromDate;
  DateTime? _filterToDate;
  String _periodPreset = 'ALL';
  final TextEditingController _businessSearchCtrl = TextEditingController();
  String _businessSearchQuery = '';
  ReportFormat _businessExportFormat = ReportFormat.xlsx;
  bool _isBusinessExporting = false;

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onDataChanged);
    _eyeCare.addListener(_onDataChanged);

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      unawaited(_repo.reloadFromDatabase());
    }
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _businessSearchCtrl.dispose();
    _eyeCare.removeListener(_onDataChanged);
    _repo.removeListener(_onDataChanged);
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

  /// Danh sách sản phẩm thực tế đang lưu kho (IN_STOCK)
  List<Item> get _inStockItems =>
      _repo.items.where((i) => i.status.code == 'IN_STOCK').toList();

  Future<void> _exportReport(List<Item> itemsToExport) async {
    if (itemsToExport.isEmpty) {
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFF59E0B),
          content: Text('⚠️ Không có mặt hàng nào để xuất báo cáo.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _isExporting = true);

    try {
      final file = await _exportService.exportInventoryReport(
        _selectedFormat,
        items: itemsToExport,
      );

      if (mounted) {
        setState(() {
          _isExporting = false;
          _lastExportPath = file.path;
        });

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF047857),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Đã trích xuất Báo Cáo Tồn Kho thành công (${itemsToExport.length} sản phẩm)!',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () => _openFileInExplorer(file.path),
                  child: const Text('MỞ THƯ MỤC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('❌ Lỗi xuất báo cáo tồn kho: $e'),
            duration: const Duration(seconds: 2),
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

  void _applyPeriodPreset(String preset) {
    final now = DateTime.now();
    setState(() {
      _periodPreset = preset;
      switch (preset) {
        case 'TODAY':
          _filterFromDate = DateTime(now.year, now.month, now.day);
          _filterToDate = DateTime(now.year, now.month, now.day);
          break;
        case '7D':
          _filterFromDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
          _filterToDate = DateTime(now.year, now.month, now.day);
          break;
        case '30D':
          _filterFromDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
          _filterToDate = DateTime(now.year, now.month, now.day);
          break;
        case 'MONTH':
          _filterFromDate = DateTime(now.year, now.month, 1);
          _filterToDate = DateTime(now.year, now.month, now.day);
          break;
        case 'ALL':
        default:
          _filterFromDate = null;
          _filterToDate = null;
          _periodPreset = 'ALL';
          break;
      }
    });
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final initialDate = isFrom
        ? (_filterFromDate ?? now)
        : (_filterToDate ?? _filterFromDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF10B981),
              onPrimary: Colors.white,
              surface: _eyeCare.colors.bgCard,
              onSurface: _eyeCare.colors.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _periodPreset = 'CUSTOM';
        if (isFrom) {
          _filterFromDate = picked;
          if (_filterToDate != null && _filterToDate!.isBefore(picked)) {
            _filterToDate = picked;
          }
        } else {
          _filterToDate = picked;
          if (_filterFromDate != null && _filterFromDate!.isAfter(picked)) {
            _filterFromDate = picked;
          }
        }
      });
    }
  }

  Future<void> _exportBusinessReport() async {
    setState(() => _isBusinessExporting = true);
    try {
      final file = await _exportService.exportReportSelected(
        _selectedBusinessType,
        _businessExportFormat,
        fromDate: _filterFromDate,
        toDate: _filterToDate,
      );

      if (mounted) {
        setState(() {
          _isBusinessExporting = false;
          _lastExportPath = file.path;
        });

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF047857),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Đã trích xuất ${_selectedBusinessType.label} thành công (${_businessExportFormat.name.toUpperCase()})!',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () => _openFileInExplorer(file.path),
                  child: const Text('MỞ THƯ MỤC', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isBusinessExporting = false);
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('❌ Lỗi xuất báo cáo nghiệp vụ: $e'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final allInStock = _inStockItems;

    // Lọc theo Số Seri (SN) hoặc từ khóa tìm kiếm
    var filteredItems = allInStock;

    // 2. Lọc theo Số Seri (SN) hoặc từ khóa tìm kiếm
    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      filteredItems = filteredItems.where((it) {
        final snMatch = it.serialNumber.toLowerCase().contains(q);
        final skuMatch = it.sku.toLowerCase().contains(q);
        final nameMatch = it.productName.toLowerCase().contains(q);
        final epcMatch = it.epc.toLowerCase().contains(q);
        final locMatch = (it.locationId ?? '').toLowerCase().contains(q);
        final palMatch = (it.palletId ?? '').toLowerCase().contains(q);
        final supMatch = it.supplierDisplay.toLowerCase().contains(q);
        final lcMatch = _repo.getTagLifecycleSummary(it.epc).toLowerCase().contains(q);
        return snMatch || skuMatch || nameMatch || epcMatch || locMatch || palMatch || supMatch || lcMatch;
      }).toList();
    }

    if (_selectedSessionDetail != null) {
      return Container(
        color: c.bgDeep,
        child: DesktopAuditTicketDetailView(
          session: _selectedSessionDetail!,
          onBack: () => setState(() => _selectedSessionDetail = null),
        ),
      );
    }

    if (_selectedReportTab == 1) {
      return Container(
        color: c.bgDeep,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderBar(c),
              const SizedBox(height: 12),
              Expanded(
                child: DesktopStockReconciliationView(
                  onOpenSessionDetail: (session) {
                    setState(() => _selectedSessionDetail = session);
                  },
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_selectedReportTab == 2) {
      return Container(
        color: c.bgDeep,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderBar(c),
              const SizedBox(height: 12),
              Expanded(
                child: _buildBusinessOperationsReportTab(c),
              ),
              if (_lastExportPath != null) ...[
                const SizedBox(height: 8),
                _buildLastExportBanner(c),
              ],
            ],
          ),
        ),
      );
    }

    return Container(
      color: c.bgDeep,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Header Bar
            _buildHeaderBar(c),

            const SizedBox(height: 12),

            // 2. Thanh Công Cụ & Tìm Kiếm Theo Số Seri (SN), SKU
            _buildActionToolbar(
              filteredItems: filteredItems,
              c: c,
            ),

            const SizedBox(height: 12),

            // 3. Bảng Dữ Liệu Tồn Kho Chi Tiết
            Expanded(
              child: _buildInventoryTable(
                filteredItems: filteredItems,
                totalInStock: allInStock.length,
                c: c,
              ),
            ),

            // 4. Thông báo tệp xuất gần nhất (nếu có)
            if (_lastExportPath != null) ...[
              const SizedBox(height: 8),
              _buildLastExportBanner(c),
            ],
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 1. HEADER BAR (RESPONSIVE)
  // ==========================================
  Widget _buildHeaderBar(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1360;
          final isUltraNarrow = constraints.maxWidth < 700;

          Widget buildTitleSection() {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                  ),
                  child: const Icon(Icons.inventory_2_rounded, color: Color(0xFF10B981), size: 22),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Text(
                            'BÁO CÁO TỒN KHO',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: c.textPrimary,
                              letterSpacing: 0.4,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF047857).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFF047857).withValues(alpha: 0.3)),
                            ),
                            child: const Text(
                              'RFID WMS',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF10B981),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tra cứu danh sách hàng hóa tồn kho và trích xuất báo cáo theo nghiệp vụ',
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          Widget buildTabs() {
            return Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildReportTabButton(0, Icons.inventory_2_outlined, 'Danh Sách Hàng Tồn', c),
                  const SizedBox(width: 4),
                  _buildReportTabButton(1, Icons.balance_rounded, 'Đối Soát Tồn Kho (Dự Kiến vs Thực Tế)', c),
                  const SizedBox(width: 4),
                  _buildReportTabButton(2, Icons.analytics_rounded, 'Báo Cáo Nghiệp Vụ', c),
                ],
              ),
            );
          }

          Widget buildRefreshButton() {
            return OutlinedButton.icon(
              onPressed: () async {
                await _repo.reloadFromDatabase();
                if (!mounted) return;
                ScaffoldMessenger.of(this.context).hideCurrentSnackBar();
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Color(0xFF10B981),
                    content: Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text(
                          '✓ Đã đồng bộ và làm mới dữ liệu từ Supabase Cloud!',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: Icon(Icons.refresh_rounded, size: 16, color: c.textSecondary),
              label: Text(
                'LÀM MỚI DỮ LIỆU',
                style: TextStyle(fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.w600),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.border),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            );
          }

          if (isWide) {
            // Màn hình rộng (>= 1360px): Hiển thị gọn trên 1 hàng ngang duy nhất
            return Row(
              children: [
                Expanded(child: buildTitleSection()),
                const SizedBox(width: 12),
                buildTabs(),
                const SizedBox(width: 12),
                buildRefreshButton(),
              ],
            );
          }

          // Màn hình tiêu chuẩn (< 1360px): Chia làm 2 hàng thoáng đãng, co giãn 100% không bị khuất
          Widget responsiveLayout = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(child: buildTitleSection()),
                  const SizedBox(width: 12),
                  buildRefreshButton(),
                ],
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: buildTabs(),
              ),
            ],
          );

          if (isUltraNarrow) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 700,
                child: responsiveLayout,
              ),
            );
          }

          return responsiveLayout;
        },
      ),
    );
  }

  Widget _buildReportTabButton(int index, IconData icon, String label, EyeCareColors c) {
    final isSelected = _selectedReportTab == index;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _selectedReportTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? const Color(0xFF10B981) : Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? const Color(0xFF10B981) : c.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF10B981) : c.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // 2. ACTION TOOLBAR & SEARCH CONTROLS
  // ==========================================
  Widget _buildActionToolbar({
    required List<Item> filteredItems,
    required EyeCareColors c,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: math.max(0, constraints.maxWidth)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Cụm điều khiển tìm kiếm (bên trái)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Ô Tìm Kiếm Số Seri (SN), SKU, Kệ đơn giản & trực quan
                      Container(
                        width: 320,
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: c.bgDeep,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _searchQuery.isNotEmpty ? const Color(0xFF10B981) : c.border,
                            width: _searchQuery.isNotEmpty ? 1.4 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.search_rounded,
                              size: 18,
                              color: _searchQuery.isNotEmpty ? const Color(0xFF10B981) : c.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: (val) => setState(() => _searchQuery = val),
                                style: TextStyle(fontSize: 13, color: c.textPrimary, fontWeight: FontWeight.w500),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'Tìm kiếm Số Seri (SN), SKU, vị trí kệ...',
                                  hintStyle: TextStyle(fontSize: 12, color: c.textSecondary.withValues(alpha: 0.7)),
                                  border: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                              ),
                            ),
                            if (_searchQuery.isNotEmpty)
                              GestureDetector(
                                onTap: () {
                                  _searchCtrl.clear();
                                  setState(() => _searchQuery = '');
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(4.0),
                                  child: Icon(Icons.clear_rounded, size: 16, color: c.textSecondary),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(width: 16),

                  // Cụm xuất báo cáo (bên phải)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 4. Chọn định dạng file xuất
                      Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        decoration: BoxDecoration(
                          color: c.bgDeep,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.border),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<ReportFormat>(
                            value: _selectedFormat,
                            dropdownColor: c.bgCard,
                            icon: Icon(Icons.arrow_drop_down_rounded, color: c.textSecondary),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary),
                            items: const [
                              DropdownMenuItem(
                                value: ReportFormat.xlsx,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.table_chart_rounded, size: 15, color: Color(0xFF10B981)),
                                    SizedBox(width: 6),
                                    Text('Excel (.xlsx)'),
                                  ],
                                ),
                              ),
                              DropdownMenuItem(
                                value: ReportFormat.csv,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.description_rounded, size: 15, color: Color(0xFF3B82F6)),
                                    SizedBox(width: 6),
                                    Text('CSV (.csv)'),
                                  ],
                                ),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedFormat = val);
                            },
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      // 5. Nút Xuất Báo Cáo
                      ElevatedButton.icon(
                        onPressed: _isExporting ? null : () => _exportReport(filteredItems),
                        icon: _isExporting
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.file_download_rounded, size: 18, color: Colors.white),
                        label: Text(
                          _isExporting ? 'ĐANG XUẤT...' : 'XUẤT BÁO CÁO (${filteredItems.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.3, color: Colors.white),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF047857),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ==========================================
  // 3. BẢNG DỮ LIỆU TỒN KHO (CÓ CỘT SỐ SERI SN)
  // ==========================================
  Widget _buildInventoryTable({
    required List<Item> filteredItems,
    required int totalInStock,
    required EyeCareColors c,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LayoutBuilder(
          builder: (context, constraints) {
            const minTableWidth = 1548.0;
            final tableWidth = math.max(constraints.maxWidth, minTableWidth);

            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                height: constraints.maxHeight,
                child: Column(
                  children: [
                    // Tiêu đề các cột
                    Container(
                      height: 42,
                      color: c.bgDeep,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          _headerCell('STT', 45, Alignment.center, c),
                          _headerCell('SỐ SERI (SN)', 140, Alignment.centerLeft, c),
                          _headerCell('MÃ SKU', 110, Alignment.centerLeft, c),
                          _headerCell('TÊN HÀNG HÓA', 170, Alignment.centerLeft, c),
                          _headerCell('MÃ CHIP RFID (EPC)', 160, Alignment.centerLeft, c),
                          _headerCell('VỊ TRÍ KỆ', 95, Alignment.centerLeft, c),
                          _headerCell('MÃ PALLET', 95, Alignment.centerLeft, c),
                          _headerCell('NGÀY NHẬP KHO', 105, Alignment.center, c),
                          _headerCell('NHÀ CUNG CẤP', 120, Alignment.centerLeft, c),
                          _headerCell('TRẠNG THÁI', 100, Alignment.center, c),
                          _headerCell('VÒNG ĐỜI THẺ', 380, Alignment.centerLeft, c),
                        ],
                      ),
                    ),

                    const Divider(height: 1, thickness: 1),

                    // Dòng dữ liệu hoặc Trạng thái rỗng
                    Expanded(
                      child: filteredItems.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.search_off_rounded, size: 54, color: c.textSecondary.withValues(alpha: 0.4)),
                                    const SizedBox(height: 14),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? 'Không tìm thấy sản phẩm tồn kho nào khớp với Số Seri: "$_searchQuery"'
                                          : 'Kho chưa có sản phẩm nào ở trạng thái Lưu Kho (IN_STOCK).',
                                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.textPrimary),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Vui lòng kiểm tra lại Số Seri (SN), mã SKU hoặc thử xóa bộ lọc tìm kiếm.',
                                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                                    ),
                                    if (_searchQuery.isNotEmpty) ...[
                                      const SizedBox(height: 14),
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() {
                                            _searchQuery = '';
                                          });
                                        },
                                        icon: const Icon(Icons.clear_all_rounded, size: 16),
                                        label: const Text('XÓA BỘ LỌC TÌM KIẾM'),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFF10B981),
                                          side: const BorderSide(color: Color(0xFF10B981)),
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            )
                          : ListView.separated(
                              itemCount: filteredItems.length,
                              separatorBuilder: (_, _) => Divider(height: 1, thickness: 0.6, color: c.border.withValues(alpha: 0.6)),
                              itemBuilder: (context, index) {
                                final it = filteredItems[index];
                                final isEven = index % 2 == 0;

                                String palletDisplay = '--';
                                if (it.palletId != null && it.palletId!.isNotEmpty) {
                                  final pallet = _repo.pallets.where((p) => p.palletId == it.palletId || p.palletCode == it.palletId).toList();
                                  palletDisplay = pallet.isNotEmpty ? pallet.first.displayName : it.palletId!;
                                }

                                return Container(
                                  height: 46,
                                  color: isEven ? Colors.transparent : c.bgDeep.withValues(alpha: 0.35),
                                  padding: const EdgeInsets.symmetric(horizontal: 14),
                                  child: Row(
                                    children: [
                                      // 1. STT
                                      SizedBox(
                                        width: 45,
                                        child: Center(
                                          child: Text(
                                            '${index + 1}',
                                            style: TextStyle(fontSize: 12, color: c.textSecondary),
                                          ),
                                        ),
                                      ),

                                      // 2. SỐ SERI (SN) - Nổi bật
                                      SizedBox(
                                        width: 140,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                            ),
                                            child: Text(
                                              it.serialNumber.isNotEmpty ? it.serialNumber : '--',
                                              style: const TextStyle(
                                                fontFamily: 'monospace',
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF10B981),
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ),

                                      // 3. MÃ SKU
                                      SizedBox(
                                        width: 110,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            it.sku,
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                              color: c.textPrimary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),

                                      // 4. TÊN HÀNG HÓA
                                      SizedBox(
                                        width: 170,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            it.productName,
                                            style: TextStyle(fontSize: 12, color: c.textPrimary),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),

                                      // 5. MÃ CHIP RFID (EPC)
                                      SizedBox(
                                        width: 160,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            it.epc,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                              color: c.rfidCyan,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),

                                      // 6. VỊ TRÍ KỆ
                                      SizedBox(
                                        width: 95,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: c.bgDeep,
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: c.border),
                                            ),
                                            child: Text(
                                              it.locationId != null && it.locationId!.isNotEmpty ? it.locationId! : 'Chưa xếp kệ',
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                fontWeight: FontWeight.w600,
                                                color: it.locationId != null ? const Color(0xFF3B82F6) : c.textSecondary,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ),
                                      ),

                                      // 7. MÃ PALLET
                                      SizedBox(
                                        width: 95,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            palletDisplay,
                                            style: TextStyle(fontSize: 11.5, color: c.textPrimary),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),

                                      // 8. NGÀY NHẬP KHO
                                      SizedBox(
                                        width: 105,
                                        child: Center(
                                          child: Text(
                                            _formatDateTime(it.inboundTime),
                                            style: TextStyle(fontSize: 11.5, color: c.textSecondary),
                                          ),
                                        ),
                                      ),

                                      // 9. NHÀ CUNG CẤP
                                      SizedBox(
                                        width: 120,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            it.supplierDisplay,
                                            style: TextStyle(fontSize: 11.5, color: c.textSecondary),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ),

                                      // 10. TRẠNG THÁI
                                      SizedBox(
                                        width: 100,
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF047857).withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: const Color(0xFF047857).withValues(alpha: 0.3)),
                                            ),
                                            child: const Text(
                                              'Đang tồn kho',
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF10B981),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),

                                      // 11. VÒNG ĐỜI THẺ (Nhấn để xem timeline chi tiết)
                                      SizedBox(
                                        width: 380,
                                        child: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Tooltip(
                                            message: 'Nhấn để xem chi tiết lịch sử vòng đời thẻ RFID',
                                            child: InkWell(
                                              onTap: () => TagLifecycleTimelineDialog.show(context, epc: it.epc, item: it),
                                              borderRadius: BorderRadius.circular(4),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: c.bgDeep,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: c.border),
                                                ),
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.history_rounded, size: 13, color: Color(0xFF10B981)),
                                                    const SizedBox(width: 4),
                                                    Expanded(
                                                      child: Text(
                                                        _repo.getTagLifecycleSummary(it.epc),
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          color: c.textPrimary,
                                                          fontWeight: FontWeight.w500,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
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
            );
          },
        ),
      ),
    );
  }

  Widget _headerCell(String title, double width, Alignment alignment, EyeCareColors c) {
    return SizedBox(
      width: width,
      child: Align(
        alignment: alignment,
        child: Text(
          title,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: c.textSecondary,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }

  // ==========================================
  // 6. LAST EXPORT BANNER
  // ==========================================
  Widget _buildLastExportBanner(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF047857).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF047857).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tệp xuất gần nhất: $_lastExportPath',
              style: TextStyle(fontSize: 12, color: c.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton.icon(
            onPressed: () => _openFileInExplorer(_lastExportPath!),
            icon: const Icon(Icons.folder_open_rounded, size: 16, color: Color(0xFF10B981)),
            label: const Text('MỞ THƯ MỤC', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF10B981))),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // 7. BÁO CÁO NGHIỆP VỤ (NHẬP - XUẤT - TỒN - BIẾN ĐỘNG)
  // ==========================================
  Widget _buildBusinessOperationsReportTab(EyeCareColors c) {
    final start = _filterFromDate != null ? DateTime(_filterFromDate!.year, _filterFromDate!.month, _filterFromDate!.day, 0, 0, 0) : null;
    final end = _filterToDate != null ? DateTime(_filterToDate!.year, _filterToDate!.month, _filterToDate!.day, 23, 59, 59, 999) : null;
    final q = _businessSearchQuery.trim().toLowerCase();

    List<InboundOrder> filteredInbounds = [];
    List<OutboundOrder> filteredOutbounds = [];
    List<Item> filteredInventory = [];
    List<InventoryTransaction> filteredTransactions = [];

    int filteredCount = 0;
    int totalSystemCount = 0;

    switch (_selectedBusinessType) {
      case ReportType.inbound:
        totalSystemCount = _repo.inboundOrders.length;
        var list = _repo.inboundOrders;
        if (start != null) list = list.where((o) => o.createdAt.isAfter(start) || o.createdAt.isAtSameMomentAs(start)).toList();
        if (end != null) list = list.where((o) => o.createdAt.isBefore(end) || o.createdAt.isAtSameMomentAs(end)).toList();
        if (q.isNotEmpty) {
          list = list.where((o) {
            final idMatch = o.inboundOrderId.toLowerCase().contains(q);
            final noMatch = o.orderNo.toLowerCase().contains(q);
            final supMatch = o.sourceSupplier.toLowerCase().contains(q);
            final skuMatch = o.details.any((d) => d.sku.toLowerCase().contains(q) || d.productName.toLowerCase().contains(q));
            return idMatch || noMatch || supMatch || skuMatch;
          }).toList();
        }
        filteredInbounds = list;
        filteredCount = list.length;
        break;

      case ReportType.outbound:
        totalSystemCount = _repo.outboundOrders.length;
        var list = _repo.outboundOrders;
        if (start != null) list = list.where((o) => o.createdAt.isAfter(start) || o.createdAt.isAtSameMomentAs(start)).toList();
        if (end != null) list = list.where((o) => o.createdAt.isBefore(end) || o.createdAt.isAtSameMomentAs(end)).toList();
        if (q.isNotEmpty) {
          list = list.where((o) {
            final idMatch = o.outboundOrderId.toLowerCase().contains(q);
            final poMatch = o.poNo.toLowerCase().contains(q);
            final cusMatch = o.customer.toLowerCase().contains(q);
            final skuMatch = o.details.any((d) => d.sku.toLowerCase().contains(q) || d.productName.toLowerCase().contains(q));
            return idMatch || poMatch || cusMatch || skuMatch;
          }).toList();
        }
        filteredOutbounds = list;
        filteredCount = list.length;
        break;

      case ReportType.inventory:
        final allStock = _repo.items.where((i) => i.status.code == 'IN_STOCK').toList();
        totalSystemCount = allStock.length;
        var list = allStock;
        if (start != null) list = list.where((i) => i.inboundTime == null || i.inboundTime!.isAfter(start) || i.inboundTime!.isAtSameMomentAs(start)).toList();
        if (end != null) list = list.where((i) => i.inboundTime == null || i.inboundTime!.isBefore(end) || i.inboundTime!.isAtSameMomentAs(end)).toList();
        if (q.isNotEmpty) {
          list = list.where((i) {
            final snMatch = i.serialNumber.toLowerCase().contains(q);
            final skuMatch = i.sku.toLowerCase().contains(q);
            final nameMatch = i.productName.toLowerCase().contains(q);
            final epcMatch = i.epc.toLowerCase().contains(q);
            final locMatch = (i.locationId ?? '').toLowerCase().contains(q);
            final palMatch = (i.palletId ?? '').toLowerCase().contains(q);
            return snMatch || skuMatch || nameMatch || epcMatch || locMatch || palMatch;
          }).toList();
        }
        filteredInventory = list;
        filteredCount = list.length;
        break;

      case ReportType.transactionLog:
        totalSystemCount = _repo.transactions.length;
        var list = _repo.transactions;
        if (start != null) list = list.where((t) => t.timestamp.isAfter(start) || t.timestamp.isAtSameMomentAs(start)).toList();
        if (end != null) list = list.where((t) => t.timestamp.isBefore(end) || t.timestamp.isAtSameMomentAs(end)).toList();
        if (q.isNotEmpty) {
          list = list.where((t) {
            final docMatch = t.documentNo.toLowerCase().contains(q);
            final skuMatch = t.sku.toLowerCase().contains(q);
            final nameMatch = t.productName.toLowerCase().contains(q);
            final actMatch = t.performedBy.toLowerCase().contains(q);
            final noteMatch = (t.notes ?? '').toLowerCase().contains(q);
            return docMatch || skuMatch || nameMatch || actMatch || noteMatch;
          }).toList();
        }
        filteredTransactions = list;
        filteredCount = list.length;
        break;

      case ReportType.audit:
        // Audit sessionshandled in reconciliation view
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Selector 4 Nghiệp vụ chính (Nhập, Xuất, Tồn, Biến Động)
        _buildBusinessTypeSelector(c),

        const SizedBox(height: 10),

        // 2. Bộ Lọc Thời Điểm / Giai Đoạn (Preset + Date Picker)
        _buildPeriodFilterBar(c),

        const SizedBox(height: 10),

        // 3. Toolbar Tìm Kiếm & Nút Trích Xuất Báo Cáo
        _buildBusinessToolbar(c, filteredCount),

        const SizedBox(height: 10),

        // 4. Bảng Preview Dữ Liệu
        Expanded(
          child: _buildBusinessPreviewContent(
            c: c,
            filteredInbounds: filteredInbounds,
            filteredOutbounds: filteredOutbounds,
            filteredInventory: filteredInventory,
            filteredTransactions: filteredTransactions,
            filteredCount: filteredCount,
            totalSystemCount: totalSystemCount,
          ),
        ),
      ],
    );
  }

  Widget _buildBusinessTypeSelector(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 900;
          final items = [
            _buildBusinessTypeTab(ReportType.inbound, Icons.move_to_inbox_rounded, 'Nhập Kho', const Color(0xFF0284C7), c),
            _buildBusinessTypeTab(ReportType.outbound, Icons.outbox_rounded, 'Xuất Kho', const Color(0xFFEA580C), c),
            _buildBusinessTypeTab(ReportType.inventory, Icons.inventory_2_rounded, 'Tồn Kho', const Color(0xFF10B981), c),
            _buildBusinessTypeTab(ReportType.transactionLog, Icons.history_rounded, 'Biến Động Kho', const Color(0xFF8B5CF6), c),
          ];

          if (isNarrow) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: items.map((w) => Padding(padding: const EdgeInsets.only(right: 6), child: w)).toList(),
              ),
            );
          }
          return Row(
            children: items.map((w) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 3), child: w))).toList(),
          );
        },
      ),
    );
  }

  Widget _buildBusinessTypeTab(ReportType type, IconData icon, String label, Color accentColor, EyeCareColors c) {
    final isSelected = _selectedBusinessType == type;
    final count = _exportService.getRecordCount(type, fromDate: _filterFromDate, toDate: _filterToDate);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        setState(() {
          _selectedBusinessType = type;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? accentColor.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accentColor : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: isSelected ? accentColor : c.textSecondary),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                color: isSelected ? accentColor : c.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? accentColor : c.bgDeep,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : c.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodFilterBar(EyeCareColors c) {
    final dateFormat = DateFormat('dd/MM/yyyy');
    final fromStr = _filterFromDate != null ? dateFormat.format(_filterFromDate!) : 'Từ ngày';
    final toStr = _filterToDate != null ? dateFormat.format(_filterToDate!) : 'Đến ngày';
    final periodDesc = _exportService.formatPeriodSubtitle(_filterFromDate, _filterToDate);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range_rounded, size: 18, color: c.textSecondary),
            const SizedBox(width: 8),
            Text(
              'Thời điểm / Giai đoạn:',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.textSecondary),
            ),
            const SizedBox(width: 10),
            // Preset chips
            _buildPresetChip('Hôm nay', 'TODAY', c),
            const SizedBox(width: 4),
            _buildPresetChip('7 ngày qua', '7D', c),
            const SizedBox(width: 4),
            _buildPresetChip('30 ngày qua', '30D', c),
            const SizedBox(width: 4),
            _buildPresetChip('Tháng này', 'MONTH', c),
            const SizedBox(width: 4),
            _buildPresetChip('Tất cả', 'ALL', c),
            const SizedBox(width: 12),
            // Custom Date Pickers
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _pickDate(isFrom: true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.bgDeep,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _filterFromDate != null ? const Color(0xFF10B981) : c.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 13, color: _filterFromDate != null ? const Color(0xFF10B981) : c.textSecondary),
                    const SizedBox(width: 6),
                    Text(fromStr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _filterFromDate != null ? c.textPrimary : c.textSecondary)),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Text('→', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => _pickDate(isFrom: false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: c.bgDeep,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: _filterToDate != null ? const Color(0xFF10B981) : c.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 13, color: _filterToDate != null ? const Color(0xFF10B981) : c.textSecondary),
                    const SizedBox(width: 6),
                    Text(toStr, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _filterToDate != null ? c.textPrimary : c.textSecondary)),
                  ],
                ),
              ),
            ),
            if (_filterFromDate != null || _filterToDate != null) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Đặt lại khoảng thời gian',
                onPressed: () => _applyPeriodPreset('ALL'),
                icon: const Icon(Icons.clear_rounded, size: 16),
                color: c.textSecondary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              ),
            ],
            const SizedBox(width: 16),
            // Subtitle tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.bgDeep,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border),
              ),
              child: Text(
                periodDesc,
                style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: c.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip(String label, String code, EyeCareColors c) {
    final isSelected = _periodPreset == code;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () => _applyPeriodPreset(code),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.15) : c.bgDeep,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981) : c.border,
            width: isSelected ? 1.4 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? const Color(0xFF10B981) : c.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildBusinessToolbar(EyeCareColors c, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 800;
          final content = Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Search text field
              Container(
                width: 320,
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.bgDeep,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _businessSearchQuery.isNotEmpty ? const Color(0xFF10B981) : c.border,
                    width: _businessSearchQuery.isNotEmpty ? 1.4 : 1.0,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: _businessSearchQuery.isNotEmpty ? const Color(0xFF10B981) : c.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _businessSearchCtrl,
                        onChanged: (val) => setState(() => _businessSearchQuery = val),
                        style: TextStyle(fontSize: 13, color: c.textPrimary, fontWeight: FontWeight.w500),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: 'Tìm kiếm theo mã đơn, SKU, sản phẩm...',
                          hintStyle: TextStyle(fontSize: 12, color: c.textSecondary.withValues(alpha: 0.7)),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    if (_businessSearchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _businessSearchCtrl.clear();
                          setState(() => _businessSearchQuery = '');
                        },
                        child: Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(Icons.close_rounded, size: 16, color: c.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),

              const SizedBox(width: 12),

              // Export Controls
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Format Selector (Excel / CSV)
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: c.bgDeep,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<ReportFormat>(
                        value: _businessExportFormat,
                        icon: Icon(Icons.arrow_drop_down_rounded, color: c.textSecondary),
                        dropdownColor: c.bgCard,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary),
                        onChanged: (fmt) {
                          if (fmt != null) setState(() => _businessExportFormat = fmt);
                        },
                        items: const [
                          DropdownMenuItem(
                            value: ReportFormat.xlsx,
                            child: Row(
                              children: [
                                Icon(Icons.table_chart_rounded, size: 16, color: Color(0xFF10B981)),
                                SizedBox(width: 6),
                                Text('Excel (.xlsx)'),
                              ],
                            ),
                          ),
                          DropdownMenuItem(
                            value: ReportFormat.csv,
                            child: Row(
                              children: [
                                Icon(Icons.article_rounded, size: 16, color: Color(0xFF0284C7)),
                                SizedBox(width: 6),
                                Text('CSV (.csv)'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Nút Trích Xuất Báo Cáo
                  ElevatedButton.icon(
                    onPressed: _isBusinessExporting ? null : _exportBusinessReport,
                    icon: _isBusinessExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download_rounded, size: 18, color: Colors.white),
                    label: Text(
                      _isBusinessExporting ? 'ĐANG KẾT XUẤT...' : 'TRÍCH XUẤT BÁO CÁO',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      disabledBackgroundColor: const Color(0xFF10B981).withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                  ),
                ],
              ),
            ],
          );

          if (isNarrow) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: 800,
                child: content,
              ),
            );
          }
          return content;
        },
      ),
    );
  }

  Widget _buildBusinessPreviewContent({
    required EyeCareColors c,
    required List<InboundOrder> filteredInbounds,
    required List<OutboundOrder> filteredOutbounds,
    required List<Item> filteredInventory,
    required List<InventoryTransaction> filteredTransactions,
    required int filteredCount,
    required int totalSystemCount,
  }) {
    switch (_selectedBusinessType) {
      case ReportType.inbound:
        return _buildInboundPreviewTable(filteredInbounds, c);
      case ReportType.outbound:
        return _buildOutboundPreviewTable(filteredOutbounds, c);
      case ReportType.inventory:
        return _buildInventoryPreviewTable(filteredInventory, c);
      case ReportType.transactionLog:
        return _buildTransactionPreviewTable(filteredTransactions, c);
      case ReportType.audit:
        return _buildEmptyPreview(c, 'Chế độ đối soát kiểm kê hiển thị tại Tab Đối Soát Tồn Kho.');
    }
  }

  // ==========================================
  // 8. BẢNG PREVIEW: ĐƠN NHẬP KHO
  // ==========================================
  Widget _buildInboundPreviewTable(List<InboundOrder> orders, EyeCareColors c) {
    if (orders.isEmpty) {
      return _buildEmptyPreview(c, 'Không có đơn nhập kho nào phù hợp trong giai đoạn đã chọn.');
    }

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          _buildTableHeader(
            c,
            [
              const TableColumn(title: 'STT', width: 60),
              const TableColumn(title: 'MÃ ĐƠN NHẬP', width: 140),
              const TableColumn(title: 'NHÀ CUNG CẤP', flex: 2),
              const TableColumn(title: 'NGÀY TẠO', width: 150),
              const TableColumn(title: 'SỐ SKU', width: 90),
              const TableColumn(title: 'SL KỲ VỌNG', width: 110),
              const TableColumn(title: 'ĐÃ NHẬN', width: 100),
              const TableColumn(title: 'TRẠNG THÁI', width: 140),
            ],
          ),
          Expanded(
            child: ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
              itemBuilder: (context, idx) {
                final ord = orders[idx];
                final reqQty = ord.details.fold<int>(0, (s, d) => s + d.requiredQty);
                final recQty = ord.details.fold<int>(0, (s, d) => s + d.receivedQty);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(width: 60, child: Text('${idx + 1}', style: TextStyle(fontSize: 12, color: c.textSecondary))),
                      SizedBox(
                        width: 140,
                        child: Text(
                          ord.orderNo,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          ord.sourceSupplier.isNotEmpty ? ord.sourceSupplier : 'Nhà cung cấp',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 150, child: Text(_formatDateTime(ord.createdAt), style: TextStyle(fontSize: 12, color: c.textSecondary))),
                      SizedBox(width: 90, child: Text('${ord.details.length} SKU', style: TextStyle(fontSize: 12, color: c.textPrimary))),
                      SizedBox(width: 110, child: Text('$reqQty cái', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary))),
                      SizedBox(
                        width: 100,
                        child: Text(
                          '$recQty cái',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: recQty >= reqQty ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _buildStatusBadge(ord.status.label, ord.status == InboundOrderStatus.completed ? const Color(0xFF10B981) : const Color(0xFF0284C7), c),
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
    );
  }

  // ==========================================
  // 9. BẢNG PREVIEW: ĐƠN XUẤT KHO
  // ==========================================
  Widget _buildOutboundPreviewTable(List<OutboundOrder> orders, EyeCareColors c) {
    if (orders.isEmpty) {
      return _buildEmptyPreview(c, 'Không có đơn xuất kho nào phù hợp trong giai đoạn đã chọn.');
    }

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          _buildTableHeader(
            c,
            [
              const TableColumn(title: 'STT', width: 60),
              const TableColumn(title: 'MÃ PO XUẤT', width: 140),
              const TableColumn(title: 'KHÁCH HÀNG / ĐIỂM ĐẾN', flex: 2),
              const TableColumn(title: 'NGÀY TẠO', width: 150),
              const TableColumn(title: 'SỐ SKU', width: 90),
              const TableColumn(title: 'SL YÊU CẦU', width: 110),
              const TableColumn(title: 'ĐÃ SOÁT', width: 100),
              const TableColumn(title: 'TRẠNG THÁI', width: 140),
            ],
          ),
          Expanded(
            child: ListView.separated(
              itemCount: orders.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
              itemBuilder: (context, idx) {
                final ord = orders[idx];
                final reqQty = ord.details.fold<int>(0, (s, d) => s + d.requiredQty);
                final pickedQty = ord.details.fold<int>(0, (s, d) => s + d.pickedQty);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(width: 60, child: Text('${idx + 1}', style: TextStyle(fontSize: 12, color: c.textSecondary))),
                      SizedBox(
                        width: 140,
                        child: Text(
                          ord.poNo,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFEA580C)),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          ord.customer.isNotEmpty ? ord.customer : 'Khách hàng',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 150, child: Text(_formatDateTime(ord.createdAt), style: TextStyle(fontSize: 12, color: c.textSecondary))),
                      SizedBox(width: 90, child: Text('${ord.details.length} SKU', style: TextStyle(fontSize: 12, color: c.textPrimary))),
                      SizedBox(width: 110, child: Text('$reqQty cái', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary))),
                      SizedBox(
                        width: 100,
                        child: Text(
                          '$pickedQty cái',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: pickedQty >= reqQty ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 140,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _buildStatusBadge(ord.status.label, ord.status == OutboundOrderStatus.shipped ? const Color(0xFF10B981) : const Color(0xFFEA580C), c),
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
    );
  }

  // ==========================================
  // 10. BẢNG PREVIEW: TỒN KHO CHI TIẾT
  // ==========================================
  Widget _buildInventoryPreviewTable(List<Item> items, EyeCareColors c) {
    if (items.isEmpty) {
      return _buildEmptyPreview(c, 'Không có mặt hàng tồn kho nào phù hợp trong giai đoạn đã chọn.');
    }

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          _buildTableHeader(
            c,
            [
              const TableColumn(title: 'STT', width: 60),
              const TableColumn(title: 'SỐ SERI (SN)', width: 140),
              const TableColumn(title: 'MÃ SKU', width: 110),
              const TableColumn(title: 'TÊN SẢN PHẨM', flex: 2),
              const TableColumn(title: 'VỊ TRÍ KỆ', width: 100),
              const TableColumn(title: 'MÃ PALLET', width: 110),
              const TableColumn(title: 'NGÀY NHẬP', width: 140),
              const TableColumn(title: 'MÃ CHIP RFID (EPC)', width: 180),
              const TableColumn(title: 'VÒNG ĐỜI THẺ', flex: 2),
            ],
          ),
          Expanded(
            child: ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
              itemBuilder: (context, idx) {
                final it = items[idx];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(width: 60, child: Text('${idx + 1}', style: TextStyle(fontSize: 12, color: c.textSecondary))),
                      SizedBox(
                        width: 140,
                        child: Text(
                          it.serialNumber.isNotEmpty ? it.serialNumber : '--',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                      ),
                      SizedBox(width: 110, child: Text(it.sku, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary))),
                      Expanded(
                        flex: 2,
                        child: Text(it.productName, style: TextStyle(fontSize: 12, color: c.textPrimary), overflow: TextOverflow.ellipsis),
                      ),
                      SizedBox(width: 100, child: Text(it.locationId ?? '--', style: TextStyle(fontSize: 12, color: c.textSecondary))),
                      SizedBox(width: 110, child: Text(it.palletId ?? '--', style: TextStyle(fontSize: 12, color: c.textSecondary))),
                      SizedBox(width: 140, child: Text(_formatDateTime(it.inboundTime), style: TextStyle(fontSize: 12, color: c.textSecondary))),
                      SizedBox(
                        width: 180,
                        child: Text(
                          it.epc,
                          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: c.textSecondary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _repo.getTagLifecycleSummary(it.epc),
                          style: TextStyle(fontSize: 11.5, color: c.textSecondary),
                          overflow: TextOverflow.ellipsis,
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
    );
  }

  // ==========================================
  // 11. BẢNG PREVIEW: BIẾN ĐỘNG KHO (TRANSACTIONS)
  // ==========================================
  Widget _buildTransactionPreviewTable(List<InventoryTransaction> transactions, EyeCareColors c) {
    if (transactions.isEmpty) {
      return _buildEmptyPreview(c, 'Không có giao dịch biến động nào trong giai đoạn đã chọn.');
    }

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          _buildTableHeader(
            c,
            [
              const TableColumn(title: 'STT', width: 60),
              const TableColumn(title: 'THỜI GIAN', width: 140),
              const TableColumn(title: 'LOẠI GIAO DỊCH', width: 130),
              const TableColumn(title: 'MÃ CHỨNG TỪ', width: 130),
              const TableColumn(title: 'MÃ SKU', width: 110),
              const TableColumn(title: 'TÊN SẢN PHẨM', flex: 2),
              const TableColumn(title: 'SỐ LƯỢNG', width: 90),
              const TableColumn(title: 'VỊ TRÍ / TỪ -> ĐẾN', width: 150),
              const TableColumn(title: 'THỰC HIỆN BỞI', width: 130),
            ],
          ),
          Expanded(
            child: ListView.separated(
              itemCount: transactions.length,
              separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
              itemBuilder: (context, idx) {
                final tx = transactions[idx];
                final locStr = '${tx.fromLocation ?? "--"} → ${tx.toLocation ?? "--"}';

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  child: Row(
                    children: [
                      SizedBox(width: 60, child: Text('${idx + 1}', style: TextStyle(fontSize: 12, color: c.textSecondary))),
                      SizedBox(width: 140, child: Text(_formatDateTime(tx.timestamp), style: TextStyle(fontSize: 12, color: c.textSecondary))),
                      SizedBox(
                        width: 130,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: _buildStatusBadge(tx.type.name.toUpperCase(), const Color(0xFF8B5CF6), c),
                        ),
                      ),
                      SizedBox(width: 130, child: Text(tx.documentNo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                      SizedBox(width: 110, child: Text(tx.sku, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary))),
                      Expanded(
                        flex: 2,
                        child: Text(tx.productName, style: TextStyle(fontSize: 12, color: c.textPrimary), overflow: TextOverflow.ellipsis),
                      ),
                      SizedBox(width: 90, child: Text('${tx.quantity}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                      SizedBox(width: 150, child: Text(locStr, style: TextStyle(fontSize: 11, color: c.textSecondary), overflow: TextOverflow.ellipsis)),
                      SizedBox(width: 130, child: Text(tx.performedBy, style: TextStyle(fontSize: 12, color: c.textSecondary), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPreview(EyeCareColors c, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: c.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(fontSize: 13, color: c.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String text, Color color, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildTableHeader(EyeCareColors c, List<TableColumn> columns) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Row(
        children: columns.map((col) {
          if (col.width != null) {
            return SizedBox(
              width: col.width,
              child: Text(
                col.title,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.textSecondary, letterSpacing: 0.3),
              ),
            );
          }
          return Expanded(
            flex: col.flex ?? 1,
            child: Text(
              col.title,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.textSecondary, letterSpacing: 0.3),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class TableColumn {
  final String title;
  final double? width;
  final int? flex;
  const TableColumn({required this.title, this.width, this.flex});
}

