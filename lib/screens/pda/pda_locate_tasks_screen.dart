import 'package:flutter/material.dart';
import '../../models/wms_models.dart';
import '../../services/warehouse_repository.dart';
import '../../services/auth_service.dart';
import '../../services/supabase_sync_service.dart';
import '../../theme/eye_care_theme.dart';
import '../radar_locate_screen.dart';

/// Màn hình Quản Lý & Thực Hiện Đơn Tìm Kiếm Vị Trí Thẻ trên PDA
class PdaLocateTasksScreen extends StatefulWidget {
  const PdaLocateTasksScreen({super.key});

  @override
  State<PdaLocateTasksScreen> createState() => _PdaLocateTasksScreenState();
}

class _PdaLocateTasksScreenState extends State<PdaLocateTasksScreen> {
  final WarehouseRepository _repo = WarehouseRepository();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  final AuthService _auth = AuthService();

  String _filter = 'MY_TASKS'; // MY_TASKS, PENDING, IN_PROGRESS, COMPLETED, ALL

  @override
  void initState() {
    super.initState();
    _eyeCare.addListener(_onStateUpdate);
    _repo.addListener(_onStateUpdate);
  }

  @override
  void dispose() {
    _repo.removeListener(_onStateUpdate);
    _eyeCare.removeListener(_onStateUpdate);
    super.dispose();
  }

  void _onStateUpdate() {
    if (mounted) setState(() {});
  }

  String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    return '$d/$m $h:$min';
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final currentUser = _auth.currentUser;
    final allOrders = _repo.locateOrders;

    final myOrders = allOrders.where((o) {
      if (currentUser == null) return false;
      return o.assignedToUserId == currentUser.userId ||
          (currentUser.fullName.isNotEmpty &&
              o.assignedToName.trim().toLowerCase() == currentUser.fullName.trim().toLowerCase());
    }).toList();

    final pendingOrders = allOrders.where((o) => o.status == LocateOrderStatus.pending).toList();
    final inProgressOrders = allOrders.where((o) => o.status == LocateOrderStatus.inProgress).toList();
    final completedOrders = allOrders.where((o) => o.status == LocateOrderStatus.completed).toList();

