import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/tag_info.dart';
import '../../models/wms_models.dart';
import '../../services/uhf_service.dart';
import '../../services/warehouse_repository.dart';
import '../../services/supabase_sync_service.dart';
import '../../theme/eye_care_theme.dart';
import '../../widgets/hardware_status_appbar.dart';
import '../../services/excel_import_service.dart';
import 'pda_putaway_screen.dart';

typedef PdaInboundScreen = InboundScreen;

/// Bộ nhớ tạm lưu phiên nhập kho đang xử lý khi vô tình thoát màn hình PDA,
/// giúp giữ nguyên file nạp, các xe Pallet và thẻ đã quét mà không cần nạp lại file.
class InboundActiveSession {
  static List<Map<String, dynamic>> receiptCartons = [];
  static Set<String> selectedCartons = {};
  static List<String> pendingLoadedOrderNos = [];
  static InboundOrder? selectedOrder;
  static String palletText = 'PALLET-01';
  static Set<String> selectedEpcs = {};
  static Map<String, TagInfo> scannedTags = {};
  static Map<String, TagInfo> unexpectedTags = {};
  static Pallet? detectedPallet;
  static int wizardStep = 1;
  static Map<String, Set<String>> epcsByPallet = {};
  static Map<String, String?> palletEpcMap = {};
  static List<String> palletOrder = [];
  static String? activePalletCode;
  static Map<String, Map<String, TagInfo>> scannedTagsByPallet = {};
  static Set<String> confirmedPallets = {};
  static String? lastPassedPallet;
  static int lastPassedCount = 0;
  static String? lastNextPallet;
  static bool isBatchCompleted = false;

  static bool get hasActiveData =>
      receiptCartons.isNotEmpty || selectedEpcs.isNotEmpty || selectedOrder != null;

  static void syncFromState({
    required List<Map<String, dynamic>> receiptCartons,
    required Set<String> selectedCartons,
    required List<String> pendingLoadedOrderNos,
    required InboundOrder? selectedOrder,
    required String palletText,
    required Set<String> selectedEpcs,
    required Map<String, TagInfo> scannedTags,
    required Map<String, TagInfo> unexpectedTags,
    required Pallet? detectedPallet,
    required int wizardStep,
    required Map<String, Set<String>> epcsByPallet,
    required Map<String, String?> palletEpcMap,
    required List<String> palletOrder,
    required String? activePalletCode,
    required Map<String, Map<String, TagInfo>> scannedTagsByPallet,
    required Set<String> confirmedPallets,
    required String? lastPassedPallet,
    required int lastPassedCount,
    required String? lastNextPallet,
    required bool isBatchCompleted,
  }) {
    InboundActiveSession.receiptCartons = List.from(receiptCartons);
    InboundActiveSession.selectedCartons = Set.from(selectedCartons);
    InboundActiveSession.pendingLoadedOrderNos = List.from(pendingLoadedOrderNos);
    InboundActiveSession.selectedOrder = selectedOrder;
    InboundActiveSession.palletText = palletText;
    InboundActiveSession.selectedEpcs = Set.from(selectedEpcs);
    InboundActiveSession.scannedTags = Map.from(scannedTags);
    InboundActiveSession.unexpectedTags = Map.from(unexpectedTags);
    InboundActiveSession.detectedPallet = detectedPallet;
    InboundActiveSession.wizardStep = wizardStep;
    InboundActiveSession.epcsByPallet = Map.from(epcsByPallet);
    InboundActiveSession.palletEpcMap = Map.from(palletEpcMap);
    InboundActiveSession.palletOrder = List.from(palletOrder);
    InboundActiveSession.activePalletCode = activePalletCode;
    InboundActiveSession.scannedTagsByPallet = Map.from(scannedTagsByPallet);
    InboundActiveSession.confirmedPallets = Set.from(confirmedPallets);
    InboundActiveSession.lastPassedPallet = lastPassedPallet;
    InboundActiveSession.lastPassedCount = lastPassedCount;
    InboundActiveSession.lastNextPallet = lastNextPallet;
    InboundActiveSession.isBatchCompleted = isBatchCompleted;
  }

  static void clear() {
    receiptCartons = [];
    selectedCartons = {};
    pendingLoadedOrderNos = [];
    selectedOrder = null;
    palletText = 'PALLET-01';
    selectedEpcs = {};
    scannedTags = {};
    unexpectedTags = {};
    detectedPallet = null;
    wizardStep = 1;
    epcsByPallet = {};
    palletEpcMap = {};
    palletOrder = [];
    activePalletCode = null;
    scannedTagsByPallet = {};
    confirmedPallets = {};
    lastPassedPallet = null;
    lastPassedCount = 0;
    lastNextPallet = null;
    isBatchCompleted = false;
  }
}

/// Màn hình Nhập Kho RFID trên máy PDA:
/// - Tích hợp nạp file Excel/PO và làm mới dữ liệu tương tự Desktop
/// - Hiển thị bảng đối soát chi tiết dạng bảng như Desktop
/// - Nhận diện thông báo hoàn thành đọc đủ từ Desktop để cất vào kệ
class InboundScreen extends StatefulWidget {
  final String? initialOrderNo;
  const InboundScreen({super.key, this.initialOrderNo});

  @override
  State<InboundScreen> createState() => _InboundScreenState();
}

