import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../theme/eye_care_theme.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _auth = AuthService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  bool _obscurePassword = true;
  bool _rememberMe = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    final success = await _auth.login(
      username: _usernameController.text,
      password: _passwordController.text,
      rememberMe: _rememberMe,
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
                child: Text('Xin chào, ${_auth.currentUser?.fullName ?? "Người dùng"}! Đăng nhập thành công.'),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _fillCredentials(String user, String pass) {
    _usernameController.text = user;
    _passwordController.text = pass;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_auth, _eyeCare]),
      builder: (context, _) {
        final c = _eyeCare.colors;

        return Scaffold(
          backgroundColor: c.bgDeep,
          body: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 440),
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
                      // Header Logo & Branding
                      Center(
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.rfidCyan.withValues(alpha: 0.15),
                            border: Border.all(color: c.rfidCyan, width: 1.5),
                          ),
                          child: Icon(Icons.sensors_rounded, color: c.rfidCyan, size: 30),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'QUẢN LÝ KHO RFID',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'UHF RFID WMS SYSTEM • ĐĂNG NHẬP',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: c.textMuted,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 22),

                      // Error message banner
                      if (_auth.authError != null) ...[
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
                                  _auth.authError!,
                                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // Username field
                      Text(
                        'Tên Đăng Nhập / Email',
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _usernameController,
                        style: TextStyle(color: c.textPrimary, fontSize: 13.5),
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          prefixIcon: Icon(Icons.person_outline_rounded, color: c.textMuted, size: 20),
                          hintText: 'Nhập tên đăng nhập hoặc email...',
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

                      // Password field
                      Text(
                        'Mật Khẩu',
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        style: TextStyle(color: c.textPrimary, fontSize: 13.5),
                        textInputAction: TextInputAction.done,
                        onSubmitted: (_) => _handleLogin(),
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
                          hintText: 'Nhập mật khẩu...',
                          hintStyle: TextStyle(color: c.textMuted, fontSize: 12.5),
                          filled: true,
                          fillColor: c.bgCardElevated,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: c.rfidCyan, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Remember Me Checkbox
                      Row(
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _rememberMe,
                              activeColor: c.rfidCyan,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                              onChanged: (val) => setState(() => _rememberMe = val ?? true),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _rememberMe = !_rememberMe),
                              child: Text(
                                'Ghi nhớ đăng nhập trên thiết bị này',
                                style: TextStyle(color: c.textSecondary, fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),

                      // Login Button
                      SizedBox(
                        height: 46,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.rfidCyan,
                            foregroundColor: c.bgDeep,
                            elevation: 0,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: _auth.isLoading ? null : _handleLogin,
                          child: _auth.isLoading
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: c.bgDeep),
                                )
                              : const Text(
                                  'ĐĂNG NHẬP HỆ THỐNG',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, letterSpacing: 0.4),
                                ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Demo quick login accounts chips
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.bgCardElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '⚡ ĐĂNG NHẬP NHANH TÀI KHOẢN MẪU:',
                              style: TextStyle(color: c.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: c.border),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    onPressed: () => _fillCredentials('admin', 'admin123'),
                                    child: Column(
                                      children: [
                                        Text('Admin', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5)),
                                        Text('admin123', style: TextStyle(color: c.textMuted, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: c.border),
                                      padding: const EdgeInsets.symmetric(vertical: 8),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    onPressed: () => _fillCredentials('thukho', '123456'),
                                    child: Column(
                                      children: [
                                        Text('Thủ kho', style: TextStyle(color: c.successEmerald, fontWeight: FontWeight.bold, fontSize: 11.5)),
                                        Text('123456', style: TextStyle(color: c.textMuted, fontSize: 10)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // Register link
                      Wrap(
                        alignment: WrapAlignment.center,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Chưa có tài khoản nhân viên? ',
                            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                          ),
                          InkWell(
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const RegisterScreen()),
                              );
                            },
                            child: Text(
                              'Đăng ký ngay',
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
