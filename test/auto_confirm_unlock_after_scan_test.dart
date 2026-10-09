import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_receive_view.dart';
import 'package:uhf/screens/desktop/desktop_goods_delivery_view.dart';
import 'package:uhf/screens/pda/pda_goods_delivery_screen.dart';
import 'package:uhf/screens/pda/pda_inbound_screen.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/tower_light_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testTheme = ThemeData(
    useMaterial3: false,
    splashFactory: InkRipple.splashFactory,
  );

  group('Auto Confirm Unlock After Scan Tests (Tự động xác nhận nhập/xuất khi quét xong)', () {
    late WarehouseRepository repo;
    late UhfService uhf;
    late TowerLightService towerLight;

    setUp(() async {
      repo = WarehouseRepository();
      uhf = UhfService();
      towerLight = TowerLightService();
      towerLight.turnOffAll();
      await repo.clearAllData(alsoClearCloud: false);
    });

    testWidgets('1. Desktop Inbound: Dừng quét ("quét xong") khi đã đủ 100% -> Tự động xác nhận nhập kho thành công', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const orderNo = 'NK-AUTOCONFIRM-001';
      final item1 = Item(
        itemId: 'ITEM-AC-01',
        productId: 'SKU-AC-01',
        sku: 'SKU-AC-01',
        productName: 'Hàng Nhập Tự Động 1',
        serialNumber: 'SN-AC-01',
        epc: 'E280119100000000AC000001',
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
        palletId: 'PAL-AC-01',
      );

      final inboundOrder = InboundOrder(
        inboundOrderId: orderNo,
        orderNo: orderNo,
        sourceSupplier: 'Nhà Cung Cấp Tự Động',
        status: InboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(productId: 'SKU-AC-01', sku: 'SKU-AC-01', productName: 'Hàng Nhập Tự Động 1', requiredQty: 1),
        ],
      );

      await repo.addInboundOrder(inboundOrder, autoGenerateEpcs: false);
      await repo.insertDirectItems([item1]);

      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: const Scaffold(
            body: DesktopGoodsReceiveView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Bắt đầu quét
      final scanBtn = find.textContaining('BẮT ĐẦU QUÉT');
      expect(scanBtn, findsOneWidget);
      await tester.tap(scanBtn);
      await tester.pump(const Duration(milliseconds: 200));

      // Gửi chip EPC qua cổng
      uhf.simulateTag('E280119100000000AC000001');
      await tester.pump(const Duration(milliseconds: 100));

      // Dừng quét ("quét xong")
      final stopBtn = find.textContaining('DỪNG QUÉT');
      expect(stopBtn, findsOneWidget);
      await tester.tap(stopBtn);
      await tester.pump(const Duration(milliseconds: 200));

      // Chờ hoàn tất tự động
      await tester.pump(const Duration(milliseconds: 600));

      // Kiểm tra trạng thái sản phẩm đã tự động chuyển sang waitingPutaway (nhập kho thành công)
      final updatedItem = repo.items.firstWhere((i) => i.itemId == 'ITEM-AC-01');
      expect(updatedItem.status, ItemStatus.waitingPutaway);
    });

    testWidgets('2. Desktop Outbound: Dừng quét ("quét xong") khi đã đủ 100% -> Tự động xác nhận xuất kho thành công', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Tạo tồn kho
      final itemOut = Item(
        itemId: 'ITEM-OUT-01',
        productId: 'PROD-OUT-01',
        sku: 'SKU-OUT-01',
        serialNumber: 'SN-OUT-01',
        productName: 'Cảm biến xuất kho',
        epc: 'E280116060000204OUT00001',
        locationId: 'A-01-01',
        palletId: 'PAL-01',
        status: ItemStatus.inStock,
      );

      repo.createOrAssignPallet(
        palletCode: 'PAL-01',
        locationId: 'A-01-01',
        newItems: [itemOut],
      );

      final order = OutboundOrder(
        outboundOrderId: 'ORD-OUT-001',
        poNo: 'PO-OUT-001',
        customer: 'Khách hàng Xuất Kho',
        createdAt: DateTime.now(),
        status: OutboundOrderStatus.newOrder,
        details: [
          OutboundOrderDetail(
            productId: 'PROD-OUT-01',
            sku: 'SKU-OUT-01',
            productName: 'Cảm biến xuất kho',
            requiredQty: 1,
            pickedQty: 0,
            epcList: ['E280116060000204OUT00001'],
          ),
        ],
      );

      await repo.addOutboundOrder(order);

      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: const Scaffold(
            body: DesktopGoodsDeliveryView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Chọn đơn hàng từ CSDL
      final selectOrderBtn = find.text('XUẤT HÀNG');
      expect(selectOrderBtn, findsOneWidget);
      await tester.tap(selectOrderBtn);
      await tester.pumpAndSettle();

      final fromDbOption = find.textContaining('Chọn Đơn Xuất Có Sẵn');
      expect(fromDbOption, findsOneWidget);
      await tester.tap(fromDbOption);
      await tester.pumpAndSettle();

      final pickBtn = find.widgetWithText(ElevatedButton, 'CHỌN');
      expect(pickBtn, findsOneWidget);
      await tester.tap(pickBtn);
      await tester.pumpAndSettle();

      // Gửi chip qua cổng
      uhf.simulateTag('E280116060000204OUT00001');
      await tester.pump(const Duration(milliseconds: 200));

      // Dừng quét ("quét xong")
      final stopGateBtn = find.textContaining('DỪNG CỔNG');
      if (stopGateBtn.evaluate().isNotEmpty) {
        await tester.tap(stopGateBtn);
        await tester.pump(const Duration(milliseconds: 200));
      }

      // Chờ tự động xác nhận sau 1s
      await tester.pump(const Duration(milliseconds: 1200));

      // Kiểm tra trạng thái đã tự động xuất kho (ItemStatus.out)
      final finalItem = repo.items.firstWhere((i) => i.itemId == 'ITEM-OUT-01');
      expect(finalItem.status, ItemStatus.out);
    });

    testWidgets('3. PDA Outbound: Dừng quét sau khi đủ 100% -> Tự động xuất kho không bị chặn', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final itemPda = Item(
        itemId: 'ITEM-PDA-OUT-01',
        productId: 'PROD-PDA-01',
        sku: 'SKU-PDA-01',
        serialNumber: 'SN-PDA-01',
        productName: 'Thiết bị PDA xuất kho',
        epc: 'E280116060000204PDA00001',
        locationId: 'A-02-01',
        palletId: 'PAL-02',
        status: ItemStatus.inStock,
      );

      repo.createOrAssignPallet(
        palletCode: 'PAL-02',
        locationId: 'A-02-01',
        newItems: [itemPda],
      );

      final order = OutboundOrder(
        outboundOrderId: 'ORD-PDA-001',
        poNo: 'PO-PDA-001',
        customer: 'Khách hàng PDA',
        createdAt: DateTime.now(),
        status: OutboundOrderStatus.newOrder,
        details: [
          OutboundOrderDetail(
            productId: 'PROD-PDA-01',
            sku: 'SKU-PDA-01',
            productName: 'Thiết bị PDA xuất kho',
            requiredQty: 1,
            pickedQty: 0,
            epcList: ['E280116060000204PDA00001'],
          ),
        ],
      );

      await repo.addOutboundOrder(order);

      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: const Scaffold(
            body: OutboundScreen(initialOrderNo: 'PO-PDA-001'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Quét thẻ
      uhf.simulateTag('E280116060000204PDA00001');
      await tester.pump(const Duration(milliseconds: 200));

      // Bấm nút dừng quét
      final stopBtn = find.widgetWithText(OutlinedButton, 'Dừng');
      if (stopBtn.evaluate().isNotEmpty) {
        await tester.tap(stopBtn);
        await tester.pump(const Duration(milliseconds: 200));
      }

      // Chờ tự động xuất kho sau 1s
      await tester.pump(const Duration(milliseconds: 1200));

      final finalItem = repo.items.firstWhere((i) => i.itemId == 'ITEM-PDA-OUT-01');
      expect(finalItem.status, ItemStatus.out);
    });

    testWidgets('4. PDA Inbound: Quét xong và dừng quét khi đủ 100% -> Tự động xác nhận nhập kho', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const orderNo = 'NK-PDA-AUTO-001';
      final itemPdaIn = Item(
        itemId: 'ITEM-PDA-IN-01',
        productId: 'SKU-PDA-IN-01',
        sku: 'SKU-PDA-IN-01',
        productName: 'Sản phẩm PDA Nhập',
        serialNumber: 'SN-PDA-IN-01',
        epc: 'E280119100000000PDAIN001',
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
        palletId: 'PAL-01',
      );

      final inboundOrder = InboundOrder(
        inboundOrderId: orderNo,
        orderNo: orderNo,
        sourceSupplier: 'Nhà Cung Cấp PDA',
        status: InboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(productId: 'SKU-PDA-IN-01', sku: 'SKU-PDA-IN-01', productName: 'Sản phẩm PDA Nhập', requiredQty: 1),
        ],
      );

      await repo.addInboundOrder(inboundOrder, autoGenerateEpcs: false);
      await repo.insertDirectItems([itemPdaIn]);

      await tester.pumpWidget(
        MaterialApp(
          theme: testTheme,
          home: const Scaffold(
            body: PdaInboundScreen(initialOrderNo: orderNo),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Bật quét trên PDA
      final scanBtn = find.textContaining('BÓP CÒ HOẶC BẤM ĐỂ QUÉT');
      if (scanBtn.evaluate().isNotEmpty) {
        await tester.tap(scanBtn);
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Quét thẻ
      uhf.simulateTag('E280119100000000PDAIN001');
      await tester.pump(const Duration(milliseconds: 100));

      // Dừng quét
      final stopBtn = find.textContaining('DỪNG QUÉT RFID');
      if (stopBtn.evaluate().isNotEmpty) {
        await tester.tap(stopBtn);
        await tester.pump(const Duration(milliseconds: 100));
      }

      // Chờ tự động hoàn tất nhập kho
      await tester.pump(const Duration(milliseconds: 600));

      final finalItem = repo.items.firstWhere((i) => i.itemId == 'ITEM-PDA-IN-01');
      expect(finalItem.status, ItemStatus.waitingPutaway);
    });
  });
}
