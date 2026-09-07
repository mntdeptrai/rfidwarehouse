/// Người dùng / Nhân viên kho (WmsUser)
class WmsUser {
  final String userId;
  final String username;
  final String fullName;
  final String? email;
  final String? phone;
  final String role; // 'admin', 'manager', 'operator', 'forklift'
  final bool isActive;
  final DateTime? createdAt;

  const WmsUser({
    required this.userId,
    required this.username,
    required this.fullName,
    this.email,
    this.phone,
    this.role = 'operator',
    this.isActive = true,
    this.createdAt,
  });

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
    role: map['role'] as String? ?? 'operator',
    isActive: map['is_active'] == 1 || map['is_active'] == true,
    createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
  );
}
