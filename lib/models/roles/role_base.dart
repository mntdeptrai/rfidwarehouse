/// Lớp cơ sở trừu tượng định nghĩa quyền hạn của từng Vai Trò (Role Permission)
abstract class BaseRolePermission {
  const BaseRolePermission();

  /// Mã định danh của vai trò trong CSDL (ví dụ: 'admin', 'thukho', 'handheld', 'seller')
  String get code;

  /// Tên hiển thị tiếng Việt của vai trò
  String get name;

  /// Mô tả chi tiết phạm vi quyền hạn
  String get description;

  /// Quyền hạn: Cho phép cấu hình phần cứng & chỉnh sửa thông số máy
  /// (IP, Port, Anten, Công suất phát sóng RF dBm, Cấu hình LAN, Baudrate, Lock/Kill RFID chip)
  ///
  /// QUY TẮC BẢO MẬT:
  /// - CHỈ DUY NHẤT ADMIN = TRUE.
  /// - THỦ KHO, MÁY CẦM TAY, SELLER = FALSE (KHÔNG ĐƯỢC PHÉP CHỈNH).
  bool get canConfigureHardware;

  /// Quyền hạn: Tạo và xác nhận đơn Nhập kho (Inbound)
  bool get canInbound;

  /// Quyền hạn: Tạo và xác nhận đơn Xuất kho (Outbound)
  bool get canOutbound;

  /// Quyền hạn: Điều chuyển kho / Xếp dỡ kệ hàng (Putaway & Transfer)
  bool get canTransfer;

  /// Quyền hạn: Thực hiện kiểm kê kho (Inventory Audit)
  bool get canAudit;

  /// Quyền hạn: Tra cứu vị trí, mã chip RFID, tồn kho sản phẩm
  bool get canLookup => true;

  /// Quyền hạn: Xem báo cáo thống kê kho
  bool get canViewReports => true;

  /// Quyền hạn: Quản lý người dùng, phân quyền tài khoản nhân viên
  bool get canManageUsers => false;

  /// Là vai trò Kỹ thuật viên (Technician)
  bool get isTechnician => false;
}
