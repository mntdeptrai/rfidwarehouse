import 'package:flutter/material.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';

class DesktopLookupView extends StatefulWidget {
  const DesktopLookupView({super.key});

  @override
  State<DesktopLookupView> createState() => _DesktopLookupViewState();
}

class _DesktopLookupViewState extends State<DesktopLookupView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final TextEditingController _queryController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _eyeCare.removeListener(_onThemeChanged);
    _queryController.dispose();
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final filteredItems = _repo.items.where((i) {
      if (_searchQuery.isEmpty) return true;
      final q = _searchQuery.toLowerCase();
      return i.serialNumber.toLowerCase().contains(q) ||
          i.epc.toLowerCase().contains(q) ||
          i.sku.toLowerCase().contains(q) ||
          i.productName.toLowerCase().contains(q);
    }).toList();

    return Container(
      color: c.bgDeep,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Text(
            'LOOKUP & SERIAL MANAGEMENT',
            style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
          ),
          const SizedBox(height: 4),
          Text(
            'Tra Cứu Mã Serial, Thùng Carton & Thẻ RFID',
            style: TextStyle(color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),

          // Search Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: c.bgCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.rfidCyan),
            ),
            child: TextField(
              controller: _queryController,
              style: TextStyle(color: c.textPrimary),
              decoration: InputDecoration(
                icon: Icon(Icons.search, color: c.rfidCyan),
                hintText: 'Nhập mã Serial, EPC tag, Barcode hoặc tên sản phẩm...',
                hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
                border: InputBorder.none,
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear, color: c.textSecondary, size: 18),
                        onPressed: () {
                          _queryController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (val) => setState(() => _searchQuery = val.trim()),
            ),
          ),
          const SizedBox(height: 20),

          // Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: filteredItems.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.search_off, size: 56, color: c.textMuted),
                          const SizedBox(height: 12),
                          Text(
                            _searchQuery.isEmpty ? 'Chưa có mặt hàng nào trong cơ sở dữ liệu.' : 'Không tìm thấy kết quả cho "$_searchQuery"',
                            style: TextStyle(color: c.textSecondary, fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredItems.length,
                      separatorBuilder: (_, index) => Divider(color: c.border, height: 1),
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        final pallet = _repo.pallets.where((p) => p.palletId == item.palletId).firstOrNull;
                        final loc = pallet != null ? _repo.locations.where((l) => l.locationId == pallet.locationId).firstOrNull : null;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: c.rfidCyan.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.qr_code, color: c.rfidCyan, size: 20),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.productName, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text('Serial: ${item.serialNumber} • SKU: ${item.sku}', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('EPC: ${item.epc}', style: TextStyle(color: c.rfidCyan, fontFamily: 'Courier', fontSize: 11)),
                                    const SizedBox(height: 2),
                                    Text('Thùng: ${pallet?.palletCode ?? "N/A"} • Vị trí: ${loc?.locationCode ?? "N/A"}', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.status.name.toUpperCase(),
                                  style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 10),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
