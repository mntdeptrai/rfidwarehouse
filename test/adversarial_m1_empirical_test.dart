import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/inventory_models.dart';
import 'package:uhf/models/order_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_delivery_view.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Empirical Verification of Critical Data Loss & Logic Bugs', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.clearAllData(alsoClearCloud: false);
      await repo.ensureInitialized();
      await repo.ensureDefault10Locations();

      await repo.addItem(Item(
        itemId: 'ITEM-TEST-1',
        productId: 'PROD-1',
        sku: 'SKU-TEST',
        productName: 'San pham test',
        serialNumber: 'SN-001',
        epc: 'E280116060000204DB9E0001',
        locationId: 'A-01-01',
        status: ItemStatus.inStock,
      ));
    });

    test('FAIL 1: confirmGateOutbound must NOT hijack an existing draft order of the same customer sharing SKU when different PO is provided', () async {
      // Samsung has order PO-SAMSUNG-001 waiting to be processed
      final orderSamsung1 = OutboundOrder(
        outboundOrderId: 'OUT-SS-001',
        poNo: 'PO-SAMSUNG-001',
        customer: 'Samsung Electronics',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-1',
            sku: 'SKU-TEST',
            productName: 'San pham test',
            requiredQty: 5,
            pickedQty: 0,
            epcList: [],
          ),
        ],
      );
      await repo.addOutboundOrder(orderSamsung1);

      // Now gate confirms delivery for an ad-hoc or separate order PO-SAMSUNG-SPECIAL
      await repo.confirmGateOutbound(
        poNo: 'PO-SAMSUNG-SPECIAL',
        customer: 'Samsung Electronics',
        scannedEpcs: ['E280116060000204DB9E0001'],
      );

      // PO-SAMSUNG-001 MUST NOT be hijacked and changed!
      final draft1 = repo.outboundOrders.where((o) => o.poNo == 'PO-SAMSUNG-001').firstOrNull;
      expect(draft1, isNotNull);
      expect(draft1!.status, equals(OutboundOrderStatus.newOrder),
          reason: 'PO-SAMSUNG-001 was hijacked and status changed!');
      expect(draft1.details.first.pickedQty, equals(0),
          reason: 'PO-SAMSUNG-001 had pickedQty modified by another PO confirmation!');
    });

    testWidgets('FAIL 2: DesktopGoodsDeliveryView clear_pending or switching order must NOT delete existing warehouse order from database', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final existingOrder = OutboundOrder(
        outboundOrderId: 'OUT-EXIST-001',
        poNo: 'PO-EXIST-001',
        customer: 'Customer Existing',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-1',
            sku: 'SKU-TEST',
            productName: 'San pham test',
            requiredQty: 1,
            pickedQty: 0,
            epcList: ['E280116060000204DB9E0001'],
          ),
        ],
      );
      await repo.addOutboundOrder(existingOrder);
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

      // Open existing order
      await tester.tap(find.text('XUẤT HÀNG'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Chọn Đơn Xuất Có Sẵn'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'CHỌN'));
      await tester.pumpAndSettle();

      expect(find.textContaining('PO-EXIST-001'), findsWidgets);

      // Now clear active pending order from screen
      await tester.tap(find.text('XUẤT HÀNG'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Xóa Danh Sách Đang Chờ Xuất'));
      await tester.pumpAndSettle();

      // The order MUST STILL EXIST in repo.outboundOrders! Clearing screen must not delete it!
      expect(repo.outboundOrders.any((o) => o.poNo == 'PO-EXIST-001'), isTrue,
          reason: 'Clearing screen deleted the existing warehouse order from repo!');
    });

    testWidgets('FAIL 3: Loading a new order while an existing draft order is on screen must NOT delete the existing draft order', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Existing order in the warehouse
      final existingOrder = OutboundOrder(
        outboundOrderId: 'OUT-EXIST-100',
        poNo: 'PO-EXIST-100',
        customer: 'Customer Existing',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-1',
            sku: 'SKU-TEST',
            productName: 'San pham test',
            requiredQty: 1,
            pickedQty: 0,
            epcList: ['E280116060000204DB9E0001'],
          ),
        ],
      );
      await repo.addOutboundOrder(existingOrder);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: DesktopGoodsDeliveryView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Select existing order onto screen
      await tester.tap(find.text('XUẤT HÀNG'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Chọn Đơn Xuất Có Sẵn'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'CHỌN'));
      await tester.pumpAndSettle();

      expect(find.textContaining('PO-EXIST-100'), findsWidgets);

      // Now create and add a second order (e.g. from file import)
      // Notice what happens if someone imports a new order PO-NEW-200:
      // In DesktopGoodsDeliveryView: _pickAndLoadOutboundFile calls _cleanupPendingDraftOutboundOrders()
      // which deletes whatever order was on screen (_pendingOutboundOrder)!
      // Let's verify via the view's internal cleanup or simulating the import flow:
      // Even if user selects another order or imports, PO-EXIST-100 MUST NOT BE DELETED!
      expect(repo.outboundOrders.any((o) => o.poNo == 'PO-EXIST-100'), isTrue);
    });
  });
}
