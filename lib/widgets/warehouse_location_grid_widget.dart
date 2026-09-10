import 'package:flutter/material.dart';
import '../models/wms_models.dart';
import '../services/warehouse_repository.dart';
import '../theme/eye_care_theme.dart';

/// Các trạng thái kệ chuẩn (Đồng bộ chuẩn giao diện Kiểm Kê Kho / Inventory View)
enum ShelfStatusType {
  full(
    label: 'KỆ ĐẦY',
    shortLabel: 'ĐẦY',
    statusCode: 'FULL',
    color: Color(0xFFEF4444),
    bgLight: Color(0x1AEF4444),
    desc: 'Kệ đã chứa đầy hàng',
  ),
  almostFull(
    label: 'SẮP HẾT CHỖ',
    shortLabel: 'SẮP HẾT',
    statusCode: 'NEAR_FULL',
    color: Color(0xFFF59E0B),
    bgLight: Color(0x1AF59E0B),
    desc: 'Kệ sắp hết chỗ trống',
  ),
  plentyAvailable(
    label: 'CÒN TRỐNG NHIỀU',
    shortLabel: 'CÒN TRỐNG',
    statusCode: 'AVAILABLE',
    color: Color(0xFF10B981),
    bgLight: Color(0x1A10B981),
    desc: 'Vị trí còn trống nhiều, sẵn sàng xếp hàng',
  );

  final String label;
  final String shortLabel;
  final String statusCode;
  final Color color;
  final Color bgLight;
  final String desc;

  const ShelfStatusType({
    required this.label,
    required this.shortLabel,
    required this.statusCode,
    required this.color,
    required this.bgLight,
    required this.desc,
  });
}

enum WarehouseLocationGridMode {
  outbound,
  inbound,
}

/// Widget hiển thị danh sách các ô kệ kho dạng ô thẻ trực quan
/// (Chuẩn giao diện Sơ đồ kệ của màn Kiểm Kê Kho / DesktopInventoryView)
class WarehouseLocationGridWidget extends StatefulWidget {
  final WarehouseLocationGridMode mode;
  final String? selectedLocationId;
  final ValueChanged<String?>? onLocationSelected;
  final VoidCallback? onLocationDataChanged;
  final double? maxGridHeight;
  final bool isCollapsible;
  final bool initialCollapsed;
  final double? maxHeight;
  final bool isExpanded;
  final bool defaultCollapsed;

  const WarehouseLocationGridWidget({
    super.key,
    this.mode = WarehouseLocationGridMode.outbound,
    this.selectedLocationId,
    this.onLocationSelected,
    this.onLocationDataChanged,
    this.maxHeight = 280.0,
    this.maxGridHeight,
    this.isCollapsible = true,
    this.isExpanded = false,
    this.defaultCollapsed = false,
    this.initialCollapsed = false,
  });

  @override
  State<WarehouseLocationGridWidget> createState() => _WarehouseLocationGridWidgetState();
}

