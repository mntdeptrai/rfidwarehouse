import 'package:flutter/material.dart';
import '../models/wms_models.dart';
import '../services/warehouse_repository.dart';
import '../services/uhf_service.dart';
import '../widgets/hardware_status_appbar.dart';
import '../widgets/rfid_telemetry_card.dart';

class InventoryAuditScreen extends StatefulWidget {
  const InventoryAuditScreen({super.key});

  @override
  State<InventoryAuditScreen> createState() => _InventoryAuditScreenState();
}

class _InventoryAuditScreenState extends State<InventoryAuditScreen> with SingleTickerProviderStateMixin {
  final WarehouseRepository _repo = WarehouseRepository();
  InventorySession? _activeSession;
  String _selectedZone = 'Zone A';
  String? _selectedLocationCode;
  bool _isScanning = false;
  final List<String> _scannedEpcs = [];
  late TabController _varianceTabController;

  @override
  void initState() {
    super.initState();
    _varianceTabController = TabController(length: 4, vsync: this);
    UhfService().setScanMode(PdaScanMode.rfid);
  }

  @override
  void dispose() {
    _varianceTabController.dispose();
    super.dispose();
  }

  void _startNewSession() {
    final session = _repo.startInventorySession(
      zone: _selectedZone,
      locationCode: _selectedLocationCode,
    );
    setState(() {
      _activeSession = session;
      _scannedEpcs.clear();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF0284C7),
        content: Text('Đã khởi tạo Phiên kiểm kê ${session.sessionCode}!'),
      ),
    );
  }

  void _simulateHandheldScan() {
    if (_activeSession == null) return;
    setState(() {
      _isScanning = true;
    });

    Future.delayed(const Duration(milliseconds: 1000), () {
      if (!mounted) return;
      setState(() {
        _isScanning = false;

        // Mô phỏng quét:
        // Lấy hầu hết các thẻ thuộc Zone A (Khớp)
        final zoneItems = _repo.items.where((it) => it.locationId?.contains('LOC-A') ?? false).toList();
        _scannedEpcs.addAll(zoneItems.take(zoneItems.length - 1).map((e) => e.epc));

        // Thêm 1 thẻ từ Zone B (Sai vị trí)
        final zoneBItems = _repo.items.where((it) => it.locationId?.contains('LOC-B') ?? false).toList();
        if (zoneBItems.isNotEmpty) {
          _scannedEpcs.add(zoneBItems.first.epc);
        }

        // Thêm 1 thẻ lạ (Chưa khai báo)
        _scannedEpcs.add('E28011600000000000088888');

        // Xử lý đối chiếu kiểm kê
        _repo.processAuditScan(
          sessionId: _activeSession!.sessionId,
          scannedEpcs: _scannedEpcs,
        );
      });
    });
  }

  void _completeSession() {
    if (_activeSession == null) return;
    _repo.completeInventorySession(_activeSession!.sessionId, 'Quản lý kho Trần Văn B');
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Text('🎉 Đã chốt và duyệt sai lệch phiên kiểm kê thành công!'),
      ),
    );
    setState(() {
      _activeSession = null;
      _scannedEpcs.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: const HardwareStatusAppBar(title: '📋 Kiểm Kê Kho (Utouch 2)'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Tạo hoặc chọn phiên kiểm kê
            _buildSessionConfigCard(),
            const SizedBox(height: 16),

            // 2. Khu vực quét Handheld
            if (_activeSession != null) ...[
              _buildHandheldScanCard(),
              const SizedBox(height: 16),

              // 3. Bảng đối chiếu 4 Tab sai lệch
              _buildVarianceTabsCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSessionConfigCard() {
    return Container(
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
              const Expanded(
                child: Text(
                  '1. THIẾT LẬP PHẠM VI KIỂM KÊ',
                  style: TextStyle(
                    color: Color(0xFF0284C7),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_activeSession != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _activeSession!.sessionCode,
                    style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Builder(
                  builder: (context) {
                    final availableZones = _repo.locations.map((l) => l.zone).where((z) => z.isNotEmpty).toSet().toList();
                    if (availableZones.isEmpty) {
                      return TextFormField(
                        initialValue: _selectedZone,
                        style: const TextStyle(color: Color(0xFF2C251E)),
                        decoration: InputDecoration(
                          labelText: 'Nhập Khu vực (Zone)',
                          labelStyle: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 12),
                          filled: true,
                          fillColor: const Color(0xFFF4EFE6),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onChanged: (val) => _selectedZone = val.trim(),
                      );
                    }
                    return DropdownButtonFormField<String>(
                      initialValue: availableZones.contains(_selectedZone) ? _selectedZone : availableZones.first,
                      dropdownColor: const Color(0xFFE9E2D5),
                      style: const TextStyle(color: Color(0xFF2C251E)),
                      decoration: InputDecoration(
                        labelText: 'Khu vực (Zone)',
                        labelStyle: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 12),
                        filled: true,
                        fillColor: const Color(0xFFF4EFE6),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      items: availableZones.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
                      onChanged: _activeSession != null ? null : (val) {
                        if (val != null) setState(() => _selectedZone = val);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_activeSession == null)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _startNewSession,
                child: const Text(
                  'BẮT ĐẦU PHIÊN KIỂM KÊ MỚI',
                  style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHandheldScanCard() {
    return Container(
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
            children: const [
              Text(
                '2. QUÉT THẺ RFID',
                style: TextStyle(
                  color: Color(0xFF0284C7),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              Text(
                'Bấm nút quét trên thiết bị',
                style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 14),

          RfidTelemetryCard(
            uniqueTags: _scannedEpcs.toSet().length,
            totalReads: _scannedEpcs.length * 2,
            readRate: _isScanning ? 95.0 : 0.0,
            isScanning: _isScanning,
            antennaInfo: 'UHF RFID',
          ),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isScanning ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _isScanning ? null : _simulateHandheldScan,
              child: Text(
                _isScanning ? 'ĐANG QUÉT THỰC TẾ...' : 'KÍCH HOẠT QUÉT THẺ RFID',
                style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVarianceTabsCard() {
    final session = _activeSession!;
    return Container(
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
            children: const [
              Text(
                '3. ĐỐI CHIẾU & PHÂN LOẠI SAI LỆCH',
                style: TextStyle(
                  color: Color(0xFF0284C7),
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 4 Tab selector
          TabBar(
            controller: _varianceTabController,
            isScrollable: true,
            indicatorColor: const Color(0xFF0284C7),
            indicatorWeight: 3,
            labelColor: const Color(0xFF0284C7),
            unselectedLabelColor: const Color(0xFF6B5D4D),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            tabs: [
              Tab(text: '🟢 Khớp (${session.matchCount})'),
              Tab(text: '🔴 Thiếu (${session.missingCount})'),
              Tab(text: '🟡 Sai vị trí (${session.wrongLocationCount})'),
              Tab(text: '🟣 Thẻ lạ (${session.unknownEpcCount})'),
            ],
          ),
          const SizedBox(height: 12),

          SizedBox(
            height: 220,
            child: TabBarView(
              controller: _varianceTabController,
              children: [
                _buildVarianceItemList(InventoryVarianceType.match),
                _buildVarianceItemList(InventoryVarianceType.missing),
                _buildVarianceItemList(InventoryVarianceType.wrongLocation),
                _buildVarianceItemList(InventoryVarianceType.unknownEpc),
              ],
            ),
          ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: session.results.isNotEmpty ? _completeSession : null,
              child: const Text(
                'PHÊ DUYỆT & CHỐT PHIÊN KIỂM KÊ',
                style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVarianceItemList(InventoryVarianceType type) {
    final filtered = _activeSession!.results.where((r) => r.resultType == type).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'Không có bản ghi nào trong mục ${type.label}',
          style: const TextStyle(color: Color(0xFF8F8070), fontSize: 12),
        ),
      );
    }

    return ListView.builder(
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final item = filtered[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFF4EFE6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Color(type.colorValue).withValues(alpha: 0.4), width: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.sku != null ? '${item.sku} - ${item.productName}' : 'Thẻ lạ',
                      style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'EPC: ${item.epc}',
                      style: const TextStyle(color: Color(0xFF6B5D4D), fontFamily: 'Courier', fontSize: 10),
                    ),
                  ],
                ),
              ),
              Text(
                item.actualLocation ?? 'N/A',
                style: TextStyle(color: Color(type.colorValue), fontWeight: FontWeight.bold, fontSize: 11),
              ),
            ],
          ),
        );
      },
    );
  }
}
