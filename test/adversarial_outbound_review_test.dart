import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/inventory_models.dart';
import 'package:uhf/models/order_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_delivery_view.dart';
import 'package:uhf/screens/pda/pda_goods_delivery_screen.dart';
import 'package:uhf/services/database_service.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Adversarial Review Tests: Breaking Prior Attempt Flaws & Verifying Edge Cases', () {
    late WarehouseRepository repo;
    late UhfService uhf;
    late DatabaseService dbService;

    setUp(() async {
      repo = WarehouseRepository();
      uhf = UhfService();
      dbService = DatabaseService();
      await repo.clearAllData(alsoClearCloud: false);
      await repo.ensureInitialized();
      await repo.ensureDefault10Locations();

      // Setup 5 in-stock items with SKU-SHIRT
      for (int i = 1; i <= 5; i++) {
        await repo.addItem(Item(
          itemId: 'ITEM-SHIRT-00$i',
          productId: 'PROD-SHIRT-001',
          sku: 'SKU-SHIRT',
          productName: 'Áo sơ mi nam',
          serialNumber: 'SN-SHIRT-00$i',
          epc: 'E280116060000204DB9E000$i',
          locationId: 'A-01-01',
          status: ItemStatus.inStock,
        ));
      }

      // Setup 2 in-stock items with SKU-CHIP
      for (int i = 1; i <= 2; i++) {
        await repo.addItem(Item(
          itemId: 'ITEM-CHIP-00$i',
          productId: 'PROD-CHIP-001',
          sku: 'SKU-CHIP',
          productName: 'Vi mạch',
          serialNumber: 'SN-CHIP-00$i',
          epc: 'E280116060000204DB9ECC0$i',
          locationId: 'A-01-02',
          status: ItemStatus.inStock,
        ));
      }
    });

    test('BUG 1: confirmGateOutbound must NOT delete other draft orders sharing same customer & SKU', () async {
      // Đơn 1 của Samsung: PO-SS-001 (cần 1 chip SKU-CHIP)
      final order1 = OutboundOrder(
        outboundOrderId: 'OUT-SS-001',
        poNo: 'PO-SS-001',
        customer: 'Samsung Electronics',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-CHIP-001',
            sku: 'SKU-CHIP',
            productName: 'Vi mạch',
            requiredQty: 1,
            pickedQty: 0,
            epcList: ['E280116060000204DB9ECC01'],
          ),
        ],
      );

      // Đơn 2 của Samsung: PO-SS-002 (cần 1 chip SKU-CHIP cho một đợt giao khác)
      final order2 = OutboundOrder(
        outboundOrderId: 'OUT-SS-002',
        poNo: 'PO-SS-002',
        customer: 'Samsung Electronics',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-CHIP-001',
            sku: 'SKU-CHIP',
            productName: 'Vi mạch',
            requiredQty: 1,
            pickedQty: 0,
            epcList: ['E280116060000204DB9ECC02'],
          ),
        ],
      );

      await repo.addOutboundOrder(order1);
      await repo.addOutboundOrder(order2);
      expect(repo.outboundOrders.length, equals(2));

      // Xuất đơn PO-SS-001 qua cổng
      await repo.confirmGateOutbound(
        poNo: 'PO-SS-001',
        customer: 'Samsung Electronics',
        scannedEpcs: ['E280116060000204DB9ECC01'],
      );

      // KIỂM TRA: Đơn PO-SS-001 chuyển sang shipped, nhưng đơn PO-SS-002 PHẢI CÒN NGUYÊN VẸN!
      expect(repo.outboundOrders.length, equals(2), reason: 'Đơn PO-SS-002 không được bị xóa!');
      final remainingDraft = repo.outboundOrders.where((o) => o.poNo == 'PO-SS-002').firstOrNull;
      expect(remainingDraft, isNotNull);
      expect(remainingDraft!.status, equals(OutboundOrderStatus.newOrder));
    });

    testWidgets('BUG 2: Desktop - Quét 1 trên 5 sản phẩm (khi nạp đơn không có sẵn EPC) TUYỆT ĐỐI KHÔNG được tự động xuất kho', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Tạo đơn hàng 5 áo sơ mi nhưng KHÔNG gán trước EPC (chỉ có SKU và số lượng 5)
      final multiOrder = OutboundOrder(
        outboundOrderId: 'OUT-MULTI-001',
        poNo: 'PO-MULTI-5-ITEMS',
        customer: 'Khách Mua Sỉ',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-SHIRT-001',
            sku: 'SKU-SHIRT',
            productName: 'Áo sơ mi nam',
            requiredQty: 5,
            pickedQty: 0,
            epcList: [], // Không có sẵn EPC trong đơn
          ),
        ],
      );
      await repo.addOutboundOrder(multiOrder);

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
      await tester.tap(find.text('XUẤT HÀNG'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Chọn Đơn Xuất Có Sẵn'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'CHỌN'));
      await tester.pumpAndSettle();

      expect(find.textContaining('PO-MULTI-5-ITEMS'), findsWidgets);

      // Bấm nút BẮT ĐẦU QUÉT
      await tester.tap(find.textContaining('BẮT ĐẦU QUÉT'));
      await tester.pump(const Duration(milliseconds: 300));

      // Bắt đầu quét: Quét CHỈ 1 thẻ trong số 5 thẻ
      uhf.simulateTag('E280116060000204DB9E0001');
      await tester.pump(const Duration(milliseconds: 300));

      // Chờ 2 giây (vượt qua auto-confirm delay 1s)
      await tester.pump(const Duration(seconds: 2));

      // Dừng quét
      uhf.stopInventory();
      await tester.pump(const Duration(milliseconds: 300));

      // Đơn hàng PHẢI VẪN LÀ newOrder, KHÔNG được tự động chuyển thành shipped vì mới quét 1/5 (20%)!
      expect(repo.outboundOrders.first.status, equals(OutboundOrderStatus.newOrder),
          reason: 'Mới quét 1/5 sản phẩm nhưng hệ thống đã tự động xuất kho!');
      expect(repo.outboundOrders.where((o) => o.status == OutboundOrderStatus.shipped).length, equals(0));
    });

    testWidgets('BUG 3: PDA - Quét 1 trên 5 sản phẩm (khi nạp đơn không có sẵn EPC) TUYỆT ĐỐI KHÔNG được tự động xuất kho', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Tạo đơn hàng 5 áo sơ mi không gán trước EPC
      final multiOrder = OutboundOrder(
        outboundOrderId: 'OUT-PDA-MULTI-001',
        poNo: 'PO-PDA-MULTI-5',
        customer: 'Khách PDA Sỉ',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-SHIRT-001',
            sku: 'SKU-SHIRT',
            productName: 'Áo sơ mi nam',
            requiredQty: 5,
            pickedQty: 0,
            epcList: [],
          ),
        ],
      );
      await repo.addOutboundOrder(multiOrder);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: OutboundScreen(initialOrderNo: 'PO-PDA-MULTI-5'),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.textContaining('PO-PDA-MULTI-5'), findsWidgets);

      // Bấm nút Quét trên PDA
      await tester.tap(find.text('Quét'));
      await tester.pump(const Duration(milliseconds: 300));

      // Quét 1 thẻ
      uhf.simulateTag('E280116060000204DB9E0001');
      await tester.pump(const Duration(milliseconds: 300));

      // Chờ 2 giây
      await tester.pump(const Duration(seconds: 2));

      uhf.stopInventory();
      await tester.pump(const Duration(milliseconds: 300));

      // Đơn hàng PHẢI VẪN LÀ newOrder, KHÔNG được tự động xuất khi mới quét 1/5!
      expect(repo.outboundOrders.first.status, equals(OutboundOrderStatus.newOrder),
          reason: 'PDA: Mới quét 1/5 sản phẩm nhưng hệ thống đã tự động xuất kho!');
      expect(repo.outboundOrders.where((o) => o.status == OutboundOrderStatus.shipped).length, equals(0));
    });

    testWidgets('BUG 4: Nạp file mới TUYỆT ĐỐI KHÔNG được xóa các đơn nháp khác trong kho có mã bắt đầu bằng PO- hoặc XK-', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Tạo sẵn 2 đơn nháp khác trong kho của khách hàng khác
      final existingOrderA = OutboundOrder(
        outboundOrderId: 'OUT-DRAFT-AAA',
        poNo: 'PO-CLIENT-AAA',
        customer: 'Khách Hàng AAA',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-SHIRT-001',
            sku: 'SKU-SHIRT',
            productName: 'Áo sơ mi nam',
            requiredQty: 1,
            pickedQty: 0,
          ),
        ],
      );
      final existingOrderB = OutboundOrder(
        outboundOrderId: 'OUT-DRAFT-BBB',
        poNo: 'XK-20261001-001',
        customer: 'Khách Hàng BBB',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-CHIP-001',
            sku: 'SKU-CHIP',
            productName: 'Vi mạch',
            requiredQty: 1,
            pickedQty: 0,
          ),
        ],
      );
      await repo.addOutboundOrder(existingOrderA);
      await repo.addOutboundOrder(existingOrderB);
      expect(repo.outboundOrders.length, equals(2));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: DesktopGoodsDeliveryView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      expect(repo.outboundOrders.any((o) => o.poNo == 'PO-CLIENT-AAA'), isTrue);
      expect(repo.outboundOrders.any((o) => o.poNo == 'XK-20261001-001'), isTrue);
    });

    test('Edge Case: Deduplication case-insensitive preserves single order and updates database properly', () async {
      final orderLower = OutboundOrder(
        outboundOrderId: 'OUT-CASE-01',
        poNo: 'po-test-case-100',
        customer: 'Khách Test Case',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-SHIRT-001',
            sku: 'SKU-SHIRT',
            productName: 'Áo sơ mi',
            requiredQty: 1,
            pickedQty: 0,
          ),
        ],
      );
      await repo.addOutboundOrder(orderLower);
      expect(repo.outboundOrders.length, equals(1));
      expect(await dbService.getOutboundOrders().then((l) => l.length), equals(1));

      // Nạp lại cùng PO nhưng viết hoa 'PO-TEST-CASE-100' và số lượng 3
      final orderUpper = OutboundOrder(
        outboundOrderId: 'OUT-CASE-02',
        poNo: 'PO-TEST-CASE-100',
        customer: 'Khách Test Case',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-SHIRT-001',
            sku: 'SKU-SHIRT',
            productName: 'Áo sơ mi',
            requiredQty: 3,
            pickedQty: 0,
          ),
        ],
      );
      await repo.addOutboundOrder(orderUpper);

      // Phải duy nhất 1 đơn trong cả repo lẫn dbService
      expect(repo.outboundOrders.length, equals(1));
      expect(repo.outboundOrders.first.details.first.requiredQty, equals(3));
      final dbOrders = await dbService.getOutboundOrders();
      expect(dbOrders.length, equals(1));
      expect(dbOrders.first.details.first.requiredQty, equals(3));
    });

    testWidgets('R2 & R3: Quét đủ 100% (cả 2 thẻ) mới kích hoạt xuất kho hoàn tất', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Tạo đơn hàng gồm 2 vi mạch
      final twoItemOrder = OutboundOrder(
        outboundOrderId: 'OUT-TWO-001',
        poNo: 'PO-TWO-ITEMS',
        customer: 'Khách Mua Đủ',
        status: OutboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          OutboundOrderDetail(
            productId: 'PROD-CHIP-001',
            sku: 'SKU-CHIP',
            productName: 'Vi mạch',
            requiredQty: 2,
            pickedQty: 0,
            epcList: ['E280116060000204DB9ECC01', 'E280116060000204DB9ECC02'],
          ),
        ],
      );
      await repo.addOutboundOrder(twoItemOrder);

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
      await tester.tap(find.text('XUẤT HÀNG'));
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Chọn Đơn Xuất Có Sẵn'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'CHỌN'));
      await tester.pumpAndSettle();

      // Bật quét
      await tester.tap(find.textContaining('BẮT ĐẦU QUÉT'));
      await tester.pump(const Duration(milliseconds: 300));

      // Quét thẻ 1: 1/2 sản phẩm
      uhf.simulateTag('E280116060000204DB9ECC01');
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(seconds: 1));

      // Đơn hàng chưa đủ 100% -> Vẫn newOrder
      expect(repo.outboundOrders.first.status, equals(OutboundOrderStatus.newOrder));

      // Quét tiếp thẻ 2: 2/2 sản phẩm (100%)
      uhf.simulateTag('E280116060000204DB9ECC02');
      await tester.pump(const Duration(milliseconds: 300));

      // Chờ tự động xuất kho sau 1s
      await tester.pump(const Duration(milliseconds: 1200));
      await tester.pump(const Duration(milliseconds: 300));

      uhf.stopInventory();
      await tester.pump(const Duration(milliseconds: 300));

      // Đơn hàng đã xuất kho hoàn tất thành shipped
      expect(repo.outboundOrders.length, equals(1));
      expect(repo.outboundOrders.first.status, equals(OutboundOrderStatus.shipped));
      expect(repo.items.where((i) => i.epc == 'E280116060000204DB9ECC01').first.status, equals(ItemStatus.out));
      expect(repo.items.where((i) => i.epc == 'E280116060000204DB9ECC02').first.status, equals(ItemStatus.out));
    });
  });
}
