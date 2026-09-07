import 'roles/role_registry.dart';

/// Người dùng / Nhân viên kho (WmsUser)
class WmsUser {
  final String userId;
  final String username;
  final String fullName;
  final String? email;
  final String? phone;
  final String role; // 'admin', 'thukho', 'handheld', 'seller', etc.
  final bool isActive;
  final DateTime? createdAt;

  const WmsUser({
    required this.userId,
    required this.username,
    required this.fullName,
    this.email,
    this.phone,
    this.role = 'thukho',
    this.isActive = true,
    this.createdAt,
  });

  /// Đối tượng quyền hạn chi tiết gắn liền với vai trò của người dùng
  BaseRolePermission get rolePermission => RoleRegistry.fromCode(role);

  /// Kiểm tra xem người dùng có quyền chỉnh sửa thông số máy/đầu đọc hay không
  /// (Chỉ duy nhất Admin = true; Thủ kho, Máy cầm tay, Seller = false)
  bool get canConfigureHardware => rolePermission.canConfigureHardware;

  Map<String, dynamic> toMap() => {
    'user_id': userId,
    'username': username,
    'full_name': fullName,
    'email': email,
    'phone': phone,
    'role': role,
    'is_active': isActive ? 1 : 0,
    'created_at': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
  };

  factory WmsUser.fromMap(Map<String, dynamic> map) => WmsUser(
    userId: map['user_id'] as String,
    username: map['username'] as String,
    fullName: map['full_name'] as String,
    email: map['email'] as String?,
    phone: map['phone'] as String?,
    role: map['role'] as String? ?? 'thukho',
    isActive: map['is_active'] == 1 || map['is_active'] == true,
    createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
  );
}
