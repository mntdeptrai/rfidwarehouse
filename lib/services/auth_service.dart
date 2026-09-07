import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import '../models/wms_models.dart';
import 'database_service.dart';

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
      // 1. Kiểm tra và khởi tạo tài khoản mặc định nếu CSDL chưa có người dùng nào
      await _seedDefaultUsersIfEmpty();

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

  /// Khởi tạo 2 tài khoản mẫu (Admin và Thủ kho) nếu CSDL chưa có người dùng
  Future<void> _seedDefaultUsersIfEmpty() async {
    try {
      final existingUsers = await _dbService.getUsers();
      if (existingUsers.isEmpty) {
        debugPrint('AuthService: CSDL chưa có người dùng. Đang khởi tạo tài khoản mẫu admin và thukho...');

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
        await _dbService.insertUserWithPassword(adminUser, hashPassword('admin123'));

        final operatorUser = WmsUser(
          userId: 'USER-OP-001',
          username: 'thukho',
          fullName: 'Thủ Kho Trưởng',
          email: 'thukho@rfidwarehouse.com',
          phone: '0987654321',
          role: 'operator',
          isActive: true,
          createdAt: DateTime.now(),
        );
        await _dbService.insertUserWithPassword(operatorUser, hashPassword('123456'));
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
      final userMap = await _dbService.getUserAuth(cleanUsername);

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

      final savedHash = userMap['password_hash'] as String?;
      final inputHash = hashPassword(cleanPassword);

      // Kiểm tra mật khẩu (hỗ trợ cả hash SHA-256 và mật khẩu mẫu)
      final bool isPasswordCorrect = (savedHash != null && savedHash == inputHash) ||
          (savedHash == null && (cleanPassword == 'admin123' || cleanPassword == '123456'));

      if (!isPasswordCorrect) {
        _authError = 'Mật khẩu không chính xác. Vui lòng kiểm tra lại.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Cập nhật lại hash nếu trước đó chưa có
      if (savedHash == null) {
        final updatedUser = WmsUser.fromMap(userMap);
        await _dbService.insertUserWithPassword(updatedUser, inputHash);
      }

      final user = WmsUser.fromMap(userMap);
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

      // 4. Tự động đăng nhập
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
