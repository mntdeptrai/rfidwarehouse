import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/tag_info.dart';
import '../models/wms_models.dart';
import '../services/uhf_service.dart';
import '../services/warehouse_repository.dart';
import '../widgets/hardware_status_appbar.dart';

class InboundScreen extends StatefulWidget {
  const InboundScreen({super.key});

  @override
  State<InboundScreen> createState() => _InboundScreenState();
}

class _InboundScreenState extends State<InboundScreen> with SingleTickerProviderStateMixin {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();

  late TabController _tabController;
  StreamSubscription<TagInfo>? _tagSubscription;
  StreamSubscription<bool>? _triggerSubscription;

  // Cấu hình nhập kho
  InboundOrder? _selectedOrder;
  final TextEditingController _palletController = TextEditingController();
  final TextEditingController _skuController = TextEditingController();
  final TextEditingController _productNameController = TextEditingController();
  final TextEditingController _searchTagController = TextEditingController();

  // Trạng thái quét RFID trực tiếp từ C72e / Hopeland / Sim
  final Map<String, TagInfo> _scannedTags = {};
  bool _isScanning = false;
  bool _isSaving = false;

  // Gate verification state
  GateVerificationResult? _gateResult;
  TagInfo? _latestScannedTag;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    // Khởi tạo chọn đơn nếu có
    if (_repo.inboundOrders.isNotEmpty) {
      _selectedOrder = _repo.inboundOrders.firstWhere(
        (o) => o.status == InboundOrderStatus.newOrder,
        orElse: () => _repo.inboundOrders.first,
      );
    }

