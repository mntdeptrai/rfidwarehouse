import 'role_base.dart';

/// Vai trò: Kỹ Thuật Viên / Nhân Viên Kỹ Thuật Thiết Bị (Technician)
/// Phụ trách hiệu chỉnh thông số đầu đọc RFID, anten, công suất phát sóng RF dBm,
/// cổng kết nối mạng TCP/IP, cổng COM, Baudrate, đọc/ghi/khóa/hủy chip RFID.
class TechnicianRole extends BaseRolePermission {
  const TechnicianRole();

  @override
  String get code => 'kythuat';

  @override
  String get name => 'Kỹ Thuật Viên (Technician)';

  @override
  String get description => 'Cấu hình thông số đầu đọc RFID, anten, công suất phát sóng RF dBm, kết nối mạng và cổng COM';

  @override
  bool get canConfigureHardware => true; // Kỹ thuật được toàn quyền hiệu chỉnh thông số máy

  @override
  bool get canInbound => true;

  @override
  bool get canOutbound => true;

  @override
  bool get canTransfer => true;

  @override
  bool get canAudit => true;

  @override
  bool get canManageUsers => false;

  @override
  bool get isTechnician => true;
}
