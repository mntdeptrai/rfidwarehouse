import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wms_models.dart';
import 'database_service.dart';
import 'supabase_sync_service.dart';
import 'warehouse_repository.dart';

class AuthService extends ChangeNotifier {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final DatabaseService _dbService = DatabaseService();

  WmsUser? _currentUser;
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _authError;

  WmsUser? get currentUser => _currentUser;
  bool get isLoggedIn => _currentUser != null;
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get authError => _authError;

  AuthService._internal();

  /// Băm mật khẩu bằng thuật toán SHA-256 kèm salt bảo mật
  static String hashPassword(String password) {
    const salt = 'UHF_RFID_WMS_SALT_2026_SECURE';
    final bytes = utf8.encode('$salt$password$salt');
    return sha256.convert(bytes).toString();
  }

  /// Khởi tạo phiên làm việc khi ứng dụng khởi động
  Future<void> init({bool force = false}) async {
    if (_isInitialized && !force) return;

    try {
      // 1. Khởi tạo tài khoản Quản Trị Viên gốc nếu CSDL hoàn toàn chưa có người dùng
      await _seedDefaultUsersIfEmpty();

      // Dọn dẹp triệt để các tài khoản mẫu (mockdata) cũ nếu còn tồn tại trong CSDL
      const legacyMockUserIds = ['USER-TECH-001', 'USER-OP-001', 'USER-PDA-001', 'USER-SEL-001'];
      for (final mockId in legacyMockUserIds) {
        final existingMock = await _dbService.getUserById(mockId);
        if (existingMock != null) {
          await _dbService.deleteUser(mockId);
        }
      }
      await WarehouseRepository().reloadFromSqlite();

      // 2. Khôi phục phiên đăng nhập trước đó từ SQLite system_config
      final savedUserId = await _dbService.getSystemConfig('active_user_id');
      if (savedUserId != null && savedUserId.trim().isNotEmpty) {
        final user = await _dbService.getUserById(savedUserId.trim());
        if (user != null && user.isActive) {
          _currentUser = user;
          debugPrint('AuthService: Tự động đăng nhập người dùng [${user.username}] - ${user.fullName} (${user.role})');
        } else {
          await _dbService.setSystemConfig('active_user_id', '');
        }
      }
    } catch (e) {
      debugPrint('AuthService.init error: $e');
    } finally {
      _isInitialized = true;
      notifyListeners();
    }
  }

  /// Khởi tạo duy nhất tài khoản Quản Trị Viên gốc (Root Admin) nếu CSDL hoàn toàn trống (Không dùng mockdata)
  Future<void> _seedDefaultUsersIfEmpty() async {
    try {
      final existingUsers = await _dbService.getUsers();
      if (existingUsers.isEmpty) {
        debugPrint('AuthService: CSDL chưa có người dùng nào. Khởi tạo tài khoản Quản Trị Viên gốc (admin)...');

        // Chỉ tạo 1 tài khoản root Admin ban đầu để đăng nhập và cấp phát tài khoản nhân sự
        final adminUser = WmsUser(
          userId: 'USER-ADMIN-001',
          username: 'admin',
          fullName: 'Quản Trị Viên Hệ Thống',
          email: 'admin@rfidwarehouse.com',
          phone: '0901234567',
          role: 'admin',
          isActive: true,
          createdAt: DateTime.now(),
        );
        final adminPassHash = hashPassword('admin123');
        await _dbService.insertUserWithPassword(adminUser, adminPassHash);
        await WarehouseRepository().addUser(adminUser, passwordHash: adminPassHash);

        // Kích hoạt đồng bộ tài khoản admin lên Supabase Cloud nếu có cấu hình
        WarehouseRepository().triggerBackgroundSync();
      }
    } catch (e) {
      debugPrint('AuthService: Lỗi khởi tạo người dùng mặc định: $e');
    }
  }

