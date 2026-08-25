import 'package:flutter/material.dart';
import '../../services/warehouse_repository.dart';
import '../../models/wms_models.dart';
import '../../theme/eye_care_theme.dart';

class DesktopLookupView extends StatefulWidget {
  const DesktopLookupView({super.key});

  @override
  State<DesktopLookupView> createState() => _DesktopLookupViewState();
}

class _DesktopLookupViewState extends State<DesktopLookupView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final TextEditingController _queryController = TextEditingController();
  String _searchQuery = '';
  ItemStatus? _selectedStatusFilter; // null = Tất cả

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onThemeChanged);
    _repo.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _repo.removeListener(_onThemeChanged);
    _eyeCare.removeListener(_onThemeChanged);
    _queryController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  Color _getStatusColor(ItemStatus status) {
    switch (status) {
      case ItemStatus.pendingInbound:
        return const Color(0xFFF59E0B); // Vàng cam: Chờ nhập kho
      case ItemStatus.waitingPutaway:
        return const Color(0xFF06B6D4); // Xanh dương nhạt: Chờ xếp kệ
      case ItemStatus.inStock:
        return const Color(0xFF10B981); // Xanh lá: Đã lưu trong kho
      case ItemStatus.allocated:
        return const Color(0xFF8B5CF6); // Tím: Đã giữ hàng
      case ItemStatus.picked:
        return const Color(0xFFEC4899); // Hồng: Đã lấy
      case ItemStatus.waitingShipment:
        return const Color(0xFF3B82F6); // Xanh biển: Chờ xuất
      case ItemStatus.out:
        return const Color(0xFF64748B); // Xám: Đã xuất kho
    }
  }

  String _getStatusDisplay(ItemStatus status) {
    switch (status) {
      case ItemStatus.pendingInbound:
        return '⏳ CHƯA NHẬP (DỰ KIẾN)';
      case ItemStatus.waitingPutaway:
        return '⚡ CHỜ XẾP KỆ (ĐÃ QUA CỔNG)';
      case ItemStatus.inStock:
        return '✓ TRONG KHO';
      case ItemStatus.allocated:
        return '🔒 ĐÃ GIỮ PO';
      case ItemStatus.picked:
        return '📦 ĐÃ NHẶT HÀNG';
      case ItemStatus.waitingShipment:
        return '🚚 CHỜ XUẤT HÀNG';
      case ItemStatus.out:
        return '📤 ĐÃ XUẤT KHO';
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final allItems = _repo.items;
    final totalCount = allItems.length;
    final inStockCount = allItems.where((i) => i.status == ItemStatus.inStock).length;
    final waitingPutawayCount = allItems.where((i) => i.status == ItemStatus.waitingPutaway).length;
    final pendingInboundCount = allItems.where((i) => i.status == ItemStatus.pendingInbound).length;

    final filteredItems = allItems.where((i) {
      if (_selectedStatusFilter != null && i.status != _selectedStatusFilter) {
        return false;
      }
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return i.serialNumber.toLowerCase().contains(q) ||
          i.epc.toLowerCase().contains(q) ||
          i.sku.toLowerCase().contains(q) ||
          i.productName.toLowerCase().contains(q) ||
          (i.orderNo ?? '').toLowerCase().contains(q);
    }).toList();

    return Container(
      color: c.bgDeep,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'LOOKUP & SERIAL MANAGEMENT',
                    style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tra Cứu Mã Serial, Thùng Carton & Thẻ RFID',
                    style: TextStyle(color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              // Summary stats chips
              Wrap(
                spacing: 8,
                children: [
                  _buildStatBadge('Trong kho: $inStockCount', const Color(0xFF10B981), c),
                  _buildStatBadge('Chờ xếp: $waitingPutawayCount', const Color(0xFF06B6D4), c),
                  _buildStatBadge('Chưa nhập: $pendingInboundCount', const Color(0xFFF59E0B), c),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Search Bar & Filter Row
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.bgCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.rfidCyan),
                  ),
                  child: TextField(
                    controller: _queryController,
                    style: TextStyle(color: c.textPrimary),
                    decoration: InputDecoration(
                      icon: Icon(Icons.search, color: c.rfidCyan),
                      hintText: 'Nhập mã Serial, EPC tag, Barcode, Thùng hoặc tên sản phẩm...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
                      border: InputBorder.none,
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: c.textSecondary, size: 18),
                              onPressed: () {
                                _queryController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                    onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Status Filter Tabs
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _buildFilterChip('Tất cả ($totalCount)', null, c),
              _buildFilterChip('✓ Trong kho ($inStockCount)', ItemStatus.inStock, c),
              _buildFilterChip('⚡ Chờ xếp kệ ($waitingPutawayCount)', ItemStatus.waitingPutaway, c),
              _buildFilterChip('⏳ Chưa nhập kho / Dự kiến ($pendingInboundCount)', ItemStatus.pendingInbound, c),
            ],
          ),
          const SizedBox(height: 16),

          // Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: filteredItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 56, color: c.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isEmpty ? 'Chưa có mặt hàng nào phù hợp với bộ lọc.' : 'Không tìm thấy kết quả cho "$_searchQuery"',
                            style: TextStyle(color: c.textSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredItems.length,
                      separatorBuilder: (_, index) => Divider(color: c.border, height: 1),
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        final pallet = _repo.pallets.where((p) => p.palletId == item.palletId).firstOrNull;
                        final loc = item.locationId != null
                            ? _repo.locations.where((l) => l.locationId == item.locationId).firstOrNull
                            : (pallet != null ? _repo.locations.where((l) => l.locationId == pallet.locationId).firstOrNull : null);

                        final cartonDisplay = item.orderNo?.isNotEmpty == true
                            ? item.orderNo!
                            : (pallet?.palletCode ?? 'Chưa đóng thùng');
                        final locationDisplay = loc?.locationCode ?? (item.locationId ?? 'Chưa có vị trí');
                        final statusColor = _getStatusColor(item.status);
                        final statusText = _getStatusDisplay(item.status);

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  item.status == ItemStatus.inStock
                                      ? Icons.inventory_2
                                      : (item.status == ItemStatus.waitingPutaway ? Icons.move_to_inbox : Icons.pending_actions),
                                  color: statusColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.productName, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text('Serial: ${item.serialNumber} • SKU: ${item.sku}', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('EPC: ${item.epc}', style: TextStyle(color: c.rfidCyan, fontFamily: 'Courier', fontSize: 11, fontWeight: FontWeight.bold)),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Thùng: $cartonDisplay • Vị trí: $locationDisplay',
                                      style: TextStyle(
                                        color: item.status == ItemStatus.pendingInbound ? const Color(0xFFF59E0B) : c.textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: statusColor.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  statusText,
                                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10.5),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, ItemStatus? status, EyeCareColors c) {
    final isSelected = _selectedStatusFilter == status;
    return InkWell(
      onTap: () => setState(() => _selectedStatusFilter = status),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan : c.bgCardElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? c.rfidCyan : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? const Color(0xFF2C251E) : c.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }

  Widget _buildStatBadge(String text, Color color, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11),
      ),
    );
  }
}
