import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/warehouse_repository.dart';
import '../../services/uhf_service.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/excel_import_service.dart';
import '../../services/tower_light_service.dart';
import '../../services/mysql_sync_service.dart';
import '../../widgets/tower_light_widget.dart';
import '../../models/wms_models.dart';
import '../../models/tag_info.dart';

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
  final MySqlSyncService _mysqlSync = MySqlSyncService();

  int _currentMode = 0; // 0: Live RFID Station, 1: Orders List & Excel
  bool _isCreating = false;

  final TextEditingController _receiveNoController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  String _selectedWarehouse = 'Kho 01';

  // Live Station State
  InboundOrder? _selectedLiveOrder;
  String _selectedLiveLocation = '';
  final TextEditingController _palletController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();
  final TextEditingController _prodNameController = TextEditingController();
  final Map<String, TagInfo> _scannedTags = {};
  bool _isScanning = false;
  bool _isSaving = false;
  bool _filterOnlyOrderEpcs = true; // Mặc định BẬT: Chỉ nhận các mã EPC có trong đơn/file đang đối soát
  int _stationTab = 0; // 0: Đã quét khớp, 1: Chưa quét trong đơn
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
    if (_repo.locations.isNotEmpty) {
      _selectedLiveLocation = _repo.locations.first.locationId;
    }

    // Tự động kéo danh sách phiếu nhập mới nhất từ MySQL về khi mở trạm
    Future.microtask(() async {
      await _mysqlSync.syncNow();
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

    _initTagListener();
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

  /// Kiểm tra xem mã EPC quét được có thuộc đơn hàng / tệp Excel đang đối soát hay không
  bool _isTagValidForCurrentOrder(String epc) {
    if (!_filterOnlyOrderEpcs || _selectedLiveOrder == null) return true;
    final expectedItems = _repo.getItemsByOrderNo(_selectedLiveOrder!.orderNo);
    if (expectedItems.isEmpty) return true; // Nếu đơn chưa gán danh sách Item thì không lọc
    final expectedEpcs = expectedItems.map((i) => i.epc.toUpperCase()).toSet();
    return expectedEpcs.contains(epc.toUpperCase());
  }

  void _onOrderSelected(InboundOrder? order) {
    setState(() {
      _selectedLiveOrder = order;
      _scannedTags.clear();
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
    if (_isAutoSaving || _isSaving) return;
    _isAutoSaving = true;

    try {
      final pallet = _palletController.text.trim().isEmpty ? 'PL-01' : _palletController.text.trim().toUpperCase();
      final sku = _skuController.text.trim();
      final prodName = _prodNameController.text.trim();
      final orderNo = _selectedLiveOrder?.orderNo;

      final saved = await _repo.confirmHandheldInbound(
        orderNo: orderNo,
        palletCode: pallet,
        locationId: _selectedLiveLocation.isNotEmpty ? _selectedLiveLocation : 'LOC-A1-01-01',
        scannedEpcs: _scannedTags.keys.toList(),
        defaultSku: sku.isNotEmpty ? sku : 'SKU-INBOUND',
        defaultProductName: prodName.isNotEmpty ? prodName : 'Hàng nhập kho',
      );

      debugPrint('⚡ [ZERO-TOUCH AUTO] Đã tự động nhập kho $saved chip cho đơn $orderNo');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 3),
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('✅ TỰ ĐỘNG NHẬP KHO THÀNH CÔNG: $orderNo ($saved chip) -> Pallet $pallet!'),
                ),
              ],
            ),
          ),
        );
      }

      // Tự động đặt lại sau 3 giây để sẵn sàng quét thùng tiếp theo
      _autoResetTimer?.cancel();
      _autoResetTimer = Timer(const Duration(milliseconds: 3000), () {
        if (mounted) {
          setState(() {
            _selectedLiveOrder = null;
            _scannedTags.clear();
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
      // 🔴 ĐÈN ĐỎ + CÒI: Cảnh báo quét trúng mã chip không có trong đơn / sai hàng
      _towerLight.triggerWarningRed(
        withBuzzer: true,
        reason: 'Phát hiện SAI HÀNG: Chip ${tag.epc} không có trong đơn đối soát!',
      );
      return;
    }

    if (_uhf.filterDuplicates && _scannedTags.containsKey(tag.epc)) {
      return; // Thẻ đã đọc rồi thì bỏ qua không đọc lại
    }

    _scannedTags[tag.epc] = tag;

    // Đánh giá số lượng thực tế so với đơn hàng
    final expectedItems = _selectedLiveOrder != null ? _repo.getItemsByOrderNo(_selectedLiveOrder!.orderNo) : <Item>[];
    final expectedCount = expectedItems.length;

    if (expectedCount > 0) {
      final matchedCount = _scannedTags.length;
      if (matchedCount >= expectedCount) {
        // 🟢 ĐÈN XANH: Đủ hàng thông qua (100% khớp đơn)
        _towerLight.triggerPass(
          reason: 'ĐỦ HÀNG THÔNG QUA: $matchedCount/$expectedCount chip khớp 100% (Đơn ${_selectedLiveOrder!.orderNo})',
        );

        // ⚡ TỰ ĐỘNG XÁC NHẬN NHẬP KHO & ĐỒNG BỘ MYSQL (Zero-Touch)
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
    _desktopUhf.removeListener(_onDesktopUhfUpdate);
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
    final expectedItems = _selectedLiveOrder != null ? _repo.getItemsByOrderNo(_selectedLiveOrder!.orderNo) : <Item>[];
    final expectedCount = expectedItems.length;

    if (expectedCount > 0) {
      final matchedCount = _scannedTags.length;
      if (matchedCount >= expectedCount) {
        _towerLight.triggerPass(
          reason: 'HOÀN TẤT ĐỐI SOÁT ($_scanDurationSeconds GIÂY): ĐỦ HÀNG THÔNG QUA ($matchedCount/$expectedCount chip khớp 100%)',
        );
      } else {
        _towerLight.triggerWarningRed(
          withBuzzer: true,
          reason: 'KẾT THÚC QUÉT ($_scanDurationSeconds GIÂY): THIẾU HÀNG! Đã quét $matchedCount/$expectedCount chip (Còn thiếu ${expectedCount - matchedCount})',
        );
      }
    }
  }

  Future<void> _saveLiveInbound() async {
    if (_scannedTags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Chưa có thẻ RFID nào được quét!')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final pallet = _palletController.text.trim().isEmpty ? 'PL-01' : _palletController.text.trim().toUpperCase();
      final sku = _skuController.text.trim();
      final prodName = _prodNameController.text.trim();

      final saved = await _repo.confirmHandheldInbound(
        orderNo: _selectedLiveOrder?.orderNo,
        palletCode: pallet,
        locationId: _selectedLiveLocation,
        scannedEpcs: _scannedTags.keys.toList(),
        defaultSku: sku.isNotEmpty ? sku : 'SKU-INBOUND',
        defaultProductName: prodName.isNotEmpty ? prodName : 'Hàng nhập kho',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('Đã nhập thành công $saved chip RFID vào Pallet $pallet (Vị trí $_selectedLiveLocation)!'),
        ),
      );

      setState(() {
        _scannedTags.clear();
        _uhf.clearTags();
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

  void _showTemplateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.table_chart, color: Color(0xFF10B981), size: 24),
            SizedBox(width: 10),
            Text('Cấu Trúc Tệp Mẫu Nhập Hàng (Template-Goods-Receive.xlsx)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFF38BDF8), size: 18),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Cấu trúc tệp Excel chuẩn gồm 4 cột: CARTON CODE, EPC, BARCODE, NAME. Khi nạp file, hệ thống sẽ lưu đúng mã EPC của từng sản phẩm ở trạng thái CHƯA NHẬP KHO.',
                          style: TextStyle(color: Colors.white70, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Table(
                  border: TableBorder.all(color: const Color(0xFF334155)),
                  columnWidths: const {
                    0: FlexColumnWidth(2),
                    1: FlexColumnWidth(3.2),
                    2: FlexColumnWidth(2),
                    3: FlexColumnWidth(2.2),
                  },
                  children: const [
                    TableRow(
                      decoration: BoxDecoration(color: Color(0xFF0F172A)),
                      children: [
                        Padding(padding: EdgeInsets.all(8), child: Text('CARTON CODE', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('EPC', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('BARCODE', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('NAME', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(padding: EdgeInsets.all(8), child: Text('CARTONTEST0001', style: TextStyle(color: Colors.white, fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('ABCDEF000000000000000001', style: TextStyle(color: Color(0xFF38BDF8), fontFamily: 'Courier', fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('8930000000001', style: TextStyle(color: Colors.white70, fontFamily: 'Courier', fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('Product Test 01', style: TextStyle(color: Colors.white70, fontSize: 11))),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(padding: EdgeInsets.all(8), child: Text('CARTONTEST0001', style: TextStyle(color: Colors.white, fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('ABCDEF000000000000000002', style: TextStyle(color: Color(0xFF38BDF8), fontFamily: 'Courier', fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('8930000000001', style: TextStyle(color: Colors.white70, fontFamily: 'Courier', fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('Product Test 02', style: TextStyle(color: Colors.white70, fontSize: 11))),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(padding: EdgeInsets.all(8), child: Text('CARTONTEST0001', style: TextStyle(color: Colors.white, fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('...', style: TextStyle(color: Colors.white38, fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('8930000000001', style: TextStyle(color: Colors.white70, fontFamily: 'Courier', fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('...', style: TextStyle(color: Colors.white38, fontSize: 11))),
                      ],
                    ),
                    TableRow(
                      children: [
                        Padding(padding: EdgeInsets.all(8), child: Text('CARTONTEST0001', style: TextStyle(color: Colors.white, fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('ABCDEF000000000000000010', style: TextStyle(color: Color(0xFF38BDF8), fontFamily: 'Courier', fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('8930000000001', style: TextStyle(color: Colors.white70, fontFamily: 'Courier', fontSize: 11))),
                        Padding(padding: EdgeInsets.all(8), child: Text('Product Test 10', style: TextStyle(color: Colors.white70, fontSize: 11))),
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
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('ĐÃ HIỂU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showSerialListDialog(String carton, String prodName, List<dynamic> serials) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.qr_code, color: Color(0xFF38BDF8), size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Danh sách Mã EPC RFID: $carton', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  Text('$prodName (${serials.length} chip)', style: const TextStyle(color: Colors.white54, fontSize: 11)),
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
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: Row(
                children: [
                  Text('#${idx + 1}', style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 10),
                  Text(serials[idx].toString(), style: const TextStyle(color: Color(0xFF38BDF8), fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 12)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ĐÓNG', style: TextStyle(color: Colors.white54))),
        ],
      ),
    );
  }



  void _exportAllPendingEpcs() {
    final pendingItems = _repo.items.where((i) => i.status == ItemStatus.pendingInbound).toList();
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

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final totalOrders = previewRows.map((r) => r['orderNo']).toSet().length;
          final totalItems = previewRows.fold<int>(0, (sum, r) => sum + (r['quantity'] as int));
          final bool hasExplicitEpcs = previewRows.any((r) => (r['epc'] as String?)?.isNotEmpty ?? false);

          return AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.file_upload, color: Color(0xFF10B981), size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Import Danh Sách Nhiều Đơn Hàng (Excel)', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        hasExplicitEpcs
                            ? 'Tự động tạo đơn & dùng trực tiếp mã EPC từ file Excel (CHƯA NHẬP KHO)'
                            : 'Tự động tạo đơn & sinh toàn bộ mã EPC ở trạng thái CHƯA NHẬP KHO',
                        style: TextStyle(color: hasExplicitEpcs ? const Color(0xFF10B981) : const Color(0xFF38BDF8), fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 840,
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                        icon: const Icon(Icons.file_open, size: 16, color: Colors.white),
                        label: const Text('Chọn File Excel Từ Máy', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          try {
                            final rows = await _excelService.pickAndParseBatchOrdersExcel();
                            if (rows != null && rows.isNotEmpty) {
                              setDialogState(() {
                                previewRows = rows;
                              });
                              if (!context.mounted) return;
                              final epcCount = rows.where((r) => (r['epc'] as String?)?.isNotEmpty ?? false).length;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  backgroundColor: const Color(0xFF10B981),
                                  content: Text(epcCount > 0
                                      ? 'Đã nạp ${rows.length} dòng ($epcCount mã EPC) từ file Excel!'
                                      : 'Đã nạp ${rows.length} dòng đơn hàng từ file Excel!'),
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
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF10B981),
                          side: const BorderSide(color: Color(0xFF10B981)),
                        ),
                        icon: const Icon(Icons.download, size: 16),
                        label: const Text('Tải File Mẫu PO (.xlsx)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: () async {
                          try {
                            final path = await _excelService.exportBatchOrdersTemplate();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF10B981),
                                duration: const Duration(seconds: 5),
                                content: Text('Đã xuất file mẫu đơn hàng: $path'),
                                action: SnackBarAction(
                                  label: 'SAO CHÉP',
                                  textColor: Colors.white,
                                  onPressed: () {
                                    Clipboard.setData(ClipboardData(text: path));
                                  },
                                ),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi xuất file mẫu: $e')),
                            );
                          }
                        },
                      ),
                      if (previewRows.isNotEmpty) ...[
                        const SizedBox(width: 10),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Color(0xFF334155)),
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
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Text(
                          hasExplicitEpcs
                              ? 'Tổng: $totalOrders đơn/thùng | $totalItems mã EPC'
                              : 'Tổng: $totalOrders đơn | $totalItems sản phẩm',
                          style: TextStyle(
                            color: previewRows.isNotEmpty ? const Color(0xFF10B981) : Colors.white38,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Expanded(
                    child: previewRows.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.upload_file_outlined, size: 56, color: Colors.white24),
                                const SizedBox(height: 12),
                                const Text(
                                  'Chưa có dữ liệu đơn hàng nào được nạp.',
                                  style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                const Text(
                                  'Bấm "Chọn File Excel Từ Máy" để nạp file của bạn hoặc "Tải File Mẫu PO (.xlsx)" để tạo file mẫu.',
                                  style: TextStyle(color: Colors.white38, fontSize: 11.5),
                                ),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            child: Table(
                              border: TableBorder.all(color: const Color(0xFF334155)),
                              columnWidths: const {
                                0: FlexColumnWidth(2),
                                1: FlexColumnWidth(3),
                                2: FlexColumnWidth(1.8),
                                3: FlexColumnWidth(2.5),
                                4: FlexColumnWidth(1.0),
                                5: FlexColumnWidth(2.2),
                              },
                              children: [
                                TableRow(
                                  decoration: const BoxDecoration(color: Color(0xFF0F172A)),
                                  children: [
                                    const Padding(padding: EdgeInsets.all(8), child: Text('Mã Đơn / Thùng', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                                    Padding(padding: const EdgeInsets.all(8), child: Text(hasExplicitEpcs ? 'Mã EPC (Từ File)' : 'Nhà Cung Cấp', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                                    const Padding(padding: EdgeInsets.all(8), child: Text('Mã SKU', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                                    const Padding(padding: EdgeInsets.all(8), child: Text('Tên Sản Phẩm', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                                    const Padding(padding: EdgeInsets.all(8), child: Text('Số Lượng', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                                    Padding(padding: const EdgeInsets.all(8), child: Text(hasExplicitEpcs ? 'Trạng Thái EPC' : 'EPC Sẽ Sinh', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11))),
                                  ],
                                ),
                                for (var row in previewRows)
                                  TableRow(
                                    children: [
                                      Padding(padding: const EdgeInsets.all(8), child: Text(row['orderNo'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11))),
                                      Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: (row['epc'] != null && (row['epc'] as String).isNotEmpty)
                                            ? Text(row['epc'], style: const TextStyle(color: Color(0xFF38BDF8), fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 11))
                                            : Text(row['supplier'], style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                      ),
                                      Padding(padding: const EdgeInsets.all(8), child: Text(row['sku'], style: const TextStyle(color: Colors.white, fontFamily: 'Courier', fontSize: 11))),
                                      Padding(padding: const EdgeInsets.all(8), child: Text(row['productName'], style: const TextStyle(color: Colors.white70, fontSize: 11))),
                                      Padding(padding: const EdgeInsets.all(8), child: Text('${row['quantity']}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12))),
                                      Padding(
                                        padding: const EdgeInsets.all(4),
                                        child: (row['epc'] != null && (row['epc'] as String).isNotEmpty)
                                            ? Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                                                ),
                                                child: const Text(
                                                  '✓ Dùng EPC từ file',
                                                  style: TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              )
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
                                  ),
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
                child: const Text('HỦY', style: TextStyle(color: Colors.white54)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: previewRows.isNotEmpty ? const Color(0xFF10B981) : Colors.grey.shade800,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                icon: Icon(hasExplicitEpcs ? Icons.verified : Icons.check_circle, color: Colors.white, size: 18),
                label: Text(
                  hasExplicitEpcs
                      ? 'XÁC NHẬN IMPORT DÙNG EPC TỪ FILE ($totalOrders ĐƠN)'
                      : 'XÁC NHẬN IMPORT ($totalOrders ĐƠN)',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                                  epc: epcVal, // DÙNG CHÍNH XÁC MÃ EPC TỪ CỘT 2 CỦA EXCEL!
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
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
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
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Text('Mã đơn / Thùng: ${order.orderNo} | Trạng thái: CHƯA NHẬP KHO (PENDING)', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 12)),
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
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Color(0xFF38BDF8), size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fromExcel
                            ? 'Toàn bộ ${items.length} mã EPC từ file Excel đã được dùng trực tiếp làm mã chip RFID EPC (không sinh mã ngẫu nhiên mới). Vui lòng chuyển sang "Trạm Quét RFID Live" để quét đối soát khi hàng về.'
                            : 'Các mã EPC này đã được tạo trong CSDL ở trạng thái CHƯA NHẬP KHO. Hãy in/ghi nhãn lên hàng hóa và đưa qua Trạm quét RFID để hoàn tất nhập kho.',
                        style: const TextStyle(color: Colors.white70, fontSize: 11.5),
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
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          Text('#${index + 1}', style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.epc, style: const TextStyle(color: Color(0xFF38BDF8), fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 12)),
                                Text('${item.productName} (${item.sku}) | ${item.serialNumber}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
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
              foregroundColor: Colors.white70,
              side: const BorderSide(color: Color(0xFF334155)),
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
            icon: const Icon(Icons.play_arrow, size: 16, color: Colors.white),
            label: const Text('Quét Nhập Kho Ngay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(
          children: [
            const Icon(Icons.list_alt, color: Color(0xFF38BDF8), size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chi tiết mã EPC - ${order.orderNo}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text('Tổng số: ${items.length} chip | Đã nhập: ${items.where((i) => i.status == ItemStatus.inStock).length} | Chưa nhập: ${items.where((i) => i.status != ItemStatus.inStock).length}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 700,
          height: 450,
          child: items.isEmpty
              ? const Center(
                  child: Text('Chưa có mã EPC nào được gắn cho đơn này.', style: TextStyle(color: Colors.white54)),
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
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: isInStock ? const Color(0xFF10B981).withValues(alpha: 0.4) : const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          Text('#${index + 1}', style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.epc, style: TextStyle(color: isInStock ? const Color(0xFF34D399) : const Color(0xFF38BDF8), fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 12)),
                                Text('${item.productName} (${item.sku}) | ${item.serialNumber} ${item.locationId != null ? "| Vị trí: ${item.locationId}" : ""}', style: const TextStyle(color: Colors.white54, fontSize: 10)),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ĐÓNG', style: TextStyle(color: Colors.white54))),
        ],
      ),
    );
  }

  void _showAddProductRowDialog() {
    final skuCtrl = TextEditingController(text: 'SKU-001');
    final nameCtrl = TextEditingController(text: 'Sản phẩm A');
    final qtyCtrl = TextEditingController(text: '10');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Thêm Sản Phẩm Vào Đơn Nhập', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: skuCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Mã SKU', labelStyle: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Tên sản phẩm', labelStyle: TextStyle(color: Colors.white70)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: qtyCtrl,
              keyboardType: TextInputType.number,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: const InputDecoration(labelText: 'Số lượng cần nhập', labelStyle: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('HỦY', style: TextStyle(color: Colors.white54))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () {
              final sku = skuCtrl.text.trim();
              final name = nameCtrl.text.trim();
              final qty = int.tryParse(qtyCtrl.text.trim()) ?? 1;
              if (sku.isNotEmpty && name.isNotEmpty && qty > 0) {
                setState(() {
                  _receiptCartons.add({
                    'cartonBox': 'THUNG-${_receiptCartons.length + 1}',
                    'productCode': sku,
                    'productName': name,
                    'quantity': qty,
                    'serials': <String>[],
                  });
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('THÊM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

    final order = InboundOrder(
      inboundOrderId: 'INB-${DateTime.now().millisecondsSinceEpoch}',
      orderNo: code,
      sourceSupplier: 'Giltech Solutions Supplier',
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
          ));
          itemSeq++;
        }
      }
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

    setState(() => _isCreating = false);

    if (mounted) {
      _showGeneratedEpcsDialog(order, generatedItems, fromExcel: hasExplicitSerials);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isCreating) {
      return _buildCreateReceiptForm();
    }

    return Container(
      color: const Color(0xFF0B1120),
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
                  const Text(
                    'GOODS RECEIVE & RFID INBOUND STATION',
                    style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text(
                        'Quản Lý Nhập Kho',
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildModeTab(0, 'Trạm Quét RFID Live', Icons.sensors),
                            _buildModeTab(1, 'Danh Sách Phiếu Nhập', Icons.list_alt),
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
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF334155)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('LÀM MỚI'),
                    onPressed: () async {
                      await _mysqlSync.syncNow();
                      await _repo.refreshFromDatabase();
                      if (mounted) {
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            backgroundColor: Color(0xFF10B981),
                            duration: Duration(seconds: 2),
                            content: Text('Đã làm mới và đồng bộ danh sách phiếu nhập từ MySQL!'),
                          ),
                        );
                      }
                    },
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add, color: Colors.white, size: 18),
                    label: const Text('TẠO PHIẾU EXCEL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
            child: _currentMode == 0 ? _buildLiveRfidStationView() : _buildReceiptsList(),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab(int mode, String title, IconData icon) {
    final isSelected = _currentMode == mode;
    return InkWell(
      onTap: () => setState(() => _currentMode = mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: isSelected ? Colors.white : Colors.white60),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
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

  Widget _buildLiveRfidStationView() {
    final scannedCount = _scannedTags.length;
    final locations = _repo.locations;
    final orders = _repo.inboundOrders;
    final expectedOrderItems = _selectedLiveOrder != null ? _repo.getItemsByOrderNo(_selectedLiveOrder!.orderNo) : <Item>[];
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
              // Tháp đèn tín hiệu công nghiệp CTP50-3T-D-J
              const TowerLightWidget(),
              const SizedBox(height: 12),

              // Target location card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF334155)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📍 VỊ TRÍ & ĐỐI SOÁT TỰ ĐỘNG', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 10),

                    // Card Tự Động Nhận Diện Đơn Hàng / Thùng
                    if (_selectedLiveOrder == null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.bolt, color: Color(0xFF38BDF8), size: 20),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('TỰ ĐỘNG KHỚP THEO MÃ CHIP', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5)),
                                  SizedBox(height: 2),
                                  Text('Quét chip bất kỳ, hệ thống sẽ tự động nhận diện đúng đơn và đếm số lượng.', style: TextStyle(color: Colors.white60, fontSize: 10.5, height: 1.2)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: const Color(0xFF10B981)),
                                      ),
                                      child: const Text('⚡ ĐÃ KHỚP ĐƠN', style: TextStyle(color: Color(0xFF10B981), fontSize: 9.5, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _selectedLiveOrder!.orderNo,
                                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                  ],
                                ),
                                InkWell(
                                  onTap: () {
                                    setState(() {
                                      _selectedLiveOrder = null;
                                      _scannedTags.clear();
                                      _uhf.clearTags();
                                      _desktopUhf.clearTags();
                                    });
                                  },
                                  child: const Text('Đổi đơn khác', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w500)),
                                ),
                              ],
                            ),
                            if (_selectedLiveOrder!.details.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${_selectedLiveOrder!.details.first.productName} (SKU: ${_selectedLiveOrder!.details.first.sku})',
                                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
                              ),
                            ],
                          ],
                        ),
                      ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Vị trí kệ:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                initialValue: locations.any((l) => l.locationId == _selectedLiveLocation) ? _selectedLiveLocation : (locations.isNotEmpty ? locations.first.locationId : null),
                                isExpanded: true,
                                dropdownColor: const Color(0xFF1E293B),
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF0F172A),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                items: locations.map((l) => DropdownMenuItem(value: l.locationId, child: Text(l.locationCode))).toList(),
                                onChanged: (val) => setState(() => _selectedLiveLocation = val ?? ''),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Mã Pallet:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                              const SizedBox(height: 4),
                              TextField(
                                controller: _palletController,
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFF0F172A),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Scan Telemetry Card
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: _isScanning ? const Color(0xFF0F2B48) : const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _isScanning ? const Color(0xFF38BDF8) : const Color(0xFF334155), width: _isScanning ? 2 : 1),
                ),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(_isScanning ? 'ĐẦU ĐỌC RFID ĐANG BẬT' : 'ĐẦU ĐỌC SẴN SÀNG', style: TextStyle(color: _isScanning ? const Color(0xFF38BDF8) : Colors.white70, fontWeight: FontWeight.bold, fontSize: 12)),
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
                                  color: _filterOnlyOrderEpcs ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: _filterOnlyOrderEpcs ? const Color(0xFF10B981) : const Color(0xFF334155)),
                                ),
                                child: Text(
                                  _filterOnlyOrderEpcs ? 'Lọc theo file: BẬT' : 'Lọc theo file: TẮT',
                                  style: TextStyle(color: _filterOnlyOrderEpcs ? const Color(0xFF10B981) : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                setState(() {
                                  _uhf.filterDuplicates = !_uhf.filterDuplicates;
                                  _desktopUhf.ignoreAlreadyScanned = _uhf.filterDuplicates;
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _uhf.filterDuplicates ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFF0F172A),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: _uhf.filterDuplicates ? const Color(0xFF10B981) : const Color(0xFF334155)),
                                ),
                                child: Text(
                                  _uhf.filterDuplicates ? 'Lọc trùng: BẬT' : 'Lọc trùng: TẮT',
                                  style: TextStyle(color: _uhf.filterDuplicates ? const Color(0xFF10B981) : Colors.white54, fontSize: 10, fontWeight: FontWeight.bold),
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
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text('Anten Cổng:', style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
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
                                        ? const Color(0xFF0284C7).withValues(alpha: 0.25)
                                        : Colors.transparent,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF38BDF8)
                                          : const Color(0xFF334155),
                                    ),
                                  ),
                                  child: Text(
                                    'ANT $ant',
                                    style: TextStyle(
                                      color: isSelected
                                          ? const Color(0xFF38BDF8)
                                          : Colors.white38,
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

                    Text('$scannedCount', style: const TextStyle(color: Colors.white, fontSize: 46, fontWeight: FontWeight.w900)),
                    Text(
                      _selectedLiveOrder != null ? 'Thẻ hợp lệ theo đơn ${_selectedLiveOrder!.orderNo}' : 'Thẻ RFID đã quét vào lô',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),

                    if (_selectedLiveOrder != null && expectedCount > 0) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF334155)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('TIẾN ĐỘ ĐỐI SOÁT FILE', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold)),
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
                                backgroundColor: const Color(0xFF1E293B),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  matchedCount == expectedCount && expectedCount > 0 ? const Color(0xFF10B981) : const Color(0xFF0284C7),
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
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.timer_outlined, size: 14, color: Color(0xFF38BDF8)),
                              SizedBox(width: 6),
                              Text('Thời gian quét:', style: TextStyle(color: Colors.white70, fontSize: 11)),
                            ],
                          ),
                          DropdownButton<int>(
                            value: _scanDurationSeconds,
                            dropdownColor: const Color(0xFF1E293B),
                            underline: const SizedBox(),
                            isDense: true,
                            style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                            items: const [
                              DropdownMenuItem(value: 3, child: Text('⚡ 3 Giây')),
                              DropdownMenuItem(value: 5, child: Text('⏱️ 5 Giây (Chuẩn)')),
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
                              backgroundColor: _isScanning ? const Color(0xFFEF4444) : const Color(0xFF0284C7),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: Icon(_isScanning ? Icons.stop_circle_outlined : Icons.sensors, color: Colors.white, size: 18),
                            label: Text(
                              _isScanning
                                  ? (_scanDurationSeconds > 0 ? 'ĐANG QUÉT (${_scanCountdown}s) - DỪNG' : 'ĐANG QUÉT - BẤM DỪNG')
                                  : (_scanDurationSeconds > 0 ? 'BẮT ĐẦU QUÉT (${_scanDurationSeconds}s)' : 'BẮT ĐẦU QUÉT RFID'),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                            onPressed: _toggleLiveScan,
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Color(0xFF334155)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            setState(() {
                              _scannedTags.clear();
                              _uhf.clearTags();
                            });
                            _desktopUhf.clearTags();
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
                    backgroundColor: scannedCount > 0 ? const Color(0xFF10B981) : Colors.grey.shade800,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.check_circle, color: Colors.white),
                  label: Text(
                    _isSaving
                        ? 'Đang lưu...'
                        : (_selectedLiveOrder != null
                            ? 'XÁC NHẬN NHẬP ĐƠN (${_selectedLiveOrder!.orderNo}: $scannedCount CHIP)'
                            : 'XÁC NHẬN NHẬP KHO ($scannedCount CHIP)'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  onPressed: (_isSaving || scannedCount == 0) ? null : _saveLiveInbound,
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
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155)),
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
                              color: _stationTab == 0 ? const Color(0xFF0284C7) : const Color(0xFF0F172A),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _stationTab == 0 ? const Color(0xFF38BDF8) : const Color(0xFF334155)),
                            ),
                            child: Text(
                              'Đã quét khớp ($matchedCount)',
                              style: TextStyle(
                                color: _stationTab == 0 ? Colors.white : Colors.white60,
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
                                color: _stationTab == 1 ? const Color(0xFFF59E0B).withValues(alpha: 0.3) : const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: _stationTab == 1 ? const Color(0xFFF59E0B) : const Color(0xFF334155)),
                              ),
                              child: Text(
                                'Chưa quét (${unscannedItems.length})',
                                style: TextStyle(
                                  color: _stationTab == 1 ? const Color(0xFFF59E0B) : Colors.white60,
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
                const SizedBox(height: 12),
                Expanded(
                  child: _stationTab == 0
                      ? (scannedCount == 0
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.nfc, size: 48, color: Colors.white24),
                                  const SizedBox(height: 10),
                                  Text(
                                    _selectedLiveOrder != null
                                        ? 'Chưa có thẻ RFID nào được đọc.\nBấm "QUÉT" để bắt đầu đối soát các chip trong file đơn hàng.'
                                        : 'Chưa có thẻ RFID nào được đọc.',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.white54, fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              itemCount: _scannedTags.length,
                              separatorBuilder: (_, _) => const Divider(color: Color(0xFF334155), height: 1),
                              itemBuilder: (context, index) {
                                final tag = _scannedTags.values.toList().reversed.toList()[index];
                                final antLabel = tag.ant.isNotEmpty ? tag.ant : '1';
                                final isAnt2 = antLabel == '2';
                                final matchedItem = expectedOrderItems.where((i) => i.epc.toUpperCase() == tag.epc.toUpperCase()).firstOrNull;

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                  child: Row(
                                    children: [
                                      Text('#${index + 1}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              tag.epc,
                                              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold),
                                            ),
                                            if (matchedItem != null) ...[
                                              const SizedBox(height: 2),
                                              Text(
                                                '${matchedItem.productName} | SKU: ${matchedItem.sku} ${matchedItem.serialNumber.isNotEmpty ? "| SN: ${matchedItem.serialNumber}" : ""}',
                                                style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11),
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
                                          color: (isAnt2 ? const Color(0xFF8B5CF6) : const Color(0xFF0284C7)).withValues(alpha: 0.2),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: isAnt2 ? const Color(0xFFA78BFA) : const Color(0xFF38BDF8)),
                                        ),
                                        child: Text(
                                          'ANT $antLabel',
                                          style: TextStyle(
                                            color: isAnt2 ? const Color(0xFFA78BFA) : const Color(0xFF38BDF8),
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
                                      Text('${tag.count} lần', style: const TextStyle(color: Colors.white38, fontSize: 10)),
                                    ],
                                  ),
                                );
                              },
                            ))
                      : (unscannedItems.isEmpty
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
                              separatorBuilder: (_, _) => const Divider(color: Color(0xFF334155), height: 1),
                              itemBuilder: (context, index) {
                                final item = unscannedItems[index];
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                  child: Row(
                                    children: [
                                      Text('#${index + 1}', style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.epc,
                                              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontSize: 13, fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${item.productName} | SKU: ${item.sku} ${item.serialNumber.isNotEmpty ? "| SN: ${item.serialNumber}" : ""}',
                                              style: const TextStyle(color: Colors.white70, fontSize: 11),
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
                            )),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildReceiptsList() {
    final inboundOrders = _repo.inboundOrders;
    final pendingCount = _repo.items.where((i) => i.status == ItemStatus.pendingInbound).length;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        children: [
          // Top Action Toolbar (Responsive Wrap to prevent overflow)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFF334155))),
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
                    const Icon(Icons.list_alt, color: Color(0xFF38BDF8), size: 20),
                    Text(
                      'Danh Sách Đơn Nhập Kho (${inboundOrders.length} đơn)',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
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
                        label: const Text('Sao Chép Tất Cả EPC (Chờ Nhập)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: _exportAllPendingEpcs,
                      ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF38BDF8),
                        side: const BorderSide(color: Color(0xFF38BDF8)),
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
                      icon: const Icon(Icons.add, size: 15, color: Colors.white),
                      label: const Text('Tạo Phiếu Mới', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
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
                        const Icon(Icons.assignment_outlined, size: 64, color: Colors.white24),
                        const SizedBox(height: 14),
                        const Text(
                          'Chưa có đơn nhập kho nào trong cơ sở dữ liệu.',
                          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Bạn có thể tạo mới phiếu nhập hoặc Import danh sách nhiều đơn hàng từ Excel.',
                          style: TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                              icon: const Icon(Icons.file_upload, color: Colors.white),
                              label: const Text('Import Danh Sách Đơn (Excel)', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              onPressed: _showBatchImportOrdersDialog,
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                              icon: const Icon(Icons.add, color: Colors.white),
                              label: const Text('Tạo Phiếu Nhập Mới', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                    separatorBuilder: (_, index) => const Divider(color: Color(0xFF334155), height: 1),
                    itemBuilder: (context, index) {
                      final order = inboundOrders[index];
                      final isCompleted = order.status == InboundOrderStatus.completed;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.article, color: Color(0xFF38BDF8), size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(order.orderNo, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text('Ngày tạo: ${order.createdAt.toString().substring(0, 10)} | NCC: ${order.sourceSupplier}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF38BDF8),
                              side: const BorderSide(color: Color(0xFF334155)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.qr_code_2, size: 16),
                            label: const Text('Xem mã EPC', style: TextStyle(fontSize: 11)),
                            onPressed: () => _showOrderEpcsDetailDialog(order),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF0284C7),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            ),
                            icon: const Icon(Icons.play_arrow, size: 16, color: Colors.white),
                            label: const Text('Quét đối soát', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
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

  Widget _buildCreateReceiptForm() {
    final totalExcelSerials = _receiptCartons.fold<int>(0, (sum, c) => sum + ((c['serials'] as List<dynamic>?)?.length ?? 0));
    final hasExcelSerials = totalExcelSerials > 0;

    return Container(
      color: const Color(0xFF0B1120),
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
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => setState(() => _isCreating = false),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    hasExcelSerials ? 'Tạo Phiếu Nhập Hàng (Theo File Excel)' : 'Tạo Phiếu Nhập & Sinh Mã EPC RFID',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
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
                    icon: Icon(hasExcelSerials ? Icons.verified : Icons.qr_code_2, color: Colors.white),
                    label: Text(
                      hasExcelSerials
                          ? 'LƯU PHIẾU DÙNG MÃ EPC EXCEL ($totalExcelSerials CHIP)'
                          : 'LƯU & SINH MÃ EPC DUY NHẤT',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
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
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _receiveNoController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(labelText: 'Mã phiếu nhập', labelStyle: TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _dateController,
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(labelText: 'Ngày nhập', labelStyle: TextStyle(color: Colors.white70, fontSize: 12)),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedWarehouse,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(labelText: 'Kho lưu trữ', labelStyle: TextStyle(color: Colors.white70, fontSize: 12)),
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
                          style: const TextStyle(color: Colors.white, fontSize: 13),
                          decoration: const InputDecoration(labelText: 'Ghi chú', labelStyle: TextStyle(color: Colors.white70, fontSize: 12)),
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
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                              icon: const Icon(Icons.add, size: 16, color: Colors.white),
                              label: const Text('Thêm mặt hàng', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              onPressed: _showAddProductRowDialog,
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0284C7),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              icon: const Icon(Icons.file_open, size: 16, color: Colors.white),
                              label: const Text('Nạp từ File Excel (.xlsx / .csv)', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
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
                                foregroundColor: Colors.white70,
                                side: const BorderSide(color: Color(0xFF334155)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                              icon: const Icon(Icons.info_outline, size: 16),
                              label: const Text('Cấu Trúc File Mẫu (4 Cột)', style: TextStyle(fontSize: 12)),
                              onPressed: _showTemplateDialog,
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
                                      const Icon(Icons.inventory_2_outlined, size: 54, color: Colors.white24),
                                      const SizedBox(height: 12),
                                      const Text(
                                        'Chưa có mặt hàng nào trong phiếu nhập.',
                                        style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'Bấm "+ Thêm mặt hàng" để nhập thủ công hoặc "Nạp từ File Excel (.xlsx / .csv)" để import.',
                                        style: TextStyle(color: Colors.white38, fontSize: 11.5),
                                      ),
                                    ],
                                  ),
                                )
                              : SingleChildScrollView(
                                  child: Table(
                                    border: TableBorder.all(color: const Color(0xFF334155)),
                                    columnWidths: const {
                                      0: FlexColumnWidth(2),
                                      1: FlexColumnWidth(1.8),
                                      2: FlexColumnWidth(2.5),
                                      3: FlexColumnWidth(1.1),
                                      4: FlexColumnWidth(3),
                                      5: FlexColumnWidth(0.8),
                                    },
                                    children: [
                                      const TableRow(
                                        decoration: BoxDecoration(color: Color(0xFF0F172A)),
                                        children: [
                                          Padding(padding: EdgeInsets.all(10), child: Text('CARTON CODE', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5))),
                                          Padding(padding: EdgeInsets.all(10), child: Text('BARCODE', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5))),
                                          Padding(padding: EdgeInsets.all(10), child: Text('NAME', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5))),
                                          Padding(padding: EdgeInsets.all(10), child: Text('SỐ LƯỢNG', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5))),
                                          Padding(padding: EdgeInsets.all(10), child: Text('MÃ EPC', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5))),
                                          Padding(padding: EdgeInsets.all(10), child: Text('XÓA', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5))),
                                        ],
                                      ),
                                      for (int i = 0; i < _receiptCartons.length; i++)
                                        TableRow(
                                          children: [
                                            Padding(padding: const EdgeInsets.all(10), child: Text(_receiptCartons[i]['cartonBox'], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12))),
                                            Padding(padding: const EdgeInsets.all(10), child: Text(_receiptCartons[i]['productCode'], style: const TextStyle(color: Colors.white70, fontFamily: 'Courier', fontSize: 11))),
                                            Padding(padding: const EdgeInsets.all(10), child: Text(_receiptCartons[i]['productName'], style: const TextStyle(color: Colors.white, fontSize: 12))),
                                            Padding(padding: const EdgeInsets.all(10), child: Text('${_receiptCartons[i]['quantity']}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13))),
                                            Padding(
                                              padding: const EdgeInsets.all(6),
                                              child: (_receiptCartons[i]['serials'] as List<dynamic>?)?.isNotEmpty ?? false
                                                  ? OutlinedButton.icon(
                                                      style: OutlinedButton.styleFrom(
                                                        foregroundColor: const Color(0xFF38BDF8),
                                                        side: const BorderSide(color: Color(0xFF334155)),
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
                                                      ),
                                                    )
                                                  : Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                                                        borderRadius: BorderRadius.circular(4),
                                                        border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.3)),
                                                      ),
                                                      child: Text(
                                                        '⚡ Tự động sinh ${_receiptCartons[i]['quantity']} mã EPC (Chưa nhập)',
                                                        style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold),
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
