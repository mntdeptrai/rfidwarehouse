import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/eye_care_theme.dart';
import '../../services/warehouse_repository.dart';
import 'pda_lookup_screen.dart';
import 'pda_putaway_screen.dart';

class PdaDrawer extends StatelessWidget {
  const PdaDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final eyeCare = EyeCareThemeService();
    final auth = AuthService();

    return ListenableBuilder(
      listenable: Listenable.merge([eyeCare, auth]),
      builder: (context, _) {
        final c = eyeCare.colors;
        final user = auth.currentUser;
        final roleLabel = switch (user?.role.toLowerCase()) {
          'admin' => 'Quản Trị Viên',
          'manager' => 'Quản Lý Kho',
          'forklift' => 'Lái Xe Nâng',
          _ => 'Thủ Kho',
        };

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
                    color: c.rfidCyan.withValues(alpha: 0.2),
                    border: Border.all(color: c.rfidCyan, width: 1.5),
                  ),
                  child: Center(
                    child: Text(
                      user?.fullName.isNotEmpty == true ? user!.fullName.substring(0, 1).toUpperCase() : 'U',
                      style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 24),
                    ),
                  ),
                ),
                accountName: Row(
                  children: [
                    Expanded(
                      child: Text(
                        user?.fullName ?? 'RFID Warehouse PDA',
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15.5),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (user != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: c.rfidCyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.rfidCyan, width: 0.8),
                        ),
                        child: Text(
                          roleLabel,
                          style: TextStyle(color: c.rfidCyan, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                accountEmail: Text(
                  user != null ? '@${user.username} • ${user.email ?? "Offline Mode"}' : 'Thiết bị Handheld PDA',
                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              ListTile(
                leading: Icon(Icons.shelves, color: c.successEmerald),
                title: Text('Xếp Kho / Cất Hàng (Putaway)', style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
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
                    const SnackBar(content: Text('Danh mục hàng hóa đã được đồng bộ')),
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
              Divider(color: c.border),
              ListTile(
                leading: Icon(Icons.delete_sweep_rounded, color: c.errorCoral),
                title: Text('Xóa Sạch Dữ Liệu', style: TextStyle(color: c.errorCoral, fontSize: 14)),
                onTap: () async {
                  Navigator.pop(context);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: c.bgCard,
                      title: Text('Xác nhận xóa sạch dữ liệu?', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
                      content: Text('Toàn bộ đơn hàng và chip RFID thử nghiệm sẽ được xóa sạch 100% để bạn bắt đầu tạo dữ liệu thực tế.', style: TextStyle(color: c.textSecondary)),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('HỦY', style: TextStyle(color: c.textMuted))),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: c.errorCoral),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('XÓA SẠCH', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await WarehouseRepository().clearAllData();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(backgroundColor: c.successEmerald, content: const Text('✓ Đã xóa sạch dữ liệu thử nghiệm trong hệ thống!')),
                      );
                    }
                  }
                },
              ),
              Divider(color: c.border),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Color(0xFFEF4444)),
                title: const Text('Đăng Xuất (Logout)', style: TextStyle(color: Color(0xFFEF4444), fontSize: 14, fontWeight: FontWeight.bold)),
                subtitle: Text(user != null ? 'Tài khoản: @${user.username}' : 'Thoát phiên làm việc', style: TextStyle(color: c.textMuted, fontSize: 11.5)),
                onTap: () async {
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
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                    await auth.logout();
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

