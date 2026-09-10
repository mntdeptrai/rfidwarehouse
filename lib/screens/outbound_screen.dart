import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' hide Border;
import '../models/tag_info.dart';
import '../models/wms_models.dart';
import '../services/database_service.dart';
import '../services/uhf_service.dart';
import '../services/warehouse_repository.dart';
import '../services/supabase_sync_service.dart';
import '../theme/eye_care_theme.dart';
import '../widgets/hardware_status_appbar.dart';

/// Màn hình Xuất Kho RFID trên máy PDA:
/// - Giao diện đồng bộ như Nhập hàng (chuẩn Desktop/PDA)
/// - Nạp file lấy hàng hoặc chọn đơn xuất: Tự động gợi ý lấy hàng theo FIFO (nhập trước xuất trước)
/// - Tự động chọn đúng & đủ số lượng yêu cầu trong file, hiển thị rõ Vị trí kệ cần đến lấy
/// - Quét đối soát chip RFID bằng tay cầm PDA (hỗ trợ cò súng vật lý)
/// - Khi quét đủ số lượng: Tự động chuyển tiếp sang trạng thái "CHỜ XUẤT HÀNG"
/// - Chỉ khi nhân viên xác nhận xuất đủ trên tay cầm: Hoàn thành xuất hàng, giải phóng kệ & trừ tồn kho
class OutboundScreen extends StatefulWidget {
  final String? initialOrderNo;
  const OutboundScreen({super.key, this.initialOrderNo});

  @override
  State<OutboundScreen> createState() => _OutboundScreenState();
}

