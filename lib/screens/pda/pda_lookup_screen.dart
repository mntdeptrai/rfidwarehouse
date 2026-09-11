import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/warehouse_repository.dart';
import '../../services/uhf_service.dart';
import '../../services/auth_service.dart';
import '../../models/wms_models.dart';
import '../../theme/eye_care_theme.dart';
import '../../widgets/hardware_status_appbar.dart';
import 'pda_transfer_screen.dart';

/// Màn hình tra cứu mã trên thiết bị tay cầm PDA (Lookup Screen)
/// Hỗ trợ:
/// 1. Quét tự động bằng súng đọc RFID UHF hoặc Laser Barcode (1D/2D QR/Code128).
/// 2. Bắt phím cò súng vật lý (Hardware Trigger Gun).
/// 3. Tra cứu thông minh: S/N (kèm tiền tố S/N:), Product ID, SKU, EPC, Tên hàng, Thùng, Kệ, Pallet.
/// 4. Di chuyển sản phẩm riêng lẻ trực tiếp từ màn hình tra cứu sang kệ kho khác.
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
  final AuthService _auth = AuthService();

  StreamSubscription? _tagSub;
  StreamSubscription? _barcodeSub;
  StreamSubscription? _triggerSub;

  List<Item> _matchedItems = [];
  Pallet? _matchedPallet;
  Location? _matchedLocation;

  bool _isScanning = false;
  PdaScanMode _currentScanMode = PdaScanMode.rfid;

  @override
  void initState() {
    super.initState();
    _currentScanMode = _uhf.scanMode;
    _subscribeHardwareScanner();
    _eyeCare.addListener(_onStateChange);
    _repo.addListener(_onStateChange);
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _subscribeHardwareScanner() {
    // 1. Lắng nghe thẻ RFID quét được từ đầu đọc UHF
    _tagSub = _uhf.onTagRead.listen((tag) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (tag.epc.isNotEmpty) {
        _handleScannedInput(tag.epc, source: 'RFID');
      }
    });

    // 2. Lắng nghe mã vạch quét được từ đầu đọc Laser Barcode
    _barcodeSub = _uhf.onBarcodeRead.listen((barcode) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (barcode.isNotEmpty) {
        _handleScannedInput(barcode, source: 'Barcode');
      }
    });

    // 3. Lắng nghe nút bóp cò vật lý trên báng súng PDA
    _triggerSub = _uhf.onTriggerStateChanged.listen((pressed) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (pressed) {
        _startHardwareScan();
      } else {
        _stopHardwareScan();
      }
    });
  }

  void _handleScannedInput(String rawCode, {required String source}) {
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
    final clean = rawCode.trim();
    if (clean.isEmpty) return;

    HapticFeedback.mediumImpact();
    _serialController.text = clean;
    _performLookup(clean);
  }

  void _startHardwareScan() {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    if (_uhf.scanMode == PdaScanMode.barcode) {
      _uhf.triggerBarcodeScan();
    } else {
      _uhf.startInventory();
    }
  }

  void _stopHardwareScan() {
    setState(() => _isScanning = false);
    if (_uhf.scanMode == PdaScanMode.rfid) {
      _uhf.stopInventory();
    }
  }

  void _toggleScanMode() {
    final newMode = _currentScanMode == PdaScanMode.rfid ? PdaScanMode.barcode : PdaScanMode.rfid;
    _uhf.setScanMode(newMode);
    setState(() {
      _currentScanMode = newMode;
    });
  }

  @override
  void dispose() {
    _tagSub?.cancel();
    _barcodeSub?.cancel();
    _triggerSub?.cancel();
    _eyeCare.removeListener(_onStateChange);
    _repo.removeListener(_onStateChange);
    _serialController.dispose();
    _uhf.setScanMode(PdaScanMode.rfid);
    super.dispose();
  }

  /// Thuật toán tra cứu đa năng hỗ trợ mọi định dạng mã trên tay cầm
  void _performLookup(String query) {
    final rawQ = query.trim();
    if (rawQ.isEmpty) {
      setState(() {
        _matchedItems = [];
        _matchedPallet = null;
        _matchedLocation = null;
      });
      return;
    }

    final lower = rawQ.toLowerCase();
    final cleanQ = lower
        .replaceAll('s/n:', '')
        .replaceAll('sn:', '')
        .replaceAll('product_id:', '')
        .replaceAll('product id:', '')
        .replaceAll('productid:', '')
        .replaceAll('prod_id:', '')
        .replaceAll('prod id:', '')
        .replaceAll('id:', '')
        .replaceAll('sku:', '')
        .replaceAll('rfid:', '')
        .replaceAll('epc:', '')
        .replaceAll('barcode:', '')
        .trim();

    final q = cleanQ.isNotEmpty ? cleanQ : lower;
    final qNoSpecial = q.replaceAll('-', '').replaceAll('_', '').replaceAll('/', '').replaceAll(' ', '');

    // 1. Tìm kiếm trong danh sách Hàng hóa / Chip RFID
    final items = _repo.items.where((i) {
      final sn = i.serialNumber.toLowerCase();
      final snNoSpecial = sn.replaceAll('-', '').replaceAll('_', '').replaceAll('/', '').replaceAll(' ', '');
      final prodId = i.productId.toLowerCase();
      final prodIdNoSpecial = prodId.replaceAll('-', '').replaceAll('_', '').replaceAll('/', '').replaceAll(' ', '');
      final epc = i.epc.toLowerCase();
      final sku = i.sku.toLowerCase();
      final name = i.productName.toLowerCase();
      final itemId = i.itemId.toLowerCase();
      final carton = _repo.getItemCartonCode(i).toLowerCase();
      final supplier = _repo.getItemSupplier(i).toLowerCase();
      final pallet = (i.palletId ?? '').toLowerCase();
      final loc = (i.locationId ?? '').toLowerCase();

      return sn.contains(q) ||
          (qNoSpecial.isNotEmpty && snNoSpecial.contains(qNoSpecial)) ||
          prodId.contains(q) ||
          (qNoSpecial.isNotEmpty && prodIdNoSpecial.contains(qNoSpecial)) ||
          epc.contains(q) ||
          sku.contains(q) ||
          itemId.contains(q) ||
          name.contains(q) ||
          carton.contains(q) ||
          supplier.contains(q) ||
          pallet.contains(q) ||
          loc.contains(q);
    }).toList();

    // 2. Thử tìm theo mã Pallet
    final pal = _repo.pallets.where((p) {
      final pCode = p.palletCode.toLowerCase();
      final pId = p.palletId.toLowerCase();
      final pEpc = (p.rfidEpc ?? '').toLowerCase();
      return pCode == q || pId == q || pEpc == q || pCode.contains(q);
    }).firstOrNull;

    // 3. Thử tìm theo mã Kệ vị trí
    final loc = _repo.locations.where((l) {
      final lCode = l.locationCode.toLowerCase();
      final lId = l.locationId.toLowerCase();
      final lName = l.displayName.toLowerCase();
      final lShelf = l.shelf.toLowerCase();
      return lCode == q || lId == q || lName.contains(q) || lShelf.contains(q);
    }).firstOrNull;

    setState(() {
      _matchedItems = items;
      _matchedPallet = pal;
      _matchedLocation = loc;
    });
  }

  /// Hộp thoại di chuyển sản phẩm riêng lẻ trực tiếp trên màn hình PDA
  void _openMoveItemSheet(Item item, EyeCareColors c) {
    String selectedLocId = item.locationId ?? (_repo.locations.isNotEmpty ? _repo.locations.first.locationId : '');
    String? selectedPalletId = item.palletId;
    bool isProcessing = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (modalCtx, setSheetState) {
          final curLoc = _repo.locations.where((l) => l.locationId == item.locationId || l.locationCode == item.locationId).firstOrNull;
          final curLocName = curLoc?.displayName ?? (item.locationId ?? 'Chưa có vị trí');

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 18,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.drive_file_move_rounded, color: Color(0xFF10B981), size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Di Chuyển Sản Phẩm Riêng Lẻ', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                          Text('Chuyển mặt hàng sang vị trí kệ / pallet mới', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: c.textMuted),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Card tóm tắt sản phẩm đang chọn
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: c.bgDeep,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.productName, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13.5)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('SKU: ${item.sku}', style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.bold)),
                          const SizedBox(width: 10),
                          Expanded(child: Text('S/N: ${item.serialNumber}', style: TextStyle(color: c.textSecondary, fontSize: 11), overflow: TextOverflow.ellipsis)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text('EPC: ${item.epc}', style: TextStyle(color: c.textMuted, fontSize: 10, fontFamily: 'Courier')),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.location_on, color: const Color(0xFFEF4444), size: 14),
                          const SizedBox(width: 4),
                          Text('Vị trí hiện tại: ', style: TextStyle(color: c.textMuted, fontSize: 11.5)),
                          Text(curLocName, style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 11.5)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Chọn Vị trí Kệ đích
                Text('1. Chọn Kệ Kho Đích:', style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  decoration: BoxDecoration(
                    color: c.bgDeep,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.6)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _repo.locations.any((l) => l.locationId == selectedLocId) ? selectedLocId : (_repo.locations.isNotEmpty ? _repo.locations.first.locationId : null),
                      isExpanded: true,
                      dropdownColor: c.bgCard,
                      items: _repo.locations.map((loc) => DropdownMenuItem(
                        value: loc.locationId,
                        child: Text('${loc.locationCode} • ${loc.displayName}', style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) setSheetState(() => selectedLocId = val);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Chọn Pallet đích (tùy chọn)
                Text('2. Pallet Đích (Tùy chọn):', style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold)),
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
                      value: selectedPalletId,
                      isExpanded: true,
                      dropdownColor: c.bgCard,
                      hint: Text('Để lẻ trên kệ (Không xếp vào Pallet)', style: TextStyle(color: c.textMuted, fontSize: 12.5)),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Để lẻ trên kệ (Không có Pallet)', style: TextStyle(color: c.textSecondary, fontSize: 12.5)),
                        ),
                        ..._repo.pallets.map((p) => DropdownMenuItem<String?>(
                          value: p.palletId,
                          child: Text('Pallet ${p.palletCode} (${p.itemIds.length} SP)', style: TextStyle(color: c.textPrimary, fontSize: 12.5)),
                        )),
                      ],
                      onChanged: (val) => setSheetState(() => selectedPalletId = val),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Nút xác nhận chuyển
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: isProcessing
                        ? null
                        : () async {
                            setSheetState(() => isProcessing = true);
                            final performer = _auth.currentUser?.fullName ??
                                _auth.currentUser?.username ??
                                _repo.resolveUserFullName(null, defaultRole: 'handheld');

                            await _repo.moveItemIndividual(
                              epc: item.epc,
                              newLocationId: selectedLocId,
                              newPalletId: selectedPalletId,
                              performedBy: performer,
                            );

                            if (ctx.mounted) Navigator.pop(ctx);
                            if (!mounted) return;
                            _performLookup(_serialController.text);
                          },
                    child: isProcessing
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('XÁC NHẬN CHUYỂN KỆ', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 14)),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: HardwareStatusAppBar(
        title: 'Tra Cứu Mã & Serial PDA',
        actions: [
          // Nút chuyển chế độ quét RFID / Barcode
          IconButton(
            icon: Icon(
              _currentScanMode == PdaScanMode.rfid ? Icons.nfc : Icons.qr_code_scanner,
              color: _currentScanMode == PdaScanMode.rfid ? const Color(0xFF00E5FF) : const Color(0xFF10B981),
            ),
            tooltip: 'Đổi chế độ quét: RFID / Barcode',
            onPressed: _toggleScanMode,
          ),
          // Nút làm mới dữ liệu
          IconButton(
            icon: Icon(Icons.refresh, color: c.textSecondary),
            tooltip: 'Làm mới từ Database',
            onPressed: () async {
              await _repo.reloadFromSqlite();
              if (mounted) _performLookup(_serialController.text);
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Thanh tìm kiếm đa năng & quét mã
            Container(
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.rfidCyan, width: 1.2),
              ),
              child: TextField(
                controller: _serialController,
                style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontFamily: 'Courier', fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'S/N, SKU, EPC, Tên SP, Kệ, Pallet',
                  labelStyle: TextStyle(color: c.rfidCyan, fontSize: 12),
                  hintText: 'Quét thẻ/barcode hoặc nhập mã...',
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 12.5),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: InputBorder.none,
                  prefixIcon: Icon(
                    _currentScanMode == PdaScanMode.rfid ? Icons.nfc : Icons.qr_code_scanner,
                    color: c.rfidCyan,
                    size: 20,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_serialController.text.isNotEmpty)
                        IconButton(
                          icon: Icon(Icons.close, color: c.textMuted, size: 18),
                          onPressed: () {
                            _serialController.clear();
                            _performLookup('');
                          },
                        ),
                      IconButton(
                        icon: Icon(
                          _isScanning ? Icons.stop_circle : Icons.sensors,
                          color: _isScanning ? const Color(0xFFEF4444) : c.rfidCyan,
                        ),
                        tooltip: _isScanning ? 'Dừng quét' : 'Bật quét',
                        onPressed: () {
                          if (_isScanning) {
                            _stopHardwareScan();
                          } else {
                            _startHardwareScan();
                          }
                        },
                      ),
                    ],
                  ),
                ),
                onChanged: _performLookup,
              ),
            ),
            const SizedBox(height: 10),

            // Banner hướng dẫn quét bằng phím cò báng súng
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border),
              ),
              child: Row(
                children: [
                  Icon(
                    _currentScanMode == PdaScanMode.rfid ? Icons.nfc : Icons.qr_code_scanner,
                    size: 16,
                    color: c.rfidCyan,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _currentScanMode == PdaScanMode.rfid ? 'RFID UHF' : 'BARCODE',
                    style: TextStyle(color: c.textPrimary, fontSize: 11.5, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _toggleScanMode,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: c.rfidCyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _currentScanMode == PdaScanMode.rfid ? 'ĐỔI BARCODE' : 'ĐỔI RFID',
                        style: TextStyle(color: c.rfidCyan, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Danh sách kết quả tra cứu
            Expanded(
              child: _buildLookupBody(c),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLookupBody(EyeCareColors c) {
    if (_serialController.text.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.radar_outlined, size: 56, color: c.textMuted.withValues(alpha: 0.4)),
              const SizedBox(height: 12),
              Text(
                'Quét mã hoặc nhập để tra cứu',
                style: TextStyle(color: c.textMuted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (_matchedItems.isEmpty && _matchedPallet == null && _matchedLocation == null) {
      return Center(
        child: SingleChildScrollView(
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
                Icon(Icons.search_off, size: 44, color: c.errorCoral),
                const SizedBox(height: 10),
                Text(
                  'Không tìm thấy "${_serialController.text}"',
                  style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView(
      physics: const BouncingScrollPhysics(),
      children: [
        // 1. Kết quả Pallet (nếu khớp)
        if (_matchedPallet != null) ...[
          _buildPalletResultCard(_matchedPallet!, c),
          const SizedBox(height: 12),
        ],

        // 2. Kết quả Kệ kho (nếu khớp)
        if (_matchedLocation != null) ...[
          _buildLocationResultCard(_matchedLocation!, c),
          const SizedBox(height: 12),
        ],

        // 3. Kết quả các Mặt hàng / Chip RFID
        if (_matchedItems.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'SẢN PHẨM KHỚP (${_matchedItems.length})',
              style: TextStyle(color: c.rfidCyan, fontSize: 11.5, fontWeight: FontWeight.bold),
            ),
          ),
          ..._matchedItems.map((it) => _buildItemResultCard(it, c)),
        ],
      ],
    );
  }

  /// Card hiển thị chi tiết 1 sản phẩm kèm nút chuyển kệ
  Widget _buildItemResultCard(Item it, EyeCareColors c) {
    final pallet = _repo.pallets.where((p) => p.palletId == it.palletId || p.palletCode == it.palletId).firstOrNull;
    final loc = it.locationId != null
        ? _repo.locations.where((l) => l.locationId == it.locationId || l.locationCode == it.locationId).firstOrNull
        : (pallet != null ? _repo.locations.where((l) => l.locationId == pallet.locationId || l.locationCode == pallet.locationId).firstOrNull : null);
    final locDisplay = loc?.displayName ?? (loc?.locationCode ?? (it.locationId ?? 'Chưa có kệ'));
    final palletDisplay = pallet?.palletCode ?? (it.palletId ?? 'Không có pallet');
    final putBy = _repo.getItemPutawayBy(it);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.inventory_2, color: Color(0xFF10B981), size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(it.productName, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text('SKU: ${it.sku}  •  ID: ${it.productId}', style: TextStyle(color: c.rfidCyan, fontSize: 11.5, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: (it.status == ItemStatus.inStock ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    it.status.label,
                    style: TextStyle(
                      color: it.status == ItemStatus.inStock ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Divider(color: c.border, height: 1),
            const SizedBox(height: 8),

            // Thông tin vị trí & Pallet
            Row(
              children: [
                Icon(Icons.location_on, color: const Color(0xFFEF4444), size: 14),
                const SizedBox(width: 4),
                Text('Kệ: ', style: TextStyle(color: c.textMuted, fontSize: 11)),
                Expanded(
                  flex: 3,
                  child: Text(locDisplay, style: TextStyle(color: c.textPrimary, fontSize: 11.5, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                Icon(Icons.pallet, color: const Color(0xFFF59E0B), size: 14),
                const SizedBox(width: 4),
                Text('Pallet: ', style: TextStyle(color: c.textMuted, fontSize: 11)),
                Expanded(
                  flex: 3,
                  child: Text(palletDisplay, style: TextStyle(color: c.textPrimary, fontSize: 11.5, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // S/N & EPC
            Row(
              children: [
                Icon(Icons.tag, color: c.textMuted, size: 13),
                const SizedBox(width: 4),
                Expanded(
                  child: Text('S/N: ${it.serialNumber}', style: TextStyle(color: c.textSecondary, fontSize: 11.5), overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 6),
                Text('Người cất: $putBy', style: TextStyle(color: c.textMuted, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 4),
            Text('EPC: ${it.epc}', style: TextStyle(color: c.rfidCyan, fontSize: 10.5, fontFamily: 'monospace')),
            const SizedBox(height: 10),

            // Nút thao tác chuyển kệ riêng lẻ cho sản phẩm này
            Wrap(
              spacing: 8,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                    side: const BorderSide(color: Color(0xFF10B981)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.drive_file_move_rounded, size: 15),
                  label: const Text('ĐỔI KỆ / CHUYỂN VỊ TRÍ', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold)),
                  onPressed: () => _openMoveItemSheet(it, c),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.rfidCyan,
                    foregroundColor: const Color(0xFF2C251E),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.swap_horiz, size: 15),
                  label: const Text('CHUYỂN KHO PDA', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PdaTransferScreen(initialItem: it),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Card hiển thị chi tiết Pallet nếu khớp mã
  Widget _buildPalletResultCard(Pallet pal, EyeCareColors c) {
    final loc = _repo.locations.where((l) => l.locationId == pal.locationId || l.locationCode == pal.locationId).firstOrNull;
    final locDisplay = loc?.displayName ?? (pal.locationId ?? 'Chưa xếp kệ');
    final itemsOnPal = _repo.items.where((it) => it.palletId == pal.palletId || it.palletId == pal.palletCode).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.pallet, color: const Color(0xFFF59E0B), size: 22),
              const SizedBox(width: 8),
              Text('PALLET: ${pal.palletCode}', style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('${itemsOnPal.length} Sản phẩm', style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Vị trí: $locDisplay • RFID: ${pal.palletId}', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
        ],
      ),
    );
  }

  /// Card hiển thị chi tiết Kệ kho nếu khớp mã
  Widget _buildLocationResultCard(Location loc, EyeCareColors c) {
    final itemsOnShelf = _repo.items.where((i) {
      final iloc = i.locationId?.toUpperCase();
      return iloc == loc.locationCode.toUpperCase() || iloc == loc.locationId.toUpperCase();
    }).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.rfidCyan.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shelves, color: c.rfidCyan, size: 22),
              const SizedBox(width: 8),
              Text(loc.displayName, style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('Mã: ${loc.locationCode}', style: TextStyle(color: c.rfidCyan, fontSize: 11.5, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          Text('${loc.displaySubtitle} • Đang có ${itemsOnShelf.length} chip sản phẩm trên kệ', style: TextStyle(color: c.textSecondary, fontSize: 11.5)),
        ],
      ),
    );
  }
}
