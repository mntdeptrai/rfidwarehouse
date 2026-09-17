import 'role_base.dart';

/// Vai trò: Máy Cầm Tay / Nhân Viên Quét PDA (Handheld PDA Operator)
/// Chịu trách nhiệm quét kiểm kê thực địa, cất hàng vào kệ (putaway), tra cứu chip RFID.
/// TUYỆT ĐỐI KHÔNG ĐƯỢC CHỈNH THÔNG SỐ PHẦN CỨNG MÁY.
class HandheldRole extends BaseRolePermission {
  const HandheldRole();

  @override
  String get code => 'handheld';

  @override
  String get name => 'Máy Cầm Tay (Handheld PDA)';

  @override
  String get description => 'Quét mã RFID/Barcode thực địa, xếp kệ, kiểm đếm tồn kho, điều chỉnh công suất ăng-ten PDA.';

  @override
  bool get canConfigureHardware => false; // KHÔNG được chỉnh thông số kết nối cổng/IP cố định

  @override
  bool get canAdjustAntennaPower => true; // Cấp quyền điều chỉnh công suất phát ăng-ten cho PDA

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
}