  /// Đăng nhập tài khoản
  Future<bool> login({
    required String username,
    required String password,
    bool rememberMe = true,
  }) async {
    final cleanUsername = username.trim();
    final cleanPassword = password.trim();

    if (cleanUsername.isEmpty || cleanPassword.isEmpty) {
      _authError = 'Vui lòng nhập đầy đủ tên đăng nhập và mật khẩu.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      Map<String, dynamic>? userMap = await _dbService.getUserAuth(cleanUsername);

      // Nếu trong SQLite cục bộ chưa có user, nhưng máy đang online kết nối Supabase, tìm trực tiếp trên Cloud
      if (userMap == null && SupabaseSyncService().isOnline) {
        try {
          final supa = Supabase.instance.client;
          final List<dynamic> supaUsers = await supa
              .from('users')
              .select()
              .or('username.ilike.$cleanUsername,email.ilike.$cleanUsername')
              .limit(1);

          if (supaUsers.isNotEmpty) {
            final fetched = Map<String, dynamic>.from(supaUsers.first as Map);
            fetched.remove('updated_at');
            if (fetched['is_active'] is bool) {
              fetched['is_active'] = (fetched['is_active'] == true) ? 1 : 0;
            }
            final db = await _dbService.database;
            await db.insert('users', fetched, conflictAlgorithm: ConflictAlgorithm.replace);
            userMap = await _dbService.getUserAuth(cleanUsername);
          }
        } catch (e) {
          debugPrint('Auth online lookup error: $e');
        }
      }

      if (userMap == null) {
        _authError = 'Tài khoản "$cleanUsername" không tồn tại trong hệ thống.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final isActive = userMap['is_active'] == 1 || userMap['is_active'] == true;
      if (!isActive) {
        _authError = 'Tài khoản này đang bị tạm khóa. Vui lòng liên hệ quản trị viên.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      String? savedHash = userMap['password_hash'] as String?;
      final inputHash = hashPassword(cleanPassword);

      // Nếu tài khoản cục bộ chưa có hash nhưng máy có kết nối Supabase, kiểm tra password_hash từ Supabase
      if (savedHash == null && SupabaseSyncService().isOnline) {
        try {
          final supa = Supabase.instance.client;
          final List<dynamic> supaUsers = await supa
              .from('users')
              .select('password_hash')
              .or('username.ilike.$cleanUsername,email.ilike.$cleanUsername')
              .limit(1);

          if (supaUsers.isNotEmpty && supaUsers.first['password_hash'] != null) {
            savedHash = supaUsers.first['password_hash'] as String;
            await _dbService.updateUserPassword(userMap['user_id'] as String, savedHash);
          }
        } catch (e) {
          debugPrint('Auth remote password_hash check error: $e');
        }
      }

      // Kiểm tra mật khẩu (hỗ trợ cả hash SHA-256 và mật khẩu mẫu khi tài khoản chưa có hash)
      final bool isPasswordCorrect = (savedHash != null && savedHash == inputHash) ||
          (savedHash == null && (cleanPassword == 'admin123' || cleanPassword == '123456' || cleanPassword == '12345678'));

      if (!isPasswordCorrect) {
        _authError = 'Mật khẩu không chính xác. Vui lòng kiểm tra lại.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final user = WmsUser.fromMap(userMap);

      // Tự động chữa lành: Cập nhật lại hash vào SQLite và Supabase Cloud nếu trước đó tài khoản chưa có hash
      if (savedHash == null) {
        await _dbService.insertUserWithPassword(user, inputHash);
        await WarehouseRepository().syncUserPassword(user.userId, inputHash);
      }

      _currentUser = user;

      // Lưu phiên làm việc nếu chọn Ghi nhớ
      if (rememberMe) {
        await _dbService.setSystemConfig('active_user_id', user.userId);
      } else {
        await _dbService.setSystemConfig('active_user_id', '');
      }

      _authError = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _authError = 'Lỗi hệ thống đăng nhập: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Đăng ký tài khoản người dùng mới
  Future<bool> register({
    required String username,
    required String password,
    required String fullName,
    String? email,
    String? phone,
    String role = 'operator',
    bool autoLogin = true,
  }) async {
    final cleanUsername = username.trim();
    final cleanPassword = password.trim();
    final cleanFullName = fullName.trim();

    if (cleanUsername.isEmpty) {
      _authError = 'Vui lòng nhập tên đăng nhập.';
      notifyListeners();
      return false;
    }

    if (cleanUsername.length < 3) {
      _authError = 'Tên đăng nhập phải có ít nhất 3 ký tự.';
      notifyListeners();
      return false;
    }

    if (cleanFullName.isEmpty) {
      _authError = 'Vui lòng nhập họ và tên nhân viên.';
      notifyListeners();
      return false;
    }

    if (cleanPassword.length < 6) {
      _authError = 'Mật khẩu phải có tối thiểu 6 ký tự.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      // 1. Kiểm tra xem username đã tồn tại chưa
      final existing = await _dbService.getUserAuth(cleanUsername);
      if (existing != null) {
        _authError = 'Tên đăng nhập "$cleanUsername" đã có người sử dụng. Vui lòng chọn tên khác.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 2. Tạo đối tượng WmsUser mới
      final now = DateTime.now();
      final newUser = WmsUser(
        userId: 'USER-${now.millisecondsSinceEpoch}',
        username: cleanUsername,
        fullName: cleanFullName,
        email: email?.trim().isNotEmpty == true ? email!.trim() : null,
        phone: phone?.trim().isNotEmpty == true ? phone!.trim() : null,
        role: role,
        isActive: true,
        createdAt: now,
      );

      // 3. Băm mật khẩu và lưu vào SQLite
      final hashedPass = hashPassword(cleanPassword);
      await _dbService.insertUserWithPassword(newUser, hashedPass);

      // 4. Đẩy vào WarehouseRepository và đồng bộ lên Supabase Cloud
      await WarehouseRepository().addUser(newUser, passwordHash: hashedPass);

      // 5. Tự động đăng nhập
      if (autoLogin) {
        _currentUser = newUser;
        await _dbService.setSystemConfig('active_user_id', newUser.userId);
      }

      _authError = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _authError = 'Lỗi đăng ký tài khoản: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Quản trị viên cấp tài khoản mới cho nhân viên
  Future<bool> adminCreateUser({
    required String username,
    required String password,
    required String fullName,
    String? email,
    String? phone,
    required String role,
    bool isActive = true,
  }) async {
    final cleanUsername = username.trim();
    final cleanPassword = password.trim();
    final cleanFullName = fullName.trim();

    if (cleanUsername.isEmpty) {
      _authError = 'Vui lòng nhập tên đăng nhập.';
      notifyListeners();
      return false;
    }

    if (cleanUsername.length < 3) {
      _authError = 'Tên đăng nhập phải có ít nhất 3 ký tự.';
      notifyListeners();
      return false;
    }

    if (cleanFullName.isEmpty) {
      _authError = 'Vui lòng nhập họ và tên nhân viên.';
      notifyListeners();
      return false;
    }

    if (cleanPassword.length < 6) {
      _authError = 'Mật khẩu phải có tối thiểu 6 ký tự.';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _authError = null;
    notifyListeners();

    try {
      final existing = await _dbService.getUserAuth(cleanUsername);
      if (existing != null) {
        _authError = 'Tên đăng nhập "$cleanUsername" đã có người sử dụng. Vui lòng chọn tên khác.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final now = DateTime.now();
      final newUser = WmsUser(
        userId: 'USER-${now.millisecondsSinceEpoch}',
        username: cleanUsername,
        fullName: cleanFullName,
        email: email?.trim().isNotEmpty == true ? email!.trim() : null,
        phone: phone?.trim().isNotEmpty == true ? phone!.trim() : null,
        role: role,
        isActive: isActive,
        createdAt: now,
      );

      final hashedPass = hashPassword(cleanPassword);
      await _dbService.insertUserWithPassword(newUser, hashedPass);
      await WarehouseRepository().addUser(newUser, passwordHash: hashedPass);

      _authError = null;
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _authError = 'Lỗi cấp tài khoản: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Quản trị viên cập nhật thông tin tài khoản nhân viên
  Future<bool> adminUpdateUser(WmsUser user) async {
    try {
      await WarehouseRepository().updateUser(user);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('AuthService.adminUpdateUser error: $e');
      return false;
    }
  }

  /// Quản trị viên đặt lại mật khẩu cho tài khoản nhân viên
  Future<bool> adminResetPassword(String userId, String newPassword) async {
    final cleanPass = newPassword.trim();
    if (cleanPass.length < 6) {
      _authError = 'Mật khẩu mới phải có tối thiểu 6 ký tự.';
      notifyListeners();
      return false;
    }
    try {
      final hashedPass = hashPassword(cleanPass);
      await WarehouseRepository().syncUserPassword(userId, hashedPass);
      _authError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _authError = 'Lỗi đặt lại mật khẩu: $e';
      notifyListeners();
      return false;
    }
  }

  /// Quản trị viên khóa hoặc mở khóa tài khoản
  Future<bool> adminToggleUserActive(WmsUser user) async {
    try {
      final updated = WmsUser(
        userId: user.userId,
        username: user.username,
        fullName: user.fullName,
        email: user.email,
        phone: user.phone,
        role: user.role,
        isActive: !user.isActive,
        createdAt: user.createdAt,
      );
      await WarehouseRepository().updateUser(updated);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('AuthService.adminToggleUserActive error: $e');
      return false;
    }
  }

  /// Quản trị viên xóa tài khoản nhân viên
  Future<bool> adminDeleteUser(String userId) async {
    if (_currentUser?.userId == userId) {
      _authError = 'Không thể tự xóa tài khoản quản trị viên đang đăng nhập.';
      notifyListeners();
      return false;
    }
    try {
      await WarehouseRepository().deleteUser(userId);
      _authError = null;
      notifyListeners();
      return true;
    } catch (e) {
      _authError = 'Lỗi xóa tài khoản: $e';
      notifyListeners();
      return false;
    }
  }

  /// Đăng xuất khỏi hệ thống
  Future<void> logout() async {
    _currentUser = null;
    _authError = null;
    try {
      await _dbService.setSystemConfig('active_user_id', '');
    } catch (_) {}
    notifyListeners();
  }
}
