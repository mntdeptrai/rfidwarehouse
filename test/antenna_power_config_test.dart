import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/uhf_connection_config.dart';
import 'package:uhf/services/desktop_uhf_tcp_service.dart';
import 'package:uhf/services/uhf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Antenna RF Power Configuration Tests', () {
    test('UhfConnectionConfig defaults antennaPowers to 30 dBm for 4 antennas', () {
      final config = UhfConnectionConfig();
      expect(config.antennaPowers, isNotEmpty);
      expect(config.antennaPowers[1], equals(30));
      expect(config.antennaPowers[2], equals(30));
      expect(config.antennaPowers[3], equals(30));
      expect(config.antennaPowers[4], equals(30));
      expect(config.rfPower, equals(30));
    });

    test('UhfConnectionConfig serialization and deserialization preserves per-antenna powers', () {
      final config = UhfConnectionConfig(
        rfPower: 26,
        antennaPowers: {1: 18, 2: 24, 3: 30, 4: 33},
      );

      final json = config.toJson();
      expect(json['antennaPowers'], isA<Map<String, dynamic>>());
      expect(json['antennaPowers']['1'], equals(18));
      expect(json['antennaPowers']['4'], equals(33));

      final restored = UhfConnectionConfig.fromJson(json);
      expect(restored.antennaPowers[1], equals(18));
      expect(restored.antennaPowers[2], equals(24));
      expect(restored.antennaPowers[3], equals(30));
      expect(restored.antennaPowers[4], equals(33));
      expect(restored.rfPower, equals(26));
    });

    test('UhfConnectionConfig fallback deserialization when antennaPowers is absent', () {
      final json = {
        'rfPower': 22,
      };

      final restored = UhfConnectionConfig.fromJson(json);
      expect(restored.antennaPowers[1], equals(22));
      expect(restored.antennaPowers[2], equals(22));
      expect(restored.antennaPowers[3], equals(22));
      expect(restored.antennaPowers[4], equals(22));
    });

    test('DesktopUhfTcpService setAntennaPower and helper methods', () async {
      final service = DesktopUhfTcpService();

      // Test setAllAntennasPower
      await service.setAllAntennasPower(25);
      expect(service.getAntennaPower(1), equals(25));
      expect(service.getAntennaPower(2), equals(25));
      expect(service.getAntennaPower(3), equals(25));
      expect(service.getAntennaPower(4), equals(25));
      expect(service.config.rfPower, equals(25));

      // Test setSingleAntennaPower
      await service.setSingleAntennaPower(2, 18);
      expect(service.getAntennaPower(1), equals(25));
      expect(service.getAntennaPower(2), equals(18));
      expect(service.getAntennaPower(3), equals(25));
      expect(service.getAntennaPower(4), equals(25));

      // Test setAntennaPower dictionary
      await service.setAntennaPower({1: 10, 2: 20, 3: 30, 4: 33});
      expect(service.getAntennaPower(1), equals(10));
      expect(service.getAntennaPower(2), equals(20));
      expect(service.getAntennaPower(3), equals(30));
      expect(service.getAntennaPower(4), equals(33));
    });

    test('UhfService setRfPower boundary checks (1 to 33 dBm)', () async {
      final uhf = UhfService();

      // Below lower bound
      final invalidLow = await uhf.setRfPower(0);
      expect(invalidLow, isFalse);

      // Above upper bound
      final invalidHigh = await uhf.setRfPower(34);
      expect(invalidHigh, isFalse);

      // Valid range in test environment (FLUTTER_TEST active)
      final valid = await uhf.setRfPower(28);
      expect(valid, isTrue);
      expect(uhf.rfPower, equals(28));
    });
  });
}
