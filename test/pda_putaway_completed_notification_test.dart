import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/pda/pda_home_screen.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDA Inbound Putaway Completed Notification Tests', () {
    late WarehouseRepository repo;
    late AuthService authService;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
      authService = AuthService();
      await authService.init(force: true);
      await authService.login(username: 'admin', password: 'admin123');
    });

    test('isInboundOrderPutawayCompleted returns true when all items are inStock on shelf', () async {
      final orderNo = 'NK-DEMO-999999';
      final order = InboundOrder(
        inboundOrderId: orderNo,
        orderNo: orderNo,
        sourceSupplier: 'Nhà cung cấp Test',
        status: InboundOrderStatus.waitingPalletize,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: 'PROD-BOX-01',
            sku: 'BOX-MET-01',
            productName: 'Hộp sắt đựng chứng từ',
            requiredQty: 2,
            receivedQty: 0,
          ),
        ],
      );
      await repo.addInboundOrder(order, autoGenerateEpcs: false);

      final items = [
        Item(
          itemId: 'ITM-999-1',
          productId: 'PROD-BOX-01',
          sku: 'BOX-MET-01',
          productName: 'Hộp sắt đựng chứng từ',
          serialNumber: 'SN-999-1',
          epc: 'E280TEST_COMPL_1',
          status: ItemStatus.inStock,
          orderNo: orderNo,
          locationId: 'LOC-A-01-01',
        ),
        Item(
          itemId: 'ITM-999-2',
          productId: 'PROD-BOX-01',
          sku: 'BOX-MET-01',
          productName: 'Hộp sắt đựng chứng từ',
          serialNumber: 'SN-999-2',
          epc: 'E280TEST_COMPL_2',
          status: ItemStatus.inStock,
          orderNo: orderNo,
          locationId: 'LOC-A-01-01',
        ),
      ];
      await repo.insertDirectItems(items);

      expect(repo.isInboundOrderPutawayCompleted(order), isTrue);
    });

    test('confirmPdaPutawayByCarton auto completes InboundOrder when all items put away', () async {
      final orderNo = 'NK-DEMO-360230';
      final order = InboundOrder(
        inboundOrderId: orderNo,
        orderNo: orderNo,
        sourceSupplier: 'Nhà cung cấp Test',
        status: InboundOrderStatus.waitingPalletize,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: 'PROD-BOX-01',
            sku: 'BOX-MET-01',
            productName: 'Hộp sắt đựng chứng từ',
            requiredQty: 2,
            receivedQty: 0,
          ),
        ],
      );
      await repo.addInboundOrder(order, autoGenerateEpcs: false);

      final items = [
        Item(
          itemId: 'ITM-360-1',
          productId: 'PROD-BOX-01',
          sku: 'BOX-MET-01',
          productName: 'Hộp sắt đựng chứng từ',
          serialNumber: 'SN-360-1',
          epc: 'E280TEST_PUT_1',
          status: ItemStatus.waitingPalletize,
          orderNo: orderNo,
        ),
        Item(
          itemId: 'ITM-360-2',
          productId: 'PROD-BOX-01',
          sku: 'BOX-MET-01',
          productName: 'Hộp sắt đựng chứng từ',
          serialNumber: 'SN-360-2',
          epc: 'E280TEST_PUT_2',
          status: ItemStatus.waitingPalletize,
          orderNo: orderNo,
        ),
      ];
      await repo.insertDirectItems(items);

      // Thêm vị trí kệ
      await repo.addLocation(Location(
        locationId: 'LOC-A-01-03-02',
        locationCode: 'A-01-03-02',
        zone: 'Khu A',
        shelf: 'Kệ 01',
        level: 'Tầng 03',
      ));

      // Thực hiện cất hàng lên kệ
      final savedCount = await repo.confirmPdaPutawayByCarton(
        cartonOrOrderBarcode: orderNo,
        locationId: 'LOC-A-01-03-02',
      );

      expect(savedCount, 2);
      final updatedOrder = repo.inboundOrders.firstWhere((o) => o.orderNo == orderNo);
      expect(updatedOrder.status, InboundOrderStatus.completed);
      expect(repo.isInboundOrderPutawayCompleted(updatedOrder), isTrue);
    });

    testWidgets('PdaHomeScreen does not show CAN XEP VAO PALLET notification when order is already put away', (tester) async {
      final orderNo = 'NK-DEMO-360230';
      final order = InboundOrder(
        inboundOrderId: orderNo,
        orderNo: orderNo,
        sourceSupplier: 'Nhà cung cấp Test',
        status: InboundOrderStatus.completed,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: 'PROD-BOX-01',
            sku: 'BOX-MET-01',
            productName: 'Hộp sắt đựng chứng từ',
            requiredQty: 2,
            receivedQty: 2,
          ),
        ],
      );
      await repo.addInboundOrder(order, autoGenerateEpcs: false);

      final items = [
        Item(
          itemId: 'ITM-360-1',
          productId: 'PROD-BOX-01',
          sku: 'BOX-MET-01',
          productName: 'Hộp sắt đựng chứng từ',
          serialNumber: 'SN-360-1',
          epc: 'E280TEST_WIDG_1',
          status: ItemStatus.inStock,
          locationId: 'LOC-A-01-03-02',
          orderNo: orderNo,
        ),
        Item(
          itemId: 'ITM-360-2',
          productId: 'PROD-BOX-01',
          sku: 'BOX-MET-01',
          productName: 'Hộp sắt đựng chứng từ',
          serialNumber: 'SN-360-2',
          epc: 'E280TEST_WIDG_2',
          status: ItemStatus.inStock,
          locationId: 'LOC-A-01-03-02',
          orderNo: orderNo,
        ),
      ];
      await repo.insertDirectItems(items);

      await tester.binding.setSurfaceSize(const Size(360, 720));
      await tester.pumpWidget(
        const MaterialApp(
          home: PdaHomeScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Không được hiển thị thông báo CẦN XẾP VÀO PALLET
      expect(find.text('CẦN XẾP VÀO PALLET'), findsNothing);
      expect(find.textContaining('NK-DEMO-360230'), findsNothing);
    });

    testWidgets('Card CAN XEP VAO PALLET dynamically disappears after putaway is completed', (tester) async {
      final orderNo = 'NK-DEMO-DYN-01';
      final order = InboundOrder(
        inboundOrderId: orderNo,
        orderNo: orderNo,
        sourceSupplier: 'Nhà cung cấp Test',
        status: InboundOrderStatus.waitingPalletize,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: 'PROD-BOX-01',
            sku: 'BOX-MET-01',
            productName: 'Hộp sắt đựng chứng từ',
            requiredQty: 2,
            receivedQty: 0,
          ),
        ],
      );
      await repo.addInboundOrder(order, autoGenerateEpcs: false);

      final items = [
        Item(
          itemId: 'ITM-DYN-1',
          productId: 'PROD-BOX-01',
          sku: 'BOX-MET-01',
          productName: 'Hộp sắt đựng chứng từ',
          serialNumber: 'SN-DYN-1',
          epc: 'E280DYN_1',
          status: ItemStatus.waitingPalletize,
          orderNo: orderNo,
        ),
        Item(
          itemId: 'ITM-DYN-2',
          productId: 'PROD-BOX-01',
          sku: 'BOX-MET-01',
          productName: 'Hộp sắt đựng chứng từ',
          serialNumber: 'SN-DYN-2',
          epc: 'E280DYN_2',
          status: ItemStatus.waitingPalletize,
          orderNo: orderNo,
        ),
      ];
      await repo.insertDirectItems(items);

      await repo.addLocation(Location(
        locationId: 'LOC-A-01-03-02',
        locationCode: 'A-01-03-02',
        zone: 'Khu A',
        shelf: 'Kệ 01',
        level: 'Tầng 03',
      ));

      await tester.binding.setSurfaceSize(const Size(360, 720));
      await tester.pumpWidget(
        const MaterialApp(
          home: PdaHomeScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Lúc này chưa cất kệ -> phải hiển thị thông báo CẦN XẾP VÀO PALLET
      expect(find.text('CẦN XẾP VÀO PALLET'), findsOneWidget);
      expect(find.textContaining(orderNo), findsOneWidget);

      // Tiến hành cất hàng lên kệ
      await repo.confirmPdaPutawayByCarton(
        cartonOrOrderBarcode: orderNo,
        locationId: 'LOC-A-01-03-02',
      );

      // Đợi UI cập nhật
      await tester.pumpAndSettle(const Duration(milliseconds: 600));

      // Sau khi đã cất vào kệ -> thẻ thông báo phải biến mất hoàn toàn!
      expect(find.text('CẦN XẾP VÀO PALLET'), findsNothing);
      expect(find.textContaining(orderNo), findsNothing);
    });
  });
}
