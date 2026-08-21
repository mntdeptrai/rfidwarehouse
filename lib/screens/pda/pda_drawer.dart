import 'package:flutter/material.dart';
import '../../theme/eye_care_theme.dart';
import 'pda_lookup_screen.dart';
import 'pda_mysql_sync_screen.dart';
import 'pda_putaway_screen.dart';

class PdaDrawer extends StatelessWidget {
  const PdaDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final eyeCare = EyeCareThemeService();

    return ListenableBuilder(
      listenable: eyeCare,
      builder: (context, _) {
        final c = eyeCare.colors;

        return Drawer(
          backgroundColor: c.bgCard,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              UserAccountsDrawerHeader(
                decoration: BoxDecoration(
                  color: c.bgDeep,
                  border: Border(bottom: BorderSide(color: c.border, width: 1)),
                ),
                currentAccountPicture: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c.rfidCyan,
                  ),
                  child: Icon(Icons.person, size: 42, color: c.bgDeep),
                ),
                accountName: Text(
                  'User01 (Thủ Kho)',
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                accountEmail: Text(
                  'user01@rfidwarehouse.vn',
                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                ),
              ),
              ListTile(
                leading: Icon(Icons.shelves, color: c.successEmerald),
                title: Text('Xếp Kho / Cất Hàng (Putaway)', style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Text('Quét Barcode Thùng & Vị Trí Kệ', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PdaPutawayScreen()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.inventory_2, color: c.rfidCyan),
                title: Text('Danh Mục Hàng Hóa', style: TextStyle(color: c.textPrimary, fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Danh mục hàng hóa đã đồng bộ SQLite')),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.search, color: c.rfidCyan),
                title: Text('Tra Cứu Mã & Serial', style: TextStyle(color: c.textPrimary, fontSize: 14)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PdaLookupScreen()),
                  );
                },
              ),
              ListTile(
                leading: Icon(Icons.sync_alt, color: c.successEmerald),
                title: Text('Đồng Bộ SQLite ⇋ MySQL', style: TextStyle(color: c.textPrimary, fontSize: 14)),
                subtitle: Text('Tự động đồng bộ khi có mạng', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const PdaMySqlSyncScreen()),
                  );
                },
              ),
              const Divider(color: Color(0xFF334155)),
              ListTile(
                leading: Icon(
                  eyeCare.mode == EyeCareMode.amberNight
                      ? Icons.nightlight_round
                      : (eyeCare.mode == EyeCareMode.softSepia ? Icons.menu_book : Icons.remove_red_eye),
                  color: c.warningAmber,
                ),
                title: Text('Chế Độ Chống Mỏi Mắt', style: TextStyle(color: c.textPrimary, fontSize: 14)),
                subtitle: Text(
                  'Đang dùng: ${eyeCare.modeName}',
                  style: TextStyle(color: c.warningAmber, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.touch_app, size: 18, color: Colors.white38),
                onTap: () {
                  eyeCare.toggleNextMode();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: c.bgCardElevated,
                      duration: const Duration(seconds: 1),
                      content: Text('Đã chuyển sang: ${eyeCare.modeName}'),
                    ),
                  );
                },
              ),
              const Divider(color: Color(0xFF334155)),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'RFIDwarehouse v1.0 • Eye-Care Enabled',
                  style: TextStyle(color: c.textMuted, fontSize: 11),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
