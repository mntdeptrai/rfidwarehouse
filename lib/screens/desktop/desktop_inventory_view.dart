import 'package:flutter/material.dart';
import '../../services/warehouse_repository.dart';
import '../../models/wms_models.dart';

class DesktopInventoryView extends StatefulWidget {
  const DesktopInventoryView({super.key});

  @override
  State<DesktopInventoryView> createState() => _DesktopInventoryViewState();
}

class _DesktopInventoryViewState extends State<DesktopInventoryView> {
  final WarehouseRepository _repo = WarehouseRepository();
  InventorySession? _selectedSession;

  @override
  Widget build(BuildContext context) {
    if (_selectedSession != null) {
      return _buildSessionDetailView(_selectedSession!);
    }
    return _buildSessionListView();
  }

  Widget _buildSessionListView() {
    final sessions = _repo.inventorySessions;

    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INVENTORY MANAGEMENT',
                      style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: 4),
                    Text(
                      'List of inventory sessions',
                      style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Color(0xFF334155)),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('RELOAD'),
                    onPressed: () => _repo.refreshFromDatabase(),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    icon: const Icon(Icons.file_download, color: Colors.white, size: 18),
                    label: const Text('EXCEL REPORT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(backgroundColor: Color(0xFF10B981), content: Text('Đã xuất báo cáo kiểm kê ra file Excel')),
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Table
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF334155)),
              ),
              child: sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.fact_check_outlined, size: 64, color: Colors.white24),
                          const SizedBox(height: 14),
                          const Text('Chưa có phiên kiểm kê nào trong CSDL.', style: TextStyle(color: Colors.white70, fontSize: 14)),
                          const SizedBox(height: 8),
                          const Text('Hãy mở máy cầm tay PDA và bấm "Inventory" để tiến hành quét kiểm kê kho.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: sessions.length,
                      separatorBuilder: (_, index) => const Divider(color: Color(0xFF334155), height: 1),
                      itemBuilder: (context, index) {
                        final s = sessions[index];
                        final isCompleted = s.isCompleted;

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0284C7).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.checklist, color: Color(0xFF38BDF8), size: 20),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.sessionCode, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text('Time: ${s.startedAt.toString().substring(0, 16)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text('Khu vực: ${s.zone}', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text('Khớp: ${s.matchCount} / ${s.matchCount + s.missingCount}', style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold, fontSize: 13)),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: isCompleted ? const Color(0xFF10B981).withValues(alpha: 0.2) : const Color(0xFFF59E0B).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
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
                              const SizedBox(width: 20),
                              IconButton(
                                icon: const Icon(Icons.visibility, color: Color(0xFF38BDF8), size: 20),
                                onPressed: () => setState(() => _selectedSession = s),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionDetailView(InventorySession s) {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header matching PDF Page 13
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => setState(() => _selectedSession = null),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Inventories View only: ${s.sessionCode}',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0284C7)),
                icon: const Icon(Icons.file_download, color: Colors.white, size: 18),
                label: const Text('EXCEL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(backgroundColor: Color(0xFF10B981), content: Text('Đã xuất dữ liệu chi tiết kiểm kê ra Excel')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // 2-Column layout matching PDF Page 13
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column: Info block
                SizedBox(
                  width: 320,
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailItem('Inventory no.', s.sessionCode),
                        const SizedBox(height: 12),
                        _buildDetailItem('Inventory date', '${s.startedAt.year}-${s.startedAt.month.toString().padLeft(2, '0')}-${s.startedAt.day.toString().padLeft(2, '0')}'),
                        const SizedBox(height: 12),
                        _buildDetailItem('Inventory type', 'All products'),
                        const SizedBox(height: 12),
                        _buildDetailItem('Warehouse', s.zone),
                        const SizedBox(height: 12),
                        _buildDetailItem('Status', s.isCompleted ? 'Completed' : 'Scanning'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 20),

                // Right column: Table
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Table(
                      border: TableBorder.all(color: const Color(0xFF334155)),
                      columnWidths: const {
                        0: FlexColumnWidth(1),
                        1: FlexColumnWidth(3),
                        2: FlexColumnWidth(3),
                        3: FlexColumnWidth(1.5),
                        4: FlexColumnWidth(1.5),
                      },
                      children: [
                        const TableRow(
                          decoration: BoxDecoration(color: Color(0xFF0F172A)),
                          children: [
                            Padding(padding: EdgeInsets.all(10), child: Text('#', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12))),
                            Padding(padding: EdgeInsets.all(10), child: Text('Mã EPC', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12))),
                            Padding(padding: EdgeInsets.all(10), child: Text('Tên sản phẩm', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12))),
                            Padding(padding: EdgeInsets.all(10), child: Text('Trạng thái', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12))),
                            Padding(padding: EdgeInsets.all(10), child: Text('Thời gian', style: TextStyle(color: Color(0xFF38BDF8), fontWeight: FontWeight.bold, fontSize: 12))),
                          ],
                        ),
                        if (s.results.isEmpty)
                          const TableRow(
                            children: [
                              Padding(padding: EdgeInsets.all(12), child: Text('-', style: TextStyle(color: Colors.white54, fontSize: 12))),
                              Padding(padding: EdgeInsets.all(12), child: Text('Chưa có dữ liệu quét', style: TextStyle(color: Colors.white54, fontSize: 12))),
                              Padding(padding: EdgeInsets.all(12), child: Text('-', style: TextStyle(color: Colors.white54, fontSize: 12))),
                              Padding(padding: EdgeInsets.all(12), child: Text('-', style: TextStyle(color: Colors.white54, fontSize: 12))),
                              Padding(padding: EdgeInsets.all(12), child: Text('-', style: TextStyle(color: Colors.white54, fontSize: 12))),
                            ],
                          )
                        else
                          ...s.results.asMap().entries.map((entry) {
                            final idx = entry.key + 1;
                            final r = entry.value;
                            final prodTitle = (r.productName != null && r.productName!.isNotEmpty)
                                ? r.productName!
                                : ((r.sku != null && r.sku!.isNotEmpty) ? r.sku! : 'Chưa phân loại');

                            return TableRow(
                              children: [
                                Padding(padding: const EdgeInsets.all(10), child: Text('$idx', style: const TextStyle(color: Colors.white70, fontSize: 12))),
                                Padding(padding: const EdgeInsets.all(10), child: Text(r.epc, style: const TextStyle(color: Colors.white70, fontFamily: 'Courier', fontSize: 11))),
                                Padding(padding: const EdgeInsets.all(10), child: Text(prodTitle, style: const TextStyle(color: Colors.white, fontSize: 12))),
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                    r.resultType.label,
                                    style: TextStyle(
                                      color: Color(r.resultType.colorValue),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                    '${r.readAt.hour.toString().padLeft(2, '0')}:${r.readAt.minute.toString().padLeft(2, '0')}:${r.readAt.second.toString().padLeft(2, '0')}',
                                    style: const TextStyle(color: Colors.white60, fontSize: 11),
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
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}