    _uhf.setScanMode(PdaScanMode.rfid);
    _initHardwareListeners();
  }

  Timer? _uiRefreshTimer;
  void _scheduleUiRefresh() {
    if (_uiRefreshTimer?.isActive ?? false) return;
    _uiRefreshTimer = Timer(const Duration(milliseconds: 40), () {
      if (mounted) setState(() {});
    });
  }

  void _initHardwareListeners() {
    _tagSubscription = _uhf.onTagRead.listen((tag) {
      if (!mounted) return;
      if (_uhf.filterDuplicates && _scannedTags.containsKey(tag.epc)) {
        return; // Thẻ đã đọc rồi thì bỏ qua không đọc lại
      }
      _scannedTags[tag.epc] = tag;
      _latestScannedTag = tag;
      _scheduleUiRefresh();
    });

    _triggerSubscription = _uhf.onTriggerStateChanged.listen((isPressed) {
      if (!mounted) return;
      _uiRefreshTimer?.cancel();
      setState(() {
        _isScanning = isPressed;
      });
    });
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    _tagSubscription?.cancel();
    _triggerSubscription?.cancel();
    _tabController.dispose();
    _palletController.dispose();
    _skuController.dispose();
    _productNameController.dispose();
    _searchTagController.dispose();
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
      _latestScannedTag = null;
      _uhf.clearTags();
      _gateResult = null;
    });
  }

  void _runGateAudit() {
    if (_selectedOrder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Vui lòng chọn đơn nhập PO trước khi đối soát Cổng Gate!'),
        ),
      );
      return;
    }

    setState(() {
      _gateResult = _repo.verifyGateInbound(
        orderNo: _selectedOrder!.orderNo,
        scannedEpcs: _scannedTags.keys.toList(),
      );
    });

    HapticFeedback.heavyImpact();
  }

  Future<void> _saveInboundToSqlite() async {
    if (_scannedTags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Chưa có thẻ RFID nào được quét! Hãy quét thẻ để tiếp tục.'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final pallet = _palletController.text.trim().isEmpty ? 'PL-01' : _palletController.text.trim().toUpperCase();
      final sku = _skuController.text.trim();
      final prodName = _productNameController.text.trim();

      final savedCount = await _repo.confirmHandheldInbound(
        orderNo: _tabController.index == 0 ? _selectedOrder?.orderNo : null,
        palletCode: pallet,
        locationId: null,
        scannedEpcs: _scannedTags.keys.toList(),
        defaultSku: sku.isNotEmpty ? sku : 'SKU-INBOUND',
        defaultProductName: prodName.isNotEmpty ? prodName : 'Hàng nhập kho',
      );

      if (!mounted) return;

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFFE9E2D5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF10B981), width: 1.5)),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text('Nhập Kho Thành Công!', style: TextStyle(color: Color(0xFF2C251E), fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF4EFE6),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFC7BDAF)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Số lượng nhập:', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                        Text('$savedCount Chip RFID', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Pallet tiếp nhận:', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                        Text(pallet, style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Trạng thái:', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                        Text('Chờ xếp kệ kho', style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    if (_tabController.index == 0 && _selectedOrder != null) ...[
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Đơn PO:', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                          Text(_selectedOrder!.orderNo, style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Row(
                children: [
                  Icon(Icons.cloud_done, color: Color(0xFF0284C7), size: 16),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text('Đã cập nhật tồn kho SQLite & đồng bộ ERP', style: TextStyle(color: Color(0xFF0284C7), fontSize: 11.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _scannedTags.clear();
                  _gateResult = null;
                });
              },
              child: const Text('TIẾP TỤC QUÉT LƯỢT MỚI', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi khi lưu dữ liệu: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showCreateOrderDialog() {
    final orderNoController = TextEditingController();
    final supplierController = TextEditingController();
    final skuController = TextEditingController();
    final nameController = TextEditingController();
    final qtyController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFE9E2D5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFC7BDAF))),
        title: const Row(
          children: [
            Icon(Icons.post_add, color: Color(0xFF0284C7), size: 24),
            SizedBox(width: 8),
            Text('Tạo Đơn Nhập Kho PO', style: TextStyle(color: Color(0xFF2C251E), fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: orderNoController,
                decoration: const InputDecoration(labelText: 'Mã Lệnh Nhập (Order No)', hintText: 'Ví dụ: PO-IN-001', labelStyle: TextStyle(color: Color(0xFF6B5D4D))),
                style: const TextStyle(color: Color(0xFF2C251E)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: supplierController,
                decoration: const InputDecoration(labelText: 'Nhà cung cấp', hintText: 'Tên nhà cung cấp...', labelStyle: TextStyle(color: Color(0xFF6B5D4D))),
                style: const TextStyle(color: Color(0xFF2C251E)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: skuController,
                decoration: const InputDecoration(labelText: 'Mã SKU', hintText: 'Ví dụ: SKU-001', labelStyle: TextStyle(color: Color(0xFF6B5D4D))),
                style: const TextStyle(color: Color(0xFF2C251E)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Tên hàng hóa', hintText: 'Tên sản phẩm...', labelStyle: TextStyle(color: Color(0xFF6B5D4D))),
                style: const TextStyle(color: Color(0xFF2C251E)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Số lượng nhập', hintText: '1', labelStyle: TextStyle(color: Color(0xFF6B5D4D))),
                style: const TextStyle(color: Color(0xFF2C251E)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY', style: TextStyle(color: Color(0xFF6B5D4D))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () async {
              final orderNo = orderNoController.text.trim();
              final supplier = supplierController.text.trim();
              final sku = skuController.text.trim();
              final name = nameController.text.trim();
              final qty = int.tryParse(qtyController.text.trim()) ?? 1;

              if (orderNo.isEmpty || sku.isEmpty) return;

              final newOrder = InboundOrder(
                inboundOrderId: 'INB-${DateTime.now().millisecondsSinceEpoch}',
                orderNo: orderNo,
                sourceSupplier: supplier,
                status: InboundOrderStatus.newOrder,
                createdAt: DateTime.now(),
                details: [
                  InboundOrderDetail(
                    productId: 'PROD-${DateTime.now().millisecondsSinceEpoch}',
                    sku: sku,
                    productName: name,
                    requiredQty: qty,
                  ),
                ],
              );

              await _repo.addInboundOrder(newOrder);
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {
                _selectedOrder = newOrder;
              });
            },
            child: const Text('LƯU ĐƠN NHẬP', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: const HardwareStatusAppBar(title: '📥 NHẬP KHO RFID'),
      body: Column(
        children: [
          // 1. Tab Bar 3 Chế độ nhập kho
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFE9E2D5),
              border: Border(bottom: BorderSide(color: Color(0xFFC7BDAF), width: 1)),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF0284C7),
              indicatorWeight: 3,
              labelColor: const Color(0xFF0284C7),
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              tabs: const [
                Tab(icon: Icon(Icons.receipt_long, size: 18), text: 'ĐƠN PO'),
                Tab(icon: Icon(Icons.flash_on, size: 18), text: 'NHẬP TỰ DO'),
                Tab(icon: Icon(Icons.meeting_room, size: 18), text: 'CỔNG GATE'),
              ],
            ),
          ),

          // 2. Nội dung chính
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tab View Specific Section
                  if (_tabController.index == 0) ...[
                    _buildOrderSelectionSection(),
                  ] else if (_tabController.index == 1) ...[
                    _buildDirectInboundConfigSection(),
                  ] else ...[
                    _buildGateInboundSection(),
                  ],
                  const SizedBox(height: 12),

                  // Cấu hình Vị trí & Pallet đích
                  _buildDestinationConfigCard(),
                  const SizedBox(height: 12),

                  // Bảng điều khiển sóng UHF & HUD Telemetry Real-time
                  _buildLiveScanTelemetryCard(),
                  const SizedBox(height: 12),

                  // Thẻ Chip vừa đọc & Danh sách chip
                  _buildTelemetrySummaryCard(),
                  const SizedBox(height: 16),

                  // Nút Chốt Nhập Kho
                  _buildSaveActionButtons(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDestinationConfigCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE9E2D5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC7BDAF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.inventory_2_rounded, color: Color(0xFF0284C7), size: 16),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'PALLET / KIỆN TIẾP NHẬN (TÙY CHỌN)',
                  style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 11.5, letterSpacing: 0.3),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Hàng quét nhập kho sẽ tự động lưu tạm ở trạng thái Chờ xếp kệ. Vị trí kệ lưu trữ sẽ được chọn ở màn hình Lưu kho khi chuyển hàng lên kệ.',
            style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 11),
          ),
          const SizedBox(height: 10),

          // Nhập Pallet Code
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Mã Pallet / Kiện:', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 11)),
              const SizedBox(height: 4),
              TextField(
                controller: _palletController,
                style: const TextStyle(color: Color(0xFF2C251E), fontSize: 12, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: const Color(0xFFF4EFE6),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  hintText: 'Mặc định: PL-01',
                  hintStyle: const TextStyle(color: Color(0xFF8F8070), fontSize: 11),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFC7BDAF))),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFC7BDAF))),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSelectionSection() {
    return AnimatedBuilder(
      animation: _repo,
      builder: (context, _) {
        final availableOrders = _repo.inboundOrders;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFE9E2D5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFC7BDAF)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.inventory, color: Color(0xFF0284C7), size: 16),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'ĐƠN NHẬP KHO PO (WMS / ERP)',
                      style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 11.5, letterSpacing: 0.3),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _showCreateOrderDialog,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF0284C7)),
                      ),
                      child: const Text(
                        '+ Tạo Đơn PO',
                        style: TextStyle(color: Color(0xFF0284C7), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (availableOrders.isEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF4EFE6),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      const Text('Chưa có đơn nhập nào trong CSDL SQLite.', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                        onPressed: _showCreateOrderDialog,
                        child: const Text('+ TẠO ĐƠN MỚI', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                DropdownButtonFormField<InboundOrder>(
                  initialValue: availableOrders.contains(_selectedOrder) ? _selectedOrder : null,
                  isExpanded: true,
                  dropdownColor: const Color(0xFFE9E2D5),
                  style: const TextStyle(color: Color(0xFF2C251E), fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFFF4EFE6),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFC7BDAF))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFC7BDAF))),
                  ),
                  items: availableOrders.map((o) {
                    return DropdownMenuItem(
                      value: o,
                      child: Text('${o.orderNo} - ${o.sourceSupplier}', overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedOrder = val);
                  },
                ),
                if (_selectedOrder != null) ...[
                  const SizedBox(height: 10),
                  // Danh sách SKU chi tiết trên đơn PO
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4EFE6),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFC7BDAF)),
                    ),
                    child: Column(
                      children: [
                        for (var d in _selectedOrder!.details)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Row(
                              children: [
                                const Icon(Icons.circle, color: Color(0xFF0284C7), size: 8),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${d.sku} - ${d.productName}',
                                    style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 11),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFE9E2D5),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    'Yêu cầu: ${d.requiredQty}',
                                    style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 10.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildDirectInboundConfigSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE9E2D5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC7BDAF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.local_offer, color: Color(0xFF0284C7), size: 16),
              SizedBox(width: 6),
              Text(
                'THÔNG TIN HÀNG HÓA GÁN MẶC ĐỊNH',
                style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Mã SKU:', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 11)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _skuController,
                      style: const TextStyle(color: Color(0xFF2C251E), fontSize: 12),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF4EFE6),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFC7BDAF))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFC7BDAF))),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tên sản phẩm:', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 11)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: _productNameController,
                      style: const TextStyle(color: Color(0xFF2C251E), fontSize: 12),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF4EFE6),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFC7BDAF))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFC7BDAF))),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildGateInboundSection() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE9E2D5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC7BDAF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.meeting_room, color: Color(0xFF0284C7), size: 16),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'CỔNG GATE (INBOUND)',
                  style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 11.5, letterSpacing: 0.3),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.rule, size: 13, color: Color(0xFF2C251E)),
                label: const Text('ĐỐI SOÁT', style: TextStyle(color: Color(0xFF2C251E), fontSize: 10.5, fontWeight: FontWeight.bold)),
                onPressed: _runGateAudit,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_gateResult == null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4EFE6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.sensors, color: Color(0xFF8F8070), size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text('Quét hàng loạt thẻ qua cổng rồi nhấn [ĐỐI SOÁT] để kiểm tra tính hợp lệ của lô hàng.', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 11.5)),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _gateResult!.isPass ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _gateResult!.isPass ? const Color(0xFF10B981) : const Color(0xFFEF4444), width: 1.5),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(_gateResult!.isPass ? Icons.verified : Icons.warning_amber, color: _gateResult!.isPass ? const Color(0xFF10B981) : const Color(0xFFEF4444), size: 24),
                      const SizedBox(width: 8),
                      Text(
                        _gateResult!.isPass ? 'GATE PASS - ĐẠT CHUẨN ĐƠN HÀNG' : 'GATE FAIL - SAI LỆCH SỐ LƯỢNG / THẺ LẠ',
                        style: TextStyle(
                          color: _gateResult!.isPass ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Yêu cầu: ${_gateResult!.totalRequiredQty}', style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 11)),
                      Text('Thực tế: ${_gateResult!.totalActualQty}', style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 11)),
                      Text('Thẻ lạ: ${_gateResult!.unexpectedEpcs.length}', style: TextStyle(color: _gateResult!.unexpectedEpcs.isNotEmpty ? const Color(0xFFEF4444) : const Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLiveScanTelemetryCard() {
    final count = _scannedTags.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE9E2D5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isScanning ? const Color(0xFF0284C7) : const Color(0xFFC7BDAF),
          width: _isScanning ? 2 : 1,
        ),
        boxShadow: _isScanning
            ? [
                BoxShadow(
                  color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : [],
      ),
      child: Column(
        children: [
          // Status bar (Responsive Wrap to prevent overflow)
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _isScanning ? const Color(0xFF10B981) : Colors.orange,
                      boxShadow: _isScanning
                          ? [
                              const BoxShadow(color: Color(0xFF10B981), blurRadius: 8, spreadRadius: 2),
                            ]
                          : [],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isScanning ? 'ĐANG PHÁT SÓNG UHF' : 'SẴN SÀNG QUÉT (CÒ PDA)',
                    style: TextStyle(
                      color: _isScanning ? const Color(0xFF0284C7) : const Color(0xFF6B5D4D),
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    onTap: () {
                      setState(() {
                        _uhf.filterDuplicates = !_uhf.filterDuplicates;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: _uhf.filterDuplicates ? const Color(0xFF10B981) : Colors.orange,
                          content: Text(_uhf.filterDuplicates ? 'Đã bật: Bỏ qua thẻ đã đọc (Lọc trùng)' : 'Đã tắt: Đọc liên tục tất cả lượt'),
                          duration: const Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                        color: _uhf.filterDuplicates ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFFF4EFE6),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _uhf.filterDuplicates ? const Color(0xFF10B981) : const Color(0xFFC7BDAF)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _uhf.filterDuplicates ? Icons.filter_alt : Icons.filter_alt_off,
                            color: _uhf.filterDuplicates ? const Color(0xFF10B981) : const Color(0xFF6B5D4D),
                            size: 11,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _uhf.filterDuplicates ? 'Lọc trùng: BẬT' : 'Lọc trùng: TẮT',
                            style: TextStyle(
                              color: _uhf.filterDuplicates ? const Color(0xFF10B981) : const Color(0xFF6B5D4D),
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF4EFE6),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFC7BDAF)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.flash_on, color: Color(0xFFF59E0B), size: 11),
                        const SizedBox(width: 3),
                        Text(
                          '${_uhf.rfPower} dBm',
                          style: const TextStyle(color: Color(0xFF0284C7), fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Big Counter
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$count',
                style: const TextStyle(
                  color: Color(0xFF2C251E),
                  fontSize: 54,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Thẻ RFID đã đọc',
                style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Primary Scan Action Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: _isScanning ? const Color(0xFFEF4444) : const Color(0xFF0284C7),
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: Icon(_isScanning ? Icons.stop : Icons.play_arrow, color: Colors.white, size: 20),
              label: Text(
                _isScanning ? 'DỪNG QUÉT' : 'BẮT ĐẦU QUÉT RFID (HOẶC BÓP CÒ)',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              onPressed: _toggleScan,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetrySummaryCard() {
    final latestTag = _latestScannedTag;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE9E2D5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFC7BDAF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.nfc, color: Color(0xFF0284C7), size: 16),
                  SizedBox(width: 6),
                  Text(
                    'CHIP RFID VỪA ĐỌC TRÚNG',
                    style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
                  ),
                ],
              ),
              if (_scannedTags.isNotEmpty)
                InkWell(
                  onTap: _clearScannedList,
                  child: const Text('Xóa dữ liệu', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 10),

          // Khung chip vừa đọc gần nhất
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF4EFE6),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: latestTag != null ? const Color(0xFF0284C7).withValues(alpha: 0.5) : const Color(0xFFC7BDAF),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'MÃ EPC ĐỘC BẢN',
                      style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                    if (latestTag != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '${latestTag.rssi} dBm',
                          style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  latestTag != null ? latestTag.epc : 'Đang chờ bóp cò hoặc nhấn nút quét...',
                  style: TextStyle(
                    color: latestTag != null ? const Color(0xFF2C251E) : const Color(0xFF8F8070),
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Nút xem chi tiết modal danh sách thẻ
          if (_scannedTags.isNotEmpty)
            SizedBox(
              width: double.infinity,
              height: 38,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0284C7),
                  side: const BorderSide(color: Color(0xFFC7BDAF)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _showTagDetailsBottomSheet(_scannedTags.values.toList()),
                icon: const Icon(Icons.list_alt, size: 16),
                label: Text(
                  'Xem chi tiết danh sách (${_scannedTags.length} mã EPC)',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showTagDetailsBottomSheet(List<TagInfo> allTags) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFFE9E2D5),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final query = _searchTagController.text.trim().toLowerCase();
            final filteredList = allTags.where((t) {
              if (query.isNotEmpty && !t.epc.toLowerCase().contains(query)) return false;
              return true;
            }).toList();

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.7,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DANH SÁCH THẺ RFID (${filteredList.length}/${allTags.length})',
                          style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Color(0xFF6B5D4D)),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                    const Divider(color: Color(0xFFC7BDAF)),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _searchTagController,
                      style: const TextStyle(color: Color(0xFF2C251E), fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Tìm kiếm mã EPC...',
                        hintStyle: const TextStyle(color: Color(0xFF8F8070), fontSize: 12),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF0284C7), size: 18),
                        filled: true,
                        fillColor: const Color(0xFFF4EFE6),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFC7BDAF))),
                      ),
                      onChanged: (_) => setModalState(() {}),
                    ),
                    const SizedBox(height: 10),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filteredList.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final tag = filteredList[index];
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF4EFE6),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFC7BDAF)),
                            ),
                            child: Row(
                              children: [
                                Text('#${index + 1}', style: const TextStyle(color: Color(0xFF0284C7), fontSize: 11, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    tag.epc,
                                    style: const TextStyle(color: Color(0xFF2C251E), fontFamily: 'monospace', fontSize: 11.5, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text('${tag.rssi} dBm', style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 11)),
                              ],
                            ),
                          );
                        },
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

  Widget _buildSaveActionButtons() {
    final count = _scannedTags.length;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: count > 0 ? const Color(0xFF10B981) : Colors.grey.shade800,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: count > 0 ? 6 : 0,
          shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
        ),
        onPressed: (_isSaving || count == 0) ? null : _saveInboundToSqlite,
        child: _isSaving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Color(0xFF2C251E), strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.check_circle_outline, color: Color(0xFF2C251E), size: 20),
                  const SizedBox(width: 8),
                  Text(
                    count > 0 ? 'XÁC NHẬN NHẬP KHO ($count CHIP)' : 'CHƯA CÓ THẺ ĐỂ NHẬP KHO',
                    style: const TextStyle(color: Color(0xFF2C251E), fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                ],
              ),
      ),
    );
  }
}
