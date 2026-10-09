import 'dart:convert';
import 'dart:typed_data';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/inventory_models.dart';
import 'package:uhf/models/order_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_delivery_view.dart';
import 'package:uhf/services/excel_import_service.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WarehouseRepository repo;
  late ExcelImportService excelService;

  setUp(() async {
    repo = WarehouseRepository();
    await repo.ensureInitialized();
    await repo.ensureDefault10Locations();
    excelService = ExcelImportService();
  });

  group('Outbound Excel Import: Mã SKU, Mã Hàng, Số Lượng (Không cần EPC)', () {
    test('1. parseOutboundExcelBytes phân tích chuẩn file Excel chỉ gồm SKU, Mã Hàng, Số lượng', () {
      final excel = Excel.createExcel();
      final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
      final sheet = excel[sheetName];

      // Ghi dòng tiêu đề không có cột EPC
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0)).value = TextCellValue('Mã SKU');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 0)).value = TextCellValue('Mã Hàng');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 0)).value = TextCellValue('Số Lượng');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 0)).value = TextCellValue('Tên Sản Phẩm');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 0)).value = TextCellValue('Khách Hàng');

      // Ghi 2 dòng dữ liệu
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('SKU-JEAN-01');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value = TextCellValue('PROD-JEAN-01');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).value = TextCellValue('3');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1)).value = TextCellValue('Quần Jean Nam');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1)).value = TextCellValue('Đại Lý Miền Nam');

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 2)).value = TextCellValue('SKU-SHIRT-02');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 2)).value = TextCellValue('PROD-SHIRT-02');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 2)).value = TextCellValue('2');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 2)).value = TextCellValue('Áo Sơ Mi Nam');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 2)).value = TextCellValue('Đại Lý Miền Nam');

      final bytes = Uint8List.fromList(excel.encode()!);
      final result = excelService.parseOutboundExcelBytes(bytes, fileName: 'Xuat_Kho_Test.xlsx');

      expect(result.rows.length, 2);
      expect(result.rows[0].sku, 'SKU-JEAN-01');
      expect(result.rows[0].productId, 'PROD-JEAN-01');
      expect(result.rows[0].quantity, 3);
      expect(result.rows[0].epc, isNull); // Không cần khai báo EPC

      expect(result.rows[1].sku, 'SKU-SHIRT-02');
      expect(result.rows[1].productId, 'PROD-SHIRT-02');
      expect(result.rows[1].quantity, 2);
      expect(result.rows[1].epc, isNull);

      expect(result.totalRequestedQuantity, 5);
      expect(result.customer, 'Đại Lý Miền Nam');
    });

    test('2. parseOutboundExcelBytes phân tích file CSV không có cột EPC', () {
      const csvContent = '''Mã SKU,Mã Hàng,Số Lượng,Tên Sản Phẩm,Khách Hàng
SKU-TEST-A,PROD-TEST-A,4,Sản Phẩm A,Khách Hàng ABC
SKU-TEST-B,PROD-TEST-B,1,Sản Phẩm B,Khách Hàng ABC''';
      final bytes = Uint8List.fromList(utf8.encode(csvContent));
      final result = excelService.parseOutboundExcelBytes(bytes, isCsv: true, fileName: 'test.csv');

      expect(result.rows.length, 2);
      expect(result.rows[0].sku, 'SKU-TEST-A');
      expect(result.rows[0].productId, 'PROD-TEST-A');
      expect(result.rows[0].quantity, 4);
      expect(result.rows[1].sku, 'SKU-TEST-B');
      expect(result.rows[1].quantity, 1);
      expect(result.totalRequestedQuantity, 5);
      expect(result.customer, 'Khách Hàng ABC');
    });

    test('3. validateOutboundInventoryAndFifo tự động khớp và phân bổ tồn kho FIFO theo SKU/Mã Hàng khi không có EPC', () async {
      final loc = repo.locations.first;

      final time1 = DateTime.now().subtract(const Duration(days: 10));
      final time2 = DateTime.now().subtract(const Duration(days: 5));
      final time3 = DateTime.now().subtract(const Duration(days: 1));

      final testEpcs = [
        'E280119100000000000000A1',
        'E280119100000000000000A2',
        'E280119100000000000000A3',
      ];

      for (var epc in testEpcs) {
        await repo.deleteItem(epc);
      }

      await repo.addItem(Item(
        itemId: 'ITEM-TEST-MATCH-01',
        productId: 'PROD-TEST-POLO',
        sku: 'SKU-TEST-POLO',
        productName: 'Áo Polo Test',
        serialNumber: 'SN-01',
        epc: testEpcs[0],
        locationId: loc.locationId,
        status: ItemStatus.inStock,
        inboundTime: time1,
      ));

      await repo.addItem(Item(
        itemId: 'ITEM-TEST-MATCH-02',
        productId: 'PROD-TEST-POLO',
        sku: 'SKU-TEST-POLO',
        productName: 'Áo Polo Test',
        serialNumber: 'SN-02',
        epc: testEpcs[1],
        locationId: loc.locationId,
        status: ItemStatus.inStock,
        inboundTime: time2,
      ));

      await repo.addItem(Item(
        itemId: 'ITEM-TEST-MATCH-03',
        productId: 'PROD-TEST-POLO',
        sku: 'SKU-TEST-POLO',
        productName: 'Áo Polo Test',
        serialNumber: 'SN-03',
        epc: testEpcs[2],
        locationId: loc.locationId,
        status: ItemStatus.inStock,
        inboundTime: time3,
      ));

      // Yêu cầu xuất 2 cái SKU-TEST-POLO mà KHÔNG có mã EPC
      final requestedItems = [
        {
          'sku': 'SKU-TEST-POLO',
          'productId': 'PROD-TEST-POLO',
          'itemId': 'PROD-TEST-POLO',
          'productName': 'Áo Polo Test',
          'epc': '--',
        },
        {
          'sku': 'SKU-TEST-POLO',
          'productId': 'PROD-TEST-POLO',
          'itemId': 'PROD-TEST-POLO',
          'productName': 'Áo Polo Test',
          'epc': '--',
        },
      ];

      final validation = repo.validateOutboundInventoryAndFifo(requestedItems: requestedItems);

      expect(validation.isStockSufficient, isTrue);
      expect(validation.shortageCount, 0);
      expect(validation.items.length, 2);

      // Phải ưu tiên gán 2 sản phẩm cũ nhất theo chuẩn FIFO: testEpcs[0] và testEpcs[1]
      expect(validation.items[0].epc, testEpcs[0]);
      expect(validation.items[0].locationCode, loc.locationCode);
      expect(validation.items[0].fifoPriority, 1);

      expect(validation.items[1].epc, testEpcs[1]);
      expect(validation.items[1].locationCode, loc.locationCode);
      expect(validation.items[1].fifoPriority, 2);

      for (var epc in testEpcs) {
        await repo.deleteItem(epc);
      }
    });

    test('4. validateOutboundInventoryAndFifo phát hiện và cảnh báo thiếu hàng khi số lượng yêu cầu vượt quá tồn kho', () async {
      const testSku = 'SKU-TEST-SHORTAGE-X';
      const testEpc = 'E280119100000000000000B1';
      await repo.deleteItem(testEpc);

      await repo.addItem(Item(
        itemId: 'ITEM-TEST-SHORTAGE-1',
        productId: 'PROD-TEST-SHORTAGE',
        sku: testSku,
        productName: 'Giày Da Test',
        serialNumber: 'SN-BOOT-1',
        epc: testEpc,
        status: ItemStatus.inStock,
      ));

      // Yêu cầu xuất 3 đôi trong khi kho chỉ có 1 đôi
      final requestedItems = [
        {'sku': testSku, 'productId': 'PROD-TEST-SHORTAGE', 'epc': '--'},
        {'sku': testSku, 'productId': 'PROD-TEST-SHORTAGE', 'epc': '--'},
        {'sku': testSku, 'productId': 'PROD-TEST-SHORTAGE', 'epc': '--'},
      ];

      final validation = repo.validateOutboundInventoryAndFifo(requestedItems: requestedItems);

      expect(validation.isStockSufficient, isFalse);
      expect(validation.shortageCount, 2); // Thiếu 2 đôi
      expect(validation.shortageBySku[testSku], 2);
      expect(validation.items.where((i) => i.isInStock).length, 1);
      expect(validation.items.where((i) => !i.isInStock).length, 2);

      await repo.deleteItem(testEpc);
    });

    test('5. exportOutboundTemplate sinh file mẫu thành công với đầy đủ cột Mã SKU, Mã Hàng, Số Lượng', () async {
      final templatePath = await excelService.exportOutboundTemplate(fileName: 'Test_Mau_Xuat_Kho.xlsx');
      expect(templatePath.isNotEmpty, isTrue);
      expect(templatePath.endsWith('Test_Mau_Xuat_Kho.xlsx'), isTrue);
    });

    testWidgets('6. DesktopGoodsDeliveryView tự động đối chiếu chip EPC từ CSDL khi đơn chỉ khai báo SKU và số lượng', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testSku = 'SKU-AUTO-MATCH-01';
      const testProdId = 'PROD-AUTO-MATCH-01';
      const testEpc = 'E28011910000000000000077';

      await repo.clearAllData(alsoClearCloud: false);
      await repo.ensureDefault10Locations();

      final loc = repo.locations.first;
      await repo.addItem(Item(
        itemId: 'ITEM-AUTO-MATCH-01',
        productId: testProdId,
        sku: testSku,
        productName: 'Áo Khoác Gió RFID',
        serialNumber: 'SN-JACKET-01',
        epc: testEpc,
        locationId: loc.locationId,
        status: ItemStatus.inStock,
        inboundTime: DateTime.now().subtract(const Duration(days: 2)),
      ));

      // Tạo đơn xuất kho chỉ có SKU và số lượng = 1 (epcList = null)
      final order = OutboundOrder(
        outboundOrderId: 'ORD-NO-EPC-001',
        poNo: 'PO-NO-EPC-001',
        customer: 'Công ty Test Matching',
        createdAt: DateTime.now(),
        status: OutboundOrderStatus.newOrder,
        details: [
          OutboundOrderDetail(
            productId: testProdId,
            sku: testSku,
            productName: 'Áo Khoác Gió RFID',
            requiredQty: 1,
            pickedQty: 0,
            epcList: null, // Không khai báo EPC
          ),
        ],
      );
      await repo.addOutboundOrder(order);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: DesktopGoodsDeliveryView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Mở PopupMenu và chọn đơn PO-NO-EPC-001
      final selectOrderBtn = find.text('XUẤT HÀNG');
      expect(selectOrderBtn, findsOneWidget);
      await tester.tap(selectOrderBtn);
      await tester.pumpAndSettle();

      final fromDbOption = find.textContaining('Chọn Đơn Xuất Có Sẵn');
      expect(fromDbOption, findsOneWidget);
      await tester.tap(fromDbOption);
      await tester.pumpAndSettle();

      // Bấm chọn đơn PO-NO-EPC-001
      final pickOrderBtn = find.widgetWithText(ElevatedButton, 'CHỌN');
      expect(pickOrderBtn, findsOneWidget);
      await tester.tap(pickOrderBtn);
      await tester.pumpAndSettle();

      // Kiểm tra đơn đã nạp: tổng yêu cầu 1 sản phẩm
      expect(find.textContaining('PO-NO-EPC-001'), findsWidgets);

      // Quét chip testEpc qua đầu đọc UHF
      final uhf = UhfService();
      uhf.simulateTag(testEpc);
      await tester.pump(const Duration(milliseconds: 300));

      // Chip testEpc trong CSDL tự động khớp ngầm với slot SKU-AUTO-MATCH-01
      // Kiểm tra icon check_circle xuất hiện trên dòng đã quét khớp thành công (do cột EPC đã được ẩn theo thiết kế)
      expect(find.byIcon(Icons.check_circle), findsWidgets);
      expect(find.textContaining('1 / 1'), findsWidgets);

      await tester.pump(const Duration(seconds: 5));
      await repo.deleteItem(testEpc);
    });

    test('7. Mẫu Nhập kho chi tiết (Ảnh 1): exportGoodsReceiveTemplate và parse phân biệt rõ SN với EPC', () {
      final excel = Excel.createExcel();
      final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
      final sheet = excel[sheetName];

      // Đúng 8 cột theo Ảnh 1
      final headers = ['CARTON CODE', 'EPC', 'NAME', 'SN', 'SKU', 'NCC', 'BARCODE PALET', 'EPC PALLET'];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      // Dữ liệu dòng mẫu 1
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('CARTON-POLO-001');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value = TextCellValue('810000000001');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).value = TextCellValue('Chứng từ 1');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1)).value = TextCellValue('SN-810000000001');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1)).value = TextCellValue('SKU-CHUNG-TU');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 1)).value = TextCellValue('Tổng Công Ty May Việt Tiến');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 1)).value = TextCellValue('PL-02');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: 1)).value = TextCellValue('E2806894000050322C76D473');

      final bytes = Uint8List.fromList(excel.encode()!);
      final (cartons, validRows) = excelService.parseBytes(bytes);
      expect(validRows, 1);
      expect(cartons.length, 1);
      final firstCarton = cartons.first;
      expect(firstCarton['cartonBox'], 'CARTON-POLO-001');
      expect(firstCarton['palletCode'], 'PL-02');
      expect(firstCarton['palletEpc'], 'E2806894000050322C76D473');
      expect(firstCarton['supplier'], 'Tổng Công Ty May Việt Tiến');

      final serialItems = firstCarton['serialItems'] as List<dynamic>;
      expect(serialItems.length, 1);
      final sItem = serialItems.first as Map<String, dynamic>;
      expect(sItem['serial'], '810000000001'); // Mã EPC
      expect(sItem['serialNumber'], 'SN-810000000001'); // Mã SN tách biệt
      expect(sItem['barcode'], 'SKU-CHUNG-TU');
      expect(sItem['name'], 'Chứng từ 1');
    });

    test('8. Mẫu Xuất kho gom Pallet (Ảnh 2): parseOutboundExcelBytes nhận diện chuẩn 7 cột', () {
      final excel = Excel.createExcel();
      final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
      final sheet = excel[sheetName];

      // Đúng 7 cột theo Ảnh 2
      final headers = ['CARTON CODE', 'NAME', 'SL', 'SKU', 'NCC', 'BARCODE PALET', 'EPC PALLET'];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('CARTON-POLO-001');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value = TextCellValue('Chứng từ 1');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).value = TextCellValue('10');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1)).value = TextCellValue('SKU-CHUNG-TU');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: 1)).value = TextCellValue('Tổng Công Ty May Việt Tiến');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 1)).value = TextCellValue('PL-02');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 1)).value = TextCellValue('E2806894000050322C76D473');

      final bytes = Uint8List.fromList(excel.encode()!);
      final result = excelService.parseOutboundExcelBytes(bytes, fileName: 'Xuat_Pallet.xlsx');

      expect(result.rows.length, 1);
      final r = result.rows.first;
      expect(r.cartonCode, 'CARTON-POLO-001');
      expect(r.productName, 'Chứng từ 1');
      expect(r.quantity, 10);
      expect(r.sku, 'SKU-CHUNG-TU');
      expect(r.supplier, 'Tổng Công Ty May Việt Tiến');
      expect(r.palletCode, 'PL-02');
      expect(r.palletEpc, 'E2806894000050322C76D473');
      expect(r.epc, isNull); // Đơn xuất không cần khai báo chip EPC của từng con hàng
    });

    test('9. Mẫu Xuất kho Lẻ (Ảnh 3): parseOutboundExcelBytes nhận diện chuẩn 4 cột', () {
      final excel = Excel.createExcel();
      final sheetName = excel.getDefaultSheet() ?? 'Sheet1';
      final sheet = excel[sheetName];

      // Đúng 4 cột theo Ảnh 3
      final headers = ['CARTON CODE', 'NAME', 'SL', 'SKU'];
      for (int i = 0; i < headers.length; i++) {
        sheet.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = TextCellValue(headers[i]);
      }

      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 1)).value = TextCellValue('CARTON-POLO-001');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: 1)).value = TextCellValue('Chứng từ 1');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: 1)).value = TextCellValue('10');
      sheet.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: 1)).value = TextCellValue('SKU-CHUNG-TU');

      final bytes = Uint8List.fromList(excel.encode()!);
      final result = excelService.parseOutboundExcelBytes(bytes, fileName: 'Xuat_Le.xlsx');

      expect(result.rows.length, 1);
      final r = result.rows.first;
      expect(r.cartonCode, 'CARTON-POLO-001');
      expect(r.productName, 'Chứng từ 1');
      expect(r.quantity, 10);
      expect(r.sku, 'SKU-CHUNG-TU');
      expect(r.epc, isNull);
    });

    testWidgets('10. Quét chip EPC tại cổng xuất tự động match slot SKU và hiển thị đúng mã SN từ CSDL', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const testSku = 'SKU-SN-MATCH-88';
      const testProdId = 'PROD-SN-MATCH-88';
      const testEpc = 'E2806894000050322C76D088';
      const testSn = 'SN-810000000088';

      await repo.clearAllData(alsoClearCloud: false);
      await repo.ensureDefault10Locations();

      final loc = repo.locations.first;
      await repo.addItem(Item(
        itemId: 'ITEM-SN-MATCH-88',
        productId: testProdId,
        sku: testSku,
        productName: 'Áo Sơ Mi Việt Tiến',
        serialNumber: testSn,
        epc: testEpc,
        locationId: loc.locationId,
        status: ItemStatus.inStock,
      ));

      // Đơn xuất chỉ có SKU và SL = 1, không có mã EPC
      final order = OutboundOrder(
        outboundOrderId: 'ORD-SN-TEST-88',
        poNo: 'PO-SN-TEST-88',
        customer: 'Khách đối soát SN',
        createdAt: DateTime.now(),
        status: OutboundOrderStatus.newOrder,
        details: [
          OutboundOrderDetail(
            productId: testProdId,
            sku: testSku,
            productName: 'Áo Sơ Mi Việt Tiến',
            requiredQty: 1,
            pickedQty: 0,
            epcList: null,
          ),
        ],
      );
      await repo.addOutboundOrder(order);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: DesktopGoodsDeliveryView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Mở PopupMenu chọn đơn
      final selectOrderBtn = find.text('XUẤT HÀNG');
      expect(selectOrderBtn, findsOneWidget);
      await tester.tap(selectOrderBtn);
      await tester.pumpAndSettle();

      final fromDbOption = find.textContaining('Chọn Đơn Xuất Có Sẵn');
      expect(fromDbOption, findsOneWidget);
      await tester.tap(fromDbOption);
      await tester.pumpAndSettle();

      final pickOrderBtn = find.widgetWithText(ElevatedButton, 'CHỌN');
      expect(pickOrderBtn, findsOneWidget);
      await tester.tap(pickOrderBtn);
      await tester.pumpAndSettle();

      // Trước khi quét: cột MÃ SN hiển thị '--'
      expect(find.text(testSn), findsNothing);

      // Quét chip testEpc qua đầu đọc RFID
      final uhf = UhfService();
      uhf.simulateTag(testEpc);
      await tester.pump(const Duration(milliseconds: 300));

      // Sau khi quét: hệ thống tự động đối chiếu EPC trong CSDL và hiển thị đúng mã SN: SN-810000000088
      expect(find.text(testSn), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsWidgets);

      await tester.pump(const Duration(seconds: 5));
      await repo.deleteItem(testEpc);
    });
  });
}
