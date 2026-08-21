import 'package:flutter/material.dart';
import '../../theme/eye_care_theme.dart';
import '../../services/warehouse_repository.dart';
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
                  child: Icon(Icons.qr_code_scanner, size: 36, color: c.bgDeep),
                ),
                accountName: Text(
                  'RFID Warehouse PDA',
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                ),
                accountEmail: Text(
                  'Thiết bị C72e • Sẵn sàng quét',
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
              Divider(color: c.border),
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
                trailing: Icon(Icons.touch_app, size: 18, color: c.textMuted),
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
              Divider(color: c.border),
              ListTile(
                leading: Icon(Icons.delete_sweep_rounded, color: c.errorCoral),
                title: Text('Xóa Sạch Dữ Liệu SQLite', style: TextStyle(color: c.errorCoral, fontSize: 14)),
                subtitle: Text('Xóa sạch đơn/thẻ thử nghiệm trên PDA & MySQL', style: TextStyle(color: c.textMuted, fontSize: 11)),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: c.bgCard,
                      title: Text('Xác nhận xóa sạch dữ liệu?', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
                      content: Text('Toàn bộ đơn hàng và chip RFID thử nghiệm (trên cả máy chủ MySQL và PDA) sẽ được xóa sạch 100% để bạn bắt đầu tạo dữ liệu thực tế.', style: TextStyle(color: c.textSecondary)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('HỦY', style: TextStyle(color: c.textMuted))),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: c.errorCoral),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('XÓA SẠCH', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await WarehouseRepository().clearAllData(alsoClearMySql: true);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(backgroundColor: c.successEmerald, content: const Text('✓ Đã xóa sạch dữ liệu thử nghiệm trên cả PDA & MySQL!')),
                      );
                    }
                  }
                },
              ),
              Divider(color: c.border),
            ],
          ),
        );
      },
    );
  }
}

