import 'dart:async';
import 'package:flutter/material.dart';
import '../models/wms_models.dart';
import '../services/uhf_service.dart';
import '../services/warehouse_repository.dart';
import '../theme/eye_care_theme.dart';
import '../widgets/hardware_status_appbar.dart';
import '../widgets/warehouse_floor_plan_widget.dart';

/// Màn hình Tìm Kiếm Vị Trí Hàng Hóa 2D & Điều Phối Lấy Hàng Theo FIFO (First In, First Out).
/// Hỗ trợ tìm kiếm theo Mã Hàng (Item ID / Serial / EPC) hoặc Mã SKU,
/// tự động vẽ bản đồ mặt bằng kho 2D và đánh dấu rõ ô kệ chứa hàng cần lấy trước nhất theo FIFO.
class FifoSearchScreen extends StatefulWidget {
  final String? initialQuery;
  final String? initialEpc;
  final String? initialSku;
  final String? initialItemId;
  final Item? initialItem;
  final Pallet? initialPallet;
  final LocateOrder? locateTask;

  const FifoSearchScreen({
    super.key,
    this.initialQuery,
    this.initialEpc,
    this.initialSku,
    this.initialItemId,
    this.initialItem,
    this.initialPallet,
    this.locateTask,
  });

  @override
  State<FifoSearchScreen> createState() => _FifoSearchScreenState();
}

