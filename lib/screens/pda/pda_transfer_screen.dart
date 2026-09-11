import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/wms_models.dart';
import '../../models/tag_info.dart';
import '../../services/auth_service.dart';
import '../../services/uhf_service.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';
import '../../widgets/hardware_status_appbar.dart';

enum _TransferMode { pallet, items }

class PdaTransferScreen extends StatefulWidget {
  final Item? initialItem;

  const PdaTransferScreen({super.key, this.initialItem});

  @override
  State<PdaTransferScreen> createState() => _PdaTransferScreenState();
}

class _PdaTransferScreenState extends State<PdaTransferScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final AuthService _auth = AuthService();

  _TransferMode _mode = _TransferMode.pallet;
  String? _selectedLocationId;
  String? _selectedTargetPalletId; // null = Để riêng lẻ trên kệ
  StreamSubscription<TagInfo>? _rfidSub;
  StreamSubscription<String>? _barcodeSub;
  StreamSubscription<bool>? _triggerSub;

  PdaScanMode _currentScanMode = PdaScanMode.rfid;
  bool _isScanning = false;

  // --- Pallet mode ---
  Pallet? _foundPallet;
  List<Item> _palletItems = [];

  // --- Items mode ---
  final List<Item> _scannedItems = [];
  final Set<String> _scannedEpcs = {};
  final TextEditingController _manualInputCtrl = TextEditingController();
  final TextEditingController _palletInputCtrl = TextEditingController();

  // --- Chung ---
  String? _errorMessage;
  bool _isProcessing = false;
  bool _isSuccess = false;
  int _lastTransferCount = 0;

  @override
  void initState() {
    super.initState();
    _selectedLocationId =
        _repo.locations.isNotEmpty ? _repo.locations.first.locationId : null;
    // Mặc định ở chế độ chuyển Pallet, dùng mắt đọc Barcode để quét tem pallet nhanh và chuẩn xác
    _uhf.setScanMode(PdaScanMode.barcode);
    _currentScanMode = PdaScanMode.barcode;
    _eyeCare.addListener(_onStateChange);
    _repo.addListener(_onStateChange);

    // Xử lý nạp sẵn sản phẩm nếu được truyền từ màn hình khác (như Tra cứu mã)
    if (widget.initialItem != null) {
      _mode = _TransferMode.items;
      final it = widget.initialItem!;
      _scannedItems.add(it);
      _scannedEpcs.add(it.epc.toUpperCase());
    }

    _subscribeHardwareScanner();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _subscribeHardwareScanner() {
    _rfidSub = _uhf.onTagRead.listen((tag) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (tag.epc.isNotEmpty) {
        _handleScan(tag.epc, source: 'RFID');
      }
    });

    _barcodeSub = _uhf.onBarcodeRead.listen((barcode) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (barcode.isNotEmpty) {
        _handleScan(barcode, source: 'Barcode');
      }
    });

    _triggerSub = _uhf.onTriggerStateChanged.listen((pressed) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (pressed) {
        _startHardwareScan();
      } else {
        _stopHardwareScan();
      }
    });
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
    if (!_isScanning) return;
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
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: newMode == PdaScanMode.rfid ? const Color(0xFF00E5FF) : const Color(0xFF10B981),
        duration: const Duration(milliseconds: 1500),
        content: Text(
          newMode == PdaScanMode.rfid ? 'Chế độ: Đọc chip RFID UHF' : 'Chế độ: Quét Laser Barcode',
          style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _manualInputCtrl.dispose();
    _palletInputCtrl.dispose();
    _rfidSub?.cancel();
    _barcodeSub?.cancel();
    _triggerSub?.cancel();
    _eyeCare.removeListener(_onStateChange);
    _repo.removeListener(_onStateChange);
    _uhf.setScanMode(PdaScanMode.rfid);
    super.dispose();
  }

  void _handleScan(String rawCode, {String source = 'RFID'}) {
    if (_isProcessing) return;
    if (_isSuccess) {
      // Tự động khởi tạo phiên chuyển mới khi có mã quét mới
      _reset();
    }
    final clean = rawCode.trim();
    if (clean.isEmpty) return;

    // 1. Kiểm tra nếu mã quét được là mã vị trí kệ kho đích (LOC-... hoặc trùng mã locationCode/locationId)
    final cleanUpper = clean.toUpperCase();
    final matchedLoc = _repo.locations.where((l) =>
        l.locationCode.toUpperCase() == cleanUpper ||
        l.locationId.toUpperCase() == cleanUpper ||
        'LOC-${l.locationCode.toUpperCase()}' == cleanUpper ||
        'LOC-${l.locationId.toUpperCase()}' == cleanUpper).firstOrNull;

    if (matchedLoc != null) {
      HapticFeedback.lightImpact();
      setState(() {
        _selectedLocationId = matchedLoc.locationId;
        _errorMessage = null;
      });
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFF00E5FF),
          duration: const Duration(milliseconds: 1500),
          content: Text(
            '✓ Đã chọn kệ kho đích: ${matchedLoc.displayName} (${matchedLoc.locationCode})',
            style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold),
          ),
        ),
      );
      return;
    }

    if (_mode == _TransferMode.pallet) {
      _handlePalletScan(clean, source: source);
    } else {
      _handleItemScan(clean, source: source);
    }
  }

  void _handlePalletScan(String code, {String source = 'RFID'}) {
    final cleanUpper = code.toUpperCase();

    // 1. Tìm trực tiếp theo rfidEpc, palletId, palletCode
    Pallet? pallet = _repo.pallets.where((p) {
      return (p.rfidEpc ?? '').toUpperCase() == cleanUpper ||
          p.palletId.toUpperCase() == cleanUpper ||
          p.palletCode.toUpperCase() == cleanUpper ||
          'PAL-${p.palletCode.toUpperCase()}' == cleanUpper;
    }).firstOrNull;

    // 2. Nếu chưa thấy, kiểm tra xem mã quét được có phải là của 1 sản phẩm nằm trên Pallet nào đó hay không
    if (pallet == null) {
      final matchedItem = _repo.items.where((it) {
        final epc = it.epc.toUpperCase();
        final sn = it.serialNumber.toUpperCase();
        final sku = it.sku.toUpperCase();
        return epc == cleanUpper || sn == cleanUpper || sku == cleanUpper;
      }).firstOrNull;

      if (matchedItem != null && matchedItem.palletId != null && matchedItem.palletId!.isNotEmpty) {
        final pId = matchedItem.palletId!.toUpperCase();
        pallet = _repo.pallets.where((p) =>
          p.palletId.toUpperCase() == pId ||
          p.palletCode.toUpperCase() == pId ||
          'PAL-${p.palletCode.toUpperCase()}' == pId
        ).firstOrNull;
      }
    }

    if (pallet == null) {
      // Khi quét bằng sóng RFID UHF, không xóa Pallet đang có nếu chỉ là chip sản phẩm ngẫu nhiên trong không khí
      if (source == 'RFID') {
        return;
      }

      setState(() {
        _foundPallet = null;
        _palletItems = [];
        _errorMessage = 'Không tìm thấy pallet nào với mã: $code';
      });
      return;
    }

    final items = _repo.items
        .where((it) =>
            it.palletId == pallet!.palletId ||
            it.palletId == pallet.palletCode ||
            it.palletId == 'PAL-${pallet.palletCode}')
        .toList();

    HapticFeedback.mediumImpact();
    setState(() {
      _foundPallet = pallet;
      _palletItems = items;
      _errorMessage = null;
    });
  }

  void _handleItemScan(String rawCode, {String source = 'RFID'}) {
    final lower = rawCode.trim().toLowerCase();
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

    // Tìm item theo EPC, S/N, SKU, itemId, productId
    final item = _repo.items.where((it) {
      final epc = it.epc.toLowerCase();
      final sn = it.serialNumber.toLowerCase();
      final snNoSpecial = sn.replaceAll('-', '').replaceAll('_', '').replaceAll('/', '').replaceAll(' ', '');
      final sku = it.sku.toLowerCase();
      final prodId = it.productId.toLowerCase();
      final prodIdNoSpecial = prodId.replaceAll('-', '').replaceAll('_', '').replaceAll('/', '').replaceAll(' ', '');
      final itemId = it.itemId.toLowerCase();

      return epc == q ||
          sn == q ||
          (qNoSpecial.isNotEmpty && snNoSpecial == qNoSpecial) ||
          sku == q ||
          itemId == q ||
          prodId == q ||
          (qNoSpecial.isNotEmpty && prodIdNoSpecial == qNoSpecial);
    }).firstOrNull;

    if (item == null) {
      if (source != 'RFID' || _errorMessage == null) {
        setState(() {
          _errorMessage = 'Không tìm thấy sản phẩm với mã: $rawCode';
        });
      }
      return;
    }

    final epcUpper = item.epc.toUpperCase();
    if (_scannedEpcs.contains(epcUpper)) {
      if (source != 'RFID') {
        setState(() {
          _errorMessage = 'Sản phẩm "${item.productName}" (${item.sku}) đã có trong danh sách.';
        });
      }
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _scannedItems.add(item);
      _scannedEpcs.add(epcUpper);
      _errorMessage = null;
    });
  }

  void _openPalletPicker(EyeCareColors c) {
    final searchCtrl = TextEditingController();
    List<Pallet> filtered = List.from(_repo.pallets);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SizedBox(
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.layers, color: Color(0xFF10B981), size: 22),
                      const SizedBox(width: 8),
                      Text('Chọn Pallet Cần Chuyển',
                          style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, color: c.textMuted),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl,
                    style: TextStyle(color: c.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Tìm theo mã Pallet, RFID, vị trí...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                      prefixIcon: const Icon(Icons.search, color: Color(0xFF10B981), size: 18),
                      filled: true,
                      fillColor: c.bgDeep,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: c.border),
                      ),
                    ),
                    onChanged: (val) {
                      final q = val.trim().toLowerCase();
                      setModalState(() {
                        filtered = _repo.pallets.where((p) {
                          if (q.isEmpty) return true;
                          return p.palletCode.toLowerCase().contains(q) ||
                              p.palletId.toLowerCase().contains(q) ||
                              (p.rfidEpc ?? '').toLowerCase().contains(q) ||
                              (p.locationId ?? '').toLowerCase().contains(q);
                        }).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text('Không tìm thấy Pallet phù hợp', style: TextStyle(color: c.textMuted)))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                            itemBuilder: (_, idx) {
                              final p = filtered[idx];
                              final isSelected = _foundPallet?.palletCode == p.palletCode;
                              final loc = _repo.locations.where((l) => l.locationId == p.locationId || l.locationCode == p.locationId).firstOrNull;
                              final locText = loc?.displayName ?? (p.locationId ?? 'Chưa có kệ');
                              final pItems = _repo.items.where((it) => it.palletId == p.palletId || it.palletId == p.palletCode).toList();

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                leading: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.2) : c.bgDeep,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    isSelected ? Icons.check_circle : Icons.layers_outlined,
                                    color: isSelected ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                    size: 18,
                                  ),
                                ),
                                title: Text(p.palletCode,
                                    style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text('Kệ: $locText • ${pItems.length} SP${p.rfidEpc != null && p.rfidEpc!.isNotEmpty ? " • RFID: ${p.rfidEpc}" : ""}',
                                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                                    overflow: TextOverflow.ellipsis),
                                trailing: isSelected
                                    ? const Text('Đã chọn', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold))
                                    : ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF10B981),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        onPressed: () {
                                          _handlePalletScan(p.palletCode, source: 'Picker');
                                          Navigator.pop(ctx);
                                        },
                                        child: const Text('CHỌN', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _openItemPicker(EyeCareColors c) {
    final searchCtrl = TextEditingController();
    List<Item> filtered = List.from(_repo.items);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          return Padding(
            padding: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: SizedBox(
              height: 480,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.inventory_2, color: c.rfidCyan, size: 22),
                      const SizedBox(width: 8),
                      Text('Chọn Sản Phẩm Từ Kho',
                          style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: Icon(Icons.close, color: c.textMuted),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: searchCtrl,
                    style: TextStyle(color: c.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Tìm theo SKU, S/N, EPC, tên SP...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                      prefixIcon: Icon(Icons.search, color: c.rfidCyan, size: 18),
                      filled: true,
                      fillColor: c.bgDeep,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: c.border),
                      ),
                    ),
                    onChanged: (val) {
                      final q = val.trim().toLowerCase();
                      setModalState(() {
                        filtered = _repo.items.where((it) {
                          if (q.isEmpty) return true;
                          return it.productName.toLowerCase().contains(q) ||
                              it.sku.toLowerCase().contains(q) ||
                              it.serialNumber.toLowerCase().contains(q) ||
                              it.epc.toLowerCase().contains(q);
                        }).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text('Không tìm thấy sản phẩm phù hợp', style: TextStyle(color: c.textMuted)))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                            itemBuilder: (_, idx) {
                              final it = filtered[idx];
                              final isSelected = _scannedEpcs.contains(it.epc.toUpperCase());
                              final loc = _repo.locations.where((l) => l.locationId == it.locationId || l.locationCode == it.locationId).firstOrNull;
                              final locText = loc?.displayName ?? (it.locationId ?? 'Chưa có kệ');

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                leading: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: isSelected ? const Color(0xFF10B981).withValues(alpha: 0.2) : c.bgDeep,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    isSelected ? Icons.check_circle : Icons.inventory_2_outlined,
                                    color: isSelected ? const Color(0xFF10B981) : c.textMuted,
                                    size: 18,
                                  ),
                                ),
                                title: Text(it.productName,
                                    style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text('SKU: ${it.sku} • S/N: ${it.serialNumber} • Kệ: $locText',
                                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                                    overflow: TextOverflow.ellipsis),
                                trailing: isSelected
                                    ? Text('Đã chọn', style: TextStyle(color: const Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold))
                                    : ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: c.rfidCyan,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _scannedItems.add(it);
                                            _scannedEpcs.add(it.epc.toUpperCase());
                                            _errorMessage = null;
                                          });
                                          Navigator.pop(ctx);
                                        },
                                        child: const Text('CHỌN', style: TextStyle(color: Color(0xFF2C251E), fontSize: 11, fontWeight: FontWeight.bold)),
                                      ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmTransfer() async {
    if (_selectedLocationId == null) return;
    if (_mode == _TransferMode.pallet && _foundPallet == null) return;
    if (_mode == _TransferMode.items && _scannedItems.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    try {
      final performer = _auth.currentUser?.fullName ??
          _auth.currentUser?.username ??
          _repo.resolveUserFullName(null, defaultRole: 'handheld');

      int count = 0;
      if (_mode == _TransferMode.pallet) {
        count = await _repo.transferPalletToLocation(
          palletEpc: _foundPallet!.palletId,
          newLocationId: _selectedLocationId!,
          performedBy: performer,
        );
      } else {
        // Di chuyển từng sản phẩm riêng lẻ đến kệ và pallet mới (nếu có)
        for (final item in _scannedItems) {
          final ok = await _repo.moveItemIndividual(
            epc: item.epc,
            newLocationId: _selectedLocationId!,
            newPalletId: _selectedTargetPalletId,
            performedBy: performer,
          );
          if (ok) count++;
        }
      }

      setState(() {
        _isProcessing = false;
        _isSuccess = true;
        _lastTransferCount = count;
      });

      final newLoc = _repo.locations
          .where((l) => l.locationId == _selectedLocationId || l.locationCode == _selectedLocationId)
          .firstOrNull;
      final newLocName = newLoc?.displayName ?? (newLoc?.locationCode ?? _selectedLocationId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text(
                '✓ Chuyển thành công $count sản phẩm → $newLocName${_selectedTargetPalletId != null ? " (Pallet $_selectedTargetPalletId)" : ""}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Lỗi: $e';
      });
    }
  }

  void _removeItem(Item item) {
    setState(() {
      _scannedItems.removeWhere((it) => it.epc == item.epc);
      _scannedEpcs.remove(item.epc.toUpperCase());
    });
  }

  void _reset() {
    setState(() {
      _foundPallet = null;
      _palletItems = [];
      _scannedItems.clear();
      _scannedEpcs.clear();
      _manualInputCtrl.clear();
      _palletInputCtrl.clear();
      _errorMessage = null;
      _isProcessing = false;
      _isSuccess = false;
      _lastTransferCount = 0;
      _selectedTargetPalletId = null;
    });
  }

  void _switchMode(_TransferMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _reset();
    });
    // Tự động chuyển chế độ quét phần cứng: Pallet -> Barcode (nhanh & chính xác); Hàng riêng lẻ -> RFID
    if (mode == _TransferMode.pallet) {
      _uhf.setScanMode(PdaScanMode.barcode);
      setState(() => _currentScanMode = PdaScanMode.barcode);
    } else {
      _uhf.setScanMode(PdaScanMode.rfid);
      setState(() => _currentScanMode = PdaScanMode.rfid);
    }
  }

  bool _hasDataToTransfer() {
    if (_mode == _TransferMode.pallet) return _foundPallet != null;
    return _scannedItems.isNotEmpty;
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
        title: 'Chuyển Kho PDA',
        actions: [
          IconButton(
            icon: Icon(
              _currentScanMode == PdaScanMode.rfid ? Icons.nfc : Icons.qr_code_scanner,
              color: _currentScanMode == PdaScanMode.rfid ? const Color(0xFF00E5FF) : const Color(0xFF10B981),
            ),
            tooltip: 'Đổi chế độ quét: RFID / Barcode',
            onPressed: _toggleScanMode,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildModeToggle(c),
            const SizedBox(height: 14),

            // Bước 1: Chọn kho đến (Vị trí kệ kho đích)
            _buildStepCard(
              c: c,
              step: '1',
              title: 'Chọn kho đến (Vị trí kệ kho đích)',
              color: c.rfidCyan,
              child: locations.isEmpty
                  ? Text('Chưa có vị trí kho.', style: TextStyle(color: c.textMuted))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLocationDropdown(c, locations),
                        if (_mode == _TransferMode.items) ...[
                          const SizedBox(height: 10),
                          _buildTargetPalletDropdown(c),
                        ],
                      ],
                    ),
            ),
            const SizedBox(height: 12),

            // Bước 2: Quét mã RFID EPC của sản phẩm đó
            _buildStepCard(
              c: c,
              step: '2',
              title: _mode == _TransferMode.pallet
                  ? 'Quét chip RFID của Pallet'
                  : 'Quét mã RFID EPC của sản phẩm',
              color: const Color(0xFFF59E0B),
              child: _mode == _TransferMode.pallet
                  ? _buildPalletScanContent(c)
                  : _buildItemsScanContent(c),
            ),

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              _buildErrorBanner(c),
            ],

            if (!_isSuccess && _hasDataToTransfer()) ...[
              const SizedBox(height: 12),
              _buildStepCard(
                c: c,
                step: '3',
                title: 'Xác nhận cập nhật lại vị trí sản phẩm',
                color: const Color(0xFF10B981),
                child: _buildConfirmContent(c, selectedLoc),
              ),
            ],

            if (_isSuccess) ...[
              const SizedBox(height: 12),
              _buildSuccessCard(c, selectedLoc),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle(EyeCareColors c) {
    return Container(
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildModeTab(c, 'Theo Pallet', Icons.inventory_2_rounded, _TransferMode.pallet),
          _buildModeTab(c, 'Sản phẩm riêng lẻ', Icons.qr_code_scanner_rounded, _TransferMode.items),
        ],
      ),
    );
  }

  Widget _buildModeTab(EyeCareColors c, String label, IconData icon, _TransferMode mode) {
    final isActive = _mode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _switchMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? c.rfidCyan : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: isActive ? const Color(0xFF2C251E) : c.textMuted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive ? const Color(0xFF2C251E) : c.textMuted,
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLocationDropdown(EyeCareColors c, List<Location> locations) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
          style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
          items: locations.map((loc) => DropdownMenuItem<String>(
            value: loc.locationId,
            child: Text(
              '${loc.locationCode} • ${loc.displayName}',
              style: TextStyle(color: c.textPrimary, fontSize: 13),
            ),
          )).toList(),
          onChanged: (val) => setState(() {
            _selectedLocationId = val;
            _isSuccess = false;
            _errorMessage = null;
          }),
        ),
      ),
    );
  }

  Widget _buildTargetPalletDropdown(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: _selectedTargetPalletId,
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
          onChanged: (val) => setState(() => _selectedTargetPalletId = val),
        ),
      ),
    );
  }

  Widget _buildPalletScanContent(EyeCareColors c) {
    if (_foundPallet == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildScanPrompt(
            c,
            _currentScanMode == PdaScanMode.barcode
                ? 'Bóp cò súng PDA quét Barcode/QR Pallet hoặc nhập mã...'
                : 'Bóp cò súng PDA quét thẻ RFID Pallet...',
            _currentScanMode == PdaScanMode.barcode ? Icons.qr_code_scanner : Icons.nfc,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _palletInputCtrl,
                  style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'Quét Barcode hoặc nhập mã Pallet...',
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                    prefixIcon: Icon(
                      _currentScanMode == PdaScanMode.barcode ? Icons.qr_code_scanner : Icons.nfc,
                      color: const Color(0xFF10B981),
                      size: 18,
                    ),
                    filled: true,
                    fillColor: c.bgDeep,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    focusedBorder: const OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: Color(0xFF10B981))),
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      _handleScan(val, source: 'Manual/Barcode');
                      _palletInputCtrl.clear();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  if (_palletInputCtrl.text.trim().isNotEmpty) {
                    _handleScan(_palletInputCtrl.text, source: 'Manual/Barcode');
                    _palletInputCtrl.clear();
                  }
                },
                child: const Icon(Icons.check, color: Colors.white, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF10B981),
                    side: const BorderSide(color: Color(0xFF10B981)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                  ),
                  icon: const Icon(Icons.layers, size: 16),
                  label: const Text('CHỌN TỪ DANH SÁCH PALLET', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _openPalletPicker(c),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: _currentScanMode == PdaScanMode.barcode ? const Color(0xFF10B981) : const Color(0xFF00E5FF),
                  side: BorderSide(color: _currentScanMode == PdaScanMode.barcode ? const Color(0xFF10B981) : const Color(0xFF00E5FF)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                icon: Icon(_currentScanMode == PdaScanMode.barcode ? Icons.qr_code_scanner : Icons.nfc, size: 16),
                label: Text(
                  _currentScanMode == PdaScanMode.barcode ? 'Barcode' : 'RFID',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                onPressed: _toggleScanMode,
              ),
            ],
          ),
        ],
      );
    }

    final oldLoc = _foundPallet!.locationId != null
        ? _repo.locations.where((l) => l.locationId == _foundPallet!.locationId || l.locationCode == _foundPallet!.locationId).firstOrNull
        : null;
    final oldLocDisplay = oldLoc?.displayName ?? (_foundPallet!.locationId ?? 'Chưa có vị trí');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEpcChip(
          c,
          _foundPallet!.palletCode,
          subtitle: _foundPallet!.rfidEpc != null && _foundPallet!.rfidEpc!.isNotEmpty ? 'Chip RFID: ${_foundPallet!.rfidEpc}' : 'Quét qua Barcode Pallet',
          icon: _currentScanMode == PdaScanMode.barcode ? Icons.qr_code_scanner : Icons.layers,
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.bgDeep,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.inventory_2_rounded, color: Color(0xFF10B981), size: 18),
                  const SizedBox(width: 8),
                  Text(_foundPallet!.palletCode,
                      style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  _buildCountBadge(c, _palletItems.length, 'sản phẩm'),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Icon(Icons.location_on_outlined, color: c.textMuted, size: 14),
                  const SizedBox(width: 4),
                  Text('Vị trí hiện tại: ', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                  Text(oldLocDisplay, style: TextStyle(color: c.textPrimary, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
              if (_palletItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                ..._palletItems.take(4).map((it) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(
                    children: [
                      Icon(Icons.circle, color: c.textMuted, size: 5),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('${it.productName}  •  ${it.sku}',
                            style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                            overflow: TextOverflow.ellipsis),
                      ),
                    ],
                  ),
                )),
                if (_palletItems.length > 4)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('... và ${_palletItems.length - 4} sản phẩm khác',
                        style: TextStyle(color: c.textMuted, fontSize: 11, fontStyle: FontStyle.italic)),
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _reset,
            icon: Icon(Icons.refresh, color: c.textMuted, size: 14),
            label: Text('Quét lại', style: TextStyle(color: c.textMuted, fontSize: 12)),
          ),
        ),
      ],
    );
  }

  Widget _buildItemsScanContent(EyeCareColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildScanPrompt(
          c,
          'Bóp cò quét chip RFID hoặc nhập mã EPC...',
          _currentScanMode == PdaScanMode.rfid ? Icons.nfc : Icons.qr_code_scanner,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _manualInputCtrl,
                style: TextStyle(color: c.textPrimary, fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Quét thẻ RFID hoặc nhập mã EPC...',
                  hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                  prefixIcon: Icon(Icons.nfc, color: c.rfidCyan, size: 18),
                  filled: true,
                  fillColor: c.bgDeep,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.rfidCyan)),
                ),
                onSubmitted: (val) {
                  if (val.trim().isNotEmpty) {
                    _handleScan(val, source: 'Manual/Scan');
                    _manualInputCtrl.clear();
                  }
                },
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: c.rfidCyan,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                if (_manualInputCtrl.text.trim().isNotEmpty) {
                  _handleScan(_manualInputCtrl.text, source: 'Manual/Scan');
                  _manualInputCtrl.clear();
                }
              },
              child: const Icon(Icons.check, color: Color(0xFF2C251E), size: 18),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.rfidCyan,
                  side: BorderSide(color: c.rfidCyan),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                icon: const Icon(Icons.list_alt_rounded, size: 16),
                label: const Text('CHỌN TỪ DANH SÁCH KHO', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                onPressed: () => _openItemPicker(c),
              ),
            ),
          ],
        ),
        if (_scannedItems.isNotEmpty) ...[
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Danh sách sản phẩm (${_scannedItems.length}):',
                  style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.w600)),
              _buildCountBadge(c, _scannedItems.length, 'SP'),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              color: c.bgDeep,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.border),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _scannedItems.length,
              separatorBuilder: (context, index) => Divider(color: c.border, height: 1),
              itemBuilder: (_, idx) {
                final item = _scannedItems[idx];
                final oldLoc = _repo.locations.where((l) => l.locationId == item.locationId || l.locationCode == item.locationId).firstOrNull;
                final oldLocText = oldLoc?.displayName ?? (item.locationId ?? 'Chưa có kệ');

                return ListTile(
                  dense: true,
                  leading: Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text('${idx + 1}',
                          style: const TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  title: Text(item.productName,
                      style: TextStyle(color: c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('SKU: ${item.sku} • S/N: ${item.serialNumber}',
                          style: TextStyle(color: c.rfidCyan, fontSize: 11),
                          overflow: TextOverflow.ellipsis),
                      Text('Hiện tại: $oldLocText${item.palletId != null ? " • Pallet: ${item.palletId}" : ""}',
                          style: TextStyle(color: c.textMuted, fontSize: 10.5),
                          overflow: TextOverflow.ellipsis),
                    ],
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.close, color: c.errorCoral, size: 16),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _removeItem(item),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildConfirmContent(EyeCareColors c, Location? selectedLoc) {
    final qty = _mode == _TransferMode.pallet ? _palletItems.length : _scannedItems.length;
    final targetLocName = selectedLoc?.displayName ?? (selectedLoc?.locationCode ?? _selectedLocationId ?? '');

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              _buildSummaryRow(c,
                  label: _mode == _TransferMode.pallet ? 'Pallet' : 'Số sản phẩm',
                  value: _mode == _TransferMode.pallet
                      ? _foundPallet!.palletCode
                      : '$qty mặt hàng',
                  valueColor: c.rfidCyan),
              const SizedBox(height: 6),
              _buildSummaryRow(c,
                  label: 'Kệ kho đích',
                  value: targetLocName,
                  valueColor: const Color(0xFF10B981)),
              if (_mode == _TransferMode.items) ...[
                const SizedBox(height: 6),
                _buildSummaryRow(c,
                    label: 'Pallet đích',
                    value: _selectedTargetPalletId != null ? 'Pallet $_selectedTargetPalletId' : 'Không gán (để riêng lẻ)',
                    valueColor: c.textSecondary),
              ],
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            icon: _isProcessing
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.swap_horiz_rounded, color: Colors.white),
            label: Text(
              _isProcessing ? 'Đang xử lý...' : 'XÁC NHẬN CẬP NHẬT VỊ TRÍ',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: _isProcessing ? null : _confirmTransfer,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessCard(EyeCareColors c, Location? selectedLoc) {
    final locName = selectedLoc?.displayName ?? (selectedLoc?.locationCode ?? _selectedLocationId);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 48),
          const SizedBox(height: 10),
          Text('Chuyển kho thành công!',
              style: const TextStyle(color: Color(0xFF10B981), fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('$_lastTransferCount sản phẩm → $locName',
              style: TextStyle(color: const Color(0xFF10B981).withValues(alpha: 0.8), fontSize: 13)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: c.rfidCyan),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              icon: Icon(Icons.refresh, color: c.rfidCyan),
              label: Text(
                _mode == _TransferMode.pallet ? 'Quét pallet tiếp theo' : 'Chuyển đợt hàng tiếp theo',
                style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold),
              ),
              onPressed: _reset,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.errorCoral.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.errorCoral.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: c.errorCoral, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_errorMessage!, style: TextStyle(color: c.errorCoral, fontSize: 13))),
        ],
      ),
    );
  }

  Widget _buildScanPrompt(EyeCareColors c, String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: c.bgDeep,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: _isScanning ? const Color(0xFF10B981) : c.textMuted, size: 26),
          const SizedBox(width: 10),
          Expanded(child: Text(text,
              style: TextStyle(color: c.textMuted, fontSize: 13, fontStyle: FontStyle.italic))),
        ],
      ),
    );
  }

  Widget _buildEpcChip(EyeCareColors c, String epc, {String? subtitle, IconData? icon}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.rfidCyan.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.rfidCyan.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(icon ?? Icons.nfc, color: c.rfidCyan, size: 16),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(epc,
                    style: TextStyle(color: c.rfidCyan, fontSize: 11.5, fontFamily: 'monospace', fontWeight: FontWeight.bold)),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(subtitle, style: TextStyle(color: c.textMuted, fontSize: 10.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountBadge(EyeCareColors c, int count, String unit) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text('$count $unit',
          style: const TextStyle(color: Color(0xFF10B981), fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSummaryRow(EyeCareColors c, {required String label, required String value, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 13)),
        Flexible(child: Text(value,
            textAlign: TextAlign.end,
            style: TextStyle(color: valueColor ?? c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold))),
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
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Center(child: Text(step,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(12), child: child),
        ],
      ),
    );
  }
}
