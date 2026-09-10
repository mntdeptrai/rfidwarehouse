import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
import 'package:uhf/screens/outbound_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

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
}

