import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/roles/role_registry.dart';
import 'package:uhf/models/user_models.dart';

void main() {
  group('Role Permissions & Hardware Configuration Lock Tests', () {
    test('Admin role has administrative user management rights but NOT hardware configuration', () {
      final role = AdminRole();
      expect(role.code, equals('admin'));
      expect(role.name, equals('Quản Trị Viên (Admin)'));
      // Machine parameter screens now belong to Technician (Kỹ thuật)
      expect(role.canConfigureHardware, isFalse);
      expect(role.canManageUsers, isTrue); // Admin provisions & manages accounts
      expect(role.canInbound, isTrue);
      expect(role.canOutbound, isTrue);
      expect(role.canTransfer, isTrue);
      expect(role.canAudit, isTrue);
      expect(role.canViewReports, isTrue);
    });

    test('Technician (Kỹ thuật) role has full hardware configuration rights', () {
      final role = TechnicianRole();
      expect(role.code, equals('kythuat'));
      expect(role.name, contains('Kỹ Thuật'));
      // Hardware configuration permission granted to Technician
      expect(role.canConfigureHardware, isTrue);
      expect(role.canManageUsers, isFalse);
      expect(role.canInbound, isTrue);
      expect(role.canOutbound, isTrue);
      expect(role.canTransfer, isTrue);
      expect(role.canAudit, isTrue);
      expect(role.canLookup, isTrue);
      expect(role.canViewReports, isTrue);
    });

    test('Thủ kho (Warehouse Keeper) CANNOT configure hardware parameters', () {
      final role = WarehouseKeeperRole();
      expect(role.code, equals('thukho'));
      expect(role.name, equals('Thủ Kho (Warehouse Keeper)'));
      // Machine parameter lock constraint
      expect(role.canConfigureHardware, isFalse);
      expect(role.canManageUsers, isFalse);
      // Warehouse operations permitted
      expect(role.canInbound, isTrue);
      expect(role.canOutbound, isTrue);
      expect(role.canTransfer, isTrue);
      expect(role.canAudit, isTrue);
      expect(role.canViewReports, isTrue);
    });

    test('Máy cầm tay (Handheld PDA) CANNOT configure hardware parameters', () {
      final role = HandheldRole();
      expect(role.code, equals('handheld'));
      expect(role.name, equals('Máy Cầm Tay (Handheld PDA)'));
      // Machine parameter lock constraint
      expect(role.canConfigureHardware, isFalse);
      expect(role.canManageUsers, isFalse);
      // Operational actions permitted
      expect(role.canInbound, isTrue);
      expect(role.canOutbound, isTrue);
      expect(role.canTransfer, isTrue);
      expect(role.canAudit, isTrue);
      expect(role.canViewReports, isTrue);
    });

    test('Seller (Bán hàng) CANNOT configure hardware parameters and has restricted access', () {
      final role = SellerRole();
      expect(role.code, equals('seller'));
      expect(role.name, equals('Người Bán Hàng (Seller)'));
      // Machine parameter lock constraint
      expect(role.canConfigureHardware, isFalse);
      expect(role.canManageUsers, isFalse);
      // Outbound allowed, inbound/transfer/audit forbidden
      expect(role.canInbound, isFalse);
      expect(role.canOutbound, isTrue);
      expect(role.canTransfer, isFalse);
      expect(role.canAudit, isFalse);
      expect(role.canViewReports, isTrue);
    });

    test('CRITICAL SECURITY: Only Technician role has canConfigureHardware == true; others must be false', () {
      final nonTechRoles = [
        AdminRole(),
        WarehouseKeeperRole(),
        HandheldRole(),
        SellerRole(),
      ];

      for (final role in nonTechRoles) {
        expect(
          role.canConfigureHardware,
          isFalse,
          reason: '${role.name} (${role.code}) must not have permission to modify machine parameters!',
        );
      }

      expect(TechnicianRole().canConfigureHardware, isTrue);
    });

    test('RoleRegistry correctly resolves all role aliases and fallback', () {
      expect(RoleRegistry.fromCode('admin'), isA<AdminRole>());
      expect(RoleRegistry.fromCode('administrator'), isA<AdminRole>());

      expect(RoleRegistry.fromCode('kythuat'), isA<TechnicianRole>());
      expect(RoleRegistry.fromCode('technician'), isA<TechnicianRole>());
      expect(RoleRegistry.fromCode('tech'), isA<TechnicianRole>());
      expect(RoleRegistry.fromCode('it'), isA<TechnicianRole>());

      expect(RoleRegistry.fromCode('thukho'), isA<WarehouseKeeperRole>());
      expect(RoleRegistry.fromCode('operator'), isA<WarehouseKeeperRole>());
      expect(RoleRegistry.fromCode('kho'), isA<WarehouseKeeperRole>());

      expect(RoleRegistry.fromCode('camtay'), isA<HandheldRole>());
      expect(RoleRegistry.fromCode('handheld'), isA<HandheldRole>());
      expect(RoleRegistry.fromCode('pda'), isA<HandheldRole>());

      expect(RoleRegistry.fromCode('seller'), isA<SellerRole>());
      expect(RoleRegistry.fromCode('banhang'), isA<SellerRole>());
      expect(RoleRegistry.fromCode('sales'), isA<SellerRole>());

      // Unknown fallback should default safely to WarehouseKeeperRole (canConfigureHardware == false)
      final fallback = RoleRegistry.fromCode('unknown_code');
      expect(fallback, isA<WarehouseKeeperRole>());
      expect(fallback.canConfigureHardware, isFalse);
    });

    test('RoleRegistry.allRoles contains exactly the 5 distinct system roles', () {
      final all = RoleRegistry.allRoles;
      expect(all.length, equals(5));
      expect(all.map((r) => r.code).toList(), containsAll(['admin', 'kythuat', 'thukho', 'handheld', 'seller']));
    });

    test('WmsUser.canConfigureHardware matches role permission directly', () {
      final adminUser = WmsUser(userId: 'u1', username: 'admin', fullName: 'Admin', role: 'admin');
      final techUser = WmsUser(userId: 'u2', username: 'kythuat', fullName: 'Kỹ thuật', role: 'kythuat');
      final thukhoUser = WmsUser(userId: 'u3', username: 'thukho', fullName: 'Thủ kho', role: 'thukho');
      final camtayUser = WmsUser(userId: 'u4', username: 'camtay', fullName: 'Cầm tay', role: 'camtay');
      final sellerUser = WmsUser(userId: 'u5', username: 'seller', fullName: 'Seller', role: 'seller');

      expect(adminUser.canConfigureHardware, isFalse);
      expect(techUser.canConfigureHardware, isTrue);
      expect(thukhoUser.canConfigureHardware, isFalse);
      expect(camtayUser.canConfigureHardware, isFalse);
      expect(sellerUser.canConfigureHardware, isFalse);
    });

    test('isTechnician is strictly true ONLY for TechnicianRole and false for all other roles', () {
      expect(TechnicianRole().isTechnician, isTrue);
      expect(AdminRole().isTechnician, isFalse);
      expect(WarehouseKeeperRole().isTechnician, isFalse);
      expect(HandheldRole().isTechnician, isFalse);
      expect(SellerRole().isTechnician, isFalse);

      final adminUser = WmsUser(userId: 'u1', username: 'admin', fullName: 'Admin', role: 'admin');
      final techUser = WmsUser(userId: 'u2', username: 'kythuat', fullName: 'Kỹ thuật', role: 'kythuat');
      final thukhoUser = WmsUser(userId: 'u3', username: 'thukho', fullName: 'Thủ kho', role: 'thukho');

      expect(techUser.isTechnician, isTrue);
      expect(adminUser.isTechnician, isFalse);
      expect(thukhoUser.isTechnician, isFalse);
    });
  });
}
