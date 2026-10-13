import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/catalog_models.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/desktop/desktop_product_management_view.dart';
import 'package:uhf/services/warehouse_repository.dart';
import 'package:uhf/theme/eye_care_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopProductManagementView Tests', () {
    late WarehouseRepository repo;

    setUp(() async {
      repo = WarehouseRepository();
      await repo.ensureInitialized();
    });

    testWidgets('renders standardized header bar and KPI metrics', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const Scaffold(
            body: DesktopProductManagementView(key: ValueKey('desktop_product_management')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Header Bar
      expect(find.text('DANH MỤC SẢN PHẨM & QUẢN LÝ SKU'), findsOneWidget);
      expect(find.byIcon(Icons.inventory_2_rounded), findsWidgets);

      // Verify KPI Metrics
      expect(find.text('TỔNG SỐ SKU'), findsOneWidget);
      expect(find.text('TỒN KHO THỰC TẾ'), findsOneWidget);
      expect(find.text('SKU CÓ TỒN KHO'), findsOneWidget);
      expect(find.text('NHÓM DANH MỤC'), findsOneWidget);

      // Verify Action Buttons
      expect(find.text('LÀM MỚI'), findsOneWidget);
      expect(find.text('XUẤT EXCEL'), findsOneWidget);
      expect(find.text('THÊM SẢN PHẨM'), findsOneWidget);
    });

    testWidgets('searches product by SKU or product name and opens add dialog', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));

      // Add a test product to repository
      await repo.addProduct(const Product(
        productId: 'PROD-TEST-SEARCH-01',
        sku: 'SKU-SEARCH-TEST',
        productName: 'Sản Phẩm Kiểm Thử Tìm Kiếm',
        unit: 'Hộp',
        category: 'Vật Tư',
        description: 'Mô tả thử nghiệm',
      ));

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: const Scaffold(
            body: DesktopProductManagementView(key: ValueKey('desktop_product_management')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify added product appears in table
      expect(find.text('SKU-SEARCH-TEST'), findsOneWidget);
      expect(find.text('Sản Phẩm Kiểm Thử Tìm Kiếm'), findsOneWidget);

      // Search by SKU
      await tester.enterText(find.byType(TextField).first, 'SEARCH-TEST');
      await tester.pumpAndSettle();
      expect(find.text('SKU-SEARCH-TEST'), findsOneWidget);

      // Search by non-matching query
      await tester.enterText(find.byType(TextField).first, 'KHONG-TON-TAI-XYZ');
      await tester.pumpAndSettle();
      expect(find.text('SKU-SEARCH-TEST'), findsNothing);

      // Clear search
      await tester.enterText(find.byType(TextField).first, '');
      await tester.pumpAndSettle();
      expect(find.text('SKU-SEARCH-TEST'), findsOneWidget);

      // Open Add Product Dialog
      await tester.tap(find.text('THÊM SẢN PHẨM'));
      await tester.pumpAndSettle();

      expect(find.text('THÊM SẢN PHẨM MỚI'), findsOneWidget);
      expect(find.text('Mã SKU *'), findsOneWidget);
      expect(find.text('Tên sản phẩm *'), findsOneWidget);

      await tester.tap(find.text('HỦY'));
      await tester.pumpAndSettle();
    });

    testWidgets('opens Create Inbound Order dialog from product row and creates inbound order with RFID', (tester) async {
      await tester.binding.setSurfaceSize(const Size(1366, 768));

      final testProd = const Product(
        productId: 'PROD-TEST-INBOUND-01',
        sku: 'SKU-INBOUND-ROW-01',
        productName: 'Thiết Bị Cảm Biến Kiểm Thử',
        unit: 'Bộ',
        category: 'Điện Tử',
        description: 'Mô tả thử nghiệm lập phiếu',
      );
      await repo.addProduct(testProd);

      bool didNavigate = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(splashFactory: InkRipple.splashFactory),
          home: Scaffold(
            body: DesktopProductManagementView(
              key: const ValueKey('desktop_product_management'),
              onNavigateToInbound: () => didNavigate = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Filter by the test product SKU so it is the only row
      await tester.enterText(find.byType(TextField).first, 'SKU-INBOUND-ROW-01');
      await tester.pumpAndSettle();

      // Find the quick create inbound order button on the product row
      final inboundBtn = find.byTooltip('Tạo phiếu nhập từ sản phẩm này');
      expect(inboundBtn, findsOneWidget);

      await tester.tap(inboundBtn);
      await tester.pumpAndSettle();

      // Dialog should appear
      expect(find.text('TẠO PHIẾU NHẬP KHO'), findsOneWidget);
      expect(find.text('Tự động sinh mã RFID chip (EPC) cho lô hàng'), findsOneWidget);
      expect(find.text('XÁC NHẬN TẠO PHIẾU'), findsOneWidget);

      // Confirm order creation
      await tester.tap(find.text('XÁC NHẬN TẠO PHIẾU'));
      await tester.pumpAndSettle();

      // Verify that navigation callback was invoked
      expect(didNavigate, isTrue);

      // Verify that the inbound order was created in repo
      expect(repo.inboundOrders.any((o) => o.details.any((d) => d.sku == 'SKU-INBOUND-ROW-01')), isTrue);
    });
  });
}
