import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/warehouse_repository.dart';
import '../../services/uhf_service.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/tower_light_service.dart';
import '../../theme/eye_care_theme.dart';
import '../../widgets/tower_light_widget.dart';
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

  @override
  void initState() {
    super.initState();
    _resetForm();

    _eyeCare.addListener(_onThemeChanged);

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
    super.dispose();
  }

  void _resetForm() {
    final now = DateTime.now();
    _deliveryNoController.text = 'OUT${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    _dateController.text = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    _customerController.text = '';
    _noteController.text = '';
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
        final ok = _repo.confirmOutboundCompletion(
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
    if (code.isEmpty) return;

    final newOrder = OutboundOrder(
      outboundOrderId: 'OUT-${DateTime.now().millisecondsSinceEpoch}',
      poNo: code,
      customer: _customerController.text.trim(),
      createdAt: DateTime.now(),
      status: OutboundOrderStatus.processing,
      details: [
        for (var item in _deliveryItems)
          OutboundOrderDetail(
            productId: item['productCode'],
            sku: item['productCode'],
            productName: item['productName'],
            requiredQty: item['quantity'],
            pickedQty: 0,
          ),
      ],
    );

    await _repo.addOutboundOrder(newOrder);
    setState(() {
      _isCreating = false;
      _selectedLiveOrder = newOrder;
      _currentMode = 0; // Chuyển ngay sang trạm quét live
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF10B981),
          content: Text('Đã tạo phiếu xuất $code. Mời đưa hàng qua trạm quét RFID!'),
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
                    icon: const Icon(Icons.add, color: Colors.white, size: 18),
                    label: const Text('TẠO PHIẾU XUẤT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    final Map<String, int> actualSkuCounts = {};

    int totalRequired = 0;
    if (_selectedLiveOrder != null) {
      totalRequired = _selectedLiveOrder!.details.fold(0, (sum, d) => sum + d.requiredQty);
      final allowedSkus = _selectedLiveOrder!.details.map((d) => d.sku).toSet();

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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left Column: Order Selection & Controls
        SizedBox(
          width: 380,
          child: SingleChildScrollView(
            child: Column(
              children: [
              // Tháp đèn tín hiệu công nghiệp CTP50-3T-D-J
              const TowerLightWidget(),
              const SizedBox(height: 12),

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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('📋 ĐƠN XUẤT KHO', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                        InkWell(
                          onTap: _generateFifo,
                          child: const Text('Tính FIFO', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ],
                    ),
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
                    if (_activeFifoPlan != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: c.bgCardElevated,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('✅ Kế hoạch Lấy hàng (FIFO)', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11)),
                            const SizedBox(height: 4),
                            ..._activeFifoPlan!.lines.map((l) => Text(
                              '• ${l.productName} (${l.sku}): Lấy ${l.quantityToPick} cái tại Pallet ${l.palletCode} (Vị trí: ${l.locationCode})',
                              style: TextStyle(color: c.textSecondary, fontSize: 10),
                            )),
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
                              Text('$totalMatched', style: const TextStyle(color: Color(0xFF10B981), fontSize: 40, fontWeight: FontWeight.w900)),
                              Text('Hợp lệ', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                            ],
                          ),
                          Container(width: 1, height: 35, color: c.border),
                          Column(
                            children: [
                              Text('$totalRequired', style: TextStyle(color: c.rfidCyan, fontSize: 40, fontWeight: FontWeight.w900)),
                              Text('Yêu cầu', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                            ],
                          ),
                          if (unexpectedEpcs.isNotEmpty) ...[
                            Container(width: 1, height: 35, color: c.border),
                            Column(
                              children: [
                                Text('${unexpectedEpcs.length}', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 40, fontWeight: FontWeight.w900)),
                                const Text('Sai hàng', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ] else ...[
                      Column(
                        children: [
                          Text('${_scannedTags.length}', style: TextStyle(color: c.textPrimary, fontSize: 44, fontWeight: FontWeight.w900)),
                          Text('Thẻ RFID đã quét để xuất kho', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                        ],
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
                    backgroundColor: (_selectedLiveOrder != null
                            ? (totalMatched > 0 && unexpectedEpcs.isEmpty)
                            : _scannedTags.isNotEmpty)
                        ? const Color(0xFF10B981)
                        : Colors.grey.shade600,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.local_shipping, color: Colors.white),
                  label: Text(
                    _isSaving
                        ? 'Đang lưu...'
                        : (_selectedLiveOrder != null
                            ? 'XÁC NHẬN XUẤT KHO ($totalMatched CHIP)'
                            : 'XÁC NHẬN XUẤT KHO (${_scannedTags.length} CHIP)'),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  onPressed: (_isSaving ||
                          (_selectedLiveOrder != null
                              ? (totalMatched == 0 || unexpectedEpcs.isEmpty)
                              : _scannedTags.isEmpty))
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
                                  final antLabel = tag.ant.isNotEmpty ? tag.ant : '1';
                                  final isAnt2 = antLabel == '2';

                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                                    child: Row(
                                      children: [
                                        Icon(
                                          isUnexpected ? Icons.cancel : Icons.check_circle,
                                          color: isUnexpected ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            epc,
                                            style: TextStyle(
                                              color: isUnexpected ? const Color(0xFFEF4444) : c.textPrimary,
                                              fontFamily: 'monospace',
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
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
                    icon: const Icon(Icons.add, color: Colors.white),
                    label: const Text('Tạo Phiếu Xuất Mới', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(order.poNo, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text('Khách hàng: ${order.customer} | Số lượng: $totalQty sản phẩm', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                          ],
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

  Widget _buildCreateDeliveryForm(EyeCareColors c) {
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
                  Text('Tạo Phiếu Xuất Hàng Mới', style: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.bold)),
                ],
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
                onPressed: _saveAndProceedToScan,
                child: const Text('LƯU & CHUYỂN SANG QUÉT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
                      children: [
                        TextField(
                          controller: _deliveryNoController,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(labelText: 'Mã phiếu xuất', labelStyle: TextStyle(color: c.textSecondary, fontSize: 12)),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _customerController,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(labelText: 'Khách hàng', labelStyle: TextStyle(color: c.textSecondary, fontSize: 12)),
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
                        Text('DANH SÁCH MẶT HÀNG CẦN XUẤT', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            child: Table(
                              border: TableBorder.all(color: c.border),
                              children: [
                                TableRow(
                                  decoration: BoxDecoration(color: c.bgCardElevated),
                                  children: [
                                    Padding(padding: const EdgeInsets.all(10), child: Text('Mã Sản Phẩm', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                                    Padding(padding: const EdgeInsets.all(10), child: Text('Tên Sản Phẩm', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                                    Padding(padding: const EdgeInsets.all(10), child: Text('Số Lượng Xuất', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                                  ],
                                ),
                                for (var it in _deliveryItems)
                                  TableRow(
                                    children: [
                                      Padding(padding: const EdgeInsets.all(10), child: Text(it['productCode'], style: TextStyle(color: c.textPrimary, fontSize: 12))),
                                      Padding(padding: const EdgeInsets.all(10), child: Text(it['productName'], style: TextStyle(color: c.textSecondary, fontSize: 12))),
                                      Padding(padding: const EdgeInsets.all(10), child: Text('${it['quantity']}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13))),
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
