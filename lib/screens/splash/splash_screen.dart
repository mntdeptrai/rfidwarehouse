import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
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

  @override
  void initState() {
    super.initState();
    _startPreloadAndScheduleNavigation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    precacheImage(const AssetImage('assets/images/nhat_minh_logo.png'), context);
  }

  void _startPreloadAndScheduleNavigation() {
    // 1. Kích hoạt nạp CSDL hệ thống và đồng bộ hoàn toàn ngầm trong RAM (Non-blocking)
    unawaited(_preloadSystemDataInBackground());

    // 2. Chuyển tiếp ngay lập tức sang Màn hình Đăng Nhập:
    // - Nếu widget.duration được truyền (từ test suite): tuân thủ chính xác duration đó.
    // - Nếu mở app thực tế (duration == null): cho logo xuất hiện ngắn gọn 100ms
    //   để người dùng cảm nhận mượt mà, sau đó chuyển cảnh ngay sang màn hình Đăng Nhập.
    final targetDuration = widget.duration ?? const Duration(milliseconds: 100);

    _timer = Timer(targetDuration, () {
      if (mounted) _navigateToLogin();
    });
  }

  Future<void> _preloadSystemDataInBackground() async {
    try {
      // Đảm bảo mở app luôn vào Màn hình Đăng Nhập
      await AuthService().logout();
      await AuthService().init();
      await WarehouseRepository().ensureInitialized();
    } catch (e) {
      debugPrint('SplashScreen background load error: $e');
    }
  }

  void _navigateToLogin() {
    _timer?.cancel();
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    final target = widget.nextScreen ?? const DesktopPdaWrapper();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 150),
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
    final isDesktop = !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
    // Trên Mobile / PDA: Khớp chuẩn xác 100% với @mipmap/launch_logo (200x80 dp) của Android Native,
    // đảm bảo khi Flutter khởi động, logo đứng yên hoàn toàn không xê dịch hay nhảy kích thước.
    final logoWidth = isDesktop ? 300.0 : 200.0;
    final logoHeight = isDesktop ? 120.0 : 80.0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _navigateToLogin, // Chạm bất kỳ đâu để vào thẳng màn hình đăng nhập ngay
        child: Center(
          child: SizedBox(
            width: logoWidth,
            height: logoHeight,
            child: Image.asset(
              'assets/images/nhat_minh_logo.png',
              width: logoWidth,
              height: logoHeight,
              fit: BoxFit.contain,
              gaplessPlayback: true,
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
