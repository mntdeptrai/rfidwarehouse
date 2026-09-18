import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/wms_models.dart';
import '../../services/warehouse_repository.dart';
import '../../services/auth_service.dart';
import '../../services/desktop_uhf_tcp_service.dart';
import '../../services/uhf_service.dart';
import '../../services/excel_import_service.dart';
import '../../theme/eye_care_theme.dart';

/// Màn hình Kiểm Kê Kho & Đối Soát RFID UHF Desktop
/// Nghiệp vụ: Tạo Đơn Kiểm Kê (Toàn kho/Khu vực/Kệ) HOẶC Nạp File Excel Kiểm Kê để Quét Đủ
class DesktopInventoryView extends StatefulWidget {
  const DesktopInventoryView({super.key});

  @override
  State<DesktopInventoryView> createState() => _DesktopInventoryViewState();
}

class _DesktopInventoryViewState extends State<DesktopInventoryView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final AuthService _auth = AuthService();
  final DesktopUhfTcpService _desktopUhf = DesktopUhfTcpService();
  final UhfService _uhf = UhfService();
  final ExcelImportService _excelService = ExcelImportService();

  // Phiên kiểm kê hiện hành đang thực hiện quét đối soát
  InventorySession? _activeSession;

  // Phiên kiểm kê cũ được chọn để xem chi tiết
  InventorySession? _selectedSessionDetail;

  // Danh sách các mã chip RFID đã quét được trong phiên hiện hành
  final Set<String> _scannedEpcs = {};
  bool _isScanning = false;

  // Bộ lọc bảng đối soát
  String _tableFilter = 'ALL'; // ALL, MATCH, MISSING, WRONG_LOC, UNKNOWN
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  StreamSubscription? _desktopUhfSub;
  StreamSubscription? _uhfSub;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onStateUpdate);
    _repo.addListener(_onStateUpdate);

    // Lắng nghe tín hiệu quét từ đầu đọc UHF Fixed/Desktop qua TCP
    _desktopUhfSub = _desktopUhf.onTagRead.listen((tag) {
      if (_isScanning && _activeSession != null) {
        _handleTagScanned(tag.epc);
      }
    });

    // Lắng nghe tín hiệu quét từ máy cầm tay PDA / UHF Service
    _uhfSub = _uhf.onTagRead.listen((tag) {
      if (_isScanning && _activeSession != null) {
        _handleTagScanned(tag.epc);
      }
    });
  }

  @override
  void dispose() {
    _desktopUhfSub?.cancel();
    _uhfSub?.cancel();
    _searchCtrl.dispose();
    _repo.removeListener(_onStateUpdate);
    _eyeCare.removeListener(_onStateUpdate);
    super.dispose();
  }

  void _onStateUpdate() {
    if (mounted) setState(() {});
  }

  /// Xử lý khi nhận diện được 1 mã chip RFID EPC
  void _handleTagScanned(String rawEpc) {
    final epc = rawEpc.trim().toUpperCase();
    if (epc.isEmpty || _activeSession == null) return;

    if (_scannedEpcs.add(epc)) {
      final session = _activeSession!;
      if (session.zone.startsWith('File:')) {
        // Đối soát danh sách hàng nạp từ File Excel
        final matchIdx = session.results.indexWhere((r) => r.epc.toUpperCase() == epc);
        if (matchIdx >= 0) {
          final old = session.results[matchIdx];
          session.results[matchIdx] = InventoryItemResult(
            epc: old.epc,
            sku: old.sku,
            productName: old.productName,
            expectedLocation: old.expectedLocation,
            actualLocation: 'Đã quét RFID',
            resultType: InventoryVarianceType.match,
            readAt: DateTime.now(),
          );
        } else {
          // Thẻ lạ không có trong file Excel
          final knownItem = _repo.items.where((i) => i.epc.toUpperCase() == epc).firstOrNull;
          session.results.add(InventoryItemResult(
            epc: epc,
            sku: knownItem?.sku,
            productName: knownItem?.productName ?? 'Thẻ lạ ngoài file Excel',
            actualLocation: 'Đã quét RFID',
            resultType: InventoryVarianceType.unknownEpc,
            readAt: DateTime.now(),
          ));
        }
      } else {
        _repo.processAuditScan(
          sessionId: session.sessionId,
          scannedEpcs: _scannedEpcs.toList(),
          notify: true,
        );
      }
      if (mounted) setState(() {});
    }
  }

  /// Bắt đầu hoặc tạm dừng quét RFID UHF
  Future<void> _toggleScanning() async {
    if (_activeSession == null) return;

    if (_isScanning) {
      // Dừng quét
      await _desktopUhf.stopInventory();
      setState(() => _isScanning = false);
    } else {
      // Bắt đầu quét
      setState(() => _isScanning = true);
      if (_desktopUhf.isConnected) {
        await _desktopUhf.startInventory();
      }
    }
  }

  /// Làm mới dữ liệu quét của phiên hiện tại (quét lại từ đầu)
  void _resetScannedData() {
    if (_activeSession == null) return;
    setState(() {
      _scannedEpcs.clear();
      final session = _activeSession!;
      if (session.zone.startsWith('File:')) {
        for (int i = session.results.length - 1; i >= 0; i--) {
          final r = session.results[i];
          if (r.resultType == InventoryVarianceType.unknownEpc) {
            session.results.removeAt(i);
          } else {
            session.results[i] = InventoryItemResult(
              epc: r.epc,
              sku: r.sku,
              productName: r.productName,
              expectedLocation: r.expectedLocation,
              resultType: InventoryVarianceType.missing,
              readAt: DateTime.now(),
            );
          }
        }
      } else {
        _repo.processAuditScan(
          sessionId: session.sessionId,
          scannedEpcs: [],
          notify: true,
        );
      }
    });
  }

  /// Hoàn tất phiên kiểm kê và lưu kết quả
  Future<void> _completeActiveSession() async {
    if (_activeSession == null) return;

    if (_isScanning) {
      await _desktopUhf.stopInventory();
      setState(() => _isScanning = false);
    }

    final s = _activeSession!;
    final totalExpected = s.matchCount + s.missingCount;
    final accuracyPercent = totalExpected > 0 ? (s.matchCount / totalExpected * 100).toStringAsFixed(1) : '100.0';

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _eyeCare.colors.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.verified_rounded, color: Color(0xFF10B981), size: 24),
            const SizedBox(width: 10),
            Text('Xác Nhận Hoàn Tất Kiểm Kê', style: TextStyle(color: _eyeCare.colors.textPrimary, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Đợt kiểm kê: ${s.sessionCode}', style: TextStyle(color: _eyeCare.colors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 8),
            Text('• Tổng hàng trong đơn: $totalExpected sản phẩm', style: TextStyle(color: _eyeCare.colors.textSecondary, fontSize: 13)),
            Text('• Đã quét khớp: ${s.matchCount} sản phẩm', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
            Text('• Còn thiếu: ${s.missingCount} sản phẩm', style: const TextStyle(color: Color(0xFFEF4444), fontWeight: FontWeight.bold, fontSize: 13)),
            Text('• Hàng lạ / ngoài đơn: ${s.varianceOrUnknownCount} thẻ chip', style: const TextStyle(color: Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 13)),
            Text('• Tỷ lệ chính xác: $accuracyPercent%', style: TextStyle(color: _eyeCare.colors.rfidCyan, fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 14),
            Text('Bạn có chắc chắn muốn chốt và lưu kết quả đợt kiểm kê này vào CSDL không?', style: TextStyle(color: _eyeCare.colors.textPrimary, fontSize: 13)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('TIẾP TỤC QUÉT', style: TextStyle(color: _eyeCare.colors.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('XÁC NHẬN CHỐT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm == true) {
      final user = _auth.currentUser?.fullName ?? 'Thủ kho (Admin)';
      await _repo.completeInventorySession(s.sessionId, user);
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
          duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF10B981),
            content: Text('✓ Đã chốt và lưu kết quả đợt kiểm kê ${s.sessionCode} thành công!'),
          ),
        );
        setState(() {
          _activeSession = null;
          _scannedEpcs.clear();
        });
      }
    }
  }

  /// Hủy hoặc đóng phiên kiểm kê hiện hành
  Future<void> _cancelActiveSession() async {
    if (_activeSession == null) return;

    if (_isScanning) {
      await _desktopUhf.stopInventory();
      setState(() => _isScanning = false);
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _eyeCare.colors.bgCard,
        title: const Text('Đóng Đơn Kiểm Kê?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Dữ liệu các thẻ đã quét sẽ không được lưu vào báo cáo hoàn thành.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('QUAY LẠI')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ĐỒNG Ý ĐÓNG', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (!mounted) return;
    if (confirm == true) {
      setState(() {
        _activeSession = null;
        _scannedEpcs.clear();
      });
    }
  }

  // ===========================================================================
  // 1. TẠO ĐƠN KIỂM KÊ MỚI (DIALOG CHỌN TOÀN KHO / THEO KHU VỰC / THEO KỆ)
  // ===========================================================================
  void _showCreateSessionDialog() {
    String selectedScope = 'ALL'; // ALL, ZONE, SHELF
    String selectedZone = 'Khu A';
    String? selectedShelf;

    // Lấy danh sách zones và kệ thực tế
    final allZones = _repo.locations.map((l) => l.zone.trim()).where((z) => z.isNotEmpty).toSet().toList();
    if (allZones.isEmpty) allZones.addAll(['Khu A', 'Khu B', 'Khu C']);

    final allShelves = _repo.locations.toList();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final c = _eyeCare.colors;

          return AlertDialog(
            backgroundColor: c.bgCard,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: c.rfidCyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Icon(Icons.add_task_rounded, color: c.rfidCyan, size: 22),
                ),
                const SizedBox(width: 12),
                Text('Tạo Đơn Kiểm Kê Mới', style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Chọn phạm vi kiểm kê hàng hóa:', style: TextStyle(color: c.textSecondary, fontSize: 13, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 12),

                  // Lựa chọn 1: Toàn bộ kho
                  _buildScopeOption(
                    title: 'Toàn Bộ Hàng Hóa Trong Kho',
                    subtitle: 'Kiểm đếm tất cả sản phẩm đang lưu kho',
                    val: 'ALL',
                    currentVal: selectedScope,
                    onSelect: (val) => setDialogState(() => selectedScope = val),
                    c: c,
                  ),

                  // Lựa chọn 2: Theo khu vực (Zone)
                  _buildScopeOption(
                    title: 'Theo Khu Vực Cụ Thể (Zone)',
                    subtitle: 'Kiểm đếm hàng thuộc Zone A, Zone B, v.v.',
                    val: 'ZONE',
                    currentVal: selectedScope,
                    onSelect: (val) => setDialogState(() => selectedScope = val),
                    c: c,
                  ),

                  if (selectedScope == 'ZONE')
                    Padding(
                      padding: const EdgeInsets.only(left: 32, right: 8, bottom: 8),
                      child: DropdownButtonFormField<String>(
                        initialValue: allZones.contains(selectedZone) ? selectedZone : allZones.first,
                        decoration: InputDecoration(
                          labelText: 'Chọn khu vực kiểm kê',
                          labelStyle: TextStyle(color: c.textSecondary),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        dropdownColor: c.bgCard,
                        style: TextStyle(color: c.textPrimary, fontSize: 13),
                        items: allZones.map((z) => DropdownMenuItem(value: z, child: Text(z))).toList(),
                        onChanged: (val) => setDialogState(() => selectedZone = val ?? selectedZone),
                      ),
                    ),

                  // Lựa chọn 3: Theo dãy kệ cụ thể
                  _buildScopeOption(
                    title: 'Theo Vị Trí / Dãy Kệ Cụ Thể',
                    subtitle: 'Kiểm đếm một vị trí kệ duy nhất',
                    val: 'SHELF',
                    currentVal: selectedScope,
                    onSelect: (val) => setDialogState(() => selectedScope = val),
                    c: c,
                  ),

                  if (selectedScope == 'SHELF')
                    Padding(
                      padding: const EdgeInsets.only(left: 32, right: 8, bottom: 8),
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedShelf,
                        hint: Text('Chọn vị trí kệ...', style: TextStyle(color: c.textMuted, fontSize: 13)),
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        dropdownColor: c.bgCard,
                        style: TextStyle(color: c.textPrimary, fontSize: 13),
                        items: allShelves.map((s) => DropdownMenuItem(
                          value: s.locationCode,
                          child: Text('${s.displayName} (${s.locationCode})'),
                        )).toList(),
                        onChanged: (val) => setDialogState(() => selectedShelf = val),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('HỦY', style: TextStyle(color: c.textSecondary)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.rfidCyan,
                  foregroundColor: const Color(0xFF2C251E),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 18),
                label: const Text('BẮT ĐẦU KIỂM KÊ', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: () {
                  String zoneParam = 'Toàn bộ kho';
                  String? locParam;

                  if (selectedScope == 'ZONE') {
                    zoneParam = selectedZone;
                  } else if (selectedScope == 'SHELF') {
                    locParam = selectedShelf;
                    zoneParam = allShelves.firstWhere((s) => s.locationCode == selectedShelf, orElse: () => allShelves.first).zone;
                  }

                  Navigator.pop(ctx);
                  final session = _repo.startInventorySession(zone: zoneParam, locationCode: locParam);
                  setState(() {
                    _activeSession = session;
                    _scannedEpcs.clear();
                    _isScanning = false;
                    _tableFilter = 'ALL';
                  });
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildScopeOption({
    required String title,
    required String subtitle,
    required String val,
    required String currentVal,
    required Function(String) onSelect,
    required EyeCareColors c,
  }) {
    final isSelected = val == currentVal;
    return InkWell(
      onTap: () => onSelect(val),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? c.rfidCyan.withValues(alpha: 0.12) : c.bgCardElevated,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? c.rfidCyan : c.border),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: isSelected ? c.rfidCyan : c.textMuted,
              size: 18,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
                  Text(subtitle, style: TextStyle(color: c.textMuted, fontSize: 11.5)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===========================================================================
  // 2. NẠP FILE EXCEL KIỂM KÊ (.XLSX) ĐỂ QUÉT ĐỐI SOÁT ĐỦ
  // ===========================================================================
  Future<void> _pickAndLoadExcelAudit() async {
    try {
      final result = await _excelService.pickAndParseGoodsReceiveExcel();
      if (result == null || result.cartons.isEmpty) return;

      final sessionId = 'SESS-EXCEL-${DateTime.now().millisecondsSinceEpoch}';
      final sessionCode = 'KK-EXCEL-${DateTime.now().day}${DateTime.now().month}-${math.Random().nextInt(900) + 100}';
      final fileName = result.fileName.isNotEmpty ? result.fileName : 'File Excel';

      final session = InventorySession(
        sessionId: sessionId,
        sessionCode: sessionCode,
        zone: 'File: $fileName',
        startedAt: DateTime.now(),
      );

      int totalLoaded = 0;
      for (final carton in result.cartons) {
        final cartonCode = carton['cartonCode']?.toString() ?? '';
        final prodCode = carton['productCode']?.toString() ?? (carton['sku']?.toString() ?? 'SKU-EXCEL');
        final prodName = carton['productName']?.toString() ?? 'Sản phẩm kiểm kê';
        final serials = (carton['serials'] as List<dynamic>?) ?? [];

        if (serials.isNotEmpty) {
          for (final s in serials) {
            final epcVal = s.toString().trim().toUpperCase();
            if (epcVal.isNotEmpty) {
              session.results.add(InventoryItemResult(
                epc: epcVal,
                sku: prodCode,
                productName: prodName,
                expectedLocation: cartonCode.isNotEmpty ? 'Thùng $cartonCode' : 'Theo File Excel',
                resultType: InventoryVarianceType.missing,
                readAt: DateTime.now(),
              ));
              totalLoaded++;
            }
          }
        } else {
          session.results.add(InventoryItemResult(
            epc: 'NO-EPC-${math.Random().nextInt(999999)}',
            sku: prodCode,
            productName: prodName,
            expectedLocation: cartonCode.isNotEmpty ? 'Thùng $cartonCode' : 'Theo File Excel',
            resultType: InventoryVarianceType.missing,
            readAt: DateTime.now(),
          ));
          totalLoaded++;
        }
      }

      await _repo.saveInventorySession(session);

      setState(() {
        _activeSession = session;
        _scannedEpcs.clear();
        _isScanning = false;
        _tableFilter = 'ALL';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
          duration: const Duration(seconds: 2),
            backgroundColor: const Color(0xFF10B981),
            content: Text('✓ Đã nạp thành công $totalLoaded mặt hàng từ file Excel vào đơn kiểm kê!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
          duration: const Duration(seconds: 2),backgroundColor: const Color(0xFFEF4444), content: Text('Lỗi nạp file: $e')),
        );
      }
    }
  }

  // ===========================================================================
  // BUILD METHOD
  // ===========================================================================
  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = math.max(constraints.maxWidth, 1100.0);

        Widget content;
        if (_selectedSessionDetail != null) {
          content = _buildSessionDetailView(_selectedSessionDetail!, c);
        } else if (_activeSession != null) {
          content = _buildActiveInventoryView(_activeSession!, c);
        } else {
          content = _buildInventoryDashboardView(c);
        }

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: contentWidth,
            height: constraints.maxHeight,
            child: content,
          ),
        );
      },
    );
  }

  // ===========================================================================
  // GIAO DIỆN 1: DASHBOARD CHÍNH (KHI CHƯA CÓ PHIÊN ACTIVE)
  // ===========================================================================
  Widget _buildInventoryDashboardView(EyeCareColors c) {
    final sessions = _repo.inventorySessions;

    return Container(
      color: c.bgDeep,
      child: Column(
        children: [
          // Header Bar
          _buildHeaderBar(c, hasActiveSession: false),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 2 Action Cards lớn (Hero Cards)
                  Row(
                    children: [
                      // Card 1: Tạo Đơn Kiểm Kê Hệ Thống
                      Expanded(
                        child: _buildActionHeroCard(
                          icon: Icons.post_add_rounded,
                          iconColor: c.rfidCyan,
                          title: 'Tạo Đơn Kiểm Kê Mới',
                          desc: 'Khởi tạo đợt kiểm kê dựa trên dữ liệu hàng tồn kho CSDL (Toàn bộ kho, Theo khu vực Zone hoặc Từng dãy kệ).',
                          btnLabel: '+ TẠO ĐƠN KIỂM KÊ',
                          btnColor: c.rfidCyan,
                          textColor: const Color(0xFF2C251E),
                          onTap: _showCreateSessionDialog,
                          c: c,
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Card 2: Nạp File Excel Kiểm Kê
                      Expanded(
                        child: _buildActionHeroCard(
                          icon: Icons.upload_file_rounded,
                          iconColor: const Color(0xFF8B5CF6),
                          title: 'Nạp File Kiểm Kê (.xlsx)',
                          desc: 'Nạp bảng tính danh mục hàng hóa từ file Excel để quét đối soát RFID xem hàng có đủ số lượng & vị trí hay không.',
                          btnLabel: '📁 NẠP FILE QUÉT ĐỦ',
                          btnColor: const Color(0xFF8B5CF6),
                          textColor: Colors.white,
                          onTap: _pickAndLoadExcelAudit,
                          c: c,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Tiêu đề danh sách lịch sử kiểm kê
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.history_rounded, size: 20, color: c.rfidCyan),
                          const SizedBox(width: 8),
                          Text(
                            'LỊCH SỬ CÁC ĐỢT KIỂM KÊ ĐÃ THỰC HIỆN (${sessions.length})',
                            style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Làm mới'),
                        onPressed: () => setState(() {}),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Bảng danh sách các phiên kiểm kê
                  if (sessions.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(40),
                      decoration: BoxDecoration(
                        color: c.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.fact_check_outlined, size: 48, color: c.textMuted),
                          const SizedBox(height: 12),
                          Text('Chưa có đợt kiểm kê nào được thực hiện', style: TextStyle(color: c.textPrimary, fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('Nhấn vào một trong hai lựa chọn ở trên để bắt đầu kiểm kê kho.', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                        ],
                      ),
                    )
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: c.bgCard,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: c.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Table(
                          border: TableBorder(horizontalInside: BorderSide(color: c.border, width: 0.8)),
                          columnWidths: const {
                            0: FlexColumnWidth(1.4),
                            1: FlexColumnWidth(1.8),
                            2: FlexColumnWidth(1.6),
                            3: FlexColumnWidth(1.4),
                            4: FlexColumnWidth(1.2),
                            5: FlexColumnWidth(1.2),
                            6: FlexColumnWidth(1.2),
                          },
                          children: [
                            TableRow(
                              decoration: BoxDecoration(color: c.bgCardElevated),
                              children: [
                                _tableHeaderCell('Mã Đợt', c),
                                _tableHeaderCell('Phạm Vi Kiểm Kê', c),
                                _tableHeaderCell('Thời Gian Bắt Đầu', c),
                                _tableHeaderCell('Số Lượng Đối Soát', c),
                                _tableHeaderCell('Chính Xác', c),
                                _tableHeaderCell('Trạng Thái', c),
                                _tableHeaderCell('Thao Tác', c, align: TextAlign.center),
                              ],
                            ),
                            ...sessions.map((s) {
                              final totalExpected = s.matchCount + s.missingCount;
                              final acc = totalExpected > 0 ? (s.matchCount / totalExpected * 100).toStringAsFixed(1) : '100.0';
                              final isDone = s.isCompleted;

                              return TableRow(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Text(s.sessionCode, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 12.5)),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Text(
                                      s.locationCode != null ? '${s.locationCode} (${s.zone})' : s.zone,
                                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Text(
                                      '${s.startedAt.day.toString().padLeft(2, '0')}/${s.startedAt.month.toString().padLeft(2, '0')}/${s.startedAt.year} ${s.startedAt.hour.toString().padLeft(2, '0')}:${s.startedAt.minute.toString().padLeft(2, '0')}',
                                      style: TextStyle(color: c.textSecondary, fontSize: 12),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Text('Đã quét ${s.actualScannedCount} / $totalExpected SP', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.w600, fontSize: 12)),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Text('$acc%', style: TextStyle(color: double.parse(acc) >= 95 ? const Color(0xFF10B981) : const Color(0xFFF59E0B), fontWeight: FontWeight.bold, fontSize: 12)),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isDone ? const Color(0xFF10B981).withValues(alpha: 0.15) : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        isDone ? 'ĐÃ HOÀN TẤT' : 'ĐANG DỞ DANG',
                                        style: TextStyle(
                                          color: isDone ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        IconButton(
                                          tooltip: 'Xem chi tiết',
                                          icon: Icon(Icons.visibility_rounded, color: c.rfidCyan, size: 18),
                                          onPressed: () => setState(() => _selectedSessionDetail = s),
                                        ),
                                        IconButton(
                                          tooltip: 'Xóa đợt kiểm kê',
                                          icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 18),
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                backgroundColor: c.bgCard,
                                                title: const Text('Xác nhận xóa đợt kiểm kê', style: TextStyle(fontWeight: FontWeight.bold)),
                                                content: Text('Bạn có chắc muốn xóa vĩnh viễn đợt kiểm kê ${s.sessionCode}?'),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('HỦY')),
                                                  ElevatedButton(
                                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                                                    onPressed: () => Navigator.pop(ctx, true),
                                                    child: const Text('XÓA', style: TextStyle(color: Colors.white)),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await _repo.deleteInventorySession(s.sessionId);
                                              setState(() {});
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // GIAO DIỆN 2: ACTIVE SESSION (ĐANG QUÉT ĐỐI SOÁT THỜI GIAN THỰC)
  // ===========================================================================
  Widget _buildActiveInventoryView(InventorySession session, EyeCareColors c) {
    final results = session.results;

    // Filter results
    final q = _searchQuery.trim().toLowerCase();
    final filteredResults = results.where((r) {
      if (_tableFilter == 'MATCH' && r.resultType != InventoryVarianceType.match) return false;
      if (_tableFilter == 'MISSING' && r.resultType != InventoryVarianceType.missing) return false;
      if (_tableFilter == 'WRONG_LOC' && r.resultType != InventoryVarianceType.wrongLocation) return false;
      if (_tableFilter == 'UNKNOWN' && r.resultType != InventoryVarianceType.unknownEpc) return false;

      if (q.isEmpty) return true;
      return r.epc.toLowerCase().contains(q) ||
          (r.sku != null && r.sku!.toLowerCase().contains(q)) ||
          (r.productName != null && r.productName!.toLowerCase().contains(q)) ||
          (r.expectedLocation != null && r.expectedLocation!.toLowerCase().contains(q));
    }).toList();

    return Container(
      color: c.bgDeep,
      child: Column(
        children: [
          // 1. Header Bar
          _buildHeaderBar(c, hasActiveSession: true),

          // 2. Active Session Control Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: c.bgCard,
              border: Border(bottom: BorderSide(color: c.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _isScanning ? const Color(0xFF10B981).withValues(alpha: 0.15) : c.bgCardElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _isScanning ? const Color(0xFF10B981) : c.border),
                      ),
                      child: Icon(
                        _isScanning ? Icons.sensors_rounded : Icons.sensors_off_rounded,
                        color: _isScanning ? const Color(0xFF10B981) : c.textMuted,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              'ĐƠN KIỂM KÊ: ${session.sessionCode}',
                              style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _isScanning ? const Color(0xFF10B981).withValues(alpha: 0.15) : c.bgCardElevated,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                _isScanning ? 'ĐANG QUÉT RFID' : 'TẠM DỪNG',
                                style: TextStyle(
                                  color: _isScanning ? const Color(0xFF10B981) : c.textSecondary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Phạm vi: ${session.locationCode != null ? "${session.locationCode} (${session.zone})" : session.zone}',
                          style: TextStyle(color: c.textSecondary, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),

                // Control Action Buttons
                Row(
                  children: [
                    // Nút Bắt đầu / Dừng quét
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isScanning ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: Icon(_isScanning ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 20),
                      label: Text(
                        _isScanning ? 'DỪNG QUÉT' : 'BẮT ĐẦU QUÉT RFID',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                      ),
                      onPressed: _toggleScanning,
                    ),
                    const SizedBox(width: 10),

                    // Nút Reset quét lại
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.textPrimary,
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.restart_alt_rounded, size: 18),
                      label: const Text('LÀM MỚI QUÉT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11.5)),
                      onPressed: _resetScannedData,
                    ),
                    const SizedBox(width: 10),

                    // Nút Hoàn tất kiểm kê
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.rfidCyan,
                        foregroundColor: const Color(0xFF2C251E),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                      label: const Text('HOÀN THÀNH KIỂM KÊ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                      onPressed: _completeActiveSession,
                    ),
                    const SizedBox(width: 10),

                    // Nút Đóng / Hủy
                    IconButton(
                      tooltip: 'Đóng đơn kiểm kê',
                      icon: Icon(Icons.close_rounded, color: c.textSecondary, size: 20),
                      onPressed: _cancelActiveSession,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3. 4 Thẻ Chỉ Số Đối Soát Thời Gian Thực (Audit KPI Cards)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: _buildAuditKpiCard(
                    title: 'ĐÃ QUÉT THỰC TẾ',
                    count: session.actualScannedCount,
                    unit: 'chip',
                    subtitle: 'Tổng tem RFID UHF đọc được',
                    color: const Color(0xFF06B6D4),
                    icon: Icons.qr_code_scanner_rounded,
                    c: c,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAuditKpiCard(
                    title: 'KHỚP ĐỦ DANH SÁCH',
                    count: session.matchCount,
                    unit: 'sản phẩm',
                    subtitle: 'Đúng vị trí & đúng mã chip',
                    color: const Color(0xFF10B981),
                    icon: Icons.check_circle_rounded,
                    c: c,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAuditKpiCard(
                    title: 'CÒN THIẾU',
                    count: session.missingCount,
                    unit: 'sản phẩm',
                    subtitle: 'Chưa quét nhận diện được',
                    color: const Color(0xFFEF4444),
                    icon: Icons.error_outline_rounded,
                    c: c,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildAuditKpiCard(
                    title: 'HÀNG LẠ / THỪA',
                    count: session.unknownEpcCount + session.wrongLocationCount,
                    unit: 'thẻ',
                    subtitle: 'Ngoài danh sách hoặc sai vị trí',
                    color: const Color(0xFFF59E0B),
                    icon: Icons.warning_amber_rounded,
                    c: c,
                  ),
                ),
              ],
            ),
          ),

          // 4. Thanh Tìm Kiếm & Bộ Lọc Trạng Thái
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                // Filter pills
                _buildFilterPill('Tất Cả (${results.length})', 'ALL', c),
                const SizedBox(width: 6),
                _buildFilterPill('Đã Khớp (${session.matchCount})', 'MATCH', c, activeColor: const Color(0xFF10B981)),
                const SizedBox(width: 6),
                _buildFilterPill('Còn Thiếu (${session.missingCount})', 'MISSING', c, activeColor: const Color(0xFFEF4444)),
                const SizedBox(width: 6),
                _buildFilterPill('Sai Vị Trí (${session.wrongLocationCount})', 'WRONG_LOC', c, activeColor: const Color(0xFFF59E0B)),
                const SizedBox(width: 6),
                _buildFilterPill('Thẻ Lạ (${session.unknownEpcCount})', 'UNKNOWN', c, activeColor: const Color(0xFF8B5CF6)),

                const Spacer(),

                // Ô tìm kiếm
                SizedBox(
                  width: 280,
                  height: 38,
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (val) => setState(() => _searchQuery = val),
                    style: TextStyle(color: c.textPrimary, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Tìm SKU, tên SP, mã chip...',
                      hintStyle: TextStyle(color: c.textMuted, fontSize: 12),
                      prefixIcon: Icon(Icons.search, color: c.textSecondary, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() { _searchCtrl.clear(); _searchQuery = ''; }))
                          : null,
                      filled: true,
                      fillColor: c.bgCard,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: c.border)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 5. Bảng Chi Tiết Đối Soát
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: Container(
                decoration: BoxDecoration(
                  color: c.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: filteredResults.isEmpty
                      ? Center(
                          child: Text('Không có dữ liệu đối soát phù hợp với bộ lọc.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                        )
                      : ListView.separated(
                          itemCount: filteredResults.length + 1,
                          separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
                          itemBuilder: (ctx, idx) {
                            if (idx == 0) {
                              // Table Header
                              return Container(
                                color: c.bgCardElevated,
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                child: Row(
                                  children: [
                                    _colHeader('#', 40, c),
                                    _colHeader('MÃ CHIP RFID (EPC)', 220, c),
                                    _colHeader('MÃ SKU', 130, c),
                                    Expanded(flex: 3, child: _colHeader('TÊN SẢN PHẨM', 0, c)),
                                    _colHeader('VỊ TRÍ DỰ KIẾN', 140, c),
                                    _colHeader('TRẠNG THÁI ĐỐI SOÁT', 170, c),
                                    _colHeader('THỜI GIAN', 110, c),
                                  ],
                                ),
                              );
                            }

                            final r = filteredResults[idx - 1];
                            final prodTitle = (r.productName != null && r.productName!.isNotEmpty)
                                ? r.productName!
                                : ((r.sku != null && r.sku!.isNotEmpty) ? r.sku! : 'Chưa phân loại');

                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              child: Row(
                                children: [
                                  SizedBox(width: 40, child: Text('$idx', style: TextStyle(color: c.textMuted, fontSize: 12))),
                                  SizedBox(
                                    width: 220,
                                    child: Text(
                                      r.epc,
                                      style: TextStyle(color: c.textPrimary, fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 11.5),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 130,
                                    child: Text(r.sku ?? '--', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.w600, fontSize: 12)),
                                  ),
                                  Expanded(
                                    flex: 3,
                                    child: Text(prodTitle, style: TextStyle(color: c.textPrimary, fontSize: 12.5), overflow: TextOverflow.ellipsis),
                                  ),
                                  SizedBox(
                                    width: 140,
                                    child: Text(r.expectedLocation ?? '--', style: TextStyle(color: c.textSecondary, fontSize: 12)),
                                  ),
                                  SizedBox(
                                    width: 170,
                                    child: _buildStatusPill(r.resultType),
                                  ),
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      '${r.readAt.hour.toString().padLeft(2, '0')}:${r.readAt.minute.toString().padLeft(2, '0')}:${r.readAt.second.toString().padLeft(2, '0')}',
                                      style: TextStyle(color: c.textMuted, fontSize: 11.5),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // GIAO DIỆN 3: XEM CHI TIẾT PHIÊN KIỂM KÊ CŨ
  // ===========================================================================
  Widget _buildSessionDetailView(InventorySession s, EyeCareColors c) {
    return Container(
      color: c.bgDeep,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: c.textPrimary),
                    onPressed: () => setState(() => _selectedSessionDetail = null),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Chi tiết kiểm kê: ${s.sessionCode}',
                    style: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('QUAY LẠI'),
                onPressed: () => setState(() => _selectedSessionDetail = null),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Cột trái: Thông tin tóm tắt
                SizedBox(
                  width: 320,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detailRow('Mã kiểm kê', s.sessionCode, c),
                        const SizedBox(height: 10),
                        _detailRow('Ngày kiểm kê', '${s.startedAt.day}/${s.startedAt.month}/${s.startedAt.year}', c),
                        const SizedBox(height: 10),
                        _detailRow('Phạm vi', s.locationCode != null ? '${s.locationCode} (${s.zone})' : s.zone, c),
                        const SizedBox(height: 10),
                        _detailRow('Trạng thái', s.isCompleted ? 'Đã hoàn tất' : 'Đang kiểm kê', c),
                        const Divider(height: 24),
                        Text('SỐ LIỆU ĐỐI SOÁT', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12)),
                        const SizedBox(height: 10),
                        _detailRow('Tổng dự kiến', '${s.matchCount + s.missingCount} SP', c),
                        const SizedBox(height: 8),
                        _detailRow('Thực tế quét', '${s.actualScannedCount} Chip', c),
                        const SizedBox(height: 8),
                        _detailRow('✓ Khớp đủ', '${s.matchCount} SP', c, valColor: const Color(0xFF10B981)),
                        const SizedBox(height: 8),
                        _detailRow('⚠️ Còn thiếu', '${s.missingCount} SP', c, valColor: const Color(0xFFEF4444)),
                        const SizedBox(height: 8),
                        _detailRow('⛔ Sai vị trí', '${s.wrongLocationCount} SP', c, valColor: const Color(0xFFF59E0B)),
                        const SizedBox(height: 8),
                        _detailRow('❓ Thẻ lạ ngoài đơn', '${s.unknownEpcCount} Thẻ', c, valColor: const Color(0xFF8B5CF6)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),

                // Cột phải: Bảng kết quả
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: s.results.isEmpty
                        ? Center(child: Text('Đợt kiểm kê này chưa có bản ghi quét nào.', style: TextStyle(color: c.textSecondary)))
                        : ListView.separated(
                            itemCount: s.results.length + 1,
                            separatorBuilder: (_, _) => Divider(height: 1, color: c.border),
                            itemBuilder: (ctx, idx) {
                              if (idx == 0) {
                                return Container(
                                  color: c.bgCardElevated,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  child: Row(
                                    children: [
                                      _colHeader('#', 40, c),
                                      _colHeader('MÃ CHIP EPC', 200, c),
                                      _colHeader('SKU', 120, c),
                                      Expanded(child: _colHeader('TÊN SẢN PHẨM', 0, c)),
                                      _colHeader('VỊ TRÍ DỰ KIẾN', 120, c),
                                      _colHeader('KẾT QUẢ', 150, c),
                                    ],
                                  ),
                                );
                              }

                              final r = s.results[idx - 1];
                              return Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                child: Row(
                                  children: [
                                    SizedBox(width: 40, child: Text('$idx', style: TextStyle(color: c.textMuted, fontSize: 12))),
                                    SizedBox(width: 200, child: Text(r.epc, style: TextStyle(color: c.textPrimary, fontFamily: 'Courier', fontSize: 11))),
                                    SizedBox(width: 120, child: Text(r.sku ?? '--', style: TextStyle(color: c.rfidCyan, fontSize: 12))),
                                    Expanded(child: Text(r.productName ?? (r.sku ?? '--'), style: TextStyle(color: c.textPrimary, fontSize: 12), overflow: TextOverflow.ellipsis)),
                                    SizedBox(width: 120, child: Text(r.expectedLocation ?? '--', style: TextStyle(color: c.textSecondary, fontSize: 12))),
                                    SizedBox(width: 150, child: _buildStatusPill(r.resultType)),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // WIDGETS & HELPER METHODS
  // ===========================================================================

  Widget _buildHeaderBar(EyeCareColors c, {required bool hasActiveSession}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: c.bgCard,
        border: Border(bottom: BorderSide(color: c.border, width: 1)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: c.rfidCyan.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: c.rfidCyan.withValues(alpha: 0.3)),
                  ),
                  child: Icon(Icons.fact_check_rounded, color: c.rfidCyan, size: 24),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KIỂM KÊ KHO & ĐỐI SOÁT RFID THỜI GIAN THỰC',
                      style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tạo đơn kiểm kê hoặc nạp file Excel để quét nhận diện đối soát đủ / thiếu / lạ',
                      style: TextStyle(color: c.textMuted, fontSize: 11.5),
                    ),
                  ],
                ),
              ],
            ),

            if (!hasActiveSession) ...[
              const SizedBox(width: 24),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('📁 NẠP FILE EXCEL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: _pickAndLoadExcelAudit,
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.rfidCyan,
                      foregroundColor: const Color(0xFF2C251E),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.add_task_rounded, size: 18),
                    label: const Text('+ TẠO ĐƠN KIỂM KÊ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    onPressed: _showCreateSessionDialog,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionHeroCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
    required String btnLabel,
    required Color btnColor,
    required Color textColor,
    required VoidCallback onTap,
    required EyeCareColors c,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: iconColor.withValues(alpha: 0.3)),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(color: c.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(desc, style: TextStyle(color: c.textSecondary, fontSize: 12, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: btnColor,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: onTap,
              child: Text(btnLabel, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 12.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAuditKpiCard({
    required String title,
    required int count,
    required String unit,
    required String subtitle,
    required Color color,
    required IconData icon,
    required EyeCareColors c,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: TextStyle(color: c.textSecondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$count', style: TextStyle(color: color, fontSize: 26, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Text(unit, style: TextStyle(color: c.textMuted, fontSize: 11.5)),
            ],
          ),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(color: c.textMuted, fontSize: 11), overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  Widget _buildFilterPill(String label, String value, EyeCareColors c, {Color? activeColor}) {
    final isSelected = _tableFilter == value;
    final actCol = activeColor ?? c.rfidCyan;

    return InkWell(
      onTap: () => setState(() => _tableFilter = value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? actCol.withValues(alpha: 0.2) : c.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? actCol : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? (activeColor ?? c.textPrimary) : c.textSecondary,
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPill(InventoryVarianceType type) {
    String label;
    Color color;

    switch (type) {
      case InventoryVarianceType.match:
        label = '✓ ĐÃ KHỚP ĐỦ';
        color = const Color(0xFF10B981);
        break;
      case InventoryVarianceType.missing:
        label = '⚠️ CHƯA QUÉT (THIẾU)';
        color = const Color(0xFFEF4444);
        break;
      case InventoryVarianceType.wrongLocation:
        label = '⛔ SAI VỊ TRÍ';
        color = const Color(0xFFF59E0B);
        break;
      case InventoryVarianceType.unknownEpc:
        label = '❓ THẺ LẠ (NGOÀI ĐƠN)';
        color = const Color(0xFF8B5CF6);
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _tableHeaderCell(String label, EyeCareColors c, {TextAlign align = TextAlign.left}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Text(
        label,
        textAlign: align,
        style: TextStyle(color: c.rfidCyan, fontSize: 11.5, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _colHeader(String title, double width, EyeCareColors c) {
    if (width > 0) {
      return SizedBox(
        width: width,
        child: Text(title, style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.bold)),
      );
    }
    return Text(title, style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.bold));
  }

  Widget _detailRow(String label, String value, EyeCareColors c, {Color? valColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.textMuted, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: valColor ?? c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}
