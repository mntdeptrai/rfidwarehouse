import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/desktop/desktop_inventory_view.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopInventoryView & Inventory Session Sync Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
    });

    testWidgets('DesktopInventoryView displays synced sessions and refresh button works', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 1. Tạo một phiên kiểm kê giả lập hoàn tất như trên PDA
      final session = InventorySession(
        sessionId: 'SESS-SYNC-001',
        sessionCode: 'KK-TEST-001',
        zone: 'Khu Vực A',
        locationCode: 'A-01-01',
        startedAt: DateTime.now().subtract(const Duration(minutes: 10)),
        completedAt: DateTime.now(),
        isCompleted: true,
        results: [
          InventoryItemResult(
            epc: 'E28068940000000000000001',
            sku: 'SKU-TEST-01',
            productName: 'Sản phẩm Test 1',
            expectedLocation: 'A-01-01',
            actualLocation: 'A-01-01',
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
            body: DesktopInventoryView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra xem tiêu đề đợt kiểm kê có hiển thị (ít nhất 1 đợt)
      expect(find.textContaining('LỊCH SỬ CÁC ĐỢT KIỂM KÊ ĐÃ THỰC HIỆN'), findsOneWidget);
      expect(find.text('KK-TEST-001'), findsOneWidget);
      expect(find.text('ĐÃ HOÀN TẤT'), findsOneWidget);

      // Kiểm tra nút Làm mới
      final refreshBtn = find.text('Làm mới');
      expect(refreshBtn, findsOneWidget);
      await tester.tap(refreshBtn);
      await tester.pumpAndSettle();

      expect(find.text('KK-TEST-001'), findsOneWidget);

      // Dọn dẹp
      await repo.deleteInventorySession('SESS-SYNC-001');
    });

    test('completeInventorySession updates isCompleted and records transaction', () async {
      final session = repo.startInventorySession(
        zone: 'Zone B',
        locationCode: 'B-01-01',
      );

      expect(session.isCompleted, isFalse);

      await repo.completeInventorySession(session.sessionId, 'Thủ Kho Test');

      final found = repo.inventorySessions.firstWhere((s) => s.sessionId == session.sessionId);
      expect(found.isCompleted, isTrue);
      expect(found.completedAt, isNotNull);

      // Dọn dẹp
      await repo.deleteInventorySession(session.sessionId);
    });
  });
}
