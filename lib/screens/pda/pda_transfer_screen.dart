import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/wms_models.dart';
import '../../models/tag_info.dart';
import '../../services/auth_service.dart';
import '../../services/uhf_service.dart';
import '../../services/warehouse_repository.dart';
import '../../services/supabase_sync_service.dart';
import '../../theme/eye_care_theme.dart';
import '../../widgets/hardware_status_appbar.dart';
import '../../widgets/hardware_trigger_feedback_banner.dart';
import '../../widgets/app_notification_bar.dart';
import 'pda_merge_pallets_screen.dart';

enum _TransferMode { pallet, items }

class PdaTransferScreen extends StatefulWidget {
  final Item? initialItem;
  final String? initialLocationId;

  const PdaTransferScreen({
    super.key,
    this.initialItem,
    this.initialLocationId,
  });

  @override
  State<PdaTransferScreen> createState() => _PdaTransferScreenState();
}

class _PdaTransferScreenState extends State<PdaTransferScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final AuthService _auth = AuthService();

  _TransferMode _mode = _TransferMode.pallet;
  int _itemTransferStep = 1; // 1 = Quét Barcode Kệ Đích, 2 = Quét mã EPC Sản Phẩm
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
  final TextEditingController _locationInputCtrl = TextEditingController();

  // --- Chung ---
  String? _errorMessage;
  bool _isProcessing = false;
  bool _isSuccess = false;
  int _lastTransferCount = 0;
  Timer? _repoThrottleTimer;

  @override
  void initState() {
    super.initState();
    // Dập tắt ngay lập tức mọi phiên phát sóng RFID ngầm tồn dư từ các màn hình trước
    _uhf.stopInventory();
    _isScanning = false;

    // Không tự động chọn ngầm kệ đầu tiên: Yêu cầu nhân viên kho quét Barcode kệ kho đích trước
    _selectedLocationId = widget.initialLocationId;
    _eyeCare.addListener(_onStateChange);
    _repo.addListener(_onRepoChange);

    // Kích hoạt quét phần cứng và bóp cò trên PDA cho màn hình Chuyển Kho
    _uhf.enableScanning('chuyen_kho');

    // Xử lý nạp sẵn sản phẩm nếu được truyền từ màn hình khác (như Tra cứu mã)
    if (widget.initialItem != null) {
      _mode = _TransferMode.items;
      final it = widget.initialItem!;
      _scannedItems.add(it);
      _scannedEpcs.add(it.epc.toUpperCase());
      _itemTransferStep = 2; // Đã có sản phẩm -> Mở ngay Bước 2
      _uhf.setScanMode(PdaScanMode.rfid);
      _currentScanMode = PdaScanMode.rfid;
    } else {
      _itemTransferStep = 1;
      _uhf.setScanMode(PdaScanMode.barcode);
      _currentScanMode = PdaScanMode.barcode;
    }

    _subscribeHardwareScanner();
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _onRepoChange() {
    if (_repoThrottleTimer?.isActive ?? false) return;
    _repoThrottleTimer = Timer(const Duration(milliseconds: 200), () {
      if (mounted) setState(() {});
    });
  }

  void _subscribeHardwareScanner() {
    _rfidSub = _uhf.onTagRead.listen((tag) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      // Nhận diện chip khi đang quét hoặc bóp cò
      if (!_isScanning && !_uhf.isScanning) return;
      if (tag.epc.isNotEmpty) {
        _handleScan(tag.epc, source: 'RFID');
      }
    });

    _barcodeSub = _uhf.onBarcodeRead.listen((barcode) {
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (barcode.isNotEmpty) {
        _stopHardwareScan();
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
    // Đảm bảo không bị khóa quét
    _uhf.enableScanning('chuyen_kho');
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
    if (_isScanning) {
      _stopHardwareScan();
    }
    final newMode = _currentScanMode == PdaScanMode.rfid ? PdaScanMode.barcode : PdaScanMode.rfid;
    _uhf.setScanMode(newMode);
    setState(() {
      _currentScanMode = newMode;
    });
  }

  @override
  void dispose() {
    _stopHardwareScan();
    _uhf.stopInventory();
    _uhf.disableScanning();
    _repoThrottleTimer?.cancel();
    _manualInputCtrl.dispose();
    _palletInputCtrl.dispose();
    _locationInputCtrl.dispose();
    _rfidSub?.cancel();
    _barcodeSub?.cancel();
    _triggerSub?.cancel();
    _eyeCare.removeListener(_onStateChange);
    _repo.removeListener(_onRepoChange);
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

    // 1. Kiểm tra nếu mã quét được là mã vị trí kệ kho đích (LOC-... hoặc trùng mã locationCode/locationId, tiền tố QR)
    // Chỉ nhận diện kệ kho khi đang ở bước 1 (hoặc pallet mode) để tránh conflict khi quét mã EPC sản phẩm
    final bool canMatchLocation = _mode == _TransferMode.pallet || _itemTransferStep == 1;
    if (canMatchLocation) {
      String normLoc = clean.toUpperCase();
      if (normLoc.startsWith('LOCATION:')) normLoc = normLoc.substring(9).trim();
      if (normLoc.startsWith('LOC:')) normLoc = normLoc.substring(4).trim();
      if (normLoc.startsWith('SHELF:')) normLoc = normLoc.substring(6).trim();
      final normStripped = normLoc.startsWith('LOC-') ? normLoc.substring(4) : normLoc;
      final normWithLoc = normLoc.startsWith('LOC-') ? normLoc : 'LOC-$normLoc';

      final matchedLoc = _repo.locations.where((l) {
        final locCode = l.locationCode.trim().toUpperCase();
        final locId = l.locationId.trim().toUpperCase();
        return locCode == normLoc ||
            locId == normLoc ||
            locCode == normStripped ||
            locId == normStripped ||
            locCode == normWithLoc ||
            locId == normWithLoc ||
            locCode.replaceAll('-', '') == normLoc.replaceAll('-', '');
      }).firstOrNull;

      if (matchedLoc != null) {
        HapticFeedback.lightImpact();
        _onLocationSelected(matchedLoc, source: source);
        return;
      }
    }

    if (_mode == _TransferMode.pallet) {
      _handlePalletScan(clean, source: source);
    } else {
      _handleItemScan(clean, source: source);
    }
  }

  void _onLocationSelected(Location matchedLoc, {String source = 'Barcode'}) {
    setState(() {
      _selectedLocationId = matchedLoc.locationId;
      _errorMessage = null;

      // Nếu đang ở chế độ sản phẩm riêng lẻ, lọc lại danh sách _scannedItems (nếu đã quét trước đó)
      if (_mode == _TransferMode.items) {
        _filterConflictedItemsForLocation(matchedLoc);
        _itemTransferStep = 2; // Tự động chuyển ngay sang Màn hình 2 quét EPC
      }
    });

    if (_mode == _TransferMode.items) {
      // Chuyển ngay sang RFID scanner để quét chùm thẻ EPC cho Bước 2
      _uhf.setScanMode(PdaScanMode.rfid);
      setState(() => _currentScanMode = PdaScanMode.rfid);
    }

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF2563EB),
        duration: const Duration(milliseconds: 1800),
        content: Text(
          _mode == _TransferMode.items
              ? '✓ Đã chọn kệ: ${matchedLoc.displayName} (${matchedLoc.locationCode}) ➔ Chuyển sang quét chip RFID'
              : '✓ Đã chọn kệ kho đích: ${matchedLoc.displayName} (${matchedLoc.locationCode})',
          style: const TextStyle(color: Color(0xFFFFFFFF), fontWeight: FontWeight.bold),
        ),
      ),
    );

    // Nếu đã quét Pallet trước đó trong Pallet mode, tự động mở ngay hộp thoại xác nhận chuyển Pallet
    if (_mode == _TransferMode.pallet && _foundPallet != null && !_isProcessing && !_isSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _foundPallet != null && !_isProcessing && !_isSuccess) {
          _showPalletConfirmDialog(_foundPallet!, _palletItems, matchedLoc);
        }
      });
    }
  }

  void _filterConflictedItemsForLocation(Location targetLoc) {
    if (_scannedItems.isEmpty) return;
    final targetLocId = targetLoc.locationId;
    final targetLocCode = targetLoc.locationCode;

    final conflicted = <Item>[];
    _scannedItems.removeWhere((item) {
      final isDirect = item.locationId != null && (
        item.locationId == targetLocId || item.locationId == targetLocCode
      );
      bool isPallet = false;
      if (item.palletId != null && item.palletId!.isNotEmpty) {
        final p = _repo.pallets.where((pal) =>
          pal.palletId == item.palletId ||
          pal.palletCode == item.palletId ||
          'PAL-${pal.palletCode}' == item.palletId
        ).firstOrNull;
        if (p != null && p.locationId != null) {
          isPallet = (p.locationId == targetLocId || p.locationId == targetLocCode);
        }
      }
      if (isDirect || isPallet) {
        conflicted.add(item);
        _scannedEpcs.remove(item.epc.toUpperCase());
        return true;
      }
      return false;
    });

    if (conflicted.isNotEmpty) {
      _errorMessage = 'Đã tự động loại bỏ ${conflicted.length} sản phẩm do đã có sẵn trên kệ ${targetLoc.displayName}.';
    }
  }

  void _handlePalletScan(String code, {String source = 'RFID'}) {
    final cleanUpper = code.toUpperCase();

    // Tránh quét lặp nếu đã nhận diện đúng pallet này
    if (_foundPallet != null) {
      if (_foundPallet!.palletCode.toUpperCase() == cleanUpper ||
          _foundPallet!.palletId.toUpperCase() == cleanUpper ||
          (_foundPallet!.rfidEpc ?? '').toUpperCase() == cleanUpper) {
        return;
      }
    }

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

    // Dừng quét ngay lập tức sau khi nhận diện pallet để tránh quét nhầm thêm mã khác
    _stopHardwareScan();
    _uhf.stopInventory();

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

    // Mở ngay hộp thoại xác nhận chuyển Pallet nếu ĐÃ CÓ KỆ ĐÍCH
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _foundPallet != null && !_isProcessing && !_isSuccess) {
        final targetLoc = _repo.locations.where((l) => l.locationId == _selectedLocationId).firstOrNull;
        if (targetLoc != null) {
          _showPalletConfirmDialog(_foundPallet!, _palletItems, targetLoc);
        } else {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFFF59E0B),
              duration: const Duration(seconds: 2),
              content: Text(
                '✓ Đã nhận diện Pallet ${_foundPallet!.palletCode}. Hãy quét Barcode Kệ đích (Bước 1) để xác nhận chuyển!',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }
      }
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

    // 1. KIỂM TRA LỌC TRÙNG VỚI SẢN PHẨM ĐANG CÓ TRÊN KỆ ĐÍCH
    if (_selectedLocationId != null) {
      final targetLoc = _repo.locations.where((l) =>
        l.locationId == _selectedLocationId || l.locationCode == _selectedLocationId
      ).firstOrNull;
      final targetLocId = targetLoc?.locationId ?? _selectedLocationId!;
      final targetLocCode = targetLoc?.locationCode;

      final isDirect = item.locationId != null && (
        item.locationId == targetLocId || (targetLocCode != null && item.locationId == targetLocCode)
      );

      bool isPallet = false;
      if (item.palletId != null && item.palletId!.isNotEmpty) {
        final p = _repo.pallets.where((pal) =>
          pal.palletId == item.palletId ||
          pal.palletCode == item.palletId ||
          'PAL-${pal.palletCode}' == item.palletId
        ).firstOrNull;
        if (p != null && p.locationId != null && p.locationId!.isNotEmpty) {
          isPallet = (p.locationId == targetLocId || (targetLocCode != null && p.locationId == targetLocCode));
        }
      }

      if (isDirect || isPallet) {
        HapticFeedback.heavyImpact();
        final shelfName = targetLoc?.displayName ?? targetLocCode ?? targetLocId;
        setState(() {
          _errorMessage = 'Sản phẩm "${item.productName}" (${item.sku}) đã có trên kệ $shelfName rồi!';
        });
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFEF4444),
            duration: const Duration(seconds: 2),
            content: Text(
              '⚠️ Sản phẩm "${item.productName}" (${item.sku}) đã có trên kệ $shelfName rồi!',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        );
        return;
      }
    }

    // 2. KIỂM TRA TRÙNG TRONG DANH SÁCH ĐÃ QUÉT HIỆN TẠI
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
      if (_mode == _TransferMode.items) {
        _itemTransferStep = 2;
      }
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
                                          Navigator.pop(ctx);
                                          _handlePalletScan(p.palletCode, source: 'Picker');
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

                              // Kiểm tra xem sản phẩm đã có trên kệ đích chưa
                              final targetLoc = _repo.locations.where((l) => l.locationId == _selectedLocationId || l.locationCode == _selectedLocationId).firstOrNull;
                              final targetLocId = targetLoc?.locationId ?? _selectedLocationId;
                              final targetLocCode = targetLoc?.locationCode;

                              final isDirectOnTarget = targetLocId != null && it.locationId != null && (
                                it.locationId == targetLocId || (targetLocCode != null && it.locationId == targetLocCode)
                              );
                              bool isPalletOnTarget = false;
                              if (targetLocId != null && it.palletId != null && it.palletId!.isNotEmpty) {
                                final p = _repo.pallets.where((pal) => pal.palletId == it.palletId || pal.palletCode == it.palletId).firstOrNull;
                                if (p != null && p.locationId != null) {
                                  isPalletOnTarget = (p.locationId == targetLocId || (targetLocCode != null && p.locationId == targetLocCode));
                                }
                              }
                              final isAlreadyOnTarget = isDirectOnTarget || isPalletOnTarget;

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
                                    isSelected ? Icons.check_circle : (isAlreadyOnTarget ? Icons.block_flipped : Icons.inventory_2_outlined),
                                    color: isSelected ? const Color(0xFF10B981) : (isAlreadyOnTarget ? const Color(0xFFEF4444) : c.textMuted),
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
                                    ? const Text('Đã chọn', style: TextStyle(color: Color(0xFF10B981), fontSize: 11, fontWeight: FontWeight.bold))
                                    : isAlreadyOnTarget
                                        ? Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.3)),
                                            ),
                                            child: const Text('Đã trên kệ này', style: TextStyle(color: Color(0xFFEF4444), fontSize: 10.5, fontWeight: FontWeight.bold)),
                                          )
                                        : ElevatedButton(
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: c.rfidCyan,
                                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                              minimumSize: Size.zero,
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                            ),
                                            onPressed: () {
                                              Navigator.pop(ctx);
                                              _handleItemScan(it.epc, source: 'Picker');
                                            },
                                            child: const Text('CHỌN', style: TextStyle(color: Color(0xFFFFFFFF), fontSize: 11, fontWeight: FontWeight.bold)),
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

  Future<void> _showPalletConfirmDialog(Pallet pallet, List<Item> items, Location? targetLoc) async {
    final c = _eyeCare.colors;
    final oldLoc = pallet.locationId != null
        ? _repo.locations.where((l) => l.locationId == pallet.locationId || l.locationCode == pallet.locationId).firstOrNull
        : null;
    final oldLocDisplay = oldLoc?.displayName ?? (pallet.locationId ?? 'Chưa có kệ');
    final targetLocDisplay = targetLoc?.displayName ?? (_selectedLocationId ?? 'Chưa chọn kệ');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF10B981), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Xác Nhận Chuyển Pallet',
                    style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Kiểm tra thông tin trước khi chuyển',
                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.bgDeep,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow(c,
                        label: 'Mã Pallet',
                        value: pallet.palletCode,
                        valueColor: c.rfidCyan),
                    const Divider(height: 14),
                    _buildSummaryRow(c,
                        label: 'Vị trí hiện tại',
                        value: oldLocDisplay),
                    const SizedBox(height: 6),
                    _buildSummaryRow(c,
                        label: 'Chuyển đến Kệ đích',
                        value: targetLocDisplay,
                        valueColor: const Color(0xFF10B981)),
                    const Divider(height: 14),
                    _buildSummaryRow(c,
                        label: 'Tổng số sản phẩm',
                        value: '${items.length} sản phẩm',
                        valueColor: c.textPrimary),
                  ],
                ),
              ),
              if (items.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Hàng hóa trên pallet:',
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                ...items.take(3).map((it) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${it.productName} (${it.sku})',
                    style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                if (items.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '... và ${items.length - 3} sản phẩm khác',
                      style: TextStyle(color: c.textMuted, fontSize: 10.5, fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.errorCoral,
                    side: BorderSide(color: c.errorCoral),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _reset(); // Hủy pallet này để thủ kho quét lại tránh nhầm
                  },
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('HỦY / QUÉT LẠI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 15),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('XÁC NHẬN CHUYỂN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmTransfer();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _confirmTransfer() async {
    if (_selectedLocationId == null) {
      setState(() {
        _errorMessage = 'Vui lòng chọn hoặc quét Barcode kệ kho đích trước!';
        if (_mode == _TransferMode.items) {
          _itemTransferStep = 1;
          _uhf.setScanMode(PdaScanMode.barcode);
          _currentScanMode = PdaScanMode.barcode;
        }
      });
      return;
    }
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

      // Lập tức kích hoạt đẩy các biến động điều chuyển lên Supabase Cloud
      try {
        await SupabaseSyncService().syncNow();
      } catch (_) {}

      if (mounted) {
        final loc = _repo.locations.where((l) => l.locationId == _selectedLocationId).firstOrNull;
        final locDisplay = loc?.displayName ?? loc?.locationCode ?? _selectedLocationId ?? '';
        AppSnackBar.showSuccess(
          context,
          '✓ Đã chuyển thành công $count sản phẩm sang kệ $locDisplay!',
        );
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _errorMessage = 'Lỗi: $e';
      });
      if (mounted) {
        AppSnackBar.showError(context, 'Lỗi chuyển kho: $e');
      }
    }
  }

  void _removeItem(Item item) {
    setState(() {
      _scannedItems.removeWhere((it) => it.epc == item.epc);
      _scannedEpcs.remove(item.epc.toUpperCase());
    });
  }

  void _reset({bool keepLocation = true}) {
    setState(() {
      _foundPallet = null;
      _palletItems = [];
      _scannedItems.clear();
      _scannedEpcs.clear();
      _manualInputCtrl.clear();
      _palletInputCtrl.clear();
      if (!keepLocation) {
        _locationInputCtrl.clear();
        _selectedLocationId = null;
        _itemTransferStep = 1;
      } else {
        if (_mode == _TransferMode.items && _selectedLocationId != null) {
          _itemTransferStep = 2;
        }
      }
      _errorMessage = null;
      _isProcessing = false;
      _isSuccess = false;
      _lastTransferCount = 0;
      _selectedTargetPalletId = null;
    });

    if (_mode == _TransferMode.items) {
      if (_itemTransferStep == 1) {
        _uhf.setScanMode(PdaScanMode.barcode);
        setState(() => _currentScanMode = PdaScanMode.barcode);
      } else {
        _uhf.setScanMode(PdaScanMode.rfid);
        setState(() => _currentScanMode = PdaScanMode.rfid);
      }
    }
  }

  void _switchMode(_TransferMode mode) {
    if (_mode == mode) return;
    setState(() {
      _mode = mode;
      _reset();
      if (mode == _TransferMode.items) {
        _itemTransferStep = (_selectedLocationId != null) ? 2 : 1;
      }
    });
    // Giữ khóa quét luôn mở khi đổi chế độ
    _uhf.enableScanning('chuyen_kho');
    // Tự động chuyển chế độ quét phần cứng: Pallet -> Barcode; Hàng riêng lẻ -> theo bước hiện tại
    if (mode == _TransferMode.pallet) {
      _uhf.setScanMode(PdaScanMode.barcode);
      setState(() => _currentScanMode = PdaScanMode.barcode);
    } else {
      if (_itemTransferStep == 1) {
        _uhf.setScanMode(PdaScanMode.barcode);
        setState(() => _currentScanMode = PdaScanMode.barcode);
      } else {
        _uhf.setScanMode(PdaScanMode.rfid);
        setState(() => _currentScanMode = PdaScanMode.rfid);
      }
    }
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
            icon: const Icon(
              Icons.merge_rounded,
              color: Color(0xFFF59E0B),
            ),
            tooltip: 'Gộp Pallet',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PdaMergePalletsScreen()),
              );
            },
          ),
          IconButton(
            icon: Icon(
              _currentScanMode == PdaScanMode.rfid ? Icons.nfc : Icons.qr_code_scanner,
              color: _currentScanMode == PdaScanMode.rfid ? const Color(0xFF2563EB) : const Color(0xFF10B981),
            ),
            tooltip: 'Đổi chế độ quét: RFID / Barcode',
            onPressed: _toggleScanMode,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: c.rfidCyan,
        backgroundColor: c.bgCardElevated,
        onRefresh: () async {
          await SupabaseSyncService().syncNow();
          await _repo.reloadFromDatabase();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(14),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HardwareTriggerFeedbackBanner(
              compact: true,
              externalIsScanning: _isScanning,
              scannedCount: _scannedItems.length,
              customIdleLabel: 'BÓP CÒ QUÉT KỆ ĐÍCH & SẢN PHẨM CẦN CHUYỂN',
            ),
            const SizedBox(height: 10),
            _buildModeToggle(c),
            _buildMergePalletBanner(c),
            const SizedBox(height: 14),

            if (_mode == _TransferMode.pallet) ...[
              // Bước 1: Quét Barcode của Kệ (Kho đích)
              _buildStepCard(
                c: c,
                step: '1',
                title: _selectedLocationId != null
                    ? 'Kệ kho đích đã chọn'
                    : 'Quét Barcode của Kệ (Kho đích)',
                color: c.rfidCyan,
                child: _buildLocationScanContent(c, locations),
              ),
              const SizedBox(height: 12),

              // Bước 2: Quét Barcode của Pallet
              _buildStepCard(
                c: c,
                step: '2',
                title: _foundPallet != null
                    ? 'Pallet đã nhận diện'
                    : 'Quét Barcode của Pallet',
                color: const Color(0xFFF59E0B),
                child: _buildPalletScanContent(c),
              ),
              const SizedBox(height: 12),

              // Bước 3: Xác nhận chuyển Pallet sang Kệ đích (Luôn hiển thị cố định chống quét nhầm)
              if (!_isSuccess) ...[
                _buildStepCard(
                  c: c,
                  step: '3',
                  title: 'Xác nhận chuyển Pallet sang Kệ đích',
                  color: (_foundPallet != null && _selectedLocationId != null)
                      ? const Color(0xFF10B981)
                      : c.textMuted,
                  child: _buildPalletConfirmContent(c, selectedLoc),
                ),
              ],
            ] else ...[
              // CHẾ ĐỘ SẢN PHẨM RIÊNG LẺ: TÁCH LÀM 2 BƯỚC / 2 MÀN HÌNH TUẦN TỰ
              _buildItemStepIndicator(c),

              if (_itemTransferStep == 1) ...[
                // MÀN HÌNH 1: QUÉT KỆ ĐÍCH
                _buildStepCard(
                  c: c,
                  step: '1',
                  title: _selectedLocationId != null
                      ? 'Kệ kho đích đã chọn'
                      : 'Quét Barcode của Kệ (Kho đích)',
                  color: c.rfidCyan,
                  child: _buildLocationScanContent(c, locations),
                ),
              ] else ...[
                // MÀN HÌNH 2: QUÉT MÃ RFID EPC CỦA SẢN PHẨM
                _buildTargetShelfBanner(c, selectedLoc),

                _buildStepCard(
                  c: c,
                  step: '2',
                  title: 'Quét mã RFID EPC của sản phẩm',
                  color: const Color(0xFFF59E0B),
                  child: _buildItemsScanContent(c),
                ),

                if (!_isSuccess) ...[
                  const SizedBox(height: 12),
                  _buildStepCard(
                    c: c,
                    step: '3',
                    title: 'Xác nhận cập nhật lại vị trí sản phẩm',
                    color: (_scannedItems.isNotEmpty && _selectedLocationId != null)
                        ? const Color(0xFF10B981)
                        : c.textMuted,
                    child: _buildItemsConfirmContent(c, selectedLoc),
                  ),
                ],
              ],
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 10),
              _buildErrorBanner(c),
            ],

            if (_isSuccess) ...[
              const SizedBox(height: 12),
              _buildSuccessCard(c, selectedLoc),
            ],
          ],
        ),
      ),
    ),
  );
}

  Widget _buildItemStepIndicator(EyeCareColors c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: [
          // Bước 1: Quét Kệ Đích
          Expanded(
            child: InkWell(
              onTap: () {
                if (_itemTransferStep != 1) {
                  setState(() => _itemTransferStep = 1);
                  _uhf.setScanMode(PdaScanMode.barcode);
                  setState(() => _currentScanMode = PdaScanMode.barcode);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  color: _itemTransferStep == 1
                      ? c.rfidCyan.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _itemTransferStep == 1
                        ? c.rfidCyan
                        : (_selectedLocationId != null
                            ? const Color(0xFF10B981).withValues(alpha: 0.4)
                            : Colors.transparent),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _selectedLocationId != null && _itemTransferStep != 1
                            ? const Color(0xFF10B981)
                            : (_itemTransferStep == 1 ? c.rfidCyan : c.border),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: _selectedLocationId != null && _itemTransferStep != 1
                            ? const Icon(Icons.check, size: 13, color: Colors.white)
                            : Text(
                                '1',
                                style: TextStyle(
                                  color: _itemTransferStep == 1
                                      ? const Color(0xFFFFFFFF)
                                      : Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '1. Quét Kệ Đích',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: _itemTransferStep == 1 ? FontWeight.bold : FontWeight.w500,
                          color: _itemTransferStep == 1
                              ? c.rfidCyan
                              : (_selectedLocationId != null ? const Color(0xFF10B981) : c.textMuted),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(Icons.arrow_forward_ios_rounded, size: 12, color: c.textMuted),
          ),
          // Bước 2: Quét Mã EPC
          Expanded(
            child: InkWell(
              onTap: () {
                if (_selectedLocationId != null && _itemTransferStep != 2) {
                  setState(() => _itemTransferStep = 2);
                  _uhf.setScanMode(PdaScanMode.rfid);
                  setState(() => _currentScanMode = PdaScanMode.rfid);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                decoration: BoxDecoration(
                  color: _itemTransferStep == 2
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _itemTransferStep == 2
                        ? const Color(0xFFF59E0B)
                        : Colors.transparent,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: _itemTransferStep == 2 ? const Color(0xFFF59E0B) : c.border,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '2',
                          style: TextStyle(
                            color: _itemTransferStep == 2 ? Colors.white : c.textMuted,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '2. Quét Mã EPC',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: _itemTransferStep == 2 ? FontWeight.bold : FontWeight.w500,
                          color: _itemTransferStep == 2 ? const Color(0xFFF59E0B) : c.textMuted,
                        ),
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

  Widget _buildTargetShelfBanner(EyeCareColors c, Location? selectedLoc) {
    final hasLoc = _selectedLocationId != null;
    final locName = selectedLoc?.displayName ?? selectedLoc?.locationCode ?? _selectedLocationId ?? 'Chưa chọn kệ';
    final zoneInfo = selectedLoc != null ? 'Khu: ${selectedLoc.zone} • Tầng: ${selectedLoc.level}' : 'Vui lòng chọn kệ đích';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: hasLoc ? c.rfidCyan.withValues(alpha: 0.12) : const Color(0xFFF59E0B).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hasLoc ? c.rfidCyan.withValues(alpha: 0.4) : const Color(0xFFF59E0B).withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: hasLoc ? c.rfidCyan.withValues(alpha: 0.2) : const Color(0xFFF59E0B).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.shelves, color: hasLoc ? c.rfidCyan : const Color(0xFFF59E0B), size: 22),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hasLoc ? 'KỆ ĐÍCH: $locName' : '⚠️ CHƯA CHỌN KỆ ĐÍCH',
                  style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  zoneInfo,
                  style: TextStyle(color: c.textSecondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: hasLoc ? c.rfidCyan : const Color(0xFFF59E0B),
              side: BorderSide(color: hasLoc ? c.rfidCyan : const Color(0xFFF59E0B)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            icon: const Icon(Icons.arrow_back, size: 13),
            label: Text(hasLoc ? 'ĐỔI KỆ' : 'CHỌN KỆ', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            onPressed: () {
              setState(() {
                _itemTransferStep = 1;
              });
              _uhf.setScanMode(PdaScanMode.barcode);
              setState(() => _currentScanMode = PdaScanMode.barcode);
            },
          ),
        ],
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

  Widget _buildMergePalletBanner(EyeCareColors c) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PdaMergePalletsScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.merge_rounded, color: Color(0xFFF59E0B), size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Gộp Pallet: Dồn hàng 2 pallet bằng quét Barcode',
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 12, color: Color(0xFFF59E0B)),
            ],
          ),
        ),
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
              Icon(icon, size: 14, color: isActive ? const Color(0xFFFFFFFF) : c.textMuted),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive ? const Color(0xFFFFFFFF) : c.textMuted,
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

  Widget _buildLocationScanContent(EyeCareColors c, List<Location> locations) {
    if (locations.isEmpty) {
      return Text('Chưa có vị trí kho trên hệ thống.', style: TextStyle(color: c.textMuted));
    }

    final selectedLoc = locations.where((l) => l.locationId == _selectedLocationId).firstOrNull;

    if (selectedLoc == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildScanPrompt(
            c,
            'Quét Barcode hoặc nhập mã Kệ (Bóp cò hoặc chạm để quét)',
            Icons.qr_code_scanner,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('location_barcode_input'),
                  controller: _locationInputCtrl,
                  style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'Nhập mã Kệ (VD: KHU-HA-TANG, A-01)...',
                    hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                    prefixIcon: Icon(
                      Icons.qr_code_scanner,
                      color: c.rfidCyan,
                      size: 18,
                    ),
                    filled: true,
                    fillColor: c.bgDeep,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: const BorderRadius.all(Radius.circular(8)), borderSide: BorderSide(color: c.rfidCyan)),
                  ),
                  onSubmitted: (val) {
                    if (val.trim().isNotEmpty) {
                      _handleScan(val, source: 'Manual/Barcode');
                      _locationInputCtrl.clear();
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.rfidCyan,
                  foregroundColor: const Color(0xFFFFFFFF),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  if (_locationInputCtrl.text.trim().isNotEmpty) {
                    _handleScan(_locationInputCtrl.text, source: 'Manual/Barcode');
                    _locationInputCtrl.clear();
                  }
                },
                child: const Icon(Icons.check, color: Color(0xFFFFFFFF), size: 18),
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
                  icon: const Icon(Icons.shelves, size: 16),
                  label: const Text('CHỌN TỪ DANH SÁCH KỆ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  onPressed: () => _openLocationPicker(c, locations),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: c.bgDeep,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: c.rfidCyan.withValues(alpha: 0.6), width: 1.2),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: c.rfidCyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.shelves, color: c.rfidCyan, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${selectedLoc.locationCode} • ${selectedLoc.displayName}',
                      style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Khu vực: ${selectedLoc.zone} • Tầng: ${selectedLoc.level}',
                      style: TextStyle(color: c.textSecondary, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.rfidCyan,
                  side: BorderSide(color: c.rfidCyan),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                icon: const Icon(Icons.refresh_rounded, size: 14),
                label: const Text('ĐỔI KỆ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: () => setState(() => _selectedLocationId = null),
              ),
            ],
          ),
        ),
        if (_mode == _TransferMode.items) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                elevation: 1,
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text(
                'TIẾP TỤC: QUÉT SẢN PHẨM (BƯỚC 2) ➔',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              onPressed: () {
                setState(() {
                  _itemTransferStep = 2;
                });
                _uhf.setScanMode(PdaScanMode.rfid);
                setState(() => _currentScanMode = PdaScanMode.rfid);
              },
            ),
          ),
        ],
      ],
    );
  }

  void _openLocationPicker(EyeCareColors c, List<Location> locations) {
    final searchCtrl = TextEditingController();
    List<Location> filtered = List.from(locations);

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
                      Icon(Icons.shelves, color: c.rfidCyan, size: 22),
                      const SizedBox(width: 8),
                      Text('Chọn Kệ Kho Đích',
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
                      hintText: 'Tìm theo mã kệ, tên kệ, khu vực...',
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
                        filtered = locations.where((loc) {
                          if (q.isEmpty) return true;
                          return loc.locationCode.toLowerCase().contains(q) ||
                              loc.displayName.toLowerCase().contains(q) ||
                              loc.zone.toLowerCase().contains(q) ||
                              loc.shelf.toLowerCase().contains(q) ||
                              loc.locationId.toLowerCase().contains(q);
                        }).toList();
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? Center(child: Text('Không tìm thấy Kệ phù hợp', style: TextStyle(color: c.textMuted)))
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                            itemBuilder: (_, idx) {
                              final loc = filtered[idx];
                              final isSelected = _selectedLocationId == loc.locationId;

                              return ListTile(
                                dense: true,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                leading: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: isSelected ? c.rfidCyan.withValues(alpha: 0.2) : c.bgDeep,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Icon(
                                    isSelected ? Icons.check_circle : Icons.shelves,
                                    color: isSelected ? c.rfidCyan : c.textMuted,
                                    size: 18,
                                  ),
                                ),
                                title: Text('${loc.locationCode} • ${loc.displayName}',
                                    style: TextStyle(color: c.textPrimary, fontSize: 13.5, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis),
                                subtitle: Text('Khu: ${loc.zone} • Kệ: ${loc.shelf} • Tầng: ${loc.level}',
                                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                                    overflow: TextOverflow.ellipsis),
                                trailing: isSelected
                                    ? Text('Đã chọn', style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.bold))
                                    : ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: c.rfidCyan,
                                          foregroundColor: const Color(0xFFFFFFFF),
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          minimumSize: Size.zero,
                                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                        onPressed: () {
                                          Navigator.pop(ctx);
                                          _handleScan(loc.locationCode, source: 'Picker');
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
          if (_selectedLocationId == null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 15),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Khuyên dùng: Quét Barcode Kệ đích ở Bước 1 trước.',
                      style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          _buildScanPrompt(
            c,
            _currentScanMode == PdaScanMode.barcode
                ? 'Quét Barcode hoặc nhập mã Pallet'
                : 'Quét thẻ RFID Pallet',
            _currentScanMode == PdaScanMode.barcode ? Icons.qr_code_scanner : Icons.nfc,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('pallet_barcode_input'),
                  controller: _palletInputCtrl,
                  style: TextStyle(color: c.textPrimary, fontSize: 13, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'Nhập mã Pallet...',
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
                  foregroundColor: _currentScanMode == PdaScanMode.barcode ? const Color(0xFF10B981) : const Color(0xFF2563EB),
                  side: BorderSide(color: _currentScanMode == PdaScanMode.barcode ? const Color(0xFF10B981) : const Color(0xFF2563EB)),
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
        Text('Pallet đích trên kệ (tùy chọn):',
            style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600)),
        const SizedBox(height: 5),
        _buildTargetPalletDropdown(c),
        const SizedBox(height: 10),
        _buildScanPrompt(
          c,
          _currentScanMode == PdaScanMode.rfid
              ? 'Quét chip RFID hoặc nhập EPC'
              : 'Quét Barcode hoặc nhập mã',
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
                  hintText: 'Nhập mã...',
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
              child: const Icon(Icons.check, color: Color(0xFFFFFFFF), size: 18),
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

  Widget _buildPalletConfirmContent(EyeCareColors c, Location? selectedLoc) {
    final hasEnoughData = _foundPallet != null && _selectedLocationId != null;

    if (!hasEnoughData) {
      final locText = selectedLoc?.displayName ?? (_selectedLocationId != null ? 'Kệ $_selectedLocationId' : 'Chưa chọn (Quét ở Bước 1)');
      final palletText = _foundPallet != null ? '${_foundPallet!.palletCode} (${_palletItems.length} SP)' : 'Chưa quét (Quét ở Bước 2)';

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.bgDeep,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: c.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Bước xác nhận chuyển chống quét nhầm:',
                    style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSummaryRow(
              c,
              label: '1. Kệ kho đích',
              value: locText,
              valueColor: _selectedLocationId != null ? const Color(0xFF10B981) : c.textMuted,
            ),
            const SizedBox(height: 6),
            _buildSummaryRow(
              c,
              label: '2. Pallet cần chuyển',
              value: palletText,
              valueColor: _foundPallet != null ? c.rfidCyan : c.textMuted,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 15, color: c.textMuted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Chờ quét đủ Kệ và Pallet để xác nhận',
                      style: TextStyle(color: c.textMuted, fontSize: 11.5, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final oldLoc = _foundPallet!.locationId != null
        ? _repo.locations.where((l) => l.locationId == _foundPallet!.locationId || l.locationCode == _foundPallet!.locationId).firstOrNull
        : null;
    final oldLocDisplay = oldLoc?.displayName ?? (_foundPallet!.locationId ?? 'Chưa có vị trí');
    final targetLocName = selectedLoc?.displayName ?? (_selectedLocationId ?? '');

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
                  label: 'Pallet cần chuyển',
                  value: _foundPallet!.palletCode,
                  valueColor: c.rfidCyan),
              const SizedBox(height: 6),
              _buildSummaryRow(c,
                  label: 'Vị trí hiện tại',
                  value: oldLocDisplay),
              const SizedBox(height: 6),
              _buildSummaryRow(c,
                  label: 'Chuyển đến Kệ đích',
                  value: targetLocName,
                  valueColor: const Color(0xFF10B981)),
              const SizedBox(height: 6),
              _buildSummaryRow(c,
                  label: 'Số sản phẩm trên Pallet',
                  value: '${_palletItems.length} sản phẩm',
                  valueColor: c.textPrimary),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.errorCoral,
                  side: BorderSide(color: c.errorCoral),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'HỦY / QUÉT LẠI',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                onPressed: _isProcessing ? null : _reset,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: _isProcessing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded, size: 18),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _isProcessing ? 'Đang chuyển...' : 'XÁC NHẬN CHUYỂN',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
                onPressed: _isProcessing
                    ? null
                    : () => _showPalletConfirmDialog(_foundPallet!, _palletItems, selectedLoc),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildItemsConfirmContent(EyeCareColors c, Location? selectedLoc) {
    if (_scannedItems.isEmpty) {
      final locText = selectedLoc?.displayName ?? (_selectedLocationId != null ? 'Kệ $_selectedLocationId' : 'Chưa chọn');

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.bgDeep,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 16, color: c.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Bước xác nhận chuyển chống quét nhầm:',
                    style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildSummaryRow(
              c,
              label: '1. Kệ kho đích',
              value: locText,
              valueColor: const Color(0xFF10B981),
            ),
            const SizedBox(height: 6),
            _buildSummaryRow(
              c,
              label: '2. Số sản phẩm đã quét',
              value: '0 sản phẩm',
              valueColor: c.textMuted,
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 10),
              decoration: BoxDecoration(
                color: c.bgCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.border.withValues(alpha: 0.6)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 15, color: c.textMuted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Quét ít nhất 1 sản phẩm để xác nhận',
                      style: TextStyle(color: c.textMuted, fontSize: 11.5, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final targetLocName = selectedLoc?.displayName ?? (_selectedLocationId != null ? 'Kệ $_selectedLocationId' : 'Chưa chọn (Quét ở Bước 1)');

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
                  label: 'Số sản phẩm cần chuyển',
                  value: '${_scannedItems.length} sản phẩm',
                  valueColor: c.rfidCyan),
              const SizedBox(height: 6),
              _buildSummaryRow(c,
                  label: 'Kệ kho đích',
                  value: targetLocName,
                  valueColor: _selectedLocationId != null ? const Color(0xFF10B981) : c.errorCoral),
              const SizedBox(height: 6),
              _buildSummaryRow(c,
                  label: 'Pallet đích',
                  value: _selectedTargetPalletId != null ? 'Pallet $_selectedTargetPalletId' : 'Không gán (để riêng lẻ)',
                  valueColor: c.textSecondary),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              flex: 1,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.errorCoral,
                  side: BorderSide(color: c.errorCoral),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'HỦY / QUÉT LẠI',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                onPressed: _isProcessing ? null : _reset,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 1,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: _isProcessing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_rounded, size: 18),
                label: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _isProcessing ? 'Đang xử lý...' : 'XÁC NHẬN CẬP NHẬT VỊ TRÍ',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                ),
                onPressed: _isProcessing
                    ? null
                    : () {
                        if (_selectedLocationId == null) {
                          setState(() {
                            _errorMessage = 'Vui lòng chọn hoặc quét Barcode kệ kho đích trước!';
                            _itemTransferStep = 1;
                            _uhf.setScanMode(PdaScanMode.barcode);
                            _currentScanMode = PdaScanMode.barcode;
                          });
                          return;
                        }
                        _showItemsConfirmDialog(selectedLoc);
                      },
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showItemsConfirmDialog(Location? targetLoc) async {
    final c = _eyeCare.colors;
    final targetLocDisplay = targetLoc?.displayName ?? (_selectedLocationId ?? 'Chưa chọn kệ');

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
        ),
        titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.swap_horiz_rounded, color: Color(0xFF10B981), size: 22),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Xác Nhận Chuyển Sản Phẩm',
                    style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Kiểm tra thông tin trước khi chuyển để tránh quét nhầm',
                    style: TextStyle(color: c.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.bgDeep,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.border),
                ),
                child: Column(
                  children: [
                    _buildSummaryRow(c,
                        label: 'Tổng số sản phẩm',
                        value: '${_scannedItems.length} mặt hàng',
                        valueColor: c.rfidCyan),
                    const Divider(height: 14),
                    _buildSummaryRow(c,
                        label: 'Chuyển đến Kệ đích',
                        value: targetLocDisplay,
                        valueColor: const Color(0xFF10B981)),
                    if (_selectedTargetPalletId != null) ...[
                      const SizedBox(height: 6),
                      _buildSummaryRow(c,
                          label: 'Gán vào Pallet đích',
                          value: 'Pallet $_selectedTargetPalletId',
                          valueColor: c.textSecondary),
                    ],
                  ],
                ),
              ),
              if (_scannedItems.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Danh sách sản phẩm sẽ chuyển:',
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                ..._scannedItems.take(3).map((it) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${it.productName} (${it.sku})',
                    style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
                if (_scannedItems.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '... và ${_scannedItems.length - 3} sản phẩm khác',
                      style: TextStyle(color: c.textMuted, fontSize: 10.5, fontStyle: FontStyle.italic),
                    ),
                  ),
              ],
            ],
          ),
        ),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.errorCoral,
                    side: BorderSide(color: c.errorCoral),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.pop(ctx),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('HỦY BỎ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.check_circle_rounded, size: 15),
                  label: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('XÁC NHẬN CHUYỂN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _confirmTransfer();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
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
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        if (_isScanning) {
          _stopHardwareScan();
        } else {
          _startHardwareScan();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: _isScanning ? const Color(0xFF10B981).withValues(alpha: 0.1) : c.bgDeep,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _isScanning ? const Color(0xFF10B981) : c.border.withValues(alpha: 0.5),
            width: _isScanning ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isScanning ? Icons.sensors : icon,
              color: _isScanning ? const Color(0xFF10B981) : c.textMuted,
              size: 26,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isScanning
                    ? 'Đang phát sóng quét... (Bóp cò hoặc chạm để dừng)'
                    : '$text (Bóp cò hoặc chạm để quét)',
                style: TextStyle(
                  color: _isScanning ? const Color(0xFF10B981) : c.textMuted,
                  fontSize: 13,
                  fontWeight: _isScanning ? FontWeight.bold : FontWeight.normal,
                  fontStyle: _isScanning ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: c.textSecondary, fontSize: 12.5),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(color: valueColor ?? c.textPrimary, fontSize: 12.5, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
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
