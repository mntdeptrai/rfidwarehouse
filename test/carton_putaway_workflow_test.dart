import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('End-to-End Carton Gate Receive & PDA Putaway Workflow Tests', () {
    test('Gate Read -> WAITING_PUTAWAY -> PDA Barcode Putaway -> IN_STOCK at Location', () async {
      final repo = WarehouseRepository();
      await repo.ensureInitialized();

      final timestamp = DateTime.now().microsecondsSinceEpoch;
      final testOrderNo = 'CARTON-WF-$timestamp';
      final testSku = 'SKU-WF-$timestamp';
      const testLocationId = 'LOC-A1-02-01';

      // 1. Tạo đơn hàng hoặc kiện hàng chờ nhập
      final order = InboundOrder(
        inboundOrderId: 'INB-$testOrderNo',
        orderNo: testOrderNo,
        sourceSupplier: 'Nhà Cung Cấp Tổng',
        status: InboundOrderStatus.newOrder,
        createdAt: DateTime.now(),
        details: [
          InboundOrderDetail(
            productId: 'PROD-WF-001',
            sku: testSku,
            productName: 'Sản Phẩm Test Luồng',
            requiredQty: 5,
          ),
        ],
      );

      final generatedItems = await repo.addInboundOrder(order, autoGenerateEpcs: true);
      expect(generatedItems.length, equals(5));
      expect(generatedItems.every((i) => i.status == ItemStatus.pendingInbound), isTrue);

      final scannedEpcs = generatedItems.map((i) => i.epc).toList();

      // 2. GIAI ĐOẠN 1: Kiện hàng đi qua Cổng RFID Gate
      final gateReceivedCount = await repo.confirmGateReceiveToWaitingPutaway(
        orderNo: testOrderNo,
        scannedEpcs: scannedEpcs,
        gateLocationId: 'LOC-GATE-IN',
        performedBy: 'Trạm Cổng RFID Desktop',
      );

      expect(gateReceivedCount, equals(5));

      // Kiểm tra trạng thái sau khi qua cổng: Chờ xếp kho (WAITING_PUTAWAY) và ở Cổng (LOC-GATE-IN)
      final itemsAfterGate = repo.getItemsByOrderNo(testOrderNo);
      expect(itemsAfterGate.length, equals(5));
      expect(itemsAfterGate.every((i) => i.status == ItemStatus.waitingPutaway), isTrue);
      expect(itemsAfterGate.every((i) => i.locationId == 'LOC-GATE-IN'), isTrue);

      final orderAfterGate = repo.inboundOrders.where((o) => o.orderNo == testOrderNo).first;
      expect(orderAfterGate.status, equals(InboundOrderStatus.waitingPutaway));

      // 3. GIAI ĐOẠN 2: Thủ kho cầm PDA quét Barcode Vị trí kệ và quét Barcode Thùng hàng
      final putawayCount = await repo.confirmPdaPutawayByCarton(
        cartonOrOrderBarcode: testOrderNo,
        locationId: testLocationId,
        performedBy: 'Thủ kho PDA',
      );

      expect(putawayCount, equals(5));

      // Kiểm tra trạng thái sau khi cất lên kệ: Đang lưu kho (IN_STOCK) và tại đúng vị trí đích
      final itemsAfterPutaway = repo.getItemsByOrderNo(testOrderNo);
      expect(itemsAfterPutaway.every((i) => i.status == ItemStatus.inStock), isTrue);
      expect(itemsAfterPutaway.every((i) => i.locationId == testLocationId), isTrue);

      final orderAfterPutaway = repo.inboundOrders.where((o) => o.orderNo == testOrderNo).first;
      expect(orderAfterPutaway.status, equals(InboundOrderStatus.completed));

      // Kiểm tra nhật ký giao dịch
      final tx = repo.transactions.where((t) => t.documentNo == testOrderNo).firstOrNull;
      expect(tx, isNotNull);
      expect(tx!.type, equals(TransactionType.movement));

      // Dọn dẹp dữ liệu test khỏi SQLite sau khi test xong
      await repo.clearAllData(alsoClearMySql: false);
    });
  });
}

