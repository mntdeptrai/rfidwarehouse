import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/desktop/desktop_inventory_view.dart';
import 'package:uhf/screens/desktop/desktop_report_view.dart';
import 'package:uhf/screens/desktop/desktop_stock_reconciliation_view.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Stock Reconciliation & Single-Location Report Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
    });

    test('getStockReconciliation automatically reconciles completed inventory session', () async {
      // Giả lập session hoàn tất
      final session = InventorySession(
        sessionId: 'SESS-AUTO-RECON-001',
        sessionCode: 'KK-AUTO-001',
        zone: 'Khu A',
        locationCode: 'LOC-001',
        startedAt: DateTime.now().subtract(const Duration(minutes: 15)),
        completedAt: DateTime.now(),
        isCompleted: true,
        results: [
          InventoryItemResult(
            epc: 'EPC-RECON-001',
            sku: 'SKU-RECON-A',
            productName: 'Sản phẩm Đối Soát A',
            expectedLocation: 'LOC-001',
            actualLocation: 'LOC-001',
            resultType: InventoryVarianceType.match,
            readAt: DateTime.now(),
          ),
          InventoryItemResult(
            epc: 'EPC-RECON-002',
            sku: 'SKU-RECON-A',
            productName: 'Sản phẩm Đối Soát A',
            expectedLocation: 'LOC-001',
            actualLocation: 'Chưa quét thấy',
            resultType: InventoryVarianceType.missing,
            readAt: DateTime.now(),
          ),
        ],
      );

      await repo.saveInventorySession(session);

      // Gọi getStockReconciliation không truyền sessionId (mặc định lấy session mới nhất)
      final rows = repo.getStockReconciliation();
      expect(rows.isNotEmpty, isTrue);

      final rowA = rows.firstWhere((r) => r.sku == 'SKU-RECON-A');
      expect(rowA.expectedQty, equals(2));
      expect(rowA.actualQty, equals(1));
      expect(rowA.matchedCount, equals(1));
      expect(rowA.missingCount, equals(1));
      expect(rowA.difference, equals(-1));
    });

    test('getStockReconciliation accurately accounts for surplus and unknown EPC tags (34 scanned, 10 match, 24 unknown)', () async {
      final List<InventoryItemResult> testResults = [];
      // 10 Match items
      for (int i = 1; i <= 10; i++) {
        testResults.add(InventoryItemResult(
          epc: 'EPC-MATCH-$i',
          sku: 'SKU-$i',
          productName: 'Sản phẩm $i',
          expectedLocation: 'Toàn bộ kho',
          actualLocation: 'Toàn bộ kho',
          resultType: InventoryVarianceType.match,
          readAt: DateTime.now(),
        ));
      }
      // 24 Unknown EPC items
      for (int i = 1; i <= 24; i++) {
        testResults.add(InventoryItemResult(
          epc: 'EPC-UNKNOWN-$i',
          sku: 'THẺ_LẠ',
          productName: 'Thẻ RFID lạ chưa khai báo',
          expectedLocation: 'Chưa khai báo',
          actualLocation: 'Toàn bộ kho',
          resultType: InventoryVarianceType.unknownEpc,
          readAt: DateTime.now(),
        ));
      }

      final session = InventorySession(
        sessionId: 'SESS-SURPLUS-TEST-001',
        sessionCode: 'KK-929-SURPLUS',
        zone: 'Toàn bộ kho',
        startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        completedAt: DateTime.now(),
        isCompleted: true,
        results: testResults,
      );

      await repo.saveInventorySession(session);

      final rows = repo.getStockReconciliation(sessionId: session.sessionId);
      final totalExpected = rows.fold<int>(0, (sum, r) => sum + r.expectedQty);
      final totalActual = rows.fold<int>(0, (sum, r) => sum + r.actualQty);
      final totalMatched = rows.fold<int>(0, (sum, r) => sum + r.matchedCount);
      final totalSurplus = rows.fold<int>(0, (sum, r) => sum + (r.difference > 0 ? r.difference : 0));

      expect(totalExpected, equals(10));
      expect(totalActual, equals(34));
      expect(totalMatched, equals(10));
      expect(totalSurplus, equals(24));

      final unknownRow = rows.firstWhere((r) => r.sku == 'THẺ_LẠ');
      expect(unknownRow.expectedQty, equals(0));
      expect(unknownRow.actualQty, equals(24));
      expect(unknownRow.difference, equals(24));
      expect(unknownRow.statusLabel, equals('Thừa 24'));
    });

    testWidgets('DesktopInventoryView does not have duplicate reconciliation tab', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const Scaffold(
            body: DesktopInventoryView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra: Nút 'Đối Soát Tồn Kho (Dự Kiến vs Thực Tế)' KHÔNG còn trong DesktopInventoryView
      expect(find.text('Đối Soát Tồn Kho (Dự Kiến vs Thực Tế)'), findsNothing);

      // Kiểm tra các tính năng kiểm kê chính vẫn đầy đủ
      expect(find.text('+ TẠO ĐƠN KIỂM KÊ'), findsWidgets);
      expect(find.text('📥 XUẤT FILE KIỂM KÊ'), findsWidgets);
    });

    testWidgets('DesktopReportView hosts DesktopStockReconciliationView and auto-selects completed session', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final session = InventorySession(
        sessionId: 'SESS-AUTO-RECON-002',
        sessionCode: 'KK-AUTO-002',
        zone: 'Khu A',
        startedAt: DateTime.now().subtract(const Duration(minutes: 5)),
        completedAt: DateTime.now(),
        isCompleted: true,
        results: [
          InventoryItemResult(
            epc: 'EPC-RECON-003',
            sku: 'SKU-RECON-B',
            productName: 'Sản phẩm Đối Soát B',
            expectedLocation: 'Khu A',
            actualLocation: 'Khu A',
            resultType: InventoryVarianceType.match,
            readAt: DateTime.now(),
          ),
        ],
      );

      await repo.saveInventorySession(session);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const Scaffold(
            body: DesktopReportView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Bấm chuyển sang tab 'Đối Soát Tồn Kho (Dự Kiến vs Thực Tế)' trong mục Báo Cáo
      final tabFinder = find.text('Đối Soát Tồn Kho (Dự Kiến vs Thực Tế)');
      expect(tabFinder, findsOneWidget);
      await tester.tap(tabFinder);
      await tester.pumpAndSettle();

      // Kiểm tra DesktopStockReconciliationView hiển thị đợt kiểm kê đã hoàn tất và kết quả đối soát
      expect(find.byType(DesktopStockReconciliationView), findsOneWidget);
      expect(find.textContaining('KK-AUTO-002'), findsWidgets);
      expect(find.textContaining('ĐỘ CHÍNH XÁC KHO'), findsOneWidget);
    });
  });
}
