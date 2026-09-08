import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/roles/role_registry.dart';
import 'package:uhf/models/user_models.dart';

void main() {
  group('Role Permissions & Hardware Configuration Lock Tests', () {
    test('Admin role has full hardware configuration and administrative rights', () {
      final role = AdminRole();
      expect(role.code, equals('admin'));
      expect(role.name, equals('Quản Trị Viên (Admin)'));
      expect(role.canConfigureHardware, isTrue);
      expect(role.canManageUsers, isTrue);
      expect(role.canInbound, isTrue);
      expect(role.canOutbound, isTrue);
      expect(role.canTransfer, isTrue);
      expect(role.canAudit, isTrue);
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

    test('CRITICAL SECURITY: Non-admin roles (thukho, camtay, seller) must all have canConfigureHardware == false', () {
      final roles = [
        WarehouseKeeperRole(),
        HandheldRole(),
        SellerRole(),
      ];

      for (final role in roles) {
        expect(
          role.canConfigureHardware,
          isFalse,
          reason: '${role.name} (${role.code}) must not have permission to modify machine parameters!',
        );
      }
    });

    test('RoleRegistry correctly resolves all role aliases and fallback', () {
      expect(RoleRegistry.fromCode('admin'), isA<AdminRole>());
      expect(RoleRegistry.fromCode('administrator'), isA<AdminRole>());

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

    test('RoleRegistry.allRoles contains exactly the 4 distinct system roles', () {
      final all = RoleRegistry.allRoles;
      expect(all.length, equals(4));
      expect(all.map((r) => r.code).toList(), containsAll(['admin', 'thukho', 'handheld', 'seller']));
    });

    test('WmsUser.canConfigureHardware matches role permission directly', () {
      final adminUser = WmsUser(userId: 'u1', username: 'admin', fullName: 'Admin', role: 'admin');
      final thukhoUser = WmsUser(userId: 'u2', username: 'thukho', fullName: 'Thủ kho', role: 'thukho');
      final camtayUser = WmsUser(userId: 'u3', username: 'camtay', fullName: 'Cầm tay', role: 'camtay');
      final sellerUser = WmsUser(userId: 'u4', username: 'seller', fullName: 'Seller', role: 'seller');

      expect(adminUser.canConfigureHardware, isTrue);
      expect(thukhoUser.canConfigureHardware, isFalse);
      expect(camtayUser.canConfigureHardware, isFalse);
      expect(sellerUser.canConfigureHardware, isFalse);
    });
  });
}
