import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/inbound_demo_service.dart';
import 'package:uhf/services/tower_light_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InboundDemoScenarioService Tests', () {
    test('EPCs for Rack Units and Metal Boxes are normalized and exact', () {
      expect(InboundDemoScenarioService.rackUnit.fixedEpcs.length, 3);
      expect(InboundDemoScenarioService.metalBox.fixedEpcs.length, 10);

      // Verify the normalized rack EPC with '0' instead of 'O'
      expect(
        InboundDemoScenarioService.normalizeEpc('E28011COA500006673BC32E3'),
        'E28011C0A500006673BC32E3',
      );

      // Verify all 3 Rack EPCs
      expect(InboundDemoScenarioService.rackUnit.fixedEpcs, [
        'E28011C0A500006673BC32E3',
        'E28011C0A500006673BC6213',
        'E28011C0A500006673BC6223',
      ]);

      // Verify all 10 Metal Box EPCs
      expect(InboundDemoScenarioService.metalBox.fixedEpcs, [
        'E280689400005024B0765C5A',
        'E280689400005024B0765C5C',
        'E280689400004024B0765C5B',
        'E280689400004024B0765C5D',
        'E280689400004024B0765C5E',
        'E280689400005024B0765C5F',
        'E280689400005024B0765C60',
        'E280689400004024B0765C61',
        'E280689400004024B0765C62',
        'E280689400005024B0765C63',
      ]);
    });

    test('buildDemoPackage generates full 13 items with correct details', () {
      final pkg = InboundDemoScenarioService.buildDemoPackage(
        orderNo: 'NK-TEST-001',
        supplier: 'Công ty Nhật Minh',
        palletCode: 'PL01',
        rackQty: 3,
        boxQty: 10,
      );

      expect(pkg.order.orderNo, 'NK-TEST-001');
      expect(pkg.items.length, 13);
      expect(pkg.products.length, 2);
      expect(pkg.order.details.length, 2);
      expect(pkg.palletCode, 'PL01');

      // 3 rack items
      final rackItems = pkg.items.where((i) => i.sku == InboundDemoScenarioService.rackUnit.sku).toList();
      expect(rackItems.length, 3);
      expect(rackItems.map((i) => i.epc).toList(), InboundDemoScenarioService.rackUnit.fixedEpcs);

      // 10 metal box items
      final boxItems = pkg.items.where((i) => i.sku == InboundDemoScenarioService.metalBox.sku).toList();
      expect(boxItems.length, 10);
      expect(boxItems.map((i) => i.epc).toList(), InboundDemoScenarioService.metalBox.fixedEpcs);

      // All items should have pendingInbound status
      for (final item in pkg.items) {
        expect(item.status, ItemStatus.pendingInbound);
        expect(item.orderNo, 'NK-TEST-001');
        expect(item.palletId, 'PL01');
      }
    });

    test('buildDemoPackage handles custom quantities correctly', () {
      final pkg = InboundDemoScenarioService.buildDemoPackage(
        orderNo: 'NK-CUSTOM-02',
        rackQty: 1,
        boxQty: 4,
      );

      expect(pkg.items.length, 5);
      expect(pkg.items.where((i) => i.sku == InboundDemoScenarioService.rackUnit.sku).length, 1);
      expect(pkg.items.where((i) => i.sku == InboundDemoScenarioService.metalBox.sku).length, 4);
    });

    test('saveDemoPackageToRepository persists directly into In-Memory WarehouseRepository', () async {
      final repo = WarehouseRepository();
      final pkg = InboundDemoScenarioService.buildDemoPackage(
        orderNo: 'NK-REPO-TEST',
        palletCode: 'PL99',
        rackQty: 2,
        boxQty: 3,
      );

      await InboundDemoScenarioService.saveDemoPackageToRepository(repo, pkg);

      expect(repo.inboundOrders.any((o) => o.orderNo == 'NK-REPO-TEST'), isTrue);
      final savedItems = repo.items.where((i) => i.orderNo == 'NK-REPO-TEST').toList();
      expect(savedItems.length, 5);
      expect(repo.pallets.any((p) => p.palletCode == 'PL99'), isTrue);
      expect(repo.products.any((p) => p.sku == InboundDemoScenarioService.rackUnit.sku), isTrue);
      expect(repo.products.any((p) => p.sku == InboundDemoScenarioService.metalBox.sku), isTrue);
    });
  });

  group('Inbound TowerLight Integration Tests', () {
    late TowerLightService towerLight;

    setUp(() {
      towerLight = TowerLightService();
      towerLight.hardwareControlEnabled = false; // Mock mode for unit tests
      towerLight.turnOffAll();
    });

    test('Triggering scanning sets yellow light without buzzer', () async {
      await towerLight.triggerScanning(reason: 'Đang quét đối soát cổng nhập kho');

      expect(towerLight.currentStatus.color, TowerLightColor.yellow);
      expect(towerLight.currentStatus.isBuzzerOn, isFalse);
      expect(towerLight.currentStatus.isOff, isFalse);
      expect(towerLight.currentStatus.reason, contains('Đang quét đối soát'));
    });

    test('Triggering unexpected tag alert sets red light and buzzer', () async {
      await towerLight.triggerWarningRed(
        withBuzzer: true,
        reason: 'CẢNH BÁO: Phát hiện chip lạ ngoài đơn nhập!',
        persistent: true,
      );

      expect(towerLight.currentStatus.color, TowerLightColor.red);
      expect(towerLight.currentStatus.isBuzzerOn, isTrue);
      expect(towerLight.currentStatus.reason, contains('chip lạ'));
    });

    test('Silencing buzzer retains red color and turns buzzer off', () async {
      await towerLight.triggerWarningRed(
        withBuzzer: true,
        reason: 'CẢNH BÁO: Phát hiện chip lạ',
        persistent: true,
      );
      expect(towerLight.currentStatus.isBuzzerOn, isTrue);

      await towerLight.silenceBuzzerOnly();
      expect(towerLight.currentStatus.color, TowerLightColor.red);
      expect(towerLight.currentStatus.isBuzzerOn, isFalse);
      expect(towerLight.currentStatus.reason, contains('Đã tắt còi'));
    });

    test('Triggering pass sets green light without buzzer', () async {
      await towerLight.triggerPass(reason: 'Đã nhận diện đủ sản phẩm cho Pallet PL01');

      expect(towerLight.currentStatus.color, TowerLightColor.green);
      expect(towerLight.currentStatus.isBuzzerOn, isFalse);
      expect(towerLight.currentStatus.reason, contains('Pallet PL01'));
    });

    test('TurnOffAll resets tower light to standby', () async {
      await towerLight.triggerPass();
      expect(towerLight.currentStatus.isOff, isFalse);

      await towerLight.turnOffAll(reason: 'Sẵn sàng chờ cổng nhập kho');
      expect(towerLight.currentStatus.color, TowerLightColor.off);
      expect(towerLight.currentStatus.isBuzzerOn, isFalse);
      expect(towerLight.currentStatus.isOff, isTrue);
    });
  });
}
