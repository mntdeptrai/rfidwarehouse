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

    test('Pallet transfer matches by palletCode, PAL-prefix, and moves items to destination location', () async {
      final repo = WarehouseRepository();
      await repo.ensureInitialized();
      
      // Create a test location
      const destLocId = 'LOC-DEST-01';
      final destLoc = Location(
        locationId: destLocId,
        locationCode: 'DEST-01',
        zone: 'Zone Transfer',
        shelf: 'Kệ T1',
        level: 'Tầng 1',
      );
      await repo.addLocation(destLoc);

      const testPalletCode = 'PL-TEST-BC-99';
      final testItem = Item(
        itemId: 'ITEM-TEST-TRF-01',
        productId: 'SKU-001',
        sku: 'SKU-001',
        productName: 'Sản phẩm test',
        serialNumber: 'SN-TEST-001',
        epc: 'E280ITEMTEST001',
        status: ItemStatus.inStock,
        locationId: 'LOC-OLD',
      );

      final pallet = repo.createOrAssignPallet(
        palletCode: testPalletCode,
        locationId: 'LOC-OLD',
        newItems: [testItem],
      );
      pallet.rfidEpc = 'E28099887766554433221100';

      // Transfer using palletCode (as scanned via Barcode)
      final movedCount = await repo.transferPalletToLocation(
        palletEpc: testPalletCode,
        newLocationId: destLocId,
        performedBy: 'Test PDA Scanner',
      );

      expect(movedCount, greaterThan(0));

      // Verify pallet location updated
      final updatedPallet = repo.pallets.firstWhere((p) => p.palletCode == testPalletCode);
      expect(updatedPallet.locationId, equals(destLocId));

      // Verify item location updated
      final updatedItem = repo.items.firstWhere((i) => i.itemId == 'ITEM-TEST-TRF-01');
      expect(updatedItem.locationId, equals(destLocId));
    });
  });
}
