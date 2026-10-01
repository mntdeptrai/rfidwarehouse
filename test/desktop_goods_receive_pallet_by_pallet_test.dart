import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_receive_view.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/uhf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('DesktopGoodsReceiveView automatically receives pallet by pallet when each pallet reaches 100%', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final repo = WarehouseRepository();
    final uhf = UhfService();

    // Dọn dẹp sạch dữ liệu thử nghiệm cũ
    final oldItems = repo.items.where((it) => it.orderNo?.startsWith('NK-TEST-PAL-') == true).map((it) => it.epc).toList();
    if (oldItems.isNotEmpty) {
      await repo.deleteItemsByEpcs(oldItems);
    }

    const orderNo = 'NK-TEST-PAL-001';

    // Tạo sản phẩm cho 2 pallet: PL-01 có 2 chip, PL-02 có 2 chip
    final itemsP1 = [
      Item(
        itemId: 'ITEM-TEST-PL1-1',
        productId: 'SKU-AO',
        sku: 'SKU-AO',
        productName: 'Áo Sơ Mi',
        serialNumber: 'SN-AO-1',
        epc: 'E280119100000000AO000001',
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
        palletId: 'PAL-PL-01',
      ),
      Item(
        itemId: 'ITEM-TEST-PL1-2',
        productId: 'SKU-AO',
        sku: 'SKU-AO',
        productName: 'Áo Sơ Mi',
        serialNumber: 'SN-AO-2',
        epc: 'E280119100000000AO000002',
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
        palletId: 'PAL-PL-01',
      ),
    ];

    final itemsP2 = [
      Item(
        itemId: 'ITEM-TEST-PL2-1',
        productId: 'SKU-QUAN',
        sku: 'SKU-QUAN',
        productName: 'Quần Tây',
        serialNumber: 'SN-QUAN-1',
        epc: 'E280119100000000QU000001',
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
        palletId: 'PAL-PL-02',
      ),
      Item(
        itemId: 'ITEM-TEST-PL2-2',
        productId: 'SKU-QUAN',
        sku: 'SKU-QUAN',
        productName: 'Quần Tây',
        serialNumber: 'SN-QUAN-2',
        epc: 'E280119100000000QU000002',
        status: ItemStatus.pendingInbound,
        orderNo: orderNo,
        palletId: 'PAL-PL-02',
      ),
    ];

    final allItems = [...itemsP1, ...itemsP2];

    final inboundOrder = InboundOrder(
      inboundOrderId: orderNo,
      orderNo: orderNo,
      sourceSupplier: 'Tổng Công Ty May Test',
      status: InboundOrderStatus.newOrder,
      createdAt: DateTime.now(),
      details: [
        InboundOrderDetail(productId: 'SKU-AO', sku: 'SKU-AO', productName: 'Áo Sơ Mi', requiredQty: 2),
        InboundOrderDetail(productId: 'SKU-QUAN', sku: 'SKU-QUAN', productName: 'Quần Tây', requiredQty: 2),
      ],
    );

    await repo.addInboundOrder(inboundOrder, autoGenerateEpcs: false);
    await repo.insertDirectItems(allItems);

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
    if (startScanBtn.evaluate().isNotEmpty) {
      await tester.tap(startScanBtn.first);
      await tester.pump();
    }

    // BƯỚC 1: Xe kéo Pallet PL-01 qua cổng, cổng quét đủ 2 chip của PL-01
    uhf.simulateTag('E280119100000000AO000001');
    uhf.simulateTag('E280119100000000AO000002');
    await tester.pump(const Duration(milliseconds: 400));
    // Chờ timer 350ms tự động nhận Pallet PL-01
    await tester.pump(const Duration(milliseconds: 500));

    // Kiểm tra: 2 chip của Pallet PL-01 đã được nhận và chuyển sang waitingPutaway!
    final p1ItemsAfter = repo.items.where((i) => i.palletId?.contains('PL-01') == true).toList();
    expect(p1ItemsAfter.every((i) => i.status == ItemStatus.waitingPutaway), isTrue);

    // Trong khi đó các chip của Pallet PL-02 VẪN ĐANG CHỜ (pendingInbound)
    final p2ItemsBefore = repo.items.where((i) => i.palletId?.contains('PL-02') == true).toList();
    expect(p2ItemsBefore.every((i) => i.status == ItemStatus.pendingInbound), isTrue);

    // BƯỚC 2: Xe kéo Pallet PL-02 qua cổng, cổng quét tiếp 2 chip của PL-02
    uhf.simulateTag('E280119100000000QU000001');
    uhf.simulateTag('E280119100000000QU000002');
    await tester.pump(const Duration(milliseconds: 400));
    // Chờ timer 350ms tự động nhận Pallet PL-02
    await tester.pump(const Duration(milliseconds: 500));

    // Kiểm tra: Bây giờ cả Pallet PL-02 cũng đã được tự động nhận sang waitingPutaway!
    final p2ItemsAfter = repo.items.where((i) => i.palletId?.contains('PL-02') == true).toList();
    expect(p2ItemsAfter.every((i) => i.status == ItemStatus.waitingPutaway), isTrue);

    // Toàn bộ các chip của cả 2 pallet đều đã nhận đủ!
    final allOrderItems = repo.items.where((i) => i.orderNo == orderNo).toList();
    expect(allOrderItems.every((i) => i.status == ItemStatus.waitingPutaway), isTrue);

    // Dừng quét và xả hết các timer còn pending (đèn tháp, banner thông báo 3-4s)
    uhf.stopInventory();
    await tester.pump(const Duration(seconds: 5));
  });
}
