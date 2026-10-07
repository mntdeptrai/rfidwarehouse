import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/tower_light_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Outbound Tower Light Alert & Signal Logic Tests', () {
    late TowerLightService towerLight;
    late WarehouseRepository repo;

    setUp(() async {
      towerLight = TowerLightService();
      towerLight.hardwareControlEnabled = false; // Disable physical TCP sockets during test
      await towerLight.turnOffAll();

      repo = WarehouseRepository();
      await repo.ensureInitialized();
    });

    test('1. Bắt đầu quét đối soát cổng xuất kích hoạt ĐÈN VÀNG', () async {
      // Khi nhấn Bắt đầu quét cổng xuất
      await towerLight.triggerScanning(
        reason: 'ĐANG QUÉT XUẤT KHO: Tay cầm PDA/Cổng RFID đang quét đối soát...',
      );

      expect(towerLight.currentStatus.color, TowerLightColor.yellow);
      expect(towerLight.currentStatus.isYellow, isTrue);
      expect(towerLight.currentStatus.isRed, isFalse);
      expect(towerLight.currentStatus.isGreen, isFalse);
      expect(towerLight.currentStatus.isBuzzerOn, isFalse);
      expect(towerLight.currentStatus.reason, contains('ĐANG QUÉT XUẤT KHO'));
    });

    test('2. Phát hiện chip lạ ngoài đơn xuất kích hoạt ĐÈN ĐỎ + CÒI BÁO (Buzzer)', () async {
      final unexpectedEpcs = ['E2801191UNEXPECTED01', 'E2801191UNEXPECTED02'];

      // Khi đối soát phát hiện chip lạ
      if (unexpectedEpcs.isNotEmpty) {
        await towerLight.triggerWarningRed(
          withBuzzer: true,
          reason: 'CẢNH BÁO: Phát hiện ${unexpectedEpcs.length} chip lạ ngoài danh sách xuất kho!',
        );
      }

      expect(towerLight.currentStatus.color, TowerLightColor.red);
      expect(towerLight.currentStatus.isRed, isTrue);
      expect(towerLight.currentStatus.isBuzzerOn, isTrue);
      expect(towerLight.currentStatus.reason, contains('Phát hiện 2 chip lạ ngoài danh sách xuất kho'));
    });

    test('3. Vi phạm nguyên tắc FIFO (lấy nhầm lô mới trước) kích hoạt ĐÈN ĐỎ (cảnh báo)', () async {
      final now = DateTime.now();
      final oldItem = Item(
        itemId: 'ITEM-OLD-01',
        productId: 'SKU-WATER-01',
        sku: 'SKU-WATER-01',
        productName: 'Nước Lavie Thùng Cũ',
        serialNumber: 'SN-OLD-01',
        epc: 'E2801191000000000000OLD1',
        status: ItemStatus.inStock,
        locationId: 'LOC-A1',
        inboundTime: now.subtract(const Duration(days: 15)),
      );

      final newItem = Item(
        itemId: 'ITEM-NEW-01',
        productId: 'SKU-WATER-01',
        sku: 'SKU-WATER-01',
        productName: 'Nước Lavie Thùng Mới',
        serialNumber: 'SN-NEW-01',
        epc: 'E2801191000000000000NEW1',
        status: ItemStatus.inStock,
        locationId: 'LOC-B2',
        inboundTime: now,
      );

      await repo.insertDirectItems([oldItem, newItem]);

      // Giả sử thủ kho quét newItem trước khi oldItem được quét
      final scannedEpc = newItem.epc;
      final olderUnscanned = [oldItem];

      if (scannedEpc == newItem.epc && olderUnscanned.isNotEmpty) {
        await towerLight.triggerWarningRed(
          withBuzzer: false,
          reason: 'LƯU Ý FIFO: Quét lô mới của ${newItem.sku}. Cần lấy lô cũ trước tại kệ LOC-A1!',
        );
      }

      expect(towerLight.currentStatus.color, TowerLightColor.red);
      expect(towerLight.currentStatus.isRed, isTrue);
      expect(towerLight.currentStatus.isBuzzerOn, isFalse); // FIFO cảnh báo không hú còi inh ỏi
      expect(towerLight.currentStatus.reason, contains('LƯU Ý FIFO'));
      expect(towerLight.currentStatus.reason, contains('LOC-A1'));
    });

    test('4. Quét đủ 100% danh sách hàng xuất kích hoạt ĐÈN XANH (Thông qua cổng)', () async {
      const totalExpected = 5;
      const scannedMatching = 5;

      if (totalExpected > 0 && scannedMatching >= totalExpected) {
        await towerLight.triggerPass(
          reason: 'ĐỦ HÀNG XUẤT KHO: $scannedMatching/$totalExpected sản phẩm đã thông qua cổng RFID!',
        );
      }

      expect(towerLight.currentStatus.color, TowerLightColor.green);
      expect(towerLight.currentStatus.isGreen, isTrue);
      expect(towerLight.currentStatus.isRed, isFalse);
      expect(towerLight.currentStatus.isBuzzerOn, isFalse);
      expect(towerLight.currentStatus.reason, contains('ĐỦ HÀNG XUẤT KHO: 5/5'));
    });

    test('5. Dừng phiên quét đối soát chuyển đèn về trạng thái STANDBY (TẮT)', () async {
      // Đang xanh
      await towerLight.triggerPass();
      expect(towerLight.currentStatus.color, TowerLightColor.green);

      // Nhấn dừng quét
      await towerLight.turnOffAll(reason: 'Đã dừng quét xuất kho trên PDA');

      expect(towerLight.currentStatus.color, TowerLightColor.off);
      expect(towerLight.currentStatus.isOff, isTrue);
      expect(towerLight.currentStatus.isBuzzerOn, isFalse);
      expect(towerLight.currentStatus.reason, 'Đã dừng quét xuất kho trên PDA');
    });

    test('6. Hoàn tất xuất kho thành công kích hoạt ĐÈN XANH xác nhận xuất hàng', () async {
      const shippedCount = 12;
      await towerLight.triggerPass(
        reason: 'XUẤT THÀNH CÔNG: $shippedCount sản phẩm đã đối soát và cập nhật hệ thống!',
      );

      expect(towerLight.currentStatus.color, TowerLightColor.green);
      expect(towerLight.currentStatus.isGreen, isTrue);
      expect(towerLight.currentStatus.reason, contains('XUẤT THÀNH CÔNG: 12 sản phẩm'));
    });

    test('7. Người mang hàng ngoài đơn xuất khớp hàng trong kho: Báo động Đỏ + Còi chỉ rõ Tên SP & SKU', () async {
      final unexpItem = Item(
        itemId: 'ITEM-UNEXP-99',
        productId: 'SKU-UNEXP-99',
        sku: 'SKU-UNEXP-99',
        productName: 'Bánh Custas Hộp 12 Gói',
        serialNumber: 'SN-UNEXP-99',
        epc: 'E2801191000000000UNEXP99',
        status: ItemStatus.inStock,
        locationId: 'LOC-C3',
      );
      await repo.insertDirectItems([unexpItem]);

      // Giả sử quét được chip của unexpItem ngoài đơn xuất
      final unexpected = [unexpItem.epc];
      final matchedInRepo = unexpected
          .map((u) => repo.items.where((i) => i.epc.toUpperCase() == u).firstOrNull)
          .whereType<Item>()
          .toList();

      expect(matchedInRepo.isNotEmpty, isTrue);
      final firstItem = matchedInRepo.first;
      final reasonText = 'CẢNH BÁO AN NINH: Hàng không nằm trong đơn xuất! [${firstItem.productName}] (SKU: ${firstItem.sku}, Kệ: ${firstItem.locationId})';

      await towerLight.triggerWarningRed(
        withBuzzer: true,
        reason: reasonText,
        persistent: true,
      );

      expect(towerLight.currentStatus.color, TowerLightColor.red);
      expect(towerLight.currentStatus.isBuzzerOn, isTrue);
      expect(towerLight.currentStatus.reason, contains('Bánh Custas Hộp 12 Gói'));
      expect(towerLight.currentStatus.reason, contains('SKU-UNEXP-99'));
      expect(towerLight.currentStatus.reason, contains('LOC-C3'));
    });

    test('8. Báo động chip lạ duy trì liên tục (persistent) và reset khi loại bỏ chip lạ', () async {
      await towerLight.triggerWarningRed(
        withBuzzer: true,
        reason: 'CẢNH BÁO: Hàng lạ tại cổng',
        persistent: true,
      );

      // Đợi ngắn hơn pulseDuration
      expect(towerLight.currentStatus.isRed, isTrue);
      expect(towerLight.currentStatus.isBuzzerOn, isTrue);

      // Khi người vận hành đưa hàng lạ ra ngoài và bấm xóa chip lạ:
      await towerLight.triggerScanning(reason: 'Đã loại bỏ chip lạ. Tiếp tục đối soát cổng...');

      expect(towerLight.currentStatus.color, TowerLightColor.yellow);
      expect(towerLight.currentStatus.isYellow, isTrue);
      expect(towerLight.currentStatus.isBuzzerOn, isFalse);
      expect(towerLight.currentStatus.reason, contains('Đã loại bỏ chip lạ'));
    });
  });
}
