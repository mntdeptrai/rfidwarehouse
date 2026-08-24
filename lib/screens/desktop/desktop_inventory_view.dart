import 'package:flutter/material.dart';
import '../../services/warehouse_repository.dart';
import '../../theme/eye_care_theme.dart';
import '../../models/wms_models.dart';

class DesktopInventoryView extends StatefulWidget {
  const DesktopInventoryView({super.key});

  @override
  State<DesktopInventoryView> createState() => _DesktopInventoryViewState();
}

class _DesktopInventoryViewState extends State<DesktopInventoryView> {
  final WarehouseRepository _repo = WarehouseRepository();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  InventorySession? _selectedSession;

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    _eyeCare.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    if (_selectedSession != null) {
      return _buildSessionDetailView(_selectedSession!, c);
    }
    return _buildSessionListView(c);
  }

  Widget _buildSessionListView(EyeCareColors c) {
    final sessions = _repo.inventorySessions;

    return Container(
      color: c.bgDeep,
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'INVENTORY MANAGEMENT',
                      style: TextStyle(color: c.textSecondary, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Danh Sách Phiên Kiểm Kê Kho',
                      style: TextStyle(color: c.textPrimary, fontSize: 22, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.textPrimary,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('LÀM MỚI'),
                    onPressed: () => _repo.refreshFromDatabase(),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    ),
                    icon: const Icon(Icons.file_download, color: Color(0xFF2C251E), size: 18),
                    label: const Text('BÁO CÁO EXCEL', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
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
                color: c.bgCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.fact_check_outlined, size: 64, color: c.textMuted),
                          const SizedBox(height: 14),
                          Text('Chưa có phiên kiểm kê nào trong CSDL.', style: TextStyle(color: c.textSecondary, fontSize: 14)),
                          const SizedBox(height: 8),
                          Text('Hãy mở máy cầm tay PDA và bấm "Inventory" để tiến hành quét kiểm kê kho.', style: TextStyle(color: c.textMuted, fontSize: 12)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: sessions.length,
                      separatorBuilder: (_, index) => Divider(color: c.border, height: 1),
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
                                  color: c.rfidCyan.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.checklist, color: c.rfidCyan, size: 20),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                flex: 3,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.sessionCode, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text('Time: ${s.startedAt.toString().substring(0, 16)}', style: TextStyle(color: c.textSecondary, fontSize: 11)),
                                  ],
                                ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text('Khu vực: ${s.zone}', style: TextStyle(color: c.textSecondary, fontSize: 13)),
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
                                icon: Icon(Icons.visibility, color: c.rfidCyan, size: 20),
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
                    onPressed: () => setState(() => _selectedSession = null),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Chi tiết kiểm kê: ${s.sessionCode}',
                    style: TextStyle(color: c.textPrimary, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: c.rfidCyan),
                icon: const Icon(Icons.file_download, color: Color(0xFF2C251E), size: 18),
                label: const Text('XUẤT EXCEL', style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold)),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(backgroundColor: Color(0xFF10B981), content: Text('Đã xuất dữ liệu chi tiết kiểm kê ra Excel')),
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

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
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildDetailItem('Mã kiểm kê', s.sessionCode, c),
                        const SizedBox(height: 12),
                        _buildDetailItem('Ngày kiểm kê', '${s.startedAt.year}-${s.startedAt.month.toString().padLeft(2, '0')}-${s.startedAt.day.toString().padLeft(2, '0')}', c),
                        const SizedBox(height: 12),
                        _buildDetailItem('Loại kiểm kê', 'Toàn bộ sản phẩm', c),
                        const SizedBox(height: 12),
                        _buildDetailItem('Kho / Khu vực', s.zone, c),
                        const SizedBox(height: 12),
                        _buildDetailItem('Trạng thái', s.isCompleted ? 'Completed' : 'Scanning', c),
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
                      color: c.bgCard,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.border),
                    ),
                    child: Table(
                      border: TableBorder.all(color: c.border),
                      columnWidths: const {
                        0: FlexColumnWidth(1),
                        1: FlexColumnWidth(3),
                        2: FlexColumnWidth(3),
                        3: FlexColumnWidth(1.5),
                        4: FlexColumnWidth(1.5),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: c.bgCardElevated),
                          children: [
                            Padding(padding: const EdgeInsets.all(10), child: Text('#', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                            Padding(padding: const EdgeInsets.all(10), child: Text('Mã EPC', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                            Padding(padding: const EdgeInsets.all(10), child: Text('Tên sản phẩm', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                            Padding(padding: const EdgeInsets.all(10), child: Text('Trạng thái', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                            Padding(padding: const EdgeInsets.all(10), child: Text('Thời gian', style: TextStyle(color: c.rfidCyan, fontWeight: FontWeight.bold, fontSize: 12))),
                          ],
                        ),
                        if (s.results.isEmpty)
                          TableRow(
                            children: [
                              Padding(padding: const EdgeInsets.all(12), child: Text('-', style: TextStyle(color: c.textMuted, fontSize: 12))),
                              Padding(padding: const EdgeInsets.all(12), child: Text('Chưa có dữ liệu quét', style: TextStyle(color: c.textSecondary, fontSize: 12))),
                              Padding(padding: const EdgeInsets.all(12), child: Text('-', style: TextStyle(color: c.textMuted, fontSize: 12))),
                              Padding(padding: const EdgeInsets.all(12), child: Text('-', style: TextStyle(color: c.textMuted, fontSize: 12))),
                              Padding(padding: const EdgeInsets.all(12), child: Text('-', style: TextStyle(color: c.textMuted, fontSize: 12))),
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
                                Padding(padding: const EdgeInsets.all(10), child: Text('$idx', style: TextStyle(color: c.textSecondary, fontSize: 12))),
                                Padding(padding: const EdgeInsets.all(10), child: Text(r.epc, style: TextStyle(color: c.textSecondary, fontFamily: 'Courier', fontSize: 11))),
                                Padding(padding: const EdgeInsets.all(10), child: Text(prodTitle, style: TextStyle(color: c.textPrimary, fontSize: 12))),
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
                                    style: TextStyle(color: c.textSecondary, fontSize: 11),
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

  Widget _buildDetailItem(String label, String value, EyeCareColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: c.textSecondary, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.bold, fontSize: 13)),
      ],
    );
  }
}

