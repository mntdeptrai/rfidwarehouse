import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/wms_models.dart';
import '../services/uhf_service.dart';
import '../services/warehouse_repository.dart';
import '../theme/eye_care_theme.dart';

/// Widget chuyên dụng cho thiết bị cầm tay PDA & Desktop:
/// Chọn nhanh hoặc quét vị trí kệ/ô lưu hàng (Location Selector)
class PdaLocationBarcodeCard extends StatefulWidget {
  final String? selectedLocationId;
  final ValueChanged<Location> onLocationChanged;
  final bool autoListenHardwareBarcode;

  const PdaLocationBarcodeCard({
    super.key,
    required this.selectedLocationId,
    required this.onLocationChanged,
    this.autoListenHardwareBarcode = true,
  });

  @override
  State<PdaLocationBarcodeCard> createState() => _PdaLocationBarcodeCardState();
}

class _PdaLocationBarcodeCardState extends State<PdaLocationBarcodeCard> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  StreamSubscription<String>? _barcodeSub;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onThemeUpdate);
    if (widget.autoListenHardwareBarcode) {
      _startBarcodeListener();
    }
  }

  void _onThemeUpdate() {
    if (mounted) setState(() {});
  }

  void _startBarcodeListener() {
    _barcodeSub?.cancel();
    _barcodeSub = _uhf.onBarcodeRead.listen((barcode) {
      if (!mounted) return;
      _handleScannedBarcode(barcode);
    });
  }

  @override
  void dispose() {
    _eyeCare.removeListener(_onThemeUpdate);
    _barcodeSub?.cancel();
    super.dispose();
  }

  Future<void> _handleScannedBarcode(String rawBarcode) async {
    final clean = rawBarcode.trim();
    if (clean.isEmpty) return;

    final upper = clean.toUpperCase();
    final found = _repo.locations.where((l) =>
        l.locationCode.trim().toUpperCase() == upper ||
        l.locationId.trim().toUpperCase() == upper ||
        l.locationCode.replaceAll('-', '').toUpperCase() == upper.replaceAll('-', '')
    ).firstOrNull;

    if (found == null) {
      // Không phải mã vị trí kệ kho hợp lệ -> Bỏ qua, tuyệt đối không chèn mã thẻ RFID/sản phẩm vào danh mục vị trí
      return;
    }

    HapticFeedback.selectionClick();
    widget.onLocationChanged(found);

    if (mounted) {
      final c = _eyeCare.colors;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: c.successEmerald,
          duration: const Duration(seconds: 2),
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('✓ Đã chọn vị trí: ${found.locationCode} (Khu ${found.zone})'),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _openLocationSelectorModal() {
    final searchController = TextEditingController();
    String selectedZoneFilter = 'ALL';
    final c = _eyeCare.colors;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bgDeep,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: c.rfidCyan, width: 1.5),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (modalContext, setModalState) {
            final allLocations = _repo.locations;
            final query = searchController.text.trim().toUpperCase();

            final filteredLocations = allLocations.where((loc) {
              if (selectedZoneFilter != 'ALL') {
                if (selectedZoneFilter == 'A' && !loc.zone.toUpperCase().contains('A') && !loc.locationCode.contains('A1')) {
                  return false;
                }
                if (selectedZoneFilter == 'B' && !loc.zone.toUpperCase().contains('B') && !loc.locationCode.contains('B1')) {
                  return false;
                }
                if (selectedZoneFilter == 'GATE' && !loc.zone.toUpperCase().contains('GATE') && !loc.locationCode.contains('GATE')) {
                  return false;
                }
              }
              if (query.isNotEmpty) {
                return loc.locationCode.toUpperCase().contains(query) ||
                    loc.zone.toUpperCase().contains(query) ||
                    loc.shelf.toUpperCase().contains(query) ||
                    loc.level.toUpperCase().contains(query);
              }
              return true;
            }).toList();

            return Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(modalContext).size.height * 0.85,
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(modalContext).viewInsets.bottom + 16,
                left: 16,
                right: 16,
                top: 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tiêu đề
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: c.rfidCyan.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.shelves, color: c.rfidCyan, size: 22),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'CHỌN VỊ TRÍ KỆ KHO',
                              style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              'Danh sách ${allLocations.length} vị trí kệ sẵn sàng',
                              style: TextStyle(color: c.textMuted, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: c.textMuted, size: 22),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(modalContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Thanh tìm kiếm nhanh
                  TextField(
                    controller: searchController,
                    style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'Tìm kiếm vị trí (A1, B1, GATE, Tầng...)',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                      filled: true,
                      fillColor: c.bgCardElevated,
                      prefixIcon: Icon(Icons.search, color: c.rfidCyan, size: 20),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: Icon(Icons.clear, color: c.textMuted, size: 18),
                              onPressed: () {
                                searchController.clear();
                                setModalState(() {});
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.rfidCyan, width: 1.5),
                      ),
                    ),
                    onChanged: (_) => setModalState(() {}),
                  ),
                  const SizedBox(height: 10),

                  // Filter Chips theo Zone
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip(
                          label: 'Tất cả (${allLocations.length})',
                          isSelected: selectedZoneFilter == 'ALL',
                          c: c,
                          onTap: () => setModalState(() => selectedZoneFilter = 'ALL'),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          label: 'Khu A1 (4 kệ)',
                          isSelected: selectedZoneFilter == 'A',
                          c: c,
                          onTap: () => setModalState(() => selectedZoneFilter = 'A'),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          label: 'Khu B1 (2 kệ)',
                          isSelected: selectedZoneFilter == 'B',
                          c: c,
                          onTap: () => setModalState(() => selectedZoneFilter = 'B'),
                        ),
                        const SizedBox(width: 8),
                        _buildFilterChip(
                          label: 'Cổng Gate (2)',
                          isSelected: selectedZoneFilter == 'GATE',
                          c: c,
                          onTap: () => setModalState(() => selectedZoneFilter = 'GATE'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Danh sách vị trí kệ
                  Expanded(
                    child: filteredLocations.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.location_off_outlined, color: c.textMuted, size: 40),
                                const SizedBox(height: 8),
                                Text(
                                  'Không tìm thấy vị trí phù hợp',
                                  style: TextStyle(color: c.textSecondary, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: filteredLocations.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 8),
                            itemBuilder: (context, index) {
                              final loc = filteredLocations[index];
                              final isSelected = loc.locationId == widget.selectedLocationId;

                              return InkWell(
                                onTap: () {
                                  Navigator.pop(modalContext);
                                  widget.onLocationChanged(loc);
                                  HapticFeedback.selectionClick();
                                },
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  decoration: BoxDecoration(
                                    color: isSelected ? c.rfidCyan.withValues(alpha: 0.18) : c.bgCard,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isSelected ? c.rfidCyan : c.border,
                                      width: isSelected ? 1.8 : 1.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? c.successEmerald.withValues(alpha: 0.2)
                                              : c.rfidCyan.withValues(alpha: 0.1),
                                          shape: BoxShape.circle,
                                        ),
                                        child: Icon(
                                          isSelected ? Icons.check_circle : Icons.shelves,
                                          color: isSelected ? c.successEmerald : c.rfidCyan,
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              loc.locationCode,
                                              style: TextStyle(
                                                color: isSelected ? c.rfidCyan : c.textPrimary,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 15,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Wrap(
                                              spacing: 6,
                                              children: [
                                                _buildInfoTag('Khu ${loc.zone}', c),
                                                _buildInfoTag('Kệ ${loc.shelf}', c),
                                                _buildInfoTag('Tầng ${loc.level}', c),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isSelected
                                              ? c.successEmerald.withValues(alpha: 0.2)
                                              : Colors.white10,
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          isSelected ? 'ĐANG CHỌN' : 'CHỌN',
                                          style: TextStyle(
                                            color: isSelected ? c.successEmerald : c.textSecondary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11,
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
            );
          },
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required EyeCareColors c,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan : c.bgCardElevated,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? c.rfidCyan : c.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : c.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoTag(String text, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: c.bgCardElevated,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      child: Text(
        text,
        style: TextStyle(color: c.textSecondary, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = _repo.locations.where((l) => l.locationId == widget.selectedLocationId).firstOrNull;
    final c = _eyeCare.colors;

    return InkWell(
      onTap: _openLocationSelectorModal,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: location != null ? c.rfidCyan.withValues(alpha: 0.8) : c.border,
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (location != null ? c.successEmerald : c.rfidCyan).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                location != null ? Icons.shelves : Icons.warehouse_rounded,
                color: location != null ? c.successEmerald : c.rfidCyan,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'VỊ TRÍ KỆ LƯU KHO',
                    style: TextStyle(
                      color: c.rfidCyan,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 3),
                  if (location != null) ...[
                    Text(
                      location.locationCode,
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Khu ${location.zone} • Kệ ${location.shelf} - Tầng ${location.level}',
                      style: TextStyle(color: c.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else ...[
                    Text(
                      'Chưa chọn vị trí kệ',
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Chạm vào để chọn từ danh mục kệ',
                      style: TextStyle(color: c.textMuted, fontSize: 11),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: c.rfidCyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.rfidCyan.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'CHỌN',
                    style: TextStyle(
                      color: c.rfidCyan,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down, color: c.rfidCyan, size: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
