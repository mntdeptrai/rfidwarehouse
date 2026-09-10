import 'package:flutter/material.dart';
import '../../services/warehouse_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/eye_care_theme.dart';
import '../../models/wms_models.dart';

enum InventoryViewTab {
  rackGrid,
  auditSessions,
}

enum ShelfStatusType {
  full(
    label: 'KỆ ĐẦY',
    shortLabel: 'ĐẦY',
    statusCode: 'FULL',
    color: Color(0xFFEF4444),
    bgLight: Color(0x1AEF4444),
    desc: 'Được đánh dấu Kệ Đầy từ máy PDA',
  ),
  almostFull(
    label: 'SẮP HẾT CHỖ',
    shortLabel: 'SẮP HẾT',
    statusCode: 'NEAR_FULL',
    color: Color(0xFFF59E0B),
    bgLight: Color(0x1AF59E0B),
    desc: 'Được đánh dấu Sắp Hết Chỗ từ máy PDA',
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

class DesktopInventoryView extends StatefulWidget {
  const DesktopInventoryView({super.key});

  @override
  State<DesktopInventoryView> createState() => _DesktopInventoryViewState();
}

class _DesktopInventoryViewState extends State<DesktopInventoryView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final AuthService _auth = AuthService();

  InventoryViewTab _activeTab = InventoryViewTab.rackGrid;
  InventorySession? _selectedSession;

  String _selectedZoneFilter = 'ALL';
  String _selectedStatusFilter = 'ALL';
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onThemeChanged);
    _repo.addListener(_onThemeChanged);

