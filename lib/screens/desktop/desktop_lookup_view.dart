import 'package:flutter/material.dart';
import '../../services/warehouse_repository.dart';
import '../../models/wms_models.dart';
import '../../theme/eye_care_theme.dart';

enum LookupDisplayMode {
  groupBySku,  // 1 mặt hàng (SKU) có nhiều mã RFID
  allFlatTable // Bảng chi tiết toàn bộ các dòng hàng hóa
}

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
  LookupDisplayMode _displayMode = LookupDisplayMode.groupBySku;
  final Set<String> _expandedSkus = {};

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
      case ItemStatus.waitingPalletize:
        return const Color(0xFFF97316); // Cam tươi: Xếp vào pallet
      case ItemStatus.waitingPutaway:
        return const Color(0xFF06B6D4); // Xanh dương nhạt: Chờ xếp kệ
      case ItemStatus.inStock:
        return const Color(0xFF10B981); // Xanh lá: Đã lưu vào vị trí
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
        return 'CHƯA NHẬP (DỰ KIẾN)';
      case ItemStatus.waitingPalletize:
        return 'XẾP VÀO PALLET';
      case ItemStatus.waitingPutaway:
        return 'CHỜ XẾP KỆ';
      case ItemStatus.inStock:
        return 'ĐÃ LƯU VÀO VỊ TRÍ';
      case ItemStatus.allocated:
        return 'ĐÃ GIỮ PO';
      case ItemStatus.picked:
        return 'ĐÃ NHẶT HÀNG';
      case ItemStatus.waitingShipment:
        return 'CHỜ XUẤT HÀNG';
      case ItemStatus.out:
        return 'ĐÃ XUẤT KHO';
    }
  }

  String _getLocationDisplay(Item item) {
    if (item.status == ItemStatus.out) {
      return 'ĐÃ XUẤT KHO';
    }
    final pallet = _repo.pallets.where((p) => p.palletId == item.palletId || p.palletCode == item.palletId).firstOrNull;
    final loc = item.locationId != null
        ? _repo.locations.where((l) => l.locationId == item.locationId || l.locationCode == item.locationId).firstOrNull
        : (pallet != null ? _repo.locations.where((l) => l.locationId == pallet.locationId || l.locationCode == pallet.locationId).firstOrNull : null);

    return loc?.displayName ?? (loc?.locationCode ?? (item.locationId ?? (pallet?.locationId ?? 'Chưa có vị trí')));
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final allItems = _repo.items;
    final inStockCount = allItems.where((i) => i.status == ItemStatus.inStock).length;
    final waitingPutawayCount = allItems.where((i) => i.status == ItemStatus.waitingPutaway).length;
    final waitingPalletizeCount = allItems.where((i) => i.status == ItemStatus.waitingPalletize).length;
    final pendingInboundCount = allItems.where((i) => i.status == ItemStatus.pendingInbound).length;
    final distinctSkusCount = allItems.map((i) => i.sku).toSet().length;

    final filteredItems = allItems.where((i) {
      if (_selectedStatusFilter != null && i.status != _selectedStatusFilter) {
        return false;
      }
      if (_searchQuery.isEmpty) return true;

      final rawQ = _searchQuery.toLowerCase().trim();

      // 1. Chuẩn hóa: bóc tách tiền tố nếu người dùng gõ kiểu 'S/N: ...', 'SN: ...', 'Product ID: ...', 'ID: ...'
      final cleanQ = rawQ
          .replaceAll('s/n:', '')
          .replaceAll('sn:', '')
          .replaceAll('product_id:', '')
          .replaceAll('product id:', '')
          .replaceAll('productid:', '')
          .replaceAll('prod_id:', '')
          .replaceAll('prod id:', '')
          .replaceAll('id:', '')
          .replaceAll('sku:', '')
          .replaceAll('rfid:', '')
          .replaceAll('epc:', '')
          .trim();

      final q = cleanQ.isNotEmpty ? cleanQ : rawQ;
      final qNoSpecial = q.replaceAll('-', '').replaceAll('_', '').replaceAll('/', '').replaceAll(' ', '');
      final qSnReplaced = q.replaceAll('s/n', 'sn');

      final serial = i.serialNumber.toLowerCase();
      final serialNoSpecial = serial.replaceAll('-', '').replaceAll('_', '').replaceAll('/', '').replaceAll(' ', '');
      final prodId = i.productId.toLowerCase();
      final prodIdNoSpecial = prodId.replaceAll('-', '').replaceAll('_', '').replaceAll('/', '').replaceAll(' ', '');
      final itemId = i.itemId.toLowerCase();
      final itemIdNoSpecial = itemId.replaceAll('-', '').replaceAll('_', '').replaceAll('/', '').replaceAll(' ', '');
      final sku = i.sku.toLowerCase();
      final epc = i.epc.toLowerCase();
      final name = i.productName.toLowerCase();
      final order = (i.orderNo ?? '').toLowerCase();
      final loc = (i.locationId ?? '').toLowerCase();
      final pallet = (i.palletId ?? '').toLowerCase();
      final supplier = _repo.getItemSupplier(i).toLowerCase();
      final carton = _repo.getItemCartonCode(i).toLowerCase();
      final inboundBy = _repo.getItemInboundBy(i).toLowerCase();
      final putawayBy = _repo.getItemPutawayBy(i).toLowerCase();

      // Kiểm tra khớp trực tiếp
      if (serial.contains(q) ||
          prodId.contains(q) ||
          itemId.contains(q) ||
          sku.contains(q) ||
          epc.contains(q) ||
          name.contains(q) ||
          order.contains(q) ||
          loc.contains(q) ||
          pallet.contains(q) ||
          carton.contains(q) ||
          supplier.contains(q) ||
          inboundBy.contains(q) ||
          putawayBy.contains(q)) {
        return true;
      }

      // Khớp chuẩn hóa S/N <-> SN
      if (qSnReplaced.isNotEmpty && (serial.contains(qSnReplaced) || prodId.contains(qSnReplaced))) {
        return true;
      }

      // Khớp không phân biệt ký tự đặc biệt (gạch ngang, gạch dưới, khoảng trắng)
      if (qNoSpecial.length >= 2) {
        if (serialNoSpecial.contains(qNoSpecial) ||
            prodIdNoSpecial.contains(qNoSpecial) ||
            itemIdNoSpecial.contains(qNoSpecial)) {
          return true;
        }
      }

      // Khớp từ khóa 's/n' hoặc 'sn' đơn thuần nếu item có số serial
      if ((rawQ == 's/n' || rawQ == 'sn') && serial.isNotEmpty) {
        return true;
      }

      return false;
    }).toList();

    // Nhóm theo SKU
    final Map<String, List<Item>> skuGroups = {};
    for (final item in filteredItems) {
      final key = item.sku.isNotEmpty ? item.sku : 'SKU-CHUA-RO';
      skuGroups.putIfAbsent(key, () => []).add(item);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenW = constraints.maxWidth;
        final isNarrow = screenW < 750;
        final edgePad = isNarrow ? 10.0 : 20.0;

        return Container(
          color: c.bgDeep,
          padding: EdgeInsets.all(edgePad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Tiêu đề
              Text(
                'Chi Tiết Hàng Hóa & Mã RFID',
                style: TextStyle(color: c.textPrimary, fontSize: isNarrow ? 18 : 22, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 14),

              // 2. Chế độ hiển thị & Thanh tìm kiếm
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  // Nút chuyển chế độ xem
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Container(
                      decoration: BoxDecoration(
                        color: c.bgCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.border),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildModeButton(
                            title: 'Xem theo Mặt Hàng ($distinctSkusCount SKU)',
                            icon: Icons.category_outlined,
                            isSelected: _displayMode == LookupDisplayMode.groupBySku,
                            onTap: () => setState(() => _displayMode = LookupDisplayMode.groupBySku),
                            c: c,
                          ),
                          const SizedBox(width: 4),
                          _buildModeButton(
                            title: 'Bảng Chi Tiết Toàn Bộ (${filteredItems.length})',
                            icon: Icons.table_chart_outlined,
                            isSelected: _displayMode == LookupDisplayMode.allFlatTable,
                            onTap: () => setState(() => _displayMode = LookupDisplayMode.allFlatTable),
                            c: c,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Thanh tìm kiếm
                  Container(
                    width: isNarrow ? double.infinity : 400,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.rfidCyan.withValues(alpha: 0.6)),
                    ),
                    child: TextField(
                      controller: _queryController,
                      style: TextStyle(color: c.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        icon: Icon(Icons.search, color: c.rfidCyan, size: 18),
                        hintText: 'Tìm S/N, Product ID, SKU, RFID, NCC, Thùng...',
                        hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                        border: InputBorder.none,
                        isDense: true,
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, color: c.textSecondary, size: 16),
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
                ],
              ),
              const SizedBox(height: 10),

              // 3. Status Filter Tabs
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildFilterChip('Tất cả (${filteredItems.length})', null, c),
                    const SizedBox(width: 8),
                    _buildFilterChip('Đã lưu vị trí ($inStockCount)', ItemStatus.inStock, c),
                    const SizedBox(width: 8),
                    _buildFilterChip('Chờ xếp kệ ($waitingPutawayCount)', ItemStatus.waitingPutaway, c),
                    const SizedBox(width: 8),
                    _buildFilterChip('Xếp vào pallet ($waitingPalletizeCount)', ItemStatus.waitingPalletize, c),
                    const SizedBox(width: 8),
                    _buildFilterChip('Chưa nhập kho ($pendingInboundCount)', ItemStatus.pendingInbound, c),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // 4. Nội dung chính: Nhóm theo SKU hoặc Bảng chi tiết toàn bộ
              Expanded(
                child: filteredItems.isEmpty
                    ? Container(
                        decoration: BoxDecoration(
                          color: c.bgCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: c.border),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.search_off, size: 52, color: c.textMuted),
                              const SizedBox(height: 10),
                              Text(
                                _searchQuery.isEmpty ? 'Chưa có mặt hàng nào phù hợp với bộ lọc.' : 'Không tìm thấy kết quả cho "$_searchQuery"',
                                style: TextStyle(color: c.textSecondary, fontSize: 13.5),
                              ),
                            ],
                          ),
                        ),
                      )
                    : (_displayMode == LookupDisplayMode.groupBySku
                        ? _buildSkuGroupedView(skuGroups, c)
                        : _buildAllFlatTableView(filteredItems, c)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModeButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required EyeCareColors c,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? const Color(0xFF2C251E) : c.textSecondary),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? const Color(0xFF2C251E) : c.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // CHẾ ĐỘ 1: XEM THEO MẶT HÀNG (SKU) - CHIA THEO CỘT THÔNG TIN CHUẨN
  // ===========================================================================
  Widget _buildSkuTableHeader(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.bgCardElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text('#', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 160,
            child: Text('MÃ SKU', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 4,
            child: Text('TÊN SẢN PHẨM', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text('NHÀ CUNG CẤP', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: Text('THÙNG / PALLET', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 95,
            child: Center(
              child: Text('TỔNG CHIP', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 150,
            child: Text('TRẠNG THÁI', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11)),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 44,
            child: Center(
              child: Text('CHI TIẾT', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStatusTag(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSkuGroupedView(Map<String, List<Item>> groups, EyeCareColors c) {
    final entries = groups.entries.toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        const double minTableWidth = 1050;
        final double tableWidth = constraints.maxWidth < minTableWidth ? minTableWidth : constraints.maxWidth;
        final bool isHeightFinite = constraints.maxHeight.isFinite;

        final listWidget = ListView.separated(
          itemCount: entries.length,
          shrinkWrap: !isHeightFinite,
          physics: isHeightFinite ? const BouncingScrollPhysics() : const NeverScrollableScrollPhysics(),
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final sku = entry.key;
            final items = entry.value;
            final firstItem = items.first;
            final prodName = firstItem.productName.isNotEmpty ? firstItem.productName : 'Sản phẩm $sku';
            final supplier = _repo.getItemSupplier(firstItem);
            final inStock = items.where((i) => i.status == ItemStatus.inStock).length;
            final waiting = items.where((i) => i.status == ItemStatus.waitingPutaway).length;
            final palletize = items.where((i) => i.status == ItemStatus.waitingPalletize).length;
            final pending = items.where((i) => i.status == ItemStatus.pendingInbound).length;
            final isExpanded = _expandedSkus.contains(sku) || _searchQuery.isNotEmpty;

            // Đếm các thùng hàng khác nhau
            final cartonCodes = items.map((i) => _repo.getItemCartonCode(i)).toSet().toList();

            return Container(
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isExpanded ? c.rfidCyan.withValues(alpha: 0.7) : c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header mặt hàng chia theo cột
                  InkWell(
                    borderRadius: isExpanded
                        ? const BorderRadius.vertical(top: Radius.circular(8))
                        : BorderRadius.circular(8),
                    onTap: () {
                      setState(() {
                        if (isExpanded) {
                          _expandedSkus.remove(sku);
                        } else {
                          _expandedSkus.add(sku);
                        }
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      child: Row(
                        children: [
                          // 1. # (STT)
                          SizedBox(
                            width: 36,
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: c.textMuted,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // 2. MÃ SKU & ID
                          SizedBox(
                            width: 160,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: const Color(0xFF8B5CF6)),
                                  ),
                                  child: Text(
                                    sku,
                                    style: const TextStyle(
                                      color: Color(0xFF8B5CF6),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (firstItem.productId.isNotEmpty && firstItem.productId != sku) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'ID: ${firstItem.productId}',
                                    style: TextStyle(
                                      color: c.rfidCyan,
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),

                          // 3. TÊN SẢN PHẨM
                          Expanded(
                            flex: 4,
                            child: Text(
                              prodName,
                              style: TextStyle(
                                color: c.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // 4. NHÀ CUNG CẤP
                          Expanded(
                            flex: 3,
                            child: Text(
                              supplier.isNotEmpty ? supplier : '---',
                              style: TextStyle(
                                color: c.textSecondary,
                                fontSize: 11.5,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 12),

                          // 5. THÙNG / PALLET
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  cartonCodes.isNotEmpty ? '${cartonCodes.length} Thùng' : '0 Thùng',
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 11.5,
                                  ),
                                ),
                                if (cartonCodes.isNotEmpty) ...[
                                  const SizedBox(height: 1),
                                  Text(
                                    cartonCodes.take(2).join(', ') + (cartonCodes.length > 2 ? '...' : ''),
                                    style: TextStyle(
                                      color: c.textMuted,
                                      fontSize: 10,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),

                          // 6. TỔNG CHIP
                          SizedBox(
                            width: 95,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                                ),
                                child: Text(
                                  '${items.length} Chip',
                                  style: const TextStyle(
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // 7. TRẠNG THÁI
                          SizedBox(
                            width: 150,
                            child: Wrap(
                              spacing: 4,
                              runSpacing: 3,
                              children: [
                                if (inStock > 0) _buildMiniStatusTag('Kho: $inStock', const Color(0xFF10B981)),
                                if (waiting > 0) _buildMiniStatusTag('Chờ: $waiting', const Color(0xFF06B6D4)),
                                if (palletize > 0) _buildMiniStatusTag('Pallet: $palletize', const Color(0xFFF97316)),
                                if (pending > 0) _buildMiniStatusTag('Chưa: $pending', const Color(0xFFF59E0B)),
                                if (inStock == 0 && waiting == 0 && palletize == 0 && pending == 0)
                                  _buildMiniStatusTag('0 chip', c.textMuted),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),

                          // 8. CHI TIẾT
                          SizedBox(
                            width: 44,
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: isExpanded ? c.rfidCyan.withValues(alpha: 0.15) : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Icon(
                                  isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  color: isExpanded ? c.rfidCyan : c.textSecondary,
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Bảng chi tiết toàn bộ mã RFID của mặt hàng này
                  if (isExpanded)
                    Container(
                      decoration: BoxDecoration(
                        color: c.bgDeep.withValues(alpha: 0.5),
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8)),
                        border: Border(top: BorderSide(color: c.border)),
                      ),
                      child: _buildItemsDataTable(items, c),
                    ),
                ],
              ),
            );
          },
        );

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: SizedBox(
            width: tableWidth,
            height: isHeightFinite ? constraints.maxHeight : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSkuTableHeader(c),
                const SizedBox(height: 8),
                if (isHeightFinite)
                  Expanded(child: listWidget)
                else
                  listWidget,
              ],
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // CHẾ ĐỘ 2: BẢNG DỮ LIỆU CHI TIẾT TOÀN BỘ (DATA TABLE CHUẨN CỘT USER YÊU CẦU)
  // ===========================================================================
  Widget _buildAllFlatTableView(List<Item> items, EyeCareColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: _buildItemsDataTable(items, c),
    );
  }

  // ===========================================================================
  // BẢNG DỮ LIỆU CHUNG HIỂN THỊ ĐỦ CÁC CỘT:
  // Nhà cung cấp, Mã sản phẩm, Ngày nhập, Mã thùng hàng, Người nhập, Người cất kệ, Mã RFID/Serial...
  // ===========================================================================
  Widget _buildItemsDataTable(List<Item> items, EyeCareColors c) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: DataTable(
                headingRowHeight: 38,
                dataRowMinHeight: 38,
                dataRowMaxHeight: 46,
                horizontalMargin: 12,
                columnSpacing: 16,
                headingRowColor: WidgetStatePropertyAll(c.bgCardElevated),
                columns: [
                  DataColumn(label: Text('#', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('NHÀ CUNG CẤP', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('MÃ SẢN PHẨM', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('TÊN SẢN PHẨM', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('EPC', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('SỐ SERIAL', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('MÃ THÙNG HÀNG', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('NGÀY NHẬP', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('NGƯỜI NHẬP', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('NGƯỜI CẤT KỆ', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('VỊ TRÍ KỆ', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                  DataColumn(label: Text('TRẠNG THÁI', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                ],
                rows: items.asMap().entries.map((e) {
                  final idx = e.key + 1;
                  final item = e.value;
                  final supplier = _repo.getItemSupplier(item);
                  final carton = _repo.getItemCartonCode(item);
                  final inboundBy = _repo.getItemInboundBy(item);
                  final putawayBy = _repo.getItemPutawayBy(item);
                  final inTime = _repo.getItemInboundTime(item);
                  final inTimeStr = '${inTime.day.toString().padLeft(2, '0')}/${inTime.month.toString().padLeft(2, '0')}/${inTime.year} ${inTime.hour.toString().padLeft(2, '0')}:${inTime.minute.toString().padLeft(2, '0')}';
                  final locDisplay = _getLocationDisplay(item);
                  final statusColor = _getStatusColor(item.status);
                  final statusText = _getStatusDisplay(item.status);

                  return DataRow(
                    cells: [
                      // # STT
                      DataCell(Text('$idx', style: TextStyle(color: c.textMuted, fontSize: 11))),

                      // 1. NHÀ CUNG CẤP
                      DataCell(
                        Container(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            supplier,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),

                      // 2. MÃ SẢN PHẨM (SKU & PRODUCT ID)
                      DataCell(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                              ),
                              child: Text(
                                item.sku,
                                style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace'),
                              ),
                            ),
                            if (item.productId.isNotEmpty && item.productId != item.sku)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  item.productId,
                                  style: TextStyle(color: c.textMuted, fontSize: 10, fontFamily: 'monospace'),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // TÊN SẢN PHẨM
                      DataCell(
                        Container(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            item.productName,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                          ),
                        ),
                      ),

                      // MÃ CHIP RFID (EPC)
                      DataCell(
                        Text(
                          item.epc,
                          style: TextStyle(color: c.rfidCyan, fontSize: 11, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                        ),
                      ),

                      // SỐ SERIAL
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: item.serialNumber.isNotEmpty ? const Color(0xFF0EA5E9).withValues(alpha: 0.1) : Colors.transparent,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.serialNumber.isNotEmpty ? item.serialNumber : '--',
                            style: TextStyle(
                              color: item.serialNumber.isNotEmpty ? const Color(0xFF0284C7) : c.textSecondary,
                              fontSize: 11,
                              fontFamily: 'monospace',
                              fontWeight: item.serialNumber.isNotEmpty ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ),
                      ),

                      // 3. MÃ THÙNG HÀNG
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            carton,
                            style: const TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 11),
                          ),
                        ),
                      ),

                      // 4. NGÀY NHẬP
                      DataCell(
                        Text(
                          inTimeStr,
                          style: TextStyle(color: c.textSecondary, fontSize: 11),
                        ),
                      ),

                      // 5. NGƯỜI NHẬP
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.login_rounded, size: 13, color: c.textSecondary),
                            const SizedBox(width: 4),
                            Text(
                              inboundBy,
                              style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),

                      // 6. NGƯỜI CẤT KỆ
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shelves, size: 13, color: item.status == ItemStatus.inStock ? const Color(0xFF10B981) : c.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              putawayBy,
                              style: TextStyle(
                                color: item.status == ItemStatus.inStock ? c.textPrimary : c.textMuted,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),

                      // VỊ TRÍ KỆ
                      DataCell(
                        Text(
                          locDisplay,
                          style: TextStyle(color: c.textSecondary, fontSize: 11),
                        ),
                      ),

                      // TRẠNG THÁI
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: statusColor.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, ItemStatus? status, EyeCareColors c) {
    final isSelected = _selectedStatusFilter == status;
    return InkWell(
      onTap: () => setState(() => _selectedStatusFilter = status),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}
