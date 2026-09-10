import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/wms_models.dart';
import '../../models/tag_info.dart';
import '../../services/auth_service.dart';
import '../../services/uhf_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';
import '../../widgets/hardware_status_appbar.dart';

class PdaTransferScreen extends StatefulWidget {
  const PdaTransferScreen({super.key});

  @override
  State<PdaTransferScreen> createState() => _PdaTransferScreenState();
}

class _PdaTransferScreenState extends State<PdaTransferScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final AuthService _auth = AuthService();

  String? _selectedLocationId;
  StreamSubscription<TagInfo>? _rfidSub;

  // Trạng thái quét
  String? _scannedEpc;
  Pallet? _foundPallet;
  List<Item> _palletItems = [];
  String? _errorMessage;
  bool _isProcessing = false;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    _selectedLocationId =
        _repo.locations.isNotEmpty ? _repo.locations.first.locationId : null;
    _eyeCare.addListener(_onStateChange);
    _repo.addListener(_onStateChange);
    _uhf.setScanMode(PdaScanMode.rfid);

    _rfidSub = _uhf.onTagRead.listen((tag) {
      _handleScannedEpc(tag.epc);
    });
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _rfidSub?.cancel();
    _eyeCare.removeListener(_onStateChange);
    _repo.removeListener(_onStateChange);
    super.dispose();
  }

  void _handleScannedEpc(String epc) {
    if (_isProcessing || _isSuccess) return;
    final cleanEpc = epc.trim().toUpperCase();
    if (cleanEpc.isEmpty) return;

    // Tìm pallet theo rfidEpc hoặc palletId
    final pallet = _repo.pallets.where((p) {
      return (p.rfidEpc ?? '').toUpperCase() == cleanEpc ||
          p.palletId.toUpperCase() == cleanEpc;
    }).firstOrNull;

    final items = pallet != null
        ? _repo.items
            .where((it) =>
                it.palletId == pallet.palletId ||
                it.palletId == pallet.palletCode)
            .toList()
        : <Item>[];

    setState(() {
      _scannedEpc = cleanEpc;
      _foundPallet = pallet;
      _palletItems = items;
      _errorMessage = pallet == null ? 'Không tìm thấy đơn hàng / pallet với mã chip: $cleanEpc' : null;
      _isSuccess = false;
    });
  }

  Future<void> _confirmTransfer() async {
    if (_foundPallet == null || _selectedLocationId == null) return;
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final performedBy = _auth.currentUser?.fullName ??
          _auth.currentUser?.username ??
          'Thủ kho PDA';

      final count = await _repo.transferPalletToLocation(
        palletEpc: _foundPallet!.palletId,
        newLocationId: _selectedLocationId!,
        performedBy: performedBy,
      );

      final newLoc = _repo.locations
          .where((l) => l.locationId == _selectedLocationId)
          .firstOrNull;
      final locDisplay = newLoc?.locationCode ?? _selectedLocationId!;

      setState(() {
        _isProcessing = false;
        _isSuccess = true;
        _errorMessage = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text(
                '✓ Đã chuyển ${_foundPallet!.palletCode} ($count sản phẩm) → Vị trí $locDisplay'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Lỗi khi chuyển kho: $e';
      });
    }
  }

  void _reset() {
    setState(() {
      _scannedEpc = null;
      _foundPallet = null;
      _palletItems = [];
      _errorMessage = null;
      _isProcessing = false;
      _isSuccess = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final locations = _repo.locations;
    final selectedLoc =
        locations.where((l) => l.locationId == _selectedLocationId).firstOrNull;

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: HardwareStatusAppBar(
        title: 'Chuyển Kho',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Bước 1: Chọn kho đích ----
            _buildStepCard(
              c: c,
              step: '1',
              title: 'Chọn vị trí kho đích',
              color: c.rfidCyan,
              child: locations.isEmpty
                  ? Text(
                      'Chưa có vị trí kho nào trong hệ thống.',
                      style: TextStyle(color: c.textMuted, fontSize: 13),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: c.bgDeep,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: c.rfidCyan.withValues(alpha: 0.5)),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedLocationId,
                          isExpanded: true,
                          dropdownColor: c.bgCard,
                          style: TextStyle(
                              color: c.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold),
                          items: locations.map((loc) {
                            return DropdownMenuItem<String>(
                              value: loc.locationId,
                              child: Text(
                                '${loc.locationCode}  (Khu ${loc.zone} – Kệ ${loc.shelf})',
                                style: TextStyle(
                                    color: c.textPrimary, fontSize: 14),
                              ),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() {
                              _selectedLocationId = val;
                              // Reset kết quả quét khi đổi vị trí
                              _scannedEpc = null;
                              _foundPallet = null;
                              _palletItems = [];
                              _isSuccess = false;
                              _errorMessage = null;
                            });
                          },
                        ),
                      ),
                    ),
            ),

            const SizedBox(height: 14),

            // ---- Bước 2: Quét RFID ----
            _buildStepCard(
              c: c,
              step: '2',
              title: 'Quét chip RFID của pallet / đơn hàng',
              color: const Color(0xFFF59E0B),
              child: Column(
                children: [
                  // Hiển thị trạng thái quét
                  if (_scannedEpc == null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 12),
                      decoration: BoxDecoration(
                        color: c.bgDeep,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: c.border.withValues(alpha: 0.5),
                            style: BorderStyle.solid),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.nfc, color: c.textMuted, size: 28),
                          const SizedBox(width: 12),
                          Text(
                            'Bóp cò để quét RFID...',
                            style: TextStyle(
                                color: c.textMuted,
                                fontSize: 14,
                                fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    )
                  else ...[
                    // EPC đã quét
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: c.bgDeep,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: (_foundPallet != null
                                    ? const Color(0xFF10B981)
                                    : c.errorCoral)
                                .withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.nfc,
                              color: _foundPallet != null
                                  ? const Color(0xFF10B981)
                                  : c.errorCoral,
                              size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _scannedEpc!,
                              style: TextStyle(
                                  color: c.rfidCyan,
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                  fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.close, color: c.textMuted, size: 18),
                            onPressed: _reset,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Kết quả tìm kiếm
                    if (_errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: c.errorCoral.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: c.errorCoral.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline,
                                color: c.errorCoral, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_errorMessage!,
                                  style: TextStyle(
                                      color: c.errorCoral, fontSize: 13)),
                            ),
                          ],
                        ),
                      )
                    else if (_foundPallet != null)
                      _buildPalletInfo(c),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 14),

            // ---- Bước 3: Xác nhận ----
            if (_foundPallet != null && !_isSuccess) ...[
              _buildStepCard(
                c: c,
                step: '3',
                title: 'Xác nhận chuyển kho',
                color: const Color(0xFF10B981),
                child: Column(
                  children: [
                    // Tóm tắt
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color: const Color(0xFF10B981).withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          _buildSummaryRow(
                            c: c,
                            label: 'Pallet',
                            value: _foundPallet!.palletCode,
                            valueColor: c.rfidCyan,
                          ),
                          const SizedBox(height: 6),
                          _buildSummaryRow(
                            c: c,
                            label: 'Số sản phẩm',
                            value: '${_palletItems.length} items',
                          ),
                          const SizedBox(height: 6),
                          _buildSummaryRow(
                            c: c,
                            label: 'Vị trí mới',
                            value: selectedLoc?.locationCode ?? _selectedLocationId ?? '',
                            valueColor: const Color(0xFF10B981),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.swap_horiz_rounded,
                                color: Colors.white),
                        label: Text(
                          _isProcessing ? 'Đang xử lý...' : 'XÁC NHẬN CHUYỂN KHO',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14),
                        ),
                        onPressed: _isProcessing ? null : _confirmTransfer,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ---- Kết quả thành công ----
            if (_isSuccess) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: const Color(0xFF10B981).withValues(alpha: 0.4)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF10B981), size: 48),
                    const SizedBox(height: 10),
                    Text(
                      'Chuyển kho thành công!',
                      style: TextStyle(
                          color: c.textPrimary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pallet ${_foundPallet?.palletCode} → ${selectedLoc?.locationCode ?? _selectedLocationId}',
                      style: TextStyle(color: c.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: c.rfidCyan),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(Icons.refresh, color: c.rfidCyan),
                        label: Text(
                          'Quét tiếp pallet khác',
                          style: TextStyle(
                              color: c.rfidCyan, fontWeight: FontWeight.bold),
                        ),
                        onPressed: _reset,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPalletInfo(EyeCareColors c) {
    final oldLoc = _foundPallet!.locationId != null
        ? _repo.locations
            .where((l) => l.locationId == _foundPallet!.locationId)
            .firstOrNull
        : null;
    final oldLocDisplay =
        oldLoc?.locationCode ?? (_foundPallet!.locationId ?? 'Chưa có vị trí');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pallet, color: const Color(0xFF10B981), size: 18),
              const SizedBox(width: 8),
              Text(
                _foundPallet!.palletCode,
                style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${_palletItems.length} sản phẩm',
                    style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.location_on_outlined,
                  color: c.textMuted, size: 14),
              const SizedBox(width: 4),
              Text('Vị trí hiện tại: ',
                  style: TextStyle(color: c.textSecondary, fontSize: 12)),
              Text(oldLocDisplay,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          if (_palletItems.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Danh sách hàng hóa:',
                style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            ...(_palletItems.take(5).map((it) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      Icon(Icons.circle, color: c.textMuted, size: 6),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${it.productName}  •  SKU: ${it.sku}',
                          style:
                              TextStyle(color: c.textPrimary, fontSize: 11.5),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ))),
            if (_palletItems.length > 5)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '... và ${_palletItems.length - 5} sản phẩm khác',
                  style: TextStyle(
                      color: c.textMuted,
                      fontSize: 11,
                      fontStyle: FontStyle.italic),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow({
    required EyeCareColors c,
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(color: c.textSecondary, fontSize: 13)),
        Text(value,
            style: TextStyle(
                color: valueColor ?? c.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStepCard({
    required EyeCareColors c,
    required String step,
    required String title,
    required Color color,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(step,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: child,
          ),
        ],
      ),
    );
  }
}
