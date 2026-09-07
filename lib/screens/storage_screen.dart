import 'package:flutter/material.dart';
import '../models/wms_models.dart';
import '../services/warehouse_repository.dart';
import '../services/uhf_service.dart';
import '../widgets/hardware_status_appbar.dart';
import '../widgets/pda_location_barcode_card.dart';
import '../theme/eye_care_theme.dart';

class StorageScreen extends StatefulWidget {
  const StorageScreen({super.key});

  @override
  State<StorageScreen> createState() => _StorageScreenState();
}

class _StorageScreenState extends State<StorageScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final WarehouseRepository _repo = WarehouseRepository();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _eyeCare.addListener(_onThemeChanged);
    _repo.addListener(_onRepoChanged);
    UhfService().setScanMode(PdaScanMode.rfid);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _repo.removeListener(_onRepoChanged);
    _eyeCare.removeListener(_onThemeChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _onRepoChanged() {
    if (mounted) setState(() {});
  }

  // --- DIALOGS ---

  void _showAddProductDialog() {
    final c = _eyeCare.colors;
    final skuController = TextEditingController();
    final nameController = TextEditingController();
    final unitController = TextEditingController();
    final categoryController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
        title: Row(
          children: [
            Icon(Icons.add_box_outlined, color: c.rfidCyan, size: 22),
            const SizedBox(width: 8),
            Text('Thêm Sản Phẩm SKU Mới', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: skuController,
                decoration: InputDecoration(
                  labelText: 'Mã SKU',
                  hintText: 'Ví dụ: SKU-001',
                  labelStyle: TextStyle(color: c.textSecondary),
                  filled: true,
                  fillColor: c.bgDeep,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                ),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: 'Tên sản phẩm',
                  hintText: 'Tên sản phẩm...',
                  labelStyle: TextStyle(color: c.textSecondary),
                  filled: true,
                  fillColor: c.bgDeep,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                ),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: categoryController,
                decoration: InputDecoration(
                  labelText: 'Danh mục / Ngành hàng',
                  hintText: 'Điện tử, May mặc...',
                  labelStyle: TextStyle(color: c.textSecondary),
                  filled: true,
                  fillColor: c.bgDeep,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                ),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: unitController,
                decoration: InputDecoration(
                  labelText: 'Đơn vị tính (ĐVT)',
                  hintText: 'Cái, Hộp, Thùng...',
                  labelStyle: TextStyle(color: c.textSecondary),
                  filled: true,
                  fillColor: c.bgDeep,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                ),
                style: TextStyle(color: c.textPrimary),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('HỦY', style: TextStyle(color: c.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: c.rfidCyan,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              final sku = skuController.text.trim().toUpperCase();
              final name = nameController.text.trim();
              if (sku.isEmpty || name.isEmpty) return;

              final newProd = Product(
                productId: 'PROD-${DateTime.now().millisecondsSinceEpoch}',
                sku: sku,
                productName: name,
                unit: unitController.text.trim().isNotEmpty ? unitController.text.trim() : 'Cái',
                category: categoryController.text.trim().isNotEmpty ? categoryController.text.trim() : 'Mặc định',
              );

              await _repo.addProduct(newProd);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('LƯU SẢN PHẨM', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddPalletDialog() {
    final c = _eyeCare.colors;
    final codeController = TextEditingController();
    String? selectedLocationId = _repo.locations.isNotEmpty ? _repo.locations.first.locationId : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          backgroundColor: c.bgCard,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
          title: Row(
            children: [
              Icon(Icons.pallet, color: const Color(0xFF10B981), size: 24),
              const SizedBox(width: 8),
              Text('Tạo Pallet Mới', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: codeController,
                  decoration: InputDecoration(
                    labelText: 'Tên / Mã Pallet (Pallet Code)',
                    hintText: 'Ví dụ: PL-006, PAL-A01...',
                    labelStyle: TextStyle(color: c.textSecondary),
                    filled: true,
                    fillColor: c.bgDeep,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                  ),
                  style: TextStyle(color: c.textPrimary),
                ),
                const SizedBox(height: 14),
                Text('Vị trí kệ kho khởi tạo:', style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.bgDeep,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: selectedLocationId,
                      isExpanded: true,
                      dropdownColor: c.bgCard,
                      hint: Text('Chưa gán vị trí (None)', style: TextStyle(color: c.textMuted)),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Chưa xếp kệ (Chưa có vị trí)', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                        ),
                        ..._repo.locations.map((loc) => DropdownMenuItem<String?>(
                          value: loc.locationId,
                          child: Text('${loc.locationCode} (Khu ${loc.zone} - Kệ ${loc.shelf})', style: TextStyle(color: c.textPrimary, fontSize: 13)),
                        )),
                      ],
                      onChanged: (val) => setDlgState(() => selectedLocationId = val),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('HỦY', style: TextStyle(color: c.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                final code = codeController.text.trim().toUpperCase();
                if (code.isEmpty) return;

                _repo.createOrAssignPallet(
                  palletCode: code,
                  locationId: selectedLocationId,
                  newItems: [],
                );

                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: const Color(0xFF10B981),
                    content: Text('✓ Đã tạo Pallet $code thành công!'),
                  ),
                );
              },
              child: const Text('TẠO PALLET', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _showMovePalletDialog(Pallet pallet) {
    if (_repo.locations.isEmpty) return;
    String selectedLocId = pallet.locationId ?? _repo.locations.first.locationId;
    final c = _eyeCare.colors;
    final palletItems = _repo.items.where((it) => it.palletId == pallet.palletId).toList();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: c.bgCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
              title: Row(
                children: [
                  Icon(Icons.drive_file_move_outlined, color: c.rfidCyan, size: 22),
                  const SizedBox(width: 8),
                  Text('Di chuyển Pallet ${pallet.palletCode}', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: c.bgDeep, borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Mã RFID: ${pallet.palletId}', style: TextStyle(color: c.rfidCyan, fontSize: 11, fontFamily: 'monospace')),
                        Text('${palletItems.length} Sản phẩm', style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('Chọn vị trí kệ kho đích:', style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  PdaLocationBarcodeCard(
                    selectedLocationId: selectedLocId,
                    onLocationChanged: (loc) {
                      setDialogState(() => selectedLocId = loc.locationId);
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('HỦY', style: TextStyle(color: c.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.rfidCyan,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    _repo.movePallet(
                      palletId: pallet.palletId,
                      newLocationId: selectedLocId,
                      performedBy: 'Thủ kho',
                    );
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        backgroundColor: const Color(0xFF10B981),
                        content: Text('✓ Đã chuyển Pallet ${pallet.palletCode} đến vị trí $selectedLocId thành công!'),
                      ),
                    );
                  },
                  child: const Text('XÁC NHẬN DI CHUYỂN', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// CHỨC NĂNG NHẬP GỘP 2 HÀNG TRÊN 2 PALLET LẠI VỚI NHAU (PALLET CONSOLIDATION)
  void _showMergePalletsDialog([Pallet? initialSourcePallet]) {
    final c = _eyeCare.colors;
    final allPallets = _repo.pallets;

    // Pallets có hàng (để làm nguồn)
    final palletsWithItems = allPallets.where((p) {
      final cnt = _repo.items.where((it) => it.palletId == p.palletId).length;
      return cnt > 0;
    }).toList();

    if (palletsWithItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: c.warningAmber,
          content: const Text('Hiện không có Pallet nào chứa hàng hóa để thực hiện gộp!'),
        ),
      );
      return;
    }

    if (allPallets.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: c.warningAmber,
          content: const Text('Cần ít nhất 2 Pallet trong hệ thống để thực hiện chức năng nhập gộp hàng!'),
        ),
      );
      return;
    }

    String selectedSourceId = (initialSourcePallet != null && palletsWithItems.any((p) => p.palletId == initialSourcePallet.palletId))
        ? initialSourcePallet.palletId
        : palletsWithItems.first.palletId;

    // Chọn pallet đích mặc định (khác pallet nguồn)
    final availableTargets = allPallets.where((p) => p.palletId != selectedSourceId).toList();
    String selectedTargetId = availableTargets.first.palletId;
    bool deleteSourcePallet = false;
    bool isProcessing = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final sourcePal = allPallets.firstWhere((p) => p.palletId == selectedSourceId);
          final targetPal = allPallets.firstWhere((p) => p.palletId == selectedTargetId);

          final sourceItems = _repo.items.where((it) => it.palletId == sourcePal.palletId).toList();
          final targetItems = _repo.items.where((it) => it.palletId == targetPal.palletId).toList();
          final totalAfterMerge = sourceItems.length + targetItems.length;

          final targetLoc = _repo.locations.where((l) => l.locationId == targetPal.locationId).firstOrNull;
          final targetLocDisplay = targetLoc?.locationCode ?? (targetPal.locationId ?? 'Chưa có kệ');

          return AlertDialog(
            backgroundColor: c.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.call_merge, color: Color(0xFF3B82F6), size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nhập Gộp Hàng 2 Pallet', style: TextStyle(color: c.textPrimary, fontSize: 17, fontWeight: FontWeight.bold)),
                      Text('Gom toàn bộ sản phẩm từ Pallet nguồn sang Pallet đích', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                    ],
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Flow card: Source -> Target
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: c.bgDeep,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border),
                      ),
                      child: Row(
                        children: [
                          // Pallet nguồn box
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text('PALLET NGUỒN (CHUYỂN ĐI)', style: TextStyle(color: const Color(0xFFF59E0B), fontSize: 10.5, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(sourcePal.palletCode, style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                                Text('${sourceItems.length} Sản phẩm', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                              ],
                            ),
                          ),
                          // Arrow
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: c.rfidCyan.withValues(alpha: 0.15),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.arrow_forward, color: c.rfidCyan, size: 20),
                          ),
                          // Pallet đích box
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text('PALLET ĐÍCH (GỘP VÀO)', style: TextStyle(color: const Color(0xFF10B981), fontSize: 10.5, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Text(targetPal.palletCode, style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                                Text('${targetItems.length} + ${sourceItems.length} = $totalAfterMerge SP', style: TextStyle(color: const Color(0xFF10B981), fontSize: 11.5, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Chọn Pallet Nguồn Dropdown
                    Text('1. Chọn Pallet Nguồn (Có hàng cần gộp):', style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.bgDeep,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.5)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedSourceId,
                          isExpanded: true,
                          dropdownColor: c.bgCard,
                          items: palletsWithItems.map((p) {
                            final cnt = _repo.items.where((it) => it.palletId == p.palletId).length;
                            final loc = _repo.locations.where((l) => l.locationId == p.locationId).firstOrNull?.locationCode ?? 'Chưa kệ';
                            return DropdownMenuItem<String>(
                              value: p.palletId,
                              child: Text('${p.palletCode} (Đang có $cnt SP • Kệ: $loc)', style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                selectedSourceId = val;
                                if (selectedTargetId == val) {
                                  final newT = allPallets.firstWhere((p) => p.palletId != val);
                                  selectedTargetId = newT.palletId;
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Chọn Pallet Đích Dropdown
                    Text('2. Chọn Pallet Đích (Nhận toàn bộ hàng):', style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.bgDeep,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedTargetId,
                          isExpanded: true,
                          dropdownColor: c.bgCard,
                          items: allPallets.where((p) => p.palletId != selectedSourceId).map((p) {
                            final cnt = _repo.items.where((it) => it.palletId == p.palletId).length;
                            final loc = _repo.locations.where((l) => l.locationId == p.locationId).firstOrNull?.locationCode ?? 'Chưa kệ';
                            return DropdownMenuItem<String>(
                              value: p.palletId,
                              child: Text('${p.palletCode} (Hiện có $cnt SP • Kệ: $loc)', style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) setModalState(() => selectedTargetId = val);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Danh sách mặt hàng chuyển đi Preview
                    Text('3. Danh sách hàng hóa sẽ chuyển sang ${targetPal.palletCode}:', style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 140),
                      decoration: BoxDecoration(
                        color: c.bgDeep,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.border),
                      ),
                      child: sourceItems.isEmpty
                          ? Center(child: Text('Không có mặt hàng nào', style: TextStyle(color: c.textMuted, fontSize: 12)))
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.all(8),
                              itemCount: sourceItems.length,
                              separatorBuilder: (_, _) => Divider(color: c.border, height: 8),
                              itemBuilder: (context, idx) {
                                final item = sourceItems[idx];
                                return Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: BoxDecoration(color: c.rfidCyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                                      child: Text('${idx + 1}', style: TextStyle(color: c.rfidCyan, fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(item.productName, style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                                          Text('SKU: ${item.sku} • EPC: ${item.epc}', style: TextStyle(color: c.textMuted, fontSize: 10.5, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
                                        ],
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    const SizedBox(height: 12),

                    // Thông báo vị trí mới
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline, color: Color(0xFF10B981), size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sau khi gộp, toàn bộ hàng hóa sẽ tự động nhận vị trí kệ kho: $targetLocDisplay theo Pallet đích ${targetPal.palletCode}.',
                              style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Tùy chọn xóa Pallet nguồn
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: deleteSourcePallet,
                      activeColor: c.rfidCyan,
                      title: Text('Xóa hoàn toàn Pallet nguồn (${sourcePal.palletCode}) sau khi gộp', style: TextStyle(color: c.textPrimary, fontSize: 12)),
                      subtitle: Text(
                        deleteSourcePallet
                            ? 'Pallet ${sourcePal.palletCode} sẽ bị xóa khỏi hệ thống.'
                            : 'Pallet ${sourcePal.palletCode} sẽ trở thành Pallet rỗng (0 items) để tái sử dụng.',
                        style: TextStyle(color: c.textSecondary, fontSize: 10.5),
                      ),
                      onChanged: (val) => setModalState(() => deleteSourcePallet = val ?? false),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isProcessing ? null : () => Navigator.pop(ctx),
                child: Text('HỦY', style: TextStyle(color: c.textMuted)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onPressed: isProcessing
                    ? null
                    : () async {
                        setModalState(() => isProcessing = true);
                        try {
                          await _repo.mergePallets(
                            sourcePalletId: selectedSourceId,
                            targetPalletId: selectedTargetId,
                            performedBy: 'Thủ kho Desktop',
                            deleteSourcePallet: deleteSourcePallet,
                          );

                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                backgroundColor: const Color(0xFF10B981),
                                content: Text('✓ Đã nhập gộp thành công ${sourceItems.length} sản phẩm từ ${sourcePal.palletCode} vào ${targetPal.palletCode}!'),
                              ),
                            );
                          }
                        } catch (e) {
                          setModalState(() => isProcessing = false);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(backgroundColor: c.errorCoral, content: Text('Lỗi khi gộp Pallet: $e')),
                            );
                          }
                        }
                      },
                child: isProcessing
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('XÁC NHẬN NHẬP GỘP', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmDeletePallet(Pallet pallet) {
    final c = _eyeCare.colors;
    final itemsCount = _repo.items.where((it) => it.palletId == pallet.palletId).length;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: c.errorCoral, size: 24),
            const SizedBox(width: 8),
            Text('Xác nhận xóa Pallet', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          itemsCount > 0
              ? 'Pallet ${pallet.palletCode} đang chứa $itemsCount sản phẩm. Nếu xóa Pallet này, các sản phẩm sẽ chuyển về trạng thái Chưa đóng pallet. Bạn có chắc chắn muốn xóa?'
              : 'Bạn có chắc chắn muốn xóa Pallet ${pallet.palletCode} không?',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('HỦY', style: TextStyle(color: c.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.errorCoral),
            onPressed: () async {
              await _repo.deletePallet(pallet.palletId);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(backgroundColor: c.successEmerald, content: Text('✓ Đã xóa Pallet ${pallet.palletCode}!')),
                );
              }
            },
            child: const Text('XÓA PALLET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmClearAllData() {
    final c = _eyeCare.colors;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: c.warningAmber, size: 28),
            const SizedBox(width: 8),
            Text('Xóa Sạch Dữ Liệu Cũ?', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Thao tác này sẽ xóa sạch toàn bộ đơn hàng và chip RFID thử nghiệm trong hệ thống, đưa về trạng thái sạch hoàn toàn để bạn bắt đầu tạo dữ liệu thực tế.',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('HỦY', style: TextStyle(color: c.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.errorCoral),
            onPressed: () async {
              await _repo.clearAllData();
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(backgroundColor: c.successEmerald, content: const Text('✓ Đã xóa sạch dữ liệu thử nghiệm trong hệ thống!')),
                );
              }
            },
            child: const Text('XÓA SẠCH DỮ LIỆU', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    // KPI Metrics
    final totalPallets = _repo.pallets.length;
    final palletsWithItems = _repo.pallets.where((p) => _repo.items.any((it) => it.palletId == p.palletId)).length;
    final emptyPallets = totalPallets - palletsWithItems;
    final usedLocations = _repo.locations.where((l) => l.currentPallets > 0 || _repo.pallets.any((p) => p.locationId == l.locationId)).length;
    final totalItemsInStock = _repo.items.where((i) => i.status == ItemStatus.inStock).length;

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: HardwareStatusAppBar(
        title: '🏢 Điều Chuyển Kho & Quản Lý Pallet',
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: c.textSecondary),
            tooltip: 'Làm mới dữ liệu từ Database',
            onPressed: () => _repo.refreshFromDatabase(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
            tooltip: 'Xóa sạch dữ liệu thử nghiệm',
            onPressed: _confirmClearAllData,
          ),
        ],
      ),
      body: Column(
        children: [
          // KPI Stats & Action Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: c.bgCard,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    // Row 1: KPI Stats Chips
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildStatChip('Tổng Pallet: $totalPallets', c.rfidCyan, c),
                            _buildStatChip('Pallet có hàng: $palletsWithItems', const Color(0xFF10B981), c),
                            _buildStatChip('Pallet trống: $emptyPallets', const Color(0xFFF59E0B), c),
                            _buildStatChip('Vị trí kệ dùng: $usedLocations/${_repo.locations.length}', const Color(0xFF8B5CF6), c),
                            _buildStatChip('Tồn kho: $totalItemsInStock SP', const Color(0xFF06B6D4), c),
                          ],
                        ),
                        // Nút hành động Toolbar
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            ElevatedButton.icon(
                              icon: const Icon(Icons.call_merge, size: 16, color: Color(0xFF2C251E)),
                              label: const Text('GỘP 2 PALLET', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFF59E0B),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              onPressed: () => _showMergePalletsDialog(),
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.add_box, size: 16, color: Color(0xFF2C251E)),
                              label: const Text('TẠO PALLET', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              ),
                              onPressed: _showAddPalletDialog,
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Row 2: Search Bar
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 38,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: c.bgDeep,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: c.border),
                            ),
                            child: TextField(
                              controller: _searchController,
                              style: TextStyle(color: c.textPrimary, fontSize: 13),
                              decoration: InputDecoration(
                                icon: Icon(Icons.search, color: c.rfidCyan, size: 18),
                                hintText: 'Tìm kiếm Pallet, Chip RFID, SKU hoặc Vị trí kệ kho...',
                                hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                                border: InputBorder.none,
                                suffixIcon: _searchQuery.isNotEmpty
                                    ? IconButton(
                                        icon: Icon(Icons.clear, color: c.textMuted, size: 16),
                                        onPressed: () {
                                          _searchController.clear();
                                          setState(() => _searchQuery = '');
                                        },
                                      )
                                    : null,
                              ),
                              onChanged: (val) => setState(() => _searchQuery = val.trim()),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),

          // Tab navigation bar
          Container(
            color: c.bgCard,
            child: TabBar(
              controller: _tabController,
              indicatorColor: c.rfidCyan,
              indicatorWeight: 3,
              labelColor: c.rfidCyan,
              unselectedLabelColor: c.textSecondary,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              tabs: const [
                Tab(icon: Icon(Icons.pallet, size: 18), text: 'Quản Lý & Điều Chuyển Pallet'),
                Tab(icon: Icon(Icons.inventory_2, size: 18), text: 'Tồn Kho SKU'),
                Tab(icon: Icon(Icons.history, size: 18), text: 'Lịch Sử Điều Chuyển Kho'),
              ],
            ),
          ),

          // Tab views
          Expanded(
            child: AnimatedBuilder(
              animation: _repo,
              builder: (context, _) {
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPalletManagementTab(c),
                    _buildSkuStockTab(c),
                    _buildMovementHistoryTab(c),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip(String label, Color color, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.bold)),
    );
  }

  // --- TAB 1: QUẢN LÝ & ĐIỀU CHUYỂN PALLET ---

  Widget _buildPalletManagementTab(EyeCareColors c) {
    final q = _searchQuery.toLowerCase();
    final pallets = _repo.pallets.where((p) {
      if (q.isEmpty) return true;
      final loc = _repo.locations.where((l) => l.locationId == p.locationId).firstOrNull;
      return p.palletCode.toLowerCase().contains(q) ||
          p.palletId.toLowerCase().contains(q) ||
          (loc?.locationCode.toLowerCase().contains(q) ?? false) ||
          _repo.items.any((it) => it.palletId == p.palletId && (it.sku.toLowerCase().contains(q) || it.productName.toLowerCase().contains(q)));
    }).toList();

    if (pallets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pallet, size: 56, color: c.textMuted),
              const SizedBox(height: 14),
              Text(
                _searchQuery.isEmpty ? 'Chưa có Pallet nào trong kho.' : 'Không tìm thấy Pallet nào khớp với "$_searchQuery"',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16, color: Color(0xFF2C251E)),
                label: const Text('TẠO PALLET MỚI', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                onPressed: _showAddPalletDialog,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: pallets.length,
      itemBuilder: (context, index) {
        final pallet = pallets[index];
        final loc = _repo.locations.where((l) => l.locationId == pallet.locationId).firstOrNull;
        final locDisplay = loc?.locationCode ?? (pallet.locationId ?? 'Chưa xếp kệ');

        final palletItems = _repo.items.where((it) => it.palletId == pallet.palletId).toList();
        final hasItems = palletItems.isNotEmpty;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: c.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: ExpansionTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: hasItems ? const Color(0xFF10B981).withValues(alpha: 0.15) : c.textMuted.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.pallet, color: hasItems ? const Color(0xFF10B981) : c.textMuted, size: 24),
            ),
            title: Row(
              children: [
                Text(
                  pallet.palletCode,
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: (pallet.isMultiSku ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: (pallet.isMultiSku ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    !hasItems ? 'Pallet Trống' : (pallet.isMultiSku ? 'Đa SKU' : 'Đơn SKU'),
                    style: TextStyle(
                      color: !hasItems ? c.textMuted : (pallet.isMultiSku ? const Color(0xFFF59E0B) : const Color(0xFF10B981)),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${palletItems.length} SP',
                  style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: const Color(0xFFEF4444), size: 14),
                  const SizedBox(width: 3),
                  Text('Kệ: $locDisplay', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                  const SizedBox(width: 14),
                  Icon(Icons.nfc, color: c.rfidCyan, size: 14),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text('RFID: ${pallet.palletId}', style: TextStyle(color: c.rfidCyan, fontFamily: 'monospace', fontSize: 11), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: c.bgDeep.withValues(alpha: 0.5),
                  border: Border(top: BorderSide(color: c.border)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Action Buttons Bar
                    Row(
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.drive_file_move_outlined, size: 15),
                          label: const Text('Chuyển Kệ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: c.rfidCyan,
                            side: BorderSide(color: c.rfidCyan),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          ),
                          onPressed: () => _showMovePalletDialog(pallet),
                        ),
                        const SizedBox(width: 8),
                        if (hasItems)
                          OutlinedButton.icon(
                            icon: const Icon(Icons.call_merge, size: 15),
                            label: const Text('Gộp Sang Pallet Khác', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFF59E0B),
                              side: const BorderSide(color: Color(0xFFF59E0B)),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            ),
                            onPressed: () => _showMergePalletsDialog(pallet),
                          ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                          tooltip: 'Xóa Pallet',
                          onPressed: () => _confirmDeletePallet(pallet),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Items List inside Pallet
                    Text('DANH SÁCH MẶT HÀNG TRÊN PALLET (${palletItems.length}):', style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    if (palletItems.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('Pallet đang trống, chưa có mặt hàng nào được gán.', style: TextStyle(color: c.textMuted, fontSize: 12)),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: palletItems.length,
                        separatorBuilder: (_, _) => Divider(color: c.border, height: 6),
                        itemBuilder: (context, idx) {
                          final it = palletItems[idx];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Text('${idx + 1}.', style: TextStyle(color: c.textMuted, fontSize: 11)),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 3,
                                  child: Text(it.productName, style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                                ),
                                Expanded(
                                  flex: 2,
                                  child: Text('SKU: ${it.sku}', style: TextStyle(color: c.textSecondary, fontSize: 11), overflow: TextOverflow.ellipsis),
                                ),
                                Expanded(
                                  flex: 3,
                                  child: Text('EPC: ${it.epc}', style: TextStyle(color: c.rfidCyan, fontSize: 10.5, fontFamily: 'monospace'), overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // --- TAB 2: TỒN KHO SKU ---

  Widget _buildSkuStockTab(EyeCareColors c) {
    final summary = _repo.getStockSummary();

    if (summary.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.inventory_2_outlined, size: 56, color: c.textMuted),
              const SizedBox(height: 14),
              Text('Chưa có tồn kho sản phẩm nào trong kho.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16, color: Color(0xFF2C251E)),
                label: const Text('THÊM SẢN PHẨM MỚI', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
                onPressed: _showAddProductDialog,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: summary.length,
      itemBuilder: (context, index) {
        final key = summary.keys.elementAt(index);
        final data = summary[key]!;
        final Product prod = data['product'];
        final int inStock = data['inStock'];
        final int allocated = data['allocated'];
        final int total = data['total'];

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(prod.sku, style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 14, letterSpacing: 0.5)),
                        const SizedBox(height: 2),
                        Text(prod.productName, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13)),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: c.bgDeep, borderRadius: BorderRadius.circular(6)),
                        child: Text(prod.category, style: TextStyle(color: c.textSecondary, fontSize: 11)),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.edit_outlined, color: c.rfidCyan, size: 18),
                        tooltip: 'Chỉnh sửa SKU',
                        onPressed: () => _showEditProductDialog(prod),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: c.textMuted, size: 18),
                        tooltip: 'Xóa sản phẩm',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              backgroundColor: c.bgCard,
                              title: Text('Xác nhận xóa SKU', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                              content: Text('Bạn có chắc chắn muốn xóa sản phẩm ${prod.sku} (${prod.productName}) không?', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('HỦY', style: TextStyle(color: c.textMuted))),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(backgroundColor: c.errorCoral),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('XÓA', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await _repo.deleteProduct(prod.productId);
                          }
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _buildStockStatBox('Khả Dụng', inStock.toString(), const Color(0xFF10B981), c)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildStockStatBox('Đã Giữ', allocated.toString(), const Color(0xFFF59E0B), c)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildStockStatBox('Tổng Tồn', total.toString(), c.rfidCyan, c)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStockStatBox(String label, String value, Color color, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: c.textSecondary, fontSize: 10.5)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16)),
        ],
      ),
    );
  }

  // --- TAB 3: LỊCH SỬ ĐIỀU CHUYỂN KHO ---

  Widget _buildMovementHistoryTab(EyeCareColors c) {
    final moves = _repo.transactions.where((t) => t.type == TransactionType.movement).toList();

    if (moves.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history_toggle_off, size: 56, color: c.textMuted),
              const SizedBox(height: 14),
              Text('Chưa có lịch sử điều chuyển hoặc gộp Pallet nào.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: moves.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final tx = moves[idx];
        final isMerge = tx.sku == 'PALLET_MERGE' || (tx.documentNo.startsWith('MERGE-'));

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isMerge ? const Color(0xFFF59E0B).withValues(alpha: 0.4) : c.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isMerge ? const Color(0xFFF59E0B) : c.rfidCyan).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(isMerge ? Icons.call_merge : Icons.swap_horiz, color: isMerge ? const Color(0xFFF59E0B) : c.rfidCyan, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isMerge ? 'NHẬP GỘP PALLET' : 'DI CHUYỂN VỊ TRÍ KỆ',
                          style: TextStyle(color: isMerge ? const Color(0xFFF59E0B) : c.rfidCyan, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _formatTimestamp(tx.timestamp),
                          style: TextStyle(color: c.textMuted, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(tx.productName, style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(tx.notes ?? '', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.person_outline, size: 13, color: c.textMuted),
                        const SizedBox(width: 4),
                        Text(tx.performedBy, style: TextStyle(color: c.textMuted, fontSize: 11)),
                        const SizedBox(width: 14),
                        Icon(Icons.pallet, size: 13, color: c.textMuted),
                        const SizedBox(width: 4),
                        Text('Pallet: ${tx.palletCode}', style: TextStyle(color: c.textMuted, fontSize: 11)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatTimestamp(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$h:$m $d/$mo/${dt.year}';
  }

  void _showEditProductDialog(Product prod) {
    final c = _eyeCare.colors;
    final nameController = TextEditingController(text: prod.productName);
    final catController = TextEditingController(text: prod.category);
    final unitController = TextEditingController(text: prod.unit);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.border)),
        title: Row(
          children: [
            Icon(Icons.edit_note, color: c.rfidCyan, size: 22),
            const SizedBox(width: 8),
            Text('Chỉnh Sửa Thông Tin SKU', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mã SKU: ${prod.sku}', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 14),
              TextField(
                controller: nameController,
                style: TextStyle(color: c.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Tên sản phẩm',
                  labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: c.bgDeep,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: catController,
                style: TextStyle(color: c.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Phân loại / Danh mục',
                  labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: c.bgDeep,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: unitController,
                style: TextStyle(color: c.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Đơn vị tính (ĐVT)',
                  labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: c.bgDeep,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('HỦY', style: TextStyle(color: c.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
            onPressed: () async {
              final newName = nameController.text.trim();
              final newCat = catController.text.trim();
              final newUnit = unitController.text.trim();

              final updated = Product(
                productId: prod.productId,
                sku: prod.sku,
                productName: newName.isNotEmpty ? newName : prod.sku,
                category: newCat.isNotEmpty ? newCat : 'Hàng nhập qua cổng RFID',
                unit: newUnit.isNotEmpty ? newUnit : 'Cái',
              );

              await _repo.updateProduct(updated);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('LƯU THAY ĐỔI', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