class _InboundScreenState extends State<InboundScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final SupabaseSyncService _supabaseSync = SupabaseSyncService();
  final ExcelImportService _excelService = ExcelImportService();

  // Quy trình: 1: Bảng dữ liệu hàng hóa & nạp file; 2: Đối soát quét RFID
  int _wizardStep = 1;

  // State nạp file và danh sách thùng hàng (Đồng bộ Desktop)
  final List<Map<String, dynamic>> _receiptCartons = [];
  final Set<String> _selectedCartons = {};
  final List<String> _pendingLoadedOrderNos = [];
  bool _isImporting = false;

  // Bước 1 State
  InboundOrder? _selectedOrder;
  final TextEditingController _palletController = TextEditingController(text: 'PALLET-01');
  final Set<String> _selectedEpcs = {};

  // Bước 2 State
  final Map<String, TagInfo> _scannedTags = {};
  final Map<String, TagInfo> _unexpectedTags = {};
  Pallet? _detectedPallet;
  bool _isScanning = false;
  bool _isSaving = false;
  bool _autoConfirmedThisSession = false; // Chặn auto-confirm trùng lặp trong 1 phiên quét
  bool _isBatchCompleted = false; // Đã đối soát đủ 100% và hoàn thành quét tại cổng
  String _activeFilter = 'ALL'; // 'ALL', 'MATCHED', 'PENDING', 'UNEXPECTED'

  // ── State quản lý đa xe Pallet ──
  // Mapping: palletCode -> Set<EPC> sản phẩm thuộc xe đó (từ file nạp)
  final Map<String, Set<String>> _epcsByPallet = {};
  // Mapping: palletCode -> rfidEpc của xe Pallet
  final Map<String, String?> _palletEpcMap = {};
  // Thứ tự xe Pallet trong file
  final List<String> _palletOrder = [];
  // Xe Pallet đang active (đang đọc)
  String? _activePalletCode;
  // Lưu vết chip đã quét tách biệt theo từng xe
  final Map<String, Map<String, TagInfo>> _scannedTagsByPallet = {};
  // Xe đã xác nhận xong
  final Set<String> _confirmedPallets = {};

  // State thông báo xe vừa qua không chặn màn hình (kiểu Desktop)
  String? _lastPassedPallet;
  int _lastPassedCount = 0;
  String? _lastNextPallet;

  // Cache danh sách hàng hóa và tập EPC dự kiến để đạt hiệu năng 60 FPS
  List<Map<String, dynamic>>? _cachedStep1DetailedItems;
  Set<String>? _cachedAllExpectedEpcs;
  Map<String, Map<String, dynamic>>? _cachedDetailMapBySerial;

  void _invalidateDetailedItemsCache() {
    _cachedStep1DetailedItems = null;
    _cachedAllExpectedEpcs = null;
    _cachedDetailMapBySerial = null;
  }

  StreamSubscription<TagInfo>? _tagSubscription;
  StreamSubscription<bool>? _triggerSubscription;
  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onStateChange);
    _repo.addListener(_onStateChange);

    _uhf.enableScanning('nhap_kho');
    _uhf.setScanMode(PdaScanMode.rfid);
    _restoreActiveSessionOrOrder();
    _checkIfPutawayCompletedAndClear();
    _initHardwareListeners();
  }

  void _onStateChange() {
    if (mounted) {
      _invalidateDetailedItemsCache();
      _checkIfPutawayCompletedAndClear();
      setState(() {});
    }
  }

  void _restoreActiveSessionOrOrder() {
    if (InboundActiveSession.hasActiveData) {
      _receiptCartons.clear();
      _receiptCartons.addAll(InboundActiveSession.receiptCartons);

      _selectedCartons.clear();
      _selectedCartons.addAll(InboundActiveSession.selectedCartons);

      _pendingLoadedOrderNos.clear();
      _pendingLoadedOrderNos.addAll(InboundActiveSession.pendingLoadedOrderNos);

      _selectedOrder = InboundActiveSession.selectedOrder;
      _palletController.text = InboundActiveSession.palletText;

      _selectedEpcs.clear();
      _selectedEpcs.addAll(InboundActiveSession.selectedEpcs);

      _scannedTags.clear();
      _scannedTags.addAll(InboundActiveSession.scannedTags);

      _unexpectedTags.clear();
      _unexpectedTags.addAll(InboundActiveSession.unexpectedTags);

      _detectedPallet = InboundActiveSession.detectedPallet;
      _wizardStep = InboundActiveSession.wizardStep;

      _epcsByPallet.clear();
      _epcsByPallet.addAll(InboundActiveSession.epcsByPallet);

      _palletEpcMap.clear();
      _palletEpcMap.addAll(InboundActiveSession.palletEpcMap);

      _palletOrder.clear();
      _palletOrder.addAll(InboundActiveSession.palletOrder);

      _activePalletCode = InboundActiveSession.activePalletCode;

      _scannedTagsByPallet.clear();
      _scannedTagsByPallet.addAll(InboundActiveSession.scannedTagsByPallet);

      _confirmedPallets.clear();
      _confirmedPallets.addAll(InboundActiveSession.confirmedPallets);

      _lastPassedPallet = InboundActiveSession.lastPassedPallet;
      _lastPassedCount = InboundActiveSession.lastPassedCount;
      _lastNextPallet = InboundActiveSession.lastNextPallet;
      _isBatchCompleted = InboundActiveSession.isBatchCompleted;
      if (!_hasLoadedInboundData) {
        _scannedTags.clear();
        _unexpectedTags.clear();
      }
      return;
    }

    if (widget.initialOrderNo != null && _repo.inboundOrders.isNotEmpty) {
      _selectedOrder = _repo.inboundOrders.where((o) => o.orderNo == widget.initialOrderNo).firstOrNull;
      if (_selectedOrder != null) {
        _loadOrderItemsAndSelectAll(_selectedOrder!);
      }
    } else {
      _selectedOrder = null;
    }
    if (!_hasLoadedInboundData) {
      _scannedTags.clear();
      _unexpectedTags.clear();
    }
  }

  bool get _hasLoadedInboundData {
    if (_receiptCartons.isNotEmpty) return true;
    if (_selectedOrder != null) {
      return _getOrderItems(_selectedOrder).isNotEmpty || _selectedOrder!.details.isNotEmpty;
    }
    return false;
  }

  List<Item> _getOrderItems(InboundOrder? order) {
    if (order == null) return [];
    return _repo.items.where((i) =>
      i.orderNo == order.orderNo || i.orderNo == order.inboundOrderId
    ).toList();
  }

  void _loadOrderItemsAndSelectAll(InboundOrder order) {
    _invalidateDetailedItemsCache();
    var items = _getOrderItems(order);
    if (items.isEmpty && order.details.isNotEmpty) {
      // Tự động sinh danh sách Item dự kiến nếu đơn mới tạo chưa có Item trong CSDL
      _ensureItemsForOrder(order);
      return;
    }

    _selectedEpcs.clear();
    for (var it in items) {
      if (it.epc.isNotEmpty) {
        _selectedEpcs.add(it.epc.trim().toUpperCase());
      }
    }
  }

  Future<void> _ensureItemsForOrder(InboundOrder order) async {
    final existing = _getOrderItems(order);
    if (existing.isNotEmpty) return;

    final now = DateTime.now();
    final newItems = <Item>[];
    int seq = 1;
    for (final d in order.details) {
      for (int q = 0; q < d.requiredQty; q++) {
        final cleanOrder = order.orderNo.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
        final epc = '$cleanOrder${seq.toString().padLeft(4, '0')}'.toUpperCase();
        newItems.add(Item(
          itemId: 'ITEM-${now.millisecondsSinceEpoch}-$seq',
          productId: d.productId,
          sku: d.sku,
          productName: d.productName,
          serialNumber: epc,
          epc: epc,
          status: ItemStatus.pendingInbound,
          orderNo: order.orderNo,
          palletId: 'THUNG-${((seq - 1) ~/ 10) + 1}',
        ));
        seq++;
      }
    }

    if (newItems.isNotEmpty) {
      await _repo.insertDirectItems(newItems);
      _invalidateDetailedItemsCache();
      if (mounted) {
        setState(() {
          _selectedEpcs.clear();
          for (var it in newItems) {
            _selectedEpcs.add(it.epc.trim().toUpperCase());
          }
        });
      }
    }
  }

  DateTime? _lastTriggerPressTime;

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      final isScanKey = key == LogicalKeyboardKey.f1 ||
          key == LogicalKeyboardKey.f2 ||
          key == LogicalKeyboardKey.f3 ||
          key == LogicalKeyboardKey.f4 ||
          key == LogicalKeyboardKey.f5 ||
          key == LogicalKeyboardKey.f6 ||
          key == LogicalKeyboardKey.f7 ||
          key == LogicalKeyboardKey.f8 ||
          key == LogicalKeyboardKey.f9 ||
          key == LogicalKeyboardKey.f10 ||
          key == LogicalKeyboardKey.f11 ||
          key == LogicalKeyboardKey.f12;
      if (isScanKey) {
        if (!_hasLoadedInboundData) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFF59E0B),
              content: Text('⚠️ Vui lòng chọn đơn nhập kho trước khi quét hàng!'),
              duration: Duration(seconds: 2),
            ),
          );
          return true;
        }
        if (_isBatchCompleted) return true;
        _toggleScan();
        return true;
      }
    }
    return false;
  }

  void _initHardwareListeners() {
    _tagSubscription = _uhf.onTagRead.listen((tag) {
      if (!mounted) return;
      _handleIncomingTag(tag);
    });

    _triggerSubscription = _uhf.onTriggerStateChanged.listen((isPressed) {
      if (!mounted) return;
      if (_isBatchCompleted) return;
      debugPrint('InboundScreen: Trigger event -> isPressed=$isPressed, _isScanning=$_isScanning');
      if (isPressed) {
        _lastTriggerPressTime = DateTime.now();
        if (!_hasLoadedInboundData) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFF59E0B),
              content: Text('⚠️ Vui lòng nạp file trước khi quét hàng!'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        if (_isScanning) {
          _stopScan();
        } else {
          _startScan();
        }
      } else {
        // Nhả cò: nếu người dùng GIỮ cò lâu (>= 300ms): dừng quét ngay khi buông tay
        final pressDurationMs = _lastTriggerPressTime != null
            ? DateTime.now().difference(_lastTriggerPressTime!).inMilliseconds
            : 0;
        if (pressDurationMs >= 300 && _isScanning) {
          _stopScan();
        }
      }
    });

    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
  }

  void _scheduleUiRefresh() {
    if (_uiRefreshTimer?.isActive ?? false) return;
    _uiRefreshTimer = Timer(const Duration(milliseconds: 60), () {
      if (mounted) setState(() {});
    });
  }

  void _handleIncomingTag(TagInfo tag) {
    if (!_hasLoadedInboundData || _isBatchCompleted) return;
    final cleanEpc = tag.epc.trim().toUpperCase();
    if (cleanEpc.isEmpty) return;

    if (_uhf.filterDuplicates && _scannedTags.containsKey(cleanEpc)) return;

    // 1. NHẬN DIỆN CHIP XE PALLET (từ file hoặc CSDL)
    String? matchedPalletCodeFromFile;
    for (final entry in _palletEpcMap.entries) {
      final pEpc = (entry.value ?? '').trim().toUpperCase();
      final pCode = entry.key.trim().toUpperCase();
      if ((pEpc.isNotEmpty && pEpc == cleanEpc) || pCode == cleanEpc) {
        matchedPalletCodeFromFile = entry.key;
        break;
      }
    }

    final matchedPalletFromDb = _repo.findPalletByRfid(cleanEpc);

    if (matchedPalletCodeFromFile != null || matchedPalletFromDb != null) {
      final palletCode = matchedPalletCodeFromFile ?? matchedPalletFromDb!.palletCode;
      _unexpectedTags.remove(cleanEpc);

      final isNewChip = !_scannedTags.containsKey(cleanEpc);
      _scannedTags[cleanEpc] = tag;

      if (_detectedPallet == null || _palletController.text.trim().isEmpty) {
        final dbPallet = matchedPalletFromDb ?? _repo.findPalletByRfid(palletCode);
        _detectedPallet = dbPallet ?? Pallet(
          palletId: 'PAL-${palletCode.toUpperCase()}',
          palletCode: palletCode,
          rfidEpc: cleanEpc,
        );
        _palletController.text = palletCode;
      }

      _scheduleUiRefresh();
      if (isNewChip) {
        if (_uhf.hapticEnabled) HapticFeedback.selectionClick();
        _checkAndAutoConfirm();
      }
      return;
    }

    // 2. NHẬN DIỆN CHIP SẢN PHẨM (đối soát toàn bộ file liên tục)
    String? ownerPallet;
    for (final entry in _epcsByPallet.entries) {
      if (entry.value.contains(cleanEpc)) {
        ownerPallet = entry.key;
        break;
      }
    }

    if (ownerPallet != null || _selectedEpcs.contains(cleanEpc)) {
      final targetPallet = ownerPallet ?? (_palletOrder.isNotEmpty ? _palletOrder.first : (_palletController.text.trim().isNotEmpty ? _palletController.text.trim() : 'PALLET-01'));
      _scannedTagsByPallet.putIfAbsent(targetPallet, () => {})[cleanEpc] = tag;
      _unexpectedTags.remove(cleanEpc);

      final isNewChip = !_scannedTags.containsKey(cleanEpc);
      _scannedTags[cleanEpc] = tag;
      _scheduleUiRefresh();

      if (isNewChip) {
        if (_uhf.hapticEnabled) HapticFeedback.selectionClick();
        _checkAndAutoConfirm();
      }
      return;
    }

    // 3. KIỂM TRA PALLET TRONG FILE / FORM (tránh báo chip lạ nếu đọc trúng mã pallet)
    final currentPallet = _palletController.text.trim().toUpperCase();
    if (currentPallet.isNotEmpty && cleanEpc == currentPallet) {
      return;
    }
    for (final entry in _palletEpcMap.entries) {
      final pEpc = (entry.value ?? '').trim().toUpperCase();
      if (entry.key.toUpperCase() == cleanEpc || (pEpc.isNotEmpty && pEpc == cleanEpc)) {
        return;
      }
    }

    // 4. CHIP LẠ NGOÀI ĐƠN
    if (!_unexpectedTags.containsKey(cleanEpc)) {
      _unexpectedTags[cleanEpc] = tag;
      if (_uhf.hapticEnabled) HapticFeedback.heavyImpact();
      _scheduleUiRefresh();
    }
  }


  void _saveSessionToCache() {
    InboundActiveSession.syncFromState(
      receiptCartons: _receiptCartons,
      selectedCartons: _selectedCartons,
      pendingLoadedOrderNos: _pendingLoadedOrderNos,
      selectedOrder: _selectedOrder,
      palletText: _palletController.text,
      selectedEpcs: _selectedEpcs,
      scannedTags: _scannedTags,
      unexpectedTags: _unexpectedTags,
      detectedPallet: _detectedPallet,
      wizardStep: _wizardStep,
      epcsByPallet: _epcsByPallet,
      palletEpcMap: _palletEpcMap,
      palletOrder: _palletOrder,
      activePalletCode: _activePalletCode,
      scannedTagsByPallet: _scannedTagsByPallet,
      confirmedPallets: _confirmedPallets,
      lastPassedPallet: _lastPassedPallet,
      lastPassedCount: _lastPassedCount,
      lastNextPallet: _lastNextPallet,
      isBatchCompleted: _isBatchCompleted,
    );
  }

  @override
  void dispose() {
    _uhf.disableScanning();
    _saveSessionToCache();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    _uiRefreshTimer?.cancel();
    _tagSubscription?.cancel();
    _triggerSubscription?.cancel();
    _eyeCare.removeListener(_onStateChange);
    _repo.removeListener(_onStateChange);
    _palletController.dispose();
    super.dispose();
  }

  void _startScan() {
    if (!_hasLoadedInboundData || _isBatchCompleted) return;
    _uhf.startInventory();
    setState(() {
      _isScanning = true;
    });
  }

  void _stopScan() {
    _uhf.stopInventory();
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _toggleScan() {
    if (!_hasLoadedInboundData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFF59E0B),
          content: Text('⚠️ Vui lòng nạp file trước khi quét hàng!'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_isBatchCompleted) return;
    if (_isScanning) {
      _stopScan();
    } else {
      _startScan();
    }
  }

  void _clearScannedList() {
    HapticFeedback.selectionClick();
    if (_isScanning) {
      _stopScan();
    }
    setState(() {
      _scannedTags.clear();
      _unexpectedTags.clear();
      _detectedPallet = null;
      _autoConfirmedThisSession = false;
      _isBatchCompleted = false;
      _scannedTagsByPallet.clear();
      _confirmedPallets.clear();
      _activePalletCode = _palletOrder.isNotEmpty ? _palletOrder.first : null;
      _uhf.clearTags();
    });
    _saveSessionToCache();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        duration: Duration(seconds: 1),
        content: Text('✓ Đã làm mới danh sách quét. Sẵn sàng quét lại!'),
      ),
    );
  }

  /// Kiểm tra điều kiện tự động xác nhận nhập kho khi đang quét liên tục (toàn bộ file):
  void _checkAndAutoConfirm() {
    if (_autoConfirmedThisSession) return;
    if (_isSaving) return;
    if (_unexpectedTags.isNotEmpty) return;

    // Kiểm tra toàn bộ file (sản phẩm + chip pallet)
    final validPalletEpcs = _palletEpcMap.values
        .where((e) => e != null && e.isNotEmpty && e != '--')
        .map((e) => e!.trim().toUpperCase())
        .toSet();
    final allExpected = {..._selectedEpcs, ...validPalletEpcs};
    final expectedCount = allExpected.length;
    if (expectedCount == 0) return;
    final scannedCount = _scannedTags.keys
        .where((epc) => allExpected.contains(epc.toUpperCase()))
        .length;

    if (scannedCount >= expectedCount) {
      _autoConfirmedThisSession = true;
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        if (_isSaving) return;
        _confirmGoodsReceiveAtGate();
      });
    }
  }

  // ---------- HELPER METHODS NẠP FILE & LÀM MỚI (ĐỒNG BỘ DESKTOP) ----------

  List<Map<String, dynamic>> _getStep1DetailedItems() {
    if (_cachedStep1DetailedItems != null) {
      return _cachedStep1DetailedItems!;
    }

    final palletMap = <String, Pallet>{};
    for (final p in _repo.pallets) {
      palletMap[p.palletId.toUpperCase()] = p;
      palletMap[p.palletCode.toUpperCase()] = p;
    }

    if (_receiptCartons.isNotEmpty) {
      final List<Map<String, dynamic>> flat = [];
      for (var cBox in _receiptCartons) {
        final boxCode = (cBox['cartonBox'] ?? cBox['code'] ?? '').toString();
        final palletCode = (cBox['palletCode'] ?? cBox['palletId'] ?? cBox['pallet'] ?? '--').toString();
        String palletEpc = (cBox['palletEpc'] ?? _palletEpcMap[palletCode] ?? '--').toString();
        if (palletEpc == '--' || palletEpc.isEmpty) {
          final dbPal = palletMap[palletCode.toUpperCase()];
          if (dbPal != null && (dbPal.rfidEpc ?? '').isNotEmpty) {
            palletEpc = dbPal.rfidEpc!;
          }
        }
        final sSupplier = (cBox['supplier'] ?? _selectedOrder?.sourceSupplier ?? 'Nhà cung cấp').toString();
        final serials = (cBox['serials'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        final sItems = (cBox['serialItems'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        for (int i = 0; i < serials.length; i++) {
          final serial = serials[i];
          String sku = (cBox['productCode'] ?? '--').toString();
          String prodName = (cBox['productName'] ?? 'Sản phẩm').toString();
          String itemSupplier = sSupplier;
          if (i < sItems.length) {
            final sItem = sItems[i];
            sku = (sItem['barcode'] ?? sku).toString();
            prodName = (sItem['name'] ?? prodName).toString();
            if (sItem['supplier'] != null && sItem['supplier'].toString().isNotEmpty) {
              itemSupplier = sItem['supplier'].toString();
            }
          }
          flat.add({
            'boxCode': boxCode,
            'palletCode': palletCode,
            'palletEpc': palletEpc,
            'sku': sku,
            'productName': prodName,
            'serial': serial,
            'supplier': itemSupplier,
          });
        }
      }
      _cachedStep1DetailedItems = flat;
      _cachedAllExpectedEpcs = {
        for (final it in flat) ...[
          if ((it['serial'] ?? '').toString().trim().isNotEmpty)
            (it['serial'] ?? '').toString().trim().toUpperCase(),
          if ((it['palletEpc'] ?? '').toString().trim().isNotEmpty && (it['palletEpc'] ?? '').toString().trim() != '--')
            (it['palletEpc'] ?? '').toString().trim().toUpperCase(),
        ]
      };
      return flat;
    }

    if (_selectedOrder != null) {
      final items = _getOrderItems(_selectedOrder);
      if (items.isNotEmpty) {
        final flat = items.map((it) {
          final pal = palletMap[(it.palletId ?? '').toUpperCase()];
          return {
            'boxCode': it.cartonCode ?? it.palletId ?? '--',
            'palletCode': it.palletId ?? '--',
            'palletEpc': pal?.rfidEpc ?? _palletEpcMap[it.palletId] ?? '--',
            'sku': it.sku,
            'productName': it.productName,
            'serial': it.epc,
            'supplier': it.supplier ?? _selectedOrder?.sourceSupplier ?? '--',
          };
        }).toList();
        _cachedStep1DetailedItems = flat;
        _cachedAllExpectedEpcs = {
          for (final it in flat) ...[
            if ((it['serial'] ?? '').toString().trim().isNotEmpty)
              (it['serial'] ?? '').toString().trim().toUpperCase(),
            if ((it['palletEpc'] ?? '').toString().trim().isNotEmpty && (it['palletEpc'] ?? '').toString().trim() != '--')
              (it['palletEpc'] ?? '').toString().trim().toUpperCase(),
          ]
        };
        return flat;
      } else if (_selectedOrder!.details.isNotEmpty) {
        final List<Map<String, dynamic>> flat = [];
        int seq = 1;
        final cleanOrder = _selectedOrder!.orderNo.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
        for (final d in _selectedOrder!.details) {
          for (int q = 0; q < d.requiredQty; q++) {
            final epc = '$cleanOrder${seq.toString().padLeft(4, '0')}'.toUpperCase();
            final boxCode = 'THUNG-${((seq - 1) ~/ 10) + 1}';
            flat.add({
              'boxCode': boxCode,
              'palletCode': boxCode,
              'palletEpc': '--',
              'sku': d.sku,
              'productName': d.productName,
              'serial': epc,
              'supplier': _selectedOrder?.sourceSupplier.isNotEmpty == true ? _selectedOrder!.sourceSupplier : 'Nhà cung cấp',
            });
            seq++;
          }
        }
        _cachedStep1DetailedItems = flat;
        _cachedAllExpectedEpcs = {
          for (final it in flat) (it['serial'] as String).toUpperCase(),
        };
        return flat;
      }
    }

    _cachedStep1DetailedItems = const [];
    _cachedAllExpectedEpcs = const {};
    return const [];
  }

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
        ..._selectedEpcs,
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

  /// Nút LÀM MỚI: Reload đồng bộ dữ liệu từ CSDL & Cloud, giữ nguyên dữ liệu hàng đợi
  Future<void> _handleSyncReload() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      await _supabaseSync.syncNow();
      await _repo.ensureInitialized();
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
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi khi làm mới: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  /// Nút XÓA HÀNG ĐỢI: Hủy bỏ và dọn dẹp hàng đợi vừa nạp
  Future<void> _handleClearQueue() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _eyeCare.colors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: _eyeCare.colors.border)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_outlined, color: Color(0xFFEF4444), size: 22),
            SizedBox(width: 8),
            Text('Xóa hàng đợi?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        content: const Text(
          'Bạn có chắc chắn muốn xóa dữ liệu file/đơn hàng đang chờ để chọn lại file khác?',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('XÓA HÀNG ĐỢI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isImporting = true);
    try {
      await _cleanupPendingDraftOrders();
      _uhf.stopInventory();
      _isScanning = false;

      _receiptCartons.clear();
      _selectedCartons.clear();
      _selectedEpcs.clear();
      _scannedTags.clear();
      _unexpectedTags.clear();
      _wizardStep = 1;
      _selectedOrder = null;

      _epcsByPallet.clear();
      _palletEpcMap.clear();
      _palletOrder.clear();
      _activePalletCode = null;
      _scannedTagsByPallet.clear();
      _confirmedPallets.clear();
      _detectedPallet = null;
      _isBatchCompleted = false;
      _autoConfirmedThisSession = false;
      InboundActiveSession.clear();
      _invalidateDetailedItemsCache();

      if (mounted) setState(() {});
      _supabaseSync.syncNow();
    } catch (e) {
      debugPrint('Lỗi xóa hàng đợi: $e');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _pickAndLoadLiveExcelFile() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final result = await _excelService.pickAndParseGoodsReceiveExcel();
      if (result == null) return;

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
            explicitItems.add(Item(
              itemId: 'ITEM-${now.millisecondsSinceEpoch}-$itemSeq',
              productId: sBarcode,
              sku: sBarcode,
              productName: sName,
              serialNumber: sSerial,
              epc: sSerial,
              status: ItemStatus.pendingInbound,
              orderNo: inboundOrderNo,
              palletId: assignedPalletId,
              cartonCode: cartonBox != null && cartonBox.isNotEmpty ? cartonBox : null,
              supplier: sSupplier,
              inboundTime: now,
              inboundBy: _repo.resolveUserFullName(null, defaultRole: 'thukho'),
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
              palletId: assignedPalletId,
              cartonCode: cartonBox != null && cartonBox.isNotEmpty ? cartonBox : null,
              supplier: sSupplier,
              inboundTime: now,
              inboundBy: _repo.resolveUserFullName(null, defaultRole: 'thukho'),
            ));
            itemSeq++;
          }
        }
      }

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

      // Cập nhật state
      setState(() {
        _receiptCartons.clear();
        _receiptCartons.addAll(result.cartons);
        _selectedCartons.clear();
        for (var c in result.cartons) {
          final box = (c['cartonBox'] ?? c['code'] ?? '').toString().trim();
          if (box.isNotEmpty) _selectedCartons.add(box);
        }
        _selectedEpcs.clear();
        for (var it in explicitItems) {
          if (it.epc.isNotEmpty) _selectedEpcs.add(it.epc.toUpperCase());
        }

        // Xây dựng mapping đa xe Pallet
        _epcsByPallet.clear();
        _palletEpcMap.clear();
        _palletOrder.clear();
        _scannedTagsByPallet.clear();
        _confirmedPallets.clear();

        // --- Resolve tên pallet thực từ CSDL theo EPC ---
        // Nếu EPC trong file trùng với pallet trong CSDL → dùng tên/mã của pallet đó (e.g. PL01)
        final Map<String, String> resolvedPalletName = {}; // fileCode → displayCode
        for (final entry in palletsToRegister.entries) {
          final fileCode = entry.key;
          final epc = (entry.value ?? '').trim().toUpperCase();
          // Ưu tiên: tra CSDL theo EPC trước
          Pallet? dbPallet;
          if (epc.isNotEmpty) {
            dbPallet = _repo.pallets.where((p) =>
              (p.rfidEpc ?? '').trim().toUpperCase() == epc
            ).firstOrNull;
          }
          // Nếu không có EPC, tra theo mã pallet trong file
          dbPallet ??= _repo.pallets.where((p) =>
            p.palletCode.toUpperCase() == fileCode.toUpperCase() ||
            p.palletId.toUpperCase() == fileCode.toUpperCase() ||
            p.palletId.toUpperCase() == 'PAL-${fileCode.toUpperCase()}'
          ).firstOrNull;
          // Dùng tên CSDL nếu tìm thấy, giữ nguyên nếu không
          resolvedPalletName[fileCode] = dbPallet?.palletCode ?? fileCode;
        }

        for (var item in explicitItems) {
          final rawCode = item.palletId?.replaceAll(RegExp(r'^PAL-', caseSensitive: false), '') ?? 'PALLET-DEFAULT';
          // Dùng tên đã resolve từ CSDL (hoặc giữ nguyên nếu không tìm thấy)
          final palletCode = resolvedPalletName[rawCode] ?? rawCode;
          _epcsByPallet.putIfAbsent(palletCode, () => <String>{}).add(item.epc.toUpperCase());
          if (!_palletOrder.contains(palletCode)) _palletOrder.add(palletCode);
        }

        for (final entry in palletsToRegister.entries) {
          final displayCode = resolvedPalletName[entry.key] ?? entry.key;
          _palletEpcMap[displayCode] = entry.value;
        }

        _activePalletCode = _palletOrder.isNotEmpty ? _palletOrder.first : null;
      });

      // Thêm sản phẩm vào CSDL
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

      _selectedOrder = order;
      _pendingLoadedOrderNos.clear();
      _pendingLoadedOrderNos.add(inboundOrderNo);
      _saveSessionToCache();

      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi nạp file Excel: $e')),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<void> _pickAndLoadPoFile() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final rows = await _excelService.pickAndParseBatchOrdersExcel();
      if (rows == null || rows.isEmpty) return;

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

      setState(() {
        _receiptCartons.clear();
        _receiptCartons.addAll(cartons);
        _selectedCartons.clear();
        for (var c in cartons) {
          final box = (c['cartonBox'] ?? c['code'] ?? '').toString().trim();
          if (box.isNotEmpty) _selectedCartons.add(box);
        }
        _selectedEpcs.clear();
        for (var it in explicitItems) {
          if (it.epc.isNotEmpty) _selectedEpcs.add(it.epc.toUpperCase());
        }

        // Xây dựng mapping đa xe Pallet (PO: mỗi PO = 1 xe)
        _epcsByPallet.clear();
        _palletEpcMap.clear();
        _palletOrder.clear();
        _scannedTagsByPallet.clear();
        _confirmedPallets.clear();

        for (var item in explicitItems) {
          final palletCode = item.palletId?.replaceAll(RegExp(r'^PAL-', caseSensitive: false), '') ?? item.orderNo ?? 'PALLET-DEFAULT';
          _epcsByPallet.putIfAbsent(palletCode, () => <String>{}).add(item.epc.toUpperCase());
          if (!_palletOrder.contains(palletCode)) _palletOrder.add(palletCode);
        }

        _activePalletCode = _palletOrder.isNotEmpty ? _palletOrder.first : null;
      });

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
      if (poGroup.isNotEmpty) {
        _selectedOrder = _repo.inboundOrders.where((o) => o.orderNo == poGroup.keys.first).firstOrNull;
      }
      _saveSessionToCache();

      if (!mounted) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi nạp file PO: $e')),
      );
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  // ---------- GIAO DIỆN CHÍNH ----------

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_wizardStep == 2) {
          if (_isScanning) _stopScan();
          _saveSessionToCache();
          setState(() => _wizardStep = 1);
        } else {
          _saveSessionToCache();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: c.bgDeep,
        appBar: HardwareStatusAppBar(
          title: '📥 NHẬP KHO RFID (PDA)',
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_wizardStep == 2) {
                if (_isScanning) _stopScan();
                _saveSessionToCache();
                setState(() => _wizardStep = 1);
              } else {
                _saveSessionToCache();
                Navigator.of(context).pop();
              }
            },
          ),
        ),
        body: Column(
          children: [
            // Banner thông báo nếu Desktop hoàn thành đọc đủ hàng chờ cất kệ (nếu không có thì SizedBox.shrink() đẩy sát lên trên)
            _buildDesktopCompletionBanner(c),

            // Nội dung theo bước: 1 (Bảng dữ liệu hàng hóa như Desktop) hoặc 2 (Đối soát quét RFID)
            Expanded(
              child: _wizardStep == 1 ? _buildStep1CartonSelection(c) : _buildStep2RfidVerification(c),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- BANNER THÔNG BÁO HOÀN THÀNH ĐỌC ĐỦ TỪ DESKTOP ----------

  Widget _buildDesktopCompletionBanner(EyeCareColors c) {
    // Kiểm tra hàng đã đọc đủ qua cổng desktop chờ cất kệ
    final waitingPutawayItems = _repo.items.where((i) =>
      i.status == ItemStatus.waitingPutaway ||
      (i.status == ItemStatus.inStock &&
       (i.locationId == null || i.locationId!.trim().isEmpty) &&
       (i.palletId != null && i.palletId!.trim().isNotEmpty))
    ).toList();

    final waitingOrders = _repo.inboundOrders.where((o) =>
      o.status == InboundOrderStatus.waitingPutaway
    ).toList();

    // Nếu không có hàng chờ cất kệ từ desktop: Không chiếm diện tích, đẩy toàn bộ giao diện sát lên trên
    if (waitingPutawayItems.isEmpty && waitingOrders.isEmpty) {
      return const SizedBox.shrink();
    }

    final palletSet = <String>{};
    for (final it in waitingPutawayItems) {
      if (it.palletId != null && it.palletId!.trim().isNotEmpty) {
        palletSet.add(it.palletId!.trim());
      }
    }
    final palletText = palletSet.isEmpty
        ? (waitingOrders.isNotEmpty ? waitingOrders.first.orderNo : 'Chưa gán pallet')
        : palletSet.join(', ');

    final totalCount = waitingPutawayItems.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shelves, color: Color(0xFFF59E0B), size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'CHƯA CẤT LÊN KỆ',
                  style: TextStyle(
                    color: Color(0xFFF59E0B),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  'Xe: $palletText • $totalCount SP',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 1,
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PdaPutawayScreen(
                    initialCartonOrPalletBarcode: palletSet.isNotEmpty ? palletSet.first : null,
                  ),
                ),
              );
              if (mounted) _checkIfPutawayCompletedAndClear();
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shelves, size: 14),
                SizedBox(width: 4),
                Text('CẤT KỆ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =======================================================
  // BƯỚC 1: BẢNG DỮ LIỆU HÀNG HÓA & ĐỐI SOÁT QUÉT (CHUẨN DESKTOP)
  // =======================================================

  Widget _buildMetricBox({
    required String label,
    required int count,
    required Color color,
    required EyeCareColors c,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.7), width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.5,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              '$count',
              style: TextStyle(
                color: color,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep1CartonSelection(EyeCareColors c) {
    final allDetailedItems = _getStep1DetailedItems();
    final allExpected = _cachedAllExpectedEpcs ?? const {};
    final expectedCount = allExpected.length;
    final scannedCount = _isBatchCompleted ? expectedCount : _scannedTags.keys.where((epc) => allExpected.contains(epc.toUpperCase())).length;
    final missingCount = _isBatchCompleted ? 0 : (expectedCount - scannedCount).clamp(0, expectedCount);
    final unexpCount = _unexpectedTags.length;
    final isComplete = _isBatchCompleted || (expectedCount > 0 && scannedCount >= expectedCount);
    final unexpList = _unexpectedTags.values.toList();

    return Column(
      children: [
        // 1. Thanh công cụ 3 nút thu gọn: NHẬP HÀNG, LÀM MỚI, XÓA HÀNG ĐỢI
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: c.bgDeep,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Nút Nhập Hàng (Dropdown menu nhỏ gọn)
                PopupMenuButton<String>(
                  enabled: !_isImporting,
                  tooltip: 'Chọn nguồn nạp file',
                  offset: const Offset(0, 34),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(color: c.border),
                  ),
                  color: c.bgCardElevated,
                  onSelected: (value) {
                    if (_isImporting) return;
                    if (value == 'excel') {
                      _pickAndLoadLiveExcelFile();
                    } else if (value == 'po') {
                      _showInboundPoOptionsDialog();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'excel',
                      height: 40,
                      child: Row(
                        children: [
                          const Icon(Icons.table_chart, color: Color(0xFF10B981), size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Nhập File Excel / CSV (.xlsx, .csv)',
                              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'po',
                      height: 40,
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long, color: c.rfidCyan, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Nhập Từ PO',
                              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: _isImporting ? c.rfidCyan.withValues(alpha: 0.5) : c.rfidCyan,
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: [
                        BoxShadow(
                          color: c.rfidCyan.withValues(alpha: 0.25),
                          blurRadius: 3,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isImporting)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2C251E)),
                          )
                        else
                          const Icon(Icons.file_download_outlined, size: 14, color: Color(0xFF2C251E)),
                        const SizedBox(width: 4),
                        Text(
                          _isImporting ? 'ĐANG NẠP...' : 'NHẬP HÀNG',
                          style: const TextStyle(
                            color: Color(0xFF2C251E),
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 14, color: Color(0xFF2C251E)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Nút Làm Mới
                Tooltip(
                  message: 'Làm mới',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(Icons.refresh, size: 14, color: c.textPrimary),
                    label: Text(
                      'LÀM MỚI',
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                    onPressed: _isImporting ? null : _handleSyncReload,
                  ),
                ),

                // Nút Xóa Hàng Đợi (Thu gọn)
                if (allDetailedItems.isNotEmpty || _receiptCartons.isNotEmpty || _selectedOrder != null) ...[
                  const SizedBox(width: 6),
                  Tooltip(
                    message: 'Xóa hàng đợi',
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.6)),
                        backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.08),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Icons.delete_sweep_outlined, size: 14, color: Color(0xFFEF4444)),
                      label: const Text(
                        'XÓA HÀNG ĐỢI',
                        style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11),
                      ),
                      onPressed: _isImporting ? null : _handleClearQueue,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // 2 & 3. CHỈ HIỂN THỊ TIÊU ĐỀ & 3 Ô CHỈ SỐ KHI ĐÃ NẠP FILE HOẶC CHỌN ĐƠN
        if (allDetailedItems.isNotEmpty || _selectedOrder != null || _receiptCartons.isNotEmpty) ...[
          // 2. Dòng Tiêu đề: DANH SÁCH HÀNG NHẬP / ĐƠN NHẬP
          Container(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            color: c.bgDeep,
            child: Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        Text(
                          _selectedOrder != null ? 'ĐƠN: ${_selectedOrder!.orderNo}' : 'DANH SÁCH HÀNG NHẬP',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '(${allDetailedItems.length} sản phẩm${_selectedOrder != null && _selectedOrder!.sourceSupplier.isNotEmpty ? " • ${_selectedOrder!.sourceSupplier}" : ""})',
                          style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                Builder(
                  builder: (context) {
                    final otherOrders = _repo.inboundOrders
                        .where((o) => o.status != InboundOrderStatus.completed && o.orderNo != _selectedOrder?.orderNo)
                        .toList();
                    if (otherOrders.isEmpty) return const SizedBox.shrink();
                    return InkWell(
                      onTap: _showSelectInboundOrderDialog,
                      borderRadius: BorderRadius.circular(6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: c.rfidCyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.rfidCyan.withValues(alpha: 0.5)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swap_horiz, size: 13, color: c.rfidCyan),
                            const SizedBox(width: 3),
                            Text('ĐỔI ĐƠN', style: TextStyle(color: c.rfidCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // 3. Thay thế ô tìm kiếm bằng 3 ô: ĐÃ QUÉT (xanh), THIẾU (vàng), LẠ (đỏ)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                // 1. ĐÃ QUÉT (Xanh lục)
                Expanded(
                  child: _buildMetricBox(
                    label: 'ĐÃ QUÉT',
                    count: scannedCount,
                    color: const Color(0xFF10B981),
                    c: c,
                  ),
                ),
                const SizedBox(width: 8),
                // 2. THIẾU (Vàng)
                Expanded(
                  child: _buildMetricBox(
                    label: 'THIẾU',
                    count: missingCount,
                    color: const Color(0xFFF59E0B),
                    c: c,
                  ),
                ),
                const SizedBox(width: 8),
                // 3. LẠ (Đỏ)
                Expanded(
                  child: _buildMetricBox(
                    label: 'LẠ',
                    count: unexpCount,
                    color: const Color(0xFFEF4444),
                    c: c,
                  ),
                ),
              ],
            ),
          ),
        ],

        // 4. BẢNG DỮ LIỆU ĐỦ 8 CỘT (HOẶC DANH SÁCH ĐƠN CHỜ NHẬP)
        Expanded(
          child: (_selectedOrder == null && _receiptCartons.isEmpty && allDetailedItems.isEmpty)
              ? _buildEmptyStateOrOrderList(c)
              : Container(
                  margin: const EdgeInsets.fromLTRB(10, 4, 10, 8),
                  decoration: BoxDecoration(
                    color: c.bgCardElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: SizedBox(
                      width: 885, // 8 cột cho PDA (đồng bộ xuất kho)
                      child: Column(
                        children: [
                          // Header 8 cột PDA
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                            decoration: BoxDecoration(
                              color: c.bgDeep,
                              border: Border(bottom: BorderSide(color: c.border)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(width: 38, child: Text('STT', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 6),
                                SizedBox(width: 90, child: Text('MÃ SKU', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 6),
                                SizedBox(width: 90, child: Text('MÃ THÙNG', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 6),
                                SizedBox(width: 90, child: Text('MÃ PALLET', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 6),
                                SizedBox(width: 120, child: Text('NHÀ CUNG CẤP', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 6),
                                Expanded(flex: 3, child: Text('TÊN SẢN PHẨM', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 6),
                                SizedBox(width: 135, child: Text('EPC PALLET', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 6),
                                SizedBox(width: 135, child: Text('EPC HÀNG', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ),

                          // Table Rows (bao gồm hàng dự kiến và chip lạ)
                          Expanded(
                            child: ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              itemCount: allDetailedItems.length + unexpList.length,
                              itemBuilder: (context, index) {
                                if (index < allDetailedItems.length) {
                                  final item = allDetailedItems[index];
                                  final boxCode = (item['boxCode'] ?? '--').toString();
                                  final sku = (item['sku'] ?? '--').toString();
                                  final palletCode = (item['palletCode'] ?? '--').toString();
                                  final supplier = (item['supplier'] ?? '--').toString();
                                  final prodName = (item['productName'] ?? 'Sản phẩm').toString();
                                  final palletEpc = (item['palletEpc'] ?? '--').toString();
                                  final serial = (item['serial'] ?? '').toString().trim().toUpperCase();
                                  final isScanned = _scannedTags.containsKey(serial);
                                  final isPalletScanned = palletEpc != '--' && palletEpc.isNotEmpty && _scannedTags.containsKey(palletEpc.toUpperCase());

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: isScanned
                                          ? const Color(0xFF10B981).withValues(alpha: 0.08)
                                          : (index % 2 == 0 ? Colors.transparent : c.bgDeep.withValues(alpha: 0.25)),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: isScanned
                                              ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                              : c.border.withValues(alpha: 0.4),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: 38,
                                          child: Text(
                                            '${index + 1}',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: c.textSecondary, fontSize: 11),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: 90,
                                          child: Text(
                                            sku,
                                            style: TextStyle(
                                              color: c.textPrimary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: 90,
                                          child: Text(
                                            boxCode,
                                            style: TextStyle(color: c.textPrimary, fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: 90,
                                          child: Text(
                                            palletCode,
                                            style: TextStyle(color: c.textPrimary, fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: 120,
                                          child: Text(
                                            supplier,
                                            style: TextStyle(color: c.textSecondary, fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            prodName,
                                            style: TextStyle(color: c.textPrimary, fontSize: 11),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: 135,
                                          child: Text(
                                            palletEpc,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 10.5,
                                              fontWeight: isPalletScanned ? FontWeight.bold : FontWeight.normal,
                                              color: isPalletScanned ? const Color(0xFF10B981) : c.textSecondary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        SizedBox(
                                          width: 135,
                                          child: Text(
                                            serial,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 10.5,
                                              fontWeight: isScanned ? FontWeight.bold : FontWeight.normal,
                                              color: isScanned ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  // Hàng Chip Lạ (Rogue Chips ngoài đơn)
                                  final unexpIdx = index - allDetailedItems.length;
                                  final unexpTag = unexpList[unexpIdx];

                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                                      border: Border(
                                        bottom: BorderSide(
                                          color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        SizedBox(width: 38, child: Text('${index + 1}', textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
                                        const SizedBox(width: 6),
                                        const SizedBox(width: 90, child: Text('CHIP LẠ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11))),
                                        const SizedBox(width: 6),
                                        const SizedBox(width: 90, child: Text('--', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
                                        const SizedBox(width: 6),
                                        const SizedBox(width: 90, child: Text('--', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
                                        const SizedBox(width: 6),
                                        const SizedBox(width: 120, child: Text('--', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
                                        const SizedBox(width: 6),
                                        const Expanded(flex: 3, child: Text('Thẻ RFID ngoài danh mục', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
                                        const SizedBox(width: 6),
                                        const SizedBox(width: 135, child: Text('--', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5))),
                                        const SizedBox(width: 6),
                                        SizedBox(width: 135, child: Text(unexpTag.epc, style: const TextStyle(color: Color(0xFFEF4444), fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 10.5))),
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
                ),
        ),

        // 5. Thanh Thao Tác Đáy: Quét RFID & Xác Nhận Nhập Kho
        if (allDetailedItems.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              border: Border(top: BorderSide(color: c.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (!_isBatchCompleted) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.textPrimary,
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF0284C7)),
                      label: const Text('Làm mới quét', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: _clearScannedList,
                    ),
                    const SizedBox(width: 6),
                  ],
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _isBatchCompleted ? const Color(0xFF10B981) : (_isScanning ? Colors.white : c.textPrimary),
                      backgroundColor: _isBatchCompleted ? const Color(0xFF10B981).withValues(alpha: 0.15) : (_isScanning ? const Color(0xFFEF4444) : null),
                      side: BorderSide(color: _isBatchCompleted ? const Color(0xFF10B981) : (_isScanning ? const Color(0xFFEF4444) : const Color(0xFF0284C7))),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: Icon(_isBatchCompleted ? Icons.check_circle : (_isScanning ? Icons.stop : Icons.play_arrow), size: 15, color: _isBatchCompleted ? const Color(0xFF10B981) : (_isScanning ? Colors.white : const Color(0xFF0284C7))),
                    label: Text(_isBatchCompleted ? 'Đã Quét Đủ 100%' : (_isScanning ? 'Dừng Quét' : 'Bắt Đầu Quét'), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _isBatchCompleted ? const Color(0xFF10B981) : (_isScanning ? Colors.white : c.textPrimary))),
                    onPressed: _isBatchCompleted ? null : _toggleScan,
                  ),
                  if (_isBatchCompleted) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0284C7),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.shelves, size: 16),
                      label: const Text(
                        '📦 CẤT HÀNG VÀO KỆ',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      onPressed: () async {
                        final targetPallet = _lastPassedPallet ?? (_palletOrder.isNotEmpty ? _palletOrder.first : null);
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PdaPutawayScreen(
                              initialCartonOrPalletBarcode: targetPallet,
                            ),
                          ),
                        );
                        if (mounted) _checkIfPutawayCompletedAndClear();
                      },
                    ),
                  ] else if (isComplete && unexpCount == 0) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _isSaving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle, size: 16),
                      label: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          _isSaving
                              ? 'ĐANG LƯU KHO...'
                              : '✓ XÁC NHẬN NHẬP KHO ($scannedCount/$expectedCount)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                      ),
                      onPressed: _isSaving ? null : _confirmGoodsReceiveAtGate,
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ==========================================
  // BƯỚC 2: ĐỐI SOÁT QUÉT RFID & TỰ ĐỘNG NHẬN PALLET
  // ==========================================

  Widget _buildStep2RfidVerification(EyeCareColors c) {
    final validPalletEpcs = _palletEpcMap.values
        .where((e) => e != null && e.isNotEmpty && e != '--')
        .map((e) => e!.trim().toUpperCase())
        .toSet();
    final allExpected = {..._selectedEpcs, ...validPalletEpcs};
    final expectedCount = allExpected.length;
    final scannedCount = _isBatchCompleted ? expectedCount : _scannedTags.keys.where((epc) => allExpected.contains(epc.toUpperCase())).length;

    final isComplete = _isBatchCompleted || (expectedCount > 0 && scannedCount >= expectedCount);
    final allPalletsConfirmed = _isBatchCompleted || _confirmedPallets.isNotEmpty || (expectedCount > 0 && scannedCount >= expectedCount);
    final progress = expectedCount > 0 ? (scannedCount / expectedCount).clamp(0.0, 1.0) : 0.0;
    final hasUnexpected = _unexpectedTags.isNotEmpty;

    final allDetails = _getStep1DetailedItems();
    final detailMap = _cachedDetailMapBySerial ??= {for (var d in allDetails) (d['serial'] ?? '').toString().toUpperCase(): d};

    final displayEpcs = _selectedEpcs;
    final activeScanned = _scannedTags;

    // Lọc danh sách theo filter chip
    final List<Map<String, dynamic>> displayList = [];
    if (_activeFilter == 'ALL' || _activeFilter == 'MATCHED') {
      for (var epc in displayEpcs) {
        if (activeScanned.containsKey(epc)) {
          final it = detailMap[epc];
          displayList.add({
            'type': 'MATCHED',
            'epc': epc,
            'sku': it?['sku'] ?? 'SKU',
            'name': it?['productName'] ?? 'Sản phẩm',
            'box': it?['boxCode'] ?? '--',
            'tag': activeScanned[epc],
          });
        }
      }
    }
    if (_activeFilter == 'ALL' || _activeFilter == 'PENDING') {
      for (var epc in displayEpcs) {
        if (!activeScanned.containsKey(epc)) {
          final it = detailMap[epc];
          displayList.add({
            'type': 'PENDING',
            'epc': epc,
            'sku': it?['sku'] ?? 'SKU',
            'name': it?['productName'] ?? 'Sản phẩm',
            'box': it?['boxCode'] ?? '--',
          });
        }
      }
    }
    if (_activeFilter == 'ALL' || _activeFilter == 'UNEXPECTED') {
      for (var entry in _unexpectedTags.entries) {
        displayList.add({
          'type': 'UNEXPECTED',
          'epc': entry.key,
          'sku': 'CHIP LẠ',
          'name': 'Thẻ RFID không thuộc danh mục nạp',
          'box': 'NGOÀI ĐƠN',
          'tag': entry.value,
        });
      }
    }

    return Column(
      children: [
        // Navigation Header: Quay lại bảng danh sách & Info tiến độ
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: c.bgCard,
          child: Row(
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.arrow_back, size: 14),
                label: const Text('⮜ Bảng danh sách', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () {
                  if (_isScanning) _stopScan();
                  setState(() => _wizardStep = 1);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Đang đối soát: ${_selectedEpcs.length} SP',
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Số xe: ${_palletOrder.isNotEmpty ? _palletOrder.length : 1} xe (${_selectedEpcs.length} SP + ${validPalletEpcs.length} pallet)',
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.textPrimary,
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.refresh, size: 14, color: Color(0xFF0284C7)),
                label: Text(
                  'Làm mới',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: c.textPrimary),
                ),
                onPressed: _clearScannedList,
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _isBatchCompleted ? const Color(0xFF10B981) : (_isScanning ? Colors.white : c.textPrimary),
                  backgroundColor: _isBatchCompleted ? const Color(0xFF10B981).withValues(alpha: 0.15) : (_isScanning ? const Color(0xFFEF4444) : null),
                  side: BorderSide(color: _isBatchCompleted ? const Color(0xFF10B981) : (_isScanning ? const Color(0xFFEF4444) : const Color(0xFF0284C7))),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  visualDensity: VisualDensity.compact,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(_isBatchCompleted ? Icons.check_circle : (_isScanning ? Icons.stop : Icons.play_arrow), size: 14, color: _isBatchCompleted ? const Color(0xFF10B981) : (_isScanning ? Colors.white : const Color(0xFF0284C7))),
                label: Text(_isBatchCompleted ? 'Đã Xong' : (_isScanning ? 'Dừng' : 'Quét'), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: _isBatchCompleted ? const Color(0xFF10B981) : (_isScanning ? Colors.white : c.textPrimary))),
                onPressed: _isBatchCompleted ? null : _toggleScan,
              ),
            ],
          ),
        ),

        Expanded(
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    children: [
                      // Banner thông báo xe vừa đối soát đủ, tự động chuyển tiếp không chặn màn hình (chuẩn Desktop)
                      if (_lastPassedPallet != null) ...[
                        _buildPassSuccessBanner(c),
                        const SizedBox(height: 10),
                      ],

                      // 1. Thẻ Hero Tiến Độ Quét (Counter & Progress Bar lớn) bọc RepaintBoundary chống repaint diện rộng
                      RepaintBoundary(
                        child: _buildHeroProgressCard(c, scannedCount, expectedCount, progress, isComplete, hasUnexpected),
                      ),
                      const SizedBox(height: 10),

                      // 2. Thẻ Cảnh Báo Nếu Có Chip Lạ Ngoài Đơn
                      if (hasUnexpected) ...[
                        _buildUnexpectedAlertBanner(c),
                        const SizedBox(height: 10),
                      ],

                      // 3. Khung điều khiển quét phần cứng PDA (Bóp cò hoặc nút bấm)
                      _buildHardwareScannerControls(c),
                      const SizedBox(height: 10),

                      // 4. Các nút lọc (Filter Chips)
                      _buildFilterChips(scannedCount, expectedCount, _unexpectedTags.length),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),

              // 5. Danh sách thẻ đã quét / đối soát (Được ảo hóa hoàn toàn, 60 FPS)
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                sliver: SliverList.separated(
                  itemCount: displayList.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final row = displayList[index];
                    return _buildVerificationRowTile(row, c);
                  },
                ),
              ),
            ],
          ),
        ),

        // Thanh thao tác dưới đáy Bước 2 (Chặn nếu có chip lạ, hoàn tất nếu đủ)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.bgCardElevated,
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: hasUnexpected
              ? ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    foregroundColor: const Color(0xFFEF4444),
                    side: const BorderSide(color: Color(0xFFEF4444), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.block, size: 18),
                  label: Text(
                    '⛔ CÓ ${_unexpectedTags.length} CHIP LẠ - VUI LÒNG LOẠI BỎ',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFFEF4444),
                        content: Text('⛔ Phát hiện ${_unexpectedTags.length} chip lạ ngoài đơn! Vui lòng nhặt hàng lạ khỏi xe Pallet trước khi lưu.'),
                      ),
                    );
                  },
                )
              : ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isBatchCompleted
                        ? const Color(0xFF0284C7)
                        : (allPalletsConfirmed
                            ? const Color(0xFF0284C7)
                            : (isComplete
                                ? const Color(0xFF10B981)
                                : (scannedCount > 0
                                    ? const Color(0xFF059669)
                                    : (_isScanning ? const Color(0xFFEF4444) : const Color(0xFF0284C7))))),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(_isBatchCompleted || allPalletsConfirmed
                          ? Icons.shelves
                          : (isComplete || scannedCount > 0
                              ? Icons.check_circle
                              : (_isScanning ? Icons.stop : Icons.sensors)),
                          size: 18),
                  label: Text(
                    _isSaving
                        ? 'ĐANG LƯU CSDL...'
                        : (_isBatchCompleted || allPalletsConfirmed
                            ? '📦 CẤT HÀNG VÀO KỆ'
                            : (isComplete
                                ? '✓ ĐÃ NHẬP KHO (${_palletOrder.isNotEmpty ? _palletOrder.length : 1} XE)'
                                : (scannedCount > 0
                                    ? 'LƯU & ĐỌC ĐỦ [$scannedCount/$expectedCount]'
                                    : (_isScanning ? 'DỪNG QUÉT RFID' : 'BÓP CÒ HOẶC BẤM ĐỂ QUÉT')))),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: (_isBatchCompleted || allPalletsConfirmed)
                      ? () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => PdaPutawayScreen(
                                initialCartonOrPalletBarcode: _lastPassedPallet ?? _palletController.text.trim(),
                              ),
                            ),
                          );
                          if (mounted) _checkIfPutawayCompletedAndClear();
                        }
                      : ((scannedCount > 0 && !_isSaving)
                          ? _confirmGoodsReceiveAtGate
                          : (_isSaving ? null : _toggleScan)),
                ),
        ),
      ],
    );
  }

  // ---------- BANNER THÔNG BÁO XE HOÀN THÀNH TỰ ĐỘNG CHUYỂN TIẾP (CHUẨN DESKTOP) ----------
  Widget _buildPassSuccessBanner(EyeCareColors c) {
    if (_lastPassedPallet == null) return const SizedBox.shrink();
    final hasNext = _lastNextPallet != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF10B981), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '✓ XE $_lastPassedPallet ĐÃ ĐỐI SOÁT ĐỦ ($_lastPassedCount SP)',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  hasNext
                      ? '⚡ Tự động chuyển xe $_lastNextPallet • Bóp cò để quét tiếp'
                      : '✓ Đã hoàn tất toàn bộ • Sẵn sàng cất lên kệ',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0284C7),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PdaPutawayScreen(
                    initialCartonOrPalletBarcode: _lastPassedPallet,
                  ),
                ),
              );
              if (mounted) _checkIfPutawayCompletedAndClear();
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.shelves, size: 14),
                SizedBox(width: 4),
                Text('CẤT KỆ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroProgressCard(
    EyeCareColors c,
    int scannedCount,
    int expectedCount,
    double progress,
    bool isComplete,
    bool hasUnexpected,
  ) {
    final Color progressColor = hasUnexpected
        ? const Color(0xFFEF4444)
        : (isComplete ? const Color(0xFF10B981) : const Color(0xFF0284C7));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: progressColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: progressColor.withValues(alpha: 0.12),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    _detectedPallet != null ? Icons.check_circle : Icons.sensors,
                    color: _detectedPallet != null ? const Color(0xFF10B981) : const Color(0xFF0284C7),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _detectedPallet != null
                        ? 'Pallet: ${_detectedPallet!.palletCode}'
                        : 'Pallet: ${_palletController.text.trim().toUpperCase()}',
                    style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: progressColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isComplete ? 'ĐÃ ĐỐI SOÁT ĐỦ' : '${(progress * 100).toInt()}%',
                  style: TextStyle(color: progressColor, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$scannedCount / $expectedCount',
            style: TextStyle(
              color: progressColor,
              fontSize: 32,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          Text(
            'SẢN PHẨM ĐÃ KHỚP ĐƠN HÀNG',
            style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: c.border,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnexpectedAlertBanner(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'CẢNH BÁO: CÓ ${_unexpectedTags.length} CHIP LẠ NGOÀI ĐƠN',
              style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHardwareScannerControls(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _isBatchCompleted ? const Color(0xFF10B981) : (_isScanning ? const Color(0xFFEF4444) : const Color(0xFF10B981)),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isBatchCompleted ? 'ĐÃ ĐỐI SOÁT ĐỦ (KHOÁ QUÉT)' : (_isScanning ? 'ĐANG QUÉT...' : 'SẴN SÀNG'),
                    style: TextStyle(
                      color: _isBatchCompleted ? const Color(0xFF10B981) : (_isScanning ? const Color(0xFFEF4444) : const Color(0xFF10B981)),
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              InkWell(
                onTap: () {
                  setState(() => _uhf.filterDuplicates = !_uhf.filterDuplicates);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: _uhf.filterDuplicates ? const Color(0xFF10B981).withValues(alpha: 0.15) : c.border,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Lọc trùng: ${_uhf.filterDuplicates ? "BẬT" : "TẮT"}',
                    style: TextStyle(
                      color: _uhf.filterDuplicates ? const Color(0xFF10B981) : c.textSecondary,
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    backgroundColor: c.bgCardElevated,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.refresh, size: 16, color: Color(0xFF0284C7)),
                  label: Text(
                    'Làm Mới Quét',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                  onPressed: _clearScannedList,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isBatchCompleted ? const Color(0xFF10B981) : (_isScanning ? const Color(0xFFEF4444) : const Color(0xFF0284C7)),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: Icon(_isBatchCompleted ? Icons.check_circle : (_isScanning ? Icons.stop : Icons.play_arrow), size: 18),
                  label: Text(
                    _isBatchCompleted ? 'Đã Đủ 100%' : (_isScanning ? 'Dừng Quét' : 'Bắt Đầu Quét'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                  ),
                  onPressed: _isBatchCompleted ? null : _toggleScan,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChips(int matchedCount, int expectedCount, int unexpCount) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _buildFilterChip('ALL', 'Tất cả (${expectedCount + unexpCount})', const Color(0xFF0284C7)),
          const SizedBox(width: 6),
          _buildFilterChip('MATCHED', '✓ Khớp ($matchedCount)', const Color(0xFF10B981)),
          const SizedBox(width: 6),
          _buildFilterChip('PENDING', '⏳ Chưa quét (${expectedCount - matchedCount})', const Color(0xFF64748B)),
          if (unexpCount > 0) ...[
            const SizedBox(width: 6),
            _buildFilterChip('UNEXPECTED', '⚠️ Chip lạ ($unexpCount)', const Color(0xFFEF4444)),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterChip(String key, String label, Color color) {
    final isSelected = _activeFilter == key;
    return InkWell(
      onTap: () => setState(() => _activeFilter = key),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 1),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildVerificationRowTile(Map<String, dynamic> row, EyeCareColors c) {
    final type = row['type'] as String;
    final isMatched = type == 'MATCHED';
    final isPending = type == 'PENDING';

    final Color badgeColor = isMatched
        ? const Color(0xFF10B981)
        : (isPending ? const Color(0xFF64748B) : const Color(0xFFEF4444));

    final IconData badgeIcon = isMatched
        ? Icons.check_circle
        : (isPending ? Icons.schedule : Icons.warning_amber_rounded);

    final String statusLabel = isMatched
        ? 'ĐÃ KHỚP'
        : (isPending ? 'CHƯA QUÉT' : 'CHIP LẠ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(badgeIcon, color: badgeColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        '${row["sku"]} • ${row["name"]}',
                        style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(color: badgeColor, fontSize: 9.5, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (row['box'] != null && row['box'] != '--') ...[
                      Text('Thùng: ${row["box"]} • ', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                    ],
                    Expanded(
                      child: Text(
                        'EPC: ${row["epc"]}',
                        style: TextStyle(color: c.textSecondary, fontFamily: 'monospace', fontSize: 10),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
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

  // ---------- THỰC HIỆN HOÀN TẤT NHẬP KHO ----------

  Future<void> _confirmGoodsReceiveAtGate() async {
    // 1. Kiểm tra chip lạ ngoài đơn
    if (_unexpectedTags.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Không thể hoàn tất khi còn chip lạ! Hãy kiểm tra và loại bỏ khỏi xe Pallet.'),
        ),
      );
      return;
    }

    // 2. Tính toán tổng expected và scanned của toàn bộ file
    final validPalletEpcs = _palletEpcMap.values
        .where((e) => e != null && e.isNotEmpty && e != '--')
        .map((e) => e!.trim().toUpperCase())
        .toSet();
    final allExpected = {..._selectedEpcs, ...validPalletEpcs};
    final expectedCount = allExpected.length;
    final scannedCount = _scannedTags.keys
        .where((epc) => allExpected.contains(epc.toUpperCase()))
        .length;

    if (scannedCount < expectedCount) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _eyeCare.colors.bgCard,
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B)),
              SizedBox(width: 8),
              Text('Chưa đối soát đủ số lượng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          content: Text(
            'Hệ thống mới quét được $scannedCount / $expectedCount chip (còn thiếu ${expectedCount - scannedCount} chip).\n\nBạn có chắc chắn muốn hoàn tất nhập kho toàn bộ đơn không?',
            style: TextStyle(color: _eyeCare.colors.textPrimary, fontSize: 13),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Quét tiếp'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Vẫn hoàn tất', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    setState(() => _isSaving = true);
    try {
      if (_isScanning) _stopScan();

      // 3. Phân chia theo từng xe Pallet và lưu vào CSDL
      final targetPallets = _palletOrder.isNotEmpty
          ? _palletOrder.toList()
          : [(_activePalletCode ?? (_palletController.text.trim().isNotEmpty ? _palletController.text.trim().toUpperCase() : 'PALLET-01'))];

      int totalItemsAssigned = 0;
      for (final pCode in targetPallets) {
        final palletExpectedEpcs = _epcsByPallet[pCode] ?? {};
        final List<String> scannedItemsForPallet;
        if (palletExpectedEpcs.isNotEmpty) {
          scannedItemsForPallet = _scannedTags.keys
              .where((e) => palletExpectedEpcs.contains(e.toUpperCase()))
              .toList();
        } else {
          scannedItemsForPallet = _scannedTags.keys
              .where((e) => _selectedEpcs.contains(e.toUpperCase()))
              .toList();
        }

        // Gán các Item vào Pallet tương ứng
        await _repo.assignItemsToPallet(
          palletCode: pCode,
          rfidEpc: _palletEpcMap[pCode],
          itemEpcs: scannedItemsForPallet,
        );

        // Xác nhận Handheld Inbound (trạng thái waitingPutaway)
        await _repo.confirmHandheldInbound(
          orderNo: _selectedOrder?.orderNo,
          palletCode: pCode,
          locationId: null,
          scannedEpcs: scannedItemsForPallet,
          performedBy: _repo.resolveUserFullName(null, defaultRole: 'handheld'),
        );

        _confirmedPallets.add(pCode);
        totalItemsAssigned += scannedItemsForPallet.length;
      }

      // Cập nhật trạng thái đơn hoàn tất nếu đã đọc đủ toàn bộ
      if (_selectedOrder != null) {
        _selectedOrder!.status = InboundOrderStatus.completed;
      }

      if (!mounted) return;

      setState(() {
        _lastPassedPallet = targetPallets.join(', ');
        _lastPassedCount = totalItemsAssigned;
        _lastNextPallet = null;
        _autoConfirmedThisSession = true;
        _isBatchCompleted = true;
        // Đảm bảo toàn bộ thẻ dự kiến đều có trong danh sách đã quét để luôn hiển thị 100% (Đủ và Tích Xanh)
        for (final epc in _selectedEpcs) {
          final cleanEpc = epc.trim().toUpperCase();
          _scannedTags.putIfAbsent(cleanEpc, () => TagInfo(epc: cleanEpc, count: 1, rssi: '-50'));
        }
        for (final pEpc in _palletEpcMap.values.whereType<String>()) {
          final cleanPEpc = pEpc.trim().toUpperCase();
          if (cleanPEpc.isNotEmpty) {
            _scannedTags.putIfAbsent(cleanPEpc, () => TagInfo(epc: cleanPEpc, count: 1, rssi: '-50'));
          }
        }
        _unexpectedTags.clear();
        _detectedPallet = null;
      });

      _uhf.stopInventory();
      _saveSessionToCache();
      if (_uhf.hapticEnabled) HapticFeedback.heavyImpact();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('✓ Đã hoàn tất nhập kho $scannedCount/$expectedCount chip (${targetPallets.length} xe chờ cất kệ)'),
          duration: const Duration(seconds: 4),
          action: SnackBarAction(
            label: 'CẤT KỆ',
            textColor: Colors.white,
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => PdaPutawayScreen(
                    initialCartonOrPalletBarcode: targetPallets.first,
                  ),
                ),
              );
              if (mounted) _checkIfPutawayCompletedAndClear();
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi khi lưu nhập kho: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// Tự động kiểm tra nếu toàn bộ hàng hóa trong đợt nạp đã cất lên kệ kho (status == inStock)
  /// thì dọn sạch danh sách nạp file và thông báo thành công.
  void _checkIfPutawayCompletedAndClear() {
    if (!_isBatchCompleted || _selectedEpcs.isEmpty) return;

    bool allInStock = true;
    for (final epc in _selectedEpcs) {
      final item = _repo.items.where((i) => i.epc.trim().toUpperCase() == epc.trim().toUpperCase()).firstOrNull;
      if (item == null || item.status != ItemStatus.inStock) {
        allInStock = false;
        break;
      }
    }

    if (allInStock) {
      _clearImportedBatchAfterPutaway();
    }
  }

  void _clearImportedBatchAfterPutaway() {
    setState(() {
      _receiptCartons.clear();
      _selectedCartons.clear();
      _pendingLoadedOrderNos.clear();
      _selectedOrder = null;
      _selectedEpcs.clear();
      _scannedTags.clear();
      _unexpectedTags.clear();
      _detectedPallet = null;
      _wizardStep = 1;
      _epcsByPallet.clear();
      _palletEpcMap.clear();
      _palletOrder.clear();
      _activePalletCode = null;
      _scannedTagsByPallet.clear();
      _confirmedPallets.clear();
      _lastPassedPallet = null;
      _lastPassedCount = 0;
      _lastNextPallet = null;
      _isBatchCompleted = false;
      _autoConfirmedThisSession = false;
    });
    InboundActiveSession.clear();
    _uhf.clearTags();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF10B981),
        content: Text('🎉 Nhập hàng thành công! Đã cất toàn bộ hàng lên kệ kho.'),
        duration: Duration(seconds: 4),
      ),
    );
  }


  // Hộp thoại lựa chọn: Nạp File Đơn PO (.xlsx, .csv) hoặc Chọn đơn PO trên hệ thống
  void _showInboundPoOptionsDialog() {
    final c = _eyeCare.colors;
    showModalBottomSheet(
      context: context,
      backgroundColor: c.bgCardElevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.receipt_long, color: c.rfidCyan, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'NHẬP TỪ PO (ĐƠN MUA HÀNG)',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: c.rfidCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.file_upload_outlined, color: c.rfidCyan, size: 20),
                ),
                title: Text('Nạp File Đơn PO (.xlsx, .csv)', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('Chọn file Excel / CSV đơn PO trên máy PDA', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickAndLoadPoFile();
                },
              ),
              Divider(color: c.border, height: 1),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.cloud_download_outlined, color: Color(0xFF10B981), size: 20),
                ),
                title: Text('Chọn Đơn PO Trên Hệ Thống', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text('Danh sách đơn nhập kho đang chờ trên Supabase Cloud', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                onTap: () {
                  Navigator.pop(ctx);
                  _showSelectInboundOrderDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------- CHỌN ĐƠN NHẬP KHO TRỰC TIẾP TỪ SUPABASE CLOUD ----------

  Future<void> _selectInboundOrder(InboundOrder order) async {
    _invalidateDetailedItemsCache();
    _receiptCartons.clear();
    _selectedCartons.clear();
    _pendingLoadedOrderNos.clear();
    _scannedTags.clear();
    _unexpectedTags.clear();
    _isBatchCompleted = false;
    _autoConfirmedThisSession = false;

    _selectedOrder = order;
    _palletController.text = 'PALLET-${order.orderNo}';

    var items = _getOrderItems(order);
    if (items.isEmpty && order.details.isNotEmpty) {
      await _ensureItemsForOrder(order);
      items = _getOrderItems(order);
    }

    _selectedEpcs.clear();
    _epcsByPallet.clear();
    _palletEpcMap.clear();
    _palletOrder.clear();
    _scannedTagsByPallet.clear();
    _confirmedPallets.clear();

    final palletCode = order.orderNo;
    for (var it in items) {
      if (it.epc.isNotEmpty) {
        _selectedEpcs.add(it.epc.trim().toUpperCase());
      }
      final pCode = it.palletId ?? palletCode;
      _epcsByPallet.putIfAbsent(pCode, () => <String>{}).add(it.epc.trim().toUpperCase());
      if (!_palletOrder.contains(pCode)) _palletOrder.add(pCode);
    }

    if (_selectedEpcs.isEmpty && order.details.isNotEmpty) {
      int seq = 1;
      final cleanOrder = order.orderNo.replaceAll(RegExp(r'[^A-Za-z0-9]'), '');
      for (final d in order.details) {
        for (int q = 0; q < d.requiredQty; q++) {
          final epc = '$cleanOrder${seq.toString().padLeft(4, '0')}'.toUpperCase();
          final pCode = 'THUNG-${((seq - 1) ~/ 10) + 1}';
          _selectedEpcs.add(epc);
          _epcsByPallet.putIfAbsent(pCode, () => <String>{}).add(epc);
          if (!_palletOrder.contains(pCode)) _palletOrder.add(pCode);
          seq++;
        }
      }
    }

    _activePalletCode = _palletOrder.isNotEmpty ? _palletOrder.first : null;
    _invalidateDetailedItemsCache();
    _saveSessionToCache();

    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('✓ Đã nạp đơn ${order.orderNo} (${_selectedEpcs.length} sản phẩm)'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showSelectInboundOrderDialog() {
    final c = _eyeCare.colors;
    final orders = _repo.inboundOrders
        .where((o) => o.status != InboundOrderStatus.completed)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCardElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: c.rfidCyan, size: 22),
            const SizedBox(width: 8),
            Text(
              'CHỌN ĐƠN NHẬP KHO',
              style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: SizedBox(
          width: 340,
          child: orders.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Không có đơn nhập kho nào đang chờ trên Supabase Cloud.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                  itemBuilder: (ctx, idx) {
                    final o = orders[idx];
                    final totalQty = o.details.fold(0, (s, d) => s + d.requiredQty);
                    final isCurrent = _selectedOrder?.orderNo == o.orderNo;
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              o.orderNo,
                              style: TextStyle(
                                color: isCurrent ? c.rfidCyan : c.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: c.rfidCyan.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'ĐANG CHỌN',
                                style: TextStyle(color: c.rfidCyan, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                      subtitle: Text(
                        '${o.sourceSupplier} • $totalQty sản phẩm',
                        style: TextStyle(color: c.textSecondary, fontSize: 11),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
                            tooltip: 'Xóa đơn này',
                            onPressed: () {
                              Navigator.pop(ctx);
                              _confirmDeleteSingleOrder(o);
                            },
                          ),
                          Icon(Icons.arrow_forward_ios, size: 14, color: c.textSecondary),
                        ],
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _selectInboundOrder(o);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('ĐÓNG', style: TextStyle(color: c.textSecondary)),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteSingleOrder(InboundOrder ord) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _eyeCare.colors.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _eyeCare.colors.border),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 22),
            SizedBox(width: 8),
            Text('Xóa đơn hàng?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn xóa đơn ${ord.orderNo} khỏi CSDL SQLite & Supabase Cloud?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('XÓA ĐƠN', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      if (_selectedOrder?.orderNo == ord.orderNo) {
        _selectedOrder = null;
        _receiptCartons.clear();
        _selectedCartons.clear();
        _selectedEpcs.clear();
        _scannedTags.clear();
        _unexpectedTags.clear();
        _wizardStep = 1;
        _epcsByPallet.clear();
        _palletEpcMap.clear();
        _palletOrder.clear();
        _activePalletCode = null;
        _scannedTagsByPallet.clear();
        _confirmedPallets.clear();
        _detectedPallet = null;
        _isBatchCompleted = false;
        _autoConfirmedThisSession = false;
        InboundActiveSession.clear();
        _invalidateDetailedItemsCache();
      }

      await _repo.deleteInboundOrder(ord.orderNo);
      await _supabaseSync.syncNow();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 2),
            content: Text('✓ Đã xóa đơn ${ord.orderNo} khỏi CSDL & Cloud'),
          ),
        );
      }
    } catch (e) {
      debugPrint('Lỗi khi xóa đơn: $e');
    }
  }

  Widget _buildEmptyStateOrOrderList(EyeCareColors c) {
    final pendingOrders = _repo.inboundOrders
        .where((o) => o.status != InboundOrderStatus.completed)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (pendingOrders.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_outlined, size: 50, color: c.textSecondary.withValues(alpha: 0.5)),
              const SizedBox(height: 12),
              Text(
                'Chưa có dữ liệu hàng nhập',
                style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Không có đơn nhập kho nào đang chờ trên Supabase Cloud.\nVui lòng bấm [LÀM MỚI] để đồng bộ hoặc bấm [NHẬP HÀNG ▾] để tạo đơn.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.rfidCyan,
                  side: BorderSide(color: c.rfidCyan),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.sync, size: 16),
                label: const Text('ĐỒNG BỘ TỪ CLOUD', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: _handleSyncReload,
              ),
            ],
          ),
        ),
      );
    }

    // Khi có đơn nhập đang chờ: Hiển thị danh sách thẻ đơn hàng để người dùng chạm chọn ngay!
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          color: c.bgDeep,
          child: Row(
            children: [
              Icon(Icons.assignment_outlined, size: 16, color: c.rfidCyan),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'ĐƠN CHỜ NHẬP (${pendingOrders.length})',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'Chạm để chọn đơn',
                style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontStyle: FontStyle.italic),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            itemCount: pendingOrders.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final ord = pendingOrders[index];
              final totalQty = ord.details.fold(0, (sum, d) => sum + d.requiredQty);
              final statusText = ord.status == InboundOrderStatus.newOrder
                  ? 'MỚI TẠO'
                  : (ord.status == InboundOrderStatus.waitingPutaway ? 'CHỜ CẤT KỆ' : 'ĐANG NHẬP');
              final statusColor = ord.status == InboundOrderStatus.newOrder
                  ? c.rfidCyan
                  : const Color(0xFFF59E0B);

              return InkWell(
                onTap: () => _selectInboundOrder(ord),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: c.bgCardElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                          color: c.rfidCyan.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.receipt_long, color: c.rfidCyan, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    ord.orderNo,
                                    style: TextStyle(
                                      color: c.textPrimary,
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: statusColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: statusColor.withValues(alpha: 0.6), width: 0.8),
                                  ),
                                  child: Text(
                                    statusText,
                                    style: TextStyle(
                                      color: statusColor,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'NCC: ${ord.sourceSupplier}',
                              style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Số lượng: $totalQty sản phẩm (${ord.details.length} SKU)',
                              style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Xóa đơn này',
                        icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444), size: 20),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        onPressed: () => _confirmDeleteSingleOrder(ord),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: c.rfidCyan,
                          foregroundColor: const Color(0xFF2C251E),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          elevation: 0,
                        ),
                        onPressed: () => _selectInboundOrder(ord),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('CHỌN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                            SizedBox(width: 2),
                            Icon(Icons.arrow_forward_ios, size: 10),
                          ],
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
    );
  }
}

