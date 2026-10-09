import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/screens/desktop/desktop_stock_reconciliation_view.dart';
import 'package:uhf/screens/desktop/desktop_audit_ticket_detail_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Desktop Stock Reconciliation & Audit Ticket Detail Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
    });

    test('1. WarehouseRepository.getStockReconciliation tính toán tồn dự kiến vs thực tế chính xác', () async {
      // 1. Tạo vị trí kệ
      final locA = Location(
        locationId: 'LOC-TEST-A',
        locationCode: 'A-01-01',
        zone: 'Khu A',
        shelf: 'Kệ A1',
        level: 'Tầng 1',
      );
      final locB = Location(
        locationId: 'LOC-TEST-B',
        locationCode: 'B-01-01',
        zone: 'Khu B',
        shelf: 'Kệ B1',
        level: 'Tầng 1',
      );
      await repo.addLocation(locA);
      await repo.addLocation(locB);

      // 2. Tạo sản phẩm tồn kho dự kiến
      final item1 = Item(
        itemId: 'ITEM-TEST-1',
        productId: 'PROD-SKU-01',
        sku: 'SKU-01',
        productName: 'Áo Thun Basic',
        serialNumber: 'SN-001',
        epc: 'E28068940000000000000001',
        status: ItemStatus.inStock,
        locationId: locA.locationId,
      );
      final item2 = Item(
        itemId: 'ITEM-TEST-2',
        productId: 'PROD-SKU-01',
        sku: 'SKU-01',
        productName: 'Áo Thun Basic',
        serialNumber: 'SN-002',
        epc: 'E28068940000000000000002',
        status: ItemStatus.inStock,
        locationId: locA.locationId,
      );
      final item3 = Item(
        itemId: 'ITEM-TEST-3',
        productId: 'PROD-SKU-02',
        sku: 'SKU-02',
        productName: 'Quần Jean Slim',
        serialNumber: 'SN-003',
        epc: 'E28068940000000000000003',
        status: ItemStatus.inStock,
        locationId: locB.locationId,
      );

      await repo.addItem(item1);
      await repo.addItem(item2);
      await repo.addItem(item3);

      // 3. Tạo một đợt kiểm kê với kết quả quét thực tế
      // SKU-01 có dự kiến 2 (item1 khớp, item2 thiếu), thực tế quét được 1
      // Thẻ lạ ngoài danh sách: EPC_EXTRA
      final session = InventorySession(
        sessionId: 'SESS-TEST-01',
        sessionCode: 'KK-TEST-001',
        zone: 'Khu A',
        startedAt: DateTime.now(),
        isCompleted: true,
        results: [
          InventoryItemResult(
            epc: item1.epc,
            resultType: InventoryVarianceType.match,
            readAt: DateTime.now(),
            sku: item1.sku,
            productName: item1.productName,
            expectedLocation: locA.locationCode,
          ),
          InventoryItemResult(
            epc: item2.epc,
            resultType: InventoryVarianceType.missing,
            readAt: DateTime.now(),
            sku: item2.sku,
            productName: item2.productName,
            expectedLocation: locA.locationCode,
          ),
          InventoryItemResult(
            epc: 'E28068940000000000099999',
            resultType: InventoryVarianceType.unknownEpc,
            readAt: DateTime.now(),
            sku: 'SKU-EXTRA',
            productName: 'Sản phẩm lạ',
          ),
        ],
      );
      await repo.saveInventorySession(session);

      // 4. Kiểm tra đối soát theo session SESS-TEST-01
      final reconRows = repo.getStockReconciliation(sessionId: session.sessionId);
      expect(reconRows, isNotEmpty);

      // Tìm SKU-01
      final sku1Row = reconRows.firstWhere((r) => r.sku == 'SKU-01');
      expect(sku1Row.expectedQty, 2);
      expect(sku1Row.actualQty, 1);
      expect(sku1Row.difference, -1);
      expect(sku1Row.accuracyPercent, 50.0);
      expect(sku1Row.statusLabel.contains('Thiếu'), isTrue);

      // Tìm SKU lạ ngoài danh sách
      final skuExtraRow = reconRows.firstWhere((r) => r.sku == 'SKU-EXTRA');
      expect(skuExtraRow.expectedQty, 0);
      expect(skuExtraRow.actualQty, 1);
      expect(skuExtraRow.difference, 1);
      expect(skuExtraRow.statusLabel.contains('Thừa'), isTrue);

      // 5. Kiểm tra lọc theo zone Khu A
      final zoneARows = repo.getStockReconciliation(zone: 'Khu A');
      expect(zoneARows.any((r) => r.sku == 'SKU-01'), isTrue);
      // SKU-02 nằm ở Khu B, không nên có trong kết quả Khu A
      expect(zoneARows.any((r) => r.sku == 'SKU-02'), isFalse);
    });

    testWidgets('2. DesktopStockReconciliationView hiển thị bảng đối soát dự kiến vs thực tế', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: false,
            splashFactory: NoSplash.splashFactory,
          ),
          home: Scaffold(
            body: DesktopStockReconciliationView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra tiêu đề và nút xuất bảng đối soát
      expect(find.text('ĐỐI SOÁT TỒN KHO: DỰ KIẾN (SỔ SÁCH) VS THỰC TẾ KIỂM KÊ'), findsOneWidget);
      expect(find.text('XUẤT BẢNG ĐỐI SOÁT (.XLSX)'), findsOneWidget);

      // Kiểm tra các chip bộ lọc
      expect(find.textContaining('Tất cả ('), findsOneWidget);
      expect(find.textContaining('Có chênh lệch'), findsOneWidget);
      expect(find.textContaining('Khớp đủ'), findsOneWidget);
      expect(find.textContaining('Lệch thiếu'), findsOneWidget);
      expect(find.textContaining('Lệch thừa'), findsOneWidget);

      // Kiểm tra các cột tiêu đề bảng đối soát
      expect(find.text('MÃ SKU'), findsOneWidget);
      expect(find.text('DỰ KIẾN (SỔ SÁCH)'), findsOneWidget);
      expect(find.text('THỰC TẾ (KIỂM KÊ)'), findsOneWidget);
      expect(find.text('CHÊNH LỆCH'), findsOneWidget);
      expect(find.text('TRẠNG THÁI'), findsOneWidget);
    });

    testWidgets('3. DesktopAuditTicketDetailView hiển thị chi tiết phiếu kiểm kê và chuyển tab', (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final session = InventorySession(
        sessionId: 'SESS-TICKET-TEST',
        sessionCode: 'KK-2026-TEST',
        zone: 'Kho Tổng',
        startedAt: DateTime(2026, 9, 29, 10, 0),
        completedAt: DateTime(2026, 9, 29, 11, 30),
        isCompleted: true,
        results: [
          InventoryItemResult(
            epc: 'E2806894000000000000AAAA',
            resultType: InventoryVarianceType.match,
            readAt: DateTime(2026, 9, 29, 10, 15),
            sku: 'SKU-AAA',
            productName: 'Sản phẩm Test AAA',
            expectedLocation: 'A-01-01',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: false,
            splashFactory: NoSplash.splashFactory,
          ),
          home: Scaffold(
            body: DesktopAuditTicketDetailView(
              session: session,
              onBack: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra mã phiếu
      expect(find.text('PHIẾU KIỂM KÊ: KK-2026-TEST'), findsOneWidget);
      expect(find.text('ĐÃ HOÀN TẤT'), findsOneWidget);
      expect(find.text('XUẤT BIÊN BẢN (.XLSX)'), findsOneWidget);
      expect(find.text('IN BIÊN BẢN'), findsOneWidget);

      // Kiểm tra 2 tab
      expect(find.textContaining('BẢNG TỔNG HỢP THEO MẶT HÀNG / SKU'), findsOneWidget);
      expect(find.textContaining('CHI TIẾT DANH SÁCH CHIP RFID EPC'), findsOneWidget);

      // Chuyển sang Tab 2: Chi tiết thẻ chip RFID
      await tester.tap(find.textContaining('CHI TIẾT DANH SÁCH CHIP RFID EPC'));
      await tester.pumpAndSettle();

      // Kiểm tra thẻ chip EPC hiển thị trên bảng
      expect(find.text('E2806894000000000000AAAA'), findsOneWidget);
      expect(find.text('SKU-AAA'), findsOneWidget);
    });

    test('4. Khi chưa thực hiện kiểm kê (chưa quét thẻ), không báo lệch thiếu sai lệch', () async {
      final unscannedSession = InventorySession(
        sessionId: 'SESS-UNAUDITED-01',
        sessionCode: 'KK-UNAUDITED-001',
        zone: 'Khu A',
        startedAt: DateTime.now(),
        isCompleted: false,
        results: [
          InventoryItemResult(
            epc: 'E28068940000000000000001',
            resultType: InventoryVarianceType.missing,
            readAt: DateTime.now(),
            sku: 'SKU-01',
            productName: 'Áo Thun Basic',
            expectedLocation: 'A-01-01',
          ),
        ],
      );

      final rows = repo.buildSessionSkuBreakdown(unscannedSession);
      expect(rows, isNotEmpty);
      final row = rows.firstWhere((r) => r.sku == 'SKU-01');
      expect(row.isAudited, isFalse);
      expect(row.expectedQty, 1);
      expect(row.actualQty, 0);
      expect(row.missingCount, 0);
      expect(row.difference, 0);
      expect(row.statusLabel, 'Chưa kiểm kê');
    });
  });
}
