import 'package:flutter/material.dart';

enum AppNotificationType {
  success, // Xanh lá - Thành công
  error,   // Đỏ - Lỗi
  warning, // Vàng - Cảnh báo
  info,    // Xanh dương - Thông tin
}

/// Tiện ích hiển thị thanh trạng thái thông báo chuẩn cho Desktop và PDA
/// - Tự động trượt xuống sau 2 giây (duration: 2s)
/// - Cho phép dùng tay vuốt trượt xuống trên màn hình cảm ứng PDA (dismissDirection: DismissDirection.down)
/// - Tự động xóa thông báo cũ trước khi hiện mới để không bị xếp hàng kẹt lỳ ở đáy màn hình
class AppSnackBar {
  static void show(
    BuildContext context, {
    required String message,
    AppNotificationType type = AppNotificationType.info,
    Duration duration = const Duration(seconds: 2),
    SnackBarAction? action,
  }) {
    if (!context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    // 1. Tự động ẩn thông báo cũ ngay lập tức để trượt xuống, không xếp hàng chờ đợi
    messenger.hideCurrentSnackBar();

    Color bgColor;
    IconData icon;

    switch (type) {
      case AppNotificationType.success:
        bgColor = const Color(0xFF10B981);
        icon = Icons.check_circle_rounded;
        break;
      case AppNotificationType.error:
        bgColor = const Color(0xFFEF4444);
        icon = Icons.error_outline_rounded;
        break;
      case AppNotificationType.warning:
        bgColor = const Color(0xFFF59E0B);
        icon = Icons.warning_amber_rounded;
        break;
      case AppNotificationType.info:
        bgColor = const Color(0xFF0284C7);
        icon = Icons.info_outline_rounded;
        break;
    }

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: bgColor,
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.down, // Dùng tay vuốt trượt xuống trên PDA
        duration: duration, // Tự động trượt xuống sau đúng 2s
        elevation: 6,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  letterSpacing: 0.2,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Nút bấm tắt nhanh nếu muốn đóng ngay lập tức
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => messenger.hideCurrentSnackBar(),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close, color: Colors.white70, size: 18),
              ),
            ),
          ],
        ),
        action: action,
      ),
    );
  }

  /// Thông báo Xanh lá - Thành công (Tự trượt xuống sau 2s, vuốt tay trượt xuống trên PDA)
  static void showSuccess(BuildContext context, String message, {Duration duration = const Duration(seconds: 2)}) {
    show(context, message: message, type: AppNotificationType.success, duration: duration);
  }

  /// Thông báo Đỏ - Thất bại / Lỗi (Tự trượt xuống sau 2s, vuốt tay trượt xuống trên PDA)
  static void showError(BuildContext context, String message, {Duration duration = const Duration(seconds: 2)}) {
    show(context, message: message, type: AppNotificationType.error, duration: duration);
  }

  /// Thông báo Vàng - Cảnh báo / Chú ý (Tự trượt xuống sau 2s, vuốt tay trượt xuống trên PDA)
  static void showWarning(BuildContext context, String message, {Duration duration = const Duration(seconds: 2)}) {
    show(context, message: message, type: AppNotificationType.warning, duration: duration);
  }

  /// Thông báo Xanh dương - Thông tin (Tự trượt xuống sau 2s, vuốt tay trượt xuống trên PDA)
  static void showInfo(BuildContext context, String message, {Duration duration = const Duration(seconds: 2)}) {
    show(context, message: message, type: AppNotificationType.info, duration: duration);
  }
}
