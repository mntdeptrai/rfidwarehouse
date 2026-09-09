import 'package:flutter/material.dart';
import '../models/wms_models.dart';
import '../services/warehouse_repository.dart';
import '../theme/eye_care_theme.dart';
import 'warehouse_floor_plan_editor_dialog.dart';

/// Chế độ hoạt động của Sơ đồ mặt bằng kho
enum WarehouseFloorPlanMode {
  /// Chế độ Xuất Kho: Nhấn chọn kệ để lấy hàng xuất
  outbound,
  /// Chế độ Nhập Kho: Nhấn chọn kệ đích để cất hàng vào kho (Putaway)
  inbound,
  /// Chế độ Xem & Quản lý mặt bằng kho
  viewOnly,
}

/// Widget Sơ Đồ Mặt Bằng Kho 2D (Warehouse Floor Plan 2D)
/// Hiển thị cổng kho, lối đi chính xe nâng và các dãy kệ thực tế,
/// tích hợp chỉ dẫn đường đi trực quan cho người chở pallet / lái xe nâng.
class WarehouseFloorPlanWidget extends StatefulWidget {
  final WarehouseFloorPlanMode mode;
  final String? selectedLocationId;
  final ValueChanged<String?>? onLocationSelected;
  final VoidCallback? onLocationDataChanged;

  const WarehouseFloorPlanWidget({
    super.key,
    this.mode = WarehouseFloorPlanMode.outbound,
    this.selectedLocationId,
    this.onLocationSelected,
    this.onLocationDataChanged,
  });

  @override
  State<WarehouseFloorPlanWidget> createState() => _WarehouseFloorPlanWidgetState();
}

