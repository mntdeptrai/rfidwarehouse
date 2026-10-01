import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/screens/pda/pda_transfer_screen.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WarehouseRepository repo;
  late UhfService uhf;

  setUp(() async {
    repo = WarehouseRepository();
    uhf = UhfService();
    await repo.ensureInitialized();

    // Reset data cleanly
    await repo.clearAllData(alsoClearCloud: false);

    // Khởi tạo các kệ thử nghiệm
    await repo.addLocation(Location(
      locationId: 'LOC-A1',
      locationCode: 'A1',
      shelf: 'A1',
      zone: 'Khu A',
      level: 'Tầng 1',
    ));

    await repo.addLocation(Location(
      locationId: 'LOC-B1',
      locationCode: 'B1',
      shelf: 'B1',
      zone: 'Khu B',
      level: 'Tầng 1',
    ));

    // Sản phẩm SP-01 đang ở trên Kệ A1
    final itemOnA1 = Item(
      itemId: 'ITEM-01',
      productId: 'PROD-01',
      sku: 'SKU-01',
      productName: 'Sản phẩm Kệ A1',
      serialNumber: 'SN-001',
      epc: 'E28068940000000000000001',
      status: ItemStatus.inStock,
      locationId: 'LOC-A1',
    );

    // Sản phẩm SP-02 đang ở trên Kệ B1
    final itemOnB1 = Item(
      itemId: 'ITEM-02',
      productId: 'PROD-02',
      sku: 'SKU-02',
      productName: 'Sản phẩm Kệ B1',
      serialNumber: 'SN-002',
      epc: 'E28068940000000000000002',
      status: ItemStatus.inStock,
      locationId: 'LOC-B1',
    );

    await repo.addItem(itemOnA1);
    await repo.addItem(itemOnB1);
  });

  group('PDA Transfer Screen: 2-Step Flow & Target Shelf Duplicate Filtering', () {
    testWidgets('1. Tab Sản phẩm riêng lẻ starts in Step 1 (Barcode) without EPC card', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 850));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const PdaTransferScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Chuyển sang tab Sản phẩm riêng lẻ
      await tester.tap(find.text('Sản phẩm riêng lẻ'));
      await tester.pumpAndSettle();

      // Scanner mode phải là Barcode để quét tem Kệ kho đích, tránh conflict RFID
      expect(uhf.scanMode, PdaScanMode.barcode);

      // Hiển thị Step 1 indicator và thẻ Quét Barcode Kệ
      expect(find.text('1. Quét Kệ Đích'), findsOneWidget);
      expect(find.text('2. Quét Mã EPC'), findsOneWidget);
      expect(find.text('Quét Barcode của Kệ (Kho đích)'), findsOneWidget);

      // Thẻ Bước 2 quét EPC chưa hiển thị
      expect(find.text('Quét mã RFID EPC của sản phẩm'), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('2. Scanning shelf advances to Step 2 and switches hardware to RFID', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 850));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const PdaTransferScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Chuyển sang tab Sản phẩm riêng lẻ
      await tester.tap(find.text('Sản phẩm riêng lẻ'));
      await tester.pumpAndSettle();

      // Bắn laser barcode quét tem Kệ A1
      uhf.simulateBarcode('A1');
      await tester.pump();
      await tester.pumpAndSettle();

      // Tự động chuyển sang Step 2
      expect(find.textContaining('KỆ ĐÍCH: KỆ A1'), findsOneWidget);
      expect(find.text('Quét mã RFID EPC của sản phẩm'), findsOneWidget);

      // Hardware scanner tự động chuyển sang RFID để đọc chùm thẻ EPC
      expect(uhf.scanMode, PdaScanMode.rfid);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('3. Scanning EPC already on target shelf is rejected with clear warning', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 850));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const PdaTransferScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Chuyển sang tab Sản phẩm riêng lẻ
      await tester.tap(find.text('Sản phẩm riêng lẻ'));
      await tester.pumpAndSettle();

      // Quét Kệ A1
      uhf.simulateBarcode('A1');
      await tester.pump();
      await tester.pumpAndSettle();

      // Bóp cò quét RFID chip ITEM-01 (đang ở trên Kệ A1)
      uhf.simulateTrigger(true);
      await tester.pump();
      uhf.simulateTag('E28068940000000000000001');
      await tester.pump();
      uhf.simulateTrigger(false);
      await tester.pumpAndSettle();

      // Phải có thông báo lỗi cảnh báo sản phẩm đã ở trên kệ này rồi
      expect(find.textContaining('đã có trên kệ KỆ A1 rồi!'), findsWidgets);

      // Danh sách sản phẩm chuyển kho phải là 0
      expect(find.textContaining('Danh sách sản phẩm'), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('4. Scanning EPC from another shelf is accepted and adds to transfer list', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 850));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const PdaTransferScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Chuyển sang tab Sản phẩm riêng lẻ
      await tester.tap(find.text('Sản phẩm riêng lẻ'));
      await tester.pumpAndSettle();

      // Quét Kệ A1
      uhf.simulateBarcode('A1');
      await tester.pump();
      await tester.pumpAndSettle();

      // Bóp cò quét RFID chip ITEM-02 (đang ở trên Kệ B1)
      uhf.simulateTrigger(true);
      await tester.pump();
      uhf.simulateTag('E28068940000000000000002');
      await tester.pump();
      uhf.simulateTrigger(false);
      await tester.pumpAndSettle();

      // Sản phẩm hợp lệ được thêm vào danh sách
      expect(find.textContaining('Sản phẩm Kệ B1'), findsOneWidget);
      expect(find.textContaining('Danh sách sản phẩm (1)'), findsOneWidget);
      expect(find.text('XÁC NHẬN CẬP NHẬT VỊ TRÍ'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('5. Clicking ĐỔI KỆ returns to Step 1 and switches scanner back to Barcode', (tester) async {
      await tester.binding.setSurfaceSize(const Size(400, 850));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const PdaTransferScreen(),
        ),
      );
      await tester.pumpAndSettle();

      // Chuyển sang tab Sản phẩm riêng lẻ
      await tester.tap(find.text('Sản phẩm riêng lẻ'));
      await tester.pumpAndSettle();

      // Quét Kệ A1
      uhf.simulateBarcode('A1');
      await tester.pump();
      await tester.pumpAndSettle();

      expect(uhf.scanMode, PdaScanMode.rfid);

      // Bấm nút ĐỔI KỆ trên banner
      final changeShelfBtn = find.widgetWithText(OutlinedButton, 'ĐỔI KỆ');
      expect(changeShelfBtn, findsOneWidget);
      await tester.tap(changeShelfBtn);
      await tester.pumpAndSettle();

      // Quay lại Step 1
      expect(find.text('Kệ kho đích đã chọn'), findsOneWidget);
      expect(find.text('TIẾP TỤC: QUÉT SẢN PHẨM (BƯỚC 2) ➔'), findsOneWidget);
      // Scanner quay lại Barcode
      expect(uhf.scanMode, PdaScanMode.barcode);

      await tester.binding.setSurfaceSize(null);
    });
  });
}
