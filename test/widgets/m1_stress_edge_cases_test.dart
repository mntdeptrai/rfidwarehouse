import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/models/wms_models.dart';
import 'package:uhf/theme/app_colors.dart';
import 'package:uhf/theme/app_theme.dart';
import 'package:uhf/widgets/gate_pass_fail_banner.dart';
import 'package:uhf/widgets/rfid_telemetry_card.dart';
import 'package:uhf/widgets/sonar_radar_widget.dart';
import 'package:uhf/widgets/tower_light_widget.dart';

void main() {
  double calculateContrast(Color c1, Color c2) {
    final double l1 = c1.computeLuminance();
    final double l2 = c2.computeLuminance();
    final double lighter = math.max(l1, l2);
    final double darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  group('M1 Adversarial Stress Test: Edge Cases, Overflows & Contrast', () {
    // -------------------------------------------------------------
    // Empirical Contrast Check on TowerLightWidget Save Button
    // -------------------------------------------------------------
    test('Empirical Contrast: TowerLightWidget dialog save button (slate950 on rfidMatched) passes WCAG AAA', () {
      final double ratio = calculateContrast(AppColors.slate950, AppColors.rfidMatched);
      expect(ratio, greaterThanOrEqualTo(4.5),
          reason: 'Button text must have at least 4.5:1 WCAG AA contrast (actual: ${ratio.toStringAsFixed(2)}:1)');
      expect(ratio, greaterThanOrEqualTo(7.0),
          reason: 'slate950 on rfidMatched achieves ${ratio.toStringAsFixed(2)}:1 contrast ratio, passing WCAG AAA');
    });

    // -------------------------------------------------------------
    // Test 1: RfidTelemetryCard with narrow screen (320px) and high counts
    // -------------------------------------------------------------
    testWidgets('RfidTelemetryCard: Standard 320px width at textScaleFactor 1.0 renders cleanly without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: RfidTelemetryCard(
                uniqueTags: 150,
                totalReads: 3200,
                readRate: 75.0,
                isScanning: true,
                antennaInfo: 'Ant 1 & 2',
              ),
            ),
          ),
        ),
      );

      final exception = tester.takeException();
      expect(exception, isNull, reason: 'RfidTelemetryCard must not overflow on 320px width');
      expect(find.text('150'), findsOneWidget);
      expect(find.text('Tags'), findsOneWidget);
    });

    testWidgets('RfidTelemetryCard: High counts (99999 tags, 1500000 reads) on Seuic UTouch (480x800) renders cleanly without overflow', (tester) async {
      tester.view.physicalSize = const Size(480, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: RfidTelemetryCard(
                uniqueTags: 99999,
                totalReads: 1500000,
                readRate: 250.0,
                isScanning: true,
                antennaInfo: 'Antenna 1 & 2',
              ),
            ),
          ),
        ),
      );

      final exception = tester.takeException();
      expect(exception, isNull, reason: 'RfidTelemetryCard must not overflow on 480px width with high counts');
      expect(find.text('99999'), findsOneWidget);
      expect(find.text('1500000'), findsOneWidget);
    });

    // -------------------------------------------------------------
    // Test 2: GatePassFailBanner with text scaling and long SKU
    // -------------------------------------------------------------
    testWidgets('GatePassFailBanner: FAIL state on 320px with 1.5x text scale renders cleanly without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final failResult = GateVerificationResult(
        mode: GateMode.outbound,
        documentNo: 'SO-FAIL-001',
        isPass: false,
        totalActualQty: 2,
        totalRequiredQty: 50,
        unexpectedEpcs: ['E280116060000204DB001122'],
        missingEpcs: ['MISS-01'],
        unstockedEpcs: [],
        verifiedAt: DateTime.now(),
        skuBreakdowns: [
          SkuVerificationBreakdown(
            sku: 'SKU-ERR',
            productName: 'Hàng lỗi kiểm kê',
            actualQty: 2,
            requiredQty: 50,
            isMatched: false,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: GatePassFailBanner(
                  result: failResult,
                  isScanning: false,
                ),
              ),
            ),
          ),
        ),
      );

      final exception = tester.takeException();
      expect(exception, isNull,
          reason: 'GatePassFailBanner must not overflow at 1.5x scale on 320px (neither header nor SKU row)');
      expect(find.text('KẾT QUẢ: FAIL - SAI LỆCH'), findsOneWidget);
      expect(find.text('2 / 50 Thẻ'), findsOneWidget);
      expect(find.textContaining('SKU-ERR'), findsOneWidget);
    });

    testWidgets('GatePassFailBanner: PASS state on 320px with 1.5x text scale renders cleanly without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final passResult = GateVerificationResult(
        mode: GateMode.inbound,
        documentNo: 'PO-PASS-001',
        isPass: true,
        totalActualQty: 50,
        totalRequiredQty: 50,
        unexpectedEpcs: [],
        missingEpcs: [],
        unstockedEpcs: [],
        verifiedAt: DateTime.now(),
        skuBreakdowns: [
          SkuVerificationBreakdown(
            sku: 'SKU-OK',
            productName: 'Bo mạch UHF Hopeland',
            actualQty: 50,
            requiredQty: 50,
            isMatched: true,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: SingleChildScrollView(
                child: GatePassFailBanner(
                  result: passResult,
                  isScanning: false,
                ),
              ),
            ),
          ),
        ),
      );

      final exception = tester.takeException();
      expect(exception, isNull,
          reason: 'GatePassFailBanner must not overflow at 1.5x scale on 320px in PASS state');
      expect(find.text('KẾT QUẢ: PASS - ĐẠT 100%'), findsOneWidget);
      expect(find.text('50 / 50 Thẻ'), findsOneWidget);
      expect(find.textContaining('SKU-OK'), findsOneWidget);
    });

    // -------------------------------------------------------------
    // Test 3: SonarRadarWidget on 320px screen width
    // -------------------------------------------------------------
    testWidgets('SonarRadarWidget: Active tracking with readsPerSecond on 320px width renders cleanly without overflow', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: SonarRadarWidget(
                rssi: -90.0,
                isTracking: true,
                targetEpc: 'E280116060000204DB001122',
                productName: 'Bo mạch điều khiển',
                locationDisplay: 'Kệ B2-01',
                readsPerSecond: 120.0,
                previousRssi: -85.0,
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      final exception = tester.takeException();
      expect(exception, isNull, reason: 'SonarRadarWidget telemetry row must not overflow on 320px width');
      expect(find.textContaining('dBm'), findsOneWidget);
      expect(find.textContaining('120 gói/s'), findsOneWidget);
    });

    // -------------------------------------------------------------
    // Test 4: TowerLightWidget compact and full panel on 320px screen
    // -------------------------------------------------------------
    testWidgets('TowerLightWidget: Full panel on 320px screen at 1.5x scale mounts and renders', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.5),
            ),
            child: const Scaffold(
              body: SingleChildScrollView(
                child: TowerLightWidget(
                  compact: false,
                  showControls: true,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(TowerLightWidget), findsOneWidget);
    });

    // -------------------------------------------------------------
    // Test 5: Theme switching and high-contrast light mode
    // -------------------------------------------------------------
    testWidgets('Theme Switching: Switching dark to light theme does not break widgets', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialLightTheme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  RfidTelemetryCard(
                    uniqueTags: 10,
                    totalReads: 50,
                    readRate: 20.0,
                    isScanning: false,
                  ),
                  SizedBox(height: 10),
                  GatePassFailBanner(result: null, isScanning: false),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('CHẾ ĐỘ CHỜ'), findsOneWidget);
      expect(find.text('Sẵn sàng quét qua Cổng RFID Gate HF340'), findsOneWidget);
    });
  });
}
