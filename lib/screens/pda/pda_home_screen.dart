import 'package:flutter/material.dart';
import '../../services/supabase_sync_service.dart';
import '../../theme/eye_care_theme.dart';
import 'pda_drawer.dart';
import 'pda_goods_delivery_screen.dart';
import 'pda_inventory_screen.dart';
import '../inbound_screen.dart';
import '../storage_screen.dart';
import 'pda_putaway_screen.dart';

class PdaHomeScreen extends StatefulWidget {
  const PdaHomeScreen({super.key});

  @override
  State<PdaHomeScreen> createState() => _PdaHomeScreenState();
}

class _PdaHomeScreenState extends State<PdaHomeScreen> {
  final _syncService = SupabaseSyncService();
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
          // Online / Offline / Cloud Status Badge
          Padding(
            padding: const EdgeInsets.only(right: 12),
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
                    if (isOnline) ...[
                      const SizedBox(width: 3),
                      Icon(
                        isSyncing ? Icons.sync : Icons.check_circle_outline,
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
                        child: Text(
                          'CẤT HÀNG LÊN KỆ (PUTAWAY)',
                          style: TextStyle(
                            color: Color(0xFF38BDF8),
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios, size: 14, color: Color(0xFF38BDF8)),
                    ],
                  ),
                ),
              ),

              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                  childAspectRatio: 1.05,
                  children: [
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
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.border, width: 1.2),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: colors.bgCardElevated,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: colors.borderLight, width: 1),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, size: 32, color: accentColor),
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
              const SizedBox(height: 10),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
