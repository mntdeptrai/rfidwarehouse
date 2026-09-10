import 'package:flutter/material.dart';
import '../../models/wms_models.dart';
import '../../services/auth_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';

class DesktopUserManagementView extends StatefulWidget {
  const DesktopUserManagementView({super.key});

  @override
  State<DesktopUserManagementView> createState() => _DesktopUserManagementViewState();
}

class _DesktopUserManagementViewState extends State<DesktopUserManagementView> {
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final WarehouseRepository _repo = WarehouseRepository();
  final AuthService _auth = AuthService();

  final TextEditingController _searchController = TextEditingController();
  String _selectedRoleFilter = 'ALL';
  String _selectedStatusFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onStateChange);
    _repo.addListener(_onStateChange);
    _auth.addListener(_onStateChange);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _repo.reloadFromSqlite();
    });
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _eyeCare.removeListener(_onStateChange);
    _repo.removeListener(_onStateChange);
    _auth.removeListener(_onStateChange);
    super.dispose();
  }

  Color _getRoleColor(String roleCode, EyeCareColors c) {
    switch (roleCode.toLowerCase()) {
      case 'admin':
        return c.rfidCyan;
      case 'kythuat':
      case 'technician':
        return const Color(0xFFF59E0B);
      case 'thukho':
        return c.successEmerald;
      case 'handheld':
        return const Color(0xFF38BDF8);
      case 'seller':
        return const Color(0xFFEC4899);
      default:
        return c.textSecondary;
    }
  }

  IconData _getRoleIcon(String roleCode) {
    switch (roleCode.toLowerCase()) {
      case 'admin':
        return Icons.admin_panel_settings_rounded;
      case 'kythuat':
      case 'technician':
        return Icons.build_rounded;
      case 'thukho':
        return Icons.warehouse_rounded;
      case 'handheld':
        return Icons.qr_code_scanner_rounded;
      case 'seller':
        return Icons.storefront_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  List<WmsUser> _getFilteredUsers() {
    final query = _searchController.text.trim().toLowerCase();
    return _repo.users.where((user) {
      if (_selectedRoleFilter != 'ALL' && user.role.toLowerCase() != _selectedRoleFilter.toLowerCase()) {
        return false;
      }
      if (_selectedStatusFilter == 'ACTIVE' && !user.isActive) return false;
      if (_selectedStatusFilter == 'INACTIVE' && user.isActive) return false;

      if (query.isNotEmpty) {
        final matchUsername = user.username.toLowerCase().contains(query);
        final matchName = user.fullName.toLowerCase().contains(query);
        final matchEmail = user.email?.toLowerCase().contains(query) ?? false;
        final matchPhone = user.phone?.toLowerCase().contains(query) ?? false;
        final matchRole = user.rolePermission.name.toLowerCase().contains(query);
        return matchUsername || matchName || matchEmail || matchPhone || matchRole;
      }
      return true;
    }).toList();
  }

  void _showCreateUserDialog(BuildContext context, EyeCareColors c) {
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final fullNameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    String selectedRole = 'kythuat';
    bool isActive = true;
    bool obscurePassword = true;
    String? localError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.rfidCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.person_add_alt_1_rounded, color: c.rfidCyan, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CẤP TÀI KHOẢN NHÂN VIÊN',
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'Chức năng quản trị viên: Tạo tài khoản và phân quyền vai trò',
                      style: TextStyle(color: c.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (localError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: c.errorCoral.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.errorCoral.withValues(alpha: 0.4)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline_rounded, color: c.errorCoral, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              localError!,
                              style: TextStyle(color: c.errorCoral, fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // Tên đăng nhập & Mật khẩu
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Tên đăng nhập *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: usernameCtrl,
                              style: TextStyle(color: c.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'vd: kythuat_kho, thukho1...',
                                hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                                prefixIcon: Icon(Icons.account_circle_outlined, color: c.textMuted, size: 18),
                                filled: true,
                                fillColor: c.bgCardElevated,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Mật khẩu khởi tạo *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: passwordCtrl,
                              obscureText: obscurePassword,
                              style: TextStyle(color: c.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'Tối thiểu 6 ký tự...',
                                hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                                prefixIcon: Icon(Icons.lock_outline_rounded, color: c.textMuted, size: 18),
                                suffixIcon: IconButton(
                                  icon: Icon(obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: c.textMuted, size: 18),
                                  onPressed: () => setDialogState(() => obscurePassword = !obscurePassword),
                                ),
                                filled: true,
                                fillColor: c.bgCardElevated,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Họ và tên
                  Text('Họ và tên nhân viên *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: fullNameCtrl,
                    style: TextStyle(color: c.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Nhập họ và tên đầy đủ...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                      prefixIcon: Icon(Icons.badge_outlined, color: c.textMuted, size: 18),
                      filled: true,
                      fillColor: c.bgCardElevated,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Chọn vai trò (Role)
                  Text('Vai trò & Phân quyền *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.bgCardElevated,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedRole,
                        isExpanded: true,
                        dropdownColor: c.bgCard,
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: c.textMuted),
                        items: RoleRegistry.allRoles.map((role) {
                          final roleColor = _getRoleColor(role.code, c);
                          return DropdownMenuItem<String>(
                            value: role.code,
                            child: Row(
                              children: [
                                Icon(_getRoleIcon(role.code), color: roleColor, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  role.name,
                                  style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) setDialogState(() => selectedRole = val);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.bgDeep,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.border.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, color: c.rfidCyan, size: 15),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            RoleRegistry.fromCode(selectedRole).description,
                            style: TextStyle(color: c.textSecondary, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Email & Số điện thoại
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Email (Tùy chọn)', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: emailCtrl,
                              style: TextStyle(color: c.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: 'email@congty.com',
                                hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                                prefixIcon: Icon(Icons.email_outlined, color: c.textMuted, size: 18),
                                filled: true,
                                fillColor: c.bgCardElevated,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Số điện thoại (Tùy chọn)', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: phoneCtrl,
                              style: TextStyle(color: c.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                hintText: '0901234567',
                                hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                                prefixIcon: Icon(Icons.phone_outlined, color: c.textMuted, size: 18),
                                filled: true,
                                fillColor: c.bgCardElevated,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Checkbox kích hoạt
                  Row(
                    children: [
                      SizedBox(
                        width: 24,
                        height: 24,
                        child: Checkbox(
                          value: isActive,
                          activeColor: c.rfidCyan,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                          onChanged: (val) => setDialogState(() => isActive = val ?? true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setDialogState(() => isActive = !isActive),
                        child: Text('Kích hoạt tài khoản ngay sau khi tạo', style: TextStyle(color: c.textPrimary, fontSize: 12.5)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text('HỦY', style: TextStyle(color: c.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.rfidCyan,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                final username = usernameCtrl.text.trim();
                final password = passwordCtrl.text.trim();
                final fullName = fullNameCtrl.text.trim();

                if (username.isEmpty || password.isEmpty || fullName.isEmpty) {
                  setDialogState(() => localError = 'Vui lòng nhập đầy đủ tên đăng nhập, mật khẩu và họ tên.');
                  return;
                }
                if (username.length < 3) {
                  setDialogState(() => localError = 'Tên đăng nhập phải có ít nhất 3 ký tự.');
                  return;
                }
                if (password.length < 6) {
                  setDialogState(() => localError = 'Mật khẩu phải có tối thiểu 6 ký tự.');
                  return;
                }

                final success = await _auth.adminCreateUser(
                  username: username,
                  password: password,
                  fullName: fullName,
                  email: emailCtrl.text.trim(),
                  phone: phoneCtrl.text.trim(),
                  role: selectedRole,
                  isActive: isActive,
                );

                if (success) {
                  if (context.mounted) {
                    Navigator.pop(dialogCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: c.successEmerald,
                        content: Row(
                          children: [
                            const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                            const SizedBox(width: 8),
                            Text('Cấp tài khoản "$username" thành công!'),
                          ],
                        ),
                      ),
                    );
                  }
                } else {
                  setDialogState(() => localError = _auth.authError ?? 'Không thể tạo tài khoản.');
                }
              },
              child: const Text('CẤP TÀI KHOẢN', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showResetPasswordDialog(BuildContext context, WmsUser user, EyeCareColors c) {
    final newPassCtrl = TextEditingController();
    bool obscure = true;
    String? localError;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
          title: Row(
            children: [
              Icon(Icons.key_rounded, color: const Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 8),
              Text('ĐẶT LẠI MẬT KHẨU', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Đặt lại mật khẩu cho tài khoản: @${user.username} (${user.fullName})',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 14),
              if (localError != null) ...[
                Text(localError!, style: TextStyle(color: c.errorCoral, fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: newPassCtrl,
                obscureText: obscure,
                style: TextStyle(color: c.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  hintText: 'Nhập mật khẩu mới (tối thiểu 6 ký tự)...',
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                  prefixIcon: Icon(Icons.lock_reset_rounded, color: c.textMuted, size: 18),
                  suffixIcon: IconButton(
                    icon: Icon(obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, color: c.textMuted, size: 18),
                    onPressed: () => setDialogState(() => obscure = !obscure),
                  ),
                  filled: true,
                  fillColor: c.bgCardElevated,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text('HỦY', style: TextStyle(color: c.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF59E0B), foregroundColor: Colors.white),
              onPressed: () async {
                final newPass = newPassCtrl.text.trim();
                if (newPass.length < 6) {
                  setDialogState(() => localError = 'Mật khẩu phải có tối thiểu 6 ký tự.');
                  return;
                }
                final success = await _auth.adminResetPassword(user.userId, newPass);
                if (success && context.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      backgroundColor: c.successEmerald,
                      content: Text('Đã cập nhật mật khẩu mới cho tài khoản @${user.username}!'),
                    ),
                  );
                } else {
                  setDialogState(() => localError = _auth.authError ?? 'Lỗi đặt lại mật khẩu.');
                }
              },
              child: const Text('CẬP NHẬT MẬT KHẨU', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditUserDialog(BuildContext context, WmsUser user, EyeCareColors c) {
    final fullNameCtrl = TextEditingController(text: user.fullName);
    final emailCtrl = TextEditingController(text: user.email ?? '');
    final phoneCtrl = TextEditingController(text: user.phone ?? '');
    String selectedRole = user.role;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.border)),
          title: Row(
            children: [
              Icon(Icons.edit_note_rounded, color: c.rfidCyan, size: 22),
              const SizedBox(width: 8),
              Text('CHỈNH SỬA TÀI KHOẢN @${user.username}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Họ và tên *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                TextField(
                  controller: fullNameCtrl,
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: c.bgCardElevated,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                  ),
                ),
                const SizedBox(height: 12),

                Text('Vai trò *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.bgCardElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: RoleRegistry.allRoles.any((r) => r.code == selectedRole) ? selectedRole : 'thukho',
                      isExpanded: true,
                      dropdownColor: c.bgCard,
                      items: RoleRegistry.allRoles.map((r) {
                        return DropdownMenuItem<String>(
                          value: r.code,
                          child: Row(
                            children: [
                              Icon(_getRoleIcon(r.code), color: _getRoleColor(r.code, c), size: 18),
                              const SizedBox(width: 8),
                              Text(r.name, style: TextStyle(color: _getRoleColor(r.code, c), fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setDialogState(() => selectedRole = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                Text('Email', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                TextField(
                  controller: emailCtrl,
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: c.bgCardElevated,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                  ),
                ),
                const SizedBox(height: 12),

                Text('Số điện thoại', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                const SizedBox(height: 4),
                TextField(
                  controller: phoneCtrl,
                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: c.bgCardElevated,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogCtx), child: Text('HỦY', style: TextStyle(color: c.textMuted))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan, foregroundColor: Colors.white),
              onPressed: () async {
                final updated = WmsUser(
                  userId: user.userId,
                  username: user.username,
                  fullName: fullNameCtrl.text.trim(),
                  email: emailCtrl.text.trim().isNotEmpty ? emailCtrl.text.trim() : null,
                  phone: phoneCtrl.text.trim().isNotEmpty ? phoneCtrl.text.trim() : null,
                  role: selectedRole,
                  isActive: user.isActive,
                  createdAt: user.createdAt,
                );
                await _auth.adminUpdateUser(updated);
                if (context.mounted) {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: c.successEmerald, content: Text('Đã cập nhật thông tin tài khoản @${user.username}!')),
                  );
                }
              },
              child: const Text('LƯU THAY ĐỔI', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmDeleteUser(BuildContext context, WmsUser user, EyeCareColors c) async {
    if (_auth.currentUser?.userId == user.userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: c.errorCoral, content: const Text('Không thể xóa tài khoản Quản trị viên đang đăng nhập!')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: c.errorCoral, size: 24),
            const SizedBox(width: 8),
            Text('Xác nhận xóa tài khoản?', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa tài khoản "${user.fullName}" (@${user.username}) khỏi hệ thống? Thao tác này không thể hoàn tác.',
          style: TextStyle(color: c.textSecondary),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('HỦY', style: TextStyle(color: c.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.errorCoral, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('XÓA TÀI KHOẢN', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _auth.adminDeleteUser(user.userId);
      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: c.successEmerald, content: Text('Đã xóa tài khoản @${user.username}!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: c.errorCoral, content: Text(_auth.authError ?? 'Lỗi khi xóa tài khoản!')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final allUsers = _repo.users;
    final filteredUsers = _getFilteredUsers();

    // Stats calculations
    final totalCount = allUsers.length;
    final adminCount = allUsers.where((u) => u.role == 'admin').length;
    final techCount = allUsers.where((u) => u.role == 'kythuat' || u.role == 'technician').length;
    final thukhoCount = allUsers.where((u) => u.role == 'thukho' || u.role == 'operator').length;
    final handheldCount = allUsers.where((u) => u.role == 'handheld').length;
    final sellerCount = allUsers.where((u) => u.role == 'seller').length;
    final activeCount = allUsers.where((u) => u.isActive).length;

    return Container(
      color: c.bgDeep,
      child: Column(
        children: [
          // Header Bar & Actions
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            decoration: BoxDecoration(
              color: c.bgCard,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.rfidCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.rfidCyan, width: 1.2),
                  ),
                  child: Icon(Icons.manage_accounts_rounded, color: c.rfidCyan, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'QUẢN LÝ & CẤP TÀI KHOẢN NHÂN VIÊN',
                            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 17, letterSpacing: 0.4),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: c.rfidCyan.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: c.rfidCyan, width: 0.8),
                            ),
                            child: Text('ADMIN ONLY', style: TextStyle(color: c.rfidCyan, fontSize: 9.5, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                            ),
                            child: const Text('CSDL THỰC TẾ (NO MOCK)', style: TextStyle(color: Color(0xFF10B981), fontSize: 9.5, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Quản trị viên toàn quyền cấp mới tài khoản, phân quyền vai trò (Kỹ thuật, Thủ kho, PDA, Seller), đặt lại mật khẩu và khóa tài khoản.',
                        style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.border),
                    foregroundColor: c.textPrimary,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('LÀM MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () async {
                    await _repo.reloadFromSqlite();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF10B981),
                          content: const Row(
                            children: [
                              Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text('Đã làm mới dữ liệu thực tế từ CSDL SQLite.'),
                            ],
                          ),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    }
                  },
                ),
                const SizedBox(width: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.rfidCyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('CẤP TÀI KHOẢN MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  onPressed: () => _showCreateUserDialog(context, c),
                ),
              ],
            ),
          ),

          // Overview Stats Badges
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            color: c.bgCardElevated.withValues(alpha: 0.5),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildStatCard('Tổng người dùng', '$totalCount', Icons.people_alt_rounded, c.textPrimary, c),
                  const SizedBox(width: 12),
                  _buildStatCard('Admin (Quản trị)', '$adminCount', Icons.admin_panel_settings_rounded, c.rfidCyan, c),
                  const SizedBox(width: 12),
                  _buildStatCard('Kỹ thuật (Hardware)', '$techCount', Icons.build_rounded, const Color(0xFFF59E0B), c),
                  const SizedBox(width: 12),
                  _buildStatCard('Thủ kho', '$thukhoCount', Icons.warehouse_rounded, c.successEmerald, c),
                  const SizedBox(width: 12),
                  _buildStatCard('Máy cầm tay (PDA)', '$handheldCount', Icons.qr_code_scanner_rounded, const Color(0xFF38BDF8), c),
                  const SizedBox(width: 12),
                  _buildStatCard('Bán hàng (Seller)', '$sellerCount', Icons.storefront_rounded, const Color(0xFFEC4899), c),
                  const SizedBox(width: 12),
                  _buildStatCard('Đang hoạt động', '$activeCount / $totalCount', Icons.verified_user_rounded, c.successEmerald, c),
                ],
              ),
            ),
          ),

          // Filter Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: c.bgCard,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                // Search Input
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      controller: _searchController,
                      style: TextStyle(color: c.textPrimary, fontSize: 13),
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        hintText: 'Tìm kiếm theo tên, username, email, số điện thoại...',
                        hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                        prefixIcon: Icon(Icons.search, color: c.textMuted, size: 18),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                        filled: true,
                        fillColor: c.bgCardElevated,
                        contentPadding: EdgeInsets.zero,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Role Filter Chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildRoleFilterChip('ALL', 'Tất cả', c),
                      const SizedBox(width: 6),
                      _buildRoleFilterChip('admin', 'Admin', c),
                      const SizedBox(width: 6),
                      _buildRoleFilterChip('kythuat', 'Kỹ thuật', c),
                      const SizedBox(width: 6),
                      _buildRoleFilterChip('thukho', 'Thủ kho', c),
                      const SizedBox(width: 6),
                      _buildRoleFilterChip('handheld', 'Cầm tay', c),
                      const SizedBox(width: 6),
                      _buildRoleFilterChip('seller', 'Seller', c),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                // Status Filter Dropdown
                Container(
                  height: 38,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: c.bgCardElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedStatusFilter,
                      dropdownColor: c.bgCard,
                      style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                      items: const [
                        DropdownMenuItem(value: 'ALL', child: Text('Tất cả trạng thái')),
                        DropdownMenuItem(value: 'ACTIVE', child: Text('Đang hoạt động')),
                        DropdownMenuItem(value: 'INACTIVE', child: Text('Tạm khóa')),
                      ],
                      onChanged: (val) {
                        if (val != null) setState(() => _selectedStatusFilter = val);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // User Table / Cards Content
          Expanded(
            child: filteredUsers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.person_search_rounded, color: c.textMuted, size: 54),
                        const SizedBox(height: 12),
                        Text(
                          'Không tìm thấy tài khoản nhân viên nào',
                          style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Hãy thử thay đổi từ khóa tìm kiếm hoặc bấm "+ CẤP TÀI KHOẢN MỚI"',
                          style: TextStyle(color: c.textMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: filteredUsers.length,
                    itemBuilder: (context, idx) {
                      final user = filteredUsers[idx];
                      final roleColor = _getRoleColor(user.role, c);
                      final isCurrentLogged = _auth.currentUser?.userId == user.userId;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: c.bgCard,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isCurrentLogged ? c.rfidCyan : c.border, width: isCurrentLogged ? 1.5 : 1),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.03),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            // Avatar
                            Container(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: roleColor.withValues(alpha: 0.18),
                                border: Border.all(color: roleColor, width: 1.5),
                              ),
                              child: Center(
                                child: Text(
                                  user.fullName.isNotEmpty ? user.fullName.substring(0, 1).toUpperCase() : 'U',
                                  style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),

                            // User Info
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Flexible(
                                        child: Text(
                                          user.fullName,
                                          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14.5),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (isCurrentLogged)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: c.rfidCyan.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: c.rfidCyan, width: 0.8),
                                          ),
                                          child: Text('BẠN', style: TextStyle(color: c.rfidCyan, fontSize: 9, fontWeight: FontWeight.bold)),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '@${user.username}',
                                    style: TextStyle(color: c.rfidCyan, fontSize: 12, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),

                            // Role Badge & Description
                            Expanded(
                              flex: 3,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: roleColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: roleColor, width: 1),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(_getRoleIcon(user.role), color: roleColor, size: 14),
                                        const SizedBox(width: 6),
                                        Text(
                                          user.rolePermission.name,
                                          style: TextStyle(color: roleColor, fontWeight: FontWeight.bold, fontSize: 11.5),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    user.canConfigureHardware
                                        ? '⚙ Quyền hiệu chỉnh thông số máy & Anten UHF'
                                        : (user.rolePermission.canManageUsers
                                            ? '🛡 Quyền cấp & quản trị tài khoản'
                                            : '📦 Nghiệp vụ kho vận & quét RFID'),
                                    style: TextStyle(color: c.textMuted, fontSize: 10.5),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),

                            // Contact info
                            Expanded(
                              flex: 2,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(Icons.email_outlined, size: 13, color: c.textMuted),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          user.email ?? 'Chưa cài đặt',
                                          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Row(
                                    children: [
                                      Icon(Icons.phone_outlined, size: 13, color: c.textMuted),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          user.phone ?? 'Chưa cài đặt',
                                          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            // Status Active Switch
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: user.isActive ? c.successEmerald.withValues(alpha: 0.12) : c.errorCoral.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: user.isActive ? c.successEmerald : c.errorCoral, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: user.isActive ? c.successEmerald : c.errorCoral,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    user.isActive ? 'Đang hoạt động' : 'Tạm khóa',
                                    style: TextStyle(
                                      color: user.isActive ? c.successEmerald : c.errorCoral,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),

                            // Actions
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Tooltip(
                                  message: 'Đặt lại mật khẩu',
                                  child: IconButton(
                                    icon: const Icon(Icons.key_rounded, size: 18),
                                    color: const Color(0xFFF59E0B),
                                    onPressed: () => _showResetPasswordDialog(context, user, c),
                                  ),
                                ),
                                Tooltip(
                                  message: 'Chỉnh sửa tài khoản',
                                  child: IconButton(
                                    icon: const Icon(Icons.edit_outlined, size: 18),
                                    color: c.rfidCyan,
                                    onPressed: () => _showEditUserDialog(context, user, c),
                                  ),
                                ),
                                Tooltip(
                                  message: user.isActive ? 'Khóa tài khoản này' : 'Mở khóa tài khoản này',
                                  child: IconButton(
                                    icon: Icon(user.isActive ? Icons.lock_outline_rounded : Icons.lock_open_rounded, size: 18),
                                    color: user.isActive ? const Color(0xFFF59E0B) : c.successEmerald,
                                    onPressed: () async {
                                      if (isCurrentLogged) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(backgroundColor: c.errorCoral, content: const Text('Không thể tự khóa tài khoản của chính mình!')),
                                        );
                                        return;
                                      }
                                      await _auth.adminToggleUserActive(user);
                                    },
                                  ),
                                ),
                                Tooltip(
                                  message: 'Xóa tài khoản',
                                  child: IconButton(
                                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                                    color: c.errorCoral,
                                    onPressed: isCurrentLogged ? null : () => _confirmDeleteUser(context, user, c),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRoleFilterChip(String code, String label, EyeCareColors c) {
    final isSelected = _selectedRoleFilter.toLowerCase() == code.toLowerCase();
    final roleColor = code == 'ALL' ? c.rfidCyan : _getRoleColor(code, c);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() => _selectedRoleFilter = code),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? roleColor.withValues(alpha: 0.2) : c.bgCardElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isSelected ? roleColor : c.border, width: isSelected ? 1.3 : 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? roleColor : c.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
