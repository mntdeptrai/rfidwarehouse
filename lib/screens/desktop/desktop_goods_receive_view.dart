import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/warehouse_repository.dart';
import '../../services/uhf_service.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/excel_import_service.dart';
import '../../services/tower_light_service.dart';
import '../../services/supabase_sync_service.dart';
import '../../widgets/putaway_barcode_modal.dart';
import '../../models/wms_models.dart';
import '../../models/tag_info.dart';
import '../../theme/eye_care_theme.dart';

class DesktopGoodsReceiveView extends StatefulWidget {
  const DesktopGoodsReceiveView({super.key});

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

  int _currentMode = 0; // 0: Live RFID Station, 1: Orders List & Excel
  bool _isCreating = false;


  final TextEditingController _receiveNoController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String _selectedWarehouse = 'Kho 01';

  // Live Station State
  InboundOrder? _selectedLiveOrder;
  final TextEditingController _palletController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();
  final TextEditingController _prodNameController = TextEditingController();
  final Map<String, TagInfo> _scannedTags = {};
  final Map<String, TagInfo> _invalidTags = {};
  bool _hasScanError = false;
  String? _scanErrorMessage;
  bool _isScanning = false;
  bool _isSaving = false;
  bool _filterOnlyOrderEpcs = true; // Mặc định BẬT: Chỉ nhận các mã EPC có trong đơn/file đang đối soát
  int _stationTab = 0; // 0: Đã quét khớp, 1: Chưa quét trong đơn, 2: Sai tem/lạ
  int _scanDurationSeconds = 5; // Mặc định: Quét tự động trong 5 giây
  int _scanCountdown = 5;       // Đếm ngược số giây quét còn lại
  Timer? _countdownTimer;
  StreamSubscription<TagInfo>? _tagSub;
  StreamSubscription<TagInfo>? _desktopTagSub;
  final List<Map<String, dynamic>> _receiptCartons = [];

  @override
  void initState() {
    super.initState();
    _resetForm();

    if (_repo.inboundOrders.isNotEmpty) {
      _selectedLiveOrder = _repo.inboundOrders.firstWhere(
        (o) => o.status == InboundOrderStatus.newOrder,
        orElse: () => _repo.inboundOrders.first,
      );
    }


    // Tự động kéo danh sách phiếu nhập mới nhất từ Supabase về khi mở trạm
    Future.microtask(() async {
      await _supabaseSync.syncNow();
      if (mounted) setState(() {});
    });

    // Đồng bộ tức thì dữ liệu thẻ và trạng thái đang quét từ Desktop UHF Bridge
    _isScanning = _desktopUhf.isScanning;
    for (final tag in _desktopUhf.tags) {
      if (_isTagValidForCurrentOrder(tag.epc)) {
        _scannedTags[tag.epc] = tag;
      }
    }
    _desktopUhf.addListener(_onDesktopUhfUpdate);
    _eyeCare.addListener(_onThemeUpdate);
    _repo.addListener(_onThemeUpdate);

    _initTagListener();
  }

  void _onThemeUpdate() {
    if (mounted) setState(() {});
  }


