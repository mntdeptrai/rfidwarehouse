import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_receive_view.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Dynamic Pallet Selection: Whichever pallet chip enters gate first (e.g. Pallet 2 before Pallet 1), system automatically selects and processes that pallet', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final repo = WarehouseRepository();
    await repo.ensureInitialized();

    // Dọn sạch các item pending cũ
    final oldPending = repo.items.where((it) => it.status == ItemStatus.pendingInbound).map((it) => it.epc).toList();
    await repo.deleteItemsByEpcs(oldPending);

    const orderNo = 'NK-DYN-ORDER-01';

    await repo.addProduct(const Product(
      productId: 'PROD-SKU-A',
      sku: 'SKU-A',
      productName: 'Hàng Pallet 1',
      unit: 'Cái',
      category: 'Gia dụng',
    ));
    await repo.addProduct(const Product(
      productId: 'PROD-SKU-B',
      sku: 'SKU-B',
      productName: 'Hàng Pallet 2',
      unit: 'Cái',
      category: 'Gia dụng',
    ));

    await repo.addInboundOrder(InboundOrder(
      inboundOrderId: orderNo,
      orderNo: orderNo,
      status: InboundOrderStatus.newOrder,
      sourceSupplier: 'Nhà cung cấp Dynamic Test',
      createdAt: DateTime.now(),
      details: [
        InboundOrderDetail(
          productId: 'PROD-SKU-A',
          sku: 'SKU-A',
          productName: 'Hàng Pallet 1',
          requiredQty: 2,
          receivedQty: 0,
        ),
        InboundOrderDetail(
          productId: 'PROD-SKU-B',
          sku: 'SKU-B',
          productName: 'Hàng Pallet 2',
          requiredQty: 2,
          receivedQty: 0,
        ),
      ],
    ), autoGenerateEpcs: false);

    // 2 items thuộc Pallet 1 (PL-01)
    final p1Epcs = ['E280119100000000PL1_ITEM1', 'E280119100000000PL1_ITEM2'];
    for (int i = 0; i < p1Epcs.length; i++) {
      await repo.addItem(Item(
        itemId: 'ITEM-DYN-P1-$i',
        productId: 'PROD-SKU-A',
        sku: 'SKU-A',
        productName: 'Hàng Pallet 1',
        serialNumber: 'SN-DYN-P1-$i',
        epc: p1Epcs[i],
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
        palletId: 'PAL-PL-01',
      ));
    }

    // 2 items thuộc Pallet 2 (PL-02)
    final p2Epcs = ['E280119100000000PL2_ITEM1', 'E280119100000000PL2_ITEM2'];
    for (int i = 0; i < p2Epcs.length; i++) {
      await repo.addItem(Item(
        itemId: 'ITEM-DYN-P2-$i',
        productId: 'PROD-SKU-B',
        sku: 'SKU-B',
        productName: 'Hàng Pallet 2',
        serialNumber: 'SN-DYN-P2-$i',
        epc: p2Epcs[i],
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
        palletId: 'PAL-PL-02',
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

    // Bắt đầu quét cổng RFID
    final startScanBtn = find.textContaining('BẮT ĐẦU QUÉT');
    expect(startScanBtn, findsOneWidget);
    await tester.tap(startScanBtn);
    await tester.pump();

    // TÌNH HUỐNG: Xe Pallet 2 (PL-02) ĐẨY VÀO CỔNG TRƯỚC!
    // Chip của Pallet 2 đến cổng trước:
    UhfService().simulateTag(p2Epcs[0]);
    await tester.pump(const Duration(milliseconds: 100));

    // Hệ thống phải tự động chọn Pallet 2 thay vì Pallet 1!
    UhfService().simulateTag(p2Epcs[1]);
    await tester.pump(const Duration(milliseconds: 200));

    // Đợi auto-complete timer 350ms
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Kiểm tra: 2 item của Pallet 2 đã được nhập thành công sang waitingPutaway!
    for (final epc in p2Epcs) {
      final item = repo.items.firstWhere((i) => i.epc == epc);
      expect(item.status, ItemStatus.waitingPutaway, reason: 'Pallet 2 vào trước phải hoàn tất trước sang waitingPutaway!');
    }

    // 2 item của Pallet 1 VẪN ĐANG pendingInbound!
    for (final epc in p1Epcs) {
      final item = repo.items.firstWhere((i) => i.epc == epc);
      expect(item.status, ItemStatus.pendingInbound, reason: 'Pallet 1 chưa vào cổng thì vẫn phải là pendingInbound!');
    }

    // TIẾP TỤC: Xe Pallet 1 (PL-01) ĐẨY VÀO CỔNG SAU ĐÓ!
    for (final epc in p1Epcs) {
      UhfService().simulateTag(epc);
    }
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));

    // Kiểm tra: Bây giờ Pallet 1 cũng đã hoàn tất thành công sang waitingPutaway!
    for (final epc in p1Epcs) {
      final item = repo.items.firstWhere((i) => i.epc == epc);
      expect(item.status, ItemStatus.waitingPutaway, reason: 'Pallet 1 vào sau cũng phải hoàn tất thành công!');
    }

    // Cả 2 pallet đều hoàn tất
    final finalOrd = repo.inboundOrders.firstWhere((o) => o.orderNo == orderNo);
    expect(finalOrd.status, InboundOrderStatus.waitingPutaway);

    // Xả timer
    await tester.pump(const Duration(seconds: 4));
  });
}
