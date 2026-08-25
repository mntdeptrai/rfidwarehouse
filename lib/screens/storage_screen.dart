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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _eyeCare.addListener(_onThemeChanged);
    _repo.addListener(_onRepoChanged);
    UhfService().setScanMode(PdaScanMode.rfid);
  }

  @override
  void dispose() {
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
        title: Text('Thêm Sản Phẩm Mới', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: skuController,
                decoration: InputDecoration(labelText: 'Mã SKU', hintText: 'Ví dụ: SKU-001', labelStyle: TextStyle(color: c.textSecondary)),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: InputDecoration(labelText: 'Tên sản phẩm', hintText: 'Tên sản phẩm...', labelStyle: TextStyle(color: c.textSecondary)),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: categoryController,
                decoration: InputDecoration(labelText: 'Danh mục', hintText: 'Điện tử, May mặc...', labelStyle: TextStyle(color: c.textSecondary)),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: unitController,
                decoration: InputDecoration(labelText: 'Đơn vị tính', hintText: 'Cái, Thùng, Hộp...', labelStyle: TextStyle(color: c.textSecondary)),
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
            style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
            onPressed: () async {
              final sku = skuController.text.trim();
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

  void _showAddLocationDialog() {
    final c = _eyeCare.colors;
    final codeController = TextEditingController();
    final zoneController = TextEditingController();
    final shelfController = TextEditingController();
    final levelController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        title: Text('Thêm Vị Trí Lưu Kho', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                decoration: InputDecoration(labelText: 'Mã Vị trí (Location Code)', hintText: 'Ví dụ: LOC-A01-01', labelStyle: TextStyle(color: c.textSecondary)),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: zoneController,
                decoration: InputDecoration(labelText: 'Khu vực (Zone)', hintText: 'Ví dụ: Zone A', labelStyle: TextStyle(color: c.textSecondary)),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: shelfController,
                decoration: InputDecoration(labelText: 'Kệ (Shelf)', hintText: 'Ví dụ: Kệ 01', labelStyle: TextStyle(color: c.textSecondary)),
                style: TextStyle(color: c.textPrimary),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: levelController,
                decoration: InputDecoration(labelText: 'Tầng (Level)', hintText: 'Ví dụ: Tầng 1', labelStyle: TextStyle(color: c.textSecondary)),
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
            style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
            onPressed: () async {
              final code = codeController.text.trim();
              if (code.isEmpty) return;

              final newLoc = Location(
                locationId: 'LOC-${DateTime.now().millisecondsSinceEpoch}',
                locationCode: code,
                zone: zoneController.text.trim().isNotEmpty ? zoneController.text.trim() : 'Zone A',
                shelf: shelfController.text.trim().isNotEmpty ? shelfController.text.trim() : 'Kệ 01',
                level: levelController.text.trim().isNotEmpty ? levelController.text.trim() : 'Tầng 1',
              );

              await _repo.addLocation(newLoc);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('LƯU VỊ TRÍ', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddPalletDialog() {
    final c = _eyeCare.colors;
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        title: Text('Tạo Pallet Mới', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              decoration: InputDecoration(labelText: 'Mã Pallet (Pallet Code)', hintText: 'Ví dụ: PL-01', labelStyle: TextStyle(color: c.textSecondary)),
              style: TextStyle(color: c.textPrimary),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('HỦY', style: TextStyle(color: c.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () {
              final code = codeController.text.trim().toUpperCase();
              if (code.isEmpty) return;

              final locId = _repo.locations.isNotEmpty ? _repo.locations.first.locationId : 'LOC-A01-01';
              _repo.createOrAssignPallet(
                palletCode: code,
                locationId: locId,
                newItems: [],
              );
              Navigator.pop(ctx);
            },
            child: const Text('TẠO PALLET', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
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
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: c.warningAmber, size: 28),
            const SizedBox(width: 8),
            Text('Xóa Sạch Dữ Liệu Cũ?', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          'Thao tác này sẽ xóa sạch 100% toàn bộ đơn hàng và chip RFID thử nghiệm trong hệ thống, đưa về trạng thái sạch hoàn toàn để bạn bắt đầu tạo dữ liệu thực tế.',
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


  void _showMovePalletDialog(Pallet pallet) {
    if (_repo.locations.isEmpty) return;
    String selectedLocId = _repo.locations.first.locationId;
    final c = _eyeCare.colors;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: c.bgCard,
              title: Text(
                'Di chuyển Pallet ${pallet.palletCode}',
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Số lượng hàng trên Pallet: ${pallet.itemIds.length} Items',
                    style: TextStyle(color: c.textSecondary, fontSize: 13),
                  ),
                  const SizedBox(height: 14),
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
                  child: Text('Hủy', style: TextStyle(color: c.textMuted)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
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
                        content: Text('Đã di chuyển Pallet ${pallet.palletCode} thành công!'),
                      ),
                    );
                  },
                  child: const Text('Xác nhận Di chuyển', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: HardwareStatusAppBar(
        title: '🏢 Quản Lý Lưu Kho',
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: c.textSecondary),
            tooltip: 'Làm mới',
            onPressed: () => _repo.refreshFromDatabase(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
            tooltip: 'Xóa sạch dữ liệu',
            onPressed: _confirmClearAllData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab bar
          Container(
            color: c.bgCard,
            child: TabBar(
              controller: _tabController,
              indicatorColor: c.rfidCyan,
              indicatorWeight: 3,
              labelColor: c.rfidCyan,
              unselectedLabelColor: c.textSecondary,
              tabs: const [
                Tab(icon: Icon(Icons.inventory_2, size: 18), text: 'Tồn Kho SKU'),
                Tab(icon: Icon(Icons.pallet, size: 18), text: 'Quản Lý Pallet'),
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
                    _buildSkuStockTab(c),
                    _buildPalletManagementTab(c),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

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
              Text(
                'Chưa có tồn kho sản phẩm nào trong kho.',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
                onPressed: _showAddProductDialog,
                child: const Text('+ THÊM SẢN PHẨM MỚI', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12)),
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
            borderRadius: BorderRadius.circular(16),
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
                        Text(
                          prod.sku,
                          style: TextStyle(
                            color: c.rfidCyan,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          prod.productName,
                          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: c.bgCardElevated,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          prod.category,
                          style: TextStyle(color: c.textSecondary, fontSize: 11),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        icon: Icon(Icons.edit_outlined, color: c.rfidCyan, size: 18),
                        tooltip: 'Chỉnh sửa tên / thông tin SKU',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () => _showEditProductDialog(prod),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, color: c.textMuted, size: 18),
                        tooltip: 'Xóa sản phẩm',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
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
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildStockStatBox('Khả Dụng', inStock.toString(), const Color(0xFF10B981), c),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStockStatBox('Đã Giữ', allocated.toString(), const Color(0xFFF59E0B), c),
                  ),

                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStockStatBox('Tổng Tồn', total.toString(), c.rfidCyan, c),
                  ),
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
        color: c.bgCardElevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(color: c.textSecondary, fontSize: 10)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildPalletManagementTab(EyeCareColors c) {
    if (_repo.pallets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.pallet, size: 56, color: c.textMuted),
              const SizedBox(height: 14),
              Text(
                'Chưa có Pallet nào trong kho.',
                style: TextStyle(color: c.textSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                onPressed: _showAddPalletDialog,
                child: const Text('+ TẠO PALLET MỚI', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _repo.pallets.length,
      itemBuilder: (context, index) {
        final pallet = _repo.pallets[index];
        final loc = _repo.locations.where((l) => l.locationId == pallet.locationId).firstOrNull ??
            Location(locationId: '', locationCode: 'Chưa gắn', zone: '', shelf: '', level: '');
        final palletItems = _repo.items.where((it) => pallet.itemIds.contains(it.itemId)).toList();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.border),
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
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: c.rfidCyan.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.pallet, color: c.rfidCyan, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pallet.palletCode,
                            style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          Text(
                            pallet.isMultiSku ? 'Pallet Đa SKU' : 'Pallet Đơn SKU',
                            style: TextStyle(
                              color: pallet.isMultiSku ? const Color(0xFFF59E0B) : const Color(0xFF10B981),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: Icon(Icons.drive_file_move_outlined, color: c.rfidCyan),
                    tooltip: 'Di chuyển Pallet',
                    onPressed: () => _showMovePalletDialog(pallet),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on, color: Color(0xFFEF4444), size: 16),
                        const SizedBox(width: 4),
                        Text(
                          'Vị trí: ${loc.locationCode} (${loc.zone})',
                          style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Text(
                      '${pallet.itemIds.length} Items',
                      style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (palletItems.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Mẫu EPC: ${palletItems.first.epc}',
                  style: TextStyle(color: c.textSecondary, fontFamily: 'Courier', fontSize: 10.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        );
      },
    );
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


