import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/wms_models.dart';
import '../services/warehouse_repository.dart';
import '../theme/eye_care_theme.dart';
import '../screens/radar_locate_screen.dart';

/// Hộp thoại hiển thị toàn bộ Nhật ký vòng đời (Audit Trail / Lifecycle Timeline) của một thẻ RFID
class TagLifecycleTimelineDialog extends StatelessWidget {
  final String epc;
  final Item? item;

  const TagLifecycleTimelineDialog({
    super.key,
    required this.epc,
    this.item,
  });

  /// Hàm tiện ích mở Dialog nhanh
  static Future<void> show(BuildContext context, {required String epc, Item? item}) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => TagLifecycleTimelineDialog(epc: epc, item: item),
    );
  }

  IconData _getActionIcon(TagLifecycleAction action) {
    switch (action) {
      case TagLifecycleAction.encoded:
        return Icons.qr_code_2_rounded;
      case TagLifecycleAction.inboundGate:
        return Icons.door_sliding_rounded;
      case TagLifecycleAction.inboundPda:
        return Icons.phone_android_rounded;
      case TagLifecycleAction.palletize:
        return Icons.pallet;
      case TagLifecycleAction.putaway:
        return Icons.shelves;
      case TagLifecycleAction.transferLocation:
        return Icons.swap_horiz_rounded;
      case TagLifecycleAction.transferPallet:
        return Icons.move_down_rounded;
      case TagLifecycleAction.mergePallet:
        return Icons.merge_rounded;
      case TagLifecycleAction.auditMatch:
        return Icons.check_circle_outline_rounded;
      case TagLifecycleAction.auditMisplaced:
        return Icons.wrong_location_rounded;
      case TagLifecycleAction.auditMissing:
        return Icons.help_outline_rounded;
      case TagLifecycleAction.auditFound:
        return Icons.auto_awesome_rounded;
      case TagLifecycleAction.locateFound:
        return Icons.track_changes_rounded;
      case TagLifecycleAction.allocatePo:
        return Icons.bookmark_added_rounded;
      case TagLifecycleAction.picked:
        return Icons.shopping_basket_outlined;
      case TagLifecycleAction.outboundGate:
        return Icons.output_rounded;
      case TagLifecycleAction.outboundPda:
        return Icons.check_box_outlined;
      case TagLifecycleAction.statusChange:
        return Icons.edit_note_rounded;
      case TagLifecycleAction.unauthorizedExit:
        return Icons.warning_amber_rounded;
    }
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString();
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$min:$s • $d/$m/$y';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Vừa xong';
    if (diff.inMinutes < 60) return '${diff.inMinutes} phút trước';
    if (diff.inHours < 24) return '${diff.inHours} giờ trước';
    if (diff.inDays < 30) return '${diff.inDays} ngày trước';
    return '${(diff.inDays / 30).floor()} tháng trước';
  }

  @override
  Widget build(BuildContext context) {
    final repo = WarehouseRepository();
    final eyeCare = EyeCareThemeService();
    final c = eyeCare.colors;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 700;

    // Lấy thông tin Item thực tế
    final effItem = item ?? repo.findItemByEpc(epc);
    final logs = repo.getTagLifecycle(epc);

    // Tính toán thông tin hiển thị
    final sku = effItem?.sku ?? 'SKU-RFID';
    final prodName = effItem?.productName ?? 'Chip RFID';
    final serial = (effItem?.serialNumber != null && effItem!.serialNumber.isNotEmpty)
        ? effItem!.serialNumber
        : '--';
    final location = effItem?.locationId ?? 'Chưa xác định';
    final pallet = effItem?.palletId ?? 'Không có';
    final status = effItem?.status.label ?? 'Chưa rõ';

    return Dialog(
      backgroundColor: c.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.border),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: isCompact ? 12 : 24,
        vertical: isCompact ? 16 : 28,
      ),
      child: Container(
        width: isCompact ? double.infinity : 680,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. HEADER MODAL
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: c.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0284C7).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFF0284C7).withValues(alpha: 0.3)),
                        ),
                        child: const Icon(Icons.history_edu_rounded, color: Color(0xFF0284C7), size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NHẬT KÝ VÒNG ĐỜI THẺ RFID',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontWeight: FontWeight.bold,
                                fontSize: isCompact ? 14 : 16,
                                letterSpacing: 0.5,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Toàn bộ lịch sử lưu vết thay đổi trạng thái, vị trí & pallet',
                              style: TextStyle(color: c.textSecondary, fontSize: isCompact ? 11 : 12),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: c.textSecondary, size: 20),
                        tooltip: 'Đóng',
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Chip thông tin EPC & Sản phẩm
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: c.bgDeep,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: c.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.sensors, size: 14, color: c.rfidBlue),
                            const SizedBox(width: 6),
                            Text('Mã EPC: ', style: TextStyle(color: c.textMuted, fontSize: 11)),
                            Expanded(
                              child: SelectableText(
                                epc,
                                style: TextStyle(
                                  color: c.textPrimary,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: epc));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Đã sao chép mã EPC vào clipboard!'), duration: Duration(seconds: 1)),
                                );
                              },
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Icon(Icons.copy_rounded, size: 14, color: c.textSecondary),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 12,
                          runSpacing: 4,
                          children: [
                            _buildInfoBadge('Mặt hàng: $sku • $prodName', c.rfidCyan, c),
                            if (serial != '--') _buildInfoBadge('SN: $serial', c.textSecondary, c),
                            _buildInfoBadge('Vị trí: $location', const Color(0xFF10B981), c),
                            if (pallet != 'Không có') _buildInfoBadge('Pallet: $pallet', const Color(0xFFF59E0B), c),
                            _buildInfoBadge('Trạng thái: $status', const Color(0xFF8B5CF6), c),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // 2. TIMELINE BODY
            Expanded(
              child: logs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.hourglass_empty_rounded, size: 48, color: c.textMuted.withValues(alpha: 0.5)),
                          const SizedBox(height: 12),
                          Text('Chưa có lịch sử vòng đời nào cho thẻ này.', style: TextStyle(color: c.textSecondary, fontSize: 13)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      physics: const BouncingScrollPhysics(),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        final isLast = index == logs.length - 1;
                        final isFirst = index == 0;
                        final color = Color(log.action.colorValue);
                        final icon = _getActionIcon(log.action);

                        return IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Cột dòng thời gian bên trái
                              SizedBox(
                                width: 36,
                                child: Column(
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                        border: Border.all(color: color, width: isFirst ? 2 : 1.5),
                                      ),
                                      child: Icon(icon, size: 14, color: color),
                                    ),
                                    if (!isLast)
                                      Expanded(
                                        child: Container(
                                          width: 2,
                                          color: c.border,
                                          margin: const EdgeInsets.symmetric(vertical: 4),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),

                              // Thẻ nội dung sự kiện
                              Expanded(
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: isFirst ? color.withValues(alpha: 0.05) : c.bgCardElevated,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: isFirst ? color.withValues(alpha: 0.4) : c.border,
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Dòng tiêu đề hành động + Thời gian
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: color.withValues(alpha: 0.15),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              log.action.label,
                                              style: TextStyle(
                                                color: color,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                          if (isFirst) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: const Text(
                                                'MỚI NHẤT',
                                                style: TextStyle(
                                                  color: Color(0xFF10B981),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                          const Spacer(),
                                          Text(
                                            _timeAgo(log.timestamp),
                                            style: TextStyle(color: c.textMuted, fontSize: 10.5),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),

                                      // Thời gian chi tiết
                                      Row(
                                        children: [
                                          Icon(Icons.schedule_rounded, size: 12, color: c.textMuted),
                                          const SizedBox(width: 4),
                                          Text(
                                            _formatDateTime(log.timestamp),
                                            style: TextStyle(color: c.textSecondary, fontSize: 11),
                                          ),
                                          if (log.documentNo != null && log.documentNo!.isNotEmpty) ...[
                                            const SizedBox(width: 10),
                                            Icon(Icons.receipt_long_rounded, size: 12, color: c.rfidCyan),
                                            const SizedBox(width: 3),
                                            Text(
                                              'Số Đơn: ${log.documentNo}',
                                              style: TextStyle(color: c.rfidCyan, fontSize: 11, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ],
                                      ),

                                      // Chi tiết chuyển đổi trạng thái / Vị trí / Pallet
                                      if (log.fromLocation != null || log.toLocation != null || log.fromPallet != null || log.toPallet != null) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                                          decoration: BoxDecoration(
                                            color: c.bgDeep.withValues(alpha: 0.6),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Wrap(
                                            spacing: 12,
                                            runSpacing: 4,
                                            children: [
                                              if (log.fromLocation != null || log.toLocation != null)
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.location_on, size: 12, color: Color(0xFFEF4444)),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Vị trí: ${log.fromLocation ?? "Chưa có"} ➔ ${log.toLocation ?? "Đã giải phóng"}',
                                                      style: TextStyle(color: c.textPrimary, fontSize: 11),
                                                    ),
                                                  ],
                                                ),
                                              if (log.fromPallet != null || log.toPallet != null)
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Icon(Icons.pallet, size: 12, color: Color(0xFFF59E0B)),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      'Pallet: ${log.fromPallet ?? "Không"} ➔ ${log.toPallet ?? "Tách Pallet"}',
                                                      style: TextStyle(color: c.textPrimary, fontSize: 11),
                                                    ),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                      ],

                                      // Ghi chú hoặc thông điệp chi tiết
                                      if (log.notes != null && log.notes!.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          log.notes!,
                                          style: TextStyle(color: c.textPrimary, fontSize: 11.5),
                                        ),
                                      ],

                                      // Người thực hiện & Thiết bị
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Icon(Icons.person_outline_rounded, size: 12, color: c.textMuted),
                                          const SizedBox(width: 4),
                                          Text(
                                            log.performedBy,
                                            style: TextStyle(color: c.textSecondary, fontSize: 10.5, fontWeight: FontWeight.w500),
                                          ),
                                          if (log.device != null && log.device!.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Text('•', style: TextStyle(color: c.textMuted)),
                                            const SizedBox(width: 8),
                                            Icon(Icons.devices_rounded, size: 12, color: c.textMuted),
                                            const SizedBox(width: 4),
                                            Text(
                                              log.device!,
                                              style: TextStyle(color: c.textMuted, fontSize: 10.5),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),

            // 3. FOOTER ACTIONS
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: c.bgCardElevated,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: c.border)),
              ),
              child: Row(
                children: [
                  Text(
                    'Tổng cộng: ${logs.length} mốc sự kiện',
                    style: TextStyle(color: c.textMuted, fontSize: 11),
                  ),
                  const Spacer(),
                  // Nút mở Radar AirTag định vị thẻ này ngay lập tức
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF0284C7),
                      side: const BorderSide(color: Color(0xFF0284C7)),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.track_changes_rounded, size: 14),
                    label: const Text('Dò sóng AirTag', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RadarLocateScreen(
                            initialItem: effItem,
                            initialEpc: epc,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.bgDeep,
                      foregroundColor: c.textPrimary,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(color: c.border),
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Đóng', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBadge(String text, Color color, EyeCareColors c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w600),
      ),
    );
  }
}