class _WarehouseFloorPlanWidgetState extends State<WarehouseFloorPlanWidget> {
  final WarehouseRepository _repo = WarehouseRepository();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onRepoChange);
  }

  @override
  void dispose() {
    _repo.removeListener(_onRepoChange);
    super.dispose();
  }

  void _onRepoChange() {
    if (mounted) setState(() {});
  }

  Location? _findSelectedLocation() {
    if (widget.selectedLocationId == null) return null;
    final clean = widget.selectedLocationId!.trim().toUpperCase();
    return _repo.locations.where((l) =>
        l.locationId.trim().toUpperCase() == clean ||
        l.locationCode.trim().toUpperCase() == clean
    ).firstOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final config = _repo.floorPlanConfig;
    final locations = _repo.locations;
    final selectedLoc = _findSelectedLocation();

    return Container(
      decoration: BoxDecoration(
        color: c.bgCardElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. THANH TIÊU ĐỀ & NÚT CẤU HÌNH SƠ ĐỒ KHO
          _buildHeaderBar(config, selectedLoc, c),

          // 2. THANH CHỈ DẪN LỘ TRÌNH XE NÂNG (NAVIGATION BANNER)
          _buildNavigationBreadcrumbBanner(config, selectedLoc, c),

          // 3. KHÔNG GIAN BẢN ĐỒ MẶT BẰNG 2D (CANVAS / AISLES & RACKS)
          _buildFloorPlanCanvas(config, locations, selectedLoc, c),
        ],
      ),
    );
  }

  // ==================== 1. THANH TIÊU ĐỀ ====================
  Widget _buildHeaderBar(WarehouseFloorPlanConfig config, Location? selectedLoc, EyeCareColors c) {
    String presetLabel;
    IconData presetIcon;
    switch (config.layoutType) {
      case WarehouseLayoutType.parallelAisles:
        presetLabel = '2 Dãy Song Song';
        presetIcon = Icons.view_column_rounded;
        break;
      case WarehouseLayoutType.uShape:
        presetLabel = 'Mặt Bằng Chữ U';
        presetIcon = Icons.u_turn_left_rounded;
        break;
      case WarehouseLayoutType.multiAisleGrid:
        presetLabel = 'Lưới Đa Dãy';
        presetIcon = Icons.grid_4x4_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
        border: Border(bottom: BorderSide(color: c.border)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 6,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // Title & Presets badge
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.map_rounded, size: 16, color: Color(0xFF10B981)),
              ),
              const SizedBox(width: 8),
              Text(
                'SƠ ĐỒ 10 VỊ TRÍ & MẶT BẰNG KHO: ${config.warehouseName.toUpperCase()}',
                style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(presetIcon, size: 12, color: const Color(0xFF10B981)),
                    const SizedBox(width: 4),
                    Text(presetLabel, style: const TextStyle(color: Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ],
          ),

          // Actions: Clear Filter + Customize Floor Plan Button
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selectedLoc != null) ...[
                InkWell(
                  onTap: () => widget.onLocationSelected?.call(null),
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.clear, size: 12, color: Color(0xFFEF4444)),
                        SizedBox(width: 4),
                        Text('Xem toàn kho (Bỏ lọc)', style: TextStyle(color: Color(0xFFEF4444), fontSize: 11, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF10B981),
                  side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                ),
                icon: const Icon(Icons.architecture, size: 14),
                label: const Text('📐 CẤU HÌNH SƠ ĐỒ KHO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () => WarehouseFloorPlanEditorDialog.show(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== 2. THANH CHỈ DẪN LỘ TRÌNH XE NÂNG ====================
  Widget _buildNavigationBreadcrumbBanner(WarehouseFloorPlanConfig config, Location? selectedLoc, EyeCareColors c) {
    if (selectedLoc == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: c.bgCard.withValues(alpha: 0.6),
          border: Border(bottom: BorderSide(color: c.border)),
        ),
        child: Row(
          children: [
            const Icon(Icons.touch_app_outlined, size: 15, color: Color(0xFF3B82F6)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '💡 Chạm vào kệ trên sơ đồ để xem lộ trình xe nâng di chuyển và lọc danh sách hàng hóa tương ứng',
                style: TextStyle(color: c.textSecondary, fontSize: 11.5),
              ),
            ),
          ],
        ),
      );
    }

    final isLeft = selectedLoc.aisleSide == 'LEFT';
    final isRight = selectedLoc.aisleSide == 'RIGHT';
    final turnText = isLeft ? 'RẼ TRÁI' : (isRight ? 'RẼ PHẢI' : 'CHẠY THẲNG ĐẾN CUỐI KHO');
    final turnIcon = isLeft ? Icons.turn_left_rounded : (isRight ? Icons.turn_right_rounded : Icons.straight_rounded);

    final isOutbound = widget.mode == WarehouseFloorPlanMode.outbound;
    final themeColor = isOutbound ? const Color(0xFFF59E0B) : const Color(0xFF10B981);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.12),
        border: Border(
          bottom: BorderSide(color: themeColor.withValues(alpha: 0.4), width: 1.2),
        ),
      ),
      child: Wrap(
        spacing: 12,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(color: themeColor, borderRadius: BorderRadius.circular(6)),
                child: const Icon(Icons.forklift, color: Colors.white, size: 15),
              ),
              const SizedBox(width: 8),
              Text(
                isOutbound ? 'LỘ TRÌNH LẤY HÀNG XUẤT:' : 'CHỈ DẪN XE PALLET VÀO KHO:',
                style: TextStyle(color: themeColor, fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),

          // Steps breadcrumb
          Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _buildStepBadge('1. ${config.entryGateName}', Icons.input_rounded, c),
              Icon(Icons.arrow_forward_rounded, size: 14, color: themeColor),
              _buildStepBadge('2. Đi thẳng theo Lối Chính', Icons.straight_rounded, c),
              Icon(Icons.arrow_forward_rounded, size: 14, color: themeColor),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: themeColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(turnIcon, size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      '3. $turnText VÀO ${selectedLoc.displayName}',
                      style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              if (isOutbound && !config.isSingleGate) ...[
                Icon(Icons.arrow_forward_rounded, size: 14, color: themeColor),
                _buildStepBadge('4. Chở ra ${config.exitGateName}', Icons.output_rounded, c),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStepBadge(String text, IconData icon, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: c.textSecondary),
          const SizedBox(width: 4),
          Text(text, style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ==================== 3. KHÔNG GIAN BẢN ĐỒ MẶT BẰNG 2D ====================
  Widget _buildFloorPlanCanvas(
    WarehouseFloorPlanConfig config,
    List<Location> locations,
    Location? selectedLoc,
    EyeCareColors c,
  ) {
    final leftRacks = locations.where((l) => l.aisleSide == 'LEFT').toList();
    final rightRacks = locations.where((l) => l.aisleSide == 'RIGHT').toList();
    final backRacks = locations.where((l) => l.aisleSide == 'BACK').toList();

    leftRacks.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    rightRacks.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    backRacks.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Enforce minimum width for visual floor plan layout
        final minW = 760.0;
        final needsHScroll = constraints.maxWidth < minW;

        Widget mapContent = Container(
          width: needsHScroll ? minW : constraints.maxWidth,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            children: [
              if (backRacks.isNotEmpty) ...[
                _buildBackRowRacks(backRacks, selectedLoc, c),
                const SizedBox(height: 8),
              ],

              // KHU VỰC 2 DÃY SONG SONG & LỐI ĐI XE NÂNG Ở GIỮA
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // DÃY KỆ BÊN TRÁI
                  Expanded(
                    flex: 4,
                    child: _buildAisleRackColumn(
                      title: 'DÃY KỆ BÊN TRÁI (LEFT AISLE)',
                      color: const Color(0xFF3B82F6),
                      racks: leftRacks,
                      selectedLoc: selectedLoc,
                      isLeft: true,
                      c: c,
                    ),
                  ),

                  const SizedBox(width: 8),

                  // LỐI ĐI CHÍNH XE NÂNG (CENTRAL FORKLIFT RUNWAY)
                  Expanded(
                    flex: 3,
                    child: _buildCentralForkliftCorridor(config, selectedLoc, c),
                  ),

                  const SizedBox(width: 8),

                  // DÃY KỆ BÊN PHẢI
                  Expanded(
                    flex: 4,
                    child: _buildAisleRackColumn(
                      title: 'DÃY KỆ BÊN PHẢI (RIGHT AISLE)',
                      color: const Color(0xFF10B981),
                      racks: rightRacks,
                      selectedLoc: selectedLoc,
                      isLeft: false,
                      c: c,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // CỔNG VÀO / CỔNG RA (GATES) Ở PHÍA TRƯỚC LỐI ĐI
              Row(
                children: [
                  Expanded(
                    child: _buildGateBar(
                      label: config.entryGateName,
                      isExit: false,
                      subtext: 'Bốc dỡ & xe nâng vào',
                      c: c,
                    ),
                  ),
                  if (!config.isSingleGate) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildGateBar(
                        label: config.exitGateName,
                        isExit: true,
                        subtext: 'Xe nhận hàng xuất',
                        c: c,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );

        if (needsHScroll) {
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: mapContent,
          );
        }
        return mapContent;
      },
    );
  }

  // Cổng kho (Gate)
  Widget _buildGateBar({
    required String label,
    required bool isExit,
    required String subtext,
    required EyeCareColors c,
  }) {
    final gateColor = isExit ? const Color(0xFFF59E0B) : const Color(0xFF10B981);
    final icon = isExit ? Icons.output_rounded : Icons.sensor_door_rounded;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: gateColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: gateColor.withValues(alpha: 0.4), width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: gateColor, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label.toUpperCase(),
              style: TextStyle(color: gateColor, fontSize: 11.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '• $subtext',
              style: TextStyle(color: c.textSecondary, fontSize: 10.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // Kệ dãy cuối kho (dành cho mô hình chữ U)
  Widget _buildBackRowRacks(List<Location> racks, Location? selectedLoc, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 6, bottom: 6),
            child: Text(
              '⬆ DÃY KỆ CUỐI KHO (BACK ROW)',
              style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: racks.map((loc) => SizedBox(
              width: 130,
              child: _buildRackCard(loc, selectedLoc, c),
            )).toList(),
          ),
        ],
      ),
    );
  }

  // Cột dãy kệ dọc theo lối đi (Left Aisle / Right Aisle)
  Widget _buildAisleRackColumn({
    required String title,
    required Color color,
    required List<Location> racks,
    required Location? selectedLoc,
    required bool isLeft,
    required EyeCareColors c,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(width: 3, height: 14, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (racks.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              alignment: Alignment.center,
              child: Text('Chưa có kệ ở dãy này', style: TextStyle(color: c.textSecondary, fontSize: 11)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 165),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: racks.length,
                separatorBuilder: (context, index) => const SizedBox(height: 6),
                itemBuilder: (context, index) {
                  final loc = racks[index];
                  return _buildRackCard(loc, selectedLoc, c);
                },
              ),
            ),
        ],
      ),
    );
  }

  // Lối đi chính xe nâng ở giữa kho (Forklift Corridor)
  Widget _buildCentralForkliftCorridor(
    WarehouseFloorPlanConfig config,
    Location? selectedLoc,
    EyeCareColors c,
  ) {
    final isSelected = selectedLoc != null;
    final isLeft = selectedLoc?.aisleSide == 'LEFT';
    final isRight = selectedLoc?.aisleSide == 'RIGHT';

    return Container(
      constraints: const BoxConstraints(minHeight: 165, maxHeight: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1E293B).withValues(alpha: 0.5), // Giả lập bề mặt đường xe nâng kho
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.6) : c.border,
          width: isSelected ? 1.5 : 1,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Directional Arrows indicating inward flow
          const Icon(Icons.arrow_downward_rounded, size: 20, color: Color(0xFFF59E0B)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.forklift, size: 14, color: Color(0xFFF59E0B)),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    config.mainAisleLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Middle Visual Runway markings
          Column(
            children: List.generate(4, (i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Container(
                width: 24,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            )),
          ),

          // If a rack is selected, show the dynamic turning arrow
          if (isSelected) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    isLeft ? Icons.arrow_back : (isRight ? Icons.arrow_forward : Icons.arrow_upward),
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    isLeft ? 'RẼ TRÁI ➜' : (isRight ? '➜ RẼ PHẢI' : 'ĐI THẲNG'),
                    style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 6),
          const Icon(Icons.arrow_downward_rounded, size: 20, color: Color(0xFFF59E0B)),
        ],
      ),
    );
  }

  // Thẻ hiển thị ô kệ (Rack Card)
  Widget _buildRackCard(Location loc, Location? selectedLoc, EyeCareColors c) {
    final isSelected = selectedLoc != null &&
        (selectedLoc.locationId == loc.locationId || selectedLoc.locationCode == loc.locationCode);

    final itemsAtLoc = _repo.getItemsAtLocation(loc);
    final itemCount = itemsAtLoc.length;
    final palletCount = _repo.getPalletCountForLocation(loc);

    Color statusColor;
    String statusText;
    switch (loc.status.toUpperCase()) {
      case 'AVAILABLE':
        statusColor = const Color(0xFF10B981);
        statusText = 'TRỐNG';
        break;
      case 'NEAR_FULL':
        statusColor = const Color(0xFFF59E0B);
        statusText = 'CÒN CHỖ';
        break;
      case 'FULL':
      default:
        statusColor = const Color(0xFFEF4444);
        statusText = 'ĐÃ ĐẦY';
        break;
    }

    final maxCap = loc.maxPalletCapacity > 0 ? loc.maxPalletCapacity : 50;
    final currentPl = palletCount > 0 ? palletCount : (itemCount > 0 ? (itemCount / 10).ceil() : 0);
    final fillRatio = (currentPl / maxCap).clamp(0.0, 1.0);

    return InkWell(
      onTap: () {
        if (isSelected) {
          widget.onLocationSelected?.call(null);
        } else {
          widget.onLocationSelected?.call(loc.locationCode);
        }
      },
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.15) : c.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981) : (itemCount > 0 ? c.border : c.border.withValues(alpha: 0.5)),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF10B981).withValues(alpha: 0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row: Rack Name + Status badge + Popup Menu
            Row(
              children: [
                Expanded(
                  child: Text(
                    loc.displayName,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF10B981) : c.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontSize: 9.5, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 4),
                _buildRackOptionsMenu(loc, c),
              ],
            ),

            const SizedBox(height: 4),
            Text(
              loc.displaySubtitle,
              style: TextStyle(color: c.textSecondary, fontSize: 10.5),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),

            const SizedBox(height: 6),

            // Sức chứa & Tiến độ chứa hàng
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '$currentPl/$maxCap Pallet',
                  style: TextStyle(color: c.textPrimary, fontSize: 10.5, fontWeight: FontWeight.w600),
                ),
                Text(
                  '$itemCount SP',
                  style: TextStyle(color: c.textSecondary, fontSize: 10.5),
                ),
              ],
            ),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                value: fillRatio,
                backgroundColor: c.bgDeep,
                valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRackOptionsMenu(Location loc, EyeCareColors c) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, size: 16, color: c.textSecondary),
      padding: EdgeInsets.zero,
      tooltip: 'Tùy chọn',
      color: c.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: c.border),
      ),
      onSelected: (val) async {
        if (val == 'AVAILABLE' || val == 'NEAR_FULL' || val == 'FULL') {
          await _repo.updateLocationStatus(loc.locationId, val);
          widget.onLocationDataChanged?.call();
          setState(() {});
        } else if (val == 'EDIT') {
          WarehouseFloorPlanEditorDialog.show(context);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'AVAILABLE',
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 16),
              SizedBox(width: 8),
              Text('Đặt trạng thái: CÒN TRỐNG'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'NEAR_FULL',
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFF59E0B), size: 16),
              SizedBox(width: 8),
              Text('Đặt trạng thái: CÒN CHỖ'),
            ],
          ),
        ),
        const PopupMenuItem(
          value: 'FULL',
          child: Row(
            children: [
              Icon(Icons.block, color: Color(0xFFEF4444), size: 16),
              SizedBox(width: 8),
              Text('Đặt trạng thái: ĐÃ ĐẦY'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'EDIT',
          child: Row(
            children: [
              Icon(Icons.edit, size: 16),
              SizedBox(width: 8),
              Text('Sửa sơ đồ mặt bằng kho...'),
            ],
          ),
        ),
      ],
    );
  }
}
