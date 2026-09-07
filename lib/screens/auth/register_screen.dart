import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/eye_care_theme.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _fullNameController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();

  final AuthService _auth = AuthService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  String _selectedRole = 'operator';
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _localError;

  final List<Map<String, String>> _roles = [
    {'code': 'operator', 'label': 'Thủ Kho / Nhân Viên Quét (Operator)'},
    {'code': 'manager', 'label': 'Quản Lý Kho (Manager)'},
    {'code': 'admin', 'label': 'Quản Trị Viên (Admin)'},
    {'code': 'forklift', 'label': 'Lái Xe Nâng (Forklift Operator)'},
  ];

  @override
  void dispose() {
    _fullNameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    setState(() => _localError = null);

    final fullName = _fullNameController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    final confirm = _confirmPasswordController.text.trim();

    if (fullName.isEmpty) {
      setState(() => _localError = 'Vui lòng nhập họ và tên nhân viên.');
      return;
    }

    if (username.length < 3) {
      setState(() => _localError = 'Tên đăng nhập phải có ít nhất 3 ký tự.');
      return;
    }

    if (password.length < 6) {
      setState(() => _localError = 'Mật khẩu phải có tối thiểu 6 ký tự.');
      return;
    }

    if (password != confirm) {
      setState(() => _localError = 'Mật khẩu xác nhận không khớp.');
      return;
    }

    FocusScope.of(context).unfocus();

    final success = await _auth.register(
      username: username,
      password: password,
      fullName: fullName,
      phone: _phoneController.text.trim(),
      email: _emailController.text.trim(),
      role: _selectedRole,
      autoLogin: true,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Đăng ký tài khoản "$username" thành công! Đã tự động đăng nhập.'),
              ),
            ],
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_auth, _eyeCare]),
      builder: (context, _) {
        final c = _eyeCare.colors;
        final errorMsg = _localError ?? _auth.authError;

        return Scaffold(
          backgroundColor: c.bgDeep,
          appBar: AppBar(
            backgroundColor: c.bgDeep,
            elevation: 0,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: c.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'ĐĂNG KÝ TÀI KHOẢN',
              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 480),
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: c.bgCard,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: c.border, width: 1.2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Subtitle
                      Text(
                        'Tạo tài khoản nhân viên kho mới để truy cập hệ thống WMS và đồng bộ thiết bị PDA.',
                        style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                      ),
                      const SizedBox(height: 18),

                      // Error message banner
                      if (errorMsg != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMsg,
                                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Full Name
                      Text('Họ và Tên Nhân Viên *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _fullNameController,
                        style: TextStyle(color: c.textPrimary, fontSize: 13.5),
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.badge_outlined, color: c.textMuted, size: 20),
                          hintText: 'Ví dụ: Nguyễn Văn A',
                          hintStyle: TextStyle(color: c.textMuted, fontSize: 12.5),
                          filled: true,
                          fillColor: c.bgCardElevated,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.rfidCyan, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Username
                      Text('Tên Đăng Nhập *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _usernameController,
                        style: TextStyle(color: c.textPrimary, fontSize: 13.5),
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.person_outline_rounded, color: c.textMuted, size: 20),
                          hintText: 'Tối thiểu 3 ký tự (chữ hoặc số)...',
                          hintStyle: TextStyle(color: c.textMuted, fontSize: 12.5),
                          filled: true,
                          fillColor: c.bgCardElevated,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.rfidCyan, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Role selection dropdown
                      Text('Vai Trò / Vị Trí Công Việc *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        initialValue: _selectedRole,
                        dropdownColor: c.bgCardElevated,
                        style: TextStyle(color: c.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.manage_accounts_outlined, color: c.textMuted, size: 20),
                          filled: true,
                          fillColor: c.bgCardElevated,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                        ),
                        items: _roles.map((r) => DropdownMenuItem<String>(
                          value: r['code'],
                          child: Text(r['label']!),
                        )).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedRole = val);
                        },
                      ),
                      const SizedBox(height: 14),

                      // Password
                      Text('Mật Khẩu *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: TextStyle(color: c.textPrimary, fontSize: 13.5),
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.lock_outline_rounded, color: c.textMuted, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: c.textMuted,
                              size: 19,
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                          hintText: 'Tối thiểu 6 ký tự...',
                          hintStyle: TextStyle(color: c.textMuted, fontSize: 12.5),
                          filled: true,
                          fillColor: c.bgCardElevated,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.rfidCyan, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Confirm Password
                      Text('Xác Nhận Mật Khẩu *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _confirmPasswordController,
                        obscureText: _obscureConfirm,
                        style: TextStyle(color: c.textPrimary, fontSize: 13.5),
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.lock_reset_rounded, color: c.textMuted, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                              color: c.textMuted,
                              size: 19,
                            ),
                            onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                          ),
                          hintText: 'Nhập lại mật khẩu để xác nhận...',
                          hintStyle: TextStyle(color: c.textMuted, fontSize: 12.5),
                          filled: true,
                          fillColor: c.bgCardElevated,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.rfidCyan, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Phone & Email Row
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Số Điện Thoại', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _phoneController,
                                  keyboardType: TextInputType.phone,
                                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                                  decoration: InputDecoration(
                                    prefixIcon: Icon(Icons.phone_outlined, color: c.textMuted, size: 18),
                                    hintText: '09xxxxxxxx',
                                    hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                                    filled: true,
                                    fillColor: c.bgCardElevated,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
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
                                Text('Email', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: _emailController,
                                  keyboardType: TextInputType.emailAddress,
                                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                                  decoration: InputDecoration(
                                    prefixIcon: Icon(Icons.email_outlined, color: c.textMuted, size: 18),
                                    hintText: 'email@kho.com',
                                    hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                                    filled: true,
                                    fillColor: c.bgCardElevated,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),

                      // Submit Register Button
                      SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.rfidCyan,
                            foregroundColor: c.bgDeep,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _auth.isLoading ? null : _handleRegister,
                          child: _auth.isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: c.bgDeep),
                                )
                              : const Text(
                                  'TẠO TÀI KHOẢN MỚI',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, letterSpacing: 0.4),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Back to login
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Đã có tài khoản? ', style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
                          InkWell(
                            onTap: () => Navigator.pop(context),
                            child: Text(
                              'Đăng nhập tại đây',
                              style: TextStyle(
                                color: c.rfidCyan,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