class _WarehouseLocationGridWidgetState extends State<WarehouseLocationGridWidget> {
  final WarehouseRepository _repo = WarehouseRepository();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final ScrollController _scrollController = ScrollController();
  late bool _isCollapsed;
  String _selectedStatusFilter = 'ALL'; // ALL, FULL, NEAR_FULL, AVAILABLE
  final String _selectedZoneFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _isCollapsed = widget.defaultCollapsed || widget.initialCollapsed;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  ShelfStatusType _getShelfStatus(Location loc) {
    final s = loc.status.toUpperCase();
    if (s == 'FULL' || s == 'ĐẦY' || s == 'ĐÃ ĐẦY') {
      return ShelfStatusType.full;
    } else if (s == 'NEAR_FULL' || s == 'CÒN CHỖ' || s == 'SẮP HẾT') {
      return ShelfStatusType.almostFull;
    } else {
      return ShelfStatusType.plentyAvailable;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final allLocations = _repo.locations;

    // Đếm số lượng theo trạng thái
    int fullCount = 0;
    int almostFullCount = 0;
    int plentyCount = 0;

    for (final loc in allLocations) {
      final st = _getShelfStatus(loc);
      if (st == ShelfStatusType.full) fullCount++;
      if (st == ShelfStatusType.almostFull) almostFullCount++;
      if (st == ShelfStatusType.plentyAvailable) plentyCount++;
    }

    // Lọc ô kệ
    final filteredLocations = allLocations.where((loc) {
      final st = _getShelfStatus(loc);
      if (_selectedStatusFilter == 'FULL' && st != ShelfStatusType.full) return false;
      if (_selectedStatusFilter == 'NEAR_FULL' && st != ShelfStatusType.almostFull) return false;
      if (_selectedStatusFilter == 'AVAILABLE' && st != ShelfStatusType.plentyAvailable) return false;

      if (_selectedZoneFilter != 'ALL') {
        final z = loc.zone.trim().toUpperCase();
        if (z != _selectedZoneFilter.trim().toUpperCase()) return false;
      }
      return true;
    }).toList();

    Location? selectedLoc;
    if (widget.selectedLocationId != null) {
      selectedLoc = allLocations.where((l) =>
          l.locationId == widget.selectedLocationId ||
          l.locationCode == widget.selectedLocationId).firstOrNull;
    }

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ==================== 1. THANH TIÊU ĐỀ & CHÚ THÍCH MÀU SẮC (GIỐNG KIỂM KHO) ====================
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.bgDeep,
              borderRadius: _isCollapsed && selectedLoc == null
                  ? BorderRadius.circular(14)
                  : const BorderRadius.vertical(top: Radius.circular(14)),
              border: _isCollapsed && selectedLoc == null
                  ? null
                  : Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        Icon(Icons.shelves, color: c.rfidCyan, size: 19),
                        const SizedBox(width: 8),
                        Text(
                          allLocations.length == 10
                              ? 'SƠ ĐỒ 10 VỊ TRÍ KHO HÀNG (CÁC Ô KỆ)'
                              : 'SƠ ĐỒ VỊ TRÍ KHO HÀNG (${allLocations.length} Ô KỆ)',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.rfidCyan.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${allLocations.length} Ô KỆ',
                            style: TextStyle(
                              color: c.rfidCyan,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),

                        // Chú thích màu sắc chuẩn Kiểm Kho
                        _buildLegendPill(
                          color: ShelfStatusType.full.color,
                          label: 'Kệ đầy ($fullCount)',
                          value: 'FULL',
                          c: c,
                        ),
                        const SizedBox(width: 6),
                        _buildLegendPill(
                          color: ShelfStatusType.almostFull.color,
                          label: 'Sắp hết ($almostFullCount)',
                          value: 'NEAR_FULL',
                          c: c,
                        ),
                        const SizedBox(width: 6),
                        _buildLegendPill(
                          color: ShelfStatusType.plentyAvailable.color,
                          label: 'Còn trống ($plentyCount)',
                          value: 'AVAILABLE',
                          c: c,
                        ),
                        const SizedBox(width: 10),

                        // Nút Thêm kệ
                        IconButton(
                          tooltip: 'Thêm ô kệ mới',
                          icon: const Icon(Icons.add_circle_outline, size: 20),
                          color: const Color(0xFF10B981),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _showAddLocationDialog(context, c),
                        ),
                        const SizedBox(width: 8),
                        // Nút Đặt lại 10 kệ mẫu
                        IconButton(
                          tooltip: 'Đặt lại 10 kệ mẫu mặc định',
                          icon: const Icon(Icons.restart_alt_rounded, size: 20),
                          color: c.textSecondary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () => _confirmResetLocations(context, c),
                        ),
                        const SizedBox(width: 8),
                        // Nút Làm mới danh sách kệ
                        IconButton(
                          tooltip: 'Làm mới danh sách kệ',
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          color: c.textSecondary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onPressed: () async {
                            await _repo.reloadFromSqlite();
                            setState(() {});
                            widget.onLocationDataChanged?.call();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.isCollapsible) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: _isCollapsed ? 'Mở rộng lưới ô kệ' : 'Thu gọn lưới ô kệ',
                    icon: Icon(
                      _isCollapsed ? Icons.unfold_more_rounded : Icons.unfold_less_rounded,
                      size: 20,
                    ),
                    color: c.rfidCyan,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () {
                      setState(() {
                        _isCollapsed = !_isCollapsed;
                      });
                    },
                  ),
                ],
              ],
            ),
          ),

          // ==================== 2. BANNER KỆ ĐANG ĐƯỢC CHỌN ====================
          if (selectedLoc != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.mode == WarehouseLocationGridMode.outbound
                          ? 'Đang lọc sản phẩm tại [${selectedLoc.displayName}] (${_repo.getItemsAtLocation(selectedLoc).length} SP) • Bấm lại ô kệ để xem toàn bộ kho'
                          : 'Đã chọn vị trí cất hàng: [${selectedLoc.displayName}] (${selectedLoc.zone.isNotEmpty ? selectedLoc.zone : 'Khu A'} • ${selectedLoc.shelf.isNotEmpty ? selectedLoc.shelf : 'Tầng 1'})',
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => widget.onLocationSelected?.call(null),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(
                        'XEM TOÀN BỘ KHO',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ==================== 3. LƯỚI CÁC Ô KỆ (SỬ DỤNG GRIDVIEW & CUỘN TỰ ĐỘNG) ====================
          if (!_isCollapsed)
            allLocations.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                      decoration: BoxDecoration(
                        color: c.bgDeep,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border.withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shelves, size: 36, color: c.textMuted.withValues(alpha: 0.6)),
                          const SizedBox(height: 8),
                          Text(
                            'Chưa có ô vị trí / kệ nào trong kho',
                            style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Dữ liệu kho do bạn tự thêm và quản lý. Bấm nút bên dưới để tạo ô kệ đầu tiên.',
                            style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('➕ THÊM Ô KỆ MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            onPressed: () => _showAddLocationDialog(context, c),
                          ),
                        ],
                      ),
                    ),
                  )
                : widget.isExpanded
                    ? Expanded(
                        child: _buildGridBody(filteredLocations, selectedLoc, c),
                      )
                    : ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: widget.maxGridHeight ?? widget.maxHeight ?? 330.0,
                        ),
                        child: _buildGridBody(filteredLocations, selectedLoc, c),
                      ),
        ],
      ),
    );
  }

  Widget _buildGridBody(List<Location> filteredLocations, Location? selectedLoc, EyeCareColors c) {
    if (filteredLocations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text(
            'Không tìm thấy ô kệ nào khớp với bộ lọc.',
            style: TextStyle(color: c.textSecondary, fontSize: 13),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(10),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth;
          int crossAxisCount = 5;
          if (availableWidth < 500) {
            crossAxisCount = 1;
          } else if (availableWidth < 750) {
            crossAxisCount = 2;
          } else if (availableWidth < 1050) {
            crossAxisCount = 3;
          } else if (availableWidth < 1350) {
            crossAxisCount = 4;
          }

          return GridView.builder(
            shrinkWrap: !widget.isExpanded,
            physics: const BouncingScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisExtent: availableWidth < 500 ? 162 : 158,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemCount: filteredLocations.length,
            itemBuilder: (context, index) {
              final loc = filteredLocations[index];
              return _buildShelfCard(loc, selectedLoc, c);
            },
          );
        },
      ),
    );
  }

  // ---------- CHÚ THÍCH & LỌC TRẠNG THÁI (LEGEND PILL TỪ KIỂM KHO) ----------
  Widget _buildLegendPill({
    required Color color,
    required String label,
    required String value,
    required EyeCareColors c,
  }) {
    final isSelected = _selectedStatusFilter == value;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedStatusFilter = isSelected ? 'ALL' : value;
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.25) : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.4),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 4. THẺ Ô KỆ HÀNG (SHELF CARD - 100% THEO CHUẨN GIAO DIỆN KIỂM KHO)
  // ===========================================================================
  Widget _buildShelfCard(Location loc, Location? selectedLoc, EyeCareColors c) {
    final status = _getShelfStatus(loc);
    final isSelected = selectedLoc != null &&
        (selectedLoc.locationId == loc.locationId || selectedLoc.locationCode == loc.locationCode);

    final locCode = loc.locationCode.trim().toUpperCase();
    final locId = loc.locationId.trim().toUpperCase();
    final itemsOnShelf = _repo.items.where((i) {
      final itemLoc = i.locationId?.trim().toUpperCase();
      if (itemLoc == null || itemLoc.isEmpty) return false;
      return itemLoc == locCode || itemLoc == locId;
    }).toList();

    final palletsOnShelf = _repo.pallets.where((p) {
      final pLoc = p.locationId?.trim().toUpperCase();
      if (pLoc == null || pLoc.isEmpty) return false;
      return pLoc == locCode || pLoc == locId;
    }).toList();

    return LayoutBuilder(
      builder: (context, cardConstraints) {
        final cardW = cardConstraints.maxWidth;
        final isCompact = cardW < 275;
        final isVeryCompact = cardW < 235;

        final badgeText = isCompact ? status.shortLabel : status.label;

        return InkWell(
          onTap: () {
            if (isSelected) {
              widget.onLocationSelected?.call(null);
            } else {
              widget.onLocationSelected?.call(loc.locationCode);
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: EdgeInsets.all(isCompact ? 10 : 13),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.12) : c.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? const Color(0xFF10B981) : status.color.withValues(alpha: 0.6),
                width: isSelected ? 2.2 : 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: (isSelected ? const Color(0xFF10B981) : status.color).withValues(alpha: isSelected ? 0.18 : 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Dòng 1: Icon + Tên kệ + Badge trạng thái màu (Đỏ / Vàng / Xanh - Tự động co giãn)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.all(isCompact ? 6 : 8),
                      decoration: BoxDecoration(
                        color: status.bgLight,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.shelves, color: status.color, size: isCompact ? 18 : 20),
                    ),
                    SizedBox(width: isCompact ? 8 : 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            loc.displayName,
                            style: TextStyle(
                              color: isSelected ? const Color(0xFF10B981) : c.textPrimary,
                              fontSize: isCompact ? 13 : 14,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            loc.displaySubtitle,
                            style: TextStyle(color: c.textSecondary, fontSize: isCompact ? 10.5 : 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Badge trạng thái màu (Đỏ / Vàng / Xanh - Tự động co gọn chữ khi hẹp)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: isCompact ? 7 : 9, vertical: isCompact ? 4 : 5),
                      decoration: BoxDecoration(
                        color: status.color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: status.color.withValues(alpha: 0.7)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6.5,
                            height: 6.5,
                            decoration: BoxDecoration(color: status.color, shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4.5),
                          Text(
                            badgeText,
                            style: TextStyle(
                              color: status.color,
                              fontSize: isVeryCompact ? 9.5 : (isCompact ? 10 : 10.5),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isCompact ? 6 : 8),

                // Dòng 2: Chi tiết số chip RFID thực tế & Pallet (Tự động co giãn nội dung)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: isCompact ? 8 : 10, vertical: isCompact ? 6 : 7),
                  decoration: BoxDecoration(
                    color: c.bgCardElevated,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.inventory_2_outlined, size: isCompact ? 14 : 15, color: status.color),
                      SizedBox(width: isCompact ? 6 : 8),
                      Expanded(
                        child: Text(
                          itemsOnShelf.isNotEmpty
                              ? (palletsOnShelf.isNotEmpty
                                  ? (isCompact
                                      ? '${itemsOnShelf.length} SP (${palletsOnShelf.length} Pallet)'
                                      : 'Đang có ${itemsOnShelf.length} chip RFID • ${palletsOnShelf.length} Pallet (${palletsOnShelf.map((p) => p.palletCode).join(', ')})')
                                  : (isCompact ? '${itemsOnShelf.length} chip RFID' : 'Đang có ${itemsOnShelf.length} chip RFID trên kệ'))
                              : (palletsOnShelf.isNotEmpty
                                  ? 'Pallet rỗng: ${palletsOnShelf.map((p) => p.palletCode).join(', ')}'
                                  : (isCompact ? 'Kệ trống' : 'Kệ trống, chưa có chip RFID')),
                          style: TextStyle(
                            color: (itemsOnShelf.isNotEmpty || palletsOnShelf.isNotEmpty) ? c.textPrimary : c.textMuted,
                            fontSize: isCompact ? 10.5 : 11,
                            fontWeight: (itemsOnShelf.isNotEmpty || palletsOnShelf.isNotEmpty) ? FontWeight.w600 : FontWeight.normal,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: isCompact ? 6 : 8),

                // Dòng 3: Ghi chú nguồn cập nhật PDA & Thao tác (Tự co giãn an toàn)
                Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.phone_android_rounded, size: isCompact ? 12 : 13, color: c.textMuted),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              isCompact ? 'PDA' : 'Cập nhật từ PDA',
                              style: TextStyle(color: c.textMuted, fontSize: isCompact ? 10 : 10.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _showEditLocationDialog(context, loc, c),
                      child: Tooltip(
                        message: 'Sửa / Xóa kệ này',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Icon(Icons.edit_outlined, size: isCompact ? 13 : 14, color: c.textSecondary),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _showShelfDetailDialog(loc, status, itemsOnShelf.length, itemsOnShelf, c),
                      child: Text(
                        isSelected ? '✓ ĐANG CHỌN' : 'Chi tiết →',
                        style: TextStyle(
                          color: isSelected ? const Color(0xFF10B981) : c.rfidCyan,
                          fontSize: isCompact ? 10.5 : 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
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
  // 5. MODAL XEM CHI TIẾT KỆ & DANH SÁCH MẶT HÀNG TRÊN KỆ (CHUẨN KIỂM KHO)
  // ===========================================================================
  void _showShelfDetailDialog(
    Location loc,
    ShelfStatusType status,
    int currentCount,
    List<Item> itemsOnShelf,
    EyeCareColors c,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final curStatus = _getShelfStatus(loc);
          final locCode = loc.locationCode.trim().toUpperCase();
          final locId = loc.locationId.trim().toUpperCase();
          final liveItems = _repo.items.where((i) {
            final itemLoc = i.locationId?.trim().toUpperCase();
            if (itemLoc == null || itemLoc.isEmpty) return false;
            return itemLoc == locCode || itemLoc == locId;
          }).toList();

          final palletsOnShelf = _repo.pallets.where((p) {
            final pLoc = p.locationId?.trim().toUpperCase();
            if (pLoc == null || pLoc.isEmpty) return false;
            return pLoc == locCode || pLoc == locId;
          }).toList();

          return AlertDialog(
            backgroundColor: c.bgCard,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: curStatus.color, width: 1.5),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: curStatus.bgLight, borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.shelves, color: curStatus.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Chi tiết: ${loc.displayName} (${loc.locationCode})',
                        style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        loc.displaySubtitle,
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: curStatus.color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    curStatus.label,
                    style: TextStyle(color: curStatus.color, fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 620,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Đổi trạng thái trực tiếp
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: c.bgCardElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.edit_note_rounded, size: 16, color: c.rfidCyan),
                            const SizedBox(width: 6),
                            Text(
                              'CẬP NHẬT TRẠNG THÁI KỆ (ĐỒNG BỘ VỚI MÁY PDA):',
                              style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildQuickStatusBtn(
                                label: '🔴 KỆ ĐẦY',
                                statusVal: 'FULL',
                                color: const Color(0xFFEF4444),
                                isSelected: loc.status == 'FULL',
                                onTap: () async {
                                  loc.status = 'FULL';
                                  setDialogState(() {});
                                  setState(() {});
                                  await _repo.updateLocationStatus(loc.locationId, 'FULL');
                                  widget.onLocationDataChanged?.call();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildQuickStatusBtn(
                                label: '🟡 SẮP HẾT CHỖ',
                                statusVal: 'NEAR_FULL',
                                color: const Color(0xFFF59E0B),
                                isSelected: loc.status == 'NEAR_FULL',
                                onTap: () async {
                                  loc.status = 'NEAR_FULL';
                                  setDialogState(() {});
                                  setState(() {});
                                  await _repo.updateLocationStatus(loc.locationId, 'NEAR_FULL');
                                  widget.onLocationDataChanged?.call();
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _buildQuickStatusBtn(
                                label: '🟢 TRỐNG NHIỀU',
                                statusVal: 'AVAILABLE',
                                color: const Color(0xFF10B981),
                                isSelected: loc.status != 'FULL' && loc.status != 'NEAR_FULL',
                                onTap: () async {
                                  loc.status = 'AVAILABLE';
                                  setDialogState(() {});
                                  setState(() {});
                                  await _repo.updateLocationStatus(loc.locationId, 'AVAILABLE');
                                  widget.onLocationDataChanged?.call();
                                },
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Thông tin Pallet đang đặt tại kệ (nếu có chuyển kho từ PDA)
                  if (palletsOnShelf.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.pallet, color: Color(0xFF10B981), size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'Pallet tại kệ (${palletsOnShelf.length}): ',
                            style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Expanded(
                            child: Text(
                              palletsOnShelf.map((p) => '${p.palletCode} (${p.itemIds.length} SP)').join(' • '),
                              style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),

                  Text(
                    'Danh sách hàng hóa / RFID Chip trên kệ (${liveItems.length}):',
                    style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 8),

                  // Bảng danh sách thẻ RFID thực tế
                  Container(
                    height: 220,
                    decoration: BoxDecoration(
                      color: c.bgDeep,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.border),
                    ),
                    child: liveItems.isEmpty
                        ? Center(
                            child: Text(
                              'Kệ hiện đang trống, chưa có sản phẩm / chip RFID nào được gán vị trí này.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: c.textMuted, fontSize: 12),
                            ),
                          )
                        : ListView.separated(
                            itemCount: liveItems.length,
                            separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                            itemBuilder: (dialogListCtx, idx) {
                              final item = liveItems[idx];
                              final itemPallet = item.palletId != null
                                  ? _repo.pallets.where((p) => p.palletId == item.palletId).firstOrNull
                                  : null;
                              return ListTile(
                                dense: true,
                                leading: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: c.rfidCyan.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(Icons.nfc, color: c.rfidCyan, size: 16),
                                ),
                                title: Text(
                                  item.productName.isNotEmpty ? item.productName : item.sku,
                                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                                subtitle: Text(
                                  itemPallet != null
                                      ? 'EPC: ${item.epc}  •  📦 Pallet: ${itemPallet.palletCode}'
                                      : 'EPC: ${item.epc}',
                                  style: TextStyle(color: c.textMuted, fontSize: 10.5, fontFamily: 'Courier'),
                                ),
                                trailing: Text(
                                  item.status.label,
                                  style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 15, color: Color(0xFF10B981)),
                label: const Text('SỬA THÔNG TIN KỆ', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showEditLocationDialog(context, loc, c);
                },
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('ĐÓNG', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildQuickStatusBtn({
    required String label,
    required String statusVal,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color, width: isSelected ? 2 : 1),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : color,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              fontSize: 11.5,
            ),
          ),
        ),
      ),
    );
  }

  // ---------- DIALOG SỬA THÔNG TIN Ô KỆ ----------
  void _showEditLocationDialog(BuildContext context, Location loc, EyeCareColors c) {
    final codeCtrl = TextEditingController(text: loc.locationCode);
    final zoneCtrl = TextEditingController(text: loc.zone.isNotEmpty ? loc.zone : 'Khu A');
    final shelfCtrl = TextEditingController(text: loc.shelf.isNotEmpty ? loc.shelf : 'Kệ A1');
    final levelCtrl = TextEditingController(text: loc.level.isNotEmpty ? loc.level : 'Tầng 1');
    final capCtrl = TextEditingController(text: '${loc.maxPalletCapacity > 0 ? loc.maxPalletCapacity : 20}');
    String selectedStatus = loc.status;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              const Icon(Icons.edit_note_rounded, color: Color(0xFF10B981)),
              const SizedBox(width: 8),
              Text('Chỉnh sửa ${loc.displayName}', style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: codeCtrl,
                    decoration: InputDecoration(
                      labelText: 'Mã Vị Trí (Location Code)',
                      labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: zoneCtrl,
                          decoration: InputDecoration(
                            labelText: 'Khu vực (Zone)',
                            labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: shelfCtrl,
                          decoration: InputDecoration(
                            labelText: 'Tên Kệ (Shelf)',
                            labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedStatus,
                    decoration: InputDecoration(
                      labelText: 'Trạng thái kệ',
                      labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'AVAILABLE', child: Text('🟢 CÒN TRỐNG NHIỀU')),
                      DropdownMenuItem(value: 'NEAR_FULL', child: Text('🟡 SẮP HẾT CHỖ')),
                      DropdownMenuItem(value: 'FULL', child: Text('🔴 KỆ ĐẦY')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDlgState(() => selectedStatus = val);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
              label: const Text('XÓA KỆ NÀY', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold)),
              onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: ctx,
                  builder: (confirmCtx) => AlertDialog(
                    backgroundColor: c.bgCard,
                    title: Text('Xác nhận xóa ô kệ?', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
                    content: Text(
                      'Bạn có chắc chắn muốn xóa ô kệ "${loc.displayName}" (${loc.locationCode}) khỏi sơ đồ kho không?',
                      style: TextStyle(color: c.textSecondary),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(confirmCtx, false), child: Text('HỦY', style: TextStyle(color: c.textMuted))),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                        onPressed: () => Navigator.pop(confirmCtx, true),
                        child: const Text('XÓA KỆ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await _repo.deleteLocation(loc.locationId);
                  if (ctx.mounted) Navigator.of(ctx).pop();
                  if (widget.selectedLocationId == loc.locationId || widget.selectedLocationId == loc.locationCode) {
                    widget.onLocationSelected?.call(null);
                  }
                  setState(() {});
                  widget.onLocationDataChanged?.call();
                }
              },
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final cap = int.tryParse(capCtrl.text) ?? loc.maxPalletCapacity;
                await _repo.updateLocationDetails(
                  locationId: loc.locationId,
                  locationCode: codeCtrl.text.trim().toUpperCase(),
                  zone: zoneCtrl.text.trim(),
                  shelf: shelfCtrl.text.trim(),
                  level: levelCtrl.text.trim(),
                  maxCapacity: cap,
                  status: selectedStatus,
                  aisleSide: loc.aisleSide,
                  sortOrder: loc.sortOrder,
                );
                if (ctx.mounted) Navigator.of(ctx).pop();
                setState(() {});
                widget.onLocationDataChanged?.call();
              },
              child: const Text('LƯU'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- DIALOG THÊM Ô KỆ MỚI ----------
  void _showAddLocationDialog(BuildContext context, EyeCareColors c) {
    final codeCtrl = TextEditingController();
    final zoneCtrl = TextEditingController(text: 'Khu A');
    final shelfCtrl = TextEditingController(text: 'Kệ A');
    final levelCtrl = TextEditingController(text: 'Tầng 1');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            const Icon(Icons.add_location_alt_outlined, color: Color(0xFF10B981)),
            const SizedBox(width: 8),
            Text('Thêm ô kệ mới', style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 380,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  decoration: InputDecoration(
                    labelText: 'Mã Vị Trí / Kệ (VD: A-06, B-06)',
                    labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: zoneCtrl,
                        decoration: InputDecoration(
                          labelText: 'Khu vực (Zone)',
                          labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: shelfCtrl,
                        decoration: InputDecoration(
                          labelText: 'Tên Kệ (Shelf)',
                          labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final code = codeCtrl.text.trim().toUpperCase();
              if (code.isEmpty) return;

              final newLoc = Location(
                locationId: 'LOC-${DateTime.now().millisecondsSinceEpoch}',
                locationCode: code,
                zone: zoneCtrl.text.trim(),
                shelf: shelfCtrl.text.trim(),
                level: levelCtrl.text.trim(),
                status: 'AVAILABLE',
                maxPalletCapacity: 20,
                currentPallets: 0,
                aisleSide: 'LEFT',
                sortOrder: _repo.locations.length + 1,
              );

              await _repo.addCustomLocation(newLoc);
              if (ctx.mounted) Navigator.of(ctx).pop();
              setState(() {});
              widget.onLocationDataChanged?.call();
            },
            child: const Text('THÊM KỆ'),
          ),
        ],
      ),
    );
  }

  // ---------- XÁC NHẬN ĐẶT LẠI 10 KỆ MẪU ----------
  Future<void> _confirmResetLocations(BuildContext context, EyeCareColors c) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        title: Text('Đặt lại 10 kệ mặc định?', style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
        content: Text('Hệ thống sẽ sắp xếp lại 10 kệ mẫu A-01..A-05 và B-01..B-05.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('HỦY')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('XÁC NHẬN'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _repo.ensureDefault10Locations();
      setState(() {});
      widget.onLocationDataChanged?.call();
    }
  }
}

