import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/wms_models.dart';
import '../../models/tag_info.dart';
import '../../services/uhf_service.dart';
import '../../services/warehouse_repository.dart';
import '../../services/supabase_sync_service.dart';
import '../../theme/eye_care_theme.dart';
import '../../widgets/hardware_status_appbar.dart';
import '../../widgets/app_notification_bar.dart';

/// Màn hình Cất Hàng Lên Kệ (Putaway) trên tay cầm PDA
/// Tối ưu: Ít chữ, không chú thích rườm rà, chọn vị trí -> quét mã Pallet -> hoàn tất.
class PdaPutawayScreen extends StatefulWidget {
  final String? initialLocationId;
  final String? initialCartonOrPalletBarcode;

  const PdaPutawayScreen({
    super.key,
    this.initialLocationId,
    this.initialCartonOrPalletBarcode,
  });

  /// Chuẩn hóa mã Pallet để so khớp thông minh không phân biệt PAL-, PL, khoảng trắng hay dấu gạch nối '-'
  static String normalizePalletCode(String raw) {
    String s = raw.trim().toUpperCase();
    if (s.startsWith('PAL-')) s = s.substring(4);
    if (s.startsWith('PAL')) s = s.substring(3);
    return s.replaceAll('-', '').replaceAll('_', '').replaceAll(' ', '');
  }

  /// Kiểm tra 2 mã Pallet/kiện hàng có tương đương nhau hay không (ví dụ PAL-PL-01 == PAL-PL01 == PL-01 == PL01)
  static bool isSamePallet(String? a, String? b) {
    if (a == null || b == null) return false;
    final cleanA = a.trim().toUpperCase();
    final cleanB = b.trim().toUpperCase();
    if (cleanA.isEmpty || cleanB.isEmpty) return false;
    if (cleanA == cleanB) return true;
    if (cleanA.replaceAll('-', '') == cleanB.replaceAll('-', '')) return true;
    final normA = normalizePalletCode(cleanA);
    final normB = normalizePalletCode(cleanB);
    return normA.isNotEmpty && normA == normB;
  }

  @override
  State<PdaPutawayScreen> createState() => _PdaPutawayScreenState();
}

