import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash/splash_screen.dart';
import 'services/uhf_service.dart';
import 'services/supabase_sync_service.dart';
import 'services/api_service.dart';
import 'theme/eye_care_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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

  // Khởi chạy UI ngay lập tức: Màn hình chờ (SplashScreen) xuất hiện tức thì trên frame đầu tiên,
  // CSDL và phiên làm việc sẽ được nạp ngầm song song trong lúc người dùng xem logo.
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
