import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/wms_models.dart';
import '../../services/report_export_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';

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

  ReportFormat _selectedFormat = ReportFormat.xlsx;
  bool _isExporting = false;
  String? _lastExportPath;

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedLocationFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onDataChanged);
    _eyeCare.addListener(_onDataChanged);
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

  /// Danh sách sản phẩm thực tế đang lưu kho (IN_STOCK)
  List<Item> get _inStockItems =>
      _repo.items.where((i) => i.status.code == 'IN_STOCK').toList();

  Future<void> _exportReport(List<Item> itemsToExport) async {
    if (itemsToExport.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFF59E0B),
          content: Text('⚠️ Không có mặt hàng nào để xuất báo cáo.'),
          duration: Duration(seconds: 3),
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
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isExporting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('❌ Lỗi xuất báo cáo tồn kho: $e'),
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
    final allInStock = _inStockItems;

    // 1. Lọc theo kệ
    var filteredItems = allInStock;
    if (_selectedLocationFilter != 'ALL') {
      filteredItems = filteredItems
          .where((it) => it.locationId == _selectedLocationFilter)
          .toList();
    }

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
        return snMatch || skuMatch || nameMatch || epcMatch || locMatch || palMatch || supMatch;
      }).toList();
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
              allInStock: allInStock,
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
  // 1. HEADER BAR
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
          final isNarrow = constraints.maxWidth < 800;

          Widget content = Row(
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
              Expanded(
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
                      'Tra cứu danh sách hàng hóa tồn kho và trích xuất báo cáo',
                      style: TextStyle(fontSize: 12, color: c.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  await _repo.reloadFromSqlite();
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      backgroundColor: c.bgCard,
                      content: Text(
                        'Đã làm mới dữ liệu tồn kho thực tế!',
                        style: TextStyle(color: c.textPrimary),
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                icon: Icon(Icons.refresh_rounded, size: 16, color: c.textSecondary),
                label: Text('LÀM MỚI DỮ LIỆU', style: TextStyle(fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
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

  // ==========================================
  // 2. ACTION TOOLBAR & SEARCH CONTROLS
  // ==========================================
  Widget _buildActionToolbar({
    required List<Item> allInStock,
    required List<Item> filteredItems,
    required EyeCareColors c,
  }) {
    // Thu thập danh sách vị trí kệ
    final shelfOptions = <String>{'ALL'};
    for (final it in allInStock) {
      if (it.locationId != null && it.locationId!.isNotEmpty) {
        shelfOptions.add(it.locationId!);
      }
    }
    final sortedShelves = shelfOptions.toList()..sort();

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
                  // Cụm điều khiển tìm kiếm & lọc (bên trái)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Ô Tìm Kiếm Số Seri (SN), SKU, Kệ đơn giản & trực quan
                      Container(
                        width: 280,
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

                      const SizedBox(width: 10),

                      // 2. Lọc Vị Trí Kệ
                      Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: c.bgDeep,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.border),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: sortedShelves.contains(_selectedLocationFilter) ? _selectedLocationFilter : 'ALL',
                            dropdownColor: c.bgCard,
                            icon: Icon(Icons.filter_list_rounded, size: 16, color: c.textSecondary),
                            style: TextStyle(fontSize: 12, color: c.textPrimary),
                            items: sortedShelves.map((loc) {
                              return DropdownMenuItem<String>(
                                value: loc,
                                child: Text(loc == 'ALL' ? 'Tất cả vị trí kệ' : 'Kệ: $loc'),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedLocationFilter = val);
                            },
                          ),
                        ),
                      ),

                      const SizedBox(width: 10),

                      // 3. Số lượng hiển thị
                      Container(
                        height: 38,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: c.bgDeep,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 15, color: c.textSecondary),
                            const SizedBox(width: 6),
                            Text(
                              'Hiển thị: ${filteredItems.length} / ${allInStock.length}',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.textPrimary),
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
            const minTableWidth = 1168.0;
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
                                    if (_searchQuery.isNotEmpty || _selectedLocationFilter != 'ALL') ...[
                                      const SizedBox(height: 14),
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() {
                                            _searchQuery = '';
                                            _selectedLocationFilter = 'ALL';
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
}
