import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/screens/pda/pda_inventory_screen.dart';
import 'package:uhf/screens/desktop/desktop_inventory_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Kiểm kê theo từng mặt hàng (SKU) & Quét lọc trên PDA', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
    });

    test('1. Tạo phiếu kiểm kê theo SKU: chỉ đưa các mặt hàng được chỉ định vào danh sách kiểm kê', () async {
      // 1. Chuẩn bị 3 sản phẩm với 3 SKU khác nhau
      const epcPepsi1 = 'E28068940000000000PEPSI_1';
      const epcPepsi2 = 'E28068940000000000PEPSI_2';
      const epcCoca = 'E28068940000000000COCA_1';
      const epcWater = 'E28068940000000000WATER_1';

      final itemPepsi1 = Item(
        itemId: 'ITEM-PEPSI-1',
        productId: 'PROD-PEPSI',
        sku: 'SKU-PEPSI',
        productName: 'Nước ngọt Pepsi 330ml',
        serialNumber: 'SN-P-001',
        epc: epcPepsi1,
        status: ItemStatus.inStock,
        locationId: 'LOC-A01',
      );
      final itemPepsi2 = Item(
        itemId: 'ITEM-PEPSI-2',
        productId: 'PROD-PEPSI',
        sku: 'SKU-PEPSI',
        productName: 'Nước ngọt Pepsi 330ml',
        serialNumber: 'SN-P-002',
        epc: epcPepsi2,
        status: ItemStatus.inStock,
        locationId: 'LOC-A01',
      );
      final itemCoca = Item(
        itemId: 'ITEM-COCA-1',
        productId: 'PROD-COCA',
        sku: 'SKU-COCA',
        productName: 'Nước ngọt Coca Cola 330ml',
        serialNumber: 'SN-C-001',
        epc: epcCoca,
        status: ItemStatus.inStock,
        locationId: 'LOC-A02',
      );
      final itemWater = Item(
        itemId: 'ITEM-WATER-1',
        productId: 'PROD-WATER',
        sku: 'SKU-WATER',
        productName: 'Nước khoáng Aquafina 500ml',
        serialNumber: 'SN-W-001',
        epc: epcWater,
        status: ItemStatus.inStock,
        locationId: 'LOC-B01',
      );

      await repo.addItem(itemPepsi1);
      await repo.addItem(itemPepsi2);
      await repo.addItem(itemCoca);
      await repo.addItem(itemWater);

      // 2. Thủ kho tạo phiếu kiểm kê CHỈ DÀNH RIÊNG cho mặt hàng SKU-PEPSI
      final session = repo.startInventorySession(
        zone: 'Toàn bộ kho',
        targetSkus: ['SKU-PEPSI'],
      );

      expect(session.isSkuSpecific, isTrue);
      expect(session.targetSkus, contains('SKU-PEPSI'));
      expect(session.targetSkusDisplay, contains('SKU-PEPSI'));

      // Ban đầu khi chưa quét gì:
      // Chỉ 2 item của SKU-PEPSI được đưa vào danh sách kiểm kê (trạng thái missing ban đầu)
      expect(session.results.length, equals(2));
      expect(session.results.every((r) => r.sku == 'SKU-PEPSI'), isTrue);
      expect(session.missingCount, equals(2));
      expect(session.matchCount, equals(0));

      // Các mặt hàng khác (SKU-COCA, SKU-WATER) tuyệt đối không có trong phiếu kiểm kê này
      expect(session.results.any((r) => r.sku == 'SKU-COCA'), isFalse);
      expect(session.results.any((r) => r.sku == 'SKU-WATER'), isFalse);

      // 3. Tiến hành quét RFID đối soát:
      // Quét thấy 1 lon Pepsi (epcPepsi1) và 1 lon Coca (epcCoca - không nằm trong phiếu kiểm kê)
      repo.processAuditScan(
        sessionId: session.sessionId,
        scannedEpcs: [epcPepsi1, epcCoca],
      );

      // 4. Kiểm tra kết quả đối soát lọc:
      // - epcPepsi1: thuộc SKU-PEPSI -> KHỚP (match)
      expect(session.matchCount, equals(1));
      final matchItem = session.results.firstWhere((r) => r.epc == epcPepsi1);
      expect(matchItem.resultType, equals(InventoryVarianceType.match));

      // - epcPepsi2: chưa quét thấy -> THIẾU (missing)
      expect(session.missingCount, equals(1));
      final missingItem = session.results.firstWhere((r) => r.epc == epcPepsi2);
      expect(missingItem.resultType, equals(InventoryVarianceType.missing));

      // - epcCoca: thuộc SKU-COCA (NGOÀI PHIẾU KIỂM KÊ) -> Cảnh báo sai vị trí / ngoài phiếu (wrongLocation)
      expect(session.wrongLocationCount, equals(1));
      final wrongItem = session.results.firstWhere((r) => r.epc == epcCoca);
      expect(wrongItem.resultType, equals(InventoryVarianceType.wrongLocation));
      expect(wrongItem.expectedLocation, contains('Ngoài phiếu kiểm kê'));

      // 5. Quét tiếp lon Pepsi thứ 2 và một thẻ lạ (UNKNOWN)
      repo.processAuditScan(
        sessionId: session.sessionId,
        scannedEpcs: [epcPepsi1, epcPepsi2, epcCoca, 'UNKNOWN_TAG_999'],
      );

      expect(session.matchCount, equals(2));
      expect(session.missingCount, equals(0));
      expect(session.wrongLocationCount, equals(1));
      expect(session.unknownEpcCount, equals(1));

      // 6. Hoàn tất phiếu kiểm kê
      await repo.completeInventorySession(session.sessionId, 'Thủ kho PDA');
      expect(session.isCompleted, isTrue);
      expect(session.completedAt, isNotNull);
    });

    testWidgets('2. Giao diện PDA hiển thị tùy chọn kiểm kê theo SKU và mở hộp thoại chọn mặt hàng', (tester) async {
      await repo.addItem(Item(
        itemId: 'ITEM-TEST-SKU-1',
        productId: 'PROD-SKU-1',
        sku: 'SKU-SNACK',
        productName: 'Bim Bim Oishi 50g',
        serialNumber: 'SN-SNACK-01',
        epc: 'EPC_SNACK_01',
        status: ItemStatus.inStock,
      ));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false, splashFactory: NoSplash.splashFactory),
          home: const PdaInventoryScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Bấm nút tạo phiếu kiểm kê (Icon hoặc Button)
      final createBtn = find.text('TẠO PHIẾU KIỂM KÊ');
      expect(createBtn, findsOneWidget);
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      // Kiểm tra dialog hình thức kiểm kê có tùy chọn "Theo Từng Mặt Hàng (SKU)"
      expect(find.text('Hình Thức Kiểm Kê'), findsOneWidget);
      expect(find.text('Theo Từng Mặt Hàng (SKU)'), findsOneWidget);

      // Chọn "Theo Từng Mặt Hàng (SKU)" và bấm "TIẾP TỤC"
      await tester.tap(find.text('Theo Từng Mặt Hàng (SKU)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('TIẾP TỤC'));
      await tester.pumpAndSettle();

      // Dialog chọn mặt hàng kiểm kê phải xuất hiện
      expect(find.text('Chọn Mặt Hàng Kiểm Kê'), findsOneWidget);
      expect(find.text('SKU-SNACK'), findsOneWidget);
      expect(find.textContaining('Bim Bim Oishi'), findsOneWidget);

      // Tích chọn SKU-SNACK
      await tester.tap(find.text('SKU-SNACK'));
      await tester.pumpAndSettle();

      expect(find.text('Đã chọn: 1 SKU'), findsOneWidget);

      // Bấm "BẮT ĐẦU KIỂM KÊ"
      await tester.tap(find.text('BẮT ĐẦU KIỂM KÊ'));
      await tester.pumpAndSettle();

      // Kiểm tra màn hình quét kiểm kê mở ra và hiển thị đúng SKU mục tiêu
      expect(find.textContaining('Mặt hàng: SKU-SNACK'), findsOneWidget);
      expect(find.text('BẮT ĐẦU QUÉT'), findsOneWidget);
    });

    testWidgets('3. Giao diện Desktop hiển thị tùy chọn kiểm kê theo SKU và tạo đơn kiểm kê theo SKU thành công', (tester) async {
      await repo.addItem(Item(
        itemId: 'ITEM-TEST-DESK-1',
        productId: 'PROD-DESK-1',
        sku: 'SKU-COFFEE',
        productName: 'Cà phê hòa tan Trung Nguyên',
        serialNumber: 'SN-CF-01',
        epc: 'EPC_COFFEE_01',
        status: ItemStatus.inStock,
      ));

      await tester.binding.setSurfaceSize(const Size(1280, 800));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false, splashFactory: NoSplash.splashFactory),
          home: const Scaffold(
            body: DesktopInventoryView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bấm nút tạo đơn kiểm kê trên Desktop (trong Hero Action Card)
      final createBtn = find.text('+ TẠO ĐƠN KIỂM KÊ').last;
      await tester.tap(createBtn);
      await tester.pumpAndSettle();

      // Kiểm tra trong dialog có mục "Theo Từng Mặt Hàng Cụ Thể (SKU)"
      expect(find.text('Theo Từng Mặt Hàng Cụ Thể (SKU)'), findsOneWidget);

      // Chọn option SKU
      await tester.tap(find.text('Theo Từng Mặt Hàng Cụ Thể (SKU)'));
      await tester.pumpAndSettle();

      // Danh sách SKU hiển thị
      expect(find.text('SKU-COFFEE'), findsOneWidget);
      expect(find.textContaining('Cà phê hòa tan'), findsOneWidget);

      // Tích chọn SKU-COFFEE
      await tester.tap(find.text('SKU-COFFEE'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Đã chọn 1 mặt hàng: SKU-COFFEE'), findsOneWidget);

      // Bấm "BẮT ĐẦU KIỂM KÊ"
      await tester.tap(find.text('BẮT ĐẦU KIỂM KÊ'));
      await tester.pumpAndSettle();

      // Kiểm tra banner session active trên Desktop hiển thị phạm vi lọc SKU
      expect(find.textContaining('Lọc 1 SKU (SKU-COFFEE)'), findsOneWidget);
    });
  });
}
