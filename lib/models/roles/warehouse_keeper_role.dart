import 'role_base.dart';

/// Vai trò: Thủ Kho / Nhân Viên Quản Lý Kho (Warehouse Keeper)
/// Chịu trách nhiệm Nhập kho, Xuất kho, Chuyển kho, Kiểm kê.
/// TUYỆT ĐỐI KHÔNG ĐƯỢC CHỈNH THÔNG SỐ PHẦN CỨNG MÁY.
class WarehouseKeeperRole extends BaseRolePermission {
  const WarehouseKeeperRole();

  @override
  String get code => 'thukho';

  @override
  String get name => 'Thủ Kho (Warehouse Keeper)';

  @override
  String get description => 'Vận hành nhập xuất kho, kiểm kê, điều chuyển vị trí. Không chỉnh thông số máy.';

  @override
  bool get canConfigureHardware => false; // KHÔNG được chỉnh thông số máy

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
