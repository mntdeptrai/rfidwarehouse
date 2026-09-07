import 'role_base.dart';

/// Vai trò: Người Bán Hàng / Nhân Viên Kinh Doanh (Seller / Sales)
/// Chịu trách nhiệm tra cứu tồn kho sản phẩm, tạo và kiểm tra đơn xuất bán hàng.
/// TUYỆT ĐỐI KHÔNG ĐƯỢC CHỈNH THÔNG SỐ PHẦN CỨNG MÁY.
class SellerRole extends BaseRolePermission {
  const SellerRole();

  @override
  String get code => 'seller';

  @override
  String get name => 'Người Bán Hàng (Seller)';

  @override
  String get description => 'Tra cứu tồn kho thực tế, tạo đơn xuất bán hàng. Không chỉnh thông số máy.';

  @override
  bool get canConfigureHardware => false; // KHÔNG được chỉnh thông số máy

  @override
  bool get canInbound => false; // Seller không phụ trách nhập hàng vào kho

  @override
  bool get canOutbound => true; // Seller được tạo và theo dõi đơn xuất hàng

  @override
  bool get canTransfer => false; // Seller không phụ trách chuyển kho

  @override
  bool get canAudit => false; // Seller không phụ trách kiểm kê kho

  @override
  bool get canManageUsers => false;
}
