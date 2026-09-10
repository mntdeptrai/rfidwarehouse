import 'package:flutter/material.dart';
import '../../services/supabase_sync_service.dart';
import '../../services/auth_service.dart';
import '../../services/warehouse_repository.dart';
import '../../models/wms_models.dart';
import '../../theme/eye_care_theme.dart';
import 'pda_drawer.dart';
import 'pda_goods_delivery_screen.dart';
import 'pda_inventory_screen.dart';
import '../inbound_screen.dart';
import 'pda_transfer_screen.dart';
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
  final _repo = WarehouseRepository();

  @override
  void initState() {
    super.initState();
    _syncService.addListener(_onStateChange);
    _eyeCare.addListener(_onStateChange);
    _authService.addListener(_onStateChange);
    _repo.addListener(_onStateChange);
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _syncService.removeListener(_onStateChange);
    _eyeCare.removeListener(_onStateChange);
    _authService.removeListener(_onStateChange);
    _repo.removeListener(_onStateChange);
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
              // Ô thông tin khi nhận lệnh nhập hoặc xuất từ app desktop (WMS Dispatch Notification)
              _buildDesktopOrderNotificationCard(c, role),

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
                                MaterialPageRoute(builder: (_) => const PdaTransferScreen()),
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

  Widget _buildDesktopOrderNotificationCard(EyeCareColors c, BaseRolePermission role) {
    if (!role.canInbound) return const SizedBox.shrink();

    // 1. Hàng đang chờ xếp vào Pallet (nhánh không có mã pallet trong file import)
    final waitingPalletizeItems = _repo.items.where((it) =>
        it.status == ItemStatus.waitingPalletize
    ).toList();
    final waitingPalletizeOrders = _repo.inboundOrders.where((o) =>
        o.status == InboundOrderStatus.waitingPalletize
    ).toList();
    final hasWaitingPalletize = waitingPalletizeItems.isNotEmpty || waitingPalletizeOrders.isNotEmpty;

    // 2. Hàng đã có Pallet và đang chờ cất vào kệ
    final waitingPutawayItems = _repo.items.where((it) =>
        (it.status == ItemStatus.waitingPutaway ||
         (it.status == ItemStatus.inStock &&
          (it.locationId == null || it.locationId!.isEmpty || it.locationId == 'LOC-GATE-IN'))) &&
        it.status != ItemStatus.pendingInbound &&
        it.status != ItemStatus.waitingPalletize &&
        (it.palletId != null && it.palletId!.trim().isNotEmpty)
    ).toList();

    final waitingInboundOrders = _repo.inboundOrders.where((o) =>
        o.status == InboundOrderStatus.waitingPutaway
    ).toList();
    final hasPutaway = waitingPutawayItems.isNotEmpty || waitingInboundOrders.isNotEmpty;

    if (!hasWaitingPalletize && !hasPutaway) {
      return const SizedBox.shrink();
    }

    final cards = <Widget>[];

    if (hasWaitingPalletize) {
      final pCount = waitingPalletizeItems.isNotEmpty
          ? waitingPalletizeItems.length
          : waitingPalletizeOrders.first.details.fold(0, (sum, d) => sum + d.requiredQty);
      final orderTitle = waitingPalletizeOrders.isNotEmpty ? waitingPalletizeOrders.first.orderNo : 'Đơn nhập cổng';

      cards.add(
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PdaPutawayScreen()),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.move_to_inbox,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'CẦN XẾP VÀO PALLET',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$orderTitle • $pCount sản phẩm',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'Đã qua cổng RFID • Cần xếp vào pallet trước khi cất kệ ➜',
                        style: TextStyle(
                          color: Color(0xFFD97706),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Color(0xFFF59E0B),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (hasPutaway) {
      final targetPallet = waitingPutawayItems.isNotEmpty
          ? (waitingPutawayItems.first.palletId ?? 'Xe hàng')
          : (waitingInboundOrders.first.orderNo);
      final count = waitingPutawayItems.isNotEmpty
          ? waitingPutawayItems.where((it) => it.palletId == targetPallet).length
          : waitingInboundOrders.first.details.fold(0, (sum, d) => sum + d.requiredQty);

      cards.add(
        InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PdaPutawayScreen()),
            );
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.shelves,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'ĐÃ ĐỌC XONG - CẦN CẤT VÀO KỆ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Xe: $targetPallet • $count sản phẩm',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Text(
                        'Máy tính đã đọc đủ • Bấm để cất vào kệ ➜',
                        style: TextStyle(
                          color: Color(0xFF059669),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios,
                  size: 14,
                  color: Color(0xFF10B981),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: cards,
    );
  }
}
