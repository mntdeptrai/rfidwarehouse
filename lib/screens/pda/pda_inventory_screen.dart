import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final UhfService _uhf = UhfService();
  InventorySession? _activeSession;

  @override
  void initState() {
    super.initState();
    // Bắt buộc kích hoạt chế độ đọc thẻ UHF RFID cho toàn bộ màn hình kiểm kê kho
    _uhf.setScanMode(PdaScanMode.rfid);
  }

  @override
  void dispose() {
    _uhf.stopInventory();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_activeSession != null) {
      return _buildInventoryScanningScreen(_activeSession!);
    }
    return AnimatedBuilder(
      animation: _repo,
      builder: (context, _) => _buildSessionListScreen(),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF0284C7), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.sensors, size: 14, color: Color(0xFF0284C7)),
                SizedBox(width: 4),
                Text('RFID UHF', style: TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          ),
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
                  onTap: () {
                    _uhf.setScanMode(PdaScanMode.rfid);
                    setState(() => _activeSession = s);
                  },
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
                            if (s.completedAt != null)
                              Text(
                                'Chốt: ${_formatDate(s.completedAt!)}',
                                style: const TextStyle(color: Color(0xFF059669), fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Quét: ${s.actualScannedCount}',
                                style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Hệ thống: ${s.knownInDbCount}',
                                style: const TextStyle(color: Color(0xFF059669), fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                            if (s.varianceOrUnknownCount > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Lệch/Lạ: ${s.varianceOrUnknownCount}',
                                  style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 11),
                                ),
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
    String selectedType = 'by_location';

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
                    title: '1. Theo từng Vị trí / Kệ kho (Sơ đồ kho)',
                    subtitle: 'Đối soát chi tiết hàng tồn trên CSDL tại kệ cụ thể vs thực tế quét',
                    icon: Icons.grid_view_rounded,
                    isSelected: selectedType == 'by_location',
                    onTap: () => setDialogState(() => selectedType = 'by_location'),
                  ),
                  const SizedBox(height: 10),
                  _buildInventoryTypeCard(
                    title: '2. Theo Phân Khu / Khu vực (Zone)',
                    subtitle: 'Kiểm kê toàn bộ các kệ thuộc 1 phân khu (Khu A, Khu B...)',
                    icon: Icons.warehouse_rounded,
                    isSelected: selectedType == 'by_zone',
                    onTap: () => setDialogState(() => selectedType = 'by_zone'),
                  ),
                  const SizedBox(height: 10),
                  _buildInventoryTypeCard(
                    title: '3. Kiểm kê toàn bộ kho hàng',
                    subtitle: 'Quét đối soát toàn bộ hàng hóa và mọi vị trí trong kho',
                    icon: Icons.storefront_outlined,
                    isSelected: selectedType == 'all',
                    onTap: () => setDialogState(() => selectedType = 'all'),
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
                  if (selectedType == 'by_location') {
                    _showSelectLocationDialog();
                  } else if (selectedType == 'by_zone') {
                    _showSelectZoneDialog();
                  } else {
                    _createNewSession(warehouse: 'Toàn bộ kho', locationCode: null);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSelectLocationDialog() {
    final searchCtrl = TextEditingController();
    final allLocations = _repo.locations;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final query = searchCtrl.text.trim().toLowerCase();
          final filtered = allLocations.where((l) {
            if (query.isEmpty) return true;
            return l.locationCode.toLowerCase().contains(query) ||
                l.displayName.toLowerCase().contains(query) ||
                l.zone.toLowerCase().contains(query) ||
                l.shelf.toLowerCase().contains(query);
          }).toList();

          return AlertDialog(
            backgroundColor: const Color(0xFFFBF8F3),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            actionsPadding: const EdgeInsets.all(16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.grid_view_rounded, color: Color(0xFF0284C7), size: 20),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Chọn Kệ Kho Cần Kiểm Kê',
                    style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 380,
              height: 420,
              child: Column(
                children: [
                  TextField(
                    controller: searchCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Tìm theo mã kệ (vd: A-01-01), tên kệ...',
                      hintStyle: const TextStyle(color: Color(0xFF8C7E6D), fontSize: 12),
                      prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF0284C7)),
                      filled: true,
                      fillColor: const Color(0xFFF4EFE6),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD1C7BA))),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFD1C7BA))),
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(
                            child: Text(
                              'Không tìm thấy vị trí kệ kho nào phù hợp',
                              style: TextStyle(color: Color(0xFF8C7E6D), fontSize: 12.5),
                            ),
                          )
                        : ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, _) => const Divider(color: Color(0xFFE9E2D5), height: 1),
                            itemBuilder: (context, idx) {
                              final loc = filtered[idx];
                              final dbItemCount = _repo.items.where((it) {
                                if (it.status != ItemStatus.inStock) return false;
                                final itemLoc = _repo.resolveItemLocation(it);
                                return itemLoc?.locationCode.toUpperCase() == loc.locationCode.toUpperCase() ||
                                       itemLoc?.locationId.toUpperCase() == loc.locationId.toUpperCase();
                              }).length;

                              return InkWell(
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _createNewSession(warehouse: loc.zone, locationCode: loc.locationCode);
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: const Icon(Icons.location_on_outlined, color: Color(0xFF0284C7), size: 18),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Text(
                                                  loc.locationCode,
                                                  style: const TextStyle(
                                                    color: Color(0xFF2C251E),
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13.5,
                                                    fontFamily: 'monospace',
                                                  ),
                                                ),
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFF0284C7).withValues(alpha: 0.12),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    loc.zone.isNotEmpty ? loc.zone : 'Khu vực chung',
                                                    style: const TextStyle(color: Color(0xFF0369A1), fontSize: 10, fontWeight: FontWeight.bold),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              loc.displayName,
                                              style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 11.5),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: dbItemCount > 0 ? const Color(0xFF10B981).withValues(alpha: 0.12) : const Color(0xFFF4EFE6),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '$dbItemCount SP',
                                          style: TextStyle(
                                            color: dbItemCount > 0 ? const Color(0xFF059669) : const Color(0xFF8C7E6D),
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
                  ),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFC7BDAF))),
                onPressed: () => Navigator.pop(ctx),
                child: const Text('QUAY LẠI', style: TextStyle(color: Color(0xFF6B5D4D))),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSelectZoneDialog() {
    final dbZones = _repo.locations.map((l) => l.zone.trim()).where((z) => z.isNotEmpty).toSet().toList();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFBF8F3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        actionsPadding: const EdgeInsets.all(16),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.warehouse_rounded, color: Color(0xFF0284C7), size: 20),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Chọn Phân Khu Kiểm Kê',
                style: TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: dbZones.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(
                    child: Text('Chưa có phân khu nào được cấu hình trong CSDL.', style: TextStyle(color: Color(0xFF8C7E6D), fontSize: 13)),
                  ),
                )
              : SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final z in dbZones) ...[
                        Builder(builder: (_) {
                          final rackCount = _repo.locations.where((l) => l.zone.trim().toUpperCase() == z.toUpperCase()).length;
                          final itemCount = _repo.items.where((it) {
                            if (it.status != ItemStatus.inStock) return false;
                            final loc = _repo.resolveItemLocation(it);
                            return loc?.zone.trim().toUpperCase() == z.toUpperCase();
                          }).length;

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: InkWell(
                              onTap: () {
                                Navigator.pop(ctx);
                                _createNewSession(warehouse: z, locationCode: null);
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: const Color(0xFFD1C7BA)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.location_on, color: Color(0xFF0284C7), size: 20),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(z, style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 13.5)),
                                          Text('$rackCount vị trí kệ kho', style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 11)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0284C7).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text('$itemCount SP', style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 11)),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
        ),
        actions: [
          OutlinedButton(
            style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFFC7BDAF))),
            onPressed: () => Navigator.pop(ctx),
            child: const Text('QUAY LẠI', style: TextStyle(color: Color(0xFF6B5D4D))),
          ),
        ],
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

  void _createNewSession({required String warehouse, String? locationCode}) {
    _uhf.setScanMode(PdaScanMode.rfid);
    final session = _repo.startInventorySession(
      zone: warehouse,
      locationCode: locationCode,
    );
    setState(() => _activeSession = session);
  }

  Widget _buildInventoryScanningScreen(InventorySession session) {
    return _InventoryScanningSubScreen(
      session: session,
      onBack: () {
        _uhf.setScanMode(PdaScanMode.rfid);
        _uhf.stopInventory();
        setState(() => _activeSession = null);
      },
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
  StreamSubscription? _barcodeSub;
  StreamSubscription? _triggerSub;
  Timer? _uiRefreshTimer;

  // Bộ lọc kết quả: 'all', 'match', 'missing', 'wrong', 'unknown'
  String _selectedFilter = 'all';
  int _lastWrongLocationCount = 0;
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _manualEpcCtrl = TextEditingController();
  bool _showManualInput = false;

  @override
  void initState() {
    super.initState();
    // Đảm bảo module phần cứng ở chế độ đọc chip RFID UHF
    _uhf.setScanMode(PdaScanMode.rfid);

    // Nạp sẵn danh sách EPC thực tế đã quét trước đó nếu có
    for (final r in widget.session.results) {
      if (r.epc.isNotEmpty && r.resultType != InventoryVarianceType.missing) {
        _scannedEpcs.add(r.epc);
      }
    }

    _lastWrongLocationCount = widget.session.wrongLocationCount;

    // Kích hoạt tính toán đối chiếu ban đầu (không trigger notifyListeners để tránh build collision)
    _repo.processAuditScan(
      sessionId: widget.session.sessionId,
      scannedEpcs: _scannedEpcs.toList(),
      notify: false,
    );

    // Chỉ kích hoạt bộ đọc nếu phiên kiểm kê ĐANG MỞ (chưa hoàn tất)
    if (!widget.session.isCompleted) {
      _subscribeScanner();
    }
  }

  void _scheduleUiRefresh() {
    if (widget.session.isCompleted) return;
    if (_uiRefreshTimer?.isActive ?? false) return;
    _uiRefreshTimer = Timer(const Duration(milliseconds: 60), () {
      if (mounted && !widget.session.isCompleted) {
        _repo.processAuditScan(
          sessionId: widget.session.sessionId,
          scannedEpcs: _scannedEpcs.toList(),
          notify: false,
        );

        // Cảnh báo rung haptic mạnh nếu phát hiện chip từ kho khác lạc vào
        if (widget.session.wrongLocationCount > _lastWrongLocationCount) {
          _lastWrongLocationCount = widget.session.wrongLocationCount;
          HapticFeedback.heavyImpact();
        }
        setState(() {});
      }
    });
  }

  void _subscribeScanner() {
    if (widget.session.isCompleted) return;

    // 1. Quét chip RFID UHF
    _tagSub = _uhf.onTagRead.listen((tag) {
      if (widget.session.isCompleted) return;
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (tag.epc.isNotEmpty) {
        final cleanEpc = tag.epc.trim();
        if (_uhf.filterDuplicates && _scannedEpcs.contains(cleanEpc)) return;
        _scannedEpcs.add(cleanEpc);
        _scheduleUiRefresh();
      }
    });

    // 2. Hỗ trợ quét mã vạch Barcode nếu kiểm kê các mặt hàng có tem barcode
    _barcodeSub = _uhf.onBarcodeRead.listen((barcode) {
      if (widget.session.isCompleted) return;
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      final clean = barcode.trim();
      if (clean.isEmpty) return;

      final matchedItem = _repo.items.where((it) {
        final epc = it.epc.toLowerCase();
        final sn = it.serialNumber.toLowerCase();
        final sku = it.sku.toLowerCase();
        final itemId = it.itemId.toLowerCase();
        final q = clean.toLowerCase();
        return epc == q || sn == q || sku == q || itemId == q;
      }).firstOrNull;

      final epcToAdd = matchedItem?.epc ?? clean;
      if (!_scannedEpcs.contains(epcToAdd)) {
        _scannedEpcs.add(epcToAdd);
        _scheduleUiRefresh();
      }
    });

    // 3. Lắng nghe bóp cò vật lý trên báng súng PDA
    _triggerSub = _uhf.onTriggerStateChanged.listen((isPressed) {
      if (widget.session.isCompleted) return;
      if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? true)) return;
      if (isPressed) {
        _startHardwareScan();
      } else {
        _stopHardwareScan();
      }
    });
  }

  void _startHardwareScan() {
    if (_isScanning) return;
    setState(() => _isScanning = true);
    // Kiểm kê kho trên PDA luôn luôn đọc chip sóng UHF RFID
    _uhf.setScanMode(PdaScanMode.rfid);
    _uhf.startInventory();
  }

  void _stopHardwareScan() {
    if (!_isScanning) return;
    setState(() => _isScanning = false);
    _uhf.stopInventory();
  }

  void _toggleScanning() async {
    if (widget.session.isCompleted) return;
    if (_isScanning) {
      _stopHardwareScan();
    } else {
      _startHardwareScan();
    }
  }

  void _addManualEpc() {
    final raw = _manualEpcCtrl.text.trim();
    if (raw.isEmpty) return;
    _manualEpcCtrl.clear();
    FocusScope.of(context).unfocus();

    if (_scannedEpcs.contains(raw)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mã EPC này đã được quét hoặc nhập trước đó.')),
      );
      return;
    }

    setState(() {
      _scannedEpcs.add(raw);
      _repo.processAuditScan(
        sessionId: widget.session.sessionId,
        scannedEpcs: _scannedEpcs.toList(),
      );
      if (widget.session.wrongLocationCount > _lastWrongLocationCount) {
        _lastWrongLocationCount = widget.session.wrongLocationCount;
        HapticFeedback.heavyImpact();
      }
    });
  }

  Future<void> _relocateItem(InventoryItemResult result) async {
    final targetCode = widget.session.locationCode;
    if (targetCode == null || targetCode.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Color(0xFFEF4444),
          content: Text('Không thể chuyển vị trí vì phiên kiểm kê theo phân khu, chưa chọn kệ cụ thể.'),
        ),
      );
      return;
    }

    final targetLoc = _repo.locations.where((l) =>
      l.locationCode.trim().toUpperCase() == targetCode.trim().toUpperCase() ||
      l.locationId.trim().toUpperCase() == targetCode.trim().toUpperCase() ||
      l.locationId.trim().toUpperCase().replaceAll('LOC-', '') == targetCode.trim().toUpperCase().replaceAll('LOC-', '')
    ).firstOrNull;

    final targetId = targetLoc?.locationId ?? targetCode;
    final performer = _repo.resolveUserFullName(null, defaultRole: 'handheld');

    final ok = await _repo.moveItemIndividual(
      epc: result.epc,
      newLocationId: targetId,
      performedBy: performer,
    );

    if (mounted) {
      setState(() {
        if (ok) {
          _repo.processAuditScan(
            sessionId: widget.session.sessionId,
            scannedEpcs: _scannedEpcs.toList(),
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: ok ? const Color(0xFF10B981) : const Color(0xFFEF4444),
          content: Text(ok
              ? '✓ Đã cập nhật sản phẩm "${result.productName ?? result.epc}" về vị trí ${targetLoc?.displayName ?? targetCode}!'
              : 'Thao tác chuyển vị trí thất bại. Vui lòng thử lại.'),
        ),
      );
    }
  }

  @override
  void dispose() {
    _uhf.stopInventory();
    _uhf.clearTags();
    _uiRefreshTimer?.cancel();
    _tagSub?.cancel();
    _barcodeSub?.cancel();
    _triggerSub?.cancel();
    _manualEpcCtrl.dispose();
    _searchCtrl.dispose();
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
          'Bạn có chắc chắn muốn chốt số liệu kiểm kê này (${_scannedEpcs.length} chip thực tế đã đọc)? Kết quả kiểm kê và đối chiếu sẽ được lưu vào hệ thống.',
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
            onPressed: () async {
              _uiRefreshTimer?.cancel();
              _tagSub?.cancel();
              _triggerSub?.cancel();
              await _uhf.stopInventory();
              _uhf.clearTags();

              _repo.processAuditScan(
                sessionId: widget.session.sessionId,
                scannedEpcs: _scannedEpcs.toList(),
              );

              if (ctx.mounted) Navigator.pop(ctx);
              widget.onBack();

              await _repo.completeInventorySession(widget.session.sessionId, _repo.resolveUserFullName(null, defaultRole: 'handheld'));
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    backgroundColor: Color(0xFF10B981),
                    content: Text('Đã hoàn tất và lưu số liệu phiếu kiểm kê!'),
                  ),
                );
              }
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
    final isDone = s.isCompleted;

    // Tính toán số lượng tồn CSDL đối chiếu
    final expectedDbCount = s.matchCount + s.missingCount;
    final totalScanned = _scannedEpcs.length;
    final matchCount = s.matchCount;
    final missingCount = s.missingCount;
    final wrongLocCount = s.wrongLocationCount;
    final unknownCount = s.unknownEpcCount;

    // Thông tin hiển thị vị trí kiểm kê
    final loc = widget.session.locationCode != null
        ? _repo.locations.where((l) =>
            l.locationCode == widget.session.locationCode ||
            l.locationId == widget.session.locationCode).firstOrNull
        : null;
    final locDisplayTitle = loc != null
        ? 'Kệ: ${loc.locationCode} • ${loc.displayName}'
        : (s.locationCode != null ? 'Kệ: ${s.locationCode}' : 'Phân khu: ${s.zone}');

    // Lọc danh sách kết quả theo tab và tìm kiếm
    final searchQ = _searchCtrl.text.trim().toLowerCase();
    final filteredResults = s.results.where((r) {
      if (_selectedFilter == 'match' && r.resultType != InventoryVarianceType.match) return false;
      if (_selectedFilter == 'missing' && r.resultType != InventoryVarianceType.missing) return false;
      if (_selectedFilter == 'wrong' && r.resultType != InventoryVarianceType.wrongLocation) return false;
      if (_selectedFilter == 'unknown' && r.resultType != InventoryVarianceType.unknownEpc) return false;

      if (searchQ.isNotEmpty) {
        final epc = r.epc.toLowerCase();
        final name = (r.productName ?? '').toLowerCase();
        final sku = (r.sku ?? '').toLowerCase();
        final expLoc = (r.expectedLocation ?? '').toLowerCase();
        final actLoc = (r.actualLocation ?? '').toLowerCase();
        return epc.contains(searchQ) || name.contains(searchQ) || sku.contains(searchQ) || expLoc.contains(searchQ) || actLoc.contains(searchQ);
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: const Color(0xFFF4EFE6),
      appBar: AppBar(
        backgroundColor: const Color(0xFFE9E2D5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF2C251E)),
          onPressed: () async {
            _uiRefreshTimer?.cancel();
            _tagSub?.cancel();
            _triggerSub?.cancel();
            await _uhf.stopInventory();
            _uhf.clearTags();
            widget.onBack();
          },
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  s.sessionCode,
                  style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFF0284C7), width: 0.8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.sensors, size: 10, color: Color(0xFF0284C7)),
                      SizedBox(width: 3),
                      Text('RFID UHF', style: TextStyle(color: Color(0xFF0284C7), fontSize: 9.5, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                if (isDone) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF10B981), width: 0.8),
                    ),
                    child: const Text('ĐÃ CHỐT SỐ LIỆU', style: TextStyle(color: Color(0xFF059669), fontSize: 9.5, fontWeight: FontWeight.bold)),
                  ),
                ],
              ],
            ),
            Text(
              locDisplayTitle,
              style: const TextStyle(color: Color(0xFF0369A1), fontSize: 11, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(_showManualInput ? Icons.keyboard_hide : Icons.keyboard, color: const Color(0xFF6B5D4D)),
            tooltip: 'Nhập EPC thủ công',
            onPressed: () => setState(() => _showManualInput = !_showManualInput),
          ),
          if (!isDone)
            IconButton(
              icon: const Icon(Icons.check_circle, color: Color(0xFF10B981), size: 26),
              tooltip: 'Hoàn tất kiểm kê',
              onPressed: _confirmComplete,
            ),
        ],
      ),
      body: Column(
        children: [
          // Banner nếu phiếu đã chốt
          if (isDone)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: const [
                  Icon(Icons.lock_outline, color: Color(0xFF059669), size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Phiếu kiểm kê này ĐÃ ĐƯỢC CHỐT SỐ LIỆU. Đầu đọc RFID đã tắt để bảo toàn kết quả.',
                      style: TextStyle(color: Color(0xFF065F46), fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          // CẢNH BÁO NỔI BẬT: Khi phát hiện chip từ kho/kệ khác lạc vào
          if (wrongLocCount > 0)
            Container(
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFEF4444), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDC2626),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'CẢNH BÁO: CÓ $wrongLocCount CHIP TỪ KHO/KỆ KHÁC VÀO ĐÂY!',
                          style: const TextStyle(
                            color: Color(0xFF991B1B),
                            fontWeight: FontWeight.w900,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Sản phẩm thuộc vị trí khác trên CSDL nhưng quét thấy tại đây.',
                          style: TextStyle(color: Color(0xFF7F1D1D), fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _selectedFilter = 'wrong'),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFDC2626),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'XEM NGAY',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // KHỐI ĐỐI CHIẾU SỐ LƯỢNG THỰC TỒN VÀ TỒN KHO DATABASE (6 chỉ số rõ ràng)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFD1C7BA)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Hàng 1: Tổng quan đối chiếu
                Row(
                  children: [
                    _buildKpiCard(
                      title: 'Tồn Database',
                      value: '$expectedDbCount',
                      unit: 'SP',
                      color: const Color(0xFF1E293B),
                      bg: const Color(0xFFF1F5F9),
                      onTap: () => setState(() => _selectedFilter = 'all'),
                    ),
                    const SizedBox(width: 6),
                    _buildKpiCard(
                      title: 'Thực tế quét',
                      value: '$totalScanned',
                      unit: 'Chip',
                      color: const Color(0xFF0284C7),
                      bg: const Color(0xFFE0F2FE),
                      onTap: () => setState(() => _selectedFilter = 'all'),
                    ),
                    const SizedBox(width: 6),
                    _buildKpiCard(
                      title: '✓ Khớp vị trí',
                      value: '$matchCount',
                      unit: 'SP',
                      color: const Color(0xFF059669),
                      bg: const Color(0xFFECFDF5),
                      onTap: () => setState(() => _selectedFilter = 'match'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                // Hàng 2: Chi tiết sai lệch
                Row(
                  children: [
                    _buildKpiCard(
                      title: '⚠️ Chưa quét (Thiếu)',
                      value: '$missingCount',
                      unit: 'SP',
                      color: const Color(0xFFD97706),
                      bg: const Color(0xFFFFFBEB),
                      onTap: () => setState(() => _selectedFilter = 'missing'),
                    ),
                    const SizedBox(width: 6),
                    _buildKpiCard(
                      title: '⛔ Từ kho khác',
                      value: '$wrongLocCount',
                      unit: 'SP',
                      color: const Color(0xFFDC2626),
                      bg: const Color(0xFFFEF2F2),
                      highlightBorder: wrongLocCount > 0,
                      onTap: () => setState(() => _selectedFilter = 'wrong'),
                    ),
                    const SizedBox(width: 6),
                    _buildKpiCard(
                      title: '❓ Thẻ lạ',
                      value: '$unknownCount',
                      unit: 'Thẻ',
                      color: const Color(0xFF7C3AED),
                      bg: const Color(0xFFF5F3FF),
                      onTap: () => setState(() => _selectedFilter = 'unknown'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Ô nhập mã EPC thủ công (nếu bật)
          if (_showManualInput)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF0284C7)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit_note, color: Color(0xFF0284C7), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _manualEpcCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Nhập mã EPC để kiểm tra...',
                        border: InputBorder.none,
                        isDense: true,
                        hintStyle: TextStyle(fontSize: 12, color: Color(0xFF8C7E6D)),
                      ),
                      style: const TextStyle(fontSize: 12, fontFamily: 'Courier'),
                      onSubmitted: (_) => _addManualEpc(),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _addManualEpc,
                    child: const Text('THÊM', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),

          // THANH LỌC PHÂN LOẠI TAB (Segmented Filter Tabs)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildFilterTabChip(
                    id: 'all',
                    label: 'Tất cả (${s.results.length})',
                    color: const Color(0xFF2C251E),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterTabChip(
                    id: 'match',
                    label: '✓ Khớp ($matchCount)',
                    color: const Color(0xFF059669),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterTabChip(
                    id: 'missing',
                    label: '⚠️ Thiếu ($missingCount)',
                    color: const Color(0xFFD97706),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterTabChip(
                    id: 'wrong',
                    label: '⛔ Từ kho khác ($wrongLocCount)',
                    color: const Color(0xFFDC2626),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterTabChip(
                    id: 'unknown',
                    label: '❓ Thẻ lạ ($unknownCount)',
                    color: const Color(0xFF7C3AED),
                  ),
                ],
              ),
            ),
          ),

          // Ô tìm kiếm nhanh
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFD1C7BA)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search, size: 18, color: Color(0xFF8C7E6D)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'Tìm theo tên SP, SKU, EPC hoặc vị trí...',
                        border: InputBorder.none,
                        isDense: true,
                        hintStyle: TextStyle(fontSize: 11.5, color: Color(0xFF8C7E6D)),
                      ),
                      style: const TextStyle(fontSize: 12),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  if (_searchCtrl.text.isNotEmpty)
                    InkWell(
                      onTap: () {
                        _searchCtrl.clear();
                        setState(() {});
                      },
                      child: const Icon(Icons.clear, size: 16, color: Color(0xFF8C7E6D)),
                    ),
                ],
              ),
            ),
          ),

          // DANH SÁCH CHI TIẾT TỪNG SẢN PHẨM / CHIP THEO ĐỐI CHIẾU
          Expanded(
            child: filteredResults.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isScanning ? Icons.sensors : Icons.check_circle_outline,
                          size: 40,
                          color: _isScanning ? const Color(0xFF0284C7) : const Color(0xFF8F8070),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _isScanning
                              ? 'Đang phát sóng đọc thẻ RFID...'
                              : (s.results.isEmpty
                                  ? 'Chưa có dữ liệu kiểm kê cho vị trí này.'
                                  : 'Không có sản phẩm nào thuộc bộ lọc này.'),
                          style: TextStyle(
                            color: _isScanning ? const Color(0xFF0284C7) : const Color(0xFF6B5D4D),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: filteredResults.length,
                    itemBuilder: (context, index) {
                      final r = filteredResults[index];
                      return _buildItemAuditCard(r, isDone);
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
            child: isDone
                ? SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF059669),
                        side: const BorderSide(color: Color(0xFF059669), width: 1.5),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('QUAY LẠI DANH SÁCH (ĐÃ HOÀN TẤT)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      onPressed: () async {
                        await _uhf.stopInventory();
                        widget.onBack();
                      },
                    ),
                  )
                : Row(
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

  Widget _buildFilterTabChip({
    required String id,
    required String label,
    required Color color,
  }) {
    final isSelected = _selectedFilter == id;
    return InkWell(
      onTap: () => setState(() => _selectedFilter = id),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? color : const Color(0xFFD1C7BA),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : const Color(0xFF6B5D4D),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 11,
          ),
        ),
      ),
    );
  }

  Widget _buildItemAuditCard(InventoryItemResult r, bool isDone) {
    switch (r.resultType) {
      case InventoryVarianceType.wrongLocation:
        // Cảnh báo chip từ kho/kệ khác lạc vào
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFEF2F2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFDC2626), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFDC2626).withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFDC2626).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.wrong_location_rounded, color: Color(0xFFDC2626), size: 18),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDC2626),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '⛔ TỪ KHO/KỆ KHÁC VÀO ĐÂY',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 9.5),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              r.sku ?? '',
                              style: const TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.bold, fontSize: 11),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          r.productName ?? 'Sản phẩm chưa đặt tên',
                          style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'EPC: ${r.epc}',
                          style: const TextStyle(color: Color(0xFF6B5D4D), fontFamily: 'Courier', fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // DÒNG THÔNG BÁO VÀ ĐỐI CHIẾU RÕ RÀNG
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.storage, size: 14, color: Color(0xFFDC2626)),
                        const SizedBox(width: 4),
                        const Text('Tồn trên CSDL: ', style: TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.bold, fontSize: 11)),
                        Expanded(
                          child: Text(
                            r.expectedLocation ?? 'Kho khác / Chưa gán',
                            style: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.pin_drop, size: 14, color: Color(0xFF0369A1)),
                        const SizedBox(width: 4),
                        const Text('Quét thấy tại: ', style: TextStyle(color: Color(0xFF0369A1), fontWeight: FontWeight.bold, fontSize: 11)),
                        Expanded(
                          child: Text(
                            r.actualLocation ?? 'Vị trí hiện tại',
                            style: const TextStyle(color: Color(0xFF0284C7), fontWeight: FontWeight.bold, fontSize: 11),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (!isDone && widget.session.locationCode != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    ),
                    icon: const Icon(Icons.drive_file_move_outline, size: 16, color: Colors.white),
                    label: const Text(
                      'CẬP NHẬT VỊ TRÍ VỀ KỆ NÀY TRÊN DB',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                    onPressed: () => _relocateItem(r),
                  ),
                ),
              ],
            ],
          ),
        );

      case InventoryVarianceType.missing:
        // Hàng trên CSDL nhưng chưa quét thấy
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFF59E0B), width: 1.2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.search_off_rounded, color: Color(0xFFD97706), size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD97706),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('⚠️ CHƯA QUÉT THẤY', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                        const Spacer(),
                        Text(r.sku ?? '', style: const TextStyle(color: Color(0xFFB45309), fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      r.productName ?? 'Sản phẩm',
                      style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    Text(
                      'EPC: ${r.epc}',
                      style: const TextStyle(color: Color(0xFF6B5D4D), fontFamily: 'Courier', fontSize: 10.5),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Tồn CSDL tại: ${r.expectedLocation ?? "Kệ này"} (Thủ kho cần kiểm tra tìm lại)',
                      style: const TextStyle(color: Color(0xFF92400E), fontSize: 10, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case InventoryVarianceType.match:
        // Khớp hoàn toàn
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Text('✓ ĐÚNG VỊ TRÍ', style: TextStyle(color: Color(0xFF059669), fontSize: 9, fontWeight: FontWeight.bold)),
                        ),
                        const Spacer(),
                        Text(r.sku ?? '', style: const TextStyle(color: Color(0xFF059669), fontSize: 10.5, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      r.productName ?? 'Sản phẩm',
                      style: const TextStyle(color: Color(0xFF2C251E), fontWeight: FontWeight.bold, fontSize: 12),
                    ),
                    Text(
                      'EPC: ${r.epc}',
                      style: const TextStyle(color: Color(0xFF6B5D4D), fontFamily: 'Courier', fontSize: 10.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

      case InventoryVarianceType.unknownEpc:
        // Thẻ lạ chưa khai báo trong CSDL
        return Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFFAF5FF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.help_outline_rounded, color: Color(0xFF7C3AED), size: 16),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C3AED),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('❓ THẺ LẠ CHƯA KHAI BÁO', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'EPC: ${r.epc}',
                      style: const TextStyle(color: Color(0xFF2C251E), fontFamily: 'Courier', fontWeight: FontWeight.bold, fontSize: 11.5),
                    ),
                    const Text(
                      'Thẻ RFID quét được nhưng chưa được đăng ký mã sản phẩm trên CSDL.',
                      style: TextStyle(color: Color(0xFF6B5D4D), fontSize: 10),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    }
  }

  static Widget _buildKpiCard({
    required String title,
    required String value,
    required String unit,
    required Color color,
    required Color bg,
    bool highlightBorder = false,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: highlightBorder
                ? Border.all(color: color, width: 1.5)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(color: Color(0xFF6B5D4D), fontSize: 9.5, fontWeight: FontWeight.w500),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    value,
                    style: TextStyle(color: color, fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    unit,
                    style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 9.5, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

