import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/pda/pda_merge_pallets_screen.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/uhf_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('PDA Pallet Consolidation / Auto-Merge Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
      await repo.clearAllData();
    });

    test('WarehouseRepository.mergePallets correctly moves items and updates locations', () async {
      // 1. Tạo 2 items cho Pallet A và 1 item cho Pallet B
      final item1 = Item(
        itemId: 'ITEM-M1',
        productId: 'PROD-1',
        sku: 'SKU-01',
        productName: 'Giày Thể Thao Nam',
        serialNumber: 'SN-001',
        epc: 'E28011000000000000000001',
        status: ItemStatus.inStock,
        locationId: 'LOC-A1',
      );
      final item2 = Item(
        itemId: 'ITEM-M2',
        productId: 'PROD-1',
        sku: 'SKU-01',
        productName: 'Giày Thể Thao Nam',
        serialNumber: 'SN-002',
        epc: 'E28011000000000000000002',
        status: ItemStatus.inStock,
        locationId: 'LOC-A1',
      );
      final item3 = Item(
        itemId: 'ITEM-M3',
        productId: 'PROD-2',
        sku: 'SKU-02',
        productName: 'Áo Thun Cổ Tròn',
        serialNumber: 'SN-003',
        epc: 'E28011000000000000000003',
        status: ItemStatus.inStock,
        locationId: 'LOC-B2',
      );

      // 2. Tạo 2 Pallet bằng createOrAssignPallet
      final palletA = repo.createOrAssignPallet(
        palletCode: 'PL-SRC-01',
        locationId: 'LOC-A1',
        newItems: [item1, item2],
      );
      final palletB = repo.createOrAssignPallet(
        palletCode: 'PL-DST-02',
        locationId: 'LOC-B2',
        newItems: [item3],
      );

      // 3. Thực hiện gộp Pallet A vào Pallet B
      final mergeSuccess = await repo.mergePallets(
        sourcePalletId: palletA.palletId,
        targetPalletId: palletB.palletId,
        performedBy: 'Thủ Kho Test PDA',
        deleteSourcePallet: false,
      );

      expect(mergeSuccess, isTrue);

      // 4. Kiểm tra dữ liệu sau gộp
      // Toàn bộ items của A đã chuyển sang B
      final updatedItem1 = repo.items.firstWhere((it) => it.itemId == 'ITEM-M1');
      final updatedItem2 = repo.items.firstWhere((it) => it.itemId == 'ITEM-M2');
      expect(updatedItem1.palletId, equals(palletB.palletId));
      expect(updatedItem2.palletId, equals(palletB.palletId));
      expect(updatedItem1.locationId, equals('LOC-B2')); // Chuyển theo vị trí kệ của Pallet B
      expect(updatedItem2.locationId, equals('LOC-B2'));

      // Pallet A đã rỗng và vẫn lưu giữ vị trí cập nhật lần cuối cùng của nó
      expect(palletA.itemIds.isEmpty, isTrue);
      expect(palletA.locationId, equals('LOC-A1'));

      // Pallet B chứa đủ 3 items (2 từ A + 1 của B)
      expect(palletB.itemIds.length, equals(3));
      expect(palletB.isMultiSku, isTrue); // Vì chứa cả SKU-01 và SKU-02

      // Kiểm tra nhật ký giao dịch
      final tx = repo.transactions.firstWhere((t) => t.transactionId.startsWith('TX-MERGE'));
      expect(tx.type, equals(TransactionType.movement));
      expect(tx.performedBy, equals('Thủ Kho Test PDA'));
      expect(tx.quantity, equals(2));
    });

    testWidgets('PdaMergePalletsScreen renders without overflow and shows auto-merge mode', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PdaMergePalletsScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('GỘP 2 PALLET (PDA)'), findsOneWidget);
      expect(find.textContaining('BƯỚC 1/2: Bóp cò súng PDA'), findsOneWidget);
      expect(find.textContaining('1. PALLET NGUỒN (A)'), findsOneWidget);
      expect(find.textContaining('2. PALLET ĐÍCH (B)'), findsOneWidget);
      expect(find.text('TỰ ĐỘNG GỘP PALLET:'), findsOneWidget);
      expect(find.text('HOẠT ĐỘNG ⚡'), findsOneWidget);
      expect(find.text('QUY TẮC MẶC ĐỊNH SAU GỘP:'), findsNothing);
      expect(UhfService().scanMode, equals(PdaScanMode.barcode));
    });

    testWidgets('PdaMergePalletsScreen automatically merges pallets immediately upon scanning 2 pallets', (WidgetTester tester) async {
      // Chuẩn bị dữ liệu 2 pallet
      final itemA = Item(
        itemId: 'ITEM-AUTO-1',
        productId: 'PROD-AUTO-1',
        sku: 'SKU-AUTO-1',
        productName: 'Sản phẩm gộp tự động',
        serialNumber: 'SN-AUTO-01',
        epc: 'E28099000000000000000001',
        status: ItemStatus.inStock,
        locationId: 'LOC-AUTO-A',
      );
      final itemB = Item(
        itemId: 'ITEM-AUTO-2',
        productId: 'PROD-AUTO-2',
        sku: 'SKU-AUTO-2',
        productName: 'Sản phẩm đích',
        serialNumber: 'SN-AUTO-02',
        epc: 'E28099000000000000000002',
        status: ItemStatus.inStock,
        locationId: 'LOC-AUTO-B',
      );

      final palletA = repo.createOrAssignPallet(
        palletCode: 'PL-AUTO-SRC',
        locationId: 'LOC-AUTO-A',
        newItems: [itemA],
      );
      final palletB = repo.createOrAssignPallet(
        palletCode: 'PL-AUTO-DST',
        locationId: 'LOC-AUTO-B',
        newItems: [itemB],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: PdaMergePalletsScreen(),
        ),
      );
      await tester.pump();

      final state = tester.state<PdaMergePalletsScreenState>(find.byType(PdaMergePalletsScreen));

      // 1. Quét Pallet Nguồn
      await tester.runAsync(() async {
        await state.handleIncomingScan(palletA.palletCode);
      });
      await tester.pump();

      // Kiểm tra pallet nguồn đã được chọn trên UI
      expect(find.textContaining('BƯỚC 2/2'), findsOneWidget);

      // 2. Quét Pallet Đích -> Tự động kích hoạt gộp ngay lập tức mà không cần thao tác bấm nút
      await tester.runAsync(() async {
        await state.handleIncomingScan(palletB.palletCode);
      });
      await tester.pump();

      // 3. Kiểm tra dữ liệu hàng hóa đã được tự động chuyển từ A sang B
      final updatedItemA = repo.items.firstWhere((it) => it.itemId == 'ITEM-AUTO-1');
      expect(updatedItemA.palletId, equals(palletB.palletId));
      expect(updatedItemA.locationId, equals('LOC-AUTO-B'));
      expect(palletA.itemIds.isEmpty, isTrue);
      expect(palletB.itemIds.contains('ITEM-AUTO-1'), isTrue);

      // 4. Kiểm tra UI hiển thị thông báo thành công
      expect(find.text('VỪA TỰ ĐỘNG GỘP THÀNH CÔNG!'), findsOneWidget);
      expect(find.textContaining('Đã chuyển 1 sản phẩm từ [PL-AUTO-SRC] sang [PL-AUTO-DST]'), findsOneWidget);

      // 5. Kiểm tra lịch sử gộp trong phiên đã được lưu
      expect(find.textContaining('LỊCH SỬ GỘP TRONG PHIÊN'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('PdaMergePalletsScreen allows selecting slot manually and auto-fills accordingly', (WidgetTester tester) async {
      final itemA = Item(
        itemId: 'ITEM-SLOT-1',
        productId: 'PROD-SLOT-1',
        sku: 'SKU-SLOT-1',
        productName: 'Sản phẩm thử nghiệm slot',
        serialNumber: 'SN-SLOT-01',
        epc: 'E28099000000000000000011',
        status: ItemStatus.inStock,
        locationId: 'LOC-SLOT-A',
      );
      final itemB = Item(
        itemId: 'ITEM-SLOT-2',
        productId: 'PROD-SLOT-2',
        sku: 'SKU-SLOT-2',
        productName: 'Sản phẩm đích slot',
        serialNumber: 'SN-SLOT-02',
        epc: 'E28099000000000000000012',
        status: ItemStatus.inStock,
        locationId: 'LOC-SLOT-B',
      );

      final palletA = repo.createOrAssignPallet(
        palletCode: 'PL-SLOT-SRC',
        locationId: 'LOC-SLOT-A',
        newItems: [itemA],
      );
      final palletB = repo.createOrAssignPallet(
        palletCode: 'PL-SLOT-DST',
        locationId: 'LOC-SLOT-B',
        newItems: [itemB],
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: PdaMergePalletsScreen(),
        ),
      );
      await tester.pump();

      // Ban đầu mặc định slot nguồn được chọn
      expect(find.text('CHỜ Ô 1 (NGUỒN)'), findsOneWidget);

      // Chạm vào mục 2 (Pallet Đích) để chọn quét mục này
      await tester.tap(find.textContaining('2. PALLET ĐÍCH (B)'));
      await tester.pump();

      // Lúc này slot đích được chọn
      expect(find.text('CHỜ Ô 2 (ĐÍCH)'), findsOneWidget);

      final state = tester.state<PdaMergePalletsScreenState>(find.byType(PdaMergePalletsScreen));

      // Quét pallet đích trước
      await tester.runAsync(() async {
        await state.handleIncomingScan(palletB.palletCode);
      });
      await tester.pump();

      // Đã tự động điền vào ô Đích và chuyển sang chờ ô Nguồn
      expect(find.text('CHỜ Ô 1 (NGUỒN)'), findsOneWidget);

      // Quét pallet nguồn -> tự động gộp ngay lập tức
      await tester.runAsync(() async {
        await state.handleIncomingScan(palletA.palletCode);
      });
      await tester.pump();

      expect(find.text('VỪA TỰ ĐỘNG GỘP THÀNH CÔNG!'), findsOneWidget);
    });

    test('Inject barcode selects source and target pallets via UhfService', () async {
      final uhf = UhfService();
      String? scanned;
      final sub = uhf.onBarcodeRead.listen((b) => scanned = b);

      uhf.injectBarcode('PL-SRC-01');
      await Future.delayed(const Duration(milliseconds: 30));
      expect(scanned, equals('PL-SRC-01'));

      uhf.injectBarcode('PL-DST-02');
      await Future.delayed(const Duration(milliseconds: 30));
      expect(scanned, equals('PL-DST-02'));

      await sub.cancel();
    });
  });
}
