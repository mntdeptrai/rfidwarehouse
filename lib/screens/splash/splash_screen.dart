import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/warehouse_repository.dart';
import '../desktop_pda_wrapper.dart';

/// Màn hình chờ khởi động ứng dụng (Splash Screen)
/// - Hiển thị Logo Nhật Minh sắc nét ngay lập tức (0ms) khi mở app.
/// - Duy trì hiển thị chuẩn xác trong 1.5 giây, song song nạp CSDL hệ thống.
/// - Tự động chuyển tiếp mượt mà sang Màn hình Đăng Nhập (LoginScreen).
class SplashScreen extends StatefulWidget {
  final Duration? duration;
  final Widget? nextScreen;

  const SplashScreen({
    super.key,
    this.duration,
    this.nextScreen,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;
  bool _hasNavigated = false;

  Duration get _effectiveDuration => widget.duration ?? const Duration(milliseconds: 1500);

  @override
  void initState() {
    super.initState();
    // Nạp dữ liệu hệ thống ngầm và tự động chuyển sang Đăng Nhập sau 1.5 giây
    _loadAppDataAndProceed();
  }

  Future<void> _loadAppDataAndProceed() async {
    final startTime = DateTime.now();

    try {
      await Future.wait([
        AuthService().init(),
        WarehouseRepository().ensureInitialized(),
      ]);

      // Đảm bảo mở app luôn vào Màn hình Đăng Nhập theo yêu cầu
      await AuthService().logout();
    } catch (e) {
      debugPrint('SplashScreen data load error: $e');
    }

    // Đúng 1.5 giây hiển thị logo rồi chuyển sang đăng nhập
    final elapsed = DateTime.now().difference(startTime);
    final remaining = _effectiveDuration - elapsed;

    if (remaining > Duration.zero) {
      _timer = Timer(remaining, () {
        if (mounted) _navigateToLogin();
      });
    } else {
      if (mounted) _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    _timer?.cancel();
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    final target = widget.nextScreen ?? const DesktopPdaWrapper();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => target,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final screenWidth = media.size.width;

    // Chiều rộng logo tương thích hoàn hảo: trên PDA ~220dp, trên Desktop ~320dp
    final logoWidth = math.min(screenWidth * 0.65, 320.0);

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _navigateToLogin, // Chạm bất kỳ đâu để vào thẳng màn hình đăng nhập ngay
        child: Center(
          child: SizedBox(
            width: logoWidth,
            child: Image.asset(
              'assets/images/nhat_minh_logo.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Nhật Minh',
                      style: TextStyle(
                        fontSize: logoWidth * 0.12,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFFC0392B),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tiếp nối công nghệ',
                      style: TextStyle(
                        fontSize: logoWidth * 0.055,
                        fontStyle: FontStyle.italic,
                        color: const Color(0xFFD4AC0D),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
