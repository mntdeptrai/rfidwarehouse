import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/wms_models.dart';
import '../models/tag_info.dart';
import '../services/uhf_service.dart';
import '../services/warehouse_repository.dart';
import '../widgets/hardware_status_appbar.dart';
import '../widgets/sonar_radar_widget.dart';

class RadarLocateScreen extends StatefulWidget {
  final String? initialEpc;
  const RadarLocateScreen({super.key, this.initialEpc});

  @override
  State<RadarLocateScreen> createState() => _RadarLocateScreenState();
}

class _RadarLocateScreenState extends State<RadarLocateScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhfService = UhfService();

  String _searchQuery = '';
  Item? _targetItem;
  bool _isTracking = false;
  double _currentRssi = -85.0;
  Timer? _trackingSimulationTimer;

  StreamSubscription<bool>? _triggerSub;
  StreamSubscription<TagInfo>? _tagSub;

  @override
  void initState() {
    super.initState();
    if (widget.initialEpc != null) {
      _targetItem = _repo.items.firstWhere(
        (it) => it.epc == widget.initialEpc,
        orElse: () => _repo.items.first,
      );
    }

    // Lắng nghe sự kiện bóp cò súng vật lý trên tay cầm PDA
    _triggerSub = _uhfService.onTriggerStateChanged.listen((isPressed) {
      if (!mounted) return;
      if (isPressed) {
        setState(() {
          _isTracking = true;
          if (_targetItem == null && _repo.items.isNotEmpty) {
            _targetItem = _repo.items.first;
          }
          _currentRssi = -78.0;
        });
      } else {
        _trackingSimulationTimer?.cancel();
        setState(() {
          _isTracking = false;
        });
      }
    });

    int lastHapticTime = 0;
    Timer? radarUiTimer;

    // Lắng nghe tín hiệu sóng RSSI và nhận diện chip thời gian thực từ thiết bị UHF (Throttled)
    _tagSub = _uhfService.onTagRead.listen((tag) {
      if (!mounted) return;

      // 1. Tự động tra cứu vị trí mặt hàng ngay khi quét trúng chip RFID
      final epcUpper = tag.epc.toUpperCase();
      final matchedItem = _repo.items.cast<Item?>().firstWhere(
        (it) => it?.epc.toUpperCase() == epcUpper,
        orElse: () => null,
      );

      if (matchedItem != null) {
        final parsedRssi = double.tryParse(tag.rssi) ?? -60.0;
        _targetItem = matchedItem;
        _currentRssi = parsedRssi.clamp(-95.0, -25.0);
        if (!_recentLookups.any((it) => it.itemId == matchedItem.itemId)) {
          _recentLookups.insert(0, matchedItem);
        }

        if (radarUiTimer?.isActive != true) {
          radarUiTimer = Timer(const Duration(milliseconds: 50), () {
            if (mounted) setState(() {});
          });
        }

        // Báo rung với throttle tối thiểu 250ms
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastHapticTime > 250) {
          lastHapticTime = now;
          HapticFeedback.mediumImpact();
        }
      }
    });
  }

  final List<Item> _recentLookups = [];

  @override
  void dispose() {
    _trackingSimulationTimer?.cancel();
    _triggerSub?.cancel();
    _tagSub?.cancel();
    super.dispose();
  }

  void _startTracking() {
    setState(() {
      _isTracking = true;
      if (_targetItem == null && _repo.items.isNotEmpty) {
        _targetItem = _repo.items.first;
      }
      _currentRssi = -78.0;
    });

    _uhfService.startInventory();

    // Mô phỏng tín hiệu tăng dần khi test trên máy ảo/desktop
    _trackingSimulationTimer?.cancel();
    _trackingSimulationTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (!mounted || !_isTracking) return;
      setState(() {
        final delta = (DateTime.now().second % 4 == 0) ? 6.0 : -1.5;
        _currentRssi = (_currentRssi + delta).clamp(-88.0, -30.0);
      });
    });
  }

  void _stopTracking() {
    _trackingSimulationTimer?.cancel();
    _uhfService.stopInventory();
    setState(() {
      _isTracking = false;
    });
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: const HardwareStatusAppBar(title: '🎯 Tra Cứu Vị Trí & Định Vị'),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Banner hướng dẫn quét UHF RFID
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFE9E2D5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _uhfService.isTriggerPressed || _isTracking
                      ? const Color(0xFF10B981)
                      : const Color(0xFFC7BDAF),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _uhfService.isTriggerPressed || _isTracking
                          ? const Color(0xFF10B981).withValues(alpha: 0.2)
                          : const Color(0xFFC7BDAF),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.sensors,
                      color: _uhfService.isTriggerPressed || _isTracking
                          ? const Color(0xFF10B981)
                          : Colors.white54,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'TRA CỨU VỊ TRÍ RFID',
                                style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: _uhfService.isTriggerPressed || _isTracking
                                    ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                    : Colors.white12,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _uhfService.isTriggerPressed || _isTracking ? 'ĐANG QUÉT' : 'SẴN SÀNG',
                                style: TextStyle(
                                  color: _uhfService.isTriggerPressed || _isTracking
                                      ? const Color(0xFF10B981)
                                      : const Color(0xFF0284C7),
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Quét chip RFID -> Hệ thống sẽ hiển thị vị trí lưu kho & Pallet ngay lập tức.',
                          style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Nút quét thử trên giao diện
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isTracking ? const Color(0xFFEF4444) : const Color(0xFF0284C7),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(_isTracking ? Icons.stop : Icons.sensors, color: const Color(0xFF2C251E), size: 20),
                    onPressed: _isTracking ? _stopTracking : _startTracking,
                    label: Text(
                      _isTracking ? 'DỪNG QUÉT ĐỊNH VỊ' : 'BẬT QUÉT TÌM KIẾM (UHF RFID)',
                      style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 1. Ô tìm kiếm
            _buildSearchHeaderCard(),
            const SizedBox(height: 16),

            // 2. KẾT QUẢ VỊ TRÍ MẶT HÀNG VỪA ĐỌC
            if (_targetItem != null) ...[
              _buildTargetItemLocationCard(),
              const SizedBox(height: 16),

              // 3. Sonar Radar Proximity Visualizer
              SonarRadarWidget(
                rssi: _currentRssi,
                isTracking: _isTracking,
                targetEpc: _targetItem!.epc,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHeaderCard() {
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
          const Text(
            'TRA CỨU THỦ CÔNG THEO SKU / SERIAL / EPC',
            style: TextStyle(
              color: Color(0xFF0284C7),
              fontWeight: FontWeight.bold,
              fontSize: 13,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            decoration: InputDecoration(
              hintText: 'Nhập mã SKU, Serial hoặc EPC cần tìm...',
              hintStyle: const TextStyle(color: Color(0xFF8F8070), fontSize: 13),
              prefixIcon: const Icon(Icons.search, color: Color(0xFF0284C7)),
              filled: true,
              fillColor: const Color(0xFFF4EFE6),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            style: const TextStyle(color: Color(0xFF2C251E)),
            onChanged: (val) {
              setState(() => _searchQuery = val.trim().toLowerCase());
            },
          ),

          // Kết quả gợi ý
          if (_searchQuery.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              child: ListView(
                shrinkWrap: true,
                children: _repo.items.where((it) {
                  return it.sku.toLowerCase().contains(_searchQuery) ||
                      it.serialNumber.toLowerCase().contains(_searchQuery) ||
                      it.epc.toLowerCase().contains(_searchQuery) ||
                      it.productName.toLowerCase().contains(_searchQuery);
                }).take(5).map((it) {
                  return ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${it.sku} - ${it.productName}', style: const TextStyle(color: Color(0xFF2C251E), fontSize: 13)),
                    subtitle: Text('EPC: ${it.epc}', style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 11)),
                    trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Color(0xFF0284C7)),
                    onTap: () {
                      setState(() {
                        _targetItem = it;
                        _searchQuery = '';
                      });
                    },
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTargetItemLocationCard() {
    final item = _targetItem!;
    final loc = _repo.locations.firstWhere(
      (l) => l.locationId == item.locationId,
      orElse: () => Location(locationId: '', locationCode: 'Chưa rõ', zone: '', shelf: '', level: ''),
    );
    final pal = _repo.pallets.firstWhere(
      (p) => p.palletId == item.palletId,
      orElse: () => Pallet(palletId: '', palletCode: 'Chưa đóng pallet'),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE9E2D5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF10B981), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'VỊ TRÍ: ${loc.locationCode} (${loc.zone})',
                  style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 16),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.status.label,
                  style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${item.sku} - ${item.productName}',
            style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.w600, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4EFE6),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Kệ / Tầng:', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                    Text('${loc.shelf} • ${loc.level}', style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Mã Pallet:', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                    Text(pal.palletCode, style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Mã EPC Chip:', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                    Expanded(
                      child: Text(
                        item.epc,
                        textAlign: TextAlign.end,
                        style: const TextStyle(color: Color(0xFFA78BFA), fontFamily: 'Courier', fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Cường độ sóng (RSSI):', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                    Text(
                      '${_currentRssi.toStringAsFixed(1)} dBm',
                      style: TextStyle(
                        color: _currentRssi > -60 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
