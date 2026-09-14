import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/tag_info.dart';
import '../models/wms_models.dart';
import '../services/auth_service.dart';
import '../services/excel_import_service.dart';
import '../services/supabase_sync_service.dart';
import '../services/tower_light_service.dart';
import '../services/uhf_service.dart';
import '../services/warehouse_repository.dart';
import '../theme/eye_care_theme.dart';
import '../widgets/hardware_status_appbar.dart';

/// Mô hình chi tiết từng sản phẩm cần xuất kho qua cổng / tay cầm RFID
class _PendingOutboundItem {
  final String sku;
  final String cartonCode;
  final String palletCode;
  final String supplier;
  final String customer;
  final String productName;
  final String palletEpc;
  final String epc;
  final bool isInStock;
  final String locationCode;
  final DateTime? inboundTime;
  final int fifoPriority;
  final String? fifoWarning;

  _PendingOutboundItem({
    required this.sku,
    required this.cartonCode,
    required this.palletCode,
    this.supplier = '--',
    required this.customer,
    required this.productName,
    required this.palletEpc,
    required this.epc,
    this.isInStock = true,
    this.locationCode = '--',
    this.inboundTime,
    this.fifoPriority = 1,
    this.fifoWarning,
  });
}

/// Mô hình đơn xuất kho nạp từ file / CSDL chờ đối soát xuất kho
class _PendingOutboundOrder {
  final String orderNo;
  final String customer;
  final List<_PendingOutboundItem> items;
  final Map<String, String?> pallets; // palletCode -> palletEpc
  final String fileName;
  final bool isStockSufficient;
  final int shortageCount;
  final Map<String, int> shortageBySku;

  _PendingOutboundOrder({
    required this.orderNo,
    required this.customer,
    required this.items,
    required this.pallets,
    required this.fileName,
    this.isStockSufficient = true,
    this.shortageCount = 0,
    this.shortageBySku = const {},
  });
}

/// Màn hình Xuất Kho RFID trên máy PDA:
/// - Luồng hoạt động & giao diện đồng bộ hoàn toàn với Xuất Kho Desktop
/// - Quản lý nạp file qua nút [XUẤT HÀNG ▼] trên thanh công cụ
/// - Khi chưa nạp file: Màn hình chờ Cổng RFID tiếp nhận hàng xuất
/// - Khi đã nạp file:
///   + 3 ô chỉ số: ĐÃ QUÉT (xanh), THIẾU (vàng), LẠ (đỏ)
///   + Bảng danh sách hàng xuất 9 cột chuẩn Desktop
///   + Thanh điều khiển dưới cùng với 3 nút giống xuất kho desktop:
///     1. Nút Làm Mới Quét
///     2. Thời gian quét: [5s] [10s] [Liên tục]
///     3. Nút BẮT ĐẦU QUÉT (BÓP CÒ) / DỪNG QUÉT
///     + Nút XÁC NHẬN XUẤT KHO khi quét đủ 100%
class OutboundScreen extends StatefulWidget {
  final String? initialOrderNo;
  const OutboundScreen({super.key, this.initialOrderNo});

  @override
  State<OutboundScreen> createState() => _OutboundScreenState();
}

