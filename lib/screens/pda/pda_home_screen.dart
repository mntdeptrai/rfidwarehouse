import 'package:flutter/material.dart';
import '../../services/supabase_sync_service.dart';
import '../../services/auth_service.dart';
import '../../models/roles/role_registry.dart';
import '../../theme/eye_care_theme.dart';
import 'pda_drawer.dart';
import 'pda_goods_delivery_screen.dart';
import 'pda_inventory_screen.dart';
import '../inbound_screen.dart';
import '../storage_screen.dart';
import 'pda_putaway_screen.dart';
import 'pda_shelf_status_screen.dart';
import 'pda_lookup_screen.dart';

class PdaHomeScreen extends StatefulWidget {
  const PdaHomeScreen({super.key});

  @override
  State<PdaHomeScreen> createState() => _PdaHomeScreenState();
}

class _PdaHomeScreenState extends State<PdaHomeScreen> {
  final _syncService = SupabaseSyncService();
  final _eyeCare = EyeCareThemeService();
  final _authService = AuthService();

  @override
  void initState() {
    super.initState();
    _syncService.addListener(_onStateChange);
    _eyeCare.addListener(_onStateChange);
    _authService.addListener(_onStateChange);
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _syncService.removeListener(_onStateChange);
    _eyeCare.removeListener(_onStateChange);
    _authService.removeListener(_onStateChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = _authService.currentUser;
    final role = user?.rolePermission ?? RoleRegistry.fromCode(user?.role);
    final isOnline = _syncService.isOnline;
    final isSyncing = _syncService.isSyncing;
    final pendingCount = _syncService.pendingCount;
    final c = _eyeCare.colors;

    final Color statusColor = isOnline
        ? c.successEmerald
        : (pendingCount > 0 ? c.warningAmber : c.textMuted);

    final String statusLabel = isSyncing
        ? 'Đang đồng bộ...'
        : (isOnline
            ? (pendingCount > 0 ? 'Cloud ($pendingCount)' : 'Cloud Online')
            : (pendingCount > 0 ? 'Offline ($pendingCount)' : 'Offline'));

    final screenWidth = MediaQuery.maybeOf(context)?.size.width ?? 600;
    final isUltraNarrow = screenWidth < 280;

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: AppBar(
        backgroundColor: c.bgDeep,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu_rounded, color: c.rfidCyan, size: isUltraNarrow ? 20 : 24),
            padding: EdgeInsets.zero,
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'QUẢN LÝ KHO RFID',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: isUltraNarrow ? 12.5 : 15,
                letterSpacing: 0.3,
              ),
            ),
            if (!isUltraNarrow)
              Text(
                'UHF RFID WMS SYSTEM',
                style: TextStyle(
                  color: c.textMuted,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        actions: [
          // Online / Offline / Cloud Status Badge
          Padding(
            padding: EdgeInsets.only(right: isUltraNarrow ? 4 : 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: c.bgCardElevated,
                    duration: const Duration(seconds: 1),
                    content: Text(
                      isOnline
                          ? 'Đang kích hoạt đồng bộ Supabase Cloud...'
                          : 'Đang kết nối lại Supabase Cloud...',
                      style: TextStyle(color: c.textPrimary),
                    ),
                  ),
                );
                await _syncService.syncNow();
              },
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: isUltraNarrow ? 6 : 9, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: statusColor,
                    width: 1.1,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isSyncing)
                      SizedBox(
                        width: 11,
                        height: 11,
                        child: CircularProgressIndicator(strokeWidth: 2, color: c.rfidCyan),
                      )
                    else
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    if (!isUltraNarrow) ...[
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 10.5,
                        ),
                      ),
                      if (isOnline) ...[
                        const SizedBox(width: 3),
                        Icon(
                          isSyncing ? Icons.sync : Icons.check_circle_outline,
                          size: 11,
                          color: statusColor,
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      drawer: const PdaDrawer(),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isUltraNarrow ? 8 : 18, vertical: isUltraNarrow ? 8 : 14),
          child: Column(
            children: [
              // Prominent Putaway Banner Card (Chỉ hiển thị cho người có quyền)
              if (role.canInbound)
                InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PdaPutawayScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF0284C7),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.shelves,
                            color: Color(0xFF2C251E),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'CẤT HÀNG LÊN KỆ (PUTAWAY)',
                            style: TextStyle(
                              color: Color(0xFF0284C7),
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward_ios,
                          size: 14,
                          color: Color(0xFF0284C7),
                        ),
                      ],
                    ),
                  ),
                ),

              Expanded(
                child: LayoutBuilder(
                  builder: (context, gridConstraints) {
                    final isUltraNarrowGrid = gridConstraints.maxWidth < 260;
                    final crossAxisCount = isUltraNarrowGrid ? 1 : (gridConstraints.maxWidth > 550 ? 3 : 2);
                    final childAspectRatio = isUltraNarrowGrid ? 2.6 : 1.05;

                    return GridView.count(
                      crossAxisCount: crossAxisCount,
                      crossAxisSpacing: isUltraNarrowGrid ? 8 : 16,
                      mainAxisSpacing: isUltraNarrowGrid ? 8 : 16,
                      childAspectRatio: childAspectRatio,
                      children: [
                        if (role.canInbound)
                          _buildPdaActionTile(
                            context,
                            title: 'Nhập kho',
                            icon: Icons.input_rounded,
                            accentColor: c.rfidCyan,
                            badgeColor: c.warningAmber,
                            colors: c,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const InboundScreen()),
                              );
                            },
                          ),
                        if (role.canOutbound)
                          _buildPdaActionTile(
                            context,
                            title: 'Xuất kho',
                            icon: Icons.output_rounded,
                            accentColor: c.rfidCyan,
                            badgeColor: c.warningAmber,
                            colors: c,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const PdaGoodsDeliveryScreen()),
                              );
                            },
                          ),
                        if (role.canTransfer)
                          _buildPdaActionTile(
                            context,
                            title: 'Chuyển kho',
                            icon: Icons.swap_horiz_rounded,
                            accentColor: c.rfidCyan,
                            badgeColor: c.warningAmber,
                            colors: c,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const StorageScreen()),
                              );
                            },
                          ),
                        if (role.canAudit)
                          _buildPdaActionTile(
                            context,
                            title: 'Kiểm kê kho',
                            icon: Icons.inventory_2_rounded,
                            accentColor: c.rfidCyan,
                            badgeColor: c.successEmerald,
                            colors: c,
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const PdaInventoryScreen()),
                              );
                            },
                          ),
                        _buildPdaActionTile(
                          context,
                          title: 'Trạng thái kệ',
                          icon: Icons.tune_rounded,
                          accentColor: const Color(0xFFF59E0B),
                          badgeColor: const Color(0xFFEF4444),
                          colors: c,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PdaShelfStatusScreen()),
                            );
                          },
                        ),
                        _buildPdaActionTile(
                          context,
                          title: 'Tra cứu mã',
                          icon: Icons.search_rounded,
                          accentColor: c.rfidCyan,
                          badgeColor: c.rfidCyan,
                          colors: c,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PdaLookupScreen()),
                            );
                          },
                        ),
                      ],
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

  Widget _buildPdaActionTile(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color accentColor,
    required Color badgeColor,
    required EyeCareColors colors,
    required VoidCallback onTap,
    bool isLocked = false,
    String roleName = '',
  }) {
    return Material(
      color: isLocked ? colors.bgCard.withValues(alpha: 0.5) : colors.bgCard,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: () {
          if (isLocked) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: colors.bgCardElevated,
                content: Row(
                  children: [
                    const Icon(Icons.lock_outline, color: Color(0xFFF59E0B), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Quyền "$roleName" không có quyền truy cập $title',
                        style: TextStyle(color: colors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ),
            );
            return;
          }
          onTap();
        },
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isLocked ? colors.border.withValues(alpha: 0.5) : colors.border,
              width: 1.2,
            ),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final isRowMode = constraints.maxWidth > 130 && constraints.maxHeight < 80;
              final iconBox = Container(
                width: isRowMode ? 38 : 50,
                height: isRowMode ? 38 : 50,
                decoration: BoxDecoration(
                  color: isLocked ? colors.bgDeep : colors.bgCardElevated,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isLocked ? colors.border : colors.borderLight,
                    width: 1,
                  ),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      isLocked ? Icons.lock_outline_rounded : icon,
                      size: isRowMode ? 22 : 28,
                      color: isLocked ? colors.textMuted : accentColor,
                    ),
                    if (isLocked)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF59E0B),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.lock, size: 7, color: Colors.white),
                        ),
                      )
                    else
                      Positioned(
                        top: 5,
                        right: 5,
                        child: Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: badgeColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
              );

              final textLabel = Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: isRowMode ? MainAxisAlignment.start : MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      title,
                      textAlign: isRowMode ? TextAlign.start : TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isLocked ? colors.textMuted : colors.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: isRowMode ? 13 : 13.5,
                      ),
                    ),
                  ),
                  if (isLocked) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.lock_rounded, size: 12, color: Color(0xFFF59E0B)),
                  ],
                ],
              );

              if (isRowMode) {
                return Row(
                  children: [
                    iconBox,
                    const SizedBox(width: 10),
                    Expanded(child: textLabel),
                    Icon(Icons.arrow_forward_ios, size: 12, color: colors.textMuted),
                  ],
                );
              }

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  iconBox,
                  const SizedBox(height: 6),
                  textLabel,
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
