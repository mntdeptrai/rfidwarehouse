import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/screens/pda/pda_inventory_screen.dart';
import 'package:uhf/screens/pda/pda_transfer_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kiểm kê theo từng vị trí kệ & Cảnh báo chip từ kho khác', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
    });

    test('1. Lọc đúng vị trí kệ theo CSDL và phát hiện chip từ kho khác', () async {
      // Thiết lập 2 vị trí kệ trong CSDL
      final locA = Location(
        locationId: 'LOC-A1-01',
        locationCode: 'R01-A-01',
        zone: 'KHO_NL',
        shelf: 'Kệ A1',
        level: 'Tầng 1',
      );
      final locB = Location(
        locationId: 'LOC-B2-05',
        locationCode: 'R02-B-05',
        zone: 'KHO_TP',
        shelf: 'Kệ B2',
        level: 'Tầng 5',
      );
      await repo.addLocation(locA);
      await repo.addLocation(locB);

      // Thiết lập 2 sản phẩm: Item 1 tại Kệ A1, Item 2 tại Kệ B2 (Kho khác)
      const epcItemA = 'E28068940000000000ITEM_A';
      const epcItemB = 'E28068940000000000ITEM_B';
      const epcUnknown = 'E28068940000000000UNKNOWN';

      final itemA = Item(
        itemId: 'ITEM-LOC-A',
        productId: 'PROD-A',
        sku: 'SKU-A',
        productName: 'Sản phẩm Kệ A1',
        serialNumber: 'SN-A-001',
        epc: epcItemA,
        status: ItemStatus.inStock,
        locationId: locA.locationId,
      );

      final itemB = Item(
        itemId: 'ITEM-LOC-B',
        productId: 'PROD-B',
        sku: 'SKU-B',
        productName: 'Sản phẩm Kệ B2 (Kho Thành Phẩm)',
        serialNumber: 'SN-B-001',
        epc: epcItemB,
        status: ItemStatus.inStock,
        locationId: locB.locationId,
      );

      await repo.addItem(itemA);
      await repo.addItem(itemB);

      // Bắt đầu phiên kiểm kê chính xác tại Kệ A1 (R01-A-01)
      final session = repo.startInventorySession(
        zone: locA.zone,
        locationCode: locA.locationCode,
      );

      expect(session.locationCode, equals(locA.locationCode));
      // Ban đầu khi chưa quét gì, CSDL ghi nhận Item A là đang thiếu (missing)
      expect(session.missingCount, equals(1));
      expect(session.results.first.epc, equals(epcItemA));
      expect(session.results.first.resultType, equals(InventoryVarianceType.missing));

      // Thực hiện quét: Quét được Item A, Item B (lạc từ kệ B2 sang) và một thẻ lạ Unknown
      repo.processAuditScan(
        sessionId: session.sessionId,
        scannedEpcs: [epcItemA, epcItemB, epcUnknown],
      );

      // 1. Kiểm tra tổng số lượng thực tế quét và tồn CSDL
      expect(session.actualScannedCount, equals(3));
      // Tồn CSDL dự kiến ở vị trí này là 1 sản phẩm (Item A)
      final expectedInDbCount = session.matchCount + session.missingCount;
      expect(expectedInDbCount, equals(1));

      // 2. Kiểm tra kết quả Khớp (Item A đúng vị trí)
      expect(session.matchCount, equals(1));
      final matchResult = session.results.firstWhere((r) => r.epc == epcItemA);
      expect(matchResult.resultType, equals(InventoryVarianceType.match));
      expect(matchResult.productName, equals('Sản phẩm Kệ A1'));

      // 3. CẢNH BÁO QUAN TRỌNG: Phát hiện chip từ kho khác vào
      expect(session.wrongLocationCount, equals(1));
      final wrongLocResult = session.results.firstWhere((r) => r.epc == epcItemB);
      expect(wrongLocResult.resultType, equals(InventoryVarianceType.wrongLocation));
      expect(wrongLocResult.productName, equals('Sản phẩm Kệ B2 (Kho Thành Phẩm)'));
      // Phải chỉ rõ vị trí CSDL gốc và vị trí thực tế quét được
      expect(wrongLocResult.expectedLocation, contains(locB.locationCode));
      expect(wrongLocResult.actualLocation, contains(locA.locationCode));

      // 4. Thẻ lạ chưa khai báo
      expect(session.unknownEpcCount, equals(1));
      final unknownResult = session.results.firstWhere((r) => r.epc == epcUnknown);
      expect(unknownResult.resultType, equals(InventoryVarianceType.unknownEpc));

      // 5. Thử nghiệm chuyển vị trí nhanh trên DB: Chuyển Item B về Kệ A1
      final moveSuccess = await repo.moveItemIndividual(
        epc: epcItemB,
        newLocationId: locA.locationId,
        performedBy: 'Thủ kho PDA Test',
      );
      expect(moveSuccess, isTrue);

      // Quét lại đối chiếu
      repo.processAuditScan(
        sessionId: session.sessionId,
        scannedEpcs: [epcItemA, epcItemB],
      );

      // Lúc này cả 2 item đều thuộc Kệ A1 trên DB -> matchCount = 2, wrongLocationCount = 0
      expect(session.matchCount, equals(2));
      expect(session.wrongLocationCount, equals(0));
    });

    testWidgets('2. Giao diện PDA hiển thị đầy đủ KPI đối chiếu và cảnh báo', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: PdaInventoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra tiêu đề màn hình PDA
      expect(find.text('Kiểm Kê Kho Hàng (RFID)'), findsOneWidget);
    });

    testWidgets('3. Bóp tay cò trên PDA quét mã không bị lỗi !_dirty và nhận chip kiểm kê', (WidgetTester tester) async {
      final loc = Location(locationId: 'LOC-TEST-01', locationCode: 'R01-01', zone: 'KHO_TEST', shelf: 'Kệ 1', level: 'Tầng 1');
      await repo.addLocation(loc);
      final item = Item(
        itemId: 'ITEM-TEST-TRIG',
        productId: 'PROD-TEST',
        sku: 'SKU-TEST',
        productName: 'Sản phẩm Test Bóp Cò',
        serialNumber: 'SN-TRIG-01',
        epc: 'EPC_TEST_TRIGGER_01',
        status: ItemStatus.inStock,
        locationId: loc.locationId,
      );
      await repo.addItem(item);

      final session = repo.startInventorySession(zone: loc.zone, locationCode: loc.locationCode);

      await tester.pumpWidget(
        const MaterialApp(
          home: PdaInventoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Bấm vào phiên kiểm kê để mở màn hình quét
      final sessionCard = find.text(session.sessionCode);
      expect(sessionCard, findsOneWidget);
      await tester.tap(sessionCard);
      await tester.pumpAndSettle();

      // Giả lập bóp tay cò vật lý PDA (pressed = true)
      final uhf = UhfService();
      uhf.simulateTrigger(true);
      await tester.pump();

      // Giả lập đầu đọc UHF bắn chip về
      uhf.simulateTag('EPC_TEST_TRIGGER_01');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Nhả tay cò vật lý PDA (pressed = false)
      uhf.simulateTrigger(false);
      await tester.pumpAndSettle();

      // Kiểm tra đã nhận diện đúng sản phẩm khớp với vị trí
      expect(find.textContaining('EPC_TEST_TRIGGER_01'), findsOneWidget);
      expect(find.text('Sản phẩm Test Bóp Cò'), findsOneWidget);
    });

    testWidgets('4. Bóp tay cò trên PdaTransferScreen quét mã không bị lỗi !_dirty', (WidgetTester tester) async {
      final loc = Location(locationId: 'LOC-TRF-01', locationCode: 'R01-TRF', zone: 'KHO_TRF', shelf: 'Kệ TRF', level: 'Tầng 1');
      await repo.addLocation(loc);
      final item = Item(
        itemId: 'ITEM-TRF-01',
        productId: 'PROD-TRF',
        sku: 'SKU-TRF',
        productName: 'Sản phẩm Test Chuyển Kho',
        serialNumber: 'SN-TRF-001',
        epc: 'EPC_TRANSFER_TRIGGER_01',
        status: ItemStatus.inStock,
        locationId: loc.locationId,
      );
      await repo.addItem(item);

      await tester.pumpWidget(
        const MaterialApp(
          home: PdaTransferScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Chuyển sang chế độ Sản phẩm riêng lẻ
      final itemModeTab = find.text('Sản phẩm riêng lẻ');
      expect(itemModeTab, findsOneWidget);
      await tester.tap(itemModeTab);
      await tester.pumpAndSettle();

      // Bóp cò
      final uhf = UhfService();
      uhf.simulateTrigger(true);
      await tester.pump();

      // Quét thẻ RFID
      uhf.simulateTag('EPC_TRANSFER_TRIGGER_01');
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();

      // Nhả cò
      uhf.simulateTrigger(false);
      await tester.pumpAndSettle();

      // Kiểm tra sản phẩm đã được thêm vào danh sách chuyển kho
      expect(find.text('Sản phẩm Test Chuyển Kho'), findsOneWidget);
    });

    testWidgets('5. Màn hình Kiểm kê tự động bắt buộc PdaScanMode.rfid và không bị nhầm sang Barcode', (WidgetTester tester) async {
      final uhf = UhfService();
      // Giả sử trước đó người dùng vào màn hình Barcode
      uhf.setScanMode(PdaScanMode.barcode);
      expect(uhf.scanMode, equals(PdaScanMode.barcode));

      // Vào màn hình PdaInventoryScreen
      await tester.pumpWidget(
        const MaterialApp(
          home: PdaInventoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra scanMode đã được cưỡng chế chuyển về PdaScanMode.rfid ngay tại danh sách phiên
      expect(uhf.scanMode, equals(PdaScanMode.rfid));
      expect(find.text('RFID UHF'), findsAtLeastNWidgets(1));

      // Mở 1 phiên kiểm kê
      final loc = Location(locationId: 'LOC-TEST-RFID', locationCode: 'R-RFID', zone: 'KHO_RFID', shelf: 'Kệ 1', level: 'Tầng 1');
      await repo.addLocation(loc);
      final session = repo.startInventorySession(zone: loc.zone, locationCode: loc.locationCode);

      await tester.pumpWidget(
        const MaterialApp(
          home: PdaInventoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      final sessionCard = find.text(session.sessionCode);
      await tester.tap(sessionCard);
      await tester.pumpAndSettle();

      // Trong màn hình quét kiểm kê chi tiết, scanMode tiếp tục là rfid
      expect(uhf.scanMode, equals(PdaScanMode.rfid));

      // Khi bóp cò, quét RFID
      uhf.simulateTrigger(true);
      await tester.pump();
      expect(uhf.scanMode, equals(PdaScanMode.rfid));

      uhf.simulateTrigger(false);
      await tester.pumpAndSettle();
    });

    testWidgets('6. Hộp thoại Chọn Hình Thức Kiểm Kê có thể chọn (tick) được cả 3 hình thức', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const PdaInventoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Bấm nút tạo phiếu kiểm kê mới để mở dialog
      final createBtn = find.text('+ TẠO PHIẾU KIỂM KÊ MỚI');
      expect(createBtn, findsOneWidget);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      // Ban đầu mặc định chọn mục 1 (Icons.radio_button_checked = 1 cái)
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

      // Bấm vào mục 2: Theo Phân Khu / Khu vực (Zone)
      final option2 = find.textContaining('Theo Phân Khu / Khu vực');
      expect(option2, findsOneWidget);
      await tester.tap(option2);
      await tester.pumpAndSettle();

      // Kiểm tra mục 2 đã được tick chọn (radio_button_checked vẫn là 1 cái)
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);

      // Bấm vào mục 3: Kiểm kê toàn bộ kho hàng
      final option3 = find.textContaining('Kiểm kê toàn bộ kho hàng');
      expect(option3, findsOneWidget);
      await tester.tap(option3);
      await tester.pumpAndSettle();

      // Kiểm tra mục 3 đã được tick chọn
      expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    });
  });
}
