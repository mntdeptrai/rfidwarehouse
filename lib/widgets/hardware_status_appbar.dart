import 'package:flutter/material.dart';
import '../services/supabase_sync_service.dart';
import '../services/uhf_service.dart';
import '../theme/eye_care_theme.dart';

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
    final syncService = SupabaseSyncService();
    final uhfService = UhfService();
    final eyeCare = EyeCareThemeService();

    return ListenableBuilder(
      listenable: Listenable.merge([syncService, uhfService, eyeCare]),
      builder: (context, _) {
        final isOnline = syncService.isOnline;
        final pendingCount = syncService.pendingCount;
        final isSyncing = syncService.isSyncing;
        final c = eyeCare.colors;

        final Color statusColor = isOnline
            ? c.successEmerald
            : (pendingCount > 0 ? c.warningAmber : c.textMuted);

        final String statusLabel = isSyncing
            ? 'Đang đồng bộ...'
            : (isOnline
                ? (pendingCount > 0 ? 'Cloud ($pendingCount)' : 'Cloud Online')
                : (pendingCount > 0 ? 'Offline ($pendingCount)' : 'Offline'));

        final scanMode = uhfService.scanMode;
        final (scanLabel, scanIcon, scanColor) = switch (scanMode) {
          PdaScanMode.auto => ('AUTO', Icons.auto_mode, c.rfidCyan),
          PdaScanMode.rfid => ('RFID', Icons.sensors, c.rfidCyan),
          PdaScanMode.barcode => ('BARCODE', Icons.qr_code_scanner, c.warningAmber),
          PdaScanMode.hybrid => ('HYBRID', Icons.alt_route, c.successEmerald),
        };

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
            // Scan Mode Switcher Chip
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () {
                  final nextMode = switch (scanMode) {
                    PdaScanMode.auto => PdaScanMode.rfid,
                    PdaScanMode.rfid => PdaScanMode.barcode,
                    PdaScanMode.barcode => PdaScanMode.hybrid,
                    PdaScanMode.hybrid => PdaScanMode.auto,
                  };
                  uhfService.scanMode = nextMode;

                  final modeDesc = switch (nextMode) {
                    PdaScanMode.auto => 'Tự động theo màn hình (Auto Context)',
                    PdaScanMode.rfid => 'Chỉ quét sóng UHF RFID',
                    PdaScanMode.barcode => 'Chỉ quét mã Laser/2D Barcode',
                    PdaScanMode.hybrid => 'Quét song song cả RFID & Barcode',
                  };

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: c.bgCardElevated,
                      duration: const Duration(milliseconds: 900),
                      content: Text('⚡ Chế độ cò PDA: $modeDesc', style: TextStyle(color: c.textPrimary)),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: scanColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scanColor, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(scanIcon, size: 12, color: scanColor),
                      const SizedBox(width: 4),
                      Text(
                        scanLabel,
                        style: TextStyle(
                          color: scanColor,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Cloud Sync Status Chip
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 3),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
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
                  await syncService.syncNow();
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
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
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
