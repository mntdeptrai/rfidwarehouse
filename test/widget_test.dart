import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/main.dart';
import 'package:uhf/screens/desktop/desktop_inventory_view.dart';
import 'package:uhf/screens/desktop/desktop_goods_receive_view.dart';
import 'package:uhf/screens/desktop/desktop_goods_delivery_view.dart';
import 'package:uhf/screens/desktop/desktop_lookup_view.dart';
import 'package:uhf/screens/desktop/desktop_uhf_studio_view.dart';
import 'package:uhf/screens/desktop/desktop_main_layout.dart';
import 'package:uhf/screens/storage_screen.dart';
import 'package:uhf/screens/pda/pda_home_screen.dart';
import 'package:uhf/screens/inbound_screen.dart';
import 'package:uhf/screens/desktop/desktop_warehouse_management_view.dart';
import 'package:uhf/screens/outbound_screen.dart';
import 'package:uhf/screens/pda/pda_putaway_screen.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/models/wms_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RFID WMS App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RfidWmsApp());
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.byType(RfidWmsApp), findsOneWidget);
  });

  testWidgets('DesktopInventoryView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopInventoryView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopInventoryView), findsOneWidget);
  });

  testWidgets('DesktopGoodsReceiveView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopGoodsReceiveView(isActive: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopGoodsReceiveView), findsOneWidget);
  });

  testWidgets('DesktopGoodsDeliveryView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopGoodsDeliveryView(isActive: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopGoodsDeliveryView), findsOneWidget);
  });

  testWidgets('StorageScreen renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: StorageScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(StorageScreen), findsOneWidget);
  });

  testWidgets('DesktopLookupView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopLookupView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopLookupView), findsOneWidget);
  });

  testWidgets('DesktopLookupView displays columnar table headers for SKU lookup', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final repo = WarehouseRepository();
    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final testOrderNo = 'LOOKUP-TEST-$timestamp';
    final testSku = 'SKU-LOOKUP-$timestamp';
    final order = InboundOrder(
      inboundOrderId: 'INB-$testOrderNo',
      orderNo: testOrderNo,
      sourceSupplier: 'Nhà Cung Cấp Tổng',
      status: InboundOrderStatus.newOrder,
      createdAt: DateTime.now(),
      details: [
        InboundOrderDetail(
          productId: 'PROD-LOOKUP-001',
          sku: testSku,
          productName: 'Cuộn cáp quang',
          requiredQty: 2,
        ),
      ],
    );
    await repo.addInboundOrder(order, autoGenerateEpcs: true);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopLookupView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('MÃ SKU'), findsOneWidget);
    expect(find.text('TÊN SẢN PHẨM'), findsWidgets);
    expect(find.text('NHÀ CUNG CẤP'), findsWidgets);
    expect(find.text('THÙNG / PALLET'), findsOneWidget);
    expect(find.text('TỔNG CHIP'), findsOneWidget);
    expect(find.text('TRẠNG THÁI'), findsWidgets);
    expect(find.text(testSku), findsOneWidget);
    expect(find.text('Cuộn cáp quang'), findsOneWidget);
  });

  testWidgets('DesktopUhfStudioView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopUhfStudioView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopUhfStudioView), findsOneWidget);
  });

  testWidgets('DesktopWarehouseManagementView renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DesktopWarehouseManagementView(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopWarehouseManagementView), findsOneWidget);
  });

  testWidgets('DesktopMainLayout renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: DesktopMainLayout(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(DesktopMainLayout), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('PdaHomeScreen renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: PdaHomeScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PdaHomeScreen), findsOneWidget);
  });

  testWidgets('InboundScreen renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: InboundScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(InboundScreen), findsOneWidget);
  });

  testWidgets('OutboundScreen renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: OutboundScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(OutboundScreen), findsOneWidget);
  });

  testWidgets('PdaPutawayScreen renders without overflow in ultra-narrow window', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(200, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: PdaPutawayScreen(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(PdaPutawayScreen), findsOneWidget);
  });
}

