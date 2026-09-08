import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/wms_models.dart';
import '../../services/warehouse_repository.dart';
import '../../services/uhf_service.dart';
import '../../theme/eye_care_theme.dart';

class PdaShelfStatusScreen extends StatefulWidget {
  const PdaShelfStatusScreen({super.key});

  @override
  State<PdaShelfStatusScreen> createState() => _PdaShelfStatusScreenState();
}

class _PdaShelfStatusScreenState extends State<PdaShelfStatusScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  StreamSubscription<String>? _barcodeSub;
  final TextEditingController _searchCtrl = TextEditingController();
  Location? _selectedLocation;
  String _selectedZoneFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onThemeUpdate);
    _repo.addListener(_onThemeUpdate);

    // Bật chế độ quét mã vạch Barcode trên máy PDA
    _uhf.setScanMode(PdaScanMode.barcode);
    _barcodeSub = _uhf.onBarcodeRead.listen(_handleScannedBarcode);

    // Mặc định chọn kệ đầu tiên nếu có
    if (_repo.locations.isNotEmpty) {
      _selectedLocation = _repo.locations.first;
    }
  }

  @override
  void dispose() {
    _barcodeSub?.cancel();
    _searchCtrl.dispose();
    _repo.removeListener(_onThemeUpdate);
    _eyeCare.removeListener(_onThemeUpdate);
    super.dispose();
  }

  void _onThemeUpdate() {
    if (mounted) setState(() {});
  }

  void _handleScannedBarcode(String rawBarcode) {
    final clean = rawBarcode.trim().toUpperCase();
    if (clean.isEmpty) return;

    final found = _repo.locations.where((l) =>
        l.locationCode.trim().toUpperCase() == clean ||
        l.locationId.trim().toUpperCase() == clean ||
        l.locationCode.replaceAll('-', '').toUpperCase() == clean.replaceAll('-', '')
    ).firstOrNull;

    if (found != null) {
      setState(() => _selectedLocation = found);
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF0284C7),
          duration: const Duration(seconds: 2),
          content: Text('📍 ĐÃ QUÉT MÃ KỆ: ${found.displayName} (${found.locationCode})'),
        ),
      );
    }
  }

  Future<void> _updateStatus(Location loc, String newStatus) async {
    HapticFeedback.heavyImpact();
    await _repo.updateLocationStatus(loc.locationId, newStatus);
    setState(() {
      loc.status = newStatus;
    });

    if (!mounted) return;
    String statusName = 'CÒN TRỐNG NHIỀU';
    Color snackColor = const Color(0xFF10B981);
    if (newStatus == 'FULL') {
      statusName = 'KỆ ĐẦY (FULL)';
      snackColor = const Color(0xFFEF4444);
    } else if (newStatus == 'NEAR_FULL') {
      statusName = 'SẮP HẾT CHỖ';
      snackColor = const Color(0xFFF59E0B);
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: snackColor,
        duration: const Duration(seconds: 2),
        content: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: Color(0xFF2C251E), size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Đã cập nhật ${loc.displayName} -> $statusName',
                style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final allLocations = _repo.locations;

    final zones = {'ALL', ...allLocations.map((l) => l.zone.trim()).where((z) => z.isNotEmpty)}.toList();

    final query = _searchCtrl.text.trim().toUpperCase();
    final filteredLocations = allLocations.where((loc) {
      if (_selectedZoneFilter != 'ALL' && !loc.zone.toUpperCase().contains(_selectedZoneFilter.toUpperCase())) {
        return false;
      }
      if (query.isNotEmpty) {
        final matchCode = loc.locationCode.toUpperCase().contains(query);
        final matchShelf = loc.displayName.toUpperCase().contains(query) || loc.shelf.toUpperCase().contains(query);
        final matchZone = loc.zone.toUpperCase().contains(query);
        if (!matchCode && !matchShelf && !matchZone) return false;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: AppBar(
        backgroundColor: c.bgDeep,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: c.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CẬP NHẬT TRẠNG THÁI KỆ',
              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
            ),
            Text(
              'Quét mã Barcode kệ hoặc chọn bên dưới',
              style: TextStyle(color: c.textMuted, fontSize: 11),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // 1. Khối Kệ Đang Chọn & 3 Nút Cập Nhật Lớn
            if (_selectedLocation != null)
              _buildSelectedShelfPanel(_selectedLocation!, c)
            else
              Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: [
                    Icon(Icons.barcode_reader, color: c.rfidCyan, size: 26),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Hãy quét mã vạch trên kệ bằng máy PDA hoặc chọn từ danh sách bên dưới.',
                        style: TextStyle(color: c.textSecondary, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // 2. Thanh tìm kiếm & Lọc Zone
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 38,
                      child: TextField(
                        controller: _searchCtrl,
                        style: TextStyle(color: c.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Tìm theo mã kệ, tầng, khu...',
                          hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                          prefixIcon: Icon(Icons.search, size: 18, color: c.textMuted),
                          filled: true,
                          fillColor: c.bgCard,
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: c.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: c.border),
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 38,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedZoneFilter,
                        dropdownColor: c.bgCard,
                        style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.bold),
                        items: zones.map((z) => DropdownMenuItem(value: z, child: Text(z == 'ALL' ? 'Tất cả' : z))).toList(),
                        onChanged: (val) {
                          if (val != null) setState(() => _selectedZoneFilter = val);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 3. Danh sách toàn bộ kệ kho
            Expanded(
              child: filteredLocations.isEmpty
                  ? Center(
                      child: Text('Không có kệ kho nào.', style: TextStyle(color: c.textMuted)),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      itemCount: filteredLocations.length,
                      itemBuilder: (ctx, idx) {
                        final loc = filteredLocations[idx];
                        final isSelected = _selectedLocation?.locationId == loc.locationId;
                        return _buildShelfListItem(loc, isSelected, c);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedShelfPanel(Location loc, EyeCareColors c) {
    Color statusColor = const Color(0xFF10B981);
    String statusLabel = 'CÒN TRỐNG NHIỀU';
    if (loc.status == 'FULL') {
      statusColor = const Color(0xFFEF4444);
      statusLabel = 'KỆ ĐẦY (FULL)';
    } else if (loc.status == 'NEAR_FULL') {
      statusColor = const Color(0xFFF59E0B);
      statusLabel = 'SẮP HẾT CHỖ';
    }

    final itemCount = _repo.items.where((i) {
      final itemLoc = i.locationId?.trim().toUpperCase();
      if (itemLoc == null || itemLoc.isEmpty) return false;
      return itemLoc == loc.locationCode.toUpperCase() || itemLoc == loc.locationId.toUpperCase();
    }).length;

    return Container(
      margin: const EdgeInsets.all(14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.shelves, color: statusColor, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.displayName,
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      loc.displaySubtitle,
                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            itemCount > 0 ? '📦 Đang chứa $itemCount chip RFID' : '📦 Kệ hiện đang trống',
            style: TextStyle(color: c.textMuted, fontSize: 11.5),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          Text(
            'CHỌN TRẠNG THÁI MỚI CHO KỆ NÀY:',
            style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.bold, letterSpacing: 0.5),
          ),
          const SizedBox(height: 8),

          // 3 Nút Bấm Lớn: ĐẦY / SẮP HẾT CHỖ / CÒN TRỐNG NHIỀU
          Row(
            children: [
              Expanded(
                child: _buildStatusUpdateButton(
                  label: 'KỆ ĐẦY',
                  statusValue: 'FULL',
                  color: const Color(0xFFEF4444),
                  icon: Icons.error_outline_rounded,
                  isSelected: loc.status == 'FULL',
                  onTap: () => _updateStatus(loc, 'FULL'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatusUpdateButton(
                  label: 'SẮP HẾT',
                  statusValue: 'NEAR_FULL',
                  color: const Color(0xFFF59E0B),
                  icon: Icons.warning_amber_rounded,
                  isSelected: loc.status == 'NEAR_FULL',
                  onTap: () => _updateStatus(loc, 'NEAR_FULL'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatusUpdateButton(
                  label: 'TRỐNG NHIỀU',
                  statusValue: 'AVAILABLE',
                  color: const Color(0xFF10B981),
                  icon: Icons.check_circle_outline_rounded,
                  isSelected: loc.status == 'AVAILABLE',
                  onTap: () => _updateStatus(loc, 'AVAILABLE'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusUpdateButton({
    required String label,
    required String statusValue,
    required Color color,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: isSelected ? color : color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color, width: isSelected ? 2 : 1),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? const Color(0xFF2C251E) : color,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? const Color(0xFF2C251E) : color,
                  fontWeight: FontWeight.bold,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShelfListItem(Location loc, bool isSelected, EyeCareColors c) {
    Color statusColor = const Color(0xFF10B981);
    String statusLabel = 'Còn trống nhiều';
    if (loc.status == 'FULL') {
      statusColor = const Color(0xFFEF4444);
      statusLabel = 'Kệ đầy';
    } else if (loc.status == 'NEAR_FULL') {
      statusColor = const Color(0xFFF59E0B);
      statusLabel = 'Sắp hết chỗ';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? c.rfidCyan.withValues(alpha: 0.1) : c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? c.rfidCyan : c.border,
          width: isSelected ? 1.8 : 1,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.shelves, color: statusColor, size: 20),
        ),
        title: Text(
          loc.displayName,
          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5),
        ),
        subtitle: Text(
          loc.displaySubtitle,
          style: TextStyle(color: c.textSecondary, fontSize: 11),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: statusColor.withValues(alpha: 0.7)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 6, height: 6, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
              const SizedBox(width: 4),
              Text(
                statusLabel,
                style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 10.5),
              ),
            ],
          ),
        ),
        onTap: () {
          setState(() => _selectedLocation = loc);
        },
      ),
    );
  }
}
