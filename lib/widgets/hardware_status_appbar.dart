import 'package:flutter/material.dart';
import '../services/mysql_sync_service.dart';
import '../theme/eye_care_theme.dart';
import '../screens/pda/pda_mysql_sync_screen.dart';

class HardwareStatusAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;

  const HardwareStatusAppBar({
    super.key,
    required this.title,
    this.actions,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final syncService = MySqlSyncService();
    final eyeCare = EyeCareThemeService();

    return ListenableBuilder(
      listenable: Listenable.merge([syncService, eyeCare]),
      builder: (context, _) {
        final isOnline = syncService.isOnline;
        final isWifi = syncService.isWifiConnected;
        final pendingCount = syncService.pendingCount;
        final c = eyeCare.colors;

        final Color statusColor = isOnline
            ? c.successEmerald
            : (isWifi ? c.rfidCyan : c.warningAmber);

        final String statusLabel = isOnline
            ? (pendingCount > 0 ? 'MySQL ($pendingCount)' : 'MySQL Online')
            : (isWifi
                ? (pendingCount > 0 ? 'Wi-Fi ($pendingCount)' : 'Wi-Fi OK')
                : (pendingCount > 0 ? 'SQLite ($pendingCount)' : 'Offline'));

        return AppBar(
          backgroundColor: c.bgDeep,
          elevation: 0,
          title: Text(
            title,
            style: TextStyle(
              color: c.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 15.5,
              letterSpacing: 0.3,
            ),
          ),
          actions: [
            // MySQL & Wi-Fi Sync Status Chip
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),

              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PdaMySqlSyncScreen()),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: statusColor,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
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
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        isOnline ? Icons.sync : (isWifi ? Icons.wifi : Icons.cloud_off),
                        size: 12,
                        color: statusColor,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            ...?actions,
          ],
        );
      },
    );
  }
}