class _OutboundScreenState extends State<OutboundScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final AuthService _auth = AuthService();
  final SupabaseSyncService _supabaseSync = SupabaseSyncService();
  final ExcelImportService _excelService = ExcelImportService();
  final TowerLightService _towerLight = TowerLightService();

  // Đơn xuất kho đang chờ đối soát qua tay cầm / cổng PDA
  _PendingOutboundOrder? _pendingOutboundOrder;

  // Danh sách chip RFID đã quét đối soát
  final Map<String, TagInfo> _gateScannedTags = {};
  bool _isScanning = false;
  Timer? _uiRefreshTimer;

  bool _isImporting = false;
  bool _isSaving = false;

  StreamSubscription<TagInfo>? _tagSubscription;
  StreamSubscription<bool>? _triggerSubscription;
  DateTime? _lastTriggerPressTime;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onStateChange);
    _repo.addListener(_onStateChange);
    _auth.addListener(_onStateChange);

    _uhf.setScanMode(PdaScanMode.rfid);
    _initHardwareListeners();
    _initInitialData();

    Future.microtask(() async {
      await _supabaseSync.syncNow();
      if (mounted) setState(() {});
    });
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _initInitialData() {
    if (widget.initialOrderNo != null && _repo.outboundOrders.isNotEmpty) {
      final order = _repo.outboundOrders.where((o) =>
          o.poNo == widget.initialOrderNo || o.outboundOrderId == widget.initialOrderNo).firstOrNull;
      if (order != null) {
        _loadOutboundOrderFromDb(order);
      }
    }
  }

  void _initHardwareListeners() {
    _tagSubscription = _uhf.onTagRead.listen((tag) {
      if (!mounted) return;
      _handleIncomingGateTag(tag);
    });

    _triggerSubscription = _uhf.onTriggerStateChanged.listen((isPressed) {
      if (!mounted) return;
      if (isPressed) {
        _lastTriggerPressTime = DateTime.now();
        if (_pendingOutboundOrder == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFFF59E0B),
              content: Text('⚠️ Vui lòng bấm [XUẤT HÀNG] ở góc trên để nạp file trước khi quét!'),
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        if (_isScanning) {
          _stopGateScan();
        } else {
          _startGateScan();
        }
      } else {
        // Nhả cò: nếu người dùng GIỮ cò lâu (>= 300ms) thì nhả ra là tự động dừng quét.
        // Nếu chỉ bóp nhấp nhanh (< 300ms) thì tiếp tục quét, bóp lần nữa mới dừng.
        final pressDurationMs = _lastTriggerPressTime != null
            ? DateTime.now().difference(_lastTriggerPressTime!).inMilliseconds
            : 0;
        if (pressDurationMs >= 300 && _isScanning) {
          _stopGateScan();
        }
      }
    });

    HardwareKeyboard.instance.addHandler(_handleHardwareKeyEvent);
  }

  bool _handleHardwareKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      final key = event.logicalKey;
      final isScanKey = key == LogicalKeyboardKey.f1 ||
          key == LogicalKeyboardKey.f2 ||
          key == LogicalKeyboardKey.f3 ||
          key == LogicalKeyboardKey.f4 ||
          key == LogicalKeyboardKey.f5 ||
          key == LogicalKeyboardKey.f6;
      if (isScanKey) {
        _toggleGateScan();
        return true;
      }
    }
    return false;
  }

  void _scheduleUiRefresh() {
    if (_uiRefreshTimer?.isActive ?? false) return;
    _uiRefreshTimer = Timer(const Duration(milliseconds: 60), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _uhf.stopInventory();
    HardwareKeyboard.instance.removeHandler(_handleHardwareKeyEvent);
    _tagSubscription?.cancel();
    _triggerSubscription?.cancel();
    _uiRefreshTimer?.cancel();
    _eyeCare.removeListener(_onStateChange);
    _repo.removeListener(_onStateChange);
    _auth.removeListener(_onStateChange);
    super.dispose();
  }

  // ---------- XỬ LÝ QUÉT & ĐỐI SOÁT CHIP THỜI GIAN THỰC ----------
  void _handleIncomingGateTag(TagInfo tag) {
    if (_pendingOutboundOrder == null) return;

    final epc = tag.epc.trim().toUpperCase();
    if (_uhf.filterDuplicates && _gateScannedTags.containsKey(epc)) return;

    _gateScannedTags[epc] = tag;

    final order = _pendingOutboundOrder!;
    final expectedEpcs = order.items.map((i) => i.epc.toUpperCase()).toSet();
    final validPalletEpcs = order.pallets.values.where((e) => e != null && e.isNotEmpty && e != '--').map((e) => e!.toUpperCase()).toSet();
    final totalExpected = expectedEpcs.length + validPalletEpcs.length;
    final scannedMatching = _gateScannedTags.keys.where((e) => expectedEpcs.contains(e) || validPalletEpcs.contains(e)).length;
    final unexpected = _gateScannedTags.keys.where((e) => !expectedEpcs.contains(e) && !validPalletEpcs.contains(e)).toList();

    if (unexpected.isNotEmpty) {
      _towerLight.triggerWarningRed(
        withBuzzer: true,
        reason: 'CẢNH BÁO: Phát hiện ${unexpected.length} chip lạ ngoài danh sách xuất kho!',
      );
    } else {
      // Đối soát tồn kho và thứ tự FIFO cho chip vừa quét
      final item = order.items.where((i) => i.epc.toUpperCase() == epc).firstOrNull;
      if (item != null) {
        if (!item.isInStock) {
          _towerLight.triggerWarningRed(
            withBuzzer: true,
            reason: 'CẢNH BÁO TỒN KHO: Mã chip $epc (SKU: ${item.sku}) không có trong kho!',
          );
        } else {
          // Kiểm tra xem có lô cũ hơn cùng SKU chưa quét không
          final olderUnscanned = order.items.where((i) =>
              i.sku.toUpperCase() == item.sku.toUpperCase() &&
              i.isInStock &&
              i.fifoPriority < item.fifoPriority &&
              !_gateScannedTags.containsKey(i.epc.toUpperCase())
          ).toList();

          if (olderUnscanned.isNotEmpty) {
            final oldest = olderUnscanned.first;
            _towerLight.triggerWarningRed(
              withBuzzer: false,
              reason: 'LƯU Ý FIFO: Quét lô mới (FIFO #${item.fifoPriority}) của ${item.sku}. Cần lấy lô cũ trước: kệ ${oldest.locationCode} (FIFO #${oldest.fifoPriority})!',
            );
          }
        }
      }

      if (totalExpected > 0 && scannedMatching >= totalExpected) {
        _towerLight.triggerPass(
          reason: 'ĐỦ HÀNG XUẤT KHO: $scannedMatching/$totalExpected chip đã thông qua tay cầm!',
        );
      }
    }

    _scheduleUiRefresh();
  }

  void _toggleGateScan() {
    if (_pendingOutboundOrder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFF59E0B),
          content: Text('⚠️ Vui lòng bấm nút [XUẤT HÀNG] ở góc trên để nạp file trước khi quét!'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    if (_isScanning) {
      _stopGateScan();
    } else {
      _startGateScan();
    }
  }

  void _startGateScan() {
    if (_pendingOutboundOrder == null) return;
    _uhf.startInventory();
    setState(() {
      _isScanning = true;
    });
  }

  void _stopGateScan() {
    _uhf.stopInventory();
    if (mounted) {
      setState(() {
        _isScanning = false;
      });
    }
  }

  void _clearGateScan() {
    HapticFeedback.selectionClick();
    _stopGateScan();
    setState(() {
      _gateScannedTags.clear();
    });
    _uhf.clearTags();
    _towerLight.turnOffAll();
  }

  // ---------- NẠP FILE XUẤT KHO THÙNG (.XLSX) ----------
  Future<void> _pickAndLoadOutboundExcelFile() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final result = await _excelService.pickAndParseGoodsReceiveExcel();
      if (result == null) return;

      final now = DateTime.now();
      final orderNo = 'XK-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';

      final Map<String, String?> pallets = {};
      final List<_PendingOutboundItem> items = [];

      for (var c in result.cartons) {
        final palletCode = c['palletCode']?.toString().trim();
        final palletEpc = c['palletEpc']?.toString().trim();
        if (palletCode != null && palletCode.isNotEmpty) {
          pallets[palletCode] = (palletEpc != null && palletEpc.isNotEmpty) ? palletEpc : pallets[palletCode];
        }

        final cartonBox = c['cartonBox']?.toString().trim() ?? '--';
        final serialItems = (c['serialItems'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList();

        if (serialItems != null && serialItems.isNotEmpty) {
          for (var sItem in serialItems) {
            final sPallet = (sItem['pallet']?.toString().trim() ?? palletCode ?? '--');
            final sPalletEpc = (sItem['palletEpc']?.toString().trim() ?? palletEpc ?? '--');
            final sSerial = sItem['serial'].toString().trim().toUpperCase();
            final sBarcode = sItem['barcode']?.toString().trim() ?? c['productCode']?.toString().trim() ?? '--';
            final sName = sItem['name']?.toString().trim() ?? c['productName']?.toString().trim() ?? '--';
            final sSupplier = (sItem['supplier'] ?? c['supplier'] ?? '--').toString().trim();
            final sCustomer = (sItem['customer'] ?? c['customer'] ?? result.customerName ?? 'Xuất Kho').toString().trim();

            if (sPallet != '--' && sPalletEpc != '--') {
              pallets[sPallet] = sPalletEpc;
            }

            items.add(_PendingOutboundItem(
              sku: sBarcode,
              cartonCode: cartonBox,
              palletCode: sPallet,
              supplier: sSupplier,
              customer: sCustomer,
              productName: sName,
              palletEpc: sPalletEpc,
              epc: sSerial,
            ));
          }
        } else {
          final serials = (c['serials'] as List<dynamic>?)?.map((e) => e.toString().trim().toUpperCase()).toList() ?? [];
          final sBarcode = c['productCode']?.toString().trim() ?? '--';
          final sName = c['productName']?.toString().trim() ?? '--';
          final sSupplier = (c['supplier'] ?? '--').toString().trim();
          final sCustomer = (c['customer'] ?? result.customerName ?? 'Xuất Kho').toString().trim();

          for (var s in serials) {
            items.add(_PendingOutboundItem(
              sku: sBarcode,
              cartonCode: cartonBox,
              palletCode: palletCode ?? '--',
              supplier: sSupplier,
              customer: sCustomer,
              productName: sName,
              palletEpc: palletEpc ?? '--',
              epc: s,
            ));
          }
        }
      }

      if (items.isEmpty) {
        throw Exception('Không tìm thấy danh sách mã hàng / chip hợp lệ trong tệp!');
      }

      // Đối soát tồn kho thực tế và kiểm tra vị trí kệ & thứ tự FIFO
      final requestedPayload = items.map((i) => {
        'sku': i.sku,
        'cartonCode': i.cartonCode,
        'palletCode': i.palletCode,
        'supplier': i.supplier,
        'customer': i.customer,
        'productName': i.productName,
        'palletEpc': i.palletEpc,
        'epc': i.epc,
      }).toList();

      final validation = _repo.validateOutboundInventoryAndFifo(requestedItems: requestedPayload);

      final List<_PendingOutboundItem> validatedItems = validation.items.map((vi) => _PendingOutboundItem(
        sku: vi.sku,
        cartonCode: vi.cartonCode,
        palletCode: vi.palletCode,
        supplier: vi.supplier,
        customer: vi.customer,
        productName: vi.productName,
        palletEpc: vi.palletEpc,
        epc: vi.epc,
        isInStock: vi.isInStock,
        locationCode: vi.locationCode,
        inboundTime: vi.inboundTime,
        fifoPriority: vi.fifoPriority,
        fifoWarning: vi.fifoWarning,
      )).toList();

      final detectedCustomer = (result.customerName != null && result.customerName!.isNotEmpty)
          ? result.customerName!
          : (validatedItems.isNotEmpty && validatedItems.first.customer.isNotEmpty && validatedItems.first.customer != 'Xuất Kho' && validatedItems.first.customer != 'Khách mua xuất kho'
              ? validatedItems.first.customer
              : 'Xuất Kho');

      _clearGateScan();
      setState(() {
        _pendingOutboundOrder = _PendingOutboundOrder(
          orderNo: orderNo,
          customer: detectedCustomer,
          items: validatedItems,
          pallets: pallets,
          fileName: result.fileName,
          isStockSufficient: validation.isStockSufficient,
          shortageCount: validation.shortageCount,
          shortageBySku: validation.shortageBySku,
        );
      });

      if (mounted) {
        if (!validation.isStockSufficient) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFEF4444),
              duration: const Duration(seconds: 5),
              content: Text('⚠️ CẢNH BÁO TỒN KHO: Không đủ hàng tồn để xuất (Thiếu ${validation.shortageCount} món)! Đã khóa xác nhận xuất.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text('✓ Đã nạp thành công ${validatedItems.length} chip xuất kho (Đủ tồn kho & đã định vị kệ)'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Lỗi nạp file xuất hàng: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  // ---------- NẠP FILE ĐƠN XUẤT HÀNG (SO / PO) ----------
  Future<void> _pickAndLoadOutboundPoFile() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final rows = await _excelService.pickAndParseBatchOrdersExcel();
      if (rows == null || rows.isEmpty) return;

      final Map<String, String?> pallets = {};
      String orderNo = 'PO-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      String customer = 'Xuất Kho';
      final List<Map<String, dynamic>> rawRequests = [];

      for (var r in rows) {
        final po = (r['orderNo'] ?? '').toString().trim();
        if (po.isNotEmpty) orderNo = po;
        final cust = (r['customer'] ?? r['supplier'] ?? '').toString().trim();
        if (cust.isNotEmpty) customer = cust;

        final sku = (r['sku'] ?? '--').toString().trim();
        final qty = (r['quantity'] as int?) ?? 1;
        final prodName = (r['productName'] ?? 'Sản phẩm xuất kho').toString().trim();
        final rowEpc = (r['epc'] ?? '').toString().trim().toUpperCase();

        if (rowEpc.isNotEmpty) {
          rawRequests.add({
            'sku': sku,
            'cartonCode': '--',
            'palletCode': '--',
            'customer': customer,
            'productName': prodName,
            'palletEpc': '--',
            'epc': rowEpc,
          });
        } else {
          for (int i = 0; i < qty; i++) {
            rawRequests.add({
              'sku': sku,
              'cartonCode': '--',
              'palletCode': '--',
              'customer': customer,
              'productName': prodName,
              'palletEpc': '--',
              'epc': '--',
            });
          }
        }
      }

      if (rawRequests.isEmpty) {
        throw Exception('Không tìm thấy danh sách mã hàng / chip hợp lệ trong file PO!');
      }

      final validation = _repo.validateOutboundInventoryAndFifo(requestedItems: rawRequests);
      final List<_PendingOutboundItem> validatedItems = validation.items.map((vi) => _PendingOutboundItem(
        sku: vi.sku,
        cartonCode: vi.cartonCode,
        palletCode: vi.palletCode,
        supplier: vi.supplier,
        customer: vi.customer.isNotEmpty && vi.customer != '--' ? vi.customer : customer,
        productName: vi.productName,
        palletEpc: vi.palletEpc,
        epc: vi.epc,
        isInStock: vi.isInStock,
        locationCode: vi.locationCode,
        inboundTime: vi.inboundTime,
        fifoPriority: vi.fifoPriority,
        fifoWarning: vi.fifoWarning,
      )).toList();

      _clearGateScan();
      setState(() {
        _pendingOutboundOrder = _PendingOutboundOrder(
          orderNo: orderNo,
          customer: customer,
          items: validatedItems,
          pallets: pallets,
          fileName: 'File PO: $orderNo',
          isStockSufficient: validation.isStockSufficient,
          shortageCount: validation.shortageCount,
          shortageBySku: validation.shortageBySku,
        );
      });

      if (mounted) {
        if (!validation.isStockSufficient) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFEF4444),
              duration: const Duration(seconds: 5),
              content: Text('⚠️ CẢNH BÁO TỒN KHO: Đơn $orderNo thiếu ${validation.shortageCount} sản phẩm! Đã khóa xác nhận xuất.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text('✓ Đã nạp thành công đơn $orderNo (${validatedItems.length} SP - Đủ tồn kho)'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Lỗi nạp file PO: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  // ---------- CHỌN TỪ ĐƠN XUẤT CÓ SẴN TRONG CSDL ----------
  void _loadOutboundOrderFromDb(OutboundOrder order) {
    final Map<String, String?> pallets = {};
    final List<Map<String, dynamic>> rawRequests = [];

    for (final detail in order.details) {
      if (detail.epcList != null && detail.epcList!.isNotEmpty) {
        for (final epc in detail.epcList!) {
          rawRequests.add({
            'sku': detail.sku,
            'cartonCode': '--',
            'palletCode': '--',
            'customer': order.customer,
            'productName': detail.productName,
            'palletEpc': '--',
            'epc': epc,
          });
        }
      } else {
        for (int i = 0; i < detail.requiredQty; i++) {
          rawRequests.add({
            'sku': detail.sku,
            'cartonCode': '--',
            'palletCode': '--',
            'customer': order.customer,
            'productName': detail.productName,
            'palletEpc': '--',
            'epc': '--',
          });
        }
      }
    }

    final validation = _repo.validateOutboundInventoryAndFifo(requestedItems: rawRequests);
    final List<_PendingOutboundItem> validatedItems = validation.items.map((vi) => _PendingOutboundItem(
      sku: vi.sku,
      cartonCode: vi.cartonCode,
      palletCode: vi.palletCode,
      supplier: vi.supplier,
      customer: vi.customer.isNotEmpty && vi.customer != '--' ? vi.customer : order.customer,
      productName: vi.productName,
      palletEpc: vi.palletEpc,
      epc: vi.epc,
      isInStock: vi.isInStock,
      locationCode: vi.locationCode,
      inboundTime: vi.inboundTime,
      fifoPriority: vi.fifoPriority,
      fifoWarning: vi.fifoWarning,
    )).toList();

    _clearGateScan();
    setState(() {
      _pendingOutboundOrder = _PendingOutboundOrder(
        orderNo: order.poNo,
        customer: order.customer,
        items: validatedItems,
        pallets: pallets,
        fileName: 'Đơn xuất: ${order.poNo}',
        isStockSufficient: validation.isStockSufficient,
        shortageCount: validation.shortageCount,
        shortageBySku: validation.shortageBySku,
      );
    });

    if (mounted) {
      if (!validation.isStockSufficient) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 5),
            content: Text('⚠️ CẢNH BÁO TỒN KHO: Đơn ${order.poNo} thiếu ${validation.shortageCount} sản phẩm! Đã khóa xác nhận xuất.'),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('✓ Đã nạp đơn ${order.poNo} (${validatedItems.length} sản phẩm - Đủ tồn kho)'),
          ),
        );
      }
    }
  }

  void _showSelectOrderDialog() {
    final c = _eyeCare.colors;
    final orders = _repo.outboundOrders.where((o) => o.status != OutboundOrderStatus.shipped).toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCardElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: c.rfidCyan, size: 22),
            const SizedBox(width: 8),
            Text('CHỌN ĐƠN XUẤT KHO', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 320,
          child: orders.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Không có đơn xuất kho nào đang chờ.', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                  itemBuilder: (ctx, idx) {
                    final o = orders[idx];
                    final totalQty = o.details.fold(0, (s, d) => s + d.requiredQty);
                    return ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      title: Text(o.poNo, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('${o.customer} • $totalQty sản phẩm', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                      trailing: Icon(Icons.arrow_forward_ios, size: 14, color: c.textSecondary),
                      onTap: () {
                        Navigator.pop(ctx);
                        _loadOutboundOrderFromDb(o);
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

  // ---------- TẠO NHANH ĐƠN XUẤT ----------
  void _showCreateQuickOrderDialog() {
    final c = _eyeCare.colors;
    final poController = TextEditingController(text: 'XK-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}');
    final qtyController = TextEditingController(text: '1');
    final inStockSkus = _repo.items.where((i) => i.status == ItemStatus.inStock).map((i) => i.sku).toSet().toList();
    String? selectedSku = inStockSkus.firstOrNull;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: c.bgCardElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.post_add, color: c.rfidCyan, size: 22),
              const SizedBox(width: 8),
              Text('TẠO NHANH ĐƠN XUẤT', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: poController,
                style: TextStyle(color: c.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Mã Phiếu/Đơn Xuất',
                  labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: c.bgCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedSku,
                dropdownColor: c.bgCardElevated,
                decoration: InputDecoration(
                  labelText: 'Chọn SKU Cần Xuất',
                  labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: c.bgCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: inStockSkus.map((sku) {
                  final stockCount = _repo.items.where((i) => i.sku == sku && i.status == ItemStatus.inStock).length;
                  return DropdownMenuItem(
                    value: sku,
                    child: Text('$sku (Tồn: $stockCount)', style: TextStyle(color: c.textPrimary, fontSize: 12.5)),
                  );
                }).toList(),
                onChanged: (v) => setDlgState(() => selectedSku = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: c.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Số Lượng Cần Xuất',
                  labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: c.bgCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan, foregroundColor: const Color(0xFF2C251E)),
              onPressed: () {
                if (selectedSku == null) return;
                final qty = int.tryParse(qtyController.text.trim()) ?? 1;
                Navigator.pop(ctx);

                final List<Map<String, dynamic>> rawRequests = [];
                for (int i = 0; i < qty; i++) {
                  rawRequests.add({
                    'sku': selectedSku,
                    'cartonCode': '--',
                    'palletCode': '--',
                    'customer': 'Khách xuất kho',
                    'productName': 'Sản phẩm xuất kho',
                    'palletEpc': '--',
                    'epc': '--',
                  });
                }

                final validation = _repo.validateOutboundInventoryAndFifo(requestedItems: rawRequests);
                final List<_PendingOutboundItem> items = validation.items.map((vi) => _PendingOutboundItem(
                  sku: vi.sku,
                  cartonCode: vi.cartonCode,
                  palletCode: vi.palletCode,
                  supplier: vi.supplier,
                  customer: 'Khách xuất kho',
                  productName: vi.productName,
                  palletEpc: vi.palletEpc,
                  epc: vi.epc,
                  isInStock: vi.isInStock,
                  locationCode: vi.locationCode,
                  inboundTime: vi.inboundTime,
                  fifoPriority: vi.fifoPriority,
                  fifoWarning: vi.fifoWarning,
                )).toList();

                if (!validation.isStockSufficient) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('SKU "$selectedSku" không đủ hàng tồn kho (Thiếu ${validation.shortageCount} món)!')),
                  );
                }

                _clearGateScan();
                setState(() {
                  _pendingOutboundOrder = _PendingOutboundOrder(
                    orderNo: poController.text.trim(),
                    customer: 'Khách xuất kho',
                    items: items,
                    pallets: {},
                    fileName: 'Tạo nhanh: ${poController.text.trim()}',
                    isStockSufficient: validation.isStockSufficient,
                    shortageCount: validation.shortageCount,
                    shortageBySku: validation.shortageBySku,
                  );
                });
              },
              child: const Text('TẠO ĐƠN', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- XÁC NHẬN XUẤT KHO HOÀN TẤT & CẬP NHẬT KHO ----------
  Future<void> _confirmOutboundDelivery() async {
    if (_isSaving || _pendingOutboundOrder == null) return;
    final order = _pendingOutboundOrder!;

    if (!order.isStockSufficient || order.items.any((i) => !i.isInStock)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text('Không thể xuất kho: Kho không đủ hàng tồn (Thiếu ${order.shortageCount} sản phẩm)! Vui lòng kiểm tra lại tồn kho.'),
        ),
      );
      return;
    }

    final expectedEpcs = order.items.map((i) => i.epc.toUpperCase()).toSet();
    final validPalletEpcs = order.pallets.values.where((e) => e != null && e.isNotEmpty && e != '--').map((e) => e!.toUpperCase()).toSet();
    final totalExpected = expectedEpcs.length + validPalletEpcs.length;
    final scannedMatching = _gateScannedTags.keys.where((e) => expectedEpcs.contains(e) || validPalletEpcs.contains(e)).length;
    final unexp = _gateScannedTags.keys.where((e) => !expectedEpcs.contains(e) && !validPalletEpcs.contains(e)).toList();

    if (scannedMatching < totalExpected || unexp.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Không thể xuất kho: Chưa quét đủ mã pallet/hàng hoặc có chip lạ ngoài đơn!'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (_isScanning) _stopGateScan();

      final shippedCount = await _repo.confirmGateOutbound(
        poNo: order.orderNo,
        customer: order.customer,
        scannedEpcs: expectedEpcs.toList(),
        performedBy: _auth.currentUser?.fullName ?? 'Tay Cầm PDA Xuất Kho',
      );

      _towerLight.triggerPass(reason: 'HOÀN TẤT XUẤT KHO: $shippedCount sản phẩm đã đối soát thành công');
      await _supabaseSync.syncNow();

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _eyeCare.colors.bgCardElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF10B981), size: 24),
              SizedBox(width: 8),
              Text('XUẤT KHO THÀNH CÔNG', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          content: Text(
            'Đã xuất kho thành công $shippedCount sản phẩm theo chứng từ ${order.orderNo}.\nDữ liệu tồn kho đã được cập nhật.',
            style: TextStyle(color: _eyeCare.colors.textPrimary, fontSize: 13),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _pendingOutboundOrder = null;
                  _clearGateScan();
                });
              },
              child: const Text('ĐỒNG Ý'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            content: Text('Lỗi xác nhận xuất kho: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // =======================================================
  // GIAO DIỆN CHÍNH
  // =======================================================

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: const HardwareStatusAppBar(title: '📤 XUẤT KHO RFID (PDA)'),
      body: Column(
        children: [
          // 1. THANH CÔNG CỤ: [XUẤT HÀNG ▼], [LÀM MỚI], [XÓA HÀNG ĐỢI] (Thu gọn chuẩn PDA)
          _buildTopHeaderBar(c),

          // 2. NỘI DUNG CHÍNH: Màn hình chờ hoặc Bảng hàng hóa + 3 ô chỉ số + 3 nút điều khiển
          Expanded(
            child: _pendingOutboundOrder == null
                ? _buildIdleGateMonitor(c)
                : _buildActiveOutboundView(c),
          ),
        ],
      ),
    );
  }

  // ---------- 1. THANH CÔNG CỤ TRÊN CÙNG ----------
  Widget _buildTopHeaderBar(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: c.bgDeep,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // Nút Xuất Hàng (Menu popup gọn gàng màu cyan)
            PopupMenuButton<String>(
              enabled: !_isImporting,
              tooltip: 'Chọn nguồn nạp yêu cầu xuất',
              offset: const Offset(0, 34),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: c.border),
              ),
              color: c.bgCardElevated,
              onSelected: (value) {
                if (_isImporting) return;
                if (value == 'excel') {
                  _pickAndLoadOutboundExcelFile();
                } else if (value == 'po') {
                  _pickAndLoadOutboundPoFile();
                } else if (value == 'order') {
                  _showSelectOrderDialog();
                } else if (value == 'manual') {
                  _showCreateQuickOrderDialog();
                } else if (value == 'clear') {
                  setState(() {
                    _pendingOutboundOrder = null;
                    _clearGateScan();
                  });
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem<String>(
                  value: 'excel',
                  height: 38,
                  child: Row(
                    children: [
                      const Icon(Icons.table_chart, color: Color(0xFF10B981), size: 16),
                      const SizedBox(width: 8),
                      Text('File Thùng Hàng (.xlsx)', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'po',
                  height: 38,
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, color: c.rfidCyan, size: 16),
                      const SizedBox(width: 8),
                      Text('File Đơn Xuất Hàng (SO / PO)', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'order',
                  height: 38,
                  child: Row(
                    children: [
                      const Icon(Icons.inventory, color: Color(0xFFF59E0B), size: 16),
                      const SizedBox(width: 8),
                      Text('Chọn Đơn Xuất Có Sẵn', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem<String>(
                  value: 'manual',
                  height: 38,
                  child: Row(
                    children: [
                      const Icon(Icons.post_add, color: Color(0xFF0284C7), size: 16),
                      const SizedBox(width: 8),
                      Text('Tạo Nhanh Đơn Xuất', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                    ],
                  ),
                ),
                if (_pendingOutboundOrder != null) ...[
                  const PopupMenuDivider(),
                  PopupMenuItem<String>(
                    value: 'clear',
                    height: 38,
                    child: const Row(
                      children: [
                        Icon(Icons.delete_sweep_outlined, color: Color(0xFFEF4444), size: 16),
                        SizedBox(width: 8),
                        Text('Xóa Danh Sách Đang Chờ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11.5)),
                      ],
                    ),
                  ),
                ],
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
                      const Icon(Icons.file_upload_outlined, size: 14, color: Color(0xFF2C251E)),
                    const SizedBox(width: 4),
                    Text(
                      _isImporting ? 'ĐANG NẠP...' : 'XUẤT HÀNG',
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
              message: 'Làm mới & đồng bộ CSDL',
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
                onPressed: _isImporting ? null : () async {
                  await _repo.reloadFromSqlite();
                  await _supabaseSync.syncNow();
                  if (mounted) setState(() {});
                },
              ),
            ),

            // Nút Xóa Hàng Đợi (Thu gọn)
            if (_pendingOutboundOrder != null) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'Xóa danh sách đang chờ xuất',
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
                  onPressed: _isImporting
                      ? null
                      : () {
                          setState(() {
                            _pendingOutboundOrder = null;
                            _clearGateScan();
                          });
                        },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------- 2. MÀN HÌNH CHỜ QUÉT KHI CHƯA NẠP FILE (CHUẨN DESKTOP) ----------
  Widget _buildIdleGateMonitor(EyeCareColors c) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: c.rfidCyan.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.sensors, size: 50, color: c.rfidCyan),
            ),
            const SizedBox(height: 16),
            Text(
              'CỔNG RFID ĐANG SẴN SÀNG TIẾP NHẬN HÀNG XUẤT',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.3),
            ),
            const SizedBox(height: 10),
            Text(
              'Vui lòng bấm nút [XUẤT HÀNG] ở góc trên để tải file danh sách xuất kho vào hệ thống.\nSau khi nạp file, bạn có thể bóp cò tay cầm PDA để đối soát xuất hàng.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 3. GIAO DIỆN XUẤT HÀNG KHI ĐÃ NẠP FILE (CHUẨN DESKTOP) ----------
  Widget _buildActiveOutboundView(EyeCareColors c) {
    final order = _pendingOutboundOrder!;
    final expectedEpcs = order.items.map((i) => i.epc.toUpperCase()).toSet();
    final validPalletEpcs = order.pallets.values.where((e) => e != null && e.isNotEmpty && e != '--').map((e) => e!.toUpperCase()).toSet();

    final expectedCount = expectedEpcs.length + validPalletEpcs.length;
    final scannedCount = _gateScannedTags.keys.where((e) => expectedEpcs.contains(e) || validPalletEpcs.contains(e)).length;
    final missingCount = (expectedCount - scannedCount).clamp(0, expectedCount);
    final unexpList = _gateScannedTags.values.where((t) => !expectedEpcs.contains(t.epc.toUpperCase()) && !validPalletEpcs.contains(t.epc.toUpperCase())).toList();
    final unexpCount = unexpList.length;

    final isComplete = expectedCount > 0 && scannedCount >= expectedCount;

    return Column(
      children: [
        // Banner cảnh báo thiếu tồn kho (nếu có)
        if (!order.isStockSufficient) ...[
          Container(
            margin: const EdgeInsets.fromLTRB(10, 6, 10, 2),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFEF4444), width: 1.2),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'CẢNH BÁO TỒN KHO: Thiếu ${order.shortageCount} sản phẩm! Đã khóa nút xác nhận xuất.',
                    style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ],

        // 1. Ô TÊN KHÁCH HÀNG (TRÊN ĐẦU DANH SÁCH THEO YÊU CẦU)
        Container(
          margin: const EdgeInsets.fromLTRB(10, 6, 10, 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF0284C7).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.5), width: 1.2),
          ),
          child: Row(
            children: [
              const Icon(Icons.person_pin, size: 16, color: Color(0xFF0284C7)),
              const SizedBox(width: 8),
              const Text(
                'KHÁCH HÀNG:',
                style: TextStyle(
                  color: Color(0xFF0284C7),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  order.customer.isNotEmpty && order.customer != '--' && order.customer != 'Khách mua xuất kho' ? order.customer : 'Xuất Kho',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),

        // 2. Dòng Tiêu đề: DANH SÁCH HÀNG XUẤT
        Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
          color: c.bgDeep,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  'DANH SÁCH HÀNG XUẤT',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${order.items.length} sản phẩm)',
                  style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                ),
                if (order.fileName.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(
                    '• ${order.fileName}',
                    style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ),

        // 3 Ô CHỈ SỐ: ĐÃ QUÉT (xanh), THIẾU (vàng), LẠ (đỏ) - Đều nhau
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: _buildMetricBox(
                  label: 'ĐÃ QUÉT',
                  count: scannedCount,
                  color: const Color(0xFF10B981),
                  c: c,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricBox(
                  label: 'THIẾU',
                  count: missingCount,
                  color: const Color(0xFFF59E0B),
                  c: c,
                ),
              ),
              const SizedBox(width: 8),
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

        // BẢNG ĐỐI SOÁT XUẤT KHO PDA (CÓ VỊ TRÍ KỆ & ƯU TIÊN FIFO)
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: c.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 1080,
                  child: Column(
                    children: [
                      // Header bảng PDA
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: c.bgDeep,
                          border: Border(bottom: BorderSide(color: c.border)),
                        ),
                        child: Row(
                          children: [
                            SizedBox(width: 38, child: Text('STT', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                            const SizedBox(width: 6),
                            SizedBox(width: 90, child: Text('MÃ SKU', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                            const SizedBox(width: 6),
                            SizedBox(width: 90, child: Text('MÃ THÙNG', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                            const SizedBox(width: 6),
                            SizedBox(width: 90, child: Text('MÃ PALLET', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                            const SizedBox(width: 6),
                            SizedBox(width: 95, child: Text('VỊ TRÍ KỆ', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                            const SizedBox(width: 6),
                            SizedBox(width: 95, child: Text('NGÀY NHẬP', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                            const SizedBox(width: 6),
                            SizedBox(width: 110, child: Text('NHÀ CUNG CẤP', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                            const SizedBox(width: 6),
                            Expanded(flex: 3, child: Text('TÊN SẢN PHẨM', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                            const SizedBox(width: 6),
                            SizedBox(width: 135, child: Text('EPC PALLET', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                            const SizedBox(width: 6),
                            SizedBox(width: 135, child: Text('EPC HÀNG', style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold))),
                          ],
                        ),
                      ),

                      // Danh sách dòng sản phẩm
                      Expanded(
                        child: ListView.separated(
                          itemCount: order.items.length + unexpList.length,
                          separatorBuilder: (_, _) => Divider(height: 1, color: c.border.withValues(alpha: 0.4)),
                          itemBuilder: (context, index) {
                            if (index < order.items.length) {
                              final item = order.items[index];
                              final epc = item.epc.trim().toUpperCase();
                              final isScanned = _gateScannedTags.containsKey(epc);

                              return Container(
                                color: isScanned ? const Color(0xFF10B981).withValues(alpha: 0.08) : Colors.transparent,
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                child: Row(
                                  children: [
                                    SizedBox(width: 38, child: Text('${index + 1}', style: TextStyle(color: c.textSecondary, fontSize: 11))),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 90,
                                      child: Text(
                                        item.sku,
                                        style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.w600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 90,
                                      child: Text(
                                        item.cartonCode,
                                        style: TextStyle(color: c.textPrimary, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 90,
                                      child: Text(
                                        item.palletCode,
                                        style: TextStyle(color: c.textPrimary, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    // VỊ TRÍ KỆ
                                    SizedBox(
                                      width: 95,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: item.isInStock
                                              ? (item.locationCode != '--' ? const Color(0xFF0284C7).withValues(alpha: 0.12) : c.bgDeep)
                                              : const Color(0xFFEF4444).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(5),
                                          border: Border.all(
                                            color: item.isInStock
                                                ? (item.locationCode != '--' ? const Color(0xFF0284C7).withValues(alpha: 0.4) : c.border)
                                                : const Color(0xFFEF4444).withValues(alpha: 0.4),
                                          ),
                                        ),
                                        child: Text(
                                          item.isInStock ? item.locationCode : 'Hết tồn',
                                          style: TextStyle(
                                            color: item.isInStock
                                                ? (item.locationCode != '--' ? const Color(0xFF0284C7) : c.textMuted)
                                                : const Color(0xFFEF4444),
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    // NGÀY NHẬP (FIFO)
                                    SizedBox(
                                      width: 95,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: item.isInStock
                                              ? const Color(0xFF10B981).withValues(alpha: 0.12)
                                              : const Color(0xFFEF4444).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(5),
                                          border: Border.all(
                                            color: item.isInStock
                                                ? const Color(0xFF10B981).withValues(alpha: 0.4)
                                                : const Color(0xFFEF4444),
                                          ),
                                        ),
                                        child: Text(
                                          item.isInStock
                                              ? (item.inboundTime != null ? DateFormat('dd/MM/yyyy').format(item.inboundTime!) : '--')
                                              : 'HẾT TỒN',
                                          style: TextStyle(
                                            color: item.isInStock
                                                ? const Color(0xFF10B981)
                                                : const Color(0xFFEF4444),
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 110,
                                      child: Text(
                                        item.supplier.isNotEmpty && item.supplier != '--' ? item.supplier : item.customer,
                                        style: TextStyle(color: c.textSecondary, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      flex: 3,
                                      child: Text(
                                        item.productName,
                                        style: TextStyle(color: c.textPrimary, fontSize: 11),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 135,
                                      child: Text(
                                        item.palletEpc,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(fontFamily: 'monospace', fontSize: 10.5, color: c.textSecondary),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    SizedBox(
                                      width: 135,
                                      child: Text(
                                        epc,
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
                              final unexp = unexpList[index - order.items.length];

                              return Container(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                child: Row(
                                  children: [
                                    SizedBox(width: 38, child: Text('${index + 1}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
                                    const SizedBox(width: 6),
                                    const SizedBox(width: 90, child: Text('CHIP LẠ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11))),
                                    const SizedBox(width: 6),
                                    const SizedBox(width: 90, child: Text('--', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
                                    const SizedBox(width: 6),
                                    const SizedBox(width: 90, child: Text('--', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
                                    const SizedBox(width: 6),
                                    const SizedBox(width: 95, child: Text('--', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5))),
                                    const SizedBox(width: 6),
                                    const SizedBox(width: 90, child: Text('--', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5))),
                                    const SizedBox(width: 6),
                                    const SizedBox(width: 110, child: Text('--', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
                                    const SizedBox(width: 6),
                                    const Expanded(flex: 3, child: Text('Chip lạ không nằm trong danh sách xuất', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
                                    const SizedBox(width: 6),
                                    const SizedBox(width: 135, child: Text('--', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5))),
                                    const SizedBox(width: 6),
                                    SizedBox(width: 135, child: Text(unexp.epc, style: const TextStyle(color: Color(0xFFEF4444), fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 10.5))),
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
        ),

        // 4. THANH ĐIỀU KHIỂN DƯỚI CÙNG VỚI 3 NÚT GIỐNG XUẤT KHO DESKTOP
        _buildBottomControlBar(
          c,
          scannedCount: scannedCount,
          expectedCount: expectedCount,
          isComplete: isComplete,
          unexpCount: unexpCount,
          isStockSufficient: order.isStockSufficient,
        ),
      ],
    );
  }

  // ---------- 4. THANH ĐIỀU KHIỂN DƯỚI CÙNG (3 NÚT GIỐNG XUẤT KHO DESKTOP) ----------
  Widget _buildBottomControlBar(
    EyeCareColors c, {
    required int scannedCount,
    required int expectedCount,
    required bool isComplete,
    required int unexpCount,
    required bool isStockSufficient,
  }) {
    final hasUnexpected = unexpCount > 0;
    final canConfirm = isComplete && !hasUnexpected;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCardElevated,
        border: Border(top: BorderSide(color: c.border)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // NÚT: LÀM MỚI QUÉT (Luôn luôn hiển thị và bấm được mọi lúc để xóa lượt quét)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: c.textPrimary,
                side: BorderSide(color: c.border),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.replay, size: 15, color: Color(0xFF0284C7)),
              label: const Text('Làm Mới Quét', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              onPressed: _clearGateScan,
            ),
            const SizedBox(width: 6),
            // NÚT: BẮT ĐẦU QUÉT / DỪNG QUÉT
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _isScanning ? Colors.white : c.textPrimary,
                backgroundColor: _isScanning ? const Color(0xFFEF4444) : null,
                side: BorderSide(color: _isScanning ? const Color(0xFFEF4444) : const Color(0xFF0284C7)),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow, size: 15, color: _isScanning ? Colors.white : const Color(0xFF0284C7)),
              label: Text(_isScanning ? 'Dừng Quét' : 'Bắt Đầu Quét', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _isScanning ? Colors.white : c.textPrimary)),
              onPressed: _toggleGateScan,
            ),
            if (canConfirm) ...[
              const SizedBox(width: 8),
              // Nút Xác Nhận Xuất Kho: Chỉ hiện khi đã quét đủ 100% và không có chip lạ
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isStockSufficient ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: isStockSufficient
                      ? (_isSaving
                          ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.check_circle, size: 16))
                      : const Icon(Icons.block, size: 16),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      !isStockSufficient
                          ? 'KHÓA XUẤT (THIẾU TỒN)'
                          : (_isSaving ? 'ĐANG LƯU KHO...' : '✓ XÁC NHẬN XUẤT KHO ($scannedCount/$expectedCount)'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ),
                  onPressed: (_isSaving || !isStockSufficient) ? null : _confirmOutboundDelivery,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ---------- 3 Ô CHỈ SỐ METRIC BOXES: ĐÃ QUÉT - THIẾU - LẠ ----------
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
}
