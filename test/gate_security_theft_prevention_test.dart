import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/inventory_models.dart';
import 'package:uhf/screens/desktop/desktop_goods_delivery_view.dart';
import 'package:uhf/services/tower_light_service.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/services/warehouse_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Gate Security & Theft Prevention Tests (Chống thất thoát hàng hóa qua cổng)', () {
    late WarehouseRepository repo;
    late TowerLightService towerLight;
    late UhfService uhf;

    setUp(() async {
      repo = WarehouseRepository();
      towerLight = TowerLightService();
      uhf = UhfService();
      towerLight.turnOffAll();
      await repo.clearAllData(alsoClearCloud: false);

      // Thêm 1 sản phẩm mẫu đang lưu kho tại kệ A-01-01
      final sampleItem = Item(
        itemId: 'ITEM-TEST-001',
        productId: 'PROD-TEST-01',
        sku: 'SKU-VALUABLE-01',
        productName: 'Màn hình công nghiệp OLED',
        serialNumber: 'SN-OLED-001',
        epc: 'E280116060000204DB9E9999',
        locationId: 'A-01-01',
        palletId: 'PAL-01',
        status: ItemStatus.inStock,
      );

      repo.createOrAssignPallet(
        palletCode: 'PAL-01',
        locationId: 'A-01-01',
        newItems: [sampleItem],
      );
    });

    testWidgets('Quét chip trong kho qua cổng khi CHƯA CÓ ĐƠN XUẤT -> Bật Đèn Đỏ + Còi Hú, ghi log UNAUTHORIZED_EXIT và hiện Banner An Ninh', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(useMaterial3: false),
          home: const Scaffold(
            body: DesktopGoodsDeliveryView(isActive: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));

      // Ban đầu tháp đèn đang tắt
      expect(towerLight.currentStatus.isRed, isFalse);
      expect(towerLight.currentStatus.isBuzzerOn, isFalse);

      // Mô phỏng có người bê sản phẩm 'E280116060000204DB9E9999' qua Cổng RFID
      uhf.simulateTag('E280116060000204DB9E9999');
      await tester.pump(const Duration(milliseconds: 200));

      // 1. Đèn đỏ và Còi hú an ninh được kích hoạt
      expect(towerLight.currentStatus.isRed, isTrue);
      expect(towerLight.currentStatus.isBuzzerOn, isTrue);

      // 2. Banner báo động an ninh xuất hiện trên UI
      expect(find.textContaining('BÁO ĐỘNG AN NINH: PHÁT HIỆN 1 HÀNG HÓA TRONG KHO QUA CỔNG'), findsOneWidget);
      expect(find.textContaining('Màn hình công nghiệp OLED'), findsWidgets);
      expect(find.textContaining('Kệ: A-01-01'), findsWidgets);

      // 3. Log vòng đời thẻ được ghi nhận vào tag_lifecycle_logs với action UNAUTHORIZED_EXIT
      final logs = repo.tagLifecycleLogs.where((l) => l.epc == 'E280116060000204DB9E9999').toList();
      expect(logs.isNotEmpty, isTrue);
      expect(logs.first.action, equals(TagLifecycleAction.unauthorizedExit));
      expect(logs.first.fromLocation, equals('A-01-01'));
      expect(logs.first.notes, contains('PHÁT HIỆN QUA CỔNG TRÁI PHÉP'));

      // 4. Bấm nút TẮT CÒI trên banner an ninh
      final muteBtn = find.text('TẮT CÒI');
      expect(muteBtn, findsOneWidget);
      await tester.tap(muteBtn);
      await tester.pump(const Duration(milliseconds: 100));

      // Tháp đèn và còi đã được tắt
      expect(towerLight.currentStatus.isRed, isFalse);
      expect(towerLight.currentStatus.isBuzzerOn, isFalse);
    });
  });
}
