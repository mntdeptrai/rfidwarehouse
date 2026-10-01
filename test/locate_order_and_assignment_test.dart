import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/inventory_models.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocateOrder & LocateOrderStatus Model Tests', () {
    test('LocateOrderStatus properties and code mapping', () {
      expect(LocateOrderStatus.pending.code, 'PENDING');
      expect(LocateOrderStatus.inProgress.code, 'IN_PROGRESS');
      expect(LocateOrderStatus.completed.code, 'COMPLETED');
      expect(LocateOrderStatus.cancelled.code, 'CANCELLED');

      expect(LocateOrderStatus.fromCode('PENDING'), LocateOrderStatus.pending);
      expect(LocateOrderStatus.fromCode('pending'), LocateOrderStatus.pending);
      expect(LocateOrderStatus.fromCode('IN_PROGRESS'), LocateOrderStatus.inProgress);
      expect(LocateOrderStatus.fromCode('in_progress'), LocateOrderStatus.inProgress);
      expect(LocateOrderStatus.fromCode('COMPLETED'), LocateOrderStatus.completed);
      expect(LocateOrderStatus.fromCode('CANCELLED'), LocateOrderStatus.cancelled);
      expect(LocateOrderStatus.fromCode('UNKNOWN'), LocateOrderStatus.pending);
      expect(LocateOrderStatus.fromCode(null), LocateOrderStatus.pending);
    });

    test('LocateOrder toMap and fromMap serialization', () {
      final now = DateTime(2026, 10, 1, 10, 30);
      final completedTime = DateTime(2026, 10, 1, 11, 0);

      final order = LocateOrder(
        orderId: 'LOC-TEST-001',
        orderNo: 'TK-261001-123',
        title: 'Tìm kiếm chip khẩn cấp',
        targetEpc: 'E28011912000001',
        targetSku: 'SKU-SAMPLE-01',
        targetProductName: 'Tai nghe Bluetooth Pro',
        targetPalletCode: 'PALLET-A1',
        expectedLocation: 'Kệ A1-02',
        status: LocateOrderStatus.completed,
        assignedToUserId: 'user-pda-01',
        assignedToName: 'Nguyễn Văn PDA',
        createdBy: 'Admin Thủ Kho',
        createdAt: now,
        completedAt: completedTime,
        completedBy: 'Nguyễn Văn PDA',
        foundLocation: 'Kệ B2-01',
        notes: 'Hàng nằm lẫn ở dãy B2',
      );

      final map = order.toMap();
      expect(map['order_id'], 'LOC-TEST-001');
      expect(map['order_no'], 'TK-261001-123');
      expect(map['status'], 'COMPLETED');
      expect(map['assigned_to_user_id'], 'user-pda-01');
      expect(map['assigned_to_name'], 'Nguyễn Văn PDA');
      expect(map['found_location'], 'Kệ B2-01');

      final deserialized = LocateOrder.fromMap(map);
      expect(deserialized.orderId, order.orderId);
      expect(deserialized.orderNo, order.orderNo);
      expect(deserialized.title, order.title);
      expect(deserialized.targetEpc, order.targetEpc);
      expect(deserialized.targetSku, order.targetSku);
      expect(deserialized.targetProductName, order.targetProductName);
      expect(deserialized.targetPalletCode, order.targetPalletCode);
      expect(deserialized.expectedLocation, order.expectedLocation);
      expect(deserialized.status, LocateOrderStatus.completed);
      expect(deserialized.assignedToUserId, 'user-pda-01');
      expect(deserialized.assignedToName, 'Nguyễn Văn PDA');
      expect(deserialized.foundLocation, 'Kệ B2-01');
      expect(deserialized.notes, 'Hàng nằm lẫn ở dãy B2');
    });

    test('LocateOrder targetDisplay priority logic', () {
      final orderWithName = LocateOrder(
        orderId: '1',
        orderNo: 'TK-1',
        title: 'Đơn tìm kiếm chung',
        targetProductName: 'Bàn phím cơ Không Dây',
        targetSku: 'SKU-001',
        targetEpc: 'EPC-001',
        assignedToUserId: 'u1',
        assignedToName: 'User 1',
        createdBy: 'Admin',
        createdAt: DateTime.now(),
      );
      expect(orderWithName.targetDisplay, 'Bàn phím cơ Không Dây');

      final orderWithSku = LocateOrder(
        orderId: '2',
        orderNo: 'TK-2',
        title: 'Đơn tìm kiếm chung',
        targetSku: 'SKU-999',
        targetEpc: 'EPC-001',
        assignedToUserId: 'u1',
        assignedToName: 'User 1',
        createdBy: 'Admin',
        createdAt: DateTime.now(),
      );
      expect(orderWithSku.targetDisplay, 'SKU: SKU-999');

      final orderWithPallet = LocateOrder(
        orderId: '3',
        orderNo: 'TK-3',
        title: 'Đơn tìm kiếm chung',
        targetPalletCode: 'PALLET-X',
        assignedToUserId: 'u1',
        assignedToName: 'User 1',
        createdBy: 'Admin',
        createdAt: DateTime.now(),
      );
      expect(orderWithPallet.targetDisplay, 'Pallet: PALLET-X');

      final orderWithEpc = LocateOrder(
        orderId: '4',
        orderNo: 'TK-4',
        title: 'Đơn tìm kiếm chung',
        targetEpc: 'E280112233',
        assignedToUserId: 'u1',
        assignedToName: 'User 1',
        createdBy: 'Admin',
        createdAt: DateTime.now(),
      );
      expect(orderWithEpc.targetDisplay, 'EPC: E280112233');

      final orderDefault = LocateOrder(
        orderId: '5',
        orderNo: 'TK-5',
        title: 'Đơn tìm kiếm chung',
        assignedToUserId: 'u1',
        assignedToName: 'User 1',
        createdBy: 'Admin',
        createdAt: DateTime.now(),
      );
      expect(orderDefault.targetDisplay, 'Đơn tìm kiếm chung');
    });
  });

  group('InventorySession Handheld Assignee Tests', () {
    test('InventorySession preserves assignedTo fields', () {
      final session = InventorySession(
        sessionId: 'SES-TEST-001',
        sessionCode: 'KK-20261001-01',
        startedAt: DateTime(2026, 10, 1, 8, 0),
        zone: 'Zone A',
        assignedToUserId: 'user-handheld-10',
        assignedToName: 'Trần Văn Cầm Tay',
        assignedBy: 'Trưởng Ca Kiểm Kê',
        notes: 'Kiểm kê đột xuất khu A',
      );

      expect(session.assignedToUserId, 'user-handheld-10');
      expect(session.assignedToName, 'Trần Văn Cầm Tay');
      expect(session.assignedBy, 'Trưởng Ca Kiểm Kê');
      expect(session.notes, 'Kiểm kê đột xuất khu A');
      expect(session.assignedToDisplay, 'Trần Văn Cầm Tay');
    });

    test('InventorySession assignedToDisplay fallback when unassigned', () {
      final unassigned = InventorySession(
        sessionId: 'SES-TEST-002',
        sessionCode: 'KK-20261001-02',
        startedAt: DateTime(2026, 10, 1, 9, 0),
        zone: 'Toàn kho',
      );
      expect(unassigned.assignedToDisplay, 'Chưa chỉ định');
    });
  });

  group('WarehouseRepository LocateOrder Operations Tests', () {
    late WarehouseRepository repo;

    setUp(() {
      repo = WarehouseRepository();
    });

    test('createLocateOrder generates valid order and adds to repo list', () async {
      final initialCount = repo.locateOrders.length;

      final order = await repo.createLocateOrder(
        title: 'Tìm chip tai nghe Bluetooth',
        targetEpc: 'E28068940000000000000001',
        targetSku: 'SKU-HEADPHONE-01',
        targetProductName: 'Tai Nghe Bluetooth X',
        targetPalletCode: 'PL-01',
        expectedLocation: 'A1-01',
        assignedToUserId: 'handheld-emp-01',
        assignedToName: 'Lê Văn Handheld',
        notes: 'Cần tìm trước 12h trưa',
      );

      expect(order.orderId.isNotEmpty, true);
      expect(order.orderNo.startsWith('TK-'), true);
      expect(order.status, LocateOrderStatus.pending);
      expect(order.assignedToUserId, 'handheld-emp-01');
      expect(order.assignedToName, 'Lê Văn Handheld');
      expect(repo.locateOrders.length, initialCount + 1);
      expect(repo.locateOrders.first.orderId, order.orderId);
    });

    test('updateLocateOrderStatus changes status to inProgress', () async {
      final order = await repo.createLocateOrder(
        title: 'Tìm đơn test status',
        assignedToUserId: 'handheld-emp-02',
        assignedToName: 'Hoàng Handheld',
      );
      expect(order.status, LocateOrderStatus.pending);

      await repo.updateLocateOrderStatus(order.orderId, LocateOrderStatus.inProgress);
      expect(order.status, LocateOrderStatus.inProgress);
    });

    test('completeLocateOrder updates status, foundLocation, and completedBy', () async {
      final order = await repo.createLocateOrder(
        title: 'Tìm đơn hoàn thành',
        targetEpc: 'E280111222',
        assignedToUserId: 'handheld-emp-03',
        assignedToName: 'Đặng Handheld',
      );

      await repo.completeLocateOrder(
        order.orderId,
        foundLocation: 'Kệ B1-03',
        completedBy: 'Đặng Handheld',
      );

      expect(order.status, LocateOrderStatus.completed);
      expect(order.foundLocation, 'Kệ B1-03');
      expect(order.completedBy, 'Đặng Handheld');
      expect(order.completedAt != null, true);
    });

    test('cancelLocateOrder sets status to cancelled', () async {
      final order = await repo.createLocateOrder(
        title: 'Tìm đơn hủy',
        assignedToUserId: 'handheld-emp-04',
        assignedToName: 'Phạm Handheld',
      );

      await repo.cancelLocateOrder(order.orderId);
      expect(order.status, LocateOrderStatus.cancelled);
    });

    test('deleteLocateOrder removes order from repo', () async {
      final order = await repo.createLocateOrder(
        title: 'Tìm đơn cần xóa',
        assignedToUserId: 'handheld-emp-05',
        assignedToName: 'Vũ Handheld',
      );
      expect(repo.locateOrders.any((o) => o.orderId == order.orderId), true);

      await repo.deleteLocateOrder(order.orderId);
      expect(repo.locateOrders.any((o) => o.orderId == order.orderId), false);
    });

    test('startInventorySession preserves assigned staff info', () {
      final session = repo.startInventorySession(
        zone: 'Zone B',
        locationCode: 'LOC-B1',
        assignedToUserId: 'user-hh-99',
        assignedToName: 'Võ Handheld PDA',
        assignedBy: 'Quản Lý Kho',
        notes: 'Kiểm kê định kỳ tháng 10',
      );

      expect(session.assignedToUserId, 'user-hh-99');
      expect(session.assignedToName, 'Võ Handheld PDA');
      expect(session.assignedBy, 'Quản Lý Kho');
      expect(session.notes, 'Kiểm kê định kỳ tháng 10');
      expect(session.assignedToDisplay, 'Võ Handheld PDA');
    });
  });
}
