import 'package:flutter/material.dart';
import 'desktop_goods_receive_view.dart';
import 'desktop_goods_delivery_view.dart';
import 'desktop_inventory_view.dart';
import 'desktop_lookup_view.dart';
import 'desktop_uhf_studio_view.dart';
import '../storage_screen.dart';

class DesktopMainLayout extends StatefulWidget {
  const DesktopMainLayout({super.key});

  @override
  State<DesktopMainLayout> createState() => _DesktopMainLayoutState();
}

class _DesktopMainLayoutState extends State<DesktopMainLayout> {
  int _selectedMenuIndex = 0;

  final List<Widget> _views = const [
    DesktopGoodsReceiveView(), // 0: Goods Receive
    DesktopGoodsDeliveryView(), // 1: Goods Delivery
    StorageScreen(), // 2: Goods Transfer / Storage
    DesktopInventoryView(), // 3: Inventory
    DesktopLookupView(), // 4: Lookup
    DesktopUhfStudioView(), // 5: UHF Reader Studio (Hopeland SDK & Fixed Reader)
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 900;
          final content = SizedBox(
            width: isNarrow ? 960 : constraints.maxWidth,
            child: Row(
              children: [
                // Sidebar matching PDF Page 6 & 8
                _buildSidebar(),

                // Main View Content
                Expanded(
                  child: Column(
                    children: [
                      // Top Header Bar
                      _buildTopHeader(),

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

  Widget _buildSidebar() {
    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(right: BorderSide(color: Color(0xFF334155), width: 1)),
      ),
      child: Column(
        children: [
          // Company Brand Header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.warehouse, color: Color(0xFF38BDF8), size: 26),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'RFIDwarehouse',
                        style: TextStyle(
                          color: Color(0xFF38BDF8),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          letterSpacing: 1.1,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        'Hệ Thống Quản Lý Kho WMS',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
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
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'QUẢN LÝ KHO HÀNG',
                    style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
                _buildMenuItem(0, Icons.input, 'Nhập Kho', 'Nhập hàng vào kho'),
                _buildMenuItem(1, Icons.output, 'Xuất Kho', 'Xuất hàng xuất bán'),
                _buildMenuItem(2, Icons.swap_horiz, 'Chuyển Kho', 'Điều chuyển / Vị trí'),
                _buildMenuItem(3, Icons.inventory_2, 'Kiểm Kê Kho', 'Kiểm đếm & quét RFID'),
                _buildMenuItem(4, Icons.search, 'Tra Cứu Serial & Kiện', 'Tra cứu mã chip RFID'),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Text(
                    'HỆ THỐNG & ĐẦU ĐỌC',
                    style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                ),
                _buildMenuItem(5, Icons.radar, 'Đầu Đọc UHF (Studio)', 'Hopeland SDK 4.42 & Fixed Reader'),
              ],
            ),
          ),

          // User Profile Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(top: BorderSide(color: Color(0xFF334155), width: 1)),
            ),
            child: const Row(
              children: [
                CircleAvatar(
                  backgroundColor: Color(0xFF0284C7),
                  radius: 18,
                  child: Text('U1', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('User01', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text('user01@giltech.com', style: TextStyle(color: Colors.white54, fontSize: 11), overflow: TextOverflow.ellipsis),
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

  Widget _buildMenuItem(int index, IconData icon, String title, String subTitle) {
    final isSelected = _selectedMenuIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: isSelected ? const Color(0xFF0284C7).withValues(alpha: 0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => _selectedMenuIndex = index),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: isSelected ? Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.5)) : null,
            ),
            child: Row(
              children: [
                Icon(icon, color: isSelected ? const Color(0xFF38BDF8) : Colors.white54, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
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

  Widget _buildTopHeader() {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF1E293B),
        border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1)),
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
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search, color: Colors.white38, size: 18),
                  hintText: 'Tìm kiếm phiếu, hàng hóa, serial, EPC...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: const Color(0xFF0F172A),
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: Color(0xFF334155)),
                  ),
                ),
              ),
            ),
          ),

          // Actions
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.notifications_none, color: Colors.white70),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.grid_view, color: Colors.white70),
                onPressed: () {},
              ),
            ],
          ),
        ],
      ),
    );
  }
}
