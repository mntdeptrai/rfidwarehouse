import 'package:flutter/material.dart';
import 'desktop_goods_receive_view.dart';
import 'desktop_goods_delivery_view.dart';
import 'desktop_inventory_view.dart';
import 'desktop_lookup_view.dart';
import 'desktop_uhf_studio_view.dart';
import '../storage_screen.dart';
import '../../theme/eye_care_theme.dart';

class DesktopMainLayout extends StatefulWidget {
  const DesktopMainLayout({super.key});

  @override
  State<DesktopMainLayout> createState() => _DesktopMainLayoutState();
}

class _DesktopMainLayoutState extends State<DesktopMainLayout> {
  int _selectedMenuIndex = 0;
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  final List<Widget> _views = const [
    DesktopGoodsReceiveView(), // 0: Goods Receive
    DesktopGoodsDeliveryView(), // 1: Goods Delivery
    StorageScreen(), // 2: Goods Transfer / Storage
    DesktopInventoryView(), // 3: Inventory
    DesktopLookupView(), // 4: Lookup
    DesktopUhfStudioView(), // 5: UHF Reader Studio (Hopeland SDK & Fixed Reader)
  ];

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onThemeUpdate);
  }

  void _onThemeUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _eyeCare.removeListener(_onThemeUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return Scaffold(
      backgroundColor: c.bgDeep,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 900;
          final content = SizedBox(
            width: isNarrow ? 960 : constraints.maxWidth,
            child: Row(
              children: [
                // Sidebar matching PDF Page 6 & 8
                _buildSidebar(c),

                // Main View Content
                Expanded(
                  child: Column(
                    children: [
                      // Top Header Bar
                      _buildTopHeader(c),

                      // Active View
                      Expanded(
                        child: IndexedStack(
                          index: _selectedMenuIndex,
                          children: _views,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );

          if (isNarrow) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: content,
            );
          }
          return content;
        },
      ),
    );
  }

  Widget _buildSidebar(EyeCareColors c) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border(right: BorderSide(color: c.border, width: 1)),
      ),
      child: Column(
        children: [
          // Company Brand Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border, width: 1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.rfidCyan.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.warehouse, color: c.rfidCyan, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RFIDwarehouse',
                        style: TextStyle(
                          color: c.rfidCyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Hệ Thống Quản Lý Kho WMS',
                        style: TextStyle(color: c.textSecondary, fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'QUẢN LÝ KHO HÀNG',
                    style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
                _buildMenuItem(0, Icons.input, 'Nhập Kho', 'Nhập hàng vào kho', c),
                _buildMenuItem(1, Icons.output, 'Xuất Kho', 'Xuất hàng xuất bán', c),
                _buildMenuItem(2, Icons.swap_horiz, 'Chuyển Kho', 'Điều chuyển / Vị trí', c),
                _buildMenuItem(3, Icons.inventory_2, 'Kiểm Kê Kho', 'Kiểm đếm & quét RFID', c),
                _buildMenuItem(4, Icons.search, 'Tra Cứu Serial & Kiện', 'Tra cứu mã chip RFID', c),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'HỆ THỐNG & ĐẦU ĐỌC',
                    style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
                _buildMenuItem(5, Icons.radar, 'Đầu Đọc UHF (Studio)', 'Hopeland SDK 4.42 & Fixed Reader', c),
              ],
            ),
          ),

          // User Profile Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              border: Border(top: BorderSide(color: c.border, width: 1)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: c.rfidCyan,
                  radius: 18,
                  child: const Icon(Icons.desktop_windows_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Trạm RFID Desktop', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('RFID Warehouse WMS', style: TextStyle(color: c.textSecondary, fontSize: 11), overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem(int index, IconData icon, String title, String subTitle, EyeCareColors c) {
    final isSelected = _selectedMenuIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? c.rfidCyan.withValues(alpha: 0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _selectedMenuIndex = index),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: c.rfidCyan.withValues(alpha: 0.5)) : null,
            ),
            child: Row(
              children: [
                Icon(icon, color: isSelected ? c.rfidCyan : c.textMuted, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? c.rfidCyan : c.textSecondary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(EyeCareColors c) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Search box
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 380),
              height: 38,
              child: TextField(
                style: TextStyle(color: c.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  prefixIcon: Icon(Icons.search, color: c.textMuted, size: 18),
                  hintText: 'Tìm kiếm phiếu, hàng hóa, serial, EPC...',
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                  filled: true,
                  fillColor: c.bgCardElevated,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: c.border),
                  ),
                ),
              ),
            ),
          ),

          // Actions
          Row(
            children: [
              IconButton(
                icon: Icon(Icons.notifications_none, color: c.textSecondary),
                onPressed: () {},
              ),
              IconButton(
                icon: Icon(Icons.grid_view, color: c.textSecondary),
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}


