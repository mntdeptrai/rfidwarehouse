import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/inventory_models.dart';
import 'package:uhf/models/order_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_delivery_view.dart';
import 'package:uhf/screens/pda/pda_goods_delivery_screen.dart';
import 'package:uhf/services/tower_light_service.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Auto Confirm Outbound Delivery Tests (Tự động xác nhận xuất kho sau 1s)', () {
    late WarehouseRepository repo;
    late TowerLightService towerLight;
    late UhfService uhf;

    setUp(() async {
      repo = WarehouseRepository();
      towerLight = TowerLightService();
      uhf = UhfService();
      towerLight.turnOffAll();
      await repo.clearAllData(alsoClearCloud: false);

      // Thêm 2 sản phẩm tồn kho tại kệ A-01-01
      final item1 = Item(
        itemId: 'ITEM-AUTO-01',
        productId: 'PROD-AUTO-01',
        sku: 'SKU-AUTO-01',
        serialNumber: 'SN-AUTO-01',
        productName: 'Cảm biến công nghiệp A',
        epc: 'E280116060000204DB9E0001',
        locationId: 'A-01-01',
        palletId: 'PAL-01',
        status: ItemStatus.inStock,
      );

      final item2 = Item(
        itemId: 'ITEM-AUTO-02',
        productId: 'PROD-AUTO-02',
        sku: 'SKU-AUTO-02',
        serialNumber: 'SN-AUTO-02',
        productName: 'Cảm biến công nghiệp B',
        epc: 'E280116060000204DB9E0002',
        locationId: 'A-01-01',
        palletId: 'PAL-01',
        status: ItemStatus.inStock,
      );

      repo.createOrAssignPallet(
        palletCode: 'PAL-01',
        locationId: 'A-01-01',
        newItems: [item1, item2],
      );

      // Thêm 1 đơn xuất kho mẫu
      final order = OutboundOrder(
        outboundOrderId: 'ORD-TEST-001',
        poNo: 'PO-AUTO-001',
        customer: 'Khách hàng Công Nghệ Cao',
        createdAt: DateTime.now(),
        status: OutboundOrderStatus.newOrder,
        details: [
          OutboundOrderDetail(
            productId: 'PROD-AUTO-01',
            sku: 'SKU-AUTO-01',
            productName: 'Cảm biến công nghiệp A',
            requiredQty: 1,
            pickedQty: 0,
            epcList: ['E280116060000204DB9E0001'],
          ),
          OutboundOrderDetail(
            productId: 'PROD-AUTO-02',
            sku: 'SKU-AUTO-02',
            productName: 'Cảm biến công nghiệp B',
            requiredQty: 1,
            pickedQty: 0,
            epcList: ['E280116060000204DB9E0002'],
          ),
        ],
      );

      await repo.addOutboundOrder(order);
    });

    testWidgets('Quét đủ 100% không chip lạ -> Chờ delay 1s -> Tự động xác nhận xuất kho thành công', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: DesktopGoodsDeliveryView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // 1. Mở modal chọn đơn xuất kho
      final selectOrderBtn = find.text('XUẤT HÀNG');
      expect(selectOrderBtn, findsOneWidget);
      await tester.tap(selectOrderBtn);
      await tester.pumpAndSettle();

      // Bấm nút "CHỌN TỪ ĐƠN XUẤT CÓ SẴN (CSDL)"
      final fromDbOption = find.textContaining('Chọn Đơn Xuất Có Sẵn');
      expect(fromDbOption, findsOneWidget);
      await tester.tap(fromDbOption);
      await tester.pumpAndSettle();

      // Bấm chọn đơn PO-AUTO-001
      final pickOrderBtn = find.widgetWithText(ElevatedButton, 'CHỌN');
      expect(pickOrderBtn, findsOneWidget);
      await tester.tap(pickOrderBtn);
      await tester.pumpAndSettle();

      // Kiểm tra đơn đã nạp vào view: yêu cầu 2 sản phẩm
      expect(find.textContaining('PO-AUTO-001'), findsWidgets);

      // 2. Quét sản phẩm thứ 1: 'E280116060000204DB9E0001'
      uhf.simulateTag('E280116060000204DB9E0001');
      await tester.pump(const Duration(milliseconds: 100));

      // Chưa đủ 100% -> Chưa kích hoạt tự động xuất kho
      expect(find.textContaining('ĐÃ ĐỌC ĐỦ 2/2'), findsNothing);
      expect(repo.items.where((i) => i.status == ItemStatus.out).length, equals(0));

      // 3. Quét sản phẩm thứ 2: 'E280116060000204DB9E0002' -> Đạt 100% (2/2)
      uhf.simulateTag('E280116060000204DB9E0002');
      await tester.pump(const Duration(milliseconds: 100));

      // Tháp đèn chuyển sang màu xanh (Pass)
      expect(towerLight.currentStatus.isGreen, isTrue);

      // UI hiển thị trạng thái chuẩn bị tự động xuất
      expect(find.textContaining('TỰ ĐỘNG XUẤT SAU 1S'), findsOneWidget);

      // Sau 400ms (chưa đủ 1s), hàng vẫn chưa xuất kho
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.items.where((i) => i.status == ItemStatus.out).length, equals(0));

      // Sau thêm 700ms (tổng > 1000ms), tự động xác nhận xuất kho kích hoạt!
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 100));

      // Kiểm tra: Cả 2 sản phẩm đã được tự động xuất kho thành công
      final outItems = repo.items.where((i) => i.status == ItemStatus.out).toList();
      expect(outItems.length, equals(2));
      expect(outItems.every((i) => i.locationId == null), isTrue);

      // Thông báo xuất kho thành công xuất hiện trên màn hình
      expect(find.textContaining('XUẤT THÀNH CÔNG'), findsWidgets);

      // Đợi timer banner thành công 4s kết thúc để dọn sạch timer
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('Quét đủ 100% nhưng có chip lạ xuất hiện trước 1s -> Hủy tự động xuất kho, báo động an ninh', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: DesktopGoodsDeliveryView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Mở modal chọn đơn xuất kho PO-AUTO-001
      await tester.tap(find.text('XUẤT HÀNG'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Chọn Đơn Xuất Có Sẵn'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'CHỌN'));
      await tester.pumpAndSettle();

      // Quét đủ cả 2 sản phẩm hợp lệ
      uhf.simulateTag('E280116060000204DB9E0001');
      uhf.simulateTag('E280116060000204DB9E0002');
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.textContaining('TỰ ĐỘNG XUẤT SAU 1S'), findsOneWidget);

      // Trong khi đang chờ 1s, phát hiện 1 chip lạ ngoài đơn:
      uhf.simulateTag('E280116060000204DB9ESTRANGER');
      await tester.pump(const Duration(milliseconds: 100));

      // Đèn đỏ báo động bật lên ngay lập tức
      expect(towerLight.currentStatus.isRed, isTrue);

      // Đợi timer cảnh báo đèn đỏ 3s hoàn tất
      await tester.pump(const Duration(seconds: 4));

      // Tuyệt đối KHÔNG tự động xuất kho vì có vi phạm an ninh
      expect(repo.items.where((i) => i.status == ItemStatus.out).length, equals(0));
    });

    testWidgets('PDA OutboundScreen: Quét đủ 100% không chip lạ -> Delay 1s -> Tự động xuất kho hoàn tất', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: OutboundScreen(initialOrderNo: 'PO-AUTO-001'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Quét thẻ 1
      uhf.simulateTag('E280116060000204DB9E0001');
      await tester.pump(const Duration(milliseconds: 100));
      expect(repo.items.where((i) => i.status == ItemStatus.out).length, equals(0));

      // Quét thẻ 2 -> Đạt 100%
      uhf.simulateTag('E280116060000204DB9E0002');
      await tester.pump(const Duration(milliseconds: 100));

      // Kiểm tra trạng thái tự động xuất kho sau 1s
      expect(find.textContaining('TỰ ĐỘNG XUẤT SAU 1S'), findsOneWidget);

      // Chưa đủ 1s
      await tester.pump(const Duration(milliseconds: 400));
      expect(repo.items.where((i) => i.status == ItemStatus.out).length, equals(0));

      // Đủ 1s -> Tự động chốt đơn
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 600));

      // Kiểm tra cả 2 sản phẩm đã out
      final outItems = repo.items.where((i) => i.status == ItemStatus.out).toList();
      expect(outItems.length, equals(2));
      expect(outItems.every((i) => i.locationId == null), isTrue);

      // Thông báo xuất kho thành công
      expect(find.textContaining('ĐÃ TỰ ĐỘNG XUẤT KHO THÀNH CÔNG'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
    });
  });
}
