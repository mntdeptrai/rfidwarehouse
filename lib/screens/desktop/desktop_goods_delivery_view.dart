import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/tag_info.dart';
import '../../services/auth_service.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/excel_import_service.dart';
import '../../services/supabase_sync_service.dart';
import '../../services/tower_light_service.dart';
import '../../services/uhf_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';

/// Mô hình chi tiết từng sản phẩm cần xuất kho qua cổng RFID
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
    required this.supplier,
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

/// Mô hình đơn xuất kho nạp từ file (lưu tạm trong RAM chờ đối soát qua cổng)
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

class DesktopGoodsDeliveryView extends StatefulWidget {
  final bool isActive;
  const DesktopGoodsDeliveryView({super.key, this.isActive = true});

  @override
  State<DesktopGoodsDeliveryView> createState() => _DesktopGoodsDeliveryViewState();
}

class _DesktopGoodsDeliveryViewState extends State<DesktopGoodsDeliveryView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final DesktopUhfTcpService _desktopUhf = DesktopUhfTcpService();
  final TowerLightService _towerLight = TowerLightService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final AuthService _auth = AuthService();
  final ExcelImportService _excelService = ExcelImportService();
  final SupabaseSyncService _supabaseSync = SupabaseSyncService();


  bool _isImporting = false;
  bool _isSaving = false;

  // Đơn xuất kho đang chờ đối soát qua cổng
  _PendingOutboundOrder? _pendingOutboundOrder;

  // Danh sách chip RFID đã quét tại trạm/cổng
  final Map<String, TagInfo> _gateScannedTags = {};
  bool _isScanning = false;
  int _scanDurationSeconds = 0; // 0 = liên tục (mặc định), 5s, 10s
  int _scanCountdown = 0;
  Timer? _countdownTimer;
  Timer? _uiRefreshTimer;

  StreamSubscription<TagInfo>? _uhfSub;
  StreamSubscription<TagInfo>? _desktopUhfSub;

  // Thông báo đối soát thành công (tự động ẩn sau 3s)
  String? _lastSuccessOrderNo;
  String? _lastSuccessPalletCode;
  int _lastSuccessCount = 0;
  Timer? _successBannerTimer;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onThemeChanged);
    _repo.addListener(_onThemeChanged);
    _auth.addListener(_onThemeChanged);
    _desktopUhf.addListener(_onDesktopUhfUpdate);

    _initTagListeners();

    if (_desktopUhf.config.autoConnectOnStartup && !_desktopUhf.isConnected) {
      _desktopUhf.connectWithSavedConfig();
    }
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onDesktopUhfUpdate() {
    if (!mounted || !widget.isActive) return;
    setState(() {
      _isScanning = _desktopUhf.isScanning;
      for (final tag in _desktopUhf.tags) {
        _gateScannedTags[tag.epc.toUpperCase()] = tag;
      }
    });
  }

  void _initTagListeners() {
    _uhfSub = _uhf.onTagRead.listen((tag) {
      if (!mounted || !widget.isActive) return;
      _handleIncomingGateTag(tag);
    });

    _desktopUhfSub = _desktopUhf.onTagRead.listen((tag) {
      if (!mounted || !widget.isActive) return;
      _handleIncomingGateTag(tag);
    });
  }

  void _handleIncomingGateTag(TagInfo tag) {
    if (_pendingOutboundOrder == null) return;

    final epc = tag.epc.trim().toUpperCase();
    if (_uhf.filterDuplicates && _gateScannedTags.containsKey(epc)) return;

    _gateScannedTags[epc] = tag;

    // Kiểm tra nhanh chip lạ
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
          reason: 'ĐỦ HÀNG XUẤT KHO: $scannedMatching/$totalExpected chip đã thông qua cổng RFID!',
        );
      }
    }

    _scheduleUiRefresh();
  }

  void _scheduleUiRefresh() {
    if (_uiRefreshTimer?.isActive ?? false) return;
    _uiRefreshTimer = Timer(const Duration(milliseconds: 60), () {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(DesktopGoodsDeliveryView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      if (_isScanning) _stopGateScan();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onThemeChanged);
    _repo.removeListener(_onThemeChanged);
    _eyeCare.removeListener(_onThemeChanged);
    _desktopUhf.removeListener(_onDesktopUhfUpdate);
    _uiRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    _successBannerTimer?.cancel();
    _uhfSub?.cancel();
    _desktopUhfSub?.cancel();
    super.dispose();
  }

  // ---------- SCANNER CONTROLS ----------
  void _toggleGateScan() async {
    if (_isScanning || _desktopUhf.isScanning) {
      _stopGateScan();
    } else {
      _startGateScan(durationSeconds: _scanDurationSeconds);
    }
  }

  Future<void> _startGateScan({int durationSeconds = 0}) async {
    _countdownTimer?.cancel();

    if (!_desktopUhf.isConnected) {
      final ok = await _desktopUhf.connectWithSavedConfig();
      if (!ok && !_desktopUhf.isConnected) {
        debugPrint('⚠️ Chưa kết nối được đầu đọc RFID (${_desktopUhf.config.connectionSummary}).');
      }
    }

    _uhf.enableScanning('xuat_kho');
    _uhf.startInventory();
    await _desktopUhf.startInventory();

    setState(() {
      _isScanning = true;
      _scanCountdown = durationSeconds > 0 ? durationSeconds : 0;
    });

    if (durationSeconds > 0) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        if (_scanCountdown > 1) {
          setState(() => _scanCountdown--);
        } else {
          timer.cancel();
          _stopGateScan();
        }
      });
    }
  }

  Future<void> _stopGateScan() async {
    _countdownTimer?.cancel();
    _uhf.disableScanning();
    await _desktopUhf.stopInventory();

    if (mounted) {
      setState(() {
        _isScanning = false;
        _scanCountdown = _scanDurationSeconds;
      });
    }
  }

  void _clearGateScan() {
    _stopGateScan();
    setState(() {
      _gateScannedTags.clear();
    });
    _uhf.clearTags();
    _desktopUhf.clearTags();
    _towerLight.turnOffAll();
  }

  // ---------- NẠP FILE XUẤT KHO (EXCEL / CSV / PO) ----------
  Future<void> _pickAndLoadOutboundFile() async {
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

      final List<_PendingOutboundItem> validatedItems = validation.validatedItems.map((vi) => _PendingOutboundItem(
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
              content: Text('⚠️ CẢNH BÁO TỒN KHO: Không đủ hàng tồn để xuất (Thiếu ${validation.shortageCount} món)! Đã khóa nút xác nhận xuất.'),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text('✓ Đã nạp thành công ${validatedItems.length} chip xuất kho từ file "${result.fileName}" (Đủ tồn kho & đã định vị kệ)'),
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

  // ---------- NẠP FILE ĐƠN XUẤT HÀNG PO (EXCEL / CSV) ----------
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
              content: Text('✓ Đã nạp thành công ${validatedItems.length} sản phẩm từ file PO! Sẵn sàng quét qua cổng.'),
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

  // ---------- XÁC NHẬN XUẤT KHO & CẬP NHẬT CƠ SỞ DỮ LIỆU ----------
  Future<void> _confirmOutboundDelivery() async {
    if (_isSaving || _pendingOutboundOrder == null) return;
    final order = _pendingOutboundOrder!;

    if (!order.isStockSufficient || order.items.any((i) => !i.isInStock)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text('Không thể xuất kho: Kho không đủ tồn kho (Thiếu ${order.shortageCount} sản phẩm)! Vui lòng kiểm tra lại tồn kho.'),
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
      if (_isScanning) await _stopGateScan();

      final shippedCount = await _repo.confirmGateOutbound(
        poNo: order.orderNo,
        customer: order.customer,
        scannedEpcs: expectedEpcs.toList(),
        performedBy: _auth.currentUser?.fullName ?? 'Cổng RFID Gate Outbound',
      );

      _towerLight.triggerPass(reason: 'HOÀN TẤT XUẤT KHO: $shippedCount sản phẩm đã thông qua cổng');
      await _supabaseSync.syncNow();

      if (!mounted) return;

      // Banner thông báo thành công
      setState(() {
        _lastSuccessOrderNo = order.orderNo;
        _lastSuccessPalletCode = order.pallets.keys.firstOrNull ?? '--';
        _lastSuccessCount = order.items.length;
        _pendingOutboundOrder = null;
        _clearGateScan();
      });

      _successBannerTimer?.cancel();
      _successBannerTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _lastSuccessOrderNo = null);
      });

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
                  child: const Icon(Icons.check_circle, size: 48, color: Color(0xFF10B981)),
                ),
                const SizedBox(height: 14),
                Text(
                  'XUẤT KHO THÀNH CÔNG!',
                  style: TextStyle(color: _eyeCare.colors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Đã thông qua cổng và xuất $shippedCount sản phẩm.\nSố lượng tồn vị trí đã được tự động giải phóng và trừ tồn kho.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _eyeCare.colors.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 18),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('TIẾP TỤC ĐƠN MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                  },
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi xác nhận xuất kho: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ---------- 3 Ô CHỈ SỐ: ĐÃ QUÉT - THIẾU - LẠ (ĐỀU NHAU, 3 MÀU XANH - VÀNG - ĐỎ) ----------
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

  // ==================== GIAO DIỆN CHÍNH (BUILD) ====================
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
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Thanh tiêu đề Header đồng bộ với Nhập Kho
              _buildTopHeaderBar(c, isNarrow),
              const SizedBox(height: 10),

              // Nội dung chính: Cổng đối soát xuất kho RFID
              Expanded(
                child: _buildOutboundGateMonitor(c),
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

  // ---------- 1. THANH TIÊU ĐỀ HEADER (NÚT XUẤT HÀNG DROPDOWN CYAN GIỐNG NHẬP HÀNG) ----------
  Widget _buildTopHeaderBar(EyeCareColors c, bool isNarrow) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Tiêu đề
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.outbox_rounded, color: Color(0xFF10B981), size: 22),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'QUẢN LÝ XUẤT KHO RFID',
                    style: TextStyle(color: c.textPrimary, fontSize: isNarrow ? 15 : 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Kiểm đếm hàng hóa • Cổng quét RFID đối soát xuất kho',
                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),

          // Nhóm nút thao tác: [XUẤT HÀNG ▼] màu cyan + LỊCH SỬ XUẤT KHO + LÀM MỚI
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Nút XUẤT HÀNG dạng PopupMenuButton màu Cyan giống Nhập Hàng
              PopupMenuButton<String>(
                tooltip: 'Chọn nạp file xuất hàng',
                onSelected: (val) {
                  if (val == 'file_excel') {
                    _pickAndLoadOutboundFile();
                  } else if (val == 'file_po') {
                    _pickAndLoadOutboundPoFile();
                  } else if (val == 'clear_pending') {
                    setState(() {
                      _pendingOutboundOrder = null;
                      _clearGateScan();
                    });
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem<String>(
                    value: 'file_excel',
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
                                  'Nạp file chứa Mã Thùng, Mã Pallet, SKU, Serial/EPC cần xuất',
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
                    value: 'file_po',
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
                                  'Nạp file đơn đặt hàng / xuất kho: Mã PO, SKU, Số lượng',
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
                  if (_pendingOutboundOrder != null) ...[
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
                                    'Xóa Danh Sách Đang Chờ Xuất',
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
                        const Icon(Icons.file_upload_outlined, size: 18, color: Color(0xFF2C251E)),
                      const SizedBox(width: 6),
                      Text(
                        _isImporting ? 'ĐANG XỬ LÝ...' : 'XUẤT HÀNG',
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
              const SizedBox(width: 10),


              // Nút Làm Mới
              Tooltip(
                message: 'Đồng bộ & làm mới dữ liệu từ CSDL',
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('LÀM MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  onPressed: () async {
                    await _repo.reloadFromSqlite();
                    await _supabaseSync.syncNow();
                    if (mounted) setState(() {});
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- 2. MÀN HÌNH CHỜ QUÉT KHI CHƯA NẠP FILE ----------
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
              'CỔNG RFID ĐANG SẴN SÀNG TIẾP NHẬN HÀNG XUẤT',
              style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            Text(
              'Vui lòng bấm nút [XUẤT HÀNG] ở góc trên để tải file danh sách xuất kho vào hệ thống.\nSau khi nạp file, hệ thống sẽ tự động quét và đối soát mã chip RFID khi xe qua cổng.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary, fontSize: 12.5, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- 3. MÀN HÌNH CỔNG XUẤT KHO RFID ĐỐI SOÁT THỜI GIAN THỰC ----------
  Widget _buildOutboundGateMonitor(EyeCareColors c) {
    if (_pendingOutboundOrder == null) {
      return _buildIdleGateMonitor(c);
    }

    final order = _pendingOutboundOrder!;
    final expectedEpcs = order.items.map((i) => i.epc.toUpperCase()).toSet();
    final validPalletEpcs = order.pallets.values.where((e) => e != null && e.isNotEmpty && e != '--').map((e) => e!.toUpperCase()).toSet();

    final expectedCount = expectedEpcs.length + validPalletEpcs.length;
    final scannedCount = _gateScannedTags.keys.where((e) => expectedEpcs.contains(e) || validPalletEpcs.contains(e)).length;
    final missingCount = (expectedCount - scannedCount).clamp(0, expectedCount);
    final unexpList = _gateScannedTags.values.where((t) => !expectedEpcs.contains(t.epc.toUpperCase()) && !validPalletEpcs.contains(t.epc.toUpperCase())).toList();
    final unexpCount = unexpList.length;

    final isComplete = expectedCount > 0 && scannedCount >= expectedCount;
    final progress = expectedCount > 0 ? (scannedCount / expectedCount).clamp(0.0, 1.0) : 0.0;
    final hasUnexpectedTags = unexpCount > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner thông cổng xuất thành công
          if (_lastSuccessOrderNo != null) ...[
            _buildPassSuccessBanner(c),
            const SizedBox(height: 10),
          ],

          // Banner Cảnh báo Tồn kho không đủ
          if (!order.isStockSufficient) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CẢNH BÁO: KHÔNG ĐỦ HÀNG TỒN KHO ĐỂ XUẤT (THIẾU ${order.shortageCount} SẢN PHẨM)',
                          style: const TextStyle(
                            color: Color(0xFFEF4444),
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Chi tiết thiếu theo SKU: ${order.shortageBySku.entries.map((e) => "${e.key}: thiếu ${e.value}").join(", ")}. Hệ thống khóa nút xác nhận xuất kho cho đến khi có đủ tồn kho.',
                          style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'KHÓA XUẤT',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 1. Thanh tiến độ đọc & 3 Ô CHỈ SỐ: ĐÃ QUÉT - THIẾU - LẠ (Đều nhau, 3 màu: Xanh - Vàng - Đỏ)
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

                // 3 Ô CHỈ SỐ: ĐÃ QUÉT - THIẾU - LẠ (Đều nhau, 3 màu: Xanh - Vàng - Đỏ)
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
          const SizedBox(height: 10),

          // Ô TÊN KHÁCH HÀNG: TRÊN BẢNG DANH SÁCH PHÍA BÊN TRÁI DƯỚI DÒNG TIẾN ĐỘ
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.5), width: 1.2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_pin, size: 15, color: Color(0xFF0284C7)),
                    const SizedBox(width: 6),
                    const Text(
                      'KHÁCH HÀNG:',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0284C7),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      order.customer.trim().isNotEmpty && order.customer.trim() != '--' && order.customer.trim() != 'Khách mua xuất kho'
                          ? order.customer.trim()
                          : 'Xuất Kho',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.bold,
                        color: c.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 2. BẢNG THÔNG TIN ĐỐI SOÁT CỔNG CÓ VỊ TRÍ KỆ & ƯU TIÊN FIFO
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: LayoutBuilder(
                builder: (ctx, constraints) {
                  final tableWidth = constraints.maxWidth > 1320 ? constraints.maxWidth : 1320.0;
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
                                SizedBox(width: 100, child: Text('MÃ THÙNG', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 100, child: Text('MÃ PALLET', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 110, child: Text('VỊ TRÍ KỆ', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 120, child: Text('NGÀY NHẬP', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 130, child: Text('NHÀ CUNG CẤP', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                Expanded(flex: 3, child: Text('TÊN SẢN PHẨM', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 150, child: Text('EPC PALLET', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 150, child: Text('EPC HÀNG', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                SizedBox(width: 110, child: Text('ATEN ĐÃ QUÉT', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                              ],
                            ),
                          ),

                          // Danh sách rows
                          Expanded(
                            child: ListView.separated(
                              itemCount: order.items.length + unexpList.length,
                              separatorBuilder: (_, _) => Divider(height: 1, color: c.border.withValues(alpha: 0.5)),
                              itemBuilder: (ctx, idx) {
                                if (idx < order.items.length) {
                                  final item = order.items[idx];
                                  final epc = item.epc.trim().toUpperCase();
                                  final isScanned = _gateScannedTags.containsKey(epc);
                                  final tag = _gateScannedTags[epc];
                                  final antenStr = isScanned
                                      ? (tag != null && tag.ant.isNotEmpty ? 'Anten ${tag.ant}' : 'Anten 1')
                                      : '--';

                                  return Container(
                                    color: isScanned ? const Color(0xFF10B981).withValues(alpha: 0.05) : Colors.transparent,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Row(
                                      children: [
                                        SizedBox(width: 45, child: Text('${idx + 1}', style: TextStyle(color: c.textSecondary, fontSize: 12))),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 110,
                                          child: Text(
                                            item.sku,
                                            style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 100,
                                          child: Text(
                                            item.cartonCode,
                                            style: TextStyle(color: c.textSecondary, fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 100,
                                          child: Text(
                                            item.palletCode,
                                            style: TextStyle(color: c.textSecondary, fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // VỊ TRÍ KỆ
                                        SizedBox(
                                          width: 110,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: item.isInStock
                                                    ? (item.locationCode != '--' ? const Color(0xFF0284C7).withValues(alpha: 0.12) : c.bgDeep)
                                                    : const Color(0xFFEF4444).withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: item.isInStock
                                                      ? (item.locationCode != '--' ? const Color(0xFF0284C7).withValues(alpha: 0.4) : c.border)
                                                      : const Color(0xFFEF4444).withValues(alpha: 0.4),
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    item.isInStock ? Icons.shelves : Icons.error_outline,
                                                    size: 13,
                                                    color: item.isInStock
                                                        ? (item.locationCode != '--' ? const Color(0xFF0284C7) : c.textMuted)
                                                        : const Color(0xFFEF4444),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    item.isInStock ? item.locationCode : 'Không có',
                                                    style: TextStyle(
                                                      color: item.isInStock
                                                          ? (item.locationCode != '--' ? const Color(0xFF0284C7) : c.textMuted)
                                                          : const Color(0xFFEF4444),
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // NGÀY NHẬP
                                        SizedBox(
                                          width: 120,
                                          child: Align(
                                            alignment: Alignment.centerLeft,
                                            child: item.isInStock
                                                ? Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(
                                                        color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                                      ),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        const Icon(
                                                          Icons.calendar_today_outlined,
                                                          size: 12,
                                                          color: Color(0xFF10B981),
                                                        ),
                                                        const SizedBox(width: 5),
                                                        Text(
                                                          item.inboundTime != null
                                                              ? DateFormat('dd/MM/yyyy').format(item.inboundTime!)
                                                              : '--',
                                                          style: const TextStyle(
                                                            color: Color(0xFF10B981),
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  )
                                                : Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: const Color(0xFFEF4444)),
                                                    ),
                                                    child: const Text(
                                                      'HẾT TỒN',
                                                      style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold),
                                                    ),
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 130,
                                          child: Text(
                                            item.supplier,
                                            style: TextStyle(color: c.textSecondary, fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          flex: 3,
                                          child: Text(
                                            item.productName,
                                            style: TextStyle(color: c.textPrimary, fontSize: 12),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 150,
                                          child: Text(
                                            item.palletEpc,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                              color: c.textSecondary,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 150,
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
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                              decoration: BoxDecoration(
                                                color: isScanned
                                                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                                    : c.bgDeep,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(
                                                  color: isScanned ? const Color(0xFF10B981) : c.border,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (isScanned) ...[
                                                    const Icon(Icons.check_circle, size: 12, color: Color(0xFF10B981)),
                                                    const SizedBox(width: 4),
                                                  ],
                                                  Text(
                                                    antenStr,
                                                    style: TextStyle(
                                                      color: isScanned ? const Color(0xFF10B981) : c.textMuted,
                                                      fontSize: 11,
                                                      fontWeight: isScanned ? FontWeight.bold : FontWeight.normal,
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
                                  // Chip lạ ngoài danh sách
                                  final unexp = unexpList[idx - order.items.length];
                                  final antenStr = unexp.ant.isNotEmpty ? 'Anten ${unexp.ant}' : 'Anten 1';

                                  return Container(
                                    color: const Color(0xFFEF4444).withValues(alpha: 0.08),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                    child: Row(
                                      children: [
                                        SizedBox(width: 45, child: Text('${idx + 1}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12))),
                                        const SizedBox(width: 8),
                                        const SizedBox(width: 110, child: Text('CHIP LẠ', style: TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 12))),
                                        const SizedBox(width: 8),
                                        const SizedBox(width: 100, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                                        const SizedBox(width: 8),
                                        const SizedBox(width: 100, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                                        const SizedBox(width: 8),
                                        const SizedBox(width: 110, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                                        const SizedBox(width: 8),
                                        const SizedBox(width: 115, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                                        const SizedBox(width: 8),
                                        const SizedBox(width: 130, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                                        const SizedBox(width: 8),
                                        const Expanded(
                                          flex: 3,
                                          child: Text('Chip không thuộc danh sách xuất kho!', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                                        ),
                                        const SizedBox(width: 8),
                                        const SizedBox(width: 150, child: Text('--', style: TextStyle(color: Color(0xFFEF4444)))),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: 150,
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
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
          const SizedBox(height: 10),

          // 3. THANH ĐIỀU KHIỂN DƯỚI CÙNG (DẠT CÁC NÚT THAO TÁC SANG PHẢI)
          _buildBottomControlBar(
            c,
            scannedCount: scannedCount,
            expectedCount: expectedCount,
            isComplete: isComplete,
            hasUnexpectedTags: hasUnexpectedTags,
            isStockSufficient: order.isStockSufficient,
          ),
        ],
      ),
    );
  }

  // ---------- 4. THANH ĐIỀU KHIỂN DƯỚI CÙNG (DẠT CÁC NÚT THAO TÁC SANG PHẢI) ----------
  Widget _buildBottomControlBar(
    EyeCareColors c, {
    required int scannedCount,
    required int expectedCount,
    required bool isComplete,
    required bool hasUnexpectedTags,
    required bool isStockSufficient,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCardElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Bên phải: Kéo dịch các nút quét, thời gian quét và làm mới quét sang bên phải
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Nút Làm Mới Quét
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.replay, size: 14),
                  label: const Text('Làm Mới Quét', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  onPressed: _clearGateScan,
                ),
                const SizedBox(width: 8),

                // Chọn thời gian quét: 5s, 10s, Liên tục
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
                      const SizedBox(width: 3),
                      _buildScanDurationButton(10, '10s', c),
                      const SizedBox(width: 3),
                      _buildScanDurationButton(0, 'Liên tục', c),
                    ],
                  ),
                ),
                const SizedBox(width: 8),

                // Nút Bắt đầu quét / Dừng quét
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isScanning ? const Color(0xFFEF4444) : c.rfidCyan,
                    foregroundColor: _isScanning ? Colors.white : const Color(0xFF2C251E),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: Icon(_isScanning ? Icons.stop_rounded : Icons.sensors, size: 16),
                  label: Text(
                    _isScanning
                        ? (_scanDurationSeconds > 0 ? 'DỪNG (${_scanCountdown}s)' : 'DỪNG QUÉT')
                        : (_scanDurationSeconds > 0 ? 'BẮT ĐẦU (${_scanDurationSeconds}s)' : 'BẮT ĐẦU QUÉT (LIÊN TỤC)'),
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                  onPressed: _toggleGateScan,
                ),

                // Nút Xác Nhận Xuất Kho: CHỈ HIỆN KHI ĐÃ ĐỌC ĐỦ 100% VÀ KHÔNG CÓ CHIP LẠ
                if (isComplete && !hasUnexpectedTags) ...[
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isStockSufficient ? const Color(0xFF10B981) : const Color(0xFF9CA3AF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: isStockSufficient ? 3 : 0,
                    ),
                    icon: Icon(isStockSufficient ? Icons.check_circle : Icons.block, size: 16),
                    label: Text(
                      !isStockSufficient
                          ? 'KHÓA XUẤT (THIẾU TỒN KHO)'
                          : (_isSaving ? 'ĐANG LƯU...' : 'ĐÃ ĐỌC ĐỦ $scannedCount/$expectedCount (XÁC NHẬN XUẤT KHO)'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: (_isSaving || !isStockSufficient) ? null : _confirmOutboundDelivery,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanDurationButton(int seconds, String label, EyeCareColors c) {
    final isSelected = _scanDurationSeconds == seconds;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: _isScanning
          ? null
          : () {
              setState(() {
                _scanDurationSeconds = seconds;
                _scanCountdown = seconds;
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

  // ---------- BANNER THÔNG CỔNG XUẤT THÀNH CÔNG ----------
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
                  '✓ ĐƠN HÀNG $_lastSuccessOrderNo ĐÃ QUA CỔNG XUẤT THÀNH CÔNG!',
                  style: const TextStyle(
                    color: Color(0xFF10B981),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Xe Pallet: ${_lastSuccessPalletCode ?? "--"} • Đã xuất $_lastSuccessCount sản phẩm (Trạng thái: Đã Xuất Kho) • Cổng sẵn sàng cho chuyến tiếp theo...',
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
