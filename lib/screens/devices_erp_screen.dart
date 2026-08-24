import 'package:flutter/material.dart';
import '../models/wms_models.dart';
import '../services/warehouse_repository.dart';
import '../services/erp_bravo_service.dart';
import '../widgets/hardware_status_appbar.dart';

class DevicesErpScreen extends StatefulWidget {
  const DevicesErpScreen({super.key});

  @override
  State<DevicesErpScreen> createState() => _DevicesErpScreenState();
}

class _DevicesErpScreenState extends State<DevicesErpScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final WarehouseRepository _repo = WarehouseRepository();
  final ErpBravoService _bravo = ErpBravoService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: const HardwareStatusAppBar(title: '📡 Thiết Bị RFID & ERP Bravo Hub'),
      body: Column(
        children: [
          Container(
            color: const Color(0xFFE9E2D5),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF0284C7),
              indicatorWeight: 3,
              labelColor: const Color(0xFF0284C7),
              unselectedLabelColor: const Color(0xFF6B5D4D),
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
              tabs: const [
                Tab(icon: Icon(Icons.devices, size: 18), text: 'Thiết Bị RFID'),
                Tab(icon: Icon(Icons.sync_alt, size: 18), text: 'Đồng Bộ ERP Bravo'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildDevicesTab(),
                _buildErpBravoTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesTab() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _repo.devices.length,
      itemBuilder: (context, index) {
        final dev = _repo.devices[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFE9E2D5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC7BDAF)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_getDeviceIcon(dev.type), color: const Color(0xFF0284C7), size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dev.name,
                      style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Cổng/IP: ${dev.ipOrPort}',
                      style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 12),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: dev.isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          dev.statusMessage,
                          style: TextStyle(
                            color: dev.isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Switch(
                value: dev.isConnected,
                activeThumbColor: const Color(0xFF10B981),
                onChanged: (val) {
                  setState(() {
                    dev.isConnected = val;
                    dev.statusMessage = val ? 'Sẵn sàng hoạt động' : 'Đã ngắt kết nối';
                  });
                },
              ),
            ],
          ),
        );
      },
    );
  }

  IconData _getDeviceIcon(DeviceType type) {
    switch (type) {
      case DeviceType.gateHf340:
        return Icons.meeting_room;
      case DeviceType.printerGx3r:
        return Icons.print;
      case DeviceType.handheldUtouch2:
        return Icons.phone_android;
      case DeviceType.desktopLjyzn105:
        return Icons.desktop_windows;
    }
  }

  Widget _buildErpBravoTab() {
    return AnimatedBuilder(
      animation: _bravo,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Server URL & Connection Status
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9E2D5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFC7BDAF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'CẤU HÌNH KẾT NỐI ERP BRAVO',
                          style: TextStyle(
                            color: Color(0xFF0284C7),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _bravo.isConnected ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _bravo.isConnected ? 'ONLINE' : 'OFFLINE',
                            style: TextStyle(
                              color: _bravo.isConnected ? const Color(0xFF10B981) : Colors.red,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Endpoint: ${_bravo.serverUrl}',
                      style: const TextStyle(color: Color(0xFF6B5D4D), fontFamily: 'Courier', fontSize: 12),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF0284C7)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => _bravo.pullInboundOrders(),
                            child: const Text('Kéo Đơn Nhập', style: TextStyle(color: Color(0xFF0284C7), fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFF6366F1)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () => _bravo.pullOutboundOrders(),
                            child: const Text('Kéo PO Xuất', style: TextStyle(color: Color(0xFF6366F1), fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Integration Logs
              const Text(
                'NHẬT KÝ TÍCH HỢP (INTEGRATION AUDIT LOG)',
                style: TextStyle(
                  color: Color(0xFF2C251E),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 10),

              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _bravo.logs.length,
                itemBuilder: (context, index) {
                  final log = _bravo.logs[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9E2D5),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: log.isSuccess ? const Color(0xFF10B981).withValues(alpha: 0.3) : Colors.red.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          log.isSuccess ? Icons.check_circle : Icons.error,
                          color: log.isSuccess ? const Color(0xFF10B981) : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                log.message,
                                style: const TextStyle(color: Color(0xFF2C251E), fontSize: 12.5, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${log.action} • ${log.timestamp.hour.toString().padLeft(2, '0')}:${log.timestamp.minute.toString().padLeft(2, '0')}:${log.timestamp.second.toString().padLeft(2, '0')}',
                                style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
