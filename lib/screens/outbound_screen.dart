import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/tag_info.dart';
import '../models/wms_models.dart';
import '../services/uhf_service.dart';
import '../services/warehouse_repository.dart';
import '../widgets/hardware_status_appbar.dart';

class OutboundScreen extends StatefulWidget {
  const OutboundScreen({super.key});

  @override
  State<OutboundScreen> createState() => _OutboundScreenState();
}

class _OutboundScreenState extends State<OutboundScreen> with SingleTickerProviderStateMixin {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();

  late TabController _tabController;
  StreamSubscription<TagInfo>? _tagSubscription;
  StreamSubscription<bool>? _triggerSubscription;

  // Đơn hàng xuất được chọn
  OutboundOrder? _selectedOrder;
  final TextEditingController _searchOrderController = TextEditingController();

  // Trạng thái quét RFID thời gian thực
  final Map<String, TagInfo> _scannedTags = {};
  bool _isScanning = false;
  bool _isSaving = false;

  // FIFO Plan
  PickingPlan? _activePickingPlan;

  // Gate verification
  GateVerificationResult? _gateResult;
  TagInfo? _latestScannedTag;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });

    if (_repo.outboundOrders.isNotEmpty) {
      _selectedOrder = _repo.outboundOrders.firstWhere(
        (o) => o.status == OutboundOrderStatus.newOrder || o.status == OutboundOrderStatus.processing,
        orElse: () => _repo.outboundOrders.first,
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
    _searchOrderController.dispose();
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
    HapticFeedback.lightImpact();
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

  void _generateFifoPlan() {
    if (_selectedOrder == null) return;
    final plan = _repo.generateFifoPickingPlan(_selectedOrder!.outboundOrderId);
    setState(() {
      _activePickingPlan = plan;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        content: Text('Đã tính toán Kế hoạch Lấy Hàng FIFO cho PO ${_selectedOrder!.poNo}!'),
      ),
    );
  }

  void _runGateAudit() {
    if (_selectedOrder == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Vui lòng chọn đơn xuất PO trước khi đối soát Cổng Gate!'),
        ),
      );
      return;
    }

    setState(() {
      _gateResult = _repo.verifyGateOutbound(
        poNo: _selectedOrder!.poNo,
        scannedEpcs: _scannedTags.keys.toList(),
      );
    });

    HapticFeedback.heavyImpact();
  }

  Future<void> _confirmOutboundShipment() async {
    if (_selectedOrder == null) return;
    final scannedEpcs = _scannedTags.keys.toList();

    if (scannedEpcs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Chưa có thẻ RFID nào được quét để xuất hàng!'),
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final success = _repo.confirmOutboundCompletion(
        poNo: _selectedOrder!.poNo,
        shippedEpcs: scannedEpcs,
        performedBy: 'Thủ kho PDA / RFID Station',
      );

      if (!mounted) return;

      if (success) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E293B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF10B981), width: 1.5)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Color(0xFF10B981), size: 28),
                SizedBox(width: 10),
                Expanded(
                  child: Text('Xuất Kho Thành Công!', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
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
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF334155)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Mã Đơn PO:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text(_selectedOrder!.poNo, style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Khách hàng:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text(_selectedOrder!.customer, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Số lượng xuất:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text('${scannedEpcs.length} Chip RFID', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Trạng thái đơn:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          Text('SHIPPED (Đã xuất)', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Icon(Icons.sync_alt, color: Color(0xFF38BDF8), size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text('Đã trừ tồn kho SQLite & đồng bộ ERP Bravo', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11.5, fontWeight: FontWeight.bold)),
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
                    _uhf.clearTags();
                    _gateResult = null;
                    _activePickingPlan = null;
                  });
                },
                child: const Text('TIẾP TỤC ĐƠN TIẾP THEO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi khi xuất kho: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showCreateOutboundDialog() {
    final poNoController = TextEditingController();
    final customerController = TextEditingController();
    final skuController = TextEditingController();
    final nameController = TextEditingController();
    final qtyController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF334155))),
        title: const Row(
          children: [
            Icon(Icons.output, color: Color(0xFF38BDF8), size: 24),
            SizedBox(width: 8),
            Text('Tạo Đơn Xuất Kho PO', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: poNoController,
                decoration: const InputDecoration(labelText: 'Mã Lệnh Xuất (PO No)', hintText: 'Ví dụ: PO-OUT-001', labelStyle: TextStyle(color: Colors.white70)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: customerController,
                decoration: const InputDecoration(labelText: 'Khách hàng nhận', hintText: 'Tên khách hàng...', labelStyle: TextStyle(color: Colors.white70)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: skuController,
                decoration: const InputDecoration(labelText: 'Mã SKU xuất', hintText: 'Ví dụ: SKU-001', labelStyle: TextStyle(color: Colors.white70)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Tên mặt hàng', hintText: 'Tên sản phẩm...', labelStyle: TextStyle(color: Colors.white70)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Số lượng xuất', hintText: '1', labelStyle: TextStyle(color: Colors.white70)),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
            onPressed: () async {
              final poNo = poNoController.text.trim();
              final customer = customerController.text.trim();
              final sku = skuController.text.trim();
              final name = nameController.text.trim();
              final qty = int.tryParse(qtyController.text.trim()) ?? 1;

              if (poNo.isEmpty || sku.isEmpty) return;

              final newOrder = OutboundOrder(
                outboundOrderId: 'OUT-${DateTime.now().millisecondsSinceEpoch}',
                poNo: poNo,
                customer: customer,
                status: OutboundOrderStatus.newOrder,
                createdAt: DateTime.now(),
                details: [
                  OutboundOrderDetail(
                    productId: 'PROD-OUT-${DateTime.now().millisecondsSinceEpoch}',
                    sku: sku,
                    productName: name,
                    requiredQty: qty,
                    pickedQty: 0,
                  ),
                ],
              );

              await _repo.addOutboundOrder(newOrder);
              if (ctx.mounted) Navigator.pop(ctx);
              setState(() {
                _selectedOrder = newOrder;
              });
            },
            child: const Text('LƯU ĐƠN XUẤT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1120),
      appBar: const HardwareStatusAppBar(title: '📤 XUẤT KHO RFID'),
      body: Column(
        children: [
          // 1. Tab Bar 3 Chế độ xuất kho
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFF1E293B),
              border: Border(bottom: BorderSide(color: Color(0xFF334155), width: 1)),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF38BDF8),
              indicatorWeight: 3,
              labelColor: const Color(0xFF38BDF8),
              unselectedLabelColor: Colors.white60,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              tabs: const [
                Tab(icon: Icon(Icons.qr_code_scanner, size: 18), text: 'QUÉT & SO KHỚP'),
                Tab(icon: Icon(Icons.list_alt, size: 18), text: 'DANH SÁCH PO'),
                Tab(icon: Icon(Icons.route, size: 18), text: 'FIFO & CỔNG GATE'),
              ],
            ),
          ),

          // 2. Nội dung Tab
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildLiveOutboundVerificationTab(),
                _buildOutboundOrdersListTab(),
                _buildFifoAndGateTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 1: QUÉT XUẤT HÀNG & SO KHỚP RFID
  // ==========================================

  Widget _buildLiveOutboundVerificationTab() {
    final scannedEpcs = _scannedTags.keys.toList();
    final itemsInDb = _repo.items;

    // Phân loại thẻ quét
    final List<Item> matchedItems = [];
    final List<String> unexpectedEpcs = [];
    final Map<String, int> actualSkuCounts = {};

    int totalRequired = 0;
    if (_selectedOrder != null) {
      totalRequired = _selectedOrder!.details.fold(0, (sum, d) => sum + d.requiredQty);
      final allowedSkus = _selectedOrder!.details.map((d) => d.sku).toSet();

      for (var epc in scannedEpcs) {
        final item = itemsInDb.where((it) => it.epc == epc).firstOrNull;
        if (item != null && allowedSkus.contains(item.sku)) {
          matchedItems.add(item);
          actualSkuCounts[item.sku] = (actualSkuCounts[item.sku] ?? 0) + 1;
        } else {
          unexpectedEpcs.add(epc);
        }
      }
    }

    final totalMatched = matchedItems.length;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order Selector Header Card
          _buildOrderSelectorCard(),
          const SizedBox(height: 12),

          // RFID HUD Telemetry Card
          _buildOutboundTelemetryCard(totalMatched: totalMatched, totalRequired: totalRequired, unexpectedCount: unexpectedEpcs.length),
          const SizedBox(height: 12),

          // Live SKU Fulfillment Matrix
          if (_selectedOrder != null) ...[
            _buildSkuFulfillmentMatrix(actualSkuCounts),
            const SizedBox(height: 12),
          ],

          // Scanned Tag Classifications
          _buildScannedTagsVerificationCard(matchedItems: matchedItems, unexpectedEpcs: unexpectedEpcs),
          const SizedBox(height: 16),

          // Dispatch Action Button
          _buildDispatchActionButton(totalMatched: totalMatched, totalRequired: totalRequired, unexpectedCount: unexpectedEpcs.length),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildOrderSelectorCard() {
    return AnimatedBuilder(
      animation: _repo,
      builder: (context, _) {
        final orders = _repo.outboundOrders;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.receipt, color: Color(0xFF38BDF8), size: 16),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      'ĐƠN HÀNG XUẤT KHO',
                      style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5, letterSpacing: 0.3),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  InkWell(
                    onTap: _showCreateOutboundDialog,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFF0284C7)),
                      ),
                      child: const Text(
                        '+ Tạo Phiếu Xuất',
                        style: TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (orders.isEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    children: [
                      const Text('Chưa có đơn xuất kho nào trong CSDL.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                        onPressed: _showCreateOutboundDialog,
                        child: const Text('+ TẠO ĐƠN XUẤT MỚI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                DropdownButtonFormField<OutboundOrder>(
                  initialValue: orders.contains(_selectedOrder) ? _selectedOrder : null,
                  isExpanded: true,
                  dropdownColor: const Color(0xFF1E293B),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF0F172A),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF334155))),
                  ),
                  items: orders.map((o) {
                    final isShipped = o.status == OutboundOrderStatus.shipped;
                    return DropdownMenuItem(
                      value: o,
                      child: Row(
                        children: [
                          Text(o.poNo, style: const TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('(${o.customer})', style: const TextStyle(color: Colors.white54, fontSize: 11), overflow: TextOverflow.ellipsis),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: isShipped ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isShipped ? 'Đã xuất' : 'Đang xử lý',
                              style: TextStyle(color: isShipped ? const Color(0xFF10B981) : const Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedOrder = val;
                        _scannedTags.clear();
                        _gateResult = null;
                        _activePickingPlan = null;
                      });
                    }
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildOutboundTelemetryCard({required int totalMatched, required int totalRequired, required int unexpectedCount}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isScanning ? const Color(0xFF0F2B48) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isScanning ? const Color(0xFF38BDF8) : (unexpectedCount > 0 ? const Color(0xFFEF4444) : const Color(0xFF334155)),
          width: _isScanning || unexpectedCount > 0 ? 2 : 1,
        ),
        boxShadow: _isScanning
            ? [
                BoxShadow(color: const Color(0xFF0284C7).withValues(alpha: 0.3), blurRadius: 16, spreadRadius: 2),
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
                      boxShadow: _isScanning ? [const BoxShadow(color: Color(0xFF10B981), blurRadius: 8, spreadRadius: 2)] : [],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isScanning ? 'ĐANG QUÉT XUẤT HÀNG' : 'SẴN SÀNG QUÉT (CÒ PDA)',
                    style: TextStyle(
                      color: _isScanning ? const Color(0xFF38BDF8) : Colors.white70,
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
                        color: _uhf.filterDuplicates ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _uhf.filterDuplicates ? const Color(0xFF10B981) : const Color(0xFF334155)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _uhf.filterDuplicates ? Icons.filter_alt : Icons.filter_alt_off,
                            color: _uhf.filterDuplicates ? const Color(0xFF10B981) : Colors.white54,
                            size: 11,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            _uhf.filterDuplicates ? 'Lọc trùng: BẬT' : 'Lọc trùng: TẮT',
                            style: TextStyle(
                              color: _uhf.filterDuplicates ? const Color(0xFF10B981) : Colors.white54,
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
                      color: const Color(0xFF0B1120),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.flash_on, color: Color(0xFFF59E0B), size: 11),
                        const SizedBox(width: 3),
                        Text(
                          '${_uhf.rfPower} dBm',
                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 10.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Big Counter Display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(
                children: [
                  Text(
                    '$totalMatched',
                    style: const TextStyle(color: Color(0xFF10B981), fontSize: 44, fontWeight: FontWeight.w900),
                  ),
                  const Text('Khớp Đơn (Hợp lệ)', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
              Container(width: 1, height: 40, color: const Color(0xFF334155)),
              Column(
                children: [
                  Text(
                    '$totalRequired',
                    style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 44, fontWeight: FontWeight.w900),
                  ),
                  const Text('Tổng yêu cầu PO', style: TextStyle(color: Colors.white70, fontSize: 11)),
                ],
              ),
              if (unexpectedCount > 0) ...[
                Container(width: 1, height: 40, color: const Color(0xFF334155)),
                Column(
                  children: [
                    Text(
                      '$unexpectedCount',
                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 44, fontWeight: FontWeight.w900),
                    ),
                    const Text('Thẻ lạ / Sai PO', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
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
                _isScanning ? 'DỪNG QUÉT RFID' : 'BẮT ĐẦU QUÉT RFID (HOẶC BÓP CÒ)',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              onPressed: _toggleScan,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkuFulfillmentMatrix(Map<String, int> actualSkuCounts) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.checklist, color: Color(0xFF38BDF8), size: 16),
              SizedBox(width: 6),
              Text(
                'TIẾN ĐỘ THỰC XUẤT THEO SKU',
                style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var detail in _selectedOrder!.details) ...[
            Builder(builder: (context) {
              final actual = actualSkuCounts[detail.sku] ?? 0;
              final required = detail.requiredQty;
              final isDone = actual >= required && required > 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isDone ? const Color(0xFF10B981).withValues(alpha: 0.5) : const Color(0xFF334155),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            '${detail.sku} - ${detail.productName}',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isDone ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFF0284C7).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '$actual/$required',
                            style: TextStyle(
                              color: isDone ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: required > 0 ? (actual / required).clamp(0.0, 1.0) : 0.0,
                        backgroundColor: const Color(0xFF1E293B),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isDone ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                        ),
                        minHeight: 5,
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

  Widget _buildScannedTagsVerificationCard({required List<Item> matchedItems, required List<String> unexpectedEpcs}) {
    final latestTag = _latestScannedTag;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF334155)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.nfc, color: Color(0xFF38BDF8), size: 16),
                  SizedBox(width: 6),
                  Text(
                    'GIÁM SÁT SO KHỚP CHIP RFID',
                    style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 0.5),
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

          // Cảnh báo thẻ lạ nếu có
          if (unexpectedEpcs.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFEF4444)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning, color: Color(0xFFEF4444), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Cảnh báo: Phát hiện ${unexpectedEpcs.length} thẻ lạ không thuộc đơn xuất này!',
                      style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Chip vừa đọc gần nhất
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: latestTag != null ? const Color(0xFF0284C7).withValues(alpha: 0.5) : const Color(0xFF334155),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('CHIP VỪA ĐỌC TRÚNG GẦN NHẤT', style: TextStyle(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold)),
                    if (latestTag != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text('${latestTag.rssi} dBm', style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  latestTag != null ? latestTag.epc : 'Đang chờ bóp cò hoặc kích hoạt quét...',
                  style: TextStyle(
                    color: latestTag != null ? Colors.white : Colors.white38,
                    fontFamily: 'monospace',
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDispatchActionButton({required int totalMatched, required int totalRequired, required int unexpectedCount}) {
    final bool canShip = totalMatched > 0 && unexpectedCount == 0;

    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: canShip ? const Color(0xFF10B981) : Colors.grey.shade800,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: canShip ? 6 : 0,
          shadowColor: const Color(0xFF10B981).withValues(alpha: 0.4),
        ),
        onPressed: (_isSaving || !canShip) ? null : _confirmOutboundShipment,
        child: _isSaving
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.local_shipping, color: Colors.white, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    unexpectedCount > 0
                        ? 'CÒN THẺ LẠ CHƯA ĐỐI SOÁT'
                        : (totalMatched > 0 ? 'XÁC NHẬN XUẤT KHO ($totalMatched CHIP)' : 'CHƯA CÓ HÀNG HỢP LỆ'),
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 0.5),
                  ),
                ],
              ),
      ),
    );
  }

  // ==========================================
  // TAB 2: DANH SÁCH PHIẾU XUẤT HÀNG (DELIVERY NOTES)
  // ==========================================

  Widget _buildOutboundOrdersListTab() {
    return AnimatedBuilder(
      animation: _repo,
      builder: (context, _) {
        final query = _searchOrderController.text.trim().toLowerCase();
        final orders = _repo.outboundOrders.where((o) {
          if (query.isNotEmpty) {
            final matchPo = o.poNo.toLowerCase().contains(query);
            final matchCust = o.customer.toLowerCase().contains(query);
            if (!matchPo && !matchCust) return false;
          }
          return true;
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            children: [
              // Search and Add Toolbar
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchOrderController,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Tìm theo PO hoặc Khách hàng...',
                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 12),
                        prefixIcon: const Icon(Icons.search, color: Color(0xFF38BDF8), size: 18),
                        filled: true,
                        fillColor: const Color(0xFF1E293B),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFF334155))),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.add, size: 16, color: Colors.white),
                    label: const Text('TẠO PO', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: _showCreateOutboundDialog,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // List
              Expanded(
                child: orders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.outbox_outlined, size: 64, color: Colors.white24),
                            const SizedBox(height: 14),
                            const Text('Không tìm thấy đơn xuất kho nào.', style: TextStyle(color: Colors.white70, fontSize: 13)),
                            const SizedBox(height: 14),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                              onPressed: _showCreateOutboundDialog,
                              child: const Text('+ TẠO PHIẾU XUẤT MỚI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        itemCount: orders.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final order = orders[index];
                          final isSelected = _selectedOrder?.outboundOrderId == order.outboundOrderId;
                          final isShipped = order.status == OutboundOrderStatus.shipped;
                          final totalQty = order.details.fold(0, (sum, d) => sum + d.requiredQty);

                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedOrder = order;
                                _scannedTags.clear();
                                _gateResult = null;
                                _tabController.animateTo(0);
                              });
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1E293B),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF38BDF8) : const Color(0xFF334155),
                                  width: isSelected ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: isShipped ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFF0284C7).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      isShipped ? Icons.local_shipping : Icons.pending_actions,
                                      color: isShipped ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          order.poNo,
                                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Khách hàng: ${order.customer}',
                                          style: const TextStyle(color: Colors.white70, fontSize: 11.5),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'Số lượng: $totalQty sản phẩm',
                                          style: const TextStyle(color: Color(0xFF38BDF8), fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: isShipped ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      isShipped ? 'Đã xuất' : 'Chọn quét',
                                      style: TextStyle(
                                        color: isShipped ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10.5,
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
        );
      },
    );
  }

  // ==========================================
  // TAB 3: GỢI Ý LẤY HÀNG FIFO & CỔNG XUẤT GATE
  // ==========================================

  Widget _buildFifoAndGateTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FIFO Section
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.route, color: Color(0xFF38BDF8), size: 16),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'KẾ HOẠCH FIFO (XUẤT TRƯỚC)',
                        style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5, letterSpacing: 0.3),
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
                      icon: const Icon(Icons.calculate, size: 13, color: Colors.white),
                      label: const Text('TÍNH FIFO', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
                      onPressed: _generateFifoPlan,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_activePickingPlan == null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                    child: const Text(
                      'Nhấn [TÍNH FIFO] để hệ thống tự động quét CSDL và chọn các Pallet nhập kho sớm nhất cho đơn này.',
                      style: TextStyle(color: Colors.white60, fontSize: 11.5),
                    ),
                  ),
                ] else ...[
                  for (var line in _activePickingPlan!.lines) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF334155)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.pallet, color: Color(0xFF38BDF8), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${line.sku} - ${line.productName}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11.5)),
                                Text('Vị trí: ${line.locationCode} | Pallet: ${line.palletCode}', style: const TextStyle(color: Colors.white54, fontSize: 10.5)),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('Lấy: ${line.quantityToPick}', style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Gate Outbound Section
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1E293B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF334155)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.meeting_room, color: Color(0xFF38BDF8), size: 16),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'CỔNG GATE (OUTBOUND)',
                        style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 11.5, letterSpacing: 0.3),
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
                      icon: const Icon(Icons.rule, size: 13, color: Colors.white),
                      label: const Text('ĐỐI SOÁT', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold)),
                      onPressed: _runGateAudit,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (_gateResult == null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(8)),
                    child: const Text(
                      'Kéo toàn bộ kiện hàng qua Cổng Gate RFID và nhấn [ĐỐI SOÁT] để kiểm tra toàn vẹn.',
                      style: TextStyle(color: Colors.white60, fontSize: 11.5),
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
                              _gateResult!.isPass ? 'GATE PASS - ĐẠT CHUẨN XUẤT HÀNG' : 'GATE FAIL - SAI LỆCH SỐ LƯỢNG / THẺ LẠ',
                              style: TextStyle(
                                color: _gateResult!.isPass ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Yêu cầu PO: ${_gateResult!.totalRequiredQty}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                            Text('Thực tế: ${_gateResult!.totalActualQty}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                            Text('Thẻ lạ: ${_gateResult!.unexpectedEpcs.length}', style: TextStyle(color: _gateResult!.unexpectedEpcs.isNotEmpty ? const Color(0xFFEF4444) : const Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
