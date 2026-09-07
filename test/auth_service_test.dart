import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhf/services/auth_service.dart';
import 'package:uhf/services/database_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('AuthService Offline-First Authentication Tests', () {
    late DatabaseService dbService;
    late AuthService authService;

    setUp(() async {
      dbService = DatabaseService();
      authService = AuthService();

      // Reset state
      final db = await dbService.database;
      await db.delete('users');
      await db.delete('system_config');
      await authService.logout();
    });

    test('Password hashing produces consistent SHA-256 salted hash', () {
      final hash1 = AuthService.hashPassword('admin123');
      final hash2 = AuthService.hashPassword('admin123');
      final hashDiff = AuthService.hashPassword('different_password');

      expect(hash1, equals(hash2));
      expect(hash1, isNot(equals(hashDiff)));
      expect(hash1.length, equals(64)); // SHA-256 hex length
    });

    test('AuthService.init() auto-seeds default 4 demo accounts for all roles', () async {
      final initialUsers = await dbService.getUsers();
      expect(initialUsers.isEmpty, isTrue);

      await authService.init(force: true);

      final seededUsers = await dbService.getUsers();
      expect(seededUsers.length, equals(4));

      final admin = seededUsers.firstWhere((u) => u.username == 'admin');
      expect(admin.role, equals('admin'));
      expect(admin.fullName, contains('Quản Trị Viên'));

      final thukho = seededUsers.firstWhere((u) => u.username == 'thukho');
      expect(thukho.role, equals('thukho'));
      expect(thukho.fullName, contains('Thủ Kho'));

      final camtay = seededUsers.firstWhere((u) => u.username == 'camtay');
      expect(camtay.role, equals('handheld'));
      expect(camtay.fullName, contains('Cầm Tay'));

      final seller = seededUsers.firstWhere((u) => u.username == 'seller');
      expect(seller.role, equals('seller'));
      expect(seller.fullName, contains('Bán Hàng'));
    });

    test('Login with valid credentials succeeds for admin', () async {
      await authService.init(force: true);

      final success = await authService.login(
        username: 'admin',
        password: 'admin123',
        rememberMe: true,
      );

      expect(success, isTrue);
      expect(authService.isLoggedIn, isTrue);
      expect(authService.currentUser?.username, equals('admin'));
      expect(authService.currentUser?.role, equals('admin'));

      // Verify session saved in system_config
      final savedId = await dbService.getSystemConfig('active_user_id');
      expect(savedId, equals(authService.currentUser?.userId));
    });

    test('Login with valid credentials succeeds for thukho', () async {
      await authService.init(force: true);

      final success = await authService.login(
        username: 'thukho',
        password: '123456',
        rememberMe: false,
      );

      expect(success, isTrue);
      expect(authService.isLoggedIn, isTrue);
      expect(authService.currentUser?.username, equals('thukho'));
      expect(authService.currentUser?.role, equals('thukho'));
    });

    test('Login with incorrect password fails with error message', () async {
      await authService.init(force: true);

      final success = await authService.login(
        username: 'admin',
        password: 'wrong_password',
      );

      expect(success, isFalse);
      expect(authService.isLoggedIn, isFalse);
      expect(authService.currentUser, isNull);
      expect(authService.authError, isNotNull);
      expect(authService.authError, contains('Mật khẩu không chính xác'));
    });

    test('Login with non-existent user fails with error message', () async {
      await authService.init(force: true);

      final success = await authService.login(
        username: 'ghost_user',
        password: 'password123',
      );

      expect(success, isFalse);
      expect(authService.isLoggedIn, isFalse);
      expect(authService.currentUser, isNull);
      expect(authService.authError, contains('không tồn tại'));
    });

    test('Register new staff user persists to SQLite and logs in immediately', () async {
      await authService.init(force: true);

      final success = await authService.register(
        username: 'nguyenvana',
        fullName: 'Nguyễn Văn A',
        password: 'password123',
        email: 'vana@rfidwms.vn',
        phone: '0987654321',
        role: 'operator',
      );

      expect(success, isTrue);
      expect(authService.isLoggedIn, isTrue);
      expect(authService.currentUser?.username, equals('nguyenvana'));
      expect(authService.currentUser?.fullName, equals('Nguyễn Văn A'));
      expect(authService.currentUser?.role, equals('operator'));

      // Verify user in SQLite
      final authRecord = await dbService.getUserAuth('nguyenvana');
      expect(authRecord, isNotNull);
      expect(authRecord!['password_hash'], equals(AuthService.hashPassword('password123')));
    });

    test('Logout clears current user and session config', () async {
      await authService.init(force: true);
      await authService.login(username: 'admin', password: 'admin123', rememberMe: true);
      expect(authService.isLoggedIn, isTrue);

      await authService.logout();

      expect(authService.isLoggedIn, isFalse);
      expect(authService.currentUser, isNull);

      final savedId = await dbService.getSystemConfig('active_user_id');
      expect(savedId, equals(''));
    });
  });
}