class _FifoSearchScreenState extends State<FifoSearchScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  late final TextEditingController _searchCtrl;
  String? _selectedLocationId;
  StreamSubscription<String>? _barcodeSub;
  StreamSubscription<bool>? _triggerSub;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onStateUpdate);
    _repo.addListener(_onStateUpdate);

    // Xác định từ khóa tìm kiếm khởi đầu
    String initial = widget.initialQuery ?? '';
    if (initial.isEmpty && widget.initialSku != null) {
      initial = widget.initialSku!;
    } else if (initial.isEmpty && widget.initialItemId != null) {
      initial = widget.initialItemId!;
    } else if (initial.isEmpty && widget.initialItem != null) {
      initial = widget.initialItem!.sku.isNotEmpty ? widget.initialItem!.sku : widget.initialItem!.itemId;
    } else if (initial.isEmpty && widget.initialPallet != null) {
      initial = widget.initialPallet!.palletCode;
    } else if (initial.isEmpty && widget.locateTask != null) {
      initial = widget.locateTask!.targetSku ??
          widget.locateTask!.targetEpc ??
          widget.locateTask!.targetPalletCode ??
          '';
    } else if (initial.isEmpty && widget.initialEpc != null) {
      initial = widget.initialEpc!;
    }

    _searchCtrl = TextEditingController(text: initial);

    // Lắng nghe máy quét mã vạch / laser 2D trên PDA
    _barcodeSub = _uhf.onBarcodeRead.listen((barcode) {
      if (!mounted) return;
      final clean = barcode.trim();
      if (clean.isNotEmpty) {
        _searchCtrl.text = clean;
        setState(() {});
      }
    });

    // Lắng nghe bóp cò vật lý trên tay cầm PDA
    _triggerSub = _uhf.onTriggerStateChanged.listen((isPressed) {
      if (!mounted) return;
      if (isPressed) {
        // Cho phép người dùng bóp cò để quét mã
      }
    });
  }

  void _onStateUpdate() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _barcodeSub?.cancel();
    _triggerSub?.cancel();
    _searchCtrl.dispose();
    _repo.removeListener(_onStateUpdate);
    _eyeCare.removeListener(_onStateUpdate);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final query = _searchCtrl.text.trim().toLowerCase();

    final isSearching = query.isNotEmpty;

    // 1. Lọc danh sách hàng hóa theo từ khóa (Mã hàng, SKU, S/N, EPC, hoặc Tên SP)
    final allAvailableItems = _repo.items.where((i) => i.status != ItemStatus.out).toList();

    List<Item> matchingItems = [];
    if (isSearching) {
      matchingItems = allAvailableItems.where((it) {
        final itemId = it.itemId.toLowerCase();
        final sku = it.sku.toLowerCase();
        final name = it.productName.toLowerCase();
        final serial = it.serialNumber.toLowerCase();
        final epc = it.epc.toLowerCase();
        final loc = (it.locationId ?? '').toLowerCase();
        final pallet = (it.palletId ?? '').toLowerCase();
        return itemId.contains(query) ||
            sku.contains(query) ||
            name.contains(query) ||
            serial.contains(query) ||
            epc.contains(query) ||
            loc.contains(query) ||
            pallet.contains(query);
      }).toList();

      // 2. Sắp xếp danh sách hàng hóa theo nguyên tắc FIFO (Nhập kho trước nhất -> Cũ nhất lên đầu)
      matchingItems.sort((a, b) {
        final timeA = a.inboundTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final timeB = b.inboundTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final comp = timeA.compareTo(timeB);
        if (comp != 0) return comp;
        return a.itemId.compareTo(b.itemId);
      });
    }

    // 3. Xác định hàng cần lấy theo FIFO (Hàng nhập trước nhất) - CHỈ KHI ĐANG TÌM KIẾM
    final Item? fifoItem = isSearching && matchingItems.isNotEmpty ? matchingItems.first : null;
    final String? fifoLocationId = fifoItem?.locationId;

    // 4. Tập hợp danh sách các ô kệ chứa hàng khớp và số lượng từng ô
    final highlightLocationIds = <String>{};
    final matchingItemCounts = <String, int>{};
    if (isSearching) {
      for (final it in matchingItems) {
        if (it.locationId != null && it.locationId!.trim().isNotEmpty) {
          final locId = it.locationId!.trim();
          highlightLocationIds.add(locId);
          matchingItemCounts[locId] = (matchingItemCounts[locId] ?? 0) + 1;
        }
      }
    }

    // Lấy thông tin ô kệ FIFO
    Location? fifoLocation;
    if (fifoLocationId != null) {
      final clean = fifoLocationId.trim().toUpperCase();
      fifoLocation = _repo.locations.where((l) =>
          l.locationId.trim().toUpperCase() == clean ||
          l.locationCode.trim().toUpperCase() == clean).firstOrNull;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 960;

        return Scaffold(
          backgroundColor: c.bgDeep,
          appBar: isDesktop
              ? AppBar(
                  backgroundColor: c.bgCard,
                  elevation: 0,
                  titleSpacing: 16,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: c.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  title: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.map_rounded, color: Color(0xFFF59E0B), size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'TÌM KIẾM VỊ TRÍ HÀNG 2D (FIFO)',
                            style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            'Tra cứu mã hàng/SKU • Vẽ bản đồ 2D vị trí • Ưu tiên lấy hàng theo FIFO',
                            style: TextStyle(color: c.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : HardwareStatusAppBar(
                  title: 'TÌM VỊ TRÍ 2D (FIFO)',
                  showScanMode: false,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded, color: c.textPrimary, size: 20),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. THANH TÌM KIẾM THEO MÃ HÀNG & MÃ SKU
                  _buildSearchBar(c),

                  const SizedBox(height: 8),

                  // 2. CHIPS GỢI Ý SKU NHANH
                  _buildQuickSkuChips(allAvailableItems, c),

                  const SizedBox(height: 8),

                  // 3. THẺ THÔNG BÁO Ô CẦN LẤY THEO FIFO (HOẶC HƯỚNG DẪN KHI CHƯA TÌM)
                  if (!isSearching)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: c.bgCard,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.touch_app_outlined, size: 14, color: c.textSecondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Nhập mã hàng/SKU hoặc chạm gợi ý bên trên để định vị ô cần lấy theo FIFO',
                              style: TextStyle(color: c.textSecondary, fontSize: 10.5),
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (fifoItem != null)
                    _buildFifoSummaryBanner(fifoItem, fifoLocation, matchingItems.length, highlightLocationIds.length, c)
                  else
                    _buildEmptySearchCard(query, c),

                  const SizedBox(height: 10),

                  // 4. BẢN ĐỒ MẶT BẰNG KHO 2D VỚI Ô HIGHLIGHT THEO FIFO
                  WarehouseFloorPlanWidget(
                    mode: WarehouseFloorPlanMode.fifoSearch,
                    selectedLocationId: _selectedLocationId ?? fifoLocationId,
                    fifoPickLocationId: fifoLocationId,
                    fifoItem: fifoItem,
                    highlightLocationIds: highlightLocationIds,
                    matchingItemCounts: matchingItemCounts,
                    onLocationSelected: (locCode) {
                      setState(() {
                        _selectedLocationId = locCode;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ==================== THANH TÌM KIẾM ====================
  Widget _buildSearchBar(EyeCareColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.search_rounded, color: Color(0xFFF59E0B), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                hintText: 'Nhập mã hàng, mã SKU, S/N hoặc quét mã barcode/RFID...',
                hintStyle: TextStyle(color: c.textSecondary, fontSize: 12.5),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          if (_searchCtrl.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.cancel, color: c.textSecondary, size: 18),
              onPressed: () {
                _searchCtrl.clear();
                setState(() {
                  _selectedLocationId = null;
                });
              },
            ),
        ],
      ),
    );
  }

  // ==================== GỢI Ý SKU ====================
  Widget _buildQuickSkuChips(List<Item> items, EyeCareColors c) {
    final skus = <String>{};
    for (final it in items) {
      if (it.sku.trim().isNotEmpty) skus.add(it.sku.trim());
    }
    if (skus.isEmpty) return const SizedBox.shrink();

    final skuList = skus.toList()..sort();
    final currentQ = _searchCtrl.text.trim().toLowerCase();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          Text(
            'Gợi ý SKU: ',
            style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          ...skuList.take(8).map((sku) {
            final isSelected = currentQ == sku.toLowerCase();
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                onTap: () {
                  _searchCtrl.text = sku;
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected ? const Color(0xFFF59E0B) : c.bgCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? const Color(0xFFF59E0B) : c.border,
                    ),
                  ),
                  child: Text(
                    sku,
                    style: TextStyle(
                      color: isSelected ? Colors.white : c.textPrimary,
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ==================== THẺ THÔNG BÁO FIFO (TỐI GIẢN) ====================
  Widget _buildFifoSummaryBanner(
    Item fifoItem,
    Location? fifoLocation,
    int totalCount,
    int rackCount,
    EyeCareColors c,
  ) {
    final locationName = fifoLocation?.displayName ?? fifoItem.locationId ?? 'Chưa xếp kệ';
    final locationSub = fifoLocation?.displaySubtitle ?? '';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star_rounded, color: Colors.white, size: 12),
                    SizedBox(width: 3),
                    Text(
                      '⭐ CẦN LẤY THEO FIFO',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                'Tồn: $totalCount SP',
                style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Icon(Icons.place_rounded, size: 14, color: Color(0xFFF59E0B)),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Ô KỆ: $locationName ${locationSub.isNotEmpty ? "($locationSub)" : ""}',
                  style: const TextStyle(
                    color: Color(0xFFF59E0B),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== TRẠNG THÁI KHÔNG TÌM THẤY ====================
  Widget _buildEmptySearchCard(String query, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Icon(Icons.search_off_rounded, color: c.textSecondary, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Không tìm thấy mặt hàng khớp với "$query"',
                  style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  'Vui lòng thử tìm với mã hàng, mã SKU khác hoặc quét lại mã vạch/RFID.',
                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


}
