import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/desktop_pda_wrapper.dart';
import 'services/database_service.dart';
import 'services/uhf_service.dart';
import 'services/supabase_sync_service.dart';
import 'services/api_service.dart';
import 'services/auth_service.dart';
import 'services/warehouse_repository.dart';
import 'theme/eye_care_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  // Xóa sạch file SQLite vật lý trên tay cầm PDA để chuyển 100% sang Supabase Cloud
  await DatabaseService.wipeHandheldSqliteDatabase();
  // Khởi tạo UHF service sớm
  UhfService().init();
  // Khởi tạo Supabase Cloud Sync & Realtime APIs
  SupabaseSyncService();
  ApiService().init();
  // Khởi tạo Auth service (phiên làm việc & tài khoản offline)
  await AuthService().init();
  // Nạp toàn bộ CSDL Pallet, vị trí, danh mục vào RAM trước khi hiển thị UI
  await WarehouseRepository().ensureInitialized();
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
          home: const DesktopPdaWrapper(),
        );
      },
    );
  }
}
