import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/screens/desktop/desktop_main_layout.dart';
import 'package:uhf/services/uhf_service.dart';
import 'package:uhf/theme/app_colors.dart';
import 'package:uhf/theme/app_theme.dart';
import 'package:uhf/widgets/hardware_trigger_feedback_banner.dart';
import 'package:uhf/widgets/putaway_barcode_modal.dart';

void main() {
  group('Milestone 2 & 3 — Seuic UTouch 2/C Hardware Trigger & Desktop Global Header Tests', () {
    tearDown(() {
      UhfService().simulateTrigger(false);
    });

    testWidgets('HardwareTriggerFeedbackBanner reacts to Seuic UTouch 2/C pistol trigger press and release', (WidgetTester tester) async {
      UhfService().simulateTrigger(false);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: const Scaffold(
            body: Column(
              children: [
                HardwareTriggerFeedbackBanner(),
              ],
            ),
          ),
        ),
      );

      // Initially shows idle standby prompt when trigger is not pressed
      expect(find.text('CÒ SÚNG SẴN SÀNG • BÓP CÒ ĐỂ QUÉT'), findsOneWidget);
      expect(find.text('⚡ ĐANG GIỮ CÒ SÚNG QUÉT'), findsNothing);

      // Press physical pistol trigger on Seuic UTouch 2 / UTouch C
      UhfService().simulateTrigger(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('⚡ ĐANG GIỮ CÒ SÚNG QUÉT'), findsOneWidget);
      expect(find.textContaining('tag/s'), findsOneWidget);

      // Release pistol trigger
      UhfService().simulateTrigger(false);
      await tester.pump();

      expect(find.text('⚡ ĐANG GIỮ CÒ SÚNG QUÉT'), findsNothing);
      expect(find.text('CÒ SÚNG SẴN SÀNG • BÓP CÒ ĐỂ QUÉT'), findsOneWidget);
    });

    testWidgets('HardwareTriggerFeedbackBanner displays customIdleLabel when provided', (WidgetTester tester) async {
      UhfService().simulateTrigger(false);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: const Scaffold(
            body: Column(
              children: [
                HardwareTriggerFeedbackBanner(
                  customIdleLabel: 'Bóp cò súng Seuic UTouch 2/C để quét',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Bóp cò súng Seuic UTouch 2/C để quét'), findsOneWidget);
    });

    testWidgets('PutawayBarcodeModal renders on 320px Seuic UTouch 2/C viewport without overflow', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: Scaffold(
            body: Center(
              child: PutawayBarcodeModal(
                barcode: 'PAL-SEUIC-001',
                orderNo: 'PO-2026-089',
                itemCount: 24,
                cartonName: 'Thùng Linh Kiện Điện Tử Công Nghiệp',
                receivedTime: DateTime(2026, 10, 8, 9, 30),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PutawayBarcodeModal), findsOneWidget);
      expect(find.text('TEM MÃ VẠCH THÙNG HÀNG XẾP KHO'), findsOneWidget);
      expect(find.text('PO-2026-089'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('DesktopMainLayout displays Unified Global Hardware Reader Status Header Bar', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: const DesktopMainLayout(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.byKey(const Key('desktop_global_hardware_header')), findsOneWidget);
      expect(find.textContaining('UHF GATE:'), findsOneWidget);
      expect(find.textContaining('dBm'), findsWidgets);
      expect(find.text('A1'), findsOneWidget);
      expect(find.text('A2'), findsOneWidget);
      expect(find.text('A3'), findsOneWidget);
      expect(find.text('A4'), findsOneWidget);

      // Flush startup timers
      await tester.pump(const Duration(seconds: 11));
      expect(tester.takeException(), isNull);
    });

    testWidgets('Industrial Dark Theme tokens enforce minimum 48dp touch height for gloved PDA operation', (WidgetTester tester) async {
      final theme = AppTheme.industrialDarkTheme;
      final elevatedMinSize = theme.elevatedButtonTheme.style?.minimumSize?.resolve({});
      final outlinedMinSize = theme.outlinedButtonTheme.style?.minimumSize?.resolve({});

      expect(elevatedMinSize, isNotNull);
      expect(elevatedMinSize!.height, greaterThanOrEqualTo(48.0));
      expect(outlinedMinSize, isNotNull);
      expect(outlinedMinSize!.height, greaterThanOrEqualTo(48.0));
      expect(theme.scaffoldBackgroundColor, equals(AppColors.slate900));
    });
  });
}
