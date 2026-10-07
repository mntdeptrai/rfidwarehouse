import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/wms_models.dart';
import '../models/tag_info.dart';
import '../services/uhf_service.dart';
import '../services/warehouse_repository.dart';
import '../theme/eye_care_theme.dart';
import '../widgets/hardware_status_appbar.dart';
import '../widgets/direction_arrow_widget.dart';
import '../services/radar_spatial_tracker.dart';
import 'pda/pda_locate_tasks_screen.dart';

enum _SearchCategory { all, items, pallets }

class RadarLocateScreen extends StatefulWidget {
  final String? initialEpc;
  final LocateOrder? locateTask;
  final Item? initialItem;
  final Pallet? initialPallet;

  const RadarLocateScreen({
    super.key,
    this.initialEpc,
    this.locateTask,
    this.initialItem,
    this.initialPallet,
  });

  @override
  State<RadarLocateScreen> createState() => _RadarLocateScreenState();
}

class _RssiSample {
  final DateTime time;
  final double rssi;
  _RssiSample(this.time, this.rssi);
}

class _RadarLocateScreenState extends State<RadarLocateScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhfService = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  ItemStatus? _statusFilter;
  _SearchCategory _categoryFilter = _SearchCategory.all;

  Item? _targetItem;
  Pallet? _targetPallet;
  String? _targetRawEpc;

  bool get hasTarget =>
      _targetItem != null || _targetPallet != null || _targetRawEpc != null;

  bool _isTracking = false;
  double _currentRssi = -90.0;
  double? _previousRssi;
  DateTime? _lastSeenTime;

  // Bộ đệm tính xu hướng (Trend & Direction Gradient) và làm mượt sóng
  final List<_RssiSample> _rssiHistory = [];
  Timer? _radarTicker;
  int _packetCountInWindow = 0;
  double _readsPerSec = 0.0;
  DateTime _lastRateReset = DateTime.now();

  // Chế độ cò súng: Mặc định là Khóa dò liên tục (Toggle / Hands-Free)
  bool _continuousLockMode = true;

  bool _soundHapticEnabled = true;
  int _lastFeedbackTimestamp = 0;

  StreamSubscription<bool>? _triggerSub;
  StreamSubscription<TagInfo>? _tagSub;
  StreamSubscription<String>? _barcodeSub;

  // Ghi nhận chip khác gần nhất khi người dùng quét không khớp mã mục tiêu
  String? _lastOtherTagEpc;
  double? _lastOtherTagRssi;
  DateTime? _lastOtherTagTime;

  // Danh sách các thẻ quét được gần đây khi ở chế độ tự do
  final Map<String, TagInfo> _nearbyTags = {};

  // Bộ theo dõi không gian và hướng vector 360 độ của chip (Spatial RSSI Tracker)
  final RadarSpatialTracker _spatialTracker = RadarSpatialTracker();
  StreamSubscription<double>? _headingSub;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onStateUpdate);
    _repo.addListener(_onStateUpdate);

    // Kích hoạt nhận dữ liệu góc la bàn / con quay hồi chuyển từ máy PDA
    _uhfService.startHeadingUpdates();
    if (_uhfService.currentHeading != 0.0) {
      _spatialTracker.updateHeading(_uhfService.currentHeading);
    }
    _headingSub = _uhfService.onHeadingChanged.listen((heading) {
      if (!mounted) return;
      _spatialTracker.updateHeading(heading);
      if (_isTracking && hasTarget && mounted) {
        setState(() {});
      }
    });

    // Bắt buộc cấu hình chế độ quét sang RFID UHF và cấp quyền quét sau khi dựng widget tree
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _uhfService.setScanMode(PdaScanMode.rfid);
        _uhfService.enableScanning('radar_locate');
      }
    });

    // 1. Nạp mục tiêu ban đầu từ initialPallet hoặc initialItem
    if (widget.initialPallet != null) {
      _targetPallet = widget.initialPallet;
    } else if (widget.initialItem != null) {
      _targetItem = widget.initialItem;
    } else {
      final effectiveEpc = widget.initialEpc ?? widget.locateTask?.targetEpc;
      if (effectiveEpc != null && effectiveEpc.isNotEmpty) {
        final epcUpper = effectiveEpc.replaceAll(' ', '').trim().toUpperCase();

        // Kiểm tra xem có khớp Item nào không
        _targetItem = _repo.items.where(
          (it) => it.epc.replaceAll(' ', '').trim().toUpperCase() == epcUpper,
        ).firstOrNull;

        // Nếu không khớp Item, kiểm tra xem có khớp Pallet không
        if (_targetItem == null) {
          _targetPallet = _repo.pallets.where((p) {
            final pEpc = (p.rfidEpc ?? '').replaceAll(' ', '').trim().toUpperCase();
            final pCode = p.palletCode.replaceAll(' ', '').trim().toUpperCase();
            return pEpc == epcUpper || pCode == epcUpper;
          }).firstOrNull;
        }

        // Nếu có đơn tìm kiếm locateTask
        if (_targetItem == null && _targetPallet == null && widget.locateTask != null) {
          if (widget.locateTask!.targetPalletCode != null) {
            _targetPallet = _repo.pallets.where((p) =>
                p.palletCode.equalsIgnoreCase(widget.locateTask!.targetPalletCode!)).firstOrNull;
          }
          if (_targetPallet == null) {
            _targetItem = Item(
              itemId: 'LOCATE_${widget.locateTask!.orderId}',
              productId: widget.locateTask!.targetSku ?? 'PROD_UNKNOWN',
              sku: widget.locateTask!.targetSku ?? 'SKU_UNKNOWN',
              productName: widget.locateTask!.targetProductName ?? widget.locateTask!.title,
              serialNumber: '',
              epc: effectiveEpc,
              locationId: widget.locateTask!.expectedLocation,
              status: ItemStatus.inStock,
            );
          }
        } else if (_targetItem == null && _targetPallet == null) {
          _targetRawEpc = effectiveEpc;
        }
      } else if (widget.locateTask != null) {
        if (widget.locateTask!.targetPalletCode != null) {
          _targetPallet = _repo.pallets.where((p) =>
              p.palletCode.equalsIgnoreCase(widget.locateTask!.targetPalletCode!)).firstOrNull;
        }
        if (_targetPallet == null && widget.locateTask!.targetSku != null) {
          _targetItem = _repo.items.where((it) =>
              it.sku.equalsIgnoreCase(widget.locateTask!.targetSku!)).firstOrNull;
        }
      }
    }

    if (widget.locateTask != null && widget.locateTask!.status == LocateOrderStatus.pending) {
      _repo.updateLocateOrderStatus(widget.locateTask!.orderId, LocateOrderStatus.inProgress);
    }

    // Timer thời gian thực (100ms): Tính tốc độ gói/giây và Decay tín hiệu khi lia máy lệch hướng/xa dần
    _radarTicker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || !_isTracking) return;

      final now = DateTime.now();

      // Cập nhật tốc độ đọc (gói/giây)
      final secElapsed = now.difference(_lastRateReset).inMilliseconds;
      if (secElapsed >= 1000) {
        _readsPerSec = (_packetCountInWindow * 1000.0) / secElapsed;
        _packetCountInWindow = 0;
        _lastRateReset = now;
      }

      // Xử lý Signal Decay khi súng lia lệch khỏi thẻ (không bắt được gói tin mới)
      if (hasTarget && _lastSeenTime != null) {
        final timeSinceLastSeen = now.difference(_lastSeenTime!).inMilliseconds;

        // Nếu quá 2200ms không có gói tin mới: tín hiệu giảm dần rất chậm (0.4 dBm / 100ms)
        // Cho phép người dùng bước đi và lia súng ở cự ly xa mà không bị tụt mất sóng ngay
        if (timeSinceLastSeen > 2200) {
          _spatialTracker.decayWithoutSignal();
          if (_currentRssi > -90.0) {
            _currentRssi = (_currentRssi - 0.4).clamp(-90.0, -25.0);
            if (mounted) setState(() {});
          }
        }

        // Nếu quá 6500ms không nhận thêm tín hiệu: xem như mất dấu sóng
        if (timeSinceLastSeen > 6500) {
          _spatialTracker.reset();
          if (_currentRssi != -90.0 || _previousRssi != null) {
            _currentRssi = -90.0;
            _previousRssi = null;
            _rssiHistory.clear();
            if (mounted) setState(() {});
          }
        }
      }
    });

    // Lắng nghe nút bóp cò vật lý trên tay cầm PDA SEUIC UTouch 2
    _triggerSub = _uhfService.onTriggerStateChanged.listen((isPressed) {
      if (!mounted) return;
      if (_continuousLockMode) {
        // Chế độ rảnh tay (Toggle): Bóp cò 1 lần -> Bắt đầu dò liên tục; bóp lần nữa -> Dừng
        if (isPressed) {
          if (!_isTracking) {
            _startTracking();
            HapticFeedback.mediumImpact();
          } else {
            _stopTracking();
            HapticFeedback.selectionClick();
          }
        }
      } else {
        // Chế độ bóp giữ (Hold): Bóp giữ để quét, nhả ra thì dừng
        if (isPressed) {
          if (!_isTracking) _startTracking();
        } else {
          if (_isTracking) _stopTracking();
        }
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

          // 1. Thử khớp mã Pallet
          final matchPallet = _repo.pallets.where((p) =>
              p.palletCode.equalsIgnoreCase(clean) ||
              (p.rfidEpc ?? '').equalsIgnoreCase(clean)).firstOrNull;
          if (matchPallet != null) {
            _selectTargetPallet(matchPallet);
            return;
          }

          // 2. Thử khớp mã Item
          final matchItem = _repo.items.where((it) =>
              it.epc.equalsIgnoreCase(clean) ||
              it.sku.equalsIgnoreCase(clean) ||
              it.serialNumber.equalsIgnoreCase(clean)).firstOrNull;
          if (matchItem != null) {
            _selectTargetItem(matchItem);
          }
        });
      }
    });

    // Lắng nghe tín hiệu sóng RFID thời gian thực từ đầu đọc UHF
    _tagSub = _uhfService.onTagRead.listen((tag) {
      if (!mounted || !_isTracking) return;

      final epcUpper = tag.epc.replaceAll(' ', '').trim().toUpperCase();
      final parsedRssi = double.tryParse(tag.rssi) ?? -65.0;
      final now = DateTime.now();

      bool isMatched = false;

      // 1. Kiểm tra khớp Mục Tiêu Item
      if (_targetItem != null) {
        final targetClean = _targetItem!.epc.replaceAll(' ', '').trim().toUpperCase();
        isMatched = epcUpper == targetClean ||
            (targetClean.length >= 8 && epcUpper.contains(targetClean)) ||
            (epcUpper.length >= 8 && targetClean.contains(epcUpper));
      }
      // 2. Kiểm tra khớp Mục Tiêu Pallet (Khớp mã thẻ Pallet HOẶC bất kỳ thẻ hàng nào trên Pallet)
      else if (_targetPallet != null) {
        final palletEpc = (_targetPallet!.rfidEpc ?? '').replaceAll(' ', '').trim().toUpperCase();
        if (palletEpc.isNotEmpty &&
            (epcUpper == palletEpc ||
             (palletEpc.length >= 8 && epcUpper.contains(palletEpc)) ||
             (epcUpper.length >= 8 && palletEpc.contains(epcUpper)))) {
          isMatched = true;
        } else {
          // Kiểm tra xem chip đọc được có nằm trong danh sách hàng hóa của pallet này không
          final itemsOnPallet = _repo.items.where(
            (it) => it.palletId == _targetPallet!.palletId && it.status == ItemStatus.inStock,
          );
          for (final it in itemsOnPallet) {
            final itClean = it.epc.replaceAll(' ', '').trim().toUpperCase();
            if (itClean.isNotEmpty &&
                (epcUpper == itClean ||
                 (itClean.length >= 8 && epcUpper.contains(itClean)) ||
                 (epcUpper.length >= 8 && itClean.contains(epcUpper)))) {
              isMatched = true;
              break;
            }
          }
        }
      }
      // 3. Khớp mã EPC tự do
      else if (_targetRawEpc != null) {
        final rawClean = _targetRawEpc!.replaceAll(' ', '').trim().toUpperCase();
        isMatched = epcUpper == rawClean ||
            (rawClean.length >= 8 && epcUpper.contains(rawClean)) ||
            (epcUpper.length >= 8 && rawClean.contains(epcUpper));
      }

      if (hasTarget) {
        if (isMatched) {
          _lastSeenTime = now;
          _packetCountInWindow++;
          _spatialTracker.recordTagSample(parsedRssi, time: now);

          final rawRssi = parsedRssi.clamp(-90.0, -25.0);

          // Làm mượt tín hiệu qua hàm mũ (Exponential Moving Average) để khử nhiễu phản xạ
          if (_currentRssi <= -88.0) {
            _currentRssi = rawRssi;
          } else {
            _currentRssi = (_currentRssi * 0.55) + (rawRssi * 0.45);
          }

          // Cập nhật lịch sử mẫu cửa sổ trượt
          _rssiHistory.add(_RssiSample(now, _currentRssi));
          _rssiHistory.removeWhere((s) => now.difference(s.time).inMilliseconds > 1200);

          // Lấy mốc RSSI từ 350ms - 750ms trước làm baseline để tính xu hướng lia súng
          final pastSamples = _rssiHistory.where((s) {
            final age = now.difference(s.time).inMilliseconds;
            return age >= 350 && age <= 750;
          }).toList();

          if (pastSamples.isNotEmpty) {
            _previousRssi = pastSamples.first.rssi;
          } else if (_rssiHistory.length > 1) {
            _previousRssi ??= _rssiHistory.first.rssi;
          }

          _triggerPrecisionHapticAndSound(_currentRssi);

          if (mounted) setState(() {});
        } else {
          // Ghi nhận chip khác gần đây khi không khớp mã đang tìm
          _lastOtherTagEpc = epcUpper;
          _lastOtherTagRssi = parsedRssi;
          _lastOtherTagTime = now;
          if (mounted) setState(() {});
        }
      } else {
        // Chế độ quét tự do dò tìm chip xung quanh
        _nearbyTags[epcUpper] = tag;
        _currentRssi = parsedRssi.clamp(-90.0, -25.0);
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
    _radarTicker?.cancel();
    _triggerSub?.cancel();
    _tagSub?.cancel();
    _barcodeSub?.cancel();
    _headingSub?.cancel();
    _uhfService.stopHeadingUpdates();
    _searchCtrl.dispose();
    _eyeCare.removeListener(_onStateUpdate);
    _repo.removeListener(_onStateUpdate);

    // Khóa và dừng quét an toàn khi rời khỏi màn hình
    _uhfService.stopInventory();
    _uhfService.disableScanning();
    super.dispose();
  }

  void _startTracking() {
    _uhfService.setScanMode(PdaScanMode.rfid);
    _uhfService.enableScanning('radar_locate');
    setState(() {
      _isTracking = true;
      _previousRssi = null;
      _rssiHistory.clear();
      _spatialTracker.reset();
      _packetCountInWindow = 0;
      _readsPerSec = 0.0;
      _lastRateReset = DateTime.now();
      _lastOtherTagEpc = null;
      _lastOtherTagRssi = null;
      _lastOtherTagTime = null;
      if (hasTarget) {
        _currentRssi = -90.0;
      }
    });
    _uhfService.startInventory();
  }

  void _stopTracking() {
    _uhfService.stopInventory();
    setState(() {
      _isTracking = false;
      _readsPerSec = 0.0;
    });
  }

  void _selectTargetItem(Item item) {
    setState(() {
      _targetItem = item;
      _targetPallet = null;
      _targetRawEpc = null;
      _currentRssi = -90.0;
      _previousRssi = null;
      _lastSeenTime = null;
      _rssiHistory.clear();
      _spatialTracker.reset();
      _lastOtherTagEpc = null;
      _lastOtherTagRssi = null;
      _lastOtherTagTime = null;
      _searchCtrl.clear();
      _searchQuery = '';
    });
  }

  void _selectTargetPallet(Pallet pallet) {
    setState(() {
      _targetPallet = pallet;
      _targetItem = null;
      _targetRawEpc = null;
      _currentRssi = -90.0;
      _previousRssi = null;
      _lastSeenTime = null;
      _rssiHistory.clear();
      _spatialTracker.reset();
      _lastOtherTagEpc = null;
      _lastOtherTagRssi = null;
      _lastOtherTagTime = null;
      _searchCtrl.clear();
      _searchQuery = '';
    });
  }

  void _clearTarget() {
    _stopTracking();
    setState(() {
      _targetItem = null;
      _targetPallet = null;
      _targetRawEpc = null;
      _currentRssi = -90.0;
      _previousRssi = null;
      _lastSeenTime = null;
      _rssiHistory.clear();
      _nearbyTags.clear();
      _lastOtherTagEpc = null;
      _lastOtherTagRssi = null;
      _lastOtherTagTime = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final allItems = _repo.items;
    final allPallets = _repo.pallets;

    // Lọc danh sách Mặt Hàng theo từ khóa & trạng thái
    final filteredItems = allItems.where((it) {
      if (_categoryFilter == _SearchCategory.pallets) return false;
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

    // Lọc danh sách Pallet theo từ khóa
    final filteredPallets = allPallets.where((p) {
      if (_categoryFilter == _SearchCategory.items) return false;
      if (_searchQuery.isEmpty) return true;

      final q = _searchQuery;
      return p.palletCode.toLowerCase().contains(q) ||
          (p.palletName ?? '').toLowerCase().contains(q) ||
          (p.rfidEpc ?? '').toLowerCase().contains(q) ||
          (p.locationId ?? '').toLowerCase().contains(q);
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
          // Nút mở danh sách Đơn tìm kiếm
          IconButton(
            tooltip: 'Đơn tìm kiếm RFID',
            icon: Icon(Icons.assignment_outlined, color: c.rfidCyan),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PdaLocateTasksScreen()),
              );
            },
          ),
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
              // 0. Banner Đơn Tìm Kiếm (nếu có nhiệm vụ được giao)
              if (widget.locateTask != null) ...[
                _buildLocateTaskBanner(widget.locateTask!, c),
                const SizedBox(height: 12),
              ],

              // 1. Thẻ mục tiêu đang định vị (Precision Target Card)
              if (hasTarget) ...[
                _buildActiveTargetCard(c),
                const SizedBox(height: 14),

                // Mũi tên chỉ hướng phong cách Apple AirTag + Cự ly cập nhật liên tục
                DirectionArrowWidget(
                  rssi: _currentRssi,
                  isTracking: _isTracking,
                  targetEpc: _getTargetEpcString(),
                  productName: _getTargetDisplayName(),
                  sku: _targetItem?.sku ?? _targetPallet?.palletCode,
                  locationDisplay: _getTargetLocationDisplay(),
                  previousRssi: _previousRssi,
                  readsPerSecond: _readsPerSec,
                  isPallet: _targetPallet != null,
                  targetAzimuthDeg: _spatialTracker.targetAzimuthDeg,
                  relativeAngleDeg: _spatialTracker.relativeAngleDeg,
                  hasLockedTarget: _spatialTracker.hasLockedTarget,
                ),
                const SizedBox(height: 12),

                // Thông báo hỗ trợ nếu đọc được chip khác gần máy mà không khớp mã đang tìm
                _buildOtherTagAlertBanner(c),

                // Nút điều khiển BẬT / DỪNG quét định vị
                _buildTrackingControlButton(c),
                if (widget.locateTask != null && widget.locateTask!.status != LocateOrderStatus.completed) ...[
                  const SizedBox(height: 10),
                  _buildConfirmFoundButton(c),
                ],
                const SizedBox(height: 14),
              ] else ...[
                // Banner hướng dẫn tìm kiếm theo mã
                _buildSearchGuideBanner(c),
                const SizedBox(height: 12),

                // Thanh tìm kiếm đa năng theo mã Pallet, SKU, EPC, Serial, Tên
                _buildSearchInputCard(c),
                const SizedBox(height: 12),

                // Danh sách kết quả tìm kiếm thực tế (Pallet & Mặt Hàng)
                _buildSearchResultsSection(
                  items: filteredItems,
                  pallets: filteredPallets,
                  colors: c,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getTargetEpcString() {
    if (_targetItem != null) return _targetItem!.epc;
    if (_targetPallet != null) return _targetPallet!.rfidEpc ?? _targetPallet!.palletCode;
    return _targetRawEpc ?? '';
  }

  String _getTargetDisplayName() {
    if (_targetItem != null) return _targetItem!.productName;
    if (_targetPallet != null) return _targetPallet!.displayName;
    return 'Chip RFID: ${_targetRawEpc ?? ""}';
  }

  String _getTargetLocationDisplay() {
    if (_targetItem != null) return _getLocationDisplay(_targetItem!);
    if (_targetPallet != null) {
      final loc = _repo.findLocationFast(_targetPallet!.locationId);
      return loc?.displayName ?? (loc?.locationCode ?? (_targetPallet!.locationId ?? 'Chưa xếp kệ'));
    }
    return '---';
  }

  /// Banner thông tin đơn tìm kiếm được giao cho nhân viên
  Widget _buildLocateTaskBanner(LocateOrder task, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0284C7).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF0284C7), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'ĐƠN TÌM KIẾM',
                  style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  task.orderNo,
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(task.status.colorValue).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  task.status.label,
                  style: TextStyle(color: Color(task.status.colorValue), fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Mục tiêu: ${task.title}',
            style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
          if (task.targetPalletCode != null && task.targetPalletCode!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '📦 Mã Pallet: ${task.targetPalletCode!}',
              style: TextStyle(color: c.rfidCyan, fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
          ],
          if (task.expectedLocation != null && task.expectedLocation!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '📍 Vị trí sổ sách: ${task.expectedLocation!}',
              style: TextStyle(color: c.textSecondary, fontSize: 11.5),
            ),
          ],
          if (task.notes != null && task.notes!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '💬 Ghi chú: ${task.notes!}',
              style: TextStyle(color: c.textMuted, fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],
        ],
      ),
    );
  }

  /// Nút xác nhận đã tìm thấy thẻ/pallet theo đơn tìm kiếm
  Widget _buildConfirmFoundButton(EyeCareColors c) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF10B981),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 1,
        ),
        icon: const Icon(Icons.check_circle_rounded, size: 20),
        label: const Text(
          'XÁC NHẬN ĐÃ TÌM THẤY',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
        onPressed: _showConfirmFoundDialog,
      ),
    );
  }

  void _showConfirmFoundDialog() {
    final c = _eyeCare.colors;
    final allLocations = _repo.locations;
    String selectedLocation = _targetItem?.locationId ??
        _targetPallet?.locationId ??
        widget.locateTask?.expectedLocation ??
        (allLocations.isNotEmpty ? allLocations.first.locationCode : 'LOC-A01-01');
    final notesCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
              const SizedBox(width: 10),
              Text(
                'Xác Nhận Đã Tìm Thấy',
                style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ghi nhận vị trí thực tế tìm thấy mã ${widget.locateTask?.orderNo ?? _getTargetDisplayName()}:',
                  style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                Text(
                  'Vị trí thực tế:',
                  style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: allLocations.any((l) => l.locationCode == selectedLocation || l.locationId == selectedLocation)
                      ? selectedLocation
                      : (allLocations.isNotEmpty ? allLocations.first.locationCode : null),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                  dropdownColor: c.bgCard,
                  items: allLocations.map((l) => DropdownMenuItem(
                    value: l.locationCode,
                    child: Text('${l.displayName} (${l.locationCode})', style: TextStyle(color: c.textPrimary, fontSize: 12)),
                  )).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedLocation = val);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Ghi chú kết quả (nếu có):',
                  style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: notesCtrl,
                  decoration: InputDecoration(
                    hintText: 'Ví dụ: Tìm thấy ở tầng 2, sau pallet PAL-01...',
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    isDense: true,
                  ),
                  style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () async {
                Navigator.pop(ctx);
                if (widget.locateTask != null) {
                  await _repo.completeLocateOrder(
                    widget.locateTask!.orderId,
                    foundLocation: selectedLocation,
                    notes: notesCtrl.text.trim(),
                  );
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('✓ Đã xác nhận tìm thấy ${widget.locateTask?.orderNo ?? "mục tiêu"} tại $selectedLocation'),
                      backgroundColor: const Color(0xFF10B981),
                    ),
                  );
                  Navigator.pop(context, true);
                }
              },
              child: const Text('HOÀN THÀNH ĐƠN', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
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
                  'Tìm theo mã Pallet, SKU, Serial hoặc EPC để bật định vị chỉ hướng và khoảng cách liên tục.',
                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Ô tìm kiếm mã hàng hóa & Pallet đa năng
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
              hintText: 'Nhập mã Pallet, SKU, S/N, EPC hoặc tên...',
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

          // Bộ lọc phân loại & trạng thái nhanh
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildCategoryFilterChip('Tất cả', _SearchCategory.all, c),
                const SizedBox(width: 6),
                _buildCategoryFilterChip('Sản phẩm', _SearchCategory.items, c),
                const SizedBox(width: 6),
                _buildCategoryFilterChip('Pallet', _SearchCategory.pallets, c),
                const SizedBox(width: 10),
                Container(width: 1, height: 16, color: c.border),
                const SizedBox(width: 10),
                _buildStatusFilterChip('Đang lưu kho', ItemStatus.inStock, c),
                const SizedBox(width: 6),
                _buildStatusFilterChip('Chờ cất kệ', ItemStatus.waitingPutaway, c),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterChip(String label, _SearchCategory cat, EyeCareColors c) {
    final isSelected = _categoryFilter == cat;
    return InkWell(
      onTap: () => setState(() => _categoryFilter = cat),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
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

  Widget _buildStatusFilterChip(String label, ItemStatus? status, EyeCareColors c) {
    final isSelected = _statusFilter == status;
    return InkWell(
      onTap: () => setState(() {
        _statusFilter = isSelected ? null : status;
      }),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981) : c.bgDeep,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? const Color(0xFF10B981) : c.border),
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

  /// Danh sách kết quả tìm kiếm thực tế: Hiển thị cả Pallet và Sản phẩm
  Widget _buildSearchResultsSection({
    required List<Item> items,
    required List<Pallet> pallets,
    required EyeCareColors colors,
  }) {
    final c = colors;
    final hasItems = items.isNotEmpty;
    final hasPallets = pallets.isNotEmpty;

    if (!hasItems && !hasPallets) {
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
              'Không tìm thấy thẻ hàng hoặc pallet phù hợp với từ khóa.',
              style: TextStyle(color: c.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    final displayPallets = pallets.take(15).toList();
    final displayItems = items.take(25).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. KẾT QUẢ PALLET (NẾU CÓ)
        if (hasPallets) ...[
          Row(
            children: [
              Expanded(
                child: Text(
                  'PALLET TÌM THẤY (${pallets.length})',
                  style: const TextStyle(
                    color: Color(0xFF0284C7),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.4,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Định vị Pallet',
                style: TextStyle(color: c.textMuted, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: displayPallets.length,
            itemBuilder: (context, idx) {
              final p = displayPallets[idx];
              final inStock = _repo.getInStockItemsForPallet(p.palletId, palletCode: p.palletCode, itemIds: p.itemIds);
              final locStr = p.locationId != null && p.locationId!.isNotEmpty ? p.locationId! : 'Chưa xếp kệ';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: c.bgCard,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: const Color(0xFF0284C7).withValues(alpha: 0.4)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.pallet, color: Color(0xFF0284C7), size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.displayName,
                              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '📍 $locStr · ${inStock.length} sản phẩm',
                              style: TextStyle(color: c.textSecondary, fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (p.rfidEpc != null && p.rfidEpc!.isNotEmpty)
                              Text(
                                'EPC: ${p.rfidEpc}',
                                style: TextStyle(color: c.textMuted, fontSize: 10.5, fontFamily: 'monospace'),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.near_me_rounded, size: 14),
                        label: const Text('ĐỊNH VỊ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: () => _selectTargetPallet(p),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
        ],

        // 2. KẾT QUẢ SẢN PHẨM / THẺ HÀNG
        if (hasItems) ...[
          Row(
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
      ],
    );
  }

  /// Thẻ thông tin mục tiêu đang định vị (hỗ trợ cả Pallet và Sản phẩm)
  Widget _buildActiveTargetCard(EyeCareColors c) {
    if (_targetPallet != null) {
      return _buildActivePalletTargetCard(_targetPallet!, c);
    } else if (_targetItem != null) {
      return _buildActiveItemTargetCard(_targetItem!, c);
    } else {
      return _buildActiveRawEpcCard(_targetRawEpc!, c);
    }
  }

  Widget _buildActivePalletTargetCard(Pallet pallet, EyeCareColors c) {
    final inStock = _repo.getInStockItemsForPallet(pallet.palletId, palletCode: pallet.palletCode, itemIds: pallet.itemIds);
    final loc = _repo.findLocationFast(pallet.locationId);
    final locStr = loc?.displayName ?? (loc?.locationCode ?? (pallet.locationId ?? 'Chưa xếp kệ'));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF0284C7), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0284C7).withValues(alpha: 0.14),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.pallet, color: Color(0xFF0284C7), size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pallet.displayName,
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0284C7),
                  side: const BorderSide(color: Color(0xFF0284C7)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.swap_horiz_rounded, size: 14),
                label: const Text('ĐỔI MÃ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: _clearTarget,
              ),
            ],
          ),
          const SizedBox(height: 6),

          Wrap(
            spacing: 8,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('MÃ: ${pallet.palletCode}', style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 11, fontFamily: 'monospace')),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('${inStock.length} SẢN PHẨM', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 6),

          if (pallet.rfidEpc != null && pallet.rfidEpc!.isNotEmpty)
            Text(
              'EPC Pallet: ${pallet.rfidEpc}',
              style: TextStyle(color: c.textMuted, fontSize: 11, fontFamily: 'monospace'),
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 6),
          Divider(color: c.border, height: 1),
          const SizedBox(height: 6),

          Row(
            children: [
              Icon(Icons.location_on_rounded, size: 15, color: c.warningAmber),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Vị trí kệ: $locStr',
                  style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveItemTargetCard(Item it, EyeCareColors c) {
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
                onPressed: _clearTarget,
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

  Widget _buildActiveRawEpcCard(String epc, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.rfidCyan, width: 1.5),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ĐỊNH VỊ THEO MÃ EPC', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 4),
                Text(epc, style: TextStyle(color: c.textPrimary, fontFamily: 'monospace', fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: _clearTarget,
            child: const Text('ĐỔI MÃ'),
          ),
        ],
      ),
    );
  }

  Widget _buildOtherTagAlertBanner(EyeCareColors c) {
    if (!_isTracking || !hasTarget || _currentRssi > -88.0 || _lastOtherTagEpc == null || _lastOtherTagTime == null) {
      return const SizedBox.shrink();
    }
    if (DateTime.now().difference(_lastOtherTagTime!).inSeconds > 8) {
      return const SizedBox.shrink();
    }

    final otherEpc = _lastOtherTagEpc!;
    final otherRssi = _lastOtherTagRssi?.toStringAsFixed(0) ?? '-45';

    // Thử khớp mặt hàng hoặc pallet trong cơ sở dữ liệu
    final matchedItem = _repo.items.where((it) => it.epc.replaceAll(' ', '').toUpperCase() == otherEpc).firstOrNull;
    final matchedPallet = matchedItem == null
        ? _repo.pallets.where((p) => (p.rfidEpc ?? '').replaceAll(' ', '').toUpperCase() == otherEpc).firstOrNull
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.warningAmber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.warningAmber, width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sensors_rounded, color: c.warningAmber, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'ĐANG ĐỌC ĐƯỢC CHIP KHÁC GẦN MÁY:',
                  style: TextStyle(
                    color: c.warningAmber,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: c.warningAmber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '$otherRssi dBm',
                  style: TextStyle(color: c.warningAmber, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Mã EPC: $otherEpc',
            style: TextStyle(color: c.textPrimary, fontSize: 12, fontFamily: 'monospace', fontWeight: FontWeight.w600),
          ),
          if (matchedItem != null) ...[
            const SizedBox(height: 2),
            Text(
              'Tên SP: ${matchedItem.productName} (${matchedItem.sku})',
              style: TextStyle(color: c.textSecondary, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ] else if (matchedPallet != null) ...[
            const SizedBox(height: 2),
            Text(
              'Pallet: ${matchedPallet.displayName} (${matchedPallet.palletCode})',
              style: TextStyle(color: c.textSecondary, fontSize: 11),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.warningAmber,
                padding: const EdgeInsets.symmetric(vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.touch_app_rounded, size: 16, color: Colors.black87),
              label: Text(
                matchedItem != null
                    ? 'CHUYỂN SANG ĐỊNH VỊ: ${matchedItem.productName}'
                    : (matchedPallet != null
                        ? 'CHUYỂN SANG ĐỊNH VỊ PALLET: ${matchedPallet.displayName}'
                        : 'ĐỊNH VỊ THEO MÃ EPC NÀY'),
                style: const TextStyle(color: Colors.black87, fontSize: 11.5, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
              onPressed: () {
                if (matchedItem != null) {
                  _selectTargetItem(matchedItem);
                } else if (matchedPallet != null) {
                  _selectTargetPallet(matchedPallet);
                } else {
                  final newRssi = _lastOtherTagRssi ?? -50.0;
                  final now = DateTime.now();
                  setState(() {
                    _targetPallet = null;
                    _targetRawEpc = otherEpc;
                    _targetItem = Item(
                      itemId: 'TEMP_$otherEpc',
                      epc: otherEpc,
                      productId: 'PROD_TEMP',
                      sku: otherEpc,
                      productName: 'Mã EPC: $otherEpc',
                      serialNumber: '',
                      status: ItemStatus.inStock,
                    );
                    _currentRssi = newRssi;
                    _previousRssi = null;
                    _lastSeenTime = now;
                    _spatialTracker.reset();
                    _spatialTracker.recordTagSample(newRssi, time: now);
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Nút bấm điều khiển Quét Định Vị
  Widget _buildTrackingControlButton(EyeCareColors c) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: _isTracking ? c.errorCoral : c.successEmerald,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: _isTracking ? 2 : 1,
            ),
            icon: Icon(
              _isTracking ? Icons.stop_circle_rounded : Icons.radar_rounded,
              color: Colors.white,
              size: 22,
            ),
            label: Text(
              _isTracking ? 'DỪNG QUÉT ĐỊNH VỊ' : 'BẬT QUÉT ĐỊNH VỊ (BÓP CÒ SÚNG)',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13.5,
              ),
            ),
            onPressed: _isTracking ? _stopTracking : _startTracking,
          ),
        ),
        const SizedBox(height: 8),

        // Tùy chọn chế độ cò súng: Rảnh tay (Bấm 1 lần) vs Bóp giữ
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: c.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Icon(
                _continuousLockMode ? Icons.lock_clock_rounded : Icons.touch_app_rounded,
                size: 15,
                color: c.rfidCyan,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _continuousLockMode
                      ? 'Chế độ: Bấm 1 lần (Dò liên tục)'
                      : 'Chế độ: Bóp giữ cò để dò',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: () {
                  setState(() => _continuousLockMode = !_continuousLockMode);
                  ScaffoldMessenger.of(context).hideCurrentSnackBar();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      duration: const Duration(seconds: 1),
                      backgroundColor: c.bgCardElevated,
                      content: Text(
                        _continuousLockMode
                            ? '✓ Chế độ: Bấm 1 lần để Bật/Tắt dò tìm liên tục'
                            : '✓ Chế độ: Bóp giữ cò súng để quét',
                        style: TextStyle(color: c.textPrimary, fontSize: 12),
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: c.rfidCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'ĐỔI',
                    style: TextStyle(
                      color: c.rfidCyan,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
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
