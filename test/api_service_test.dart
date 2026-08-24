import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Supabase ApiService Realtime Tests', () {
    test('ApiService singleton and Realtime Broadcast Event Bus', () async {
      final api = ApiService();
      expect(api, isNotNull);

      // Test Realtime Gate Pass Event Stream
      GateRealtimeEvent? receivedEvent;
      final sub = api.onGateEvent.listen((e) {
        receivedEvent = e;
      });

      final testEvent = GateRealtimeEvent(
        orderNo: 'INB-TEST-001',
        epcs: ['E28011600000000000000001', 'E28011600000000000000002'],
        passType: 'INBOUND',
        isPass: true,
        message: 'Gate Pass OK',
        timestamp: DateTime.now(),
      );

      await api.broadcastGatePass(testEvent);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(receivedEvent, isNotNull);
      expect(receivedEvent!.orderNo, equals('INB-TEST-001'));
      expect(receivedEvent!.epcs.length, equals(2));
      expect(receivedEvent!.isPass, isTrue);

      await sub.cancel();
    });

    test('ApiService Putaway Realtime Event Broadcast', () async {
      final api = ApiService();

      PutawayRealtimeEvent? putawayEvent;
      final sub = api.onPutawayEvent.listen((e) {
        putawayEvent = e;
      });

      final event = PutawayRealtimeEvent(
        palletCode: 'PL-TEST-99',
        locationCode: 'A-01-01',
        itemCount: 24,
        performedBy: 'Thủ kho Test',
        timestamp: DateTime.now(),
      );

      await api.broadcastPutaway(event);
      await Future.delayed(const Duration(milliseconds: 10));

      expect(putawayEvent, isNotNull);
      expect(putawayEvent!.palletCode, equals('PL-TEST-99'));
      expect(putawayEvent!.locationCode, equals('A-01-01'));
      expect(putawayEvent!.itemCount, equals(24));

      await sub.cancel();
    });
  });
}
