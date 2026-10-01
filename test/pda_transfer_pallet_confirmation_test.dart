import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/pda/pda_transfer_screen.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PDA Transfer Pallet Scanning & Confirmation Tests', () {
    late WarehouseRepository repo;
    late UhfService uhf;

    setUp(() async {
      repo = WarehouseRepository();
      uhf = UhfService();
      await repo.ensureInitialized();

      // Thêm 2 vị trí kệ
      final locA = Location(
        locationId: 'LOC-A1',
        locationCode: 'A1',
        zone: 'KHU_A',
        shelf: 'Kệ A1',
        level: 'Tầng 1',
      );
      final locB = Location(
        locationId: 'LOC-B2',
        locationCode: 'B2',
        zone: 'KHU_B',
        shelf: 'Kệ B2',
        level: 'Tầng 1',
      );
      await repo.addLocation(locA);
      await repo.addLocation(locB);

      // Thêm Pallet qua registerOrUpdatePallet
      await repo.registerOrUpdatePallet(
        palletCode: 'PAL-TEST-01',
        rfidEpc: 'EPC-PAL-01',
        locationId: locA.locationId,
      );

      final pallet = repo.pallets.firstWhere((p) => p.palletCode == 'PAL-TEST-01');

      // Thêm sản phẩm trên Pallet
      final item = Item(
        itemId: 'ITEM-PAL-01',
        productId: 'PROD-01',
        sku: 'SKU-01',
        productName: 'Sản phẩm Test Pallet',
        serialNumber: 'SN-001',
        epc: 'EPC-ITEM-01',
        status: ItemStatus.inStock,
        palletId: pallet.palletId,
        locationId: locA.locationId,
      );
      await repo.addItem(item);
    });

    testWidgets('PdaTransferScreen enables scanning and shows confirmation dialog upon shelf scan then pallet scan', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false, splashFactory: NoSplash.splashFactory),
          home: const PdaTransferScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Kiểm tra scanning đã được bật cho chuyen_kho
      expect(uhf.isScanAllowed, isTrue);
      expect(uhf.activeScanModule, 'chuyen_kho');

      // Bước 1: Mô phỏng quét Barcode của Kệ kho đích trước (A1)
      uhf.simulateBarcode('A1');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.textContaining('KỆ A1'), findsWidgets);

      // Bước 2: Mô phỏng quét Barcode của Pallet sau đó (PAL-TEST-01)
      uhf.simulateBarcode('PAL-TEST-01');
      await tester.pump();
      await tester.pumpAndSettle();

      // Hộp thoại xác nhận chuyển Pallet phải xuất hiện
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Xác Nhận Chuyển Pallet'), findsOneWidget);
      expect(find.text('Kiểm tra thông tin trước khi chuyển'), findsOneWidget);
      expect(find.text('PAL-TEST-01'), findsWidgets);

      // Thử bấm HỦY / QUÉT LẠI trong AlertDialog để tránh chuyển nhầm
      final cancelInDialog = find.descendant(of: find.byType(AlertDialog), matching: find.text('HỦY / QUÉT LẠI'));
      expect(cancelInDialog, findsOneWidget);
      await tester.tap(cancelInDialog);
      await tester.pumpAndSettle();

      // Hộp thoại phải đóng lại và Pallet vẫn ở vị trí cũ (chưa bị chuyển)
      expect(find.byType(AlertDialog), findsNothing);
      final palletBefore = repo.pallets.firstWhere((p) => p.palletCode == 'PAL-TEST-01');
      expect(palletBefore.locationId, 'LOC-A1');

      // Quét lại Pallet và xác nhận chuyển
      uhf.simulateBarcode('PAL-TEST-01');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      final confirmInDialog = find.descendant(of: find.byType(AlertDialog), matching: find.text('XÁC NHẬN CHUYỂN'));
      expect(confirmInDialog, findsOneWidget);
      await tester.tap(confirmInDialog);
      await tester.pumpAndSettle();

      // Kiểm tra chuyển kho thành công
      expect(find.text('Chuyển kho thành công!'), findsOneWidget);
      final palletAfter = repo.pallets.firstWhere((p) => p.palletCode == 'PAL-TEST-01');
      expect(palletAfter.locationId, isNotNull);
    });

    testWidgets('PdaTransferScreen Step 3 has both HỦY / QUÉT LẠI and XÁC NHẬN CHUYỂN buttons', (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1000));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false, splashFactory: NoSplash.splashFactory),
          home: const PdaTransferScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Bước 1: Quét Barcode Kệ đích trước
      uhf.simulateBarcode('A1');
      await tester.pump();
      await tester.pumpAndSettle();

      // Bước 2: Mô phỏng nhập thủ công mã pallet
      final textInput = find.byKey(const Key('pallet_barcode_input'));
      expect(textInput, findsOneWidget);
      await tester.enterText(textInput, 'PAL-TEST-01');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pumpAndSettle();

      // Đóng alert dialog bằng nút HỦY để kiểm tra giao diện bước 3 khi chọn lại
      expect(find.byType(AlertDialog), findsOneWidget);
      final cancelBtn = find.descendant(of: find.byType(AlertDialog), matching: find.text('HỦY / QUÉT LẠI'));
      await tester.tap(cancelBtn);
      await tester.pumpAndSettle();

      // Bấm chọn từ danh sách Pallet
      final pickerBtn = find.text('CHỌN TỪ DANH SÁCH PALLET');
      expect(pickerBtn, findsOneWidget);
      await tester.ensureVisible(pickerBtn);
      await tester.tap(pickerBtn);
      await tester.pumpAndSettle();

      // Chọn Pallet trong bottom sheet
      final chooseBtn = find.text('CHỌN');
      expect(chooseBtn, findsWidgets);
      await tester.tap(chooseBtn.first);
      await tester.pump();
      await tester.pumpAndSettle();

      // Hộp thoại xác nhận xuất hiện khi chọn từ danh sách
      expect(find.byType(AlertDialog), findsOneWidget);
      final confirmBtn = find.descendant(of: find.byType(AlertDialog), matching: find.text('XÁC NHẬN CHUYỂN'));
      expect(confirmBtn, findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('PdaTransferScreen supports reverse scan order: pallet first then shelf', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false, splashFactory: NoSplash.splashFactory),
          home: const PdaTransferScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Quét Pallet trước khi quét Kệ
      uhf.simulateBarcode('PAL-TEST-01');
      await tester.pump();
      await tester.pumpAndSettle();

      // Chưa mở AlertDialog vì chưa có kệ đích, mà hiện thông báo hướng dẫn
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.textContaining('Hãy quét Barcode Kệ đích'), findsOneWidget);

      // 2. Quét Kệ đích sau đó
      uhf.simulateBarcode('B2');
      await tester.pump();
      await tester.pumpAndSettle();

      // Bây giờ hộp thoại xác nhận đã xuất hiện với Kệ B2!
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('KỆ B2'), findsWidgets);
      expect(find.text('PAL-TEST-01'), findsWidgets);
    });

    testWidgets('PdaTransferScreen allows changing shelf with ĐỔI KỆ button', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false, splashFactory: NoSplash.splashFactory),
          home: const PdaTransferScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Quét Kệ A1
      uhf.simulateBarcode('A1');
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.textContaining('KỆ A1'), findsWidgets);

      // Bấm nút ĐỔI KỆ
      final changeShelfBtn = find.text('ĐỔI KỆ');
      expect(changeShelfBtn, findsOneWidget);
      await tester.tap(changeShelfBtn);
      await tester.pumpAndSettle();

      // Bước 1 quay về trạng thái nhập/quét Kệ
      expect(find.text('CHỌN TỪ DANH SÁCH KỆ'), findsOneWidget);
      expect(find.byKey(const Key('location_barcode_input')), findsOneWidget);
    });
  });
}
