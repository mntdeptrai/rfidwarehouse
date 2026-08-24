import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/inbound_screen.dart';
import 'screens/storage_screen.dart';
import 'screens/inventory_audit_screen.dart';
import 'screens/radar_locate_screen.dart';
import 'screens/outbound_screen.dart';
import 'screens/gate_monitor_screen.dart';
import 'screens/devices_erp_screen.dart';
import 'screens/desktop_pda_wrapper.dart';
import 'services/uhf_service.dart';
import 'services/supabase_sync_service.dart';
import 'services/api_service.dart';

import 'theme/eye_care_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  // Khởi tạo UHF service sớm
  UhfService().init();
  // Khởi tạo Supabase Cloud Sync & Realtime APIs
  SupabaseSyncService();
  ApiService().init();
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

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final UhfService _uhfService = UhfService();

  final List<Widget> _screens = const [
    InboundScreen(),
    StorageScreen(),
    InventoryAuditScreen(),
    RadarLocateScreen(),
    OutboundScreen(),
    GateMonitorScreen(),
    DevicesErpScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _initUhf();
  }

  Future<void> _initUhf() async {
    await _uhfService.init();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildAppDrawer(),
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          border: Border(top: BorderSide(color: Color(0xFF334155), width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex.clamp(0, 4),
          onTap: (index) => setState(() => _currentIndex = index),
          type: BottomNavigationBarType.fixed,
          backgroundColor: const Color(0xFF0F172A),
          selectedItemColor: const Color(0xFF38BDF8),
          unselectedItemColor: Colors.white54,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.input),
              label: 'Nhập kho',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.warehouse),
              label: 'Lưu kho',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.fact_check),
              label: 'Kiểm kê',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.radar),
              label: 'Định vị',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.local_shipping),
              label: 'Xuất kho',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppDrawer() {
    return Drawer(
      backgroundColor: const Color(0xFF0F172A),
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0284C7), Color(0xFF1E293B)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: const [
                Icon(Icons.nfc, size: 36, color: Colors.white),
                SizedBox(height: 8),
                Text(
                  'RFID WMS SYSTEM',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  'Tích hợp ERP Bravo & Hardware',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          _buildDrawerItem(
            index: 0,
            icon: Icons.input,
            title: '1. Nhập Kho (Inbound)',
            subtitle: 'Lệnh nhập Bravo, Gán Pallet, Gate IN',
          ),
          _buildDrawerItem(
            index: 1,
            icon: Icons.warehouse,
            title: '2. Quản Lý Lưu Kho (Storage)',
            subtitle: 'Tồn kho SKU, Pallet, Sơ đồ Location',
          ),
          _buildDrawerItem(
            index: 2,
            icon: Icons.fact_check,
            title: '3. Kiểm Kê (Inventory Audit)',
            subtitle: 'Quét RFID, Phân loại 4 nhóm sai lệch',
          ),
          _buildDrawerItem(
            index: 3,
            icon: Icons.radar,
            title: '4. Tìm Kiếm & Định Vị Thẻ',
            subtitle: 'Sonar Radar Visualizer, Thước đo RSSI',
          ),
          _buildDrawerItem(
            index: 4,
            icon: Icons.local_shipping,
            title: '5. Xuất Kho & FIFO (Outbound)',
            subtitle: 'Gợi ý FIFO, Picking list, Gate OUT',
          ),
          const Divider(color: Color(0xFF334155)),
          _buildDrawerItem(
            index: 5,
            icon: Icons.meeting_room,
            title: '6. Kiosk RFID Gate HF340',
            subtitle: 'Cổng kiểm soát toàn màn hình PASS/FAIL',
          ),
          _buildDrawerItem(
            index: 6,
            icon: Icons.devices,
            title: '7. Thiết Bị & ERP Bravo Hub',
            subtitle: 'Quản lý Gate HF340, PDA RFID, Đồng bộ Bravo',
          ),
          const Divider(color: Color(0xFF334155)),
          ListTile(
            leading: const Icon(Icons.remove_red_eye, color: Color(0xFFF59E0B)),
            title: const Text('Chế Độ Chống Mỏi Mắt', style: TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Đang dùng: ${EyeCareThemeService().modeName}',
              style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10.5),
            ),
            trailing: const Icon(Icons.touch_app, size: 16, color: Colors.white38),
            onTap: () {
              EyeCareThemeService().toggleNextMode();
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF1E293B),
                  duration: const Duration(seconds: 1),
                  content: Text('Đã bật chế độ: ${EyeCareThemeService().modeName}'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem({
    required int index,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isSelected = _currentIndex == index;
    return ListTile(
      leading: Icon(icon, color: isSelected ? const Color(0xFF38BDF8) : Colors.white70),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? const Color(0xFF38BDF8) : Colors.white,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 13.5,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: Colors.white54, fontSize: 10.5),
      ),
      selected: isSelected,
      selectedTileColor: const Color(0xFF1E293B),
      onTap: () {
        setState(() => _currentIndex = index);
        Navigator.pop(context);
      },
    );
  }
}
