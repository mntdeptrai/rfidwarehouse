import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/catalog_models.dart';
import '../../models/wms_models.dart';
import '../../services/warehouse_repository.dart';
import '../../services/auth_service.dart';
import '../../theme/eye_care_theme.dart';

/// Màn hình Quản Lý Danh Mục Sản Phẩm (SKU Catalog) trên Desktop Workstation.
///
/// Kết nối 100% dữ liệu thực từ WarehouseRepository (Supabase / SQLite).
/// Tuân thủ quy tắc Không Mock Data, Clean Architecture và Hệ Thống Màu Xanh Doanh Nghiệp.
class DesktopProductManagementView extends StatefulWidget {
  final VoidCallback? onNavigateToInbound;

  const DesktopProductManagementView({
    super.key,
    this.onNavigateToInbound,
  });

  @override
  State<DesktopProductManagementView> createState() => _DesktopProductManagementViewState();
}

class _DesktopProductManagementViewState extends State<DesktopProductManagementView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final AuthService _auth = AuthService();

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'ALL';

  @override
  void initState() {
    super.initState();
    _repo.addListener(_onStateChange);
    _eyeCare.addListener(_onStateChange);
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _repo.removeListener(_onStateChange);
    _eyeCare.removeListener(_onStateChange);
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Product> _getFilteredProducts() {
    final all = _repo.products;
    return all.where((p) {
      if (_selectedCategory != 'ALL' && p.category.trim().toUpperCase() != _selectedCategory.toUpperCase()) {
        return false;
      }
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase().trim();
      final matchSku = p.sku.toLowerCase().contains(q);
      final matchName = p.productName.toLowerCase().contains(q);
      final matchCat = p.category.toLowerCase().contains(q);
      final matchUnit = p.unit.toLowerCase().contains(q);
      final matchDesc = (p.description ?? '').toLowerCase().contains(q);
      return matchSku || matchName || matchCat || matchUnit || matchDesc;
    }).toList();
  }

  int _getStockForSku(String sku) {
    final clean = sku.trim().toUpperCase();
    return _repo.items.where((i) => i.sku.trim().toUpperCase() == clean && i.status == ItemStatus.inStock).length;
  }

  List<String> _getAllCategories() {
    final cats = _repo.products
        .map((p) => p.category.trim())
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    cats.sort();
    return cats;
  }

  Future<void> _showAddOrEditProductDialog({Product? existing}) async {
    final isEdit = existing != null;
    final c = _eyeCare.colors;

    final skuCtrl = TextEditingController(text: existing?.sku ?? '');
    final nameCtrl = TextEditingController(text: existing?.productName ?? '');
    final unitCtrl = TextEditingController(text: existing?.unit ?? 'Cái');
    final catCtrl = TextEditingController(text: existing?.category ?? 'Hàng Hóa');
    final descCtrl = TextEditingController(text: existing?.description ?? '');

    String? errorMsg;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: c.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: c.border),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.rfidCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      isEdit ? Icons.edit_note_rounded : Icons.add_box_rounded,
                      color: c.rfidCyan,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isEdit ? 'CHỈNH SỬA SẢN PHẨM' : 'THÊM SẢN PHẨM MỚI',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 480,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (errorMsg != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline_rounded, color: Color(0xFFEF4444), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorMsg!,
                                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Mã SKU
                      Text('Mã SKU *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: skuCtrl,
                        enabled: !isEdit, // Không sửa mã SKU khi đã tạo để bảo toàn liên kết dữ liệu
                        style: TextStyle(color: c.textPrimary, fontSize: 13, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          hintText: 'vd: SKU-VT-001, BOX-STEEL-01...',
                          hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                          filled: true,
                          fillColor: isEdit ? c.bgCardElevated.withValues(alpha: 0.5) : c.bgCardElevated,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Tên sản phẩm
                      Text('Tên sản phẩm *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: nameCtrl,
                        style: TextStyle(color: c.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'vd: Hộp sắt đựng chứng từ, Bulong M8...',
                          hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                          filled: true,
                          fillColor: c.bgCardElevated,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Đơn vị tính & Danh mục
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Đơn vị tính *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: unitCtrl,
                                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'vd: Cái, Hộp, Thùng...',
                                    hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                                    filled: true,
                                    fillColor: c.bgCardElevated,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Danh mục / Nhóm *', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                                const SizedBox(height: 4),
                                TextField(
                                  controller: catCtrl,
                                  style: TextStyle(color: c.textPrimary, fontSize: 13),
                                  decoration: InputDecoration(
                                    hintText: 'vd: Kim Khí, Bao Bì...',
                                    hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                                    filled: true,
                                    fillColor: c.bgCardElevated,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Mô tả
                      Text('Mô tả / Quy cách', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: descCtrl,
                        maxLines: 2,
                        style: TextStyle(color: c.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Thông số kỹ thuật, ghi chú kích thước...',
                          hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                          filled: true,
                          fillColor: c.bgCardElevated,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: Text('HỦY', style: TextStyle(color: c.textMuted, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.rfidCyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final sku = skuCtrl.text.trim().toUpperCase();
                    final name = nameCtrl.text.trim();
                    final unit = unitCtrl.text.trim().isEmpty ? 'Cái' : unitCtrl.text.trim();
                    final cat = catCtrl.text.trim().isEmpty ? 'Chung' : catCtrl.text.trim();
                    final desc = descCtrl.text.trim();

                    if (sku.isEmpty || name.isEmpty) {
                      setDialogState(() => errorMsg = 'Vui lòng nhập đầy đủ Mã SKU và Tên sản phẩm.');
                      return;
                    }

                    if (!isEdit) {
                      final duplicate = _repo.products.where((p) => p.sku.trim().toUpperCase() == sku).firstOrNull;
                      if (duplicate != null) {
                        setDialogState(() => errorMsg = 'Mã SKU "$sku" đã tồn tại trong hệ thống.');
                        return;
                      }

                      final newProd = Product(
                        productId: 'PROD-${DateTime.now().millisecondsSinceEpoch}',
                        sku: sku,
                        productName: name,
                        unit: unit,
                        category: cat,
                        description: desc.isNotEmpty ? desc : null,
                      );
                      await _repo.addProduct(newProd);
                    } else {
                      final updated = Product(
                        productId: existing.productId,
                        sku: existing.sku,
                        productName: name,
                        unit: unit,
                        category: cat,
                        description: desc.isNotEmpty ? desc : null,
                      );
                      await _repo.updateProduct(updated);
                    }

                    if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF10B981),
                          content: Text(
                            isEdit ? '✓ Đã cập nhật sản phẩm "$sku"' : '✓ Đã thêm sản phẩm mới "$sku"',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      );
                    }
                  },
                  child: Text(isEdit ? 'LƯU THAY ĐỔI' : 'THÊM MỚI', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeleteProduct(Product prod) async {
    final c = _eyeCare.colors;
    final inStockCount = _getStockForSku(prod.sku);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 24),
            const SizedBox(width: 10),
            Text('Xác nhận xóa sản phẩm?', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bạn có chắc chắn muốn xóa sản phẩm SKU "${prod.sku}" (${prod.productName})?',
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
            if (inStockCount > 0) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                ),
                child: Text(
                  'CẢNH BÁO: Hiện có $inStockCount sản phẩm đang tồn kho thực tế gắn với SKU này! Thao tác xóa sẽ đồng bộ và giải phóng các bản ghi liên quan.',
                  style: const TextStyle(color: Color(0xFFEF4444), fontSize: 11.5, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('HỦY', style: TextStyle(color: c.textMuted, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('XÓA SẢN PHẨM', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _repo.deleteProduct(prod.productId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('✓ Đã xóa sản phẩm "${prod.sku}" thành công.'),
          ),
        );
      }
    }
  }

  void _exportProductsToCsv() {
    final products = _getFilteredProducts();
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không có sản phẩm nào để xuất.')),
      );
      return;
    }

    final buffer = StringBuffer();
    // Thêm UTF-8 BOM cho Excel
    buffer.write('\uFEFF');
    buffer.writeln('STT,Mã SKU,Tên Sản Phẩm,Danh Mục,Đơn Vị Tính,Tồn Kho Thực Tế,Mô Tả');

    for (int i = 0; i < products.length; i++) {
      final p = products[i];
      final stock = _getStockForSku(p.sku);
      final desc = (p.description ?? '').replaceAll(',', ' ').replaceAll('\n', ' ');
      buffer.writeln('${i + 1},"${p.sku}","${p.productName}","${p.category}","${p.unit}",$stock,"$desc"');
    }

    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF10B981),
        content: Text('✓ Đã sao chép dữ liệu CSV của ${products.length} sản phẩm vào bộ nhớ tạm (Clipboard).'),
      ),
    );
  }

  Future<void> _showCreateInboundOrderDialog(Product prod) async {
    final c = _eyeCare.colors;
    final now = DateTime.now();
    final defaultOrderNo = 'PN-${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}-${(now.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}';

    final orderNoCtrl = TextEditingController(text: defaultOrderNo);
    final supplierCtrl = TextEditingController(text: 'Nhà cung cấp tổng hợp');
    final palletCtrl = TextEditingController(text: 'PL01');
    final qtyCtrl = TextEditingController(text: '10');

    int inboundQty = 10;
    bool autoGenerateEpcs = true;
    bool navigateToInbound = true;
    String? errorMsg;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: c.bgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: c.border),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: c.rfidCyan.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
                    ),
                    child: Icon(Icons.playlist_add_check_circle_rounded, color: c.rfidCyan, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TẠO PHIẾU NHẬP KHO',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Lập lệnh nhập kho cho sản phẩm "${prod.sku}" và nạp vào hệ thống',
                          style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(dialogCtx),
                    icon: Icon(Icons.close, color: c.textSecondary, size: 20),
                    tooltip: 'Đóng',
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
                      // Thẻ thông tin sản phẩm đã chọn
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.bgCardElevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.borderLight),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: c.rfidCyan.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.inventory_2_rounded, color: c.rfidCyan, size: 24),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: c.rfidCyan.withValues(alpha: 0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          prod.sku,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            color: c.rfidCyan,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        prod.unit,
                                        style: TextStyle(color: c.textSecondary, fontSize: 11),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    prod.productName,
                                    style: TextStyle(
                                      color: c.textPrimary,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Thông tin phiếu
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: orderNoCtrl,
                              style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                labelText: 'Mã phiếu nhập (*)',
                                labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                                prefixIcon: const Icon(Icons.receipt_long_rounded, size: 18),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: palletCtrl,
                              style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                              decoration: InputDecoration(
                                labelText: 'Mã Pallet (tùy chọn)',
                                labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                                hintText: 'VD: PL01',
                                prefixIcon: const Icon(Icons.layers_rounded, size: 18),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Nhà cung cấp
                      TextField(
                        controller: supplierCtrl,
                        style: TextStyle(color: c.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Nhà cung cấp',
                          labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                          prefixIcon: const Icon(Icons.storefront_rounded, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          isDense: true,
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Số lượng nhập
                      Text(
                        'SỐ LƯỢNG CẦN NHẬP (${prod.unit.toUpperCase()}):',
                        style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: c.bgCardElevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: c.border),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 22),
                              color: c.textSecondary,
                              tooltip: 'Giảm 1',
                              onPressed: () {
                                if (inboundQty > 1) {
                                  setDialogState(() {
                                    inboundQty--;
                                    qtyCtrl.text = '$inboundQty';
                                  });
                                }
                              },
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: qtyCtrl,
                                textAlign: TextAlign.center,
                                keyboardType: TextInputType.number,
                                style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  isDense: true,
                                ),
                                onChanged: (val) {
                                  final n = int.tryParse(val.trim());
                                  if (n != null && n > 0) {
                                    setDialogState(() => inboundQty = n);
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 22),
                              color: c.rfidCyan,
                              tooltip: 'Tăng 1',
                              onPressed: () {
                                setDialogState(() {
                                  inboundQty++;
                                  qtyCtrl.text = '$inboundQty';
                                });
                              },
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: c.rfidCyan.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                prod.unit,
                                style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Tùy chọn Checkbox sinh RFID
                      Material(
                        color: c.bgCardElevated,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: autoGenerateEpcs
                                ? c.rfidCyan.withValues(alpha: 0.4)
                                : c.borderLight,
                          ),
                        ),
                        child: CheckboxListTile(
                          value: autoGenerateEpcs,
                          activeColor: c.rfidCyan,
                          title: Text(
                            'Tự động sinh mã RFID chip (EPC) cho lô hàng',
                            style: TextStyle(
                              color: c.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                          subtitle: Text(
                            'Gán $inboundQty thẻ RFID (trạng thái Chờ Nhập) sẵn sàng quét qua cổng hoặc PDA',
                            style: TextStyle(color: c.textSecondary, fontSize: 11),
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          dense: true,
                          onChanged: (val) => setDialogState(() => autoGenerateEpcs = val ?? true),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Tùy chọn chuyển tab sang Nhập Kho
                      if (widget.onNavigateToInbound != null)
                        Material(
                          color: c.bgCardElevated,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(color: c.borderLight),
                          ),
                          child: CheckboxListTile(
                            value: navigateToInbound,
                            activeColor: c.rfidCyan,
                            title: Text(
                              'Chuyển sang màn hình Nhập Kho ngay sau khi tạo',
                              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w600, fontSize: 12.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                            dense: true,
                            onChanged: (val) => setDialogState(() => navigateToInbound = val ?? true),
                          ),
                        ),

                      if (errorMsg != null) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(errorMsg!, style: const TextStyle(color: Color(0xFFEF4444), fontSize: 12)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting ? null : () => Navigator.pop(dialogCtx),
                  child: Text('HỦY', style: TextStyle(color: c.textMuted, fontWeight: FontWeight.bold)),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.rfidCyan,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: isSubmitting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline_rounded, size: 18),
                  label: Text(
                    isSubmitting ? 'ĐANG TẠO...' : 'XÁC NHẬN TẠO PHIẾU',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  onPressed: isSubmitting ? null : () async {
                    final ordNo = orderNoCtrl.text.trim().toUpperCase();
                    if (ordNo.isEmpty) {
                      setDialogState(() => errorMsg = 'Vui lòng nhập mã phiếu nhập.');
                      return;
                    }

                    final parsedQty = int.tryParse(qtyCtrl.text.trim()) ?? inboundQty;
                    if (parsedQty <= 0) {
                      setDialogState(() => errorMsg = 'Số lượng nhập phải lớn hơn 0.');
                      return;
                    }

                    setDialogState(() {
                      isSubmitting = true;
                      errorMsg = null;
                    });

                    try {
                      final supp = supplierCtrl.text.trim().isNotEmpty
                          ? supplierCtrl.text.trim()
                          : 'Nhà cung cấp tổng hợp';
                      final palCode = palletCtrl.text.trim().toUpperCase();

                      final order = InboundOrder(
                        inboundOrderId: ordNo,
                        orderNo: ordNo,
                        sourceSupplier: supp,
                        status: InboundOrderStatus.newOrder,
                        createdAt: DateTime.now(),
                        details: [
                          InboundOrderDetail(
                            productId: prod.productId,
                            sku: prod.sku,
                            productName: prod.productName,
                            requiredQty: parsedQty,
                            receivedQty: 0,
                          ),
                        ],
                      );

                      // Lưu InboundOrder và sinh mã thẻ RFID nếu chọn
                      final items = await _repo.addInboundOrder(
                        order,
                        autoGenerateEpcs: autoGenerateEpcs,
                        palletCode: palCode.isNotEmpty ? palCode : null,
                      );

                      if (mounted) {
                        Navigator.pop(dialogCtx);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: const Color(0xFF10B981),
                            content: Text(
                              autoGenerateEpcs
                                  ? '✓ Đã tạo thành công phiếu nhập "$ordNo" gồm $parsedQty ${prod.unit} (${items.length} thẻ RFID sẵn sàng qua cổng)!'
                                  : '✓ Đã tạo thành công phiếu nhập "$ordNo" gồm $parsedQty ${prod.unit}!',
                            ),
                          ),
                        );

                        if (navigateToInbound && widget.onNavigateToInbound != null) {
                          widget.onNavigateToInbound!();
                        }
                      }
                    } catch (e) {
                      setDialogState(() {
                        isSubmitting = false;
                        errorMsg = 'Lỗi tạo phiếu nhập: $e';
                      });
                    }
                  },
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
    final allProducts = _repo.products;
    final inStockTotal = _repo.items.where((i) => i.status == ItemStatus.inStock).length;
    final inStockSkuCount = allProducts.where((p) => _getStockForSku(p.sku) > 0).length;
    final categories = _getAllCategories();
    final filtered = _getFilteredProducts();

    return Container(
      color: c.bgDeep,
      child: Column(
        children: [
          // 1. Unified Header Bar
          _buildHeaderBar(c, categories),

          // 2. Metrics Bar
          _buildMetricsBar(
            c: c,
            totalSku: allProducts.length,
            totalStock: inStockTotal,
            inStockSku: inStockSkuCount,
            catCount: categories.length,
          ),

          // 3. Main Data Table
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Column(
                  children: [
                    // Table Header
                    _buildTableHeader(c),
                    Divider(height: 1, color: c.border),

                    // Table Body
                    Expanded(
                      child: filtered.isEmpty
                          ? _buildEmptyState(c)
                          : ListView.separated(
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: c.borderLight),
                              itemBuilder: (context, index) {
                                final p = filtered[index];
                                final stock = _getStockForSku(p.sku);
                                return _buildProductRow(p, index + 1, stock, c);
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderBar(EyeCareColors c, List<String> categories) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 1100;

          return Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: c.rfidCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
                ),
                child: Icon(Icons.inventory_2_rounded, color: c.rfidCyan, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'DANH MỤC SẢN PHẨM & QUẢN LÝ SKU',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Search Bar
              Container(
                width: isNarrow ? 180 : 260,
                height: 38,
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Icon(Icons.search_rounded, size: 16, color: c.textMuted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        style: TextStyle(color: c.textPrimary, fontSize: 12.5),
                        decoration: InputDecoration(
                          hintText: 'Tìm SKU, Tên, ĐVT...',
                          hintStyle: TextStyle(color: c.textMuted, fontSize: 11.5),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      ),
                    ),
                    if (_searchQuery.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _searchCtrl.clear();
                          setState(() => _searchQuery = '');
                        },
                        child: Icon(Icons.close_rounded, size: 14, color: c.textMuted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 10),

              // Category Filter Dropdown
              Container(
                height: 38,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: c.bgCardElevated,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    dropdownColor: c.bgCard,
                    style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                    icon: Icon(Icons.arrow_drop_down, color: c.textSecondary, size: 18),
                    items: [
                      const DropdownMenuItem(value: 'ALL', child: Text('Tất Cả Danh Mục')),
                      ...categories.map((cat) => DropdownMenuItem(value: cat, child: Text(cat))),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _selectedCategory = val);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 10),

              // Refresh Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.border),
                  foregroundColor: c.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('LÀM MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () async {
                  await _repo.refreshFromDatabase();
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(width: 8),

              // Export Excel Button
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: c.border),
                  foregroundColor: c.textPrimary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: const Text('XUẤT EXCEL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: _exportProductsToCsv,
              ),
              const SizedBox(width: 8),

              // Add Product Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.rfidCyan,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('THÊM SẢN PHẨM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                onPressed: () => _showAddOrEditProductDialog(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricsBar({
    required EyeCareColors c,
    required int totalSku,
    required int totalStock,
    required int inStockSku,
    required int catCount,
  }) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: _buildMetricCard('TỔNG SỐ SKU', '$totalSku', Icons.category_outlined, c.rfidCyan, c)),
          const SizedBox(width: 12),
          Expanded(child: _buildMetricCard('TỒN KHO THỰC TẾ', '$totalStock', Icons.layers_outlined, const Color(0xFF10B981), c)),
          const SizedBox(width: 12),
          Expanded(child: _buildMetricCard('SKU CÓ TỒN KHO', '$inStockSku', Icons.check_circle_outline_rounded, const Color(0xFF0284C7), c)),
          const SizedBox(width: 12),
          Expanded(child: _buildMetricCard('NHÓM DANH MỤC', '$catCount', Icons.grid_view_rounded, const Color(0xFFF59E0B), c)),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, IconData icon, Color color, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.3),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(color: c.textPrimary, fontSize: 18, fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTableHeader(EyeCareColors c) {
    return Container(
      color: c.bgCardElevated,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(width: 45, child: Text('STT', style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.bold))),
          const SizedBox(width: 12),
          SizedBox(width: 160, child: Text('MÃ SKU', style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
          Expanded(flex: 3, child: Text('TÊN SẢN PHẨM', style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
          SizedBox(width: 130, child: Text('DANH MỤC', style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
          SizedBox(width: 80, child: Text('ĐVT', style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
          SizedBox(width: 120, child: Text('TỒN KHO', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
          Expanded(flex: 2, child: Text('MÔ TẢ', style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.bold))),
          const SizedBox(width: 16),
          SizedBox(width: 140, child: Text('THAO TÁC', textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildProductRow(Product prod, int index, int stock, EyeCareColors c) {
    final hasStock = stock > 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 45,
            child: Text('$index', style: TextStyle(color: c.textSecondary, fontSize: 12)),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 160,
            child: Text(
              prod.sku,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: c.rfidCyan,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Text(
              prod.productName,
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 130,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: c.borderLight),
              ),
              child: Text(
                prod.category,
                style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w500),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 80,
            child: Text(
              prod.unit,
              style: TextStyle(color: c.textPrimary, fontSize: 12),
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 120,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: hasStock
                      ? const Color(0xFF10B981).withValues(alpha: 0.12)
                      : c.bgCardElevated,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: hasStock
                        ? const Color(0xFF10B981).withValues(alpha: 0.4)
                        : c.borderLight,
                  ),
                ),
                child: Text(
                  '$stock ${prod.unit}',
                  style: TextStyle(
                    color: hasStock ? const Color(0xFF10B981) : c.textMuted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Text(
              prod.description ?? '--',
              style: TextStyle(color: c.textMuted, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 16),
          SizedBox(
            width: 140,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.playlist_add_rounded, size: 19, color: c.rfidCyan),
                  tooltip: 'Tạo phiếu nhập từ sản phẩm này',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => _showCreateInboundOrderDialog(prod),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.edit_outlined, size: 17, color: c.textSecondary),
                  tooltip: 'Chỉnh sửa sản phẩm',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => _showAddOrEditProductDialog(existing: prod),
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 17, color: Color(0xFFEF4444)),
                  tooltip: 'Xóa sản phẩm',
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  onPressed: () => _confirmDeleteProduct(prod),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(EyeCareColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 48, color: c.textMuted),
            const SizedBox(height: 12),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Không tìm thấy sản phẩm nào khớp với từ khóa "$_searchQuery"'
                  : 'Chưa có sản phẩm nào trong danh mục',
              style: TextStyle(color: c.textSecondary, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Bấm nút [THÊM SẢN PHẨM] ở góc trên để tạo mới hoặc đồng bộ từ CSDL.',
              style: TextStyle(color: c.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
