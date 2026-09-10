import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/tag_info.dart';
import '../models/wms_models.dart';
import '../services/uhf_service.dart';
import '../services/warehouse_repository.dart';
import '../services/supabase_sync_service.dart';
import '../theme/eye_care_theme.dart';
import '../widgets/hardware_status_appbar.dart';
import '../services/excel_import_service.dart';
import 'pda/pda_putaway_screen.dart';

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
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _selectedEpcs = {};
  String _searchQuery = '';

  // Bước 2 State
  final Map<String, TagInfo> _scannedTags = {};
  final Map<String, TagInfo> _unexpectedTags = {};
  Pallet? _detectedPallet;
  bool _isScanning = false;
  bool _isSaving = false;
  bool _autoConfirmedThisSession = false; // Chặn auto-confirm trùng lặp trong 1 phiên quét
  String _activeFilter = 'ALL'; // 'ALL', 'MATCHED', 'PENDING', 'UNEXPECTED'

  StreamSubscription<TagInfo>? _tagSubscription;
  StreamSubscription<bool>? _triggerSubscription;
  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onStateChange);
    _repo.addListener(_onStateChange);

    _uhf.setScanMode(PdaScanMode.rfid);
    _initSelectedOrder();
    _initHardwareListeners();

    // Đồng bộ nhanh từ Cloud Supabase nếu có mạng
    Future.microtask(() async {
      await _supabaseSync.syncNow();
      if (mounted) setState(() {});
    });
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _initSelectedOrder() {
    if (_repo.inboundOrders.isNotEmpty) {
      if (widget.initialOrderNo != null) {
        _selectedOrder = _repo.inboundOrders.where((o) => o.orderNo == widget.initialOrderNo).firstOrNull ??
            _repo.inboundOrders.firstWhere(
              (o) => o.status == InboundOrderStatus.newOrder || o.status == InboundOrderStatus.waitingPutaway,
              orElse: () => _repo.inboundOrders.first,
            );
      } else {
        _selectedOrder = _repo.inboundOrders.firstWhere(
          (o) => o.status == InboundOrderStatus.newOrder || o.status == InboundOrderStatus.waitingPutaway,
          orElse: () => _repo.inboundOrders.first,
        );
      }
    }

    if (_selectedOrder != null) {
      _loadOrderItemsAndSelectAll(_selectedOrder!);
    }
  }

  List<Item> _getOrderItems(InboundOrder? order) {
    if (order == null) return [];
    return _repo.items.where((i) =>
      i.orderNo == order.orderNo || i.orderNo == order.inboundOrderId
    ).toList();
  }

  void _loadOrderItemsAndSelectAll(InboundOrder order) {
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

  void _initHardwareListeners() {
    _tagSubscription = _uhf.onTagRead.listen((tag) {
      if (!mounted) return;
      _handleIncomingTag(tag);
    });

    _triggerSubscription = _uhf.onTriggerStateChanged.listen((isPressed) {
      if (!mounted) return;
      if (isPressed && !_isScanning) {
        _startScan();
      } else if (!isPressed && _isScanning) {
        _stopScan();
      }
    });
  }

  void _scheduleUiRefresh() {
    if (_uiRefreshTimer?.isActive ?? false) return;
    _uiRefreshTimer = Timer(const Duration(milliseconds: 60), () {
      if (mounted) setState(() {});
    });
  }

  void _handleIncomingTag(TagInfo tag) {
    final cleanEpc = tag.epc.trim().toUpperCase();
    if (cleanEpc.isEmpty) return;

    // 1. Nhận diện xe Pallet từ thẻ quét nếu trùng với Pallet trong CSDL
    final matchedPallet = _repo.findPalletByRfid(cleanEpc);
    if (matchedPallet != null) {
      if (_detectedPallet?.palletCode != matchedPallet.palletCode) {
        setState(() {
          _detectedPallet = matchedPallet;
          _palletController.text = matchedPallet.palletCode;
          _unexpectedTags.remove(cleanEpc);
        });
        if (_uhf.hapticEnabled) HapticFeedback.mediumImpact();
      }
      return;
    }

    // 2. Nếu đang ở Bước 2: Đối soát chip sản phẩm
    if (_wizardStep == 2) {
      if (_selectedEpcs.contains(cleanEpc)) {
        if (!_scannedTags.containsKey(cleanEpc)) {
          _scannedTags[cleanEpc] = tag;
          _unexpectedTags.remove(cleanEpc);
          if (_uhf.hapticEnabled) HapticFeedback.selectionClick();
          _scheduleUiRefresh();

          // ★ AUTO-CONFIRM: Khi quét liên tục, nếu đã đọc đủ 100% và không có chip lạ
          //   → Tự động xác nhận nhập kho ngay lập tức mà không cần dừng quét
          _checkAndAutoConfirm();
        }
      } else {
        // Kiểm tra xem có phải mã Pallet đang chọn hay không
        final currentPallet = _palletController.text.trim().toUpperCase();
        if (currentPallet.isNotEmpty && cleanEpc == currentPallet) {
          return;
        }

        if (!_unexpectedTags.containsKey(cleanEpc)) {
          _unexpectedTags[cleanEpc] = tag;
          if (_uhf.hapticEnabled) HapticFeedback.heavyImpact();
          _scheduleUiRefresh();
        }
      }
    }
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    _tagSubscription?.cancel();
    _triggerSubscription?.cancel();
    _eyeCare.removeListener(_onStateChange);
    _repo.removeListener(_onStateChange);
    _palletController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _startScan() {
    if (_isScanning) return;
    HapticFeedback.mediumImpact();
    setState(() => _isScanning = true);
    _uhf.startInventory();
  }

  void _stopScan() {
    if (!_isScanning) return;
    HapticFeedback.mediumImpact();
    setState(() => _isScanning = false);
    _uhf.stopInventory();
  }

  void _toggleScan() {
    if (_isScanning) {
      _stopScan();
    } else {
      _startScan();
    }
  }

  void _clearScannedList() {
    HapticFeedback.selectionClick();
    setState(() {
      _scannedTags.clear();
      _unexpectedTags.clear();
      _detectedPallet = null;
      _autoConfirmedThisSession = false; // Reset cờ auto-confirm khi làm mới
      _uhf.clearTags();
    });
  }

  /// Kiểm tra điều kiện tự động xác nhận nhập kho khi đang quét liên tục:
  /// - Đã quét đủ 100% số lượng mã hàng khai báo
  /// - Tất cả mã EPC quét được đều trùng khớp với danh sách khai báo
  /// - Không có bất kỳ chip lạ nào ngoài đơn
  /// - Chưa auto-confirm trong phiên quét hiện tại
  void _checkAndAutoConfirm() {
    if (_autoConfirmedThisSession) return; // Đã auto-confirm rồi
    if (_isSaving) return; // Đang lưu CSDL
    if (_unexpectedTags.isNotEmpty) return; // Có chip lạ → không auto

    final expectedCount = _selectedEpcs.length;
    if (expectedCount == 0) return;

    final scannedCount = _scannedTags.keys
        .where((epc) => _selectedEpcs.contains(epc.toUpperCase()))
        .length;

    if (scannedCount >= expectedCount) {
      // ★ ĐỌC ĐỦ 100% + KHÔNG CÓ CHIP LẠ → Auto-confirm ngay!
      _autoConfirmedThisSession = true;
      // Cho UI kịp cập nhật thanh tiến độ 100% trước khi chạy confirm
      Future.delayed(const Duration(milliseconds: 150), () {
        if (!mounted) return;
        if (_isSaving) return;
        _confirmGoodsReceiveAtGate();
      });
    }
  }

  // ---------- HELPER METHODS NẠP FILE & LÀM MỚI (ĐỒNG BỘ DESKTOP) ----------

  List<Map<String, dynamic>> _getStep1DetailedItems() {
    if (_receiptCartons.isNotEmpty) {
      final List<Map<String, dynamic>> flat = [];
      for (var cBox in _receiptCartons) {
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
      return flat;
    }

    if (_selectedOrder != null) {
      final items = _getOrderItems(_selectedOrder);
      if (items.isNotEmpty) {
        return items.map((it) => {
          'boxCode': it.palletId ?? '--',
          'sku': it.sku,
          'productName': it.productName,
          'serial': it.epc,
        }).toList();
      }
    }

    final pendingItems = _repo.items.where((i) => i.status == ItemStatus.pendingInbound).toList();
    if (pendingItems.isNotEmpty) {
      return pendingItems.map((it) => {
        'boxCode': it.palletId ?? '--',
        'sku': it.sku,
        'productName': it.productName,
        'serial': it.epc,
      }).toList();
    }

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

  Future<void> _handleRefreshOrClearFile() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final messenger = ScaffoldMessenger.of(context);
      final hadLoadedData = _receiptCartons.isNotEmpty ||
          _pendingLoadedOrderNos.isNotEmpty ||
          _selectedEpcs.isNotEmpty;

      // 1. Dọn dẹp đơn hàng nháp và chip tạm trong CSDL
      await _cleanupPendingDraftOrders();

      // 2. Dừng quét và xóa sạch dữ liệu trên giao diện
      _uhf.stopInventory();
      _isScanning = false;

      _receiptCartons.clear();
      _selectedCartons.clear();
      _selectedEpcs.clear();
      _scannedTags.clear();
      _unexpectedTags.clear();
      _searchController.clear();
      _searchQuery = '';
      _wizardStep = 1;

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
            explicitItems.add(Item(
              itemId: 'ITEM-${now.millisecondsSinceEpoch}-$itemSeq',
              productId: sBarcode,
              sku: sBarcode,
              productName: sName,
              serialNumber: sSerial,
              epc: sSerial,
              status: ItemStatus.pendingInbound,
              orderNo: inboundOrderNo,
              palletId: effectivePallet,
              cartonCode: cartonBox != null && cartonBox.isNotEmpty ? cartonBox : null,
              supplier: sSupplier,
              inboundTime: now,
              inboundBy: 'Thủ kho PDA',
            ));
            itemSeq++;
          }
        } else {
          final serials = (c['serials'] as List<dynamic>?)?.map((e) => e.toString().trim()).toList() ?? [];
          final sSupplier = (c['supplier'] ?? 'Nhà cung cấp tổng hợp').toString().trim();
          final effectivePallet = (palletCode != null && palletCode.isNotEmpty) ? palletCode : null;
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
              palletId: effectivePallet,
              cartonCode: cartonBox != null && cartonBox.isNotEmpty ? cartonBox : null,
              supplier: sSupplier,
              inboundTime: now,
              inboundBy: 'Thủ kho PDA',
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
      if (mounted) setState(() => _isImporting = false);
    }
  }

  // ---------- GIAO DIỆN CHÍNH ----------

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: const HardwareStatusAppBar(title: '📥 NHẬP KHO RFID (PDA)'),
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
        ? (waitingOrders.isNotEmpty ? waitingOrders.first.orderNo : 'Xe Pallet')
        : palletSet.join(', ');

    final totalCount = waitingPutawayItems.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF10B981), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.1),
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
              color: const Color(0xFF10B981).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Text(
                      'ĐÃ ĐỌC ĐỦ TỪ DESKTOP',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    SizedBox(width: 6),
                    Text(
                      '• Chờ cất vào kệ',
                      style: TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Xe: $palletText ($totalCount SP)',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              visualDensity: VisualDensity.compact,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              elevation: 1,
            ),
            icon: const Icon(Icons.shelves, size: 15),
            label: const Text(
              'CẤT KỆ',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const PdaPutawayScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // =======================================================
  // BƯỚC 1: BẢNG DỮ LIỆU THÙNG HÀNG & NẠP FILE (CHUẨN DESKTOP)
  // =======================================================

  Widget _buildStep1CartonSelection(EyeCareColors c) {
    final allDetailedItems = _getStep1DetailedItems();

    final query = _searchQuery.trim().toUpperCase();
    final filteredDetails = query.isEmpty
        ? allDetailedItems
        : allDetailedItems.where((item) {
            final boxCode = (item['boxCode'] ?? '').toString().toUpperCase();
            final sku = (item['sku'] ?? '').toString().toUpperCase();
            final prodName = (item['productName'] ?? '').toString().toUpperCase();
            final serial = (item['serial'] ?? '').toString().toUpperCase();
            return boxCode.contains(query) || sku.contains(query) || prodName.contains(query) || serial.contains(query);
          }).toList();

    final allSelected = allDetailedItems.isNotEmpty &&
        allDetailedItems.every((item) => _selectedEpcs.contains((item['serial'] ?? '').toString().trim().toUpperCase()));

    return Column(
      children: [
        // Thanh công cụ NHẬP HÀNG & LÀM MỚI (Kéo Nhập Hàng sang bên trái)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: c.bgDeep,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Nút Nhập Hàng (Dropdown menu kéo sang bên trái)
                PopupMenuButton<String>(
                  enabled: !_isImporting,
                  tooltip: 'Chọn nguồn nạp file',
                  offset: const Offset(0, 38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: c.border),
                  ),
                  color: c.bgCardElevated,
                  onSelected: (value) {
                    if (_isImporting) return;
                    if (value == 'excel') {
                      _pickAndLoadLiveExcelFile();
                    } else if (value == 'po') {
                      _pickAndLoadPoFile();
                    } else if (value == 'manual') {
                      _showCreateOrderDialog();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'excel',
                      child: Row(
                        children: [
                          const Icon(Icons.table_chart, color: Color(0xFF10B981), size: 18),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'File Thùng Hàng (.xlsx)',
                                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              Text(
                                'Carton Box, SKU, Serial/EPC',
                                style: TextStyle(color: c.textSecondary, fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'po',
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long, color: c.rfidCyan, size: 18),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'File Nhập PO (Đơn Mua Hàng)',
                                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              Text(
                                'Đơn PO: Mã PO, SKU, Số lượng',
                                style: TextStyle(color: c.textSecondary, fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'manual',
                      child: Row(
                        children: [
                          const Icon(Icons.post_add, color: Color(0xFF0284C7), size: 18),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Tạo Đơn Thủ Công',
                                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              Text(
                                'Nhập mã đơn, SKU, số lượng thủ công',
                                style: TextStyle(color: c.textSecondary, fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _isImporting ? c.rfidCyan.withValues(alpha: 0.5) : c.rfidCyan,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: c.rfidCyan.withValues(alpha: 0.25),
                          blurRadius: 4,
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
                          const Icon(Icons.file_download_outlined, size: 16, color: Color(0xFF2C251E)),
                        const SizedBox(width: 5),
                        Text(
                          _isImporting ? 'ĐANG NẠP...' : 'NHẬP HÀNG',
                          style: const TextStyle(
                            color: Color(0xFF2C251E),
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF2C251E)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Nút Làm Mới (Xóa file đã nạp để chọn lại file khác)
                Tooltip(
                  message: 'Xóa dữ liệu file đã nạp để chọn lại file mới',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(Icons.refresh, size: 15, color: c.textPrimary),
                    label: Text(
                      'LÀM MỚI',
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                    onPressed: _isImporting ? null : _handleRefreshOrClearFile,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Dòng Tiêu đề: DANH SÁCH HÀNG NHẬP (chuyển xuống dưới)
        Container(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
          color: c.bgDeep,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'DANH SÁCH HÀNG NHẬP',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    letterSpacing: 0.5,
                  ),
                ),
                if (allDetailedItems.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '(${allDetailedItems.length} sản phẩm)',
                    style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ),

        // Sub-toolbar: Tìm kiếm & Chọn tất cả
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: c.bgDeep,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  style: TextStyle(color: c.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Tìm theo Thùng, SKU, Tên SP, EPC...',
                    hintStyle: TextStyle(color: c.textSecondary.withValues(alpha: 0.5), fontSize: 11),
                    prefixIcon: Icon(Icons.search, size: 15, color: c.textSecondary),
                    filled: true,
                    fillColor: c.bgCard,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    if (allSelected) {
                      _selectedEpcs.clear();
                      _selectedCartons.clear();
                    } else {
                      for (var it in allDetailedItems) {
                        final s = (it['serial'] ?? '').toString().trim().toUpperCase();
                        if (s.isNotEmpty) _selectedEpcs.add(s);
                      }
                      for (var cBox in _receiptCartons) {
                        final b = (cBox['cartonBox'] ?? cBox['code'] ?? '').toString().trim();
                        if (b.isNotEmpty) _selectedCartons.add(b);
                      }
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    color: allSelected ? c.rfidCyan.withValues(alpha: 0.15) : c.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: allSelected ? c.rfidCyan : c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        allSelected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 16,
                        color: allSelected ? c.rfidCyan : c.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        allSelected ? 'Bỏ chọn' : 'Chọn hết',
                        style: TextStyle(
                          color: allSelected ? c.rfidCyan : c.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // BẢNG DỮ LIỆU THÙNG HÀNG & SẢN PHẨM (KHI NẠP FILE SẼ HIỆN BẢNG NHƯ DESKTOP)
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
                          style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Vui lòng bấm nút [NHẬP HÀNG] ở trên để nạp file Excel hoặc file PO',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                )
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
                      width: 760, // Kích thước cố định khớp bảng desktop
                      child: Column(
                        children: [
                          // Table Header (như desktop)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: c.bgDeep,
                              border: Border(bottom: BorderSide(color: c.border)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 40,
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
                                              if (s.isNotEmpty) _selectedEpcs.add(s);
                                            }
                                            for (var cBox in _receiptCartons) {
                                              final b = (cBox['cartonBox'] ?? cBox['code'] ?? '').toString().trim();
                                              if (b.isNotEmpty) _selectedCartons.add(b);
                                            }
                                          } else {
                                            _selectedEpcs.clear();
                                            _selectedCartons.clear();
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                ),
                                SizedBox(
                                  width: 40,
                                  child: Text('STT', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 120,
                                  child: Text('MÃ THÙNG HÀNG', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 130,
                                  child: Text('MÃ SKU', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 180,
                                  child: Text('TÊN SẢN PHẨM / QUY CÁCH', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 160,
                                  child: Text('MÃ CHIP RFID (EPC)', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 90,
                                  child: Text('TRẠNG THÁI', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ),

                          // Table Rows (như desktop)
                          Expanded(
                            child: ListView.builder(
                              physics: const BouncingScrollPhysics(),
                              itemCount: filteredDetails.length,
                              itemBuilder: (context, index) {
                                final item = filteredDetails[index];
                                final boxCode = (item['boxCode'] ?? 'THUNG').toString();
                                final sku = (item['sku'] ?? '--').toString();
                                final prodName = (item['productName'] ?? 'Sản phẩm').toString();
                                final serial = (item['serial'] ?? '').toString();
                                final isSelected = _selectedEpcs.contains(serial.toUpperCase());

                                return InkWell(
                                  onTap: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedEpcs.remove(serial.toUpperCase());
                                      } else {
                                        _selectedEpcs.add(serial.toUpperCase());
                                      }
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                                          width: 40,
                                          child: Center(
                                            child: Checkbox(
                                              value: isSelected,
                                              activeColor: c.rfidCyan,
                                              checkColor: const Color(0xFF2C251E),
                                              onChanged: (val) {
                                                setState(() {
                                                  if (val == true) {
                                                    _selectedEpcs.add(serial.toUpperCase());
                                                  } else {
                                                    _selectedEpcs.remove(serial.toUpperCase());
                                                  }
                                                });
                                              },
                                            ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 40,
                                          child: Text(
                                            '${index + 1}',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(color: c.textSecondary, fontSize: 11),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 120,
                                          child: Text(
                                            boxCode,
                                            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 130,
                                          child: Text(
                                            sku,
                                            style: TextStyle(
                                              color: c.textSecondary,
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.w600,
                                              fontSize: 11,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 180,
                                          child: Text(
                                            prodName,
                                            style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 160,
                                          child: Text(
                                            serial,
                                            style: const TextStyle(
                                              color: Color(0xFF0284C7),
                                              fontFamily: 'monospace',
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10.5,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 90,
                                          child: Center(
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'CHỜ QUÉT',
                                                style: TextStyle(
                                                  color: Color(0xFF10B981),
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                ),
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
                ),
        ),

        // Bottom Bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: c.bgCardElevated,
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'ĐÃ CHỌN: ${_selectedEpcs.length} / ${allDetailedItems.length} SP',
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    Text(
                      'Xe Pallet: ${_palletController.text.trim().isEmpty ? "PALLET-01" : _palletController.text.trim().toUpperCase()}',
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedEpcs.isNotEmpty ? const Color(0xFF0284C7) : c.border,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text(
                    'TIẾP TỤC: QUÉT RFID ➜',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                onPressed: _selectedEpcs.isEmpty
                    ? () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Vui lòng chọn ít nhất 1 sản phẩm để nhập kho!')),
                        );
                      }
                    : () {
                        if (_palletController.text.trim().isEmpty) {
                          _palletController.text = 'PALLET-01';
                        }
                        _autoConfirmedThisSession = false; // Reset cờ auto-confirm khi bắt đầu phiên quét mới
                        setState(() => _wizardStep = 2);
                      },
              ),
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
    final expectedCount = _selectedEpcs.length;
    final scannedCount = _scannedTags.keys.where((epc) => _selectedEpcs.contains(epc.toUpperCase())).length;
    final isComplete = expectedCount > 0 && scannedCount >= expectedCount;
    final progress = expectedCount > 0 ? (scannedCount / expectedCount).clamp(0.0, 1.0) : 0.0;
    final hasUnexpected = _unexpectedTags.isNotEmpty;

    final allDetails = _getStep1DetailedItems();
    final detailMap = {for (var d in allDetails) (d['serial'] ?? '').toString().toUpperCase(): d};

    // Lọc danh sách theo filter chip
    final List<Map<String, dynamic>> displayList = [];
    if (_activeFilter == 'ALL' || _activeFilter == 'MATCHED') {
      for (var epc in _selectedEpcs) {
        if (_scannedTags.containsKey(epc)) {
          final it = detailMap[epc];
          displayList.add({
            'type': 'MATCHED',
            'epc': epc,
            'sku': it?['sku'] ?? 'SKU',
            'name': it?['productName'] ?? 'Sản phẩm',
            'box': it?['boxCode'] ?? '--',
            'tag': _scannedTags[epc],
          });
        }
      }
    }
    if (_activeFilter == 'ALL' || _activeFilter == 'PENDING') {
      for (var epc in _selectedEpcs) {
        if (!_scannedTags.containsKey(epc)) {
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
                      'Xe: ${_palletController.text.trim().isEmpty ? "PALLET-01" : _palletController.text.trim().toUpperCase()}',
                      style: const TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, size: 18, color: c.textSecondary),
                tooltip: 'Làm mới quét',
                onPressed: _clearScannedList,
              ),
            ],
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              children: [
                // 1. Thẻ Hero Tiến Độ Quét (Counter & Progress Bar lớn)
                _buildHeroProgressCard(c, scannedCount, expectedCount, progress, isComplete, hasUnexpected),
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

                // 5. Danh sách thẻ đã quét / đối soát
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayList.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final row = displayList[index];
                    return _buildVerificationRowTile(row, c);
                  },
                ),
              ],
            ),
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
                    backgroundColor: isComplete
                        ? const Color(0xFF10B981)
                        : (scannedCount > 0 ? const Color(0xFF059669) : c.border),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle, size: 18),
                  label: Text(
                    _isSaving
                        ? 'ĐANG LƯU CSDL...'
                        : (isComplete
                            ? 'XÁC NHẬN ĐỌC ĐỦ VÀ NHẬP KHO'
                            : (scannedCount > 0
                                ? 'LƯU & ĐỌC ĐỦ [$scannedCount/$expectedCount]'
                                : 'XÁC NHẬN NHẬP KHO')),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: (scannedCount > 0 && !_isSaving) ? _confirmGoodsReceiveAtGate : null,
                ),
        ),
      ],
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
                        ? 'Xe Pallet: ${_detectedPallet!.palletCode}'
                        : 'Xe: ${_palletController.text.trim().toUpperCase()}',
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'CẢNH BÁO: CÓ ${_unexpectedTags.length} CHIP LẠ NGOÀI ĐƠN!',
                  style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  'Phát hiện thẻ RFID không khớp với đơn hàng. Hãy kiểm tra & loại bỏ trước khi hoàn tất.',
                  style: TextStyle(color: c.textPrimary, fontSize: 11),
                ),
              ],
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
                      color: _isScanning ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isScanning ? 'ĐANG QUÉT RFID...' : 'SẴN SÀNG QUÉT (CÒ PDA)',
                    style: TextStyle(
                      color: _isScanning ? const Color(0xFFEF4444) : const Color(0xFF10B981),
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
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isScanning ? const Color(0xFFEF4444) : const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(_isScanning ? Icons.stop : Icons.sensors, size: 20),
              label: Text(
                _isScanning ? 'DỪNG QUÉT RFID' : 'BẮT ĐẦU QUÉT RFID (HOẶC BÓP CÒ PDA)',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
              ),
              onPressed: _toggleScan,
            ),
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
    final expectedCount = _selectedEpcs.length;
    final scannedCount = _scannedTags.keys.where((epc) => _selectedEpcs.contains(epc.toUpperCase())).length;
    final palletCode = _palletController.text.trim().toUpperCase();

    if (_unexpectedTags.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Không thể hoàn tất khi còn chip lạ! Hãy kiểm tra và loại bỏ khỏi xe Pallet.'),
        ),
      );
      return;
    }

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
            'Hệ thống mới quét được $scannedCount / $expectedCount sản phẩm (còn thiếu ${expectedCount - scannedCount} SP).\n\nBạn có chắc chắn muốn hoàn tất nhập kho cho xe $palletCode không?',
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

      final validEpcs = _scannedTags.keys.where((epc) => _selectedEpcs.contains(epc.toUpperCase())).toList();

      // 1. Gán các Item vào Pallet
      await _repo.assignItemsToPallet(
        palletCode: palletCode,
        itemEpcs: validEpcs,
      );

      // 2. Xác nhận Handheld Inbound (cập nhật trạng thái item, đơn PO & giao dịch)
      await _repo.confirmHandheldInbound(
        orderNo: _selectedOrder?.orderNo,
        palletCode: palletCode,
        locationId: null, // Lưu tạm chờ xếp kệ
        scannedEpcs: validEpcs,
        performedBy: 'Thủ kho PDA',
      );

      // Cập nhật trạng thái đơn hoàn tất nếu đọc đủ
      if (scannedCount >= expectedCount && _selectedOrder != null) {
        _selectedOrder!.status = InboundOrderStatus.completed;
      }

      if (!mounted) return;

      // Hiển thị Dialog Thành Công
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: _eyeCare.colors.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Color(0xFF10B981), width: 1.5)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, size: 48, color: Color(0xFF10B981)),
              ),
              const SizedBox(height: 14),
              Text(
                'XÁC NHẬN NHẬP KHO THÀNH CÔNG!',
                textAlign: TextAlign.center,
                style: TextStyle(color: _eyeCare.colors.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'Đã lưu $scannedCount/$expectedCount sản phẩm lên xe $palletCode.\nHàng ở trạng thái Chờ xếp kệ và sẵn sàng chuyển lên kệ lưu trữ.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _eyeCare.colors.textSecondary, fontSize: 12),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.shelves, size: 16),
                  label: const Text('CẤT HÀNG VÀO KỆ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const PdaPutawayScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _eyeCare.colors.border),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _scannedTags.clear();
                          _unexpectedTags.clear();
                          _wizardStep = 1;
                        });
                      },
                      child: const Text('VỀ CHỌN ĐƠN', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      onPressed: () {
                        Navigator.pop(ctx);
                        setState(() {
                          _scannedTags.clear();
                          _unexpectedTags.clear();
                          _detectedPallet = null;
                        });
                        _uhf.clearTags();
                      },
                      child: const Text('QUÉT TIẾP XE', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
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

  // Dialog Tạo Đơn Nhập PO nhanh trên PDA
  void _showCreateOrderDialog() {
    final orderNoController = TextEditingController();
    final supplierController = TextEditingController();
    final skuController = TextEditingController();
    final nameController = TextEditingController();
    final qtyController = TextEditingController(text: '10');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _eyeCare.colors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: _eyeCare.colors.border)),
        title: const Row(
          children: [
            Icon(Icons.post_add, color: Color(0xFF0284C7), size: 22),
            SizedBox(width: 8),
            Text('Tạo Đơn Nhập Hàng', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: orderNoController,
                decoration: const InputDecoration(labelText: 'Mã đơn nhập', hintText: 'Ví dụ: NK-001'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: supplierController,
                decoration: const InputDecoration(labelText: 'Nhà cung cấp', hintText: 'Tên nhà cung cấp...'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: skuController,
                decoration: const InputDecoration(labelText: 'Mã SKU', hintText: 'Ví dụ: SKU-001'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Tên hàng hóa', hintText: 'Tên sản phẩm...'),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Số lượng nhập', hintText: '10'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () async {
              final orderNo = orderNoController.text.trim();
              final supplier = supplierController.text.trim();
              final sku = skuController.text.trim();
              final name = nameController.text.trim();
              final qty = int.tryParse(qtyController.text.trim()) ?? 10;

              if (orderNo.isEmpty || sku.isEmpty) return;

              final newOrder = InboundOrder(
                inboundOrderId: 'INB-${DateTime.now().millisecondsSinceEpoch}',
                orderNo: orderNo,
                sourceSupplier: supplier.isNotEmpty ? supplier : 'Nhà cung cấp',
                status: InboundOrderStatus.newOrder,
                createdAt: DateTime.now(),
                details: [
                  InboundOrderDetail(
                    productId: 'PROD-${DateTime.now().millisecondsSinceEpoch}',
                    sku: sku,
                    productName: name.isNotEmpty ? name : 'Sản phẩm $sku',
                    requiredQty: qty,
                  ),
                ],
              );

              await _repo.addInboundOrder(newOrder, autoGenerateEpcs: true);
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {
                _selectedOrder = newOrder;
                _loadOrderItemsAndSelectAll(newOrder);
              });
            },
            child: const Text('LƯU ĐƠN NHẬP', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
