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

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onStateChange);
    _repo.addListener(_onStateChange);

    if (widget.initialLocationId != null && widget.initialLocationId!.trim().isNotEmpty) {
      _lockedLocationId = widget.initialLocationId!.trim();
    }

    if (widget.initialCartonOrPalletBarcode != null &&
        widget.initialCartonOrPalletBarcode!.trim().isNotEmpty) {
      _activePalletGroup = widget.initialCartonOrPalletBarcode!.trim();
    } else {
      final pending = _pendingGroups();
      if (pending.isNotEmpty) {
        _activePalletGroup = pending.keys.first;
      }
    }

    _uhf.setScanMode(PdaScanMode.barcode);

    _barcodeSub = _uhf.onBarcodeRead.listen((barcode) {
      if (!mounted) return;
      _handleScannedCode(barcode);
    });

    _tagSub = _uhf.onTagRead.listen((tag) {
      if (!mounted) return;
      _handleScannedCode(tag.epc);
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

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _barcodeSub?.cancel();
    _tagSub?.cancel();
    _triggerSub?.cancel();
    _uhf.setScanMode(PdaScanMode.rfid);
    _eyeCare.removeListener(_onStateChange);
    _repo.removeListener(_onStateChange);
    super.dispose();
  }

  List<Item> _pendingItems() {
    return _repo.items.where((i) =>
      i.status == ItemStatus.waitingPutaway ||
      (i.status == ItemStatus.inStock &&
       (i.locationId == null || i.locationId!.trim().isEmpty || i.locationId == 'LOC-GATE-IN') &&
       (i.palletId != null && i.palletId!.trim().isNotEmpty))
    ).toList();
  }

  Map<String, List<Item>> _pendingGroups() {
    final groups = <String, List<Item>>{};
    for (var it in _pendingItems()) {
      final key = (it.palletId != null && it.palletId!.trim().isNotEmpty)
          ? it.palletId!.trim()
          : (it.orderNo ?? 'CHƯA_RÕ');
      groups.putIfAbsent(key, () => []).add(it);
    }
    return groups;
  }

  Future<void> _handleScannedCode(String raw) async {
    final clean = raw.trim().toUpperCase();
    if (clean.isEmpty) return;

    const ignoredCommands = {
      'ACTION_SCAN', 'ACTION_STOP_SCAN', 'SCANNER_START', 'SCANNER_STOP',
      'START_SCAN', 'STOP_SCAN', 'SCAN', 'KEY_CONTROL',
      'KEY_CONTROL_DISABLED', 'TRUE', 'FALSE',
    };
    if (ignoredCommands.contains(clean)) return;

    // 1. Kiểm tra mã vị trí kệ
    final loc = _repo.locations.where((l) =>
      l.locationCode.toUpperCase() == clean ||
      l.locationId.toUpperCase() == clean ||
      clean.startsWith('LOC-')
    ).firstOrNull;

    if (loc != null) {
      HapticFeedback.mediumImpact();
      setState(() => _lockedLocationId = loc.locationId);

      if (_activePalletGroup != null && !_isProcessing) {
        await _doPutaway(_activePalletGroup!, loc.locationId);
      }
      return;
    }

    // 2. Kiểm tra mã Pallet
    final groups = _pendingGroups();
    String? matchedPalletKey;
    if (groups.containsKey(clean)) {
      matchedPalletKey = clean;
    } else if (groups.containsKey('PAL-$clean')) {
      matchedPalletKey = 'PAL-$clean';
    } else if (clean.startsWith('PAL-') && groups.containsKey(clean.replaceFirst('PAL-', ''))) {
      matchedPalletKey = clean.replaceFirst('PAL-', '');
    } else {
      final pal = _repo.pallets.where((p) =>
        p.palletId.toUpperCase() == clean ||
        p.palletCode.toUpperCase() == clean ||
        p.palletId.toUpperCase() == 'PAL-$clean' ||
        (p.rfidEpc != null && p.rfidEpc!.toUpperCase() == clean)
      ).firstOrNull;

      if (pal != null) {
        matchedPalletKey = pal.palletId;
      } else {
        final matchedItem = _repo.items.where((i) =>
          i.cartonCode?.toUpperCase() == clean ||
          i.epc.toUpperCase() == clean ||
          i.serialNumber.toUpperCase() == clean ||
          i.sku.toUpperCase() == clean
        ).firstOrNull;

        matchedPalletKey = matchedItem?.palletId ?? clean;
      }
    }

    HapticFeedback.selectionClick();
    setState(() => _activePalletGroup = matchedPalletKey);

    if (_lockedLocationId != null && !_isProcessing) {
      await _doPutaway(matchedPalletKey, _lockedLocationId!);
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
          final remaining = _pendingGroups();
          remaining.remove(palletOrCarton);
          remaining.remove('PAL-$palletOrCarton');
          remaining.remove(palletOrCarton.replaceAll(RegExp(r'^PAL-', caseSensitive: false), ''));
          _activePalletGroup = remaining.isNotEmpty ? remaining.keys.first : null;
        });
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
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text('Lỗi: $e'),
        ));
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final groups = _pendingGroups();
    final selectedLoc = _repo.locations.where((l) => l.locationId == _lockedLocationId).firstOrNull;
    final activeItems = _activePalletGroup != null ? (groups[_activePalletGroup] ?? _repo.items.where((i) => i.palletId == _activePalletGroup || i.palletId == 'PAL-$_activePalletGroup').toList()) : <Item>[];
    final bool canComplete = _lockedLocationId != null && _activePalletGroup != null && !_isProcessing;

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: const HardwareStatusAppBar(title: 'CẤT HÀNG LÊN KỆ'),
      body: RefreshIndicator(
        color: c.rfidCyan,
        onRefresh: () async {
          await SupabaseSyncService().syncNow();
          await _repo.reloadFromSqlite();
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

              if (groups.isEmpty && _lastResult != null && _lastResult!.success) ...[
                _buildAllDoneView(c),
              ] else ...[
                _buildLocationCard(c, selectedLoc),
                const SizedBox(height: 10),

                _buildPalletCard(c, groups, activeItems),
                const SizedBox(height: 12),

                // Nút quét phụ (nếu không bấm cò vật lý)
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.rfidCyan,
                      side: BorderSide(color: c.rfidCyan.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      backgroundColor: c.bgCardElevated,
                    ),
                    icon: const Icon(Icons.qr_code_scanner, size: 18),
                    label: const Text(
                      'QUÉT MÃ',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: () => _uhf.triggerBarcodeScan(),
                  ),
                ),
                const SizedBox(height: 12),

                // Nút hoàn tất
                _buildCompleteActionButton(c, canComplete, activeItems.length),
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

  Widget _buildLocationCard(EyeCareColors c, Location? selectedLoc) {
    final hasLoc = selectedLoc != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasLoc ? const Color(0xFF10B981) : c.rfidCyan,
          width: 1.2,
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
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasLoc ? 'KỆ: ${selectedLoc.locationCode}' : 'VỊ TRÍ KỆ',
                  style: TextStyle(
                    color: hasLoc ? const Color(0xFF10B981) : c.rfidCyan,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (hasLoc)
                InkWell(
                  onTap: () => setState(() => _lockedLocationId = null),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('Đổi', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: hasLoc ? const Color(0xFF10B981).withValues(alpha: 0.4) : c.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                dropdownColor: c.bgCardElevated,
                value: _lockedLocationId,
                icon: Icon(Icons.arrow_drop_down, color: hasLoc ? const Color(0xFF10B981) : c.rfidCyan),
                hint: Text('Chọn vị trí kệ...', style: TextStyle(color: c.textMuted, fontSize: 12)),
                style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                items: _repo.locations.map((loc) {
                  return DropdownMenuItem(
                    value: loc.locationId,
                    child: Text(
                      '${loc.locationCode} • ${loc.zone} - ${loc.shelf}',
                      style: TextStyle(color: c.textPrimary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _lockedLocationId = val);
                    HapticFeedback.selectionClick();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPalletCard(EyeCareColors c, Map<String, List<Item>> groups, List<Item> activeItems) {
    final hasPallet = _activePalletGroup != null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hasPallet ? const Color(0xFFF59E0B) : c.border,
          width: hasPallet ? 1.2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.inventory_2_outlined, color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasPallet ? 'PALLET: $_activePalletGroup (${activeItems.length} SP)' : 'PALLET',
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
              if (hasPallet && groups.length > 1)
                InkWell(
                  onTap: () => setState(() => _activePalletGroup = null),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Text('Đổi', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ),
            ],
          ),
          if (groups.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: hasPallet ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : c.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  dropdownColor: c.bgCardElevated,
                  value: groups.containsKey(_activePalletGroup) ? _activePalletGroup : null,
                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFFF59E0B)),
                  hint: Text('Chọn Pallet (${groups.length})...', style: TextStyle(color: c.textMuted, fontSize: 12)),
                  style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                  items: groups.entries.map((entry) {
                    return DropdownMenuItem(
                      value: entry.key,
                      child: Text(
                        '${entry.key} • ${entry.value.length} SP',
                        style: TextStyle(color: c.textPrimary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _activePalletGroup = val);
                      HapticFeedback.selectionClick();
                    }
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCompleteActionButton(EyeCareColors c, bool canComplete, int itemCount) {
    String label = 'HOÀN TẤT CẤT KỆ';
    Color color = const Color(0xFF10B981);

    if (_isProcessing) {
      label = 'ĐANG LƯU...';
      color = c.border;
    } else if (_lockedLocationId == null) {
      label = 'CHƯA CHỌN KỆ';
      color = c.border;
    } else if (_activePalletGroup == null) {
      label = 'CHƯA CHỌN PALLET';
      color = c.border;
    } else {
      label = 'HOÀN TẤT CẤT KỆ ($itemCount SP)';
    }

    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          disabledBackgroundColor: c.border.withValues(alpha: 0.4),
          disabledForegroundColor: c.textMuted,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          elevation: canComplete ? 2 : 0,
        ),
        onPressed: canComplete ? () => _doPutaway(_activePalletGroup!, _lockedLocationId!) : null,
        child: Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
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
          SizedBox(
            width: double.infinity,
            height: 42,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.rfidCyan,
                foregroundColor: const Color(0xFF2C251E),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('QUAY LẠI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            ),
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
