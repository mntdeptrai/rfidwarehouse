import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/wms_models.dart';
import '../../services/warehouse_repository.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/uhf_service.dart';
import '../../services/supabase_sync_service.dart';
import '../../theme/eye_care_theme.dart';
import 'desktop_location_management_view.dart';
import 'desktop_lookup_view.dart';
import '../../widgets/app_notification_bar.dart';

class _PalletGroupSummary {
  final String sku;
  final String productName;
  int quantity;
  DateTime inboundTime;
  final List<Item> items;

  _PalletGroupSummary({
    required this.sku,
    required this.productName,
    required this.quantity,
    required this.inboundTime,
    required this.items,
  });
}

class DesktopWarehouseManagementView extends StatefulWidget {
  const DesktopWarehouseManagementView({super.key});

  @override
  State<DesktopWarehouseManagementView> createState() => _DesktopWarehouseManagementViewState();
}

class _DesktopWarehouseManagementViewState extends State<DesktopWarehouseManagementView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final WarehouseRepository _repo = WarehouseRepository();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final DesktopUhfTcpService _desktopUhf = DesktopUhfTcpService();
  final UhfService _uhf = UhfService();
  final SupabaseSyncService _supabaseSync = SupabaseSyncService();

  // Pallet tab state
  final TextEditingController _palletSearchCtrl = TextEditingController();
  String _palletSearchQuery = '';
  String _palletFilter = 'ALL'; // ALL, IN_USE, EMPTY, HAS_RFID, NO_RFID

  // History tab state
  final TextEditingController _historySearchCtrl = TextEditingController();
  String _historySearchQuery = '';
  String _historyTypeFilter = 'ALL'; // ALL, INBOUND, OUTBOUND, MOVEMENT
  String _historyStatusFilter = 'ALL'; // ALL, COMPLETED, IN_PROGRESS

  StreamSubscription? _desktopUhfSub;
  StreamSubscription? _uhfSub;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _eyeCare.addListener(_onStateUpdate);
    _repo.addListener(_onStateUpdate);
  }

  @override
  void dispose() {
    _desktopUhfSub?.cancel();
    _uhfSub?.cancel();
    _tabController.dispose();
    _palletSearchCtrl.dispose();
    _historySearchCtrl.dispose();
    _repo.removeListener(_onStateUpdate);
    _eyeCare.removeListener(_onStateUpdate);
    super.dispose();
  }

  void _onStateUpdate() {
    if (mounted) setState(() {});
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

  String _convertPalletCodeToHex(String code) {
    if (code.trim().isEmpty) return '';
    final hexString = code.trim().codeUnits
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join('');
    if (hexString.length >= 24) {
      return hexString.substring(0, 24);
    }
    return hexString.padRight(24, '0');
  }

  // ==========================================
  // BUILD METHOD
  // ==========================================
  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return Container(
      color: c.bgDeep,
      child: Column(
        children: [
          // 1. Header Bar with Tabs
          _buildHeaderBar(c),

          // 2. Tab Content Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildPalletManagementTab(c),
                const DesktopLocationManagementView(),
                _buildHistoryManagementTab(c),
                const DesktopLookupView(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // HEADER & TAB BAR
  // ==========================================
  Widget _buildHeaderBar(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.rfidCyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
              ),
              child: Icon(Icons.warehouse_rounded, color: c.rfidCyan, size: 24),
            ),
            const SizedBox(width: 14),
            Text(
              'QUẢN LÝ KHO & LỊCH SỬ GIAO DỊCH',
              style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(width: 24),

            // Tab Navigation Buttons
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: c.bgDeep,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildTabButton(0, Icons.layers_outlined, 'Quản Lý Pallet', c),
                  const SizedBox(width: 4),
                  _buildTabButton(1, Icons.grid_view_rounded, 'Quản Lý Vị Trí Kho', c),
                  const SizedBox(width: 4),
                  _buildTabButton(2, Icons.history_rounded, 'Quản Lý Lịch Sử', c),
                  const SizedBox(width: 4),
                  _buildTabButton(3, Icons.inventory_2_outlined, 'Thông Tin Sản Phẩm', c),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabButton(int index, IconData icon, String title, EyeCareColors c) {
    final isSelected = _tabController.index == index;

    return InkWell(
      onTap: () {
        setState(() {
          _tabController.animateTo(index);
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : c.textSecondary),
            const SizedBox(width: 8),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : c.textSecondary,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==========================================
  // TAB 1: QUẢN LÝ PALLET
  // ==========================================
  Widget _buildPalletManagementTab(EyeCareColors c) {
    final allPallets = _repo.pallets;
    final allItems = _repo.items;

    // Filter logic
    final q = _palletSearchQuery.trim().toLowerCase();
    final filteredPallets = allPallets.where((p) {
      final matchesSearch = q.isEmpty ||
          p.palletCode.toLowerCase().contains(q) ||
          p.displayName.toLowerCase().contains(q) ||
          (p.rfidEpc != null && p.rfidEpc!.toLowerCase().contains(q)) ||
          (p.locationId != null && p.locationId!.toLowerCase().contains(q));

      if (!matchesSearch) return false;

      final palletItems = allItems.where((i) => (i.palletId == p.palletId || i.palletId == p.palletCode) && i.status != ItemStatus.out).toList();
      final hasItems = palletItems.isNotEmpty;
      final hasRfid = p.rfidEpc != null && p.rfidEpc!.trim().isNotEmpty;

      switch (_palletFilter) {
        case 'IN_USE':
          return hasItems;
        case 'EMPTY':
          return !hasItems;
        case 'HAS_RFID':
          return hasRfid;
        case 'NO_RFID':
          return !hasRfid;
        default:
          return true;
      }
    }).toList();

    // Stats
    final totalPallets = allPallets.length;
    final rfidPallets = allPallets.where((p) => p.rfidEpc != null && p.rfidEpc!.trim().isNotEmpty).length;
    final inUsePallets = allPallets.where((p) => allItems.any((i) => (i.palletId == p.palletId || i.palletId == p.palletCode) && i.status != ItemStatus.out)).length;
    final emptyPallets = totalPallets - inUsePallets;

    return LayoutBuilder(
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
          // 3 Metric Tiles
          Row(
            children: [
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.layers_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: 'TỔNG SỐ PALLET',
                  value: '$totalPallets Pallet',
                  c: c,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.inventory_2_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: 'ĐANG CÓ HÀNG',
                  value: '$inUsePallets Pallet',
                  c: c,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildMetricTile(
                  icon: Icons.check_circle_outline_rounded,
                  iconColor: const Color(0xFF3B82F6),
                  title: 'PALLET TRỐNG',
                  value: '$emptyPallets Pallet',
                  c: c,
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Search & Filter Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                // Search Input
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _palletSearchCtrl,
                      onChanged: (val) => setState(() => _palletSearchQuery = val),
                      style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                      decoration: InputDecoration(
                        hintText: 'Tìm theo Mã Pallet, Tên, Mã RFID EPC, Kệ lưu...',
                        hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                        prefixIcon: Icon(Icons.search, size: 18, color: c.textSecondary),
                        suffixIcon: _palletSearchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _palletSearchCtrl.clear();
                                  setState(() => _palletSearchQuery = '');
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

                // Filter Pills
                _buildFilterPill('Tất cả ($totalPallets)', 'ALL', _palletFilter, (f) => setState(() => _palletFilter = f), c),
                const SizedBox(width: 6),
                _buildFilterPill('Đang có hàng ($inUsePallets)', 'IN_USE', _palletFilter, (f) => setState(() => _palletFilter = f), c),
                const SizedBox(width: 6),
                _buildFilterPill('Pallet trống ($emptyPallets)', 'EMPTY', _palletFilter, (f) => setState(() => _palletFilter = f), c),
                const SizedBox(width: 6),
                _buildFilterPill('Có chip RFID ($rfidPallets)', 'HAS_RFID', _palletFilter, (f) => setState(() => _palletFilter = f), c),

                const Spacer(),

                // Add Pallet Button
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('THÊM PALLET MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () => _showAddOrEditPalletDialog(context, c),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // Pallet Data Table
          Expanded(
            child: Container(
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
                        SizedBox(width: 45, child: Text('STT', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        Expanded(flex: 2, child: Text('MÃ PALLET (BARCODE)', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        Expanded(flex: 3, child: Text('EPC', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        Expanded(flex: 2, child: Text('VỊ TRÍ KỆ', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        Expanded(flex: 2, child: Text('SỐ LƯỢNG HÀNG', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        SizedBox(width: 120, child: Text('TRẠNG THÁI', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        SizedBox(width: 170, child: Text('THAO TÁC', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),

                  // Table Body
                  Expanded(
                    child: filteredPallets.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.layers_outlined, size: 48, color: c.textMuted),
                                const SizedBox(height: 10),
                                Text(
                                  allPallets.isEmpty
                                      ? 'Chưa có Pallet nào trong cơ sở dữ liệu kho.'
                                      : 'Không tìm thấy Pallet nào khớp với tiêu chí tìm kiếm.',
                                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                                ),
                                if (allPallets.isEmpty) ...[
                                  const SizedBox(height: 14),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('THÊM PALLET ĐẦU TIÊN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                    onPressed: () => _showAddOrEditPalletDialog(context, c),
                                  ),
                                ],
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredPallets.length,
                            itemBuilder: (context, idx) {
                              final p = filteredPallets[idx];
                              final palletItems = allItems.where((i) => (i.palletId == p.palletId || i.palletId == p.palletCode) && i.status != ItemStatus.out).toList();
                              final itemCount = palletItems.length;
                              final hasRfid = p.rfidEpc != null && p.rfidEpc!.trim().isNotEmpty;
                              final loc = _repo.locations.where((l) => l.locationId == p.locationId || l.locationCode == p.locationId).firstOrNull;
                              final locDisplay = loc?.displayName ?? (loc?.locationCode ?? (p.locationId ?? 'Chưa xếp kệ'));

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
                                ),
                                child: Row(
                                  children: [
                                    // STT
                                    SizedBox(
                                      width: 45,
                                      child: Text(
                                        '${idx + 1}',
                                        style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),

                                    // Mã Pallet
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          const Icon(Icons.layers, size: 16, color: Color(0xFFF59E0B)),
                                          const SizedBox(width: 8),
                                          Flexible(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  p.palletCode,
                                                  style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                if (p.palletName != null && p.palletName != p.palletCode)
                                                  Text(
                                                    p.palletName!,
                                                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Mã Chip RFID
                                    Expanded(
                                      flex: 3,
                                      child: Row(
                                        children: [
                                          Icon(Icons.nfc, size: 14, color: hasRfid ? c.rfidCyan : c.textMuted),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              hasRfid ? p.rfidEpc! : 'Chưa gắn thẻ RFID',
                                              style: TextStyle(
                                                fontFamily: hasRfid ? 'monospace' : null,
                                                color: hasRfid ? c.rfidCyan : c.textMuted,
                                                fontSize: 11.5,
                                                fontWeight: hasRfid ? FontWeight.bold : FontWeight.normal,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Vị trí kệ
                                    Expanded(
                                      flex: 2,
                                      child: Row(
                                        children: [
                                          Icon(Icons.location_on_outlined, size: 14, color: loc != null ? const Color(0xFF10B981) : c.textMuted),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              locDisplay,
                                              style: TextStyle(
                                                color: loc != null ? const Color(0xFF10B981) : c.textMuted,
                                                fontSize: 12,
                                                fontWeight: loc != null ? FontWeight.bold : FontWeight.normal,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Số lượng hàng
                                    Expanded(
                                      flex: 2,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: itemCount > 0 ? const Color(0xFF10B981).withValues(alpha: 0.12) : c.bgDeep,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(
                                              color: itemCount > 0 ? const Color(0xFF10B981).withValues(alpha: 0.3) : c.border,
                                            ),
                                          ),
                                          child: Text(
                                            itemCount > 0 ? '$itemCount chip hàng' : '0 hàng',
                                            style: TextStyle(
                                              color: itemCount > 0 ? const Color(0xFF10B981) : c.textMuted,
                                              fontSize: 11.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Trạng thái
                                    SizedBox(
                                      width: 120,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: itemCount > 0
                                                ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                                                : const Color(0xFF10B981).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: itemCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                                            ),
                                          ),
                                          child: Text(
                                            itemCount > 0 ? 'Đang chứa hàng' : 'Pallet trống',
                                            style: TextStyle(
                                              color: itemCount > 0 ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Thao tác
                                    SizedBox(
                                      width: 170,
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.end,
                                        children: [
                                          // Nút xem chi tiết hàng trong pallet
                                          IconButton(
                                            icon: const Icon(Icons.inventory_2_outlined, size: 17),
                                            color: const Color(0xFF10B981),
                                            tooltip: 'Xem danh sách hàng hóa trong Pallet',
                                            onPressed: () => _showPalletItemsDialog(context, p, palletItems, c),
                                          ),
                                          // Nút sửa Pallet & chip RFID
                                          IconButton(
                                            icon: const Icon(Icons.edit_outlined, size: 17),
                                            color: const Color(0xFF3B82F6),
                                            tooltip: 'Sửa Pallet hoặc thay chip RFID',
                                            onPressed: () => _showAddOrEditPalletDialog(context, c, editingPallet: p),
                                          ),
                                          // Nút xóa Pallet
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, size: 17),
                                            color: const Color(0xFFEF4444),
                                            tooltip: 'Xóa Pallet khi bị hư hỏng',
                                            onPressed: () => _confirmDeletePallet(p, c),
                                          ),
                                        ],
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
          ),
        ],
      ),
    ),
  ),
);
      },
    );
  }

  // ==========================================
  // TAB 3: QUẢN LÝ LỊCH SỬ KHO (HỢP NHẤT TOÀN DIỆN)
  // ==========================================
  Widget _buildHistoryManagementTab(EyeCareColors c) {
    return _buildOrderHistoryContent(c);
  }

  Widget _buildOrderHistoryContent(EyeCareColors c) {
    final allInboundOrders = _repo.inboundOrders;
    final allOutboundOrders = _repo.outboundOrders;
    final allItems = _repo.items;
    final allTransactions = _repo.transactions;

    // Build unified history list
    final List<Map<String, dynamic>> historyRecords = [];

    for (var o in allInboundOrders) {
      final ordItems = allItems.where((i) => i.orderNo == o.orderNo || i.orderNo == o.inboundOrderId).toList();
      final totalQty = ordItems.isNotEmpty ? ordItems.length : o.details.fold<int>(0, (sum, d) => sum + d.requiredQty);
      final receivedQty = ordItems.isNotEmpty ? ordItems.where((i) => i.status != ItemStatus.pendingInbound).length : o.details.fold<int>(0, (sum, d) => sum + d.receivedQty);
      final pallets = ordItems.map((i) => i.palletId).where((p) => p != null && p.isNotEmpty).toSet().toList();

      historyRecords.add({
        'recordType': 'INBOUND',
        'isOutbound': false,
        'orderNo': o.orderNo,
        'orderId': o.inboundOrderId,
        'partner': o.sourceSupplier,
        'createdAt': o.createdAt,
        'status': o.status,
        'statusLabel': o.status == InboundOrderStatus.completed ? 'ĐÃ HOÀN TẤT' : (o.status == InboundOrderStatus.processing ? 'ĐANG NHẬN HÀNG' : 'MỚI TẠO'),
        'totalQty': totalQty,
        'doneQty': receivedQty,
        'pallets': pallets,
        'details': o.details,
        'items': ordItems,
      });
    }

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

      final dynamicDetails = o.details.isNotEmpty
          ? o.details
          : (relatedTxs.isNotEmpty
              ? relatedTxs.map((t) => OutboundOrderDetail(
                  productId: t.sku,
                  sku: t.sku,
                  productName: t.productName.isNotEmpty ? t.productName : 'Sản phẩm xuất kho',
                  requiredQty: t.quantity,
                  pickedQty: t.quantity,
                )).toList()
              : <dynamic>[]);

      historyRecords.add({
        'recordType': 'OUTBOUND',
        'isOutbound': true,
        'orderNo': o.poNo,
        'orderId': o.outboundOrderId,
        'partner': o.customer,
        'createdAt': o.createdAt,
        'status': o.status,
        'statusLabel': o.status == OutboundOrderStatus.shipped ? 'ĐÃ XUẤT KHO' : 'ĐANG XỬ LÝ',
        'totalQty': totalQty,
        'doneQty': pickedQty,
        'pallets': pallets,
        'details': dynamicDetails,
        'items': ordItems,
        'transaction': relatedTxs.firstOrNull,
      });
    }

    // Thêm các đợt kiểm kê kho thực tế từ CSDL
    final allSessions = _repo.inventorySessions;
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

    // Giao dịch điều chuyển vị trí, xuất kho, nhập kho & điều chỉnh kiểm kê từ CSDL
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
        } else {
          final rec = historyRecords.where((h) =>
              h['recordType'] == 'OUTBOUND' &&
              (h['orderNo'] == doc || h['orderId'] == doc || h['orderId'] == t.transactionId)).firstOrNull;
          if (rec != null) {
            if ((rec['totalQty'] as int? ?? 0) == 0) {
              rec['totalQty'] = t.quantity;
              rec['doneQty'] = t.quantity;
            }
            rec['transaction'] ??= t;
            if (t.palletCode != null && t.palletCode!.isNotEmpty) {
              final palList = (rec['pallets'] as List).cast<String>();
              if (!palList.contains(t.palletCode!)) {
                palList.add(t.palletCode!);
              }
            }
          }
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
            'statusLabel': 'ĐÃ HOÀN TẤT',
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

    // Sort by timestamp desc
    historyRecords.sort((a, b) => (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));

    // Stats
    final totalInbound = historyRecords.where((h) => h['recordType'] == 'INBOUND').length;
    final totalOutbound = historyRecords.where((h) => h['recordType'] == 'OUTBOUND').length;
    final totalMovement = historyRecords.where((h) => h['recordType'] == 'MOVEMENT').length;
    final totalAudit = historyRecords.where((h) => h['recordType'] == 'AUDIT').length;
    final totalAll = historyRecords.length;

    // Filter logic
    final q = _historySearchQuery.trim().toLowerCase();
    final filteredHistory = historyRecords.where((h) {
      final recType = h['recordType'] as String? ?? '';
      if (_historyTypeFilter == 'INBOUND' && recType != 'INBOUND') return false;
      if (_historyTypeFilter == 'OUTBOUND' && recType != 'OUTBOUND') return false;
      if (_historyTypeFilter == 'MOVEMENT' && recType != 'MOVEMENT') return false;
      if (_historyTypeFilter == 'AUDIT' && recType != 'AUDIT') return false;

      final statusLabel = (h['statusLabel'] as String).toUpperCase();
      if (_historyStatusFilter == 'COMPLETED' && (!statusLabel.contains('ĐÃ') && !statusLabel.contains('HOÀN THÀNH'))) return false;
      if (_historyStatusFilter == 'IN_PROGRESS' && (statusLabel.contains('ĐÃ') || statusLabel.contains('HOÀN THÀNH'))) return false;

      if (q.isEmpty) return true;

      final ordNo = (h['orderNo'] as String).toLowerCase();
      final partner = (h['partner'] as String).toLowerCase();
      final pallets = (h['pallets'] as List).join(' ').toLowerCase();

      return ordNo.contains(q) || partner.contains(q) || pallets.contains(q);
    }).toList();

    return LayoutBuilder(
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
                  // 1. Bốn Thẻ Chỉ Số Thống Kê Tổng Quan (Nhập, Xuất, Chuyển, Kiểm Kê)
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.input_rounded,
                          iconColor: const Color(0xFF10B981),
                          title: 'ĐƠN NHẬP KHO',
                          value: '$totalInbound Đơn',
                          subtitle: 'Giao dịch nhập kho RFID',
                          c: c,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.output_rounded,
                          iconColor: const Color(0xFF3B82F6),
                          title: 'ĐƠN XUẤT KHO',
                          value: '$totalOutbound Đơn',
                          subtitle: 'Giao dịch xuất kho RFID',
                          c: c,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.sync_alt_rounded,
                          iconColor: const Color(0xFFF59E0B),
                          title: 'ĐIỀU CHUYỂN KHO',
                          value: '$totalMovement Lượt',
                          subtitle: 'Luân chuyển vị trí kệ',
                          c: c,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricTile(
                          icon: Icons.fact_check_outlined,
                          iconColor: const Color(0xFF8B5CF6),
                          title: 'KIỂM KÊ KHO',
                          value: '$totalAudit Đợt',
                          subtitle: 'Phiên kiểm kê & đối soát',
                          c: c,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // 2. Thanh Điều Hướng Phân Chia Nghiệp Vụ Chuyên Biệt (Chia 4 nghiệp vụ rõ ràng, dễ nhìn, dễ thao tác)
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      children: [
                        _buildCategoryTabButton('TẤT CẢ ($totalAll)', Icons.list_alt_rounded, 'ALL', c.rfidCyan, c),
                        const SizedBox(width: 6),
                        _buildCategoryTabButton('📥 NHẬP KHO ($totalInbound)', Icons.input_rounded, 'INBOUND', const Color(0xFF10B981), c),
                        const SizedBox(width: 6),
                        _buildCategoryTabButton('📤 XUẤT KHO ($totalOutbound)', Icons.output_rounded, 'OUTBOUND', const Color(0xFF3B82F6), c),
                        const SizedBox(width: 6),
                        _buildCategoryTabButton('🔄 ĐIỀU CHUYỂN ($totalMovement)', Icons.sync_alt_rounded, 'MOVEMENT', const Color(0xFFF59E0B), c),
                        const SizedBox(width: 6),
                        _buildCategoryTabButton('📊 KIỂM KÊ ($totalAudit)', Icons.fact_check_outlined, 'AUDIT', const Color(0xFF8B5CF6), c),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 3. Thanh Tìm Kiếm & Lọc Trạng Thái
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      children: [
                        // Search Input
                        Expanded(
                          child: SizedBox(
                            height: 38,
                            child: TextField(
                              controller: _historySearchCtrl,
                              onChanged: (val) => setState(() => _historySearchQuery = val),
                              style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                              decoration: InputDecoration(
                                hintText: 'Tìm theo Mã Đơn/PO, Chứng Từ, SKU, Pallet, Tuyến Kho, Vị Trí, Đối Tác...',
                                hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                                prefixIcon: Icon(Icons.search, size: 18, color: c.textSecondary),
                                suffixIcon: _historySearchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear, size: 16),
                                        onPressed: () {
                                          _historySearchCtrl.clear();
                                          setState(() => _historySearchQuery = '');
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
                        const SizedBox(width: 14),

                        // Filter Status Pills
                        _buildFilterPill('Tất cả trạng thái', 'ALL', _historyStatusFilter, (f) => setState(() => _historyStatusFilter = f), c),
                        const SizedBox(width: 6),
                        _buildFilterPill('Đã hoàn tất', 'COMPLETED', _historyStatusFilter, (f) => setState(() => _historyStatusFilter = f), c),
                        const SizedBox(width: 6),
                        _buildFilterPill('Đang xử lý', 'IN_PROGRESS', _historyStatusFilter, (f) => setState(() => _historyStatusFilter = f), c),
                        const SizedBox(width: 10),

                        // Nút Làm Mới Dữ Liệu
                        Tooltip(
                          message: 'Đồng bộ & làm mới dữ liệu từ CSDL',
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: c.textPrimary,
                              side: BorderSide(color: c.border),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('LÀM MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                            onPressed: () async {
                              await _repo.reloadFromSqlite();
                              await _supabaseSync.syncNow();
                              if (mounted) setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // 4. Bảng Lịch Sử Giao Dịch Kho Toàn Diện
                  Expanded(
                    child: Container(
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
                                SizedBox(width: 45, child: Text('STT', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                SizedBox(width: 125, child: Text('THỜI GIAN', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                SizedBox(width: 125, child: Text('NGHIỆP VỤ', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('MÃ CHỨNG TỪ / ĐƠN', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                Expanded(flex: 3, child: Text('ĐỐI TÁC / VỊ TRÍ / KHU VỰC', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('SỐ LƯỢNG HÀNG', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                SizedBox(width: 130, child: Text('TRẠNG THÁI', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                SizedBox(width: 100, child: Text('THAO TÁC', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ),

                  // Table Body
                  Expanded(
                    child: filteredHistory.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.history_toggle_off_rounded, size: 48, color: c.textMuted),
                                const SizedBox(height: 10),
                                Text(
                                  historyRecords.isEmpty
                                      ? 'Chưa có lịch sử giao dịch kho nào.'
                                      : 'Không tìm thấy kết quả phù hợp với bộ lọc tìm kiếm.',
                                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: filteredHistory.length,
                            itemBuilder: (context, idx) {
                              final h = filteredHistory[idx];
                              final isOutbound = h['isOutbound'] as bool;
                              final statusLabel = h['statusLabel'] as String;
                              final isDone = statusLabel.contains('ĐÃ') || statusLabel == 'ĐIỀU CHUYỂN' || statusLabel == 'KIỂM KÊ';
                              final doneQty = h['doneQty'] as int;
                              final totalQty = h['totalQty'] as int;
                              final recType = h['recordType'] as String? ?? (isOutbound ? 'OUTBOUND' : 'INBOUND');

                              Color typeColor = const Color(0xFF10B981);
                              IconData typeIcon = Icons.input_rounded;
                              String typeTitle = 'NHẬP KHO';

                              if (recType == 'OUTBOUND') {
                                typeColor = const Color(0xFF3B82F6);
                                typeIcon = Icons.output_rounded;
                                typeTitle = 'XUẤT KHO';
                              } else if (recType == 'MOVEMENT') {
                                typeColor = const Color(0xFFF59E0B);
                                typeIcon = Icons.sync_alt_rounded;
                                typeTitle = 'ĐIỀU CHUYỂN';
                              } else if (recType == 'AUDIT') {
                                typeColor = const Color(0xFF8B5CF6);
                                typeIcon = Icons.fact_check_outlined;
                                typeTitle = 'KIỂM KÊ';
                              }

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
                                ),
                                child: Row(
                                  children: [
                                    // STT
                                    SizedBox(
                                      width: 45,
                                      child: Text(
                                        '${idx + 1}',
                                        style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                                      ),
                                    ),

                                    // Thời gian
                                    SizedBox(
                                      width: 125,
                                      child: Text(
                                        _formatDateTime(h['createdAt'] as DateTime?),
                                        style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                                      ),
                                    ),

                                    // Nghiệp vụ (Nhập / Xuất / Điều chuyển / Kiểm kê)
                                    SizedBox(
                                      width: 125,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: typeColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: typeColor),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(typeIcon, size: 13, color: typeColor),
                                              const SizedBox(width: 4),
                                              Flexible(
                                                child: Text(
                                                  typeTitle,
                                                  style: TextStyle(
                                                    color: typeColor,
                                                    fontSize: 10.5,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Mã đơn / chứng từ
                                    Expanded(
                                      flex: 2,
                                      child: Text(
                                        h['orderNo'] as String,
                                        style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Đối tác / Vị trí / Tuyến kho
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        (h['partner'] as String).isNotEmpty ? (h['partner'] as String) : 'Chưa chỉ định',
                                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),

                                    // Số lượng hàng
                                    Expanded(
                                      flex: 2,
                                      child: Center(
                                        child: Text(
                                          recType == 'AUDIT'
                                              ? '$totalQty chip ($doneQty khớp)'
                                              : (recType == 'MOVEMENT'
                                                  ? '$totalQty kiện'
                                                  : '$doneQty / $totalQty chip'),
                                          style: TextStyle(
                                            color: c.textPrimary,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Trạng thái
                                    SizedBox(
                                      width: 130,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isDone
                                                ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                                : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isDone ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                            ),
                                          ),
                                          child: Text(
                                            statusLabel,
                                            style: TextStyle(
                                              color: isDone ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                              fontSize: 10.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Thao tác
                                    SizedBox(
                                      width: 100,
                                      child: Center(
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                            side: BorderSide(color: c.border),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                          ),
                                          onPressed: () => _showHistoryDetailDialog(context, h, c),
                                          child: Text(
                                            'Chi Tiết',
                                            style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.bold),
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
          ),
        ],
      ),
    ),
  ),
);
      },
    );
  }

  // ==========================================
  // HELPER WIDGETS & DIALOGS
  // ==========================================

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    String? subtitle,
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
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                if (subtitle != null && subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String label, String value, String currentVal, Function(String) onSelect, EyeCareColors c) {
    final isSelected = currentVal == value;

    return InkWell(
      onTap: () => onSelect(value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan.withValues(alpha: 0.15) : c.bgDeep,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? c.rfidCyan : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? c.rfidCyan : c.textSecondary,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildCategoryTabButton(String label, IconData icon, String filterValue, Color activeColor, EyeCareColors c) {
    final isSelected = _historyTypeFilter == filterValue;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _historyTypeFilter = filterValue),
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
                  style: TextStyle(
                    color: isSelected ? c.textPrimary : c.textSecondary,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- DIALOG: THÊM / SỬA PALLET ---
  void _showAddOrEditPalletDialog(BuildContext context, EyeCareColors c, {Pallet? editingPallet}) {
    final codeCtrl = TextEditingController(text: editingPallet?.palletCode ?? '');
    final nameCtrl = TextEditingController(text: editingPallet?.palletName ?? '');
    final rfidCtrl = TextEditingController(text: editingPallet?.rfidEpc ?? '');
    String? selectedLocationId = editingPallet?.locationId ?? (_repo.locations.isNotEmpty ? _repo.locations.first.locationId : null);
    bool isProcessing = false;

    StreamSubscription? dlgSub1;
    StreamSubscription? dlgSub2;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDlgState) {
            // Listen to RFID tag events while dialog is active
            dlgSub1 ??= _desktopUhf.onTagRead.listen((tag) {
              if (dialogCtx.mounted) {
                rfidCtrl.text = tag.epc;
                setDlgState(() {});
              }
            });
            dlgSub2 ??= _uhf.onTagRead.listen((tag) {
              if (dialogCtx.mounted) {
                rfidCtrl.text = tag.epc;
                setDlgState(() {});
              }
            });

            return AlertDialog(
              backgroundColor: c.bgCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (editingPallet != null ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(editingPallet != null ? Icons.edit_note_rounded : Icons.add_box_rounded,
                        color: editingPallet != null ? const Color(0xFFF59E0B) : const Color(0xFF10B981), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    editingPallet != null ? 'SỬA PALLET: ${editingPallet.palletCode}' : 'THÊM PALLET & GẮN CHIP RFID',
                    style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nhập mã barcode định danh Pallet và mã chip RFID cố định trên Pallet. Có thể quét chip trực tiếp từ đầu đọc.',
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),
                    const SizedBox(height: 16),

                    // Mã Pallet (Barcode)
                    TextField(
                      controller: codeCtrl,
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Mã Pallet (Barcode) *',
                        hintText: 'VD: PL-01, 945321582...',
                        filled: true,
                        fillColor: c.bgDeep,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Tên Pallet
                    TextField(
                      controller: nameCtrl,
                      style: TextStyle(color: c.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Tên / Ghi chú Pallet (Tùy chọn)',
                        hintText: 'VD: Pallet Kho A, Pallet Nhựa...',
                        filled: true,
                        fillColor: c.bgDeep,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Mã thẻ RFID EPC
                    TextField(
                      controller: rfidCtrl,
                      style: TextStyle(color: c.rfidCyan, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12.5),
                      decoration: InputDecoration(
                        labelText: 'Mã EPC',
                        hintText: 'Quét thẻ qua đầu đọc để tự điền...',
                        prefixIcon: Icon(Icons.sensors, size: 18, color: c.rfidCyan),
                        suffixIcon: rfidCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  rfidCtrl.clear();
                                  setDlgState(() {});
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: c.bgDeep,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Vị trí kệ lưu mặc định
                    if (_repo.locations.isNotEmpty) ...[
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _repo.locations.any((l) => l.locationId == selectedLocationId) ? selectedLocationId : null,
                        dropdownColor: c.bgCard,
                        style: TextStyle(color: c.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Vị trí kệ kho (Tùy chọn)',
                          filled: true,
                          fillColor: c.bgDeep,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: [
                          const DropdownMenuItem<String>(
                            value: null,
                            child: Text('Chưa xếp kệ (Lưu tạm dưới sàn)', overflow: TextOverflow.ellipsis, maxLines: 1),
                          ),
                          ..._repo.locations.map((loc) => DropdownMenuItem<String>(
                                value: loc.locationId,
                                child: Text('${loc.locationCode} - ${loc.displayName}', overflow: TextOverflow.ellipsis, maxLines: 1),
                              )),
                        ],
                        onChanged: (val) => setDlgState(() => selectedLocationId = val),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: editingPallet != null ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: isProcessing
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 16),
                  label: Text(
                    editingPallet != null ? 'CẬP NHẬT' : 'LƯU PALLET',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: isProcessing
                      ? null
                      : () async {
                          final code = codeCtrl.text.trim().toUpperCase();
                          if (code.isEmpty) {
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
          duration: Duration(seconds: 2),backgroundColor: Color(0xFFEF4444), content: Text('Vui lòng nhập Mã Pallet (Barcode)!')),
                            );
                            return;
                          }

                          final rfid = rfidCtrl.text.trim().isNotEmpty
                              ? rfidCtrl.text.trim().toUpperCase()
                              : _convertPalletCodeToHex(code);

                          final name = nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : code;

                          setDlgState(() => isProcessing = true);
                          try {
                            await _repo.registerOrUpdatePallet(
                              palletCode: code,
                              palletName: name,
                              rfidEpc: rfid,
                              locationId: selectedLocationId,
                              oldPalletCode: editingPallet?.palletCode,
                              oldPalletId: editingPallet?.palletId,
                            );

                            if (dialogCtx.mounted) {
                              Navigator.pop(dialogCtx);
                              final isEdit = editingPallet != null;
                              AppSnackBar.showSuccess(
                                context,
                                isEdit ? '✓ Đã cập nhật thành công Pallet "$code"!' : '✓ Đã tạo mới thành công Pallet "$code"!',
                              );
                            }
                          } catch (e) {
                            if (dialogCtx.mounted) {
                              AppSnackBar.showError(context, 'Lỗi: $e');
                            }
                          } finally {
                            if (dialogCtx.mounted) setDlgState(() => isProcessing = false);
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    ).then((_) {
      dlgSub1?.cancel();
      dlgSub2?.cancel();
    });
  }

  // --- DIALOG: XÁC NHẬN XÓA PALLET ---
  Future<void> _confirmDeletePallet(Pallet p, EyeCareColors c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
            const SizedBox(width: 8),
            Text('Xác nhận xóa Pallet', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa vĩnh viễn Pallet "${p.palletCode}" khỏi hệ thống CSDL không?\n\nHành động này không thể hoàn tác.',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('XÓA PALLET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _repo.deletePalletFromMaster(p.palletCode, palletId: p.palletId);
      if (!mounted) return;
      AppSnackBar.showSuccess(context, '✓ Đã xóa Pallet "${p.palletCode}" thành công!');
    } catch (e) {
      if (!mounted) return;
      AppSnackBar.showError(context, 'Lỗi khi xóa: $e');
    }
  }

  // --- DIALOG: DANH SÁCH HÀNG TRONG PALLET ---
  void _showPalletItemsDialog(BuildContext context, Pallet p, List<Item> items, EyeCareColors c) {
    // Gom nhóm mặt hàng theo SKU: Số lượng, Tên, Mã, Ngày nhập
    final Map<String, _PalletGroupSummary> productGroups = {};
    for (final it in items) {
      final skuCode = it.sku.trim().isNotEmpty ? it.sku.trim() : (it.productId.trim().isNotEmpty ? it.productId.trim() : 'CHƯA CÓ MÃ');
      final prodName = it.productName.trim().isNotEmpty ? it.productName.trim() : skuCode;
      final inTime = _repo.getItemInboundTime(it);
      if (productGroups.containsKey(skuCode)) {
        final grp = productGroups[skuCode]!;
        grp.quantity += 1;
        grp.items.add(it);
        if (inTime.isAfter(grp.inboundTime)) {
          grp.inboundTime = inTime;
        }
      } else {
        productGroups[skuCode] = _PalletGroupSummary(
          sku: skuCode,
          productName: prodName,
          quantity: 1,
          inboundTime: inTime,
          items: [it],
        );
      }
    }
    final groupList = productGroups.values.toList();
    int currentViewMode = 0; // 0: Tổng hợp mặt hàng, 1: Chi tiết từng chip RFID

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          return AlertDialog(
            backgroundColor: c.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.bgDeep,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.border.withValues(alpha: 0.6)),
                  ),
                  child: const Icon(Icons.layers, color: Color(0xFF0F172A), size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('HÀNG HÓA TRONG PALLET: ${p.palletCode}', style: const TextStyle(color: Color(0xFF0F172A), fontSize: 16, fontWeight: FontWeight.bold)),
                      Text('Tổng cộng: ${groupList.length} mặt hàng • ${items.length} chip RFID • Thẻ RFID: ${p.rfidEpc ?? "Chưa gắn"}', style: const TextStyle(color: Color(0xFF334155), fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 820,
              height: 490,
              child: items.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 48, color: Color(0xFF334155)),
                          SizedBox(height: 10),
                          Text('Pallet này hiện đang trống (chưa có sản phẩm nào).', style: TextStyle(color: Color(0xFF334155), fontSize: 13, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Bộ chọn chế độ xem
                        Row(
                          children: [
                            InkWell(
                              onTap: () => setDialogState(() => currentViewMode = 0),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: currentViewMode == 0 ? const Color(0xFF0F172A) : c.bgCardElevated,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: c.border),
                                ),
                                child: Text(
                                  'TỔNG HỢP MẶT HÀNG (${groupList.length})',
                                  style: TextStyle(
                                    color: currentViewMode == 0 ? Colors.white : const Color(0xFF0F172A),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            InkWell(
                              onTap: () => setDialogState(() => currentViewMode = 1),
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: currentViewMode == 1 ? const Color(0xFF0F172A) : c.bgCardElevated,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: c.border),
                                ),
                                child: Text(
                                  'CHI TIẾT TỪNG CHIP RFID (${items.length})',
                                  style: TextStyle(
                                    color: currentViewMode == 1 ? Colors.white : const Color(0xFF0F172A),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // BẢNG 1: TỔNG HỢP MẶT HÀNG (SỐ LƯỢNG, TÊN, MÃ, NGÀY NHẬP)
                        if (currentViewMode == 0)
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: c.bgCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: c.border),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                                    decoration: BoxDecoration(
                                      color: c.bgCardElevated,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                      border: Border(bottom: BorderSide(color: c.border)),
                                    ),
                                    child: Row(
                                      children: const [
                                        SizedBox(width: 36, child: Text('STT', style: TextStyle(color: Color(0xFF0F172A), fontSize: 11.5, fontWeight: FontWeight.bold))),
                                        SizedBox(width: 8),
                                        Expanded(flex: 3, child: Text('MÃ SẢN PHẨM', style: TextStyle(color: Color(0xFF0F172A), fontSize: 11.5, fontWeight: FontWeight.bold))),
                                        SizedBox(width: 8),
                                        Expanded(flex: 5, child: Text('TÊN SẢN PHẨM', style: TextStyle(color: Color(0xFF0F172A), fontSize: 11.5, fontWeight: FontWeight.bold))),
                                        SizedBox(width: 8),
                                        SizedBox(width: 110, child: Text('SỐ LƯỢNG', textAlign: TextAlign.center, style: TextStyle(color: Color(0xFF0F172A), fontSize: 11.5, fontWeight: FontWeight.bold))),
                                        SizedBox(width: 8),
                                        SizedBox(width: 140, child: Text('NGÀY NHẬP', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF0F172A), fontSize: 11.5, fontWeight: FontWeight.bold))),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: groupList.length,
                                      itemBuilder: (gCtx, idx) {
                                        final grp = groupList[idx];
                                        final inTime = grp.inboundTime;
                                        final inTimeStr = '${inTime.day.toString().padLeft(2, '0')}/${inTime.month.toString().padLeft(2, '0')}/${inTime.year} ${inTime.hour.toString().padLeft(2, '0')}:${inTime.minute.toString().padLeft(2, '0')}';

                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                          decoration: BoxDecoration(
                                            border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.5))),
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(width: 36, child: Text('${idx + 1}', style: const TextStyle(color: Color(0xFF334155), fontSize: 12, fontWeight: FontWeight.w500))),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  grp.sku,
                                                  style: const TextStyle(
                                                    color: Color(0xFF0F172A),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12.5,
                                                    fontFamily: 'monospace',
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 5,
                                                child: Text(
                                                  grp.productName,
                                                  style: const TextStyle(
                                                    color: Color(0xFF0F172A),
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 12.5,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                width: 110,
                                                child: Center(
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: c.bgCardElevated,
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: c.border),
                                                    ),
                                                    child: Text(
                                                      '${grp.quantity} cái',
                                                      style: const TextStyle(
                                                        color: Color(0xFF0F172A),
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12,
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              SizedBox(
                                                width: 140,
                                                child: Text(
                                                  inTimeStr,
                                                  textAlign: TextAlign.right,
                                                  style: const TextStyle(
                                                    color: Color(0xFF0F172A),
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w500,
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
                          ),

                        // BẢNG 2: CHI TIẾT TỪNG CHIP RFID
                        if (currentViewMode == 1)
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: c.bgCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: c.border),
                              ),
                              child: Column(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: c.bgCardElevated,
                                      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                      border: Border(bottom: BorderSide(color: c.border)),
                                    ),
                                    child: Row(
                                      children: const [
                                        SizedBox(width: 36, child: Text('STT', style: TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.bold))),
                                        Expanded(flex: 2, child: Text('MÃ SP', style: TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.bold))),
                                        Expanded(flex: 3, child: Text('TÊN SẢN PHẨM', style: TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.bold))),
                                        Expanded(flex: 3, child: Text('MÃ RFID (EPC)', style: TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.bold))),
                                        SizedBox(width: 90, child: Text('THÙNG', style: TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.bold))),
                                        SizedBox(width: 130, child: Text('NGÀY NHẬP', textAlign: TextAlign.right, style: TextStyle(color: Color(0xFF0F172A), fontSize: 11, fontWeight: FontWeight.bold))),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView.builder(
                                      itemCount: items.length,
                                      itemBuilder: (itemCtx, idx) {
                                        final it = items[idx];
                                        final inTime = _repo.getItemInboundTime(it);
                                        final inTimeStr = '${inTime.day.toString().padLeft(2, '0')}/${inTime.month.toString().padLeft(2, '0')}/${inTime.year} ${inTime.hour.toString().padLeft(2, '0')}:${inTime.minute.toString().padLeft(2, '0')}';

                                        return Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.4))),
                                          ),
                                          child: Row(
                                            children: [
                                              SizedBox(width: 36, child: Text('${idx + 1}', style: const TextStyle(color: Color(0xFF334155), fontSize: 11.5))),
                                              Expanded(
                                                flex: 2,
                                                child: Text(
                                                  it.sku,
                                                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  it.productName,
                                                  style: const TextStyle(color: Color(0xFF0F172A), fontSize: 12),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              Expanded(
                                                flex: 3,
                                                child: Text(
                                                  it.epc,
                                                  style: const TextStyle(color: Color(0xFF0F172A), fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.bold),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                              SizedBox(
                                                width: 90,
                                                child: Text(it.cartonCode ?? '--', style: const TextStyle(color: Color(0xFF334155), fontSize: 11.5)),
                                              ),
                                              SizedBox(
                                                width: 130,
                                                child: Text(inTimeStr, textAlign: TextAlign.right, style: const TextStyle(color: Color(0xFF0F172A), fontSize: 11.5, fontWeight: FontWeight.w500)),
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
                          ),
                      ],
                    ),
            ),
            actions: [
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan, foregroundColor: const Color(0xFF2C251E)),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('ĐÓNG', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- DIALOG: XEM CHI TIẾT ĐƠN HÀNG NHẬP / XUẤT / ĐIỀU CHUYỂN / KIỂM KÊ ---
  void _showHistoryDetailDialog(BuildContext context, Map<String, dynamic> record, EyeCareColors c) {
    final recType = record['recordType'] as String? ?? '';
    final trans = record['transaction'] as InventoryTransaction?;
    final session = record['session'] as InventorySession?;

    // 1. Nếu là đợt kiểm kê (InventorySession)
    if (recType == 'AUDIT' && session != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.fact_check_outlined, color: Color(0xFF8B5CF6), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CHI TIẾT ĐỢT KIỂM KÊ: ${session.sessionCode.isNotEmpty ? session.sessionCode : session.sessionId}',
                      style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Khu vực: ${session.zone} ${session.locationCode != null ? "• Kệ: ${session.locationCode}" : ""} • Thời gian: ${_formatDateTime(session.completedAt ?? session.startedAt)} • Trạng thái: ${session.isCompleted ? "ĐÃ HOÀN TẤT" : "ĐANG KIỂM KÊ"}',
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 780,
            height: 480,
            child: Column(
              children: [
                // 4 Thẻ chỉ số kiểm kê
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                        decoration: BoxDecoration(color: c.bgCardElevated, borderRadius: BorderRadius.circular(8), border: Border.all(color: c.border)),
                        child: Column(
                          children: [
                            Text('ĐÃ QUÉT THỰC TẾ', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('${session.actualScannedCount}', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                        decoration: BoxDecoration(color: const Color(0xFF10B981).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF10B981))),
                        child: Column(
                          children: [
                            const Text('KHỚP HỆ THỐNG', style: TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('${session.matchCount}', style: const TextStyle(color: Color(0xFF10B981), fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                        decoration: BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFEF4444))),
                        child: Column(
                          children: [
                            const Text('THIẾU THỰC TẾ', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('${session.missingCount}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
                        decoration: BoxDecoration(color: const Color(0xFF8B5CF6).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF8B5CF6))),
                        child: Column(
                          children: [
                            const Text('THẺ LẠ / NGOÀI DS', style: TextStyle(color: Color(0xFF8B5CF6), fontSize: 10.5, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('${session.unknownEpcCount}', style: const TextStyle(color: Color(0xFF8B5CF6), fontSize: 16, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Danh sách chip RFID đã kiểm kê
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(color: c.bgCardElevated, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
                  child: Row(
                    children: [
                      SizedBox(width: 40, child: Text('STT', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 3, child: Text('MÃ EPC / RFID', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('MÃ SKU', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 3, child: Text('TÊN SẢN PHẨM', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      SizedBox(width: 120, child: Text('KẾT QUẢ ĐỐI SOÁT', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
                Expanded(
                  child: session.results.isEmpty
                      ? Center(child: Text('Chưa có chi tiết thẻ nào được ghi nhận trong đợt kiểm kê này.', style: TextStyle(color: c.textSecondary, fontSize: 12)))
                      : ListView.builder(
                          itemCount: session.results.length,
                          itemBuilder: (context, idx) {
                            final r = session.results[idx];
                            final color = Color(r.resultType.colorValue);
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.4)))),
                              child: Row(
                                children: [
                                  SizedBox(width: 40, child: Text('${idx + 1}', style: TextStyle(color: c.textSecondary, fontSize: 11.5))),
                                  Expanded(
                                    flex: 3,
                                    child: Text(r.epc, style: TextStyle(color: c.textPrimary, fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Text(r.sku ?? '--', style: TextStyle(color: c.textPrimary, fontSize: 12)),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(r.productName ?? 'Chưa xác định', style: TextStyle(color: c.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: color),
                                        ),
                                        child: Text(
                                          r.resultType.label,
                                          style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
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
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan, foregroundColor: const Color(0xFF2C251E)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ĐÓNG', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    // 2. Nếu là giao dịch điều chuyển vị trí hoặc điều chỉnh
    if (trans != null || recType == 'MOVEMENT' || recType == 'AUDIT') {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.sync_alt_rounded, color: Color(0xFFF59E0B), size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CHI TIẾT ĐIỀU CHUYỂN / KIỂM KÊ: ${record['orderNo']}',
                      style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Thời gian: ${_formatDateTime(record['createdAt'] as DateTime?)} • Trạng thái: ${record['statusLabel']}',
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 580,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.bgDeep,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildHistoryInfoRow('Mã chứng từ / giao dịch', trans?.documentNo.isNotEmpty == true ? trans!.documentNo : (trans?.transactionId ?? (record['orderNo'] as String)), c),
                  _buildHistoryInfoRow('Loại biến động', trans?.type.label ?? (record['statusLabel'] as String), c),
                  _buildHistoryInfoRow('Mặt hàng (SKU)', '${trans?.sku ?? "--"} - ${trans?.productName ?? "--"}', c),
                  _buildHistoryInfoRow('Số lượng', '${trans?.quantity ?? record['totalQty']} sản phẩm / kiện', c),
                  _buildHistoryInfoRow('Pallet liên quan', (trans?.palletCode != null && trans!.palletCode!.isNotEmpty) ? trans.palletCode! : ((record['pallets'] as List).isNotEmpty ? (record['pallets'] as List).join(', ') : '--'), c),
                  _buildHistoryInfoRow('Từ vị trí', trans?.fromLocation ?? 'Chưa xác định', c),
                  _buildHistoryInfoRow('Đến vị trí', trans?.toLocation ?? 'Chưa xác định', c),
                  _buildHistoryInfoRow('Người thực hiện', trans?.performedBy ?? 'Hệ thống', c),
                  _buildHistoryInfoRow('Ghi chú nghiệp vụ', trans?.notes ?? 'Không có ghi chú', c),
                ],
              ),
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan, foregroundColor: const Color(0xFF2C251E)),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ĐÓNG', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    final isOutbound = record['isOutbound'] as bool;
    final orderNo = record['orderNo'] as String;
    final partner = record['partner'] as String;
    final createdAt = record['createdAt'] as DateTime?;
    final statusLabel = record['statusLabel'] as String;
    final details = record['details'] as List<dynamic>;
    final items = (record['items'] as List<dynamic>?)?.cast<Item>() ?? [];

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (isOutbound ? const Color(0xFF3B82F6) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(isOutbound ? Icons.output_rounded : Icons.input_rounded,
                  color: isOutbound ? const Color(0xFF3B82F6) : const Color(0xFF10B981), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${isOutbound ? "CHI TIẾT XUẤT KHO" : "CHI TIẾT NHẬP KHO"}: $orderNo',
                      style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Đối tác: $partner • Thời gian: ${_formatDateTime(createdAt)} • Trạng thái: $statusLabel',
                      style: TextStyle(color: c.textSecondary, fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 820,
          height: 500,
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                TabBar(
                  labelColor: c.rfidCyan,
                  unselectedLabelColor: c.textSecondary,
                  indicatorColor: c.rfidCyan,
                  tabs: [
                    Tab(text: 'Danh Mục Sản Phẩm (${details.length} SKU)'),
                    Tab(text: 'Danh Sách Chip RFID Đã Quét (${items.isNotEmpty ? items.length : "Chi tiết"})'),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: TabBarView(
                    children: [
                      // Tab 1: SKU Details
                      Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(color: c.bgCardElevated, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
                            child: Row(
                              children: [
                                SizedBox(width: 40, child: Text('STT', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                Expanded(flex: 2, child: Text('MÃ SKU', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                Expanded(flex: 4, child: Text('TÊN SẢN PHẨM', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                SizedBox(width: 100, child: Text('YÊU CẦU', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                SizedBox(width: 100, child: Text('THỰC TẾ', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ),
                          Expanded(
                            child: ListView.builder(
                              itemCount: details.length,
                              itemBuilder: (ctx, idx) {
                                final d = details[idx];
                                final reqQty = isOutbound ? (d as OutboundOrderDetail).requiredQty : (d as InboundOrderDetail).requiredQty;
                                final actQty = isOutbound ? (d as OutboundOrderDetail).pickedQty : (d as InboundOrderDetail).receivedQty;

                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.4)))),
                                  child: Row(
                                    children: [
                                      SizedBox(width: 40, child: Text('${idx + 1}', style: TextStyle(color: c.textSecondary, fontSize: 11.5))),
                                      Expanded(flex: 2, child: Text(d.sku, style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold))),
                                      Expanded(flex: 4, child: Text(d.productName, style: TextStyle(color: c.textSecondary, fontSize: 12), overflow: TextOverflow.ellipsis)),
                                      SizedBox(width: 100, child: Center(child: Text('$reqQty', style: TextStyle(color: c.textPrimary, fontSize: 12)))),
                                      SizedBox(
                                        width: 100,
                                        child: Center(
                                          child: Text(
                                            '$actQty',
                                            style: TextStyle(
                                              color: actQty >= reqQty && reqQty > 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
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

                      // Tab 2: RFID Tags List
                      items.isEmpty
                          ? Center(
                              child: Text('Chi tiết chip RFID được quản lý theo PO hoặc đã chuyển vào vị trí kho.', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                            )
                          : Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(color: c.bgCardElevated, borderRadius: const BorderRadius.vertical(top: Radius.circular(8))),
                                  child: Row(
                                    children: [
                                      SizedBox(width: 40, child: Text('STT', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                      Expanded(flex: 3, child: Text('EPC', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                      Expanded(flex: 2, child: Text('SKU', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                      SizedBox(width: 110, child: Text('PALLET', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                      SizedBox(width: 110, child: Text('TRẠNG THÁI', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ListView.builder(
                                    itemCount: items.length,
                                    itemBuilder: (ctx, idx) {
                                      final it = items[idx];
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.4)))),
                                        child: Row(
                                          children: [
                                            SizedBox(width: 40, child: Text('${idx + 1}', style: TextStyle(color: c.textSecondary, fontSize: 11.5))),
                                            Expanded(
                                              flex: 3,
                                              child: Text(it.epc, style: TextStyle(color: c.textPrimary, fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.bold)),
                                            ),
                                            Expanded(flex: 2, child: Text(it.sku, style: TextStyle(color: c.textPrimary, fontSize: 12))),
                                            SizedBox(width: 110, child: Text(it.palletId ?? '--', style: TextStyle(color: c.textSecondary, fontSize: 11.5))),
                                            SizedBox(
                                              width: 110,
                                              child: Text(it.status.label, style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan, foregroundColor: const Color(0xFF2C251E)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ĐÓNG', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryInfoRow(String label, String value, EyeCareColors c) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 170,
            child: Text(
              label,
              style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
