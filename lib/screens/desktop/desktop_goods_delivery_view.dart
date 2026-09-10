import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/tag_info.dart';
import '../../models/wms_models.dart';
import '../../services/auth_service.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/tower_light_service.dart';
import '../../services/uhf_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';
import '../../widgets/warehouse_location_grid_widget.dart';

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

  // Mode: 0 = Quy trình xuất kho (Sơ đồ vị trí & Cổng RFID), 1 = Lịch sử xuất kho
  int _currentMode = 0;

  // Wizard Step: 1 = Chọn hàng từ sơ đồ 10 vị trí, 2 = Cổng quét RFID đối soát xuất kho
  int _wizardStep = 1;

  // Vị trí đang được chọn để lọc bảng sản phẩm (null = Xem tất cả)
  String? _selectedLocationId;

  // Tìm kiếm sản phẩm
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Các thẻ / sản phẩm được chọn để xuất kho
  final Set<String> _selectedEpcs = {};

  // Step 2: Cổng RFID Station
  final Map<String, TagInfo> _gateScannedTags = {};
  bool _isScanning = false;
  int _scanDurationSeconds = 5;
  int _scanCountdown = 5;
  Timer? _countdownTimer;
  Timer? _uiRefreshTimer;
  bool _isSaving = false;

  StreamSubscription<TagInfo>? _uhfSub;
  StreamSubscription<TagInfo>? _desktopUhfSub;

  // Thông tin đơn xuất kho (tùy chọn)
  final TextEditingController _outboundPoController = TextEditingController();
  final TextEditingController _customerController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _resetForm();

    _eyeCare.addListener(_onThemeChanged);
    _repo.addListener(_onThemeChanged);
    _auth.addListener(_onThemeChanged);
    _desktopUhf.addListener(_onDesktopUhfUpdate);

    _initTagListeners();
  }

  void _resetForm() {
    final now = DateTime.now();
    _outboundPoController.text =
        'OUT${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';
    _customerController.text = 'Khách mua xuất kho';
    _noteController.text = '';
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onDesktopUhfUpdate() {
    if (!mounted || !widget.isActive) return;
    setState(() {
      _isScanning = _desktopUhf.isScanning;
      if (_wizardStep == 2) {
        for (final tag in _desktopUhf.tags) {
          _gateScannedTags[tag.epc.toUpperCase()] = tag;
        }
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
    if (_wizardStep != 2) return;

    final epc = tag.epc.trim().toUpperCase();
    if (_uhf.filterDuplicates && _gateScannedTags.containsKey(epc)) return;

    _gateScannedTags[epc] = tag;

    // Đánh giá trạng thái đối soát với danh sách xuất
    final expectedEpcs = _selectedEpcs;
    final totalExpected = expectedEpcs.length;
    final totalScanned = _gateScannedTags.length;

    final unexpected = _gateScannedTags.keys.where((e) => !expectedEpcs.contains(e)).toList();

    if (unexpected.isNotEmpty) {
      _towerLight.triggerWarningRed(
        withBuzzer: true,
        reason: 'CẢNH BÁO: Phát hiện ${unexpected.length} chip RFID lạ ngoài danh sách xuất kho!',
      );
    } else if (totalExpected > 0 && totalScanned >= totalExpected) {
      _towerLight.triggerPass(
        reason: 'ĐỦ HÀNG XUẤT KHO: $totalScanned/$totalExpected chip đã thông qua cổng RFID!',
      );
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
    _uhfSub?.cancel();
    _desktopUhfSub?.cancel();
    _searchController.dispose();
    _outboundPoController.dispose();
    _customerController.dispose();
    _noteController.dispose();
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

  Future<void> _startGateScan({int durationSeconds = 5}) async {
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
          _stopGateScan();
        }
      });
    }
  }

  Future<void> _stopGateScan() async {
    _countdownTimer?.cancel();
    _uhf.stopInventory();
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


  List<Item> _getAllStockedItems() {
    return _repo.items.where((it) => it.status == ItemStatus.inStock || it.status == ItemStatus.allocated).toList();
  }

  List<Item> _getFilteredItems() {
    List<Item> items;
    if (_selectedLocationId != null) {
      final loc = _repo.locations.where((l) => l.locationId == _selectedLocationId || l.locationCode == _selectedLocationId).firstOrNull;
      items = loc != null ? _repo.getItemsAtLocation(loc) : _getAllStockedItems();
    } else {
      items = _getAllStockedItems();
    }

    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toUpperCase();
      items = items.where((it) {
        return it.sku.toUpperCase().contains(q) ||
            it.productId.toUpperCase().contains(q) ||
            it.serialNumber.toUpperCase().contains(q) ||
            it.productName.toUpperCase().contains(q) ||
            it.epc.toUpperCase().contains(q) ||
            (it.palletId != null && it.palletId!.toUpperCase().contains(q)) ||
            (it.locationId != null && it.locationId!.toUpperCase().contains(q));
      }).toList();
    }

    // Ưu tiên gợi ý xuất kho FIFO: Trong trường hợp 1 mã hàng có ngày nhập khác nhau,
    // ưu tiên đẩy gợi ý có ngày nhập xa hiện tại nhất (cũ nhất) lên đầu.
    items.sort((a, b) {
      final skuComp = a.sku.trim().toLowerCase().compareTo(b.sku.trim().toLowerCase());
      if (skuComp != 0) return skuComp;

      final timeA = a.inboundTime;
      final timeB = b.inboundTime;
      if (timeA == null && timeB == null) return 0;
      if (timeA == null) return 1;
      if (timeB == null) return -1;
      return timeA.compareTo(timeB); // Nhỏ hơn (xa thời điểm hiện tại hơn) lên đầu
    });

    return items;
  }

  void _suggestFifoOutbound(List<Item> currentItems) {
    if (currentItems.isEmpty) return;
    final Map<String, List<Item>> skuMap = {};
    for (var it in currentItems) {
      skuMap.putIfAbsent(it.sku.trim().toLowerCase(), () => []).add(it);
    }

    final Set<String> toSelect = {};
    for (var list in skuMap.values) {
      list.sort((a, b) {
        final tA = a.inboundTime;
        final tB = b.inboundTime;
        if (tA == null && tB == null) return 0;
        if (tA == null) return 1;
        if (tB == null) return -1;
        return tA.compareTo(tB);
      });
      if (list.isNotEmpty) {
        final oldestTime = list.first.inboundTime;
        if (oldestTime != null) {
          final oldestBatch = list.where((i) => i.inboundTime == oldestTime);
          for (var it in oldestBatch) {
            toSelect.add(it.epc.toUpperCase());
          }
        } else {
          toSelect.add(list.first.epc.toUpperCase());
        }
      }
    }

    setState(() {
      _selectedEpcs.addAll(toSelect);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        duration: const Duration(seconds: 3),
        content: Text('⚡ Đã tự động gợi ý chọn ${toSelect.length} sản phẩm có ngày nhập xa hiện tại nhất (FIFO)!'),
      ),
    );
  }


  // ---------- HOÀN TẤT XUẤT KHO QUA CỔNG RFID (STEP 2) ----------
  Future<void> _completeGateOutbound() async {
    final scannedEpcs = _gateScannedTags.keys.toList();
    final expectedEpcs = _selectedEpcs.toList();

    if (scannedEpcs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Chưa quét được sản phẩm nào qua cổng RFID! Vui lòng bật quét.'),
        ),
      );
      return;
    }

    final unexpected = scannedEpcs.where((e) => !expectedEpcs.contains(e)).toList();
    if (unexpected.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFEF4444),
          content: Text('⛔ Có ${unexpected.length} chip lạ ngoài đơn! Vui lòng loại bỏ trước khi hoàn tất.'),
        ),
      );
      return;
    }

    if (scannedEpcs.length < expectedEpcs.length) {
      final diff = expectedEpcs.length - scannedEpcs.length;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: _eyeCare.colors.bgCard,
          title: const Text('Chưa quét đủ số lượng'),
          content: Text('Còn thiếu $diff sản phẩm chưa qua cổng RFID. Bạn có chắc muốn xuất kho phần đã quét (${scannedEpcs.length} SP)?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Quét tiếp')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Vẫn xuất phần đã quét'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    setState(() => _isSaving = true);
    try {
      if (_isScanning) _stopGateScan();

      final shippedCount = await _repo.confirmDirectOutbound(
        poNo: _outboundPoController.text.trim(),
        scannedEpcs: scannedEpcs,
        performedBy: _auth.currentUser?.fullName ?? 'Cổng RFID Gate Outbound',
      );

      _towerLight.triggerPass(reason: 'HOÀN TẤT XUẤT KHO: $shippedCount sản phẩm đã thông qua cổng');

      if (!mounted) return;

      // Hiển thị dialog hoàn tất thành công
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
                  'Đã thông qua cổng và xuất $shippedCount sản phẩm.\nSố lượng tồn vị trí đã được tự động cập nhật và trừ tồn kho.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _eyeCare.colors.textSecondary, fontSize: 12.5),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: _eyeCare.colors.border),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: Icon(Icons.dashboard_outlined, size: 16, color: _eyeCare.colors.textPrimary),
                        label: Text('VỀ SƠ ĐỒ KHO', style: TextStyle(color: _eyeCare.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                        onPressed: () {
                          Navigator.of(dialogCtx).pop();
                          setState(() {
                            _wizardStep = 1;
                            _selectedEpcs.clear();
                            _clearGateScan();
                            _resetForm();
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('XUẤT ĐƠN TIẾP', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                        onPressed: () {
                          Navigator.of(dialogCtx).pop();
                          setState(() {
                            _wizardStep = 1;
                            _selectedEpcs.clear();
                            _clearGateScan();
                            _resetForm();
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


  // ==================== MAIN BUILD METHOD ====================
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
              // Top Bar Header
              _buildTopHeaderBar(c, isNarrow),
              const SizedBox(height: 8),

              // Main Body Wizard / List
              Expanded(
                child: _currentMode == 0 ? _buildOutboundWizard(c) : _buildDeliveryHistory(c),
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

  // ---------- HEADER & MODE TABS ----------
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
          Row(
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
                children: [
                  Text(
                    'QUẢN LÝ XUẤT KHO RFID',
                    style: TextStyle(color: c.textPrimary, fontSize: isNarrow ? 15 : 18, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Sơ đồ 10 vị trí • Kiểm đếm hàng hóa • Cổng quét RFID đối soát xuất xe',
                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),

          // Tabs Mode Switcher
          Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: c.bgDeep,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    _buildTopTabItem(0, 'XUẤT KHO THEO SƠ ĐỒ', Icons.map_outlined, c),
                    _buildTopTabItem(1, 'LỊCH SỬ XUẤT KHO', Icons.receipt_long_outlined, c),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
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
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabItem(int mode, String title, IconData icon, EyeCareColors c) {
    final isSelected = _currentMode == mode;
    return InkWell(
      onTap: () => setState(() => _currentMode = mode),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? Colors.white : c.textSecondary),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : c.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- WIZARD WRAPPER ----------
  Widget _buildOutboundWizard(EyeCareColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: _wizardStep == 1 ? _buildStep1LocationAndStockTable(c) : _buildStep2GateOutboundLive(c),
      ),
    );
  }

  // ==================== BƯỚC 1: SƠ ĐỒ 10 VỊ TRÍ & BẢNG SẢN PHẨM ====================
  Widget _buildStep1LocationAndStockTable(EyeCareColors c) {
    final items = _getFilteredItems();
    final allStock = _getAllStockedItems();

    final allSelected = items.isNotEmpty && items.every((i) => _selectedEpcs.contains(i.epc.toUpperCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---------- 1. PHẦN TRÊN: SƠ ĐỒ 10 VỊ TRÍ (CÁC Ô KỆ DỄ NHÌN) ----------
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: WarehouseLocationGridWidget(
            mode: WarehouseLocationGridMode.outbound,
            selectedLocationId: _selectedLocationId,
            onLocationSelected: (locId) {
              setState(() {
                _selectedLocationId = locId;
              });
            },
            onLocationDataChanged: () {
              setState(() {});
            },
          ),
        ),

        // ---------- 2. BỘ LỌC TÌM KIẾM & THAO TÁC CHỌN NHANH ----------
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: c.bgDeep,
            border: Border(bottom: BorderSide(color: c.border)),
          ),
          child: Row(
            children: [
              // Checkbox Chọn tất cả
              InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  setState(() {
                    if (allSelected) {
                      for (var it in items) {
                        _selectedEpcs.remove(it.epc.toUpperCase());
                      }
                    } else {
                      for (var it in items) {
                        _selectedEpcs.add(it.epc.toUpperCase());
                      }
                    }
                  });
                },
                child: Row(
                  children: [
                    Checkbox(
                      value: allSelected,
                      activeColor: const Color(0xFF10B981),
                      checkColor: Colors.white,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            for (var it in items) {
                              _selectedEpcs.add(it.epc.toUpperCase());
                            }
                          } else {
                            for (var it in items) {
                              _selectedEpcs.remove(it.epc.toUpperCase());
                            }
                          }
                        });
                      },
                    ),
                    Text(
                      'Chọn tất cả (${items.length} SP)',
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),

              // Nút gợi ý xuất FIFO (Ưu tiên lô xa nhất)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.flash_on, size: 15),
                label: const Text(
                  'GỢI Ý FIFO (LÔ XA NHẤT)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
                onPressed: () => _suggestFifoOutbound(items),
              ),
              const SizedBox(width: 14),

              // Ô tìm kiếm
              Expanded(
                child: SizedBox(
                  height: 38,
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: c.textPrimary, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm theo mã SKU, tên sản phẩm, mã RFID EPC, mã thùng...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 11.5),
                      prefixIcon: Icon(Icons.search, size: 16, color: c.textMuted),
                      filled: true,
                      fillColor: c.bgCard,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Tổng số tồn kho & Đã chọn xuất
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Text('Tồn kho: ', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                    Text('${allStock.length} SP', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5)),
                    const SizedBox(width: 8),
                    Text('• Đang chọn: ', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                    Text('${_selectedEpcs.length} SP', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 11.5)),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ---------- 3. BẢNG SỐ LIỆU SẢN PHẨM TỒN KHO (CHUẨN DOANH NGHIỆP NHẬP KHO) ----------
        Expanded(
          child: Column(
            children: [
              // Header bảng
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  border: Border(bottom: BorderSide(color: c.border)),
                ),
                child: Row(
                  children: [
                    SizedBox(width: 45, child: Text('CHỌN', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    SizedBox(width: 45, child: Text('STT', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    SizedBox(width: 110, child: Text('VỊ TRÍ KỆ', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    SizedBox(width: 130, child: Text('MÃ THÙNG / PALLET', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    SizedBox(width: 140, child: Text('MÃ SKU', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    Expanded(flex: 3, child: Text('TÊN SẢN PHẨM / QUY CÁCH', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    Expanded(flex: 3, child: Text('MÃ CHIP RFID (EPC)', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    SizedBox(width: 170, child: Text('NGÀY NHẬP KHO (FIFO)', style: TextStyle(color: const Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold))),
                    const SizedBox(width: 8),
                    SizedBox(width: 110, child: Text('TRẠNG THÁI', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                  ],
                ),
              ),

              // Rows dữ liệu
              Expanded(
                child: items.isEmpty
                    ? Center(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 38, color: c.textSecondary.withValues(alpha: 0.5)),
                              const SizedBox(height: 8),
                              Text(
                                _selectedLocationId != null
                                    ? 'Không có sản phẩm nào đang lưu tại vị trí này'
                                    : 'Không có sản phẩm nào khớp với tìm kiếm',
                                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Vui lòng chọn vị trí khác hoặc xóa bộ lọc tìm kiếm.',
                                style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final it = items[index];
                          final isSelected = _selectedEpcs.contains(it.epc.toUpperCase());
                          final locName = it.locationId ?? 'Chưa xếp kệ';
                          final pallet = it.palletId ?? '--';

                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  _selectedEpcs.remove(it.epc.toUpperCase());
                                } else {
                                  _selectedEpcs.add(it.epc.toUpperCase());
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? const Color(0xFF10B981).withValues(alpha: 0.08)
                                    : (index % 2 == 0 ? Colors.transparent : c.bgDeep.withValues(alpha: 0.3)),
                                border: Border(
                                  bottom: BorderSide(
                                    color: isSelected
                                        ? const Color(0xFF10B981).withValues(alpha: 0.3)
                                        : c.border.withValues(alpha: 0.35),
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 45,
                                    child: Center(
                                      child: Checkbox(
                                        value: isSelected,
                                        activeColor: const Color(0xFF10B981),
                                        checkColor: Colors.white,
                                        onChanged: (val) {
                                          setState(() {
                                            if (val == true) {
                                              _selectedEpcs.add(it.epc.toUpperCase());
                                            } else {
                                              _selectedEpcs.remove(it.epc.toUpperCase());
                                            }
                                          });
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 45,
                                    child: Text(
                                      '${index + 1}',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 110,
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                          border: Border.all(color: const Color(0xFF3B82F6)),
                                        ),
                                        child: Text(
                                          locName,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(color: Color(0xFF3B82F6), fontWeight: FontWeight.bold, fontSize: 11),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 130,
                                    child: Text(
                                      pallet,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: c.textSecondary, fontFamily: 'monospace', fontSize: 11),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 140,
                                    child: Text(
                                      it.sku,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      it.productName,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      it.epc,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: isSelected ? const Color(0xFF10B981) : c.textSecondary,
                                        fontFamily: 'monospace',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 170,
                                    child: Builder(
                                      builder: (context) {
                                        if (it.inboundTime == null) {
                                          return Text('--', style: TextStyle(color: c.textSecondary, fontSize: 11));
                                        }
                                        final inTime = it.inboundTime!;
                                        final daysAgo = DateTime.now().difference(inTime).inDays;
                                        final sameSkuItems = items.where((x) => x.sku.trim().toLowerCase() == it.sku.trim().toLowerCase() && x.inboundTime != null).toList();
                                        final isOldestBatch = sameSkuItems.isNotEmpty && !sameSkuItems.any((x) => x.inboundTime!.isBefore(inTime));

                                        return Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              it.formattedInboundDate,
                                              style: TextStyle(
                                                color: isOldestBatch ? const Color(0xFFF59E0B) : c.textPrimary,
                                                fontSize: 11,
                                                fontWeight: isOldestBatch ? FontWeight.bold : FontWeight.normal,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            if (isOldestBatch)
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                                decoration: BoxDecoration(
                                                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(4),
                                                  border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5), width: 0.8),
                                                ),
                                                child: Text(
                                                  '⚡ Lô xa nhất (${daysAgo > 0 ? "$daysAgo ngày trước" : "Hôm nay"})',
                                                  style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 9.5, fontWeight: FontWeight.bold),
                                                ),
                                              )
                                            else
                                              Text(
                                                '${daysAgo > 0 ? "$daysAgo ngày trước" : "Hôm nay"} (Mới hơn)',
                                                style: TextStyle(color: c.textSecondary, fontSize: 10),
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 110,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                              : c.bgDeep,
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(
                                            color: isSelected ? const Color(0xFF10B981) : c.border,
                                          ),
                                        ),
                                        child: Text(
                                          isSelected ? '📦 CHỌN XUẤT' : '🟢 TỒN KHO',
                                          style: TextStyle(
                                            color: isSelected ? const Color(0xFF10B981) : c.textSecondary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
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

        // ---------- 4. THANH HÀNH ĐỘNG DƯỚI CÙNG (BOTTOM ACTION BAR) ----------
        // ---------- 4. FOOTER THANH ĐIỀU HƯỚNG BƯỚC 1 ----------
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: c.bgCardElevated,
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Thông tin số lượng đã chọn (Bên trái)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle_outline, size: 20, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Text(
                    'ĐÃ CHỌN: ${_selectedEpcs.length} / ${items.length} SẢN PHẨM ĐỂ XUẤT KHO',
                    style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),

              // NÚT TIẾP TỤC QUA CỔNG RFID (Đẩy sát góc phải)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.rfidCyan,
                  foregroundColor: const Color(0xFF2C251E),
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 1,
                ),
                icon: const Icon(Icons.arrow_forward, size: 17),
                label: const Text(
                  'TIẾP TỤC: QUA CỔNG RFID XUẤT KHO ➜',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
                onPressed: () {
                  if (_selectedEpcs.isEmpty) {
                    // Tự động chọn tất cả nếu chưa chọn
                    for (var it in items) {
                      _selectedEpcs.add(it.epc.toUpperCase());
                    }
                  }
                  setState(() {
                    _wizardStep = 2;
                    _clearGateScan();
                  });
                },
              ),
            ],
          ),
        ),
      ],
    );
  }


  // ==================== BƯỚC 2: CỔNG RFID XUẤT KHO LIVE ====================
  Widget _buildStep2GateOutboundLive(EyeCareColors c) {
    final expectedEpcs = _selectedEpcs.toList();
    final expectedCount = expectedEpcs.length;
    final scannedCount = _gateScannedTags.length;
    final progress = expectedCount > 0 ? (scannedCount / expectedCount).clamp(0.0, 1.0) : 0.0;
    final isComplete = expectedCount > 0 && scannedCount >= expectedCount;

    final unexpected = _gateScannedTags.keys.where((e) => !expectedEpcs.contains(e)).toList();
    final hasUnexpected = unexpected.isNotEmpty;

    // Danh sách hiển thị sản phẩm đối soát
    final allItemsMap = {for (var i in _repo.items) i.epc.toUpperCase(): i};

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Navigation Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.textPrimary,
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('QUAY LẠI CHỌN HÀNG', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                onPressed: () {
                  _stopGateScan();
                  setState(() => _wizardStep = 1);
                },
              ),
              Row(
                children: [
                  Text('Mã phiếu: ', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  Text(_outboundPoController.text, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(width: 16),
                  Text('Khách hàng: ', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  Text(_customerController.text, style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),

          // KHỐI ĐIỀU KHIỂN CỔNG QUÉT & TIẾN ĐỘ ĐỐI SOÁT
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: hasUnexpected
                    ? const Color(0xFFEF4444)
                    : (isComplete ? const Color(0xFF10B981) : c.border),
                width: hasUnexpected || isComplete ? 1.5 : 1.0,
              ),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Icon trạng thái
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: hasUnexpected
                            ? const Color(0xFFEF4444).withValues(alpha: 0.15)
                            : (isComplete ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFF59E0B).withValues(alpha: 0.15)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        hasUnexpected ? Icons.error_outline : (isComplete ? Icons.check_circle : Icons.sensors),
                        color: hasUnexpected ? const Color(0xFFEF4444) : (isComplete ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Tiêu đề & Thông báo trạng thái
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'CỔNG QUÉT XUẤT KHO RFID',
                                style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _desktopUhf.isConnected ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFEF4444).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  _desktopUhf.isConnected ? 'CỔNG SẴN SÀNG (COM3)' : 'CHƯA KẾT NỐI COM3',
                                  style: TextStyle(
                                    color: _desktopUhf.isConnected ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            hasUnexpected
                                ? '⛔ PHÁT HIỆN ${unexpected.length} CHIP LẠ NGOÀI ĐƠN! VUI LÒNG DỪNG XE KIỂM TRA'
                                : (isComplete
                                    ? '✅ ĐÃ ĐỐI SOÁT ĐỦ $scannedCount/$expectedCount SẢN PHẨM • SẴN SÀNG XÁC NHẬN XUẤT KHO'
                                    : (scannedCount > 0 ? '⚡ Đang quét hàng qua cổng... Còn thiếu ${expectedCount - scannedCount} sản phẩm' : 'Đưa pallet/kiện hàng đã chọn đi qua cổng RFID để đối soát')),
                            style: TextStyle(
                              color: hasUnexpected
                                  ? const Color(0xFFEF4444)
                                  : (isComplete ? const Color(0xFF10B981) : c.textSecondary),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Bộ đếm to (Hero Counter)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: isComplete ? const Color(0xFF10B981).withValues(alpha: 0.12) : c.bgDeep,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isComplete ? const Color(0xFF10B981) : c.border),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '$scannedCount',
                            style: TextStyle(
                              color: isComplete ? const Color(0xFF10B981) : (scannedCount > 0 ? const Color(0xFFF59E0B) : c.textPrimary),
                              fontSize: 28,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(' / $expectedCount SP', style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Tiến độ ProgressBar
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: c.bgDeep,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      hasUnexpected ? const Color(0xFFEF4444) : (isComplete ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Thanh nút điều khiển quét
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      // Chọn thời gian quét
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: c.bgDeep,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.border),
                        ),
                        child: DropdownButton<int>(
                          value: _scanDurationSeconds,
                          underline: const SizedBox(),
                          dropdownColor: c.bgCardElevated,
                          style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                          items: const [
                            DropdownMenuItem(value: 3, child: Text('⏱️ Quét 3 giây')),
                            DropdownMenuItem(value: 5, child: Text('⏱️ Quét 5 giây (Chuẩn)')),
                            DropdownMenuItem(value: 10, child: Text('⏱️ Quét 10 giây')),
                            DropdownMenuItem(value: 0, child: Text('⏱️ Quét liên tục')),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _scanDurationSeconds = v);
                          },
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Nút Bật/Dừng quét
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _isScanning ? const Color(0xFFEF4444) : c.rfidCyan,
                          foregroundColor: const Color(0xFF2C251E),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: Icon(_isScanning ? Icons.stop : Icons.sensors, size: 16),
                        label: Text(
                          _isScanning
                              ? (_scanDurationSeconds > 0 ? 'DỪNG QUÉT (${_scanCountdown}s)' : 'DỪNG QUÉT')
                              : (_scanDurationSeconds > 0 ? 'BẬT QUÉT RFID (${_scanDurationSeconds}s)' : 'BẬT QUÉT LIÊN TỤC'),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                        ),
                        onPressed: _toggleGateScan,
                      ),
                      const SizedBox(width: 8),

                      // Nút Xóa kết quả
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: c.textSecondary,
                          side: BorderSide(color: c.border),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        ),
                        onPressed: _clearGateScan,
                        child: const Text('XÓA KẾT QUẢ', style: TextStyle(fontSize: 11.5)),
                      ),
                      const SizedBox(width: 16),

                      // NÚT XÁC NHẬN HOÀN TẤT XUẤT KHO
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: (scannedCount > 0 && !hasUnexpected) ? const Color(0xFF10B981) : c.bgDeep,
                          foregroundColor: (scannedCount > 0 && !hasUnexpected) ? Colors.white : c.textMuted,
                          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: Text(
                          _isSaving ? 'ĐANG LƯU...' : 'XÁC NHẬN HOÀN TẤT XUẤT KHO ($scannedCount SP)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                        ),
                        onPressed: (_isSaving || scannedCount == 0 || hasUnexpected) ? null : _completeGateOutbound,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // BẢNG ĐỐI SOÁT CHI TIẾT
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: c.bgDeep,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      border: Border(bottom: BorderSide(color: c.border)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 45, child: Text('STT', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        Expanded(flex: 3, child: Text('MÃ RFID EPC', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        SizedBox(width: 150, child: Text('MÃ SKU', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        Expanded(flex: 3, child: Text('TÊN SẢN PHẨM', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        SizedBox(width: 120, child: Text('VỊ TRÍ KỆ GỐC', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                        const SizedBox(width: 8),
                        SizedBox(width: 150, child: Text('KẾT QUẢ CỔNG', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold))),
                      ],
                    ),
                  ),

                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      itemCount: expectedEpcs.length + unexpected.length,
                      itemBuilder: (context, index) {
                        if (index < expectedEpcs.length) {
                          final epc = expectedEpcs[index];
                          final item = allItemsMap[epc];
                          final isPassed = _gateScannedTags.containsKey(epc);

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: isPassed ? const Color(0xFF10B981).withValues(alpha: 0.08) : Colors.transparent,
                              border: Border(bottom: BorderSide(color: c.border.withValues(alpha: 0.35))),
                            ),
                            child: Row(
                              children: [
                                SizedBox(width: 45, child: Text('${index + 1}', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11))),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    epc,
                                    style: TextStyle(
                                      color: isPassed ? const Color(0xFF10B981) : c.textPrimary,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(width: 150, child: Text(item?.sku ?? '--', style: TextStyle(color: c.textPrimary, fontSize: 11.5, fontWeight: FontWeight.w600))),
                                const SizedBox(width: 8),
                                Expanded(flex: 3, child: Text(item?.productName ?? 'Sản phẩm', style: TextStyle(color: c.textSecondary, fontSize: 11.5))),
                                const SizedBox(width: 8),
                                SizedBox(width: 120, child: Text(item?.locationId ?? '--', style: TextStyle(color: c.textMuted, fontSize: 11))),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 150,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isPassed ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFF59E0B).withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isPassed ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                                      ),
                                      child: Text(
                                        isPassed ? '✅ ĐÃ QUA CỔNG' : '⏳ CHỜ QUA CỔNG',
                                        style: TextStyle(
                                          color: isPassed ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        } else {
                          // Chip lạ ngoài danh sách
                          final unexpIndex = index - expectedEpcs.length;
                          final epc = unexpected[unexpIndex];
                          final item = allItemsMap[epc];

                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                              border: Border(bottom: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.4))),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 45, child: Icon(Icons.warning, size: 16, color: Color(0xFFEF4444))),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: Text(
                                    epc,
                                    style: const TextStyle(color: Color(0xFFEF4444), fontFamily: 'monospace', fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(width: 150, child: Text(item?.sku ?? 'CHIP LẠ', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11.5, fontWeight: FontWeight.bold))),
                                const SizedBox(width: 8),
                                Expanded(flex: 3, child: Text(item?.productName ?? 'Không nằm trong danh sách xuất', style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11))),
                                const SizedBox(width: 8),
                                SizedBox(width: 120, child: Text(item?.locationId ?? '--', style: TextStyle(color: c.textMuted, fontSize: 11))),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 150,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFFEF4444)),
                                      ),
                                      child: const Text(
                                        '⛔ CHIP LẠ NGOÀI ĐƠN',
                                        style: TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.bold),
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
          ),
        ],
      ),
    );
  }

  // ==================== TAB 2: LỊCH SỬ XUẤT KHO ====================
  Widget _buildDeliveryHistory(EyeCareColors c) {
    final orders = _repo.outboundOrders;
    final transactions = _repo.transactions.where((t) => t.type == TransactionType.outbound).toList();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LỊCH SỬ GIAO DỊCH XUẤT KHO (${transactions.length} giao dịch)',
            style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: transactions.isEmpty && orders.isEmpty
                ? Center(
                    child: Text('Chưa có giao dịch xuất kho nào.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                  )
                : Container(
                    decoration: BoxDecoration(
                      color: c.bgCardElevated,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border),
                    ),
                    child: ListView.separated(
                      itemCount: transactions.isNotEmpty ? transactions.length : orders.length,
                      separatorBuilder: (context, index) => Divider(color: c.border.withValues(alpha: 0.4), height: 1),
                      itemBuilder: (context, idx) {
                        if (transactions.isNotEmpty) {
                          final tx = transactions[idx];
                          return ListTile(
                            leading: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.outbox, color: Color(0xFF10B981), size: 18),
                            ),
                            title: Text('${tx.documentNo} • ${tx.productName}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text('Số lượng: ${tx.quantity} SP • Người xuất: ${tx.performedBy} • ${tx.timestamp.toLocal()}', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('ĐÃ XUẤT', style: TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold)),
                            ),
                          );
                        } else {
                          final o = orders[idx];
                          final count = o.details.fold(0, (sum, d) => sum + d.requiredQty);
                          return ListTile(
                            leading: const Icon(Icons.local_shipping_outlined, color: Color(0xFF10B981)),
                            title: Text('Đơn ${o.poNo} - ${o.customer}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                            subtitle: Text('Tổng: $count sản phẩm • Ngày tạo: ${o.createdAt.toLocal()}', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                            trailing: Text(o.status.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                          );
                        }
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
