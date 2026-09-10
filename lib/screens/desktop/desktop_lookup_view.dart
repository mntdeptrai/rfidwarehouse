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
    final totalCount = allItems.length;
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
      final q = _searchQuery.toLowerCase();
      final supplier = _repo.getItemSupplier(i).toLowerCase();
      final carton = _repo.getItemCartonCode(i).toLowerCase();
      final inboundBy = _repo.getItemInboundBy(i).toLowerCase();
      final putawayBy = _repo.getItemPutawayBy(i).toLowerCase();

      return i.serialNumber.toLowerCase().contains(q) ||
          i.epc.toLowerCase().contains(q) ||
          i.sku.toLowerCase().contains(q) ||
          i.productName.toLowerCase().contains(q) ||
          (i.orderNo ?? '').toLowerCase().contains(q) ||
          carton.contains(q) ||
          supplier.contains(q) ||
          inboundBy.contains(q) ||
          putawayBy.contains(q);
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
              // 1. Tiêu đề & Thống kê
              Wrap(
                spacing: 14,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isNarrow ? 'TRA CỨU HÀNG HÓA RFID' : 'QUẢN LÝ VÀ ĐỐI SOÁT CHI TIẾT HÀNG HÓA RFID',
                        style: TextStyle(color: c.textSecondary, fontSize: isNarrow ? 10 : 11, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Chi Tiết Hàng Hóa & Mã RFID',
                        style: TextStyle(color: c.textPrimary, fontSize: isNarrow ? 18 : 22, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      _buildStatBadge('Mặt hàng: $distinctSkusCount SKU', c.rfidCyan, c),
                      _buildStatBadge('Tổng chip: $totalCount', const Color(0xFF8B5CF6), c),
                      _buildStatBadge('Đã lưu vị trí: $inStockCount', const Color(0xFF10B981), c),
                      _buildStatBadge('Chờ xếp kệ: $waitingPutawayCount', const Color(0xFF06B6D4), c),
                      _buildStatBadge('Xếp vào pallet: $waitingPalletizeCount', const Color(0xFFF97316), c),
                      _buildStatBadge('Chưa nhập: $pendingInboundCount', const Color(0xFFF59E0B), c),
                    ],
                  ),
                ],
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
                        hintText: 'Tìm SKU, RFID, NCC, Thùng, Người nhập...',
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
  // CHẾ ĐỘ 1: XEM THEO MẶT HÀNG (SKU) - 1 MẶT HÀNG NHIỀU MÃ RFID
  // ===========================================================================
  Widget _buildSkuGroupedView(Map<String, List<Item>> groups, EyeCareColors c) {
    final entries = groups.entries.toList();

    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final sku = entry.key;
        final items = entry.value;
        final firstItem = items.first;
        final prodName = firstItem.productName.isNotEmpty ? firstItem.productName : 'Sản phẩm $sku';
        final supplier = _repo.getItemSupplier(firstItem);
        final inStock = items.where((i) => i.status == ItemStatus.inStock).length;
        final waiting = items.where((i) => i.status == ItemStatus.waitingPutaway).length;
        final isExpanded = _expandedSkus.contains(sku);

        // Đếm các thùng hàng khác nhau
        final cartonCodes = items.map((i) => _repo.getItemCartonCode(i)).toSet().toList();

        return Container(
          decoration: BoxDecoration(
            color: c.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isExpanded ? c.rfidCyan.withValues(alpha: 0.7) : c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header mặt hàng
              InkWell(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
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
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: c.rfidCyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.inventory_2_outlined, color: c.rfidCyan, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
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
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    prodName,
                                    style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Nhà cung cấp: $supplier  •  ${cartonCodes.length} Thùng hàng (${cartonCodes.take(3).join(', ')}${cartonCodes.length > 3 ? '...' : ''})',
                              style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Thống kê số lượng RFID
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                            ),
                            child: Text(
                              '${items.length} Mã RFID',
                              style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11.5),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Kho: $inStock  •  Chờ xếp: $waiting',
                            style: TextStyle(color: c.textMuted, fontSize: 10.5),
                          ),
                        ],
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: c.textSecondary,
                        size: 20,
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
                    border: Border(top: BorderSide(color: c.border)),
                  ),
                  child: _buildItemsDataTable(items, c),
                ),
            ],
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
                  DataColumn(label: Text('MÃ CHIP RFID (EPC)', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
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

                      // 2. MÃ SẢN PHẨM (SKU)
                      DataCell(
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
                        Text(
                          item.serialNumber.isNotEmpty ? item.serialNumber : '--',
                          style: TextStyle(color: c.textSecondary, fontSize: 11, fontFamily: 'monospace'),
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

  Widget _buildStatBadge(String text, Color color, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 10.5),
      ),
    );
  }
}
