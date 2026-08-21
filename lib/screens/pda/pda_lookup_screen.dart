import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/warehouse_repository.dart';
import '../../services/uhf_service.dart';
import '../../models/wms_models.dart';
import '../../theme/eye_care_theme.dart';

class PdaLookupScreen extends StatefulWidget {
  const PdaLookupScreen({super.key});

  @override
  State<PdaLookupScreen> createState() => _PdaLookupScreenState();
}

class _PdaLookupScreenState extends State<PdaLookupScreen> {
  final TextEditingController _serialController = TextEditingController();
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();

  StreamSubscription? _tagSub;
  StreamSubscription? _triggerSub;

  Item? _foundItem;
  Pallet? _foundPallet;
  Location? _foundLocation;

  @override
  void initState() {
    super.initState();
    _subscribeHardwareScanner();
    _eyeCare.addListener(_onThemeUpdate);
  }

  void _onThemeUpdate() {
    if (mounted) setState(() {});
  }

  void _subscribeHardwareScanner() {
    _tagSub = _uhf.onTagRead.listen((tag) {
      if (mounted && tag.epc.isNotEmpty) {
        _serialController.text = tag.epc;
        _performLookup(tag.epc);
      }
    });

    _triggerSub = _uhf.onTriggerStateChanged.listen((pressed) {
      if (mounted && pressed) {
        // Trigger hardware active
      }
    });
  }

  @override
  void dispose() {
    _eyeCare.removeListener(_onThemeUpdate);
    _tagSub?.cancel();
    _triggerSub?.cancel();
    _serialController.dispose();
    super.dispose();
  }

  void _performLookup(String query) {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) {
      setState(() {
        _foundItem = null;
        _foundPallet = null;
        _foundLocation = null;
      });
      return;
    }

    // Tìm trong items theo serialNumber, epc, itemId
    final item = _repo.items.where((i) {
      return i.serialNumber.toLowerCase() == cleanQuery.toLowerCase() ||
          i.epc.toLowerCase() == cleanQuery.toLowerCase() ||
          i.itemId.toLowerCase() == cleanQuery.toLowerCase();
    }).firstOrNull;

    Pallet? pallet;
    Location? location;

    if (item != null) {
      pallet = _repo.pallets.where((p) => p.palletId == item.palletId || p.itemIds.contains(item.itemId)).firstOrNull;
      if (pallet != null) {
        location = _repo.locations.where((l) => l.locationId == pallet!.locationId).firstOrNull;
      }
    } else {
      // Thử tìm theo mã Pallet / Thùng Carton
      pallet = _repo.pallets.where((p) => p.palletCode.toLowerCase() == cleanQuery.toLowerCase()).firstOrNull;
      if (pallet != null) {
        location = _repo.locations.where((l) => l.locationId == pallet!.locationId).firstOrNull;
      }
    }

    setState(() {
      _foundItem = item;
      _foundPallet = pallet;
      _foundLocation = location;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: AppBar(
        backgroundColor: c.bgCard,
        elevation: 0,
        title: Text('Lookup (Tra Cứu Serial)', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: c.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Search field matching PDF Page 14
            Container(
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.rfidCyan, width: 1.2),
              ),
              child: TextField(
                controller: _serialController,
                style: TextStyle(color: c.textPrimary, fontSize: 14, fontFamily: 'Courier', fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Serial number / EPC',
                  labelStyle: TextStyle(color: c.rfidCyan, fontSize: 12),
                  hintText: 'Quét thẻ RFID hoặc nhập mã...',
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 13),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: InputBorder.none,
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_serialController.text.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.close, color: c.textMuted, size: 20),
                          onPressed: () {
                            _serialController.clear();
                            _performLookup('');
                          },
                        ),
                      IconButton(
                        icon: Icon(Icons.qr_code_scanner, color: c.rfidCyan),
                        tooltip: 'Quét RFID',
                        onPressed: () => _uhf.startInventory(),
                      ),
                    ],
                  ),
                ),
                onChanged: _performLookup,
              ),
            ),
            const SizedBox(height: 20),

            // Result Display
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: _buildLookupResult(c),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLookupResult(EyeCareColors c) {
    if (_serialController.text.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.radar_outlined, size: 64, color: c.textMuted.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(
              'Quét thẻ RFID hoặc nhập mã Serial để tra cứu thông tin',
              style: TextStyle(color: c.textMuted, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (_foundItem == null && _foundPallet == null) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: c.bgCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: c.errorCoral.withValues(alpha: 0.5)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off, size: 48, color: c.errorCoral),
              const SizedBox(height: 10),
              Text(
                'Không tìm thấy mã: "${_serialController.text}"',
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Mã thẻ/Serial này chưa có trong CSDL SQLite hoặc chưa được nhập kho.',
                style: TextStyle(color: c.textMuted, fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // Matching PDF Page 14 card layout
    final whName = _foundLocation?.zone.isNotEmpty == true ? _foundLocation!.zone : 'Kho 01';
    final boxName = _foundPallet?.palletCode ?? 'CARTON-UNASSIGNED';
    final barcode = _foundItem?.sku ?? _foundPallet?.palletCode ?? 'N/A';
    final itemName = _foundItem?.productName ?? 'Pallet / Thùng ${_foundPallet?.palletCode}';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildInfoRow('Warehouse (Kho)', whName, c),
          Divider(color: c.border, height: 24),
          _buildInfoRow('Box (Thùng/Pallet)', boxName, c),
          Divider(color: c.border, height: 24),
          _buildInfoRow('Barcode (Mã SKU/Vạch)', barcode, c),
          Divider(color: c.border, height: 24),
          _buildInfoRow('Item name (Tên hàng)', itemName, c),
          if (_foundItem != null) ...[
            Divider(color: c.border, height: 24),
            _buildInfoRow('EPC Tag', _foundItem!.epc, c, isEpc: true),
            Divider(color: c.border, height: 24),
            _buildInfoRow('Status (Trạng thái)', _foundItem!.status.name.toUpperCase(), c),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, EyeCareColors c, {bool isEpc = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: c.textMuted, fontSize: 13),
        ),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              color: isEpc ? c.rfidCyan : c.textPrimary,
              fontWeight: FontWeight.bold,
              fontSize: isEpc ? 12 : 14,
              fontFamily: isEpc ? 'Courier' : null,
            ),
          ),
        ),
      ],
    );
  }
}

