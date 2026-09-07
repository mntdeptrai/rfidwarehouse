import 'role_base.dart';

/// Vai trò: Quản Trị Viên Hệ Thống (Admin)
/// Toàn quyền quản trị, cấu hình phần cứng RFID, chỉnh thông số máy, IP/Port, công suất phát
class AdminRole extends BaseRolePermission {
  const AdminRole();

  @override
  String get code => 'admin';

  @override
  String get name => 'Quản Trị Viên (Admin)';

  @override
  String get description => 'Toàn quyền cấu hình đầu đọc RFID, công suất máy, kết nối mạng và quản trị hệ thống';

  @override
  bool get canConfigureHardware => true; // Admin được toàn quyền chỉnh thông số máy

  @override
  bool get canInbound => true;

  @override
  bool get canOutbound => true;

  @override
  bool get canTransfer => true;

  @override
  bool get canAudit => true;

  @override
  bool get canManageUsers => true;
}
