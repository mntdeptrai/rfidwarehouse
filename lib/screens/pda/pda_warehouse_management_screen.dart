import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/wms_models.dart';
import '../../services/warehouse_repository.dart';
import '../../services/uhf_service.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_sync_service.dart';
import '../../theme/eye_care_theme.dart';
import '../../widgets/hardware_status_appbar.dart';
import 'pda_transfer_screen.dart';
import '../../widgets/app_notification_bar.dart';

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

  // Tab 2: Lịch Sử (Đồng bộ 5 mục đầy đủ với Desktop: Tất cả, Nhập kho, Xuất kho, Điều chuyển, Kiểm kê)
  final TextEditingController _historySearchCtrl = TextEditingController();
  String _historyQuery = '';
  String _historyCategoryFilter = 'ALL'; // ALL, INBOUND, OUTBOUND, MOVEMENT, AUDIT
  String _historyStatusFilter = 'ALL'; // ALL, COMPLETED, IN_PROGRESS
  bool _isHistoryRefreshing = false;

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
    _historySearchCtrl.dispose();
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
                AppSnackBar.showSuccess(context, '✓ Đã xóa thành công Pallet "${p.palletCode}"!');
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
                AppSnackBar.showSuccess(context, '✓ Đã tạo thành công Pallet "$code"!');
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
          title: Row(
            children: [
              Icon(Icons.shelves, color: c.rfidCyan, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gán Vị Trí Kệ: ${p.palletCode}',
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_repo.locations.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('Chưa có vị trí kệ nào trong kho.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                  )
                else
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _repo.locations.any((l) => l.locationId == selectedLocId) ? selectedLocId : null,
                    dropdownColor: c.bgCard,
                    decoration: InputDecoration(
                      labelText: 'Chọn Vị Trí Kệ',
                      labelStyle: TextStyle(color: c.textSecondary),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.rfidCyan, width: 1.5)),
                    ),
                    items: _repo.locations.map((loc) {
                      return DropdownMenuItem(
                        value: loc.locationId,
                        child: Text(
                          '${loc.locationCode} (${loc.displayName})',
                          style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      );
                    }).toList(),
                    onChanged: (val) => setDlgState(() => selectedLocId = val),
                  ),
              ],
            ),
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
              onPressed: selectedLocId == null
                  ? null
                  : () {
                      _repo.movePallet(
                        palletId: p.palletId,
                        newLocationId: selectedLocId!,
                        performedBy: _auth.currentUser?.fullName ?? 'Thủ kho PDA',
                      );
                      Navigator.pop(ctx);
                      setState(() {});
                      if (mounted) {
                        final loc = _repo.locations.where((l) => l.locationId == selectedLocId).firstOrNull;
                        final locDisplay = loc?.displayName ?? loc?.locationCode ?? selectedLocId;
                        AppSnackBar.showSuccess(context, '✓ Đã xếp Pallet lên kệ $locDisplay thành công!');
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
    AppSnackBar.showSuccess(context, '✓ Đã cập nhật kệ ${loc.locationCode}: $newStatus');
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
  // TAB 2: QUẢN LÝ LỊCH SỬ (ĐỒNG BỘ ĐẦY ĐỦ 5 MỤC NHƯ DESKTOP)
  // ===========================================================================
  Widget _buildHistoryTab(EyeCareColors c) {
    final historyRecords = <Map<String, dynamic>>[];
    final allInboundOrders = _repo.inboundOrders;
    final allOutboundOrders = _repo.outboundOrders;
    final allSessions = _repo.inventorySessions;
    final allTransactions = _repo.transactions;
    final allItems = _repo.items;

    // 1. Đơn nhập kho
    for (var o in allInboundOrders) {
      final ordItems = allItems.where((i) =>
          i.orderNo != null && i.orderNo!.trim().toUpperCase() == o.orderNo.trim().toUpperCase()).toList();
      var totalQty = o.details.fold<int>(0, (sum, d) => sum + d.requiredQty);
      var receivedQty = o.details.fold<int>(0, (sum, d) => sum + d.receivedQty);
      if (totalQty == 0 && ordItems.isNotEmpty) {
        totalQty = ordItems.length;
        receivedQty = ordItems.where((i) => i.status == ItemStatus.inStock || i.status == ItemStatus.waitingPutaway).length;
      }
      final pallets = ordItems.map((i) => i.palletId).where((p) => p != null && p.isNotEmpty).cast<String>().toSet().toList();

      historyRecords.add({
        'recordType': 'INBOUND',
        'isOutbound': false,
        'orderNo': o.orderNo,
        'orderId': o.inboundOrderId,
        'partner': o.sourceSupplier.isNotEmpty ? o.sourceSupplier : 'Nhà cung cấp',
        'createdAt': o.createdAt,
        'status': o.status,
        'statusLabel': o.status == InboundOrderStatus.completed ? 'ĐÃ HOÀN TẤT' : (o.status == InboundOrderStatus.processing ? 'ĐANG NHẬN HÀNG' : 'MỚI TẠO'),
        'totalQty': totalQty,
        'doneQty': receivedQty,
        'pallets': pallets,
        'details': o.details,
        'items': ordItems,
        'inboundOrder': o,
      });
    }

    // 2. Đơn xuất kho
    for (var o in allOutboundOrders) {
      final relatedTxs = allTransactions.where((t) =>
          t.type == TransactionType.outbound &&
          (t.documentNo.trim().toUpperCase() == o.poNo.trim().toUpperCase() ||
           t.documentNo.trim().toUpperCase() == o.outboundOrderId.trim().toUpperCase() ||
           (o.poNo.isNotEmpty && t.transactionId.contains(o.poNo)) ||
           (o.outboundOrderId.isNotEmpty && t.transactionId.contains(o.outboundOrderId)))).toList();
      final txQty = relatedTxs.fold<int>(0, (sum, t) => sum + t.quantity);

      final ordItems = allItems.where((i) =>
          i.orderNo != null &&
          (i.orderNo!.trim().toUpperCase() == o.poNo.trim().toUpperCase() ||
           i.orderNo!.trim().toUpperCase() == o.outboundOrderId.trim().toUpperCase())).toList();

      var totalQty = o.details.fold<int>(0, (sum, d) => sum + d.requiredQty);
      var pickedQty = o.details.fold<int>(0, (sum, d) => sum + d.pickedQty);

      if (totalQty == 0) {
        if (txQty > 0) {
          totalQty = txQty;
          pickedQty = txQty;
        } else if (ordItems.isNotEmpty) {
          totalQty = ordItems.length;
          pickedQty = ordItems.where((i) => i.status == ItemStatus.out).length;
          if (pickedQty == 0 && o.status == OutboundOrderStatus.shipped) {
            pickedQty = totalQty;
          }
        }
      } else if (pickedQty == 0 && o.status == OutboundOrderStatus.shipped) {
        pickedQty = totalQty;
      }

      final pallets = <String>{
        ...relatedTxs.map((t) => t.palletCode).where((p) => p != null && p.isNotEmpty).cast<String>(),
        ...ordItems.map((i) => i.palletId).where((p) => p != null && p.isNotEmpty).cast<String>(),
      }.toList();

      historyRecords.add({
        'recordType': 'OUTBOUND',
        'isOutbound': true,
        'orderNo': o.poNo,
        'orderId': o.outboundOrderId,
        'partner': o.customer.isNotEmpty ? o.customer : 'Khách hàng xuất kho',
        'createdAt': o.createdAt,
        'status': o.status,
        'statusLabel': o.status == OutboundOrderStatus.shipped ? 'ĐÃ XUẤT KHO' : 'ĐANG XỬ LÝ',
        'totalQty': totalQty,
        'doneQty': pickedQty,
        'pallets': pallets,
        'details': o.details,
        'items': ordItems,
        'outboundOrder': o,
        'transaction': relatedTxs.firstOrNull,
      });
    }

    // 3. Đợt kiểm kê kho (Inventory Sessions)
    for (var s in allSessions) {
      final locDisplay = (s.locationCode != null && s.locationCode!.isNotEmpty)
          ? 'Kệ: ${s.locationCode} (${s.zone})'
          : 'Khu vực: ${s.zone}';

      historyRecords.add({
        'recordType': 'AUDIT',
        'isOutbound': false,
        'orderNo': s.sessionCode.isNotEmpty ? s.sessionCode : s.sessionId,
        'orderId': s.sessionId,
        'partner': locDisplay,
        'createdAt': s.completedAt ?? s.startedAt,
        'status': s.isCompleted ? InboundOrderStatus.completed : InboundOrderStatus.processing,
        'statusLabel': s.isCompleted ? 'ĐÃ KIỂM KÊ' : 'ĐANG KIỂM KÊ',
        'totalQty': s.actualScannedCount,
        'doneQty': s.matchCount,
        'pallets': <String>[],
        'details': <dynamic>[],
        'items': <Item>[],
        'session': s,
      });
    }

    // 4. Biến động kho: Điều chuyển vị trí kệ/Pallet & Giao dịch chưa đại diện
    for (var t in allTransactions) {
      if (t.type == TransactionType.movement || t.type == TransactionType.auditAdjustment) {
        final isMove = t.type == TransactionType.movement;
        final typeCode = isMove ? 'MOVEMENT' : 'AUDIT';
        final typeName = isMove ? 'ĐIỀU CHUYỂN' : 'ĐIỀU CHỈNH';
        final route = t.toLocation != null
            ? '${t.fromLocation ?? "--"} → ${t.toLocation}'
            : (t.palletCode != null ? 'Pallet: ${t.palletCode}' : 'Điều chỉnh kho');

        historyRecords.add({
          'recordType': typeCode,
          'isOutbound': false,
          'orderNo': t.documentNo.isNotEmpty ? t.documentNo : t.transactionId,
          'orderId': t.transactionId,
          'partner': route,
          'createdAt': t.timestamp,
          'status': InboundOrderStatus.completed,
          'statusLabel': typeName,
          'totalQty': t.quantity,
          'doneQty': t.quantity,
          'pallets': t.palletCode != null && t.palletCode!.isNotEmpty ? [t.palletCode!] : <String>[],
          'details': <dynamic>[],
          'items': <Item>[],
          'transaction': t,
        });
      } else if (t.type == TransactionType.outbound) {
        final doc = t.documentNo.trim();
        final alreadyRepresented = historyRecords.any((h) =>
            h['recordType'] == 'OUTBOUND' &&
            (h['orderNo'] == doc || h['orderId'] == doc || h['orderId'] == t.transactionId));
        if (!alreadyRepresented) {
          historyRecords.add({
            'recordType': 'OUTBOUND',
            'isOutbound': true,
            'orderNo': t.documentNo.isNotEmpty ? t.documentNo : t.transactionId,
            'orderId': t.transactionId,
            'partner': t.toLocation ?? 'Khách mua xuất kho',
            'createdAt': t.timestamp,
            'status': OutboundOrderStatus.shipped,
            'statusLabel': 'ĐÃ XUẤT KHO',
            'totalQty': t.quantity,
            'doneQty': t.quantity,
            'pallets': t.palletCode != null && t.palletCode!.isNotEmpty ? [t.palletCode!] : <String>[],
            'details': <dynamic>[],
            'items': <Item>[],
            'transaction': t,
          });
        }
      } else if (t.type == TransactionType.inbound) {
        final doc = t.documentNo.trim();
        final alreadyRepresented = historyRecords.any((h) =>
            h['recordType'] == 'INBOUND' &&
            (h['orderNo'] == doc || h['orderId'] == doc || h['orderId'] == t.transactionId));
        if (!alreadyRepresented) {
          historyRecords.add({
            'recordType': 'INBOUND',
            'isOutbound': false,
            'orderNo': t.documentNo.isNotEmpty ? t.documentNo : t.transactionId,
            'orderId': t.transactionId,
            'partner': t.fromLocation ?? 'Nhà cung cấp',
            'createdAt': t.timestamp,
            'status': InboundOrderStatus.completed,
            'statusLabel': 'ĐÃ NHẬP KHO',
            'totalQty': t.quantity,
            'doneQty': t.quantity,
            'pallets': t.palletCode != null && t.palletCode!.isNotEmpty ? [t.palletCode!] : <String>[],
            'details': <dynamic>[],
            'items': <Item>[],
            'transaction': t,
          });
        }
      }
    }

    // Sắp xếp thời gian mới nhất lên đầu
    historyRecords.sort((a, b) => (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));

    // Thống kê số lượng theo 5 mục nghiệp vụ
    final totalInbound = historyRecords.where((h) => h['recordType'] == 'INBOUND').length;
    final totalOutbound = historyRecords.where((h) => h['recordType'] == 'OUTBOUND').length;
    final totalMovement = historyRecords.where((h) => h['recordType'] == 'MOVEMENT').length;
    final totalAudit = historyRecords.where((h) => h['recordType'] == 'AUDIT').length;
    final totalAll = historyRecords.length;

    // Lọc theo mục, trạng thái và từ khóa tìm kiếm
    final q = _historyQuery.trim().toLowerCase();
    final filteredHistory = historyRecords.where((h) {
      final recType = h['recordType'] as String? ?? '';
      if (_historyCategoryFilter == 'INBOUND' && recType != 'INBOUND') return false;
      if (_historyCategoryFilter == 'OUTBOUND' && recType != 'OUTBOUND') return false;
      if (_historyCategoryFilter == 'MOVEMENT' && recType != 'MOVEMENT') return false;
      if (_historyCategoryFilter == 'AUDIT' && recType != 'AUDIT') return false;

      final statusLabel = (h['statusLabel'] as String).toUpperCase();
      if (_historyStatusFilter == 'COMPLETED' &&
          (!statusLabel.contains('ĐÃ') && !statusLabel.contains('HOÀN THÀNH') && statusLabel != 'ĐIỀU CHUYỂN')) {
        return false;
      }
      if (_historyStatusFilter == 'IN_PROGRESS' &&
          (statusLabel.contains('ĐÃ') || statusLabel.contains('HOÀN THÀNH') || statusLabel == 'ĐIỀU CHUYỂN')) {
        return false;
      }

      if (q.isEmpty) return true;

      final ordNo = (h['orderNo'] as String).toLowerCase();
      final partner = (h['partner'] as String).toLowerCase();
      final pallets = (h['pallets'] as List).join(' ').toLowerCase();

      return ordNo.contains(q) || partner.contains(q) || pallets.contains(q);
    }).toList();

    return Column(
      children: [
        // 1. Thanh danh mục 5 mục nghiệp vụ cuộn ngang (Tất cả, Nhập kho, Xuất kho, Điều chuyển, Kiểm kê)
        Container(
          height: 48,
          color: c.bgCardElevated,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              children: [
                _buildHistoryCategoryChip(
                  label: 'TẤT CẢ ($totalAll)',
                  icon: Icons.list_alt_rounded,
                  categoryCode: 'ALL',
                  color: c.rfidCyan,
                  c: c,
                ),
                const SizedBox(width: 6),
                _buildHistoryCategoryChip(
                  label: 'NHẬP KHO ($totalInbound)',
                  icon: Icons.input_rounded,
                  categoryCode: 'INBOUND',
                  color: const Color(0xFF10B981),
                  c: c,
                ),
                const SizedBox(width: 6),
                _buildHistoryCategoryChip(
                  label: 'XUẤT KHO ($totalOutbound)',
                  icon: Icons.output_rounded,
                  categoryCode: 'OUTBOUND',
                  color: const Color(0xFF3B82F6),
                  c: c,
                ),
                const SizedBox(width: 6),
                _buildHistoryCategoryChip(
                  label: 'ĐIỀU CHUYỂN ($totalMovement)',
                  icon: Icons.sync_alt_rounded,
                  categoryCode: 'MOVEMENT',
                  color: const Color(0xFFF59E0B),
                  c: c,
                ),
                const SizedBox(width: 6),
                _buildHistoryCategoryChip(
                  label: 'KIỂM KÊ ($totalAudit)',
                  icon: Icons.fact_check_rounded,
                  categoryCode: 'AUDIT',
                  color: const Color(0xFF8B5CF6),
                  c: c,
                ),
              ],
            ),
          ),
        ),

        // 2. Ô tìm kiếm đa năng + Bộ lọc trạng thái & Nút Làm Mới
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          color: c.bgCard,
          child: Column(
            children: [
              // Search input
              TextField(
                controller: _historySearchCtrl,
                onChanged: (val) => setState(() => _historyQuery = val),
                style: TextStyle(color: c.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Tìm theo Mã Đơn, SKU, Pallet, Vị trí, Đối tác...',
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                  prefixIcon: Icon(Icons.search_rounded, color: c.rfidCyan, size: 18),
                  suffixIcon: _historyQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(Icons.clear_rounded, color: c.textMuted, size: 16),
                          onPressed: () {
                            _historySearchCtrl.clear();
                            setState(() => _historyQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: c.bgDeep,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.rfidCyan)),
                ),
              ),
              const SizedBox(height: 6),
              // Filter status buttons & Refresh
              Row(
                children: [
                  _buildHistoryStatusChip('Tất cả', 'ALL', c),
                  const SizedBox(width: 4),
                  _buildHistoryStatusChip('Đã hoàn tất', 'COMPLETED', c),
                  const SizedBox(width: 4),
                  _buildHistoryStatusChip('Đang xử lý', 'IN_PROGRESS', c),
                  const Spacer(),
                  InkWell(
                    onTap: _isHistoryRefreshing ? null : _refreshHistory,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: c.bgCardElevated,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _isHistoryRefreshing
                              ? SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: c.rfidCyan),
                                )
                              : Icon(Icons.refresh_rounded, size: 13, color: c.textPrimary),
                          const SizedBox(width: 4),
                          Text('LÀM MỚI', style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 3. Danh sách lịch sử giao dịch & nghiệp vụ
        Expanded(
          child: filteredHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.history_rounded, size: 48, color: c.textMuted.withValues(alpha: 0.5)),
                      const SizedBox(height: 8),
                      Text('Không tìm thấy lịch sử phù hợp bộ lọc', style: TextStyle(color: c.textMuted, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 16),
                  itemCount: filteredHistory.length,
                  itemBuilder: (context, idx) {
                    final rec = filteredHistory[idx];
                    return _buildHistoryItemCard(rec, c);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildHistoryCategoryChip({
    required String label,
    required IconData icon,
    required String categoryCode,
    required Color color,
    required EyeCareColors c,
  }) {
    final isSelected = _historyCategoryFilter == categoryCode;
    return InkWell(
      onTap: () => setState(() => _historyCategoryFilter = categoryCode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.18) : c.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? color : c.border, width: isSelected ? 1.5 : 1.0),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? color : c.textSecondary),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : c.textSecondary,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryStatusChip(String label, String code, EyeCareColors c) {
    final isSelected = _historyStatusFilter == code;
    return InkWell(
      onTap: () => setState(() => _historyStatusFilter = code),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan.withValues(alpha: 0.2) : c.bgDeep,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: isSelected ? c.rfidCyan : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? c.rfidCyan : c.textMuted,
            fontSize: 10.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryItemCard(Map<String, dynamic> rec, EyeCareColors c) {
    final recType = rec['recordType'] as String? ?? 'INBOUND';
    Color typeColor = const Color(0xFF10B981);
    IconData typeIcon = Icons.input_rounded;
    String typeLabel = 'NHẬP KHO';

    if (recType == 'OUTBOUND') {
      typeColor = const Color(0xFF3B82F6);
      typeIcon = Icons.output_rounded;
      typeLabel = 'XUẤT KHO';
    } else if (recType == 'MOVEMENT') {
      typeColor = const Color(0xFFF59E0B);
      typeIcon = Icons.sync_alt_rounded;
      typeLabel = 'ĐIỀU CHUYỂN';
    } else if (recType == 'AUDIT') {
      typeColor = const Color(0xFF8B5CF6);
      typeIcon = Icons.fact_check_rounded;
      typeLabel = 'KIỂM KÊ';
    }

    final orderNo = rec['orderNo']?.toString() ?? '--';
    final partner = rec['partner']?.toString() ?? '--';
    final statusLabel = rec['statusLabel']?.toString() ?? '--';
    final totalQty = (rec['totalQty'] as num?)?.toInt() ?? 0;
    final doneQty = (rec['doneQty'] as num?)?.toInt() ?? 0;
    final pallets = (rec['pallets'] as List?)?.cast<String>() ?? [];
    final dt = rec['createdAt'] as DateTime? ?? DateTime.now();
    final timeStr = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: c.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border),
      ),
      child: InkWell(
        onTap: () => _showHistoryDetailDialog(context, rec, c),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hàng 1: Icon box + Mã chứng từ + Type badge + Thời gian
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(typeIcon, color: typeColor, size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            orderNo,
                            style: TextStyle(
                              color: c.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: typeColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            typeLabel,
                            style: TextStyle(color: typeColor, fontWeight: FontWeight.bold, fontSize: 9.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(timeStr, style: TextStyle(color: c.textMuted, fontSize: 10.5)),
                ],
              ),
              const SizedBox(height: 8),

              // Hàng 2: Đối tác / Lộ trình điều chuyển / Kệ kiểm kê
              Row(
                children: [
                  Icon(
                    recType == 'MOVEMENT'
                        ? Icons.route_rounded
                        : (recType == 'AUDIT' ? Icons.location_on_outlined : Icons.business_outlined),
                    size: 13,
                    color: c.textSecondary,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      partner,
                      style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Hàng 3: Chip Số lượng + Pallet + Chip trạng thái
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.bgCardElevated,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      recType == 'MOVEMENT'
                          ? 'SL: $totalQty SP'
                          : (recType == 'AUDIT' ? 'Khớp: $doneQty / $totalQty' : 'SL: $doneQty / $totalQty'),
                      style: TextStyle(color: c.textPrimary, fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (pallets.isNotEmpty) ...[
                    const SizedBox(width: 5),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.rfidCyan.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        pallets.length == 1 ? pallets.first : '${pallets.length} Pallets',
                        style: TextStyle(color: c.rfidCyan, fontSize: 10, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                    decoration: BoxDecoration(
                      color: typeColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHistoryDetailDialog(BuildContext context, Map<String, dynamic> record, EyeCareColors c) {
    final recType = record['recordType'] as String? ?? '';
    final trans = record['transaction'] as InventoryTransaction?;
    final session = record['session'] as InventorySession?;
    final inOrd = record['inboundOrder'] as InboundOrder?;
    final outOrd = record['outboundOrder'] as OutboundOrder?;
    final dt = record['createdAt'] as DateTime? ?? DateTime.now();
    final timeStr = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.92,
          expand: false,
          builder: (_, scrollCtrl) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: ListView(
                controller: scrollCtrl,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: c.textMuted.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tiêu đề
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CHI TIẾT ${recType == "MOVEMENT" ? "ĐIỀU CHUYỂN" : (recType == "AUDIT" ? "KIỂM KÊ" : (recType == "OUTBOUND" ? "XUẤT KHO" : "NHẬP KHO"))}',
                              style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              record['orderNo']?.toString() ?? '--',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.bgCardElevated,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.border),
                        ),
                        child: Text(
                          record['statusLabel']?.toString() ?? '',
                          style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Divider(color: c.border, height: 1),
                  const SizedBox(height: 12),

                  // Thông tin cơ bản
                  _buildDetailRow('Thời gian', timeStr, c),
                  _buildDetailRow('Đối tác / Vị trí', record['partner']?.toString() ?? '--', c),
                  if (trans != null && trans.performedBy.isNotEmpty)
                    _buildDetailRow('Người thực hiện', trans.performedBy, c),
                  if (trans != null && (trans.notes?.isNotEmpty ?? false))
                    _buildDetailRow('Ghi chú', trans.notes!, c),

                  const SizedBox(height: 14),

                  // Chi tiết theo từng loại nghiệp vụ
                  if (recType == 'AUDIT' && session != null) ...[
                    Row(
                      children: [
                        Expanded(
                          child: _buildMetricMiniCard('ĐÃ QUÉT', '${session.actualScannedCount}', c.textPrimary, c),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricMiniCard('KHỚP', '${session.matchCount}', const Color(0xFF10B981), c),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildMetricMiniCard(
                            'LỆCH',
                            '${(session.actualScannedCount - session.matchCount).abs()}',
                            const Color(0xFFEF4444),
                            c,
                          ),
                        ),
                      ],
                    ),
                  ] else if (recType == 'MOVEMENT' && trans != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.bgCardElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('LỘ TRÌNH ĐIỀU CHUYỂN', style: TextStyle(color: c.textMuted, fontSize: 10.5, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: Text('Từ: ${trans.fromLocation ?? "--"}', style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                              ),
                              Icon(Icons.arrow_forward_rounded, color: c.rfidCyan, size: 16),
                              Expanded(
                                child: Text('Đến: ${trans.toLocation ?? "--"}', style: TextStyle(color: c.rfidCyan, fontSize: 13, fontWeight: FontWeight.bold), textAlign: TextAlign.right),
                              ),
                            ],
                          ),
                          if (trans.palletCode != null && trans.palletCode!.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text('Mã Pallet: ${trans.palletCode}', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                          ],
                          const SizedBox(height: 4),
                          Text('Mặt hàng: ${trans.productName} (SKU: ${trans.sku}) • SL: ${trans.quantity}', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ] else if (inOrd != null && inOrd.details.isNotEmpty) ...[
                    Text('DANH SÁCH MẶT HÀNG NHẬP KHO', style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...inOrd.details.map((d) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: c.bgCardElevated,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.productName, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12)),
                                Text('SKU: ${d.sku}', style: TextStyle(color: c.textMuted, fontSize: 10.5)),
                              ],
                            ),
                          ),
                          Text('SL: ${d.receivedQty} / ${d.requiredQty}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    )),
                  ] else if (outOrd != null && outOrd.details.isNotEmpty) ...[
                    Text('DANH SÁCH MẶT HÀNG XUẤT KHO', style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...outOrd.details.map((d) => Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: c.bgCardElevated,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(d.productName, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12)),
                                Text('SKU: ${d.sku}', style: TextStyle(color: c.textMuted, fontSize: 10.5)),
                              ],
                            ),
                          ),
                          Text('SL: ${d.pickedQty} / ${d.requiredQty}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    )),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.bgCardElevated,
                        foregroundColor: c.textPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: c.border)),
                      ),
                      child: const Text('ĐÓNG', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value, EyeCareColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(color: c.textMuted, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricMiniCard(String label, String value, Color color, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      decoration: BoxDecoration(
        color: c.bgCardElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color, fontSize: 15, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Future<void> _refreshHistory() async {
    setState(() => _isHistoryRefreshing = true);
    try {
      await SupabaseSyncService().syncNow();
    } catch (_) {
      await _repo.reloadFromSqlite();
    } finally {
      if (mounted) {
        setState(() => _isHistoryRefreshing = false);
      }
    }
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
