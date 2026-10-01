import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/pda/pda_putaway_screen.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDA Putaway Barcode Scanning Workflow Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
      await repo.clearAllData(alsoClearCloud: false);

      // Thêm vị trí kệ
      await repo.addLocation(Location(
        locationId: 'LOC-SHELF-01',
        locationCode: 'LOC-SHELF-01',
        zone: 'Khu A',
        shelf: 'Kệ 01',
        level: 'Tầng 1',
      ));
      await repo.addLocation(Location(
        locationId: 'LOC-SHELF-02',
        locationCode: 'LOC-SHELF-02',
        zone: 'Khu B',
        shelf: 'Kệ 02',
        level: 'Tầng 1',
      ));

      // Thêm sản phẩm chờ cất cho 2 Pallet
      await repo.addItem(Item(
        itemId: 'ITEM-PA-001',
        productId: 'PROD-01',
        sku: 'SKU-PA-01',
        productName: 'Sản phẩm Pallet A',
        serialNumber: 'SN-PA-001',
        epc: 'E280PA000000000000000001',
        status: ItemStatus.waitingPutaway,
        palletId: 'PAL-SCAN-01',
      ));
      await repo.addItem(Item(
        itemId: 'ITEM-PA-002',
        productId: 'PROD-02',
        sku: 'SKU-PA-02',
        productName: 'Sản phẩm Pallet B',
        serialNumber: 'SN-PA-002',
        epc: 'E280PA000000000000000002',
        status: ItemStatus.waitingPutaway,
        palletId: 'PAL-SCAN-02',
      ));
    });

    tearDown(() async {
      await repo.clearAllData(alsoClearCloud: false);
    });

    testWidgets('Quét Barcode: Quét Pallet trước -> Quét Kệ sau -> Tự động cất hàng thành công', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PdaPutawayScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Ban đầu: Hiển thị 2 box quét barcode rõ ràng
      expect(find.textContaining('BÓP CÒ PDA ĐỂ QUÉT BARCODE PALLET'), findsOneWidget);
      expect(find.textContaining('BÓP CÒ PDA QUÉT MÃ NHÃN KỆ'), findsOneWidget);

      // Bước 1: Quét mã vạch Pallet PAL-SCAN-01
      UhfService().simulateBarcode('PAL-SCAN-01');
      await tester.pump(const Duration(milliseconds: 500));

      // Pallet được nhận diện với tick xanh
      expect(find.textContaining('PALLET ĐÃ QUÉT: PAL-SCAN-01'), findsOneWidget);
      expect(find.textContaining('PAL-SCAN-01 (1 sản phẩm)'), findsWidgets);

      // Bước 2: Quét mã nhãn kệ LOC-SHELF-01
      UhfService().simulateBarcode('LOC-SHELF-01');
      await tester.pump(const Duration(milliseconds: 800));

      // Hệ thống tự động xác nhận cất hàng thành công
      final updatedItem = repo.items.firstWhere((i) => i.itemId == 'ITEM-PA-001');
      expect(updatedItem.status, equals(ItemStatus.inStock));
      expect(updatedItem.locationId, equals('LOC-SHELF-01'));
    });

    testWidgets('Quét Barcode đảo chiều: Quét Kệ trước -> Quét Pallet sau -> Tự động cất hàng thành công', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PdaPutawayScreen(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      // Bước 1: Quét mã nhãn kệ LOC-SHELF-02 trước
      UhfService().simulateBarcode('LOC-SHELF-02');
      await tester.pump(const Duration(milliseconds: 500));

      // Kệ được nhận diện với tick xanh
      expect(find.textContaining('KỆ ĐÃ QUÉT: LOC-SHELF-02'), findsOneWidget);

      // Bước 2: Quét mã Pallet PAL-SCAN-02 sau
      UhfService().simulateBarcode('PAL-SCAN-02');
      await tester.pump(const Duration(milliseconds: 800));

      // Hệ thống tự động cất vào đúng kệ đã quét trước đó
      final updatedItem = repo.items.firstWhere((i) => i.itemId == 'ITEM-PA-002');
      expect(updatedItem.status, equals(ItemStatus.inStock));
      expect(updatedItem.locationId, equals('LOC-SHELF-02'));
    });
  });
}
