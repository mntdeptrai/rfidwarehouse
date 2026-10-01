import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_receive_view.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Sequential Inbound: Pallet 1 completes and receives immediately without waiting for Pallet 2', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final repo = WarehouseRepository();
    await repo.ensureInitialized();

    // Dọn sạch các item pending cũ
    final oldPending = repo.items.where((it) => it.status == ItemStatus.pendingInbound).map((it) => it.epc).toList();
    await repo.deleteItemsByEpcs(oldPending);

    const orderNo = 'NK-SEQ-PALLET-01';

    await repo.addProduct(const Product(
      productId: 'PROD-SKU-P1',
      sku: 'SKU-P1',
      productName: 'Sản phẩm P1',
      unit: 'Cái',
      category: 'Hàng gia dụng',
    ));
    await repo.addProduct(const Product(
      productId: 'PROD-SKU-P2',
      sku: 'SKU-P2',
      productName: 'Sản phẩm P2',
      unit: 'Cái',
      category: 'Hàng gia dụng',
    ));

    await repo.addInboundOrder(InboundOrder(
      inboundOrderId: orderNo,
      orderNo: orderNo,
      status: InboundOrderStatus.newOrder,
      sourceSupplier: 'Nhà cung cấp Test',
      createdAt: DateTime.now(),
      details: [
        InboundOrderDetail(
          productId: 'PROD-SKU-P1',
          sku: 'SKU-P1',
          productName: 'Sản phẩm P1',
          requiredQty: 3,
          receivedQty: 0,
        ),
        InboundOrderDetail(
          productId: 'PROD-SKU-P2',
          sku: 'SKU-P2',
          productName: 'Sản phẩm P2',
          requiredQty: 4,
          receivedQty: 0,
        ),
      ],
    ), autoGenerateEpcs: false);

    // 3 items cho Pallet 1 (PL-01)
    final p1Epcs = ['E280119100000000SEQ1001', 'E280119100000000SEQ1002', 'E280119100000000SEQ1003'];
    for (int i = 0; i < p1Epcs.length; i++) {
      await repo.addItem(Item(
        itemId: 'ITEM-SEQ-P1-$i',
        productId: 'PROD-SKU-P1',
        sku: 'SKU-P1',
        productName: 'Sản phẩm P1',
        serialNumber: 'SN-SEQ-P1-$i',
        epc: p1Epcs[i],
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
        palletId: 'PAL-PL01',
      ));
    }

    // 4 items cho Pallet 2 (PL-02)
    final p2Epcs = ['E280119100000000SEQ2001', 'E280119100000000SEQ2002', 'E280119100000000SEQ2003', 'E280119100000000SEQ2004'];
    for (int i = 0; i < p2Epcs.length; i++) {
      await repo.addItem(Item(
        itemId: 'ITEM-SEQ-P2-$i',
        productId: 'PROD-SKU-P2',
        sku: 'SKU-P2',
        productName: 'Sản phẩm P2',
        serialNumber: 'SN-SEQ-P2-$i',
        epc: p2Epcs[i],
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
        palletId: 'PAL-PL02',
      ));
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(splashFactory: InkRipple.splashFactory),
        home: const Scaffold(
          body: DesktopGoodsReceiveView(isActive: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    // Bắt đầu quét qua cổng
    await tester.tap(find.textContaining('BẮT ĐẦU QUÉT'));
    await tester.pump();

    // 1. Quét Pallet 1: mô phỏng chỉ 3 chip của Pallet 1 qua cổng
    for (final epc in p1Epcs) {
      UhfService().simulateTag(epc);
    }
    await tester.pump(const Duration(milliseconds: 100));
    // Đợi auto complete timer (350ms)
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Kiểm tra: 3 item của Pallet 1 đã chuyển thành waitingPutaway!
    for (final epc in p1Epcs) {
      final item = repo.items.firstWhere((i) => i.epc == epc);
      expect(item.status, ItemStatus.waitingPutaway, reason: 'Pallet 1 phải được nhập thành công sang waitingPutaway!');
    }

    // Nhưng 4 item của Pallet 2 vẫn đang là pendingInbound!
    for (final epc in p2Epcs) {
      final item = repo.items.firstWhere((i) => i.epc == epc);
      expect(item.status, ItemStatus.pendingInbound, reason: 'Pallet 2 chưa quét thì không được tự ý đổi trạng thái!');
    }

    // Đơn hàng đang ở trạng thái processing vì còn Pallet 2 chưa qua cổng!
    final ord = repo.inboundOrders.firstWhere((o) => o.orderNo == orderNo);
    expect(ord.status, InboundOrderStatus.processing);

    // 2. Tiếp tục cho Pallet 2 qua cổng: mô phỏng 4 chip của Pallet 2
    for (final epc in p2Epcs) {
      UhfService().simulateTag(epc);
    }
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Kiểm tra: 4 item của Pallet 2 cũng đã chuyển thành waitingPutaway!
    for (final epc in p2Epcs) {
      final item = repo.items.firstWhere((i) => i.epc == epc);
      expect(item.status, ItemStatus.waitingPutaway, reason: 'Pallet 2 quét đủ phải được nhập sang waitingPutaway!');
    }

    // Toàn bộ cả 2 pallet đều đã hoàn tất
    final finalOrd = repo.inboundOrders.firstWhere((o) => o.orderNo == orderNo);
    expect(finalOrd.status, InboundOrderStatus.waitingPutaway);

    // Xả timer
    await tester.pump(const Duration(seconds: 4));
  });
}
