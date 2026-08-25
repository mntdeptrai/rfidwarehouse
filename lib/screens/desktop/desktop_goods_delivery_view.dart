import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/warehouse_repository.dart';
import '../../services/uhf_service.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/tower_light_service.dart';
import '../../theme/eye_care_theme.dart';
import '../../models/wms_models.dart';
import '../../models/tag_info.dart';

class DesktopGoodsDeliveryView extends StatefulWidget {
  const DesktopGoodsDeliveryView({super.key});

  @override
  State<DesktopGoodsDeliveryView> createState() => _DesktopGoodsDeliveryViewState();
}

class _DesktopGoodsDeliveryViewState extends State<DesktopGoodsDeliveryView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final DesktopUhfTcpService _desktopUhf = DesktopUhfTcpService();
  final TowerLightService _towerLight = TowerLightService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  int _currentMode = 0; // 0: Live Outbound RFID Station, 1: Orders List
  bool _isCreating = false;
  int _scanDurationSeconds = 5; // Mặc định: Quét tự động trong 5 giây
  int _scanCountdown = 5;       // Đếm ngược số giây quét còn lại
  Timer? _countdownTimer;

  final TextEditingController _deliveryNoController = TextEditingController();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  // Live Station State
  OutboundOrder? _selectedLiveOrder;
  final Map<String, TagInfo> _scannedTags = {};
  bool _isScanning = false;
  bool _isSaving = false;
  PickingPlan? _activeFifoPlan;
  StreamSubscription<TagInfo>? _tagSub;
  StreamSubscription<TagInfo>? _desktopTagSub;
  final List<Map<String, dynamic>> _deliveryItems = [];

  // Creation Mode State: 0 = Xuất Lẻ (theo EPC), 1 = Xuất Theo Thùng (theo Barcode Thùng)
  int _createOutboundTab = 0;
  final Set<String> _selectedEpcSet = {};
  final Set<String> _selectedCartonSet = {};
  final Map<String, int> _cartonCustomQty = {};
  final TextEditingController _epcSearchFilterController = TextEditingController();
  final TextEditingController _cartonSearchFilterController = TextEditingController();
  final TextEditingController _scanDesktopController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _resetForm();

    _eyeCare.addListener(_onThemeChanged);
    _repo.addListener(_onThemeChanged);

    if (_repo.outboundOrders.isNotEmpty) {
      _selectedLiveOrder = _repo.outboundOrders.firstWhere(
        (o) => o.status == OutboundOrderStatus.newOrder || o.status == OutboundOrderStatus.processing,
        orElse: () => _repo.outboundOrders.first,
      );
    }

    // Đồng bộ tức thì dữ liệu thẻ và trạng thái đang quét từ Desktop UHF Bridge
    _isScanning = _desktopUhf.isScanning;
    for (final tag in _desktopUhf.tags) {
      _scannedTags[tag.epc] = tag;
    }
    _desktopUhf.addListener(_onDesktopUhfUpdate);

    _initTagListener();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onDesktopUhfUpdate() {
    if (!mounted) return;
    setState(() {
      _isScanning = _desktopUhf.isScanning;
      if (_desktopUhf.tags.isEmpty) {
        _scannedTags.clear();
      } else {
        for (final tag in _desktopUhf.tags) {
          _scannedTags[tag.epc] = tag;
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

  void _handleIncomingTag(TagInfo tag) {
    if (_isCreating) {
      final epc = tag.epc.trim().toUpperCase();
      if (_createOutboundTab == 0) {
        _selectedEpcSet.add(epc);
      } else {
        final item = _repo.items.where((i) => i.epc.toUpperCase() == epc).firstOrNull;
        final cartonCode = item?.palletId ?? item?.sku;
        if (cartonCode != null && cartonCode.isNotEmpty) {
          _selectedCartonSet.add(cartonCode.toUpperCase());
        }
      }
      if (mounted) setState(() {});
      return;
    }

    if (!_isScanning) return;

    if (_uhf.filterDuplicates && _scannedTags.containsKey(tag.epc)) {
      return; // Thẻ đã đọc rồi thì bỏ qua không đọc lại
    }

    _scannedTags[tag.epc] = tag;

    if (_selectedLiveOrder != null) {
      final totalRequired = _selectedLiveOrder!.details.fold<int>(0, (sum, d) => sum + d.requiredQty);
      final currentScanned = _scannedTags.length;

      if (totalRequired > 0) {
        if (currentScanned >= totalRequired) {
          // 🟢 ĐÈN XANH: Đủ hàng xuất kho (100% khớp đơn)
          _towerLight.triggerPass(
            reason: 'ĐỦ HÀNG XUẤT KHO: $currentScanned/$totalRequired chip khớp 100% đơn ${_selectedLiveOrder!.poNo}',
          );
        }
      } else {
        _towerLight.triggerPass(reason: 'Quét thẻ xuất kho trực tiếp: $currentScanned chip');
      }
    } else {
      _towerLight.triggerPass(reason: 'Quét thẻ xuất kho trực tiếp: ${_scannedTags.length} chip');
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
    _repo.removeListener(_onThemeChanged);
    _eyeCare.removeListener(_onThemeChanged);
    _desktopUhf.removeListener(_onDesktopUhfUpdate);
    _uiRefreshTimer?.cancel();
    _countdownTimer?.cancel();
    _tagSub?.cancel();
    _desktopTagSub?.cancel();
    _deliveryNoController.dispose();
    _dateController.dispose();
    _customerController.dispose();
    _noteController.dispose();
    _epcSearchFilterController.dispose();
    _cartonSearchFilterController.dispose();
    _scanDesktopController.dispose();
    super.dispose();
  }

  void _resetForm() {
    final now = DateTime.now();
    _deliveryNoController.text = 'OUT${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    _dateController.text = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _customerController.text = '';
    _noteController.text = '';
    _selectedEpcSet.clear();
    _selectedCartonSet.clear();
    _cartonCustomQty.clear();
    _deliveryItems.clear();
    _epcSearchFilterController.clear();
    _cartonSearchFilterController.clear();
    _scanDesktopController.clear();
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

    if (_selectedLiveOrder != null) {
      final totalRequired = _selectedLiveOrder!.details.fold<int>(0, (sum, d) => sum + d.requiredQty);
      final currentScanned = _scannedTags.length;

      if (totalRequired > 0) {
        if (currentScanned >= totalRequired) {
          _towerLight.triggerPass(
            reason: 'HOÀN TẤT XUẤT KHO ($_scanDurationSeconds GIÂY): ĐỦ HÀNG THÔNG QUA ($currentScanned/$totalRequired chip 100%)',
          );
        } else {
          _towerLight.triggerWarningRed(
            withBuzzer: true,
            reason: 'KẾT THÚC QUÉT ($_scanDurationSeconds GIÂY): THIẾU HÀNG XUẤT! Đã quét $currentScanned/$totalRequired chip (Còn thiếu ${totalRequired - currentScanned})',
          );
        }
      }
    }
  }

  void _generateFifo() {
    if (_selectedLiveOrder == null) return;
    final plan = _repo.generateFifoPickingPlan(_selectedLiveOrder!.outboundOrderId);
    setState(() {
      _activeFifoPlan = plan;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: const Color(0xFF10B981), content: Text('Đã tính toán FIFO cho PO ${_selectedLiveOrder!.poNo}!')),
    );
  }

  Future<void> _confirmShipment() async {
    final epcs = _scannedTags.keys.toList();

    if (epcs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Chưa quét thẻ RFID nào để xuất kho!')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      if (_selectedLiveOrder != null) {
        final ok = await _repo.confirmOutboundCompletion(
          poNo: _selectedLiveOrder!.poNo,
          shippedEpcs: epcs,
          performedBy: 'Thủ kho Desktop Station',
        );

        if (!mounted) return;

        if (ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF10B981),
              content: Text('Đã xuất kho thành công đơn ${_selectedLiveOrder!.poNo} (${epcs.length} chip RFID)!'),
            ),
          );
        }
      } else {
        final count = await _repo.confirmDirectOutbound(
          scannedEpcs: epcs,
          performedBy: 'Thủ kho Desktop Station',
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('Đã xuất kho trực tiếp thành công $count chip RFID!'),
          ),
        );
      }

      setState(() {
        _scannedTags.clear();
        _uhf.clearTags();
        _activeFifoPlan = null;
      });
      _desktopUhf.clearTags();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi xuất kho: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _saveAndProceedToScan() async {
    final code = _deliveryNoController.text.trim();
    if (code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Vui lòng nhập mã phiếu xuất (PO No)!')),
      );
      return;
    }

    final List<OutboundOrderDetail> details = [];

    if (_createOutboundTab == 0) {
      // 🏷️ XUẤT LẺ TỪNG SẢN PHẨM THEO MÃ EPC
      if (_selectedEpcSet.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Vui lòng tích chọn ít nhất 1 sản phẩm theo mã EPC cần xuất!')),
        );
        return;
      }

      final Map<String, List<Item>> epcBySku = {};
      for (var epc in _selectedEpcSet) {
        final item = _repo.items.where((i) => i.epc.toUpperCase() == epc.toUpperCase()).firstOrNull;
        final sku = item?.sku ?? epc;
        epcBySku.putIfAbsent(sku, () => []).add(
          item ?? Item(itemId: epc, productId: sku, sku: sku, productName: 'Sản phẩm $sku', serialNumber: epc, epc: epc, status: ItemStatus.inStock),
        );
      }

      for (var entry in epcBySku.entries) {
        final firstItem = entry.value.first;
        details.add(OutboundOrderDetail(
          productId: firstItem.productId,
          sku: entry.key,
          productName: firstItem.productName,
          requiredQty: entry.value.length,
          pickedQty: 0,
          epcList: entry.value.map((i) => i.epc).toList(),
        ));
      }
    } else {
      // 📦 XUẤT THEO THÙNG THEO BARCODE THÙNG
      if (_selectedCartonSet.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Color(0xFFEF4444), content: Text('Vui lòng tích chọn ít nhất 1 thùng hàng theo mã Barcode cần xuất!')),
        );
        return;
      }

      for (var cartonBarcode in _selectedCartonSet) {
        final cartonItems = _repo.items.where((i) =>
          (i.palletId != null && i.palletId!.toUpperCase() == cartonBarcode.toUpperCase()) ||
          i.sku.toUpperCase() == cartonBarcode.toUpperCase() ||
          i.productId.toUpperCase() == cartonBarcode.toUpperCase()
        ).toList();

        final firstItem = cartonItems.firstOrNull;
        final prod = _repo.products.where((p) => p.sku.toUpperCase() == cartonBarcode.toUpperCase() || p.productId.toUpperCase() == cartonBarcode.toUpperCase()).firstOrNull;
        final name = firstItem?.productName ?? prod?.productName ?? 'Kiện hàng $cartonBarcode';
        final qty = _cartonCustomQty[cartonBarcode] ?? (cartonItems.isNotEmpty ? cartonItems.length : 1);

        details.add(OutboundOrderDetail(
          productId: cartonBarcode,
          sku: cartonBarcode,
          productName: name,
          requiredQty: qty,
          pickedQty: 0,
          epcList: cartonItems.map((i) => i.epc).toList(),
        ));
      }
    }

    final totalChips = details.fold<int>(0, (sum, d) => sum + d.requiredQty);

    final newOrder = OutboundOrder(
      outboundOrderId: 'OUT-${DateTime.now().millisecondsSinceEpoch}',
      poNo: code,
      customer: _customerController.text.trim().isNotEmpty ? _customerController.text.trim() : 'Khách mua lẻ',
      createdAt: DateTime.now(),
      status: OutboundOrderStatus.processing,
      details: details,
    );

    await _repo.addOutboundOrder(newOrder);
    setState(() {
      _isCreating = false;
      _selectedLiveOrder = newOrder;
      _currentMode = 0; // Chuyển sang trạm quét live
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('Đã tạo phiếu xuất $code ($totalChips SP). Mời đưa hàng qua trạm quét RFID!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    if (_isCreating) {
      return _buildCreateDeliveryForm(c);
    }

    return Container(
      color: c.bgDeep,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header & Mode Switcher
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
                    'GOODS DELIVERY & DISPATCH RFID STATION',
                    style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 14,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Quản Lý Xuất Kho',
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
                            _buildModeTab(0, 'Trạm Quét Xuất RFID Live', Icons.qr_code_scanner, c),
                            _buildModeTab(1, 'Danh Sách Phiếu Xuất', Icons.list_alt, c),
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
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('LÀM MỚI'),
                    onPressed: () => _repo.refreshFromDatabase(),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.rfidCyan,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add, color: Color(0xFF2C251E), size: 18),
                    label: const Text('TẠO PHIẾU XUẤT', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
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

          // Body View
          Expanded(
            child: _currentMode == 0 ? _buildLiveOutboundStationView(c) : _buildDeliveryList(c),
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

  // ==================== TRẠM QUÉT XUẤT KHO RFID LIVE ====================

  Widget _buildLiveOutboundStationView(EyeCareColors c) {
    final orders = _repo.outboundOrders;
    final scannedEpcs = _scannedTags.keys.toList();
    final itemsInDb = _repo.items;

    final List<Item> matchedItems = [];
    final List<String> unexpectedEpcs = [];
    final List<String> unstockedEpcs = [];
    final Map<String, int> actualSkuCounts = {};

    int totalRequired = 0;
    if (_selectedLiveOrder != null) {
      totalRequired = _selectedLiveOrder!.details.fold(0, (sum, d) => sum + d.requiredQty);
      final allowedSkus = _selectedLiveOrder!.details.map((d) => d.sku).toSet();

      for (var epc in scannedEpcs) {
        final item = itemsInDb.where((it) => it.epc == epc).firstOrNull;
        if (item == null || !allowedSkus.contains(item.sku)) {
          unexpectedEpcs.add(epc);
        } else if (!_repo.isItemStockedInLocation(item)) {
          unstockedEpcs.add(epc);
        } else {
          matchedItems.add(item);
          actualSkuCounts[item.sku] = (actualSkuCounts[item.sku] ?? 0) + 1;
        }
      }
    } else {
      for (var epc in scannedEpcs) {
        final item = itemsInDb.where((it) => it.epc == epc).firstOrNull;
        if (item == null || !_repo.isItemStockedInLocation(item)) {
          unstockedEpcs.add(epc);
        } else {
          matchedItems.add(item);
        }
      }
    }

    final totalMatched = matchedItems.length;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Order Selection & Controls
        SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              children: [
              // Order info card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('📋 ĐƠN XUẤT KHO', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 10),
                    if (orders.isNotEmpty) ...[
                      DropdownButtonFormField<String?>(
                        initialValue: _selectedLiveOrder == null ? null : (orders.any((o) => o.poNo == _selectedLiveOrder?.poNo) ? _selectedLiveOrder?.poNo : null),
                        isExpanded: true,
                        dropdownColor: c.bgCardElevated,
                        style: TextStyle(color: c.textPrimary, fontSize: 12),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: c.bgCardElevated,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                        ),
                        items: [
                          DropdownMenuItem<String?>(
                            value: null,
                            child: Text('-- Xuất trực tiếp (Không theo PO) --', style: TextStyle(color: c.rfidCyan)),
                          ),
                          ...orders.map((o) => DropdownMenuItem<String?>(
                            value: o.poNo,
                            child: Text('${o.poNo} - ${o.customer}', overflow: TextOverflow.ellipsis),
                          )),
                        ],
                        onChanged: (val) {
                          setState(() {
                            _selectedLiveOrder = val == null ? null : orders.firstWhere((o) => o.poNo == val, orElse: () => orders.first);
                            _scannedTags.clear();
                            _activeFifoPlan = null;
                          });
                        },
                      ),
                    ] else ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: c.bgCardElevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: c.rfidCyan, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Chế độ Xuất Trực Tiếp (Bấm "+ TẠO PHIẾU XUẤT" nếu cần đối soát theo đơn PO)',
                                style: TextStyle(color: c.textSecondary, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Gate Telemetry & Scan Stats
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _isScanning ? c.rfidCyan : (unexpectedEpcs.isNotEmpty ? const Color(0xFFEF4444) : c.border),
                    width: _isScanning || unexpectedEpcs.isNotEmpty ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(_isScanning ? 'ĐANG QUÉT ĐỐI SOÁT' : 'TRẠM XUẤT SẴN SÀNG', style: TextStyle(color: _isScanning ? c.rfidCyan : c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                        Wrap(
                          spacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
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
                                  color: _uhf.filterDuplicates ? const Color(0xFF10B981).withValues(alpha: 0.2) : c.bgCardElevated,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: _uhf.filterDuplicates ? const Color(0xFF10B981) : c.border),
                                ),
                                child: Text(
                                  _uhf.filterDuplicates ? 'Lọc trùng: BẬT' : 'Lọc trùng: TẮT',
                                  style: TextStyle(color: _uhf.filterDuplicates ? const Color(0xFF10B981) : c.textMuted, fontSize: 10, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            Text('${_uhf.rfPower} dBm', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Antenna Dual Selector Row (2 Anten cho cổng xuất kho)
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
                    const SizedBox(height: 12),
                    if (_selectedLiveOrder != null) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text('$totalMatched', style: const TextStyle(color: Color(0xFF10B981), fontSize: 34, fontWeight: FontWeight.w900)),
                              Text('Hợp lệ', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                            ],
                          ),
                          Container(width: 1, height: 35, color: c.border),
                          Column(
                            children: [
                              Text('$totalRequired', style: TextStyle(color: c.rfidCyan, fontSize: 34, fontWeight: FontWeight.w900)),
                              Text('Yêu cầu', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                            ],
                          ),
                          if (unstockedEpcs.isNotEmpty) ...[
                            Container(width: 1, height: 35, color: c.border),
                            Column(
                              children: [
                                Text('${unstockedEpcs.length}', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 34, fontWeight: FontWeight.w900)),
                                const Text('Chưa xếp kệ', style: TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                          if (unexpectedEpcs.isNotEmpty) ...[
                            Container(width: 1, height: 35, color: c.border),
                            Column(
                              children: [
                                Text('${unexpectedEpcs.length}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 34, fontWeight: FontWeight.w900)),
                                const Text('Sai hàng', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text('$totalMatched', style: const TextStyle(color: Color(0xFF10B981), fontSize: 34, fontWeight: FontWeight.w900)),
                              Text('Đủ điều kiện xuất', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                            ],
                          ),
                          if (unstockedEpcs.isNotEmpty) ...[
                            Container(width: 1, height: 35, color: c.border),
                            Column(
                              children: [
                                Text('${unstockedEpcs.length}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 34, fontWeight: FontWeight.w900)),
                                const Text('Chưa xếp kệ', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ],
                    // Warning banner if unstocked goods are scanned
                    if (unstockedEpcs.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF7F1D1D).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEF4444)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.shelves, color: Color(0xFFEF4444), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'LỖI: ${unstockedEpcs.length} chip chưa được xếp vào kệ nào trong kho (Vị trí trống/chưa Putaway)!',
                                style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
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
                              backgroundColor: _isScanning ? const Color(0xFFEF4444) : c.rfidCyan,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            icon: Icon(_isScanning ? Icons.stop_circle_outlined : Icons.sensors, color: const Color(0xFF2C251E), size: 18),
                            label: Text(
                              _isScanning
                                  ? (_scanDurationSeconds > 0 ? 'ĐANG QUÉT (${_scanCountdown}s) - DỪNG' : 'ĐANG QUÉT - BẤM DỪNG')
                                  : (_scanDurationSeconds > 0 ? 'BẮT ĐẦU QUÉT (${_scanDurationSeconds}s)' : 'BẮT ĐẦU QUÉT RFID'),
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

              // Dispatch Button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: (unstockedEpcs.isEmpty &&
                            (_selectedLiveOrder != null
                                ? (totalMatched > 0 && unexpectedEpcs.isEmpty && totalMatched == totalRequired)
                                : totalMatched > 0))
                        ? const Color(0xFF10B981)
                        : Colors.grey.shade600,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.local_shipping, color: Color(0xFF2C251E)),
                  label: Text(
                    _isSaving
                        ? 'Đang lưu...'
                        : (_selectedLiveOrder != null
                            ? 'XÁC NHẬN XUẤT KHO ($totalMatched CHIP)'
                            : 'XÁC NHẬN XUẤT KHO ($totalMatched CHIP)'),
                    style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold),
                  ),
                  onPressed: (_isSaving ||
                          unstockedEpcs.isNotEmpty ||
                          (_selectedLiveOrder != null
                              ? (totalMatched == 0 || unexpectedEpcs.isNotEmpty || totalMatched < totalRequired)
                              : totalMatched == 0))
                      ? null
                      : _confirmShipment,
                ),
              ),
            ],
          ),
        ),
      ),
        const SizedBox(width: 20),

        // Right Column: Live SKU Breakdown & Scanned Tags
        Expanded(
          child: Column(
            children: [
              // SKU Matrix
              if (_selectedLiveOrder != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.bgCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TIẾN ĐỘ THỰC XUẤT THEO SKU', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 8),
                      for (var d in _selectedLiveOrder!.details) ...[
                        Builder(builder: (context) {
                          final actual = actualSkuCounts[d.sku] ?? 0;
                          final req = d.requiredQty;
                          final isDone = actual >= req && req > 0;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: Text('${d.sku}: ${d.productName}', style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                                ),
                                Expanded(
                                  flex: 4,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: req > 0 ? (actual / req).clamp(0.0, 1.0) : 0.0,
                                      backgroundColor: c.bgCardElevated,
                                      valueColor: AlwaysStoppedAnimation<Color>(isDone ? const Color(0xFF10B981) : c.rfidCyan),
                                      minHeight: 8,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text('$actual/$req', style: TextStyle(color: isDone ? const Color(0xFF10B981) : c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Scanned Chips Table
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
                        spacing: 8,
                        runSpacing: 4,
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text('DANH SÁCH THẺ RFID (${_scannedTags.length})', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 13)),
                          if (unexpectedEpcs.isNotEmpty)
                            Text('${unexpectedEpcs.length} THẺ LẠ BÁO ĐỎ', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _scannedTags.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.nfc, size: 48, color: c.textMuted),
                                    const SizedBox(height: 10),
                                    Text('Chưa có thẻ RFID nào được đọc.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                                  ],
                                ),
                              )
                            : ListView.separated(
                                itemCount: _scannedTags.length,
                                separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                                itemBuilder: (context, index) {
                                  final epc = _scannedTags.keys.toList().reversed.toList()[index];
                                  final tag = _scannedTags[epc]!;
                                  final isUnexpected = unexpectedEpcs.contains(epc);
                                  final isUnstocked = unstockedEpcs.contains(epc);
                                  final antLabel = tag.ant.isNotEmpty ? tag.ant : '1';
                                  final isAnt2 = antLabel == '2';

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isUnexpected
                                              ? Icons.cancel
                                              : (isUnstocked ? Icons.shelves : Icons.check_circle),
                                          color: isUnexpected
                                              ? const Color(0xFFEF4444)
                                              : (isUnstocked ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            epc,
                                            style: TextStyle(
                                              color: (isUnexpected || isUnstocked) ? const Color(0xFFEF4444) : c.textPrimary,
                                              fontFamily: 'monospace',
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        if (isUnstocked) ...[
                                          const SizedBox(width: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF7F1D1D).withValues(alpha: 0.3),
                                              borderRadius: BorderRadius.circular(4),
                                              border: Border.all(color: const Color(0xFFEF4444)),
                                            ),
                                            child: const Text('CHƯA XẾP KỆ', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold)),
                                          ),
                                        ],
                                        const SizedBox(width: 8),
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
                                        Text('${tag.rssi} dBm', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                                        const SizedBox(width: 8),
                                        Text('${tag.count} lần', style: TextStyle(color: c.textMuted, fontSize: 10)),
                                      ],
                                    ),
                                  );
                                },
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
    );
  }

  Widget _buildDeliveryList(EyeCareColors c) {
    final outboundOrders = _repo.outboundOrders;

    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: outboundOrders.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.outbox_outlined, size: 64, color: c.textMuted),
                  const SizedBox(height: 14),
                  Text('Chưa có phiếu xuất kho nào trong CSDL.', style: TextStyle(color: c.textSecondary, fontSize: 14)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
                    icon: const Icon(Icons.add, color: Color(0xFF2C251E)),
                    label: const Text('Tạo Phiếu Xuất Mới', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
                    onPressed: () {
                      _resetForm();
                      setState(() => _isCreating = true);
                    },
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: outboundOrders.length,
              separatorBuilder: (_, index) => Divider(color: c.border, height: 1),
              itemBuilder: (context, index) {
                final order = outboundOrders[index];
                final isCompleted = order.status == OutboundOrderStatus.shipped;
                final totalQty = order.details.fold(0, (sum, d) => sum + d.requiredQty);

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
                        child: Icon(Icons.local_shipping, color: c.rfidCyan, size: 20),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 3,
                        child: Builder(
                            builder: (context) {
                              final cartonCount = order.details.map((d) => d.sku).toSet().length;
                              final String orderTypeLabel;
                              final Color orderTypeColor;

                              if (totalQty == 1) {
                                orderTypeLabel = '🏷️ Xuất Lẻ (1 SP)';
                                orderTypeColor = const Color(0xFF0284C7);
                              } else if (cartonCount == 1) {
                                orderTypeLabel = '📦 Xuất 1 Thùng ($totalQty SP)';
                                orderTypeColor = const Color(0xFF10B981);
                              } else {
                                orderTypeLabel = '🚚 Đơn Lớn ($cartonCount Thùng · $totalQty SP)';
                                orderTypeColor = const Color(0xFF8B5CF6);
                              }

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: [
                                      Text(order.poNo, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: orderTypeColor.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: orderTypeColor.withValues(alpha: 0.3)),
                                        ),
                                        child: Text(
                                          orderTypeLabel,
                                          style: TextStyle(color: orderTypeColor, fontSize: 10.5, fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Khách hàng: ${order.customer.isNotEmpty ? order.customer : "Khách mua"} | Tổng: $totalQty sản phẩm',
                                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                                  ),
                                ],
                              );
                            },
                          ),
                      ),
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
                );
              },
            ),
    );
  }

  void _handleFormScannedCode(String rawCode) {
    final code = rawCode.trim();
    if (code.isEmpty) return;
    final upperCode = code.toUpperCase();

    if (_createOutboundTab == 0) {
      // Xuất lẻ: Tìm theo EPC hoặc SKU/Barcode
      final item = _repo.items.where((i) => i.epc.toUpperCase() == upperCode).firstOrNull;
      if (item != null) {
        _selectedEpcSet.add(item.epc.toUpperCase());
      } else {
        final matchedItems = _repo.items.where((i) =>
          i.sku.toUpperCase() == upperCode ||
          i.productId.toUpperCase() == upperCode ||
          (i.palletId != null && i.palletId!.toUpperCase() == upperCode)
        ).toList();
        for (var mi in matchedItems) {
          _selectedEpcSet.add(mi.epc.toUpperCase());
        }
      }
    } else {
      // Xuất thùng: Tìm thùng theo Barcode hoặc EPC
      final carton = _repo.items.where((i) =>
        (i.palletId != null && i.palletId!.toUpperCase() == upperCode) ||
        i.sku.toUpperCase() == upperCode ||
        i.epc.toUpperCase() == upperCode
      ).firstOrNull;
      final cCode = carton?.palletId ?? carton?.sku ?? upperCode;
      _selectedCartonSet.add(cCode.toUpperCase());
    }

    if (mounted) setState(() {});
  }

  Widget _buildCreateDeliveryForm(EyeCareColors c) {
    // Lấy toàn bộ danh sách mặt hàng có sẵn trong kho
    final stockItems = _repo.items.where((i) => _repo.isItemStockedInLocation(i) || i.status == ItemStatus.inStock).toList();

    // Lọc cho Tab 0 (Xuất Lẻ theo mã EPC)
    final epcQuery = _epcSearchFilterController.text.trim().toUpperCase();
    final filteredEpcItems = stockItems.where((i) {
      if (epcQuery.isEmpty) return true;
      return i.epc.toUpperCase().contains(epcQuery) ||
             i.productName.toUpperCase().contains(epcQuery) ||
             i.sku.toUpperCase().contains(epcQuery) ||
             (i.palletId != null && i.palletId!.toUpperCase().contains(epcQuery)) ||
             (i.locationId != null && i.locationId!.toUpperCase().contains(epcQuery));
    }).toList();

    // Gom nhóm cho Tab 1 (Xuất theo Thùng theo Barcode Thùng)
    final Map<String, List<Item>> cartonGroups = {};
    for (var it in stockItems) {
      final cCode = (it.palletId != null && it.palletId!.isNotEmpty) ? it.palletId! : it.sku;
      cartonGroups.putIfAbsent(cCode, () => []).add(it);
    }

    final cartonQuery = _cartonSearchFilterController.text.trim().toUpperCase();
    final filteredCartonEntries = cartonGroups.entries.where((entry) {
      if (cartonQuery.isEmpty) return true;
      final cCode = entry.key.toUpperCase();
      final pName = entry.value.firstOrNull?.productName.toUpperCase() ?? '';
      final loc = entry.value.firstOrNull?.locationId?.toUpperCase() ?? '';
      return cCode.contains(cartonQuery) || pName.contains(cartonQuery) || loc.contains(cartonQuery);
    }).toList();

    final totalSelectedEpc = _selectedEpcSet.length;
    final totalSelectedCartons = _selectedCartonSet.length;
    final totalSelectedCartonChips = _selectedCartonSet.fold<int>(0, (sum, cCode) {
      final cItems = cartonGroups[cCode] ?? [];
      final customQ = _cartonCustomQty[cCode] ?? (cItems.isNotEmpty ? cItems.length : 1);
      return sum + customQ;
    });

    final totalItemsToDeliver = _createOutboundTab == 0 ? totalSelectedEpc : totalSelectedCartonChips;

    return Container(
      color: c.bgDeep,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Bar
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tạo Phiếu Xuất Kho',
                        style: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        _createOutboundTab == 0
                            ? 'Chế độ Xuất Lẻ: Tích chọn từng sản phẩm theo Mã EPC RFID (quét ZK-105 để tự chọn)'
                            : 'Chế độ Xuất Thùng: Tích chọn từng kiện hàng theo Mã Barcode 128 Thùng',
                        style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                      ),
                    ],
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: totalItemsToDeliver > 0 ? const Color(0xFF10B981) : c.bgCardElevated,
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: Icon(Icons.check_circle, size: 18, color: totalItemsToDeliver > 0 ? const Color(0xFF2C251E) : c.textMuted),
                label: Text(
                  'LƯU & CHUYỂN SANG TRẠM QUÉT ($totalItemsToDeliver SP)',
                  style: TextStyle(
                    color: totalItemsToDeliver > 0 ? const Color(0xFF2C251E) : c.textMuted,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onPressed: () => _saveAndProceedToScan(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cột trái: Thông tin PO & Tóm tắt
                SizedBox(
                  width: 300,
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
                        Text('THÔNG TIN CHUNG', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _deliveryNoController,
                          style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(labelText: 'Mã phiếu xuất (PO No)', labelStyle: TextStyle(color: c.textSecondary, fontSize: 12)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _customerController,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(labelText: 'Khách hàng', hintText: 'Khách mua lẻ / Đại lý...', labelStyle: TextStyle(color: c.textSecondary, fontSize: 12)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _dateController,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(labelText: 'Ngày xuất', labelStyle: TextStyle(color: c.textSecondary, fontSize: 12)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _noteController,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(labelText: 'Ghi chú', hintText: 'Xuất hàng lẻ / sỉ...', labelStyle: TextStyle(color: c.textSecondary, fontSize: 12)),
                        ),
                        const Divider(height: 28),
                        Text('TỔNG QUAN ĐƠN XUẤT', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.bold, fontSize: 11)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c.bgDeep,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: c.border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Hình thức:', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                                  Text(
                                    _createOutboundTab == 0 ? 'Xuất Lẻ (EPC)' : 'Xuất Thùng (Barcode)',
                                    style: TextStyle(color: _createOutboundTab == 0 ? const Color(0xFF0284C7) : const Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11.5),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Số lượng chọn:', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                                  Text(
                                    _createOutboundTab == 0
                                        ? '$totalSelectedEpc SP lẻ'
                                        : '$totalSelectedCartons thùng ($totalSelectedCartonChips SP)',
                                    style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Cột phải: 2 Tab Chọn Hàng (Xuất Lẻ theo EPC vs Xuất Thùng theo Barcode)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Tab Selector
                        Container(
                          decoration: BoxDecoration(
                            color: c.bgDeep,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: c.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: InkWell(
                                  onTap: () => setState(() => _createOutboundTab = 0),
                                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: _createOutboundTab == 0 ? c.rfidCyan.withValues(alpha: 0.2) : Colors.transparent,
                                      borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                                      border: _createOutboundTab == 0 ? Border.all(color: c.rfidCyan) : null,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.qr_code_2, size: 16, color: _createOutboundTab == 0 ? c.rfidCyan : c.textSecondary),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            '🏷️ Xuất Lẻ (Mã EPC) · $totalSelectedEpc SP',
                                            style: TextStyle(
                                              color: _createOutboundTab == 0 ? c.rfidCyan : c.textSecondary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11.5,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: InkWell(
                                  onTap: () => setState(() => _createOutboundTab = 1),
                                  borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                                    decoration: BoxDecoration(
                                      color: _createOutboundTab == 1 ? const Color(0xFF10B981).withValues(alpha: 0.2) : Colors.transparent,
                                      borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                                      border: _createOutboundTab == 1 ? Border.all(color: const Color(0xFF10B981)) : null,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.inventory_2, size: 16, color: _createOutboundTab == 1 ? const Color(0xFF10B981) : c.textSecondary),
                                        const SizedBox(width: 6),
                                        Flexible(
                                          child: Text(
                                            '📦 Xuất Thùng (Barcode) · $totalSelectedCartons Thùng',
                                            style: TextStyle(
                                              color: _createOutboundTab == 1 ? const Color(0xFF10B981) : c.textSecondary,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 11.5,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // TAB CONTENT
                        if (_createOutboundTab == 0) ...[
                          // ================= TAB 0: XUẤT LẺ THEO MÃ EPC =================
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _epcSearchFilterController,
                                  style: TextStyle(color: c.textPrimary, fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'Tìm kiếm mã EPC RFID, Tên SP, Thùng, Vị trí kệ...',
                                    hintStyle: TextStyle(color: c.textMuted, fontSize: 11),
                                    prefixIcon: Icon(Icons.search, size: 16, color: c.textMuted),
                                    filled: true,
                                    fillColor: c.bgDeep,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _desktopUhf.isScanning ? const Color(0xFFEF4444) : c.rfidCyan,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: Icon(_desktopUhf.isScanning ? Icons.stop : Icons.sensors, size: 16, color: const Color(0xFF2C251E)),
                                label: Text(
                                  _desktopUhf.isScanning ? 'DỪNG ĐỌC' : 'BẬT QUÉT ZK-105',
                                  style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                                onPressed: () async {
                                  if (_desktopUhf.isScanning) {
                                    await _desktopUhf.stopInventory();
                                  } else {
                                    if (!_desktopUhf.isConnected) {
                                      await _desktopUhf.connectSerial('COM3', 115200);
                                    }
                                    await _desktopUhf.startInventory();
                                  }
                                  setState(() {});
                                },
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: c.textPrimary,
                                  side: BorderSide(color: c.border),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                ),
                                onPressed: () {
                                  setState(() {
                                    for (var it in filteredEpcItems) {
                                      _selectedEpcSet.add(it.epc.toUpperCase());
                                    }
                                  });
                                },
                                child: const Text('Chọn tất cả', style: TextStyle(fontSize: 11)),
                              ),
                              const SizedBox(width: 6),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: c.errorCoral,
                                  side: BorderSide(color: c.border),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                ),
                                onPressed: () => setState(() => _selectedEpcSet.clear()),
                                child: const Text('Bỏ chọn', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          Expanded(
                            child: filteredEpcItems.isEmpty
                                ? Center(
                                    child: Text('Không có sản phẩm nào trong kho khớp bộ lọc.', style: TextStyle(color: c.textMuted, fontSize: 12)),
                                  )
                                : Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: c.border),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: ListView.separated(
                                      itemCount: filteredEpcItems.length,
                                      separatorBuilder: (_, __) => Divider(color: c.border, height: 1),
                                      itemBuilder: (context, idx) {
                                        final it = filteredEpcItems[idx];
                                        final isChecked = _selectedEpcSet.contains(it.epc.toUpperCase());

                                        return InkWell(
                                          onTap: () {
                                            setState(() {
                                              if (isChecked) {
                                                _selectedEpcSet.remove(it.epc.toUpperCase());
                                              } else {
                                                _selectedEpcSet.add(it.epc.toUpperCase());
                                              }
                                            });
                                          },
                                          child: Container(
                                            color: isChecked ? c.rfidCyan.withValues(alpha: 0.1) : Colors.transparent,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                            child: Row(
                                              children: [
                                                Checkbox(
                                                  value: isChecked,
                                                  activeColor: c.rfidCyan,
                                                  checkColor: const Color(0xFF2C251E),
                                                  onChanged: (val) {
                                                    setState(() {
                                                      if (val == true) {
                                                        _selectedEpcSet.add(it.epc.toUpperCase());
                                                      } else {
                                                        _selectedEpcSet.remove(it.epc.toUpperCase());
                                                      }
                                                    });
                                                  },
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  flex: 3,
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        it.epc,
                                                        style: TextStyle(
                                                          color: isChecked ? c.rfidCyan : c.textPrimary,
                                                          fontFamily: 'Courier',
                                                          fontSize: 12,
                                                          fontWeight: FontWeight.bold,
                                                        ),
                                                      ),
                                                      Text(
                                                        it.productName,
                                                        style: TextStyle(color: c.textSecondary, fontSize: 11),
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Expanded(
                                                  flex: 2,
                                                  child: Text(
                                                    it.palletId ?? it.sku,
                                                    style: TextStyle(color: c.textMuted, fontSize: 11, fontFamily: 'Courier'),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: c.bgDeep,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: c.border),
                                                  ),
                                                  child: Text(
                                                    it.locationId ?? 'Chưa xếp kệ',
                                                    style: TextStyle(color: c.textSecondary, fontSize: 10.5),
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
                        ] else ...[
                          // ================= TAB 1: XUẤT THEO THÙNG THEO BARCODE =================
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _cartonSearchFilterController,
                                  style: TextStyle(color: c.textPrimary, fontSize: 12),
                                  decoration: InputDecoration(
                                    hintText: 'Tìm hoặc quét mã Barcode Thùng (16 ký tự Hex)...',
                                    hintStyle: TextStyle(color: c.textMuted, fontSize: 11),
                                    prefixIcon: Icon(Icons.search, size: 16, color: c.textMuted),
                                    filled: true,
                                    fillColor: c.bgDeep,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                                  ),
                                  onChanged: (val) {
                                    if (val.trim().length == 16) {
                                      final match = cartonGroups.keys.where((k) => k.toUpperCase() == val.trim().toUpperCase()).firstOrNull;
                                      if (match != null) {
                                        _selectedCartonSet.add(match.toUpperCase());
                                      }
                                    }
                                    setState(() {});
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _desktopUhf.isScanning ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                icon: Icon(_desktopUhf.isScanning ? Icons.stop : Icons.sensors, size: 16, color: const Color(0xFF2C251E)),
                                label: Text(
                                  _desktopUhf.isScanning ? 'DỪNG ĐỌC' : 'BẬT QUÉT ZK-105',
                                  style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                                onPressed: () async {
                                  if (_desktopUhf.isScanning) {
                                    await _desktopUhf.stopInventory();
                                  } else {
                                    if (!_desktopUhf.isConnected) {
                                      await _desktopUhf.connectSerial('COM3', 115200);
                                    }
                                    await _desktopUhf.startInventory();
                                  }
                                  setState(() {});
                                },
                              ),
                              const SizedBox(width: 8),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: c.textPrimary,
                                  side: BorderSide(color: c.border),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                ),
                                onPressed: () {
                                  setState(() {
                                    for (var entry in filteredCartonEntries) {
                                      _selectedCartonSet.add(entry.key.toUpperCase());
                                    }
                                  });
                                },
                                child: const Text('Chọn tất cả thùng', style: TextStyle(fontSize: 11)),
                              ),
                              const SizedBox(width: 6),
                              OutlinedButton(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: c.errorCoral,
                                  side: BorderSide(color: c.border),
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                ),
                                onPressed: () => setState(() => _selectedCartonSet.clear()),
                                child: const Text('Bỏ chọn', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),

                          Expanded(
                            child: filteredCartonEntries.isEmpty
                                ? Center(
                                    child: Text('Không có thùng hàng nào trong kho khớp bộ lọc.', style: TextStyle(color: c.textMuted, fontSize: 12)),
                                  )
                                : Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(color: c.border),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: ListView.separated(
                                      itemCount: filteredCartonEntries.length,
                                      separatorBuilder: (_, __) => Divider(color: c.border, height: 1),
                                      itemBuilder: (context, idx) {
                                        final entry = filteredCartonEntries[idx];
                                        final cartonCode = entry.key;
                                        final cItems = entry.value;
                                        final isChecked = _selectedCartonSet.contains(cartonCode.toUpperCase());
                                        final firstItem = cItems.firstOrNull;
                                        final prod = _repo.products.where((p) => p.sku.toUpperCase() == cartonCode.toUpperCase()).firstOrNull;
                                        final pName = firstItem?.productName ?? prod?.productName ?? 'Kiện hàng $cartonCode';
                                        final loc = firstItem?.locationId ?? 'Chưa xếp kệ';
                                        final totalInCarton = cItems.length;
                                        final deliverQty = _cartonCustomQty[cartonCode] ?? totalInCarton;

                                        return InkWell(
                                          onTap: () {
                                            setState(() {
                                              if (isChecked) {
                                                _selectedCartonSet.remove(cartonCode.toUpperCase());
                                              } else {
                                                _selectedCartonSet.add(cartonCode.toUpperCase());
                                              }
                                            });
                                          },
                                          child: Container(
                                            color: isChecked ? const Color(0xFF10B981).withValues(alpha: 0.1) : Colors.transparent,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                                            child: Row(
                                              children: [
                                                Checkbox(
                                                  value: isChecked,
                                                  activeColor: const Color(0xFF10B981),
                                                  checkColor: const Color(0xFF2C251E),
                                                  onChanged: (val) {
                                                    setState(() {
                                                      if (val == true) {
                                                        _selectedCartonSet.add(cartonCode.toUpperCase());
                                                      } else {
                                                        _selectedCartonSet.remove(cartonCode.toUpperCase());
                                                      }
                                                    });
                                                  },
                                                ),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  flex: 3,
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Row(
                                                        children: [
                                                          Text(
                                                            cartonCode,
                                                            style: TextStyle(
                                                              color: isChecked ? const Color(0xFF10B981) : c.textPrimary,
                                                              fontFamily: 'Courier',
                                                              fontSize: 13,
                                                              fontWeight: FontWeight.bold,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 6),
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                            decoration: BoxDecoration(
                                                              color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                              borderRadius: BorderRadius.circular(4),
                                                            ),
                                                            child: Text('Tồn: $totalInCarton SP', style: const TextStyle(color: Color(0xFF10B981), fontSize: 10, fontWeight: FontWeight.bold)),
                                                          ),
                                                        ],
                                                      ),
                                                      Text(pName, style: TextStyle(color: c.textSecondary, fontSize: 11)),
                                                    ],
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: c.bgDeep,
                                                    borderRadius: BorderRadius.circular(4),
                                                    border: Border.all(color: c.border),
                                                  ),
                                                  child: Text(loc, style: TextStyle(color: c.textSecondary, fontSize: 11)),
                                                ),
                                                const SizedBox(width: 16),
                                                Row(
                                                  children: [
                                                    IconButton(
                                                      icon: const Icon(Icons.remove_circle_outline, size: 18),
                                                      color: const Color(0xFF10B981),
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(),
                                                      onPressed: () {
                                                        if (deliverQty > 1) {
                                                          setState(() => _cartonCustomQty[cartonCode] = deliverQty - 1);
                                                        }
                                                      },
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Text('$deliverQty', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
                                                    const SizedBox(width: 6),
                                                    IconButton(
                                                      icon: const Icon(Icons.add_circle_outline, size: 18),
                                                      color: const Color(0xFF10B981),
                                                      padding: EdgeInsets.zero,
                                                      constraints: const BoxConstraints(),
                                                      onPressed: () {
                                                        if (deliverQty < totalInCarton) {
                                                          setState(() => _cartonCustomQty[cartonCode] = deliverQty + 1);
                                                        }
                                                      },
                                                    ),
                                                  ],
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


