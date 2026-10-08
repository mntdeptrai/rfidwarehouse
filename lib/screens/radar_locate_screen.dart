import 'package:flutter/material.dart';
import '../models/wms_models.dart';
import 'fifo_search_screen.dart';

export 'fifo_search_screen.dart';

extension StringCompareExtension on String {
  bool equalsIgnoreCase(String other) => toLowerCase() == other.toLowerCase();
}

/// Màn hình Tìm kiếm & Định vị hàng hóa.
/// Đã chuyển đổi hoàn toàn từ tìm kiếm Radar sang:
/// - Tìm kiếm theo Mã Hàng (Item ID / Serial / EPC) & Mã SKU
/// - Vẽ bản đồ 2D mặt bằng kho vị trí hàng được để
/// - Xác định và hiển thị trực tiếp ô cần lấy theo nguyên tắc FIFO
/// Hoạt động đồng bộ trên cả tay cầm PDA lẫn Desktop.
class RadarLocateScreen extends StatelessWidget {
  final String? initialEpc;
  final LocateOrder? locateTask;
  final Item? initialItem;
  final Pallet? initialPallet;
  final String? initialQuery;
  final String? initialSku;
  final String? initialItemId;

  const RadarLocateScreen({
    super.key,
    this.initialEpc,
    this.locateTask,
    this.initialItem,
    this.initialPallet,
    this.initialQuery,
    this.initialSku,
    this.initialItemId,
  });

  @override
  Widget build(BuildContext context) {
    return FifoSearchScreen(
      initialEpc: initialEpc,
      locateTask: locateTask,
      initialItem: initialItem,
      initialPallet: initialPallet,
      initialQuery: initialQuery,
      initialSku: initialSku,
      initialItemId: initialItemId,
    );
  }
}
