import 'package:flutter/material.dart';
import '../../services/mysql_sync_service.dart';
import '../../theme/eye_care_theme.dart';
import 'pda_drawer.dart';
import 'pda_goods_delivery_screen.dart';
import 'pda_inventory_screen.dart';
import 'pda_mysql_sync_screen.dart';
import '../inbound_screen.dart';
import '../storage_screen.dart';
import 'pda_putaway_screen.dart';

class PdaHomeScreen extends StatefulWidget {
  const PdaHomeScreen({super.key});

  @override
  State<PdaHomeScreen> createState() => _PdaHomeScreenState();
}

class _PdaHomeScreenState extends State<PdaHomeScreen> {
  final _syncService = MySqlSyncService();
  final _eyeCare = EyeCareThemeService();

  @override
  void initState() {
    super.initState();
    _syncService.addListener(_onStateChange);
    _eyeCare.addListener(_onStateChange);
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _syncService.removeListener(_onStateChange);
    _eyeCare.removeListener(_onStateChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isOnline = _syncService.isOnline;
    final isWifi = _syncService.isWifiConnected;
    final isSyncing = _syncService.isSyncing;
    final pendingCount = _syncService.pendingCount;
    final c = _eyeCare.colors;

    final Color statusColor = isOnline
        ? c.successEmerald
        : (isWifi ? c.rfidCyan : c.warningAmber);

    final String statusLabel = isOnline
        ? (pendingCount > 0 ? 'Online ($pendingCount)' : 'MySQL Online')
        : (isWifi
            ? (pendingCount > 0 ? 'Wi-Fi ($pendingCount)' : 'Wi-Fi OK')
            : (pendingCount > 0 ? 'Offline ($pendingCount)' : 'Offline'));

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: AppBar(
        backgroundColor: c.bgDeep,
        elevation: 0,
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: Icon(Icons.menu_rounded, color: c.rfidCyan, size: 24),
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'KHO TỔNG C72E',
              style: TextStyle(
                color: c.textPrimary,
                fontWeight: FontWeight.bold,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
            Text(
              'Chainway UHF RFID WMS',
              style: TextStyle(
                color: c.textMuted,
                fontSize: 10,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        actions: [
          // Online / Offline / Wi-Fi Status Badge
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const PdaMySqlSyncScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
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
                    const SizedBox(width: 5),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 10.5,
                      ),
                    ),
                    if (isOnline || isWifi) ...[
                      const SizedBox(width: 3),
                      Icon(
                        isSyncing ? Icons.sync : Icons.sync_problem_outlined,
                        size: 11,
                        color: statusColor,
                      ),
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
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Column(
            children: [
              // Offline/Online/Wi-Fi Status Notice Banner (Anti-Glare)
              InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PdaMySqlSyncScreen()),
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: c.bgCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isOnline ? c.border : statusColor.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isOnline
                            ? Icons.cloud_done_rounded
                            : (isWifi ? Icons.wifi_rounded : Icons.cloud_off_rounded),
                        color: statusColor,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          isOnline
                              ? 'MySQL Online · ${_syncService.config.host} • Tự động đồng bộ'
                              : (isWifi
                                  ? 'Đã có Wi-Fi · ${_syncService.pdaIpAddress} • Chạm để kết nối MySQL'
                                  : 'Chế độ Ngoại tuyến: Lưu trữ SQLite • Chống mỏi mắt'),
                          style: TextStyle(
                            color: isOnline ? c.textPrimary : statusColor,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, size: 16, color: c.textMuted),
                    ],
                  ),
                ),
              ),

              // Prominent Putaway Banner Card
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
                    border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.shelves, color: Colors.white, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CẤT HÀNG LÊN KỆ',
                              style: TextStyle(color: Color(0xFF38BDF8), fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.3),
                            ),
                            Text(
                              'Quét Barcode vị trí kệ & mã thùng hàng để cất',
                              style: TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF38BDF8)),
                    ],
                  ),
                ),
              ),


              // 4 Large Action Tiles with Soft Eye-Comfort Styling
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 0.96,
                  children: [
                    // 1. Goods receive
                    _buildPdaActionTile(
                      context,
                      title: 'Nhập kho',
                      subTitle: 'Quét nhận hàng',
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

                    // 2. Goods delivery
                    _buildPdaActionTile(
                      context,
                      title: 'Xuất kho',
                      subTitle: 'Quét xuất hàng',
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

                    // 3. Move goods
                    _buildPdaActionTile(
                      context,
                      title: 'Chuyển kho',
                      subTitle: 'Chuyển vị trí & kệ',
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

                    // 4. Inventory
                    _buildPdaActionTile(
                      context,
                      title: 'Kiểm kê kho',
                      subTitle: 'Kiểm đếm RFID',
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
                  ],
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
    required String subTitle,
    required IconData icon,
    required Color accentColor,
    required Color badgeColor,
    required EyeCareColors colors,
    required VoidCallback onTap,
  }) {
    return Material(
      color: colors.bgCard,
      borderRadius: BorderRadius.circular(18),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.border, width: 1.2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Icon container with soft anti-glare elevation
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  color: colors.bgCardElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.borderLight, width: 1),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, size: 34, color: accentColor),
                    Positioned(
                      top: 7,
                      right: 7,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: badgeColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subTitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
