import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDA Barcode Location Scanner Tests', () {
    test('UhfService onBarcodeRead stream and injectBarcode work correctly', () async {
      final uhf = UhfService();
      String? receivedBarcode;

      final sub = uhf.onBarcodeRead.listen((barcode) {
        receivedBarcode = barcode;
      });

      uhf.injectBarcode('LOC-A1-01-01');
      await Future.delayed(const Duration(milliseconds: 50));

      expect(receivedBarcode, equals('LOC-A1-01-01'));
      await sub.cancel();
    });

    test('Location lookup by barcode and auto-creation in WarehouseRepository', () async {
      final repo = WarehouseRepository();
      const testBarcode = 'LOC-ZONE-C-02';

      // Verify location lookup or add
      final existing = repo.locations.where((l) => l.locationCode == testBarcode).firstOrNull;
      if (existing == null) {
        final newLoc = Location(
          locationId: 'LOC-$testBarcode',
          locationCode: testBarcode,
          zone: 'Zone C',
          shelf: 'Kệ 02',
          level: 'Tầng 1',
        );
        await repo.addLocation(newLoc);
      }

      final matched = repo.locations.where((l) => l.locationCode == testBarcode).firstOrNull;
      expect(matched, isNotNull);
      expect(matched!.locationCode, equals(testBarcode));
      expect(matched.zone, equals('Zone C'));
    });
  });
}
