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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2C251E)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Inventory (Kiểm Kê)', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_sync, color: Color(0xFF0284C7)),
            tooltip: 'Đồng bộ Supabase Cloud',
            onPressed: () async {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đang kích hoạt đồng bộ Supabase Cloud...'), duration: Duration(seconds: 1)),
              );
              await SupabaseSyncService().syncNow();
            },
          ),
          IconButton(
            icon: const Icon(Icons.history, color: Color(0xFF6B5D4D)),
            onPressed: () => _repo.reloadFromSqlite(),
          ),
          IconButton(
            icon: const Icon(Icons.add, color: Color(0xFF0284C7), size: 28),
            tooltip: 'Tạo vé kiểm kê mới',
            onPressed: _showCreateInventoryWorkflowDialog,
          ),
        ],
      ),
      body: sessions.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.fact_check_outlined, size: 64, color: Color(0xFF8F8070)),
                  const SizedBox(height: 14),
                  const Text('Chưa có phiếu kiểm kê nào.', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 13)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                    onPressed: _showCreateInventoryWorkflowDialog,
                    child: const Text('+ TẠO PHIẾU KIỂM KÊ MỚI', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: sessions.length,
              itemBuilder: (context, index) {
                final s = sessions[index];
                final isCompleted = s.isCompleted;

                return GestureDetector(
                  onTap: () => setState(() => _activeSession = s),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE9E2D5),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFC7BDAF)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.checklist, color: Color(0xFF0284C7), size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                s.sessionCode,
                                style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                'Inventory date: ${_formatDate(s.startedAt)} • ${s.zone}',
                                style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isCompleted
                                ? const Color(0xFF10B981).withValues(alpha: 0.2)
                                : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            isCompleted ? 'Completed' : 'Scanning',
                            style: TextStyle(
                              color: isCompleted ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
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
    );
  }

  void _showCreateInventoryWorkflowDialog() {
    String selectedType = 'all';

    // Step 1: Select Inventory Type (PDF Page 12)
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFFE9E2D5),
            title: const Text('Select inventory type', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSelectionTile(
                  title: 'Take inventory of all',
                  isSelected: selectedType == 'all',
                  onTap: () => setDialogState(() => selectedType = 'all'),
                ),
                const SizedBox(height: 8),
                _buildSelectionTile(
                  title: 'Inventory by product',
                  isSelected: selectedType == 'by_product',
                  onTap: () => setDialogState(() => selectedType = 'by_product'),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('CANCEL', style: TextStyle(color: Color(0xFF6B5D4D))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _showSelectWarehouseDialog(selectedType);
                },
                child: const Text('OK', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSelectWarehouseDialog(String inventoryType) {
    String selectedWarehouse = 'Kho 01';

    // Step 2: Select Warehouse (PDF Page 12)
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFFE9E2D5),
            title: const Text('Select warehouse', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 16)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final wh in ['Kho 01', 'Kho 02', 'Kho 03', 'Kho 04'])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildSelectionTile(
                      title: wh,
                      isSelected: selectedWarehouse == wh,
                      onTap: () => setDialogState(() => selectedWarehouse = wh),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF6B5D4D))),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                onPressed: () {
                  Navigator.pop(ctx);
                  _createNewSession(selectedWarehouse, inventoryType);
                },
                child: const Text('OK', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
              ),
            ],
          );
        },
      ),
    );
  }

  static Widget _buildSelectionTile({
    required String title,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0284C7).withValues(alpha: 0.2) : const Color(0xFFF4EFE6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFC7BDAF),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? const Color(0xFF0284C7) : Colors.white38,
              size: 20,
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
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
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
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
    _triggerSub = _uhf.onTriggerStateChanged.listen((_) {});
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
        backgroundColor: const Color(0xFFE9E2D5),
        title: const Text('Confirmation', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 16)),
        content: const Text('Are you sure you want to complete?', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL', style: TextStyle(color: Color(0xFF6B5D4D))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981)),
            onPressed: () {
              _repo.completeInventorySession(widget.session.sessionId, 'Thủ kho PDA');
              Navigator.pop(ctx);
              widget.onBack();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(backgroundColor: Color(0xFF10B981), content: Text('Đã hoàn tất phiếu kiểm kê kho thành công!')),
              );
            },
            child: const Text('OK', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final totalScanned = _scannedEpcs.length;

    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE9E2D5),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2C251E)),
          onPressed: widget.onBack,
        ),
        title: Text(
          s.sessionCode,
          style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.save_outlined, color: Color(0xFF6B5D4D)),
            tooltip: 'Lưu tạm',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Đã lưu tiến độ kiểm kê')),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.check, color: Color(0xFF10B981)),
            tooltip: 'Hoàn tất kiểm kê',
            onPressed: _confirmComplete,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info block matching PDF Page 13
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFE9E2D5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFC7BDAF)),
              ),
              child: Column(
                children: [
                  _buildMetaRow('Inventory no.', s.sessionCode),
                  const SizedBox(height: 6),
                  _buildMetaRow('Inventory date', '${s.startedAt.year}-${s.startedAt.month.toString().padLeft(2, '0')}-${s.startedAt.day.toString().padLeft(2, '0')} ${s.startedAt.hour.toString().padLeft(2, '0')}:${s.startedAt.minute.toString().padLeft(2, '0')}:${s.startedAt.second.toString().padLeft(2, '0')}'),
                  const SizedBox(height: 6),
                  _buildMetaRow('Warehouse', s.zone),
                  const SizedBox(height: 6),
                  _buildMetaRow('Note', 'Kiểm kê định kỳ'),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Summary row
            Text(
              'Số lượng SKU: ${_repo.products.length}\nTổng số thẻ đã đọc: $totalScanned',
              style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),

            // Item / Zone Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFE9E2D5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Khu vực: ${s.zone}',
                    style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  if (s.locationCode != null && s.locationCode!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Text('Vị trí kệ: ', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                        Text(s.locationCode!, style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 12)),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Column(
                        children: [
                          const Text('Kỳ vọng (CSDL)', style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            '${s.matchCount + s.missingCount}',
                            style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 22),
                          ),
                        ],
                      ),
                      Container(width: 1, height: 36, color: const Color(0xFFC7BDAF)),
                      Column(
                        children: [
                          const Text('Thực tế (Đã quét)', style: TextStyle(color: Color(0xFF0284C7), fontSize: 12)),
                          const SizedBox(height: 4),
                          Text(
                            '$totalScanned',
                            style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 22),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),
            // Hardware trigger instruction
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF4EFE6),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.barcode_reader, color: Color(0xFF0284C7), size: 24),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Quét hàng loạt thẻ RFID để đối soát kiểm kê trong kho.',
                      style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 12),
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

  Widget _buildMetaRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 12)),
        Text(value, style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.w500, fontSize: 12)),
      ],
    );
  }
}