  /// Tự động tìm kiếm Đơn nhập / Thùng tương ứng với mã EPC được quét
  InboundOrder? _findOrderForEpc(String epc) {
    final cleanEpc = epc.trim().toUpperCase();
    final item = _repo.items.where((i) => i.epc.toUpperCase() == cleanEpc).firstOrNull;
    if (item != null && item.orderNo != null && item.orderNo!.isNotEmpty) {
      final order = _repo.inboundOrders.where((o) => o.orderNo.trim().toUpperCase() == item.orderNo!.trim().toUpperCase() || o.inboundOrderId.trim().toUpperCase() == item.orderNo!.trim().toUpperCase()).firstOrNull;
      if (order != null) return order;
      return InboundOrder(
        inboundOrderId: item.orderNo!,
        orderNo: item.orderNo!,
        sourceSupplier: 'Tự động nhận diện',
        status: InboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: item.productId,
            sku: item.sku,
            productName: item.productName,
            requiredQty: _repo.getItemsByOrderNo(item.orderNo!).length,
          ),
        ],
      );
    }

    if (_receiptCartons.isNotEmpty) {
      for (final carton in _receiptCartons) {
        final serials = (carton['serials'] as List<dynamic>?)?.map((e) => e.toString().trim().toUpperCase()).toSet() ?? {};
        if (serials.contains(cleanEpc)) {
          final code = carton['code']?.toString() ?? _receiveNoController.text;
          return InboundOrder(
            inboundOrderId: code,
            orderNo: code,
            sourceSupplier: carton['productName'] ?? 'Tệp Excel',
            status: InboundOrderStatus.newOrder,
            createdAt: DateTime.now(),
            details: [
              InboundOrderDetail(
                productId: carton['productCode'] ?? '',
                sku: carton['productCode'] ?? '',
                productName: carton['productName'] ?? '',
                requiredQty: serials.length,
              ),
            ],
          );
        }
      }
    }
    return null;
  }

  /// Lấy danh sách mã EPC kỳ vọng cho đơn/thùng hàng (tra cứu đa tầng: Repo items > _receiptCartons)
  Set<String> _getExpectedEpcsForOrder(String? orderNo) {
    if (orderNo == null || orderNo.isEmpty) return {};
    // Tầng 1: Tra từ repo items (đã lưu vào SQLite)
    final repoItems = _repo.getItemsByOrderNo(orderNo);
    if (repoItems.isNotEmpty) {
      return repoItems.map((i) => i.epc.toUpperCase()).toSet();
    }
    // Tầng 2: Tra từ _receiptCartons (dữ liệu Excel vừa nạp, chưa lưu hoặc bị xóa khỏi SQLite)
    final cleanOrderNo = orderNo.trim().toUpperCase();
    for (final carton in _receiptCartons) {
      final cartonBox = (carton['cartonBox'] ?? '').toString().trim().toUpperCase();
      if (cartonBox == cleanOrderNo) {
        final serials = (carton['serials'] as List<dynamic>?)
            ?.map((e) => e.toString().trim().toUpperCase())
            .toSet() ?? {};
        if (serials.isNotEmpty) return serials;
      }
    }
    return {};
  }

  /// Lấy danh sách Item kỳ vọng (đầy đủ thông tin sản phẩm) cho hiển thị UI và đối soát
  List<Item> _getExpectedItemsForOrder(String? orderNo) {
    if (orderNo == null || orderNo.isEmpty) return [];
    // Tầng 1: Tra từ repo items
    final repoItems = _repo.getItemsByOrderNo(orderNo);
    if (repoItems.isNotEmpty) return repoItems;
    // Tầng 2: Xây dựng từ _receiptCartons (fallback khi repo trống)
    final cleanOrderNo = orderNo.trim().toUpperCase();
    final List<Item> fallbackItems = [];
    for (final carton in _receiptCartons) {
      final cartonBox = (carton['cartonBox'] ?? '').toString().trim().toUpperCase();
      if (cartonBox == cleanOrderNo) {
        final serialItems = (carton['serialItems'] as List<dynamic>?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (serialItems != null && serialItems.isNotEmpty) {
          for (var sItem in serialItems) {
            fallbackItems.add(Item(
              itemId: 'EXCEL-${sItem['serial']}',
              productId: sItem['barcode']?.toString() ?? carton['productCode'] ?? '',
              sku: sItem['barcode']?.toString() ?? carton['productCode'] ?? '',
              productName: sItem['name']?.toString() ?? carton['productName'] ?? '',
              serialNumber: sItem['serial'].toString(),
              epc: sItem['serial'].toString(),
              status: ItemStatus.pendingInbound,
              orderNo: orderNo,
            ));
          }
        } else {
          final serials = (carton['serials'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          for (var serial in serials) {
            fallbackItems.add(Item(
              itemId: 'EXCEL-$serial',
              productId: carton['productCode'] ?? '',
              sku: carton['productCode'] ?? '',
              productName: carton['productName'] ?? '',
              serialNumber: serial,
              epc: serial,
              status: ItemStatus.pendingInbound,
              orderNo: orderNo,
            ));
          }
        }
      }
    }
    return fallbackItems;
  }

  /// Kiểm tra xem mã EPC quét được có thuộc đơn hàng / tệp Excel đang đối soát hay không
  bool _isTagValidForCurrentOrder(String epc) {
    if (!_filterOnlyOrderEpcs || _selectedLiveOrder == null) return true;
    final expectedEpcs = _getExpectedEpcsForOrder(_selectedLiveOrder!.orderNo);
    if (expectedEpcs.isEmpty) return true; // Nếu đơn chưa gán danh sách Item nào thì không lọc
    return expectedEpcs.contains(epc.toUpperCase());
  }

  void _onOrderSelected(InboundOrder? order) {
    setState(() {
      _selectedLiveOrder = order;
      _scannedTags.clear();
      _invalidTags.clear();
      _hasScanError = false;
      _scanErrorMessage = null;
      _uhf.clearTags();
      _desktopUhf.clearTags();
      if (order != null && order.details.isNotEmpty) {
        _skuController.text = order.details.first.sku;
        _prodNameController.text = order.details.first.productName;
      }
    });
  }

  void _onDesktopUhfUpdate() {
    if (!mounted) return;
    setState(() {
      _isScanning = _desktopUhf.isScanning;
      if (_desktopUhf.tags.isEmpty) {
        _scannedTags.clear();
        _invalidTags.clear();
        _hasScanError = false;
        _scanErrorMessage = null;
      } else {
        for (final tag in _desktopUhf.tags) {
          if (_selectedLiveOrder == null) {
            final detected = _findOrderForEpc(tag.epc);
            if (detected != null) {
              _selectedLiveOrder = detected;
              if (detected.details.isNotEmpty) {
                _skuController.text = detected.details.first.sku;
                _prodNameController.text = detected.details.first.productName;
              }
            }
          }
          if (_isTagValidForCurrentOrder(tag.epc)) {
            _scannedTags[tag.epc] = tag;
          } else {
            _invalidTags[tag.epc] = tag;
            _hasScanError = true;
            _scanErrorMessage = 'Phát hiện SAI TEM: Chip ${tag.epc} không thuộc đơn ${_selectedLiveOrder?.orderNo ?? ""}!';
          }
        }
      }
    });
  }

  Timer? _uiRefreshTimer;
  void _scheduleUiRefresh() {
    if (_uiRefreshTimer?.isActive ?? false) return;
    _uiRefreshTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted) setState(() {});
    });
  }

  bool _isAutoSaving = false;
  Timer? _autoResetTimer;

  Future<void> _triggerAutoConfirmInbound() async {
    if (_isAutoSaving || _isSaving || _hasScanError || _invalidTags.isNotEmpty) return;
    final expectedItems = _getExpectedItemsForOrder(_selectedLiveOrder?.orderNo);
    final expectedCount = expectedItems.length;
    if (expectedCount > 0 && _scannedTags.length != expectedCount) return;

    _isAutoSaving = true;

    try {
      final orderNo = _selectedLiveOrder?.orderNo ?? (_scannedTags.isNotEmpty ? _findOrderForEpc(_scannedTags.keys.first)?.orderNo : null);

      if (orderNo != null && orderNo.isNotEmpty) {
        final existingBarcode = _repo.items
            .where((i) => i.orderNo == orderNo)
            .map((i) => i.sku)
            .where((s) => s.isNotEmpty && s != orderNo && RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(s))
            .firstOrNull;
        final hexBarcode = existingBarcode ?? _repo.generateHexBarcode128();

        final saved = await _repo.confirmGateReceiveToWaitingPutaway(
          orderNo: orderNo,
          scannedEpcs: _scannedTags.keys.toList(),
          cartonCode: hexBarcode,
          performedBy: 'Trạm Cổng RFID Desktop',
        );

        debugPrint('⚡ [ZERO-TOUCH AUTO] Cổng RFID đã tiếp nhận kiện $orderNo ($saved chip) -> CHUYỂN SANG CHỜ XẾP KHO (Mã Barcode: $hexBarcode)');

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              duration: const Duration(seconds: 2),
              content: Text('✅ Kiện $orderNo ($saved chip) đã thông qua cổng RFID thành công!'),
            ),
          );
        }
      }

      // Tự động đặt lại sau 1.5 giây để sẵn sàng quét thùng tiếp theo
      _autoResetTimer?.cancel();
      _autoResetTimer = Timer(const Duration(milliseconds: 1500), () {
        if (mounted) {
          setState(() {
            _selectedLiveOrder = null;
            _scannedTags.clear();
            _invalidTags.clear();
            _hasScanError = false;
            _scanErrorMessage = null;
            _uhf.clearTags();
            _desktopUhf.clearTags();
            _isAutoSaving = false;
          });
          _towerLight.turnOffAll();
        }
      });
    } catch (e) {
      debugPrint('Auto-confirm error: $e');
      _isAutoSaving = false;
    }
  }

  void _handleIncomingTag(TagInfo tag) {
    if (!_isScanning) return;

    // 1. Tự động nhận diện đơn hàng ngay khi bắt được sóng chip đầu tiên
    if (_selectedLiveOrder == null) {
      final detected = _findOrderForEpc(tag.epc);
      if (detected != null) {
        _selectedLiveOrder = detected;
        if (detected.details.isNotEmpty) {
          _skuController.text = detected.details.first.sku;
          _prodNameController.text = detected.details.first.productName;
        }
      }
    }

    final bool isValid = _isTagValidForCurrentOrder(tag.epc);
    if (!isValid) {
      _invalidTags[tag.epc] = tag;
      _hasScanError = true;
      _scanErrorMessage = 'Phát hiện SAI TEM: Chip ${tag.epc} không có trong đơn đối soát!';
      // 🔴 ĐÈN ĐỎ + CÒI: Cảnh báo quét trúng mã chip không có trong đơn / sai hàng
      _towerLight.triggerWarningRed(
        withBuzzer: true,
        reason: _scanErrorMessage!,
      );
      _scheduleUiRefresh();
      return;
    }

    if (_uhf.filterDuplicates && _scannedTags.containsKey(tag.epc)) {
      return; // Thẻ đã đọc rồi thì bỏ qua không đọc lại
    }

    _scannedTags[tag.epc] = tag;

    // Đánh giá số lượng thực tế so với đơn hàng
    final expectedItems = _getExpectedItemsForOrder(_selectedLiveOrder?.orderNo);
    final expectedCount = expectedItems.length;

    if (expectedCount > 0) {
      final matchedCount = _scannedTags.length;
      if (_invalidTags.isNotEmpty) {
        _hasScanError = true;
        _scanErrorMessage = 'Phát hiện SAI TEM: Có ${_invalidTags.length} chip không thuộc đơn!';
        _towerLight.triggerWarningRed(
          withBuzzer: true,
          reason: _scanErrorMessage!,
        );
      } else if (matchedCount > expectedCount) {
        _hasScanError = true;
        _scanErrorMessage = 'Phát hiện THỪA HÀNG: Đã quét $matchedCount/$expectedCount chip (Thừa ${matchedCount - expectedCount} chip)!';
        // 🔴 ĐÈN ĐỎ + CÒI: Cảnh báo thừa hàng
        _towerLight.triggerWarningRed(
          withBuzzer: true,
          reason: _scanErrorMessage!,
        );
      } else if (matchedCount == expectedCount) {
        _hasScanError = false;
        _scanErrorMessage = null;
        // 🟢 ĐÈN XANH: Đủ hàng thông qua (100% khớp đơn)
        _towerLight.triggerPass(
          reason: 'ĐỦ HÀNG THÔNG QUA: $matchedCount/$expectedCount chip khớp 100% (Đơn ${_selectedLiveOrder!.orderNo})',
        );

        // ⚡ TỰ ĐỘNG XÁC NHẬN QUA CỔNG (Zero-Touch - Không cần bấm tay)
        _triggerAutoConfirmInbound();
      }
    } else {
      // Nếu không lọc theo đơn, quét chip hợp lệ là xanh
      _towerLight.triggerPass(reason: 'Quét thẻ hợp lệ: ${_scannedTags.length} chip');
    }

    _scheduleUiRefresh();
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
  }

  @override
  void dispose() {
    _repo.removeListener(_onThemeUpdate);
    _desktopUhf.removeListener(_onDesktopUhfUpdate);
    _eyeCare.removeListener(_onThemeUpdate);
    _uiRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    _autoResetTimer?.cancel();
    _tagSub?.cancel();
    _desktopTagSub?.cancel();
    _receiveNoController.dispose();
    _dateController.dispose();
    _noteController.dispose();
    _palletController.dispose();
    _skuController.dispose();
    _prodNameController.dispose();
    super.dispose();
  }

  void _resetForm() {
    final now = DateTime.now();
    _receiveNoController.text = 'IN${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    _dateController.text = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _noteController.text = '';
    _selectedWarehouse = 'Kho 01';
    _receiptCartons.clear();
  }

  void _toggleLiveScan() async {
    if (_isScanning || _desktopUhf.isScanning) {
      _stopLiveScan();
    } else {
      _startLiveScan(durationSeconds: _scanDurationSeconds);
    }
  }

  Future<void> _startLiveScan({int durationSeconds = 5}) async {
    _countdownTimer?.cancel();

    if (!_desktopUhf.isConnected) {
      await _desktopUhf.connectSerial('COM3', 115200);
    }

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
          _stopLiveScan(autoFinished: true);
        }
      });
    }
  }

  Future<void> _stopLiveScan({bool autoFinished = false}) async {
    _countdownTimer?.cancel();
    _uhf.stopInventory();
    await _desktopUhf.stopInventory();

    if (mounted) {
      setState(() {
        _isScanning = false;
        _scanCountdown = _scanDurationSeconds;
      });
    }

    // Đánh giá kết quả cuối cùng sau khi kết thúc đợt quét:
    final expectedItems = _getExpectedItemsForOrder(_selectedLiveOrder?.orderNo);
    final expectedCount = expectedItems.length;

    if (_invalidTags.isNotEmpty) {
      _hasScanError = true;
      _scanErrorMessage = 'Phát hiện SAI TEM: Có ${_invalidTags.length} chip lạ không thuộc đơn!';
      _towerLight.triggerWarningRed(
        withBuzzer: true,
        reason: 'KẾT THÚC QUÉT: CẢNH BÁO SAI TEM (${_invalidTags.length} chip lạ)! Đã khóa nhập kho.',
      );
    } else if (expectedCount > 0) {
      final matchedCount = _scannedTags.length;
      if (matchedCount > expectedCount) {
        _hasScanError = true;
        _scanErrorMessage = 'Phát hiện THỪA HÀNG: Đã quét $matchedCount/$expectedCount chip (Thừa ${matchedCount - expectedCount} chip)!';
        _towerLight.triggerWarningRed(
          withBuzzer: true,
          reason: 'KẾT THÚC QUÉT: CẢNH BÁO THỪA HÀNG ($matchedCount/$expectedCount chip)! Đã khóa nhập kho.',
        );
      } else if (matchedCount < expectedCount) {
        _towerLight.triggerWarningRed(
          withBuzzer: true,
          reason: 'KẾT THÚC QUÉT ($_scanDurationSeconds GIÂY): THIẾU HÀNG! Đã quét $matchedCount/$expectedCount chip (Còn thiếu ${expectedCount - matchedCount})',
        );
      } else {
        _hasScanError = false;
        _scanErrorMessage = null;
        _towerLight.triggerPass(
          reason: 'HOÀN TẤT ĐỐI SOÁT ($_scanDurationSeconds GIÂY): ĐỦ HÀNG THÔNG QUA ($matchedCount/$expectedCount chip khớp 100%)',
        );
        _triggerAutoConfirmInbound();
      }
    }
  }

  Future<void> _saveLiveInbound({bool isAuto = false}) async {
    if (_invalidTags.isNotEmpty) {
      if (!isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('⛔ BỊ KHÓA NHẬP KHO: Phát hiện ${_invalidTags.length} chip sai tem/lạ!')),
        );
      }
      return;
    }

    final expectedItems = _getExpectedItemsForOrder(_selectedLiveOrder?.orderNo);
    final expectedCount = expectedItems.length;
    if (expectedCount > 0 && _scannedTags.length > expectedCount) {
      if (!isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('⛔ BỊ KHÓA NHẬP KHO: Phát hiện thừa hàng (${_scannedTags.length}/$expectedCount chip)!')),
        );
      }
      return;
    }

    if (_scannedTags.isEmpty) {
      if (!isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Chưa có thẻ RFID nào được quét!')),
        );
      }
      return;
    }

    if (_selectedLiveOrder == null) {
      if (!isAuto) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Color(0xFFF59E0B), content: Text('Chưa chọn đơn nhập kho để đối soát!')),
        );
      }
      return;
    }

    setState(() => _isSaving = true);
    try {
      final currentOrderNo = _selectedLiveOrder!.orderNo;
      // Tái sử dụng mã Barcode 128 Hex đã được sinh ngay lúc nạp danh sách nhập hàng
      final existingItems = _repo.items.where((i) => i.orderNo == currentOrderNo).toList();
      final existingBarcode = existingItems
          .map((i) => i.sku)
          .where((s) => s.isNotEmpty && s != currentOrderNo && RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(s))
          .firstOrNull;

      final hexBarcode = existingBarcode ?? _repo.generateHexBarcode128();
      final saved = await _repo.confirmGateReceiveToWaitingPutaway(
        orderNo: currentOrderNo,
        scannedEpcs: _scannedTags.keys.toList(),
        cartonCode: hexBarcode,
        performedBy: 'Thủ kho Desktop',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 2),
          content: Text('✅ Đã xác nhận nhập kho $saved chip cho đơn $currentOrderNo thành công!'),
        ),
      );

      setState(() {
        _scannedTags.clear();
        _uhf.clearTags();
        // Chuyển sang đơn mới tiếp theo (bỏ qua đơn đã xác nhận)
        final nextOrder = _repo.inboundOrders.where((o) =>
          o.status == InboundOrderStatus.newOrder ||
          o.status == InboundOrderStatus.processing
        ).firstOrNull;
        _selectedLiveOrder = nextOrder;
      });
      _desktopUhf.clearTags();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _importGoodsReceiveExcel() async {
    try {
      final result = await _excelService.pickAndParseGoodsReceiveExcel();
      if (result == null) return; // Người dùng hủy chọn

      for (var carton in result.cartons) {
        final rawCode = carton['productCode']?.toString().trim() ?? '';
        if (!RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(rawCode)) {
          carton['productCode'] = _repo.generateHexBarcode128();
        }
      }

      final defaultCode = (result.cartons.isNotEmpty && result.cartons.first['cartonBox'] != null && result.cartons.first['cartonBox'].toString().isNotEmpty)
          ? result.cartons.first['cartonBox'].toString().trim()
          : 'IN${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}${DateTime.now().hour.toString().padLeft(2, '0')}${DateTime.now().minute.toString().padLeft(2, '0')}';

      setState(() {
        _receiptCartons.clear();
        _receiptCartons.addAll(result.cartons);
        _receiveNoController.text = defaultCode;
        _noteController.text = 'Nhập hàng từ tệp ${result.fileName} (${result.totalSerials} mã Serial/EPC)';
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('Đã nạp ${result.totalCartons} nhóm hàng/thùng (${result.totalRows} dòng, ${result.totalSerials} mã Serial/EPC) từ "${result.fileName}"!'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text('Lỗi nạp file Excel: $e'),
        ),
      );
    }
  }

  Future<void> _downloadGoodsReceiveTemplate() async {
    try {
      final path = await _excelService.exportGoodsReceiveTemplate();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          duration: const Duration(seconds: 6),
          content: Text('Đã xuất file Excel mẫu thành công: $path'),
          action: SnackBarAction(
            label: 'SAO CHÉP ĐƯỜNG DẪN',
            textColor: Colors.white,
            onPressed: () {
              Clipboard.setData(ClipboardData(text: path));
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text('Lỗi xuất file mẫu: $e'),
        ),
      );
    }
  }

  void _showTemplateDialog(EyeCareColors c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.table_chart, color: Color(0xFF10B981), size: 24),
            const SizedBox(width: 10),
            Text('Cấu Trúc Tệp Mẫu Nhập Hàng', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 780,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.bgCardElevated,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: c.rfidCyan, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cấu trúc tệp Excel gồm 3 cột chuẩn: CARTON CODE (Mã thùng/kiện), EPC (Mã chip RFID sản phẩm), NAME (Tên sản phẩm). Khi nạp file, hệ thống sẽ lưu đúng mã EPC của từng sản phẩm ở trạng thái CHƯA NHẬP KHO.',
                          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Table(
                  border: TableBorder.all(color: c.border),
                  columnWidths: const {
                    0: FlexColumnWidth(2.2),
                    1: FlexColumnWidth(3.8),
                    2: FlexColumnWidth(2.5),
                  },
                  children: [
                    TableRow(
                      decoration: BoxDecoration(color: c.bgCardElevated),
                      children: [
                        Padding(padding: const EdgeInsets.all(8), child: Text('CARTON CODE', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                        Padding(padding: const EdgeInsets.all(8), child: Text('EPC', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                        Padding(padding: const EdgeInsets.all(8), child: Text('NAME', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.all(8), child: Text('CARTONTEST0001', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                        Padding(padding: const EdgeInsets.all(8), child: Text('ABCDEF000000000000000001', style: TextStyle(color: c.rfidCyan, fontFamily: 'Courier', fontSize: 11))),
                        Padding(padding: const EdgeInsets.all(8), child: Text('Áo Polo RFID Cotton Standard', style: TextStyle(color: c.textSecondary, fontSize: 11))),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.all(8), child: Text('CARTONTEST0001', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                        Padding(padding: const EdgeInsets.all(8), child: Text('ABCDEF000000000000000002', style: TextStyle(color: c.rfidCyan, fontFamily: 'Courier', fontSize: 11))),
                        Padding(padding: const EdgeInsets.all(8), child: Text('Áo Polo RFID Cotton Standard', style: TextStyle(color: c.textSecondary, fontSize: 11))),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.all(8), child: Text('CARTONTEST0001', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                        Padding(padding: const EdgeInsets.all(8), child: Text('...', style: TextStyle(color: c.textMuted, fontSize: 11))),
                        Padding(padding: const EdgeInsets.all(8), child: Text('...', style: TextStyle(color: c.textMuted, fontSize: 11))),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(padding: const EdgeInsets.all(8), child: Text('CARTONTEST0001', style: TextStyle(color: c.textPrimary, fontSize: 11))),
                        Padding(padding: const EdgeInsets.all(8), child: Text('ABCDEF000000000000000010', style: TextStyle(color: c.rfidCyan, fontFamily: 'Courier', fontSize: 11))),
                        Padding(padding: const EdgeInsets.all(8), child: Text('quần kakak', style: TextStyle(color: c.textSecondary, fontSize: 11))),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF10B981),
              side: const BorderSide(color: Color(0xFF10B981)),
            ),
            icon: const Icon(Icons.download, size: 16),
            label: const Text('TẢI FILE EXCEL MẪU (.XLSX)'),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadGoodsReceiveTemplate();
            },
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ĐÃ HIỂU', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSerialListDialog(String carton, String prodName, List<dynamic> serials, EyeCareColors c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.qr_code, color: c.rfidCyan, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Danh sách Mã EPC RFID: $carton', style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                  Text('$prodName · ${serials.length} chip', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 520,
          height: 380,
          child: ListView.builder(
            itemCount: serials.length,
            itemBuilder: (ctx, idx) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Text('#${idx + 1}', style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  Text(serials[idx].toString(), style: TextStyle(color: c.rfidCyan, fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 12)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Chưa nhập', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 9.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('ĐÓNG', style: TextStyle(color: c.textSecondary))),
        ],
      ),
    );
  }




  void _exportAllPendingEpcs() {
    final activeOrderNos = _repo.inboundOrders.map((o) => o.orderNo.trim().toUpperCase()).toSet();
    final pendingItems = _repo.items.where((i) => i.status == ItemStatus.pendingInbound && i.orderNo != null && activeOrderNos.contains(i.orderNo!.trim().toUpperCase())).toList();
    if (pendingItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hiện không có mã EPC nào ở trạng thái Chưa nhập kho.')),
      );
      return;
    }
    final text = pendingItems.map((i) => '${i.orderNo ?? "N/A"}\t${i.epc}\t${i.sku}\t${i.productName}\t${i.serialNumber}').join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        content: Text('Đã sao chép ${pendingItems.length} mã EPC Chưa nhập kho của tất cả các đơn vào bộ nhớ tạm!'),
      ),
    );
  }

  void _showBatchImportOrdersDialog() {
    List<Map<String, dynamic>> previewRows = [];
    final c = _eyeCare.colors;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final totalOrders = previewRows.map((r) => r['orderNo']).toSet().length;
          final totalItems = previewRows.fold<int>(0, (sum, r) => sum + (r['quantity'] as int));
          final bool hasExplicitEpcs = previewRows.any((r) => (r['epc'] as String?)?.isNotEmpty ?? false);

          final List<String> explicitEpcs = previewRows
              .map((r) => (r['epc'] as String?)?.trim().toUpperCase())
              .where((epc) => epc != null && epc.isNotEmpty)
              .cast<String>()
              .toList();

          final Map<String, int> epcOccurrences = {};
          for (var epc in explicitEpcs) {
            epcOccurrences[epc] = (epcOccurrences[epc] ?? 0) + 1;
          }
          final Set<String> internalDuplicateEpcs = epcOccurrences.entries
              .where((e) => e.value > 1)
              .map((e) => e.key)
              .toSet();

          final Set<String> existingDbEpcs = _repo.items.map((i) => i.epc.toUpperCase()).toSet();
          final Set<String> dbDuplicateEpcs = explicitEpcs
              .where((epc) => existingDbEpcs.contains(epc))
              .toSet();

          final bool hasEpcDuplicates = internalDuplicateEpcs.isNotEmpty || dbDuplicateEpcs.isNotEmpty;

          return AlertDialog(
            backgroundColor: c.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.file_upload, color: Color(0xFF10B981), size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Import Danh Sách Nhiều Đơn Hàng', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        hasExplicitEpcs
                            ? 'Tự động tạo đơn, đối soát so sánh mã EPC với CSDL & kiểm tra trùng'
                            : 'Tự động tạo đơn & sinh toàn bộ mã EPC ở trạng thái CHƯA NHẬP KHO',
                        style: TextStyle(color: hasExplicitEpcs ? const Color(0xFF10B981) : c.rfidCyan, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 840,
              height: 500,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
                        icon: const Icon(Icons.file_open, size: 16, color: Color(0xFF2C251E)),
                        label: const Text('Chọn File Excel Từ Máy', style: TextStyle(color: Color(0xFF2C251E), fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          try {
                            final rows = await _excelService.pickAndParseBatchOrdersExcel();
                            if (rows != null && rows.isNotEmpty) {
                              final Map<String, String> orderBarcodeMap = {};
                              for (var row in rows) {
                                final orderNo = (row['orderNo'] ?? '').toString().trim();
                                final rawSku = row['sku']?.toString().trim() ?? '';
                                if (RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(rawSku)) {
                                  orderBarcodeMap[orderNo] = rawSku.toUpperCase();
                                } else if (!orderBarcodeMap.containsKey(orderNo)) {
                                  orderBarcodeMap[orderNo] = _repo.generateHexBarcode128();
                                }
                                row['sku'] = orderBarcodeMap[orderNo]!;
                              }

                              setDialogState(() {
                                previewRows = rows;
                              });
                              if (!context.mounted) return;
                              final epcCount = rows.where((r) => (r['epc'] as String?)?.isNotEmpty ?? false).length;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFF10B981),
                                  content: Text(epcCount > 0
                                      ? 'Đã nạp ${rows.length} dòng ($epcCount mã EPC) từ file Excel! Đã tự động sinh mã Barcode 128 cho các kiện.'
                                      : 'Đã nạp ${rows.length} dòng đơn hàng từ file Excel! Đã tự động sinh mã Barcode 128 cho các kiện.'),
                                ),
                              );
                            }
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi nạp file Excel: $e')),
                            );
                          }
                        },
                      ),
                      if (previewRows.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: BorderSide(color: c.border),
                          ),
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('Xóa Bảng', style: TextStyle(fontSize: 12)),
                          onPressed: () => setDialogState(() => previewRows.clear()),
                        ),
                      ],
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: c.bgCardElevated,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: c.border),
                        ),
                        child: Text(
                          hasExplicitEpcs
                              ? 'Tổng: $totalOrders đơn/thùng | $totalItems mã EPC'
                              : 'Tổng: $totalOrders đơn | $totalItems sản phẩm',
                          style: TextStyle(
                            color: previewRows.isNotEmpty ? const Color(0xFF10B981) : c.textMuted,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (hasEpcDuplicates) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFEF4444)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'CẢNH BÁO TRÙNG MÃ EPC: ${internalDuplicateEpcs.isNotEmpty ? "${internalDuplicateEpcs.length} mã bị lặp trong file. " : ""}${dbDuplicateEpcs.isNotEmpty ? "${dbDuplicateEpcs.length} mã đã tồn tại trong CSDL kho. " : ""}Vui lòng kiểm tra lại file trước khi nạp!',
                              style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Expanded(
                    child: previewRows.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.upload_file_outlined, size: 56, color: c.textMuted),
                                const SizedBox(height: 12),
                                Text(
                                  'Chưa có dữ liệu đơn hàng.',
                                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Bấm "Chọn File Excel Từ Máy" để tải lên file Excel chứa danh sách các đơn hàng.',
                                  style: TextStyle(color: c.textSecondary, fontSize: 12),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            child: Table(
                              border: TableBorder.all(color: c.border),
                              columnWidths: const {
                                0: FlexColumnWidth(1.8),
                                1: FlexColumnWidth(2.8),
                                2: FlexColumnWidth(1.8),
                                3: FlexColumnWidth(2.5),
                                4: FlexColumnWidth(1.0),
                                5: FlexColumnWidth(2.2),
                              },
                              children: [
                                TableRow(
                                  decoration: BoxDecoration(color: c.bgCardElevated),
                                  children: [
                                    Padding(padding: const EdgeInsets.all(8), child: Text('Mã Đơn / Thùng', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                                    Padding(padding: const EdgeInsets.all(8), child: Text(hasExplicitEpcs ? 'Mã EPC' : 'Nhà Cung Cấp', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                                    Padding(padding: const EdgeInsets.all(8), child: Text(hasExplicitEpcs ? 'Barcode Ngoài Thùng' : 'Mã SKU', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                                    Padding(padding: const EdgeInsets.all(8), child: Text('Tên Sản Phẩm', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                                    Padding(padding: const EdgeInsets.all(8), child: Text('Số Lượng', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                                    Padding(padding: const EdgeInsets.all(8), child: Text(hasExplicitEpcs ? 'Trạng Thái EPC' : 'EPC Sẽ Sinh', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11))),
                                  ],
                                ),
                                ...previewRows.map((row) {
                                  final epcVal = (row['epc'] as String?)?.trim().toUpperCase() ?? '';
                                  final bool isInternalDup = epcVal.isNotEmpty && internalDuplicateEpcs.contains(epcVal);
                                  final bool isDbDup = epcVal.isNotEmpty && dbDuplicateEpcs.contains(epcVal);
                                  final bool isDup = isInternalDup || isDbDup;

                                  return TableRow(
                                    decoration: isDup ? BoxDecoration(color: const Color(0xFFEF4444).withValues(alpha: 0.1)) : null,
                                    children: [
                                      Padding(padding: const EdgeInsets.all(8), child: Text(row['orderNo'], style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11))),
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: (row['epc'] != null && (row['epc'] as String).isNotEmpty)
                                            ? Text(row['epc'], style: TextStyle(color: isDup ? const Color(0xFFEF4444) : c.rfidCyan, fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 11))
                                            : Text(row['supplier'], style: TextStyle(color: c.textSecondary, fontSize: 11)),
                                      ),
                                      Padding(padding: const EdgeInsets.all(8), child: Text(row['sku'], style: TextStyle(color: c.textPrimary, fontFamily: 'Courier', fontSize: 11))),
                                      Padding(padding: const EdgeInsets.all(8), child: Text(row['productName'], style: TextStyle(color: c.textSecondary, fontSize: 11))),
                                      Padding(padding: const EdgeInsets.all(8), child: Text('${row['quantity']}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12))),
                                      Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: (row['epc'] != null && (row['epc'] as String).isNotEmpty)
                                            ? (isDup
                                                ? Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: const Color(0xFFEF4444)),
                                                    ),
                                                    child: Text(
                                                      isInternalDup ? '⛔ Trùng trong file' : '⛔ Đã có trong CSDL',
                                                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold),
                                                    ),
                                                  )
                                                : Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                                    ),
                                                    child: const Text(
                                                      '✓ Hợp lệ (Mới)',
                                                      style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                                                    ),
                                                  ))
                                            : Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(4),
                                                ),
                                                child: Text(
                                                  '⚡ ${row['quantity']} EPC (Chưa nhập)',
                                                  style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                      ),
                                    ],
                                  );
                                }),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: (previewRows.isNotEmpty && !hasEpcDuplicates) ? const Color(0xFF10B981) : Colors.grey.shade600,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: Icon(hasExplicitEpcs ? Icons.verified : Icons.check_circle, color: const Color(0xFF2C251E), size: 18),
                label: Text(
                  hasExplicitEpcs
                      ? 'XÁC NHẬN IMPORT DÙNG EPC TỪ FILE ($totalOrders ĐƠN)'
                      : 'XÁC NHẬN IMPORT ($totalOrders ĐƠN)',
                  style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold),
                ),
                onPressed: previewRows.isEmpty
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        final Map<String, List<Map<String, dynamic>>> grouped = {};
                        for (var row in previewRows) {
                          grouped.putIfAbsent(row['orderNo'], () => []).add(row);
                        }

                        if (hasExplicitEpcs) {
                          final List<InboundOrder> ordersToCreate = [];
                          final List<Item> directItems = [];
                          final now = DateTime.now();
                          int itemSeq = 1;

                          for (var entry in grouped.entries) {
                            final orderNo = entry.key;
                            final rows = entry.value;
                            final supplier = rows.first['supplier'] as String? ?? 'Nhà cung cấp';

                            final Map<String, InboundOrderDetail> detailMap = {};
                            for (var r in rows) {
                              final sku = r['sku'] as String;
                              final name = r['productName'] as String;
                              final qty = r['quantity'] as int;
                              if (!detailMap.containsKey(sku)) {
                                detailMap[sku] = InboundOrderDetail(
                                  productId: sku,
                                  sku: sku,
                                  productName: name,
                                  requiredQty: qty,
                                  receivedQty: 0,
                                );
                              } else {
                                final existing = detailMap[sku]!;
                                detailMap[sku] = InboundOrderDetail(
                                  productId: existing.productId,
                                  sku: existing.sku,
                                  productName: existing.productName,
                                  requiredQty: existing.requiredQty + qty,
                                  receivedQty: 0,
                                );
                              }

                              final epcVal = r['epc']?.toString().trim();
                              if (epcVal != null && epcVal.isNotEmpty) {
                                directItems.add(Item(
                                  itemId: 'ITEM-${now.millisecondsSinceEpoch}-$itemSeq',
                                  productId: sku,
                                  sku: sku,
                                  productName: name,
                                  serialNumber: epcVal,
                                  epc: epcVal,
                                  status: ItemStatus.pendingInbound,
                                  orderNo: orderNo,
                                ));
                                itemSeq++;
                              }
                            }

                            final order = InboundOrder(
                              inboundOrderId: 'INB-${now.millisecondsSinceEpoch}-${ordersToCreate.length}',
                              orderNo: orderNo,
                              sourceSupplier: supplier,
                              createdAt: now,
                              status: InboundOrderStatus.newOrder,
                              details: detailMap.values.toList(),
                            );
                            ordersToCreate.add(order);
                          }

                          for (var order in ordersToCreate) {
                            await _repo.addInboundOrder(order, autoGenerateEpcs: false);
                          }
                          for (var item in directItems) {
                            await _repo.insertDirectItem(item);
                          }

                          setState(() {});

                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF10B981),
                              content: Text('Đã import thành công ${ordersToCreate.length} đơn hàng và lưu ${directItems.length} mã EPC chính xác từ file Excel!'),
                            ),
                          );
                        } else {
                          final List<InboundOrder> ordersToCreate = [];
                          for (var entry in grouped.entries) {
                            final orderNo = entry.key;
                            final rows = entry.value;
                            final supplier = rows.first['supplier'] as String;

                            final order = InboundOrder(
                              inboundOrderId: 'INB-${DateTime.now().millisecondsSinceEpoch}-${ordersToCreate.length}',
                              orderNo: orderNo,
                              sourceSupplier: supplier,
                              createdAt: DateTime.now(),
                              status: InboundOrderStatus.newOrder,
                              details: rows.map((r) => InboundOrderDetail(
                                productId: r['sku'],
                                sku: r['sku'],
                                productName: r['productName'],
                                requiredQty: r['quantity'],
                                receivedQty: 0,
                              )).toList(),
                            );
                            ordersToCreate.add(order);
                          }

                          final allEpcs = await _repo.batchImportInboundOrders(ordersToCreate);
                          setState(() {});

                          if (!mounted) return;
                          ScaffoldMessenger.of(this.context).showSnackBar(
                            SnackBar(
                              backgroundColor: const Color(0xFF10B981),
                              content: Text('Đã import thành công ${ordersToCreate.length} đơn hàng và sinh ${allEpcs.length} mã EPC!'),
                            ),
                          );
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showGeneratedEpcsDialog(InboundOrder order, List<Item> items, {bool fromExcel = false}) {
    final c = _eyeCare.colors;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(fromExcel ? Icons.verified : Icons.qr_code_2, color: const Color(0xFF10B981), size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fromExcel ? 'Đã lưu ${items.length} mã EPC từ cột EPC Excel' : 'Đã sinh ${items.length} mã EPC duy nhất',
                    style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text('Mã đơn / Thùng: ${order.orderNo} | Trạng thái: CHƯA NHẬP KHO', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 680,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: c.rfidCyan, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fromExcel
                            ? 'Toàn bộ ${items.length} mã EPC từ file Excel đã được dùng trực tiếp làm mã chip RFID EPC (không sinh mã ngẫu nhiên mới). Vui lòng chuyển sang "Trạm Quét RFID Live" để quét đối soát khi hàng về.'
                            : 'Các mã EPC này đã được tạo trong CSDL ở trạng thái CHƯA NHẬP KHO. Hãy in/ghi nhãn lên hàng hóa và đưa qua Trạm quét RFID để hoàn tất nhập kho.',
                        style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.bgCardElevated,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          Text('#${index + 1}', style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.epc, style: TextStyle(color: c.rfidCyan, fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 12)),
                                Text('${item.productName} (${item.sku}) | ${item.serialNumber}', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: const Color(0xFFF59E0B)),
                            ),
                            child: const Text('Chưa nhập kho', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold)),
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
        actions: [
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: c.textSecondary,
              side: BorderSide(color: c.border),
            ),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Sao chép tất cả EPC'),
            onPressed: () {
              final epcText = items.map((i) => '${i.epc}\t${i.sku}\t${i.productName}\t${i.serialNumber}').join('\n');
              Clipboard.setData(ClipboardData(text: epcText));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(backgroundColor: const Color(0xFF10B981), content: Text('Đã sao chép ${items.length} mã EPC vào bộ nhớ tạm!')),
              );
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            icon: const Icon(Icons.play_arrow, size: 16, color: Color(0xFF2C251E)),
            label: const Text('Quét Nhập Kho Ngay', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _isCreating = false;
                _currentMode = 0;
                _selectedLiveOrder = order;
              });
            },
          ),
        ],
      ),
    );
  }

  void _showOrderEpcsDetailDialog(InboundOrder order) {
    final items = _repo.getItemsByOrderNo(order.orderNo);
    final c = _eyeCare.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            Icon(Icons.list_alt, color: c.rfidCyan, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chi tiết mã EPC - ${order.orderNo}', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Tổng số: ${items.length} chip | Đã nhập: ${items.where((i) => i.status == ItemStatus.inStock).length} | Chưa nhập: ${items.where((i) => i.status != ItemStatus.inStock).length}', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: 450,
          child: items.isEmpty
              ? Center(
                  child: Text('Chưa có mã EPC nào được gắn cho đơn này.', style: TextStyle(color: c.textSecondary)),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final isInStock = item.status == ItemStatus.inStock;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: c.bgCardElevated,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isInStock ? const Color(0xFF10B981).withValues(alpha: 0.4) : c.border),
                      ),
                      child: Row(
                        children: [
                          Text('#${index + 1}', style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.epc, style: TextStyle(color: isInStock ? const Color(0xFF34D399) : c.rfidCyan, fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 12)),
                                Text('${item.productName} (${item.sku}) | ${item.serialNumber} ${item.locationId != null ? "| Vị trí: ${item.locationId}" : ""}', style: TextStyle(color: c.textSecondary, fontSize: 10)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: isInStock ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: isInStock ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                            ),
                            child: Text(
                              isInStock ? 'Đã nhập kho' : 'Chưa nhập kho',
                              style: TextStyle(color: isInStock ? const Color(0xFF10B981) : const Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('ĐÓNG', style: TextStyle(color: c.textSecondary))),
        ],
      ),
    );
  }

  void _showAddProductRowDialog(EyeCareColors c) {
    final skuCtrl = TextEditingController(text: 'SKU-001');
    final nameCtrl = TextEditingController(text: 'Sản phẩm A');
    final qtyCtrl = TextEditingController(text: '10');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Thêm Sản Phẩm Vào Đơn Nhập', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: skuCtrl,
              style: TextStyle(color: c.textPrimary, fontSize: 13),
              decoration: InputDecoration(labelText: 'Mã SKU', labelStyle: TextStyle(color: c.textSecondary)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              style: TextStyle(color: c.textPrimary, fontSize: 13),
              decoration: InputDecoration(labelText: 'Tên sản phẩm', labelStyle: TextStyle(color: c.textSecondary)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              style: TextStyle(color: c.textPrimary, fontSize: 13),
              decoration: InputDecoration(labelText: 'Số lượng cần nhập', labelStyle: TextStyle(color: c.textSecondary)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('HỦY', style: TextStyle(color: c.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
            onPressed: () {
              final sku = skuCtrl.text.trim();
              final name = nameCtrl.text.trim();
              final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
              if (sku.isNotEmpty && name.isNotEmpty && qty > 0) {
                final barcode = RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(sku) ? sku : _repo.generateHexBarcode128();
                setState(() {
                  _receiptCartons.add({
                    'cartonBox': 'THUNG-${_receiptCartons.length + 1}',
                    'productCode': barcode,
                    'productName': name,
                    'quantity': qty,
                    'serials': <String>[],
                  });
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('THÊM', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _saveReceipt(bool markCompleted) async {
    final code = _receiveNoController.text.trim();
    if (code.isEmpty) return;

    if (_receiptCartons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Vui lòng thêm ít nhất 1 mặt hàng hoặc nạp từ file Excel trước khi lưu!'),
        ),
      );
      return;
    }

    for (var c in _receiptCartons) {
      final rawCode = c['productCode']?.toString().trim() ?? '';
      if (!RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(rawCode)) {
        c['productCode'] = _repo.generateHexBarcode128();
      }
    }

    final order = InboundOrder(
      inboundOrderId: 'INB-${DateTime.now().millisecondsSinceEpoch}',
      orderNo: code,
      sourceSupplier: _noteController.text.trim().isNotEmpty ? _noteController.text.trim() : 'Nhà cung cấp',
      createdAt: DateTime.now(),
      status: markCompleted ? InboundOrderStatus.completed : InboundOrderStatus.newOrder,
      details: [
        for (var c in _receiptCartons)
          InboundOrderDetail(
            productId: c['productCode'],
            sku: c['productCode'],
            productName: c['productName'],
            requiredQty: c['quantity'],
            receivedQty: markCompleted ? c['quantity'] : 0,
          ),
      ],
    );

    // Kiểm tra xem các thùng có sẵn danh sách serial từ Excel không
    final List<Item> explicitItems = [];
    final now = DateTime.now();
    int itemSeq = 1;
    for (var c in _receiptCartons) {
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
            epc: sSerial, // Cột SERIAL chính là mã EPC RFID, dùng trực tiếp 100%, không sinh mã mới
            status: ItemStatus.pendingInbound,
            orderNo: code,
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
            epc: serial, // Cột SERIAL chính là mã EPC RFID, dùng trực tiếp 100%, không sinh mã mới
            status: ItemStatus.pendingInbound,
            orderNo: code,
            palletId: cartonBox != null && cartonBox.isNotEmpty ? cartonBox : null,
          ));
          itemSeq++;
        }
      }
    }

    final c = _eyeCare.colors;

    // 1. So sánh kiểm tra trùng mã EPC trong danh sách nạp
    final List<String> serials = explicitItems.map((e) => e.epc.trim().toUpperCase()).toList();
    final Map<String, int> counts = {};
    for (var s in serials) {
      counts[s] = (counts[s] ?? 0) + 1;
    }
    final internalDups = counts.entries.where((e) => e.value > 1).map((e) => e.key).toList();
    final existingDbEpcs = _repo.items.map((i) => i.epc.toUpperCase()).toSet();
    final dbDups = serials.where((s) => existingDbEpcs.contains(s)).toSet().toList();

    if (internalDups.isNotEmpty || dbDups.isNotEmpty) {
      setState(() => _isCreating = false);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: c.bgCard,
          title: Row(
            children: const [
              Icon(Icons.error_outline, color: Color(0xFFEF4444)),
              SizedBox(width: 8),
              Text('Phát Hiện Trùng Mã EPC/Serial', style: TextStyle(color: Color(0xFFEF4444), fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (internalDups.isNotEmpty)
                Text('• Có ${internalDups.length} mã bị lặp lại trong danh sách:\n  ${internalDups.take(5).join(", ")}${internalDups.length > 5 ? "..." : ""}', style: TextStyle(color: c.textPrimary, fontSize: 12)),
              if (dbDups.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('• Có ${dbDups.length} mã đã tồn tại trong CSDL kho:\n  ${dbDups.take(5).join(", ")}${dbDups.length > 5 ? "..." : ""}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
              ],
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ĐÃ HIỂU - KIỂM TRA LẠI', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      return;
    }

    List<Item> generatedItems = [];
    final bool hasExplicitSerials = explicitItems.isNotEmpty;
    if (hasExplicitSerials) {
      await _repo.addInboundOrder(order, autoGenerateEpcs: false);
      for (var item in explicitItems) {
        await _repo.insertDirectItem(item);
      }
      generatedItems = explicitItems;
    } else {
      generatedItems = await _repo.addInboundOrder(order, autoGenerateEpcs: true);
    }

    // Tự động khởi tạo bản ghi Sản phẩm (SKU/Product) trong CSDL theo mã Barcode vừa sinh
    for (var c in _receiptCartons) {
      final bCode = c['productCode']?.toString().trim() ?? '';
      final pName = c['productName']?.toString().trim() ?? 'Kiện hàng $bCode';
      if (bCode.isNotEmpty) {
        final existing = _repo.products.where((p) => p.sku == bCode || p.productId == bCode).firstOrNull;
        if (existing == null) {
          await _repo.addProduct(Product(
            productId: bCode,
            sku: bCode,
            productName: pName,
            category: 'Hàng nhập qua cổng RFID',
            unit: 'Cái',
          ));
        }
      }
    }

    setState(() => _isCreating = false);

    if (mounted) {
      _showGeneratedEpcsDialog(order, generatedItems, fromExcel: hasExplicitSerials);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    if (_isCreating) {
      return _buildCreateReceiptForm(c);
    }

    return Container(
      color: c.bgDeep,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Mode Switcher Header
          Wrap(
            spacing: 16,
            runSpacing: 12,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'GOODS RECEIVE & RFID INBOUND STATION',
                    style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Quản Lý Nhập Kho',
                        style: TextStyle(color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: c.bgCard,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildModeTab(0, 'Trạm Quét RFID Live', Icons.sensors, c),
                            _buildModeTab(1, 'Danh Sách Phiếu Nhập', Icons.list_alt, c),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: Icon(Icons.refresh, size: 18, color: c.textPrimary),
                    label: Text('LÀM MỚI', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await _supabaseSync.syncNow();
                      await _repo.reloadFromSqlite();
                      if (mounted) {
                        setState(() {});
                        messenger.showSnackBar(
                          const SnackBar(
                            backgroundColor: Color(0xFF10B981),
                            duration: Duration(seconds: 2),
                            content: Text('Đã làm mới và đồng bộ danh sách phiếu nhập thành công!'),
                          ),
                        );
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.rfidCyan,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add, color: Color(0xFF2C251E), size: 18),
                    label: const Text('TẠO PHIẾU EXCEL', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
                    onPressed: () {
                      _resetForm();
                      setState(() => _isCreating = true);
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Main View Body
          Expanded(
            child: _currentMode == 0 ? _buildLiveRfidStationView(c) : _buildReceiptsList(c),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(int mode, String title, IconData icon, EyeCareColors c) {
    final isSelected = _currentMode == mode;
    return InkWell(
      onTap: () => setState(() => _currentMode = mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : c.textSecondary),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : c.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }


  // ==================== TRẠM QUÉT RFID LIVE TRÊN DESKTOP ====================

  Widget _buildLiveRfidStationView(EyeCareColors c) {
    final scannedCount = _scannedTags.length;
    final expectedOrderItems = _getExpectedItemsForOrder(_selectedLiveOrder?.orderNo);

    final expectedCount = expectedOrderItems.length;
    final expectedEpcs = expectedOrderItems.map((i) => i.epc.toUpperCase()).toSet();
    final matchedTags = _scannedTags.values.where((tag) => expectedEpcs.isEmpty || expectedEpcs.contains(tag.epc.toUpperCase())).toList();
    final matchedCount = matchedTags.length;
    final unscannedItems = expectedOrderItems.where((it) => !_scannedTags.containsKey(it.epc)).toList();
    final double progress = expectedCount > 0 ? (matchedCount / expectedCount).clamp(0.0, 1.0) : 0.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Configuration & Controls
        SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              children: [
              // Scan Telemetry Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _isScanning ? c.rfidCyan.withValues(alpha: 0.15) : c.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _isScanning ? c.rfidCyan : c.border, width: _isScanning ? 2 : 1),
                ),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(_isScanning ? 'ĐẦU ĐỌC RFID ĐANG BẬT' : 'ĐẦU ĐỌC SẴN SÀNG', style: TextStyle(color: _isScanning ? c.rfidCyan : c.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _filterOnlyOrderEpcs = !_filterOnlyOrderEpcs;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _filterOnlyOrderEpcs ? const Color(0xFF10B981).withValues(alpha: 0.2) : c.bgCardElevated,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: _filterOnlyOrderEpcs ? const Color(0xFF10B981) : c.border),
                                ),
                                child: Text(
                                  _filterOnlyOrderEpcs ? 'Lọc theo file: BẬT' : 'Lọc theo file: TẮT',
                                  style: TextStyle(color: _filterOnlyOrderEpcs ? const Color(0xFF10B981) : c.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            Tooltip(
                              message: 'Chống đọc đè lặp lại 1 chip nhiều lần từ sóng anten RFID',
                              child: InkWell(
                                onTap: () {
                                  setState(() {
                                    _uhf.filterDuplicates = !_uhf.filterDuplicates;
                                    _desktopUhf.ignoreAlreadyScanned = _uhf.filterDuplicates;
                                  });
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _uhf.filterDuplicates ? const Color(0xFF10B981).withValues(alpha: 0.2) : c.bgCardElevated,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: _uhf.filterDuplicates ? const Color(0xFF10B981) : c.border),
                                  ),
                                  child: Text(
                                    _uhf.filterDuplicates ? 'Lọc trùng sóng RF: BẬT' : 'Lọc trùng sóng RF: TẮT',
                                    style: TextStyle(color: _uhf.filterDuplicates ? const Color(0xFF10B981) : c.textSecondary, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Antenna Dual Selector Row (2 Anten cho cổng/trạm nhập kho)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.bgCardElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.border),
                      ),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('Anten Cổng:', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 4),
                          for (int ant = 1; ant <= 4; ant++) ...[
                            Builder(builder: (context) {
                              final isSelected = _desktopUhf.activeAntennas.contains(ant);
                              return InkWell(
                                onTap: () => _desktopUhf.toggleAntenna(ant),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isSelected
                                        ? c.rfidCyan.withValues(alpha: 0.25)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isSelected
                                          ? c.rfidCyan
                                          : c.border,
                                    ),
                                  ),
                                  child: Text(
                                    'ANT $ant',
                                    style: TextStyle(
                                      color: isSelected
                                          ? c.rfidCyan
                                          : c.textMuted,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    Text('$scannedCount', style: TextStyle(color: c.textPrimary, fontSize: 46, fontWeight: FontWeight.w900)),
                    Text(
                      _selectedLiveOrder != null ? 'Thẻ hợp lệ theo đơn ${_selectedLiveOrder!.orderNo}' : 'Thẻ RFID đã quét vào lô',
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),

                    if (_selectedLiveOrder != null && expectedCount > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: c.bgCardElevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('TIẾN ĐỘ ĐỐI SOÁT FILE', style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.bold)),
                                Text(
                                  '$matchedCount / $expectedCount chip (${(progress * 100).toStringAsFixed(0)}%)',
                                  style: TextStyle(
                                    color: matchedCount == expectedCount && expectedCount > 0 ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress,
                                backgroundColor: c.bgCard,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  matchedCount == expectedCount && expectedCount > 0 ? const Color(0xFF10B981) : c.rfidCyan,
                                ),
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    // Duration Selector & Scan Button
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: c.bgCardElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.border),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined, size: 14, color: c.rfidCyan),
                              const SizedBox(width: 6),
                              Text('Thời gian quét:', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                            ],
                          ),
                          DropdownButton<int>(
                            value: _scanDurationSeconds,
                            dropdownColor: c.bgCardElevated,
                            underline: const SizedBox(),
                            isDense: true,
                            style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.bold),
                            items: const [
                              DropdownMenuItem(value: 3, child: Text('⚡ 3 Giây')),
                              DropdownMenuItem(value: 5, child: Text('⏱️ 5 Giây - Chuẩn')),
                              DropdownMenuItem(value: 10, child: Text('⏱️ 10 Giây')),
                              DropdownMenuItem(value: 0, child: Text('♾️ Quét liên tục')),
                            ],
                            onChanged: _isScanning
                                ? null
                                : (val) {
                                    if (val != null) {
                                      setState(() {
                                        _scanDurationSeconds = val;
                                        _scanCountdown = val;
                                      });
                                    }
                                  },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _isScanning ? const Color(0xFFEF4444) : c.rfidCyan,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: Icon(_isScanning ? Icons.stop_circle_outlined : Icons.sensors, color: const Color(0xFF2C251E), size: 18),
                            label: Text(
                              _isScanning
                                  ? (_scanDurationSeconds > 0 ? 'ĐANG QUÉT · ${_scanCountdown}s - DỪNG' : 'ĐANG QUÉT - BẤM DỪNG')
                                  : (_scanDurationSeconds > 0 ? 'BẮT ĐẦU QUÉT · ${_scanDurationSeconds}s' : 'BẮT ĐẦU QUÉT RFID'),
                              style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            onPressed: _toggleLiveScan,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: BorderSide(color: c.border),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            _stopLiveScan();
                            setState(() {
                              _scannedTags.clear();
                              _uhf.clearTags();
                              _desktopUhf.clearTags();
                            });
                            _towerLight.turnOffAll();
                          },
                          child: const Text('XÓA'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Save Action Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _hasScanError
                        ? const Color(0xFFEF4444)
                        : (scannedCount > 0 ? const Color(0xFF10B981) : c.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: Icon(
                    _hasScanError ? Icons.block : Icons.check_circle,
                    color: _hasScanError ? Colors.white : const Color(0xFF2C251E),
                  ),
                  label: Text(
                    _isSaving
                        ? 'Đang lưu...'
                        : (_hasScanError
                            ? '⛔ BỊ KHÓA: SAI TEM HOẶC THỪA HÀNG'
                            : (_selectedLiveOrder != null
                                ? 'XÁC NHẬN QUA CỔNG · ${_selectedLiveOrder!.orderNo}: $scannedCount CHIP (CHỜ XẾP KHO)'
                                : 'XÁC NHẬN QUA CỔNG · $scannedCount CHIP (CHỜ XẾP KHO)')),
                    style: TextStyle(
                      color: _hasScanError ? Colors.white : const Color(0xFF2C251E),
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  onPressed: (_isSaving || scannedCount == 0 || _hasScanError) ? null : _saveLiveInbound,
                ),
              ),
            ],
          ),
        ),
      ),
      const SizedBox(width: 20),

        // Right Column: Live RFID Scanned Tags Table with Tabs
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        InkWell(
                          onTap: () => setState(() => _stationTab = 0),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: _stationTab == 0 ? c.rfidCyan : c.bgCardElevated,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _stationTab == 0 ? c.rfidCyan : c.border),
                            ),
                            child: Text(
                              'Đã quét khớp · $matchedCount',
                              style: TextStyle(
                                color: _stationTab == 0 ? Colors.white : c.textSecondary,
                                fontWeight: FontWeight.bold,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ),
                        if (_selectedLiveOrder != null && expectedCount > 0)
                          InkWell(
                            onTap: () => setState(() => _stationTab = 1),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _stationTab == 1 ? const Color(0xFFF59E0B).withValues(alpha: 0.3) : c.bgCardElevated,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _stationTab == 1 ? const Color(0xFFF59E0B) : c.border),
                              ),
                              child: Text(
                                'Chưa quét · ${unscannedItems.length}',
                                style: TextStyle(
                                  color: _stationTab == 1 ? const Color(0xFFF59E0B) : c.textSecondary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ),
                        if (_invalidTags.isNotEmpty)
                          InkWell(
                            onTap: () => setState(() => _stationTab = 2),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _stationTab == 2 ? const Color(0xFFEF4444) : const Color(0xFFEF4444).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: const Color(0xFFEF4444)),
                              ),
                              child: Text(
                                '🔴 Sai tem / Lạ · ${_invalidTags.length}',
                                style: TextStyle(
                                  color: _stationTab == 2 ? Colors.white : const Color(0xFFEF4444),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11.5,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (_filterOnlyOrderEpcs && _selectedLiveOrder != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '⚡ Đang lọc theo file đơn ${_selectedLiveOrder!.orderNo}',
                          style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                if (_hasScanError && _scanErrorMessage != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error, color: Color(0xFFEF4444), size: 22),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '🔴 CẢNH BÁO: $_scanErrorMessage - ĐÃ KHÓA NHẬP KHO!',
                            style: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _stationTab == 0
                      ? (scannedCount == 0
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.nfc, size: 48, color: c.textMuted),
                                  const SizedBox(height: 10),
                                  Text(
                                    _selectedLiveOrder != null
                                        ? 'Chưa có thẻ RFID nào được đọc.\nBấm "QUÉT" để bắt đầu đối soát các chip trong file đơn hàng.'
                                        : 'Chưa có thẻ RFID nào được đọc.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: _scannedTags.length,
                              separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                              itemBuilder: (context, index) {
                                final tag = _scannedTags.values.toList().reversed.toList()[index];
                                final antLabel = tag.ant.isNotEmpty ? tag.ant : '1';
                                final isAnt2 = antLabel == '2';
                                final matchedItem = expectedOrderItems.where((i) => i.epc.toUpperCase() == tag.epc.toUpperCase()).firstOrNull;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                  child: Row(
                                    children: [
                                      Text('#${index + 1}', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              tag.epc,
                                              style: TextStyle(color: c.textPrimary, fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold),
                                            ),
                                            if (matchedItem != null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                '${matchedItem.productName} | SKU: ${matchedItem.sku} ${matchedItem.serialNumber.isNotEmpty ? "| SN: ${matchedItem.serialNumber}" : ""}',
                                                style: TextStyle(color: c.rfidCyan, fontSize: 11),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (matchedItem != null) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(4),
                                            border: Border.all(color: const Color(0xFF10B981)),
                                          ),
                                          child: const Text('✓ Khớp file', style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: (isAnt2 ? const Color(0xFF8B5CF6) : c.rfidCyan).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: isAnt2 ? const Color(0xFFA78BFA) : c.rfidCyan),
                                        ),
                                        child: Text(
                                          'ANT $antLabel',
                                          style: TextStyle(
                                            color: isAnt2 ? const Color(0xFFA78BFA) : c.rfidCyan,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text('${tag.rssi} dBm', style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                                      const SizedBox(width: 8),
                                      Text('${tag.count} lần', style: TextStyle(color: c.textMuted, fontSize: 10)),
                                    ],
                                  ),
                                );
                              },
                            ))
                      : (_stationTab == 1
                          ? (unscannedItems.isEmpty
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.check_circle, size: 52, color: Color(0xFF10B981)),
                                      SizedBox(height: 10),
                                      Text(
                                        'Tuyệt vời! Đã quét đủ 100% chip theo file đơn hàng.',
                                        style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: unscannedItems.length,
                                  separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                                  itemBuilder: (context, index) {
                                    final item = unscannedItems[index];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                      child: Row(
                                        children: [
                                          Text('#${index + 1}', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.epc,
                                                  style: TextStyle(color: c.textPrimary, fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  '${item.productName} | SKU: ${item.sku} ${item.serialNumber.isNotEmpty ? "| SN: ${item.serialNumber}" : ""}',
                                                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: const Color(0xFFF59E0B)),
                                            ),
                                            child: const Text('⚡ Chưa quét', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ))
                          : (_invalidTags.isEmpty
                              ? const Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.verified, size: 52, color: Color(0xFF10B981)),
                                      SizedBox(height: 10),
                                      Text(
                                        'Không có chip lạ hoặc sai tem nào!',
                                        style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                    ],
                                  ),
                                )
                              : ListView.separated(
                                  itemCount: _invalidTags.length,
                                  separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                                  itemBuilder: (context, index) {
                                    final tag = _invalidTags.values.toList().reversed.toList()[index];
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                      child: Row(
                                        children: [
                                          Text('#${index + 1}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.bold)),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  tag.epc,
                                                  style: const TextStyle(color: Color(0xFFEF4444), fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold),
                                                ),
                                                const SizedBox(height: 2),
                                                const Text(
                                                  '⚠️ CHIP KHÔNG CÓ TRONG ĐƠN / SAI TEM ĐỐI SOÁT',
                                                  style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: const Color(0xFFEF4444)),
                                            ),
                                            child: const Text('⛔ SAI TEM', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ))),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _getOrEnsureOrderBarcode(InboundOrder order) {
    final orderItems = _repo.items.where((i) => i.orderNo == order.orderNo).toList();
    String? barcode = orderItems
        .map((i) => i.sku)
        .where((s) => s.isNotEmpty && s != order.orderNo && RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(s))
        .firstOrNull;

    if (barcode == null || barcode.isEmpty) {
      barcode = order.details
          .map((d) => d.sku)
          .where((s) => s.isNotEmpty && s != order.orderNo && RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(s))
          .firstOrNull;
    }

    if (barcode == null || barcode.isEmpty) {
      final newBarcode = _repo.generateHexBarcode128();
      barcode = newBarcode;
      _repo.updateInboundOrderBarcode(order.orderNo, newBarcode);
    }

    return barcode;
  }

  Widget _buildReceiptsList(EyeCareColors c) {
    final inboundOrders = _repo.inboundOrders;
    final activeOrderNos = inboundOrders.map((o) => o.orderNo.trim().toUpperCase()).toSet();
    final pendingCount = _repo.items.where((i) => i.status == ItemStatus.pendingInbound && i.orderNo != null && activeOrderNos.contains(i.orderNo!.trim().toUpperCase())).length;

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        children: [
          // Top Action Toolbar (Responsive Wrap to prevent overflow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Icon(Icons.list_alt, color: c.rfidCyan, size: 20),
                    Text(
                      'Danh Sách Đơn Nhập Kho · ${inboundOrders.length} đơn',
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    if (pendingCount > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFF59E0B)),
                        ),
                        child: Text(
                          '$pendingCount chip Chưa nhập kho',
                          style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (pendingCount > 0)
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF59E0B),
                          side: const BorderSide(color: Color(0xFFF59E0B)),
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        icon: const Icon(Icons.copy, size: 15),
                        label: const Text('Sao Chép Tất Cả EPC Chưa Nhập', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: _exportAllPendingEpcs,
                      ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.rfidCyan,
                        side: BorderSide(color: c.rfidCyan),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      icon: const Icon(Icons.sync, size: 15),
                      label: const Text('Làm Mới & Đồng Bộ Cloud', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () async {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Đang làm mới & đồng bộ dữ liệu...'), duration: Duration(seconds: 1)),
                        );
                        await _supabaseSync.syncNow();
                        await _repo.reloadFromSqlite();
                        setState(() {});
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('✅ Đã làm mới & đồng bộ thành công!'), duration: Duration(seconds: 2)),
                          );
                        }
                      },
                    ),

                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.rfidCyan,
                        side: BorderSide(color: c.rfidCyan),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      icon: const Icon(Icons.file_upload, size: 15),
                      label: const Text('Import Danh Sách Đơn (Excel)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: _showBatchImportOrdersDialog,
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      icon: const Icon(Icons.add, size: 15, color: Color(0xFF2C251E)),
                      label: const Text('Tạo Phiếu Mới', style: TextStyle(color: Color(0xFF2C251E), fontSize: 11, fontWeight: FontWeight.bold)),
                      onPressed: () {
                        _resetForm();
                        setState(() => _isCreating = true);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: inboundOrders.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.assignment_outlined, size: 64, color: c.textMuted),
                        const SizedBox(height: 14),
                        Text(
                          'Chưa có đơn nhập kho nào trong cơ sở dữ liệu.',
                          style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Bạn có thể tạo mới phiếu nhập hoặc Import danh sách nhiều đơn hàng từ Excel.',
                          style: TextStyle(color: c.textSecondary, fontSize: 12),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
                              icon: const Icon(Icons.file_upload, color: Color(0xFF2C251E)),
                              label: const Text('Import Danh Sách Đơn (Excel)', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
                              onPressed: _showBatchImportOrdersDialog,
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                              icon: const Icon(Icons.add, color: Color(0xFF2C251E)),
                              label: const Text('Tạo Phiếu Nhập Mới', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
                              onPressed: () {
                                _resetForm();
                                setState(() => _isCreating = true);
                              },
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: inboundOrders.length,
                    separatorBuilder: (_, index) => Divider(color: c.border, height: 1),
                    itemBuilder: (itemCtx, index) {
                      final order = inboundOrders[index];
                      final isCompleted = order.status == InboundOrderStatus.completed;
                      final barcodeDisplay = _getOrEnsureOrderBarcode(order);
                      final orderItems = _repo.items.where((i) => i.orderNo == order.orderNo).toList();
                      final orderItemCount = orderItems.isNotEmpty ? orderItems.length : order.details.fold<int>(0, (sum, d) => sum + d.requiredQty);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: c.rfidCyan.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.article, color: c.rfidCyan, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 8,
                              runSpacing: 4,
                              children: [
                                Text(order.orderNo, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: c.rfidCyan.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.qr_code, size: 12, color: c.rfidCyan),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Barcode 128: $barcodeDisplay',
                                        style: TextStyle(color: c.rfidCyan, fontSize: 10.5, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text('Ngày tạo: ${order.createdAt.toString().substring(0, 10)} | NCC: ${order.sourceSupplier}', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF10B981),
                                side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              ),
                              icon: const Icon(Icons.print, size: 15),
                              label: const Text('In Tem Thùng', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                              onPressed: () {
                                PutawayBarcodeModal.show(
                                  context,
                                  barcode: barcodeDisplay,
                                  orderNo: order.orderNo,
                                  itemCount: orderItemCount,
                                  performedBy: 'In Tem Nhập Kho',
                                );
                              },
                            ),
                          ),
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: c.rfidCyan,
                              side: BorderSide(color: c.border),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.qr_code_2, size: 16),
                            label: const Text('Xem mã EPC', style: TextStyle(fontSize: 11)),
                            onPressed: () => _showOrderEpcsDetailDialog(order),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: c.rfidCyan,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.play_arrow, size: 16, color: Color(0xFF2C251E)),
                            label: const Text('Quét đối soát', style: TextStyle(color: Color(0xFF2C251E), fontSize: 11, fontWeight: FontWeight.bold)),
                            onPressed: () {
                              _onOrderSelected(order);
                              setState(() {
                                _currentMode = 0;
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: isCompleted ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isCompleted ? 'Completed' : 'Draft',
                              style: TextStyle(
                                color: isCompleted ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 18, color: c.errorCoral),
                            tooltip: 'Xóa đơn hàng này',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: itemCtx,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: c.bgCard,
                                  title: Text('XÓA ĐƠN HÀNG', style: TextStyle(color: c.errorCoral, fontWeight: FontWeight.bold)),
                                  content: Text('Bạn có chắc muốn xóa đơn "${order.orderNo}" và tất cả chip RFID thuộc đơn này không?', style: TextStyle(color: c.textPrimary)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('HỦY', style: TextStyle(color: c.textSecondary))),
                                    ElevatedButton(
                                      style: ElevatedButton.styleFrom(backgroundColor: c.errorCoral),
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('XÓA ĐƠN', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await _repo.deleteInboundOrder(order.inboundOrderId);
                                setState(() {
                                  if (_selectedLiveOrder?.inboundOrderId == order.inboundOrderId) {
                                    _selectedLiveOrder = null;
                                  }
                                });
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('✅ Đã xóa đơn ${order.orderNo}!')),
                                  );
                                }
                              }
                            },
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
      ),
    );
  }


  Widget _buildCreateReceiptForm(EyeCareColors c) {
    final totalExcelSerials = _receiptCartons.fold<int>(0, (sum, ct) => sum + ((ct['serials'] as List<dynamic>?)?.length ?? 0));
    final hasExcelSerials = totalExcelSerials > 0;

    return Container(
      color: c.bgDeep,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: c.textPrimary),
                    onPressed: () => setState(() => _isCreating = false),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hasExcelSerials ? 'Tạo Phiếu Nhập Hàng Theo File Excel' : 'Tạo Phiếu Nhập & Sinh Mã EPC RFID',
                    style: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              Row(
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: Icon(hasExcelSerials ? Icons.verified : Icons.qr_code_2, color: const Color(0xFF2C251E)),
                    label: Text(
                      hasExcelSerials
                          ? 'LƯU PHIẾU DÙNG MÃ EPC EXCEL · $totalExcelSerials CHIP'
                          : 'LƯU & SINH MÃ EPC DUY NHẤT',
                      style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _saveReceipt(false),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 320,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _receiveNoController,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(labelText: 'Mã phiếu nhập', labelStyle: TextStyle(color: c.textSecondary, fontSize: 12)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _dateController,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(labelText: 'Ngày nhập', labelStyle: TextStyle(color: c.textSecondary, fontSize: 12)),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedWarehouse,
                          dropdownColor: c.bgCardElevated,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(labelText: 'Kho lưu trữ', labelStyle: TextStyle(color: c.textSecondary, fontSize: 12)),
                          items: const [
                            DropdownMenuItem(value: 'Kho 01', child: Text('Kho 01')),
                            DropdownMenuItem(value: 'Kho 02', child: Text('Kho 02')),
                            DropdownMenuItem(value: 'Kho 03', child: Text('Kho 03')),
                          ],
                          onChanged: (val) {
                            if (val != null) setState(() => _selectedWarehouse = val);
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _noteController,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(labelText: 'Ghi chú', labelStyle: TextStyle(color: c.textSecondary, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                              icon: const Icon(Icons.add, size: 16, color: Color(0xFF2C251E)),
                              label: const Text('Thêm mặt hàng', style: TextStyle(color: Color(0xFF2C251E), fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: () => _showAddProductRowDialog(c),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: c.rfidCyan,
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              icon: const Icon(Icons.file_open, size: 16, color: Color(0xFF2C251E)),
                              label: const Text('Nạp từ File Excel', style: TextStyle(color: Color(0xFF2C251E), fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: _importGoodsReceiveExcel,
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFF10B981),
                                side: const BorderSide(color: Color(0xFF10B981)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              icon: const Icon(Icons.download, size: 16),
                              label: const Text('Tải File Mẫu (.xlsx)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: _downloadGoodsReceiveTemplate,
                            ),
                            const SizedBox(width: 10),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: c.textSecondary,
                                side: BorderSide(color: c.border),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              icon: const Icon(Icons.info_outline, size: 16),
                              label: const Text('Cấu Trúc File Mẫu 4 Cột', style: TextStyle(fontSize: 12)),
                              onPressed: () => _showTemplateDialog(c),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _receiptCartons.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.inventory_2_outlined, size: 54, color: c.textMuted),
                                      const SizedBox(height: 12),
                                      Text(
                                        'Chưa có mặt hàng nào trong phiếu nhập.',
                                        style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Bấm "+ Thêm mặt hàng" để nhập thủ công hoặc "Nạp từ File Excel" để import.',
                                        style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                                      ),
                                    ],
                                  ),
                                )
                              : SingleChildScrollView(
                                  child: Table(
                                    border: TableBorder.all(color: c.border),
                                    columnWidths: const {
                                      0: FlexColumnWidth(2),
                                      1: FlexColumnWidth(1.8),
                                      2: FlexColumnWidth(2.5),
                                      3: FlexColumnWidth(1.1),
                                      4: FlexColumnWidth(3),
                                      5: FlexColumnWidth(0.8),
                                    },
                                    children: [
                                      TableRow(
                                        decoration: BoxDecoration(color: c.bgCardElevated),
                                        children: [
                                          Padding(padding: const EdgeInsets.all(10), child: Text('CARTON CODE', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5))),
                                          Padding(padding: const EdgeInsets.all(10), child: Text('BARCODE', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5))),
                                          Padding(padding: const EdgeInsets.all(10), child: Text('NAME', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5))),
                                          Padding(padding: const EdgeInsets.all(10), child: Text('SỐ LƯỢNG', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5))),
                                          Padding(padding: const EdgeInsets.all(10), child: Text('MÃ EPC', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5))),
                                          Padding(padding: const EdgeInsets.all(10), child: Text('XÓA', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 11.5))),
                                        ],
                                      ),
                                      for (int i = 0; i < _receiptCartons.length; i++)
                                        TableRow(
                                          children: [
                                            Padding(padding: const EdgeInsets.all(10), child: Text(_receiptCartons[i]['cartonBox'], style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12))),
                                            Padding(padding: const EdgeInsets.all(10), child: Text(_receiptCartons[i]['productCode'], style: TextStyle(color: c.textSecondary, fontFamily: 'Courier', fontSize: 11))),
                                            Padding(padding: const EdgeInsets.all(10), child: Text(_receiptCartons[i]['productName'], style: TextStyle(color: c.textPrimary, fontSize: 12))),
                                            Padding(padding: const EdgeInsets.all(10), child: Text('${_receiptCartons[i]['quantity']}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13))),
                                            Padding(
                                              padding: const EdgeInsets.all(6),
                                              child: (_receiptCartons[i]['serials'] as List<dynamic>?)?.isNotEmpty ?? false
                                                  ? OutlinedButton.icon(
                                                      style: OutlinedButton.styleFrom(
                                                        foregroundColor: c.rfidCyan,
                                                        side: BorderSide(color: c.border),
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      ),
                                                      icon: const Icon(Icons.remove_red_eye, size: 14),
                                                      label: Text(
                                                        'Xem ${(_receiptCartons[i]['serials'] as List).length} Serial/EPC',
                                                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold),
                                                      ),
                                                      onPressed: () => _showSerialListDialog(
                                                        _receiptCartons[i]['cartonBox'],
                                                        _receiptCartons[i]['productName'],
                                                        _receiptCartons[i]['serials'],
                                                        c,
                                                      ),
                                                    )
                                                  : Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: c.rfidCyan.withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
                                                      ),
                                                      child: Text(
                                                        '⚡ Tự động sinh ${_receiptCartons[i]['quantity']} mã EPC',
                                                        style: TextStyle(color: c.rfidCyan, fontSize: 10.5, fontWeight: FontWeight.bold),
                                                      ),
                                                    ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: IconButton(
                                                icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                                onPressed: () {
                                                  setState(() {
                                                    _receiptCartons.removeAt(i);
                                                  });
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

}
