import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/inventory_models.dart';
import 'package:uhf/models/order_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_delivery_view.dart';
import 'package:uhf/services/database_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Reviewer R2 Adversarial Break Tests', () {
    late WarehouseRepository repo;
    late DatabaseService dbService;

    setUp(() async {
      repo = WarehouseRepository();
      dbService = DatabaseService();
      await repo.clearAllData(alsoClearCloud: false);
      await repo.ensureInitialized();
      await repo.ensureDefault10Locations();

      // Add in-stock items
      for (int i = 1; i <= 5; i++) {
        await repo.addItem(Item(
          itemId: 'ITEM-TEST-00$i',
          productId: 'PROD-TEST-001',
          sku: 'SKU-TEST',
          productName: 'Sản phẩm Test',
          serialNumber: 'SN-TEST-00$i',
          epc: 'E280116060000204DB9E000$i',
          locationId: 'A-01-01',
          status: ItemStatus.inStock,
        ));
      }
    });

    test('DEFECT 3: confirmGateOutbound must NOT hijack existing draft order matching same customer and SKU when a distinct poNo is passed', () async {
      final order1 = OutboundOrder(
        outboundOrderId: 'OUT-DRAFT-101',
        poNo: 'PO-DRAFT-101',
        customer: 'Khách VIP',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-TEST-001',
            sku: 'SKU-TEST',
            productName: 'Sản phẩm Test',
            requiredQty: 5,
            pickedQty: 0,
            epcList: ['E280116060000204DB9E0001'],
          ),
        ],
      );
      await repo.addOutboundOrder(order1);
      expect(repo.outboundOrders.length, equals(1));

      // Thực hiện xuất kho cho một đơn hàng mới khác tại cổng (XK-GATE-NEW) của cùng khách hàng Khách VIP
      final count = await repo.confirmGateOutbound(
        poNo: 'XK-GATE-NEW',
        customer: 'Khách VIP',
        scannedEpcs: ['E280116060000204DB9E0001'],
      );
      expect(count, equals(1));

      // Đơn PO-DRAFT-101 PHẢI VẪN CÒN NGUYÊN là newOrder với pickedQty == 0!
      final originalDraft = repo.outboundOrders.where((o) => o.poNo == 'PO-DRAFT-101').firstOrNull;
      expect(originalDraft, isNotNull, reason: 'Đơn PO-DRAFT-101 không được bị thay đổi hoặc biến mất!');
      expect(originalDraft!.status, equals(OutboundOrderStatus.newOrder), reason: 'Đơn PO-DRAFT-101 phải giữ nguyên newOrder');
      expect(originalDraft.details.first.pickedQty, equals(0), reason: 'Đơn PO-DRAFT-101 không được bị tăng pickedQty');

      // Và đơn XK-GATE-NEW phải được tạo mới với status shipped!
      final newGateOrder = repo.outboundOrders.where((o) => o.poNo == 'XK-GATE-NEW').firstOrNull;
      expect(newGateOrder, isNotNull, reason: 'Đơn XK-GATE-NEW phải được tạo mới!');
      expect(newGateOrder!.status, equals(OutboundOrderStatus.shipped));
    });

    testWidgets('DEFECT 4: Desktop clear_pending ("Xóa Danh Sách Đang Chờ Xuất") must NOT delete order from repository or database', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final order = OutboundOrder(
        outboundOrderId: 'OUT-KEEP-01',
        poNo: 'PO-KEEP-01',
        customer: 'Khách Lưu Trữ',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-TEST-001',
            sku: 'SKU-TEST',
            productName: 'Sản phẩm Test',
            requiredQty: 2,
            pickedQty: 0,
            epcList: [],
          ),
        ],
      );
      await repo.addOutboundOrder(order);
      expect(repo.outboundOrders.length, equals(1));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: DesktopGoodsDeliveryView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Chọn đơn từ DB
      await tester.tap(find.text('XUẤT HÀNG'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Chọn Đơn Xuất Có Sẵn'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'CHỌN'));
      await tester.pumpAndSettle();

      expect(find.textContaining('PO-KEEP-01'), findsWidgets);

      // Bây giờ người dùng mở menu XUẤT HÀNG và bấm "Xóa Danh Sách Đang Chờ Xuất" (clear_pending)
      await tester.tap(find.text('XUẤT HÀNG'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Xóa Danh Sách Đang Chờ Xuất'));
      await tester.pumpAndSettle();

      // Đơn hàng trên giao diện đã xóa chờ đối soát cổng (không còn thanh tiến độ đối soát)
      expect(find.textContaining('TIẾN ĐỘ ĐỐI SOÁT QUA CỔNG'), findsNothing);
      expect(find.textContaining('DANH SÁCH ĐƠN XUẤT CHỜ QUÉT'), findsOneWidget);

      // NHƯNG TRONG REPOSITORY VÀ DATABASE ĐƠN HÀNG PHẢI CÒN NGUYÊN VẸN!
      expect(repo.outboundOrders.length, equals(1), reason: 'Đơn hàng không được bị xóa khỏi repository khi chỉ clear màn hình!');
      expect(repo.outboundOrders.first.poNo, equals('PO-KEEP-01'));
      final dbOrders = await dbService.getOutboundOrders();
      expect(dbOrders.length, equals(1), reason: 'Đơn hàng không được bị xóa khỏi database khi chỉ clear màn hình!');
      expect(dbOrders.first.poNo, equals('PO-KEEP-01'));
    });
  });
}
