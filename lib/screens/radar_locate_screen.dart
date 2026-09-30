import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/wms_models.dart';
import '../models/tag_info.dart';
import '../services/uhf_service.dart';
import '../services/warehouse_repository.dart';
import '../theme/eye_care_theme.dart';
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
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  ItemStatus? _statusFilter;

  Item? _targetItem;
  bool _isTracking = false;
  double _currentRssi = -90.0;
  double? _previousRssi;
  DateTime? _lastSeenTime;

  bool _soundHapticEnabled = true;
  int _lastFeedbackTimestamp = 0;

  StreamSubscription<bool>? _triggerSub;
  StreamSubscription<TagInfo>? _tagSub;
  StreamSubscription<String>? _barcodeSub;

  // Danh sách các thẻ quét được gần đây khi ở chế độ tự do
  final Map<String, TagInfo> _nearbyTags = {};

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onStateUpdate);
    _repo.addListener(_onStateUpdate);

    // Kích hoạt quyền quét cho phân hệ Định Vị / Radar sau khi build xong frame đầu
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _uhfService.enableScanning('radar_locate');
      }
    });

    // Nạp mặt hàng ban đầu nếu có initialEpc
    if (widget.initialEpc != null && widget.initialEpc!.isNotEmpty) {
      final epcUpper = widget.initialEpc!.toUpperCase();
      _targetItem = _repo.items.where(
        (it) => it.epc.toUpperCase() == epcUpper,
      ).firstOrNull;
    }

    // Lắng nghe nút bóp cò vật lý trên tay cầm PDA SEUIC UTouch 2
    _triggerSub = _uhfService.onTriggerStateChanged.listen((isPressed) {
      if (!mounted) return;
      if (isPressed) {
        if (!_isTracking) _startTracking();
      } else {
        if (_isTracking) _stopTracking();
      }
    });

    // Lắng nghe mắt đọc Laser Barcode / 2D Scanner
    _barcodeSub = _uhfService.onBarcodeRead.listen((barcode) {
      if (!mounted) return;
      final clean = barcode.trim();
      if (clean.isNotEmpty) {
        _searchCtrl.text = clean;
        setState(() {
          _searchQuery = clean.toLowerCase();
          // Tự động gán nếu tìm thấy đúng 1 item khớp mã Barcode / EPC / S/N / SKU
          final match = _repo.items.where((it) =>
              it.epc.equalsIgnoreCase(clean) ||
              it.sku.equalsIgnoreCase(clean) ||
              it.serialNumber.equalsIgnoreCase(clean)).firstOrNull;
          if (match != null) {
            _selectTargetItem(match);
          }
        });
      }
    });

    // Lắng nghe tín hiệu sóng RFID thời gian thực từ đầu đọc UHF
    _tagSub = _uhfService.onTagRead.listen((tag) {
      if (!mounted || !_isTracking) return;

      final epcUpper = tag.epc.trim().toUpperCase();
      final parsedRssi = double.tryParse(tag.rssi) ?? -65.0;

      // 1. Nếu đã chọn mục tiêu cụ thể: CHỈ LỌC DUY NHẤT MÃ EPC CỦA MỤC TIÊU (Precision Finding)
      if (_targetItem != null) {
        if (_targetItem!.epc.toUpperCase() == epcUpper) {
          _previousRssi = _currentRssi;
          _currentRssi = parsedRssi.clamp(-95.0, -25.0);
          _lastSeenTime = DateTime.now();

          _triggerPrecisionHapticAndSound(_currentRssi);

          if (mounted) setState(() {});
        }
      } else {
        // 2. Chế độ quét tự do dò tìm chip xung quanh
        _nearbyTags[epcUpper] = tag;
        _currentRssi = parsedRssi.clamp(-95.0, -25.0);
        if (mounted) setState(() {});
      }
    });
  }

  void _onStateUpdate() {
    if (mounted) setState(() {});
  }

  /// Phát nhịp rung và âm thanh dồn dập khi đến càng gần mục tiêu (Geiger Counter / AirTag Sound)
  void _triggerPrecisionHapticAndSound(double rssi) {
    if (!_soundHapticEnabled) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    // Chu kỳ phản hồi âm thanh / haptic theo cự ly
    int intervalMs = 1200;
    if (rssi >= -35.0) {
      intervalMs = 120; // Chạm đích (< 20 cm): nhịp cực dồn dập
    } else if (rssi >= -48.0) {
      intervalMs = 260; // Cự ly gần dưới 1 mét (< 1m): nhịp nhanh
    } else if (rssi >= -65.0) {
      intervalMs = 650; // Đang tiếp cận (1 - 3m)
    }

    if (now - _lastFeedbackTimestamp >= intervalMs) {
      _lastFeedbackTimestamp = now;
      if (rssi >= -35.0) {
        HapticFeedback.heavyImpact();
        SystemSound.play(SystemSoundType.click);
      } else if (rssi >= -48.0) {
        HapticFeedback.mediumImpact();
        SystemSound.play(SystemSoundType.click);
      } else {
        HapticFeedback.selectionClick();
      }
    }
  }

  @override
  void dispose() {
    _triggerSub?.cancel();
    _tagSub?.cancel();
    _barcodeSub?.cancel();
    _searchCtrl.dispose();
    _eyeCare.removeListener(_onStateUpdate);
    _repo.removeListener(_onStateUpdate);

    // Khóa và dừng quét an toàn khi rời khỏi màn hình
    _uhfService.stopInventory();
    _uhfService.disableScanning();
    super.dispose();
  }

  void _startTracking() {
    setState(() {
      _isTracking = true;
      _previousRssi = null;
      if (_targetItem != null) {
        _currentRssi = -90.0;
      }
    });
    _uhfService.startInventory();
  }

  void _stopTracking() {
    _uhfService.stopInventory();
    setState(() {
      _isTracking = false;
    });
  }

  void _selectTargetItem(Item item) {
    setState(() {
      _targetItem = item;
      _currentRssi = -90.0;
      _previousRssi = null;
      _lastSeenTime = null;
      _searchCtrl.clear();
      _searchQuery = '';
    });
  }

  void _clearTargetItem() {
    _stopTracking();
    setState(() {
      _targetItem = null;
      _currentRssi = -90.0;
      _previousRssi = null;
      _lastSeenTime = null;
      _nearbyTags.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final allItems = _repo.items;

    // Lọc danh sách theo từ khóa tìm kiếm & trạng thái
    final filteredItems = allItems.where((it) {
      if (_statusFilter != null && it.status != _statusFilter) return false;
      if (_searchQuery.isEmpty) return true;

      final q = _searchQuery;
      return it.sku.toLowerCase().contains(q) ||
          it.productName.toLowerCase().contains(q) ||
          it.epc.toLowerCase().contains(q) ||
          it.serialNumber.toLowerCase().contains(q) ||
          (it.palletId ?? '').toLowerCase().contains(q) ||
          (it.locationId ?? '').toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: HardwareStatusAppBar(
        title: '🎯 TÌM KIẾM & ĐỊNH VỊ',
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: c.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Nút bật/tắt phản hồi âm thanh & rung (Haptic / Sound)
          IconButton(
            tooltip: _soundHapticEnabled ? 'Tắt âm thanh & rung' : 'Bật âm thanh & rung',
            icon: Icon(
              _soundHapticEnabled ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: _soundHapticEnabled ? c.rfidCyan : c.textMuted,
            ),
            onPressed: () {
              setState(() => _soundHapticEnabled = !_soundHapticEnabled);
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  duration: const Duration(seconds: 1),
                  backgroundColor: c.bgCardElevated,
                  content: Text(
                    _soundHapticEnabled ? '✓ Đã bật âm thanh & rung phản hồi' : 'Đã tắt âm thanh & rung',
                    style: TextStyle(color: c.textPrimary),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Thẻ mục tiêu đang định vị (Precision Target Card)
              if (_targetItem != null) ...[
                _buildActiveTargetCard(c),
                const SizedBox(height: 14),

                // Radar Sonar Proximity Visualizer phong cách Apple AirTag
                SonarRadarWidget(
                  rssi: _currentRssi,
                  isTracking: _isTracking,
                  targetEpc: _targetItem!.epc,
                  productName: _targetItem!.productName,
                  sku: _targetItem!.sku,
                  locationDisplay: _getLocationDisplay(_targetItem!),
                  previousRssi: _previousRssi,
                ),
                const SizedBox(height: 16),

                // Nút điều khiển BẬT / DỪNG quét định vị
                _buildTrackingControlButton(c),
                const SizedBox(height: 14),
              ] else ...[
                // Banner hướng dẫn tìm kiếm theo mã
                _buildSearchGuideBanner(c),
                const SizedBox(height: 12),

                // Thanh tìm kiếm đa năng theo mã SKU, EPC, Serial, Tên
                _buildSearchInputCard(c),
                const SizedBox(height: 12),

                // Danh sách kết quả tìm kiếm hàng hóa thực tế
                _buildSearchResultsSection(filteredItems, c),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Banner hướng dẫn tìm kiếm theo mã
  Widget _buildSearchGuideBanner(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.rfidCyan.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.track_changes_rounded, color: c.rfidCyan, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ĐỊNH VỊ CHÍNH XÁC (AIRTAG / FIND MY)',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Nhập mã SKU, Serial hoặc EPC bên dưới để bắt đầu dò sóng định vị thẻ RFID.',
                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ô tìm kiếm mã hàng hóa
  Widget _buildSearchInputCard(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            onChanged: (val) => setState(() => _searchQuery = val.trim().toLowerCase()),
            style: TextStyle(color: c.textPrimary, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: 'Nhập SKU, S/N, EPC, vị trí kệ hoặc tên SP...',
              hintStyle: TextStyle(color: c.textMuted, fontSize: 12.5),
              prefixIcon: Icon(Icons.search_rounded, color: c.rfidCyan, size: 20),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.clear_rounded, color: c.textMuted, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _searchQuery = '');
                      },
                    ),
                  // Nút kích hoạt mắt đọc Laser Barcode trên PDA
                  IconButton(
                    tooltip: 'Quét Barcode / QR',
                    icon: Icon(Icons.qr_code_scanner_rounded, color: c.rfidCyan, size: 20),
                    onPressed: () {
                      _uhfService.pushScanMode(PdaScanMode.barcode);
                      ScaffoldMessenger.of(context).hideCurrentSnackBar();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          duration: const Duration(seconds: 2),
                          backgroundColor: c.bgCardElevated,
                          content: Text('Bóp cò súng PDA để đọc Barcode/QR tìm kiếm...', style: TextStyle(color: c.textPrimary)),
                        ),
                      );
                    },
                  ),
                ],
              ),
              filled: true,
              fillColor: c.bgDeep,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: c.border),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Bộ lọc trạng thái nhanh
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildStatusFilterChip('Tất cả', null, c),
                const SizedBox(width: 6),
                _buildStatusFilterChip('Đang lưu kho', ItemStatus.inStock, c),
                const SizedBox(width: 6),
                _buildStatusFilterChip('Chờ cất kệ', ItemStatus.waitingPutaway, c),
                const SizedBox(width: 6),
                _buildStatusFilterChip('Đã xuất', ItemStatus.out, c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilterChip(String label, ItemStatus? status, EyeCareColors c) {
    final isSelected = _statusFilter == status;
    return InkWell(
      onTap: () => setState(() => _statusFilter = status),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan : c.bgDeep,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? c.rfidCyan : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : c.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  /// Danh sách sản phẩm kết quả tìm kiếm thực tế
  Widget _buildSearchResultsSection(List<Item> items, EyeCareColors c) {
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Column(
          children: [
            Icon(Icons.search_off_rounded, color: c.textMuted, size: 36),
            const SizedBox(height: 8),
            Text(
              'Không tìm thấy mặt hàng phù hợp với từ khóa.',
              style: TextStyle(color: c.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final displayItems = items.take(30).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'KẾT QUẢ TÌM THẤY (${items.length})',
                style: TextStyle(
                  color: c.rfidCyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  letterSpacing: 0.4,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Chạm để định vị',
              style: TextStyle(color: c.textMuted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 8),

        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: displayItems.length,
          itemBuilder: (context, idx) {
            final it = displayItems[idx];
            final locStr = _getLocationDisplay(it);

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              color: c.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: c.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            it.productName,
                            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: it.status == ItemStatus.out
                                ? Colors.grey.withValues(alpha: 0.15)
                                : c.successEmerald.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            it.status.label,
                            style: TextStyle(
                              color: it.status == ItemStatus.out ? Colors.grey : c.successEmerald,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text('SKU: ${it.sku}', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
                        if (it.serialNumber.isNotEmpty)
                          Text('S/N: ${it.serialNumber}', style: TextStyle(color: c.textSecondary, fontSize: 11, fontFamily: 'monospace')),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('EPC: ${it.epc}', style: TextStyle(color: c.textMuted, fontSize: 10.5, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, size: 13, color: it.status == ItemStatus.out ? Colors.grey : c.warningAmber),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            locStr,
                            style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.rfidCyan,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.near_me_rounded, size: 14, color: Colors.white),
                          label: const Text('ĐỊNH VỊ', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                          onPressed: () => _selectTargetItem(it),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Thẻ thông tin mục tiêu đang định vị
  Widget _buildActiveTargetCard(EyeCareColors c) {
    final it = _targetItem!;
    final locStr = _getLocationDisplay(it);
    final pallet = _repo.findPalletFast(it.palletId);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.rfidCyan, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: c.rfidCyan.withValues(alpha: 0.12),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  it.productName,
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.rfidCyan,
                  side: BorderSide(color: c.rfidCyan),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                label: const Text('ĐỔI MÃ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: _clearTargetItem,
              ),
            ],
          ),
          const SizedBox(height: 4),

          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: c.rfidCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('SKU: ${it.sku}', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
              ),
              if (it.serialNumber.isNotEmpty)
                Text('S/N: ${it.serialNumber}', style: TextStyle(color: c.textSecondary, fontSize: 11, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(height: 6),

          Text(
            'Mã EPC: ${it.epc}',
            style: TextStyle(color: c.textMuted, fontSize: 11, fontFamily: 'monospace'),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Divider(color: c.border, height: 1),
          const SizedBox(height: 8),

          Row(
            children: [
              Icon(Icons.location_on_rounded, size: 15, color: c.warningAmber),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Vị trí hệ thống: $locStr',
                  style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (pallet != null) ...[
                const SizedBox(width: 6),
                Text(
                  'Pallet: ${pallet.palletCode}',
                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  /// Nút bấm điều khiển Quét Định Vị
  Widget _buildTrackingControlButton(EyeCareColors c) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: _isTracking ? c.errorCoral : c.successEmerald,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: _isTracking ? 2 : 1,
        ),
        icon: Icon(_isTracking ? Icons.stop_circle_rounded : Icons.radar_rounded, color: Colors.white, size: 22),
        label: Text(
          _isTracking ? 'DỪNG QUÉT ĐỊNH VỊ' : 'BẬT QUÉT ĐỊNH VỊ (BÓP CÒ SÚNG)',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
        ),
        onPressed: _isTracking ? _stopTracking : _startTracking,
      ),
    );
  }

  String _getLocationDisplay(Item item) {
    if (item.status == ItemStatus.out) return 'ĐÃ XUẤT KHO';
    final pallet = _repo.findPalletFast(item.palletId);
    final loc = item.locationId != null
        ? _repo.findLocationFast(item.locationId)
        : (pallet != null ? _repo.findLocationFast(pallet.locationId) : null);

    return loc?.displayName ?? (loc?.locationCode ?? (item.locationId ?? 'Chưa xác định kệ'));
  }
}

extension _StringExtension on String {
  bool equalsIgnoreCase(String other) => toLowerCase() == other.toLowerCase();
}
