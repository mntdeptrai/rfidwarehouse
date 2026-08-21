import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/wms_models.dart';
import '../services/uhf_service.dart';
import '../services/warehouse_repository.dart';
import '../theme/eye_care_theme.dart';

/// Widget chuyên dụng cho thiết bị cầm tay PDA:
/// Quét mã vạch Barcode/QR để xác nhận vị trí kệ/ô lưu hàng (Location)
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
    Location matched;
    final found = _repo.locations.where((l) =>
        l.locationCode.trim().toUpperCase() == upper ||
        l.locationId.trim().toUpperCase() == upper ||
        l.locationCode.replaceAll('-', '').toUpperCase() == upper.replaceAll('-', '')
    ).firstOrNull;

    if (found == null) {
      // Phân tích mã vạch vị trí thực tế được quét từ kệ kho
      final parts = clean.split('-');
      String zoneName = 'Khu vực chung';
      String shelfName = 'Kệ';
      String levelName = 'Tầng';

      if (parts.length >= 4 && parts[0].toUpperCase() == 'LOC') {
        zoneName = 'Khu ${parts[1]}';
        shelfName = 'Kệ ${parts[2]}';
        levelName = 'Tầng ${parts[3]}';
      } else if (parts.length == 3) {
        zoneName = 'Khu ${parts[0]}';
        shelfName = 'Kệ ${parts[1]}';
        levelName = 'Tầng ${parts[2]}';
      } else if (parts.length == 2) {
        zoneName = 'Khu ${parts[0]}';
        shelfName = 'Kệ ${parts[1]}';
        levelName = 'Tầng 1';
      }

      matched = Location(
        locationId: 'LOC-$upper',
        locationCode: clean,
        zone: zoneName,
        shelf: shelfName,
        level: levelName,
      );
      await _repo.addLocation(matched);
    } else {
      matched = found;
    }

    HapticFeedback.heavyImpact();
    widget.onLocationChanged(matched);

    if (mounted) {
      final c = _eyeCare.colors;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: c.successEmerald,
          duration: const Duration(seconds: 2),
          content: Row(
            children: [
              const Icon(Icons.qr_code_scanner, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('✓ Đã xác nhận vị trí kệ: ${matched.locationCode} (${matched.zone})'),
              ),
            ],
          ),
        ),
      );
    }
  }

  void _openBarcodeScannerModal() {
    final barcodeController = TextEditingController();
    final focusNode = FocusNode();
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
            final locations = _repo.locations;

            return Padding(
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
                  Row(
                    children: [
                      Icon(Icons.qr_code_scanner, color: c.rfidCyan, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'QUÉT BARCODE VỊ TRÍ KỆ',
                          style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 15),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: c.textMuted, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: () => Navigator.pop(modalContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.rfidCyan.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.bolt, color: c.rfidCyan, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Bóp cò Barcode trên tay cầm PDA hoặc gõ mã vị trí để xác nhận ngay.',
                            style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Input Box with Auto-Focus for Hardware Barcode Scanners / Wedge
                  TextField(
                    controller: barcodeController,
                    focusNode: focusNode,
                    autofocus: true,
                    style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'Nhập hoặc quét mã vạch kệ (VD: LOC-A01-01)...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                      filled: true,
                      fillColor: c.bgCardElevated,
                      prefixIcon: Icon(Icons.barcode_reader, color: c.rfidCyan),
                      suffixIcon: IconButton(
                        icon: Icon(Icons.check_circle, color: c.successEmerald),
                        onPressed: () {
                          final code = barcodeController.text.trim();
                          if (code.isNotEmpty) {
                            Navigator.pop(modalContext);
                            _handleScannedBarcode(code);
                          }
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.rfidCyan),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide(color: c.border),
                      ),
                    ),
                    onSubmitted: (val) {
                      if (val.trim().isNotEmpty) {
                        Navigator.pop(modalContext);
                        _handleScannedBarcode(val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),

                  // Hardware Trigger Trigger Button
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: c.rfidCyan,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          icon: const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 18),
                          label: const Text(
                            'BÓP CÒ QUÉT 2D/LASER',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                          onPressed: () async {
                            await _uhf.triggerBarcodeScan();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Quick Select List from Database
                  if (locations.isNotEmpty) ...[
                    Text(
                      'Hoặc chọn nhanh từ danh mục kệ có sẵn:',
                      style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: locations.length,
                        separatorBuilder: (context, index) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final loc = locations[index];
                          final isSelected = loc.locationId == widget.selectedLocationId;

                          return InkWell(
                            onTap: () {
                              Navigator.pop(modalContext);
                              widget.onLocationChanged(loc);
                              HapticFeedback.selectionClick();
                            },
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? c.rfidCyan.withValues(alpha: 0.2) : c.bgCard,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isSelected ? c.rfidCyan : c.border,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSelected ? Icons.check_circle : Icons.location_on_outlined,
                                    color: isSelected ? c.successEmerald : c.rfidCyan,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      loc.locationCode,
                                      style: TextStyle(
                                        color: isSelected ? c.rfidCyan : c.textPrimary,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${loc.zone} • ${loc.shelf}',
                                    style: TextStyle(color: c.textMuted, fontSize: 11),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = _repo.locations.where((l) => l.locationId == widget.selectedLocationId).firstOrNull;
    final c = _eyeCare.colors;

    return InkWell(
      onTap: _openBarcodeScannerModal,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: location != null ? c.successEmerald.withValues(alpha: 0.8) : c.rfidCyan.withValues(alpha: 0.6),
            width: 1.2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (location != null ? c.successEmerald : c.rfidCyan).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                location != null ? Icons.qr_code_2 : Icons.barcode_reader,
                color: location != null ? c.successEmerald : c.rfidCyan,
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 2,
                    children: [
                      Text(
                        location != null ? 'VỊ TRÍ KỆ (ĐÃ XÁC NHẬN)' : 'VỊ TRÍ KỆ ĐÍCH',
                        style: TextStyle(
                          color: location != null ? c.successEmerald : c.rfidCyan,
                          fontWeight: FontWeight.bold,
                          fontSize: 10.5,
                          letterSpacing: 0.3,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: (location != null ? c.successEmerald : c.rfidCyan).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          location != null ? 'BARCODE OK' : '📷 BÓP CÒ QUÉT',
                          style: TextStyle(
                            color: location != null ? c.successEmerald : c.rfidCyan,
                            fontSize: 8.5,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  if (location != null) ...[
                    Text(
                      location.locationCode,
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${location.zone} • ${location.shelf} - ${location.level}',
                      style: TextStyle(color: c.textSecondary, fontSize: 10.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ] else ...[
                    Text(
                      'Chưa quét mã vạch (Chạm hoặc bóp cò để quét)',
                      style: TextStyle(color: c.textMuted, fontSize: 11.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.qr_code_scanner,
              color: location != null ? c.successEmerald : c.rfidCyan,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
