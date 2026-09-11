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

/// Mô hình lưu tạm đơn hàng chờ qua cổng RFID (chưa quét sẽ KHÔNG lưu vào CSDL)
class _PendingGateOrder {
  final InboundOrder order;
  final List<Item> items;
  final List<Product> products;
  final Map<String, String?> pallets; // palletCode -> rfidEpc
  final String supplier;
  final String fileName;

  _PendingGateOrder({
    required this.order,
    required this.items,
    required this.products,
    required this.pallets,
    required this.supplier,
    required this.fileName,
  });
}

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
  // Danh sách đơn nạp từ file đang chờ xe qua cổng (Lưu trong RAM, chưa quét sẽ CHƯA lưu CSDL)
  final List<_PendingGateOrder> _pendingGateOrders = [];

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
  // Lưu vết chip RFID đã quét tách biệt theo từng đơn hàng / xe Pallet (ngăn ngừa lẫn lộn giữa các xe)
  final Map<String, Map<String, TagInfo>> _scannedTagsByOrderNo = {};
  final Map<String, String> _scannedPalletTagsByOrderNo = {};
  bool _wizardIsScanning = false;
  int _wizardScanDuration = 0; // 0 = liên tục (mặc định cho cổng quét), 5s, 10s
  int _wizardScanCountdown = 0;
  Timer? _wizardCountdownTimer;

  int get _totalFileExpected => _pendingGateOrders.fold<int>(0, (sum, p) => sum + p.items.length);
  int get _totalFileScanned {
    int count = 0;
    for (final p in _pendingGateOrders) {
      final scannedMap = _scannedTagsByOrderNo[p.order.orderNo];
      if (scannedMap != null) {
        for (final it in p.items) {
          if (scannedMap.containsKey(it.epc.trim().toUpperCase())) {
            count++;
          }
        }
      }
    }
    return count;
  }

  void _syncWizardScannedTagsForActiveOrder() {
    _wizardScannedTags.clear();
    final ordNo = _activeOrderNo;
    if (ordNo != null && _scannedTagsByOrderNo.containsKey(ordNo)) {
      _wizardScannedTags.addAll(_scannedTagsByOrderNo[ordNo]!);
    }
  }

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

  // Tự động hoàn tất nhập kho và chuyển sang PDA khi đọc đủ 100% khớp file
  Timer? _autoCompleteTimer;
  bool _isCompletingGoodsReceive = false;

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

    if (!_desktopUhf.isConnected && _desktopUhf.config.autoConnectOnStartup) {
      _desktopUhf.connectWithSavedConfig();
    }
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
    _checkAndTriggerAutoComplete();
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
    _autoCompleteTimer?.cancel();
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
      final success = await _desktopUhf.connectWithSavedConfig();
      if (!success && !_desktopUhf.isConnected) {
        debugPrint('⚠️ Chưa kết nối được đầu đọc RFID (${_desktopUhf.config.connectionSummary}). Vui lòng vào Cấu Hình Kết Nối!');
        return;
      }
    }
    _uhf.startInventory();
    final started = await _desktopUhf.startInventory();
    if (!started && !_desktopUhf.isConnected) {
      return;
    }

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
    _autoCompleteTimer?.cancel();
    _autoCompleteTimer = null;
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
    final knownEpcs = <String>{};

    // 1. Toàn bộ mã chip RFID pallet từ CSDL
    for (final p in _repo.pallets) {
      if (p.rfidEpc != null && p.rfidEpc!.isNotEmpty) {
        knownEpcs.add(p.rfidEpc!.trim().toUpperCase());
      }
      knownEpcs.add(p.palletCode.trim().toUpperCase());
    }

    // 2. Toàn bộ mã chip RFID pallet và chip sản phẩm từ TẤT CẢ các đơn hàng trong file (_pendingGateOrders)
    for (final pOrder in _pendingGateOrders) {
      for (final entry in pOrder.pallets.entries) {
        if (entry.value != null && entry.value!.trim().isNotEmpty) {
          knownEpcs.add(entry.value!.trim().toUpperCase());
        }
        knownEpcs.add(entry.key.trim().toUpperCase());
      }
      for (final item in pOrder.items) {
        knownEpcs.add(item.epc.trim().toUpperCase());
        if (item.serialNumber.trim().isNotEmpty) {
          knownEpcs.add(item.serialNumber.trim().toUpperCase());
        }
      }
    }

    // 3. Pallet đang active hoặc vừa nhận diện
    if (_wizardDetectedPallet?.rfidEpc != null && _wizardDetectedPallet!.rfidEpc!.isNotEmpty) {
      knownEpcs.add(_wizardDetectedPallet!.rfidEpc!.trim().toUpperCase());
    }
    if (_wizardDetectedPalletTag != null && _wizardDetectedPalletTag!.isNotEmpty) {
      knownEpcs.add(_wizardDetectedPalletTag!.trim().toUpperCase());
    }
    if (_activePallet?.rfidEpc != null && _activePallet!.rfidEpc!.isNotEmpty) {
      knownEpcs.add(_activePallet!.rfidEpc!.trim().toUpperCase());
    }
    if (_activePalletTag != null && _activePalletTag!.isNotEmpty) {
      knownEpcs.add(_activePalletTag!.trim().toUpperCase());
    }

    // 4. Sản phẩm chờ nhập trong CSDL
    for (final item in _repo.items) {
      if (item.status == ItemStatus.pendingInbound) {
        knownEpcs.add(item.epc.trim().toUpperCase());
      }
    }

    // 5. Thùng hàng receiptCartons
    for (final c in _receiptCartons) {
      final serials = (c['serials'] as List<dynamic>?)?.map((e) => e.toString().trim().toUpperCase()) ?? [];
      knownEpcs.addAll(serials);
      final pEpc = c['palletEpc']?.toString().trim().toUpperCase();
      if (pEpc != null && pEpc.isNotEmpty) knownEpcs.add(pEpc);
    }

    return _wizardUnexpectedTags.values.where((t) {
      final epc = t.epc.trim().toUpperCase();
      if (knownEpcs.contains(epc)) return false;
      if (_repo.findPalletByRfid(epc) != null) return false;
      return true;
    }).toList();
  }

  void _handleWizardGateTag(TagInfo tag) {
    final cleanEpc = tag.epc.trim().toUpperCase();
    if (cleanEpc.isEmpty) return;

    // Nếu chưa nạp file và không có đơn hàng nào đang chờ qua cổng, không xử lý thẻ
    final hasPendingOrders = _pendingGateOrders.isNotEmpty ||
        _repo.items.any((i) => i.status == ItemStatus.pendingInbound);
    if (!hasPendingOrders) {
      return;
    }

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
      return;
    }

    // 1.2 Kiểm tra nếu chip quét được là chip của một xe Pallet (từ đơn chờ qua cổng hoặc CSDL)
    _PendingGateOrder? matchedPendingPalletOrder;
    Pallet? matchedPallet;
    String? matchedPalletEpc;

    for (final pOrder in _pendingGateOrders) {
      for (final entry in pOrder.pallets.entries) {
        final epcVal = (entry.value ?? '').trim().toUpperCase();
        final codeVal = entry.key.trim().toUpperCase();
        if ((epcVal.isNotEmpty && epcVal == cleanEpc) || codeVal == cleanEpc) {
          matchedPendingPalletOrder = pOrder;
          matchedPalletEpc = epcVal.isNotEmpty ? epcVal : cleanEpc;
          matchedPallet = Pallet(
            palletId: 'PAL-$codeVal',
            palletCode: entry.key,
            rfidEpc: matchedPalletEpc,
          );
          break;
        }
      }
      if (matchedPallet != null) break;
    }

    matchedPallet ??= _repo.findPalletByRfid(cleanEpc);

    if (matchedPallet != null) {
      final mPallet = matchedPallet;
      _wizardUnexpectedTags.remove(cleanEpc);
      if (mPallet.rfidEpc != null) {
        _wizardUnexpectedTags.remove(mPallet.rfidEpc!.trim().toUpperCase());
      }

      // Xác định đơn hàng của pallet này
      String? targetOrderNo = matchedPendingPalletOrder?.order.orderNo ??
          _pendingGateOrders.where((p) => p.pallets.containsKey(mPallet.palletCode) || p.items.any((i) => i.palletId == mPallet.palletId || i.palletId == mPallet.palletCode)).firstOrNull?.order.orderNo ??
          _repo.items.where((i) => (i.palletId == mPallet.palletId || i.palletId == mPallet.palletCode) && i.status == ItemStatus.pendingInbound).firstOrNull?.orderNo;

      // Nếu không khớp mã pallet trong file nhưng file chỉ có 1 đơn hàng (hoặc đang có đơn active)
      if (targetOrderNo == null && _pendingGateOrders.length == 1) {
        targetOrderNo = _pendingGateOrders.first.order.orderNo;
      }
      targetOrderNo ??= _activeOrderNo;

      if (targetOrderNo != null) {
        _scannedPalletTagsByOrderNo[targetOrderNo] = cleanEpc;
      }

      // Chỉ kích hoạt xe Pallet nếu xác định được đơn hàng chờ tương ứng (tránh tạo xe ma 0/0 chip)
      if (targetOrderNo != null && (_activePallet?.palletCode != mPallet.palletCode || _activeOrderNo != targetOrderNo)) {
        setState(() {
          _activePallet = mPallet;
          _activePalletTag = cleanEpc;
          _wizardDetectedPallet = mPallet;
          _wizardDetectedPalletTag = cleanEpc;
          _activeOrderNo = targetOrderNo;

          // Lấy danh sách hàng tương ứng với xe Pallet này
          if (matchedPendingPalletOrder != null) {
            _activeExpectedItems = matchedPendingPalletOrder.items;
          } else {
            final pOrder = _pendingGateOrders.where((p) => p.order.orderNo == targetOrderNo).firstOrNull;
            if (pOrder != null) {
              _activeExpectedItems = pOrder.items;
            } else {
              _activeExpectedItems = _repo.items.where((i) =>
                (i.orderNo == targetOrderNo || i.palletId == mPallet.palletId || i.palletId == mPallet.palletCode) &&
                i.status == ItemStatus.pendingInbound
              ).toList();
            }
          }

          _wizardSelectedCartons.clear();
          for (var it in _activeExpectedItems) {
            if (it.cartonCode != null && it.cartonCode!.isNotEmpty) {
              _wizardSelectedCartons.add(it.cartonCode!);
            }
          }

          // Đồng bộ lại chỉ các chip đã quét thuộc xe Pallet này
          _syncWizardScannedTagsForActiveOrder();
          _hasDiscrepancyError = false;
          _discrepancyMissingItems.clear();
          _discrepancyUnexpectedTags.clear();
          _invalidateCartonCaches();
        });
        _towerLight.triggerPass(reason: 'Đã nhận diện xe Pallet ${mPallet.palletCode}!');
      }

      final expectedSerials = _getWizardExpectedSerials();
      if (expectedSerials.isNotEmpty && _wizardScannedTags.length >= expectedSerials.length && _getFilteredUnexpectedTags().isEmpty) {
        _tagBatchUiTimer?.cancel();
        _tagBatchUiTimer = null;
        final pCode = mPallet.palletCode;
        _towerLight.triggerPass(reason: 'Pallet $pCode: Đã quét đủ ${expectedSerials.length} chip hàng. Tự động chuyển sang PDA!');
        if (mounted) setState(() {});
      }
      _checkAndTriggerAutoComplete();
      return;
    }

    // 2. KIỂM TRA CHIP SẢN PHẨM TRONG CÁC ĐƠN CHỜ QUA CỔNG (_pendingGateOrders)
    _PendingGateOrder? itemPendingOrder;
    Item? matchedItem;
    for (final pOrder in _pendingGateOrders) {
      final found = pOrder.items.where((i) =>
        i.epc.trim().toUpperCase() == cleanEpc ||
        i.serialNumber.trim().toUpperCase() == cleanEpc
      ).firstOrNull;
      if (found != null) {
        itemPendingOrder = pOrder;
        matchedItem = found;
        break;
      }
    }

    if (itemPendingOrder != null && matchedItem != null) {
      final ordNo = itemPendingOrder.order.orderNo;
      _scannedTagsByOrderNo.putIfAbsent(ordNo, () => {})[cleanEpc] = tag;
      _wizardUnexpectedTags.remove(cleanEpc);

      // Nếu chưa có xe nào active -> tự động active xe này
      if (_activeOrderNo == null) {
        _selectActivePendingOrder(ordNo);
        _checkAndTriggerAutoComplete();
        return;
      }

      // Nếu thuộc đúng xe Pallet đang active hiện tại
      if (_activeOrderNo == ordNo) {
        if (!_wizardScannedTags.containsKey(cleanEpc)) {
          _wizardScannedTags[cleanEpc] = tag;
          final expectedSerials = _getWizardExpectedSerials();
          if (expectedSerials.isNotEmpty && _wizardScannedTags.length >= expectedSerials.length && _getFilteredUnexpectedTags().isEmpty) {
            _tagBatchUiTimer?.cancel();
            _tagBatchUiTimer = null;
            final pCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode ?? 'Xe Pallet';
            _towerLight.triggerPass(reason: 'Pallet $pCode: Đã quét đủ ${expectedSerials.length} sản phẩm. Tự động chuyển sang PDA!');
            if (mounted) setState(() {});
          } else {
            if (_tagBatchUiTimer == null || !_tagBatchUiTimer!.isActive) {
              _tagBatchUiTimer = Timer(const Duration(milliseconds: 60), () {
                if (mounted) setState(() {});
              });
            }
          }
        }
      } else {
        // Chip thuộc một xe Pallet KHÁC trong file đang chờ (ví dụ: Pallet 1 đã qua trước đó)
        // -> ĐÃ LƯU VÀO _scannedTagsByOrderNo[ordNo], TUYỆT ĐỐI KHÔNG BÁO CHIP LẠ!
        if (_tagBatchUiTimer == null || !_tagBatchUiTimer!.isActive) {
          _tagBatchUiTimer = Timer(const Duration(milliseconds: 100), () {
            if (mounted) setState(() {});
          });
        }
      }
      _checkAndTriggerAutoComplete();
      return;
    }

    // 3. KIỂM TRA CHIP SẢN PHẨM TRONG CSDL HOẶC TRONG DANH SÁCH EXPECTED HIỆN TẠI
    final expectedSerials = _getWizardExpectedSerials();
    if (expectedSerials.contains(cleanEpc)) {
      if (!_wizardScannedTags.containsKey(cleanEpc)) {
        _wizardScannedTags[cleanEpc] = tag;
        _wizardUnexpectedTags.remove(cleanEpc);
        if (_activeOrderNo != null) {
          _scannedTagsByOrderNo.putIfAbsent(_activeOrderNo!, () => {})[cleanEpc] = tag;
        }

        if (expectedSerials.isNotEmpty && _wizardScannedTags.length >= expectedSerials.length && _getFilteredUnexpectedTags().isEmpty) {
          _tagBatchUiTimer?.cancel();
          _tagBatchUiTimer = null;
          final pCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode ?? 'Xe Pallet';
          _towerLight.triggerPass(reason: 'Pallet $pCode: Đã quét đủ ${expectedSerials.length} sản phẩm. Tự động chuyển sang PDA!');
          if (mounted) setState(() {});
        } else {
          if (_tagBatchUiTimer == null || !_tagBatchUiTimer!.isActive) {
            _tagBatchUiTimer = Timer(const Duration(milliseconds: 60), () {
              if (mounted) setState(() {});
            });
          }
        }
      }
      _checkAndTriggerAutoComplete();
      return;
    }

    // 4. KIỂM TRA NẾU LÀ PALLET BẤT KỲ HOẶC HÀNG TRONG CSDL
    final isAnyPallet = _repo.pallets.any((p) =>
      (p.rfidEpc ?? '').trim().toUpperCase() == cleanEpc ||
      p.palletCode.toUpperCase() == cleanEpc) ||
      _pendingGateOrders.any((pOrder) => pOrder.pallets.entries.any((e) =>
        (e.value ?? '').trim().toUpperCase() == cleanEpc || e.key.toUpperCase() == cleanEpc));
    if (isAnyPallet) {
      return;
    }

    final isAnyKnownDbItem = _repo.items.any((i) =>
      i.epc.trim().toUpperCase() == cleanEpc && i.status == ItemStatus.pendingInbound);
    if (isAnyKnownDbItem) {
      return;
    }

    // 5. CHIP LẠ THỰC SỰ: Không thuộc bất kỳ pallet hay sản phẩm nào trong file hoặc CSDL!
    _autoCompleteTimer?.cancel();
    _autoCompleteTimer = null;
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

  /// Tự động hoàn tất nhập kho và đẩy sang PDA khi đã quét đủ 100% khớp file (không cần bấm tay)
  void _checkAndTriggerAutoComplete() {
    if (_isCompletingGoodsReceive) return;
    final unexp = _getFilteredUnexpectedTags();
    if (unexp.isNotEmpty) {
      _autoCompleteTimer?.cancel();
      _autoCompleteTimer = null;
      return;
    }

    // Kiểm tra xem có xe pallet / đơn nào trong file đã quét đủ 100% khớp file không
    bool hasReadyOrder = false;
    for (final p in _pendingGateOrders) {
      final ordNo = p.order.orderNo;
      final scannedMap = _scannedTagsByOrderNo[ordNo] ?? {};
      final scannedCount = p.items.where((i) => scannedMap.containsKey(i.epc.trim().toUpperCase())).length;
      if (p.items.isNotEmpty && scannedCount >= p.items.length) {
        hasReadyOrder = true;
        break;
      }
    }

    // Hoặc nếu quét trực tiếp theo _activeExpectedItems (đơn từ CSDL)
    if (!hasReadyOrder && _activeOrderNo != null && _activeExpectedItems.isNotEmpty) {
      final scannedCount = _activeExpectedItems.where((i) => _wizardScannedTags.containsKey(i.epc.trim().toUpperCase())).length;
      if (scannedCount >= _activeExpectedItems.length) {
        hasReadyOrder = true;
      }
    }

    if (hasReadyOrder) {
      if (_autoCompleteTimer == null || !_autoCompleteTimer!.isActive) {
        _autoCompleteTimer = Timer(const Duration(milliseconds: 350), () {
          _autoCompleteTimer = null;
          if (!mounted || _isCompletingGoodsReceive) return;
          final currentUnexp = _getFilteredUnexpectedTags();
          if (currentUnexp.isEmpty) {
            _completeGoodsReceiveAtGate();
          }
        });
      }
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
    _autoCompleteTimer?.cancel();
    _autoCompleteTimer = null;

    setState(() {
      _hasDiscrepancyError = true;
      _discrepancyOrderNo = _activeOrderNo ?? (_wizardSelectedCartons.isNotEmpty ? _wizardSelectedCartons.first : 'Chưa rõ mã đơn');
      _discrepancyPalletCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode;
      _discrepancyMissingItems = missing;
      _discrepancyUnexpectedTags = unexp;
    });
  }

  void _retryCurrentVehicle() {
    _autoCompleteTimer?.cancel();
    _autoCompleteTimer = null;
    setState(() {
      if (_activeOrderNo != null) {
        _scannedTagsByOrderNo.remove(_activeOrderNo);
      }
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
    final String? palletCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode;
    final itemEpcs = _wizardScannedTags.keys.toList();
    final count = itemEpcs.length;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _eyeCare.colors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _eyeCare.colors.border)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 22),
            const SizedBox(width: 8),
            Text('Xác nhận nhập thiếu?', style: TextStyle(color: _eyeCare.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        content: Text(
          'Đơn hàng "$orderNo" (Pallet: ${palletCode ?? "--"}) chỉ mới đọc được $count chip (thiếu ${_discrepancyMissingItems.length} chip).\n\nBạn có chắc chắn muốn lưu thông tin nhập thiếu này vào CSDL?',
          style: TextStyle(color: _eyeCare.colors.textSecondary, fontSize: 12.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('HỦY', style: TextStyle(color: _eyeCare.colors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('XÁC NHẬN NHẬP THIẾU', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Khi xác nhận nhập thiếu, lưu dữ liệu đơn hàng chờ vào CSDL trước khi xác nhận lưu kho
    final pendingIdx = _pendingGateOrders.indexWhere((p) => p.order.orderNo == orderNo || p.order.inboundOrderId == orderNo);
    if (pendingIdx != -1) {
      final pending = _pendingGateOrders[pendingIdx];
      if (pending.products.isNotEmpty) {
        await _repo.addProductsBatch(pending.products);
      }
      for (final entry in pending.pallets.entries) {
        await _repo.registerOrUpdatePallet(palletCode: entry.key, rfidEpc: entry.value ?? '');
      }
      await _repo.addInboundOrder(pending.order, autoGenerateEpcs: false);
      await _repo.insertDirectItems(pending.items);
      _pendingGateOrders.removeAt(pendingIdx);
      _scannedTagsByOrderNo.remove(orderNo);
    }

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

  /// Kích hoạt chọn xe Pallet / đơn hàng đang chờ để kiểm tra hoặc xác nhận
  void _selectActivePendingOrder(String orderNo) {
    final pendingOrderObj = _pendingGateOrders.where((p) => p.order.orderNo == orderNo || p.order.inboundOrderId == orderNo).firstOrNull;
    if (pendingOrderObj == null) {
      final pItems = _repo.items.where((i) => (i.orderNo == orderNo) && i.status == ItemStatus.pendingInbound).toList();
      if (pItems.isEmpty) return;
      setState(() {
        _activeOrderNo = orderNo;
        _activeExpectedItems = pItems;
        final pId = pItems.first.palletId;
        if (pId != null) {
          _activePallet = _repo.pallets.where((p) => p.palletId.toUpperCase() == pId.toUpperCase() || p.palletCode.toUpperCase() == pId.toUpperCase()).firstOrNull;
          _wizardDetectedPallet = _activePallet;
          _wizardDetectedPalletTag = _activePallet?.rfidEpc;
          _activePalletTag = _activePallet?.rfidEpc;
        }
        _hasDiscrepancyError = false;
        _discrepancyMissingItems.clear();
        _discrepancyUnexpectedTags.clear();
        _syncWizardScannedTagsForActiveOrder();
        _invalidateCartonCaches();
      });
      return;
    }

    setState(() {
      _activeOrderNo = orderNo;
      _activeExpectedItems = pendingOrderObj.items;
      _wizardSelectedCartons.clear();
      for (var it in pendingOrderObj.items) {
        if (it.cartonCode != null && it.cartonCode!.isNotEmpty) {
          _wizardSelectedCartons.add(it.cartonCode!);
        }
      }

      Pallet? pal;
      String? palTag;
      if (pendingOrderObj.pallets.isNotEmpty) {
        final pEntry = pendingOrderObj.pallets.entries.first;
        palTag = pEntry.value;
        pal = _repo.pallets.where((p) => p.palletCode.toUpperCase() == pEntry.key.toUpperCase() || p.palletId.toUpperCase() == pEntry.key.toUpperCase()).firstOrNull;
        pal ??= Pallet(
          palletId: 'PAL-${pEntry.key.toUpperCase()}',
          palletCode: pEntry.key,
          rfidEpc: palTag,
        );
      } else if (pendingOrderObj.items.isNotEmpty && pendingOrderObj.items.first.palletId != null) {
        final pId = pendingOrderObj.items.first.palletId!;
        final pCode = pId.replaceAll('PAL-', '');
        palTag = pendingOrderObj.pallets[pCode];
        pal = _repo.pallets.where((p) => p.palletId.toUpperCase() == pId.toUpperCase() || p.palletCode.toUpperCase() == pId.toUpperCase()).firstOrNull;
        pal ??= Pallet(palletId: pId, palletCode: pCode, rfidEpc: palTag);
      }

      _activePallet = pal;
      _activePalletTag = palTag;
      _wizardDetectedPallet = pal;
      _wizardDetectedPalletTag = palTag;
      _hasDiscrepancyError = false;
      _discrepancyMissingItems.clear();
      _discrepancyUnexpectedTags.clear();

      _syncWizardScannedTagsForActiveOrder();
      _invalidateCartonCaches();
    });
  }

  Future<void> _completeGoodsReceiveAtGate() async {
    if (_isCompletingGoodsReceive) return;
    _isCompletingGoodsReceive = true;
    _autoCompleteTimer?.cancel();
    _autoCompleteTimer = null;

    try {
      final unexpList = _getFilteredUnexpectedTags();
      if (unexpList.isNotEmpty) {
        _reportDiscrepancyError();
        return;
      }

      // Kiểm tra danh sách các xe pallet đã quét đủ số lượng
      final completedOrders = _pendingGateOrders.where((p) {
        final ordNo = p.order.orderNo;
        final scannedMap = _scannedTagsByOrderNo[ordNo] ?? {};
        final scannedItemCount = p.items.where((i) => scannedMap.containsKey(i.epc.trim().toUpperCase())).length;
        return p.items.isNotEmpty && scannedItemCount >= p.items.length;
      }).toList();

      if (completedOrders.isEmpty) {
        if (_activeOrderNo != null && _activeExpectedItems.isNotEmpty) {
          final scannedEpcs = _activeExpectedItems.where((i) => _wizardScannedTags.containsKey(i.epc.trim().toUpperCase())).map((i) => i.epc.trim().toUpperCase()).toList();
          if (scannedEpcs.length >= _activeExpectedItems.length) {
            final ordNo = _activeOrderNo!;
            final pCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode;
            await _repo.confirmGateReceiveToWaitingPutaway(
              orderNo: ordNo,
              scannedEpcs: scannedEpcs,
              palletCode: pCode,
              performedBy: 'Cổng RFID Gate',
            );
            _recentCompletedPasses.insert(0, {
              'orderNo': ordNo,
              'palletCode': pCode ?? '--',
              'count': scannedEpcs.length,
              'total': _activeExpectedItems.length,
              'time': DateTime.now(),
              'status': 'CHỜ XẾP KỆ',
              'isSuccess': true,
            });
            _towerLight.triggerPass(reason: 'Đã hoàn tất nhập kho và chuyển sang PDA cho đơn $ordNo!');
            if (mounted) {
              setState(() {
                _lastSuccessOrderNo = ordNo;
                _lastSuccessCount = scannedEpcs.length;
                _hasDiscrepancyError = false;
                _discrepancyMissingItems.clear();
                _discrepancyUnexpectedTags.clear();
                _invalidateCartonCaches();
                _activeOrderNo = null;
                _activePallet = null;
                _activePalletTag = null;
                _activeExpectedItems.clear();
                _wizardScannedTags.clear();
                _stopWizardScan();
                _desktopUhf.clearTags();
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF10B981),
                  content: Text('✓ Đã tự động hoàn tất đơn $ordNo và đẩy sang PDA!'),
                ),
              );
            }
            return;
          }
        }
        _reportDiscrepancyError();
        return;
      }

      for (final pending in List<_PendingGateOrder>.from(completedOrders)) {
        final ordNo = pending.order.orderNo;
        final scannedMap = _scannedTagsByOrderNo[ordNo] ?? {};
        final scannedEpcs = pending.items.where((i) => scannedMap.containsKey(i.epc.trim().toUpperCase())).map((i) => i.epc.trim().toUpperCase()).toList();
        final pCode = pending.pallets.keys.firstOrNull ?? (pending.items.isNotEmpty ? pending.items.first.palletId?.replaceAll('PAL-', '') : null) ?? ordNo;
        final rfidEpc = _scannedPalletTagsByOrderNo[ordNo] ?? pending.pallets[pCode];

        try {
          if (pending.products.isNotEmpty) {
            await _repo.addProductsBatch(pending.products);
          }
          for (final entry in pending.pallets.entries) {
            await _repo.registerOrUpdatePallet(palletCode: entry.key, rfidEpc: entry.value ?? '');
          }
          await _repo.addInboundOrder(pending.order, autoGenerateEpcs: false);
          await _repo.insertDirectItems(pending.items);

          await _repo.assignItemsToPallet(
            palletCode: pCode,
            rfidEpc: rfidEpc,
            itemEpcs: scannedEpcs,
          );

          await _repo.confirmGateReceiveToWaitingPutaway(
            orderNo: ordNo,
            scannedEpcs: scannedEpcs,
            palletCode: pCode,
            performedBy: 'Cổng RFID Gate',
          );

          _recentCompletedPasses.insert(0, {
            'orderNo': ordNo,
            'palletCode': pCode,
            'count': scannedEpcs.length,
            'total': pending.items.length,
            'time': DateTime.now(),
            'status': 'CHỜ XẾP KỆ',
            'isSuccess': true,
          });

          _pendingGateOrders.remove(pending);
          _pendingLoadedOrderNos.remove(ordNo);
          _scannedTagsByOrderNo.remove(ordNo);
          _scannedPalletTagsByOrderNo.remove(ordNo);
        } catch (e) {
          debugPrint('Lỗi xác nhận đơn $ordNo: $e');
        }
      }

      final totalSaved = completedOrders.fold<int>(0, (sum, p) => sum + p.items.length);
      _towerLight.triggerPass(reason: 'Đã hoàn tất nhập kho và chuyển sang PDA cho ${completedOrders.length} xe Pallet ($totalSaved chip)!');

      if (mounted) {
        setState(() {
          _lastSuccessOrderNo = completedOrders.map((p) => p.order.orderNo).join(', ');
          _lastSuccessCount = totalSaved;
          _hasDiscrepancyError = false;
          _discrepancyMissingItems.clear();
          _discrepancyUnexpectedTags.clear();
          _invalidateCartonCaches();
          if (_pendingGateOrders.isEmpty) {
            _activeOrderNo = null;
            _activePallet = null;
            _activePalletTag = null;
            _activeExpectedItems.clear();
            _wizardScannedTags.clear();
            _stopWizardScan();
            _desktopUhf.clearTags();
          } else {
            // Tự động chuyển sang xe Pallet tiếp theo trong hàng đợi
            _selectActivePendingOrder(_pendingGateOrders.first.order.orderNo);
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('✓ Đã tự động hoàn tất ${completedOrders.length} xe Pallet ($totalSaved chip) và đẩy sang PDA!'),
          ),
        );
      }
    } finally {
      _isCompletingGoodsReceive = false;
    }
  }

  void _resetWizard() {
    _autoCompleteTimer?.cancel();
    _wizardCountdownTimer?.cancel();
    _tagBatchUiTimer?.cancel();
    _successBannerTimer?.cancel();
    _uhf.stopInventory();
    _desktopUhf.stopInventory();
    _desktopUhf.clearTags();
    setState(() {
      _isImporting = false;
      _wizardIsScanning = false;
      _wizardScanCountdown = _wizardScanDuration;
      _scannedTagsByOrderNo.clear();
      _scannedPalletTagsByOrderNo.clear();
      _wizardScannedTags.clear();
      _wizardUnexpectedTags.clear();
      _hasDiscrepancyError = false;
      _discrepancyMissingItems.clear();
      _discrepancyUnexpectedTags.clear();
      _lastSuccessOrderNo = null;
      _lastSuccessPalletCode = null;
      _lastSuccessCount = 0;
      _receiptCartons.clear();
      _invalidateCartonCaches();

      if (_pendingGateOrders.isNotEmpty) {
        final firstOrderNo = _pendingLoadedOrderNos.firstOrNull ?? _pendingGateOrders.first.order.orderNo;
        _selectActivePendingOrder(firstOrderNo);
      } else {
        _activeOrderNo = null;
        _activePallet = null;
        _activePalletTag = null;
        _activeExpectedItems.clear();
        _wizardDetectedPallet = null;
        _wizardDetectedPalletTag = null;
        _wizardSelectedCartons.clear();
        _wizardSelectedEpcs.clear();
      }
    });

    if (_pendingGateOrders.isNotEmpty) {
      _wizardScanDuration = 0;
      _startWizardScan(durationSeconds: 0);
    }
  }

  /// Dọn dẹp các đơn hàng nháp và chip tạm thời được nạp từ file nếu chưa xác nhận hoàn tất nhập kho
  Future<void> _cleanupPendingDraftOrders() async {
    try {
      _pendingGateOrders.clear();
      _pendingLoadedOrderNos.clear();
      _scannedTagsByOrderNo.clear();
      _scannedPalletTagsByOrderNo.clear();
      await _repo.wipeAllPendingInboundOrdersAndItems();
    } catch (e) {
      debugPrint('Lỗi dọn dẹp đơn hàng nạp file nháp: $e');
    } finally {
      _pendingGateOrders.clear();
      _pendingLoadedOrderNos.clear();
      _scannedTagsByOrderNo.clear();
      _scannedPalletTagsByOrderNo.clear();
    }
  }

  /// Xử lý bấm nút LÀM MỚI: Reload đồng bộ dữ liệu từ CSDL và Cloud, giữ nguyên dữ liệu hàng đợi
  Future<void> _handleSyncReload() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      await _supabaseSync.syncNow();
      await _repo.ensureInitialized();
      _invalidateCartonCaches();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
            content: Text('✓ Đã đồng bộ dữ liệu mới nhất từ CSDL & Cloud'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi khi đồng bộ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  // ---------- XÓA TOÀN BỘ ĐƠN CHỜ ĐỂ CHỌN FILE MỚI ----------

  Future<void> _confirmAndDeleteAllPendingOrders(Map<String, List<Item>> pendingOrdersMap) async {
    // 1. Cập nhật giao diện trống ngay lập tức (0ms, không làm quay nút Nhập hàng)
    _pendingGateOrders.clear();
    _scannedTagsByOrderNo.clear();
    _resetWizard();
    _pendingLoadedOrderNos.clear();
    _receiptCartons.clear();
    _wizardSelectedCartons.clear();
    _wizardSelectedEpcs.clear();
    _desktopUhf.clearTags();
    _invalidateCartonCaches();

    if (mounted) setState(() {});

    // 2. Xóa sạch CSDL và đồng bộ ngầm siêu nhanh (không chặn UI, không làm quay nút Nhập hàng, không hiện dòng xanh)
    _repo.wipeAllPendingInboundOrdersAndItems().then((_) {
      _supabaseSync.syncNow();
    }).catchError((e) {
      debugPrint('Lỗi khi xóa đơn chờ: $e');
    });
  }

  Future<void> _triggerClearAllPendingDialog() async {
    final Map<String, List<Item>> pendingOrdersMap = {};
    for (var pOrder in _pendingGateOrders) {
      pendingOrdersMap[pOrder.order.orderNo] = pOrder.items;
    }
    final validInboundOrders = _repo.inboundOrders.where((o) => o.status == InboundOrderStatus.newOrder).toList();
    final pendingItems = _repo.items.where((i) => i.status == ItemStatus.pendingInbound).toList();
    for (var order in validInboundOrders) {
      if (!pendingOrdersMap.containsKey(order.orderNo)) {
        final ordItems = pendingItems.where((i) => i.orderNo == order.orderNo || i.orderNo == order.inboundOrderId).toList();
        if (ordItems.isNotEmpty) {
          pendingOrdersMap[order.orderNo] = ordItems;
        }
      }
    }
    for (var item in pendingItems) {
      final ordNo = item.orderNo;
      if (ordNo != null && ordNo.isNotEmpty && !pendingOrdersMap.containsKey(ordNo)) {
        final matchingOrder = _repo.inboundOrders.where((o) => (o.orderNo == ordNo || o.inboundOrderId == ordNo) && o.status == InboundOrderStatus.newOrder).firstOrNull;
        if (matchingOrder != null) {
          pendingOrdersMap.putIfAbsent(ordNo, () => []).add(item);
        }
      }
    }
    await _confirmAndDeleteAllPendingOrders(pendingOrdersMap);
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

      // Pallet được ghi nhận để kiểm tra và chỉ lưu vào CSDL khi xe quét qua cổng RFID

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

      // 2. Chuẩn bị danh mục sản phẩm (chỉ lưu vào CSDL khi xe quét qua cổng)
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

      // 3. Lưu vào hàng đợi bộ nhớ tạm _pendingGateOrders (CHƯA quét sẽ CHƯA lưu vào CSDL)
      final firstSupplier = explicitItems.map((i) => i.supplier).where((s) => s != null && s.isNotEmpty && s != 'Nhà cung cấp tổng hợp').firstOrNull;
      final effectiveSupplier = firstSupplier ?? 'File: ${result.fileName}';

      // --- Resolve tên pallet thực từ CSDL theo EPC ---
      // Nếu EPC trong file trùng với pallet trong CSDL → dùng tên/mã của pallet đó (e.g. PL01)
      final Map<String, String> resolvedPalletName = {}; // fileCode → displayCode
      for (final entry in palletsToRegister.entries) {
        final fileCode = entry.key;
        final epc = (entry.value ?? '').trim().toUpperCase();
        Pallet? dbPallet;
        if (epc.isNotEmpty) {
          dbPallet = _repo.pallets.where((p) =>
            (p.rfidEpc ?? '').trim().toUpperCase() == epc
          ).firstOrNull;
        }
        dbPallet ??= _repo.pallets.where((p) =>
          p.palletCode.toUpperCase() == fileCode.toUpperCase() ||
          p.palletId.toUpperCase() == fileCode.toUpperCase() ||
          p.palletId.toUpperCase() == 'PAL-${fileCode.toUpperCase()}'
        ).firstOrNull;
        resolvedPalletName[fileCode] = dbPallet?.palletCode ?? fileCode;
      }

      // Build palletsToRegister với tên đã resolve
      final Map<String, String?> resolvedPalletsToRegister = {
        for (final entry in palletsToRegister.entries)
          (resolvedPalletName[entry.key] ?? entry.key): entry.value,
      };

      _pendingGateOrders.clear();
      _pendingLoadedOrderNos.clear();
      for (final entry in ordersDetailMap.entries) {
        final currentOrderNo = entry.key;
        final currentDetailMap = entry.value;
        final orderItems = explicitItems.where((i) => (i.orderNo ?? inboundOrderNo) == currentOrderNo).toList();

        final order = InboundOrder(
          inboundOrderId: currentOrderNo,
          orderNo: currentOrderNo,
          sourceSupplier: effectiveSupplier,
          status: InboundOrderStatus.newOrder,
          createdAt: now,
          details: currentDetailMap.values.toList(),
        );

        final thisOrderPallets = <String, String?>{};
        for (final item in orderItems) {
          final rawCode = item.palletId?.replaceAll('PAL-', '');
          if (rawCode != null) {
            // Tìm resolved name theo rawCode hoặc trực tiếp trong resolvedPalletsToRegister
            final displayCode = resolvedPalletName[rawCode] ?? rawCode;
            if (resolvedPalletsToRegister.containsKey(displayCode)) {
              thisOrderPallets[displayCode] = resolvedPalletsToRegister[displayCode];
            } else if (palletsToRegister.containsKey(rawCode)) {
              thisOrderPallets[displayCode] = palletsToRegister[rawCode];
            }
          }
        }
        if (thisOrderPallets.isEmpty && resolvedPalletsToRegister.length == 1) {
          thisOrderPallets.addAll(resolvedPalletsToRegister);
        }

        _pendingGateOrders.add(_PendingGateOrder(
          order: order,
          items: orderItems,
          products: newProducts,
          pallets: thisOrderPallets,
          supplier: effectiveSupplier,
          fileName: result.fileName,
        ));
        _pendingLoadedOrderNos.add(currentOrderNo);
      }

      if (mounted) {
        setState(() => _isImporting = false);
      }

      if (_pendingGateOrders.isNotEmpty) {
        _selectActivePendingOrder(_pendingLoadedOrderNos.first);
      }
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
      // 3. Lưu vào hàng đợi bộ nhớ tạm _pendingGateOrders (CHƯA quét sẽ CHƯA lưu vào CSDL)
      _pendingGateOrders.clear();
      _pendingLoadedOrderNos.clear();
      for (var entry in poGroup.entries) {
        final poNo = entry.key;
        final poItems = explicitItems.where((i) => i.orderNo == poNo).toList();
        final order = InboundOrder(
          inboundOrderId: poNo,
          orderNo: poNo,
          sourceSupplier: entry.value.first['supplier']?.toString() ?? 'Nhà cung cấp PO',
          status: InboundOrderStatus.newOrder,
          createdAt: now,
          details: detailMap.values.where((d) => entry.value.any((r) => r['sku'] == d.sku)).toList(),
        );

        _pendingGateOrders.add(_PendingGateOrder(
          order: order,
          items: poItems,
          products: newProducts,
          pallets: const {},
          supplier: order.sourceSupplier,
          fileName: 'File PO',
        ));
        _pendingLoadedOrderNos.add(poNo);
      }

      if (mounted) {
        setState(() => _isImporting = false);
      }

      if (_pendingGateOrders.isNotEmpty) {
        _selectActivePendingOrder(_pendingLoadedOrderNos.first);
      }
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
                          } else if (value == 'clear_pending') {
                            _triggerClearAllPendingDialog();
                          }
                        },
                        itemBuilder: (context) {
                          final hasPending = _pendingGateOrders.isNotEmpty ||
                              _repo.inboundOrders.any((o) => o.status == InboundOrderStatus.newOrder) ||
                              _repo.items.any((i) => i.status == ItemStatus.pendingInbound) ||
                              _pendingLoadedOrderNos.isNotEmpty;
                          return [
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
                            if (hasPending) ...[
                              const PopupMenuDivider(),
                              PopupMenuItem<String>(
                                value: 'clear_pending',
                                enabled: !_isImporting,
                                child: SizedBox(
                                  width: 360,
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.delete_sweep_outlined, color: Color(0xFFEF4444), size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Text(
                                              'Xóa Sạch Đơn Vừa Nạp Nhầm Khỏi CSDL',
                                              style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Xóa toàn bộ dữ liệu đơn chờ để chọn nạp file khác',
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
                          ];
                        },
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
                        message: 'Đồng bộ & làm mới dữ liệu từ CSDL và Cloud',
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.textPrimary,
                            side: BorderSide(color: c.border),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: Icon(Icons.refresh, size: 16, color: c.textPrimary),
                          label: Text('LÀM MỚI', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: _handleSyncReload,
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
    final totalExpected = _totalFileExpected;
    final totalScanned = _totalFileScanned;
    final isAllFileComplete = totalExpected > 0 && totalScanned >= totalExpected;
    final unexpList = _getFilteredUnexpectedTags();
    final hasUnexpectedTags = unexpList.isNotEmpty;

    final hasPendingInbound = _pendingGateOrders.isNotEmpty || _repo.items.any((i) => i.status == ItemStatus.pendingInbound);
    final isVehicleActive = hasPendingInbound;

    final waitingPutawayItems = _repo.items.where((i) =>
      i.status == ItemStatus.waitingPutaway ||
      (i.status == ItemStatus.inStock &&
       (i.locationId == null || i.locationId!.trim().isEmpty) &&
       (i.palletId != null && i.palletId!.trim().isNotEmpty))
    ).toList();

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

          // 2.1 BANNER THÔNG BÁO HÀNG ĐÃ QUA CỔNG - CHƯA CẤT LÊN KỆ (CHỜ TAY CẦM PDA)
          if (waitingPutawayItems.isNotEmpty && !_hasDiscrepancyError) ...[
            _buildWaitingPutawayNoticeBanner(c, waitingPutawayItems),
            const SizedBox(height: 12),
          ],

          // 3. KHUNG NỘI DUNG CHÍNH (ĐANG CÓ XE QUA CỔNG HOẶC MÀN HÌNH CHỜ QUÉT TỰ ĐỘNG)
          Expanded(
            child: isVehicleActive
                ? _buildActiveVehicleScanView(
                    c,
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
            scannedCount: totalScanned,
            expectedCount: totalExpected,
            isComplete: isAllFileComplete,
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

  // ---------- 2.1 BANNER THÔNG BÁO HÀNG ĐÃ QUA CỔNG CHỜ TAY CẦM CẤT KỆ ----------
  Widget _buildWaitingPutawayNoticeBanner(EyeCareColors c, List<Item> waitingItems) {
    final palletSet = <String>{};
    for (final it in waitingItems) {
      if (it.palletId != null && it.palletId!.trim().isNotEmpty) {
        palletSet.add(it.palletId!.replaceAll('PAL-', '').trim());
      }
    }
    final palletText = palletSet.isEmpty ? 'Xe Pallet' : palletSet.join(', ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shelves, color: Color(0xFFF59E0B), size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📦 HÀNG ĐÃ NHẬP QUA CỔNG - CHƯA CẤT LÊN KỆ (Chờ tay cầm PDA xếp vào vị trí kệ)',
                  style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                const SizedBox(height: 2),
                Text(
                  'Xe: $palletText • ${waitingItems.length} sản phẩm đang ở khu vực đệm chờ cất vào kệ. Khi tay cầm PDA hoàn tất xếp kệ, thông báo này sẽ tự động biến mất.',
                  style: TextStyle(color: c.textPrimary, fontSize: 12),
                ),
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
    required List<TagInfo> unexpList,
    required bool hasUnexpectedTags,
  }) {
    // 1. Lấy danh sách các xe pallet đã qua cổng (hoặc xe đầu tiên trong file nếu chưa qua)
    final passedOrders = _pendingGateOrders.where((p) =>
      (_scannedTagsByOrderNo[p.order.orderNo]?.isNotEmpty == true) ||
      _scannedPalletTagsByOrderNo.containsKey(p.order.orderNo) ||
      p.order.orderNo == _activeOrderNo
    ).toList();

    if (passedOrders.isEmpty && _pendingGateOrders.isNotEmpty) {
      passedOrders.add(_pendingGateOrders.first);
    }

    // Nếu không có trong _pendingGateOrders (ví dụ: quét trực tiếp từ CSDL)
    if (passedOrders.isEmpty) {
      final expectedSerials = _getWizardExpectedSerials();
      final expectedCount = expectedSerials.length;
      final scannedCount = expectedCount > 0 ? expectedSerials.where((s) => _wizardScannedTags.containsKey(s)).length : _wizardScannedTags.length;
      final isComplete = expectedCount > 0 && scannedCount >= expectedCount;
      final progress = expectedCount > 0 ? (scannedCount / expectedCount).clamp(0.0, 1.0) : 0.0;
      final activeItems = _getStep2FlatInspectionItems();
      final pCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode ?? 'Xe Pallet';
      final pRfid = _activePalletTag ?? _wizardDetectedPalletTag ?? _activePallet?.rfidEpc ?? '--';

      return _buildSingleVehicleLayout(
        c,
        palletCode: pCode,
        palletRfid: pRfid,
        orderNo: _activeOrderNo ?? '--',
        items: activeItems,
        expectedCount: expectedCount,
        scannedCount: scannedCount,
        isComplete: isComplete,
        progress: progress,
        unexpList: unexpList,
        hasUnexpectedTags: hasUnexpectedTags,
        isScannedCallback: (epc) => _wizardScannedTags.containsKey(epc),
      );
    }

    // Nếu chỉ có 1 xe đi qua (hiển thị trọn vẹn không cuộn ngoài)
    if (passedOrders.length == 1) {
      final pOrder = passedOrders.first;
      final ordNo = pOrder.order.orderNo;
      final pCode = pOrder.pallets.keys.firstOrNull ?? (pOrder.items.isNotEmpty ? pOrder.items.first.palletId?.replaceAll('PAL-', '') : null) ?? ordNo;
      final pRfid = _scannedPalletTagsByOrderNo[ordNo] ?? pOrder.pallets[pCode] ?? '--';
      final scannedMap = _scannedTagsByOrderNo[ordNo] ?? {};
      final scannedCount = pOrder.items.where((i) => scannedMap.containsKey(i.epc.trim().toUpperCase())).length;
      final expectedCount = pOrder.items.length;
      final isComplete = expectedCount > 0 && scannedCount >= expectedCount;
      final progress = expectedCount > 0 ? (scannedCount / expectedCount).clamp(0.0, 1.0) : 0.0;

      final items = pOrder.items.map((i) => {
        'boxCode': i.cartonCode ?? '--',
        'sku': i.sku,
        'productName': i.productName,
        'serial': i.epc,
      }).toList();

      return _buildSingleVehicleLayout(
        c,
        palletCode: pCode,
        palletRfid: pRfid,
        orderNo: ordNo,
        items: items,
        expectedCount: expectedCount,
        scannedCount: scannedCount,
        isComplete: isComplete,
        progress: progress,
        unexpList: unexpList,
        hasUnexpectedTags: hasUnexpectedTags,
        isScannedCallback: (epc) => scannedMap.containsKey(epc) || _wizardScannedTags.containsKey(epc),
      );
    }

    // Nếu có NHIỀU XE pallet đi qua liên tục (cuộn mượt mà từng xe)
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: passedOrders.length + (hasUnexpectedTags ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 16),
      itemBuilder: (ctx, idx) {
        if (idx < passedOrders.length) {
          final pOrder = passedOrders[idx];
          return _buildMultiVehicleCard(c, pOrder);
        } else {
          return _buildUnexpectedCard(c, unexpList);
        }
      },
    );
  }

  Widget _buildSingleVehicleLayout(
    EyeCareColors c, {
    required String palletCode,
    required String palletRfid,
    required String orderNo,
    required List<Map<String, dynamic>> items,
    required int expectedCount,
    required int scannedCount,
    required bool isComplete,
    required double progress,
    required List<TagInfo> unexpList,
    required bool hasUnexpectedTags,
    required bool Function(String epc) isScannedCallback,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Dòng xe Pallet
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: c.bgCardElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isComplete ? const Color(0xFF10B981) : (scannedCount > 0 ? c.rfidCyan : c.border),
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
                          'Xe Pallet: $palletCode',
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
                      'Mã Đơn: $orderNo • RFID Pallet: $palletCode ($palletRfid) • Cần nhận diện: $expectedCount chip hàng',
                      style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // 2. Thanh tiến độ đọc & Hero Counter
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

        // 3. Bảng danh mục sản phẩm đối soát thời gian thực
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: [
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
                Expanded(
                  child: ListView.separated(
                    itemCount: items.length + unexpList.length,
                    separatorBuilder: (_, _) => Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
                    itemBuilder: (ctx, idx) {
                      if (idx < items.length) {
                        final item = items[idx];
                        final epc = (item['serial'] ?? '').toString().trim().toUpperCase();
                        final isScanned = isScannedCallback(epc);
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
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              SizedBox(
                                width: 110,
                                child: Text(
                                  item['sku'] ?? '--',
                                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  item['productName'] ?? '--',
                                  style: TextStyle(color: c.textPrimary, fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  epc,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                        final unexp = unexpList[idx - items.length];
                        return Container(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              SizedBox(width: 45, child: Text('${idx + 1}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12))),
                              const SizedBox(width: 120, child: Text('CHIP LẠ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12))),
                              const SizedBox(width: 110, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                              const Expanded(
                                flex: 3,
                                child: Text(
                                  'Chip không thuộc đơn hàng đang qua cổng!',
                                  style: TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Text(
                                  unexp.epc,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFEF4444),
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: 140,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFEF4444)),
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

  Widget _buildMultiVehicleCard(EyeCareColors c, _PendingGateOrder pOrder) {
    final ordNo = pOrder.order.orderNo;
    final pCode = pOrder.pallets.keys.firstOrNull ?? (pOrder.items.isNotEmpty ? pOrder.items.first.palletId?.replaceAll('PAL-', '') : null) ?? ordNo;
    final pRfid = _scannedPalletTagsByOrderNo[ordNo] ?? pOrder.pallets[pCode] ?? '--';
    final scannedMap = _scannedTagsByOrderNo[ordNo] ?? {};
    final scannedCount = pOrder.items.where((i) => scannedMap.containsKey(i.epc.trim().toUpperCase())).length;
    final expectedCount = pOrder.items.length;
    final isComplete = expectedCount > 0 && scannedCount >= expectedCount;
    final progress = expectedCount > 0 ? (scannedCount / expectedCount).clamp(0.0, 1.0) : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isComplete ? const Color(0xFF10B981) : (scannedCount > 0 ? c.rfidCyan : c.border),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pallet Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
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
                    size: 22,
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
                            'Xe Pallet: $pCode',
                            style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
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
                      const SizedBox(height: 2),
                      Text(
                        'Mã Đơn: $ordNo • RFID Pallet: $pCode ($pRfid) • Cần nhận diện: $expectedCount chip hàng',
                        style: TextStyle(color: c.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: isComplete ? const Color(0xFF10B981).withValues(alpha: 0.15) : c.bgDeep,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: isComplete ? const Color(0xFF10B981) : c.border),
                  ),
                  child: Text(
                    '$scannedCount / $expectedCount chip',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isComplete ? const Color(0xFF10B981) : c.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Progress bar
          LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: c.border.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(
              isComplete ? const Color(0xFF10B981) : c.rfidCyan,
            ),
          ),

          // Table of carton chips below pallet line
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: c.bgDeep,
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
          for (int idx = 0; idx < pOrder.items.length; idx++) ...[
            if (idx > 0) Divider(height: 1, color: c.border.withValues(alpha: 0.4)),
            Builder(builder: (ctx) {
              final item = pOrder.items[idx];
              final epc = item.epc.trim().toUpperCase();
              final isScanned = scannedMap.containsKey(epc);
              return Container(
                color: isScanned ? const Color(0xFF10B981).withValues(alpha: 0.05) : Colors.transparent,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(width: 45, child: Text('${idx + 1}', style: TextStyle(color: c.textSecondary, fontSize: 12))),
                    SizedBox(
                      width: 120,
                      child: Text(
                        item.cartonCode ?? '--',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(
                      width: 110,
                      child: Text(
                        item.sku,
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        item.productName,
                        style: TextStyle(color: c.textPrimary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        epc,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildUnexpectedCard(EyeCareColors c, List<TagInfo> unexpList) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning, size: 16, color: Color(0xFFEF4444)),
                const SizedBox(width: 8),
                Text(
                  'CÓ ${unexpList.length} CHIP LẠ NGOÀI ĐƠN HÀNG!',
                  style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
          for (int idx = 0; idx < unexpList.length; idx++) ...[
            if (idx > 0) Divider(height: 1, color: const Color(0xFFEF4444).withValues(alpha: 0.2)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  SizedBox(width: 45, child: Text('${idx + 1}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12))),
                  const SizedBox(width: 120, child: Text('CHIP LẠ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12))),
                  const SizedBox(width: 110, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                  const Expanded(
                    flex: 3,
                    child: Text('Chip không thuộc đơn hàng đang qua cổng!', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      unexpList[idx].epc,
                      style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Color(0xFFEF4444), fontSize: 11.5),
                    ),
                  ),
                  const SizedBox(
                    width: 140,
                    child: Center(
                      child: Text('❌ CHIP LẠ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11)),
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

  // ---------- 4. MÀN HÌNH CHỜ QUÉT TỰ ĐỘNG KHI CHƯA CÓ XE QUA CỔNG ----------
  Widget _buildIdleGateMonitor(EyeCareColors c) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 36),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.rfidCyan.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.sensors, size: 48, color: c.rfidCyan),
            ),
            const SizedBox(height: 16),
            Text(
              'CỔNG RFID ĐANG SẴN SÀNG TIẾP NHẬN HÀNG',
              style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Vui lòng bấm nút [NHẬP HÀNG] ở góc trên để tải file Excel/PO vào hệ thống.\nSau khi nạp file, hệ thống sẽ tự động quét và đối soát mã chip RFID khi xe qua cổng.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary, fontSize: 12.5, height: 1.5),
            ),
          ],
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCardElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.border),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(Icons.refresh, size: 15, color: c.textSecondary),
              label: Text('Làm Mới Quét', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
              onPressed: _resetWizard,
            ),
            const SizedBox(width: 10),
            // Bộ chọn thời gian quét: 5s, 10s, Liên tục
            Container(
              padding: const EdgeInsets.all(2),
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
            const SizedBox(width: 8),
            // Nút Bắt đầu / Dừng quét
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _wizardIsScanning ? const Color(0xFFEF4444) : c.rfidCyan,
                foregroundColor: _wizardIsScanning ? Colors.white : const Color(0xFF2C251E),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                elevation: 2,
              ),
              icon: Icon(_wizardIsScanning ? Icons.stop : Icons.sensors, size: 16),
              label: Text(
                _wizardIsScanning
                    ? (_wizardScanDuration == 0 ? 'DỪNG QUÉT LIÊN TỤC' : 'DỪNG QUÉT ($_wizardScanCountdown s)')
                    : 'BẮT ĐẦU QUÉT (${_wizardScanDuration == 0 ? "LIÊN TỤC" : "${_wizardScanDuration}s"})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
              onPressed: _toggleWizardScan,
            ),
            if (isVehicleActive) ...[
              const SizedBox(width: 8),
              // Nút Báo lỗi sai sót thủ công
              if (hasUnexpectedTags || (expectedCount > 0 && scannedCount < expectedCount))
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.report_problem, size: 15, color: Color(0xFFEF4444)),
                  label: const Text('BÁO LỖI SAI SÓT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  onPressed: _reportDiscrepancyError,
                ),
              const SizedBox(width: 8),
              // Nút Xác nhận nhập kho (CHỈ cho phép bấm khi đọc đủ 100% và không có chip lạ)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isComplete
                      ? const Color(0xFF10B981)
                      : c.bgDeep,
                  foregroundColor: isComplete ? Colors.white : c.textMuted,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: isComplete ? 3 : 0,
                  side: BorderSide(color: isComplete ? const Color(0xFF10B981) : c.border),
                ),
                icon: Icon(isComplete ? Icons.check_circle : Icons.hourglass_top_rounded, size: 16),
                label: Text(
                  isComplete
                      ? 'ĐÃ ĐỌC ĐỦ $scannedCount/$expectedCount (TỰ ĐỘNG ĐẨY SANG PDA)'
                      : (scannedCount > 0 ? 'CHƯA ĐỌC ĐỦ ($scannedCount/$expectedCount CHIP)' : 'CHƯA ĐỌC ĐỦ'),
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: isComplete ? Colors.white : c.textMuted),
                ),
                onPressed: (isComplete && !hasUnexpectedTags) ? _completeGoodsReceiveAtGate : null,
              ),
            ],
          ],
        ),
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
