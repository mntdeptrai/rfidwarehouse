import 'role_base.dart';

/// Vai trò: Quản Trị Viên Hệ Thống (Admin)
/// Toàn quyền quản trị hệ thống, cấp và phân quyền tài khoản người dùng
class AdminRole extends BaseRolePermission {
  const AdminRole();

  @override
  String get code => 'admin';

  @override
  String get name => 'Quản Trị Viên (Admin)';

  @override
  String get description => 'Toàn quyền quản trị hệ thống, cấp và phân quyền tài khoản nhân viên';

  @override
  bool get canConfigureHardware => false; // Màn hình chỉnh thông số máy thuộc về role Kỹ thuật

  @override
  bool get canInbound => true;

  @override
  bool get canOutbound => true;

  @override
  bool get canTransfer => true;

  @override
  bool get canAudit => true;

  @override
  bool get canManageUsers => true; // Admin cấp và quản lý tài khoản
}

