import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/wms_models.dart';
import '../../models/tag_info.dart';
import '../../services/warehouse_repository.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/uhf_service.dart';
import '../../services/tower_light_service.dart';
import '../../services/supabase_sync_service.dart';
import '../../services/excel_import_service.dart';
import '../../services/inbound_demo_service.dart';
import '../../theme/eye_care_theme.dart';

/// Mô hình lưu tạm đơn hàng chờ qua cổng RFID (chưa quét sẽ KHÔNG lưu vào CSDL)
class _PendingGateOrder {
  final InboundOrder order;
  final List<Item> items;
  final List<Product> products;
  final Map<String, String?> pallets; // palletCode -> rfidEpc
  final String supplier;
  final String fileName;
  bool isGatePassed = false;
  final Set<String> passedPalletCodes = {};

  _PendingGateOrder({
    required this.order,
    required this.items,
    required this.products,
    required this.pallets,
    required this.supplier,
    required this.fileName,
  });

  List<String> getPalletCodes() {
    final codes = <String>{};
    if (pallets.isNotEmpty) {
      codes.addAll(pallets.keys.where((k) => k.trim().isNotEmpty));
    }
    for (final it in items) {
      if (it.palletId != null && it.palletId!.isNotEmpty) {
        codes.add(it.palletId!.replaceAll('PAL-', ''));
      }
    }
    if (codes.isEmpty) {
      codes.add(order.orderNo);
    }
    return codes.toList()..sort();
  }

  List<Item> getItemsForPallet(String palletCode) {
    final cleanPal = palletCode.trim().toUpperCase().replaceAll('PAL-', '');
    final palCodes = getPalletCodes();
    return items.where((i) {
      final itPal = (i.palletId ?? '').trim().toUpperCase().replaceAll('PAL-', '');
      if (itPal == cleanPal) return true;
      if (palCodes.length <= 1 && itPal.isEmpty) return true;
      return false;
    }).toList();
  }
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

  // Cơ chế lọc chip đã quét qua cổng (tránh báo chip lạ khi xe pallet còn trong vùng phủ sóng - luôn tự động bật)
  final Set<String> _passedGateEpcs = {};
  final Map<String, TagInfo> _filteredPassedTags = {};

  // Trạng thái còi tháp đèn và nhật ký cảnh báo an ninh nhập kho
  bool _isBuzzerManuallySilenced = false;
  final Set<String> _securityAlertLoggedEpcs = {};

  bool _wizardIsScanning = false;
  int _wizardScanDuration = 0; // 0 = liên tục (mặc định cho cổng quét), 5s, 10s
  int _wizardScanCountdown = 0;
  Timer? _wizardCountdownTimer;

  int get _totalFileExpected {
    if (_pendingGateOrders.isNotEmpty) {
      final targetOrders = _activeOrderNo != null
          ? _pendingGateOrders.where((p) => p.order.orderNo == _activeOrderNo || p.order.inboundOrderId == _activeOrderNo).toList()
          : _pendingGateOrders.where((p) => !p.isGatePassed).toList();
      final effectiveOrders = targetOrders.isNotEmpty ? targetOrders : _pendingGateOrders;
      int count = 0;
      for (final p in effectiveOrders) {
        count += p.items.length;
        for (final palletEpc in p.pallets.values) {
          if (palletEpc != null && palletEpc.isNotEmpty && palletEpc != '--') {
            count += 1;
          }
        }
      }
      return count;
    }
    final effectiveItems = _activeExpectedItems.isNotEmpty
        ? _activeExpectedItems
        : _repo.items.where((i) => i.status == ItemStatus.pendingInbound).toList();
    return effectiveItems.length;
  }

  int get _totalFileScanned {
    if (_pendingGateOrders.isNotEmpty) {
      final targetOrders = _activeOrderNo != null
          ? _pendingGateOrders.where((p) => p.order.orderNo == _activeOrderNo || p.order.inboundOrderId == _activeOrderNo).toList()
          : _pendingGateOrders.where((p) => !p.isGatePassed).toList();
      final effectiveOrders = targetOrders.isNotEmpty ? targetOrders : _pendingGateOrders;
      int count = 0;
      for (final p in effectiveOrders) {
        final ordNo = p.order.orderNo;
        final scannedMap = _scannedTagsByOrderNo[ordNo] ?? {};
        final matchedItemsCount = p.items.where((i) {
          final clean = i.epc.trim().toUpperCase();
          return clean != '--' && clean.isNotEmpty &&
              (scannedMap.containsKey(clean) || _wizardScannedTags.containsKey(clean) || _passedGateEpcs.contains(clean));
        }).length;
        count += matchedItemsCount;
        for (final palletEpc in p.pallets.values) {
          if (palletEpc != null && palletEpc.isNotEmpty && palletEpc != '--') {
            final cleanPal = palletEpc.trim().toUpperCase();
            if (scannedMap.containsKey(cleanPal) || _wizardScannedTags.containsKey(cleanPal) || _passedGateEpcs.contains(cleanPal)) {
              count += 1;
            }
          }
        }
      }
      return count;
    }
    final effectiveItems = _activeExpectedItems.isNotEmpty
        ? _activeExpectedItems
        : _repo.items.where((i) => i.status == ItemStatus.pendingInbound).toList();
    return effectiveItems.where((i) {
      final clean = i.epc.trim().toUpperCase();
      return clean != '--' && clean.isNotEmpty &&
          (_passedGateEpcs.contains(clean) || _wizardScannedTags.containsKey(clean));
    }).length;
  }

