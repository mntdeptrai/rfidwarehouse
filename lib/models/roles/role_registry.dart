import 'role_base.dart';
import 'admin_role.dart';
import 'technician_role.dart';
import 'warehouse_keeper_role.dart';
import 'handheld_role.dart';
import 'seller_role.dart';

export 'role_base.dart';
export 'admin_role.dart';
export 'technician_role.dart';
export 'warehouse_keeper_role.dart';
export 'handheld_role.dart';
export 'seller_role.dart';

/// Bộ điều phối và tra cứu Vai Trò (Role Registry)
class RoleRegistry {
  static const AdminRole admin = AdminRole();
  static const TechnicianRole technician = TechnicianRole();
  static const WarehouseKeeperRole warehouseKeeper = WarehouseKeeperRole();
  static const HandheldRole handheld = HandheldRole();
  static const SellerRole seller = SellerRole();

  /// Danh sách tất cả các vai trò khả dụng trong hệ thống
  static const List<BaseRolePermission> allRoles = [
    admin,
    technician,
    warehouseKeeper,
    handheld,
    seller,
  ];

  /// Danh sách dạng Map phục vụ cho Dropdown chọn vai trò khi cấp tài khoản
  static List<Map<String, String>> get dropdownItems => allRoles
      .map((r) => {
            'code': r.code,
            'label': r.name,
            'description': r.description,
          })
      .toList();

  /// Tra cứu đối tượng RolePermission từ mã code (không phân biệt chữ hoa/thường)
  static BaseRolePermission fromCode(String? code) {
    if (code == null || code.trim().isEmpty) {
      return warehouseKeeper;
    }

    final clean = code.trim().toLowerCase();
    switch (clean) {
      case 'admin':
      case 'administrator':
        return admin;

      case 'kythuat':
      case 'technician':
      case 'tech':
      case 'it':
      case 'kythuatvien':
        return technician;

      case 'thukho':
      case 'operator':
      case 'manager':
      case 'kho':
        return warehouseKeeper;

      case 'handheld':
      case 'forklift':
      case 'camtay':
      case 'pda':
        return handheld;

      case 'seller':
      case 'sales':
      case 'sale':
      case 'banhang':
        return seller;

      default:
        return warehouseKeeper;
    }
  }
}

