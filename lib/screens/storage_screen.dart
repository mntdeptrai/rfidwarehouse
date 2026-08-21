import 'package:flutter/material.dart';
import '../models/wms_models.dart';
import '../services/warehouse_repository.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _showAddProductDialog() {
    final skuController = TextEditingController();
    final nameController = TextEditingController();
    final unitController = TextEditingController();
    final categoryController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Thêm Sản Phẩm Mới', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: skuController,
                decoration: const InputDecoration(labelText: 'Mã SKU', hintText: 'Ví dụ: SKU-001', labelStyle: TextStyle(color: Colors.white70)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Tên sản phẩm', hintText: 'Tên sản phẩm...', labelStyle: TextStyle(color: Colors.white70)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: categoryController,
                decoration: const InputDecoration(labelText: 'Danh mục', hintText: 'Điện tử, May mặc...', labelStyle: TextStyle(color: Colors.white70)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: unitController,
                decoration: const InputDecoration(labelText: 'Đơn vị tính', hintText: 'Cái, Thùng, Hộp...', labelStyle: TextStyle(color: Colors.white70)),
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
            child: const Text('LƯU SẢN PHẨM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddLocationDialog() {
    final codeController = TextEditingController();
    final zoneController = TextEditingController();
    final shelfController = TextEditingController();
    final levelController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Thêm Vị Trí Lưu Kho', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: codeController,
                decoration: const InputDecoration(labelText: 'Mã Vị trí (Location Code)', hintText: 'Ví dụ: LOC-A01-01', labelStyle: TextStyle(color: Colors.white70)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: zoneController,
                decoration: const InputDecoration(labelText: 'Khu vực (Zone)', hintText: 'Ví dụ: Zone A', labelStyle: TextStyle(color: Colors.white70)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: shelfController,
                decoration: const InputDecoration(labelText: 'Kệ (Shelf)', hintText: 'Ví dụ: Kệ 01', labelStyle: TextStyle(color: Colors.white70)),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: levelController,
                decoration: const InputDecoration(labelText: 'Tầng (Level)', hintText: 'Ví dụ: Tầng 1', labelStyle: TextStyle(color: Colors.white70)),
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
            child: const Text('LƯU VỊ TRÍ', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showAddPalletDialog() {
    final codeController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Tạo Pallet Mới', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: codeController,
              decoration: const InputDecoration(labelText: 'Mã Pallet (Pallet Code)', hintText: 'Ví dụ: PL-01', labelStyle: TextStyle(color: Colors.white70)),
              style: const TextStyle(color: Colors.white),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY', style: TextStyle(color: Colors.white54)),
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
            child: const Text('TẠO PALLET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _confirmClearAllData() {
    final c = EyeCareThemeService().colors;
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
          'Thao tác này sẽ xóa sạch 100% toàn bộ đơn hàng và chip RFID thử nghiệm trong CSDL SQLite trên máy cầm tay và cả trên máy chủ MySQL, đưa về trạng thái sạch hoàn toàn để bạn nhập dữ liệu thực tế.',
          style: TextStyle(color: c.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('HỦY', style: TextStyle(color: c.textMuted))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: c.errorCoral),
            onPressed: () async {
              await _repo.clearAllData(alsoClearMySql: true);
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(backgroundColor: c.successEmerald, content: const Text('✓ Đã xóa sạch dữ liệu thử nghiệm trên cả SQLite & MySQL thành công!')),
                );
              }
            },
            child: const Text('XÓA SẠCH DỮ LIỆU', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }


  void _showMovePalletDialog(Pallet pallet) {
    if (_repo.locations.isEmpty) return;
    String selectedLocId = _repo.locations.first.locationId;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1E293B),
              title: Text(
                'Di chuyển Pallet ${pallet.palletCode}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Số lượng hàng trên Pallet: ${pallet.itemIds.length} Items',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
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
                  child: const Text('Hủy', style: TextStyle(color: Colors.white54)),
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
                  child: const Text('Xác nhận Di chuyển', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: HardwareStatusAppBar(
        title: '🏢 Quản Lý Lưu Kho',
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            tooltip: 'Làm mới',
            onPressed: () => _repo.refreshFromDatabase(),
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
            tooltip: 'Xóa sạch CSDL SQLite',
            onPressed: _confirmClearAllData,
          ),
        ],
      ),
      body: Column(
        children: [
          // Tab bar
          Container(
            color: const Color(0xFF1E293B),
            child: TabBar(
              controller: _tabController,
              indicatorColor: const Color(0xFF38BDF8),
              indicatorWeight: 3,
              labelColor: const Color(0xFF38BDF8),
              unselectedLabelColor: Colors.white54,
              tabs: const [
                Tab(icon: Icon(Icons.inventory_2, size: 18), text: 'Tồn Kho SKU'),
                Tab(icon: Icon(Icons.pallet, size: 18), text: 'Quản Lý Pallet'),
                Tab(icon: Icon(Icons.grid_view, size: 18), text: 'Sơ Đồ Location'),
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
                    _buildSkuStockTab(),
                    _buildPalletManagementTab(),
                    _buildLocationGridTab(),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkuStockTab() {
    final summary = _repo.getStockSummary();

    if (summary.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.inventory_2_outlined, size: 56, color: Colors.white24),
              const SizedBox(height: 14),
              const Text(
                'Chưa có tồn kho sản phẩm nào trong SQLite.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                onPressed: _showAddProductDialog,
                child: const Text('+ THÊM SẢN PHẨM MỚI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
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
                          style: const TextStyle(
                            color: Color(0xFF38BDF8),
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          prod.productName,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F172A),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      prod.category,
                      style: const TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildStockStatBox('Khả Dụng', inStock.toString(), const Color(0xFF10B981)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStockStatBox('Đã Giữ (PO)', allocated.toString(), const Color(0xFFF59E0B)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildStockStatBox('Tổng Tồn', total.toString(), const Color(0xFF38BDF8)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStockStatBox(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildPalletManagementTab() {
    if (_repo.pallets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.pallet, size: 56, color: Colors.white24),
              const SizedBox(height: 14),
              const Text(
                'Chưa có Pallet nào trong kho SQLite.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
                onPressed: _showAddPalletDialog,
                child: const Text('+ TẠO PALLET MỚI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
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
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
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
                          color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.pallet, color: Color(0xFF38BDF8), size: 22),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            pallet.palletCode,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
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
                    icon: const Icon(Icons.drive_file_move_outlined, color: Color(0xFF38BDF8)),
                    tooltip: 'Di chuyển Pallet',
                    onPressed: () => _showMovePalletDialog(pallet),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
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
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    Text(
                      '${pallet.itemIds.length} Items',
                      style: const TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (palletItems.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Mẫu EPC: ${palletItems.first.epc}',
                  style: const TextStyle(color: Colors.white54, fontFamily: 'Courier', fontSize: 10.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLocationGridTab() {
    if (_repo.locations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.grid_view_outlined, size: 56, color: Colors.white24),
              const SizedBox(height: 14),
              const Text(
                'Chưa có Vị trí kho nào trong SQLite.',
                style: TextStyle(color: Colors.white70, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                onPressed: _showAddLocationDialog,
                child: const Text('+ THÊM VỊ TRÍ MỚI', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _repo.locations.length,
      itemBuilder: (context, index) {
        final loc = _repo.locations[index];
        final bool hasPallet = loc.currentPallets > 0;
        final palletsAtLoc = _repo.pallets.where((p) => p.locationId == loc.locationId).toList();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: hasPallet ? const Color(0xFF38BDF8).withValues(alpha: 0.5) : const Color(0xFF334155),
              width: hasPallet ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    loc.locationCode,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: hasPallet ? const Color(0xFF10B981) : Colors.white24,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
              Text(
                '${loc.zone} • ${loc.shelf}',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  hasPallet ? palletsAtLoc.map((e) => e.palletCode).join(', ') : 'Vị trí trống',
                  style: TextStyle(
                    color: hasPallet ? const Color(0xFF38BDF8) : Colors.white38,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
