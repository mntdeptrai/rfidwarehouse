import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/inventory_models.dart';
import 'package:uhf/models/order_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_delivery_view.dart';
import 'package:uhf/screens/pda/pda_goods_delivery_screen.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Outbound Single Order Import & Auto-Confirm Lock Tests (R1, R2, R3)', () {
    late WarehouseRepository repo;
    late UhfService uhf;

    setUp(() async {
      repo = WarehouseRepository();
      uhf = UhfService();
      await repo.clearAllData(alsoClearCloud: false);
      await repo.ensureInitialized();
      await repo.ensureDefault10Locations();

      // Thêm 2 sản phẩm tồn kho mẫu
      final item1 = Item(
        itemId: 'ITEM-TEST-001',
        productId: 'PROD-TEST-001',
        sku: 'SKU-SINGLE-01',
        productName: 'Sản phẩm thử nghiệm 1',
        serialNumber: 'SN-TEST-001',
        epc: 'E280116060000204DB9E1111',
        locationId: 'A-01-01',
        status: ItemStatus.inStock,
      );
      final item2 = Item(
        itemId: 'ITEM-TEST-002',
        productId: 'PROD-TEST-002',
        sku: 'SKU-SINGLE-02',
        productName: 'Sản phẩm thử nghiệm 2',
        serialNumber: 'SN-TEST-002',
        epc: 'E280116060000204DB9E2222',
        locationId: 'A-01-02',
        status: ItemStatus.inStock,
      );
      await repo.addItem(item1);
      await repo.addItem(item2);
    });

    testWidgets('R1 & R2: Desktop - Nạp đơn xuất kho tạo ĐÚNG 1 đơn newOrder, KHÔNG tự động nhảy sang "Đã giao" khi chưa quét chip', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Tạo sẵn 1 đơn xuất kho trong CSDL với trạng thái newOrder
      final initialOrder = OutboundOrder(
        outboundOrderId: 'OUT-TEST-DESK-01',
        poNo: 'PO-DESK-SINGLE-01',
        customer: 'Công ty ABC',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-TEST-001',
            sku: 'SKU-SINGLE-01',
            productName: 'Sản phẩm thử nghiệm 1',
            requiredQty: 1,
            pickedQty: 0,
            epcList: ['E280116060000204DB9E1111'],
          ),
        ],
      );
      await repo.addOutboundOrder(initialOrder);

      expect(repo.outboundOrders.length, equals(1));
      expect(repo.outboundOrders.first.status, equals(OutboundOrderStatus.newOrder));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: DesktopGoodsDeliveryView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Nạp đơn từ DB
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

      // Kiểm tra: Đơn đã nạp trên giao diện
      expect(find.textContaining('PO-DESK-SINGLE-01'), findsWidgets);

      // Chờ delay 2 giây khi CHƯA có chip RFID nào được quét
      await tester.pump(const Duration(seconds: 2));

      // R1: Tổng số đơn xuất kho vẫn CHÍNH XÁC là 1 đơn, không sinh đơn thứ 2
      expect(repo.outboundOrders.length, equals(1));

      // R2: Trạng thái đơn vẫn là newOrder, TUYỆT ĐỐI không tự động nhảy sang "shipped"
      expect(repo.outboundOrders.first.status, equals(OutboundOrderStatus.newOrder));
      expect(repo.outboundOrders.where((o) => o.status == OutboundOrderStatus.shipped).length, equals(0));

      // Hàng tồn kho vẫn nguyên vẹn inStock
      expect(repo.items.where((i) => i.epc == 'E280116060000204DB9E1111').first.status, equals(ItemStatus.inStock));

      // Bây giờ mới quét thực tế chip EPC qua cổng RFID
      uhf.simulateTag('E280116060000204DB9E1111');
      await tester.pump(const Duration(milliseconds: 300));

      // Quét đủ 100% -> hiển thị chuẩn bị xuất sau 1s
      expect(find.textContaining('TỰ ĐỘNG XUẤT SAU 1S'), findsOneWidget);

      // Chờ đủ 1s delay
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 200));

      // R3: Sau khi quét thực tế đủ 100%, đơn chuyển sang shipped và VẪN CHỈ CÓ DUY NHẤT 1 ĐƠN
      expect(repo.outboundOrders.length, equals(1));
      expect(repo.outboundOrders.first.status, equals(OutboundOrderStatus.shipped));
      expect(repo.items.where((i) => i.epc == 'E280116060000204DB9E1111').first.status, equals(ItemStatus.out));

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('R1 & R2: PDA - Nạp đơn xuất kho tạo ĐÚNG 1 đơn newOrder, KHÔNG tự động xuất khi chưa quét chip', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Tạo sẵn 1 đơn xuất kho trong CSDL
      final initialOrder = OutboundOrder(
        outboundOrderId: 'OUT-TEST-PDA-01',
        poNo: 'PO-PDA-SINGLE-01',
        customer: 'Khách PDA Test',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-TEST-002',
            sku: 'SKU-SINGLE-02',
            productName: 'Sản phẩm thử nghiệm 2',
            requiredQty: 1,
            pickedQty: 0,
            epcList: ['E280116060000204DB9E2222'],
          ),
        ],
      );
      await repo.addOutboundOrder(initialOrder);

      expect(repo.outboundOrders.length, equals(1));
      expect(repo.outboundOrders.first.status, equals(OutboundOrderStatus.newOrder));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: OutboundScreen(initialOrderNo: 'PO-PDA-SINGLE-01'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('PO-PDA-SINGLE-01'), findsWidgets);

      // Chờ delay 2 giây khi CHƯA có thẻ nào quét
      await tester.pump(const Duration(seconds: 2));

      // R1 & R2: Duy nhất 1 đơn, vẫn là newOrder
      expect(repo.outboundOrders.length, equals(1));
      expect(repo.outboundOrders.first.status, equals(OutboundOrderStatus.newOrder));
      expect(repo.outboundOrders.where((o) => o.status == OutboundOrderStatus.shipped).length, equals(0));
      expect(repo.items.where((i) => i.epc == 'E280116060000204DB9E2222').first.status, equals(ItemStatus.inStock));

      // Quét thẻ thực tế trên PDA
      uhf.simulateTag('E280116060000204DB9E2222');
      await tester.pump(const Duration(milliseconds: 300));

      // Tự động xuất sau 1s
      expect(find.textContaining('TỰ ĐỘNG XUẤT SAU 1S'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump(const Duration(milliseconds: 500));

      // Đã xuất kho thành công: Vẫn duy nhất 1 đơn
      expect(repo.outboundOrders.length, equals(1));
      expect(repo.outboundOrders.first.status, equals(OutboundOrderStatus.shipped));
      expect(repo.items.where((i) => i.epc == 'E280116060000204DB9E2222').first.status, equals(ItemStatus.out));

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('R3: Nạp lại cùng mã đơn PO/XK cập nhật đơn cũ thay vì nhân đôi đơn hàng', (WidgetTester tester) async {
      final order1 = OutboundOrder(
        outboundOrderId: 'OUT-DUP-01',
        poNo: 'PO-DEDUP-999',
        customer: 'Khách Hàng X',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-TEST-001',
            sku: 'SKU-SINGLE-01',
            productName: 'Sản phẩm 1',
            requiredQty: 1,
            pickedQty: 0,
            epcList: ['E280116060000204DB9E1111'],
          ),
        ],
      );
      await repo.addOutboundOrder(order1);
      expect(repo.outboundOrders.length, equals(1));

      // Nạp lại đơn cùng số PO nhưng ID khác (mô phỏng nhập lại file hoặc client khác gửi lên)
      final order2 = OutboundOrder(
        outboundOrderId: 'OUT-DUP-02',
        poNo: 'PO-DEDUP-999',
        customer: 'Khách Hàng X',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-TEST-001',
            sku: 'SKU-SINGLE-01',
            productName: 'Sản phẩm 1',
            requiredQty: 2,
            pickedQty: 0,
            epcList: ['E280116060000204DB9E1111'],
          ),
        ],
      );
      await repo.addOutboundOrder(order2);

      // Phải duy nhất 1 đơn, số lượng được cập nhật thành 2
      expect(repo.outboundOrders.length, equals(1));
      expect(repo.outboundOrders.first.poNo, equals('PO-DEDUP-999'));
      expect(repo.outboundOrders.first.details.first.requiredQty, equals(2));
      expect(repo.outboundOrders.where((o) => o.status == OutboundOrderStatus.shipped).length, equals(0));
    });
  });
}