    List<LocateOrder> displayedOrders;
    switch (_filter) {
      case 'MY_TASKS':
        displayedOrders = myOrders;
        break;
      case 'PENDING':
        displayedOrders = pendingOrders;
        break;
      case 'IN_PROGRESS':
        displayedOrders = inProgressOrders;
        break;
      case 'COMPLETED':
        displayedOrders = completedOrders;
        break;
      case 'ALL':
      default:
        displayedOrders = allOrders;
        break;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F4),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAFAF9),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF1C1917)),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: const Text(
          'Đơn Tìm Kiếm Vị Trí (RFID)',
          style: TextStyle(color: Color(0xFF1C1917), fontWeight: FontWeight.bold, fontSize: 16),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            margin: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF2563EB).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2563EB), width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.sensors, size: 14, color: Color(0xFF2563EB)),
                SizedBox(width: 4),
                Text('UHF RADAR', style: TextStyle(color: Color(0xFF2563EB), fontWeight: FontWeight.bold, fontSize: 11)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Color(0xFF57534E)),
            tooltip: 'Làm mới',
            onPressed: () => _repo.reloadFromDatabase(),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: const Color(0xFF2563EB),
        onRefresh: () async {
          await SupabaseSyncService().syncNow();
          await _repo.reloadFromDatabase();
          if (mounted) setState(() {});
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // 1. Thẻ Chuyển Nhanh sang Dò Tìm Tự Do (Radar Sonar / Mũi tên)
            SliverToBoxAdapter(
              child: Container(
                color: const Color(0xFFFAFAF9),
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: InkWell(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const RadarLocateScreen()),
                    );
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.explore_rounded, color: Colors.white, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: const [
                              Text(
                                'TÌM VỊ TRÍ HÀNG 2D (FIFO)',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12.5),
                              ),
                              Text(
                                'Nhập mã hàng/SKU để xem vị trí 2D và ô cần lấy theo FIFO',
                                style: TextStyle(color: Color(0xFFE0F2FE), fontSize: 10.5),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // 2. Filter Segments
            SliverToBoxAdapter(
              child: Container(
                color: const Color(0xFFFAFAF9),
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _buildFilterChip('Giao cho tôi (${myOrders.length})', 'MY_TASKS', Icons.person_rounded),
                      const SizedBox(width: 6),
                      _buildFilterChip('Chờ tìm (${pendingOrders.length})', 'PENDING', Icons.pending_actions_rounded),
                      const SizedBox(width: 6),
                      _buildFilterChip('Đang tìm (${inProgressOrders.length})', 'IN_PROGRESS', Icons.radar_rounded),
                      const SizedBox(width: 6),
                      _buildFilterChip('Đã tìm thấy (${completedOrders.length})', 'COMPLETED', Icons.check_circle_rounded),
                      const SizedBox(width: 6),
                      _buildFilterChip('Tất cả (${allOrders.length})', 'ALL', Icons.list_alt_rounded),
                    ],
                  ),
                ),
              ),
            ),

            // 3. Danh sách Đơn Tìm Kiếm (hỗ trợ vuốt xuống để làm mới)
            if (displayedOrders.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.track_changes_rounded, size: 56, color: Color(0xFF2563EB)),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _filter == 'MY_TASKS'
                              ? 'Chưa có đơn tìm kiếm nào được giao cho bạn'
                              : 'Chưa có đơn tìm kiếm nào trong mục này',
                          style: const TextStyle(color: Color(0xFF1C1917), fontWeight: FontWeight.bold, fontSize: 15),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Quản lý kho sẽ tạo và giao đơn tìm kiếm cho nhân viên cầm tay khi cần tìm hàng thất lạc hoặc cần lấy gấp. Vuốt xuống để làm mới.',
                          style: TextStyle(color: Color(0xFF57534E), fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.all(14),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final order = displayedOrders[index];
                      final isAssignedToMe = currentUser != null &&
                          (order.assignedToUserId == currentUser.userId ||
                              order.assignedToName.trim().toLowerCase() == currentUser.fullName.trim().toLowerCase());

                      return _buildOrderCard(order, isAssignedToMe, c);
                    },
                    childCount: displayedOrders.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String key, IconData icon) {
    final isSelected = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF2563EB) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF2563EB) : const Color(0xFFD6D3D1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? Colors.white : const Color(0xFF57534E),
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : const Color(0xFF1C1917),
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(LocateOrder order, bool isAssignedToMe, EyeCareColors c) {
    final isCompleted = order.status == LocateOrderStatus.completed;
    final statusColor = Color(order.status.colorValue);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAssignedToMe ? const Color(0xFF2563EB).withValues(alpha: 0.6) : const Color(0xFFD6D3D1),
          width: isAssignedToMe ? 1.4 : 1.0,
        ),
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
          // Header: Mã đơn + Huy hiệu trạng thái
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  order.orderNo,
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (isAssignedToMe)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'GIAO CHO BẠN',
                    style: TextStyle(color: Color(0xFF059669), fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: statusColor, width: 0.8),
                ),
                child: Text(
                  order.status.label,
                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Tên đơn / Mặt hàng cần tìm
          Text(
            order.title,
            style: const TextStyle(
              color: Color(0xFF1C1917),
              fontWeight: FontWeight.bold,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 6),

          // Chi tiết mã: SKU, S/N, EPC, Pallet
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (order.targetSku != null && order.targetSku!.isNotEmpty)
                _buildTagChip('SKU: ${order.targetSku!}', const Color(0xFF2563EB)),
              if (order.targetPalletCode != null && order.targetPalletCode!.isNotEmpty)
                _buildTagChip('Pallet: ${order.targetPalletCode!}', const Color(0xFFF59E0B)),
              if (order.targetEpc != null && order.targetEpc!.isNotEmpty)
                _buildTagChip('EPC: ${order.targetEpc!}', const Color(0xFF8B5CF6)),
            ],
          ),
          const SizedBox(height: 8),

          // Vị trí sổ sách
          if (order.expectedLocation != null && order.expectedLocation!.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 14, color: Color(0xFFF59E0B)),
                const SizedBox(width: 4),
                Text(
                  'Vị trí sổ sách: ${order.expectedLocation!}',
                  style: const TextStyle(color: Color(0xFF57534E), fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),

          // Vị trí tìm thấy thực tế nếu đã hoàn thành
          if (isCompleted && order.foundLocation != null && order.foundLocation!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded, size: 14, color: Color(0xFF10B981)),
                const SizedBox(width: 4),
                Text(
                  'Đã tìm thấy tại: ${order.foundLocation!}',
                  style: const TextStyle(color: Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],

          if (order.notes != null && order.notes!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              '💬 Ghi chú: ${order.notes!}',
              style: const TextStyle(color: Color(0xFF57534E), fontSize: 11, fontStyle: FontStyle.italic),
            ),
          ],

          const SizedBox(height: 10),
          const Divider(height: 1, color: Color(0xFFFAFAF9)),
          const SizedBox(height: 8),

          // Footer: Người giao, Người nhận, Nút hành động
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Phụ trách: ${order.assignedToName}',
                      style: const TextStyle(color: Color(0xFF4A3E31), fontSize: 11, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Tạo bởi: ${order.createdBy} (${_formatDate(order.createdAt)})',
                      style: const TextStyle(color: Color(0xFF57534E), fontSize: 10.5),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isCompleted ? const Color(0xFF78716C) : const Color(0xFF2563EB),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                ),
                icon: Icon(
                  isCompleted ? Icons.visibility_rounded : Icons.radar_rounded,
                  size: 16,
                ),
                label: Text(
                  isCompleted ? 'XEM LẠI' : 'TÌM KIẾM',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RadarLocateScreen(
                        locateTask: order,
                        initialEpc: order.targetEpc,
                      ),
                    ),
                  );
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTagChip(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
      ),
    );
  }
}