class _PdaPutawayScreenState extends State<PdaPutawayScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  StreamSubscription<String>? _barcodeSub;
  StreamSubscription<TagInfo>? _tagSub;
  StreamSubscription<bool>? _triggerSub;

  String? _activePalletGroup;
  String? _lockedLocationId;
  _PutawayResult? _lastResult;
  bool _isProcessing = false;
  final TextEditingController _barcodeInputController = TextEditingController();
  final FocusNode _barcodeFocusNode = FocusNode();
  final TextEditingController _palletInputController = TextEditingController();
  final FocusNode _palletFocusNode = FocusNode();
  final TextEditingController _locationInputController = TextEditingController();
  final FocusNode _locationFocusNode = FocusNode();
  Timer? _repoThrottleTimer;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onThemeChange);
    _repo.addListener(_onRepoChange);

    if (widget.initialLocationId != null && widget.initialLocationId!.trim().isNotEmpty) {
      final input = widget.initialLocationId!.trim();
      final matchedLoc = _repo.locations.where((l) =>
        l.locationId.toUpperCase() == input.toUpperCase() ||
        l.locationCode.toUpperCase() == input.toUpperCase()
      ).firstOrNull;
      _lockedLocationId = matchedLoc?.locationId ?? input;
    }

    if (widget.initialCartonOrPalletBarcode != null &&
        widget.initialCartonOrPalletBarcode!.trim().isNotEmpty) {
      final input = widget.initialCartonOrPalletBarcode!.trim();
      final pending = _pendingGroups();
      final matchedKey = pending.keys.where((k) =>
        isSamePallet(k, input) ||
        k.toUpperCase() == input.toUpperCase() ||
        k.toUpperCase() == 'PAL-${input.toUpperCase()}' ||
        'PAL-${k.toUpperCase()}' == input.toUpperCase() ||
        pending[k]!.any((it) => (it.orderNo?.toUpperCase() == input.toUpperCase()))
      ).firstOrNull;
      _activePalletGroup = matchedKey ?? input;
    } else {
      final pending = _pendingGroups();
      if (pending.length == 1) {
        _activePalletGroup = pending.keys.first;
      } else {
        _activePalletGroup = null;
      }
    }

    _uhf.enableScanning('cat_ke');
    _uhf.stopInventory();
    _uhf.setScanMode(PdaScanMode.barcode);

    _barcodeSub = _uhf.onBarcodeRead.listen((barcode) {
      if (!mounted) return;
      _handleScannedCode(barcode);
    });

    _tagSub = _uhf.onTagRead.listen((tag) {
      if (!mounted) return;
      _handleScannedCode(tag.epc, isFromRfid: true);
    });

    _triggerSub = _uhf.onTriggerStateChanged.listen((isPressed) {
      if (!mounted) return;
      if (isPressed) {
        if (_uhf.scanMode == PdaScanMode.barcode) {
          _uhf.triggerBarcodeScan();
        } else {
          _uhf.startInventory();
        }
      } else {
        if (_uhf.scanMode == PdaScanMode.rfid) {
          _uhf.stopInventory();
        }
      }
    });
  }

  Map<String, List<Item>>? _cachedGroups;

  void _invalidateGroupsCache() {
    _cachedGroups = null;
  }

  void _onThemeChange() {
    if (mounted) setState(() {});
  }

  void _onRepoChange() {
    if (_repoThrottleTimer?.isActive ?? false) return;
    _repoThrottleTimer = Timer(const Duration(milliseconds: 300), () {
      _invalidateGroupsCache();
      final pending = _pendingGroups();
      if (_activePalletGroup != null && !pending.containsKey(_activePalletGroup)) {
        _activePalletGroup = null;
      }
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant PdaPutawayScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialLocationId != oldWidget.initialLocationId &&
        widget.initialLocationId != null &&
        widget.initialLocationId!.trim().isNotEmpty) {
      final input = widget.initialLocationId!.trim();
      final matchedLoc = _repo.locations.where((l) =>
        l.locationId.toUpperCase() == input.toUpperCase() ||
        l.locationCode.toUpperCase() == input.toUpperCase()
      ).firstOrNull;
      _lockedLocationId = matchedLoc?.locationId ?? input;
    }
  }

  @override
  void dispose() {
    _repoThrottleTimer?.cancel();
    _uhf.disableScanning();
    _uhf.stopInventory();
    _barcodeSub?.cancel();
    _tagSub?.cancel();
    _triggerSub?.cancel();
    _barcodeInputController.dispose();
    _barcodeFocusNode.dispose();
    _palletInputController.dispose();
    _palletFocusNode.dispose();
    _locationInputController.dispose();
    _locationFocusNode.dispose();
    _uhf.setScanMode(PdaScanMode.rfid);
    _eyeCare.removeListener(_onThemeChange);
    _repo.removeListener(_onRepoChange);
    super.dispose();
  }

  List<Item> _pendingItems() {
    final waitingOrderNos = _repo.inboundOrders
        .where((o) => o.status == InboundOrderStatus.waitingPutaway)
        .map((o) => o.orderNo.trim().toUpperCase())
        .toSet();

    return _repo.items.where((i) =>
      i.status == ItemStatus.waitingPutaway ||
      i.status == ItemStatus.waitingPalletize ||
      (i.status == ItemStatus.inStock &&
       (i.locationId == null || i.locationId!.trim().isEmpty || i.locationId == 'LOC-GATE-IN')) ||
      (waitingOrderNos.contains((i.orderNo ?? '').trim().toUpperCase()) &&
       i.status != ItemStatus.out &&
       (i.locationId == null || i.locationId!.trim().isEmpty || i.locationId == 'LOC-GATE-IN'))
    ).toList();
  }

  static String normalizePalletCode(String raw) => PdaPutawayScreen.normalizePalletCode(raw);
  static bool isSamePallet(String? a, String? b) => PdaPutawayScreen.isSamePallet(a, b);

  Map<String, List<Item>> _pendingGroups() {
    if (_cachedGroups != null) return _cachedGroups!;
    final groups = <String, List<Item>>{};
    for (var it in _pendingItems()) {
      final rawKey = (it.palletId != null && it.palletId!.trim().isNotEmpty)
          ? it.palletId!.trim()
          : (it.cartonCode != null && it.cartonCode!.trim().isNotEmpty)
              ? it.cartonCode!.trim()
              : (it.orderNo != null && it.orderNo!.trim().isNotEmpty)
                  ? it.orderNo!.trim()
                  : 'LÔ_CHỜ_KỆ';

      // Tìm xem đã có nhóm nào cùng mã pallet chưa (so khớp thông minh bỏ qua dấu '-')
      final matchedKey = groups.keys.where((k) => isSamePallet(k, rawKey)).firstOrNull;
      final targetKey = matchedKey ?? rawKey;
      groups.putIfAbsent(targetKey, () => []).add(it);
    }
    _cachedGroups = groups;
    return groups;
  }

  Future<void> _handleScannedCode(String raw, {bool isFromRfid = false}) async {
    final clean = raw.trim().toUpperCase();
    if (clean.isEmpty) return;

    const ignoredCommands = {
      'ACTION_SCAN', 'ACTION_STOP_SCAN', 'SCANNER_START', 'SCANNER_STOP',
      'START_SCAN', 'STOP_SCAN', 'SCAN', 'KEY_CONTROL',
      'KEY_CONTROL_DISABLED', 'TRUE', 'FALSE',
    };
    if (ignoredCommands.contains(clean)) return;

    // 1. Kiểm tra mã vị trí kệ (qua Barcode/QR code: hỗ trợ mã thuần, tiền tố LOCATION:/LOC:/SHELF:, hoặc có/không có LOC-)
    String normLoc = clean;
    if (normLoc.startsWith('LOCATION:')) normLoc = normLoc.substring(9).trim();
    if (normLoc.startsWith('LOC:')) normLoc = normLoc.substring(4).trim();
    if (normLoc.startsWith('SHELF:')) normLoc = normLoc.substring(6).trim();
    final normStripped = normLoc.startsWith('LOC-') ? normLoc.substring(4) : normLoc;
    final normWithLoc = normLoc.startsWith('LOC-') ? normLoc : 'LOC-$normLoc';

    final loc = _repo.locations.where((l) {
      final locCode = l.locationCode.trim().toUpperCase();
      final locId = l.locationId.trim().toUpperCase();
      return locCode == normLoc ||
          locId == normLoc ||
          locCode == normStripped ||
          locId == normStripped ||
          locCode == normWithLoc ||
          locId == normWithLoc ||
          locCode.replaceAll('-', '') == normLoc.replaceAll('-', '');
    }).firstOrNull;

    if (loc != null) {
      HapticFeedback.mediumImpact();
      setState(() => _lockedLocationId = loc.locationId);

      // Nếu đã có hàng cần cất và quét mã kệ: tự động cất vào vị trí đã chọn
      // CHỈ tự động cất nếu quét từ Barcode thực tế và có kiện hàng đang chọn
      if (_activePalletGroup != null && !_isProcessing && !isFromRfid) {
        await _doPutaway(_activePalletGroup!, loc.locationId);
      }
      return;
    }

    // 2. Tìm xe pallet / thùng hàng / sản phẩm tương ứng với mã quét
    final groups = _pendingGroups();
    String? matchedPalletKey;
    final directOrFuzzyKey = groups.keys.where((k) => isSamePallet(k, clean)).firstOrNull;
    if (directOrFuzzyKey != null) {
      matchedPalletKey = directOrFuzzyKey;
    } else if (groups.containsKey(clean)) {
      matchedPalletKey = clean;
    } else if (groups.containsKey('PAL-$clean')) {
      matchedPalletKey = 'PAL-$clean';
    } else if (clean.startsWith('PAL-') && groups.containsKey(clean.replaceFirst('PAL-', ''))) {
      matchedPalletKey = clean.replaceFirst('PAL-', '');
    } else {
      final pal = _repo.pallets.where((p) =>
        isSamePallet(p.palletId, clean) ||
        isSamePallet(p.palletCode, clean) ||
        p.palletId.toUpperCase() == clean ||
        p.palletCode.toUpperCase() == clean ||
        p.palletId.toUpperCase() == 'PAL-$clean' ||
        (p.rfidEpc != null && p.rfidEpc!.toUpperCase() == clean)
      ).firstOrNull;

      if (pal != null) {
        matchedPalletKey = groups.keys.where((k) => isSamePallet(k, pal.palletId) || isSamePallet(k, pal.palletCode)).firstOrNull;
      }

      if (matchedPalletKey == null) {
        final matchedItem = _repo.items.where((i) =>
          i.cartonCode?.toUpperCase() == clean ||
          i.epc.toUpperCase() == clean ||
          i.serialNumber.toUpperCase() == clean ||
          i.sku.toUpperCase() == clean ||
          (i.orderNo != null && i.orderNo!.toUpperCase() == clean) ||
          isSamePallet(i.palletId, clean)
        ).firstOrNull;

        if (matchedItem != null) {
          final itemPal = matchedItem.palletId ?? matchedItem.cartonCode ?? matchedItem.orderNo;
          if (itemPal != null) {
            matchedPalletKey = groups.keys.where((k) => isSamePallet(k, itemPal)).firstOrNull ?? itemPal;
          }
        }

        if (matchedPalletKey == null) {
          final matchedByOrder = _pendingItems().where((i) =>
            i.orderNo?.toUpperCase() == clean ||
            i.orderNo?.toUpperCase() == 'INB-$clean' ||
            'INB-${i.orderNo?.toUpperCase()}' == clean
          ).firstOrNull;
          if (matchedByOrder != null) {
            final palKey = matchedByOrder.palletId ?? matchedByOrder.cartonCode ?? matchedByOrder.orderNo;
            if (palKey != null) {
              matchedPalletKey = groups.keys.where((k) => isSamePallet(k, palKey)).firstOrNull ?? palKey;
            }
          }
        }

        if (matchedPalletKey == null) {
          for (final k in groups.keys) {
            if (isSamePallet(k, clean)) {
              matchedPalletKey = k;
              break;
            }
            final strippedK = k.replaceAll(RegExp(r'^PAL-', caseSensitive: false), '').trim().toUpperCase();
            final strippedClean = clean.replaceAll(RegExp(r'^PAL-', caseSensitive: false), '').trim().toUpperCase();
            if (strippedK == strippedClean || strippedK == clean || k.toUpperCase() == strippedClean) {
              matchedPalletKey = k;
              break;
            }
          }
        }
      }
    }

    // Nếu nhận từ sóng RFID thụ động trong không khí: CHỈ chọn pallet nếu khớp chính xác, TUYỆT ĐỐI không tự động cất hàng!
    if (isFromRfid) {
      if (matchedPalletKey != null && _activePalletGroup != matchedPalletKey) {
        setState(() => _activePalletGroup = matchedPalletKey);
      }
      return;
    }

    // 3. Nếu đã có vị trí kệ được chọn:
    // CHỈ cất hàng nếu mã barcode quét khớp với kiện hàng trong danh sách chờ hoặc khớp với _activePalletGroup!
    if (_lockedLocationId != null && !_isProcessing) {
      final targetPallet = matchedPalletKey ?? (clean == _activePalletGroup?.toUpperCase() ? _activePalletGroup : null);
      if (targetPallet != null) {
        await _doPutaway(targetPallet, _lockedLocationId!);
        return;
      } else {
        HapticFeedback.vibrate();
        if (mounted) {
          AppSnackBar.showWarning(context, 'Mã quét "$clean" không nằm trong danh sách hàng cần cất kệ!');
        }
        return;
      }
    }

    // 4. Nếu chưa chọn vị trí kệ mà quét mã Pallet/Thùng hàng:
    if (matchedPalletKey != null) {
      final typeLabel = (matchedPalletKey.toUpperCase().startsWith('PAL-') || matchedPalletKey.toUpperCase().startsWith('PALLET'))
          ? 'Pallet'
          : 'kiện hàng';
      HapticFeedback.selectionClick();
      setState(() => _activePalletGroup = matchedPalletKey);
      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          '✓ Đã quét nhận diện $typeLabel: $matchedPalletKey (${groups[matchedPalletKey]?.length ?? 0} sản phẩm)',
        );
      }
    } else {
      HapticFeedback.vibrate();
      if (mounted) {
        AppSnackBar.showError(context, 'Không tìm thấy kiện hàng/kệ tương ứng với mã "$clean"');
      }
    }
  }

  Future<void> _doPutaway(String palletOrCarton, String locationId) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    try {
      final loc = _repo.locations.where((l) => l.locationId == locationId || l.locationCode == locationId).firstOrNull;
      final targetLocId = loc?.locationId ?? locationId;

      final savedCount = await _repo.confirmPdaPutawayByCarton(
        cartonOrOrderBarcode: palletOrCarton,
        locationId: targetLocId,
        performedBy: _repo.resolveUserFullName(null, defaultRole: 'handheld'),
      );

      if (savedCount > 0) {
        HapticFeedback.heavyImpact();
        final result = _PutawayResult(
          palletCode: palletOrCarton,
          locationCode: loc?.locationCode ?? locationId,
          itemCount: savedCount,
          success: true,
        );

        setState(() {
          _lastResult = result;
          _lockedLocationId = null; // Hoàn thành cất hàng, reset để chọn vị trí cho kiện tiếp theo
          final remaining = _pendingGroups();
          remaining.removeWhere((k, _) => isSamePallet(k, palletOrCarton));
          remaining.remove(palletOrCarton);
          remaining.remove('PAL-$palletOrCarton');
          remaining.remove(palletOrCarton.replaceAll(RegExp(r'^PAL-', caseSensitive: false), ''));
          _activePalletGroup = remaining.isNotEmpty ? remaining.keys.first : null;
        });
        _barcodeInputController.clear();
        if (mounted) {
          final locDisplay = loc?.displayName ?? loc?.locationCode ?? locationId;
          final remaining = _pendingGroups();
          if (remaining.isEmpty) {
            AppSnackBar.showSuccess(
              context,
              '✓ Đã cất thành công $savedCount sản phẩm vào kệ $locDisplay! Toàn bộ hàng đã cất kệ hoàn tất.',
            );
          } else {
            AppSnackBar.showSuccess(
              context,
              '✓ Đã cất thành công $savedCount sản phẩm vào kệ $locDisplay!',
            );
          }
        }
      } else {
        HapticFeedback.vibrate();
        setState(() {
          _lastResult = _PutawayResult(
            palletCode: palletOrCarton,
            locationCode: loc?.locationCode ?? locationId,
            itemCount: 0,
            success: false,
          );
        });
        if (mounted) {
          AppSnackBar.showWarning(
            context,
            'Không có sản phẩm nào được cất vào kệ (có thể đã được cất trước đó)!',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(context, 'Lỗi cất hàng: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final groups = _pendingGroups();
    final selectedLoc = _repo.locations.where((l) =>
      l.locationId == _lockedLocationId || l.locationCode == _lockedLocationId
    ).firstOrNull;
    final activeItems = _activePalletGroup != null
        ? (groups[_activePalletGroup] ??
            _repo.items.where((i) =>
              isSamePallet(i.palletId, _activePalletGroup) ||
              (i.palletId != null && i.palletId!.trim().toUpperCase() == _activePalletGroup?.toUpperCase()) ||
              (i.orderNo != null && i.orderNo!.trim().toUpperCase() == _activePalletGroup?.toUpperCase())
            ).toList())
        : <Item>[];

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: const HardwareStatusAppBar(title: 'CẤT HÀNG LÊN KỆ'),
      body: RefreshIndicator(
        color: c.rfidCyan,
        onRefresh: () async {
          await SupabaseSyncService().syncNow();
          await _repo.reloadFromDatabase();
          _invalidateGroupsCache();
          if (mounted) setState(() {});
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_lastResult != null) ...[
                _buildResultBanner(c, _lastResult!),
                const SizedBox(height: 10),
              ],

              if (groups.isEmpty && (_activePalletGroup == null || activeItems.isEmpty)) ...[
                if (_lastResult != null && _lastResult!.success)
                  _buildAllDoneView(c)
                else
                  _buildEmptyPendingView(c),
              ] else ...[
                // Ô 1: THÔNG TIN HÀNG CẦN CẤT
                _buildItemInfoCard(c, groups, activeItems),
                const SizedBox(height: 12),

                // Ô 2: CHỌN VỊ TRÍ & QUÉT BARCODE CẤT HÀNG
                _buildLocationAndScanCard(c, selectedLoc),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResultBanner(EyeCareColors c, _PutawayResult result) {
    final color = result.success ? const Color(0xFF10B981) : const Color(0xFFEF4444);
    final icon = result.success ? Icons.check_circle : Icons.error_outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              result.success
                  ? 'Đã cất ${result.palletCode} ➔ Kệ ${result.locationCode} (${result.itemCount} SP)'
                  : 'Không tìm thấy "${result.palletCode}"',
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _lastResult = null),
            child: Icon(Icons.close, color: c.textSecondary, size: 16),
          ),
        ],
      ),
    );
  }

  // ========== Ô 1: QUÉT BARCODE PALLET / KIỆN HÀNG CẦN CẤT ==========
  Widget _buildItemInfoCard(EyeCareColors c, Map<String, List<Item>> groups, List<Item> activeItems) {
    final hasPallet = _activePalletGroup != null && _activePalletGroup!.trim().isNotEmpty;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasPallet ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
          width: hasPallet ? 1.5 : 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasPallet ? Icons.check_circle_rounded : Icons.qr_code_scanner,
                color: hasPallet ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasPallet ? 'PALLET ĐÃ QUÉT: $_activePalletGroup' : 'QUÉT BARCODE PALLET CẦN CẤT',
                  style: TextStyle(
                    color: hasPallet ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (hasPallet)
                InkWell(
                  onTap: () {
                    setState(() => _activePalletGroup = null);
                    HapticFeedback.selectionClick();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.bgDeep,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.border),
                    ),
                    child: Text(
                      'Quét lại',
                      style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (!hasPallet) ...[
            // Khung quét Barcode Pallet nổi bật
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.qr_code_2, color: Color(0xFFF59E0B), size: 24),
                      SizedBox(width: 8),
                      Text(
                        'BÓP CÒ PDA ĐỂ QUÉT BARCODE PALLET',
                        style: TextStyle(
                          color: Color(0xFFF59E0B),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Hướng máy quét vào mã vạch dán trên Pallet / Thùng hàng',
                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Ô nhập tay / nhận diện quét mã Pallet
                  TextField(
                    controller: _palletInputController,
                    focusNode: _palletFocusNode,
                    style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'Bóp cò PDA hoặc nhập mã Pallet...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 11),
                      filled: true,
                      fillColor: c.bgDeep,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      prefixIcon: const Icon(Icons.qr_code, color: Color(0xFFF59E0B), size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward, color: Color(0xFFF59E0B), size: 18),
                        onPressed: () {
                          if (_palletInputController.text.trim().isNotEmpty) {
                            _handleScannedCode(_palletInputController.text);
                            _palletInputController.clear();
                          }
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFF59E0B), width: 1.5)),
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        _handleScannedCode(val);
                        _palletInputController.clear();
                      }
                    },
                  ),
                ],
              ),
            ),
          ] else ...[
            // Đã quét nhận diện Pallet
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_activePalletGroup (${activeItems.length} sản phẩm)',
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Sẵn sàng cất lên kệ • Quét mã vị trí để hoàn tất',
                          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ========== Ô 2: QUÉT BARCODE VỊ TRÍ KỆ ==========
  Widget _buildLocationAndScanCard(EyeCareColors c, Location? selectedLoc) {
    final hasLoc = selectedLoc != null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasLoc ? const Color(0xFF10B981) : c.rfidCyan,
          width: hasLoc ? 1.5 : 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasLoc ? Icons.check_circle_rounded : Icons.shelves,
                color: hasLoc ? const Color(0xFF10B981) : c.rfidCyan,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasLoc ? 'KỆ ĐÃ QUÉT: ${selectedLoc.locationCode}' : 'QUÉT BARCODE VỊ TRÍ KỆ',
                  style: TextStyle(
                    color: hasLoc ? const Color(0xFF10B981) : c.rfidCyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (hasLoc)
                InkWell(
                  onTap: () {
                    setState(() => _lockedLocationId = null);
                    HapticFeedback.selectionClick();
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: c.bgDeep,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: c.border),
                    ),
                    child: Text('Đổi vị trí', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          if (!hasLoc) ...[
            // Khung quét Barcode Kệ nổi bật
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
              decoration: BoxDecoration(
                color: c.rfidCyan.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.shelves, color: c.rfidCyan, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'BÓP CÒ PDA QUÉT MÃ NHÃN KỆ',
                        style: TextStyle(
                          color: c.rfidCyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Quét mã nhãn vị trí dán trên kệ (ví dụ: LOC-xxx, A-01...)',
                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),

                  // Ô nhập tay / nhận diện quét mã kệ
                  TextField(
                    controller: _locationInputController,
                    focusNode: _locationFocusNode,
                    style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'Bóp cò PDA hoặc nhập mã nhãn kệ (LOC-xxx)...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 11),
                      filled: true,
                      fillColor: c.bgDeep,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      prefixIcon: Icon(Icons.qr_code, color: c.rfidCyan, size: 18),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.arrow_forward, color: c.rfidCyan, size: 18),
                        onPressed: () {
                          if (_locationInputController.text.trim().isNotEmpty) {
                            _handleScannedCode(_locationInputController.text);
                            _locationInputController.clear();
                          }
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.rfidCyan, width: 1.5)),
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        _handleScannedCode(val);
                        _locationInputController.clear();
                      }
                    },
                  ),
                ],
              ),
            ),
          ] else ...[
            // Đã chọn/quét vị trí kệ
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedLoc.locationCode,
                          style: const TextStyle(
                            color: Color(0xFF10B981),
                            fontWeight: FontWeight.bold,
                            fontSize: 13.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Khu vực: ${selectedLoc.zone} • Tầng: ${selectedLoc.shelf}',
                          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Khối DÒNG 2: QUÉT BARCODE ĐỂ CẤT HÀNG
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.rfidCyan.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.qr_code_scanner, color: c.rfidCyan, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'DÒNG 2: QUÉT BARCODE ĐỂ CẤT HÀNG',
                          style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  TextField(
                    controller: _barcodeInputController,
                    focusNode: _barcodeFocusNode,
                    style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'Bóp cò PDA hoặc nhập mã quét...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 11.5),
                      filled: true,
                      fillColor: c.bgDeep,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      prefixIcon: Icon(Icons.qr_code, color: c.textSecondary, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.arrow_forward, color: Color(0xFF10B981)),
                        onPressed: () {
                          if (_barcodeInputController.text.trim().isNotEmpty) {
                            _handleScannedCode(_barcodeInputController.text);
                            _barcodeInputController.clear();
                          }
                        },
                      ),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.rfidCyan, width: 1.5)),
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        _handleScannedCode(val);
                        _barcodeInputController.clear();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '⚡ Quét xong sẽ tự động cất vào kệ ${selectedLoc.locationCode} và hoàn thành!',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textSecondary, fontSize: 11, fontStyle: FontStyle.italic),
                  ),

                  // Nút hoàn thành trực tiếp (tùy chọn bấm tay nếu không quét phần cứng)
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (_isProcessing || _activePalletGroup == null) ? c.border : const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('XÁC NHẬN CẤT VÀO VỊ TRÍ NÀY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                      onPressed: (_isProcessing || _activePalletGroup == null)
                          ? null
                          : () => _doPutaway(_activePalletGroup!, selectedLoc.locationId),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyPendingView(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.rfidCyan.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.shelves, color: c.rfidCyan, size: 38),
          ),
          const SizedBox(height: 14),
          Text(
            'CHƯA CÓ HÀNG CHỜ CẤT KỆ',
            style: TextStyle(
              color: c.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: 14.5,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Hiện tại không có kiện hàng hoặc pallet nào đang chờ xếp lên kệ.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            'Nếu hàng vừa quét qua Cổng RFID Gate, vui lòng bấm nút dưới để đồng bộ dữ liệu mới.',
            textAlign: TextAlign.center,
            style: TextStyle(color: c.textMuted, fontSize: 11),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.rfidCyan,
                foregroundColor: const Color(0xFF2C251E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.sync_rounded, size: 18),
              label: const Text('ĐỒNG BỘ & LÀM MỚI DỮ LIỆU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
              onPressed: () async {
                HapticFeedback.selectionClick();
                await SupabaseSyncService().syncNow();
                await _repo.reloadFromDatabase();
                _invalidateGroupsCache();
                if (mounted) setState(() {});
              },
            ),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: c.bgDeep,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.qr_code_scanner, color: c.rfidCyan, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Hoặc bóp cò PDA quét mã Barcode kiện/kệ để bắt đầu',
                    style: TextStyle(color: c.textMuted, fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllDoneView(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.done_all_rounded, color: Color(0xFF10B981), size: 40),
          const SizedBox(height: 12),
          const Text(
            'HOÀN TẤT CẤT KỆ',
            style: TextStyle(
              color: Color(0xFF10B981),
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Đã xếp hết hàng vào kho.',
            style: TextStyle(color: c.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.rfidCyan,
                    side: BorderSide(color: c.rfidCyan),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  icon: const Icon(Icons.sync_rounded, size: 16),
                  label: const Text('LÀM MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    await SupabaseSyncService().syncNow();
                    await _repo.reloadFromDatabase();
                    _invalidateGroupsCache();
                    if (mounted) setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.rfidCyan,
                    foregroundColor: const Color(0xFF2C251E),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () => Navigator.pop(context),
                  child: const Text('QUAY LẠI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PutawayResult {
  final String palletCode;
  final String locationCode;
  final int itemCount;
  final bool success;

  _PutawayResult({
    required this.palletCode,
    required this.locationCode,
    required this.itemCount,
    required this.success,
  });
}
