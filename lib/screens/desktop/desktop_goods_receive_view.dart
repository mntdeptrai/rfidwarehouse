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

  // ---------- TRẠNG THÁI CỔNG NHẬP KHO QUÉT LIÊN TỤC ĐA ĐƠN HÀNG ----------
  bool _isImporting = false;
  final List<Map<String, dynamic>> _receiptCartons = [];
  final Set<String> _wizardSelectedCartons = {};
  final Set<String> _wizardSelectedEpcs = {};
  final List<String> _pendingLoadedOrderNos = [];

  // Thông tin xe hàng & Đơn hàng đang đi qua cổng hiện tại
  String? _activeOrderNo;
  Pallet? _activePallet;
  String? _activePalletTag;
  List<Item> _activeExpectedItems = [];

  // Pallet tự động nhận diện từ CSDL hoặc chọn nhanh
  Pallet? _wizardDetectedPallet;
  String? _wizardDetectedPalletTag;

  final Map<String, TagInfo> _wizardScannedTags = {};
  final Map<String, TagInfo> _wizardUnexpectedTags = {};
  bool _wizardIsScanning = false;
  int _wizardScanDuration = 0; // 0 = liên tục (mặc định cho cổng quét), 5s, 10s
  int _wizardScanCountdown = 0;
  Timer? _wizardCountdownTimer;

  // Trạng thái báo lỗi sai sót theo đơn hàng khi qua cổng
  bool _hasDiscrepancyError = false;
  String? _discrepancyOrderNo;
  String? _discrepancyPalletCode;
  List<Item> _discrepancyMissingItems = [];
  List<TagInfo> _discrepancyUnexpectedTags = [];

  // Thông báo đối soát thành công (tự động giải phóng sau 3s)
  String? _lastSuccessOrderNo;
  String? _lastSuccessPalletCode;
  int _lastSuccessCount = 0;
  Timer? _successBannerTimer;

  // Lịch sử các xe đã qua cổng thành công trong ca
  final List<Map<String, dynamic>> _recentCompletedPasses = [];

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
    for (final tag in _desktopUhf.tags) {
      _handleWizardGateTag(tag);
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
    _successBannerTimer?.cancel();
    super.dispose();
  }

  void _handleIncomingTag(TagInfo tag) {
    if (!widget.isActive) return;
    _handleWizardGateTag(tag);
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
    final Set<String> set = {};
    if (_activeExpectedItems.isNotEmpty) {
      set.addAll(_activeExpectedItems.map((i) => i.epc.trim().toUpperCase()));
    } else if (_wizardSelectedEpcs.isNotEmpty) {
      set.addAll(_wizardSelectedEpcs.map((e) => e.trim().toUpperCase()));
    } else {
      final cartons = _getAvailableCartons();
      for (var c in cartons) {
        final box = (c['cartonBox'] ?? c['code'] ?? '').toString().trim();
        if (_wizardSelectedCartons.contains(box)) {
          final serials = (c['serials'] as List<dynamic>?)?.map((e) => e.toString().trim().toUpperCase()).toList() ?? [];
          set.addAll(serials);
        }
      }
    }

    // Gom tất cả các xe Pallet có gắn chip RFID liên quan đến đợt hàng (hỗ trợ cả 1, 2 hay nhiều Pallet cùng lúc)
    final Set<Pallet> relevantPallets = {};
    if (_activePallet != null) relevantPallets.add(_activePallet!);
    if (_wizardDetectedPallet != null) relevantPallets.add(_wizardDetectedPallet!);

    // Lấy tất cả pallet từ _activeExpectedItems
    if (_activeExpectedItems.isNotEmpty) {
      final pIds = _activeExpectedItems.map((i) => i.palletId).where((id) => id != null && id.isNotEmpty).toSet();
      for (final pId in pIds) {
        final pFound = _repo.pallets.where((item) =>
          item.palletId.toUpperCase() == pId!.toUpperCase() ||
          item.palletCode.toUpperCase() == pId.toUpperCase() ||
          item.palletId.toUpperCase() == 'PAL-${pId.toUpperCase()}' ||
          'PAL-${item.palletCode.toUpperCase()}' == pId.toUpperCase()
        ).firstOrNull;
        if (pFound != null) relevantPallets.add(pFound);
      }
    }

    // Lấy tất cả pallet từ _receiptCartons
    if (_receiptCartons.isNotEmpty) {
      for (final c in _receiptCartons) {
        final pCode = c['palletCode']?.toString();
        final pEpc = c['palletEpc']?.toString();
        if (pCode != null && pCode.isNotEmpty) {
          final pFound = _repo.pallets.where((item) =>
            item.palletCode.toUpperCase() == pCode.toUpperCase() ||
            item.palletId.toUpperCase() == pCode.toUpperCase() ||
            item.palletId.toUpperCase() == 'PAL-${pCode.toUpperCase()}' ||
            'PAL-${item.palletCode.toUpperCase()}' == pCode.toUpperCase()
          ).firstOrNull;
          if (pFound != null) relevantPallets.add(pFound);
        }
        if (pEpc != null && pEpc.isNotEmpty) {
          final pFound = _repo.findPalletByRfid(pEpc);
          if (pFound != null) relevantPallets.add(pFound);
        }
      }
    }

    // Thêm RFID của tất cả Pallet liên quan vào danh sách cần đối soát
    for (final pal in relevantPallets) {
      final epc = (pal.rfidEpc ?? '').trim().toUpperCase();
      if (epc.isNotEmpty) {
        set.add(epc);
      }
    }
    if (_wizardDetectedPalletTag != null && _wizardDetectedPalletTag!.isNotEmpty) {
      set.add(_wizardDetectedPalletTag!.trim().toUpperCase());
    }
    if (_activePalletTag != null && _activePalletTag!.isNotEmpty) {
      set.add(_activePalletTag!.trim().toUpperCase());
    }

    _cachedExpectedSerials = set;
    return set;
  }

  List<Map<String, dynamic>> _getStep1DetailedItems() {
    if (_cachedStep1DetailedItems != null) return _cachedStep1DetailedItems!;
    final List<Map<String, dynamic>> list = [];
    if (_activeExpectedItems.isNotEmpty) {
      list.addAll(_activeExpectedItems.map((i) => {
        'boxCode': i.cartonCode ?? '--',
        'sku': i.sku,
        'productName': i.productName,
        'serial': i.epc,
        'supplier': i.supplier ?? '--',
        'orderNo': i.orderNo ?? '--',
      }));
    } else {
      final cartons = _getAvailableCartons();
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
          final sSupplier = (i < sItems.length ? sItems[i]['supplier'] : null) ?? cBox['supplier'] ?? 'Nhà cung cấp tổng hợp';
          list.add({
            'boxCode': boxCode,
            'sku': sku,
            'productName': prodName,
            'serial': serial,
            'supplier': sSupplier.toString(),
            'orderNo': (cBox['_orderNo'] ?? '--').toString(),
          });
        }
      }
    }

    // Đưa thẻ RFID của TẤT CẢ các Xe Pallet liên quan vào đầu bảng đối soát
    final Set<Pallet> relevantPallets = {};
    if (_activePallet != null) relevantPallets.add(_activePallet!);
    if (_wizardDetectedPallet != null) relevantPallets.add(_wizardDetectedPallet!);

    if (_activeExpectedItems.isNotEmpty) {
      final pIds = _activeExpectedItems.map((i) => i.palletId).where((id) => id != null && id.isNotEmpty).toSet();
      for (final pId in pIds) {
        final pFound = _repo.pallets.where((item) =>
          item.palletId.toUpperCase() == pId!.toUpperCase() ||
          item.palletCode.toUpperCase() == pId.toUpperCase() ||
          item.palletId.toUpperCase() == 'PAL-${pId.toUpperCase()}' ||
          'PAL-${item.palletCode.toUpperCase()}' == pId.toUpperCase()
        ).firstOrNull;
        if (pFound != null) relevantPallets.add(pFound);
      }
    }

    if (_receiptCartons.isNotEmpty) {
      for (final c in _receiptCartons) {
        final pCode = c['palletCode']?.toString();
        final pEpc = c['palletEpc']?.toString();
        if (pCode != null && pCode.isNotEmpty) {
          final pFound = _repo.pallets.where((item) =>
            item.palletCode.toUpperCase() == pCode.toUpperCase() ||
            item.palletId.toUpperCase() == pCode.toUpperCase() ||
            item.palletId.toUpperCase() == 'PAL-${pCode.toUpperCase()}' ||
            'PAL-${item.palletCode.toUpperCase()}' == pCode.toUpperCase()
          ).firstOrNull;
          if (pFound != null) relevantPallets.add(pFound);
        }
        if (pEpc != null && pEpc.isNotEmpty) {
          final pFound = _repo.findPalletByRfid(pEpc);
          if (pFound != null) relevantPallets.add(pFound);
        }
      }
    }

    int insertIdx = 0;
    for (final pal in relevantPallets) {
      final pEpc = (pal.rfidEpc ?? '').trim().toUpperCase();
      final pCode = pal.palletCode;
      if (pEpc.isNotEmpty && !list.any((e) => (e['serial'] ?? '').toString().toUpperCase() == pEpc)) {
        list.insert(insertIdx++, {
          'boxCode': 'PALLET: $pCode',
          'sku': pCode,
          'productName': '🏷️ Chip RFID Xe Pallet ($pCode)',
          'serial': pEpc,
          'supplier': list.isNotEmpty ? list.first['supplier'] : 'Xe Pallet WMS',
          'orderNo': _activeOrderNo ?? '--',
          'isPallet': true,
        });
      }
    }

    _cachedStep1DetailedItems = list;
    return list;
  }

  List<Map<String, dynamic>> _getStep2FlatInspectionItems() {
    if (_cachedStep2FlatItems != null) return _cachedStep2FlatItems!;
    final list = _getStep1DetailedItems();
    _cachedStep2FlatItems = list;
    return list;
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

    // Khi có chip mới tới cổng, xóa ngay banner thông báo thành công của đơn trước
    if (_lastSuccessOrderNo != null) {
      _lastSuccessOrderNo = null;
      _successBannerTimer?.cancel();
    }

    // 1. TỰ ĐỘNG NHẬN DIỆN XE PALLET
    // 1.1 Kiểm tra nếu đây là chip của xe Pallet đang active
    final curPalletEpc = (_activePallet?.rfidEpc ?? _wizardDetectedPalletTag ?? _wizardDetectedPallet?.rfidEpc)?.trim().toUpperCase();
    if (curPalletEpc != null && curPalletEpc.isNotEmpty && (curPalletEpc == cleanEpc || _wizardDetectedPalletTag == cleanEpc || _activePalletTag == cleanEpc)) {
      _wizardUnexpectedTags.remove(cleanEpc);
      if (!_wizardScannedTags.containsKey(cleanEpc)) {
        _wizardScannedTags[cleanEpc] = tag;
        final expectedSerials = _getWizardExpectedSerials();
        if (expectedSerials.isNotEmpty && _wizardScannedTags.length >= expectedSerials.length && _getFilteredUnexpectedTags().isEmpty) {
          _tagBatchUiTimer?.cancel();
          _tagBatchUiTimer = null;
          final pCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode ?? 'Xe Pallet';
          _towerLight.triggerPass(reason: 'Pallet $pCode: Đã quét đủ ${expectedSerials.length} chip (gồm cả chip Pallet) qua cổng!');
          _triggerPassSuccess();
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

    // 1.2 Kiểm tra nếu chip quét được là chip của một xe Pallet trong CSDL
    final matchedPallet = _repo.findPalletByRfid(cleanEpc);
    if (matchedPallet != null) {
      _wizardUnexpectedTags.remove(cleanEpc);
      if (matchedPallet.rfidEpc != null) {
        _wizardUnexpectedTags.remove(matchedPallet.rfidEpc!.trim().toUpperCase());
      }
      _wizardScannedTags[cleanEpc] = tag;

      if (_wizardDetectedPallet?.palletCode != matchedPallet.palletCode || _activePallet?.palletCode != matchedPallet.palletCode) {
        setState(() {
          _wizardDetectedPallet = matchedPallet;
          _wizardDetectedPalletTag = cleanEpc;
          _activePallet = matchedPallet;
          _activePalletTag = cleanEpc;
          _wizardUnexpectedTags.remove(cleanEpc);

          // Nếu chưa có đơn hàng active, tra cứu các sản phẩm pendingInbound của pallet này
          if (_activeOrderNo == null) {
            final pItems = _repo.items.where((i) =>
              (i.palletId == matchedPallet.palletId || i.palletId == matchedPallet.palletCode || i.palletId == 'PAL-${matchedPallet.palletCode}') &&
              i.status == ItemStatus.pendingInbound
            ).toList();
            if (pItems.isNotEmpty) {
              _activeOrderNo = pItems.first.orderNo;
              _activeExpectedItems = pItems;
              _wizardSelectedCartons.clear();
              for (var it in pItems) {
                if (it.cartonCode != null && it.cartonCode!.isNotEmpty) {
                  _wizardSelectedCartons.add(it.cartonCode!);
                }
              }
            }
          }
          _invalidateCartonCaches();
        });
        _towerLight.triggerPass(reason: 'Đã nhận diện xe Pallet ${matchedPallet.palletCode} từ CSDL!');
      }

      final expectedSerials = _getWizardExpectedSerials();
      if (expectedSerials.isNotEmpty && _wizardScannedTags.length >= expectedSerials.length && _getFilteredUnexpectedTags().isEmpty) {
        _tagBatchUiTimer?.cancel();
        _tagBatchUiTimer = null;
        final pCode = matchedPallet.palletCode;
        _towerLight.triggerPass(reason: 'Pallet $pCode: Đã quét đủ ${expectedSerials.length} chip (gồm cả chip Pallet) qua cổng!');
        _triggerPassSuccess();
      }
      return;
    }

    // 1.2 Nếu chưa xác định đơn hàng active, tự động nhận diện đơn hàng từ chip sản phẩm pendingInbound
    if (_activeOrderNo == null && _wizardSelectedEpcs.isEmpty && _receiptCartons.isEmpty) {
      final matchedPendingItem = _repo.items.where((i) =>
        i.epc.trim().toUpperCase() == cleanEpc && i.status == ItemStatus.pendingInbound
      ).firstOrNull;

      if (matchedPendingItem != null) {
        setState(() {
          _activeOrderNo = matchedPendingItem.orderNo;
          if (matchedPendingItem.palletId != null && matchedPendingItem.palletId!.isNotEmpty) {
            _activePallet = _repo.pallets.where((p) =>
              p.palletId.toUpperCase() == matchedPendingItem.palletId!.toUpperCase() ||
              p.palletCode.toUpperCase() == matchedPendingItem.palletId!.toUpperCase()
            ).firstOrNull;
            _wizardDetectedPallet = _activePallet;
            _wizardDetectedPalletTag = _activePallet?.rfidEpc;
          }
          _activeExpectedItems = _repo.items.where((i) =>
            (i.orderNo == matchedPendingItem.orderNo || (matchedPendingItem.orderNo == null && i.palletId == matchedPendingItem.palletId)) &&
            i.status == ItemStatus.pendingInbound
          ).toList();

          _wizardSelectedCartons.clear();
          for (var it in _activeExpectedItems) {
            if (it.cartonCode != null && it.cartonCode!.isNotEmpty) {
              _wizardSelectedCartons.add(it.cartonCode!);
            }
          }
          _hasDiscrepancyError = false;
          _discrepancyMissingItems.clear();
          _discrepancyUnexpectedTags.clear();
          _invalidateCartonCaches();
        });
      }
    }

    // 2. Nhận diện sản phẩm trong danh mục thùng hàng cần đối soát
    final expectedSerials = _getWizardExpectedSerials();
    if (expectedSerials.contains(cleanEpc)) {
      if (!_wizardScannedTags.containsKey(cleanEpc)) {
        _wizardScannedTags[cleanEpc] = tag;
        _wizardUnexpectedTags.remove(cleanEpc);

        if (expectedSerials.isNotEmpty && _wizardScannedTags.length >= expectedSerials.length && _getFilteredUnexpectedTags().isEmpty) {
          _tagBatchUiTimer?.cancel();
          _tagBatchUiTimer = null;
          final pCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode ?? 'Xe Pallet';
          _towerLight.triggerPass(reason: 'Pallet $pCode: Đã quét đủ ${expectedSerials.length} sản phẩm qua cổng!');
          _triggerPassSuccess();
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

  /// Tự động xác nhận thành công đơn qua cổng khi đọc đủ 100% không có chip lạ
  Future<void> _triggerPassSuccess() async {
    _tagBatchUiTimer?.cancel();
    _tagBatchUiTimer = null;

    final expectedSerials = _getWizardExpectedSerials();
    final expectedCount = expectedSerials.length;
    final scannedCount = _wizardScannedTags.length;
    final palletCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode;
    final rfidEpc = _activePalletTag ?? _wizardDetectedPalletTag ?? _activePallet?.rfidEpc;
    final orderNo = _activeOrderNo ?? (_wizardSelectedCartons.isNotEmpty ? _wizardSelectedCartons.first : 'NK-${DateTime.now().millisecondsSinceEpoch}');

    final itemEpcs = _wizardScannedTags.keys.toList();
    final cleanPalletEpc = rfidEpc?.trim().toUpperCase();
    final productEpcs = (cleanPalletEpc != null && cleanPalletEpc.isNotEmpty)
        ? itemEpcs.where((e) => e.toUpperCase() != cleanPalletEpc).toList()
        : itemEpcs;

    try {
      if (palletCode != null) {
        await _repo.assignItemsToPallet(
          palletCode: palletCode,
          rfidEpc: rfidEpc,
          itemEpcs: productEpcs,
        );
      }

      await _repo.confirmGateReceiveToWaitingPutaway(
        orderNo: orderNo,
        scannedEpcs: productEpcs,
        palletCode: palletCode,
        performedBy: 'Cổng RFID Gate',
      );

      final hasPallet = palletCode != null || _activeExpectedItems.any((i) => i.palletId != null && i.palletId!.isNotEmpty);

      _towerLight.triggerPass(reason: 'Đã đối soát đủ $scannedCount/$expectedCount chip đơn $orderNo');

      _recentCompletedPasses.insert(0, {
        'orderNo': orderNo,
        'palletCode': palletCode ?? '--',
        'count': scannedCount,
        'total': expectedCount > 0 ? expectedCount : scannedCount,
        'time': DateTime.now(),
        'status': hasPallet ? 'CHỜ XẾP KỆ' : 'XẾP VÀO PALLET',
        'isSuccess': true,
      });

      // Giải phóng xe NGAY LẬP TỨC để cổng sẵn sàng đón xe tiếp theo không cần chờ
      setState(() {
        _activeOrderNo = null;
        _activePallet = null;
        _activePalletTag = null;
        _activeExpectedItems.clear();
        _wizardScannedTags.clear();
        _wizardUnexpectedTags.clear();
        _wizardDetectedPallet = null;
        _wizardDetectedPalletTag = null;
        _hasDiscrepancyError = false;
        _discrepancyMissingItems.clear();
        _discrepancyUnexpectedTags.clear();
        _lastSuccessOrderNo = orderNo;
        _lastSuccessPalletCode = palletCode;
        _lastSuccessCount = scannedCount;
        _invalidateCartonCaches();
      });
      _desktopUhf.clearTags();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
            content: Text('✅ Đơn $orderNo ($scannedCount chip) đối soát thành công! Cổng đã giải phóng sẵn sàng đón xe tiếp theo.'),
          ),
        );
      }

      // Tự động tắt banner thành công sau 3 giây nếu chưa có xe mới
      _successBannerTimer?.cancel();
      _successBannerTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _lastSuccessOrderNo != null) {
          setState(() {
            _lastSuccessOrderNo = null;
          });
        }
      });
    } catch (e) {
      debugPrint('Lỗi xác nhận qua cổng thành công: $e');
    }
  }

  /// Báo lỗi sai sót đích danh đơn hàng qua cổng (thiếu sản phẩm hoặc có chip lạ)
  void _reportDiscrepancyError() {
    final missing = _activeExpectedItems.where((i) => !_wizardScannedTags.containsKey(i.epc.trim().toUpperCase())).toList();
    final unexp = _getFilteredUnexpectedTags();

    var p = _activePallet ?? _wizardDetectedPallet;
    if (p == null && _activeExpectedItems.isNotEmpty) {
      final pId = _activeExpectedItems.first.palletId;
      if (pId != null && pId.isNotEmpty) {
        p = _repo.pallets.where((item) =>
          item.palletId.toUpperCase() == pId.toUpperCase() ||
          item.palletCode.toUpperCase() == pId.toUpperCase() ||
          item.palletId.toUpperCase() == 'PAL-${pId.toUpperCase()}' ||
          'PAL-${item.palletCode.toUpperCase()}' == pId.toUpperCase()
        ).firstOrNull;
      }
    }
    final palletEpc = (p?.rfidEpc ?? _wizardDetectedPalletTag ?? _activePalletTag)?.trim().toUpperCase();
    if (palletEpc != null && palletEpc.isNotEmpty && !_wizardScannedTags.containsKey(palletEpc)) {
      final palletCode = p?.palletCode ?? 'Xe Pallet';
      missing.insert(0, Item(
        itemId: 'PALLET-$palletCode',
        productId: palletCode,
        sku: palletCode,
        productName: '🏷️ Thẻ RFID Xe Pallet ($palletCode)',
        serialNumber: palletEpc,
        epc: palletEpc,
        status: ItemStatus.pendingInbound,
        orderNo: _activeOrderNo,
        cartonCode: 'PALLET: $palletCode',
      ));
    }

    _towerLight.triggerWarningRed(withBuzzer: true, reason: 'Sai sót tại đơn ${_activeOrderNo ?? "--"}: Thiếu ${missing.length} chip, có ${unexp.length} chip lạ!');

    setState(() {
      _hasDiscrepancyError = true;
      _discrepancyOrderNo = _activeOrderNo ?? (_wizardSelectedCartons.isNotEmpty ? _wizardSelectedCartons.first : 'Chưa rõ mã đơn');
      _discrepancyPalletCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode;
      _discrepancyMissingItems = missing;
      _discrepancyUnexpectedTags = unexp;
    });
  }

  void _retryCurrentVehicle() {
    setState(() {
      _wizardScannedTags.clear();
      _wizardUnexpectedTags.clear();
      _hasDiscrepancyError = false;
      _discrepancyMissingItems.clear();
      _discrepancyUnexpectedTags.clear();
    });
    _desktopUhf.clearTags();
    _startWizardScan();
  }

  Future<void> _confirmPartialInbound() async {
    if (_wizardScannedTags.isEmpty) return;
    final orderNo = _activeOrderNo ?? (_wizardSelectedCartons.isNotEmpty ? _wizardSelectedCartons.first : 'NK-${DateTime.now().millisecondsSinceEpoch}');
    final palletCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode;
    final itemEpcs = _wizardScannedTags.keys.toList();
    final count = itemEpcs.length;

    await _repo.confirmGateReceiveToWaitingPutaway(
      orderNo: orderNo,
      scannedEpcs: itemEpcs,
      palletCode: palletCode,
      performedBy: 'Cổng RFID Gate (Nhập thiếu)',
    );

    final hasPallet = palletCode != null || _activeExpectedItems.any((i) => i.palletId != null && i.palletId!.isNotEmpty);

    _recentCompletedPasses.insert(0, {
      'orderNo': orderNo,
      'palletCode': palletCode ?? '--',
      'count': count,
      'total': _activeExpectedItems.isNotEmpty ? _activeExpectedItems.length : count,
      'time': DateTime.now(),
      'status': '${hasPallet ? "CHỜ XẾP KỆ" : "XẾP VÀO PALLET"} (Thiếu ${_discrepancyMissingItems.length})',
      'isSuccess': false,
    });

    setState(() {
      _hasDiscrepancyError = false;
      _activeOrderNo = null;
      _activePallet = null;
      _activePalletTag = null;
      _activeExpectedItems.clear();
      _wizardScannedTags.clear();
      _wizardUnexpectedTags.clear();
      _wizardDetectedPallet = null;
      _wizardDetectedPalletTag = null;
      _discrepancyMissingItems.clear();
      _discrepancyUnexpectedTags.clear();
      _invalidateCartonCaches();
    });
    _desktopUhf.clearTags();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFF59E0B),
          content: Text('⚠️ Đã xác nhận nhập thiếu đơn $orderNo ($count sản phẩm). Cổng sẵn sàng đón xe tiếp theo!'),
        ),
      );
    }
  }

  void _skipCurrentVehicle() {
    setState(() {
      _hasDiscrepancyError = false;
      _activeOrderNo = null;
      _activePallet = null;
      _activePalletTag = null;
      _activeExpectedItems.clear();
      _wizardScannedTags.clear();
      _wizardUnexpectedTags.clear();
      _wizardDetectedPallet = null;
      _wizardDetectedPalletTag = null;
      _discrepancyMissingItems.clear();
      _discrepancyUnexpectedTags.clear();
      _invalidateCartonCaches();
    });
    _desktopUhf.clearTags();
  }

  Future<void> _completeGoodsReceiveAtGate() async {
    final expectedSerials = _getWizardExpectedSerials();
    final expectedCount = expectedSerials.length;
    final scannedCount = _wizardScannedTags.length;

    // Chặn hoàn toàn nếu có chip lạ
    final unexpList = _getFilteredUnexpectedTags();
    if (unexpList.isNotEmpty) {
      _reportDiscrepancyError();
      return;
    }

    if (expectedCount > 0 && scannedCount < expectedCount) {
      _reportDiscrepancyError();
      return;
    }

    await _triggerPassSuccess();
  }

  void _resetWizard() {
    _wizardCountdownTimer?.cancel();
    _uhf.stopInventory();
    _desktopUhf.stopInventory();
    setState(() {
      _wizardIsScanning = false;
      _wizardScanCountdown = _wizardScanDuration;
      _activeOrderNo = null;
      _activePallet = null;
      _activePalletTag = null;
      _activeExpectedItems.clear();
      _wizardDetectedPallet = null;
      _wizardDetectedPalletTag = null;
      _wizardSelectedCartons.clear();
      _wizardSelectedEpcs.clear();
      _wizardScannedTags.clear();
      _wizardUnexpectedTags.clear();
      _hasDiscrepancyError = false;
      _discrepancyMissingItems.clear();
      _discrepancyUnexpectedTags.clear();
      _receiptCartons.clear();
      _invalidateCartonCaches();
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
      // Dọn dẹp bất kỳ đơn nháp cũ nào còn tồn ở trạng thái newOrder
      for (final o in _repo.inboundOrders.where((ord) => ord.status == InboundOrderStatus.newOrder)) {
        ordersToDelete.add(o.inboundOrderId);
        ordersToDelete.add(o.orderNo);
      }

      for (final ordNo in ordersToDelete) {
        final existingOrder = _repo.inboundOrders.where((o) => o.orderNo == ordNo || o.inboundOrderId == ordNo).firstOrNull;
        if (existingOrder != null && existingOrder.status == InboundOrderStatus.newOrder) {
          await _repo.deleteInboundOrder(ordNo);
        }
      }

      // Xóa triệt để các chip pendingInbound mồ côi (không thuộc đơn hợp lệ nào)
      final activeOrderNos = _repo.inboundOrders.map((o) => o.orderNo).toSet();
      final orphanItems = _repo.items
          .where((i) => i.status == ItemStatus.pendingInbound && (i.orderNo == null || !activeOrderNos.contains(i.orderNo)))
          .map((i) => i.epc)
          .toList();
      if (orphanItems.isNotEmpty) {
        await _repo.deleteItemsByEpcs(orphanItems);
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
      _wizardIsScanning = false;
      _wizardScanCountdown = _wizardScanDuration;
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
      final Map<String, String?> palletsToRegister = {};

      for (var c in result.cartons) {
        final palletCode = c['palletCode']?.toString().trim();
        final palletEpc = c['palletEpc']?.toString().trim();
        if (palletCode != null && palletCode.isNotEmpty) {
          palletsToRegister[palletCode] = (palletEpc != null && palletEpc.isNotEmpty) ? palletEpc : palletsToRegister[palletCode];
        }
        final serialItems = (c['serialItems'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (serialItems != null && serialItems.isNotEmpty) {
          for (var sItem in serialItems) {
            final sPallet = (sItem['pallet']?.toString().trim() ?? palletCode);
            final sPalletEpc = (sItem['palletEpc']?.toString().trim() ?? palletEpc);
            final effectivePallet = (sPallet != null && sPallet.isNotEmpty) ? sPallet : null;
            if (effectivePallet != null) {
              if (sPalletEpc != null && sPalletEpc.isNotEmpty) {
                palletsToRegister[effectivePallet] = sPalletEpc;
              } else if (!palletsToRegister.containsKey(effectivePallet)) {
                palletsToRegister[effectivePallet] = null;
              }
            }
          }
        }
      }

      // Đăng ký/cập nhật thông tin xe Pallet nếu file Excel có chứa mã Pallet hoặc RFID Pallet
      for (final entry in palletsToRegister.entries) {
        final pCode = entry.key;
        final pEpc = entry.value ?? '';
        await _repo.registerOrUpdatePallet(
          palletCode: pCode,
          rfidEpc: pEpc,
        );
      }

      for (var c in result.cartons) {
        final cartonBox = c['cartonBox']?.toString().trim();
        final palletCode = c['palletCode']?.toString().trim();
        final serialItems = (c['serialItems'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (serialItems != null && serialItems.isNotEmpty) {
          for (var sItem in serialItems) {
            final sSerial = sItem['serial'].toString().trim();
            final sBarcode = sItem['barcode']?.toString().trim() ?? c['productCode'];
            final sName = sItem['name']?.toString().trim() ?? c['productName'];
            final sSupplier = (sItem['supplier'] ?? c['supplier'] ?? 'Nhà cung cấp tổng hợp').toString().trim();
            final sPallet = (sItem['pallet']?.toString().trim() ?? palletCode);
            final effectivePallet = (sPallet != null && sPallet.isNotEmpty) ? sPallet : null;
            final assignedPalletId = effectivePallet != null
                ? (_repo.pallets.where((p) => p.palletCode.toUpperCase() == effectivePallet.toUpperCase() || p.palletId.toUpperCase() == effectivePallet.toUpperCase() || p.palletId.toUpperCase() == 'PAL-${effectivePallet.toUpperCase()}').firstOrNull?.palletId ?? (effectivePallet.toUpperCase().startsWith('PAL-') ? effectivePallet : 'PAL-$effectivePallet'))
                : null;
            final assignedOrderNo = (effectivePallet != null && palletsToRegister.length > 1)
                ? '$inboundOrderNo-$effectivePallet'
                : inboundOrderNo;
            explicitItems.add(Item(
              itemId: 'ITEM-${now.millisecondsSinceEpoch}-$itemSeq',
              productId: sBarcode,
              sku: sBarcode,
              productName: sName,
              serialNumber: sSerial,
              epc: sSerial,
              status: ItemStatus.pendingInbound,
              orderNo: assignedOrderNo,
              palletId: assignedPalletId,
              cartonCode: cartonBox != null && cartonBox.isNotEmpty ? cartonBox : null,
              supplier: sSupplier,
              inboundTime: now,
              inboundBy: 'Cổng RFID Gate',
            ));
            itemSeq++;
          }
        } else {
          final serials = (c['serials'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
          final sSupplier = (c['supplier'] ?? 'Nhà cung cấp tổng hợp').toString().trim();
          final effectivePallet = (palletCode != null && palletCode.isNotEmpty) ? palletCode : null;
          final assignedPalletId = effectivePallet != null
              ? (_repo.pallets.where((p) => p.palletCode.toUpperCase() == effectivePallet.toUpperCase() || p.palletId.toUpperCase() == effectivePallet.toUpperCase() || p.palletId.toUpperCase() == 'PAL-${effectivePallet.toUpperCase()}').firstOrNull?.palletId ?? (effectivePallet.toUpperCase().startsWith('PAL-') ? effectivePallet : 'PAL-$effectivePallet'))
              : null;
          final assignedOrderNo = (effectivePallet != null && palletsToRegister.length > 1)
              ? '$inboundOrderNo-$effectivePallet'
              : inboundOrderNo;
          for (var serial in serials) {
            explicitItems.add(Item(
              itemId: 'ITEM-${now.millisecondsSinceEpoch}-$itemSeq',
              productId: c['productCode'],
              sku: c['productCode'],
              productName: c['productName'],
              serialNumber: serial,
              epc: serial,
              status: ItemStatus.pendingInbound,
              orderNo: assignedOrderNo,
              palletId: assignedPalletId,
              cartonCode: cartonBox != null && cartonBox.isNotEmpty ? cartonBox : null,
              supplier: sSupplier,
              inboundTime: now,
              inboundBy: 'Cổng RFID Gate',
            ));
            itemSeq++;
          }
        }
      }

      // Gom chi tiết đơn theo từng đơn hàng (từng xe Pallet) và từng SKU riêng biệt
      final Map<String, Map<String, InboundOrderDetail>> ordersDetailMap = {};
      for (var item in explicitItems) {
        final ord = item.orderNo ?? inboundOrderNo;
        ordersDetailMap.putIfAbsent(ord, () => {});
        final detailMap = ordersDetailMap[ord]!;
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

      // Lưu trữ ngầm vào CSDL, không hiển thị bảng checklist tick chọn để giữ cổng quét trực tiếp
      setState(() {
        _receiptCartons.clear();
        _wizardSelectedCartons.clear();
        _wizardSelectedEpcs.clear();
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
      final firstSupplier = explicitItems.map((i) => i.supplier).where((s) => s != null && s.isNotEmpty && s != 'Nhà cung cấp tổng hợp').firstOrNull;
      final effectiveSupplier = firstSupplier ?? 'File: ${result.fileName}';

      _pendingLoadedOrderNos.clear();
      for (final entry in ordersDetailMap.entries) {
        final currentOrderNo = entry.key;
        final currentDetailMap = entry.value;

        var order = _repo.inboundOrders.where((o) => o.orderNo == currentOrderNo).firstOrNull;
        if (order == null) {
          order = InboundOrder(
            inboundOrderId: currentOrderNo,
            orderNo: currentOrderNo,
            sourceSupplier: effectiveSupplier,
            status: InboundOrderStatus.newOrder,
            createdAt: now,
            details: currentDetailMap.values.toList(),
          );
          await _repo.addInboundOrder(order, autoGenerateEpcs: false);
        }
        _pendingLoadedOrderNos.add(currentOrderNo);
      }

      final existingEpcs = _repo.items.map((i) => i.epc.toUpperCase()).toSet();
      final newItems = explicitItems.where((item) => !existingEpcs.contains(item.epc.toUpperCase())).toList();
      if (newItems.isNotEmpty) {
        await _repo.insertDirectItems(newItems);
      }

      final palletCountWithTag = palletsToRegister.values.where((rfid) => rfid != null && rfid.isNotEmpty).length;
      final totalExpectedChips = explicitItems.length + palletCountWithTag;
      final chipDesc = palletCountWithTag > 0
          ? '$totalExpectedChips chip (${explicitItems.length} hàng + $palletCountWithTag pallet)'
          : '$totalExpectedChips chip';

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 4),
          content: Text('✅ Đã nạp file "${result.fileName}" ($chipDesc) vào hệ thống! Cổng RFID sẵn sàng đối soát khi xe qua cổng.'),
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

            final poSupplier = (r['supplier'] ?? 'Nhà cung cấp PO').toString().trim();
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
              cartonCode: poNo,
              supplier: poSupplier,
              inboundTime: now,
              inboundBy: 'Cổng RFID Gate',
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

      // Lưu trữ ngầm vào CSDL, không hiển thị bảng checklist tick chọn để giữ cổng quét trực tiếp
      setState(() {
        _receiptCartons.clear();
        _wizardSelectedCartons.clear();
        _wizardSelectedEpcs.clear();
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
          duration: const Duration(seconds: 4),
          content: Text('✅ Đã nạp file PO thành công (${explicitItems.length} chip sản phẩm từ ${poGroup.length} PO)! Cổng RFID sẵn sàng đối soát khi xe qua cổng.'),
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
    return _buildStep2GateRfidAndPallet(c);
  }

  // ---------- CỔNG QUÉT RFID TỰ ĐỘNG & ĐỐI SOÁT ĐA ĐƠN HÀNG LIÊN TỤC ----------
  Widget _buildStep2GateRfidAndPallet(EyeCareColors c) {
    final expectedSerials = _getWizardExpectedSerials();
    final expectedCount = expectedSerials.length;
    final scannedCount = _wizardScannedTags.length;
    final isComplete = expectedCount > 0 && scannedCount >= expectedCount;
    final progress = expectedCount > 0 ? (scannedCount / expectedCount).clamp(0.0, 1.0) : 0.0;
    final unexpList = _getFilteredUnexpectedTags();
    final hasUnexpectedTags = unexpList.isNotEmpty;

    final isVehicleActive = _activeOrderNo != null || _activePallet != null || scannedCount > 0 || hasUnexpectedTags;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. BANNER BÁO LỖI SAI SÓT ĐÍCH DANH ĐƠN HÀNG KHI QUA CỔNG
          if (_hasDiscrepancyError) ...[
            _buildDiscrepancyErrorCard(c),
            const SizedBox(height: 12),
          ],

          // 2. BANNER THÔNG CỔNG THÀNH CÔNG (TỰ ĐỘNG RESET SAU 3S)
          if (_lastSuccessOrderNo != null && !_hasDiscrepancyError) ...[
            _buildPassSuccessBanner(c),
            const SizedBox(height: 12),
          ],

          // 3. KHUNG NỘI DUNG CHÍNH (ĐANG CÓ XE QUA CỔNG HOẶC MÀN HÌNH CHỜ QUÉT TỰ ĐỘNG)
          Expanded(
            child: isVehicleActive
                ? _buildActiveVehicleScanView(
                    c,
                    expectedSerials: expectedSerials,
                    expectedCount: expectedCount,
                    scannedCount: scannedCount,
                    isComplete: isComplete,
                    progress: progress,
                    unexpList: unexpList,
                    hasUnexpectedTags: hasUnexpectedTags,
                  )
                : _buildIdleGateMonitor(c),
          ),

          const SizedBox(height: 12),

          // 4. THANH ĐIỀU KHIỂN DƯỚI CÙNG (BOTTOM CONTROL BAR)
          _buildBottomControlBar(
            c,
            isVehicleActive: isVehicleActive,
            scannedCount: scannedCount,
            expectedCount: expectedCount,
            isComplete: isComplete,
            hasUnexpectedTags: hasUnexpectedTags,
            unexpList: unexpList,
          ),
        ],
      ),
    );
  }

  // ---------- 1. BANNER BÁO LỖI SAI SÓT THEO ĐƠN HÀNG ----------
  Widget _buildDiscrepancyErrorCard(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '⛔ PHÁT HIỆN SAI SÓT ĐỐI SOÁT - ĐƠN HÀNG: ${_discrepancyOrderNo ?? "CHƯA XÁC ĐỊNH"}',
                      style: const TextStyle(
                        color: Color(0xFFEF4444),
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Xe Pallet: ${_discrepancyPalletCode ?? "Chưa gán pallet"} • Thiếu ${_discrepancyMissingItems.length} chip sản phẩm • Có ${_discrepancyUnexpectedTags.length} chip lạ ngoài đơn',
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.replay, size: 16),
                label: const Text('QUÉT LẠI XE NÀY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                onPressed: _retryCurrentVehicle,
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.check, size: 16),
                label: const Text('XÁC NHẬN NHẬP THIẾU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                onPressed: _wizardScannedTags.isNotEmpty ? _confirmPartialInbound : null,
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: c.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                ),
                icon: const Icon(Icons.skip_next, size: 16),
                label: const Text('BỎ QUA XE NÀY', style: TextStyle(fontSize: 11.5)),
                onPressed: _skipCurrentVehicle,
              ),
            ],
          ),
          if (_discrepancyMissingItems.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('Danh sách chip thiếu:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
                  ..._discrepancyMissingItems.take(5).map((m) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${m.sku} (${m.epc})',
                      style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Color(0xFFEF4444)),
                    ),
                  )),
                  if (_discrepancyMissingItems.length > 5)
                    Text('+${_discrepancyMissingItems.length - 5} chip nữa...', style: TextStyle(fontSize: 11, color: c.textSecondary)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------- 2. BANNER THÔNG CỔNG THÀNH CÔNG ----------
  Widget _buildPassSuccessBanner(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF10B981), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '✓ ĐƠN HÀNG $_lastSuccessOrderNo ĐÃ QUA CỔNG THÀNH CÔNG!',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Xe Pallet: ${_lastSuccessPalletCode ?? "--"} • Đã ghi nhận $_lastSuccessCount/$_lastSuccessCount chip (Trạng thái: Chờ Xếp Kệ) • Đang sẵn sàng đón xe tiếp theo...',
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.autorenew, size: 14, color: Color(0xFF10B981)),
                SizedBox(width: 4),
                Text('TỰ ĐỘNG CHUYỂN TIẾP', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 3. MÀN HÌNH QUÉT KHI ĐANG CÓ XE QUA CỔNG ----------
  Widget _buildActiveVehicleScanView(
    EyeCareColors c, {
    required Set<String> expectedSerials,
    required int expectedCount,
    required int scannedCount,
    required bool isComplete,
    required double progress,
    required List<TagInfo> unexpList,
    required bool hasUnexpectedTags,
  }) {
    final activeItems = _getStep2FlatInspectionItems();
    final hasPalletTagInExpected = (_activePallet?.rfidEpc != null && _activePallet!.rfidEpc!.trim().isNotEmpty);
    final countDesc = hasPalletTagInExpected
        ? '$expectedCount chip (${expectedCount - 1} hàng + 1 pallet)'
        : '$expectedCount chip';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Card thông tin xe đang qua cổng
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: c.bgCardElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isComplete
                  ? const Color(0xFF10B981)
                  : (_activePallet != null || _wizardDetectedPallet != null ? c.rfidCyan : c.border),
              width: 1.5,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isComplete
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : (scannedCount > 0 ? const Color(0xFFF59E0B).withValues(alpha: 0.15) : c.rfidCyan.withValues(alpha: 0.15)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  isComplete ? Icons.check_circle : Icons.sensors,
                  color: isComplete
                      ? const Color(0xFF10B981)
                      : (scannedCount > 0 ? const Color(0xFFF59E0B) : c.rfidCyan),
                  size: 26,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          _activePallet != null
                              ? 'Xe Pallet: ${_activePallet!.palletCode}'
                              : (_activeOrderNo != null ? 'Đơn Hàng: $_activeOrderNo' : 'Xe Hàng Đang Qua Cổng'),
                          style: TextStyle(color: c.textPrimary, fontSize: 15.5, fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: isComplete
                                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isComplete ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                            ),
                          ),
                          child: Text(
                            isComplete ? '✓ ĐỦ TOÀN BỘ' : '⚡ ĐANG ĐỐI SOÁT TRỰC TIẾP',
                            style: TextStyle(
                              color: isComplete ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      () {
                        final palNames = <String>[];
                        if (_activePallet != null) palNames.add('${_activePallet!.palletCode} (${_activePallet!.rfidEpc ?? "--"})');
                        if (_wizardDetectedPallet != null && _wizardDetectedPallet != _activePallet) {
                          palNames.add('${_wizardDetectedPallet!.palletCode} (${_wizardDetectedPallet!.rfidEpc ?? "--"})');
                        }
                        if (_activeExpectedItems.isNotEmpty) {
                          final pIds = _activeExpectedItems.map((i) => i.palletId).where((id) => id != null && id.isNotEmpty).toSet();
                          for (final pId in pIds) {
                            final p = _repo.pallets.where((item) =>
                              item.palletId.toUpperCase() == pId!.toUpperCase() ||
                              item.palletCode.toUpperCase() == pId.toUpperCase() ||
                              item.palletId.toUpperCase() == 'PAL-${pId.toUpperCase()}'
                            ).firstOrNull;
                            if (p != null) {
                              final desc = '${p.palletCode} (${p.rfidEpc ?? "--"})';
                              if (!palNames.contains(desc)) palNames.add(desc);
                            }
                          }
                        }
                        final palDesc = palNames.isNotEmpty ? palNames.join(' • ') : (_activePalletTag ?? _wizardDetectedPalletTag ?? '--');
                        return 'Mã Đơn: ${_activeOrderNo ?? "--"} • RFID Pallet: $palDesc • Cần nhận diện: $countDesc';
                      }(),
                      style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.rfidCyan.withValues(alpha: 0.8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(Icons.layers_outlined, size: 16, color: c.rfidCyan),
                label: Text('QUẢN LÝ PALLET', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5)),
                onPressed: _showPalletManagementDialog,
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Thanh tiến độ đọc & Số lượng to (Hero Counter)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: hasUnexpectedTags
                ? const Color(0xFFEF4444).withValues(alpha: 0.08)
                : (isComplete ? const Color(0xFF10B981).withValues(alpha: 0.08) : c.bgDeep),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: hasUnexpectedTags
                  ? const Color(0xFFEF4444)
                  : (isComplete ? const Color(0xFF10B981).withValues(alpha: 0.4) : c.border),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TIẾN ĐỘ ĐỐI SOÁT QUA CỔNG:',
                      style: TextStyle(
                        color: hasUnexpectedTags ? const Color(0xFFEF4444) : c.textSecondary,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 7,
                        backgroundColor: c.border.withValues(alpha: 0.3),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          hasUnexpectedTags
                              ? const Color(0xFFEF4444)
                              : (isComplete ? const Color(0xFF10B981) : c.rfidCyan),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              if (hasUnexpectedTags)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: const Color(0xFFEF4444)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.warning, size: 14, color: Color(0xFFEF4444)),
                      const SizedBox(width: 4),
                      Text(
                        'CÓ ${unexpList.length} CHIP LẠ!',
                        style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                decoration: BoxDecoration(
                  color: isComplete
                      ? const Color(0xFF10B981).withValues(alpha: 0.15)
                      : (scannedCount > 0 ? const Color(0xFFF59E0B).withValues(alpha: 0.12) : c.bgCard),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isComplete
                        ? const Color(0xFF10B981)
                        : (scannedCount > 0 ? const Color(0xFFF59E0B) : c.border),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$scannedCount',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: isComplete
                            ? const Color(0xFF10B981)
                            : (scannedCount > 0 ? const Color(0xFFF59E0B) : c.textPrimary),
                      ),
                    ),
                    Text(
                      ' / $expectedCount',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: c.textSecondary),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'chip',
                      style: TextStyle(fontSize: 11, color: c.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Bảng danh mục sản phẩm đối soát thời gian thực
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
                // Header bảng
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.bgDeep,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                    border: Border(bottom: BorderSide(color: c.border)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 45, child: Text('STT', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      SizedBox(width: 120, child: Text('THÙNG HÀNG', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      SizedBox(width: 110, child: Text('MÃ SKU', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 3, child: Text('TÊN SẢN PHẨM / QUY CÁCH', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 3, child: Text('MÃ CHIP RFID (EPC)', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      SizedBox(width: 140, child: Text('TRẠNG THÁI CỔNG', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
                // Danh sách dòng
                Expanded(
                  child: ListView.separated(
                    itemCount: activeItems.length + unexpList.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
                    itemBuilder: (ctx, idx) {
                      if (idx < activeItems.length) {
                        final item = activeItems[idx];
                        final epc = (item['serial'] ?? '').toString().trim().toUpperCase();
                        final isScanned = _wizardScannedTags.containsKey(epc);
                        return Container(
                          color: isScanned ? const Color(0xFF10B981).withValues(alpha: 0.05) : Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              SizedBox(width: 45, child: Text('${idx + 1}', style: TextStyle(color: c.textSecondary, fontSize: 12))),
                              SizedBox(
                                width: 120,
                                child: Text(
                                  item['boxCode'] ?? '--',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              ),
                              SizedBox(width: 110, child: Text(item['sku'] ?? '--', style: TextStyle(color: c.textSecondary, fontSize: 12))),
                              Expanded(flex: 3, child: Text(item['productName'] ?? '--', style: TextStyle(color: c.textPrimary, fontSize: 12))),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  epc,
                                  style: TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 11.5,
                                    fontWeight: isScanned ? FontWeight.bold : FontWeight.normal,
                                    color: isScanned ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 140,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isScanned
                                          ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                          : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: isScanned ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                      ),
                                    ),
                                    child: Text(
                                      isScanned ? '✓ ĐÃ ĐỐI SOÁT' : '⏳ CHỜ QUA CỔNG',
                                      style: TextStyle(
                                        color: isScanned ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      } else {
                        final unexp = unexpList[idx - activeItems.length];
                        return Container(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              SizedBox(width: 45, child: Text('${idx + 1}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12))),
                              const SizedBox(width: 120, child: Text('CHIP LẠ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12))),
                              const SizedBox(width: 110, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                              const Expanded(flex: 3, child: Text('Chip không thuộc đơn hàng đang qua cổng!', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12))),
                              Expanded(flex: 3, child: Text(unexp.epc, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Color(0xFFEF4444), fontSize: 12))),
                              SizedBox(
                                width: 140,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: Color(0xFFEF4444)),
                                    ),
                                    child: const Text(
                                      '❌ CHIP LẠ',
                                      style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ---------- 4. MÀN HÌNH CHỜ QUÉT TỰ ĐỘNG KHI CHƯA CÓ XE QUA CỔNG ----------
  Widget _buildIdleGateMonitor(EyeCareColors c) {
    // Lấy dữ liệu thực tế từ Database/Repository (KHÔNG mock data)
    final validInboundOrders = _repo.inboundOrders.where((o) => o.status == InboundOrderStatus.newOrder).toList();
    final pendingItems = _repo.items.where((i) => i.status == ItemStatus.pendingInbound).toList();
    final Map<String, List<Item>> pendingOrdersMap = {};
    for (var order in validInboundOrders) {
      final ordItems = pendingItems.where((i) => i.orderNo == order.orderNo || i.orderNo == order.inboundOrderId).toList();
      if (ordItems.isNotEmpty) {
        pendingOrdersMap[order.orderNo] = ordItems;
      }
    }
    // Fallback CHỈ KHI item có orderNo trùng với một đơn newOrder hợp lệ (không tự sinh đơn giả từ item mồ côi)
    for (var item in pendingItems) {
      final ordNo = item.orderNo;
      if (ordNo != null && ordNo.isNotEmpty && !pendingOrdersMap.containsKey(ordNo)) {
        final matchingOrder = _repo.inboundOrders.where((o) => (o.orderNo == ordNo || o.inboundOrderId == ordNo) && o.status == InboundOrderStatus.newOrder).firstOrNull;
        if (matchingOrder != null) {
          pendingOrdersMap.putIfAbsent(ordNo, () => []).add(item);
        }
      }
    }
    final pendingPalletsCount = pendingItems.map((i) => i.palletId).where((p) => p != null && p.isNotEmpty).toSet().length;

    int totalPendingPalletTags = 0;
    final allPendingPalletIds = pendingItems.map((i) => i.palletId).where((p) => p != null && p.isNotEmpty).toSet();
    for (final pId in allPendingPalletIds) {
      final pObj = _repo.pallets.where((p) =>
        p.palletCode.toUpperCase() == pId!.toUpperCase() ||
        p.palletId.toUpperCase() == pId.toUpperCase() ||
        p.palletId.toUpperCase() == 'PAL-${pId.toUpperCase()}' ||
        'PAL-${p.palletCode.toUpperCase()}' == pId.toUpperCase()
      ).firstOrNull;
      if (pObj != null && pObj.rfidEpc != null && pObj.rfidEpc!.trim().isNotEmpty) {
        totalPendingPalletTags++;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Hero Gate Status Banner
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: c.bgCardElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _wizardIsScanning ? c.rfidCyan : c.border, width: _wizardIsScanning ? 1.5 : 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (_wizardIsScanning ? c.rfidCyan : const Color(0xFF10B981)).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _wizardIsScanning ? c.rfidCyan : const Color(0xFF10B981),
                    width: 1.5,
                  ),
                ),
                child: Icon(
                  Icons.sensors_rounded,
                  color: _wizardIsScanning ? c.rfidCyan : const Color(0xFF10B981),
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
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
                          'CỔNG RFID SẴN SÀNG QUÉT LIÊN TỤC',
                          style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: (_wizardIsScanning ? c.rfidCyan : const Color(0xFF10B981)).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _wizardIsScanning ? c.rfidCyan : const Color(0xFF10B981),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: _wizardIsScanning ? c.rfidCyan : const Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                _wizardIsScanning ? 'ĐẦU ĐỌC ĐANG PHÁT SÓNG QUÉT' : 'TRỰC TUYẾN • CHỜ XE QUA CỔNG',
                                style: TextStyle(
                                  color: _wizardIsScanning ? c.rfidCyan : const Color(0xFF10B981),
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
                      'Hệ thống tự động nhận diện xe Pallet hoặc mã đơn khi đi qua cổng. Đơn tới trước quét trước, đơn tới sau quét sau. Nếu có sai sót sẽ báo lỗi đích danh đơn hàng đó.',
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.rfidCyan.withValues(alpha: 0.8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(Icons.layers_outlined, size: 16, color: c.rfidCyan),
                label: Text('QUẢN LÝ PALLET', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5)),
                onPressed: _showPalletManagementDialog,
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 4 Thẻ Thống Kê Tổng Quan Trực Tuyến
        Row(
          children: [
            Expanded(
              child: _buildMetricTile(
                icon: Icons.inventory_2_outlined,
                iconColor: const Color(0xFF3B82F6),
                title: 'ĐƠN CHỜ QUA CỔNG',
                value: '${pendingOrdersMap.length} Đơn',
                subtitle: totalPendingPalletTags > 0
                    ? '${pendingItems.length + totalPendingPalletTags} chip (${pendingItems.length} hàng + $totalPendingPalletTags pallet)'
                    : '${pendingItems.length} chip sản phẩm',
                c: c,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.layers_outlined,
                iconColor: const Color(0xFFF59E0B),
                title: 'XE PALLET CHỜ THÔNG CỔNG',
                value: '$pendingPalletsCount Xe',
                subtitle: 'Gắn chip RFID xe',
                c: c,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.verified_outlined,
                iconColor: const Color(0xFF10B981),
                title: 'ĐÃ THÔNG CỔNG CA NÀY',
                value: '${_recentCompletedPasses.where((p) => p['isSuccess'] == true).length} Xe',
                subtitle: '${_recentCompletedPasses.length} lượt qua',
                c: c,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildMetricTile(
                icon: Icons.router_outlined,
                iconColor: c.rfidCyan,
                title: 'ĐẦU ĐỌC RFID CỔNG',
                value: _desktopUhf.isConnected ? 'Đã Kết Nối' : 'Sẵn Sàng',
                subtitle: _desktopUhf.isConnected ? 'Cổng COM3 (Hoạt động)' : 'Máy cầm tay / Cổng cố định',
                c: c,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Hàng đợi đơn hàng đang chờ tới cổng
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.queue_outlined, size: 16, color: c.textSecondary),
                          const SizedBox(width: 8),
                          Text(
                            'DANH SÁCH ĐƠN HÀNG ĐANG CHỜ XE QUA CỔNG (${pendingOrdersMap.length} ĐƠN)',
                            style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Text(
                        'Không cần chọn thủ công • Đẩy xe qua cổng để đối soát tự động',
                        style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: c.border),
                // Table Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                  color: c.bgDeep,
                  child: Row(
                    children: [
                      SizedBox(width: 45, child: Text('STT', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('MÃ ĐƠN HÀNG', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 3, child: Text('NHÀ CUNG CẤP', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      SizedBox(width: 100, child: Text('SỐ THÙNG', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      SizedBox(width: 160, child: Text('SỐ LƯỢNG CHIP', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text('PALLET ĐÍCH', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      SizedBox(width: 130, child: Text('TRẠNG THÁI', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    ],
                  ),
                ),
                // Table Body
                Expanded(
                  child: pendingOrdersMap.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_outlined, size: 48, color: c.textSecondary.withValues(alpha: 0.5)),
                              const SizedBox(height: 10),
                              Text(
                                'Hiện không có đơn hàng nào trong hàng đợi qua cổng.',
                                style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w500),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Bấm nút [NHẬP HÀNG] ở góc trên để tải file Excel/PO mới vào hệ thống.',
                                style: TextStyle(color: c.textSecondary.withValues(alpha: 0.7), fontSize: 11.5),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          itemCount: pendingOrdersMap.length,
                          separatorBuilder: (_, _) => Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
                          itemBuilder: (ctx, idx) {
                            final ordNo = pendingOrdersMap.keys.elementAt(idx);
                            final ordItems = pendingOrdersMap[ordNo]!;
                            final matchingOrder = _repo.inboundOrders.where((o) => o.orderNo == ordNo || o.inboundOrderId == ordNo).firstOrNull;
                            final supplier = (matchingOrder != null && matchingOrder.sourceSupplier.isNotEmpty)
                                ? matchingOrder.sourceSupplier
                                : ordItems.first.supplierDisplay;
                            final cartonCount = ordItems.map((i) => i.cartonCode).where((b) => b != null && b.isNotEmpty).toSet().length;
                            final palletCodes = ordItems.map((i) => i.palletId).where((b) => b != null && b.isNotEmpty).toSet().toList();
                            final pObjs = palletCodes.map((palletCode) => _repo.pallets.where((p) =>
                              p.palletCode.toUpperCase() == palletCode!.toUpperCase() ||
                              p.palletId.toUpperCase() == palletCode.toUpperCase() ||
                              p.palletId.toUpperCase() == 'PAL-${palletCode.toUpperCase()}' ||
                              'PAL-${p.palletCode.toUpperCase()}' == palletCode.toUpperCase()
                            ).firstOrNull).whereType<Pallet>().toList();
                            final palletTagCount = pObjs.where((p) => p.rfidEpc != null && p.rfidEpc!.trim().isNotEmpty).length;
                            final totalOrderChips = ordItems.length + palletTagCount;
                            final bool hasPallet = palletCodes.isNotEmpty;
                            final bool hasPalletTag = palletTagCount > 0;
                            final String displayPalletCode = pObjs.isNotEmpty
                                ? pObjs.map((p) => '${p.palletCode}${p.rfidEpc != null && p.rfidEpc!.isNotEmpty ? " (${p.rfidEpc})" : ""}').join(' • ')
                                : (palletCodes.isNotEmpty ? palletCodes.join(', ') : '--');

                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  SizedBox(width: 45, child: Text('${idx + 1}', style: TextStyle(color: c.textSecondary, fontSize: 12))),
                                  Expanded(
                                    flex: 2,
                                    child: Text(
                                      ordNo,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      supplier,
                                      style: TextStyle(color: c.textPrimary, fontSize: 12),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  SizedBox(
                                    width: 100,
                                    child: Center(
                                      child: Text(
                                        cartonCount > 0 ? '$cartonCount thùng' : '--',
                                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 160,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: c.bgDeep,
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: c.border),
                                        ),
                                        child: Text(
                                          hasPalletTag ? '$totalOrderChips chip (${ordItems.length} hàng + 1 pallet)' : '$totalOrderChips chip',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    flex: 2,
                                    child: Row(
                                      children: [
                                        Icon(
                                          hasPallet ? Icons.layers : Icons.layers_clear_outlined,
                                          size: 14,
                                          color: hasPallet ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          hasPallet ? displayPalletCode : 'Xếp sau cổng',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: hasPallet ? FontWeight.bold : FontWeight.normal,
                                            color: hasPallet ? c.textPrimary : const Color(0xFFF59E0B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    width: 130,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                                        ),
                                        child: const Text(
                                          '⏳ CHỜ QUA CỔNG',
                                          style: TextStyle(
                                            color: Color(0xFFF59E0B),
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
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
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String value,
    required String subtitle,
    required EyeCareColors c,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: 9.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.textSecondary, fontSize: 10)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------- 5. THANH ĐIỀU KHIỂN DƯỚI CÙNG ----------
  Widget _buildBottomControlBar(
    EyeCareColors c, {
    required bool isVehicleActive,
    required int scannedCount,
    required int expectedCount,
    required bool isComplete,
    required bool hasUnexpectedTags,
    required List<TagInfo> unexpList,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.bgCardElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          if (isVehicleActive) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.border),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.skip_next, size: 16),
              label: Text('Bỏ Qua Xe Này', style: TextStyle(color: c.textSecondary, fontSize: 12)),
              onPressed: _skipCurrentVehicle,
            ),
            const SizedBox(width: 8),
          ],
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: c.border),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: Icon(Icons.refresh, size: 16, color: c.textSecondary),
            label: Text('Làm Mới Quét', style: TextStyle(color: c.textSecondary, fontSize: 12)),
            onPressed: _resetWizard,
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
          // Nút Bắt đầu / Dừng quét
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
                  ? (_wizardScanDuration == 0 ? 'DỪNG QUÉT LIÊN TỤC' : 'DỪNG QUÉT ($_wizardScanCountdown s)')
                  : 'BẮT ĐẦU QUÉT (${_wizardScanDuration == 0 ? "LIÊN TỤC" : "${_wizardScanDuration}s"})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
            ),
            onPressed: _toggleWizardScan,
          ),
          if (isVehicleActive) ...[
            const SizedBox(width: 10),
            // Nút Báo lỗi sai sót thủ công
            if (hasUnexpectedTags || (expectedCount > 0 && scannedCount < expectedCount))
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.report_problem, size: 16, color: Color(0xFFEF4444)),
                label: const Text('BÁO LỖI SAI SÓT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: _reportDiscrepancyError,
              ),
            const SizedBox(width: 10),
            // Nút Xác nhận đọc đủ
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: isComplete
                    ? const Color(0xFF10B981)
                    : (scannedCount > 0 ? const Color(0xFF059669) : c.border),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: isComplete ? 3 : 1,
              ),
              icon: const Icon(Icons.check_circle, size: 18),
              label: Text(
                isComplete
                    ? 'XÁC NHẬN ĐỌC ĐỦ'
                    : (scannedCount > 0 ? 'LƯU & ĐỌC ĐỦ [$scannedCount/$expectedCount]' : 'XÁC NHẬN ĐỌC ĐỦ'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
              onPressed: (scannedCount > 0 && !hasUnexpectedTags) ? _completeGoodsReceiveAtGate : null,
            ),
          ],
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
