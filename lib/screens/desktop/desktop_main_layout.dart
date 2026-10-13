import 'package:flutter/material.dart';
import 'desktop_goods_receive_view.dart';
import 'desktop_goods_delivery_view.dart';
import 'desktop_product_management_view.dart';
import 'desktop_lookup_view.dart';
import 'desktop_location_management_view.dart';
import 'desktop_warehouse_management_view.dart';
import 'desktop_inventory_view.dart';
import 'desktop_report_view.dart';
import 'desktop_stock_reconciliation_view.dart';
import 'desktop_uhf_studio_view.dart';
import 'desktop_user_management_view.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/uhf_service.dart';
import '../../services/auth_service.dart';
import '../../services/report_export_service.dart';
import '../../theme/eye_care_theme.dart';

class DesktopMainLayout extends StatefulWidget {
  const DesktopMainLayout({super.key});

  @override
  State<DesktopMainLayout> createState() => _DesktopMainLayoutState();
}

class _DesktopMainLayoutState extends State<DesktopMainLayout> {
  int _selectedMenuIndex = 0;
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final AuthService _auth = AuthService();

  List<Widget> _buildViews() => [
    DesktopGoodsReceiveView(key: const ValueKey('desktop_goods_receive'), isActive: _selectedMenuIndex == 0), // 0: Nhập Kho
    DesktopGoodsDeliveryView(key: const ValueKey('desktop_goods_delivery'), isActive: _selectedMenuIndex == 1), // 1: Xuất Kho
    DesktopProductManagementView(
      key: const ValueKey('desktop_product_management'),
      onNavigateToInbound: () => setState(() => _selectedMenuIndex = 0),
    ), // 2: Danh Mục Sản Phẩm
    const DesktopLookupView(key: ValueKey('desktop_lookup')), // 3: Tìm Kiếm Hàng Hóa
    const DesktopLocationManagementView(key: ValueKey('desktop_location_management')), // 4: Sơ Đồ Kệ Kho
    const DesktopWarehouseManagementView(key: ValueKey('desktop_pallet_management'), initialTab: 0, showTabBar: false), // 5: Quản Lý Pallet
    const DesktopInventoryView(key: ValueKey('desktop_inventory')), // 6: Kiểm Kê Kho
    const DesktopReportView(key: ValueKey('desktop_report_inventory'), initialBusinessType: ReportType.inventory), // 7: Báo Cáo Tồn Kho
    const DesktopReportView(key: ValueKey('desktop_report_inbound'), initialBusinessType: ReportType.inbound), // 8: Báo Cáo Nhập Kho
    const DesktopReportView(key: ValueKey('desktop_report_outbound'), initialBusinessType: ReportType.outbound), // 9: Báo Cáo Xuất Kho
    const DesktopStockReconciliationView(key: ValueKey('desktop_stock_reconciliation')), // 10: Đối Soát Tồn Kho
    const DesktopReportView(key: ValueKey('desktop_report_history'), initialBusinessType: ReportType.transactionLog), // 11: Lịch Sử Nhập Xuất
    const DesktopUhfStudioView(key: ValueKey('desktop_uhf_studio')), // 12: Cài Đặt Đầu Đọc RFID
    const DesktopUserManagementView(key: ValueKey('desktop_user_management')), // 13: Quản Lý Tài Khoản
  ];

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onThemeUpdate);
    _auth.addListener(_onThemeUpdate);
  }

  void _onThemeUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _eyeCare.removeListener(_onThemeUpdate);
    _auth.removeListener(_onThemeUpdate);
    super.dispose();
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final user = _auth.currentUser;
    final c = _eyeCare.colors;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        title: Text('Xác nhận đăng xuất?', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
        content: Text('Bạn có chắc chắn muốn đăng xuất khỏi tài khoản "${user?.fullName ?? user?.username ?? "người dùng"}"?', style: TextStyle(color: c.textSecondary)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('HỦY', style: TextStyle(color: c.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ĐĂNG XUẤT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _auth.logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final user = _auth.currentUser;
    final perm = user?.rolePermission;
    final isTech = perm?.isTechnician ?? false;
    final canManageUsers = perm?.canManageUsers ?? false;
    final canIn = perm?.canInbound ?? true;
    final canAud = perm?.canAudit ?? true;

    // Tự động chuyển sang màn hình được phép nếu màn hình hiện tại bị ẩn
    int effectiveIndex = _selectedMenuIndex;
    if (effectiveIndex == 0 && !canIn) effectiveIndex = 1;
    if (effectiveIndex == 6 && !canAud) effectiveIndex = 1;
    if (effectiveIndex == 12 && !isTech) effectiveIndex = canManageUsers ? 13 : 1;
    if (effectiveIndex == 13 && !canManageUsers) effectiveIndex = isTech ? 12 : 1;

    return Scaffold(
      backgroundColor: c.bgDeep,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompactSidebar = constraints.maxWidth < 1050;

          return Row(
            children: [
              // Sidebar: Tự động co giãn thanh điều hướng theo kích thước cửa sổ
              _buildSidebar(c, isCompact: isCompactSidebar),

              // Main View Content
              Expanded(
                child: IndexedStack(
                  index: effectiveIndex,
                  children: _buildViews(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSidebar(EyeCareColors c, {bool isCompact = false}) {
    final user = _auth.currentUser;
    final perm = user?.rolePermission;
    final isTech = perm?.isTechnician ?? false;
    final canManageUsers = perm?.canManageUsers ?? false;
    final canIn = perm?.canInbound ?? true;
    final canAud = perm?.canAudit ?? true;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: isCompact ? 68 : 260,
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border(right: BorderSide(color: c.border, width: 1)),
      ),
      child: Column(
        children: [
          // Company Brand Header
          if (isCompact)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border, width: 1)),
              ),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.rfidCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
                ),
                child: Icon(Icons.warehouse_rounded, color: c.rfidCyan, size: 22),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border, width: 1)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.rfidCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.warehouse_rounded, color: c.rfidCyan, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'RFIDwarehouse',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: 0.5,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),

          // Menu Items: Thiết kế 1 cấp phẳng, trực quan, tối giản
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: 8, horizontal: isCompact ? 6 : 8),
              children: [
                if (canIn)
                  _buildMenuItem(
                    0,
                    Icons.input_rounded,
                    'Nhập Kho',
                    c,
                    isCompact: isCompact,
                  ),
                _buildMenuItem(
                  1,
                  Icons.output_rounded,
                  'Xuất Kho',
                  c,
                  isCompact: isCompact,
                ),
                _buildMenuItem(
                  2,
                  Icons.category_rounded,
                  'Danh Mục Sản Phẩm',
                  c,
                  isCompact: isCompact,
                ),
                _buildMenuItem(
                  3,
                  Icons.search_rounded,
                  'Tìm Kiếm Hàng Hóa',
                  c,
                  isCompact: isCompact,
                ),
                _buildMenuItem(
                  4,
                  Icons.grid_view_rounded,
                  'Sơ Đồ Kệ Kho',
                  c,
                  isCompact: isCompact,
                ),
                _buildMenuItem(
                  5,
                  Icons.layers_rounded,
                  'Quản Lý Pallet',
                  c,
                  isCompact: isCompact,
                ),
                if (canAud)
                  _buildMenuItem(
                    6,
                    Icons.checklist_rounded,
                    'Kiểm Kê Kho',
                    c,
                    isCompact: isCompact,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                  child: Divider(color: c.borderLight, height: 1),
                ),
                _buildMenuItem(
                  7,
                  Icons.inventory_2_rounded,
                  'Báo Cáo Tồn Kho',
                  c,
                  isCompact: isCompact,
                ),
                _buildMenuItem(
                  8,
                  Icons.move_to_inbox_rounded,
                  'Báo Cáo Nhập Kho',
                  c,
                  isCompact: isCompact,
                ),
                _buildMenuItem(
                  9,
                  Icons.outbox_rounded,
                  'Báo Cáo Xuất Kho',
                  c,
                  isCompact: isCompact,
                ),
                _buildMenuItem(
                  10,
                  Icons.balance_rounded,
                  'Đối Soát Tồn Kho',
                  c,
                  isCompact: isCompact,
                ),
                _buildMenuItem(
                  11,
                  Icons.history_rounded,
                  'Lịch Sử Nhập Xuất',
                  c,
                  isCompact: isCompact,
                ),
                if (isTech) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                    child: Divider(color: c.borderLight, height: 1),
                  ),
                  _buildMenuItem(
                    12,
                    Icons.radar,
                    'Cài Đặt',
                    c,
                    badge: 'KỸ THUẬT',
                    isCompact: isCompact,
                  ),
                ],
                if (canManageUsers) ...[
                  if (!isTech)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                      child: Divider(color: c.borderLight, height: 1),
                    ),
                  _buildMenuItem(
                    13,
                    Icons.manage_accounts_rounded,
                    'Quản Lý Tài Khoản',
                    c,
                    badge: 'ADMIN',
                    isCompact: isCompact,
                  ),
                ],
              ],
            ),
          ),

          // User Profile Footer
          Builder(
            builder: (context) {
              final user = _auth.currentUser;
              final roleLabel = user?.rolePermission.name ?? 'Thủ Kho';

              if (isCompact) {
                return Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c.bgCardElevated,
                    border: Border(top: BorderSide(color: c.border, width: 1)),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 20),
                    tooltip: 'Đăng xuất (@${user?.username ?? ""})',
                    onPressed: () => _confirmLogout(context),
                  ),
                );
              }

              return Container(
                margin: const EdgeInsets.all(10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border.withValues(alpha: 0.7)),
                ),
                child: Row(
                  children: [
                    Stack(
                      children: [
                        CircleAvatar(
                          backgroundColor: c.rfidCyan.withValues(alpha: 0.18),
                          radius: 16,
                          child: Text(
                            user?.fullName.isNotEmpty == true ? user!.fullName.substring(0, 1).toUpperCase() : 'U',
                            style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981),
                              shape: BoxShape.circle,
                              border: Border.all(color: c.bgCardElevated, width: 1.2),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.fullName ?? 'Người Dùng WMS',
                            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            roleLabel,
                            style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 18),
                      tooltip: 'Đăng xuất',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () => _confirmLogout(context),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(
    int index,
    IconData icon,
    String title,
    EyeCareColors c, {
    Color? accentColor,
    bool isLocked = false,
    bool isCompact = false,
    String? badge,
    String? lockMessage,
  }) {
    final isSelected = _selectedMenuIndex == index;

    return _SidebarItem(
      index: index,
      icon: icon,
      title: title,
      accentColor: accentColor,
      c: c,
      isSelected: isSelected,
      isLocked: isLocked,
      isCompact: isCompact,
      badge: badge,
      onTap: () {
        if (isLocked) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFEF4444),
              content: Text(lockMessage ?? 'Tài khoản của bạn không có quyền truy cập chức năng này.'),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        if (_selectedMenuIndex != index) {
          DesktopUhfTcpService().stopInventory();
          UhfService().stopInventory();
          setState(() => _selectedMenuIndex = index);
        }
      },
    );
  }
}

class _SidebarItem extends StatefulWidget {
  final int index;
  final IconData icon;
  final String title;
  final Color? accentColor;
  final EyeCareColors c;
  final bool isSelected;
  final bool isLocked;
  final bool isCompact;
  final String? badge;
  final VoidCallback onTap;

  const _SidebarItem({
    required this.index,
    required this.icon,
    required this.title,
    this.accentColor,
    required this.c,
    required this.isSelected,
    this.isLocked = false,
    this.isCompact = false,
    this.badge,
    required this.onTap,
  });

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final isSelected = widget.isSelected;
    final isLocked = widget.isLocked;
    final activeColor = widget.accentColor ?? c.rfidCyan;

    if (widget.isCompact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Tooltip(
          message: widget.title,
          waitDuration: const Duration(milliseconds: 250),
          child: MouseRegion(
            onEnter: (_) => setState(() => _isHovered = true),
            onExit: (_) => setState(() => _isHovered = false),
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? activeColor.withValues(alpha: 0.18)
                      : (_isHovered ? c.bgCardElevated : Colors.transparent),
                  borderRadius: BorderRadius.circular(8),
                  border: isSelected
                      ? Border.all(color: activeColor.withValues(alpha: 0.8), width: 1.2)
                      : (_isHovered
                          ? Border.all(color: c.border.withValues(alpha: 0.6), width: 1)
                          : Border.all(color: Colors.transparent)),
                ),
                child: Icon(
                  widget.icon,
                  color: isSelected
                      ? activeColor
                      : (isLocked ? c.textMuted : (_isHovered ? activeColor : c.textSecondary)),
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8.5),
            decoration: BoxDecoration(
              color: isSelected
                  ? activeColor.withValues(alpha: 0.14)
                  : (_isHovered ? c.bgCardElevated.withValues(alpha: 0.7) : Colors.transparent),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected
                    ? activeColor.withValues(alpha: 0.45)
                    : (_isHovered ? c.border.withValues(alpha: 0.5) : Colors.transparent),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: 3.5,
                  height: isSelected ? 22 : 0,
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: isSelected ? 8 : 4),
                // Icon pill
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isSelected ? activeColor.withValues(alpha: 0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    isLocked ? Icons.lock_outline_rounded : widget.icon,
                    color: isSelected
                        ? activeColor
                        : (isLocked ? c.textMuted : (_isHovered ? c.textPrimary : c.textSecondary)),
                    size: 19,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    widget.title,
                    style: TextStyle(
                      color: isSelected
                          ? activeColor
                          : (isLocked ? c.textMuted : c.textPrimary),
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (widget.badge != null)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isLocked
                          ? const Color(0xFFEF4444).withValues(alpha: 0.12)
                          : activeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isLocked
                            ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                            : activeColor.withValues(alpha: 0.3),
                        width: 0.8,
                      ),
                    ),
                    child: Text(
                      widget.badge!,
                      style: TextStyle(
                        color: isLocked ? const Color(0xFFEF4444) : activeColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