  void _syncWizardScannedTagsForActiveOrder() {
    _wizardScannedTags.clear();
    final ordNo = _activeOrderNo;
    if (ordNo != null && _scannedTagsByOrderNo.containsKey(ordNo)) {
      final activeSerials = _activeExpectedItems.map((i) => i.epc.trim().toUpperCase()).toSet();
      if (_activePalletTag != null && _activePalletTag!.isNotEmpty) {
        activeSerials.add(_activePalletTag!.trim().toUpperCase());
      }
      final allOrderTags = _scannedTagsByOrderNo[ordNo]!;
      for (final entry in allOrderTags.entries) {
        if (activeSerials.isEmpty || activeSerials.contains(entry.key.trim().toUpperCase())) {
          _wizardScannedTags[entry.key] = entry.value;
        }
      }
    }
  }


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
    _towerLight.addListener(_onThemeUpdate);
    _initTagListener();
  }

  void _onThemeUpdate() {
    if (mounted) setState(() {});
  }

  void _onRepoUpdate() {
    if (_isImporting) return;
    _invalidateCartonCaches();

    // Kiểm tra các đơn hàng đã qua cổng (isGatePassed == true) xem toàn bộ hàng đã được PDA cất lên kệ chưa
    final fullyPutawayOrders = <_PendingGateOrder>[];
    for (final pOrder in _pendingGateOrders) {
      if (!pOrder.isGatePassed) continue;
      final allItemsPutaway = pOrder.items.isNotEmpty && pOrder.items.every((i) {
        final epc = i.epc.trim().toUpperCase();
        final dbItem = _repo.items.where((it) => it.epc.trim().toUpperCase() == epc).firstOrNull;
        return dbItem != null &&
            dbItem.status == ItemStatus.inStock &&
            dbItem.locationId != null &&
            dbItem.locationId!.trim().isNotEmpty;
      });

      if (allItemsPutaway) {
        fullyPutawayOrders.add(pOrder);
      }
    }

    if (fullyPutawayOrders.isNotEmpty) {
      for (final p in fullyPutawayOrders) {
        _pendingGateOrders.remove(p);
        _pendingLoadedOrderNos.remove(p.order.orderNo);
        _scannedTagsByOrderNo.remove(p.order.orderNo);
        _scannedPalletTagsByOrderNo.remove(p.order.orderNo);
      }

      if (_pendingGateOrders.isEmpty) {
        _activeOrderNo = null;
        _activePallet = null;
        _activePalletTag = null;
        _activeExpectedItems.clear();
        _wizardScannedTags.clear();
        _stopWizardScan();
        _desktopUhf.clearTags();
      }

      final ordNames = fullyPutawayOrders.map((p) => p.order.orderNo).join(', ');
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
          content: Text('✓ Đơn hàng $ordNames đã được cất lên vị trí kệ kho hoàn tất.'),
        ),
      );
    }

    // Tương tự nếu quét theo _activeExpectedItems (không qua file)
    if (_activeExpectedItems.isNotEmpty && _activeOrderNo != null) {
      final allPutaway = _activeExpectedItems.every((i) {
        final epc = i.epc.trim().toUpperCase();
        final dbItem = _repo.items.where((it) => it.epc.trim().toUpperCase() == epc).firstOrNull;
        return dbItem != null &&
            dbItem.status == ItemStatus.inStock &&
            dbItem.locationId != null &&
            dbItem.locationId!.trim().isNotEmpty;
      });
      if (allPutaway) {
        final ord = _activeOrderNo!;
        _activeOrderNo = null;
        _activePallet = null;
        _activePalletTag = null;
        _activeExpectedItems.clear();
        _wizardScannedTags.clear();
        _stopWizardScan();
        _desktopUhf.clearTags();
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
            content: Text('✓ Đơn hàng $ord đã được cất lên vị trí kệ kho hoàn tất.'),
          ),
        );
      }
    }

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
    if (_desktopUhf.isConnected && _desktopUhf.isScanning != _wizardIsScanning) {
      setState(() {
        _wizardIsScanning = _desktopUhf.isScanning;
        if (!_wizardIsScanning) {
          _wizardScanCountdown = _wizardScanDuration;
        }
      });
    }
    // Nếu không trong trạng thái quét, tuyệt đối không duyệt lại chip cũ và không gọi auto complete
    if (!_wizardIsScanning && !_desktopUhf.isScanning) {
      return;
    }
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
    _towerLight.removeListener(_onThemeUpdate);
    _towerLight.turnOffAll();
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

    // 1. Ưu tiên danh sách hàng của xe/pallet đang active hiện tại
    if (_activeExpectedItems.isNotEmpty) {
      set.addAll(_activeExpectedItems.map((i) => i.epc.trim().toUpperCase()).where((e) => e.isNotEmpty && e != '--'));
      if (_activePalletTag != null && _activePalletTag!.isNotEmpty && _activePalletTag != '--') {
        set.add(_activePalletTag!.trim().toUpperCase());
      }
    } else if (_activeOrderNo != null && _pendingGateOrders.isNotEmpty) {
      final pOrder = _pendingGateOrders.where((p) => p.order.orderNo == _activeOrderNo || p.order.inboundOrderId == _activeOrderNo).firstOrNull;
      if (pOrder != null) {
        set.addAll(pOrder.items.map((i) => i.epc.trim().toUpperCase()).where((e) => e.isNotEmpty && e != '--'));
        for (final pal in pOrder.pallets.values) {
          if (pal != null && pal.isNotEmpty && pal != '--') {
            set.add(pal.trim().toUpperCase());
          }
        }
      }
    } else if (_pendingGateOrders.isNotEmpty) {
      for (final p in _pendingGateOrders) {
        if (p.isGatePassed) continue;
        set.addAll(p.items.map((i) => i.epc.trim().toUpperCase()).where((e) => e.isNotEmpty && e != '--'));
        for (final pal in p.pallets.values) {
          if (pal != null && pal.isNotEmpty && pal != '--') {
            set.add(pal.trim().toUpperCase());
          }
        }
      }
    } else if (_wizardSelectedEpcs.isNotEmpty) {
      set.addAll(_wizardSelectedEpcs.map((e) => e.trim().toUpperCase()).where((e) => e.isNotEmpty && e != '--'));
    } else {
      final cartons = _getAvailableCartons();
      for (var c in cartons) {
        final box = (c['cartonBox'] ?? c['code'] ?? '').toString().trim();
        if (_wizardSelectedCartons.contains(box)) {
          final serials = (c['serials'] as List<dynamic>?)?.map((e) => e.toString().trim().toUpperCase()).toList() ?? [];
          set.addAll(serials.where((e) => e.isNotEmpty && e != '--'));
        }
      }
      if (set.isEmpty) {
        final dbPending = _repo.items.where((i) => i.status == ItemStatus.pendingInbound);
        set.addAll(dbPending.map((i) => i.epc.trim().toUpperCase()).where((e) => e.isNotEmpty && e != '--'));
      }
    }

    _cachedExpectedSerials = set;
    return set;
  }

  List<Map<String, dynamic>> _getStep1DetailedItems() {
    if (_cachedStep1DetailedItems != null) return _cachedStep1DetailedItems!;
    final List<Map<String, dynamic>> list = [];
    if (_activeExpectedItems.isNotEmpty) {
      list.addAll(_activeExpectedItems.map((i) {
        final pal = _repo.pallets.where((p) => p.palletId == i.palletId || p.palletCode == i.palletId).firstOrNull;
        return {
          'boxCode': i.cartonCode ?? '--',
          'palletCode': i.palletId ?? '--',
          'palletEpc': pal?.rfidEpc ?? '--',
          'sku': i.sku,
          'productName': i.productName,
          'serial': i.epc,
          'supplier': i.supplier ?? _repo.inboundOrders.where((o) => o.orderNo == i.orderNo).firstOrNull?.sourceSupplier ?? '--',
          'orderNo': i.orderNo ?? '--',
        };
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
            'palletCode': (cBox['palletCode'] ?? cBox['palletId'] ?? '--').toString(),
            'palletEpc': (cBox['palletEpc'] ?? '--').toString(),
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

  Widget _buildMetricBadge({
    required String label,
    required int count,
    required Color color,
    required EyeCareColors c,
    double width = 80,
  }) {
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.6), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '$count',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
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
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest && !_desktopUhf.isConnected) {
      final success = await _desktopUhf.connectWithSavedConfig();
      if (!success && !_desktopUhf.isConnected) {
        debugPrint('⚠️ Chưa kết nối được đầu đọc RFID (${_desktopUhf.config.connectionSummary}).');
        if (mounted) {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              duration: const Duration(seconds: 4),
              backgroundColor: const Color(0xFFF59E0B),
              content: Row(
                children: [
                  const Icon(Icons.wifi_off, color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Chưa kết nối được đầu đọc RFID (${_desktopUhf.config.connectionSummary}). Đang ở chế độ quét chờ thiết bị...',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }
    _uhf.enableScanning('nhap_kho');
    _uhf.startInventory();
    if (!isTest && _desktopUhf.isConnected) {
      await _desktopUhf.startInventory();
    }

    setState(() {
      _wizardIsScanning = true;
      _wizardScanCountdown = duration > 0 ? duration : 0;
    });

    _towerLight.triggerScanning(
      reason: 'CỔNG NHẬP KHO: Đang phát sóng quét đối soát chip RFID...',
    );

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
    _wizardCountdownTimer = null;
    _tagBatchUiTimer?.cancel();
    _tagBatchUiTimer = null;

    if (mounted) {
      setState(() {
        _wizardIsScanning = false;
        _wizardScanCountdown = _wizardScanDuration;
      });
    }

    _uhf.disableScanning();
    _uhf.stopInventory();
    await _desktopUhf.stopInventory();

    if (_wizardUnexpectedTags.isEmpty) {
      _towerLight.turnOffAll(reason: 'Đã dừng quét cổng nhập kho');
    }

    // Tự động kiểm tra và xác nhận nếu đã đối soát đủ khi dừng quét
    _checkAndTriggerAutoComplete();
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
      if (_passedGateEpcs.contains(epc) || _repo.items.any((i) => i.epc.trim().toUpperCase() == epc)) {
        return false;
      }
      if (_repo.findPalletByRfid(epc) != null) return false;
      return true;
    }).toList();
  }

  void _handleWizardGateTag(TagInfo tag) {
    final cleanEpc = tag.epc.trim().toUpperCase();
    if (cleanEpc.isEmpty) return;

    // BẮT BUỘC: Nếu không trong trạng thái quét (_wizardIsScanning == false) hoặc tất cả đơn đã qua cổng, không xử lý thẻ
    if (!_wizardIsScanning) {
      return;
    }
    if (_pendingGateOrders.isNotEmpty && _pendingGateOrders.every((p) => p.isGatePassed)) {
      return;
    }

    // Nếu chưa nạp file và không có đơn hàng nào đang chờ qua cổng: cảnh báo an ninh cổng nhập
    final hasPendingOrders = _pendingGateOrders.isNotEmpty ||
        _repo.items.any((i) => i.status == ItemStatus.pendingInbound);
    if (!hasPendingOrders) {
      if (!_wizardUnexpectedTags.containsKey(cleanEpc)) {
        _wizardUnexpectedTags[cleanEpc] = tag;
        setState(() {});
      }
      SystemSound.play(SystemSoundType.alert);
      _towerLight.triggerWarningRed(
        withBuzzer: !_isBuzzerManuallySilenced,
        reason: '🚨 CẢNH BÁO NHẬP KHO: Phát hiện chip ($cleanEpc) qua cổng khi CHƯA CÓ ĐƠN HÀNG!',
        persistent: false,
        durationSeconds: 3,
      );
      if (!_securityAlertLoggedEpcs.contains(cleanEpc)) {
        _securityAlertLoggedEpcs.add(cleanEpc);
        _repo.recordTagLifecycle(
          epc: cleanEpc,
          productName: 'Thẻ qua cổng nhập khi chưa có đơn',
          action: TagLifecycleAction.unauthorizedExit,
          newStatus: 'UNAUTHORIZED_INBOUND',
          performedBy: 'Hệ thống Cổng RFID Nhập Kho',
          device: 'Cổng RFID Desktop Hopeland',
          notes: '🚨 CẢNH BÁO: Thẻ RFID đi qua cổng nhập kho khi chưa kích hoạt đơn hàng nào!',
        );
      }
      return;
    }

    // Khi có chip mới tới cổng, xóa ngay banner thông báo thành công của đơn trước
    if (_lastSuccessOrderNo != null) {
      _lastSuccessOrderNo = null;
      _successBannerTimer?.cancel();
    }

    // 0. CƠ CHẾ LỌC CÁC CHIP ĐÃ QUÉT TRƯỚC ĐÓ ĐÃ QUA CỔNG (LUÔN TỰ ĐỘNG BẬT)
    final isPassedGate = _passedGateEpcs.contains(cleanEpc);
    final isExistingItemInWarehouse = _repo.items.any((i) =>
      i.epc.trim().toUpperCase() == cleanEpc && i.status != ItemStatus.pendingInbound
    );

    // Kiểm tra xem chip này có thuộc đơn hàng ĐANG CHỜ qua cổng hay không
    final isInPendingOrder = _pendingGateOrders.where((p) => !p.isGatePassed).any((p) =>
      p.items.any((i) => i.epc.trim().toUpperCase() == cleanEpc) ||
      p.pallets.values.any((v) => (v ?? '').trim().toUpperCase() == cleanEpc)
    ) || _activeExpectedItems.any((i) => i.epc.trim().toUpperCase() == cleanEpc) ||
    _repo.items.any((i) => i.epc.trim().toUpperCase() == cleanEpc && i.status == ItemStatus.pendingInbound);

    if ((isPassedGate || isExistingItemInWarehouse) && !isInPendingOrder) {
      // Chip đã qua cổng thành công trước đó hoặc đã lưu kho -> lọc bỏ, không coi là chip lạ
      _filteredPassedTags[cleanEpc] = tag;
      _wizardUnexpectedTags.remove(cleanEpc);
      return;
    }

    // 1. TỰ ĐỘNG NHẬN DIỆN XE PALLET
    // 1.1 Kiểm tra nếu đây là chip của xe Pallet đang active
    final curPalletEpc = (_activePallet?.rfidEpc ?? _wizardDetectedPalletTag ?? _wizardDetectedPallet?.rfidEpc)?.trim().toUpperCase();
    if (curPalletEpc != null && curPalletEpc.isNotEmpty && (curPalletEpc == cleanEpc || _wizardDetectedPalletTag == cleanEpc || _activePalletTag == cleanEpc)) {
      _wizardUnexpectedTags.remove(cleanEpc);
      _wizardScannedTags[cleanEpc] = tag;
      if (_activeOrderNo != null) {
        _scannedTagsByOrderNo.putIfAbsent(_activeOrderNo!, () => {})[cleanEpc] = tag;
      }
      if (mounted) setState(() {});
      return;
    }

    // 1.2 Kiểm tra nếu chip quét được là chip của một xe Pallet (từ đơn chờ qua cổng hoặc CSDL)
    _PendingGateOrder? matchedPendingPalletOrder;
    Pallet? matchedPallet;
    String? matchedPalletEpc;

    for (final pOrder in _pendingGateOrders) {
      if (pOrder.isGatePassed) continue;
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
          _pendingGateOrders.where((p) => !p.isGatePassed && (p.pallets.containsKey(mPallet.palletCode) || p.items.any((i) => i.palletId == mPallet.palletId || i.palletId == mPallet.palletCode))).firstOrNull?.order.orderNo ??
          _repo.items.where((i) => (i.palletId == mPallet.palletId || i.palletId == mPallet.palletCode) && i.status == ItemStatus.pendingInbound).firstOrNull?.orderNo;

      // Nếu không khớp mã pallet trong file nhưng file chỉ có 1 đơn hàng chưa qua cổng (hoặc đang có đơn active)
      final remainingPending = _pendingGateOrders.where((p) => !p.isGatePassed).toList();
      if (targetOrderNo == null && remainingPending.length == 1) {
        targetOrderNo = remainingPending.first.order.orderNo;
      }
      targetOrderNo ??= _activeOrderNo;

      _wizardScannedTags[cleanEpc] = tag;
      if (targetOrderNo != null) {
        _scannedPalletTagsByOrderNo[targetOrderNo] = cleanEpc;
        _scannedTagsByOrderNo.putIfAbsent(targetOrderNo, () => {})[cleanEpc] = tag;
      }

      // Chỉ kích hoạt xe Pallet nếu xác định được đơn hàng chờ tương ứng (tránh tạo xe ma 0/0 chip)
      final bool activePalletHasScannedItems = _activeExpectedItems.any((i) =>
        _wizardScannedTags.containsKey(i.epc.trim().toUpperCase())
      );
      final bool shouldSwitchPallet = targetOrderNo != null &&
          (_activePallet?.palletCode != mPallet.palletCode || _activeOrderNo != targetOrderNo) &&
          (_activePallet == null ||
           (matchedPendingPalletOrder?.passedPalletCodes.contains(_activePallet!.palletCode) == true) ||
           !activePalletHasScannedItems);

      if (shouldSwitchPallet) {
        _selectActivePendingPallet(targetOrderNo, mPallet.palletCode);
        _towerLight.triggerPass(reason: 'Đã nhận diện Pallet ${mPallet.palletCode}!');
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
      if (pOrder.isGatePassed) continue;
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

    // Nếu không khớp chính xác EPC đã có trong file, kiểm tra slot chưa gán EPC (-- hoặc rỗng)
    if (itemPendingOrder == null) {
      for (final pOrder in _pendingGateOrders) {
        if (pOrder.isGatePassed) continue;
        final ordNo = pOrder.order.orderNo;
        final scannedMap = _scannedTagsByOrderNo[ordNo] ?? {};
        if (scannedMap.containsKey(cleanEpc) || _wizardScannedTags.containsKey(cleanEpc)) continue;

        // Ưu tiên pallet đang active nếu có
        Item? unassignedSlot;
        if (_activePallet != null) {
          final cleanActivePal = _activePallet!.palletCode.trim().toUpperCase().replaceAll('PAL-', '');
          unassignedSlot = pOrder.items.where((i) {
            final itPal = (i.palletId ?? '').trim().toUpperCase().replaceAll('PAL-', '');
            final isPalMatch = itPal == cleanActivePal || (itPal.isEmpty && pOrder.getPalletCodes().length <= 1);
            return isPalMatch && (i.epc.trim().isEmpty || i.epc.trim() == '--');
          }).firstOrNull;
        }
        unassignedSlot ??= pOrder.items.where((i) => i.epc.trim().isEmpty || i.epc.trim() == '--').firstOrNull;

        if (unassignedSlot != null) {
          final slotIdx = pOrder.items.indexOf(unassignedSlot);
          if (slotIdx >= 0) {
            final updatedItem = unassignedSlot.copyWith(
              epc: cleanEpc,
              serialNumber: cleanEpc,
            );
            pOrder.items[slotIdx] = updatedItem;
            final repoIdx = _repo.items.indexWhere((it) => it.itemId == unassignedSlot!.itemId);
            if (repoIdx >= 0) {
              _repo.items[repoIdx] = updatedItem;
            }
            if (_activeExpectedItems.isNotEmpty) {
              final actIdx = _activeExpectedItems.indexWhere((it) => it.itemId == unassignedSlot!.itemId);
              if (actIdx >= 0) {
                _activeExpectedItems[actIdx] = updatedItem;
              }
            }
            _invalidateCartonCaches();
            itemPendingOrder = pOrder;
            matchedItem = updatedItem;
            break;
          }
        }
      }
    }

    if (itemPendingOrder != null && matchedItem != null) {
      final ordNo = itemPendingOrder.order.orderNo;
      final itPal = matchedItem.palletId;
      final cleanPal = (itPal != null && itPal.isNotEmpty) ? itPal.replaceAll('PAL-', '').trim() : null;

      // CHIP CỦA PALLET NÀO VÀO TRƯỚC THÌ CHỌN PALLET ĐÓ:
      // Tự động chuyển active pallet nếu:
      // 1. Chưa chọn xe nào (_activeOrderNo == null hoặc _activePallet == null)
      // 2. Hoặc xe hiện tại đã qua cổng (passedPalletCodes chứa pallet hiện tại)
      // 3. Hoặc xe hiện tại chưa quét được chip nào (0 chip) và chip này thuộc một xe pallet khác đang chờ
      final bool activePalletHasScannedItems = _activeExpectedItems.any((i) =>
        _wizardScannedTags.containsKey(i.epc.trim().toUpperCase())
      );
      final bool shouldSwitchPallet = _activeOrderNo == null ||
          _activePallet == null ||
          (cleanPal != null &&
           _activePallet!.palletCode != cleanPal &&
           (itemPendingOrder.passedPalletCodes.contains(_activePallet!.palletCode) || !activePalletHasScannedItems));

      if (shouldSwitchPallet) {
        if (cleanPal != null) {
          _selectActivePendingPallet(ordNo, cleanPal);
        } else {
          _selectActivePendingOrder(ordNo);
        }
      }

      final isNewTag = !_wizardScannedTags.containsKey(cleanEpc);
      _scannedTagsByOrderNo.putIfAbsent(ordNo, () => {})[cleanEpc] = tag;
      _wizardScannedTags[cleanEpc] = tag;
      _wizardUnexpectedTags.remove(cleanEpc);

      // Nếu thuộc đúng xe Pallet đang active hiện tại
      if (_activeOrderNo == ordNo && (_activePallet == null || cleanPal == null || _activePallet!.palletCode == cleanPal)) {
        if (isNewTag) {
          final expectedSerials = _getWizardExpectedSerials();
          if (expectedSerials.isNotEmpty && _wizardScannedTags.length >= expectedSerials.length && _getFilteredUnexpectedTags().isEmpty) {
            _tagBatchUiTimer?.cancel();
            _tagBatchUiTimer = null;
            final pCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode ?? 'Pallet';
            _towerLight.triggerPass(reason: 'Pallet $pCode: Đã quét đủ ${expectedSerials.length} sản phẩm. Tự động chuyển sang PDA!');
            if (mounted) setState(() {});
          } else {
            // Cập nhật UI real-time: dùng timer ngắn 60ms để gom batch tránh build quá nhiều
            _tagBatchUiTimer?.cancel();
            _tagBatchUiTimer = Timer(const Duration(milliseconds: 60), () {
              if (mounted) setState(() {});
            });
          }
        }
      } else {
        // Chip thuộc một xe Pallet KHÁC trong file đang chờ (ví dụ: Pallet 1 đã qua trước đó)
        // -> ĐÃ LƯU VÀO _scannedTagsByOrderNo[ordNo], TUYỆT ĐỐI KHÔNG BÁO CHIP LẠ!
        if (isNewTag) {
          _tagBatchUiTimer?.cancel();
          _tagBatchUiTimer = Timer(const Duration(milliseconds: 100), () {
            if (mounted) setState(() {});
          });
        }
      }
      _checkAndTriggerAutoComplete();
      return;
    }

    // 3. KIỂM TRA CHIP SẢN PHẨM TRONG CSDL (ItemStatus.pendingInbound)
    final dbItem = _repo.items.where((i) =>
      (i.epc.trim().toUpperCase() == cleanEpc || i.serialNumber.trim().toUpperCase() == cleanEpc) &&
      i.status == ItemStatus.pendingInbound
    ).firstOrNull;

    if (dbItem != null) {
      final ordNo = dbItem.orderNo ?? _activeOrderNo ?? 'INBOUND-AUTO';
      final itPal = dbItem.palletId;
      final cleanPal = (itPal != null && itPal.isNotEmpty) ? itPal.replaceAll('PAL-', '').trim() : null;

      final bool activePalletHasScannedItems = _activeExpectedItems.any((i) =>
        _wizardScannedTags.containsKey(i.epc.trim().toUpperCase())
      );
      final bool shouldSwitchPallet = _activeOrderNo == null ||
          _activePallet == null ||
          (cleanPal != null &&
           _activePallet!.palletCode != cleanPal &&
           (_passedGateEpcs.contains(_activePalletTag) || !activePalletHasScannedItems));

      if (shouldSwitchPallet) {
        if (cleanPal != null) {
          _selectActivePendingPallet(ordNo, cleanPal);
        } else {
          _selectActivePendingOrder(ordNo);
        }
      }

      final isNewTag = !_wizardScannedTags.containsKey(cleanEpc);
      _scannedTagsByOrderNo.putIfAbsent(ordNo, () => {})[cleanEpc] = tag;
      _wizardScannedTags[cleanEpc] = tag;
      _wizardUnexpectedTags.remove(cleanEpc);

      if (isNewTag) {
        final expectedSerials = _getWizardExpectedSerials();
        if (expectedSerials.isNotEmpty && _wizardScannedTags.length >= expectedSerials.length && _getFilteredUnexpectedTags().isEmpty) {
          _tagBatchUiTimer?.cancel();
          _tagBatchUiTimer = null;
          final pCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode ?? 'Pallet';
          _towerLight.triggerPass(reason: 'Pallet $pCode: Đã quét đủ ${expectedSerials.length} sản phẩm. Tự động chuyển sang PDA!');
          if (mounted) setState(() {});
        } else {
          _tagBatchUiTimer?.cancel();
          _tagBatchUiTimer = Timer(const Duration(milliseconds: 60), () {
            if (mounted) setState(() {});
          });
        }
      }
      _checkAndTriggerAutoComplete();
      return;
    }

    // 4. KIỂM TRA CHIP SẢN PHẨM TRONG DANH SÁCH EXPECTED HIỆN TẠI (receiptCartons / wizardSelectedEpcs)
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
          final pCode = _activePallet?.palletCode ?? _wizardDetectedPallet?.palletCode ?? 'Pallet';
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
      i.epc.trim().toUpperCase() == cleanEpc && i.status != ItemStatus.pendingInbound);
    if (isAnyKnownDbItem) {
      _filteredPassedTags[cleanEpc] = tag;
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
      SystemSound.play(SystemSoundType.alert);
      _towerLight.triggerWarningRed(
        withBuzzer: !_isBuzzerManuallySilenced,
        reason: '🚨 CẢNH BÁO NHẬP KHO: Phát hiện chip lạ ngoài đơn: $cleanEpc',
        persistent: false,
        durationSeconds: 3,
      );
    }

    if (!_securityAlertLoggedEpcs.contains(cleanEpc)) {
      _securityAlertLoggedEpcs.add(cleanEpc);
      _repo.recordTagLifecycle(
        epc: cleanEpc,
        productName: 'Chip RFID Lạ (Ngoài đơn nhập)',
        action: TagLifecycleAction.unauthorizedExit,
        newStatus: 'UNAUTHORIZED_STRANGER',
        performedBy: 'Hệ thống Cổng RFID Nhập Kho',
        device: 'Cổng RFID Desktop Hopeland',
        notes: '🚨 PHÁT HIỆN QUA CỔNG NHẬP KHO TRÁI PHÉP: Mã chip lạ không có trong đơn nhập!',
      );
    }
  }

  /// Tự động hoàn tất nhập kho và đẩy sang PDA khi đã quét đủ 100% khớp file (không cần bấm tay)
  void _checkAndTriggerAutoComplete() {
    if (_isCompletingGoodsReceive) return;
    if (_pendingGateOrders.isNotEmpty && _pendingGateOrders.every((p) => p.isGatePassed)) {
      _autoCompleteTimer?.cancel();
      _autoCompleteTimer = null;
      return;
    }
    final unexp = _getFilteredUnexpectedTags();
    if (unexp.isNotEmpty) {
      _autoCompleteTimer?.cancel();
      _autoCompleteTimer = null;
      return;
    }

    // Kiểm tra xem có xe pallet / đơn nào trong file đã quét đủ 100% chip của pallet đó không
    bool hasReadyOrder = false;
    for (final p in _pendingGateOrders) {
      if (p.isGatePassed) continue;
      final ordNo = p.order.orderNo;
      final scannedMap = _scannedTagsByOrderNo[ordNo] ?? {};
      final palletCodes = p.getPalletCodes();

      for (final palCode in palletCodes) {
        if (p.passedPalletCodes.contains(palCode)) continue;
        final palItems = p.getItemsForPallet(palCode);
        if (palItems.isEmpty) continue;

        final palScannedCount = palItems.where((i) {
          final clean = i.epc.trim().toUpperCase();
          return scannedMap.containsKey(clean) || _wizardScannedTags.containsKey(clean);
        }).length;

        if (palScannedCount >= palItems.length) {
          hasReadyOrder = true;
          break;
        }
      }
      if (hasReadyOrder) break;
    }

    // Hoặc nếu quét trực tiếp theo _activeExpectedItems hoặc CSDL (CHỈ KHI CHƯA NẠP FILE)
    if (!hasReadyOrder && _pendingGateOrders.isEmpty) {
      final unpassedDbItems = _repo.items.where((i) =>
        i.status == ItemStatus.pendingInbound &&
        !_passedGateEpcs.contains(i.epc.trim().toUpperCase())
      ).toList();

      final Map<String, List<Item>> palGroups = {};
      for (final it in unpassedDbItems) {
        final palCode = (it.palletId ?? '').trim().toUpperCase().replaceAll('PAL-', '');
        final key = palCode.isNotEmpty ? palCode : (it.orderNo ?? 'NO_PALLET');
        palGroups.putIfAbsent(key, () => []).add(it);
      }

      for (final entry in palGroups.entries) {
        final palItems = entry.value;
        if (palItems.isEmpty) continue;
        final palScannedCount = palItems.where((i) =>
          _wizardScannedTags.containsKey(i.epc.trim().toUpperCase())
        ).length;

        if (palScannedCount >= palItems.length) {
          hasReadyOrder = true;
          if (_activeExpectedItems.isEmpty) {
            _activeExpectedItems = palItems;
            _activeOrderNo ??= palItems.first.orderNo ?? 'INBOUND-AUTO';
          }
          break;
        }
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




  /// Kích hoạt chọn xe Pallet / đơn hàng đang chờ để kiểm tra hoặc xác nhận
  void _selectActivePendingOrder(String orderNo) {
    final pendingOrderObj = _pendingGateOrders.where((p) => p.order.orderNo == orderNo || p.order.inboundOrderId == orderNo).firstOrNull;
    if (pendingOrderObj == null) {
      final pItems = _repo.items.where((i) => (i.orderNo == orderNo || i.orderNo == 'INB-$orderNo') && i.status == ItemStatus.pendingInbound).toList();
      setState(() {
        _activeOrderNo = orderNo;
        _activeExpectedItems = pItems;
        final pId = pItems.firstOrNull?.palletId;
        if (pId != null) {
          _activePallet = _repo.pallets.where((p) => p.palletId.toUpperCase() == pId.toUpperCase() || p.palletCode.toUpperCase() == pId.toUpperCase()).firstOrNull;
          _wizardDetectedPallet = _activePallet;
          _wizardDetectedPalletTag = _activePallet?.rfidEpc;
          _activePalletTag = _activePallet?.rfidEpc;
        }
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

      _syncWizardScannedTagsForActiveOrder();
      _invalidateCartonCaches();
    });
  }

  /// Kích hoạt quét đối soát cho MỘT pallet cụ thể trong đơn hàng
  void _selectActivePendingPallet(String orderNo, String? palletCode) {
    if (palletCode == null || palletCode.trim().isEmpty) {
      // Không có palletCode -> fallback về chọn toàn bộ đơn (hàng lẻ không pallet)
      _selectActivePendingOrder(orderNo);
      return;
    }

    // Tìm pending order chứa pallet này
    final pendingOrderObj = _pendingGateOrders.where((p) => p.order.orderNo == orderNo || p.order.inboundOrderId == orderNo).firstOrNull;
    if (pendingOrderObj == null) {
      final cleanPal = palletCode.trim().toUpperCase().replaceAll('PAL-', '');
      final pItems = _repo.items.where((i) {
        if ((i.orderNo != orderNo && i.orderNo != 'INB-$orderNo') || i.status != ItemStatus.pendingInbound) return false;
        final itPal = (i.palletId ?? '').trim().toUpperCase().replaceAll('PAL-', '');
        return itPal == cleanPal || itPal == palletCode.trim().toUpperCase();
      }).toList();
      final pal = _repo.pallets.where((p) => p.palletCode.toUpperCase() == cleanPal || p.palletId.toUpperCase() == palletCode.toUpperCase() || p.palletId.toUpperCase() == 'PAL-$cleanPal').firstOrNull;
      setState(() {
        _activeOrderNo = orderNo;
        _activeExpectedItems = pItems.isNotEmpty
            ? pItems
            : _repo.items.where((i) => (i.orderNo == orderNo || i.orderNo == 'INB-$orderNo') && i.status == ItemStatus.pendingInbound).toList();
        _activePallet = pal;
        _activePalletTag = pal?.rfidEpc;
        _wizardDetectedPallet = pal;
        _wizardDetectedPalletTag = pal?.rfidEpc;
        _wizardSelectedCartons.clear();
        for (var it in _activeExpectedItems) {
          if (it.cartonCode != null && it.cartonCode!.isNotEmpty) {
            _wizardSelectedCartons.add(it.cartonCode!);
          }
        }
        _syncWizardScannedTagsForActiveOrder();
        _invalidateCartonCaches();
      });
      return;
    }

    // Lấy items chỉ thuộc pallet này
    final palItems = pendingOrderObj.getItemsForPallet(palletCode);
    final palEpc = pendingOrderObj.pallets[palletCode] ?? pendingOrderObj.pallets['PAL-$palletCode'];
    final pal = Pallet(
      palletId: palletCode.startsWith('PAL-') ? palletCode : 'PAL-$palletCode',
      palletCode: palletCode.replaceAll('PAL-', ''),
      rfidEpc: palEpc,
    );

    setState(() {
      _activeOrderNo = orderNo;
      _activeExpectedItems = palItems;
      _activePallet = pal;
      _activePalletTag = palEpc;
      _wizardDetectedPallet = pal;
      _wizardDetectedPalletTag = palEpc;
      _wizardSelectedCartons.clear();
      for (var it in palItems) {
        if (it.cartonCode != null && it.cartonCode!.isNotEmpty) {
          _wizardSelectedCartons.add(it.cartonCode!);
        }
      }
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
        return;
      }

      // 1. Kiểm tra danh sách các xe pallet đã quét đủ số lượng chip sản phẩm (tự động nhận từng pallet)
      final completedPalletEntries = <Map<String, dynamic>>[];

      // 1.1 Từ danh sách _pendingGateOrders (nạp từ Excel)
      for (final p in _pendingGateOrders) {
        if (p.isGatePassed) continue;
        final ordNo = p.order.orderNo;
        final scannedMap = _scannedTagsByOrderNo[ordNo] ?? {};
        final palletCodes = p.getPalletCodes();

        for (final palCode in palletCodes) {
          if (p.passedPalletCodes.contains(palCode)) continue;
          final palItems = p.getItemsForPallet(palCode);
          if (palItems.isEmpty) continue;

          final scannedEpcs = palItems.where((i) {
            final clean = i.epc.trim().toUpperCase();
            return scannedMap.containsKey(clean) || _wizardScannedTags.containsKey(clean);
          }).map((i) => i.epc.trim().toUpperCase()).toList();

          if (scannedEpcs.length >= palItems.length) {
            completedPalletEntries.add({
              'pendingOrder': p,
              'palletCode': palCode,
              'palItems': palItems,
              'scannedEpcs': scannedEpcs,
              'orderNo': ordNo,
            });
          }
        }
      }

      // 1.2 Từ CSDL nếu _pendingGateOrders rỗng: nhóm theo từng pallet riêng biệt
      if (completedPalletEntries.isEmpty && _pendingGateOrders.isEmpty) {
        final unpassedDbItems = _repo.items.where((i) =>
          i.status == ItemStatus.pendingInbound &&
          !_passedGateEpcs.contains(i.epc.trim().toUpperCase())
        ).toList();

        final Map<String, List<Item>> palGroups = {};
        for (final it in unpassedDbItems) {
          final palCode = (it.palletId ?? '').trim().toUpperCase().replaceAll('PAL-', '');
          final key = palCode.isNotEmpty ? palCode : (it.orderNo ?? 'NO_PALLET');
          palGroups.putIfAbsent(key, () => []).add(it);
        }

        for (final entry in palGroups.entries) {
          final palCode = entry.key;
          final palItems = entry.value;
          final scannedEpcs = palItems.where((i) =>
            _wizardScannedTags.containsKey(i.epc.trim().toUpperCase())
          ).map((i) => i.epc.trim().toUpperCase()).toList();

          if (scannedEpcs.length >= palItems.length) {
            final ordNo = palItems.first.orderNo ?? _activeOrderNo ?? 'INBOUND-AUTO';
            completedPalletEntries.add({
              'pendingOrder': null,
              'palletCode': palCode,
              'palItems': palItems,
              'scannedEpcs': scannedEpcs,
              'orderNo': ordNo,
            });
          }
        }
      }

      if (completedPalletEntries.isEmpty) {
        // Nếu không còn pallet nào cần xác nhận (đã hoàn tất hết), tự động thoát khỏi màn hình đối soát
        if (mounted) {
          setState(() {
            _activeOrderNo = null;
            _activePallet = null;
            _activePalletTag = null;
            _activeExpectedItems.clear();
            _wizardDetectedPallet = null;
            _wizardDetectedPalletTag = null;
            _wizardSelectedCartons.clear();
            _wizardSelectedEpcs.clear();
            _wizardScannedTags.clear();
            _invalidateCartonCaches();
          });
        }
        return;
      }

      // 2. Xử lý lưu từng pallet hoàn tất vào CSDL và chuyển trạng thái sang WAITING_PUTAWAY
      for (final entry in completedPalletEntries) {
        final pending = entry['pendingOrder'] as _PendingGateOrder?;
        final palCode = entry['palletCode'] as String;
        final palItems = entry['palItems'] as List<Item>;
        final scannedEpcs = entry['scannedEpcs'] as List<String>;
        final ordNo = entry['orderNo'] as String;
        final isNoPallet = palCode.isEmpty || palCode == ordNo || palCode == 'NO_PALLET' || palCode == 'KHONG_PALLET';

        final palObj = isNoPallet
            ? null
            : _repo.pallets.where((p) =>
                p.palletCode.toUpperCase() == palCode.toUpperCase() ||
                p.palletId.toUpperCase() == 'PAL-$palCode' ||
                p.palletId.toUpperCase() == palCode.toUpperCase()
              ).firstOrNull;

        final rfidEpc = isNoPallet
            ? null
            : (palObj?.rfidEpc ??
                _scannedPalletTagsByOrderNo[ordNo] ??
                pending?.pallets[palCode] ??
                pending?.pallets['PAL-$palCode'] ??
                (_activePallet?.palletCode == palCode ? _activePalletTag : null));

        try {
          if (pending != null && pending.products.isNotEmpty) {
            await _repo.addProductsBatch(pending.products);
          }
          if (!isNoPallet) {
            await _repo.registerOrUpdatePallet(palletCode: palCode, rfidEpc: rfidEpc ?? '');
          }
          final targetPalId = isNoPallet ? null : (palCode.startsWith('PAL-') ? palCode : 'PAL-$palCode');
          if (pending != null) {
            final alreadyInRepo = _repo.inboundOrders.any((o) =>
                o.orderNo == pending.order.orderNo || o.inboundOrderId == pending.order.inboundOrderId);
            if (!alreadyInRepo) {
              await _repo.addInboundOrder(pending.order, autoGenerateEpcs: false);
            }
            for (var it in palItems) {
              it.status = ItemStatus.waitingPutaway;
              it.palletId = targetPalId;
            }
            await _repo.insertDirectItems(palItems);
          }

          if (!isNoPallet) {
            await _repo.assignItemsToPallet(
              palletCode: palCode,
              rfidEpc: rfidEpc,
              itemEpcs: scannedEpcs,
            );
          }

          await _repo.confirmGateReceiveToWaitingPutaway(
            orderNo: ordNo,
            scannedEpcs: scannedEpcs,
            palletCode: isNoPallet ? null : palCode,
            performedBy: 'Cổng RFID Gate',
          );
          _passedGateEpcs.addAll(scannedEpcs);
          if (rfidEpc != null && rfidEpc.isNotEmpty) {
            _passedGateEpcs.add(rfidEpc.trim().toUpperCase());
          }

          _recentCompletedPasses.insert(0, {
            'orderNo': ordNo,
            'palletCode': isNoPallet ? 'Hàng lẻ (Không Pallet)' : palCode,
            'count': scannedEpcs.length,
            'total': palItems.length,
            'time': DateTime.now(),
            'status': isNoPallet ? 'CHỜ CẤT KỆ' : 'CHỜ XẾP KỆ',
            'isSuccess': true,
          });

          // Đánh dấu pallet này đã qua cổng thành công
          if (pending != null) {
            pending.passedPalletCodes.add(palCode);
            final allPalletCodes = pending.getPalletCodes();
            if (allPalletCodes.every((c) => pending.passedPalletCodes.contains(c))) {
              pending.isGatePassed = true;
              _pendingLoadedOrderNos.remove(ordNo);
            }
          }
        } catch (e) {
          debugPrint('Lỗi xác nhận pallet $palCode của đơn $ordNo: $e');
        }
      }

      final totalSaved = completedPalletEntries.fold<int>(0, (sum, e) => sum + (e['scannedEpcs'] as List<String>).length);
      final palletNames = completedPalletEntries.map((e) => e['palletCode']).toSet().join(', ');
      final orderNames = completedPalletEntries.map((e) => e['orderNo'] as String).toSet().join(', ');

      _towerLight.triggerPass(reason: 'Đã hoàn tất nhập kho và chuyển sang PDA cho Pallet $palletNames ($totalSaved chip)!');

      // Dọn buffer đầu đọc để không bị quét lặp lại chip của pallet vừa qua
      _desktopUhf.clearTags();

      // Kiểm tra xem còn đơn hoặc pallet nào chưa qua cổng không
      bool hasRemainingUnpassed = false;
      if (_pendingGateOrders.isNotEmpty) {
        hasRemainingUnpassed = _pendingGateOrders.any((p) =>
          !p.isGatePassed && p.getPalletCodes().any((c) => !p.passedPalletCodes.contains(c))
        );
      } else {
        final remainingDbItems = _repo.items.where((i) =>
          i.status == ItemStatus.pendingInbound &&
          !_passedGateEpcs.contains(i.epc.trim().toUpperCase())
        ).toList();
        hasRemainingUnpassed = remainingDbItems.isNotEmpty;
      }

      // Xóa chip của pallet vừa qua khỏi bộ đệm quét tạm nếu vẫn còn pallet khác đang chờ
      if (hasRemainingUnpassed) {
        for (final entry in completedPalletEntries) {
          final scannedEpcs = entry['scannedEpcs'] as List<String>;
          final ordNo = entry['orderNo'] as String;
          for (final epc in scannedEpcs) {
            _wizardScannedTags.remove(epc);
            _scannedTagsByOrderNo[ordNo]?.remove(epc);
          }
        }
      }

      // Chỉ dừng quét khi TẤT CẢ các đơn hàng và pallet đều đã hoàn tất
      if (!hasRemainingUnpassed) {
        await _stopWizardScan();
      }

      // Tìm pallet tiếp theo chưa qua cổng (nếu có) để tự động chuyển tiếp
      String? nextPalletCode;
      String? nextOrderNo;
      if (hasRemainingUnpassed) {
        if (_pendingGateOrders.isNotEmpty) {
          final nextPending = _pendingGateOrders.where((p) =>
            !p.isGatePassed && p.getPalletCodes().any((c) => !p.passedPalletCodes.contains(c))
          ).firstOrNull;
          if (nextPending != null) {
            nextOrderNo = nextPending.order.orderNo;
            nextPalletCode = nextPending.getPalletCodes().where((c) => !nextPending.passedPalletCodes.contains(c)).firstOrNull;
          }
        } else {
          final remainingDbItems = _repo.items.where((i) =>
            i.status == ItemStatus.pendingInbound &&
            !_passedGateEpcs.contains(i.epc.trim().toUpperCase())
          ).toList();
          if (remainingDbItems.isNotEmpty) {
            nextOrderNo = remainingDbItems.first.orderNo;
            nextPalletCode = remainingDbItems.first.palletId?.replaceAll('PAL-', '');
          }
        }
      }

      if (mounted) {
        setState(() {
          _lastSuccessOrderNo = orderNames;
          _lastSuccessPalletCode = palletNames;
          _lastSuccessCount = totalSaved;

          if (hasRemainingUnpassed && nextPalletCode != null && nextOrderNo != null) {
            // Tự động chuyển màn hình sang pallet tiếp theo đang chờ
            _selectActivePendingPallet(nextOrderNo, nextPalletCode);
          } else if (!hasRemainingUnpassed) {
            // Đã hoàn tất toàn bộ: Giữ nguyên _activeOrderNo và _activeExpectedItems trên màn hình
            // để nhân viên đối soát đầy đủ danh sách và duy trì trạng thái khoá quét ĐÃ ĐỐI SOÁT ĐỦ
            if (_activeExpectedItems.isEmpty && completedPalletEntries.isNotEmpty) {
              _activeExpectedItems = completedPalletEntries.first['palItems'] as List<Item>;
              _activeOrderNo ??= completedPalletEntries.first['orderNo'] as String?;
            }
            _wizardDetectedPallet = null;
            _wizardDetectedPalletTag = null;
            _wizardSelectedCartons.clear();
            _wizardSelectedEpcs.clear();
            _invalidateCartonCaches();
          } else {
            // Có remaining nhưng chưa rõ pallet tiếp theo: reset active pallet để chờ chip quét tự nhận diện
            _activeOrderNo = null;
            _activePallet = null;
            _activePalletTag = null;
            _activeExpectedItems.clear();
            _wizardDetectedPallet = null;
            _wizardDetectedPalletTag = null;
            _wizardSelectedCartons.clear();
            _wizardSelectedEpcs.clear();
            _invalidateCartonCaches();
          }
        });

        _successBannerTimer?.cancel();
        _successBannerTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _lastSuccessOrderNo = null;
              _lastSuccessPalletCode = null;
              _lastSuccessCount = 0;
              if (!hasRemainingUnpassed) {
                // Đã hoàn tất toàn bộ các pallet: Tự động giải phóng màn hình và quay về Cổng sẵn sàng
                _activeOrderNo = null;
                _activePallet = null;
                _activePalletTag = null;
                _activeExpectedItems.clear();
                _wizardDetectedPallet = null;
                _wizardDetectedPalletTag = null;
                _wizardSelectedCartons.clear();
                _wizardSelectedEpcs.clear();
                _wizardScannedTags.clear();
                _invalidateCartonCaches();
              }
            });
          }
        });

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF10B981),
            content: Text('✓ Pallet $palletNames ($totalSaved chip) đã qua cổng thành công! Đang chờ xếp kệ trên PDA.'),
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
      _filteredPassedTags.clear();
      _passedGateEpcs.clear();
      _lastSuccessOrderNo = null;
      _lastSuccessPalletCode = null;
      _lastSuccessCount = 0;
      _receiptCartons.clear();
      _invalidateCartonCaches();

      _activeOrderNo = null;
      _activePallet = null;
      _activePalletTag = null;
      _activeExpectedItems.clear();
      _wizardDetectedPallet = null;
      _wizardDetectedPalletTag = null;
      _wizardSelectedCartons.clear();
      _wizardSelectedEpcs.clear();
      if (_pendingGateOrders.every((p) => p.isGatePassed)) {
        _pendingGateOrders.clear();
        _pendingLoadedOrderNos.clear();
      }
    });
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
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
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
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
          duration: const Duration(seconds: 2),backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi khi đồng bộ: $e')),
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

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          duration: Duration(seconds: 2),
          content: Text('✓ Đã xóa sạch các đơn vừa nạp thành công!'),
        ),
      );
    }

    // 2. Xóa sạch CSDL và đồng bộ ngầm siêu nhanh (không chặn UI, không làm quay nút Nhập hàng, không hiện dòng xanh)
    _repo.wipeAllPendingInboundOrdersAndItems().then((_) {
      _supabaseSync.syncNow();
    }).catchError((e) {
      debugPrint('Lỗi khi xóa đơn chờ: $e');
    });
  }

  // ---------- XÓA ĐƠN HÀNG ĐƠN LẺ NẠP NHẦM KHỎI CSDL & SUPABASE ----------

  Future<void> _confirmDeleteSingleOrder(String orderNo, {int chipCount = 0}) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _eyeCare.colors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: _eyeCare.colors.border),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 22),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Xác nhận xóa đơn hàng?',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bạn có chắc chắn muốn xóa đơn hàng $orderNo?',
              style: TextStyle(color: _eyeCare.colors.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              chipCount > 0
                  ? 'Toàn bộ $chipCount chip RFID và dữ liệu của đơn này sẽ bị xóa hoàn toàn khỏi hệ thống.'
                  : 'Toàn bộ dữ liệu của đơn này sẽ bị xóa hoàn toàn khỏi hệ thống.',
              style: TextStyle(color: _eyeCare.colors.textSecondary, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('HỦY', style: TextStyle(color: _eyeCare.colors.textSecondary, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.delete_forever, size: 16),
            label: const Text('XÓA ĐƠN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // 1. Dọn dẹp RAM ngay lập tức
    _pendingGateOrders.removeWhere((p) => p.order.orderNo == orderNo || p.order.inboundOrderId == orderNo);
    _pendingLoadedOrderNos.remove(orderNo);
    _scannedTagsByOrderNo.remove(orderNo);
    _scannedPalletTagsByOrderNo.remove(orderNo);

    if (_activeOrderNo == orderNo) {
      _activeOrderNo = null;
      _activePallet = null;
      _activePalletTag = null;
      _activeExpectedItems.clear();
      _wizardScannedTags.clear();
      _stopWizardScan();
      _desktopUhf.clearTags();
    }
    _invalidateCartonCaches();

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          duration: const Duration(seconds: 2),
          content: Text('✓ Đã xóa đơn hàng $orderNo thành công!'),
        ),
      );
    }

    // 2. Xóa bộ nhớ cục bộ và Supabase Cloud
    try {
      await _repo.deleteInboundOrder(orderNo);
      await _supabaseSync.syncNow();
    } catch (e) {
      debugPrint('Lỗi khi xóa đơn $orderNo: $e');
    }
    if (mounted) setState(() {});
  }

  /// Lấy danh sách các đơn hàng chờ qua cổng để hiển thị thẻ chọn và xóa
  List<Map<String, dynamic>> _getPendingOrdersList() {
    final List<Map<String, dynamic>> result = [];

    // 1. Lấy từ danh sách đơn trong bộ nhớ tạm _pendingGateOrders (nạp từ file phiên hiện tại)
    // TÁCH TỪNG PALLET THÀNH 1 MỤC RIÊNG
    for (final p in _pendingGateOrders) {
      if (p.isGatePassed) continue;
      final ord = p.order;
      final ordNo = ord.orderNo;
      final palletCodes = p.getPalletCodes();

      for (final palCode in palletCodes) {
        if (p.passedPalletCodes.contains(palCode)) continue; // Pallet đã qua cổng -> ẩn
        final palItems = p.getItemsForPallet(palCode);
        final chipCount = palItems.length;
        if (chipCount == 0) continue;

        // Đếm SKU riêng cho pallet này
        final skuSet = palItems.map((i) => i.sku).toSet();

        result.add({
          'orderNo': ordNo,
          'palletCode': palCode,
          'supplier': p.supplier.isNotEmpty && p.supplier != 'Nhà cung cấp tổng hợp' ? p.supplier : ord.sourceSupplier,
          'status': ord.status,
          'statusLabel': 'CHỜ QUÉT CỔNG',
          'statusColor': _eyeCare.colors.rfidCyan,
          'createdAt': ord.createdAt,
          'chipCount': chipCount,
          'skuCount': skuSet.length,
          'palletInfo': palCode,
          'inboundOrder': ord,
        });
      }
    }

    // 2. Lấy từ CSDL Supabase Cloud (_repo.inboundOrders)
    final existingOrderNos = result.map((r) => r['orderNo'] as String).toSet();
    final dbPendingOrders = _repo.inboundOrders
        .where((o) => o.status == InboundOrderStatus.newOrder || o.status == InboundOrderStatus.processing)
        .toList();
    for (final ord in dbPendingOrders) {
      final ordNo = ord.orderNo;
      if (existingOrderNos.contains(ordNo)) continue;

      final items = _repo.items.where((i) =>
          (i.orderNo == ordNo || i.orderNo == ord.inboundOrderId) &&
          i.status == ItemStatus.pendingInbound).toList();

      // Nhóm theo pallet
      final palletGroups = <String, List<Item>>{};
      for (final i in items) {
        final palCode = (i.palletId ?? '').replaceAll('PAL-', '').trim();
        final key = palCode.isNotEmpty ? palCode : ordNo;
        palletGroups.putIfAbsent(key, () => []).add(i);
      }

      if (palletGroups.isEmpty) {
        // Kiểm tra xem đơn hàng này đã qua cổng thành công (các chip đã chuyển sang waitingPutaway/inbound/inStock) chưa
        final anyItemsOfOrder = _repo.items.where((i) =>
            i.orderNo == ordNo || i.orderNo == ord.inboundOrderId).toList();
        if (anyItemsOfOrder.isNotEmpty && anyItemsOfOrder.every((i) => i.status != ItemStatus.pendingInbound)) {
          // Toàn bộ chip của đơn này đã qua cổng thành công -> Không hiển thị lại ở danh sách chờ qua cổng
          continue;
        }

        // Không có items pending -> kiểm tra chi tiết đơn hàng
        final chipCount = ord.details.fold<int>(0, (s, d) => s + d.requiredQty);
        // Nếu đơn không có chip nào, không có chi tiết và không có item nào -> đơn rỗng, bỏ qua
        if (chipCount == 0 && ord.details.isEmpty && anyItemsOfOrder.isEmpty) {
          continue;
        }

        result.add({
          'orderNo': ordNo,
          'palletCode': null,
          'supplier': ord.sourceSupplier.isNotEmpty ? ord.sourceSupplier : 'Nhà cung cấp tổng hợp',
          'status': ord.status,
          'createdAt': ord.createdAt,
          'chipCount': chipCount,
          'skuCount': ord.details.length,
          'palletInfo': '--',
          'inboundOrder': ord,
        });
      } else {
        for (final entry in palletGroups.entries) {
          final skuSet = entry.value.map((i) => i.sku).toSet();
          result.add({
            'orderNo': ordNo,
            'palletCode': entry.key,
            'supplier': ord.sourceSupplier.isNotEmpty ? ord.sourceSupplier : 'Nhà cung cấp tổng hợp',
            'status': ord.status,
            'createdAt': ord.createdAt,
            'chipCount': entry.value.length,
            'skuCount': skuSet.length,
            'palletInfo': entry.key,
            'inboundOrder': ord,
          });
        }
      }
    }

    result.sort((a, b) => (b['createdAt'] as DateTime).compareTo(a['createdAt'] as DateTime));
    return result;
  }

  // ---------- GIAO DIỆN DANH SÁCH ĐƠN HÀNG CHỜ NHẬP & NÚT XÓA ĐƠN ----------

  Widget _buildPendingOrdersListView(EyeCareColors c, List<Map<String, dynamic>> pendingOrders) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header danh sách đơn
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: c.bgCardElevated,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_wizardIsScanning ? const Color(0xFF10B981) : c.rfidCyan).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _wizardIsScanning ? Icons.sensors : Icons.assignment_outlined,
                  color: _wizardIsScanning ? const Color(0xFF10B981) : c.rfidCyan,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DANH SÁCH PALLET CHỜ QUA CỔNG (${pendingOrders.length} PALLET)',
                      style: TextStyle(
                        color: _wizardIsScanning ? const Color(0xFF10B981) : c.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _wizardIsScanning
                          ? 'ĐẦU ĐỌC RFID ĐANG QUÉT: Pallet nào đẩy qua cổng trước, hệ thống sẽ tự động chọn và đối soát pallet đó.'
                          : 'Hệ thống đang sẵn sàng tiếp nhận. Đẩy pallet qua cổng để hệ thống tự động nhận diện và đối soát.',
                      style: TextStyle(
                        color: _wizardIsScanning ? const Color(0xFF10B981) : c.textSecondary,
                        fontSize: 12,
                        fontWeight: _wizardIsScanning ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Danh sách thẻ đơn hàng
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            itemCount: pendingOrders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final ordData = pendingOrders[index];
              final ordNo = ordData['orderNo'] as String;
              final palletCode = ordData['palletCode'] as String?;
              final supplier = ordData['supplier'] as String;
              final chipCount = ordData['chipCount'] as int;
              final skuCount = ordData['skuCount'] as int;
              final palletInfo = ordData['palletInfo'] as String;
              final createdAt = ordData['createdAt'] as DateTime;
              final timeStr = '${createdAt.hour.toString().padLeft(2, '0')}:${createdAt.minute.toString().padLeft(2, '0')} ${createdAt.day.toString().padLeft(2, '0')}/${createdAt.month.toString().padLeft(2, '0')}/${createdAt.year}';

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hàng 1: Mã đơn, Trạng thái, Thời gian
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.inventory_2, color: Color(0xFFF59E0B), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                palletCode != null ? 'Pallet: $palletCode' : ordNo,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$ordNo  •  NCC: $supplier',
                                style: TextStyle(color: c.textSecondary, fontSize: 12.5),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: ((ordData['statusColor'] as Color?) ?? c.rfidCyan).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: ((ordData['statusColor'] as Color?) ?? c.rfidCyan).withValues(alpha: 0.5)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: (ordData['statusColor'] as Color?) ?? c.rfidCyan,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                (ordData['statusLabel'] as String?) ?? 'CHỜ QUÉT CỔNG',
                                style: TextStyle(
                                  color: (ordData['statusColor'] as Color?) ?? c.rfidCyan,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),
                    Divider(color: c.border.withValues(alpha: 0.5), height: 1),
                    const SizedBox(height: 12),

                    // Hàng 2: Các thông số chi tiết (Chip count, SKU, Pallet, Thời gian)
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      children: [
                        _buildOrderStatChip(
                          icon: Icons.sell_outlined,
                          label: 'Số Chip RFID',
                          value: '$chipCount chip',
                          color: const Color(0xFF10B981),
                          c: c,
                        ),
                        _buildOrderStatChip(
                          icon: Icons.category_outlined,
                          label: 'Số SKU',
                          value: '$skuCount SKU',
                          color: const Color(0xFF0284C7),
                          c: c,
                        ),
                        _buildOrderStatChip(
                          icon: Icons.inventory_2_outlined,
                          label: 'Pallet',
                          value: palletInfo.isNotEmpty ? palletInfo : '--',
                          color: const Color(0xFFF59E0B),
                          c: c,
                        ),
                        _buildOrderStatChip(
                          icon: Icons.access_time,
                          label: 'Thời Gian Tạo',
                          value: timeStr,
                          color: c.textSecondary,
                          c: c,
                        ),
                      ],
                    ),

                    const SizedBox(height: 14),

                    // Hàng 3: Nút Thao Tác (Xóa Đơn & Chọn Đối Soát)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        // Nút Xóa Đơn (Màu đỏ nổi bật)
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.6)),
                            backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.08),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.delete_outline, size: 16, color: Color(0xFFEF4444)),
                          label: const Text(
                            'XÓA ĐƠN',
                            style: TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          onPressed: () => _confirmDeleteSingleOrder(ordNo, chipCount: chipCount),
                        ),
                        const SizedBox(width: 12),

                        // Nút Chọn Đối Soát (Màu Cyan)
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.rfidCyan,
                            foregroundColor: const Color(0xFFFFFFFF),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 1,
                          ),
                          icon: const Icon(Icons.sensors, size: 16, color: Color(0xFFFFFFFF)),
                          label: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'CHỌN ĐỐI SOÁT',
                                style: TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                              SizedBox(width: 6),
                              Icon(Icons.arrow_forward, size: 14, color: Color(0xFFFFFFFF)),
                            ],
                          ),
                          onPressed: () => _selectActivePendingPallet(ordNo, palletCode),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOrderStatChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required EyeCareColors c,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: TextStyle(color: c.textSecondary, fontSize: 11),
          ),
          Text(
            value,
            style: TextStyle(color: c.textPrimary, fontSize: 11.5, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerClearAllPendingDialog() async {
    final Map<String, List<Item>> pendingOrdersMap = {};
    for (var pOrder in _pendingGateOrders) {
      pendingOrdersMap[pOrder.order.orderNo] = pOrder.items;
    }
    final validInboundOrders = _repo.inboundOrders.where((o) => o.status == InboundOrderStatus.newOrder || o.status == InboundOrderStatus.processing).toList();
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
        final matchingOrder = _repo.inboundOrders.where((o) => (o.orderNo == ordNo || o.inboundOrderId == ordNo) && (o.status == InboundOrderStatus.newOrder || o.status == InboundOrderStatus.processing)).firstOrNull;
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
        if (rawCode.isEmpty) {
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
            final sSerialNumber = (sItem['serialNumber'] ?? sSerial).toString().trim();
            explicitItems.add(Item(
              itemId: 'ITEM-${now.millisecondsSinceEpoch}-$itemSeq',
              productId: sBarcode,
              sku: sBarcode,
              productName: sName,
              serialNumber: sSerialNumber.isNotEmpty ? sSerialNumber : sSerial,
              epc: sSerial,
              status: ItemStatus.pendingInbound,
              orderNo: inboundOrderNo,
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
          final assignedOrderNo = inboundOrderNo;
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
        final cleanProdName = _repo.getSkuProductName(item.sku, item.productName);
        if (detailMap.containsKey(item.sku)) {
          final old = detailMap[item.sku]!;
          detailMap[item.sku] = InboundOrderDetail(
            productId: item.productId,
            sku: item.sku,
            productName: cleanProdName,
            requiredQty: old.requiredQty + 1,
          );
        } else {
          detailMap[item.sku] = InboundOrderDetail(
            productId: item.productId,
            sku: item.sku,
            productName: cleanProdName,
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
            productName: _repo.getSkuProductName(item.sku, item.productName),
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

        final thisOrderPallets = <String, String?>{...resolvedPalletsToRegister};

        // Lưu ngay đơn hàng và danh sách chip vào CSDL & đồng bộ lên Supabase Cloud
        if (newProducts.isNotEmpty) {
          await _repo.addProductsBatch(newProducts);
        }
        for (final palEntry in thisOrderPallets.entries) {
          await _repo.registerOrUpdatePallet(palletCode: palEntry.key, rfidEpc: palEntry.value ?? '');
        }
        await _repo.addInboundOrder(order, autoGenerateEpcs: false);
        await _repo.insertDirectItems(orderItems);

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
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
          duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF10B981),
            content: Text('✓ Đã nạp ${explicitItems.length} chip cho đơn $inboundOrderNo thành công!'),
          ),
        );
      }

      // Giữ ở màn hình danh sách đơn hàng kèm nút [XÓA ĐƠN] và [CHỌN ĐỐI SOÁT]
      _activeOrderNo = null;
      _activeExpectedItems.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi nạp file Excel: $e')),
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
          final prodName = _repo.getSkuProductName(sku, (r['productName'] ?? 'Sản phẩm PO').toString().trim());
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
            productName: _repo.getSkuProductName(item.sku, item.productName),
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

        // Lưu ngay đơn hàng PO và danh sách chip vào CSDL & đồng bộ lên Supabase Cloud
        if (newProducts.isNotEmpty) {
          await _repo.addProductsBatch(newProducts);
        }
        await _repo.addInboundOrder(order, autoGenerateEpcs: false);
        await _repo.insertDirectItems(poItems);

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
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
          duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF10B981),
            content: Text('✓ Đã nạp đơn PO và lưu ${explicitItems.length} chip thành công!'),
          ),
        );
      }

      // Giữ ở màn hình danh sách đơn hàng kèm nút [XÓA ĐƠN] và [CHỌN ĐỐI SOÁT]
      _activeOrderNo = null;
      _activeExpectedItems.clear();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi nạp file PO: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  // ---------- KỊCH BẢN DEMO: TẠO PHIẾU NHẬP & TỰ SINH MÃ RFID (TỦ RACK & HỘP SẮT) ----------

  Future<void> _showCreateDemoInboundDialog() async {
    final c = _eyeCare.colors;
    final defaultOrderNo = 'NK-DEMO-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
    final orderNoController = TextEditingController(text: defaultOrderNo);
    final supplierController = TextEditingController(text: 'Công ty Cổ phần Thiết Bị Công Nghệ Nhật Minh');
    final palletController = TextEditingController(text: 'PL01');

    bool includeRack = true;
    int rackQty = 3; // 1 to 3
    bool includeBox = true;
    int boxQty = 10; // 1 to 10
    bool enterGateImmediately = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final totalQty = (includeRack ? rackQty : 0) + (includeBox ? boxQty : 0);

            return Dialog(
              backgroundColor: c.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.border),
              ),
              insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 840, maxHeight: 820),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 1. Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: c.bgCardElevated,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        border: Border(bottom: BorderSide(color: c.border)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.playlist_add_check_circle, color: Color(0xFF0284C7), size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'TẠO PHIẾU NHẬP LẺ',
                                  style: TextStyle(
                                    color: c.textPrimary,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    letterSpacing: 0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Tạo đơn nhập lẻ và gán mã RFID theo số lượng tài sản • Sẵn sàng nạp vào cổng đối soát',
                                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: Icon(Icons.close, color: c.textSecondary, size: 20),
                            tooltip: 'Đóng',
                          ),
                        ],
                      ),
                    ),

                    // 2. Nội dung cuộn
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Hàng cấu hình thông tin chung của đơn hàng
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: c.bgCardElevated,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: c.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                children: [
                                  // Mã đơn nhập
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: orderNoController,
                                      style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        labelText: 'Mã phiếu nhập',
                                        labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                                        prefixIcon: const Icon(Icons.receipt_long, size: 18),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Nhà cung cấp
                                  Expanded(
                                    flex: 4,
                                    child: TextField(
                                      controller: supplierController,
                                      style: TextStyle(color: c.textPrimary, fontSize: 13),
                                      decoration: InputDecoration(
                                        labelText: 'Nhà cung cấp',
                                        labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                                        prefixIcon: const Icon(Icons.business, size: 18),
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  // Pallet đích (cho phép để trống đối với đơn hàng lẻ không dùng pallet)
                                  Expanded(
                                    flex: 3,
                                    child: TextField(
                                      controller: palletController,
                                      onChanged: (_) => setDialogState(() {}),
                                      style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                      decoration: InputDecoration(
                                        labelText: 'Mã Pallet',
                                        hintText: 'Để trống nếu là hàng lẻ',
                                        hintStyle: TextStyle(color: c.textSecondary.withValues(alpha: 0.6), fontSize: 11),
                                        labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                                        prefixIcon: Icon(
                                          palletController.text.trim().isEmpty ? Icons.layers_clear_outlined : Icons.grid_view_rounded,
                                          size: 18,
                                          color: palletController.text.trim().isEmpty ? const Color(0xFFF59E0B) : const Color(0xFF0284C7),
                                        ),
                                        suffixIcon: palletController.text.trim().isNotEmpty
                                            ? IconButton(
                                                icon: const Icon(Icons.clear, size: 16),
                                                tooltip: 'Xóa pallet (đổi sang hàng lẻ rời)',
                                                onPressed: () {
                                                  palletController.clear();
                                                  setDialogState(() {});
                                                },
                                              )
                                            : null,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              // Thanh hiển thị trực quan trạng thái Pallet vs Hàng lẻ
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  if (palletController.text.trim().isEmpty) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3B82F6).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.inventory_2_outlined, size: 14, color: Color(0xFF3B82F6)),
                                          SizedBox(width: 5),
                                          Text(
                                            '📦 Đơn hàng lẻ xếp rời • Không gắn Pallet (pallet_id = NULL)',
                                            style: TextStyle(color: Color(0xFF3B82F6), fontSize: 11.5, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      ),
                                      icon: const Icon(Icons.add_circle_outline, size: 14, color: Color(0xFF0284C7)),
                                      label: const Text('Gán xe Pallet (PL01)', style: TextStyle(fontSize: 11.5, color: Color(0xFF0284C7))),
                                      onPressed: () {
                                        palletController.text = 'PL01';
                                        setDialogState(() {});
                                      },
                                    ),
                                  ] else ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.grid_view_rounded, size: 14, color: Color(0xFF10B981)),
                                          const SizedBox(width: 5),
                                          Text(
                                            '🏷️ Đóng theo xe Pallet: ${palletController.text.trim().toUpperCase()}',
                                            style: const TextStyle(color: Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const Spacer(),
                                    TextButton.icon(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                      ),
                                      icon: const Icon(Icons.layers_clear_outlined, size: 14, color: Color(0xFFF59E0B)),
                                      label: const Text('Bỏ Pallet (Hàng lẻ rời)', style: TextStyle(fontSize: 11.5, color: Color(0xFFF59E0B))),
                                      onPressed: () {
                                        palletController.clear();
                                        setDialogState(() {});
                                      },
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        ),

                            const SizedBox(height: 16),
                            Text(
                              'CHỌN TÀI SẢN & SỐ LƯỢNG NHẬP (TỰ ĐỘNG KHỚP EPC CỐ ĐỊNH)',
                              style: TextStyle(
                                color: c.rfidCyan,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 10),

                            // CARD 1: Thiết bị tủ rack 1-3
                            _buildAssetConfigCard(
                              c: c,
                              title: 'Thiết bị tủ rack',
                              subtitle: 'SKU: RACK-SRV-01 • Nhóm: Linh kiện tủ server (1-3 bộ)',
                              tagGroupDesc: '🏷️ Nhóm dán thẻ: Dán thẻ RFID On-Metal chống kim loại lên bề mặt kim loại / linh kiện tủ server',
                              icon: Icons.dns_rounded,
                              iconColor: const Color(0xFFF59E0B),
                              isEnabled: includeRack,
                              onToggleEnabled: (v) => setDialogState(() => includeRack = v),
                              currentQty: rackQty,
                              minQty: 1,
                              maxQty: InboundDemoScenarioService.rackUnit.fixedEpcs.length,
                              unit: 'Bộ',
                              epcList: InboundDemoScenarioService.rackUnit.fixedEpcs,
                              onQtyChanged: (q) => setDialogState(() => rackQty = q),
                            ),

                            const SizedBox(height: 12),

                            // CARD 2: Hộp sắt đựng chứng từ 1-10
                            _buildAssetConfigCard(
                              c: c,
                              title: 'Hộp sắt đựng chứng từ',
                              subtitle: 'SKU: BOX-MET-01 • Nhóm: Hộp kim loại, gáy hồ sơ chứng từ (1-10 hộp)',
                              tagGroupDesc: '🏷️ Nhóm dán thẻ: Dán thẻ RFID On-Metal chống kim loại lên hộp kim loại hoặc gáy hồ sơ chứng từ',
                              icon: Icons.inventory_2_rounded,
                              iconColor: const Color(0xFF8B5CF6),
                              isEnabled: includeBox,
                              onToggleEnabled: (v) => setDialogState(() => includeBox = v),
                              currentQty: boxQty,
                              minQty: 1,
                              maxQty: InboundDemoScenarioService.metalBox.fixedEpcs.length,
                              unit: 'Hộp',
                              epcList: InboundDemoScenarioService.metalBox.fixedEpcs,
                              onQtyChanged: (q) => setDialogState(() => boxQty = q),
                            ),

                            const SizedBox(height: 14),

                            // Option check: Vào thẳng đối soát tại cổng ngay
                            InkWell(
                              onTap: () => setDialogState(() => enterGateImmediately = !enterGateImmediately),
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                                child: Row(
                                  children: [
                                    Checkbox(
                                      value: enterGateImmediately,
                                      activeColor: const Color(0xFF0284C7),
                                      onChanged: (v) => setDialogState(() => enterGateImmediately = v ?? true),
                                    ),
                                    Expanded(
                                      child: Text(
                                        'Kích hoạt và chuyển ngay vào màn hình cổng quét đối soát sau khi tạo',
                                        style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w500),
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

                    // 3. Footer Actions
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      decoration: BoxDecoration(
                        color: c.bgCardElevated,
                        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                        border: Border(top: BorderSide(color: c.border)),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          // Thống kê tổng số lượng
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 16),
                                const SizedBox(width: 6),
                                Text(
                                  'Tổng: $totalQty thẻ RFID (${(includeRack ? rackQty : 0)} Tủ rack + ${(includeBox ? boxQty : 0)} Hộp sắt)',
                                  style: const TextStyle(
                                    color: Color(0xFF10B981),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Nút In & Mã hóa tem RFID
                              OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: c.textPrimary,
                                  side: BorderSide(color: c.border),
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: const Icon(Icons.qr_code_2, size: 18),
                                label: const Text('IN & MÃ HÓA TEM RFID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                onPressed: totalQty == 0 ? null : () {
                                  final pkg = InboundDemoScenarioService.buildDemoPackage(
                                    orderNo: orderNoController.text.trim().isEmpty ? defaultOrderNo : orderNoController.text.trim(),
                                    supplier: supplierController.text.trim(),
                                    palletCode: palletController.text.trim(),
                                    rackQty: includeRack ? rackQty : 0,
                                    boxQty: includeBox ? boxQty : 0,
                                  );
                                  _showPrintAndEncodeTagsDialog(dialogContext, pkg);
                                },
                              ),
                              const SizedBox(width: 10),

                              TextButton(
                                onPressed: () => Navigator.pop(dialogContext),
                                child: Text('HỦY', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 10),

                              // Nút Tạo & Nạp vào cổng
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0284C7),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                  elevation: 2,
                                ),
                                icon: const Icon(Icons.playlist_add_check, size: 18, color: Colors.white),
                                label: const Text(
                                  'TẠO & NẠP VÀO CỔNG',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12.5,
                                  ),
                                ),
                                onPressed: totalQty == 0 ? null : () async {
                                  final ordNo = orderNoController.text.trim().isEmpty ? defaultOrderNo : orderNoController.text.trim().toUpperCase();
                                  final supp = supplierController.text.trim();
                                  final palCode = palletController.text.trim().toUpperCase();

                                  final pkg = InboundDemoScenarioService.buildDemoPackage(
                                    orderNo: ordNo,
                                    supplier: supp,
                                    palletCode: palCode,
                                    rackQty: includeRack ? rackQty : 0,
                                    boxQty: includeBox ? boxQty : 0,
                                  );

                                  Navigator.pop(dialogContext);

                                  await _applyDemoInboundPackage(pkg, enterGateImmediately: enterGateImmediately);
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _applyDemoInboundPackage(DemoInboundPackage pkg, {bool enterGateImmediately = true}) async {
    setState(() => _isImporting = true);
    try {
      // 1. Lưu vào WarehouseRepository, SQLite và Supabase
      await InboundDemoScenarioService.saveDemoPackageToRepository(_repo, pkg);

      // 2. Thêm vào hàng đợi _pendingGateOrders
      _pendingGateOrders.removeWhere((p) => p.order.orderNo == pkg.order.orderNo || p.order.inboundOrderId == pkg.order.inboundOrderId);
      _pendingLoadedOrderNos.removeWhere((no) => no == pkg.order.orderNo);

      final hasPallet = pkg.palletCode.isNotEmpty;
      _pendingGateOrders.add(_PendingGateOrder(
        order: pkg.order,
        items: pkg.items,
        products: pkg.products,
        pallets: hasPallet ? {pkg.palletCode: null} : {},
        supplier: pkg.supplier,
        fileName: hasPallet
            ? 'Phiếu Nhập Lẻ (Pallet ${pkg.palletCode})'
            : 'Phiếu Nhập Lẻ (Hàng lẻ không Pallet)',
      ));
      _pendingLoadedOrderNos.add(pkg.order.orderNo);

      if (mounted) {
        if (enterGateImmediately) {
          _selectActivePendingPallet(pkg.order.orderNo, pkg.palletCode);
        } else {
          _activeOrderNo = null;
          _activeExpectedItems.clear();
          setState(() {});
        }

        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFF10B981),
            content: Text(hasPallet
                ? '✓ Đã tạo phiếu nhập lẻ ${pkg.order.orderNo} (Pallet ${pkg.palletCode}) gồm ${pkg.items.length} thẻ RFID sẵn sàng qua cổng!'
                : '✓ Đã tạo phiếu nhập lẻ ${pkg.order.orderNo} (Hàng lẻ không Pallet) gồm ${pkg.items.length} thẻ RFID sẵn sàng qua cổng!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 3),
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Lỗi tạo phiếu nhập lẻ: $e'),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Widget _buildAssetConfigCard({
    required EyeCareColors c,
    required String title,
    required String subtitle,
    required String tagGroupDesc,
    required IconData icon,
    required Color iconColor,
    required bool isEnabled,
    required ValueChanged<bool> onToggleEnabled,
    required int currentQty,
    required int minQty,
    required int maxQty,
    required String unit,
    required List<String> epcList,
    required ValueChanged<int> onQtyChanged,
  }) {
    final activeEpcs = epcList.take(currentQty).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isEnabled ? c.bgCardElevated : c.bgCard.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEnabled ? iconColor.withValues(alpha: 0.4) : c.border,
          width: isEnabled ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: isEnabled ? c.textPrimary : c.textSecondary,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                activeThumbColor: iconColor,
                onChanged: onToggleEnabled,
              ),
            ],
          ),

          if (isEnabled) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: iconColor.withValues(alpha: 0.2)),
              ),
              child: Text(
                tagGroupDesc,
                style: TextStyle(
                  color: isEnabled ? c.textPrimary : c.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 12),

            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Số lượng nhập ($unit):',
                      style: TextStyle(color: c.textSecondary, fontSize: 12.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      color: currentQty > minQty ? c.rfidCyan : c.textSecondary.withValues(alpha: 0.4),
                      onPressed: currentQty > minQty ? () => onQtyChanged(currentQty - 1) : null,
                      tooltip: 'Giảm 1',
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.bgCard,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.border),
                      ),
                      child: Text(
                        '$currentQty / $maxQty $unit',
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      color: currentQty < maxQty ? c.rfidCyan : c.textSecondary.withValues(alpha: 0.4),
                      onPressed: currentQty < maxQty ? () => onQtyChanged(currentQty + 1) : null,
                      tooltip: 'Tăng 1',
                    ),
                  ],
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      onPressed: () => onQtyChanged(minQty),
                      child: Text('Tối thiểu ($minQty)', style: TextStyle(fontSize: 11, color: c.textSecondary)),
                    ),
                    TextButton(
                      onPressed: () => onQtyChanged(maxQty),
                      child: Text('Tối đa ($maxQty)', style: TextStyle(fontSize: 11, color: iconColor, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (int i = 0; i < activeEpcs.length; i++)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: iconColor.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '#${i + 1}',
                          style: TextStyle(color: iconColor, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 5),
                        Text(
                          activeEpcs[i],
                          style: TextStyle(
                            color: c.textPrimary,
                            fontFamily: 'monospace',
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _showPrintAndEncodeTagsDialog(BuildContext parentContext, DemoInboundPackage pkg) async {
    final c = _eyeCare.colors;

    await showDialog<void>(
      context: parentContext,
      builder: (dialogCtx) => Dialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.border),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 860, maxHeight: 800),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.qr_code_2, color: Color(0xFF10B981), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'IN & MÃ HÓA TEM RFID THEO DANH SÁCH',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              letterSpacing: 0.3,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Phiếu: ${pkg.order.orderNo} • Tổng số tem: ${pkg.items.length} • Dán theo từng nhóm sản phẩm',
                            style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      icon: Icon(Icons.close, color: c.textSecondary, size: 20),
                    ),
                  ],
                ),
              ),

              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: pkg.items.length,
                  separatorBuilder: (ctx, i) => const SizedBox(height: 10),
                  itemBuilder: (ctx, index) {
                    final item = pkg.items[index];
                    final isRack = item.sku == InboundDemoScenarioService.rackUnit.sku;
                    final badgeColor = isRack ? const Color(0xFFF59E0B) : const Color(0xFF8B5CF6);
                    final tagNote = isRack
                        ? '🏷️ Nhóm: Linh kiện tủ server (Thẻ On-Metal chống kim loại)'
                        : '🏷️ Nhóm: Hộp kim loại, gáy hồ sơ chứng từ (Thẻ On-Metal chống kim loại)';

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: c.bgCardElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '#${index + 1}',
                              style: TextStyle(color: badgeColor, fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                          ),
                          const SizedBox(width: 14),

                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'SKU: ${item.sku} • Serial: ${item.serialNumber}',
                                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                                ),
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: badgeColor.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                                  ),
                                  child: Text(
                                    tagNote,
                                    style: TextStyle(color: badgeColor, fontSize: 10.5, fontWeight: FontWeight.w600),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),

                          Expanded(
                            flex: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: c.bgCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: c.border),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.nfc, size: 16, color: Color(0xFF0284C7)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      item.epc,
                                      style: TextStyle(
                                        color: c.textPrimary,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy, size: 16),
                                    color: c.textSecondary,
                                    tooltip: 'Sao chép mã EPC',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    onPressed: () {
                                      Clipboard.setData(ClipboardData(text: item.epc));
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          duration: const Duration(seconds: 1),
                                          backgroundColor: const Color(0xFF10B981),
                                          content: Text('Đã sao chép: ${item.epc}'),
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.textPrimary,
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.copy_all, size: 18),
                      label: const Text('SAO CHÉP TẤT CẢ EPC', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      onPressed: () {
                        final allEpcs = pkg.items.map((i) => i.epc).join('\n');
                        Clipboard.setData(ClipboardData(text: allEpcs));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 2),
                            backgroundColor: const Color(0xFF10B981),
                            content: Text('✓ Đã sao chép toàn bộ ${pkg.items.length} mã EPC vào Clipboard!'),
                          ),
                        );
                      },
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.print, size: 18, color: Colors.white),
                      label: const Text(
                        'IN TEM RA MÁY IN RFID',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            duration: const Duration(seconds: 3),
                            backgroundColor: const Color(0xFF10B981),
                            content: Text('🖨️ Đã gửi lệnh in và mã hóa ${pkg.items.length} tem RFID tới máy in công nghiệp!'),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 10),
                    TextButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      child: Text('ĐÓNG', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- THANH TRẠNG THÁI & CẢNH BÁO ĐÈN THÁP NHẬP KHO (TOWER LIGHT) ----------

  void _silenceBuzzer() {
    setState(() {
      _isBuzzerManuallySilenced = true;
    });
    _towerLight.silenceBuzzerOnly();
  }

  void _restoreBuzzer() {
    setState(() {
      _isBuzzerManuallySilenced = false;
    });
    if (_towerLight.currentStatus.color == TowerLightColor.red) {
      _towerLight.triggerWarningRed(withBuzzer: true, reason: _towerLight.currentStatus.reason, persistent: false, durationSeconds: 3);
    }
  }

  Widget _buildTowerLightBadge(EyeCareColors c) {
    final status = _towerLight.currentStatus;
    final isConnected = _desktopUhf.isConnected;
    final Color badgeColor = switch (status.color) {
      TowerLightColor.red => const Color(0xFFEF4444),
      TowerLightColor.yellow => const Color(0xFFF59E0B),
      TowerLightColor.green => const Color(0xFF10B981),
      TowerLightColor.off => isConnected ? const Color(0xFF10B981) : c.textMuted,
    };
    final String label = switch (status.color) {
      TowerLightColor.red => 'ĐÈN ĐỎ (CẢNH BÁO)',
      TowerLightColor.yellow => 'ĐÈN VÀNG (ĐANG QUÉT)',
      TowerLightColor.green => 'ĐÈN XANH (THÔNG QUA)',
      TowerLightColor.off => isConnected ? 'SẴN SÀNG (GPO 1-4)' : 'CHƯA KẾT NỐI',
    };

    return PopupMenuButton<String>(
      tooltip: 'Trạng thái & Thử nghiệm Tháp Đèn Tín Hiệu Nhập Kho (Bấm để thử đèn & cài đặt GPO)',
      onSelected: (val) {
        if (val == 'test_red') {
          _towerLight.triggerWarningRed(withBuzzer: true, reason: 'Thử nghiệm thủ công: Đèn Đỏ + Còi Hú');
        } else if (val == 'test_yellow') {
          _towerLight.triggerScanning(reason: 'Thử nghiệm thủ công: Đèn Vàng');
        } else if (val == 'test_green') {
          _towerLight.triggerPass(reason: 'Thử nghiệm thủ công: Đèn Xanh');
        } else if (val == 'turn_off') {
          _towerLight.turnOffAll(reason: 'Tắt đèn về Standby');
        } else if (val == 'config_gpo') {
          _showTowerLightGpoDialog(c);
        }
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            'THÁP ĐÈN CTP50-3T-D-J (${isConnected ? "ĐÃ NỐI GPO" : "CHƯA NỐI ĐẦU ĐỌC"})',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.textSecondary),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'test_red',
          child: Row(
            children: [
              Icon(Icons.circle, color: Color(0xFFEF4444), size: 14),
              SizedBox(width: 8),
              Text('Thử Đèn Đỏ + Còi Báo Động (Cảnh báo)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFEF4444))),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'test_yellow',
          child: Row(
            children: [
              Icon(Icons.circle, color: Color(0xFFF59E0B), size: 14),
              SizedBox(width: 8),
              Text('Thử Đèn Vàng (Đang Quét Đối Soát)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'test_green',
          child: Row(
            children: [
              Icon(Icons.circle, color: Color(0xFF10B981), size: 14),
              SizedBox(width: 8),
              Text('Thử Đèn Xanh (Đủ Hàng Thông Qua)', style: TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'turn_off',
          child: Row(
            children: [
              Icon(Icons.power_settings_new, color: Colors.grey, size: 14),
              SizedBox(width: 8),
              Text('Tắt tháp đèn (Standby)', style: TextStyle(fontSize: 12)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'config_gpo',
          child: Row(
            children: [
              Icon(Icons.settings, color: c.rfidCyan, size: 14),
              const SizedBox(width: 8),
              Text('Cài đặt & Test chân GPO 1-4...', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: c.bgCardElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: badgeColor,
                boxShadow: [
                  BoxShadow(color: badgeColor.withValues(alpha: 0.6), blurRadius: 4, spreadRadius: 1),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'THÁP ĐÈN: $label',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: badgeColor,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 14, color: badgeColor),
          ],
        ),
      ),
    );
  }

  Widget _buildTowerLightAlertBar(EyeCareColors c) {
    final status = _towerLight.currentStatus;
    final (barColor, borderColor, statusTitle, statusIcon) = switch (status.color) {
      TowerLightColor.red => (
        const Color(0xFFEF4444),
        const Color(0xFFEF4444),
        'ĐÈN ĐỎ: CẢNH BÁO NHẬP KHO (CHIP LẠ / SAI ĐƠN)',
        Icons.warning_rounded,
      ),
      TowerLightColor.yellow => (
        const Color(0xFFF59E0B),
        const Color(0xFFF59E0B),
        'ĐÈN VÀNG: ĐANG QUÉT ĐỐI SOÁT CỔNG NHẬP',
        Icons.hourglass_top_rounded,
      ),
      TowerLightColor.green => (
        const Color(0xFF10B981),
        const Color(0xFF10B981),
        'ĐÈN XANH: THÔNG QUA CỔNG NHẬP KHO',
        Icons.check_circle_rounded,
      ),
      TowerLightColor.off => (
        c.textMuted,
        c.border,
        'ĐÈN CHỜ (STANDBY)',
        Icons.lightbulb_outline_rounded,
      ),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: status.isOff ? c.bgCard : barColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: status.isOff ? c.border : borderColor.withValues(alpha: 0.8),
          width: status.isOff ? 1 : 1.5,
        ),
      ),
      child: Row(
        children: [
          // Mô phỏng 3 bóng đèn LED (Đỏ - Vàng - Xanh)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: c.bgDeep,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: c.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildLedBulb(
                  color: const Color(0xFFEF4444),
                  isActive: status.color == TowerLightColor.red,
                  isBuzzer: status.isBuzzerOn,
                ),
                const SizedBox(width: 6),
                _buildLedBulb(
                  color: const Color(0xFFF59E0B),
                  isActive: status.color == TowerLightColor.yellow,
                ),
                const SizedBox(width: 6),
                _buildLedBulb(
                  color: const Color(0xFF10B981),
                  isActive: status.color == TowerLightColor.green,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Icon + Tiêu đề + Lý do cảnh báo
          Icon(statusIcon, color: barColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      statusTitle,
                      style: TextStyle(
                        color: barColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (status.isBuzzerOn) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.volume_up_rounded, color: Colors.white, size: 10),
                            SizedBox(width: 2),
                            Text('CÒI BÁO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  status.reason,
                  style: TextStyle(
                    color: status.isOff ? c.textSecondary : c.textPrimary,
                    fontSize: 11.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),

          // Nút tắt còi báo động khi đang báo động
          if (status.isBuzzerOn || _isBuzzerManuallySilenced) ...[
            TextButton.icon(
              style: TextButton.styleFrom(
                foregroundColor: _isBuzzerManuallySilenced ? c.textSecondary : const Color(0xFFEF4444),
                backgroundColor: _isBuzzerManuallySilenced ? c.bgDeep : const Color(0xFFEF4444).withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: Icon(_isBuzzerManuallySilenced ? Icons.volume_off : Icons.volume_up, size: 14),
              label: Text(
                _isBuzzerManuallySilenced ? 'BẬT LẠI CÒI' : 'TẮT CÒI',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
              ),
              onPressed: _isBuzzerManuallySilenced ? _restoreBuzzer : _silenceBuzzer,
            ),
            const SizedBox(width: 8),
          ],

          // Menu thử đèn thủ công (Manual Test Controls)
          PopupMenuButton<String>(
            tooltip: 'Thử nghiệm tín hiệu đèn tháp',
            onSelected: (val) {
              if (val == 'test_green') {
                _towerLight.triggerPass(reason: 'Kiểm tra thủ công: Đèn Xanh thông qua');
              } else if (val == 'test_yellow') {
                _towerLight.triggerScanning(reason: 'Kiểm tra thủ công: Đèn Vàng đang quét');
              } else if (val == 'test_red') {
                _towerLight.triggerWarningRed(withBuzzer: true, reason: 'Kiểm tra thủ công: Đèn Đỏ + Còi báo động');
              } else if (val == 'turn_off') {
                _towerLight.turnOffAll();
              } else if (val == 'config_gpo') {
                _showTowerLightGpoDialog(c);
              }
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'test_green',
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Color(0xFF10B981), size: 14),
                    SizedBox(width: 8),
                    Text('Thử Đèn Xanh (Thông qua)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'test_yellow',
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Color(0xFFF59E0B), size: 14),
                    SizedBox(width: 8),
                    Text('Thử Đèn Vàng (Đang quét)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'test_red',
                child: Row(
                  children: [
                    Icon(Icons.circle, color: Color(0xFFEF4444), size: 14),
                    SizedBox(width: 8),
                    Text('Thử Đèn Đỏ + Còi (Cảnh báo)'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'turn_off',
                child: Row(
                  children: [
                    Icon(Icons.power_settings_new, color: Colors.grey, size: 14),
                    SizedBox(width: 8),
                    Text('Tắt tháp đèn (Standby)'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'config_gpo',
                child: Row(
                  children: [
                    Icon(Icons.settings, color: c.rfidCyan, size: 14),
                    const SizedBox(width: 8),
                    Text('Cài đặt & Test chân GPO 1-4...', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: c.bgDeep,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.tune, size: 13, color: Color(0xFF0284C7)),
                  const SizedBox(width: 4),
                  const Text('Thử Đèn', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF0284C7))),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_drop_down, size: 13, color: Color(0xFF0284C7)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLedBulb({required Color color, required bool isActive, bool isBuzzer = false}) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isActive ? color : color.withValues(alpha: 0.15),
        border: Border.all(
          color: isActive ? color : Colors.transparent,
          width: 1.2,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.6),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
    );
  }

  void _showTowerLightGpoDialog(EyeCareColors c) {
    int redPin = _towerLight.config.redPin;
    int yellowPin = _towerLight.config.yellowPin;
    int greenPin = _towerLight.config.greenPin;
    int buzzerPin = _towerLight.config.buzzerPin;
    final Map<int, bool> pinStates = {1: false, 2: false, 3: false, 4: false};

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: c.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.border),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.settings_input_composite, color: Color(0xFFEF4444), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CẤU HÌNH & TEST CHÂN RELAY GPO THÁP ĐÈN',
                          style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Đầu đọc Hopeland CL7206 / Tháp đèn CTP50-3T-D-J (Cổng COM/TCP)',
                          style: TextStyle(color: c.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.bgDeep,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: c.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.bolt, size: 16, color: Color(0xFFF59E0B)),
                                const SizedBox(width: 6),
                                Text(
                                  'BẬT / TẮT TRỰC TIẾP TỪNG CHÂN RELAY (TEST PHẦN CỨNG)',
                                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Gạt công tắc để kiểm tra xem bóng đèn nào hoặc còi nào thực tế đang nối vào cổng GPO tương ứng:',
                              style: TextStyle(color: c.textSecondary, fontSize: 11),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [1, 2, 3, 4].map((pin) {
                                final isOn = pinStates[pin] ?? false;
                                return Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 3),
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                    decoration: BoxDecoration(
                                      color: isOn ? c.rfidCyan.withValues(alpha: 0.15) : c.bgCard,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: isOn ? c.rfidCyan : c.border),
                                    ),
                                    child: Column(
                                      children: [
                                        Text('GPO $pin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5, color: isOn ? c.rfidCyan : c.textPrimary)),
                                        const SizedBox(height: 6),
                                        Switch(
                                          value: isOn,
                                          activeThumbColor: c.rfidCyan,
                                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          onChanged: (val) {
                                            setDialogState(() {
                                              pinStates[pin] = val;
                                            });
                                            _towerLight.testIndividualPin(pin, val);
                                          },
                                        ),
                                        Text(isOn ? 'BẬT' : 'TẮT', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isOn ? const Color(0xFF10B981) : c.textSecondary)),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      Text(
                        'GÁN CHÂN CHO TỪNG TÍN HIỆU CẢNH BÁO:',
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                      ),
                      const SizedBox(height: 8),

                      _buildPinSelectorRow(
                        title: 'Đèn Đỏ (Cảnh báo / Sai đơn)',
                        color: const Color(0xFFEF4444),
                        currentPin: redPin,
                        c: c,
                        onChanged: (p) => setDialogState(() => redPin = p),
                      ),
                      const SizedBox(height: 8),

                      _buildPinSelectorRow(
                        title: 'Đèn Vàng (Đang quét đối soát)',
                        color: const Color(0xFFF59E0B),
                        currentPin: yellowPin,
                        c: c,
                        onChanged: (p) => setDialogState(() => yellowPin = p),
                      ),
                      const SizedBox(height: 8),

                      _buildPinSelectorRow(
                        title: 'Đèn Xanh (Đủ hàng thông cổng)',
                        color: const Color(0xFF10B981),
                        currentPin: greenPin,
                        c: c,
                        onChanged: (p) => setDialogState(() => greenPin = p),
                      ),
                      const SizedBox(height: 8),

                      _buildPinSelectorRow(
                        title: 'Còi Hú Buzzer (Báo động)',
                        color: const Color(0xFF8B5CF6),
                        currentPin: buzzerPin,
                        c: c,
                        onChanged: (p) => setDialogState(() => buzzerPin = p),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () {
                    for (int p = 1; p <= 4; p++) {
                      _towerLight.testIndividualPin(p, false);
                    }
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('ĐÓNG'),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('LƯU CẤU HÌNH GPO'),
                  onPressed: () async {
                    for (int p = 1; p <= 4; p++) {
                      await _towerLight.testIndividualPin(p, false);
                    }
                    final newConfig = TowerLightPinConfig(
                      redPin: redPin,
                      yellowPin: yellowPin,
                      greenPin: greenPin,
                      buzzerPin: buzzerPin,
                    );
                    await _towerLight.saveConfig(newConfig);
                    if (context.mounted) {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Color(0xFF10B981),
                          content: Text('✓ Đã lưu cấu hình chân GPO Tháp Đèn thành công!'),
                        ),
                      );
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildPinSelectorRow({
    required String title,
    required Color color,
    required int currentPin,
    required EyeCareColors c,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: c.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: currentPin,
                isDense: true,
                dropdownColor: c.bgCard,
                items: [1, 2, 3, 4].map((pin) {
                  return DropdownMenuItem<int>(
                    value: pin,
                    child: Text('GPO $pin', style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                  );
                }).toList(),
                onChanged: (val) {
                  if (val != null) onChanged(val);
                },
              ),
            ),
          ),
        ],
      ),
    );
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
                      // Badge Tháp Đèn Tín Hiệu CTP50-3T-D-J
                      _buildTowerLightBadge(c),

                      // Nút Nhập Hàng với 3 lựa chọn (File Excel, File nhập PO hoặc Tạo phiếu nhập lẻ)
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
                          } else if (value == 'single_inbound') {
                            _showCreateDemoInboundDialog();
                          } else if (value == 'clear_pending') {
                            _triggerClearAllPendingDialog();
                          }
                        },
                        itemBuilder: (context) {
                          final hasPending = _pendingGateOrders.isNotEmpty ||
                              _repo.inboundOrders.any((o) => o.status == InboundOrderStatus.newOrder || o.status == InboundOrderStatus.processing) ||
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
                                            'Nhập File Excel / CSV (.xlsx, .csv)',
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
                                            'Nhập Từ PO (File PO)',
                                            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Nạp file đơn PO mua hàng: Mã PO, Nhà cung cấp, SKU, Số lượng',
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
                              value: 'single_inbound',
                              enabled: !_isImporting,
                              child: SizedBox(
                                width: 360,
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(Icons.playlist_add_circle_outlined, color: Color(0xFF8B5CF6), size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Tạo Phiếu Nhập Lẻ',
                                            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'Tạo đơn nhập lẻ và gán mã RFID theo số lượng tài sản',
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
                                              'Xóa Sạch Đơn Vừa Nạp Nhầm',
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
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFFFFFF)),
                                )
                              else
                                const Icon(Icons.file_download_outlined, size: 18, color: Color(0xFFFFFFFF)),
                              const SizedBox(width: 6),
                              Text(
                                _isImporting ? 'ĐANG XỬ LÝ...' : 'NHẬP HÀNG',
                                style: const TextStyle(
                                  color: Color(0xFFFFFFFF),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFFFFFFFF)),
                            ],
                          ),
                        ),
                      ),


                      Tooltip(
                        message: 'Làm mới dữ liệu hệ thống',
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
              const SizedBox(height: 10),

              // Thanh Trạng Thái & Cảnh Báo Tháp Đèn Nhập Kho (Đỏ: Cảnh báo/Chip lạ, Vàng: Đang quét, Xanh: Đủ hàng)
              _buildTowerLightAlertBar(c),
              const SizedBox(height: 6),

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

    // Tính riêng cho xe / pallet đang active hiện tại
    final palletExpected = _activeExpectedItems.isNotEmpty
        ? _activeExpectedItems.map((i) => i.epc.trim().toUpperCase()).toSet().length
        : totalExpected;
    final palletScanned = _activeExpectedItems.isNotEmpty
        ? _activeExpectedItems.where((i) {
            final clean = i.epc.trim().toUpperCase();
            return _passedGateEpcs.contains(clean) ||
                _wizardScannedTags.containsKey(clean) ||
                _scannedTagsByOrderNo.values.any((m) => m.containsKey(clean));
          }).length
        : totalScanned;
    final isPalletComplete = palletExpected > 0 && palletScanned >= palletExpected;

    final pendingOrders = _getPendingOrdersList();
    final hasPendingOrders = pendingOrders.isNotEmpty;
    final hasDirectPendingItems = _repo.items.any((i) {
      if (i.status != ItemStatus.pendingInbound) return false;
      final ord = _repo.inboundOrders.where((o) => o.orderNo == i.orderNo || o.inboundOrderId == i.orderNo).firstOrNull;
      if (ord != null) {
        return ord.status == InboundOrderStatus.newOrder || ord.status == InboundOrderStatus.processing;
      }
      return true;
    });

    final isVehicleActive = _activeOrderNo != null || (!hasPendingOrders && hasDirectPendingItems);

    final waitingPutawayItems = _repo.items.where((i) =>
      i.status == ItemStatus.waitingPutaway ||
      (i.status == ItemStatus.inStock &&
       (i.locationId == null || i.locationId!.trim().isEmpty) &&
       (i.palletId != null && i.palletId!.trim().isNotEmpty))
    ).toList();

    Widget mainContent;
    if (_activeOrderNo != null) {
      mainContent = _buildActiveVehicleScanView(
        c,
        unexpList: unexpList,
        hasUnexpectedTags: hasUnexpectedTags,
      );
    } else if (hasPendingOrders) {
      mainContent = _buildPendingOrdersListView(c, pendingOrders);
    } else if (hasDirectPendingItems) {
      mainContent = _buildActiveVehicleScanView(
        c,
        unexpList: unexpList,
        hasUnexpectedTags: hasUnexpectedTags,
      );
    } else {
      mainContent = _buildIdleGateMonitor(c);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. BANNER THÔNG CỔNG THÀNH CÔNG (TỰ ĐỘNG RESET SAU 3S)
          if (_lastSuccessOrderNo != null) ...[
            _buildPassSuccessBanner(c),
            const SizedBox(height: 12),
          ],

          // 2. BANNER THÔNG BÁO HÀNG ĐÃ QUA CỔNG - CHƯA CẤT LÊN KỆ (CHỜ TAY CẦM PDA)
          if (waitingPutawayItems.isNotEmpty) ...[
            _buildWaitingPutawayNoticeBanner(c, waitingPutawayItems),
            const SizedBox(height: 12),
          ],

          // 3. KHUNG NỘI DUNG CHÍNH (DANH SÁCH ĐƠN / ĐỐI SOÁT QUÉT QUA CỔNG / MÀN HÌNH CHỜ)
          Expanded(
            child: mainContent,
          ),

          const SizedBox(height: 12),

          // 4. THANH ĐIỀU KHIỂN DƯỚI CÙNG (BOTTOM CONTROL BAR)
          _buildBottomControlBar(
            c,
            isVehicleActive: isVehicleActive,
            scannedCount: totalScanned,
            expectedCount: totalExpected,
            isComplete: isAllFileComplete,
            palletScannedCount: palletScanned,
            palletExpectedCount: palletExpected,
            isPalletComplete: isPalletComplete,
            hasUnexpectedTags: hasUnexpectedTags,
            unexpList: unexpList,
          ),
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
                  'Pallet/Kiện: ${_lastSuccessPalletCode ?? "--"} • Đã ghi nhận $_lastSuccessCount/$_lastSuccessCount chip (Trạng thái: Chờ Xếp Kệ) • Đang sẵn sàng đón kiện tiếp theo...',
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: () {
              _successBannerTimer?.cancel();
              if (mounted) {
                setState(() {
                  _lastSuccessOrderNo = null;
                  _lastSuccessPalletCode = null;
                  _lastSuccessCount = 0;
                  _activeOrderNo = null;
                  _activePallet = null;
                  _activePalletTag = null;
                  _activeExpectedItems.clear();
                  _wizardDetectedPallet = null;
                  _wizardDetectedPalletTag = null;
                  _wizardSelectedCartons.clear();
                  _wizardSelectedEpcs.clear();
                  _wizardScannedTags.clear();
                  _invalidateCartonCaches();
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_forward, size: 14, color: Color(0xFF10B981)),
                  SizedBox(width: 4),
                  Text('CHUYỂN TIẾP NGAY', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                ],
              ),
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
    final palletText = palletSet.isEmpty ? 'Pallet' : palletSet.join(', ');

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
                  'Pallet: $palletText • ${waitingItems.length} sản phẩm đang ở khu vực đệm chờ cất vào kệ. Khi tay cầm PDA hoàn tất xếp kệ, thông báo này sẽ tự động biến mất.',
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
    // 1. Nếu có đơn hàng nạp từ file trong _pendingGateOrders -> hiển thị sản phẩm theo đơn đang đối soát
    if (_pendingGateOrders.isNotEmpty) {
      final targetOrders = _activeOrderNo != null
          ? _pendingGateOrders.where((p) => p.order.orderNo == _activeOrderNo || p.order.inboundOrderId == _activeOrderNo).toList()
          : _pendingGateOrders.where((p) => !p.isGatePassed).toList();
      final effectiveOrders = targetOrders.isNotEmpty ? targetOrders : _pendingGateOrders;

      final allPallets = <String, String?>{};
      for (final p in effectiveOrders) {
        allPallets.addAll(p.pallets);
      }

      // --- PALLET TRACKERS: luôn hiển thị tất cả pallet để user thấy tổng quan ---
      final List<Map<String, dynamic>> palletTrackers = [];
      String? firstUnpassedPalletCode;
      for (final p in effectiveOrders) {
        final pPalletCodes = p.getPalletCodes();
        final hasRealPallets = p.pallets.isNotEmpty || p.items.any((it) => it.palletId != null && it.palletId!.isNotEmpty);
        for (final palCode in pPalletCodes) {
          final isNoPallet = !hasRealPallets && palCode == p.order.orderNo;
          final palItems = p.getItemsForPallet(palCode);
          final isPassed = p.passedPalletCodes.contains(palCode);
          final palScanned = palItems.where((i) {
            final clean = i.epc.trim().toUpperCase();
            return _passedGateEpcs.contains(clean) ||
                _wizardScannedTags.containsKey(clean) ||
                (_scannedTagsByOrderNo[p.order.orderNo] ?? {}).containsKey(clean);
          }).length;
          palletTrackers.add({
            'code': palCode,
            'isNoPallet': isNoPallet,
            'scanned': palScanned,
            'total': palItems.length,
            'isPassed': isPassed,
          });
          // Track pallet chưa qua cổng đầu tiên
          if (!isPassed && firstUnpassedPalletCode == null) {
            firstUnpassedPalletCode = palCode;
          }
        }
      }

      // --- XÁC ĐỊNH PALLET ĐANG ACTIVE: ưu tiên _activePallet, fallback pallet chưa qua cổng đầu tiên ---
      final activePalCode = _activePallet?.palletCode ?? firstUnpassedPalletCode;
      final bool hasManyPallets = palletTrackers.length > 1;

      // --- LỌC ITEMS: chỉ lấy items của pallet đang active (nếu có nhiều pallet) ---
      List<Item> displayItems;
      if (hasManyPallets && activePalCode != null) {
        // Chỉ hiển thị items thuộc pallet đang active
        displayItems = <Item>[];
        for (final p in effectiveOrders) {
          displayItems.addAll(p.getItemsForPallet(activePalCode));
        }
      } else {
        // Chỉ có 1 pallet hoặc chưa xác định -> hiển thị tất cả
        displayItems = effectiveOrders.expand((p) => p.items).toList();
      }

      // --- TÍNH PROGRESS CHỈ CHO PALLET ĐANG ACTIVE ---
      final expectedProductEpcs = displayItems.map((i) => i.epc.trim().toUpperCase()).toSet();
      // Chỉ thêm EPC pallet nếu pallet đang active có EPC riêng
      final Set<String> activePalletEpcs = {};
      if (activePalCode != null) {
        final palEpc = allPallets[activePalCode] ?? allPallets['PAL-$activePalCode'];
        if (palEpc != null && palEpc.trim().isNotEmpty && palEpc != '--') {
          activePalletEpcs.add(palEpc.trim().toUpperCase());
        }
      } else {
        // Không có pallet active cụ thể -> lấy tất cả EPC pallet
        for (final e in allPallets.values) {
          if (e != null && e.trim().isNotEmpty && e != '--') {
            activePalletEpcs.add(e.trim().toUpperCase());
          }
        }
      }
      final allExpectedEpcs = {...expectedProductEpcs, ...activePalletEpcs};
      final expectedCount = allExpectedEpcs.length;

      final scannedCount = allExpectedEpcs.where((epc) {
        return _passedGateEpcs.contains(epc) ||
            _wizardScannedTags.containsKey(epc) ||
            _scannedTagsByOrderNo.values.any((m) => m.containsKey(epc));
      }).length;
      final isComplete = expectedCount > 0 && scannedCount >= expectedCount;
      final progress = expectedCount > 0 ? (scannedCount / expectedCount).clamp(0.0, 1.0) : 0.0;

      final items = displayItems.map((i) {
        final itemPalletCode = (i.palletId != null && i.palletId!.isNotEmpty)
            ? i.palletId!
            : (allPallets.keys.firstOrNull ?? '--');
        final cleanPallet = itemPalletCode.replaceAll('PAL-', '');
        final itemPalletEpc = allPallets[itemPalletCode] ?? allPallets[cleanPallet] ?? (allPallets.values.firstOrNull ?? '--');
        final supp = (i.supplier != null && i.supplier!.isNotEmpty && i.supplier != 'Nhà cung cấp tổng hợp')
            ? i.supplier!
            : (effectiveOrders.first.supplier.isNotEmpty ? effectiveOrders.first.supplier : '--');
        return {
          'boxCode': i.cartonCode ?? '--',
          'palletCode': itemPalletCode,
          'supplier': supp,
          'sku': i.sku,
          'productName': i.productName,
          'palletEpc': itemPalletEpc,
          'serial': i.epc,
        };
      }).toList();

      return _buildSingleVehicleLayout(
        c,
        items: items,
        palletTrackers: palletTrackers,
        expectedCount: expectedCount,
        scannedCount: scannedCount,
        isComplete: isComplete,
        progress: progress,
        unexpList: unexpList,
        hasUnexpectedTags: hasUnexpectedTags,
        isScannedCallback: (epc) {
          final clean = epc.trim().toUpperCase();
          return _passedGateEpcs.contains(clean) ||
              _wizardScannedTags.containsKey(clean) ||
              _scannedTagsByOrderNo.values.any((m) => m.containsKey(clean));
        },
        getTagCallback: (epc) {
          final clean = epc.trim().toUpperCase();
          return _wizardScannedTags[clean] ??
              _scannedTagsByOrderNo.values.where((m) => m.containsKey(clean)).firstOrNull?[clean];
        },
      );
    }

    // 2. Nếu không có trong _pendingGateOrders (ví dụ: quét trực tiếp từ CSDL)
    final dbPendingItems = _repo.items.where((i) => i.status == ItemStatus.pendingInbound).toList();
    final effectiveItems = _activeExpectedItems.isNotEmpty ? _activeExpectedItems : dbPendingItems;
    final expectedSerials = effectiveItems.isNotEmpty
        ? effectiveItems.map((i) => i.epc.trim().toUpperCase()).toSet()
        : _getWizardExpectedSerials();
    final expectedCount = expectedSerials.length;
    final scannedCount = expectedCount > 0
        ? expectedSerials.where((s) => _passedGateEpcs.contains(s) || _wizardScannedTags.containsKey(s)).length
        : _wizardScannedTags.length;
    final isComplete = expectedCount > 0 && scannedCount >= expectedCount;
    final progress = expectedCount > 0 ? (scannedCount / expectedCount).clamp(0.0, 1.0) : 0.0;
    final activeItems = effectiveItems.isNotEmpty
        ? effectiveItems.map((i) {
            final pal = _repo.pallets.where((p) => p.palletId == i.palletId || p.palletCode == i.palletId).firstOrNull;
            return {
              'boxCode': i.cartonCode ?? '--',
              'palletCode': i.palletId ?? '--',
              'palletEpc': pal?.rfidEpc ?? '--',
              'sku': i.sku,
              'productName': i.productName,
              'serial': i.epc,
              'supplier': i.supplier ?? _repo.inboundOrders.where((o) => o.orderNo == i.orderNo).firstOrNull?.sourceSupplier ?? '--',
              'orderNo': i.orderNo ?? '--',
            };
          }).toList()
        : _getStep2FlatInspectionItems();

    return _buildSingleVehicleLayout(
      c,
      items: activeItems,
      expectedCount: expectedCount,
      scannedCount: scannedCount,
      isComplete: isComplete,
      progress: progress,
      unexpList: unexpList,
      hasUnexpectedTags: hasUnexpectedTags,
      isScannedCallback: (epc) {
        final clean = epc.trim().toUpperCase();
        return _passedGateEpcs.contains(clean) || _wizardScannedTags.containsKey(clean);
      },
      getTagCallback: (epc) => _wizardScannedTags[epc],
    );
  }

  Widget _buildSingleVehicleLayout(
    EyeCareColors c, {
    required List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> palletTrackers = const [],
    required int expectedCount,
    required int scannedCount,
    required bool isComplete,
    required double progress,
    required List<TagInfo> unexpList,
    required bool hasUnexpectedTags,
    required bool Function(String epc) isScannedCallback,
    TagInfo? Function(String epc)? getTagCallback,
  }) {
    final missingCount = (expectedCount - scannedCount).clamp(0, expectedCount);
    final unexpCount = unexpList.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 0. THANH ĐIỀU HƯỚNG QUAY LẠI DANH SÁCH ĐƠN & NÚT XÓA ĐƠN ĐANG ĐỐI SOÁT
        if (_activeOrderNo != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.arrow_back, size: 15),
                  label: const Text(
                    'DANH SÁCH ĐƠN',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  onPressed: () {
                    _stopWizardScan();
                    setState(() {
                      _activeOrderNo = null;
                      _activeExpectedItems.clear();
                    });
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.qr_code_scanner, size: 16, color: c.rfidCyan),
                      const SizedBox(width: 8),
                      Text(
                        'ĐANG ĐỐI SOÁT ĐƠN: $_activeOrderNo',
                        style: TextStyle(
                          color: c.textPrimary,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      if (_activePallet != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: c.bgDeep,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: c.border),
                          ),
                          child: Text(
                            'Pallet: ${_activePallet!.palletCode}',
                            style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFEF4444),
                    side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.6)),
                    backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.delete_outline, size: 15, color: Color(0xFFEF4444)),
                  label: const Text(
                    'XÓA ĐƠN NÀY',
                    style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                  onPressed: () => _confirmDeleteSingleOrder(_activeOrderNo!, chipCount: expectedCount),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        // 1. Thanh tiến độ đọc & 3 Ô CHỈ SỐ: ĐÃ QUÉT - THIẾU - LẠ
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
                      'TIẾN ĐỘ ĐỐI SOÁT QUA CỔNG: ($scannedCount / $expectedCount chip)',
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
              const SizedBox(width: 16),

              // CÁC Ô CHỈ SỐ: ĐÃ QUÉT - THIẾU - LẠ - ĐÃ LỌC
              _buildMetricBadge(
                label: 'ĐÃ QUÉT',
                count: scannedCount,
                color: const Color(0xFF10B981),
                c: c,
              ),
              const SizedBox(width: 8),
              _buildMetricBadge(
                label: 'THIẾU',
                count: missingCount,
                color: const Color(0xFFF59E0B),
                c: c,
              ),
              const SizedBox(width: 8),
              _buildMetricBadge(
                label: 'LẠ',
                count: unexpCount,
                color: const Color(0xFFEF4444),
                c: c,
              ),
            ],
          ),
        ),

        // 1.1 Hàng trạng thái từng Pallet (Pallet Tracker Chips)
        if (palletTrackers.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: palletTrackers.map((pal) {
              final isPassed = pal['isPassed'] as bool;
              final code = pal['code'] as String;
              final scanned = pal['scanned'] as int;
              final total = pal['total'] as int;
                    final isNoPallet = pal['isNoPallet'] as bool? ?? false;
                    final prefix = isNoPallet ? '📦 Hàng lẻ (Không Pallet)' : 'Pallet $code';
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isPassed
                            ? const Color(0xFF10B981).withValues(alpha: 0.12)
                            : (scanned > 0 ? c.rfidCyan.withValues(alpha: 0.1) : c.bgDeep),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isPassed
                              ? const Color(0xFF10B981)
                              : (scanned > 0 ? c.rfidCyan : c.border),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPassed
                                ? Icons.check_circle
                                : (scanned > 0 ? Icons.sensors : (isNoPallet ? Icons.inventory_2_outlined : Icons.grid_view_rounded)),
                            size: 14,
                            color: isPassed ? const Color(0xFF10B981) : (scanned > 0 ? c.rfidCyan : const Color(0xFFF59E0B)),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '$prefix: $scanned/$total chip ${isPassed ? '(✓ ĐÃ QUA CỔNG)' : ''}',
                            style: TextStyle(
                              color: isPassed ? const Color(0xFF10B981) : (scanned > 0 ? c.rfidCyan : c.textPrimary),
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
            }).toList(),
          ),
        ],

        const SizedBox(height: 10),

        // 2. BẢNG THÔNG TIN SẢN PHẨM ĐỐI SOÁT THỜI GIAN THỰC (9 CỘT THEO YÊU CẦU)
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: LayoutBuilder(
              builder: (ctx, constraints) {
                final tableWidth = constraints.maxWidth > 1100 ? constraints.maxWidth : 1100.0;
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: tableWidth,
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
                              const SizedBox(width: 8),
                              SizedBox(width: 110, child: Text('MÃ SKU', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              const SizedBox(width: 8),
                              SizedBox(width: 110, child: Text('MÃ THÙNG', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              const SizedBox(width: 8),
                              SizedBox(width: 110, child: Text('MÃ PALLET', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              const SizedBox(width: 8),
                              SizedBox(width: 140, child: Text('NHÀ CUNG CẤP', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              const SizedBox(width: 8),
                              Expanded(flex: 3, child: Text('TÊN SẢN PHẨM', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              const SizedBox(width: 8),
                              SizedBox(width: 160, child: Text('EPC PALLET', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              const SizedBox(width: 8),
                              SizedBox(width: 160, child: Text('EPC HÀNG', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              const SizedBox(width: 8),
                              SizedBox(width: 110, child: Text('ATEN ĐÃ QUÉT', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                            ],
                          ),
                        ),
                        // Danh sách rows
                        Expanded(
                          child: ListView.separated(
                            itemCount: items.length + unexpList.length,
                            separatorBuilder: (_, _) => Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
                            itemBuilder: (ctx, idx) {
                              if (idx < items.length) {
                                final item = items[idx];
                                final epc = (item['serial'] ?? '').toString().trim().toUpperCase();
                                final isScanned = isScannedCallback(epc);
                                final palletEpc = (item['palletEpc'] ?? '').toString().trim().toUpperCase();
                                final isPalletScanned = palletEpc != '--' && palletEpc.isNotEmpty && isScannedCallback(palletEpc);
                                final isRowHighlighted = isScanned || isPalletScanned;
                                final tag = getTagCallback?.call(epc) ?? (isPalletScanned ? getTagCallback?.call(palletEpc) : null);
                                final antenStr = isRowHighlighted
                                    ? (tag != null && tag.ant.isNotEmpty ? 'Anten ${tag.ant}' : 'Anten 1')
                                    : '--';

                                return Container(
                                  color: isRowHighlighted ? const Color(0xFF10B981).withValues(alpha: 0.05) : Colors.transparent,
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Row(
                                    children: [
                                      SizedBox(width: 45, child: Text('${idx + 1}', style: TextStyle(color: c.textSecondary, fontSize: 12))),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 110,
                                        child: Text(
                                          item['sku'] ?? '--',
                                          style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 110,
                                        child: Text(
                                          item['boxCode'] ?? '--',
                                          style: TextStyle(color: c.textSecondary, fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 110,
                                        child: Text(
                                          item['palletCode'] ?? '--',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 140,
                                        child: Text(
                                          item['supplier'] ?? '--',
                                          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        flex: 3,
                                        child: Text(
                                          item['productName'] ?? '--',
                                          style: TextStyle(color: c.textPrimary, fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 160,
                                        child: Text(
                                          item['palletEpc'] ?? '--',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontSize: 11,
                                            fontWeight: isPalletScanned ? FontWeight.bold : FontWeight.normal,
                                            color: (palletEpc == '--' || palletEpc.isEmpty)
                                                ? c.textSecondary
                                                : (isPalletScanned ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 160,
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
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 110,
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: isRowHighlighted
                                                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                                  : c.bgDeep,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(
                                                color: isRowHighlighted ? const Color(0xFF10B981) : c.border,
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                if (isRowHighlighted) ...[
                                                  const Icon(Icons.check_circle, size: 12, color: Color(0xFF10B981)),
                                                  const SizedBox(width: 4),
                                                ],
                                                Text(
                                                  antenStr,
                                                  style: TextStyle(
                                                    color: isRowHighlighted ? const Color(0xFF10B981) : c.textMuted,
                                                    fontSize: 11,
                                                    fontWeight: isRowHighlighted ? FontWeight.bold : FontWeight.normal,
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
                              } else {
                                final unexp = unexpList[idx - items.length];
                                final antenStr = unexp.ant.isNotEmpty ? 'Anten ${unexp.ant}' : 'Anten 1';
                                return Container(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Row(
                                    children: [
                                      SizedBox(width: 45, child: Text('${idx + 1}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12))),
                                      const SizedBox(width: 8),
                                      const SizedBox(width: 110, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                                      const SizedBox(width: 8),
                                      const SizedBox(width: 110, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                                      const SizedBox(width: 8),
                                      const SizedBox(width: 110, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                                      const SizedBox(width: 8),
                                      const SizedBox(width: 140, child: Text('CHIP LẠ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11.5))),
                                      const SizedBox(width: 8),
                                      const Expanded(
                                        flex: 3,
                                        child: Text(
                                          'Chip không thuộc đơn hàng đang qua cổng!',
                                          style: TextStyle(color: Color(0xFFEF4444), fontSize: 12),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const SizedBox(width: 160, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 160,
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
                                      const SizedBox(width: 8),
                                      SizedBox(
                                        width: 110,
                                        child: Center(
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFEF4444)),
                                            ),
                                            child: Text(
                                              antenStr,
                                              style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold),
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
                );
              },
            ),
          ),
        ),
      ],
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


  // ---------- 5. THANH ĐIỀU KHIỂN DƯỚI CÙNG (DẠT CÁC NÚT THAO TÁC SANG PHẢI) ----------
  Widget _buildBottomControlBar(
    EyeCareColors c, {
    required bool isVehicleActive,
    required int scannedCount,
    required int expectedCount,
    required bool isComplete,
    int? palletScannedCount,
    int? palletExpectedCount,
    bool isPalletComplete = false,
    required bool hasUnexpectedTags,
    required List<TagInfo> unexpList,
  }) {
    final activePending = _pendingGateOrders.where((p) => p.order.orderNo == _activeOrderNo || p.order.inboundOrderId == _activeOrderNo).firstOrNull;
    final isCurrentPalletAlreadyPassed = (activePending != null && _activePallet != null && activePending.passedPalletCodes.contains(_activePallet!.palletCode)) ||
        (activePending != null && activePending.isGatePassed) ||
        (_activeExpectedItems.isNotEmpty && _activeExpectedItems.every((i) => i.status == ItemStatus.waitingPutaway || i.status == ItemStatus.inStock || _passedGateEpcs.contains(i.epc.trim().toUpperCase())));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCardElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Trạng thái Tháp Đèn Tín Hiệu Nhập Kho (CTP50-3T-D-J)
                  _buildTowerLightBadge(c),

                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Nút Làm Mới Quét
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                      const SizedBox(width: 10),

                      // Nút Bắt đầu / Dừng quét
                      Builder(
                        builder: (ctx) {
                          final bool isAllGatePassed = _pendingGateOrders.isNotEmpty && _pendingGateOrders.every((p) => p.isGatePassed);
                          final bool isScanning = _wizardIsScanning || _desktopUhf.isScanning;
                          final bool isLocked = !isScanning && isVehicleActive && (isComplete || isAllGatePassed) && !hasUnexpectedTags;

                          return ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isScanning
                                  ? const Color(0xFFEF4444)
                                  : (isLocked ? const Color(0xFF10B981) : c.rfidCyan),
                              foregroundColor: (isScanning || isLocked) ? Colors.white : const Color(0xFFFFFFFF),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              elevation: 2,
                            ),
                            icon: Icon(
                              isScanning
                                  ? Icons.stop
                                  : (isLocked ? Icons.check_circle_rounded : Icons.sensors),
                              size: 16,
                            ),
                            label: Text(
                              isScanning
                                  ? (_wizardScanDuration == 0 ? 'DỪNG QUÉT LIÊN TỤC' : 'DỪNG QUÉT ($_wizardScanCountdown s)')
                                  : (isLocked
                                      ? 'ĐÃ ĐỐI SOÁT ĐỦ (KHOÁ QUÉT)'
                                      : 'BẮT ĐẦU QUÉT (${_wizardScanDuration == 0 ? "LIÊN TỤC" : "${_wizardScanDuration}s"})'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            onPressed: isScanning
                                ? _stopWizardScan
                                : (isLocked ? () => _completeGoodsReceiveAtGate() : _toggleWizardScan),
                          );
                        },
                      ),

                      // Nút Xác nhận nhập kho: Bỏ nút "CHƯA ĐỌC ĐỦ", chỉ hiện khi đọc đủ 100% pallet hoặc cả đơn
                      if (_lastSuccessOrderNo != null) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF10B981)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
                              const SizedBox(width: 6),
                              Text(
                                _lastSuccessPalletCode != null && _lastSuccessPalletCode != '--'
                                    ? 'ĐÃ ĐỐI SOÁT XONG PALLET $_lastSuccessPalletCode ✓'
                                    : 'ĐÃ ĐỐI SOÁT QUA CỔNG XONG ✓',
                                style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ] else if (isCurrentPalletAlreadyPassed) ...[
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 2,
                          ),
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: const Text('✓ ĐÃ HOÀN TẤT QUA CỔNG (QUAY VỀ CỔNG)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          onPressed: () {
                            setState(() {
                              _activeOrderNo = null;
                              _activePallet = null;
                              _activePalletTag = null;
                              _activeExpectedItems.clear();
                              _wizardDetectedPallet = null;
                              _wizardDetectedPalletTag = null;
                              _wizardSelectedCartons.clear();
                              _wizardSelectedEpcs.clear();
                              _wizardScannedTags.clear();
                              _invalidateCartonCaches();
                            });
                          },
                        ),
                      ] else if (isVehicleActive && (isPalletComplete || isComplete) && !hasUnexpectedTags) ...[
                        const SizedBox(width: 10),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            elevation: 3,
                          ),
                          icon: const Icon(Icons.check_circle, size: 16),
                          label: Text(
                            isPalletComplete && _activePallet != null
                                ? 'XÁC NHẬN NHẬP PALLET ${_activePallet!.palletCode}: ${palletScannedCount ?? scannedCount}/${palletExpectedCount ?? expectedCount}'
                                : 'ĐÃ ĐỌC ĐỦ $scannedCount/$expectedCount (XÁC NHẬN)',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          onPressed: _completeGoodsReceiveAtGate,
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          );
            },
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
                color: isSelected ? const Color(0xFFFFFFFF) : c.textSecondary,
              )
            else
              Icon(
                Icons.timer_outlined,
                size: 13,
                color: isSelected ? const Color(0xFFFFFFFF) : c.textSecondary,
              ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? const Color(0xFFFFFFFF) : c.textSecondary,
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
