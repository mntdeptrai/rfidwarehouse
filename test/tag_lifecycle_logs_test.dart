import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RFID Tag Lifecycle Logs & Audit Trail Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
    });

    test('TagLifecycleLog model serialization & deserialization', () {
      final now = DateTime.now();
      final log = TagLifecycleLog(
        logId: 'LOG-TEST-001',
        epc: 'E28068940000000000000001',
        itemId: 'ITEM-TEST-001',
        sku: 'SKU-VT-001',
        productName: 'Module Cảm Biến UHF',
        serialNumber: 'SN-001',
        action: TagLifecycleAction.transferLocation,
        previousStatus: ItemStatus.inStock.label,
        newStatus: ItemStatus.inStock.label,
        fromLocation: 'Kệ A1',
        toLocation: 'Kệ B2',
        fromPallet: 'PL-01',
        toPallet: 'PL-02',
        documentNo: 'DC-2026-001',
        performedBy: 'Nguyễn Văn A',
        device: 'SEUIC UTouch 2 (PDA)',
        timestamp: now,
        notes: 'Chuyển vị trí thử nghiệm',
      );

      final map = log.toMap();
      expect(map['log_id'], equals('LOG-TEST-001'));
      expect(map['epc'], equals('E28068940000000000000001'));
      expect(map['action'], equals('TRANSFER_LOC'));
      expect(map['from_location'], equals('Kệ A1'));
      expect(map['to_location'], equals('Kệ B2'));

      final reconstructed = TagLifecycleLog.fromMap(map);
      expect(reconstructed.logId, equals(log.logId));
      expect(reconstructed.epc, equals(log.epc));
      expect(reconstructed.action, equals(TagLifecycleAction.transferLocation));
      expect(reconstructed.fromLocation, equals('Kệ A1'));
      expect(reconstructed.toLocation, equals('Kệ B2'));
      expect(reconstructed.performedBy, equals('Nguyễn Văn A'));
      expect(reconstructed.device, equals('SEUIC UTouch 2 (PDA)'));
    });

    test('moveItemIndividual automatically records TagLifecycleAction.transferLocation', () async {
      final loc1 = Location(locationId: 'LOC-LIFECYCLE-1', locationCode: 'KỆ L1', zone: 'A', shelf: 'Kệ 1', level: '1');
      final loc2 = Location(locationId: 'LOC-LIFECYCLE-2', locationCode: 'KỆ L2', zone: 'B', shelf: 'Kệ 2', level: '1');
      await repo.addLocation(loc1);
      await repo.addLocation(loc2);

      const epc = 'E28068940000TESTLIFECYCLE1';
      final item = Item(
        itemId: 'ITEM-LC-001',
        productId: 'PROD-LC-001',
        sku: 'SKU-LC-001',
        productName: 'Mắt đọc hồng ngoại',
        serialNumber: 'SN-LC-001',
        epc: epc,
        status: ItemStatus.inStock,
        locationId: 'LOC-LIFECYCLE-1',
      );

      repo.createOrAssignPallet(
        palletCode: 'PL-LC-01',
        locationId: 'LOC-LIFECYCLE-1',
        newItems: [item],
      );

      final pallet2 = repo.createOrAssignPallet(
        palletCode: 'PL-LC-02',
        locationId: 'LOC-LIFECYCLE-2',
        newItems: [],
      );

      // Thực hiện điều chuyển item riêng lẻ
      final ok = await repo.moveItemIndividual(
        epc: epc,
        newLocationId: 'LOC-LIFECYCLE-2',
        newPalletId: pallet2.palletId,
        performedBy: 'Kỹ sư RFID',
      );
      expect(ok, isTrue);

      // Tra cứu lịch sử thẻ
      final logs = repo.getTagLifecycle(epc);
      expect(logs.isNotEmpty, isTrue);

      final transferLog = logs.firstWhere(
        (l) => l.action == TagLifecycleAction.transferLocation,
      );
      expect(transferLog.epc, equals(epc));
      expect(transferLog.sku, equals('SKU-LC-001'));
      expect(transferLog.fromLocation, equals('KỆ 1'));
      expect(transferLog.toLocation, equals('KỆ 2'));
      expect(transferLog.fromPallet, equals('PL-LC-01'));
      expect(transferLog.toPallet, equals('PL-LC-02'));
      expect(transferLog.performedBy, equals('Kỹ sư RFID'));
    });

    test('putawayPalletToLocation records TagLifecycleAction.putaway for all tags in pallet', () async {
      final locA = Location(locationId: 'LOC-PUTAWAY-1', locationCode: 'KỆ P1', zone: 'C', shelf: 'Kệ 1', level: '1');
      await repo.addLocation(locA);

      const epc1 = 'E2806894PUTAWAY001';
      const epc2 = 'E2806894PUTAWAY002';
      final it1 = Item(
        itemId: 'ITEM-PA-1',
        productId: 'P-PA-1',
        sku: 'SKU-PA-1',
        productName: 'Bo mạch UHF',
        serialNumber: 'SN-PA-1',
        epc: epc1,
        status: ItemStatus.waitingPutaway,
      );
      final it2 = Item(
        itemId: 'ITEM-PA-2',
        productId: 'P-PA-2',
        sku: 'SKU-PA-2',
        productName: 'Bo mạch UHF',
        serialNumber: 'SN-PA-2',
        epc: epc2,
        status: ItemStatus.waitingPutaway,
      );

      final pallet = repo.createOrAssignPallet(
        palletCode: 'PL-PUTAWAY-01',
        newItems: [it1, it2],
      );

      // Cất kệ pallet
      final ok = await repo.putawayPalletToLocation(
        palletCodeOrId: pallet.palletId,
        locationId: 'LOC-PUTAWAY-1',
        performedBy: 'Nhân viên A',
      );
      expect(ok, greaterThan(0));

      // Cả 2 thẻ đều phải có log putaway
      final logs1 = repo.getTagLifecycle(epc1);
      final logs2 = repo.getTagLifecycle(epc2);

      expect(logs1.any((l) => l.action == TagLifecycleAction.putaway), isTrue);
      expect(logs2.any((l) => l.action == TagLifecycleAction.putaway), isTrue);

      final paLog1 = logs1.firstWhere((l) => l.action == TagLifecycleAction.putaway);
      expect(paLog1.toLocation, equals('KỆ 1'));
      expect(paLog1.toPallet, equals('PL-PUTAWAY-01'));
      expect(paLog1.performedBy, equals('Nhân viên A'));
    });

    test('confirmDirectOutbound records TagLifecycleAction.outboundGate and status out', () async {
      final locOb = Location(locationId: 'LOC-OB-1', locationCode: 'KỆ XUẤT 1', zone: 'OUT', shelf: 'Kệ 1', level: '1');
      await repo.addLocation(locOb);

      const epc = 'E2806894OUTBOUND001';
      final item = Item(
        itemId: 'ITEM-OB-1',
        productId: 'P-OB-1',
        sku: 'SKU-OB-1',
        productName: 'Ăng-ten định hướng',
        serialNumber: 'SN-OB-1',
        epc: epc,
        status: ItemStatus.inStock,
        orderNo: 'ORD-OUT-999',
        locationId: 'LOC-OB-1',
      );

      repo.createOrAssignPallet(
        palletCode: 'PL-OB-01',
        locationId: 'LOC-OB-1',
        newItems: [item],
      );

      // Xuất kho trực tiếp
      final count = await repo.confirmDirectOutbound(
        poNo: 'ORD-OUT-999',
        scannedEpcs: [epc],
        performedBy: 'Thủ kho Cổng',
      );
      expect(count, equals(1));

      final logs = repo.getTagLifecycle(epc);
      expect(logs.any((l) => l.action == TagLifecycleAction.outboundGate), isTrue);
      final outLog = logs.firstWhere((l) => l.action == TagLifecycleAction.outboundGate);

      expect(outLog.action, equals(TagLifecycleAction.outboundGate));
      expect(outLog.newStatus, equals(ItemStatus.out.label));
      expect(outLog.documentNo, equals('ORD-OUT-999'));
    });

    test('getTagLifecycle fallback reconstructs timeline from Item historical fields when no logs exist', () {
      const epc = 'E2806894FALLBACK001';
      final inboundDate = DateTime.now().subtract(const Duration(days: 3));
      final item = Item(
        itemId: 'ITEM-FB-1',
        productId: 'P-FB-1',
        sku: 'SKU-FB-1',
        productName: 'Bộ nguồn công nghiệp',
        serialNumber: 'SN-FB-1',
        epc: epc,
        status: ItemStatus.inStock,
        inboundTime: inboundDate,
        inboundBy: 'Nguyễn Văn Kiểm',
        putawayBy: 'Trần Văn Kệ',
        orderNo: 'PO-2026-IMPORT',
        locationId: 'KỆ C1',
      );

      repo.createOrAssignPallet(
        palletCode: 'PL-FB-01',
        locationId: 'KỆ C1',
        newItems: [item],
      );

      // Gọi getTagLifecycle khi chưa có bản ghi nào trong DatabaseService
      final logs = repo.getTagLifecycle(epc);
      expect(logs.isNotEmpty, isTrue);

      // Phải có sự kiện nhập kho từ inboundTime
      expect(logs.any((l) => l.action == TagLifecycleAction.inboundGate), isTrue);
      final ibLog = logs.firstWhere((l) => l.action == TagLifecycleAction.inboundGate);
      expect(ibLog.performedBy, equals('Nguyễn Văn Kiểm'));
      expect(ibLog.documentNo, equals('PO-2026-IMPORT'));

      // Phải có sự kiện cất kệ từ putawayBy
      expect(logs.any((l) => l.action == TagLifecycleAction.putaway), isTrue);
      final paLog = logs.firstWhere((l) => l.action == TagLifecycleAction.putaway);
      expect(paLog.performedBy, equals('Trần Văn Kệ'));
      expect(paLog.toLocation, equals('KỆ C1'));
    });

    test('Tracking tag lifecycle through multiple shelves, warehouses, and pallets preserves initial putaway and all move transitions', () async {
      final locA1 = Location(locationId: 'LOC-A1-MULTI', locationCode: 'KỆ A1', zone: 'KHO 1', shelf: 'Kệ A1', level: '1');
      final locB2 = Location(locationId: 'LOC-B2-MULTI', locationCode: 'KỆ B2', zone: 'KHO 2', shelf: 'Kệ B2', level: '1');
      final locC3 = Location(locationId: 'LOC-C3-MULTI', locationCode: 'KỆ C3', zone: 'KHO 2', shelf: 'Kệ C3', level: '1');
      await repo.addLocation(locA1);
      await repo.addLocation(locB2);
      await repo.addLocation(locC3);

      const epc = 'E2806894MULTIHOP001';
      final item = Item(
        itemId: 'ITEM-MULTI-01',
        productId: 'P-MULTI-01',
        sku: 'SKU-MULTI-01',
        productName: 'Cảm biến rung công nghiệp',
        serialNumber: 'SN-MULTI-01',
        epc: epc,
        status: ItemStatus.waitingPutaway,
      );

      final pallet1 = repo.createOrAssignPallet(
        palletCode: 'PL-INIT-01',
        locationId: 'LOC-A1-MULTI',
        newItems: [item],
      );

      // 1. Cất vào Kệ ban đầu (KỆ A1, Pallet PL-INIT-01)
      await repo.putawayPalletToLocation(
        palletCodeOrId: pallet1.palletCode,
        locationId: 'LOC-A1-MULTI',
        performedBy: 'Thủ kho A',
      );

      // 2. Chuyển sang Kệ B2 (Kho 2) và đổi sang Pallet PL-HOP-02
      final pallet2 = repo.createOrAssignPallet(
        palletCode: 'PL-HOP-02',
        locationId: 'LOC-B2-MULTI',
        newItems: [],
      );
      await repo.moveItemIndividual(
        epc: epc,
        newLocationId: 'LOC-B2-MULTI',
        newPalletId: pallet2.palletId,
        performedBy: 'Kỹ thuật viên B',
      );

      // 3. Chuyển tiếp cả Pallet PL-HOP-02 sang Kệ C3 (Kho 2)
      await repo.transferPalletToLocation(
        palletEpc: pallet2.palletCode,
        newLocationId: 'LOC-C3-MULTI',
        performedBy: 'Thủ kho C',
      );

      // Kiểm tra chuỗi tóm tắt vòng đời
      final summary = repo.getTagLifecycleSummary(epc, multiline: true);

      // Bước 1 phải ghi rõ cất vào kệ A1
      expect(summary.contains('Cất vào Kệ [KỆ A1 (KHO 1)] (Pallet: PL-INIT-01)'), isTrue, reason: 'Phải ghi rõ cất vào Kệ A1');
      // Bước 2 ghi rõ chuyển vị trí và đổi Pallet
      expect(summary.contains('Chuyển vị trí [KỆ A1 (KHO 1) → KỆ B2 (KHO 2)] (Pallet: PL-INIT-01 → PL-HOP-02)'), isTrue, reason: 'Phải thể hiện chi tiết vị trí cũ sang mới và pallet');
      // Bước 3 ghi rõ chuyển Pallet sang Kệ C3
      expect(summary.contains('Chuyển vị trí [KỆ B2 (KHO 2) → KỆ C3 (KHO 2)] (Pallet: PL-HOP-02)'), isTrue, reason: 'Phải ghi nhận bước chuyển pallet sang kệ C3');
      // Kiểm tra xuống dòng cho từng mốc
      final lines = summary.split('\n');
      expect(lines.length, greaterThanOrEqualTo(3));
    });
  });
}
