import 'package:flutter/material.dart';
import 'desktop_goods_receive_view.dart';
import 'desktop_goods_delivery_view.dart';
import 'desktop_inventory_view.dart';
import 'desktop_lookup_view.dart';
import 'desktop_uhf_studio_view.dart';
import 'desktop_user_management_view.dart';
import 'desktop_warehouse_management_view.dart';
import 'desktop_connection_config_view.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/uhf_service.dart';
import '../../services/auth_service.dart';
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
    DesktopGoodsReceiveView(key: const ValueKey('desktop_goods_receive'), isActive: _selectedMenuIndex == 0), // 0: Goods Receive
    DesktopGoodsDeliveryView(key: const ValueKey('desktop_goods_delivery'), isActive: _selectedMenuIndex == 1), // 1: Goods Delivery
    const DesktopWarehouseManagementView(key: ValueKey('desktop_warehouse_management')), // 2: Warehouse Management (Pallet, In/Out History & Audit Log)
    const DesktopInventoryView(key: ValueKey('desktop_inventory')), // 3: Inventory
    const DesktopLookupView(key: ValueKey('desktop_lookup')), // 4: Lookup
    const DesktopUhfStudioView(key: ValueKey('desktop_uhf_studio')), // 5: UHF Reader Studio (Hopeland SDK & Fixed Reader)
    const DesktopUserManagementView(key: ValueKey('desktop_user_management')), // 6: User Management (Admin Account Provisioning)
    const DesktopConnectionConfigView(key: ValueKey('desktop_connection_config')), // 7: Hardware Connection Configuration
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
    if (effectiveIndex == 3 && !canAud) effectiveIndex = 1;
    if (effectiveIndex == 5 && !isTech) effectiveIndex = canManageUsers ? 6 : 1;
    if (effectiveIndex == 6 && !canManageUsers) effectiveIndex = isTech ? 5 : 1;
    if (effectiveIndex == 7 && !isTech) effectiveIndex = canManageUsers ? 6 : 1;

    return Scaffold(
      backgroundColor: c.bgDeep,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isCompactSidebar = constraints.maxWidth < 1050;

          return Row(
            children: [
              // Sidebar: Tự động co giãn thanh điều hướng theo kích thước cửa sổ
              _buildSidebar(c, isCompact: isCompactSidebar),

              // Main View Content: Tự động co giãn toàn bộ diện tích còn lại, sát trên cùng
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
      width: isCompact ? 68 : 250,
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
                  color: c.rfidCyan.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.warehouse, color: c.rfidCyan, size: 24),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: c.border, width: 1)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.rfidCyan.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.warehouse, color: c.rfidCyan, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'RFIDwarehouse',
                          style: TextStyle(
                            color: c.rfidCyan,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            letterSpacing: 1.1,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Hệ Thống Quản Lý Kho WMS',
                          style: TextStyle(color: c.textSecondary, fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(vertical: 12, horizontal: isCompact ? 6 : 12),
              children: [
                if (!isCompact)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Text(
                      'QUẢN LÝ KHO HÀNG',
                      style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                if (canIn)
                  _buildMenuItem(
                    0,
                    Icons.input,
                    'Nhập Kho',
                    'Nhập hàng vào kho',
                    c,
                    isCompact: isCompact,
                  ),
                _buildMenuItem(1, Icons.output, 'Xuất Kho', 'Xuất hàng xuất bán', c, isCompact: isCompact),
                _buildMenuItem(
                  2,
                  Icons.warehouse_rounded,
                  'Quản Lý Kho',
                  'Pallet & lịch sử nhập xuất',
                  c,
                  isCompact: isCompact,
                ),
                if (canAud)
                  _buildMenuItem(
                    3,
                    Icons.inventory_2,
                    'Kiểm Kê Kho',
                    'Kiểm đếm & quét RFID',
                    c,
                    isCompact: isCompact,
                  ),
                _buildMenuItem(4, Icons.search, 'Tra Cứu Serial & Kiện', 'Tra cứu mã chip RFID', c, isCompact: isCompact),
                if (isTech) ...[
                  const SizedBox(height: 8),
                  if (!isCompact)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        'HỆ THỐNG & ĐẦU ĐỌC',
                        style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ),
                  _buildMenuItem(
                    5,
                    Icons.radar,
                    'Đầu Đọc UHF (Studio)',
                    'Hopeland SDK 4.42 & Chỉnh thông số máy',
                    c,
                    badge: 'KỸ THUẬT',
                    isCompact: isCompact,
                  ),
                  _buildMenuItem(
                    7,
                    Icons.settings_input_antenna_rounded,
                    'Cấu Hình Kết Nối',
                    'IP LAN, COM & tự kết nối',
                    c,
                    badge: 'KẾT NỐI',
                    isCompact: isCompact,
                  ),
                ],
                if (canManageUsers) ...[
                  const SizedBox(height: 8),
                  if (!isCompact)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      child: Text(
                        'QUẢN TRỊ HỆ THỐNG',
                        style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                      ),
                    ),
                  _buildMenuItem(
                    6,
                    Icons.manage_accounts_rounded,
                    'Cấp & Quản Lý Tài Khoản',
                    'Cấp phát, phân quyền nhân viên',
                    c,
                    badge: 'ADMIN',
                    isCompact: isCompact,
                  ),
                ],
              ],
            ),
          ),

          // User Profile Footer (Tự động thích ứng compact)
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
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  border: Border(top: BorderSide(color: c.border, width: 1)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: c.rfidCyan.withValues(alpha: 0.2),
                      radius: 17,
                      child: Text(
                        user?.fullName.isNotEmpty == true ? user!.fullName.substring(0, 1).toUpperCase() : 'U',
                        style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user?.fullName ?? 'Người Dùng WMS',
                            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12.5),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '@${user?.username ?? "user"} • $roleLabel',
                            style: TextStyle(color: c.rfidCyan, fontSize: 10.5, fontWeight: FontWeight.w600),
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
    String subTitle,
    EyeCareColors c, {
    bool isLocked = false,
    bool isCompact = false,
    String? badge,
    String? lockMessage,
  }) {
    final isSelected = _selectedMenuIndex == index;

    if (isCompact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Tooltip(
          message: title,
          waitDuration: const Duration(milliseconds: 300),
          child: Material(
            color: isSelected ? c.rfidCyan.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                if (isLocked) {
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
              child: Container(
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected ? Border.all(color: c.rfidCyan, width: 1.5) : null,
                ),
                child: Icon(
                  icon,
                  color: isSelected ? c.rfidCyan : (isLocked ? c.textMuted : c.textSecondary),
                  size: 22,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? c.rfidCyan.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            if (isLocked) {
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
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: c.rfidCyan.withValues(alpha: 0.5)) : null,
            ),
            child: Row(
              children: [
                Icon(
                  isLocked ? Icons.lock_rounded : icon,
                  color: isSelected ? c.rfidCyan : (isLocked ? c.textMuted : c.textMuted),
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected
                          ? c.rfidCyan
                          : (isLocked ? c.textMuted : c.textSecondary),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isLocked
                          ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                          : c.rfidCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isLocked
                            ? const Color(0xFFEF4444).withValues(alpha: 0.4)
                            : c.rfidCyan.withValues(alpha: 0.4),
                        width: 0.7,
                      ),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        color: isLocked ? const Color(0xFFEF4444) : c.rfidCyan,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
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


