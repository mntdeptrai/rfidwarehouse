import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/wms_models.dart';
import '../../services/report_export_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';

/// Đại diện một dòng bản ghi trong bảng báo cáo có thể chọn
class _ReportRowItem {
  final String key;
  final String code;
  final String partner;
  final DateTime? timestamp;
  final String detail;
  final int itemCount;
  final String statusLabel;
  final Color statusColor;

  const _ReportRowItem({
    required this.key,
    required this.code,
    required this.partner,
    this.timestamp,
    required this.detail,
    required this.itemCount,
    required this.statusLabel,
    required this.statusColor,
  });
}

/// Màn hình Báo Cáo Kho — Form chọn lọc và trích xuất báo cáo (Excel / CSV)
class DesktopReportView extends StatefulWidget {
  const DesktopReportView({super.key});

  @override
  State<DesktopReportView> createState() => _DesktopReportViewState();
}

class _DesktopReportViewState extends State<DesktopReportView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final ReportExportService _exportService = ReportExportService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  ReportType _selectedReportType = ReportType.inbound;
  ReportFormat _selectedFormat = ReportFormat.xlsx;
  bool _isExporting = false;
  String? _lastExportPath;

  final Set<String> _selectedKeys = {};
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onDataChanged);
    _eyeCare.addListener(_onDataChanged);
    _selectAllCurrentCategory();
  }

  void _onDataChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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

  List<_ReportRowItem> _loadItemsForType(ReportType type) {
    final List<_ReportRowItem> list = [];

    switch (type) {
      case ReportType.inbound:
        for (final o in _repo.inboundOrders) {
          final ordItems = _repo.items.where((i) => i.orderNo == o.orderNo || i.orderNo == o.inboundOrderId).toList();
          final skuCount = o.details.isNotEmpty ? o.details.length : ordItems.map((i) => i.sku).toSet().length;
          final totalQty = ordItems.isNotEmpty ? ordItems.length : o.details.fold<int>(0, (sum, d) => sum + d.requiredQty);

          final isDone = o.status == InboundOrderStatus.completed;
          final isProc = o.status == InboundOrderStatus.processing;
          final statusLabel = isDone ? 'Hoàn tất' : (isProc ? 'Đang nhận' : 'Mới tạo');
          final statusColor = isDone ? const Color(0xFF10B981) : (isProc ? const Color(0xFF3B82F6) : const Color(0xFFF59E0B));

          list.add(_ReportRowItem(
            key: o.orderNo,
            code: o.orderNo,
            partner: o.sourceSupplier.isNotEmpty ? o.sourceSupplier : 'Nhà cung cấp',
            timestamp: o.createdAt,
            detail: '$skuCount SKU • $totalQty sản phẩm',
            itemCount: totalQty,
            statusLabel: statusLabel,
            statusColor: statusColor,
          ));
        }
        break;

      case ReportType.outbound:
        for (final o in _repo.outboundOrders) {
          final totalQty = o.details.fold<int>(0, (sum, d) => sum + d.requiredQty);
          final pickedQty = o.details.fold<int>(0, (sum, d) => sum + d.pickedQty);

          final isShipped = o.status == OutboundOrderStatus.shipped;
          final statusLabel = isShipped ? 'Đã xuất kho' : 'Đang xử lý';
          final statusColor = isShipped ? const Color(0xFF10B981) : const Color(0xFF3B82F6);

          list.add(_ReportRowItem(
            key: o.poNo,
            code: o.poNo,
            partner: o.customer.isNotEmpty ? o.customer : 'Khách hàng',
            timestamp: o.createdAt,
            detail: '${o.details.length} SKU • Xuất $pickedQty/$totalQty',
            itemCount: totalQty,
            statusLabel: statusLabel,
            statusColor: statusColor,
          ));
        }
        break;

      case ReportType.inventory:
        final inStock = _repo.items.where((i) => i.status.code == 'IN_STOCK').toList();
        for (final it in inStock) {
          String palletDisplay = '--';
          if (it.palletId != null && it.palletId!.isNotEmpty) {
            final p = _repo.pallets.where((x) => x.palletId == it.palletId || x.palletCode == it.palletId).toList();
            palletDisplay = p.isNotEmpty ? p.first.displayName : it.palletId!;
          }

          list.add(_ReportRowItem(
            key: it.epc,
            code: it.epc,
            partner: '${it.productName} (${it.sku})',
            timestamp: it.inboundTime,
            detail: 'Pallet: $palletDisplay • Kệ: ${it.locationId ?? "--"}',
            itemCount: 1,
            statusLabel: 'Tồn kho',
            statusColor: const Color(0xFF047857),
          ));
        }
        break;

      case ReportType.audit:
        for (final s in _repo.inventorySessions) {
          final code = s.sessionCode.isNotEmpty ? s.sessionCode : s.sessionId;
          final loc = (s.locationCode != null && s.locationCode!.isNotEmpty)
              ? 'Kệ: ${s.locationCode} (${s.zone})'
              : 'Khu vực: ${s.zone}';

          list.add(_ReportRowItem(
            key: code,
            code: code,
            partner: loc,
            timestamp: s.completedAt ?? s.startedAt,
            detail: 'Quét: ${s.actualScannedCount} • Khớp: ${s.matchCount} • Lệch: ${s.missingCount + s.wrongLocationCount}',
            itemCount: s.actualScannedCount,
            statusLabel: s.isCompleted ? 'Hoàn thành' : 'Đang kiểm',
            statusColor: s.isCompleted ? const Color(0xFF10B981) : const Color(0xFF8B5CF6),
          ));
        }
        break;

      case ReportType.transactionLog:
        for (final t in _repo.transactions) {
          final doc = t.documentNo.isNotEmpty ? t.documentNo : t.transactionId;
          final route = t.toLocation != null
              ? '${t.fromLocation ?? "--"} → ${t.toLocation}'
              : (t.palletCode != null ? 'Pallet: ${t.palletCode}' : t.type.label);

          list.add(_ReportRowItem(
            key: doc,
            code: doc,
            partner: '${t.productName} (${t.sku})',
            timestamp: t.timestamp,
            detail: 'Tuyến: $route • Người làm: ${t.performedBy}',
            itemCount: t.quantity,
            statusLabel: t.type.label,
            statusColor: const Color(0xFFF59E0B),
          ));
        }
        break;
    }

    // Sắp xếp thời gian giảm dần
    list.sort((a, b) {
      if (a.timestamp == null && b.timestamp == null) return 0;
      if (a.timestamp == null) return 1;
      if (b.timestamp == null) return -1;
      return b.timestamp!.compareTo(a.timestamp!);
    });

    return list;
  }

  void _selectAllCurrentCategory() {
    final allItems = _loadItemsForType(_selectedReportType);
    _selectedKeys.clear();
    for (final it in allItems) {
      _selectedKeys.add(it.key);
    }
  }

  void _switchCategory(ReportType type) {
    if (_selectedReportType == type) return;
    setState(() {
      _selectedReportType = type;
      _searchCtrl.clear();
      _searchQuery = '';
      _selectAllCurrentCategory();
    });
  }

  Future<void> _exportSelected() async {
    if (_selectedKeys.isEmpty) return;

    setState(() => _isExporting = true);

    try {
      final file = await _exportService.exportReportSelected(
        _selectedReportType,
        _selectedFormat,
        selectedKeys: _selectedKeys.toList(),
      );

      if (mounted) {
        setState(() {
          _isExporting = false;
          _lastExportPath = file.path;
        });

        final unitName = (_selectedReportType == ReportType.inbound || _selectedReportType == ReportType.outbound)
            ? 'đơn'
            : (_selectedReportType == ReportType.audit ? 'phiên' : 'bản ghi');

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF047857),
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Đã tự động điền dữ liệu ${_selectedKeys.length} $unitName vào Biểu Mẫu Phiếu ${_selectedReportType.label} và xuất file thành công!',
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
        setState(() => _isExporting = false);
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

    final allItems = _loadItemsForType(_selectedReportType);
    final q = _searchQuery.trim().toLowerCase();

    final filteredItems = allItems.where((it) {
      if (q.isEmpty) return true;
      return it.code.toLowerCase().contains(q) ||
          it.partner.toLowerCase().contains(q) ||
          it.detail.toLowerCase().contains(q) ||
          it.statusLabel.toLowerCase().contains(q);
    }).toList();

    // Tính tổng số lượng sản phẩm của các bản ghi đã chọn
    final selectedItemSum = allItems
        .where((it) => _selectedKeys.contains(it.key))
        .fold<int>(0, (sum, it) => sum + it.itemCount);

    final isAllFilteredSelected = filteredItems.isNotEmpty &&
        filteredItems.every((it) => _selectedKeys.contains(it.key));

    final isPartiallySelected = !isAllFilteredSelected &&
        filteredItems.any((it) => _selectedKeys.contains(it.key));

    final unitName = (_selectedReportType == ReportType.inbound || _selectedReportType == ReportType.outbound)
        ? 'Đơn'
        : (_selectedReportType == ReportType.audit ? 'Phiên' : 'Bản ghi');

    return Container(
      color: c.bgDeep,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final contentWidth = math.max(constraints.maxWidth, 1150.0);

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: constraints.maxHeight,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Header Bar
                    _buildHeaderBar(c),

                    const SizedBox(height: 12),

                    // 2. Bốn Thẻ Chỉ Số Báo Cáo
                    _buildMetricCards(allItems.length, selectedItemSum, unitName, c),

                    const SizedBox(height: 12),

                    // 3. Thanh Chuyển Đổi Nghiệp Vụ Báo Cáo
                    _buildCategorySwitcher(c),

                    const SizedBox(height: 12),

                    // 4. Thanh Công Cụ (Tìm kiếm, Chọn tất cả, Định dạng, Nút Xuất)
                    _buildToolbar(filteredItems, isAllFilteredSelected, unitName, c),

                    const SizedBox(height: 12),

                    // 5. Bảng Dữ Liệu Chọn Lọc
                    Expanded(
                      child: _buildSelectableTable(
                        filteredItems,
                        allItems.length,
                        isAllFilteredSelected,
                        isPartiallySelected,
                        c,
                      ),
                    ),

                    // 6. Thông báo tệp xuất gần nhất (nếu có)
                    if (_lastExportPath != null) ...[
                      const SizedBox(height: 8),
                      _buildLastExportBanner(c),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ==========================================
  // HEADER BAR
  // ==========================================
  Widget _buildHeaderBar(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: c.rfidCyan.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
            ),
            child: Icon(Icons.assessment_rounded, color: c.rfidCyan, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Trung Tâm Báo Cáo Kho',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tự động điền dữ liệu các đơn đã chọn vào biểu mẫu phiếu (Phiếu Nhập, Phiếu Xuất, Biên Bản Kiểm Kê) rồi xuất file Excel/CSV — không cần nạp file',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // METRIC TILES
  // ==========================================
  Widget _buildMetricCards(int totalCount, int selectedItemSum, String unitName, EyeCareColors c) {
    final catColor = _getCategoryColor(_selectedReportType);

    return Row(
      children: [
        Expanded(
          child: _buildMetricTile(
            icon: Icons.storage_rounded,
            iconColor: catColor,
            title: 'TỔNG SỐ $unitName'.toUpperCase(),
            value: '$totalCount $unitName',
            subtitle: 'Bản ghi hiện có trong kho',
            c: c,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricTile(
            icon: Icons.check_box_outlined,
            iconColor: const Color(0xFF10B981),
            title: 'ĐÃ CHỌN XUẤT FILE',
            value: '${_selectedKeys.length} / $totalCount $unitName',
            subtitle: 'Sẽ được trích xuất ra tệp',
            c: c,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricTile(
            icon: Icons.inventory_2_outlined,
            iconColor: const Color(0xFF3B82F6),
            title: 'LƯỢNG HÀNG TRONG ĐƠN CHỌN',
            value: '$selectedItemSum Sản phẩm',
            subtitle: 'Tổng số lượng hàng hóa/chip',
            c: c,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildMetricTile(
            icon: Icons.description_outlined,
            iconColor: const Color(0xFF8B5CF6),
            title: 'ĐỊNH DẠNG XUẤT',
            value: _selectedFormat == ReportFormat.xlsx ? 'Excel (.xlsx)' : 'CSV (.csv)',
            subtitle: 'Tương thích phần mềm kế toán',
            c: c,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
    required EyeCareColors c,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: c.textSecondary, fontSize: 10.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // CATEGORY SWITCHER TABS
  // ==========================================
  Widget _buildCategorySwitcher(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          _buildCategoryTabButton(
            '📥 NHẬP KHO (${_getRecordCount(ReportType.inbound)})',
            Icons.input_rounded,
            ReportType.inbound,
            const Color(0xFF10B981),
            c,
          ),
          const SizedBox(width: 6),
          _buildCategoryTabButton(
            '📤 XUẤT KHO (${_getRecordCount(ReportType.outbound)})',
            Icons.output_rounded,
            ReportType.outbound,
            const Color(0xFF3B82F6),
            c,
          ),
          const SizedBox(width: 6),
          _buildCategoryTabButton(
            '📦 TỒN KHO (${_getRecordCount(ReportType.inventory)})',
            Icons.inventory_2_outlined,
            ReportType.inventory,
            const Color(0xFF047857),
            c,
          ),
          const SizedBox(width: 6),
          _buildCategoryTabButton(
            '📊 KIỂM KÊ (${_getRecordCount(ReportType.audit)})',
            Icons.fact_check_outlined,
            ReportType.audit,
            const Color(0xFF8B5CF6),
            c,
          ),
          const SizedBox(width: 6),
          _buildCategoryTabButton(
            '🔄 BIẾN ĐỘNG (${_getRecordCount(ReportType.transactionLog)})',
            Icons.sync_alt_rounded,
            ReportType.transactionLog,
            const Color(0xFFF59E0B),
            c,
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabButton(
    String label,
    IconData icon,
    ReportType type,
    Color activeColor,
    EyeCareColors c,
  ) {
    final isSelected = _selectedReportType == type;

    return Expanded(
      child: InkWell(
        onTap: () => _switchCategory(type),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? activeColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: isSelected ? activeColor : c.textSecondary),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isSelected ? c.textPrimary : c.textSecondary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    fontSize: 11.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==========================================
  // TOOLBAR (Search, Select All, Format, Export)
  // ==========================================
  Widget _buildToolbar(
    List<_ReportRowItem> filteredItems,
    bool isAllFilteredSelected,
    String unitName,
    EyeCareColors c,
  ) {
    final hasSelection = _selectedKeys.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          // 1. Search Bar
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                controller: _searchCtrl,
                onChanged: (val) => setState(() => _searchQuery = val),
                style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'Tìm kiếm theo Mã Đơn, EPC, Đối Tác, Khu Vực, Trạng Thái...',
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                  prefixIcon: Icon(Icons.search, size: 18, color: c.textSecondary),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 16),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: c.bgDeep,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 2. Nút Chọn Tất Cả / Bỏ Chọn
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.textPrimary,
              side: BorderSide(color: c.border),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: Icon(
              isAllFilteredSelected ? Icons.deselect : Icons.select_all,
              size: 16,
              color: isAllFilteredSelected ? const Color(0xFFEF4444) : c.rfidCyan,
            ),
            label: Text(
              isAllFilteredSelected ? 'BỎ CHỌN' : 'CHỌN TẤT CẢ (${filteredItems.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
            ),
            onPressed: () {
              setState(() {
                if (isAllFilteredSelected) {
                  for (final it in filteredItems) {
                    _selectedKeys.remove(it.key);
                  }
                } else {
                  for (final it in filteredItems) {
                    _selectedKeys.add(it.key);
                  }
                }
              });
            },
          ),
          const SizedBox(width: 10),

          // 3. Dropdown Định Dạng Xuất File
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
                value: _selectedFormat,
                dropdownColor: c.bgCard,
                style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                icon: Icon(Icons.arrow_drop_down, color: c.textSecondary, size: 18),
                isDense: true,
                items: const [
                  DropdownMenuItem(value: ReportFormat.xlsx, child: Text('Excel (.xlsx)')),
                  DropdownMenuItem(value: ReportFormat.csv, child: Text('CSV (.csv)')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _selectedFormat = v);
                },
              ),
            ),
          ),
          const SizedBox(width: 10),

          // 4. Nút Xuất Báo Cáo
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.rfidCyan,
              disabledBackgroundColor: c.bgCardElevated,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            onPressed: _isExporting || !hasSelection ? null : _exportSelected,
            icon: _isExporting
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.file_download_rounded, size: 16),
            label: Text(
              _isExporting
                  ? 'ĐANG XUẤT...'
                  : 'XUẤT BÁO CÁO (${_selectedKeys.length} $unitName)'.toUpperCase(),
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 0.4),
            ),
          ),
          const SizedBox(width: 8),

          // 5. Nút Làm Mới
          Tooltip(
            message: 'Đồng bộ & làm mới dữ liệu từ CSDL',
            child: IconButton(
              style: IconButton.styleFrom(
                side: BorderSide(color: c.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.all(9),
              ),
              icon: Icon(Icons.refresh, size: 16, color: c.textPrimary),
              onPressed: () async {
                await _repo.reloadFromSqlite();
                if (mounted) setState(() {});
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // SELECTABLE DATA TABLE
  // ==========================================
  Widget _buildSelectableTable(
    List<_ReportRowItem> filteredItems,
    int totalCategoryItems,
    bool isAllFilteredSelected,
    bool isPartiallySelected,
    EyeCareColors c,
  ) {
    final codeColumnTitle = _getCodeColumnTitle(_selectedReportType);
    final partnerColumnTitle = _getPartnerColumnTitle(_selectedReportType);

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                // Checkbox All
                SizedBox(
                  width: 38,
                  child: Checkbox(
                    value: isAllFilteredSelected ? true : (isPartiallySelected ? null : false),
                    tristate: true,
                    activeColor: c.rfidCyan,
                    side: BorderSide(color: c.border, width: 1.5),
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          for (final it in filteredItems) {
                            _selectedKeys.add(it.key);
                          }
                        } else {
                          for (final it in filteredItems) {
                            _selectedKeys.remove(it.key);
                          }
                        }
                      });
                    },
                  ),
                ),
                SizedBox(
                  width: 45,
                  child: Text('STT', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                SizedBox(
                  width: 125,
                  child: Text('THỜI GIAN', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(codeColumnTitle, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  flex: 3,
                  child: Text(partnerColumnTitle, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                Expanded(
                  flex: 3,
                  child: Text('SỐ LƯỢNG / CHI TIẾT', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                SizedBox(
                  width: 120,
                  child: Text('TRẠNG THÁI', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),

          // Table Body
          Expanded(
            child: filteredItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 44, color: c.textMuted),
                        const SizedBox(height: 10),
                        Text(
                          totalCategoryItems == 0
                              ? 'Chưa có dữ liệu nào trong kho cho danh mục này.'
                              : 'Không tìm thấy bản ghi nào khớp với từ khóa tìm kiếm.',
                          style: TextStyle(color: c.textSecondary, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredItems.length,
                    itemBuilder: (context, idx) {
                      final item = filteredItems[idx];
                      final isSelected = _selectedKeys.contains(item.key);

                      return InkWell(
                        onTap: () {
                          setState(() {
                            if (isSelected) {
                              _selectedKeys.remove(item.key);
                            } else {
                              _selectedKeys.add(item.key);
                            }
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: isSelected ? c.rfidCyan.withValues(alpha: 0.07) : Colors.transparent,
                            border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
                          ),
                          child: Row(
                            children: [
                              // Checkbox
                              SizedBox(
                                width: 38,
                                child: Checkbox(
                                  value: isSelected,
                                  activeColor: c.rfidCyan,
                                  side: BorderSide(color: c.border, width: 1.5),
                                  onChanged: (val) {
                                    setState(() {
                                      if (val == true) {
                                        _selectedKeys.add(item.key);
                                      } else {
                                        _selectedKeys.remove(item.key);
                                      }
                                    });
                                  },
                                ),
                              ),

                              // STT
                              SizedBox(
                                width: 45,
                                child: Text(
                                  '#${idx + 1}',
                                  style: TextStyle(color: c.textMuted, fontSize: 11.5, fontWeight: FontWeight.w600),
                                ),
                              ),

                              // Thời gian
                              SizedBox(
                                width: 125,
                                child: Text(
                                  _formatDateTime(item.timestamp),
                                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                                ),
                              ),

                              // Mã Đơn / EPC
                              Expanded(
                                flex: 3,
                                child: Text(
                                  item.code,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                  ),
                                ),
                              ),

                              // Đối tác / Vị trí
                              Expanded(
                                flex: 3,
                                child: Text(
                                  item.partner,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w500),
                                ),
                              ),

                              // Chi tiết / Số lượng
                              Expanded(
                                flex: 3,
                                child: Text(
                                  item.detail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                                ),
                              ),

                              // Trạng thái
                              SizedBox(
                                width: 120,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: item.statusColor.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: item.statusColor.withValues(alpha: 0.3)),
                                    ),
                                    child: Text(
                                      item.statusLabel,
                                      style: TextStyle(
                                        color: item.statusColor,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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
  // LAST EXPORT PATH BANNER
  // ==========================================
  Widget _buildLastExportBanner(EyeCareColors c) {
    final path = _lastExportPath!;
    final fileName = path.split(Platform.pathSeparator).last;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF047857).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF047857).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF047857), size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Tệp xuất gần nhất: $fileName ($path)',
              style: const TextStyle(
                color: Color(0xFF047857),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: () => _openFileInExplorer(path),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open_rounded, color: c.rfidCyan, size: 15),
                  const SizedBox(width: 4),
                  Text(
                    'MỞ THƯ MỤC',
                    style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // HELPERS
  // ==========================================
  int _getRecordCount(ReportType type) {
    return _exportService.getRecordCount(type);
  }

  Color _getCategoryColor(ReportType type) {
    switch (type) {
      case ReportType.inbound:
        return const Color(0xFF10B981);
      case ReportType.outbound:
        return const Color(0xFF3B82F6);
      case ReportType.inventory:
        return const Color(0xFF047857);
      case ReportType.audit:
        return const Color(0xFF8B5CF6);
      case ReportType.transactionLog:
        return const Color(0xFFF59E0B);
    }
  }

  String _getCodeColumnTitle(ReportType type) {
    switch (type) {
      case ReportType.inbound:
        return 'MÃ ĐƠN NHẬP';
      case ReportType.outbound:
        return 'MÃ PO / XUẤT';
      case ReportType.inventory:
        return 'MÃ EPC / RFID';
      case ReportType.audit:
        return 'MÃ PHIÊN KIỂM KÊ';
      case ReportType.transactionLog:
        return 'MÃ CHỨNG TỪ';
    }
  }

  String _getPartnerColumnTitle(ReportType type) {
    switch (type) {
      case ReportType.inbound:
        return 'NHÀ CUNG CẤP';
      case ReportType.outbound:
        return 'KHÁCH HÀNG';
      case ReportType.inventory:
        return 'SẢN PHẨM / SKU';
      case ReportType.audit:
        return 'KHU VỰC / VỊ TRÍ';
      case ReportType.transactionLog:
        return 'SẢN PHẨM / SKU';
    }
  }
}
