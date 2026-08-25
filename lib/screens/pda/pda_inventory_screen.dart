import 'dart:async';
import 'package:flutter/material.dart';
import '../../services/warehouse_repository.dart';
import '../../services/supabase_sync_service.dart';
import '../../services/uhf_service.dart';
import '../../models/wms_models.dart';

class PdaInventoryScreen extends StatefulWidget {
  const PdaInventoryScreen({super.key});

  @override
  State<PdaInventoryScreen> createState() => _PdaInventoryScreenState();
}

class _PdaInventoryScreenState extends State<PdaInventoryScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  InventorySession? _activeSession;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _repo,
      builder: (context, _) {
        if (_activeSession != null) {
          return _buildInventoryScanningScreen(_activeSession!);
        }
        return _buildSessionListScreen();
      },
    );
  }

  Widget _buildSessionListScreen() {
    final sessions = _repo.inventorySessions;

    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE9E2D5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2C251E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Kiểm Kê Kho Hàng (RFID)',
          style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_sync, color: Color(0xFF0284C7)),
            tooltip: 'Đồng bộ Đám mây',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đang đồng bộ dữ liệu kiểm kê...'), duration: Duration(seconds: 1)),
              );
              await SupabaseSyncService().syncNow();
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF6B5D4D)),
            tooltip: 'Làm mới',
            onPressed: () => _repo.reloadFromSqlite(),
          ),
        ],
      ),
      body: sessions.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.fact_check_outlined, size: 56, color: Color(0xFF0284C7)),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Chưa có phiếu kiểm kê nào',
                      style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Bấm nút bên dưới để bắt đầu phiên kiểm kê kho mới bằng đầu đọc RFID cầm tay.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12.5),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.add, color: Colors.white),
                        label: const Text(
                          'TẠO PHIẾU KIỂM KÊ MỚI',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        onPressed: _showCreateInventoryWorkflowDialog,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(14),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final s = sessions[index];
                final isCompleted = s.isCompleted;

                return GestureDetector(
                  onTap: () => setState(() => _activeSession = s),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFD1C7BA)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
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
                                color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.inventory_2_outlined, color: Color(0xFF0284C7), size: 22),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.sessionCode,
                                    style: const TextStyle(
                                      color: Color(0xFF2C251E),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                  Text(
                                    'Khu vực: ${s.zone}',
                                    style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: isCompleted
                                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                    : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isCompleted ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                                  width: 0.8,
                                ),
                              ),
                              child: Text(
                                isCompleted ? 'ĐÃ HOÀN TẤT' : 'ĐANG QUÉT',
                                style: TextStyle(
                                  color: isCompleted ? const Color(0xFF059669) : const Color(0xFFD97706),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        const Divider(height: 1, color: Color(0xFFE9E2D5)),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Bắt đầu: ${_formatDate(s.startedAt)}',
                              style: const TextStyle(color: Color(0xFF8C7E6D), fontSize: 11),
                            ),
                            Row(
                              children: [
                                const Icon(Icons.nfc, size: 14, color: Color(0xFF0284C7)),
                                const SizedBox(width: 4),
                                Text(
                                  'Đã quét: ${s.results.length} chip',
                                  style: const TextStyle(
                                    color: Color(0xFF0284C7),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: sessions.isNotEmpty
          ? Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Color(0xFFE9E2D5),
                border: Border(top: BorderSide(color: Color(0xFFD1C7BA))),
              ),
              child: SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                  label: const Text(
                    '+ TẠO PHIẾU KIỂM KÊ MỚI',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: _showCreateInventoryWorkflowDialog,
                ),
              ),
            )
          : null,
    );
  }

  void _showCreateInventoryWorkflowDialog() {
    String selectedType = 'all';

    // Step 1: Chọn Hình Thức Kiểm Kê
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFFFBF8F3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            actionsPadding: const EdgeInsets.all(16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.fact_check, color: Color(0xFF0284C7), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Chọn Hình Thức Kiểm Kê',
                    style: TextStyle(
                      color: Color(0xFF2C251E),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildInventoryTypeCard(
                    title: 'Kiểm kê toàn bộ kho',
                    subtitle: 'Quét đối soát toàn bộ hàng hóa và vị trí trong kho',
                    icon: Icons.storefront_outlined,
                    isSelected: selectedType == 'all',
                    onTap: () => setDialogState(() => selectedType = 'all'),
                  ),
                  const SizedBox(height: 10),
                  _buildInventoryTypeCard(
                    title: 'Kiểm kê theo khu vực / Vị trí',
                    subtitle: 'Quét đối soát theo từng khu vực hoặc kệ chỉ định',
                    icon: Icons.grid_view_rounded,
                    isSelected: selectedType == 'by_product',
                    onTap: () => setDialogState(() => selectedType = 'by_product'),
                  ),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFC7BDAF)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('HỦY', style: TextStyle(color: Color(0xFF6B5D4D), fontWeight: FontWeight.bold)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                icon: const Icon(Icons.arrow_forward, color: Colors.white, size: 16),
                label: const Text(
                  'TIẾP TỤC',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showSelectWarehouseDialog(selectedType);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSelectWarehouseDialog(String inventoryType) {
    // Lấy danh sách Zone thực tế từ CSDL
    final dbZones = _repo.locations.map((l) => l.zone.trim()).where((z) => z.isNotEmpty).toSet().toList();
    if (dbZones.isEmpty) {
      dbZones.addAll(['Kho 01', 'Kho 02', 'Kho 03', 'Khu A', 'Khu B']);
    }
    if (!dbZones.contains('Toàn bộ kho')) {
      dbZones.insert(0, 'Toàn bộ kho');
    }

    String selectedWarehouse = dbZones.first;

    // Step 2: Chọn Khu Vực
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFFFBF8F3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            actionsPadding: const EdgeInsets.all(16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.location_on, color: Color(0xFF0284C7), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Chọn Khu Vực Kiểm Kê',
                    style: TextStyle(
                      color: Color(0xFF2C251E),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final wh in dbZones)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildWarehouseOptionTile(
                          title: wh,
                          isSelected: selectedWarehouse == wh,
                          onTap: () => setDialogState(() => selectedWarehouse = wh),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFFC7BDAF)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('QUAY LẠI', style: TextStyle(color: Color(0xFF6B5D4D), fontWeight: FontWeight.bold)),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0284C7),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                ),
                icon: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
                label: const Text(
                  'BẮT ĐẦU KIỂM KÊ',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  _createNewSession(selectedWarehouse, inventoryType);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _buildInventoryTypeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE0F2FE) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFD1C7BA),
            width: isSelected ? 2.0 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF8C7E6D),
              size: 22,
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF0284C7).withValues(alpha: 0.15)
                    : const Color(0xFFF4EFE6),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF6B5D4D),
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isSelected ? const Color(0xFF0369A1) : const Color(0xFF2C251E),
                      fontWeight: FontWeight.bold,
                      fontSize: 13.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF6B5D4D),
                      fontSize: 11,
                      height: 1.25,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _buildWarehouseOptionTile({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE0F2FE) : const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFD1C7BA),
            width: isSelected ? 1.8 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF8C7E6D),
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? const Color(0xFF0369A1) : const Color(0xFF2C251E),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 13.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _createNewSession(String warehouse, String inventoryType) {
    final session = _repo.startInventorySession(
      zone: warehouse,
    );
    setState(() => _activeSession = session);
  }

  Widget _buildInventoryScanningScreen(InventorySession session) {
    return _InventoryScanningSubScreen(
      session: session,
      onBack: () => setState(() => _activeSession = null),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _InventoryScanningSubScreen extends StatefulWidget {
  final InventorySession session;
  final VoidCallback onBack;

  const _InventoryScanningSubScreen({required this.session, required this.onBack});

  @override
  State<_InventoryScanningSubScreen> createState() => _InventoryScanningSubScreenState();
}

class _InventoryScanningSubScreenState extends State<_InventoryScanningSubScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final UhfService _uhf = UhfService();
  final Set<String> _scannedEpcs = {};
  bool _isScanning = false;
  StreamSubscription? _tagSub;
  StreamSubscription? _triggerSub;
  Timer? _uiRefreshTimer;

  @override
  void initState() {
    super.initState();
    _subscribeScanner();
  }

  void _scheduleUiRefresh() {
    if (_uiRefreshTimer?.isActive ?? false) return;
    _uiRefreshTimer = Timer(const Duration(milliseconds: 50), () {
      if (mounted) {
        setState(() {
          _repo.processAuditScan(
            sessionId: widget.session.sessionId,
            scannedEpcs: _scannedEpcs.toList(),
          );
        });
      }
    });
  }

  void _subscribeScanner() {
    _tagSub = _uhf.onTagRead.listen((tag) {
      if (mounted && tag.epc.isNotEmpty) {
        if (_uhf.filterDuplicates && _scannedEpcs.contains(tag.epc)) return;
        _scannedEpcs.add(tag.epc);
        _scheduleUiRefresh();
      }
    });
    _triggerSub = _uhf.onTriggerStateChanged.listen((isPressed) {
      if (mounted) {
        setState(() => _isScanning = isPressed);
      }
    });
  }

  void _toggleScanning() async {
    if (_isScanning) {
      await _uhf.stopInventory();
      setState(() => _isScanning = false);
    } else {
      await _uhf.startInventory();
      setState(() => _isScanning = true);
    }
  }

  @override
  void dispose() {
    _uiRefreshTimer?.cancel();
    _tagSub?.cancel();
    _triggerSub?.cancel();
    super.dispose();
  }

  void _confirmComplete() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFBF8F3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.check_circle_outline, color: Color(0xFF10B981), size: 24),
            SizedBox(width: 8),
            Text(
              'Xác Nhận Hoàn Tất',
              style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(
          'Bạn có chắc chắn muốn chốt số liệu kiểm kê này (${_scannedEpcs.length} chip đã đọc)? Kết quả kiểm kê sẽ được lưu vào hệ thống.',
          style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 13.5, height: 1.3),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFC7BDAF))),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('HỦY', style: TextStyle(color: Color(0xFF6B5D4D))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () {
              _repo.completeInventorySession(widget.session.sessionId, 'Thủ kho PDA');
              Navigator.pop(ctx);
              widget.onBack();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  backgroundColor: Color(0xFF10B981),
                  content: Text('Đã hoàn tất và lưu số liệu phiếu kiểm kê!'),
                ),
              );
            },
            child: const Text('HOÀN TẤT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final totalScanned = _scannedEpcs.length;
    final totalExpected = s.matchCount + s.missingCount;

    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE9E2D5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2C251E)),
          onPressed: widget.onBack,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.sessionCode,
              style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 14.5),
            ),
            Text(
              'Khu vực: ${s.zone}',
              style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 11),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 26),
            tooltip: 'Hoàn tất kiểm kê',
            onPressed: _confirmComplete,
          ),
        ],
      ),
      body: Column(
        children: [
          // 4 Chỉ số KPI thống kê lớn
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD1C7BA)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildKpiBox(
                      title: 'Kỳ vọng (CSDL)',
                      value: '$totalExpected',
                      color: const Color(0xFF2C251E),
                      bg: const Color(0xFFF4EFE6),
                    ),
                    const SizedBox(width: 8),
                    _buildKpiBox(
                      title: 'Đã quét thực tế',
                      value: '$totalScanned',
                      color: const Color(0xFF0284C7),
                      bg: const Color(0xFFE0F2FE),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _buildKpiBox(
                      title: '🟢 Đúng vị trí',
                      value: '${s.matchCount}',
                      color: const Color(0xFF059669),
                      bg: const Color(0xFFECFDF5),
                    ),
                    const SizedBox(width: 8),
                    _buildKpiBox(
                      title: '🔴 Lệch / Lạ',
                      value: '${s.wrongLocationCount + s.unknownEpcCount}',
                      color: const Color(0xFFDC2626),
                      bg: const Color(0xFFFEF2F2),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Header danh sách chip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Danh sách Chip đọc được (${_scannedEpcs.length}):',
                  style: const TextStyle(
                    color: Color(0xFF2C251E),
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                  ),
                ),
                if (_scannedEpcs.isNotEmpty)
                  InkWell(
                    onTap: () => setState(() => _scannedEpcs.clear()),
                    child: const Text(
                      'Xóa danh sách',
                      style: TextStyle(color: Colors.redAccent, fontSize: 11.5, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),

          // List chi tiết chip
          Expanded(
            child: _scannedEpcs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isScanning ? Icons.sensors : Icons.nfc_outlined,
                          size: 48,
                          color: _isScanning ? const Color(0xFF0284C7) : const Color(0xFF8F8070),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _isScanning
                              ? 'Đang phát sóng đọc thẻ RFID...'
                              : 'Bấm nút "BẮT ĐẦU QUÉT" hoặc bóp cò súng PDA',
                          style: TextStyle(
                            color: _isScanning ? const Color(0xFF0284C7) : const Color(0xFF6B5D4D),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: _scannedEpcs.length,
                    itemBuilder: (context, index) {
                      final epc = _scannedEpcs.elementAt(index);
                      final item = _repo.items.where((i) => i.epc.toUpperCase() == epc.toUpperCase()).firstOrNull;

                      final isKnown = item != null;
                      final isRightZone = isKnown && (item.locationId != null || s.zone == 'Toàn bộ kho');

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isKnown ? const Color(0xFFD1C7BA) : const Color(0xFFEF4444).withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: isKnown
                                    ? const Color(0xFF0284C7).withValues(alpha: 0.1)
                                    : const Color(0xFFEF4444).withValues(alpha: 0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                isKnown ? Icons.check : Icons.help_outline,
                                size: 16,
                                color: isKnown ? const Color(0xFF0284C7) : const Color(0xFFEF4444),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item?.productName ?? 'Mã chip lạ / Chưa gán SP',
                                    style: TextStyle(
                                      color: isKnown ? const Color(0xFF2C251E) : const Color(0xFFDC2626),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  Text(
                                    'EPC: $epc',
                                    style: const TextStyle(
                                      color: Color(0xFF6B5D4D),
                                      fontFamily: 'Courier',
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isRightZone
                                    ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                    : const Color(0xFFF59E0B).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                isKnown ? (item.locationId ?? 'Chưa gán kệ') : 'Ngoài CSDL',
                                style: TextStyle(
                                  color: isRightZone ? const Color(0xFF059669) : const Color(0xFFD97706),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Thanh điều khiển đáy màn hình PDA
          Container(
            padding: const EdgeInsets.all(12),
            decoration: const BoxDecoration(
              color: Color(0xFFE9E2D5),
              border: Border(top: BorderSide(color: Color(0xFFD1C7BA))),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isScanning ? const Color(0xFFEF4444) : const Color(0xFF0284C7),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: Icon(_isScanning ? Icons.stop : Icons.sensors, color: Colors.white, size: 20),
                      label: Text(
                        _isScanning ? 'DỪNG QUÉT' : 'BẮT ĐẦU QUÉT',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      onPressed: _toggleScanning,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _confirmComplete,
                      child: const Text(
                        'HOÀN TẤT',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
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

  static Widget _buildKpiBox({
    required String title,
    required String value,
    required Color color,
    required Color bg,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 11)),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}