    // Mặc định đối với vai trò Thủ Kho là mở giao diện lưới trạng thái kệ
    final user = _auth.currentUser;
    final isKeeper = user?.rolePermission.code == 'thukho' || user?.role == 'thukho';
    _activeTab = isKeeper ? InventoryViewTab.rackGrid : InventoryViewTab.rackGrid;
  }

  @override
  void dispose() {
    _searchController.dispose();
    _repo.removeListener(_onThemeChanged);
    _eyeCare.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  /// Đếm số lượng sản phẩm THỰC TẾ đang có trên kệ từ CSDL (Không dùng mockdata)
  int _getShelfCurrentCount(Location loc) {
    final locCode = loc.locationCode.trim().toUpperCase();
    final locId = loc.locationId.trim().toUpperCase();

    return _repo.items.where((i) {
      final itemLoc = i.locationId?.trim().toUpperCase();
      if (itemLoc == null || itemLoc.isEmpty) return false;
      return itemLoc == locCode || itemLoc == locId;
    }).length;
  }

  /// Trạng thái kệ: Lấy trực tiếp từ thuộc tính status được cập nhật bởi máy cầm tay PDA
  ShelfStatusType _getShelfStatus(Location loc) {
    final s = loc.status.toUpperCase();
    if (s == 'FULL') {
      return ShelfStatusType.full; // ĐỎ: Kệ đầy
    } else if (s == 'NEAR_FULL') {
      return ShelfStatusType.almostFull; // VÀNG: Kệ sắp hết chỗ
    } else {
      return ShelfStatusType.plentyAvailable; // XANH: Kệ còn trống nhiều
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    if (_activeTab == InventoryViewTab.auditSessions) {
      if (_selectedSession != null) {
        return _buildSessionDetailView(_selectedSession!, c);
      }
      return _buildSessionListView(c);
    }

    return _buildRackGridView(c);
  }

  // ===========================================================================
  // 1. GIAO DIỆN LƯỚI HIỂN THỊ TÌNH TRẠNG KỆ (CHO THỦ KHO)
  // ===========================================================================
  Widget _buildRackGridView(EyeCareColors c) {
    final allLocations = List<Location>.from(_repo.locations);
    allLocations.sort((a, b) {
      final z = a.zone.compareTo(b.zone);
      if (z != 0) return z;
      final s = a.shelf.compareTo(b.shelf);
      if (s != 0) return s;
      final l = a.level.compareTo(b.level);
      if (l != 0) return l;
      return a.locationCode.compareTo(b.locationCode);
    });

    // Tính toán thống kê số lượng kệ theo trạng thái thực tế
    int fullCount = 0;
    int almostFullCount = 0;
    int plentyCount = 0;

    for (final loc in allLocations) {
      final status = _getShelfStatus(loc);
      if (status == ShelfStatusType.full) fullCount++;
      if (status == ShelfStatusType.almostFull) almostFullCount++;
      if (status == ShelfStatusType.plentyAvailable) plentyCount++;
    }

    // Lọc danh sách kệ theo Khu vực, Trạng thái & Từ khóa tìm kiếm
    final filteredLocations = allLocations.where((loc) {
      if (_selectedZoneFilter != 'ALL' && !loc.zone.toUpperCase().contains(_selectedZoneFilter.toUpperCase())) {
        return false;
      }

      final status = _getShelfStatus(loc);
      if (_selectedStatusFilter == 'FULL' && status != ShelfStatusType.full) return false;
      if (_selectedStatusFilter == 'NEAR_FULL' && status != ShelfStatusType.almostFull) return false;
      if (_selectedStatusFilter == 'PLENTY' && status != ShelfStatusType.plentyAvailable) return false;

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toUpperCase();
        final matchCode = loc.locationCode.toUpperCase().contains(q);
        final matchShelf = loc.displayName.toUpperCase().contains(q) || loc.shelf.toUpperCase().contains(q);
        final matchZone = loc.zone.toUpperCase().contains(q);
        final matchLevel = loc.level.toUpperCase().contains(q);
        if (!matchCode && !matchShelf && !matchZone && !matchLevel) return false;
      }

      return true;
    }).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final isUltraNarrow = screenWidth < 500;
        final isSmallScreen = screenWidth < 800;
        final isMediumScreen = screenWidth < 1200;
        final horizontalPadding = isUltraNarrow ? 8.0 : (isSmallScreen ? 12.0 : (isMediumScreen ? 16.0 : 20.0));
        final verticalPadding = isUltraNarrow ? 8.0 : (isSmallScreen ? 12.0 : 16.0);

        return Container(
          color: c.bgDeep,
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: verticalPadding),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header & Tab Switcher (Tự động co giãn theo chiều rộng cửa sổ)
                    _buildTopHeaderBar(c),
                    const SizedBox(height: 12),

                    // KPI Cards & Color Legend Bar (Tự động co giãn)
                    _buildKpiAndLegendBar(
                      c: c,
                      totalShelves: allLocations.length,
                      fullCount: fullCount,
                      almostFullCount: almostFullCount,
                      plentyCount: plentyCount,
                    ),
                    const SizedBox(height: 12),

                    // Toolbar Bộ lọc (Zone, Status, Search) với khả năng cuộn ngang an toàn
                    _buildFilterToolbar(c, allLocations),
                    const SizedBox(height: 14),
                  ],
                ),
              ),

              // Lưới kệ hàng (SliverGrid - Tự động co giãn thích ứng mọi kích thước, không bao giờ bị tràn đáy)
              if (filteredLocations.isEmpty)
                SliverToBoxAdapter(
                  child: _buildEmptyRackView(c),
                )
              else
                SliverGrid(
                  gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: screenWidth < 500 ? double.infinity : (screenWidth < 700 ? 300 : 330),
                    mainAxisExtent: 162,
                    crossAxisSpacing: isSmallScreen ? 10 : 14,
                    mainAxisSpacing: isSmallScreen ? 10 : 14,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final loc = filteredLocations[index];
                      return _buildShelfCard(loc, c);
                    },
                    childCount: filteredLocations.length,
                  ),
                ),

              const SliverToBoxAdapter(
                child: SizedBox(height: 24),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTopHeaderBar(EyeCareColors c) {
    return LayoutBuilder(
      builder: (_, constraints) {
        final isNarrow = constraints.maxWidth < 980;

        final titleSection = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  'QUẢN LÝ KHO • VAI TRÒ THỦ KHO',
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: constraints.maxWidth < 450 ? 10.5 : 11.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  softWrap: true,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.rfidCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.grid_view_rounded, size: 12, color: c.rfidCyan),
                      const SizedBox(width: 4),
                      Text(
                        'SƠ ĐỒ LƯỚI KỆ',
                        style: TextStyle(color: c.rfidCyan, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Sơ Đồ Trạng Thái Kệ Kho (Rack Grid)',
              style: TextStyle(
                color: c.textPrimary,
                fontSize: constraints.maxWidth < 450 ? 18 : 22,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        );

        final actionButtons = SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTabButton(
                      tab: InventoryViewTab.rackGrid,
                      icon: Icons.grid_view_rounded,
                      title: 'Sơ Đồ Kệ (Lưới)',
                      c: c,
                    ),
                    const SizedBox(width: 4),
                    _buildTabButton(
                      tab: InventoryViewTab.auditSessions,
                      icon: Icons.checklist_rounded,
                      title: 'Lịch Sử Kiểm Kê (${_repo.inventorySessions.length})',
                      c: c,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.textPrimary,
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('LÀM MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () async {
                  await _repo.refreshFromDatabase();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: c.successEmerald,
                        content: const Text('Đã làm mới dữ liệu trạng thái kệ kho từ CSDL'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  }
                },
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.rfidCyan,
                  foregroundColor: const Color(0xFF2C251E),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.add_location_alt_outlined, size: 18),
                label: const Text('+ THÊM KỆ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _showAddShelfDialog(c),
              ),
              if (_repo.locations.isNotEmpty) ...[
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  tooltip: 'Tùy chọn',
                  icon: Icon(Icons.more_vert, color: c.textSecondary, size: 20),
                  color: c.bgCard,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  onSelected: (val) async {
                    final messenger = ScaffoldMessenger.of(context);
                    if (val == 'clear_all') {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: c.bgCard,
                          title: const Text('Xác nhận xóa toàn bộ kệ', style: TextStyle(fontWeight: FontWeight.bold)),
                          content: Text(
                            'Bạn có chắc chắn muốn xóa toàn bộ ${_repo.locations.length} kệ hàng hiện tại trong kho không?\n(Sau khi xóa, bạn có thể tự thêm lại kệ mới theo ý muốn).',
                            style: TextStyle(color: c.textPrimary),
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('HỦY', style: TextStyle(color: c.textSecondary))),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('XÓA HẾT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true) {
                        await _repo.deleteAllLocations();
                        if (mounted) setState(() {});
                        messenger.showSnackBar(
                          const SnackBar(backgroundColor: Color(0xFF10B981), content: Text('Đã xóa sạch toàn bộ kệ trong kho!')),
                        );
                      }
                    }
                  },
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(
                      value: 'clear_all',
                      child: Row(
                        children: [
                          Icon(Icons.delete_sweep_outlined, color: Color(0xFFEF4444), size: 18),
                          SizedBox(width: 8),
                          Text('Xóa toàn bộ kệ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleSection,
              const SizedBox(height: 12),
              actionButtons,
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: titleSection),
            const SizedBox(width: 16),
            actionButtons,
          ],
        );
      },
    );
  }

  Widget _buildTabButton({
    required InventoryViewTab tab,
    required IconData icon,
    required String title,
    required EyeCareColors c,
  }) {
    final isSelected = _activeTab == tab;
    return InkWell(
      onTap: () => setState(() => _activeTab = tab),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? const Color(0xFF2C251E) : c.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? const Color(0xFF2C251E) : c.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 2. KPI CARDS & CHÚ THÍCH MÃ MÀU TRẠNG THÁI KỆ
  // ===========================================================================
  Widget _buildKpiAndLegendBar({
    required EyeCareColors c,
    required int totalShelves,
    required int fullCount,
    required int almostFullCount,
    required int plentyCount,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final isUltraNarrow = w < 540;
        final isNarrow = w < 920;

        final cardTotal = _buildKpiCard(
          title: 'TỔNG SỐ KỆ',
          value: '$totalShelves Kệ',
          subtitle: 'Đang quản lý',
          icon: Icons.shelves,
          color: c.rfidCyan,
          c: c,
          isCompact: isUltraNarrow,
        );
        final cardFull = _buildKpiCard(
          title: 'KỆ ĐẦY (FULL)',
          value: '$fullCount Kệ',
          subtitle: '🔴 Cập nhật bởi PDA',
          icon: Icons.error_outline_rounded,
          color: const Color(0xFFEF4444),
          c: c,
          isCompact: isUltraNarrow,
        );
        final cardNearFull = _buildKpiCard(
          title: 'SẮP HẾT CHỖ',
          value: '$almostFullCount Kệ',
          subtitle: '🟡 Cập nhật bởi PDA',
          icon: Icons.warning_amber_rounded,
          color: const Color(0xFFF59E0B),
          c: c,
          isCompact: isUltraNarrow,
        );
        final cardPlenty = _buildKpiCard(
          title: 'CÒN TRỐNG NHIỀU',
          value: '$plentyCount Kệ',
          subtitle: '🟢 Vị trí sẵn sàng',
          icon: Icons.check_circle_outline_rounded,
          color: const Color(0xFF10B981),
          c: c,
          isCompact: isUltraNarrow,
        );

        Widget cardsSection;
        if (isUltraNarrow) {
          cardsSection = Column(
            children: [
              cardTotal,
              const SizedBox(height: 8),
              cardFull,
              const SizedBox(height: 8),
              cardNearFull,
              const SizedBox(height: 8),
              cardPlenty,
            ],
          );
        } else if (isNarrow) {
          cardsSection = Column(
            children: [
              Row(
                children: [
                  Expanded(child: cardTotal),
                  const SizedBox(width: 8),
                  Expanded(child: cardFull),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: cardNearFull),
                  const SizedBox(width: 8),
                  Expanded(child: cardPlenty),
                ],
              ),
            ],
          );
        } else {
          cardsSection = Row(
            children: [
              Expanded(child: cardTotal),
              const SizedBox(width: 12),
              Expanded(child: cardFull),
              const SizedBox(width: 12),
              Expanded(child: cardNearFull),
              const SizedBox(width: 12),
              Expanded(child: cardPlenty),
            ],
          );
        }

        return Column(
          children: [
            cardsSection,
            const SizedBox(height: 10),

            // Thanh Chú thích Màu Sắc Tiêu Chuẩn (Dùng Wrap chống overflow)
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: isUltraNarrow ? 10 : 16,
                vertical: isUltraNarrow ? 8 : 10,
              ),
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.palette_outlined, size: 14, color: c.textMuted),
                      const SizedBox(width: 6),
                      Text(
                        isUltraNarrow ? 'TRẠNG THÁI:' : 'TRẠNG THÁI (PDA CẬP NHẬT):',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: isUltraNarrow ? 10 : 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  _buildLegendPill(
                    color: const Color(0xFFEF4444),
                    label: isUltraNarrow ? 'Đỏ: Đầy' : 'Màu đỏ: Kệ đầy',
                    c: c,
                    isCompact: isUltraNarrow,
                  ),
                  _buildLegendPill(
                    color: const Color(0xFFF59E0B),
                    label: isUltraNarrow ? 'Vàng: Sắp hết' : 'Màu vàng: Kệ sắp hết chỗ',
                    c: c,
                    isCompact: isUltraNarrow,
                  ),
                  _buildLegendPill(
                    color: const Color(0xFF10B981),
                    label: isUltraNarrow ? 'Xanh: Trống' : 'Màu xanh: Kệ còn trống nhiều',
                    c: c,
                    isCompact: isUltraNarrow,
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required EyeCareColors c,
    bool isCompact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 10 : 16,
        vertical: isCompact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(isCompact ? 7 : 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: isCompact ? 18 : 22),
          ),
          SizedBox(width: isCompact ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: isCompact ? 9.5 : 10.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: isCompact ? 16 : 20,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: c.textMuted,
                    fontSize: isCompact ? 9 : 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendPill({
    required Color color,
    required String label,
    required EyeCareColors c,
    bool isCompact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isCompact ? 7 : 10, vertical: isCompact ? 3.5 : 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
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
              fontSize: isCompact ? 10 : 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. THANH BỘ LỌC VÀ TÌM KIẾM (Cuộn ngang an toàn)
  // ===========================================================================
  Widget _buildFilterToolbar(EyeCareColors c, List<Location> allLocations) {
    final zones = {'ALL', ...allLocations.map((l) => l.zone.trim()).where((z) => z.isNotEmpty)}.toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Tìm kiếm nhanh mã kệ
            SizedBox(
              width: 220,
              height: 36,
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                decoration: InputDecoration(
                  hintText: 'Tìm theo mã kệ, tầng, khu...',
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 11.5),
                  prefixIcon: Icon(Icons.search, size: 16, color: c.textMuted),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 14),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: c.bgCardElevated,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.border),
                  ),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.trim()),
              ),
            ),
            const SizedBox(width: 14),

            // Lọc theo Khu vực (Zone)
            Text('Khu vực:', style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedZoneFilter,
                  dropdownColor: c.bgCard,
                  style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                  items: zones.map((z) {
                    return DropdownMenuItem<String>(
                      value: z,
                      child: Text(z == 'ALL' ? 'Tất cả các khu' : z),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedZoneFilter = val);
                  },
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Lọc theo Trạng thái (Đầy / Sắp đầy / Trống nhiều)
            Text('Trạng thái:', style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            _buildStatusFilterChip('Tất cả', 'ALL', c.textPrimary, c),
            const SizedBox(width: 6),
            _buildStatusFilterChip('🔴 Kệ đầy', 'FULL', const Color(0xFFEF4444), c),
            const SizedBox(width: 6),
            _buildStatusFilterChip('🟡 Sắp hết chỗ', 'NEAR_FULL', const Color(0xFFF59E0B), c),
            const SizedBox(width: 6),
            _buildStatusFilterChip('🟢 Còn trống nhiều', 'PLENTY', const Color(0xFF10B981), c),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusFilterChip(String label, String value, Color color, EyeCareColors c) {
    final isSelected = _selectedStatusFilter == value;
    return InkWell(
      onTap: () => setState(() => _selectedStatusFilter = value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.18) : c.bgCardElevated,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : c.border,
            width: isSelected ? 1.4 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? color : c.textSecondary,
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 4. THẺ TRẠNG THÁI TỪNG KỆ HÀNG (SHELF CARD - TỰ ĐỘNG CO GIÃN THEO KÍCH THƯỚC)
  // ===========================================================================
  Widget _buildShelfCard(Location loc, EyeCareColors c) {
    final status = _getShelfStatus(loc);
    final currentCount = _getShelfCurrentCount(loc);

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
          onTap: () => _showShelfDetailDialog(loc, status, currentCount, itemsOnShelf, c),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: EdgeInsets.all(isCompact ? 10 : 13),
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: status.color.withValues(alpha: 0.6),
                width: 1.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: status.color.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Dòng 1: Icon + Tên kệ + Badge trạng thái màu (Tự động co giãn theo chiều rộng thẻ)
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
                              color: c.textPrimary,
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
                    const SizedBox(width: 6),
                    Text(
                      'Chi tiết →',
                      style: TextStyle(color: c.rfidCyan, fontSize: isCompact ? 10.5 : 11, fontWeight: FontWeight.bold),
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

  Widget _buildEmptyRackView(EyeCareColors c) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 56, color: c.textMuted),
          const SizedBox(height: 12),
          Text(
            'Không tìm thấy kệ hàng nào phù hợp với bộ lọc.',
            style: TextStyle(color: c.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            style: OutlinedButton.styleFrom(side: BorderSide(color: c.border)),
            onPressed: () {
              setState(() {
                _selectedZoneFilter = 'ALL';
                _selectedStatusFilter = 'ALL';
                _searchQuery = '';
                _searchController.clear();
              });
            },
            child: Text('Đặt lại bộ lọc', style: TextStyle(color: c.textPrimary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 5. MODAL XEM CHI TIẾT KỆ & DANH SÁCH MẶT HÀNG TRÊN KỆ
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
                                  decoration: BoxDecoration(color: c.rfidCyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                                  child: Icon(Icons.nfc, color: c.rfidCyan, size: 16),
                                ),
                                title: Text(item.productName.isNotEmpty ? item.productName : item.sku, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                                subtitle: Text(
                                  itemPallet != null
                                      ? 'EPC: ${item.epc}  •  📦 Pallet: ${itemPallet.palletCode}'
                                      : 'EPC: ${item.epc}',
                                  style: TextStyle(color: c.textMuted, fontSize: 10.5, fontFamily: 'Courier'),
                                ),
                                trailing: Text(item.status.label, style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton.icon(
                style: TextButton.styleFrom(foregroundColor: const Color(0xFFEF4444)),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('XÓA KỆ', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  final confirm = await showDialog<bool>(
                    context: ctx,
                    builder: (confirmCtx) => AlertDialog(
                      backgroundColor: c.bgCard,
                      title: const Text('Xác nhận xóa kệ', style: TextStyle(fontWeight: FontWeight.bold)),
                      content: Text(
                        'Bạn có chắc chắn muốn xóa kệ ${loc.displayName} (${loc.locationCode}) khỏi hệ thống không?',
                        style: TextStyle(color: c.textPrimary),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(confirmCtx, false),
                          child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                          onPressed: () => Navigator.pop(confirmCtx, true),
                          child: const Text('XÓA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _repo.deleteLocation(loc.locationId);
                    if (ctx.mounted) Navigator.pop(ctx);
                    if (mounted) setState(() {});
                    messenger.showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF10B981),
                        content: Text('Đã xóa kệ ${loc.displayName} thành công!'),
                      ),
                    );
                  }
                },
              ),
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('ĐÓNG', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.rfidCyan,
                  foregroundColor: const Color(0xFF2C251E),
                ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('SỬA KỆ', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showEditShelfDialog(loc, c);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  // ===========================================================================
  // 5B. SỬA THÔNG TIN KỆ
  // ===========================================================================
  void _showEditShelfDialog(Location loc, EyeCareColors c) {
    final messenger = ScaffoldMessenger.of(context);
    final codeCtrl = TextEditingController(text: loc.locationCode);
    final shelfCtrl = TextEditingController(text: loc.shelf);
    final zoneCtrl = TextEditingController(text: loc.zone);
    final levelCtrl = TextEditingController(text: loc.level);
    final capCtrl = TextEditingController(text: loc.maxPalletCapacity.toString());
    String selectedStatus = loc.status;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: c.bgCard,
          title: Text(
            'Sửa Thông Tin Kệ: ${loc.displayName}',
            style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: codeCtrl,
                  decoration: InputDecoration(
                    labelText: 'Mã Vị Trí (Location Code)',
                    hintText: 'Ví dụ: LOC-A3-01',
                    labelStyle: TextStyle(color: c.textSecondary),
                  ),
                  style: TextStyle(color: c.textPrimary),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: shelfCtrl,
                  decoration: InputDecoration(
                    labelText: 'Tên Kệ (Shelf)',
                    hintText: 'Ví dụ: Kệ A3',
                    labelStyle: TextStyle(color: c.textSecondary),
                  ),
                  style: TextStyle(color: c.textPrimary),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: zoneCtrl,
                  decoration: InputDecoration(
                    labelText: 'Khu Vực (Zone)',
                    hintText: 'Ví dụ: Khu A',
                    labelStyle: TextStyle(color: c.textSecondary),
                  ),
                  style: TextStyle(color: c.textPrimary),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: levelCtrl,
                  decoration: InputDecoration(
                    labelText: 'Tầng (Level)',
                    hintText: 'Ví dụ: Tầng 1',
                    labelStyle: TextStyle(color: c.textSecondary),
                  ),
                  style: TextStyle(color: c.textPrimary),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: capCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Sức chứa tối đa (Pallet)',
                    labelStyle: TextStyle(color: c.textSecondary),
                  ),
                  style: TextStyle(color: c.textPrimary),
                ),
                const SizedBox(height: 14),
                Text('Trạng thái kệ:', style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('CÒN TRỐNG'),
                      selected: selectedStatus == 'AVAILABLE',
                      selectedColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: selectedStatus == 'AVAILABLE' ? const Color(0xFF10B981) : c.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      onSelected: (_) => setDialogState(() => selectedStatus = 'AVAILABLE'),
                    ),
                    ChoiceChip(
                      label: const Text('SẮP HẾT'),
                      selected: selectedStatus == 'NEAR_FULL',
                      selectedColor: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: selectedStatus == 'NEAR_FULL' ? const Color(0xFFF59E0B) : c.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      onSelected: (_) => setDialogState(() => selectedStatus = 'NEAR_FULL'),
                    ),
                    ChoiceChip(
                      label: const Text('ĐẦY'),
                      selected: selectedStatus == 'FULL',
                      selectedColor: const Color(0xFFEF4444).withValues(alpha: 0.2),
                      labelStyle: TextStyle(
                        color: selectedStatus == 'FULL' ? const Color(0xFFEF4444) : c.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                      onSelected: (_) => setDialogState(() => selectedStatus = 'FULL'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
              onPressed: () async {
                final code = codeCtrl.text.trim();
                final shelf = shelfCtrl.text.trim();
                if (code.isEmpty || shelf.isEmpty) return;

                final cap = int.tryParse(capCtrl.text.trim()) ?? loc.maxPalletCapacity;
                await _repo.updateLocationDetails(
                  locationId: loc.locationId,
                  locationCode: code,
                  zone: zoneCtrl.text.trim(),
                  shelf: shelf,
                  level: levelCtrl.text.trim(),
                  maxCapacity: cap,
                  status: selectedStatus,
                  aisleSide: loc.aisleSide,
                  sortOrder: loc.sortOrder,
                );

                if (ctx.mounted) Navigator.pop(ctx);
                if (mounted) setState(() {});
                messenger.showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF10B981),
                    content: Text('Đã cập nhật thông tin kệ $shelf thành công!'),
                  ),
                );
              },
              child: const Text('CẬP NHẬT', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
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
              color: isSelected ? const Color(0xFF2C251E) : color,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // 6. THÊM KỆ MỚI
  // ===========================================================================
  void _showAddShelfDialog(EyeCareColors c) {
    final messenger = ScaffoldMessenger.of(context);
    final codeCtrl = TextEditingController();
    final shelfCtrl = TextEditingController();
    final zoneCtrl = TextEditingController(text: 'Khu A');
    final levelCtrl = TextEditingController(text: 'Tầng 1');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        title: Text('Thêm Kệ Hàng Mới', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeCtrl,
                decoration: InputDecoration(
                  labelText: 'Mã Vị Trí (Location Code)',
                  hintText: 'Ví dụ: LOC-A3-01',
                  labelStyle: TextStyle(color: c.textSecondary),
                ),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: shelfCtrl,
                decoration: InputDecoration(
                  labelText: 'Tên Kệ (Shelf)',
                  hintText: 'Ví dụ: Kệ A3',
                  labelStyle: TextStyle(color: c.textSecondary),
                ),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: zoneCtrl,
                decoration: InputDecoration(
                  labelText: 'Khu Vực (Zone)',
                  hintText: 'Ví dụ: Khu A',
                  labelStyle: TextStyle(color: c.textSecondary),
                ),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: levelCtrl,
                decoration: InputDecoration(
                  labelText: 'Tầng (Level)',
                  hintText: 'Ví dụ: Tầng 1',
                  labelStyle: TextStyle(color: c.textSecondary),
                ),
                style: TextStyle(color: c.textPrimary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
            onPressed: () async {
              final code = codeCtrl.text.trim();
              final shelf = shelfCtrl.text.trim();
              if (code.isEmpty || shelf.isEmpty) return;

              final newLoc = Location(
                locationId: code,
                locationCode: code,
                zone: zoneCtrl.text.trim(),
                shelf: shelf,
                level: levelCtrl.text.trim(),
                maxPalletCapacity: 1,
                currentPallets: 0,
                status: 'AVAILABLE',
              );

              await _repo.addLocation(newLoc);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) setState(() {});
              messenger.showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF10B981),
                  content: Text('Đã thêm kệ ${newLoc.displayName} thành công!'),
                ),
              );
            },
            child: const Text('LƯU KỆ', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 7. DANH SÁCH & CHI TIẾT PHIÊN KIỂM KÊ KHO (AUDIT SESSIONS)
  // ===========================================================================
  Widget _buildSessionListView(EyeCareColors c) {
    final sessions = _repo.inventorySessions;

    return Container(
      color: c.bgDeep,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INVENTORY MANAGEMENT',
                      style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Danh Sách Phiên Kiểm Kê Kho',
                      style: TextStyle(color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border),
                    ),
                    child: Row(
                      children: [
                        _buildTabButton(
                          tab: InventoryViewTab.rackGrid,
                          icon: Icons.grid_view_rounded,
                          title: 'Sơ Đồ Kệ (Lưới)',
                          c: c,
                        ),
                        const SizedBox(width: 4),
                        _buildTabButton(
                          tab: InventoryViewTab.auditSessions,
                          icon: Icons.checklist_rounded,
                          title: 'Lịch Sử Kiểm Kê',
                          c: c,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('LÀM MỚI'),
                    onPressed: () => _repo.refreshFromDatabase(),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    icon: const Icon(Icons.file_download, color: Color(0xFF2C251E), size: 18),
                    label: const Text('BÁO CÁO EXCEL', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(backgroundColor: Color(0xFF10B981), content: Text('Đã xuất báo cáo kiểm kê ra file Excel')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.fact_check_outlined, size: 64, color: c.textMuted),
                          const SizedBox(height: 14),
                          Text('Chưa có phiên kiểm kê nào trong CSDL.', style: TextStyle(color: c.textSecondary, fontSize: 14)),
                          const SizedBox(height: 8),
                          Text('Hãy mở máy cầm tay PDA và bấm "Inventory" để tiến hành quét kiểm kê kho.', style: TextStyle(color: c.textMuted, fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: sessions.length,
                      separatorBuilder: (_, index) => Divider(color: c.border, height: 1),
                      itemBuilder: (context, index) {
                        final s = sessions[index];
                        final isCompleted = s.isCompleted;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: c.rfidCyan.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.checklist, color: c.rfidCyan, size: 20),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.sessionCode, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text('Time: ${s.startedAt.toString().substring(0, 16)}', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text('Khu vực: ${s.zone}', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text('Đã quét: ${s.actualScannedCount} chip (Hệ thống: ${s.knownInDbCount})', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isCompleted ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isCompleted ? 'Completed' : 'Scanning',
                                  style: TextStyle(
                                    color: isCompleted ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 20),
                              IconButton(
                                icon: Icon(Icons.visibility, color: c.rfidCyan, size: 20),
                                onPressed: () => setState(() => _selectedSession = s),
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

  Widget _buildSessionDetailView(InventorySession s, EyeCareColors c) {
    return Container(
      color: c.bgDeep,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: c.textPrimary),
                    onPressed: () => setState(() => _selectedSession = null),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Chi tiết kiểm kê: ${s.sessionCode}',
                    style: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
                icon: const Icon(Icons.file_download, color: Color(0xFF2C251E), size: 18),
                label: const Text('XUẤT EXCEL', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(backgroundColor: Color(0xFF10B981), content: Text('Đã xuất dữ liệu chi tiết kiểm kê ra Excel')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column: Info block
                SizedBox(
                  width: 320,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailItem('Mã kiểm kê', s.sessionCode, c),
                        const SizedBox(height: 12),
                        _buildDetailItem('Ngày kiểm kê', '${s.startedAt.year}-${s.startedAt.month.toString().padLeft(2, '0')}-${s.startedAt.day.toString().padLeft(2, '0')}', c),
                        const SizedBox(height: 12),
                        _buildDetailItem('Loại kiểm kê', 'Toàn bộ sản phẩm', c),
                        const SizedBox(height: 12),
                        _buildDetailItem('Kho / Khu vực', s.zone, c),
                        const SizedBox(height: 12),
                        _buildDetailItem('Trạng thái', s.isCompleted ? 'Completed' : 'Scanning', c),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),

                // Right column: Table
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Table(
                      border: TableBorder.all(color: c.border),
                      columnWidths: const {
                        0: FlexColumnWidth(1),
                        1: FlexColumnWidth(3),
                        2: FlexColumnWidth(3),
                        3: FlexColumnWidth(1.5),
                        4: FlexColumnWidth(1.5),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: c.bgCardElevated),
                          children: [
                            Padding(padding: const EdgeInsets.all(10), child: Text('#', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                            Padding(padding: const EdgeInsets.all(10), child: Text('Mã EPC', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                            Padding(padding: const EdgeInsets.all(10), child: Text('Tên sản phẩm', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                            Padding(padding: const EdgeInsets.all(10), child: Text('Trạng thái', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                            Padding(padding: const EdgeInsets.all(10), child: Text('Thời gian', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                          ],
                        ),
                        if (s.results.isEmpty)
                          TableRow(
                            children: [
                              Padding(padding: const EdgeInsets.all(12), child: Text('-', style: TextStyle(color: c.textMuted, fontSize: 12))),
                              Padding(padding: const EdgeInsets.all(12), child: Text('Chưa có dữ liệu quét', style: TextStyle(color: c.textSecondary, fontSize: 12))),
                              Padding(padding: const EdgeInsets.all(12), child: Text('-', style: TextStyle(color: c.textMuted, fontSize: 12))),
                              Padding(padding: const EdgeInsets.all(12), child: Text('-', style: TextStyle(color: c.textMuted, fontSize: 12))),
                              Padding(padding: const EdgeInsets.all(12), child: Text('-', style: TextStyle(color: c.textMuted, fontSize: 12))),
                            ],
                          )
                        else
                          ...s.results.asMap().entries.map((entry) {
                            final idx = entry.key + 1;
                            final r = entry.value;
                            final prodTitle = (r.productName != null && r.productName!.isNotEmpty)
                                ? r.productName!
                                : ((r.sku != null && r.sku!.isNotEmpty) ? r.sku! : 'Chưa phân loại');

                            return TableRow(
                              children: [
                                Padding(padding: const EdgeInsets.all(10), child: Text('$idx', style: TextStyle(color: c.textSecondary, fontSize: 12))),
                                Padding(padding: const EdgeInsets.all(10), child: Text(r.epc, style: TextStyle(color: c.textSecondary, fontFamily: 'Courier', fontSize: 11))),
                                Padding(padding: const EdgeInsets.all(10), child: Text(prodTitle, style: TextStyle(color: c.textPrimary, fontSize: 12))),
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                    r.resultType.label,
                                    style: TextStyle(
                                      color: Color(r.resultType.colorValue),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                    '${r.readAt.hour.toString().padLeft(2, '0')}:${r.readAt.minute.toString().padLeft(2, '0')}:${r.readAt.second.toString().padLeft(2, '0')}',
                                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                                  ),
                                ),
                              ],
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, EyeCareColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}
