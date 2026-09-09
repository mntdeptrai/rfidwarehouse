import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhf/services/auth_service.dart';
import 'package:uhf/services/database_service.dart';
import 'package:uhf/models/wms_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('AuthService Offline-First Authentication & Admin Management Tests', () {
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

    test('AuthService.init() auto-seeds only root admin when empty (No mock users)', () async {
      final initialUsers = await dbService.getUsers();
      expect(initialUsers.isEmpty, isTrue);

      await authService.init(force: true);

      final seededUsers = await dbService.getUsers();
      // Zero mockdata: Only root admin account is initialized
      expect(seededUsers.length, equals(1));

      final admin = seededUsers.firstWhere((u) => u.username == 'admin');
      expect(admin.role, equals('admin'));
      expect(admin.fullName, contains('Quản Trị Viên'));

      // Ensure no mock users exist
      expect(seededUsers.any((u) => u.username == 'kythuat'), isFalse);
      expect(seededUsers.any((u) => u.username == 'thukho'), isFalse);
      expect(seededUsers.any((u) => u.username == 'camtay'), isFalse);
      expect(seededUsers.any((u) => u.username == 'seller'), isFalse);
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
      expect(authService.currentUser?.rolePermission.canManageUsers, isTrue);
      expect(authService.currentUser?.rolePermission.canConfigureHardware, isFalse);

      // Verify session saved in system_config
      final savedId = await dbService.getSystemConfig('active_user_id');
      expect(savedId, equals(authService.currentUser?.userId));
    });

    test('Login with valid credentials succeeds for kythuat provisioned by admin', () async {
      await authService.init(force: true);
      await authService.login(username: 'admin', password: 'admin123');
      await authService.adminCreateUser(
        username: 'kythuat',
        fullName: 'Kỹ Thuật Viên Thiết Bị',
        password: '123456',
        role: 'kythuat',
        isActive: true,
      );
      await authService.logout();

      final success = await authService.login(
        username: 'kythuat',
        password: '123456',
        rememberMe: false,
      );

      expect(success, isTrue);
      expect(authService.isLoggedIn, isTrue);
      expect(authService.currentUser?.username, equals('kythuat'));
      expect(authService.currentUser?.role, equals('kythuat'));
      expect(authService.currentUser?.rolePermission.canConfigureHardware, isTrue);
      expect(authService.currentUser?.rolePermission.canManageUsers, isFalse);
    });

    test('Login with valid credentials succeeds for thukho provisioned by admin', () async {
      await authService.init(force: true);
      await authService.login(username: 'admin', password: 'admin123');
      await authService.adminCreateUser(
        username: 'thukho',
        fullName: 'Thủ Kho Trưởng',
        password: '123456',
        role: 'thukho',
        isActive: true,
      );
      await authService.logout();

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

    test('Admin provisions new staff account without automatically logging in', () async {
      await authService.init(force: true);
      await authService.login(username: 'admin', password: 'admin123');

      final success = await authService.adminCreateUser(
        username: 'tech_lan',
        fullName: 'Kỹ Thuật Viên Lan',
        password: 'password123',
        email: 'lan@rfidwms.vn',
        phone: '0987112233',
        role: 'kythuat',
        isActive: true,
      );

      expect(success, isTrue);
      // Admin should remain logged in
      expect(authService.currentUser?.username, equals('admin'));

      // Verify user persisted to SQLite
      final authRecord = await dbService.getUserAuth('tech_lan');
      expect(authRecord, isNotNull);
      expect(authRecord!['role'], equals('kythuat'));
      expect(authRecord['password_hash'], equals(AuthService.hashPassword('password123')));

      // Now verify new user can log in
      await authService.logout();
      final loginSuccess = await authService.login(username: 'tech_lan', password: 'password123');
      expect(loginSuccess, isTrue);
      expect(authService.currentUser?.rolePermission.canConfigureHardware, isTrue);
    });

    test('Admin resets password for staff account', () async {
      await authService.init(force: true);
      await authService.login(username: 'admin', password: 'admin123');

      // Admin provisions staff user first (No mockdata)
      await authService.adminCreateUser(
        username: 'staff_thukho',
        fullName: 'Thủ Kho Test',
        password: 'initial_pass',
        role: 'thukho',
        isActive: true,
      );

      final targetUser = await dbService.getUserAuth('staff_thukho');
      expect(targetUser, isNotNull);

      final resetSuccess = await authService.adminResetPassword(targetUser!['user_id'], 'newpass654');
      expect(resetSuccess, isTrue);

      // Old password should fail
      await authService.logout();
      final failLogin = await authService.login(username: 'staff_thukho', password: 'initial_pass');
      expect(failLogin, isFalse);

      // New password should succeed
      final okLogin = await authService.login(username: 'staff_thukho', password: 'newpass654');
      expect(okLogin, isTrue);
    });

    test('Admin toggles active/inactive state and locked user cannot login', () async {
      await authService.init(force: true);
      await authService.login(username: 'admin', password: 'admin123');

      // Admin provisions seller user first (No mockdata)
      await authService.adminCreateUser(
        username: 'seller_test',
        fullName: 'Seller Test',
        password: 'password123',
        role: 'seller',
        isActive: true,
      );

      final userMap = await dbService.getUserAuth('seller_test');
      final user = WmsUser.fromMap(userMap!);

      // Toggle to inactive
      await authService.adminToggleUserActive(user);

      // Attempt login should fail due to account disabled
      final loginResult = await authService.login(username: 'seller_test', password: 'password123');
      expect(loginResult, isFalse);
      expect(authService.authError, contains('tạm khóa'));

      // Toggle back to active
      final inactiveUserMap = await dbService.getUserAuth('seller_test');
      final inactiveUser = WmsUser.fromMap(inactiveUserMap!);
      await authService.adminToggleUserActive(inactiveUser);

      // Should succeed now
      final loginOk = await authService.login(username: 'seller_test', password: 'password123');
      expect(loginOk, isTrue);
    });

    test('Admin cannot delete their own currently active account', () async {
      await authService.init(force: true);
      await authService.login(username: 'admin', password: 'admin123');

      final deleteSelf = await authService.adminDeleteUser(authService.currentUser!.userId);
      expect(deleteSelf, isFalse);
      expect(authService.authError, contains('Không thể tự xóa'));
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

    test('User with null password_hash from cloud sync can login with 12345678 and gets self-healed in SQLite', () async {
      await authService.init(force: true);

      // Simulate a user pulled from Cloud with null password_hash
      final cloudUser = WmsUser(
        userId: 'USER-CLOUD-001',
        username: 'pda_test',
        fullName: 'Test PDA Worker',
        role: 'thukho',
        isActive: true,
        createdAt: DateTime.now(),
      );
      final db = await dbService.database;
      final map = cloudUser.toMap();
      map['password_hash'] = null;
      await db.insert('users', map);

      // Verify password_hash is null initially
      final initialAuth = await dbService.getUserAuth('pda_test');
      expect(initialAuth, isNotNull);
      expect(initialAuth!['password_hash'], isNull);

      // Logging in with 12345678 should succeed via fallback
      final loginSuccess = await authService.login(username: 'pda_test', password: '12345678');
      expect(loginSuccess, isTrue);
      expect(authService.currentUser?.username, equals('pda_test'));

      // Verify self-healing: password_hash is now populated in SQLite
      final healedAuth = await dbService.getUserAuth('pda_test');
      expect(healedAuth!['password_hash'], equals(AuthService.hashPassword('12345678')));

      // Next login with 12345678 uses hashed password
      await authService.logout();
      final loginAgain = await authService.login(username: 'pda_test', password: '12345678');
      expect(loginAgain, isTrue);
    });
  });
}
