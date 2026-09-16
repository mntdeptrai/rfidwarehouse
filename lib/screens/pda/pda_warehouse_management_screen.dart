import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/wms_models.dart';
import '../../services/warehouse_repository.dart';
import '../../services/uhf_service.dart';
import '../../services/auth_service.dart';
import '../../theme/eye_care_theme.dart';
import '../../widgets/hardware_status_appbar.dart';
import 'pda_transfer_screen.dart';

/// Màn hình Quản Lý Kho tối ưu chuyên biệt cho tay cầm PDA (Handheld Terminal)
/// Đồng bộ 4 Tabs nghiệp vụ với app Desktop:
/// - Tab 0: Quản Lý Pallet
/// - Tab 1: Quản Lý Vị Trí Kho (Sơ đồ/Danh sách kệ, 3 KPI Đầy/Sắp hết/Còn trống, nút bấm nhanh trạng thái kệ)
/// - Tab 2: Quản Lý Lịch Sử (Lịch sử giao dịch & Nhật ký hệ thống Audit Trail)
/// - Tab 3: Quản Lý Thông Tin Sản Phẩm (Tra cứu từ khóa đa năng, quét súng RFID/Laser Barcode, hiển thị rõ hàng đã xuất)
class PdaWarehouseManagementScreen extends StatefulWidget {
  final int initialTabIndex;
  const PdaWarehouseManagementScreen({super.key, this.initialTabIndex = 0});

  @override
  State<PdaWarehouseManagementScreen> createState() => _PdaWarehouseManagementScreenState();
}

