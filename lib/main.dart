import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash/splash_screen.dart';
import 'services/uhf_service.dart';
import 'services/supabase_sync_service.dart';
import 'services/api_service.dart';
import 'services/warehouse_repository.dart';
import 'services/auth_service.dart';
import 'theme/eye_care_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Kích hoạt giải mã Logo Nhật Minh sớm trong ImageCache, tránh chớp nháy trắng ở frame đầu
  const AssetImage('assets/images/nhat_minh_logo.png').resolve(ImageConfiguration.empty);

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  // Khởi tạo UHF service sớm (non-blocking)
  UhfService().init();
  // Khởi tạo Supabase Cloud Sync & Realtime APIs (non-blocking)
  SupabaseSyncService();
  ApiService().init();

  // Nạp trước CSDL SQLite và cấu hình vào RAM ngay lập tức (non-blocking pre-warm)
  WarehouseRepository().ensureInitialized();
  AuthService().init();

  // Khởi chạy UI ngay lập tức: Màn hình chờ (SplashScreen) xuất hiện tức thì trên frame đầu tiên
  runApp(const RfidWmsApp());
}

class RfidWmsApp extends StatelessWidget {
  const RfidWmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final eyeCare = EyeCareThemeService();

    return ListenableBuilder(
      listenable: eyeCare,
      builder: (context, _) {
        return MaterialApp(
          title: 'RFIDwarehouse',
          debugShowCheckedModeBanner: false,
          theme: eyeCare.themeData,
          home: const SplashScreen(),
        );
      },
    );
  }
}
 