import 'package:flutter/material.dart';
import '../models/wms_models.dart';
import '../services/warehouse_repository.dart';
import '../theme/eye_care_theme.dart';

/// Hộp thoại cấu hình sơ đồ mặt bằng kho thực tế cho khách hàng
class WarehouseFloorPlanEditorDialog extends StatefulWidget {
  const WarehouseFloorPlanEditorDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const WarehouseFloorPlanEditorDialog(),
    );
  }

  @override
  State<WarehouseFloorPlanEditorDialog> createState() => _WarehouseFloorPlanEditorDialogState();
}

class _WarehouseFloorPlanEditorDialogState extends State<WarehouseFloorPlanEditorDialog> with SingleTickerProviderStateMixin {
  final WarehouseRepository _repo = WarehouseRepository();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  late TabController _tabController;
  late WarehouseFloorPlanConfig _config;

  final TextEditingController _warehouseNameCtrl = TextEditingController();
  final TextEditingController _entryGateCtrl = TextEditingController();
  final TextEditingController _exitGateCtrl = TextEditingController();
  final TextEditingController _aisleLabelCtrl = TextEditingController();

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _config = _repo.floorPlanConfig;

    _warehouseNameCtrl.text = _config.warehouseName;
    _entryGateCtrl.text = _config.entryGateName;
    _exitGateCtrl.text = _config.exitGateName;
    _aisleLabelCtrl.text = _config.mainAisleLabel;
  }

  @override
  void dispose() {
    _tabController.dispose();
    _warehouseNameCtrl.dispose();
    _entryGateCtrl.dispose();
    _exitGateCtrl.dispose();
    _aisleLabelCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveConfig() async {
    setState(() => _isSaving = true);
    try {
      final updatedConfig = _config.copyWith(
        warehouseName: _warehouseNameCtrl.text.trim().isEmpty ? 'KHO HÀNG TRUNG TÂM' : _warehouseNameCtrl.text.trim(),
        entryGateName: _entryGateCtrl.text.trim().isEmpty ? 'CỔNG NHẬP (GATE IN)' : _entryGateCtrl.text.trim(),
        exitGateName: _exitGateCtrl.text.trim().isEmpty ? 'CỔNG XUẤT (GATE OUT)' : _exitGateCtrl.text.trim(),
        mainAisleLabel: _aisleLabelCtrl.text.trim().isEmpty ? 'LỐI ĐI CHÍNH XE NÂNG (FORKLIFT AISLE)' : _aisleLabelCtrl.text.trim(),
      );
      await _repo.saveWarehouseLayoutConfig(updatedConfig);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi khi lưu sơ đồ: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final media = MediaQuery.of(context);
    final dialogWidth = (media.size.width * 0.82).clamp(550.0, 960.0);
    final dialogHeight = (media.size.height * 0.85).clamp(520.0, 750.0);

    return Dialog(
      backgroundColor: c.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.6), width: 1.5),
      ),
      child: Container(
        width: dialogWidth,
        height: dialogHeight,
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.architecture_rounded, color: Color(0xFF10B981), size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '📐 CẤU HÌNH SƠ ĐỒ MẶT BẰNG KHO THỰC TẾ',
                        style: TextStyle(color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Tùy biến theo đúng kho của khách hàng: Cổng vào/ra, lối đi xe nâng và vị trí các dãy kệ',
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: c.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Tab Bar
            Container(
              decoration: BoxDecoration(
                color: c.bgDeep,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: TabBar(
                controller: _tabController,
                indicatorColor: const Color(0xFF10B981),
                indicatorWeight: 3,
                labelColor: const Color(0xFF10B981),
                unselectedLabelColor: c.textSecondary,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                tabs: const [
                  Tab(icon: Icon(Icons.dashboard_customize_outlined, size: 18), text: '1. MẪU MẶT BẰNG KHO'),
                  Tab(icon: Icon(Icons.meeting_room_outlined, size: 18), text: '2. CỔNG VÀO / RA & LỐI XE'),
                  Tab(icon: Icon(Icons.grid_view_rounded, size: 18), text: '3. QUẢN LÝ CÁC DÃY KỆ'),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tab Content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildTabPresets(c),
                  _buildTabGatesAndAisle(c),
                  _buildTabRacks(c),
                ],
              ),
            ),

            const SizedBox(height: 14),
            // Bottom Action Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Đặt lại 10 kệ mẫu mặc định'),
                  style: TextButton.styleFrom(foregroundColor: c.textSecondary),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: c.bgCard,
                        title: Text('Xác nhận đặt lại?', style: TextStyle(color: c.textPrimary)),
                        content: Text('Hệ thống sẽ sắp xếp lại 10 kệ A-01..A-05 (Dãy Trái) và B-01..B-05 (Dãy Phải).', style: TextStyle(color: c.textSecondary)),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('HỦY')),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('XÁC NHẬN'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await _repo.resetLayoutToPreset(_config.layoutType);
                      setState(() {});
                    }
                  },
                ),
                Row(
                  children: [
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.textPrimary,
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('ĐÓNG'),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save, size: 18),
                      label: const Text('LƯU SƠ ĐỒ KHO', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _isSaving ? null : _saveConfig,
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== TAB 1: CÁC MẪU SƠ ĐỒ MẶT BẰNG ====================
  Widget _buildTabPresets(EyeCareColors c) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Chọn mô hình mặt bằng kho gần giống nhất với thực tế:', style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildPresetCard(
            type: WarehouseLayoutType.parallelAisles,
            title: 'Mô hình 1: Hai Dãy Kệ Song Song (Lối đi chính ở giữa)',
            description: 'Phổ biến nhất tại các kho hàng. Xe nâng đi thẳng vào cổng ở giữa, hai bên là Dãy Kệ Trái (Dãy A) và Dãy Kệ Phải (Dãy B). Tài xế chỉ cần chạy thẳng và rẽ trái/phải.',
            icon: Icons.view_column_rounded,
            tag: 'Khuyên Dùng Cho Xe Nâng',
            c: c,
          ),
          const SizedBox(height: 12),
          _buildPresetCard(
            type: WarehouseLayoutType.uShape,
            title: 'Mô hình 2: Mặt Bằng Chữ U (U-Shape)',
            description: 'Lối đi hình chữ U hoặc có kệ ở dãy cuối kho. Bao gồm Dãy Trái, Kệ Cuối Kho (Back Row), và Dãy Phải. Rất phù hợp kho vuông hoặc kho có khu vực quay đầu xe.',
            icon: Icons.u_turn_left_rounded,
            tag: 'Kho Khép Kín',
            c: c,
          ),
          const SizedBox(height: 12),
          _buildPresetCard(
            type: WarehouseLayoutType.multiAisleGrid,
            title: 'Mô hình 3: Lưới Phân Khu Đa Dãy (Grid Matrix)',
            description: 'Phân chia kho thành các khu vực rộng (Khu A, Khu B, Khu C, Khu D...) với nhiều lối đi đan xen. Phù hợp kho phân phối lớn hoặc trung tâm logistics.',
            icon: Icons.grid_4x4_rounded,
            tag: 'Kho Đa Khu Vực',
            c: c,
          ),
        ],
      ),
    );
  }

  Widget _buildPresetCard({
    required WarehouseLayoutType type,
    required String title,
    required String description,
    required IconData icon,
    required String tag,
    required EyeCareColors c,
  }) {
    final isSelected = _config.layoutType == type;
    return InkWell(
      onTap: () {
        setState(() {
          _config = _config.copyWith(layoutType: type);
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.1) : c.bgCardElevated,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF10B981) : c.border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF10B981) : c.bgDeep,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: isSelected ? Colors.white : c.textSecondary, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF10B981) : c.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.2) : c.bgDeep,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(
                            color: isSelected ? const Color(0xFF10B981) : c.textSecondary,
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(description, style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(
              isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: isSelected ? const Color(0xFF10B981) : c.textSecondary,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  // ==================== TAB 2: CẤU HÌNH CỔNG VÀO / RA & LỐI XE NÂNG ====================
  Widget _buildTabGatesAndAisle(EyeCareColors c) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Thông tin Định Danh Kho & Cổng Di Chuyển:', style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          // Tên phân xưởng kho
          _buildTextField(
            label: 'Tên Kho Hàng / Khách Hàng',
            hint: 'VD: Kho Tổng Logistics Miền Nam, Kho Phụ Tùng...',
            icon: Icons.warehouse_rounded,
            controller: _warehouseNameCtrl,
            c: c,
          ),
          const SizedBox(height: 14),

          // Chế độ Cổng: Chung 1 cổng hay 2 cổng riêng biệt
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.bgCardElevated,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border),
            ),
            child: Row(
              children: [
                const Icon(Icons.door_sliding_outlined, color: Color(0xFF10B981), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Thiết Kế Cổng Ra Vào', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                      Text(
                        _config.isSingleGate
                            ? 'Dùng chung 1 Cổng Chính vừa làm Cổng Nhập vừa làm Cổng Xuất'
                            : 'Có 2 Cổng riêng biệt: Cổng Nhập xe tải ở đầu vào và Cổng Xuất xe ở đầu ra',
                        style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: !_config.isSingleGate,
                  activeTrackColor: const Color(0xFF10B981),
                  onChanged: (val) {
                    setState(() {
                      _config = _config.copyWith(isSingleGate: !val);
                    });
                  },
                ),
                Text(!_config.isSingleGate ? '2 Cổng Riêng' : '1 Cổng Chung', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Tên Cổng Nhập
          _buildTextField(
            label: 'Tên Cổng Vào / Cổng Nhập Hàng (Gate In)',
            hint: 'VD: CỔNG NHẬP 01, CỬA NHẬP SỐ 1...',
            icon: Icons.input_rounded,
            controller: _entryGateCtrl,
            c: c,
          ),
          const SizedBox(height: 14),

          // Tên Cổng Xuất
          if (!_config.isSingleGate) ...[
            _buildTextField(
              label: 'Tên Cổng Ra / Cổng Xuất Hàng (Gate Out)',
              hint: 'VD: CỔNG XUẤT 01, CỬA XUẤT HÀNG...',
              icon: Icons.output_rounded,
              controller: _exitGateCtrl,
              c: c,
            ),
            const SizedBox(height: 14),
          ],

          // Tên Lối Đi Chính
          _buildTextField(
            label: 'Tên Lối Đi Chính Cho Xe Nâng (Forklift Aisle)',
            hint: 'VD: LỐI ĐI TRUNG TÂM XE NÂNG (RỘNG 3.5M)...',
            icon: Icons.alt_route_rounded,
            controller: _aisleLabelCtrl,
            c: c,
          ),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required String hint,
    required IconData icon,
    required TextEditingController controller,
    required EyeCareColors c,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: TextStyle(color: c.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            prefixIcon: Icon(icon, color: const Color(0xFF10B981), size: 18),
            hintText: hint,
            hintStyle: TextStyle(color: c.textSecondary.withValues(alpha: 0.6), fontSize: 12),
            filled: true,
            fillColor: c.bgDeep,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF10B981))),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  // ==================== TAB 3: QUẢN LÝ DANH SÁCH Ô KỆ ====================
  Widget _buildTabRacks(EyeCareColors c) {
    final locations = _repo.locations;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Danh sách các ô kệ lưu hàng (${locations.length} kệ):',
              style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('THÊM KỆ MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
              onPressed: () => _showAddOrEditRackDialog(null),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: c.bgDeep,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border),
            ),
            child: locations.isEmpty
                ? Center(
                    child: Text('Chưa có kệ nào. Hãy bấm "Thêm kệ mới" hoặc Đặt lại 10 kệ mẫu.', style: TextStyle(color: c.textSecondary)),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(8),
                    itemCount: locations.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final loc = locations[index];
                      return _buildRackRowItem(loc, c);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildRackRowItem(Location loc, EyeCareColors c) {
    final sideColor = loc.aisleSide == 'LEFT'
        ? const Color(0xFF3B82F6)
        : loc.aisleSide == 'RIGHT'
            ? const Color(0xFF10B981)
            : const Color(0xFFF59E0B);
    final sideLabel = loc.aisleSide == 'LEFT'
        ? 'Dãy Trái'
        : loc.aisleSide == 'RIGHT'
            ? 'Dãy Phải'
            : 'Cuối Kho';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: sideColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: sideColor.withValues(alpha: 0.4)),
            ),
            child: Text(
              sideLabel,
              style: TextStyle(color: sideColor, fontSize: 11, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.displayName,
                  style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                ),
                Text(
                  '${loc.displaySubtitle} • Sức chứa: ${loc.maxPalletCapacity} pallet • Thứ tự: #${loc.sortOrder}',
                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: Color(0xFF10B981)),
            tooltip: 'Sửa thông tin kệ',
            onPressed: () => _showAddOrEditRackDialog(loc),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18, color: Color(0xFFEF4444)),
            tooltip: 'Xóa kệ này',
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: c.bgCard,
                  title: Text('Xóa kệ ${loc.displayName}?', style: TextStyle(color: c.textPrimary)),
                  content: Text('Bạn có chắc muốn xóa kệ này khỏi sơ đồ mặt bằng kho?', style: TextStyle(color: c.textSecondary)),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('HỦY')),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('XÓA'),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await _repo.deleteCustomLocation(loc.locationId);
                setState(() {});
              }
            },
          ),
        ],
      ),
    );
  }

  void _showAddOrEditRackDialog(Location? existing) {
    final c = _eyeCare.colors;
    final isEdit = existing != null;

    final codeCtrl = TextEditingController(text: existing?.locationCode ?? 'C-01');
    final shelfCtrl = TextEditingController(text: existing?.shelf ?? 'Kệ 01');
    final zoneCtrl = TextEditingController(text: existing?.zone ?? 'Khu C');
    final levelCtrl = TextEditingController(text: existing?.level ?? 'Tầng 1');
    final capCtrl = TextEditingController(text: (existing?.maxPalletCapacity ?? 50).toString());
    final orderCtrl = TextEditingController(text: (existing?.sortOrder ?? (_repo.locations.length + 1)).toString());
    String selectedSide = existing?.aisleSide ?? 'LEFT';

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setModalState) => AlertDialog(
          backgroundColor: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: c.border)),
          title: Text(isEdit ? 'Sửa Kệ: ${existing.displayName}' : 'Thêm Kệ Mới Vào Sơ Đồ', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: codeCtrl,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Mã Vị Trí / Kệ',
                            labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: shelfCtrl,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Tên Kệ Hiển Thị',
                            labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: zoneCtrl,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Khu Vực (Zone)',
                            labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: levelCtrl,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Tầng Lưu',
                            labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Vị trí trên lối đi
                  DropdownButtonFormField<String>(
                    initialValue: selectedSide,
                    dropdownColor: c.bgCard,
                    style: TextStyle(color: c.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      labelText: 'Bố Trí Trên Sơ Đồ Mặt Bằng',
                      labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'LEFT', child: Text('⬅ Dãy Trái Lối Đi')),
                      DropdownMenuItem(value: 'RIGHT', child: Text('➡ Dãy Phải Lối Đi')),
                      DropdownMenuItem(value: 'BACK', child: Text('⬆ Hàng Cuối Kho')),
                    ],
                    onChanged: (val) {
                      if (val != null) setModalState(() => selectedSide = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: capCtrl,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Sức Chứa (Pallet)',
                            labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: orderCtrl,
                          keyboardType: TextInputType.number,
                          style: TextStyle(color: c.textPrimary, fontSize: 13),
                          decoration: InputDecoration(
                            labelText: 'Thứ Tự Dọc Lối (#)',
                            labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              onPressed: () async {
                final code = codeCtrl.text.trim().toUpperCase();
                final shelf = shelfCtrl.text.trim();
                final zone = zoneCtrl.text.trim();
                final level = levelCtrl.text.trim();
                final cap = int.tryParse(capCtrl.text.trim()) ?? 50;
                final order = int.tryParse(orderCtrl.text.trim()) ?? 0;

                if (code.isEmpty) return;

                if (isEdit) {
                  await _repo.updateLocationDetails(
                    locationId: existing.locationId,
                    locationCode: code,
                    zone: zone,
                    shelf: shelf,
                    level: level,
                    maxCapacity: cap,
                    aisleSide: selectedSide,
                    sortOrder: order,
                  );
                } else {
                  final newLoc = Location(
                    locationId: 'LOC-$code',
                    locationCode: code,
                    zone: zone.isEmpty ? 'Khu A' : zone,
                    shelf: shelf.isEmpty ? 'Kệ $code' : shelf,
                    level: level.isEmpty ? 'Tầng 1' : level,
                    maxPalletCapacity: cap,
                    currentPallets: 0,
                    status: 'AVAILABLE',
                    aisleSide: selectedSide,
                    sortOrder: order,
                  );
                  await _repo.addCustomLocation(newLoc);
                }

                if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
                setState(() {});
              },
              child: Text(isEdit ? 'CẬP NHẬT' : 'THÊM KỆ', style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }
}