class _OutboundScreenState extends State<OutboundScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final DatabaseService _dbService = DatabaseService();
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final SupabaseSyncService _supabaseSync = SupabaseSyncService();

  // Quy trình 2 bước:
  // 1: Bảng dữ liệu hàng hóa & Gợi ý lấy hàng theo FIFO
  // 2: Quét đối soát tay cầm PDA ➜ Chờ xuất hàng ➜ Xác nhận xuất đủ
  int _wizardStep = 1;

  // Bước 1 State: Danh sách gợi ý FIFO & Nạp file
  final List<Map<String, dynamic>> _suggestedFifoItems = [];
  final Set<String> _selectedEpcs = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  OutboundOrder? _selectedOrder;
  String? _loadedFileName;
  bool _isImporting = false;

  // Bước 2 State: Quét đối soát RFID PDA
  final Map<String, TagInfo> _scannedTags = {};
  final Map<String, TagInfo> _unexpectedTags = {};
  bool _isScanning = false;
  bool _isSaving = false;
  String _activeFilter = 'ALL'; // 'ALL', 'MATCHED', 'PENDING', 'UNEXPECTED'

  StreamSubscription<TagInfo>? _tagSubscription;
  StreamSubscription<bool>? _triggerSubscription;
  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onStateChange);
    _repo.addListener(_onStateChange);

    _uhf.setScanMode(PdaScanMode.rfid);
    _initHardwareListeners();
    _initInitialData();

    // Đồng bộ nhanh từ Supabase Cloud nếu có kết nối
    Future.microtask(() async {
      await _supabaseSync.syncNow();
      if (mounted) setState(() {});
    });
  }

  void _onStateChange() {
    if (mounted) setState(() {});
  }

  void _initInitialData() {
    if (_repo.outboundOrders.isNotEmpty) {
      if (widget.initialOrderNo != null) {
        _selectedOrder = _repo.outboundOrders.where((o) => o.poNo == widget.initialOrderNo || o.outboundOrderId == widget.initialOrderNo).firstOrNull;
      }
      _selectedOrder ??= _repo.outboundOrders.where(
        (o) => o.status != OutboundOrderStatus.shipped,
      ).firstOrNull ?? _repo.outboundOrders.first;

      if (_selectedOrder != null && _suggestedFifoItems.isEmpty) {
        _applyOrderToFifoSuggestions(_selectedOrder!);
      }
    }
  }

  void _initHardwareListeners() {
    _tagSubscription = _uhf.onTagRead.listen((tag) {
      if (!mounted) return;
      _handleIncomingTag(tag);
    });

    _triggerSubscription = _uhf.onTriggerStateChanged.listen((isPressed) {
      if (!mounted) return;
      if (isPressed && !_isScanning) {
        _startScan();
      } else if (!isPressed && _isScanning) {
        _stopScan();
      }
    });
  }

  void _scheduleUiRefresh() {
    if (_uiRefreshTimer?.isActive ?? false) return;
    _uiRefreshTimer = Timer(const Duration(milliseconds: 60), () {
      if (mounted) setState(() {});
    });
  }

  void _handleIncomingTag(TagInfo tag) {
    final cleanEpc = tag.epc.trim().toUpperCase();
    if (cleanEpc.isEmpty) return;

    // Chỉ nhận diện khi đang ở Bước 2
    if (_wizardStep == 2) {
      if (_selectedEpcs.contains(cleanEpc)) {
        if (!_scannedTags.containsKey(cleanEpc)) {
          _scannedTags[cleanEpc] = tag;
          _unexpectedTags.remove(cleanEpc);
          if (_uhf.hapticEnabled) HapticFeedback.selectionClick();
          _scheduleUiRefresh();
        }
      } else {
        if (!_unexpectedTags.containsKey(cleanEpc)) {
          _unexpectedTags[cleanEpc] = tag;
          if (_uhf.hapticEnabled) HapticFeedback.heavyImpact();
          _scheduleUiRefresh();
        }
      }
    }
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    _tagSubscription?.cancel();
    _triggerSubscription?.cancel();
    _eyeCare.removeListener(_onStateChange);
    _repo.removeListener(_onStateChange);
    _searchController.dispose();
    super.dispose();
  }

  void _startScan() {
    if (_isScanning) return;
    HapticFeedback.mediumImpact();
    setState(() => _isScanning = true);
    _uhf.startInventory();
  }

  void _stopScan() {
    if (!_isScanning) return;
    HapticFeedback.mediumImpact();
    setState(() => _isScanning = false);
    _uhf.stopInventory();
  }

  void _toggleScan() {
    if (_isScanning) {
      _stopScan();
    } else {
      _startScan();
    }
  }

  void _clearScannedList() {
    HapticFeedback.selectionClick();
    setState(() {
      _scannedTags.clear();
      _unexpectedTags.clear();
      _uhf.clearTags();
    });
  }

  // =======================================================
  // THUẬT TOÁN GỢI Ý LẤY HÀNG FIFO (NHẬP TRƯỚC - XUẤT TRƯỚC)
  // =======================================================

  /// Tự động quét kho, lọc các sản phẩm có cùng SKU đang tồn kho (inStock),
  /// sắp xếp theo ngày nhập (inboundTime) từ cũ nhất đến mới nhất (FIFO),
  /// và tự động tích chọn đủ số lượng yêu cầu trong file.
  void _applyFifoDemands({
    required Map<String, int> skuDemands,
    String? orderNo,
    String? fileName,
  }) {
    final List<Map<String, dynamic>> suggestions = [];
    final Set<String> autoSelected = {};
    final List<String> warnings = [];

    for (final entry in skuDemands.entries) {
      final sku = entry.key.trim();
      final requiredQty = entry.value;
      if (requiredQty <= 0) continue;

      // 1. Lọc tất cả sản phẩm trong kho có SKU này và đang ở trạng thái tồn kho (inStock hoặc waitingShipment)
      final availableItems = _repo.items.where((it) {
        final matchSku = it.sku.toUpperCase() == sku.toUpperCase() ||
            it.productId.toUpperCase() == sku.toUpperCase();
        final isInStock = it.status == ItemStatus.inStock ||
            it.status == ItemStatus.waitingShipment ||
            it.status == ItemStatus.allocated;
        return matchSku && isInStock;
      }).toList();

      // 2. Sắp xếp theo FIFO: thời gian nhập kho (inboundTime) cũ nhất / xa hiện tại nhất lên đầu
      availableItems.sort((a, b) {
        final timeA = a.inboundTime;
        final timeB = b.inboundTime;
        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1;
        if (timeB == null) return -1;
        return timeA.compareTo(timeB);
      });

      // 3. Tự động chọn đúng & đủ số lượng yêu cầu trong file
      final pickedItems = availableItems.take(requiredQty).toList();
      if (pickedItems.length < requiredQty) {
        warnings.add('SKU "$sku": Cần $requiredQty nhưng kho chỉ còn ${pickedItems.length} SP!');
      }

      for (var item in pickedItems) {
        // Tra cứu vị trí kệ cụ thể để thủ kho biết chính xác vị trí cần đến lấy
        String locCode = 'CHƯA GÁN KỆ';
        if (item.locationId != null && item.locationId!.trim().isNotEmpty) {
          final loc = _repo.locations.where((l) =>
              l.locationId == item.locationId || l.locationCode == item.locationId).firstOrNull;
          locCode = loc?.locationCode ?? item.locationId!;
        } else if (item.palletId != null) {
          final pal = _repo.pallets.where((p) =>
              p.palletId == item.palletId || p.palletCode == item.palletId).firstOrNull;
          if (pal?.locationId != null && pal!.locationId!.trim().isNotEmpty) {
            final loc = _repo.locations.where((l) =>
                l.locationId == pal.locationId || l.locationCode == pal.locationId).firstOrNull;
            locCode = loc?.locationCode ?? pal.locationId!;
          }
        }

        final cleanEpc = item.epc.trim().toUpperCase();
        autoSelected.add(cleanEpc);

        suggestions.add({
          'item': item,
          'epc': cleanEpc,
          'sku': item.sku,
          'productName': item.productName,
          'locationCode': locCode,
          'palletCode': item.palletId ?? '--',
          'inboundTime': item.inboundTime,
          'orderNo': orderNo ?? item.orderNo ?? '--',
          'isFifo': true,
        });
      }
    }

    // 4. Ưu tiên gợi ý xuất kho: Trong trường hợp 1 mã hàng có ngày nhập khác nhau,
    // ưu tiên đẩy gợi ý có ngày nhập xa hiện tại nhất lên đầu
    suggestions.sort((a, b) {
      final skuA = (a['sku'] ?? '').toString().trim().toLowerCase();
      final skuB = (b['sku'] ?? '').toString().trim().toLowerCase();
      final skuComp = skuA.compareTo(skuB);
      if (skuComp != 0) return skuComp;

      final timeA = a['inboundTime'] as DateTime?;
      final timeB = b['inboundTime'] as DateTime?;
      if (timeA == null && timeB == null) return 0;
      if (timeA == null) return 1;
      if (timeB == null) return -1;
      return timeA.compareTo(timeB);
    });

    setState(() {
      _suggestedFifoItems.clear();
      _suggestedFifoItems.addAll(suggestions);
      _selectedEpcs.clear();
      _selectedEpcs.addAll(autoSelected);
      _loadedFileName = fileName;
      _scannedTags.clear();
      _unexpectedTags.clear();
    });

    if (warnings.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFF59E0B),
          duration: const Duration(seconds: 4),
          content: Text(warnings.join('\n')),
        ),
      );
    }
  }

  void _applyOrderToFifoSuggestions(OutboundOrder order) {
    final Map<String, int> demands = {};
    for (final d in order.details) {
      demands[d.sku] = d.requiredQty;
    }
    _applyFifoDemands(
      skuDemands: demands,
      orderNo: order.poNo,
      fileName: 'Đơn xuất: ${order.poNo}',
    );
  }

  // =======================================================
  // NẠP FILE EXCEL & LÀM MỚI DỮ LIỆU (ĐỒNG BỘ DESKTOP)
  // =======================================================

  Future<void> _pickAndLoadOutboundExcelFile() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls', 'csv'],
      );

      if (files.isEmpty) return;

      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) throw Exception('Tệp rỗng hoặc không đọc được.');

      final excel = Excel.decodeBytes(bytes);
      if (excel.tables.isEmpty) throw Exception('Tệp Excel rỗng.');

      final sheetName = excel.tables.keys.first;
      final sheet = excel.tables[sheetName]!;
      final rows = sheet.rows;
      if (rows.isEmpty) throw Exception('Bảng dữ liệu không có dòng nào.');

      // Phân tích header linh hoạt
      int? skuCol;
      int? qtyCol;
      int? epcCol;
      int? orderCol;
      int startRow = 0;

      final firstRow = rows.first;
      final headers = firstRow.map((c) => _cellToString(c?.value).toLowerCase()).toList();
      bool hasHeader = false;

      for (int i = 0; i < headers.length; i++) {
        final h = headers[i];
        if (h.contains('sku') || h.contains('mã sp') || h.contains('mã hàng') || h.contains('barcode') || h.contains('code')) {
          skuCol = i;
          hasHeader = true;
        } else if (h.contains('qty') || h.contains('số lượng') || h.contains('sl') || h.contains('quantity')) {
          qtyCol = i;
          hasHeader = true;
        } else if (h.contains('epc') || h.contains('serial') || h.contains('chip') || h.contains('rfid')) {
          epcCol = i;
          hasHeader = true;
        } else if (h.contains('order') || h.contains('đơn') || h.contains('po') || h.contains('phiếu') || h.contains('carton')) {
          orderCol = i;
          hasHeader = true;
        }
      }

      if (hasHeader) startRow = 1;
      skuCol ??= 0;
      qtyCol ??= (headers.length > 1 ? 1 : null);

      final Map<String, int> demands = {};
      final Set<String> directEpcs = {};
      String? detectedOrderNo;

      for (int r = startRow; r < rows.length; r++) {
        final row = rows[r];
        if (row.isEmpty) continue;

        if (orderCol != null && orderCol < row.length) {
          final ord = _cellToString(row[orderCol]?.value).trim();
          if (ord.isNotEmpty && detectedOrderNo == null) detectedOrderNo = ord;
        }

        // Nếu file có danh sách EPC cụ thể
        if (epcCol != null && epcCol < row.length) {
          final epc = _cellToString(row[epcCol]?.value).trim().toUpperCase();
          if (epc.isNotEmpty) {
            directEpcs.add(epc);
          }
        }

        // Nếu file có SKU và Số lượng
        if (skuCol < row.length) {
          final sku = _cellToString(row[skuCol]?.value).trim();
          if (sku.isNotEmpty) {
            int qty = 1;
            if (qtyCol != null && qtyCol < row.length) {
              final rawQty = _cellToString(row[qtyCol]?.value).trim();
              qty = int.tryParse(rawQty) ?? 1;
            }
            demands[sku] = (demands[sku] ?? 0) + (qty > 0 ? qty : 1);
          }
        }
      }

      if (directEpcs.isNotEmpty && demands.isEmpty) {
        // Tự động tìm SKU của các EPC này trong kho để chạy FIFO
        for (final epc in directEpcs) {
          final it = _repo.items.where((i) => i.epc.toUpperCase() == epc).firstOrNull;
          if (it != null) {
            demands[it.sku] = (demands[it.sku] ?? 0) + 1;
          }
        }
      }

      if (demands.isEmpty) {
        throw Exception('Không tìm thấy cột Mã SKU hoặc Số lượng hợp lệ trong file!');
      }

      _applyFifoDemands(
        skuDemands: demands,
        orderNo: detectedOrderNo ?? 'FILE-XUẤT-${DateTime.now().millisecondsSinceEpoch % 10000}',
        fileName: file.name,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            content: Text('Đã nạp file và gợi ý ${_suggestedFifoItems.length} sản phẩm theo FIFO (Nhập trước - Xuất trước)!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi nạp file xuất hàng: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  String _cellToString(dynamic val) {
    if (val == null) return '';
    if (val is TextCellValue) return val.value.text ?? '';
    if (val is IntCellValue) return val.value.toString();
    if (val is DoubleCellValue) {
      return (val.value == val.value.toInt()) ? val.value.toInt().toString() : val.value.toString();
    }
    return val.toString().trim();
  }

  Future<void> _handleRefreshOrClearFile() async {
    if (_isImporting) return;
    setState(() => _isImporting = true);
    try {
      final messenger = ScaffoldMessenger.of(context);
      final hadLoadedData = _suggestedFifoItems.isNotEmpty || _selectedEpcs.isNotEmpty;

      _uhf.stopInventory();
      _isScanning = false;

      _suggestedFifoItems.clear();
      _selectedEpcs.clear();
      _scannedTags.clear();
      _unexpectedTags.clear();
      _searchController.clear();
      _searchQuery = '';
      _loadedFileName = null;
      _wizardStep = 1;

      // Đồng bộ lại CSDL
      await _supabaseSync.syncNow();
      await _repo.reloadFromSqlite();

      if (mounted) {
        setState(() {});
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 2),
            content: Text(
              hadLoadedData
                  ? 'Đã xóa dữ liệu file đã nạp. Bạn có thể chọn nạp file mới!'
                  : 'Đã làm mới và đồng bộ dữ liệu kho thành công!',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi khi làm mới: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  void _showSelectOrderDialog() {
    final pendingOrders = _repo.outboundOrders.where((o) => o.status != OutboundOrderStatus.shipped).toList();
    final c = _eyeCare.colors;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCardElevated,
        title: Row(
          children: [
            Icon(Icons.receipt_long, color: c.rfidCyan, size: 22),
            const SizedBox(width: 8),
            Text('CHỌN ĐƠN XUẤT KHO', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: pendingOrders.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Không có đơn xuất kho nào đang chờ xử lý.', style: TextStyle(color: c.textSecondary)),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: pendingOrders.length,
                  separatorBuilder: (_, _) => Divider(color: c.border, height: 1),
                  itemBuilder: (context, idx) {
                    final ord = pendingOrders[idx];
                    final totalQty = ord.details.fold<int>(0, (sum, d) => sum + d.requiredQty);
                    return ListTile(
                      dense: true,
                      title: Text(ord.poNo, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold)),
                      subtitle: Text('Khách: ${ord.customer} • $totalQty SP', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFFF59E0B)),
                        ),
                        child: Text(ord.status.label, style: const TextStyle(color: Color(0xFFF59E0B), fontSize: 10, fontWeight: FontWeight.bold)),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _selectedOrder = ord;
                        _applyOrderToFifoSuggestions(ord);
                      },
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('ĐÓNG', style: TextStyle(color: c.textSecondary)),
          ),
        ],
      ),
    );
  }

  void _showCreateQuickOrderDialog() {
    final c = _eyeCare.colors;
    final poController = TextEditingController(text: 'XK-${DateTime.now().millisecondsSinceEpoch % 100000}');
    final qtyController = TextEditingController(text: '5');
    String? selectedSku;

    final inStockSkus = _repo.items
        .where((i) => i.status == ItemStatus.inStock)
        .map((i) => i.sku)
        .toSet()
        .toList();

    if (inStockSkus.isNotEmpty) {
      selectedSku = inStockSkus.first;
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          backgroundColor: c.bgCardElevated,
          title: Row(
            children: [
              Icon(Icons.post_add, color: c.rfidCyan, size: 22),
              const SizedBox(width: 8),
              Text('TẠO NHANH ĐƠN XUẤT', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: poController,
                style: TextStyle(color: c.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Mã Phiếu/Đơn Xuất',
                  labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: c.bgCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedSku,
                dropdownColor: c.bgCardElevated,
                decoration: InputDecoration(
                  labelText: 'Chọn SKU Cần Xuất',
                  labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: c.bgCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                items: inStockSkus.map((sku) {
                  final stockCount = _repo.items.where((i) => i.sku == sku && i.status == ItemStatus.inStock).length;
                  return DropdownMenuItem(
                    value: sku,
                    child: Text('$sku (Tồn: $stockCount)', style: TextStyle(color: c.textPrimary, fontSize: 13)),
                  );
                }).toList(),
                onChanged: (v) => setDlgState(() => selectedSku = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyController,
                keyboardType: TextInputType.number,
                style: TextStyle(color: c.textPrimary, fontSize: 13),
                decoration: InputDecoration(
                  labelText: 'Số Lượng Cần Xuất',
                  labelStyle: TextStyle(color: c.textSecondary, fontSize: 12),
                  filled: true,
                  fillColor: c.bgCard,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan, foregroundColor: const Color(0xFF2C251E)),
              onPressed: () {
                if (selectedSku == null) return;
                final qty = int.tryParse(qtyController.text.trim()) ?? 1;
                Navigator.pop(ctx);
                _applyFifoDemands(
                  skuDemands: {selectedSku!: qty},
                  orderNo: poController.text.trim(),
                  fileName: 'Tạo nhanh: ${poController.text.trim()}',
                );
              },
              child: const Text('GỢI Ý FIFO', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  // =======================================================
  // XÁC NHẬN XUẤT ĐỦ (HOÀN THÀNH XUẤT HÀNG & CẬP NHẬT KHO)
  // =======================================================

  Future<void> _confirmOutboundCompletion() async {
    if (_isSaving) return;

    final c = _eyeCare.colors;
    final totalRequired = _selectedEpcs.length;
    final totalScanned = _scannedTags.length;

    // Hiển thị Dialog xác nhận chi tiết trước khi cập nhật
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.bgCardElevated,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.verified_outlined, color: Color(0xFF10B981), size: 24),
            SizedBox(width: 10),
            Text('XÁC NHẬN XUẤT ĐỦ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bạn có chắc chắn muốn xác nhận xuất đủ và hoàn tất đơn xuất kho này?',
              style: TextStyle(color: c.textPrimary, fontSize: 13.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Số lượng xuất:', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                      Text('$totalScanned / $totalRequired sản phẩm', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Mã chứng từ:', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                      Text(_selectedOrder?.poNo ?? _loadedFileName ?? 'XUẤT-FIFO', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Thao tác kho:', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                      const Text('Trừ tồn kho & Giải phóng kệ', style: TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 11)),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(foregroundColor: c.textSecondary),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('HỦY BỎ'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('XÁC NHẬN HOÀN TẤT', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isSaving = true);
    try {
      final shippedEpcs = _scannedTags.keys.toList();
      final now = DateTime.now();
      final performedBy = 'Thủ kho PDA';
      final poNo = _selectedOrder?.poNo ?? _loadedFileName ?? 'XUẤT-FIFO-${now.millisecondsSinceEpoch % 10000}';

      final List<Item> itemsToUpdate = [];

      // 1. Cập nhật trạng thái từng item sang OUT và giải phóng kệ/pallet
      for (final epc in shippedEpcs) {
        final item = _repo.items.where((it) => it.epc.toUpperCase() == epc).firstOrNull;
        if (item != null) {
          item.status = ItemStatus.out;
          item.locationId = null;
          if (item.palletId != null) {
            final pal = _repo.pallets.where((p) => p.palletId == item.palletId).firstOrNull;
            pal?.itemIds.remove(item.itemId);
          }
          itemsToUpdate.add(item);
        }
      }

      if (itemsToUpdate.isNotEmpty) {
        await _repo.insertDirectItems(itemsToUpdate);
      }

      // 2. Cập nhật đơn xuất kho nếu có
      if (_selectedOrder != null) {
        _selectedOrder!.status = OutboundOrderStatus.shipped;
        await _dbService.updateOutboundOrderStatus(_selectedOrder!.outboundOrderId, OutboundOrderStatus.shipped);
      }

      // 3. Ghi nhận lịch sử giao dịch kho
      _repo.transactions.insert(
        0,
        InventoryTransaction(
          transactionId: 'TX-${now.millisecondsSinceEpoch}',
          type: TransactionType.outbound,
          documentNo: poNo,
          sku: 'MULTI-SKU-FIFO',
          productName: 'Xuất kho RFID (Gợi ý FIFO)',
          quantity: shippedEpcs.length,
          fromLocation: 'KHO_TONG',
          toLocation: 'XUẤT_GIAO',
          performedBy: performedBy,
          timestamp: now,
          notes: 'Xuất kho thành công $totalScanned chip RFID trên máy PDA theo gợi ý FIFO',
        ),
      );

      // 4. Đồng bộ Supabase Cloud & SQLite
      await _supabaseSync.syncNow();
      await _repo.reloadFromSqlite();

      if (_uhf.hapticEnabled) HapticFeedback.heavyImpact();

      if (!mounted) return;

      // Hiển thị Dialog chúc mừng hoàn tất thành công
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          backgroundColor: c.bgCardElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFF10B981),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check, color: Colors.white, size: 40),
              ),
              const SizedBox(height: 16),
              Text(
                '🎉 XUẤT KHO HOÀN TẤT!',
                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 8),
              Text(
                'Đã xuất kho thành công $totalScanned sản phẩm theo đúng chuẩn FIFO.\nVị trí kệ và tồn kho đã được cập nhật chính xác.',
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, fontSize: 12.5),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    // Reset sạch dữ liệu để sẵn sàng cho phiên tiếp theo
                    setState(() {
                      _suggestedFifoItems.clear();
                      _selectedEpcs.clear();
                      _scannedTags.clear();
                      _unexpectedTags.clear();
                      _loadedFileName = null;
                      _wizardStep = 1;
                    });
                  },
                  child: const Text('HOÀN TẤT & LÀM MỚI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi khi xuất kho: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // =======================================================
  // GIAO DIỆN CHÍNH
  // =======================================================

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return Scaffold(
      backgroundColor: c.bgDeep,
      appBar: const HardwareStatusAppBar(title: '📤 XUẤT KHO RFID (PDA)'),
      body: _wizardStep == 1
          ? _buildStep1FifoSelection(c)
          : _buildStep2RfidVerification(c),
    );
  }

  // =======================================================
  // BƯỚC 1: BẢNG DỮ LIỆU GỢI Ý LẤY HÀNG FIFO (CHUẨN DESKTOP)
  // =======================================================

  Widget _buildStep1FifoSelection(EyeCareColors c) {
    final query = _searchQuery.trim().toUpperCase();
    final filteredItems = query.isEmpty
        ? _suggestedFifoItems
        : _suggestedFifoItems.where((item) {
            final loc = (item['locationCode'] ?? '').toString().toUpperCase();
            final pallet = (item['palletCode'] ?? '').toString().toUpperCase();
            final sku = (item['sku'] ?? '').toString().toUpperCase();
            final prodName = (item['productName'] ?? '').toString().toUpperCase();
            final epc = (item['epc'] ?? '').toString().toUpperCase();
            return loc.contains(query) || pallet.contains(query) || sku.contains(query) || prodName.contains(query) || epc.contains(query);
          }).toList();

    final allSelected = _suggestedFifoItems.isNotEmpty &&
        _suggestedFifoItems.every((item) => _selectedEpcs.contains(item['epc']));

    // Tóm tắt vị trí kệ cần đến lấy
    final Map<String, int> locSummary = {};
    for (final it in _suggestedFifoItems) {
      if (_selectedEpcs.contains(it['epc'])) {
        final loc = it['locationCode']?.toString() ?? 'KHO CHỜ XẾP';
        locSummary[loc] = (locSummary[loc] ?? 0) + 1;
      }
    }

    return Column(
      children: [
        // Thanh công cụ XUẤT HÀNG & LÀM MỚI (Tương tự Desktop & Nhập hàng)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: c.bgDeep,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'GỢI Ý LẤY HÀNG (FIFO)',
                      style: TextStyle(
                        color: c.textPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    if (_loadedFileName != null)
                      Text(
                        _loadedFileName!,
                        style: TextStyle(color: c.rfidCyan, fontSize: 10.5, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // Nút Xuất Hàng (Menu popup tương tự Desktop)
                PopupMenuButton<String>(
                  enabled: !_isImporting,
                  tooltip: 'Chọn nguồn nạp yêu cầu xuất',
                  offset: const Offset(0, 38),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: c.border),
                  ),
                  color: c.bgCardElevated,
                  onSelected: (value) {
                    if (_isImporting) return;
                    if (value == 'excel') {
                      _pickAndLoadOutboundExcelFile();
                    } else if (value == 'order') {
                      _showSelectOrderDialog();
                    } else if (value == 'manual') {
                      _showCreateQuickOrderDialog();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'excel',
                      child: Row(
                        children: [
                          const Icon(Icons.table_chart, color: Color(0xFF10B981), size: 18),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Nạp File Lấy Hàng (.xlsx)',
                                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              Text(
                                'Đọc file & Tự động gợi ý FIFO',
                                style: TextStyle(color: c.textSecondary, fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'order',
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long, color: c.rfidCyan, size: 18),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Chọn Từ Đơn Xuất Kho',
                                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              Text(
                                'Đơn xuất có sẵn trong CSDL',
                                style: TextStyle(color: c.textSecondary, fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem<String>(
                      value: 'manual',
                      child: Row(
                        children: [
                          const Icon(Icons.post_add, color: Color(0xFF0284C7), size: 18),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Tạo Nhanh Đơn Xuất',
                                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12),
                              ),
                              Text(
                                'Nhập mã đơn, SKU cần xuất',
                                style: TextStyle(color: c.textSecondary, fontSize: 10),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _isImporting ? c.rfidCyan.withValues(alpha: 0.5) : c.rfidCyan,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: c.rfidCyan.withValues(alpha: 0.25),
                          blurRadius: 4,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isImporting)
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF2C251E)),
                          )
                        else
                          const Icon(Icons.file_download_outlined, size: 16, color: Color(0xFF2C251E)),
                        const SizedBox(width: 5),
                        Text(
                          _isImporting ? 'ĐANG NẠP...' : 'XUẤT HÀNG',
                          style: const TextStyle(
                            color: Color(0xFF2C251E),
                            fontWeight: FontWeight.bold,
                            fontSize: 11.5,
                          ),
                        ),
                        const Icon(Icons.arrow_drop_down, size: 16, color: Color(0xFF2C251E)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Nút Làm Mới (Xóa dữ liệu file đã nạp để chọn lại file khác)
                Tooltip(
                  message: 'Xóa dữ liệu file đã nạp để chọn lại file mới',
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(Icons.refresh, size: 15, color: c.textPrimary),
                    label: Text(
                      'LÀM MỚI',
                      style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                    onPressed: _isImporting ? null : _handleRefreshOrClearFile,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Sub-toolbar: Ô tìm kiếm & Checkbox Chọn tất cả
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: c.bgDeep,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onChanged: (val) => setState(() => _searchQuery = val.trim()),
                  style: TextStyle(color: c.textPrimary, fontSize: 12),
                  decoration: InputDecoration(
                    hintText: 'Tìm theo Kệ, Thùng, SKU, Tên SP, EPC...',
                    hintStyle: TextStyle(color: c.textSecondary.withValues(alpha: 0.5), fontSize: 11),
                    prefixIcon: Icon(Icons.search, size: 15, color: c.textSecondary),
                    filled: true,
                    fillColor: c.bgCard,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                onTap: () {
                  setState(() {
                    if (allSelected) {
                      _selectedEpcs.clear();
                    } else {
                      for (var it in _suggestedFifoItems) {
                        _selectedEpcs.add(it['epc']);
                      }
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  decoration: BoxDecoration(
                    color: allSelected ? c.rfidCyan.withValues(alpha: 0.15) : c.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: allSelected ? c.rfidCyan : c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        allSelected ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 16,
                        color: allSelected ? c.rfidCyan : c.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        allSelected ? 'Bỏ chọn' : 'Chọn hết',
                        style: TextStyle(
                          color: allSelected ? c.rfidCyan : c.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Thẻ thông tin gợi ý FIFO
        if (_suggestedFifoItems.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFFF59E0B), size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Đã tự động chọn hàng theo nguyên tắc FIFO (Nhập trước - Xuất trước).',
                    style: TextStyle(color: c.textPrimary, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  '${_selectedEpcs.length}/${_suggestedFifoItems.length} SP',
                  style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 11.5),
                ),
              ],
            ),
          ),

        // Bảng dữ liệu dạng DataTable cuộn ngang/dọc
        Expanded(
          child: _suggestedFifoItems.isEmpty
              ? _buildEmptyState(c)
              : Container(
                  margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
                  decoration: BoxDecoration(
                    color: c.bgCard,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          headingRowHeight: 38,
                          dataRowMinHeight: 40,
                          dataRowMaxHeight: 48,
                          horizontalMargin: 12,
                          columnSpacing: 16,
                          headingRowColor: WidgetStateProperty.all(c.bgCardElevated),
                          columns: [
                            const DataColumn(label: Text('CHỌN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            const DataColumn(label: Text('STT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            const DataColumn(label: Text('VỊ TRÍ KỆ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFF10B981)))),
                            const DataColumn(label: Text('THÙNG / PALLET', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            const DataColumn(label: Text('MÃ SKU', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            const DataColumn(label: Text('TÊN SẢN PHẨM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            const DataColumn(label: Text('CHIP RFID (EPC)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                            const DataColumn(label: Text('NGÀY NHẬP KHO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFFF59E0B)))),
                            const DataColumn(label: Text('ƯU TIÊN FIFO', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11))),
                          ],
                          rows: List.generate(filteredItems.length, (index) {
                            final item = filteredItems[index];
                            final epc = item['epc'] as String;
                            final isChecked = _selectedEpcs.contains(epc);
                            final inboundDate = item['inboundTime'] as DateTime?;
                            final formattedDate = inboundDate != null
                                ? '${inboundDate.day.toString().padLeft(2, '0')}/${inboundDate.month.toString().padLeft(2, '0')}/${inboundDate.year} ${inboundDate.hour.toString().padLeft(2, '0')}:${inboundDate.minute.toString().padLeft(2, '0')}'
                                : '--';
                            final daysAgo = inboundDate != null ? DateTime.now().difference(inboundDate).inDays : 0;
                            final sameSkuItems = filteredItems.where((x) =>
                                (x['sku'] ?? '').toString().trim().toLowerCase() ==
                                    (item['sku'] ?? '').toString().trim().toLowerCase() &&
                                x['inboundTime'] is DateTime).toList();
                            final isOldestForSku = sameSkuItems.isNotEmpty &&
                                (inboundDate != null &&
                                    !sameSkuItems.any((x) => (x['inboundTime'] as DateTime).isBefore(inboundDate)));

                            return DataRow(
                              color: WidgetStateProperty.resolveWith((states) {
                                if (isChecked) return c.rfidCyan.withValues(alpha: 0.06);
                                return index.isEven ? c.bgCard.withValues(alpha: 0.5) : c.bgCardElevated.withValues(alpha: 0.3);
                              }),
                              cells: [
                                DataCell(
                                  Checkbox(
                                    value: isChecked,
                                    activeColor: c.rfidCyan,
                                    checkColor: const Color(0xFF2C251E),
                                    visualDensity: VisualDensity.compact,
                                    onChanged: (val) {
                                      setState(() {
                                        if (val == true) {
                                          _selectedEpcs.add(epc);
                                        } else {
                                          _selectedEpcs.remove(epc);
                                        }
                                      });
                                    },
                                  ),
                                ),
                                DataCell(Text('${index + 1}', style: TextStyle(color: c.textSecondary, fontSize: 11))),
                                // VỊ TRÍ KỆ (Badge xanh nổi bật)
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFF10B981), width: 1.2),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(Icons.shelves, size: 12, color: Color(0xFF10B981)),
                                        const SizedBox(width: 4),
                                        Text(
                                          item['locationCode'] ?? '--',
                                          style: const TextStyle(
                                            color: Color(0xFF10B981),
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11.5,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                DataCell(Text(item['palletCode'] ?? '--', style: TextStyle(color: c.textPrimary, fontSize: 11.5))),
                                DataCell(Text(item['sku'] ?? '--', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 11.5))),
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 180),
                                    child: Text(
                                      item['productName'] ?? '--',
                                      style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    epc,
                                    style: TextStyle(
                                      color: c.rfidCyan,
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.w600,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                                DataCell(
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        formattedDate,
                                        style: TextStyle(
                                          color: isOldestForSku ? const Color(0xFFF59E0B) : c.textPrimary,
                                          fontSize: 11,
                                          fontWeight: isOldestForSku ? FontWeight.bold : FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        daysAgo > 0 ? '$daysAgo ngày trước' : 'Hôm nay',
                                        style: TextStyle(color: c.textSecondary, fontSize: 10),
                                      ),
                                    ],
                                  ),
                                ),
                                DataCell(
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isOldestForSku ? const Color(0xFFF59E0B).withValues(alpha: 0.2) : c.bgCardElevated,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isOldestForSku ? const Color(0xFFF59E0B) : c.border,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      isOldestForSku ? '⚡ FIFO Xa nhất' : 'Lô mới hơn',
                                      style: TextStyle(
                                        color: isOldestForSku ? const Color(0xFFF59E0B) : c.textSecondary,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ),
                    ),
                  ),
                ),
        ),

        // Bottom Bar: Tóm tắt & Nút Chuyển Tiếp Bước 2 Quét Tay Cầm
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.bgCardElevated,
            border: Border(top: BorderSide(color: c.border)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Text('ĐÃ CHỌN: ', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                          Text(
                            '${_selectedEpcs.length} / ${_suggestedFifoItems.length} SP',
                            style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ],
                      ),
                      if (locSummary.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Kệ cần lấy: ${locSummary.entries.map((e) => "${e.key} (${e.value})").join(", ")}',
                          style: TextStyle(color: c.textSecondary, fontSize: 10.5),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.rfidCyan,
                      foregroundColor: const Color(0xFF2C251E),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                    label: const Text(
                      'TIẾP TỤC: QUÉT TAY CẦM',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: _selectedEpcs.isEmpty
                        ? null
                        : () {
                            setState(() {
                              _wizardStep = 2;
                              _scannedTags.clear();
                              _unexpectedTags.clear();
                            });
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(EyeCareColors c) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: c.rfidCyan.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.inventory_2_outlined, size: 54, color: c.rfidCyan),
            ),
            const SizedBox(height: 16),
            Text(
              'Chưa Có Danh Sách Yêu Cầu Xuất Hàng',
              style: TextStyle(color: c.textPrimary, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Nạp file Excel hoặc chọn đơn xuất kho có sẵn.\nHệ thống sẽ tự động tìm kiếm sản phẩm trong kho và gợi ý lấy hàng theo nguyên tắc FIFO (Nhập trước - Xuất trước).',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.4),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.rfidCyan,
                    foregroundColor: const Color(0xFF2C251E),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('NẠP FILE EXCEL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: _pickAndLoadOutboundExcelFile,
                ),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.textPrimary,
                    side: BorderSide(color: c.border),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: Icon(Icons.receipt_long, size: 18, color: c.rfidCyan),
                  label: const Text('CHỌN ĐƠN CÓ SẴN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  onPressed: _showSelectOrderDialog,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // =======================================================
  // BƯỚC 2: QUÉT ĐỐI SOÁT RFID TAY CẦM & CHỜ XUẤT HÀNG
  // =======================================================

  Widget _buildStep2RfidVerification(EyeCareColors c) {
    final totalRequired = _selectedEpcs.length;
    final scannedCount = _scannedTags.length;
    final isFullyScanned = scannedCount >= totalRequired && totalRequired > 0;
    final progress = totalRequired > 0 ? (scannedCount / totalRequired).clamp(0.0, 1.0) : 0.0;

    return Column(
      children: [
        // Sub-header Bước 2
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: c.bgDeep,
          child: Row(
            children: [
              InkWell(
                onTap: () {
                  _stopScan();
                  setState(() => _wizardStep = 1);
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: c.bgCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back_ios_new, size: 14, color: c.textPrimary),
                      const SizedBox(width: 4),
                      Text('Quay lại bảng FIFO', style: TextStyle(color: c.textPrimary, fontSize: 11.5, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Nút xóa quét
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                  side: const BorderSide(color: Color(0xFFEF4444)),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.delete_sweep_outlined, size: 15),
                label: const Text('XÓA QUÉT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                onPressed: _clearScannedList,
              ),
            ],
          ),
        ),

        // Hero Progress Card: Trực quan hóa tiến độ đối soát
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: c.bgCard,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFullyScanned ? const Color(0xFF10B981) : c.border,
              width: isFullyScanned ? 1.8 : 1,
            ),
            boxShadow: [
              BoxShadow(
                color: (isFullyScanned ? const Color(0xFF10B981) : c.rfidCyan).withValues(alpha: 0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TIẾN ĐỘ ĐỐI SOÁT TAY CẦM', style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '$scannedCount',
                            style: TextStyle(
                              color: isFullyScanned ? const Color(0xFF10B981) : c.textPrimary,
                              fontWeight: FontWeight.bold,
                              fontSize: 26,
                            ),
                          ),
                          Text(' / $totalRequired ĐÃ KHỚP', style: TextStyle(color: c.textSecondary, fontWeight: FontWeight.bold, fontSize: 13)),
                        ],
                      ),
                    ],
                  ),
                  // Nút bật/tắt quét trực tiếp
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isScanning ? const Color(0xFFEF4444) : c.rfidCyan,
                      foregroundColor: _isScanning ? Colors.white : const Color(0xFF2C251E),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: Icon(_isScanning ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 20),
                    label: Text(
                      _isScanning ? 'DỪNG' : 'BẮT ĐẦU QUÉT',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    onPressed: _toggleScan,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 8,
                  backgroundColor: c.bgCardElevated,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isFullyScanned ? const Color(0xFF10B981) : c.rfidCyan,
                  ),
                ),
              ),
            ],
          ),
        ),

        // BANNER CHUYỂN TIẾP: TRẠNG THÁI "CHỜ XUẤT HÀNG" (KHI ĐÃ QUÉT ĐỦ)
        if (isFullyScanned)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 4, 12, 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF10B981), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Text(
                            'TRẠNG THÁI: CHỜ XUẤT HÀNG',
                            style: TextStyle(
                              color: Color(0xFF10B981),
                              fontWeight: FontWeight.bold,
                              fontSize: 12.5,
                            ),
                          ),
                          SizedBox(width: 6),
                          Text('• ĐÃ QUÉT ĐỦ', style: TextStyle(color: Color(0xFF10B981), fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Đã đối soát đủ số lượng theo gợi ý FIFO. Hàng đang chờ xuất tại kho. Nhân viên kiểm tra và bấm Xác Nhận bên dưới để hoàn tất.',
                        style: TextStyle(color: c.textPrimary, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Tabs bộ lọc thẻ chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              _buildFilterTab(c, 'ALL', 'TẤT CẢ (${_selectedEpcs.length})'),
              const SizedBox(width: 6),
              _buildFilterTab(c, 'MATCHED', 'ĐÃ KHỚP ($scannedCount)', color: const Color(0xFF10B981)),
              const SizedBox(width: 6),
              _buildFilterTab(c, 'PENDING', 'CHƯA QUÉT (${totalRequired - scannedCount})', color: const Color(0xFFF59E0B)),
              if (_unexpectedTags.isNotEmpty) ...[
                const SizedBox(width: 6),
                _buildFilterTab(c, 'UNEXPECTED', 'LẠ (${_unexpectedTags.length})', color: const Color(0xFFEF4444)),
              ],
            ],
          ),
        ),

        // Danh sách chip đối soát
        Expanded(
          child: _buildScannedItemsList(c),
        ),

        // NÚT HÀNH ĐỘNG DƯỚI CÙNG: XÁC NHẬN XUẤT ĐỦ ĐỂ CẬP NHẬT KHO
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.bgCardElevated,
            border: Border(top: BorderSide(color: c.border)),
          ),
          child: SafeArea(
            top: false,
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isFullyScanned ? const Color(0xFF10B981) : Colors.grey.shade700,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: isFullyScanned ? 3 : 0,
                ),
                icon: _isSaving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.check_circle_outline, size: 22),
                label: Text(
                  _isSaving
                      ? 'ĐANG CẬP NHẬT KHO...'
                      : (isFullyScanned
                          ? 'XÁC NHẬN XUẤT ĐỦ (HOÀN THÀNH XUẤT KHO)'
                          : 'CẦN QUÉT ĐỦ $totalRequired SP ĐỂ XÁC NHẬN ($scannedCount/$totalRequired)'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                ),
                onPressed: (isFullyScanned && !_isSaving) ? _confirmOutboundCompletion : null,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFilterTab(EyeCareColors c, String key, String label, {Color? color}) {
    final isSelected = _activeFilter == key;
    final tabColor = color ?? c.rfidCyan;

    return InkWell(
      onTap: () => setState(() => _activeFilter = key),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? tabColor.withValues(alpha: 0.15) : c.bgCard,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? tabColor : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? tabColor : c.textSecondary,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            fontSize: 10.5,
          ),
        ),
      ),
    );
  }

  Widget _buildScannedItemsList(EyeCareColors c) {
    // Lọc danh sách theo filter tab
    final List<Map<String, dynamic>> itemsToShow = [];

    if (_activeFilter == 'ALL' || _activeFilter == 'MATCHED' || _activeFilter == 'PENDING') {
      for (final it in _suggestedFifoItems) {
        final epc = it['epc'] as String;
        if (!_selectedEpcs.contains(epc)) continue;
        final isScanned = _scannedTags.containsKey(epc);

        if (_activeFilter == 'ALL' ||
            (_activeFilter == 'MATCHED' && isScanned) ||
            (_activeFilter == 'PENDING' && !isScanned)) {
          itemsToShow.add({
            ...it,
            'isScanned': isScanned,
            'tag': _scannedTags[epc],
            'type': 'EXPECTED',
          });
        }
      }
    }

    if (_activeFilter == 'ALL' || _activeFilter == 'UNEXPECTED') {
      for (final entry in _unexpectedTags.entries) {
        itemsToShow.add({
          'epc': entry.key,
          'sku': 'CHIP LẠ',
          'productName': 'Chưa nằm trong danh sách FIFO được chọn',
          'locationCode': '--',
          'palletCode': '--',
          'isScanned': true,
          'tag': entry.value,
          'type': 'UNEXPECTED',
        });
      }
    }

    if (itemsToShow.isEmpty) {
      return Center(
        child: Text('Không có chip nào trong danh mục này.', style: TextStyle(color: c.textSecondary, fontSize: 12)),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      itemCount: itemsToShow.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, idx) {
        final it = itemsToShow[idx];
        final isScanned = it['isScanned'] == true;
        final isUnexpected = it['type'] == 'UNEXPECTED';

        Color cardBorder = isScanned ? const Color(0xFF10B981) : c.border;
        Color statusBg = isScanned ? const Color(0xFF10B981).withValues(alpha: 0.1) : c.bgCardElevated;
        if (isUnexpected) {
          cardBorder = const Color(0xFFEF4444);
          statusBg = const Color(0xFFEF4444).withValues(alpha: 0.1);
        }

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: c.bgCard,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: cardBorder, width: isScanned ? 1.2 : 1),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: statusBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isUnexpected
                      ? Icons.warning_amber_rounded
                      : (isScanned ? Icons.check_circle_rounded : Icons.radio_button_unchecked),
                  color: isUnexpected
                      ? const Color(0xFFEF4444)
                      : (isScanned ? const Color(0xFF10B981) : c.textSecondary),
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            it['locationCode'] ?? '--',
                            style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 10.5),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(it['sku'] ?? '--', style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      it['productName'] ?? '--',
                      style: TextStyle(color: c.textPrimary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      it['epc'] ?? '--',
                      style: TextStyle(color: c.rfidCyan, fontFamily: 'monospace', fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              Text(
                isUnexpected
                    ? 'CHIP LẠ'
                    : (isScanned ? 'ĐÃ KHỚP' : 'CHỜ QUÉT'),
                style: TextStyle(
                  color: isUnexpected
                      ? const Color(0xFFEF4444)
                      : (isScanned ? const Color(0xFF10B981) : c.textSecondary),
                  fontWeight: FontWeight.bold,
                  fontSize: 10.5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
