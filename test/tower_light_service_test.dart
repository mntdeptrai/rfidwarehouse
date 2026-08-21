import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/services/tower_light_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TowerLightService Tests (CTP50-3T-D-J)', () {
    late TowerLightService service;

    setUp(() {
      service = TowerLightService();
      service.hardwareControlEnabled = false; // Disable direct socket sending during unit test
    });

    test('Initial state is off / standby', () {
      expect(service.currentStatus.color, TowerLightColor.off);
      expect(service.currentStatus.isBuzzerOn, false);
      expect(service.currentStatus.isOff, true);
    });

    test('🟢 triggerPass sets GREEN signal for full order match', () async {
      await service.triggerPass(reason: 'Đủ hàng 10/10 chip thông qua');
      expect(service.currentStatus.color, TowerLightColor.green);
      expect(service.currentStatus.isGreen, true);
      expect(service.currentStatus.isRed, false);
      expect(service.currentStatus.isYellow, false);
      expect(service.currentStatus.isBuzzerOn, false);
      expect(service.currentStatus.reason, contains('Đủ hàng 10/10'));
    });

    test('🔴 triggerWarningRed sets RED signal + buzzer for wrong/missing items', () async {
      await service.triggerWarningRed(
        withBuzzer: true,
        reason: 'Phát hiện sai hàng: Mã lạ',
      );
      expect(service.currentStatus.color, TowerLightColor.red);
      expect(service.currentStatus.isRed, true);
      expect(service.currentStatus.isGreen, false);
      expect(service.currentStatus.isBuzzerOn, true);
      expect(service.currentStatus.reason, contains('sai hàng'));
    });

    test('🟡 triggerSystemError sets YELLOW signal for component failures', () async {
      await service.triggerSystemError(
        componentName: 'Đầu đọc UHF RFID (Mất kết nối COM3)',
      );
      expect(service.currentStatus.color, TowerLightColor.yellow);
      expect(service.currentStatus.isYellow, true);
      expect(service.currentStatus.isRed, false);
      expect(service.currentStatus.isGreen, false);
      expect(service.currentStatus.isBuzzerOn, false);
      expect(service.currentStatus.reason, contains('Lỗi hệ thống'));
    });

    test('turnOffAll returns tower to standby state', () async {
      await service.triggerPass();
      expect(service.currentStatus.color, TowerLightColor.green);

      await service.turnOffAll(reason: 'Chờ lệnh mới');
      expect(service.currentStatus.color, TowerLightColor.off);
      expect(service.currentStatus.isBuzzerOn, false);
      expect(service.currentStatus.reason, 'Chờ lệnh mới');
    });

    test('manualTest properly sets requested signals and reasons', () async {
      await service.manualTest(color: TowerLightColor.red, buzzer: true);
      expect(service.currentStatus.color, TowerLightColor.red);
      expect(service.currentStatus.isBuzzerOn, true);

      await service.manualTest(color: TowerLightColor.yellow, buzzer: false);
      expect(service.currentStatus.color, TowerLightColor.yellow);
      expect(service.currentStatus.isBuzzerOn, false);

      await service.manualTest(color: TowerLightColor.green, buzzer: false);
      expect(service.currentStatus.color, TowerLightColor.green);
    });

    test('Pin config defaults and customizations are maintained', () {
      expect(service.config.redPin, 4);
      expect(service.config.yellowPin, 2);
      expect(service.config.greenPin, 3);
      expect(service.config.buzzerPin, 1);

      service.config.redPin = 2;
      service.config.yellowPin = 1;
      expect(service.config.redPin, 2);
      expect(service.config.yellowPin, 1);

      // Restore defaults
      service.config.redPin = 4;
      service.config.yellowPin = 2;
    });
  });
}
