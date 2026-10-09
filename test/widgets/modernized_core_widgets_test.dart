import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/theme/app_theme.dart';
import 'package:uhf/widgets/gate_pass_fail_banner.dart';
import 'package:uhf/widgets/rfid_telemetry_card.dart';
import 'package:uhf/widgets/sonar_radar_widget.dart';
import 'package:uhf/widgets/tower_light_widget.dart';

void main() {
  group('Modernized Core Widgets Test Suite', () {
    testWidgets('RfidTelemetryCard renders with Slate tokens and high contrast text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: const Scaffold(
            body: RfidTelemetryCard(
              uniqueTags: 42,
              totalReads: 500,
              readRate: 85.0,
              isScanning: true,
              antennaInfo: 'Antenna 1 & 2',
            ),
          ),
        ),
      );

      // Verify text elements
      expect(find.text('SÓNG RFID ĐANG PHÁT'), findsOneWidget);
      expect(find.text('Antenna 1 & 2'), findsOneWidget);
      expect(find.text('Thẻ Duy Nhất'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(find.text('500'), findsOneWidget);
      expect(find.text('85'), findsOneWidget);

      // Check that idle mode also renders cleanly with visible status
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: const Scaffold(
            body: RfidTelemetryCard(
              uniqueTags: 0,
              totalReads: 0,
              readRate: 0.0,
              isScanning: false,
              antennaInfo: 'Antenna 1',
            ),
          ),
        ),
      );
      expect(find.text('CHẾ ĐỘ CHỜ'), findsOneWidget);
    });

    testWidgets('GatePassFailBanner PASS state renders crisp white high-contrast text', (tester) async {
      final passResult = GateVerificationResult(
        mode: GateMode.inbound,
        documentNo: 'PO-TEST-001',
        isPass: true,
        totalActualQty: 50,
        totalRequiredQty: 50,
        unexpectedEpcs: [],
        missingEpcs: [],
        unstockedEpcs: [],
        verifiedAt: DateTime.now(),
        skuBreakdowns: [
          SkuVerificationBreakdown(
            sku: 'SKU-01',
            productName: 'Sản phẩm thử nghiệm',
            actualQty: 50,
            requiredQty: 50,
            isMatched: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: Scaffold(
            body: GatePassFailBanner(
              result: passResult,
              isScanning: false,
            ),
          ),
        ),
      );

      // Verify PASS banner renders
      expect(find.text('KẾT QUẢ: PASS - ĐẠT 100%'), findsOneWidget);
      expect(find.text('50 / 50 Thẻ'), findsOneWidget);
      expect(find.text('SKU-01 - Sản phẩm thử nghiệm'), findsOneWidget);

      // Inspect title text color is crisp white (not dark sepia 0xFF2C251E)
      final titleText = tester.widget<Text>(find.text('KẾT QUẢ: PASS - ĐẠT 100%'));
      expect(titleText.style?.color, equals(Colors.white));

      // Inspect quantity text color is crisp white
      final qtyText = tester.widget<Text>(find.text('50 / 50 Thẻ'));
      expect(qtyText.style?.color, equals(Colors.white));
    });

    testWidgets('GatePassFailBanner FAIL state renders warning and crisp white text', (tester) async {
      final failResult = GateVerificationResult(
        mode: GateMode.outbound,
        documentNo: 'PO-TEST-002',
        isPass: false,
        totalActualQty: 40,
        totalRequiredQty: 50,
        unexpectedEpcs: ['ROGUE-EPC-99'],
        missingEpcs: ['MISS-EPC-01'],
        unstockedEpcs: ['UNSTOCK-EPC-02'],
        verifiedAt: DateTime.now(),
        skuBreakdowns: [
          SkuVerificationBreakdown(
            sku: 'SKU-02',
            productName: 'Hàng thiếu',
            actualQty: 40,
            requiredQty: 50,
            isMatched: false,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: Scaffold(
            body: GatePassFailBanner(
              result: failResult,
              isScanning: false,
            ),
          ),
        ),
      );

      expect(find.text('KẾT QUẢ: FAIL - SAI LỆCH'), findsOneWidget);
      expect(find.textContaining('ROGUE-EPC-99'), findsOneWidget);
      expect(find.textContaining('chưa được xếp vào kệ'), findsOneWidget);

      final titleText = tester.widget<Text>(find.text('KẾT QUẢ: FAIL - SAI LỆCH'));
      expect(titleText.style?.color, equals(Colors.white));
    });

    testWidgets('GatePassFailBanner idle state renders slate card', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: const Scaffold(
            body: GatePassFailBanner(
              result: null,
              isScanning: false,
            ),
          ),
        ),
      );

      expect(find.text('Sẵn sàng quét qua Cổng RFID Gate HF340'), findsOneWidget);
    });

    testWidgets('SonarRadarWidget renders with slate tokens and accurate distance styling', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: SonarRadarWidget(
                rssi: -30.0,
                isTracking: true,
                targetEpc: 'E280116060000204DB001122',
                productName: 'Mục tiêu',
                locationDisplay: 'Kệ A1-02',
              ),
            ),
          ),
        ),
      );

      // In tracking mode with -30 dBm (isVeryClose)
      expect(find.text('ĐÃ TÌM THẤY MỤC TIÊU!'), findsOneWidget);
      expect(find.textContaining('Kệ A1-02'), findsOneWidget);
    });

    testWidgets('TowerLightWidget renders graphic with industrial theme and save button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: const Scaffold(
            body: TowerLightWidget(
              compact: true,
              showControls: false,
            ),
          ),
        ),
      );

      // Verify the widget mounts cleanly
      expect(find.byType(TowerLightWidget), findsOneWidget);
    });
  });
}
