import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhf/models/tag_info.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/database_service.dart';
import 'package:uhf/services/mysql_sync_service.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('WarehouseRepository Core Business Engine Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.clearAllData();

      await repo.addLocation(Location(locationId: 'LOC-A01-01', locationCode: 'A-01-01', zone: 'Zone A', shelf: 'Kệ 01', level: 'Tầng 1'));
      await repo.addLocation(Location(locationId: 'LOC-A01-02', locationCode: 'A-01-02', zone: 'Zone A', shelf: 'Kệ 01', level: 'Tầng 2'));
      await repo.addLocation(Location(locationId: 'LOC-B01-01', locationCode: 'B-01-01', zone: 'Zone B', shelf: 'Kệ 01', level: 'Tầng 1'));
      await repo.addLocation(Location(locationId: 'LOC-B02-01', locationCode: 'B-02-01', zone: 'Zone B', shelf: 'Kệ 02', level: 'Tầng 1'));

      await repo.addProduct(const Product(productId: 'PROD-001', sku: 'SKU-ELEC-01', productName: 'Bo mạch IoT', unit: 'Cái', category: 'Điện tử'));
      await repo.addProduct(const Product(productId: 'PROD-002', sku: 'SKU-TEXT-02', productName: 'Áo Polo', unit: 'Chiếc', category: 'May mặc'));

      await repo.addInboundOrder(
        InboundOrder(
          inboundOrderId: 'INB-001',
          orderNo: 'INB-2026-001',
          sourceSupplier: 'Nhà cung cấp Test',
          status: InboundOrderStatus.newOrder,
          createdAt: DateTime.now(),
          details: [
            InboundOrderDetail(
              productId: 'PROD-001',
              sku: 'SKU-ELEC-01',
              productName: 'Bo mạch IoT',
              requiredQty: 4,
            ),
            InboundOrderDetail(
              productId: 'PROD-002',
              sku: 'SKU-TEXT-02',
              productName: 'Áo Polo',
              requiredQty: 2,
            ),
          ],
        ),
      );
    });

    test('SQLite Dynamic Data is loaded properly', () {
      expect(repo.products.length >= 2, isTrue);
      expect(repo.locations.length >= 4, isTrue);
      expect(repo.inboundOrders.any((o) => o.orderNo == 'INB-2026-001'), isTrue);
    });

    test('Inbound Workflow: Encode -> Pallet -> Gate Verify PASS -> Inbound Completion', () {
      final order = repo.inboundOrders.firstWhere((o) => o.orderNo == 'INB-2026-001');
      final newItems = repo.generateItemsForInbound(order);
      expect(newItems.length, 6); // 4 + 2

      // Gán vào Pallet
      final pallet = repo.createOrAssignPallet(
        palletCode: 'PL-TEST-01',
        locationId: 'LOC-A01-01',
        newItems: newItems,
      );
      expect(pallet.itemIds.length, 6);

      // Gate verify với đầy đủ EPC -> Phải PASS
      final allEpcs = newItems.map((e) => e.epc).toList();
      final passResult = repo.verifyGateInbound(orderNo: order.orderNo, scannedEpcs: allEpcs);
      expect(passResult.isPass, isTrue);
      expect(passResult.totalActualQty, 6);
      expect(passResult.totalRequiredQty, 6);

      // Gate verify khi thiếu 1 EPC -> Phải FAIL
      final incompleteEpcs = allEpcs.take(5).toList();
      final failResult = repo.verifyGateInbound(orderNo: order.orderNo, scannedEpcs: incompleteEpcs);
      expect(failResult.isPass, isFalse);

      // Xác nhận hoàn tất nhập kho
      final confirmed = repo.confirmInboundCompletion(
        orderNo: order.orderNo,
        palletCode: pallet.palletCode,
        locationId: 'LOC-A01-01',
        performedBy: 'Tester',
      );
      expect(confirmed, isTrue);
      expect(order.status, InboundOrderStatus.completed);
    });

    test('Outbound & FIFO Algorithm: Pick earliest Pallet first', () async {
      final now = DateTime.now();
      // Tạo 2 pallet với ngày nhập khác nhau
      final pl1Items = [
        for (int i = 1; i <= 5; i++)
          Item(itemId: 'IT-$i', productId: 'PROD-001', sku: 'SKU-ELEC-01', productName: 'Bo mạch IoT', serialNumber: 'SN-$i', epc: 'EPC-$i', status: ItemStatus.inStock, inboundTime: now.subtract(const Duration(days: 10))),
      ];
      final pl2Items = [
        for (int i = 6; i <= 10; i++)
          Item(itemId: 'IT-$i', productId: 'PROD-001', sku: 'SKU-ELEC-01', productName: 'Bo mạch IoT', serialNumber: 'SN-$i', epc: 'EPC-$i', status: ItemStatus.inStock, inboundTime: now.subtract(const Duration(days: 5))),
      ];

      final pl1 = repo.createOrAssignPallet(palletCode: 'PL-01', locationId: 'LOC-A01-01', newItems: pl1Items);
      pl1.inboundTime = now.subtract(const Duration(days: 10));
      final pl2 = repo.createOrAssignPallet(palletCode: 'PL-02', locationId: 'LOC-A01-02', newItems: pl2Items);
      pl2.inboundTime = now.subtract(const Duration(days: 5));

      final po = OutboundOrder(
        outboundOrderId: 'OUT-001',
        poNo: 'PO-2026-801',
        customer: 'Siêu thị Mega',
        status: OutboundOrderStatus.newOrder,
        createdAt: now,
        details: [
          OutboundOrderDetail(productId: 'PROD-001', sku: 'SKU-ELEC-01', productName: 'Bo mạch IoT', requiredQty: 7),
        ],
      );
      await repo.addOutboundOrder(po);

      final plan = repo.generateFifoPickingPlan(po.outboundOrderId);

      expect(plan.lines.isNotEmpty, isTrue);
      expect(plan.totalRequiredQty, 7);

      // Pallet PL-01 nhập trước phải được ưu tiên lấy 5 cái
      expect(plan.lines.first.palletCode, 'PL-01');
      expect(plan.lines.first.quantityToPick, 5);

      // Pallet PL-02 nhập sau được lấy 2 cái còn lại
      expect(plan.lines[1].palletCode, 'PL-02');
      expect(plan.lines[1].quantityToPick, 2);

      // Gate verify xuất kho
      final allTargetItemIds = plan.lines.expand((l) => l.targetItemIds).toList();
      final allTargetEpcs = repo.items.where((it) => allTargetItemIds.contains(it.itemId)).map((e) => e.epc).toList();
      final gatePass = repo.verifyGateOutbound(poNo: po.poNo, scannedEpcs: allTargetEpcs);
      expect(gatePass.isPass, isTrue);

      // Xác nhận xuất kho
      final outboundConfirmed = repo.confirmOutboundCompletion(
        poNo: po.poNo,
        shippedEpcs: allTargetEpcs,
        performedBy: 'Tester',
      );
      expect(outboundConfirmed, isTrue);
      expect(po.status, OutboundOrderStatus.shipped);
    });

    test('Inventory Audit: Categorizes 4 Variance Types correctly', () {
      // Setup 1 item ở B-01-01 và 1 item ở A-01-01
      repo.createOrAssignPallet(
        palletCode: 'PL-B1',
        locationId: 'LOC-B01-01',
        newItems: [
          Item(itemId: 'IT-AUDIT-1', productId: 'PROD-001', sku: 'SKU-ELEC-01', productName: 'Bo mạch IoT', serialNumber: 'SN-1', epc: 'E28011600000000000000301', status: ItemStatus.inStock),
          Item(itemId: 'IT-AUDIT-MISSING', productId: 'PROD-001', sku: 'SKU-ELEC-01', productName: 'Bo mạch IoT', serialNumber: 'SN-2', epc: 'E28011600000000000000302', status: ItemStatus.inStock),
        ],
      );
      repo.createOrAssignPallet(
        palletCode: 'PL-A1',
        locationId: 'LOC-A01-01',
        newItems: [
          Item(itemId: 'IT-AUDIT-2', productId: 'PROD-001', sku: 'SKU-ELEC-01', productName: 'Bo mạch IoT', serialNumber: 'SN-3', epc: 'E28011600000000000000201', status: ItemStatus.inStock),
        ],
      );

      final session = repo.startInventorySession(zone: 'Zone B', locationCode: 'B-01-01');
      expect(session.isCompleted, isFalse);

      // Quét các thẻ tại B-01-01: 1 thẻ khớp, 1 thẻ sai vị trí (thuộc A-01-01), 1 thẻ lạ
      final scanned = [
        'E28011600000000000000301', // Match (ở B-01-01)
        'E28011600000000000000201', // Wrong location (ở A-01-01)
        'E28011600000000000099999', // Unknown EPC (thẻ lạ)
      ];

      repo.processAuditScan(sessionId: session.sessionId, scannedEpcs: scanned);

      expect(session.results.any((r) => r.resultType == InventoryVarianceType.match), isTrue);
      expect(session.results.any((r) => r.resultType == InventoryVarianceType.wrongLocation), isTrue);
      expect(session.results.any((r) => r.resultType == InventoryVarianceType.unknownEpc), isTrue);
      expect(session.results.any((r) => r.resultType == InventoryVarianceType.missing), isTrue);

      // Chốt phiên
      repo.completeInventorySession(session.sessionId, 'Manager');
      expect(session.isCompleted, isTrue);
    });

    test('Pallet Movement updates Location and Item positions', () {
      final pallet = repo.createOrAssignPallet(
        palletCode: 'PL-MOVE-01',
        locationId: 'LOC-A01-01',
        newItems: [
          Item(itemId: 'IT-MV-1', productId: 'PROD-001', sku: 'SKU-ELEC-01', productName: 'Bo mạch', serialNumber: 'SN-1', epc: 'EPC-MV-1'),
        ],
      );
      final moved = repo.movePallet(
        palletId: pallet.palletId,
        newLocationId: 'LOC-B02-01',
        performedBy: 'Tester',
      );
      expect(moved, isTrue);
      expect(pallet.locationId, 'LOC-B02-01');

      for (var itemId in pallet.itemIds) {
        final item = repo.items.firstWhere((it) => it.itemId == itemId);
        expect(item.locationId, 'LOC-B02-01');
      }
    });

    test('UhfService Duplicate Tag Filter: skips already read tags', () async {
      final uhf = UhfService();
      uhf.clearTags();
      uhf.filterDuplicates = true;

      final streamedTags = <TagInfo>[];
      final sub = uhf.onTagRead.listen((t) => streamedTags.add(t));

      // Simulate first read
      await uhf.inventorySingleTag();
      await Future.delayed(const Duration(milliseconds: 30));

      expect(uhf.uniqueTagCount, 1);
      expect(streamedTags.length, 1);

      // Simulate second read of the exact same tag
      await uhf.inventorySingleTag();
      await Future.delayed(const Duration(milliseconds: 30));

      // Should still be 1 because duplicate was skipped
      expect(uhf.uniqueTagCount, 1);
      expect(streamedTags.length, 1);

      // Now toggle filterDuplicates = false
      uhf.filterDuplicates = false;
      await uhf.inventorySingleTag();
      await Future.delayed(const Duration(milliseconds: 30));

      // Now it should have emitted the 2nd stream event
      expect(streamedTags.length, 2);

      await sub.cancel();
      uhf.filterDuplicates = true;
    });

    test('PDA Offline-First SQLite Queue: operations are saved locally and synced to MySQL', () async {
      final dbService = DatabaseService();
      final syncService = MySqlSyncService();

      // Clear sync queue
      await dbService.clearAllData();
      expect(await dbService.getPendingSyncCount(), 0);

      // Perform an offline Inbound Scan operation
      await repo.confirmHandheldInbound(
        orderNo: 'INB-OFFLINE-001',
        palletCode: 'PL-OFFLINE-A',
        locationId: 'LOC-A01-01',
        scannedEpcs: ['E28011600000000000099001', 'E28011600000000000099002'],
        performedBy: 'Thủ kho Offline',
      );

      // Verify SQLite recorded pending sync items
      final pendingCount = await dbService.getPendingSyncCount();
      expect(pendingCount, greaterThanOrEqualTo(1));

      final pendingItems = await dbService.getPendingSyncItems();
      expect(pendingItems.any((item) => item['record_id'] == 'INB-OFFLINE-001'), isTrue);

      // Trigger MySQL Sync
      final syncOk = await syncService.syncNow();
      expect(syncOk, isTrue);

      // Verify sync completed and queue was cleared
      expect(await dbService.getPendingSyncCount(), 0);
      expect(syncService.logs.any((l) => l.action == 'PUSH'), isTrue);
    });

    test('Automatic Sync triggers immediately when Wi-Fi connects without pressing any button', () async {
      final dbService = DatabaseService();
      final syncService = MySqlSyncService();

      // Clear sync queue
      await dbService.clearAllData();

      // Perform a local transaction
      await repo.confirmHandheldInbound(
        orderNo: 'INB-AUTOSYNC-001',
        palletCode: 'PL-AUTO-01',
        locationId: 'LOC-A01-01',
        scannedEpcs: ['E28011600000000000099888'],
        performedBy: 'Thủ kho Wi-Fi Auto',
      );

      expect(await dbService.getPendingSyncCount(), greaterThanOrEqualTo(1));

      // Simulate Wi-Fi connection trigger
      await syncService.checkConnectivity();

      // Auto-sync should process and flush queue
      final syncResult = await syncService.syncNow();
      expect(syncResult, isTrue);
      expect(await dbService.getPendingSyncCount(), 0);
    });
  });
}