class _PdaWarehouseManagementScreenState extends State<PdaWarehouseManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final AuthService _auth = AuthService();

  // Tab 0: Pallet
  final TextEditingController _palletSearchCtrl = TextEditingController();
  String _palletQuery = '';

  // Tab 1: Vị Trí Kho
  final TextEditingController _locationSearchCtrl = TextEditingController();
  String _locationQuery = '';
  String _selectedZoneFilter = 'ALL';

  // Tab 2: Lịch Sử
  int _historySubTabIndex = 0; // 0: Giao dịch, 1: Nhật ký (Audit)

  // Tab 3: Sản Phẩm (Tra Cứu)
  final TextEditingController _productSearchCtrl = TextEditingController();
  String _productQuery = '';
  ItemStatus? _selectedProductStatusFilter;
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex);
    _tabController.addListener(_handleTabChange);

    _eyeCare.addListener(_onStateUpdate);
    _repo.addListener(_onStateUpdate);

    // Màn hình Quản Lý Kho KHÔNG cho phép quét: khóa và dừng đầu đọc ngay lập tức
    _uhf.disableScanning();
  }

  void _handleTabChange() {
    if (mounted) setState(() {});
  }

  void _onStateUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _uhf.disableScanning();
    _palletSearchCtrl.dispose();
    _locationSearchCtrl.dispose();
    _productSearchCtrl.dispose();
    _tabController.dispose();
    _repo.removeListener(_onStateUpdate);
    _eyeCare.removeListener(_onStateUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: HardwareStatusAppBar(
        title: 'QUẢN LÝ KHO',
        showScanMode: false,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: c.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // TabBar điều hướng 4 Tab tối ưu cho ngón tay chạm cảm ứng trên PDA
            Container(
              color: c.bgCard,
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.center,
                indicatorColor: c.rfidCyan,
                indicatorWeight: 3,
                labelColor: c.rfidCyan,
                unselectedLabelColor: c.textMuted,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal, fontSize: 11.5),
                tabs: [
                  const Tab(icon: Icon(Icons.pallet, size: 20), text: 'Pallet'),
                  const Tab(icon: Icon(Icons.grid_view_rounded, size: 20), text: 'Vị Trí Kho'),
                  const Tab(icon: Icon(Icons.history_rounded, size: 20), text: 'Lịch Sử'),
                  const Tab(icon: Icon(Icons.inventory_2_rounded, size: 20), text: 'Sản Phẩm'),
                ],
              ),
            ),
            const Divider(height: 1, thickness: 1),

            // Nội dung từng Tab
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildPalletManagementTab(c),
                  _buildLocationManagementTab(c),
                  _buildHistoryTab(c),
                  _buildProductLookupTab(c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 0: QUẢN LÝ PALLET
  // ===========================================================================
  Widget _buildPalletManagementTab(EyeCareColors c) {
    final allPallets = _repo.pallets;
    final totalPallets = allPallets.length;
    final activePallets = allPallets.where((p) {
      final inStockItems = _repo.items.where((i) =>
        i.status == ItemStatus.inStock &&
        (p.itemIds.contains(i.itemId) || i.palletId == p.palletId || i.palletId == p.palletCode)
      ).length;
      return inStockItems > 0;
    }).length;
    final emptyPallets = totalPallets - activePallets;

    final query = _palletQuery.trim().toUpperCase();
    final filteredPallets = allPallets.where((p) {
      if (query.isEmpty) return true;
      final code = p.palletCode.toUpperCase();
      final id = p.palletId.toUpperCase();
      final epc = (p.rfidEpc ?? '').toUpperCase();
      final loc = (p.locationId ?? '').toUpperCase();
      return code.contains(query) || id.contains(query) || epc.contains(query) || loc.contains(query);
    }).toList();

    return Column(
      children: [
        // 1. Thẻ thống kê nhanh gọn
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: c.bgCardElevated,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildMiniKpiBadge('Tổng: $totalPallets', c.rfidCyan, c),
                const SizedBox(width: 8),
                _buildMiniKpiBadge('Có hàng: $activePallets', const Color(0xFF10B981), c),
                const SizedBox(width: 8),
                _buildMiniKpiBadge('Trống: $emptyPallets', c.textMuted, c),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.rfidCyan,
                    foregroundColor: const Color(0xFF2C251E),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Thêm', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  onPressed: () => _showAddPalletDialog(c),
                ),
              ],
            ),
          ),
        ),

        // 2. Thanh tìm kiếm
        Padding(
          padding: const EdgeInsets.all(10),
          child: TextField(
            controller: _palletSearchCtrl,
            onChanged: (val) => setState(() => _palletQuery = val),
            style: TextStyle(color: c.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Tìm pallet theo mã, EPC, vị trí...',
              hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
              prefixIcon: Icon(Icons.search, color: c.rfidCyan, size: 20),
              suffixIcon: _palletQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear, color: c.textMuted, size: 18),
                      onPressed: () {
                        _palletSearchCtrl.clear();
                        setState(() => _palletQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: c.bgCard,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.border),
              ),
            ),
          ),
        ),

        // 3. Danh sách Pallet
        Expanded(
          child: filteredPallets.isEmpty
              ? Center(
                  child: Text('Không tìm thấy pallet phù hợp', style: TextStyle(color: c.textMuted, fontSize: 13)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  itemCount: filteredPallets.length,
                  itemBuilder: (context, idx) {
                    final p = filteredPallets[idx];
                    return _buildPdaPalletCard(p, c);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildPdaPalletCard(Pallet p, EyeCareColors c) {
    final inStockItems = _repo.items.where((i) =>
      i.status == ItemStatus.inStock &&
      (p.itemIds.contains(i.itemId) || i.palletId == p.palletId || i.palletId == p.palletCode)
    ).toList();
    final itemCount = inStockItems.length;
    final locText = p.locationId != null && p.locationId!.isNotEmpty ? p.locationId! : 'Chưa xếp kệ';
    final hasLocation = p.locationId != null && p.locationId!.isNotEmpty;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: c.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: itemCount > 0 ? c.rfidCyan.withValues(alpha: 0.3) : c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (itemCount > 0 ? c.rfidCyan : c.textMuted).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.pallet, color: itemCount > 0 ? c.rfidCyan : c.textMuted, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.palletCode,
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'monospace'),
                      ),
                      if (p.rfidEpc != null && p.rfidEpc!.isNotEmpty)
                        Text(
                          'EPC: ${p.rfidEpc}',
                          style: TextStyle(color: c.rfidCyan, fontSize: 10.5, fontFamily: 'monospace'),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (itemCount > 0 ? const Color(0xFF10B981) : c.textMuted).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    itemCount > 0 ? '$itemCount SP' : 'TRỐNG',
                    style: TextStyle(
                      color: itemCount > 0 ? const Color(0xFF10B981) : c.textMuted,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.location_on, size: 14, color: hasLocation ? const Color(0xFFEF4444) : c.textMuted),
                      const SizedBox(width: 4),
                      Text('Vị trí: ', style: TextStyle(color: c.textMuted, fontSize: 12)),
                      Flexible(
                        child: Text(
                          locText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: hasLocation ? c.textPrimary : c.textMuted,
                            fontWeight: hasLocation ? FontWeight.bold : FontWeight.normal,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 4),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.rfidCyan,
                    side: BorderSide(color: c.rfidCyan),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.edit_location_alt, size: 13),
                  label: Text(hasLocation ? 'Đổi kệ' : 'Gán kệ', style: const TextStyle(fontSize: 10.5)),
                  onPressed: () => _showAssignPalletLocationDialog(p, c),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 18),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  tooltip: 'Xóa Pallet',
                  onPressed: () => _confirmDeletePallet(p, c),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeletePallet(Pallet p, EyeCareColors c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 22),
            const SizedBox(width: 8),
            Text('Xác nhận xóa Pallet', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa Pallet ${p.palletCode} không?\nCác mặt hàng (nếu có) sẽ chuyển về trạng thái không gắn pallet.',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Hủy', style: TextStyle(color: c.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(ctx);
              await _repo.deletePallet(p.palletId.isNotEmpty ? p.palletId : p.palletCode);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã xóa Pallet: ${p.palletCode}')),
                );
              }
            },
            child: const Text('Xóa', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddPalletDialog(EyeCareColors c) {
    final codeCtrl = TextEditingController(text: 'PALLET-${DateTime.now().millisecondsSinceEpoch.toString().substring(8)}');
    final epcCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Thêm Pallet Mới', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeCtrl,
              decoration: InputDecoration(labelText: 'Mã Pallet', labelStyle: TextStyle(color: c.textSecondary)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: epcCtrl,
              decoration: InputDecoration(labelText: 'Mã RFID EPC (Tùy chọn)', labelStyle: TextStyle(color: c.textSecondary)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Hủy', style: TextStyle(color: c.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan, foregroundColor: const Color(0xFF2C251E)),
            onPressed: () async {
              final code = codeCtrl.text.trim();
              if (code.isEmpty) return;
              final epc = epcCtrl.text.trim().isNotEmpty ? epcCtrl.text.trim() : null;
              final newPal = _repo.createOrAssignPallet(
                palletCode: code,
                newItems: [],
                placedBy: _auth.currentUser?.fullName ?? 'Thủ kho PDA',
              );
              if (epc != null) {
                newPal.rfidEpc = epc;
              }
              Navigator.pop(ctx);
              setState(() {});
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã tạo Pallet: $code')));
              }
            },
            child: const Text('Tạo Pallet', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAssignPalletLocationDialog(Pallet p, EyeCareColors c) {
    String? selectedLocId = p.locationId ?? (_repo.locations.isNotEmpty ? _repo.locations.first.locationId : null);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDlgState) => AlertDialog(
          backgroundColor: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('Gán Vị Trí Kệ: ${p.palletCode}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedLocId,
                dropdownColor: c.bgCard,
                decoration: InputDecoration(
                  labelText: 'Chọn Vị Trí Kệ',
                  labelStyle: TextStyle(color: c.textSecondary),
                ),
                items: _repo.locations.map((loc) {
                  return DropdownMenuItem(
                    value: loc.locationId,
                    child: Text('${loc.locationCode} (${loc.displayName})', style: TextStyle(color: c.textPrimary, fontSize: 12)),
                  );
                }).toList(),
                onChanged: (val) => setDlgState(() => selectedLocId = val),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                _repo.movePallet(
                  palletId: p.palletId,
                  newLocationId: '',
                  performedBy: _auth.currentUser?.fullName ?? 'Thủ kho PDA',
                );
                Navigator.pop(ctx);
                setState(() {});
              },
              child: const Text('Gỡ Khỏi Kệ', style: TextStyle(color: Color(0xFFEF4444))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan, foregroundColor: const Color(0xFF2C251E)),
              onPressed: () {
                if (selectedLocId != null) {
                  _repo.movePallet(
                    palletId: p.palletId,
                    newLocationId: selectedLocId!,
                    performedBy: _auth.currentUser?.fullName ?? 'Thủ kho PDA',
                  );
                  Navigator.pop(ctx);
                  setState(() {});
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Đã xếp pallet lên kệ: $selectedLocId')));
                  }
                }
              },
              child: const Text('Lưu Vị Trí', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 1: QUẢN LÝ VỊ TRÍ KHO (SƠ ĐỒ / DANH SÁCH KỆ)
  // ===========================================================================
  Widget _buildLocationManagementTab(EyeCareColors c) {
    final allLocations = _repo.locations;
    final fullCount = allLocations.where((l) => l.status.toUpperCase() == 'FULL').length;
    final nearFullCount = allLocations.where((l) => l.status.toUpperCase() == 'NEAR_FULL').length;
    final availCount = allLocations.length - fullCount - nearFullCount;

    final zones = {'ALL', ...allLocations.map((l) => l.zone.trim()).where((z) => z.isNotEmpty)}.toList();

    final query = _locationQuery.trim().toUpperCase();
    final filteredLocations = allLocations.where((loc) {
      if (_selectedZoneFilter != 'ALL' && !loc.zone.toUpperCase().contains(_selectedZoneFilter)) {
        return false;
      }
      if (query.isNotEmpty) {
        final code = loc.locationCode.toUpperCase();
        final id = loc.locationId.toUpperCase();
        final name = loc.displayName.toUpperCase();
        return code.contains(query) || id.contains(query) || name.contains(query);
      }
      return true;
    }).toList();

    return Column(
      children: [
        // 1. 3 KPI Thẻ Chỉ Số: ĐẦY / SẮP HẾT / CÒN TRỐNG
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: c.bgCardElevated,
          child: Row(
            children: [
              Expanded(child: _buildShelfKpiCard('ĐẦY', fullCount, const Color(0xFFEF4444), c)),
              const SizedBox(width: 6),
              Expanded(child: _buildShelfKpiCard('SẮP HẾT', nearFullCount, const Color(0xFFF59E0B), c)),
              const SizedBox(width: 6),
              Expanded(child: _buildShelfKpiCard('CÒN TRỐNG', availCount, const Color(0xFF10B981), c)),
            ],
          ),
        ),

        // 2. Bộ lọc Zone và Thanh tìm kiếm
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _locationSearchCtrl,
                  onChanged: (val) => setState(() => _locationQuery = val),
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'Tìm hoặc quét mã kệ...',
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                    prefixIcon: Icon(Icons.qr_code_scanner, color: c.rfidCyan, size: 20),
                    suffixIcon: _locationQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear, color: c.textMuted, size: 18),
                            onPressed: () {
                              _locationSearchCtrl.clear();
                              setState(() => _locationQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: c.bgCard,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Dropdown Zone
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedZoneFilter,
                    dropdownColor: c.bgCard,
                    items: zones.map((z) => DropdownMenuItem(value: z, child: Text(z == 'ALL' ? 'Tất cả Zone' : 'Zone $z', style: TextStyle(color: c.textPrimary, fontSize: 12)))).toList(),
                    onChanged: (val) => setState(() => _selectedZoneFilter = val ?? 'ALL'),
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3. Danh sách Kệ Hàng PDA
        Expanded(
          child: filteredLocations.isEmpty
              ? Center(child: Text('Không có kệ nào', style: TextStyle(color: c.textMuted)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  itemCount: filteredLocations.length,
                  itemBuilder: (context, idx) {
                    final loc = filteredLocations[idx];
                    return _buildPdaLocationCard(loc, c);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildShelfKpiCard(String label, int count, Color color, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 10)),
        ],
      ),
    );
  }

  Widget _buildPdaLocationCard(Location loc, EyeCareColors c) {
    Color statusColor = const Color(0xFF10B981);
    String statusLabel = 'CÒN TRỐNG';
    if (loc.status.toUpperCase() == 'FULL') {
      statusColor = const Color(0xFFEF4444);
      statusLabel = 'ĐẦY';
    } else if (loc.status.toUpperCase() == 'NEAR_FULL') {
      statusColor = const Color(0xFFF59E0B);
      statusLabel = 'SẮP HẾT';
    }

    final locCode = loc.locationCode.trim().toUpperCase();
    final locId = loc.locationId.trim().toUpperCase();

    // CHỈ ĐẾM CÁC SẢN PHẨM CÒN TỒN KHO (ItemStatus.inStock)
    final itemsOnShelf = _repo.items.where((i) {
      if (i.status != ItemStatus.inStock) return false;
      final itemLoc = i.locationId?.trim().toUpperCase();
      if (itemLoc == null || itemLoc.isEmpty) return false;
      return itemLoc == locCode || itemLoc == locId;
    }).toList();

    final palletsOnShelf = _repo.pallets.where((p) {
      final pLoc = p.locationId?.trim().toUpperCase();
      if (pLoc == null || pLoc.isEmpty) return false;
      return pLoc == locCode || pLoc == locId;
    }).toList();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: c.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.shelves, color: statusColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loc.displayName,
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        'Mã: ${loc.locationCode} • Zone ${loc.zone}',
                        style: TextStyle(color: c.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    statusLabel,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Chỉ số số lượng SP & Pallet
            Row(
              children: [
                Text(
                  '📦 Tồn: ${itemsOnShelf.length} SP',
                  style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
                const SizedBox(width: 12),
                Text(
                  '🏗️ ${palletsOnShelf.length} Pallet',
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                ),
                const Spacer(),
                InkWell(
                  onTap: () => _showShelfItemsDialog(loc, itemsOnShelf, palletsOnShelf, c),
                  child: Text(
                    'Xem chi tiết >',
                    style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(color: c.border, height: 1),
            const SizedBox(height: 8),

            // 3 Nút cập nhật trạng thái nhanh 1-chạm
            Row(
              children: [
                Expanded(
                  child: _buildShelfQuickBtn(
                    label: 'ĐẦY',
                    color: const Color(0xFFEF4444),
                    isSelected: loc.status.toUpperCase() == 'FULL',
                    onTap: () => _updateShelfStatus(loc, 'FULL'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildShelfQuickBtn(
                    label: 'SẮP HẾT',
                    color: const Color(0xFFF59E0B),
                    isSelected: loc.status.toUpperCase() == 'NEAR_FULL',
                    onTap: () => _updateShelfStatus(loc, 'NEAR_FULL'),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: _buildShelfQuickBtn(
                    label: 'CÒN CHỖ',
                    color: const Color(0xFF10B981),
                    isSelected: loc.status.toUpperCase() == 'AVAILABLE',
                    onTap: () => _updateShelfStatus(loc, 'AVAILABLE'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShelfQuickBtn({
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color, width: isSelected ? 1.5 : 1),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.bold,
            fontSize: 10.5,
          ),
        ),
      ),
    );
  }

  Future<void> _updateShelfStatus(Location loc, String newStatus) async {
    HapticFeedback.heavyImpact();
    setState(() {
      loc.status = newStatus;
    });
    await _repo.updateLocationStatus(loc.locationId, newStatus);
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã cập nhật kệ ${loc.locationCode}: $newStatus'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  void _showShelfItemsDialog(Location loc, List<Item> items, List<Pallet> pallets, EyeCareColors c) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bgCard,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (_, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Hàng trên kệ: ${loc.displayName} (${loc.locationCode})',
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              Text('Tổng cộng: ${items.length} sản phẩm • ${pallets.length} pallet', style: TextStyle(color: c.textMuted, fontSize: 12)),
              const Divider(height: 16),
              Expanded(
                child: items.isEmpty
                    ? Center(child: Text('Kệ hiện không có sản phẩm nào', style: TextStyle(color: c.textMuted)))
                    : ListView.builder(
                        controller: scrollCtrl,
                        itemCount: items.length,
                        itemBuilder: (_, i) {
                          final item = items[i];
                          return ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.inventory_2, color: c.rfidCyan, size: 20),
                            title: Text(item.productName, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
                            subtitle: Text('SKU: ${item.sku} • EPC: ${item.epc}', style: TextStyle(color: c.textMuted, fontSize: 11)),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('TỒN KHO', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // TAB 2: QUẢN LÝ LỊCH SỬ
  // ===========================================================================
  Widget _buildHistoryTab(EyeCareColors c) {
    return Column(
      children: [
        // Sub-tabs switcher
        Container(
          padding: const EdgeInsets.all(8),
          color: c.bgCardElevated,
          child: Row(
            children: [
              Expanded(
                child: _buildSubTabButton(
                  title: 'Giao Dịch Kho',
                  icon: Icons.sync_alt,
                  isSelected: _historySubTabIndex == 0,
                  onTap: () => setState(() => _historySubTabIndex = 0),
                  c: c,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSubTabButton(
                  title: 'Nhật Ký (Audit)',
                  icon: Icons.receipt_long,
                  isSelected: _historySubTabIndex == 1,
                  onTap: () => setState(() => _historySubTabIndex = 1),
                  c: c,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _historySubTabIndex == 0 ? _buildTransactionsList(c) : _buildAuditLogList(c),
        ),
      ],
    );
  }

  Widget _buildSubTabButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required EyeCareColors c,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan : c.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? c.rfidCyan : c.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: isSelected ? const Color(0xFF2C251E) : c.textSecondary),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? const Color(0xFF2C251E) : c.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionsList(EyeCareColors c) {
    final txs = _repo.transactions;
    if (txs.isEmpty) {
      return Center(child: Text('Chưa có lịch sử giao dịch nào', style: TextStyle(color: c.textMuted)));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: txs.length,
      itemBuilder: (context, idx) {
        final tx = txs[idx];
        Color typeColor = c.rfidCyan;
        String typeLabel = 'GIAO DỊCH';
        if (tx.type == TransactionType.inbound) {
          typeColor = const Color(0xFF10B981);
          typeLabel = 'NHẬP KHO';
        } else if (tx.type == TransactionType.outbound) {
          typeColor = const Color(0xFF3B82F6);
          typeLabel = 'XUẤT KHO';
        } else if (tx.type == TransactionType.movement) {
          typeColor = const Color(0xFFF59E0B);
          typeLabel = 'CHUYỂN KỆ';
        }

        final timeStr = '${tx.timestamp.day.toString().padLeft(2, '0')}/${tx.timestamp.month.toString().padLeft(2, '0')} ${tx.timestamp.hour.toString().padLeft(2, '0')}:${tx.timestamp.minute.toString().padLeft(2, '0')}';

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.border)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: typeColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text(typeLabel, style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 10)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(tx.documentNo, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')),
                    ),
                    Text(timeStr, style: TextStyle(color: c.textMuted, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 6),
                Text(tx.productName, style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600)),
                Text('SKU: ${tx.sku} • SL: ${tx.quantity}', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                const SizedBox(height: 4),
                Text('Lộ trình: ${tx.fromLocation ?? "N/A"} ➔ ${tx.toLocation ?? "N/A"}', style: TextStyle(color: c.textMuted, fontSize: 11)),
                Text('Người thực hiện: ${tx.performedBy}', style: TextStyle(color: c.textMuted, fontSize: 11)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAuditLogList(EyeCareColors c) {
    final inOrders = _repo.inboundOrders;
    final outOrders = _repo.outboundOrders;

    if (inOrders.isEmpty && outOrders.isEmpty) {
      return Center(child: Text('Chưa có chứng từ đơn hàng nào', style: TextStyle(color: c.textMuted)));
    }

    final allOrders = <Map<String, dynamic>>[];
    for (final o in inOrders) {
      allOrders.add({
        'type': 'INBOUND',
        'code': o.orderNo,
        'partner': o.sourceSupplier,
        'status': o.status.label,
        'time': o.createdAt,
        'items': o.details.fold<int>(0, (sum, d) => sum + d.requiredQty),
      });
    }
    for (final o in outOrders) {
      allOrders.add({
        'type': 'OUTBOUND',
        'code': o.poNo,
        'partner': o.customer,
        'status': o.status.label,
        'time': o.createdAt,
        'items': o.details.fold<int>(0, (sum, d) => sum + d.requiredQty),
      });
    }

    allOrders.sort((a, b) => (b['time'] as DateTime).compareTo(a['time'] as DateTime));

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: allOrders.length,
      itemBuilder: (context, idx) {
        final ord = allOrders[idx];
        final isIn = ord['type'] == 'INBOUND';
        final color = isIn ? const Color(0xFF10B981) : const Color(0xFF3B82F6);
        final dt = ord['time'] as DateTime;
        final timeStr = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          color: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: c.border)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Icon(isIn ? Icons.input_rounded : Icons.output_rounded, color: color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ord['code'] as String, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace')),
                      const SizedBox(height: 2),
                      Text('${ord['partner']} • ${ord['items']} SP', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text(ord['status'] as String, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10)),
                    ),
                    const SizedBox(height: 3),
                    Text(timeStr, style: TextStyle(color: c.textMuted, fontSize: 10.5)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // TAB 3: QUẢN LÝ THÔNG TIN SẢN PHẨM (TRA CỨU TỪ KHÓA & BẮT CÒ SÚNG)
  // ===========================================================================
  Widget _buildProductLookupTab(EyeCareColors c) {
    final allItems = _repo.items;
    final rawQ = _productQuery.trim().toLowerCase();

    final filteredItems = allItems.where((i) {
      if (_selectedProductStatusFilter != null && i.status != _selectedProductStatusFilter) {
        return false;
      }
      if (rawQ.isEmpty) return true;

      final cleanQ = rawQ
          .replaceAll('s/n:', '')
          .replaceAll('sn:', '')
          .replaceAll('product_id:', '')
          .replaceAll('product id:', '')
          .replaceAll('id:', '')
          .replaceAll('sku:', '')
          .replaceAll('epc:', '')
          .trim();
      final q = cleanQ.isNotEmpty ? cleanQ : rawQ;

      final sn = i.serialNumber.toLowerCase();
      final prodId = i.productId.toLowerCase();
      final sku = i.sku.toLowerCase();
      final epc = i.epc.toLowerCase();
      final name = i.productName.toLowerCase();
      final loc = (i.locationId ?? '').toLowerCase();
      final pal = (i.palletId ?? '').toLowerCase();
      final supplier = _repo.getItemSupplier(i).toLowerCase();

      return sn.contains(q) ||
          prodId.contains(q) ||
          sku.contains(q) ||
          epc.contains(q) ||
          name.contains(q) ||
          loc.contains(q) ||
          pal.contains(q) ||
          supplier.contains(q);
    }).toList();

    return Column(
      children: [
        // 1. Thanh tìm kiếm từ khóa + Nút đổi chế độ quét súng
        Container(
          padding: const EdgeInsets.all(10),
          color: c.bgCardElevated,
          child: Column(
            children: [
              TextField(
                controller: _productSearchCtrl,
                onChanged: (val) => setState(() => _productQuery = val),
                style: TextStyle(color: c.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Nhập SKU, tên, barcode, EPC, vị trí...',
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                  prefixIcon: Icon(Icons.search, color: c.rfidCyan, size: 20),
                  suffixIcon: _productQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear, color: c.textMuted, size: 18),
                          onPressed: () {
                            _productSearchCtrl.clear();
                            setState(() => _productQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: c.bgCard,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                ),
              ),
              const SizedBox(height: 8),
              // Bộ lọc trạng thái
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildStatusChip('Tất cả (${allItems.length})', null, c),
                    const SizedBox(width: 6),
                    _buildStatusChip('Đang lưu kho', ItemStatus.inStock, c),
                    const SizedBox(width: 6),
                    _buildStatusChip('Chờ cất kệ', ItemStatus.waitingPutaway, c),
                    const SizedBox(width: 6),
                    _buildStatusChip('Đã xuất kho', ItemStatus.out, c),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 2. Danh sách kết quả sản phẩm
        Expanded(
          child: filteredItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.search_off, size: 40, color: c.textMuted),
                      const SizedBox(height: 8),
                      Text('Không tìm thấy sản phẩm phù hợp', style: TextStyle(color: c.textMuted, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(10),
                  itemCount: filteredItems.length,
                  itemBuilder: (context, idx) {
                    final item = filteredItems[idx];
                    return _buildPdaProductCard(item, c);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStatusChip(String label, ItemStatus? status, EyeCareColors c) {
    final isSelected = _selectedProductStatusFilter == status;
    return InkWell(
      onTap: () => setState(() => _selectedProductStatusFilter = status),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan : c.bgCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? c.rfidCyan : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF2C251E) : c.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildPdaProductCard(Item it, EyeCareColors c) {
    final pallet = _repo.pallets.where((p) => p.palletId == it.palletId || p.palletCode == it.palletId).firstOrNull;
    final loc = it.locationId != null
        ? _repo.locations.where((l) => l.locationId == it.locationId || l.locationCode == it.locationId).firstOrNull
        : (pallet != null ? _repo.locations.where((l) => l.locationId == pallet.locationId || l.locationCode == pallet.locationId).firstOrNull : null);

    // XỬ LÝ CHUẨN XÁC VỊ TRÍ KHI ĐÃ XUẤT KHO:
    final bool isOut = it.status == ItemStatus.out;
    final String locDisplay = isOut
        ? 'ĐÃ XUẤT KHỎI KHO'
        : (loc?.displayName ?? (loc?.locationCode ?? (it.locationId ?? 'Chưa có kệ')));
    final String palletDisplay = isOut ? '---' : (pallet?.palletCode ?? (it.palletId ?? 'Không có'));

    Color statusColor = const Color(0xFF10B981);
    String statusText = 'ĐÃ LƯU KHO';
    if (isOut) {
      statusColor = const Color(0xFF64748B);
      statusText = 'ĐÃ XUẤT KHO';
    } else if (it.status == ItemStatus.waitingPutaway) {
      statusColor = const Color(0xFF06B6D4);
      statusText = 'CHỜ CẤT KỆ';
    } else if (it.status == ItemStatus.waitingPalletize) {
      statusColor = const Color(0xFFF97316);
      statusText = 'CHỜ PALLET';
    } else if (it.status == ItemStatus.pendingInbound) {
      statusColor = const Color(0xFFF59E0B);
      statusText = 'DỰ KIẾN';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: c.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: isOut ? c.border : statusColor.withValues(alpha: 0.5)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Tiêu đề & Trạng thái
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.productName, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5)),
                      const SizedBox(height: 2),
                      Text('SKU: ${it.sku}', style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                  child: Text(statusText, style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Divider(color: c.border, height: 1),
            const SizedBox(height: 8),

            // Vị trí kệ & Pallet
            Row(
              children: [
                Icon(Icons.location_on, size: 14, color: isOut ? c.textMuted : const Color(0xFFEF4444)),
                const SizedBox(width: 4),
                Text('Kệ: ', style: TextStyle(color: c.textMuted, fontSize: 11.5)),
                Expanded(
                  child: Text(
                    locDisplay,
                    style: TextStyle(
                      color: isOut ? c.textMuted : c.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.pallet, size: 14, color: isOut ? c.textMuted : const Color(0xFFF59E0B)),
                const SizedBox(width: 4),
                Text('Pallet: ', style: TextStyle(color: c.textMuted, fontSize: 11.5)),
                Text(
                  palletDisplay,
                  style: TextStyle(color: isOut ? c.textMuted : c.textPrimary, fontSize: 11.5),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // S/N & EPC
            if (it.serialNumber.isNotEmpty)
              Text('S/N: ${it.serialNumber}', style: TextStyle(color: c.textSecondary, fontSize: 11, fontFamily: 'monospace')),
            Text('EPC: ${it.epc}', style: TextStyle(color: c.rfidCyan, fontSize: 10.5, fontFamily: 'monospace')),

            // Nút chuyển vị trí kệ nếu hàng còn trong kho
            if (!isOut) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                    side: const BorderSide(color: Color(0xFF10B981)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                  icon: const Icon(Icons.drive_file_move_rounded, size: 14),
                  label: const Text('Đổi kệ / Chuyển vị trí', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PdaTransferScreen(initialItem: it)),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMiniKpiBadge(String text, Color color, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
    );
  }
}
