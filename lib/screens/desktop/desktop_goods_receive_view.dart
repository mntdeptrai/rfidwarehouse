import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/wms_models.dart';
import '../../models/tag_info.dart';
import '../../services/warehouse_repository.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/uhf_service.dart';
import '../../services/tower_light_service.dart';
import '../../services/supabase_sync_service.dart';
import '../../services/excel_import_service.dart';
import '../../theme/eye_care_theme.dart';

/// Màn hình Quản Lý Nhập Kho Desktop với Quy Trình 5 Bước Tuần Tự (Guided Inbound & Putaway Wizard)
class DesktopGoodsReceiveView extends StatefulWidget {
  final bool isActive;
  const DesktopGoodsReceiveView({super.key, this.isActive = true});

  @override
  State<DesktopGoodsReceiveView> createState() => _DesktopGoodsReceiveViewState();
}

class _DesktopGoodsReceiveViewState extends State<DesktopGoodsReceiveView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final DesktopUhfTcpService _desktopUhf = DesktopUhfTcpService();
  final ExcelImportService _excelService = ExcelImportService();
  final TowerLightService _towerLight = TowerLightService();
  final SupabaseSyncService _supabaseSync = SupabaseSyncService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  // ---------- TRẠNG THÁI QUY TRÌNH NHẬP KHO (METHOD 1) ----------
  int _wizardStep = 1; // 1 to 4
  bool _isImporting = false;
  final List<Map<String, dynamic>> _receiptCartons = [];
  final Set<String> _wizardSelectedCartons = {};
  final Set<String> _wizardSelectedEpcs = {};
  final List<String> _pendingLoadedOrderNos = [];

  // Pallet tự động nhận diện từ CSDL hoặc chọn nhanh
  Pallet? _wizardDetectedPallet;
  String? _wizardDetectedPalletTag;

  final Map<String, TagInfo> _wizardScannedTags = {};
  final Map<String, TagInfo> _wizardUnexpectedTags = {};
  bool _wizardIsScanning = false;
  int _wizardScanDuration = 5; // 5s, 10s, 0 = liên tục
  int _wizardScanCountdown = 5;
  Timer? _wizardCountdownTimer;

  String _wizardCartonSearchQuery = '';

  // Performance caches
  List<Map<String, dynamic>>? _cachedAvailableCartons;
  List<Map<String, dynamic>>? _cachedStep1DetailedItems;
  Set<String>? _cachedExpectedSerials;
  List<Map<String, dynamic>>? _cachedStep2FlatItems;
  Timer? _tagBatchUiTimer;
  DateTime? _lastWarningTime;

  StreamSubscription<TagInfo>? _tagSub;
  StreamSubscription<TagInfo>? _desktopTagSub;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await _supabaseSync.syncNow();
      if (mounted) setState(() {});
    });

    _eyeCare.addListener(_onThemeUpdate);
    _repo.addListener(_onRepoUpdate);
    _initTagListener();
  }

  void _onThemeUpdate() {
    if (mounted) setState(() {});
  }

  void _onRepoUpdate() {
    if (_isImporting) return;
    _invalidateCartonCaches();
    if (mounted) setState(() {});
  }

  void _invalidateCartonCaches() {
    _cachedAvailableCartons = null;
    _cachedStep1DetailedItems = null;
    _cachedExpectedSerials = null;
    _cachedStep2FlatItems = null;
  }

  void _initTagListener() {
    _tagSub = _uhf.onTagRead.listen((tag) {
      if (!mounted) return;
      _handleIncomingTag(tag);
    });

    _desktopTagSub = _desktopUhf.onTagRead.listen((tag) {
      if (!mounted) return;
      _handleIncomingTag(tag);
    });

    _desktopUhf.addListener(_onDesktopUhfUpdate);
  }

  void _onDesktopUhfUpdate() {
    if (!mounted || !widget.isActive) return;
    if (_wizardStep == 2) {
      for (final tag in _desktopUhf.tags) {
        _handleWizardGateTag(tag);
      }
    }
  }

  @override
  void didUpdateWidget(DesktopGoodsReceiveView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive != widget.isActive) {
      if (!widget.isActive) {
        if (_wizardIsScanning) _stopWizardScan();
      }
    }
  }

  @override
  void dispose() {
    _tagBatchUiTimer?.cancel();
    _repo.removeListener(_onRepoUpdate);
    _eyeCare.removeListener(_onThemeUpdate);
    _desktopUhf.removeListener(_onDesktopUhfUpdate);
    _tagSub?.cancel();
    _desktopTagSub?.cancel();
    _wizardCountdownTimer?.cancel();
    super.dispose();
  }

  void _handleIncomingTag(TagInfo tag) {
    if (!widget.isActive) return;

    // Khi ở Bước 2: Xe qua cổng quét RFID (tự động nhận diện pallet & đối soát chip hàng)
    if (_wizardStep == 2) {
      _handleWizardGateTag(tag);
      return;
    }
  }

  // ---------- HELPER METHODS CHO QUY TRÌNH 4 BƯỚC ----------

  String _convertPalletNameToHexAscii(String name) {
    if (name.trim().isEmpty) return '';
    final hexString = name.trim().codeUnits
        .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
        .join('');
    if (hexString.length >= 24) {
      return hexString.substring(0, 24);
    }
    return hexString.padRight(24, '0');
  }

  List<Map<String, dynamic>> _getAvailableCartons() {
    if (_cachedAvailableCartons != null) return _cachedAvailableCartons!;
    if (_receiptCartons.isNotEmpty) {
      _cachedAvailableCartons = _receiptCartons;
      return _receiptCartons;
    }
    _cachedAvailableCartons = const [];
    return const [];
  }


  Set<String> _getWizardExpectedSerials() {
    if (_cachedExpectedSerials != null) return _cachedExpectedSerials!;
    if (_wizardSelectedEpcs.isNotEmpty) {
      _cachedExpectedSerials = Set<String>.from(_wizardSelectedEpcs.map((e) => e.trim().toUpperCase()));
      return _cachedExpectedSerials!;
    }
    final cartons = _getAvailableCartons();
    final Set<String> set = {};
    for (var c in cartons) {
      final box = (c['cartonBox'] ?? c['code'] ?? '').toString().trim();
      if (_wizardSelectedCartons.contains(box)) {
        final serials = (c['serials'] as List<dynamic>?)?.map((e) => e.toString().trim().toUpperCase()).toList() ?? [];
        set.addAll(serials);
      }
    }
    _cachedExpectedSerials = set;
    return set;
  }

  List<Map<String, dynamic>> _getStep1DetailedItems() {
    if (_cachedStep1DetailedItems != null) return _cachedStep1DetailedItems!;
    final cartons = _getAvailableCartons();
    final List<Map<String, dynamic>> flat = [];
    for (var cBox in cartons) {
      final boxCode = (cBox['cartonBox'] ?? cBox['code'] ?? '').toString();
      final serials = (cBox['serials'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
      final sItems = (cBox['serialItems'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      for (int i = 0; i < serials.length; i++) {
        final serial = serials[i];
        String sku = (cBox['productCode'] ?? '--').toString();
        String prodName = (cBox['productName'] ?? 'Sản phẩm').toString();
        if (i < sItems.length) {
          final sItem = sItems[i];
          sku = (sItem['barcode'] ?? sku).toString();
          prodName = (sItem['name'] ?? prodName).toString();
        }
        flat.add({
          'boxCode': boxCode,
          'sku': sku,
          'productName': prodName,
          'serial': serial,
        });
      }
    }
    _cachedStep1DetailedItems = flat;
    return flat;
  }

  List<Map<String, dynamic>> _getStep2FlatInspectionItems() {
    if (_cachedStep2FlatItems != null) return _cachedStep2FlatItems!;
    final expectedEpcs = _getWizardExpectedSerials();
    final allItems = _getStep1DetailedItems();
    final List<Map<String, dynamic>> filtered = [];
    for (var it in allItems) {
      final s = (it['serial'] ?? '').toString().trim().toUpperCase();
      if (expectedEpcs.contains(s)) {
        filtered.add(it);
      }
    }
    _cachedStep2FlatItems = filtered;
    return filtered;
  }

  void _toggleWizardScan() {
    if (_wizardIsScanning) {
      _stopWizardScan();
    } else {
      _startWizardScan();
    }
  }

  Future<void> _startWizardScan({int? durationSeconds}) async {
    final duration = durationSeconds ?? _wizardScanDuration;
    _wizardCountdownTimer?.cancel();
    _desktopUhf.clearTags();
    if (!_desktopUhf.isConnected) {
      await _desktopUhf.connectSerial('COM3', 115200);
      await Future.delayed(const Duration(milliseconds: 300));
    }
    _uhf.startInventory();
    await _desktopUhf.startInventory();

    setState(() {
      _wizardIsScanning = true;
      _wizardScanCountdown = duration > 0 ? duration : 0;
    });

    if (duration > 0) {
      _wizardCountdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_wizardScanCountdown > 1) {
          setState(() => _wizardScanCountdown--);
        } else {
          timer.cancel();
          _stopWizardScan();
        }
      });
    }
  }

  Future<void> _stopWizardScan() async {
    _wizardCountdownTimer?.cancel();
    _uhf.stopInventory();
    await _desktopUhf.stopInventory();
    if (mounted) {
      setState(() {
        _wizardIsScanning = false;
        _wizardScanCountdown = _wizardScanDuration;
      });
    }
  }

  List<TagInfo> _getFilteredUnexpectedTags() {
    final palletEpcs = <String>{};
    if (_wizardDetectedPallet?.rfidEpc != null && _wizardDetectedPallet!.rfidEpc!.isNotEmpty) {
      palletEpcs.add(_wizardDetectedPallet!.rfidEpc!.trim().toUpperCase());
    }
    if (_wizardDetectedPalletTag != null && _wizardDetectedPalletTag!.isNotEmpty) {
      palletEpcs.add(_wizardDetectedPalletTag!.trim().toUpperCase());
    }
    for (final p in _repo.pallets) {
      if (p.rfidEpc != null && p.rfidEpc!.isNotEmpty) {
        palletEpcs.add(p.rfidEpc!.trim().toUpperCase());
      }
      palletEpcs.add(p.palletCode.trim().toUpperCase());
    }

    return _wizardUnexpectedTags.values.where((t) {
      final epc = t.epc.trim().toUpperCase();
      if (palletEpcs.contains(epc)) return false;
      if (_repo.findPalletByRfid(epc) != null) return false;
      return true;
    }).toList();
  }

  void _handleWizardGateTag(TagInfo tag) {
    final cleanEpc = tag.epc.trim().toUpperCase();
    if (cleanEpc.isEmpty) return;

    // 1. TỰ ĐỘNG NHẬN DIỆN XE PALLET (ƯU TIÊN TUYỆT ĐỐI: Không bao giờ để chip Pallet thành chip lạ)
    // 1.1. Nếu là chip của xe Pallet đang được nhận diện hiện tại
    if (_wizardDetectedPallet != null) {
      final curPalletEpc = (_wizardDetectedPallet!.rfidEpc ?? '').trim().toUpperCase();
      if (curPalletEpc == cleanEpc || _wizardDetectedPalletTag == cleanEpc) {
        _wizardUnexpectedTags.remove(cleanEpc);
        return; // Thuộc về xe Pallet đang chọn, không tính là sản phẩm hay chip lạ!
      }
    }

    // 1.2. Tra cứu xe Pallet từ danh mục CSDL (đã khai báo cố định)
    final matchedPallet = _repo.findPalletByRfid(cleanEpc);
    if (matchedPallet != null) {
      _wizardUnexpectedTags.remove(cleanEpc);
      if (matchedPallet.rfidEpc != null) {
        _wizardUnexpectedTags.remove(matchedPallet.rfidEpc!.trim().toUpperCase());
      }

      if (_wizardDetectedPallet?.palletCode != matchedPallet.palletCode || _wizardDetectedPalletTag != cleanEpc) {
        setState(() {
          _wizardDetectedPallet = matchedPallet;
          _wizardDetectedPalletTag = cleanEpc;
          _wizardUnexpectedTags.remove(cleanEpc);
        });
        _towerLight.triggerPass(reason: 'Đã nhận diện xe Pallet ${matchedPallet.palletCode} từ CSDL!');
      }
      return; // Thẻ Pallet bóc tách riêng, không tính vào chip sản phẩm hay chip lạ!
    }

    // 1.3. Fallback tra cứu bất đồng bộ từ SQLite nếu bộ nhớ repo chưa kịp đồng bộ
    _repo.findPalletByRfidAsync(cleanEpc).then((dbPallet) {
      if (dbPallet != null && mounted) {
        setState(() {
          _wizardDetectedPallet = dbPallet;
          _wizardDetectedPalletTag = cleanEpc;
          _wizardUnexpectedTags.remove(cleanEpc);
          if (dbPallet.rfidEpc != null) {
            _wizardUnexpectedTags.remove(dbPallet.rfidEpc!.trim().toUpperCase());
          }
        });
        _towerLight.triggerPass(reason: 'Đã nhận diện xe Pallet ${dbPallet.palletCode} từ CSDL!');
      }
    });

    // 2. Nhận diện sản phẩm trong danh mục thùng hàng đã nạp
    final expectedSerials = _getWizardExpectedSerials();
    if (expectedSerials.contains(cleanEpc)) {
      if (!_wizardScannedTags.containsKey(cleanEpc)) {
        _wizardScannedTags[cleanEpc] = tag;
        _wizardUnexpectedTags.remove(cleanEpc);

        if (_wizardScannedTags.length >= expectedSerials.length) {
          _tagBatchUiTimer?.cancel();
          _tagBatchUiTimer = null;
          setState(() {});
          final pCode = _wizardDetectedPallet?.palletCode ?? 'Xe Pallet';
          _towerLight.triggerPass(reason: 'Pallet $pCode: Đã quét đủ ${expectedSerials.length} sản phẩm qua cổng!');
          _stopWizardScan();
        } else {
          if (_tagBatchUiTimer == null || !_tagBatchUiTimer!.isActive) {
            _tagBatchUiTimer = Timer(const Duration(milliseconds: 60), () {
              if (mounted) setState(() {});
            });
          }
        }
      }
      return;
    }

    // 3. CHIP LẠ: Thẻ không thuộc Pallet và không có trong danh sách hàng cần nhập!
    // Kiểm tra an toàn cuối cùng: nếu EPC này là của bất kỳ xe Pallet nào thì không bao giờ thêm vào chip lạ
    final isAnyPallet = _repo.pallets.any((p) =>
        (p.rfidEpc ?? '').trim().toUpperCase() == cleanEpc ||
        p.palletCode.toUpperCase() == cleanEpc);
    if (isAnyPallet) {
      return;
    }

    if (!_wizardUnexpectedTags.containsKey(cleanEpc)) {
      _wizardUnexpectedTags[cleanEpc] = tag;
      if (_tagBatchUiTimer == null || !_tagBatchUiTimer!.isActive) {
        _tagBatchUiTimer = Timer(const Duration(milliseconds: 60), () {
          if (mounted) setState(() {});
        });
      }
    }

    // Cảnh báo chip lạ ngoài đơn hàng
    final now = DateTime.now();
    if (_lastWarningTime == null || now.difference(_lastWarningTime!).inMilliseconds > 1500) {
      _lastWarningTime = now;
      _towerLight.triggerWarningRed(withBuzzer: true, reason: 'Phát hiện chip lạ ngoài đơn: $cleanEpc');
    }
  }

  Future<void> _completeGoodsReceiveAtGate() async {
    final expectedSerials = _getWizardExpectedSerials();
    final expectedCount = expectedSerials.length;
    final scannedCount = _wizardScannedTags.length;

    // Nếu chưa tự động nhận diện được xe Pallet qua cổng, tự chọn xe đầu tiên trong CSDL hoặc yêu cầu
    if (_wizardDetectedPallet == null) {
      if (_repo.pallets.isNotEmpty) {
        setState(() {
          _wizardDetectedPallet = _repo.pallets.first;
          _wizardDetectedPalletTag = _wizardDetectedPallet!.rfidEpc;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Vui lòng cho xe Pallet qua cổng quét hoặc khai báo mã xe Pallet!')),
        );
        return;
      }
    }

    final palletCode = _wizardDetectedPallet!.palletCode;
    final rfidEpc = _wizardDetectedPalletTag ?? _wizardDetectedPallet!.rfidEpc;

    // Chặn hoàn toàn nếu có chip lạ
    final unexpList = _getFilteredUnexpectedTags();
    if (unexpList.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 4),
          content: Text('⛔ KHÔNG THỂ TIẾP TỤC NHẬP KHO: Phát hiện ${unexpList.length} chip lạ ngoài danh sách! Vui lòng loại bỏ hàng lạ khỏi xe Pallet trước khi hoàn tất.'),
        ),
      );
      return;
    }

    // Cảnh báo nếu chưa đủ số lượng
    if (expectedCount > 0 && scannedCount < expectedCount) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _eyeCare.colors.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('Chưa đối soát đủ số lượng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Text(
            'Hệ thống mới quét được $scannedCount / $expectedCount sản phẩm (còn thiếu ${expectedCount - scannedCount} sản phẩm).\n\nBạn có chắc chắn muốn hoàn tất nhập kho cho xe $palletCode với số lượng này không?',
            style: TextStyle(color: _eyeCare.colors.textPrimary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Quét tiếp'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Vẫn hoàn tất nhập kho'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    try {
      if (_wizardIsScanning) _stopWizardScan();

      // Gán các sản phẩm đã chọn vào Pallet trong CSDL
      final itemEpcs = _wizardSelectedCartons.isNotEmpty
          ? _getWizardExpectedSerials().toList()
          : _wizardScannedTags.keys.toList();

      await _repo.assignItemsToPallet(
        palletCode: palletCode,
        rfidEpc: rfidEpc,
        itemEpcs: itemEpcs,
      );

      if (_wizardSelectedCartons.isNotEmpty) {
        await _repo.assignCartonsToPallet(
          palletCode: palletCode,
          rfidEpc: rfidEpc,
          cartonCodes: _wizardSelectedCartons.toList(),
        );
      }

      // Cập nhật trạng thái inStock và vị trí lưu kho
      for (final it in _repo.items) {
        if ((it.palletId != null && it.palletId!.toUpperCase() == palletCode.toUpperCase()) ||
            itemEpcs.contains(it.epc) ||
            (it.orderNo != null && _wizardSelectedCartons.contains(it.orderNo))) {
          it.status = ItemStatus.inStock;
          it.palletId = palletCode;
        }
      }

      // Cập nhật InboundOrder hoàn tất nếu toàn bộ sản phẩm đơn đã nhập
      for (final order in _repo.inboundOrders) {
        final orderItems = _repo.items.where((i) => i.orderNo == order.orderNo).toList();
        if (orderItems.isNotEmpty && orderItems.every((i) => i.status == ItemStatus.inStock)) {
          order.status = InboundOrderStatus.completed;
          _pendingLoadedOrderNos.remove(order.orderNo);
        }
      }

      if (!mounted) return;

      // Hiển thị thông báo hoàn tất ngay trên màn hình mà không cần chuyển các bước phía sau
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (dialogCtx) => AlertDialog(
          backgroundColor: _eyeCare.colors.bgCard,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: const BorderSide(color: Color(0xFF10B981), width: 1.5),
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_circle, size: 50, color: Color(0xFF10B981)),
                ),
                const SizedBox(height: 14),
                Text(
                  'XÁC NHẬN ĐỌC ĐỦ THÀNH CÔNG!',
                  style: TextStyle(color: _eyeCare.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Đã đối soát đủ $scannedCount/$expectedCount sản phẩm • Không có chip lạ.\nDữ liệu đã được lưu CSDL và sẵn sàng đồng bộ sang máy PDA.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _eyeCare.colors.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: _eyeCare.colors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: Icon(Icons.arrow_back, size: 16, color: _eyeCare.colors.textPrimary),
                        label: Text('VỀ CHỌN ĐƠN', style: TextStyle(color: _eyeCare.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                        onPressed: () {
                          Navigator.of(dialogCtx).pop();
                          _resetWizard();
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('QUÉT TIẾP XE KHÁC', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                        onPressed: () {
                          Navigator.of(dialogCtx).pop();
                          setState(() {
                            _wizardScannedTags.clear();
                            _wizardUnexpectedTags.clear();
                            _wizardDetectedPallet = null;
                            _wizardDetectedPalletTag = null;
                          });
                          _desktopUhf.clearTags();
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi khi hoàn tất nhập kho: $e')),
        );
      }
    }
  }

  void _resetWizard() {
    _wizardCountdownTimer?.cancel();
    _uhf.stopInventory();
    _desktopUhf.stopInventory();
    setState(() {
      _wizardIsScanning = false;
      _wizardScanCountdown = _wizardScanDuration;
      _wizardDetectedPallet = null;
      _wizardDetectedPalletTag = null;
      _wizardSelectedCartons.clear();
      _wizardSelectedEpcs.clear();
      _wizardScannedTags.clear();
      _wizardUnexpectedTags.clear();
      _receiptCartons.clear();
      _wizardCartonSearchQuery = '';
      _invalidateCartonCaches();
      _wizardStep = 1;
    });
  }

  /// Dọn dẹp các đơn hàng nháp và chip tạm thời được nạp từ file nếu chưa xác nhận hoàn tất nhập kho
  Future<void> _cleanupPendingDraftOrders() async {
    try {
      final ordersToDelete = <String>{..._pendingLoadedOrderNos};
      for (final c in _receiptCartons) {
        final ord = c['_orderNo']?.toString();
        if (ord != null && ord.isNotEmpty) ordersToDelete.add(ord);
      }

      for (final ordNo in ordersToDelete) {
        final existingOrder = _repo.inboundOrders.where((o) => o.orderNo == ordNo || o.inboundOrderId == ordNo).firstOrNull;
        if (existingOrder != null && existingOrder.status == InboundOrderStatus.newOrder) {
          await _repo.deleteInboundOrder(ordNo);
        }
      }

      final epcsToClean = <String>{
        ..._wizardSelectedEpcs,
        for (final c in _receiptCartons)
          ...((c['serials'] as List<dynamic>?)?.map((e) => e.toString().trim().toUpperCase()) ?? [])
      };
      if (epcsToClean.isNotEmpty) {
        final itemsToDelete = _repo.items
            .where((i) => epcsToClean.contains(i.epc.toUpperCase()) && i.status == ItemStatus.pendingInbound)
            .map((i) => i.epc)
            .toList();
        if (itemsToDelete.isNotEmpty) {
          await _repo.deleteItemsByEpcs(itemsToDelete);
        }
      }
    } catch (e) {
      debugPrint('Lỗi dọn dẹp đơn hàng nạp file nháp: $e');
    } finally {
      _pendingLoadedOrderNos.clear();
    }
  }

  /// Xử lý bấm nút LÀM MỚI: Xóa sạch dữ liệu file đã nạp để người dùng chọn lại file khác
  Future<void> _handleRefreshOrClearFile() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final messenger = ScaffoldMessenger.of(context);
      final hadLoadedData = _receiptCartons.isNotEmpty ||
          _pendingLoadedOrderNos.isNotEmpty ||
          _wizardSelectedEpcs.isNotEmpty;

      // 1. Dọn dẹp đơn hàng nháp và chip tạm trong CSDL
      await _cleanupPendingDraftOrders();

      // 2. Dừng quét và xóa sạch dữ liệu trên giao diện
      _wizardCountdownTimer?.cancel();
      _uhf.stopInventory();
      _desktopUhf.stopInventory();

      _receiptCartons.clear();
      _wizardSelectedCartons.clear();
      _wizardSelectedEpcs.clear();
      _wizardScannedTags.clear();
      _wizardUnexpectedTags.clear();
      _wizardDetectedPallet = null;
      _wizardDetectedPalletTag = null;
      _wizardCartonSearchQuery = '';
      _wizardIsScanning = false;
      _wizardScanCountdown = _wizardScanDuration;
      _wizardStep = 1;
      _invalidateCartonCaches();

      // 3. Tải lại và đồng bộ CSDL
      await _supabaseSync.syncNow();
      await _repo.reloadFromSqlite();

      if (mounted) {
        setState(() {});
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
            content: Text(
              hadLoadedData
                  ? 'Đã xóa dữ liệu file đã nạp. Bạn có thể chọn nạp file mới!'
                  : 'Đã làm mới và đồng bộ dữ liệu kho thành công!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi khi làm mới: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _showPalletManagementDialog() {
    final c = _eyeCare.colors;
    final codeCtrl = TextEditingController();
    final rfidCtrl = TextEditingController();
    Pallet? editingPallet;

    StreamSubscription? dlgSub1;
    StreamSubscription? dlgSub2;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final allPallets = _repo.pallets;

            // Lắng nghe thẻ quét từ cổng RFID khi hộp thoại đang mở để tự điền mã chip
            dlgSub1 ??= _uhf.onTagRead.listen((tag) {
              if (dialogCtx.mounted) {
                rfidCtrl.text = tag.epc;
                setDialogState(() {});
              }
            });
            dlgSub2 ??= _desktopUhf.onTagRead.listen((tag) {
              if (dialogCtx.mounted) {
                rfidCtrl.text = tag.epc;
                setDialogState(() {});
              }
            });

            return Dialog(
              backgroundColor: c.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: c.border),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800, maxHeight: 660),
                child: Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: Quản Lý Pallet gọn gàng
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFF59E0B)),
                            ),
                            child: const Icon(Icons.layers, color: Color(0xFFF59E0B), size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Quản Lý Pallet Cố Định & Gắn Chip RFID',
                                  style: TextStyle(color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Thêm 1 lần dùng mãi mãi cho mọi lần nhập/xuất kho. Chỉ cần cập nhật hoặc xóa khi chip/pallet bị hỏng.',
                                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: c.textSecondary),
                            onPressed: () {
                              dlgSub1?.cancel();
                              dlgSub2?.cancel();
                              Navigator.of(dialogCtx).pop();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Form khai báo / sửa chip Pallet
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: c.bgCardElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: editingPallet != null ? const Color(0xFFF59E0B) : c.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  editingPallet != null
                                      ? '🛠️ SỬA MÃ XE PALLET & CẬP NHẬT CHIP RFID: ${editingPallet!.palletCode}'
                                      : 'THÊM PALLET & GẮN CHIP RFID CỐ ĐỊNH:',
                                  style: TextStyle(
                                    color: editingPallet != null ? const Color(0xFFF59E0B) : c.rfidCyan,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (editingPallet != null)
                                  TextButton.icon(
                                    style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                                    icon: const Icon(Icons.close, size: 14, color: Color(0xFFEF4444)),
                                    label: const Text('Hủy sửa', style: TextStyle(fontSize: 11, color: Color(0xFFEF4444))),
                                    onPressed: () {
                                      editingPallet = null;
                                      codeCtrl.clear();
                                      rfidCtrl.clear();
                                      setDialogState(() {});
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: codeCtrl,
                                    enabled: true,
                                    style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                    decoration: InputDecoration(
                                      labelText: 'Mã Pallet / Mã xe',
                                      labelStyle: TextStyle(color: c.textSecondary, fontSize: 11),
                                      hintText: 'Nhập hoặc sửa mã Pallet',
                                      hintStyle: TextStyle(color: c.textSecondary.withValues(alpha: 0.5), fontSize: 11),
                                      filled: true,
                                      fillColor: c.bgDeep,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: rfidCtrl,
                                    style: TextStyle(color: c.rfidCyan, fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 12),
                                    decoration: InputDecoration(
                                      labelText: 'Mã thẻ RFID (EPC) - Quét chip hoặc nhập',
                                      labelStyle: TextStyle(color: c.textSecondary, fontSize: 11),
                                      hintText: 'Quét chip hoặc nhập mã RFID (EPC)',
                                      hintStyle: TextStyle(color: c.textSecondary.withValues(alpha: 0.5), fontSize: 11),
                                      filled: true,
                                      fillColor: c.bgDeep,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: editingPallet != null ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                  icon: Icon(editingPallet != null ? Icons.sync : Icons.save, size: 16),
                                  label: Text(
                                    editingPallet != null ? 'CẬP NHẬT PALLET' : 'LƯU PALLET',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                                  ),
                                  onPressed: () async {
                                    final pCode = codeCtrl.text.trim().toUpperCase();
                                    if (pCode.isEmpty) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Vui lòng nhập Mã Pallet!')),
                                      );
                                      return;
                                    }
                                    final pRfid = rfidCtrl.text.trim().isNotEmpty
                                        ? rfidCtrl.text.trim().toUpperCase()
                                        : _convertPalletNameToHexAscii(pCode);

                                    final oldPalletCode = editingPallet?.palletCode;
                                    await _repo.registerOrUpdatePallet(
                                      palletCode: pCode,
                                      rfidEpc: pRfid,
                                      oldPalletCode: oldPalletCode,
                                    );

                                    setState(() {
                                      if (_wizardDetectedPallet?.palletCode == oldPalletCode ||
                                          _wizardDetectedPallet?.palletCode == pCode ||
                                          _wizardDetectedPallet == null) {
                                        _wizardDetectedPallet = _repo.pallets.where((p) => p.palletCode == pCode).firstOrNull;
                                        _wizardDetectedPalletTag = pRfid;
                                      }
                                      _wizardUnexpectedTags.remove(pRfid);
                                    });

                                    editingPallet = null;
                                    codeCtrl.clear();
                                    rfidCtrl.clear();
                                    setDialogState(() {});
                                    setState(() {});

                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          backgroundColor: const Color(0xFF10B981),
                                          content: Text('✅ Đã lưu Pallet $pCode (RFID: $pRfid) vào CSDL vĩnh viễn!'),
                                        ),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Danh sách các Pallet đã lưu trong CSDL
                      Text('DANH SÁCH PALLET HIỆN CÓ TRONG KHO (${allPallets.length}):', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: c.bgDeep,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: c.border),
                          ),
                          child: Column(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: c.bgCardElevated,
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                                  border: Border(bottom: BorderSide(color: c.border)),
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(width: 45, child: Text('STT', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                    const SizedBox(width: 10),
                                    SizedBox(width: 130, child: Text('MÃ PALLET', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text('MÃ THẺ RFID (EPC)', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                    const SizedBox(width: 10),
                                    SizedBox(width: 180, child: Text('THAO TÁC', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: allPallets.isEmpty
                                    ? Center(
                                        child: Text(
                                          'Chưa có Pallet nào trong kho. Hãy nhập form phía trên để thêm 1 lần (dùng vĩnh viễn).',
                                          style: TextStyle(color: c.textSecondary, fontSize: 12),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: allPallets.length,
                                        itemBuilder: (context, idx) {
                                          final p = allPallets[idx];
                                          final isCurrentSelected = _wizardDetectedPallet?.palletCode == p.palletCode;

                                          return Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            decoration: BoxDecoration(
                                              color: isCurrentSelected ? const Color(0xFF10B981).withValues(alpha: 0.08) : Colors.transparent,
                                              border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.4))),
                                            ),
                                            child: Row(
                                              children: [
                                                SizedBox(width: 45, child: Text('${idx + 1}', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11.5))),
                                                const SizedBox(width: 10),
                                                SizedBox(
                                                  width: 130,
                                                  child: Row(
                                                    children: [
                                                      const Icon(Icons.layers, size: 14, color: Color(0xFFF59E0B)),
                                                      const SizedBox(width: 6),
                                                      Text(p.palletCode, style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12.5)),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    p.rfidEpc ?? '--',
                                                    style: TextStyle(color: c.rfidCyan, fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.w600),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                SizedBox(
                                                  width: 180,
                                                  child: Row(
                                                    mainAxisAlignment: MainAxisAlignment.end,
                                                    children: [
                                                      TextButton.icon(
                                                        style: TextButton.styleFrom(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                                          foregroundColor: const Color(0xFF10B981),
                                                        ),
                                                        icon: const Icon(Icons.check, size: 14),
                                                        label: const Text('Chọn', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                                        onPressed: () {
                                                          dlgSub1?.cancel();
                                                          dlgSub2?.cancel();
                                                          setState(() {
                                                            _wizardDetectedPallet = p;
                                                            _wizardDetectedPalletTag = p.rfidEpc;
                                                          });
                                                          Navigator.of(dialogCtx).pop();
                                                          ScaffoldMessenger.of(context).showSnackBar(
                                                            SnackBar(
                                                              backgroundColor: const Color(0xFF10B981),
                                                              content: Text('Đã chọn Pallet: ${p.palletCode}'),
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF3B82F6)),
                                                        tooltip: 'Sửa / Thay chip RFID mới khi chip cũ bị hỏng',
                                                        onPressed: () {
                                                          editingPallet = p;
                                                          codeCtrl.text = p.palletCode;
                                                          rfidCtrl.text = p.rfidEpc ?? '';
                                                          setDialogState(() {});
                                                        },
                                                      ),
                                                      IconButton(
                                                        icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                                                        tooltip: 'Xóa khỏi danh mục khi Pallet bị hư hỏng',
                                                        onPressed: () async {
                                                          await _repo.deletePalletFromMaster(p.palletCode);
                                                          if (_wizardDetectedPallet?.palletCode == p.palletCode) {
                                                            setState(() {
                                                              _wizardDetectedPallet = null;
                                                              _wizardDetectedPalletTag = null;
                                                            });
                                                          }
                                                          if (editingPallet?.palletCode == p.palletCode) {
                                                            editingPallet = null;
                                                            codeCtrl.clear();
                                                            rfidCtrl.clear();
                                                          }
                                                          setDialogState(() {});
                                                          setState(() {});
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      dlgSub1?.cancel();
      dlgSub2?.cancel();
    });
  }

  Future<void> _pickAndLoadLiveExcelFile() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final result = await _excelService.pickAndParseGoodsReceiveExcel();
      if (result == null) return;

      // Xóa và dọn dẹp các đơn hàng nháp cũ chưa xác nhận trước khi nạp file mới
      await _cleanupPendingDraftOrders();

      final now = DateTime.now();
      final inboundOrderNo = 'NK-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      for (var carton in result.cartons) {
        carton['_orderNo'] = inboundOrderNo;
        final rawCode = carton['productCode']?.toString().trim() ?? '';
        if (!RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(rawCode)) {
          carton['productCode'] = _repo.generateHexBarcode128();
        }
      }

      final List<Item> explicitItems = [];
      int itemSeq = 1;
      for (var c in result.cartons) {
        final cartonBox = c['cartonBox']?.toString().trim();
        final serialItems = (c['serialItems'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (serialItems != null && serialItems.isNotEmpty) {
          for (var sItem in serialItems) {
            final sSerial = sItem['serial'].toString().trim();
            final sBarcode = sItem['barcode']?.toString().trim() ?? c['productCode'];
            final sName = sItem['name']?.toString().trim() ?? c['productName'];
            explicitItems.add(Item(
              itemId: 'ITEM-${now.millisecondsSinceEpoch}-$itemSeq',
              productId: sBarcode,
              sku: sBarcode,
              productName: sName,
              serialNumber: sSerial,
              epc: sSerial,
              status: ItemStatus.pendingInbound,
              orderNo: inboundOrderNo,
              palletId: cartonBox != null && cartonBox.isNotEmpty ? cartonBox : null,
            ));
            itemSeq++;
          }
        } else {
          final serials = (c['serials'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
          for (var serial in serials) {
            explicitItems.add(Item(
              itemId: 'ITEM-${now.millisecondsSinceEpoch}-$itemSeq',
              productId: c['productCode'],
              sku: c['productCode'],
              productName: c['productName'],
              serialNumber: serial,
              epc: serial,
              status: ItemStatus.pendingInbound,
              orderNo: inboundOrderNo,
              palletId: cartonBox != null && cartonBox.isNotEmpty ? cartonBox : null,
            ));
            itemSeq++;
          }
        }
      }

      // Gom chi tiết đơn theo từng SKU riêng biệt
      final Map<String, InboundOrderDetail> detailMap = {};
      for (var item in explicitItems) {
        if (detailMap.containsKey(item.sku)) {
          final old = detailMap[item.sku]!;
          detailMap[item.sku] = InboundOrderDetail(
            productId: item.productId,
            sku: item.sku,
            productName: item.productName,
            requiredQty: old.requiredQty + 1,
          );
        } else {
          detailMap[item.sku] = InboundOrderDetail(
            productId: item.productId,
            sku: item.sku,
            productName: item.productName,
            requiredQty: 1,
          );
        }
      }

      // 1. CẬP NHẬT GIAO DIỆN NGAY LẬP TỨC: Hiển thị danh sách ngay, chống chớp nháy và biến mất
      setState(() {
        _receiptCartons.clear();
        _receiptCartons.addAll(result.cartons);
        _wizardSelectedCartons.clear();
        for (var c in result.cartons) {
          final box = (c['cartonBox'] ?? c['code'] ?? '').toString().trim();
          if (box.isNotEmpty) _wizardSelectedCartons.add(box);
        }
        _wizardSelectedEpcs.clear();
        for (var it in explicitItems) {
          if (it.epc.isNotEmpty) _wizardSelectedEpcs.add(it.epc.toUpperCase());
        }
        _invalidateCartonCaches();
      });

      // 2. Đăng ký toàn bộ các sản phẩm mới vào danh mục trước (bảo đảm Foreign Key hợp lệ 100%)
      final seenSkus = <String>{};
      final newProducts = <Product>[];
      for (var item in explicitItems) {
        if (item.sku.isNotEmpty && seenSkus.add(item.sku)) {
          newProducts.add(Product(
            productId: item.productId,
            sku: item.sku,
            productName: item.productName,
            category: 'Hàng nhập qua cổng RFID',
            unit: 'Cái',
          ));
        }
      }
      if (newProducts.isNotEmpty) {
        await _repo.addProductsBatch(newProducts);
      }

      // 3. Lưu trữ cơ sở dữ liệu an toàn qua Batch (siêu tốc < 10ms)
      var order = _repo.inboundOrders.where((o) => o.orderNo == inboundOrderNo).firstOrNull;
      if (order == null) {
        order = InboundOrder(
          inboundOrderId: inboundOrderNo,
          orderNo: inboundOrderNo,
          sourceSupplier: 'File: ${result.fileName}',
          status: InboundOrderStatus.newOrder,
          createdAt: now,
          details: detailMap.values.toList(),
        );
        await _repo.addInboundOrder(order, autoGenerateEpcs: false);
        await _repo.insertDirectItems(explicitItems);
      } else {
        final existingEpcs = _repo.items.map((i) => i.epc.toUpperCase()).toSet();
        final newItems = explicitItems.where((item) => !existingEpcs.contains(item.epc.toUpperCase())).toList();
        if (newItems.isNotEmpty) {
          await _repo.insertDirectItems(newItems);
        }
      }

      _pendingLoadedOrderNos.clear();
      _pendingLoadedOrderNos.add(inboundOrderNo);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('Đã nạp file "${result.fileName}" (${explicitItems.length} chip) thành công!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi nạp file Excel: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _pickAndLoadPoFile() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final rows = await _excelService.pickAndParseBatchOrdersExcel();
      if (rows == null || rows.isEmpty) return;

      // Xóa và dọn dẹp các đơn hàng nháp cũ chưa xác nhận trước khi nạp file mới
      await _cleanupPendingDraftOrders();

      final now = DateTime.now();
      final List<Item> explicitItems = [];
      final List<Map<String, dynamic>> cartons = [];
      final Map<String, List<Map<String, dynamic>>> poGroup = {};

      for (var r in rows) {
        final po = (r['orderNo'] ?? 'PO-001').toString().trim();
        poGroup.putIfAbsent(po, () => []).add(r);
      }

      int itemSeq = 1;
      final Map<String, InboundOrderDetail> detailMap = {};

      for (var entry in poGroup.entries) {
        final poNo = entry.key;
        final poRows = entry.value;
        final List<String> serials = [];
        final List<Map<String, dynamic>> serialItems = [];

        for (var r in poRows) {
          final sku = (r['sku'] ?? '--').toString().trim();
          final prodName = (r['productName'] ?? 'Sản phẩm PO').toString().trim();
          final qty = (r['quantity'] as int?) ?? 1;
          final rowEpc = (r['epc'] ?? '').toString().trim();

          for (int q = 0; q < qty; q++) {
            final epc = (q == 0 && rowEpc.isNotEmpty)
                ? rowEpc
                : _repo.generateHexBarcode128();

            serials.add(epc);
            serialItems.add({
              'serial': epc,
              'barcode': sku,
              'name': prodName,
              'sku': sku,
            });

            explicitItems.add(Item(
              itemId: 'ITEM-${now.millisecondsSinceEpoch}-$itemSeq',
              productId: sku,
              sku: sku,
              productName: prodName,
              serialNumber: epc,
              epc: epc,
              status: ItemStatus.pendingInbound,
              orderNo: poNo,
              palletId: poNo,
            ));
            itemSeq++;

            if (detailMap.containsKey(sku)) {
              final old = detailMap[sku]!;
              detailMap[sku] = InboundOrderDetail(
                productId: sku,
                sku: sku,
                productName: prodName,
                requiredQty: old.requiredQty + 1,
              );
            } else {
              detailMap[sku] = InboundOrderDetail(
                productId: sku,
                sku: sku,
                productName: prodName,
                requiredQty: 1,
              );
            }
          }
        }

        cartons.add({
          '_orderNo': poNo,
          'cartonBox': poNo,
          'code': poNo,
          'productCode': poRows.first['sku'] ?? '--',
          'productName': poRows.first['productName'] ?? 'Hàng theo PO',
          'serials': serials,
          'serialItems': serialItems,
        });
      }

      // 1. CẬP NHẬT GIAO DIỆN NGAY LẬP TỨC: Hiển thị danh sách ngay, chống chớp nháy và biến mất
      setState(() {
        _receiptCartons.clear();
        _receiptCartons.addAll(cartons);
        _wizardSelectedCartons.clear();
        for (var c in cartons) {
          final box = (c['cartonBox'] ?? c['code'] ?? '').toString().trim();
          if (box.isNotEmpty) _wizardSelectedCartons.add(box);
        }
        _wizardSelectedEpcs.clear();
        for (var it in explicitItems) {
          if (it.epc.isNotEmpty) _wizardSelectedEpcs.add(it.epc.toUpperCase());
        }
        _invalidateCartonCaches();
      });

      // 2. Đăng ký toàn bộ các sản phẩm mới vào danh mục trước (bảo đảm Foreign Key hợp lệ 100%)
      final seenSkus = <String>{};
      final newProducts = <Product>[];
      for (var item in explicitItems) {
        if (item.sku.isNotEmpty && seenSkus.add(item.sku)) {
          newProducts.add(Product(
            productId: item.productId,
            sku: item.sku,
            productName: item.productName,
            category: 'Hàng nhập đơn PO',
            unit: 'Cái',
          ));
        }
      }
      if (newProducts.isNotEmpty) {
        await _repo.addProductsBatch(newProducts);
      }

      // 3. Lưu trữ cơ sở dữ liệu an toàn qua Batch (siêu tốc < 10ms)
      for (var entry in poGroup.entries) {
        final poNo = entry.key;
        var order = _repo.inboundOrders.where((o) => o.orderNo == poNo).firstOrNull;
        if (order == null) {
          order = InboundOrder(
            inboundOrderId: poNo,
            orderNo: poNo,
            sourceSupplier: entry.value.first['supplier']?.toString() ?? 'Nhà cung cấp PO',
            status: InboundOrderStatus.newOrder,
            createdAt: now,
            details: detailMap.values.where((d) => entry.value.any((r) => r['sku'] == d.sku)).toList(),
          );
          await _repo.addInboundOrder(order, autoGenerateEpcs: false);
        }
      }

      await _repo.insertDirectItems(explicitItems);

      _pendingLoadedOrderNos.clear();
      _pendingLoadedOrderNos.addAll(poGroup.keys);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('Đã nạp file PO thành công (${explicitItems.length} chip sản phẩm từ ${poGroup.length} PO)!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi nạp file PO: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }


  // ---------- GIAO DIỆN CHÍNH ----------

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        const minW = 1150.0;
        const minH = 650.0;
        final isNarrow = constraints.maxWidth < minW;
        final isShort = constraints.maxHeight < minH;

        final contentW = isNarrow ? minW : constraints.maxWidth;
        final contentH = isShort ? minH : constraints.maxHeight;

        Widget mainContent = Container(
          width: contentW,
          height: contentH,
          color: c.bgDeep,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Bar
              Wrap(
                spacing: 16,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'Quản Lý Nhập Kho',
                    style: TextStyle(color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      // Nút Nhập Hàng với 2 lựa chọn (File Excel hoặc File nhập PO)
                      PopupMenuButton<String>(
                        enabled: !_isImporting,
                        tooltip: 'Chọn nguồn nhập hàng',
                        offset: const Offset(0, 44),
                        constraints: const BoxConstraints(minWidth: 380, maxWidth: 440),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(color: c.border),
                        ),
                        color: c.bgCardElevated,
                        elevation: 6,
                        onSelected: (value) {
                          if (_isImporting) return;
                          if (value == 'excel') {
                            _pickAndLoadLiveExcelFile();
                          } else if (value == 'po') {
                            _pickAndLoadPoFile();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'excel',
                            enabled: !_isImporting,
                            child: SizedBox(
                              width: 360,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.table_chart, color: Color(0xFF10B981), size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'File Danh Sách Thùng Hàng (.xlsx)',
                                          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Nạp file chứa Carton Box, SKU, Serial/EPC chuẩn bị nhập',
                                          style: TextStyle(color: c.textSecondary, fontSize: 11),
                                          softWrap: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const PopupMenuDivider(),
                          PopupMenuItem<String>(
                            value: 'po',
                            enabled: !_isImporting,
                            child: SizedBox(
                              width: 360,
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: c.rfidCyan.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(Icons.receipt_long, color: c.rfidCyan, size: 20),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'File Nhập PO (Đơn Mua Hàng)',
                                          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Nạp file đơn PO: Mã PO, Nhà cung cấp, SKU, Số lượng',
                                          style: TextStyle(color: c.textSecondary, fontSize: 11),
                                          softWrap: true,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: _isImporting ? c.rfidCyan.withValues(alpha: 0.5) : c.rfidCyan,
                            borderRadius: BorderRadius.circular(8),
                            boxShadow: [
                              BoxShadow(
                                color: c.rfidCyan.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_isImporting)
                                const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2C251E)),
                                )
                              else
                                const Icon(Icons.file_download_outlined, size: 18, color: Color(0xFF2C251E)),
                              const SizedBox(width: 6),
                              Text(
                                _isImporting ? 'ĐANG XỬ LÝ...' : 'NHẬP HÀNG',
                                style: const TextStyle(
                                  color: Color(0xFF2C251E),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF2C251E)),
                            ],
                          ),
                        ),
                      ),

                      Tooltip(
                        message: 'Xóa dữ liệu file đã nạp để chọn lại file mới',
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.textPrimary,
                            side: BorderSide(color: c.border),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: Icon(Icons.refresh, size: 16, color: c.textPrimary),
                          label: Text('LÀM MỚI', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: _isImporting ? null : _handleRefreshOrClearFile,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Khung nội dung nhập kho
              Expanded(
                child: _buildStepByStepWizard(c),
              ),
            ],
          ),
        );

        if (isNarrow || isShort) {
          return SingleChildScrollView(
            scrollDirection: Axis.vertical,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: mainContent,
            ),
          );
        }
        return mainContent;
      },
    );
  }

  // ---------- CONTAINER NỘI DUNG NHẬP KHO ----------

  Widget _buildStepByStepWizard(EyeCareColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _buildWizardStepContent(c),
      ),
    );
  }

  Widget _buildWizardStepContent(EyeCareColors c) {
    switch (_wizardStep) {
      case 1:
        return _buildStep1CartonSkuBinding(c);
      case 2:
      default:
        return _buildStep2GateRfidAndPallet(c);
    }
  }

  // ---------- BƯỚC 1: GÁN SKU VỚI TỪNG THÙNG HÀNG (DẠNG BẢNG DOANH NGHIỆP) ----------
  Widget _buildStep1CartonSkuBinding(EyeCareColors c) {
    final cartons = _getAvailableCartons();
    final allDetailedItems = _getStep1DetailedItems();
    final totalSerials = allDetailedItems.length;

    // Auto-select all on first load if nothing selected yet
    if (allDetailedItems.isNotEmpty && _wizardSelectedEpcs.isEmpty && _wizardSelectedCartons.isEmpty) {
      for (var it in allDetailedItems) {
        final s = (it['serial'] ?? '').toString().trim().toUpperCase();
        if (s.isNotEmpty) _wizardSelectedEpcs.add(s);
      }
      for (var item in cartons) {
        final b = (item['cartonBox'] ?? item['code'] ?? '').toString().trim();
        if (b.isNotEmpty) _wizardSelectedCartons.add(b);
      }
    }

    final allSelected = allDetailedItems.isNotEmpty &&
        allDetailedItems.every((item) => _wizardSelectedEpcs.contains((item['serial'] ?? '').toString().trim().toUpperCase()));

    final query = _wizardCartonSearchQuery.trim().toUpperCase();
    final filteredDetails = query.isEmpty
        ? allDetailedItems
        : allDetailedItems.where((item) {
            final boxCode = (item['boxCode'] ?? '').toString().toUpperCase();
            final sku = (item['sku'] ?? '').toString().toUpperCase();
            final prodName = (item['productName'] ?? '').toString().toUpperCase();
            final serial = (item['serial'] ?? '').toString().toUpperCase();
            return boxCode.contains(query) || sku.contains(query) || prodName.contains(query) || serial.contains(query);
          }).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sub toolbar: Select all + Search box + View Mode Switch + Counter Badges
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    setState(() {
                      if (allSelected) {
                        _wizardSelectedEpcs.clear();
                        _wizardSelectedCartons.clear();
                      } else {
                        for (var it in allDetailedItems) {
                          final s = (it['serial'] ?? '').toString().trim().toUpperCase();
                          if (s.isNotEmpty) _wizardSelectedEpcs.add(s);
                        }
                        for (var item in cartons) {
                          final b = (item['cartonBox'] ?? item['code'] ?? '').toString().trim();
                          if (b.isNotEmpty) _wizardSelectedCartons.add(b);
                        }
                      }
                      _cachedExpectedSerials = null;
                      _cachedStep2FlatItems = null;
                    });
                  },
                  child: Row(
                    children: [
                      Checkbox(
                        value: allSelected,
                        activeColor: c.rfidCyan,
                        checkColor: const Color(0xFF2C251E),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              for (var it in allDetailedItems) {
                                final s = (it['serial'] ?? '').toString().trim().toUpperCase();
                                if (s.isNotEmpty) _wizardSelectedEpcs.add(s);
                              }
                              for (var item in cartons) {
                                final b = (item['cartonBox'] ?? item['code'] ?? '').toString().trim();
                                if (b.isNotEmpty) _wizardSelectedCartons.add(b);
                              }
                            } else {
                              _wizardSelectedEpcs.clear();
                              _wizardSelectedCartons.clear();
                            }
                            _cachedExpectedSerials = null;
                            _cachedStep2FlatItems = null;
                          });
                        },
                      ),
                      Text(
                        'Chọn tất cả (${allDetailedItems.length} chip)',
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const Spacer(),

                // Total counter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.bgDeep,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.nfc, size: 14, color: c.rfidCyan),
                      const SizedBox(width: 6),
                      Text(
                        'Tổng: $totalSerials chip sản phẩm',
                        style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // BẢNG DỮ LIỆU THÙNG HÀNG & MÃ SKU (DẠNG BẢNG CHI TIẾT)
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: [
                  // Table Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                    decoration: BoxDecoration(
                      color: c.bgDeep,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      border: Border(bottom: BorderSide(color: c.border)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 45,
                          child: Center(
                            child: Checkbox(
                              value: allSelected,
                              activeColor: c.rfidCyan,
                              checkColor: const Color(0xFF2C251E),
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    for (var it in allDetailedItems) {
                                      final s = (it['serial'] ?? '').toString().trim().toUpperCase();
                                      if (s.isNotEmpty) _wizardSelectedEpcs.add(s);
                                    }
                                    for (var item in cartons) {
                                      final b = (item['cartonBox'] ?? item['code'] ?? '').toString().trim();
                                      if (b.isNotEmpty) _wizardSelectedCartons.add(b);
                                    }
                                  } else {
                                    _wizardSelectedEpcs.clear();
                                    _wizardSelectedCartons.clear();
                                  }
                                  _cachedExpectedSerials = null;
                                  _cachedStep2FlatItems = null;
                                });
                              },
                            ),
                          ),
                        ),
                        SizedBox(width: 45, child: Text('STT', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        SizedBox(width: 145, child: Text('MÃ THÙNG HÀNG', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        SizedBox(width: 180, child: Text('MÃ SKU', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        Expanded(flex: 3, child: Text('TÊN SẢN PHẨM / QUY CÁCH', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        Expanded(flex: 3, child: Text('MÃ CHIP RFID (EPC GÁN RIÊNG)', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        SizedBox(width: 110, child: Text('TRẠNG THÁI', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),

                  // Table Rows
                  Expanded(
                    child: allDetailedItems.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(32),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.inbox_outlined, size: 48, color: c.textSecondary.withValues(alpha: 0.6)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Chưa có dữ liệu hàng hóa nhập kho',
                                    style: TextStyle(color: c.textPrimary, fontSize: 14.5, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Vui lòng bấm nút [NHẬP HÀNG] ở góc trên để nạp file Excel hoặc file nhập PO',
                                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.builder(
                                physics: const BouncingScrollPhysics(),
                                itemCount: filteredDetails.length,
                                itemBuilder: (context, index) {
                                  final item = filteredDetails[index];
                                  final boxCode = (item['boxCode'] ?? 'THUNG').toString();
                                  final sku = (item['sku'] ?? '--').toString();
                                  final prodName = (item['productName'] ?? 'Sản phẩm').toString();
                                  final serial = (item['serial'] ?? '').toString();
                                  final isSelected = _wizardSelectedEpcs.contains(serial.toUpperCase());

                                  return InkWell(
                                    onTap: () {
                                      setState(() {
                                        if (isSelected) {
                                          _wizardSelectedEpcs.remove(serial.toUpperCase());
                                        } else {
                                          _wizardSelectedEpcs.add(serial.toUpperCase());
                                        }
                                        _wizardSelectedCartons.clear();
                                        for (var d in allDetailedItems) {
                                          if (_wizardSelectedEpcs.contains((d['serial'] as String).toUpperCase())) {
                                            _wizardSelectedCartons.add((d['boxCode'] ?? '').toString());
                                          }
                                        }
                                        _cachedExpectedSerials = null;
                                        _cachedStep2FlatItems = null;
                                      });
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? c.rfidCyan.withValues(alpha: 0.08)
                                            : (index % 2 == 0 ? Colors.transparent : c.bgDeep.withValues(alpha: 0.25)),
                                        border: Border(
                                          bottom: BorderSide(
                                            color: isSelected
                                                ? c.rfidCyan.withValues(alpha: 0.3)
                                                : c.border.withValues(alpha: 0.4),
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          SizedBox(
                                            width: 45,
                                            child: Center(
                                              child: Checkbox(
                                                value: isSelected,
                                                activeColor: c.rfidCyan,
                                                checkColor: const Color(0xFF2C251E),
                                                onChanged: (val) {
                                                  setState(() {
                                                    if (val == true) {
                                                      _wizardSelectedEpcs.add(serial.toUpperCase());
                                                    } else {
                                                      _wizardSelectedEpcs.remove(serial.toUpperCase());
                                                    }
                                                    _wizardSelectedCartons.clear();
                                                    for (var d in allDetailedItems) {
                                                      if (_wizardSelectedEpcs.contains((d['serial'] as String).toUpperCase())) {
                                                        _wizardSelectedCartons.add((d['boxCode'] ?? '').toString());
                                                      }
                                                    }
                                                    _cachedExpectedSerials = null;
                                                    _cachedStep2FlatItems = null;
                                                  });
                                                },
                                              ),
                                            ),
                                          ),
                                          SizedBox(
                                            width: 45,
                                            child: Text(
                                              '${index + 1}',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 145,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(5),
                                                  border: Border.all(color: const Color(0xFF3B82F6)),
                                                ),
                                                child: Text(
                                                  boxCode,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 11.5),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 180,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(5),
                                                  border: Border.all(color: const Color(0xFF8B5CF6)),
                                                ),
                                                child: Text(
                                                  sku,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Color(0xFF8B5CF6),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 11.5,
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 3,
                                            child: Text(
                                              prodName,
                                              overflow: TextOverflow.ellipsis,
                                              maxLines: 2,
                                              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            flex: 3,
                                            child: Align(
                                              alignment: Alignment.centerLeft,
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: c.bgDeep,
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: c.border),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.nfc, size: 12, color: c.rfidCyan),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      serial,
                                                      style: TextStyle(
                                                        color: c.textPrimary,
                                                        fontFamily: 'monospace',
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 11,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 110,
                                            child: Center(
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                decoration: BoxDecoration(
                                                  color: isSelected
                                                      ? c.rfidCyan.withValues(alpha: 0.15)
                                                      : c.bgDeep,
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(
                                                    color: isSelected
                                                        ? c.rfidCyan
                                                        : c.border,
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                                                      size: 13,
                                                      color: isSelected ? c.rfidCyan : c.textSecondary,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      isSelected ? 'ĐÃ CHỌN' : 'CHƯA CHỌN',
                                                      style: TextStyle(
                                                        color: isSelected ? c.rfidCyan : c.textSecondary,
                                                        fontSize: 10,
                                                        fontWeight: FontWeight.bold,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Bottom Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 18, color: c.rfidCyan),
                const SizedBox(width: 8),
                Text(
                  'Đã chọn: ${_wizardSelectedEpcs.length} / ${allDetailedItems.length} chip sản phẩm',
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.rfidCyan,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.arrow_forward, color: Color(0xFF2C251E), size: 17),
                  label: const Text(
                    'TIẾP TỤC: QUA CỔNG QUÉT RFID & NHẬN PALLET ➜',
                    style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  onPressed: () {
                    if (cartons.isEmpty && allDetailedItems.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Vui lòng nạp file Excel danh sách thùng hàng trước!')),
                      );
                      return;
                    }
                    if (_wizardSelectedEpcs.isEmpty) {
                      for (var it in allDetailedItems) {
                        final s = (it['serial'] ?? '').toString().trim().toUpperCase();
                        if (s.isNotEmpty) _wizardSelectedEpcs.add(s);
                      }
                      for (var item in cartons) {
                        final b = (item['cartonBox'] ?? item['code'] ?? '').toString().trim();
                        if (b.isNotEmpty) _wizardSelectedCartons.add(b);
                      }
                    }
                    _cachedExpectedSerials = null;
                    _cachedStep2FlatItems = null;
                    setState(() => _wizardStep = 2);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- BƯỚC 2: CỔNG QUÉT RFID & TỰ ĐỘNG NHẬN DIỆN XE PALLET ----------
  Widget _buildStep2GateRfidAndPallet(EyeCareColors c) {
    final expectedSerials = _getWizardExpectedSerials();
    final expectedCount = expectedSerials.length;
    final scannedCount = _wizardScannedTags.length;
    final isComplete = expectedCount > 0 && scannedCount >= expectedCount;
    final progress = expectedCount > 0 ? (scannedCount / expectedCount).clamp(0.0, 1.0) : 0.0;
    final unexpList = _getFilteredUnexpectedTags();
    final hasUnexpectedTags = unexpList.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Gate Status & Pallet Auto-detection Card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isComplete
                    ? const Color(0xFF10B981)
                    : (_wizardDetectedPallet != null ? c.rfidCyan : c.border),
                width: isComplete || _wizardDetectedPallet != null ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _wizardDetectedPallet != null
                            ? const Color(0xFF10B981).withValues(alpha: 0.15)
                            : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _wizardDetectedPallet != null ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        ),
                      ),
                      child: Icon(
                        _wizardDetectedPallet != null ? Icons.check_circle : Icons.sensors,
                        color: _wizardDetectedPallet != null ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 10,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                _wizardDetectedPallet != null
                                    ? 'Xe Pallet: ${_wizardDetectedPallet!.palletCode}'
                                    : 'Chờ Quét Xe Pallet',
                                style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _wizardDetectedPallet != null
                                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                      : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: _wizardDetectedPallet != null ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _wizardDetectedPallet != null ? Icons.verified : Icons.sync,
                                      size: 13,
                                      color: _wizardDetectedPallet != null ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _wizardDetectedPallet != null
                                          ? '✓ TỰ ĐỘNG NHẬN DIỆN TỪ CSDL'
                                          : 'ĐANG CHỜ XE QUA CỔNG',
                                      style: TextStyle(
                                        color: _wizardDetectedPallet != null ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _wizardDetectedPallet != null
                                ? 'Mã xe: ${_wizardDetectedPallet!.palletCode} • RFID: ${_wizardDetectedPalletTag ?? _wizardDetectedPallet!.rfidEpc ?? '--'} • ${_wizardSelectedCartons.length} thùng'
                                : 'Xe Pallet gắn chip RFID đi qua cổng sẽ được tự động nhận diện từ CSDL mà không cần chọn lại.',
                            style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: c.rfidCyan.withValues(alpha: 0.8)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: Icon(Icons.layers_outlined, size: 16, color: c.rfidCyan),
                      label: Text('QUẢN LÝ PALLET', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5)),
                      onPressed: _showPalletManagementDialog,
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // Progress Indicator & Hero Quantity Counter
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: hasUnexpectedTags
                        ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                        : (isComplete
                            ? const Color(0xFF10B981).withValues(alpha: 0.08)
                            : (scannedCount > 0 ? const Color(0xFFF59E0B).withValues(alpha: 0.06) : c.bgDeep)),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: hasUnexpectedTags
                          ? const Color(0xFFEF4444)
                          : (isComplete
                              ? const Color(0xFF10B981).withValues(alpha: 0.4)
                              : (scannedCount > 0 ? const Color(0xFFF59E0B).withValues(alpha: 0.3) : c.border)),
                      width: hasUnexpectedTags ? 1.5 : 1.0,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TIẾN ĐỘ ĐỐI SOÁT HÀNG QUA CỔNG:',
                                style: TextStyle(
                                  color: hasUnexpectedTags ? const Color(0xFFEF4444) : c.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                hasUnexpectedTags
                                    ? '⛔ PHÁT HIỆN ${unexpList.length} CHIP LẠ! KHÔNG ĐƯỢC PHÉP NHẬP KHO'
                                    : (isComplete
                                        ? '✅ ĐÃ ĐỐI SOÁT ĐỦ TOÀN BỘ SẢN PHẨM • SẴN SÀNG XÁC NHẬN ĐỌC ĐỦ'
                                        : (scannedCount > 0
                                            ? '⚡ ĐANG QUÉT... (CÒN THIẾU ${expectedCount - scannedCount} SẢN PHẨM)'
                                            : 'Chờ xe hàng đi qua cổng quét RFID...')),
                                style: TextStyle(
                                  color: hasUnexpectedTags
                                      ? const Color(0xFFEF4444)
                                      : (isComplete
                                          ? const Color(0xFF10B981)
                                          : (scannedCount > 0 ? const Color(0xFFF59E0B) : c.textSecondary.withValues(alpha: 0.7))),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                          const Spacer(),
                          () {
                            final unexpList = _getFilteredUnexpectedTags();
                            if (unexpList.isEmpty) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFFEF4444)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.error, size: 14, color: Color(0xFFEF4444)),
                                    const SizedBox(width: 5),
                                    Text(
                                      'CÓ ${unexpList.length} CHIP LẠ!',
                                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11.5, fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }(),

                          // SỐ LƯỢNG TO & DỄ NHÌN (HERO QUANTITY DISPLAY)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                            decoration: BoxDecoration(
                              color: isComplete
                                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                  : (scannedCount > 0 ? const Color(0xFFF59E0B).withValues(alpha: 0.12) : c.bgCard),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isComplete
                                    ? const Color(0xFF10B981)
                                    : (scannedCount > 0 ? const Color(0xFFF59E0B) : c.border),
                                width: 1.5,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  '$scannedCount',
                                  style: TextStyle(
                                    color: isComplete
                                        ? const Color(0xFF10B981)
                                        : (scannedCount > 0 ? const Color(0xFFF59E0B) : c.textPrimary),
                                    fontSize: 34,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  child: Text(
                                    '/',
                                    style: TextStyle(
                                      color: c.textSecondary.withValues(alpha: 0.6),
                                      fontSize: 24,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  '$expectedCount',
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'sản phẩm',
                                  style: TextStyle(
                                    color: c.textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isComplete ? const Color(0xFF10B981) : c.rfidCyan,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '${(progress * 100).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 10,
                          backgroundColor: c.bgCard,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            isComplete ? const Color(0xFF10B981) : (scannedCount > 0 ? const Color(0xFFF59E0B) : c.rfidCyan),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Realtime Inspection Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: c.bgDeep,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      border: Border(bottom: BorderSide(color: c.border)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 45, child: Text('STT', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        SizedBox(width: 145, child: Text('THÙNG HÀNG', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        SizedBox(width: 180, child: Text('MÃ SKU', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        Expanded(flex: 3, child: Text('TÊN SẢN PHẨM', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        Expanded(flex: 3, child: Text('MÃ CHIP RFID (EPC)', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        SizedBox(width: 160, child: Text('TRẠNG THÁI CỔNG', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: () {
                      final flatItems = _getStep2FlatInspectionItems();
                      final unexpectedList = _getFilteredUnexpectedTags();
                      final totalRowCount = flatItems.length + unexpectedList.length;

                      if (totalRowCount == 0) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.inventory_2_outlined, size: 38, color: c.textSecondary),
                                const SizedBox(height: 10),
                                Text(
                                  'Chưa có sản phẩm nào để đối soát qua cổng',
                                  style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Vui lòng quay lại để nạp danh sách thùng hàng.',
                                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: totalRowCount,
                        itemBuilder: (context, index) {
                          // 1. Phân chia: Sản phẩm trong danh sách nạp đơn
                          if (index < flatItems.length) {
                            final item = flatItems[index];
                            final boxCode = item['boxCode'] as String;
                            final sku = item['sku'] as String;
                            final prodName = item['productName'] as String;
                            final serial = item['serial'] as String;
                            final isScanned = _wizardScannedTags.containsKey(serial.toUpperCase());

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isScanned ? const Color(0xFF10B981).withValues(alpha: 0.08) : Colors.transparent,
                                border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.4))),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 45,
                                    child: Text(
                                      '${index + 1}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: isScanned ? const Color(0xFF10B981) : c.textSecondary,
                                        fontWeight: isScanned ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 145,
                                    child: Text(
                                      boxCode,
                                      style: TextStyle(
                                        color: isScanned ? const Color(0xFF10B981) : c.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 180,
                                    child: Text(
                                      sku,
                                      style: TextStyle(
                                        color: isScanned ? const Color(0xFF10B981) : c.textSecondary,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.w600,
                                        fontSize: 11.5,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      prodName,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isScanned ? const Color(0xFF10B981) : c.textPrimary,
                                        fontWeight: isScanned ? FontWeight.bold : FontWeight.normal,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      serial,
                                      style: TextStyle(
                                        color: isScanned ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 160,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isScanned
                                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                              : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isScanned ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isScanned ? Icons.check_circle : Icons.hourglass_top,
                                              size: 12,
                                              color: isScanned ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              isScanned ? '✓ ĐÃ QUA CỔNG' : '⏳ CHỜ QUA CỔNG',
                                              style: TextStyle(
                                                color: isScanned ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }

                          // 2. Phân chia: Chip lạ ngoài danh mục (hiển thị màu ĐỎ)
                          final unexpIndex = index - flatItems.length;
                          final unexpTag = unexpectedList[unexpIndex];

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                              border: Border(bottom: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.3))),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 45,
                                  child: Text(
                                    '${index + 1}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11.5),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 145,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'NGOÀI ĐƠN',
                                      style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const SizedBox(
                                  width: 180,
                                  child: Text('CHIP LẠ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11.5)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    'Thẻ RFID lạ chưa khai báo (RSSI: ${unexpTag.rssi} dBm • Ant ${unexpTag.ant})',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    unexpTag.epc,
                                    style: const TextStyle(
                                      color: Color(0xFFEF4444),
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 160,
                                  child: Center(
                                    child: InkWell(
                                      borderRadius: BorderRadius.circular(6),
                                      onTap: () {
                                        setState(() {
                                          _wizardUnexpectedTags.remove(unexpTag.epc.toUpperCase());
                                        });
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            backgroundColor: const Color(0xFF3B82F6),
                                            duration: const Duration(seconds: 1),
                                            content: Text('Đã bỏ qua chip lạ: ${unexpTag.epc}'),
                                          ),
                                        );
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFEF4444)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.warning, size: 12, color: Color(0xFFEF4444)),
                                            SizedBox(width: 4),
                                            Text(
                                              '❌ CHIP LẠ',
                                              style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5, fontWeight: FontWeight.bold),
                                            ),
                                            SizedBox(width: 4),
                                            Icon(Icons.close, size: 12, color: Color(0xFFEF4444)),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    }(),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Bottom Navigation Bar (Đã bỏ toàn bộ các bước cất kho kệ phía sau)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.border),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: Icon(Icons.arrow_back, size: 16, color: c.textPrimary),
                  label: Text('⮜ Quay Lại Chọn Đơn', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () => setState(() => _wizardStep = 1),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: c.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: Icon(Icons.refresh, size: 16, color: c.textSecondary),
                  label: Text('Làm Mới Quét', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  onPressed: () {
                    setState(() {
                      _wizardScannedTags.clear();
                      _wizardUnexpectedTags.clear();
                      _wizardDetectedPallet = null;
                      _wizardDetectedPalletTag = null;
                    });
                    _desktopUhf.clearTags();
                  },
                ),
                const Spacer(),
                // Bộ chọn thời gian quét: 5s, 10s, Liên tục
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: c.bgDeep,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildScanDurationButton(5, '5s', c),
                      const SizedBox(width: 2),
                      _buildScanDurationButton(10, '10s', c),
                      const SizedBox(width: 2),
                      _buildScanDurationButton(0, 'Liên tục', c),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Nút Quét
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _wizardIsScanning ? const Color(0xFFEF4444) : c.rfidCyan,
                    foregroundColor: _wizardIsScanning ? Colors.white : const Color(0xFF2C251E),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 2,
                  ),
                  icon: Icon(_wizardIsScanning ? Icons.stop : Icons.sensors, size: 18),
                  label: Text(
                    _wizardIsScanning
                        ? (_wizardScanDuration == 0
                            ? 'DỪNG QUÉT LIÊN TỤC'
                            : 'DỪNG QUÉT ($_wizardScanCountdown s)')
                        : (scannedCount > 0
                            ? 'TIẾP TỤC QUÉT (${_wizardScanDuration == 0 ? "LIÊN TỤC" : "${_wizardScanDuration}s"})'
                            : 'BẮT ĐẦU QUÉT (${_wizardScanDuration == 0 ? "LIÊN TỤC" : "${_wizardScanDuration}s"})'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  onPressed: _toggleWizardScan,
                ),
                const SizedBox(width: 12),
                // Nút Hoàn tất nhập kho trực tiếp tại cổng (Chặn nếu có chip lạ, cho phép xác nhận khi đủ)
                if (hasUnexpectedTags)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      foregroundColor: const Color(0xFFEF4444),
                      side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    icon: const Icon(Icons.block, size: 18, color: Color(0xFFEF4444)),
                    label: Text(
                      '⛔ CÓ ${unexpList.length} CHIP LẠ - KHÔNG THỂ NHẬP KHO',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                    ),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFFEF4444),
                          duration: const Duration(seconds: 4),
                          content: Text(
                            '⛔ KHÔNG THỂ TIẾP TỤC NHẬP KHO: Phát hiện ${unexpList.length} chip lạ ngoài danh sách! Vui lòng loại bỏ hàng lạ khỏi xe Pallet trước khi hoàn tất.',
                          ),
                        ),
                      );
                    },
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isComplete
                          ? const Color(0xFF10B981)
                          : (scannedCount > 0 ? const Color(0xFF059669) : c.border),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: isComplete ? 3 : 1,
                    ),
                    icon: const Icon(Icons.check_circle, size: 18),
                    label: Text(
                      isComplete
                          ? 'XÁC NHẬN ĐỌC ĐỦ'
                          : (scannedCount > 0
                              ? 'LƯU & ĐỌC ĐỦ [$scannedCount/$expectedCount]'
                              : 'XÁC NHẬN ĐỌC ĐỦ'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    onPressed: (scannedCount > 0 && !hasUnexpectedTags) ? _completeGoodsReceiveAtGate : null,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanDurationButton(int seconds, String label, EyeCareColors c) {
    final isSelected = _wizardScanDuration == seconds;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: _wizardIsScanning
          ? null
          : () {
              setState(() {
                _wizardScanDuration = seconds;
                _wizardScanCountdown = seconds;
              });
            },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (seconds == 0)
              Icon(
                Icons.all_inclusive,
                size: 13,
                color: isSelected ? const Color(0xFF2C251E) : c.textSecondary,
              )
            else
              Icon(
                Icons.timer_outlined,
                size: 13,
                color: isSelected ? const Color(0xFF2C251E) : c.textSecondary,
              ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFF2C251E) : c.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
