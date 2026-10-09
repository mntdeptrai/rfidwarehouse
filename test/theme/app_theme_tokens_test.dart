import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/theme/eye_care_theme.dart';

void main() {
  // Helper to calculate WCAG 2.1 relative luminance
  double calculateRelativeLuminance(Color color) {
    return color.computeLuminance();
  }

  // Helper to calculate WCAG contrast ratio between two colors
  double calculateContrastRatio(Color c1, Color c2) {
    final double l1 = calculateRelativeLuminance(c1);
    final double l2 = calculateRelativeLuminance(c2);
    final double lighter = math.max(l1, l2);
    final double darker = math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  // Legacy paper colors that must be completely absent from active theme tokens
  const Set<int> legacyPaperHexValues = {
    0xFFF4EFE6, // Legacy soft sepia bgDeep
    0xFFE9E2D5, // Legacy soft sepia bgCard
    0xFFDFD6C7, // Legacy soft sepia bgCardElevated
    0xFFC7BDAF, // Legacy soft sepia border
    0xFFB5A999, // Legacy soft sepia borderLight
    0xFF2C251E, // Legacy textPrimary
    0xFF6B5D4D, // Legacy textSecondary
    0xFF8F8070, // Legacy textMuted
  };

  group('F1: Modern Tech Color Palette (Tier 1)', () {
    test('1.1 AppColors Slate palette defines exact Industrial Modern Tech hex codes', () {
      expect(AppColors.slate950, const Color(0xFF020617));
      expect(AppColors.slate900, const Color(0xFF0F172A));
      expect(AppColors.slate850, const Color(0xFF172033));
      expect(AppColors.slate800, const Color(0xFF1E293B));
      expect(AppColors.slate750, const Color(0xFF24334A));
      expect(AppColors.slate700, const Color(0xFF334155));
      expect(AppColors.slate600, const Color(0xFF475569));
      expect(AppColors.slate500, const Color(0xFF64748B));
      expect(AppColors.slate400, const Color(0xFF94A3B8));
      expect(AppColors.slate300, const Color(0xFFCBD5E1));
      expect(AppColors.slate200, const Color(0xFFE2E8F0));
      expect(AppColors.slate100, const Color(0xFFF1F5F9));
      expect(AppColors.slate50, const Color(0xFFF8FAFC));
    });

    test('1.2 AppColors modern accents define Electric Cyan and Tech Blue families', () {
      expect(AppColors.electricCyan, const Color(0xFF00E5FF));
      expect(AppColors.electricCyanLight, const Color(0xFF67E8F9));
      expect(AppColors.cyanTech, const Color(0xFF06B6D4));
      expect(AppColors.techBlue, const Color(0xFF0284C7));
      expect(AppColors.techBlueDark, const Color(0xFF0369A1));
    });

    test('1.3 Slate palette luminance decreases monotonically from slate50 to slate950', () {
      final List<Color> slateScale = [
        AppColors.slate50,
        AppColors.slate100,
        AppColors.slate200,
        AppColors.slate300,
        AppColors.slate400,
        AppColors.slate500,
        AppColors.slate600,
        AppColors.slate700,
        AppColors.slate750,
        AppColors.slate800,
        AppColors.slate850,
        AppColors.slate900,
        AppColors.slate950,
      ];

      for (int i = 0; i < slateScale.length - 1; i++) {
        final double currentLuminance = slateScale[i].computeLuminance();
        final double nextLuminance = slateScale[i + 1].computeLuminance();
        expect(
          currentLuminance,
          greaterThan(nextLuminance),
          reason: 'Luminance of slateScale[$i] ($currentLuminance) must be greater than slateScale[${i + 1}] ($nextLuminance)',
        );
      }
    });

    test('1.4 Primary palette colors are fully opaque (alpha == 255)', () {
      final List<Color> opaqueTokens = [
        AppColors.slate950,
        AppColors.slate900,
        AppColors.slate850,
        AppColors.slate800,
        AppColors.slate750,
        AppColors.slate700,
        AppColors.slate600,
        AppColors.slate500,
        AppColors.slate400,
        AppColors.slate300,
        AppColors.slate200,
        AppColors.slate100,
        AppColors.slate50,
        AppColors.electricCyan,
        AppColors.cyanTech,
        AppColors.techBlue,
        AppColors.techBlueDark,
      ];

      for (final color in opaqueTokens) {
        expect(color.a, 1.0, reason: 'Color $color must have 100% opacity (alpha 1.0)');
      }
    });

    test('1.5 Pulse and glow effects maintain appropriate semi-transparent alpha channels', () {
      expect(AppColors.rfidMatchedGlow.a, lessThan(1.0));
      expect(AppColors.rfidMatchedGlow.a, greaterThan(0.0));
      expect(AppColors.rfidScanningGlow.a, lessThan(1.0));
      expect(AppColors.rfidScanningGlow.a, greaterThan(0.0));
      expect(AppColors.rfidWarningGlow.a, lessThan(1.0));
      expect(AppColors.rfidWarningGlow.a, greaterThan(0.0));
      expect(AppColors.rfidErrorGlow.a, lessThan(1.0));
      expect(AppColors.rfidErrorGlow.a, greaterThan(0.0));
      expect(AppColors.rfidDuplicateGlow.a, lessThan(1.0));
      expect(AppColors.rfidDuplicateGlow.a, greaterThan(0.0));
    });
  });

  group('F2: Standardized RFID Status Colors (Tier 1)', () {
    test('2.1 AppColors defines all 5 standardized RFID status colors matching R1', () {
      // 1. Matched / Success (Emerald Green)
      expect(AppColors.rfidMatched, const Color(0xFF10B981));
      // 2. Scanning / Processing (Electric Cyan)
      expect(AppColors.rfidScanning, const Color(0xFF00E5FF));
      // 3. Mismatch / Warning (Amber / Orange)
      expect(AppColors.rfidWarning, const Color(0xFFF59E0B));
      // 4. Error / Rogue Tag (Coral Red)
      expect(AppColors.rfidError, const Color(0xFFEF4444));
      // 5. Duplicate / Different Pallet (Deep Indigo)
      expect(AppColors.rfidDuplicate, const Color(0xFF6366F1));
    });

    test('2.2 RfidStatusTokens semantic aliases mirror AppColors accurately', () {
      expect(RfidStatusTokens.matched, AppColors.rfidMatched);
      expect(RfidStatusTokens.matchedLight, AppColors.rfidMatchedLight);
      expect(RfidStatusTokens.matchedDark, AppColors.rfidMatchedDark);
      expect(RfidStatusTokens.matchedGlow, AppColors.rfidMatchedGlow);

      expect(RfidStatusTokens.scanning, AppColors.rfidScanning);
      expect(RfidStatusTokens.scanningTech, AppColors.rfidScanningTech);
      expect(RfidStatusTokens.scanningLight, AppColors.rfidScanningLight);
      expect(RfidStatusTokens.scanningGlow, AppColors.rfidScanningGlow);

      expect(RfidStatusTokens.warning, AppColors.rfidWarning);
      expect(RfidStatusTokens.warningLight, AppColors.rfidWarningLight);
      expect(RfidStatusTokens.warningDark, AppColors.rfidWarningDark);
      expect(RfidStatusTokens.warningGlow, AppColors.rfidWarningGlow);

      expect(RfidStatusTokens.error, AppColors.rfidError);
      expect(RfidStatusTokens.errorCoral, AppColors.rfidErrorCoral);
      expect(RfidStatusTokens.errorLight, AppColors.rfidErrorLight);
      expect(RfidStatusTokens.errorDark, AppColors.rfidErrorDark);
      expect(RfidStatusTokens.errorGlow, AppColors.rfidErrorGlow);

      expect(RfidStatusTokens.duplicate, AppColors.rfidDuplicate);
      expect(RfidStatusTokens.duplicateDeep, AppColors.rfidDuplicateDeep);
      expect(RfidStatusTokens.duplicateLight, AppColors.rfidDuplicateLight);
      expect(RfidStatusTokens.duplicateGlow, AppColors.rfidDuplicateGlow);
    });

    test('2.3 All 5 RFID status colors have distinct hues for clear visual discrimination', () {
      final List<Color> statusColors = [
        AppColors.rfidMatched,   // Emerald (~160 deg)
        AppColors.rfidScanning,  // Cyan (~186 deg)
        AppColors.rfidWarning,   // Amber (~38 deg)
        AppColors.rfidError,     // Coral Red (~0 deg)
        AppColors.rfidDuplicate, // Indigo (~239 deg)
      ];

      final List<double> hues = statusColors.map((c) => HSVColor.fromColor(c).hue).toList();

      // Pairwise check: each hue is distinct
      for (int i = 0; i < hues.length; i++) {
        for (int j = i + 1; j < hues.length; j++) {
          final double diff = (hues[i] - hues[j]).abs();
          final double angularDiff = math.min(diff, 360.0 - diff);
          expect(angularDiff, greaterThan(15.0),
              reason: 'Hue separation between color $i and color $j must be > 15 degrees for warehouse visibility');
        }
      }
    });

    test('2.4 Each RFID status color provides complete light and dark container pairings', () {
      expect(AppColors.rfidMatchedLight, const Color(0xFFD1FAE5));
      expect(AppColors.rfidMatchedDark, const Color(0xFF047857));

      expect(AppColors.rfidScanningLight, const Color(0xFFCFFAFE));
      expect(AppColors.rfidScanningTech, const Color(0xFF06B6D4));

      expect(AppColors.rfidWarningLight, const Color(0xFFFEF3C7));
      expect(AppColors.rfidWarningDark, const Color(0xFFB45309));

      expect(AppColors.rfidErrorLight, const Color(0xFFFEE2E2));
      expect(AppColors.rfidErrorDark, const Color(0xFFB91C1C));

      expect(AppColors.rfidDuplicateLight, const Color(0xFFE0E7FF));
      expect(AppColors.rfidDuplicateDeep, const Color(0xFF4338CA));
    });

    test('2.5 Core RFID status tokens are fully opaque and non-black', () {
      final List<Color> coreStatus = [
        AppColors.rfidMatched,
        AppColors.rfidScanning,
        AppColors.rfidWarning,
        AppColors.rfidError,
        AppColors.rfidDuplicate,
      ];

      for (final color in coreStatus) {
        expect(color.a, 1.0);
        expect(color.toARGB32(), isNot(0));
        expect(color.computeLuminance(), greaterThan(0.05));
      }
    });
  });

  group('F3: Monospace & Tabular Figures Typography (Tier 1)', () {
    test('3.1 AppTypography sets monospaceFamily to monospace', () {
      expect(AppTypography.monospaceFamily, 'monospace');
    });

    test('3.2 AppTypography tabularFeature contains FontFeature.tabularFigures()', () {
      expect(AppTypography.tabularFeature, contains(const FontFeature.tabularFigures()));
    });

    test('3.3 AppTypography.monospaceTabular factory generates valid styles with tabularFigures', () {
      final TextStyle customStyle = AppTypography.monospaceTabular(
        fontSize: 16.0,
        fontWeight: FontWeight.w700,
        color: AppColors.slate100,
        letterSpacing: 0.5,
        height: 1.2,
      );

      expect(customStyle.fontFamily, 'monospace');
      expect(customStyle.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(customStyle.fontSize, 16.0);
      expect(customStyle.fontWeight, FontWeight.w700);
      expect(customStyle.color, AppColors.slate100);
      expect(customStyle.letterSpacing, 0.5);
      expect(customStyle.height, 1.2);
    });

    test('3.4 Identifier text styles (epc, epcCompact, barcode, codeLabel, dataGridCell) enforce monospace & tabular figures', () {
      final List<TextStyle> idStyles = [
        AppTypography.epc,
        AppTypography.epcCompact,
        AppTypography.barcode,
        AppTypography.codeLabel,
        AppTypography.dataGridCell,
      ];

      for (final style in idStyles) {
        expect(style.fontFamily, 'monospace');
        expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
        expect(style.fontWeight, isNotNull);
        expect(style.fontSize, isNotNull);
      }
    });

    test('3.5 Telemetry KPI number styles maintain strict size hierarchy and tabular figures', () {
      expect(AppTypography.kpiNumberLarge.fontFamily, 'monospace');
      expect(AppTypography.kpiNumberLarge.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(AppTypography.kpiNumberLarge.fontSize, 32.0);

      expect(AppTypography.kpiNumberMedium.fontFamily, 'monospace');
      expect(AppTypography.kpiNumberMedium.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(AppTypography.kpiNumberMedium.fontSize, 20.0);

      expect(AppTypography.kpiNumber.fontFamily, 'monospace');
      expect(AppTypography.kpiNumber.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(AppTypography.kpiNumber.fontSize, 18.0);

      expect(AppTypography.kpiNumberSmall.fontFamily, 'monospace');
      expect(AppTypography.kpiNumberSmall.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(AppTypography.kpiNumberSmall.fontSize, 14.0);

      expect(AppTypography.kpiNumberLarge.fontSize!, greaterThan(AppTypography.kpiNumberMedium.fontSize!));
      expect(AppTypography.kpiNumberMedium.fontSize!, greaterThan(AppTypography.kpiNumber.fontSize!));
      expect(AppTypography.kpiNumber.fontSize!, greaterThan(AppTypography.kpiNumberSmall.fontSize!));
    });

    test('3.6 Metadata label styles (fieldLabel, unitLabel) define sharp compact typography', () {
      expect(AppTypography.fieldLabel.fontWeight, FontWeight.w600);
      expect(AppTypography.fieldLabel.fontSize, 11.0);
      expect(AppTypography.fieldLabel.letterSpacing, 0.3);

      expect(AppTypography.unitLabel.fontWeight, FontWeight.w600);
      expect(AppTypography.unitLabel.fontSize, 10.0);
      expect(AppTypography.unitLabel.letterSpacing, 0.2);
    });
  });

  group('F4: Legacy Theme Compatibility Adapter (Tier 1)', () {
    test('4.1 EyeCareThemeService().colors defaults map directly to Enterprise Warm Stone & Royal Blue tokens', () {
      final EyeCareColors colors = EyeCareThemeService().colors;

      expect(colors.bgDeep, AppColors.warmBgDeep);
      expect(colors.bgCard, AppColors.warmBgCard);
      expect(colors.bgCardElevated, AppColors.warmBgElevated);
      expect(colors.border, AppColors.warmBorder);
      expect(colors.borderLight, AppColors.warmBorderLight);
      expect(colors.textPrimary, AppColors.warmTextPrimary);
      expect(colors.textSecondary, AppColors.warmTextSecondary);
      expect(colors.textMuted, AppColors.warmTextMuted);
      expect(colors.rfidCyan, AppColors.royalBlue);
      expect(colors.rfidBlue, AppColors.royalBlueDark);
      expect(colors.successEmerald, AppColors.emeraldEnterprise);
      expect(colors.warningAmber, AppColors.amberEnterprise);
      expect(colors.errorCoral, AppColors.coralEnterprise);
    });

    test('4.2 EyeCareColors provides modern extension getters for seamless migration', () {
      const EyeCareColors colors = EyeCareColors();

      expect(colors.duplicateIndigo, AppColors.rfidDuplicate);
      expect(colors.rfidMatched, AppColors.emeraldEnterprise);
      expect(colors.rfidScanning, AppColors.royalBlue);
      expect(colors.rfidWarning, AppColors.amberEnterprise);
      expect(colors.rfidError, AppColors.coralEnterprise);
      expect(colors.rfidDuplicate, AppColors.rfidDuplicate);

      expect(colors.slate950, AppColors.slate950);
      expect(colors.slate900, AppColors.slate900);
      expect(colors.slate850, AppColors.slate850);
      expect(colors.slate800, AppColors.slate800);
      expect(colors.slate750, AppColors.slate750);
      expect(colors.slate700, AppColors.slate700);
      expect(colors.slate600, AppColors.slate600);
      expect(colors.slate500, AppColors.slate500);
      expect(colors.slate400, AppColors.slate400);
      expect(colors.slate300, AppColors.slate300);
      expect(colors.slate200, AppColors.slate200);
      expect(colors.slate100, AppColors.slate100);
      expect(colors.slate50, AppColors.slate50);
    });

    test('4.3 EyeCareThemeService themeData delegates to AppTheme.enterpriseWarmLightTheme', () {
      final service = EyeCareThemeService();
      final themeData = service.themeData;

      expect(themeData.brightness, Brightness.light);
      expect(themeData.scaffoldBackgroundColor, AppColors.warmBgDeep);
      expect(themeData.cardColor, AppColors.warmBgCard);
      expect(themeData.dividerColor, AppColors.warmBorder);
      expect(themeData.colorScheme.primary, AppColors.royalBlue);
      expect(themeData.colorScheme.onPrimary, Colors.white);
    });

    test('4.4 EyeCareThemeService modeName returns Enterprise Warm Light', () {
      final service = EyeCareThemeService();
      expect(service.modeName, 'Enterprise Warm Light');
    });

    test('4.5 EyeCareThemeService operates as a singleton and notifies listeners', () {
      final instance1 = EyeCareThemeService();
      final instance2 = EyeCareThemeService();
      expect(identical(instance1, instance2), isTrue);

      bool notified = false;
      void listener() {
        notified = true;
      }

      instance1.addListener(listener);
      instance1.toggleNextMode();
      expect(notified, isTrue);

      notified = false;
      instance1.setMode(EyeCareMode.warmDark);
      expect(notified, isTrue);
      expect(instance1.mode, EyeCareMode.warmDark);

      // Reset
      instance1.setMode(EyeCareMode.softSepia);
      instance1.removeListener(listener);
    });

    test('4.6 Legacy static constants (softSepia, warmDark, amberNight) map to Warm Stone & Royal Blue tokens', () {
      expect(EyeCareColors.softSepia.bgDeep, AppColors.warmBgDeep);
      expect(EyeCareColors.warmDark.bgDeep, AppColors.warmBgDeep);
      expect(EyeCareColors.amberNight.bgDeep, AppColors.warmBgDeep);

      expect(EyeCareColors.softSepia.textPrimary, AppColors.warmTextPrimary);
      expect(EyeCareColors.warmDark.textPrimary, AppColors.warmTextPrimary);
      expect(EyeCareColors.amberNight.textPrimary, AppColors.warmTextPrimary);
      expect(EyeCareColors.softSepia.rfidCyan, AppColors.royalBlue);
    });
  });

  group('F1/F2 Tier 2: Boundary & Contrast Tests (WCAG AAA >= 7.0:1)', () {
    test('2.1 WCAG AAA: Primary text (slate100) on Scaffold background (slate900) exceeds 7.0:1', () {
      final double contrast = calculateContrastRatio(AppColors.slate100, AppColors.slate900);
      expect(contrast, greaterThanOrEqualTo(7.0),
          reason: 'Primary text on dark scaffold must achieve WCAG AAA (>= 7.0:1). Actual: ${contrast.toStringAsFixed(2)}:1');
    });

    test('2.2 WCAG AAA: Primary text (slate100) on Card background (slate800) exceeds 7.0:1', () {
      final double contrast = calculateContrastRatio(AppColors.slate100, AppColors.slate800);
      expect(contrast, greaterThanOrEqualTo(7.0),
          reason: 'Primary text on card surface must achieve WCAG AAA (>= 7.0:1). Actual: ${contrast.toStringAsFixed(2)}:1');
    });

    test('2.3 WCAG AAA: High-contrast title (slate50) on Scaffold (slate900) and Card (slate800) exceeds 7.0:1', () {
      final double scaffoldContrast = calculateContrastRatio(AppColors.slate50, AppColors.slate900);
      final double cardContrast = calculateContrastRatio(AppColors.slate50, AppColors.slate800);

      expect(scaffoldContrast, greaterThanOrEqualTo(7.0),
          reason: 'High-contrast text on scaffold must achieve WCAG AAA. Actual: ${scaffoldContrast.toStringAsFixed(2)}:1');
      expect(cardContrast, greaterThanOrEqualTo(7.0),
          reason: 'High-contrast text on card must achieve WCAG AAA. Actual: ${cardContrast.toStringAsFixed(2)}:1');
    });

    test('2.4 WCAG AAA: Electric Cyan trigger feedback on Scaffold (slate900) exceeds 7.0:1', () {
      final double contrast = calculateContrastRatio(AppColors.electricCyan, AppColors.slate900);
      expect(contrast, greaterThanOrEqualTo(7.0),
          reason: 'Electric Cyan active trigger feedback on dark scaffold must achieve WCAG AAA. Actual: ${contrast.toStringAsFixed(2)}:1');
    });

    test('2.5 WCAG AAA: RFID Matched (Emerald Green) on Scaffold (slate900) exceeds 7.0:1', () {
      final double contrast = calculateContrastRatio(AppColors.rfidMatched, AppColors.slate900);
      expect(contrast, greaterThanOrEqualTo(7.0),
          reason: 'RFID Matched status on scaffold must achieve WCAG AAA (>= 7.0:1). Actual: ${contrast.toStringAsFixed(2)}:1');
    });

    test('2.6 WCAG AAA: RFID Warning (Amber) on Scaffold (slate900) exceeds 7.0:1', () {
      final double contrast = calculateContrastRatio(AppColors.rfidWarning, AppColors.slate900);
      expect(contrast, greaterThanOrEqualTo(7.0),
          reason: 'RFID Warning status on scaffold must achieve WCAG AAA (>= 7.0:1). Actual: ${contrast.toStringAsFixed(2)}:1');
    });

    test('2.7 WCAG: RFID Error (Coral Red >= 4.5:1) and Duplicate (Indigo UI component >= 3.0:1, text >= 7.0:1) on Scaffold', () {
      final double errorContrast = calculateContrastRatio(AppColors.rfidError, AppColors.slate900);
      final double duplicateComponentContrast = calculateContrastRatio(AppColors.rfidDuplicate, AppColors.slate900);
      final double duplicateTextContrast = calculateContrastRatio(AppColors.rfidDuplicateLight, AppColors.slate900);

      expect(errorContrast, greaterThanOrEqualTo(4.5),
          reason: 'RFID Error status on scaffold must achieve at least WCAG AA (>= 4.5:1). Actual: ${errorContrast.toStringAsFixed(2)}:1');
      expect(duplicateComponentContrast, greaterThanOrEqualTo(3.0),
          reason: 'RFID Duplicate component on scaffold must achieve WCAG 2.1 UI Component contrast (>= 3.0:1). Actual: ${duplicateComponentContrast.toStringAsFixed(2)}:1');
      expect(duplicateTextContrast, greaterThanOrEqualTo(7.0),
          reason: 'RFID Duplicate badge text on scaffold must achieve WCAG AAA (>= 7.0:1). Actual: ${duplicateTextContrast.toStringAsFixed(2)}:1');
    });

    test('2.8 WCAG AA: Secondary text (slate400) on Card (slate800) exceeds 4.5:1', () {
      final double contrast = calculateContrastRatio(AppColors.slate400, AppColors.slate800);
      expect(contrast, greaterThanOrEqualTo(4.5),
          reason: 'Secondary metadata text on card must achieve WCAG AA (>= 4.5:1). Actual: ${contrast.toStringAsFixed(2)}:1');
    });

    test('2.9 Zero legacy paper colors in active AppColors palette', () {
      final List<Color> activeTokens = [
        AppColors.slate950,
        AppColors.slate900,
        AppColors.slate850,
        AppColors.slate800,
        AppColors.slate750,
        AppColors.slate700,
        AppColors.slate600,
        AppColors.slate500,
        AppColors.slate400,
        AppColors.slate300,
        AppColors.slate200,
        AppColors.slate100,
        AppColors.slate50,
        AppColors.electricCyan,
        AppColors.cyanTech,
        AppColors.techBlue,
        AppColors.rfidMatched,
        AppColors.rfidScanning,
        AppColors.rfidWarning,
        AppColors.rfidError,
        AppColors.rfidDuplicate,
      ];

      for (final color in activeTokens) {
        expect(
          legacyPaperHexValues.contains(color.toARGB32()),
          isFalse,
          reason: 'Color token 0x${color.toARGB32().toRadixString(16).toUpperCase()} is a forbidden legacy paper color',
        );
      }
    });

    test('2.10 Zero legacy paper colors in EyeCareColors default values', () {
      const EyeCareColors colors = EyeCareColors();
      final List<Color> eyeCareTokens = [
        colors.bgDeep,
        colors.bgCard,
        colors.bgCardElevated,
        colors.border,
        colors.borderLight,
        colors.textPrimary,
        colors.textSecondary,
        colors.textMuted,
        colors.rfidCyan,
        colors.rfidBlue,
        colors.successEmerald,
        colors.warningAmber,
        colors.errorCoral,
      ];

      for (final color in eyeCareTokens) {
        expect(
          legacyPaperHexValues.contains(color.toARGB32()),
          isFalse,
          reason: 'EyeCareColors token 0x${color.toARGB32().toRadixString(16).toUpperCase()} must not contain legacy paper tones',
        );
      }
    });
  });

  group('F5 & Tier 3: Cross-Feature Interactions & Widget Integration', () {
    testWidgets('3.1 Theme widget renders EPC code with AppTypography.epc and correct theme styles', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: Scaffold(
            body: Center(
              child: Text(
                'E2801160600002047805ABCD',
                style: AppTypography.epc.copyWith(color: AppColors.slate100),
              ),
            ),
          ),
        ),
      );

      final textFinder = find.text('E2801160600002047805ABCD');
      expect(textFinder, findsOneWidget);

      final Text textWidget = tester.widget<Text>(textFinder);
      expect(textWidget.style?.fontFamily, 'monospace');
      expect(textWidget.style?.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(textWidget.style?.color, AppColors.slate100);
    });

    testWidgets('3.2 Card widget inside industrialDarkTheme adopts slate800 background and slate700 border', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: const Scaffold(
            body: Card(
              child: SizedBox(
                width: 100,
                height: 50,
                child: Text('Card Content'),
              ),
            ),
          ),
        ),
      );

      final cardFinder = find.byType(Card);
      expect(cardFinder, findsOneWidget);

      final BuildContext context = tester.element(cardFinder);
      expect(Theme.of(context).cardTheme.color, AppColors.slate800);
      expect(Theme.of(context).cardColor, AppColors.slate800);

      // Verify the underlying Material widget used by Card renders with slate800
      final materialFinder = find.descendant(of: cardFinder, matching: find.byType(Material));
      expect(materialFinder, findsOneWidget);
      final Material material = tester.widget<Material>(materialFinder);
      expect(material.color, AppColors.slate800);
      final shape = material.shape as RoundedRectangleBorder?;
      expect(shape?.side.color, AppColors.slate700);
    });

    testWidgets('3.3 ElevatedButton under industrialDarkTheme satisfies Ergonomic PDA Touch Target >= 48dp', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {},
                child: const Text('BẮT ĐẦU QUÉT'),
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(ElevatedButton);
      expect(buttonFinder, findsOneWidget);

      final Size buttonSize = tester.getSize(buttonFinder);
      expect(buttonSize.height, greaterThanOrEqualTo(48.0),
          reason: 'PDA touch target height must be >= 48dp for glove-friendly trigger operation');
    });

    testWidgets('3.4 OutlinedButton under industrialDarkTheme satisfies Ergonomic PDA Touch Target >= 48dp', (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.industrialDarkTheme,
          home: Scaffold(
            body: Center(
              child: OutlinedButton(
                onPressed: () {},
                child: const Text('DỪNG QUÉT'),
              ),
            ),
          ),
        ),
      );

      final buttonFinder = find.byType(OutlinedButton);
      expect(buttonFinder, findsOneWidget);

      final Size buttonSize = tester.getSize(buttonFinder);
      expect(buttonSize.height, greaterThanOrEqualTo(48.0),
          reason: 'PDA outlined action button height must be >= 48dp');
    });

    testWidgets('3.5 EyeCareThemeService reactive builder updates widget tree on mode switch', (WidgetTester tester) async {
      final service = EyeCareThemeService();
      service.setMode(EyeCareMode.softSepia);

      await tester.pumpWidget(
        AnimatedBuilder(
          animation: service,
          builder: (context, _) {
            return MaterialApp(
              theme: service.themeData,
              home: Scaffold(
                body: Text('Current Mode: ${service.mode.name}'),
              ),
            );
          },
        ),
      );

      expect(find.text('Current Mode: softSepia'), findsOneWidget);

      service.setMode(EyeCareMode.warmDark);
      await tester.pump();

      expect(find.text('Current Mode: warmDark'), findsOneWidget);

      // Clean up
      service.setMode(EyeCareMode.softSepia);
    });
  });

  group('Tier 4: Real-World Workload Scenarios', () {
    test('4.1 High-speed 100-tag burst status resolution executes with zero errors and valid tokens', () {
      final List<String> simulatedTagStates = [
        'matched',
        'scanning',
        'warning',
        'error',
        'duplicate',
      ];

      for (int i = 0; i < 100; i++) {
        final state = simulatedTagStates[i % simulatedTagStates.length];
        Color resolvedColor;
        switch (state) {
          case 'matched':
            resolvedColor = RfidStatusTokens.matched;
            break;
          case 'scanning':
            resolvedColor = RfidStatusTokens.scanning;
            break;
          case 'warning':
            resolvedColor = RfidStatusTokens.warning;
            break;
          case 'error':
            resolvedColor = RfidStatusTokens.error;
            break;
          case 'duplicate':
            resolvedColor = RfidStatusTokens.duplicate;
            break;
          default:
            resolvedColor = AppColors.slate500;
        }

        expect(resolvedColor, isNotNull);
        expect(resolvedColor.a, 1.0);
        expect(legacyPaperHexValues.contains(resolvedColor.toARGB32()), isFalse);
      }
    });

    test('4.2 Tabular figures ensure uniform width rendering between diverse digit sequences', () {
      final style = AppTypography.kpiNumber;
      expect(style.fontFeatures, contains(const FontFeature.tabularFigures()));
      expect(style.fontFamily, 'monospace');
      // Style is structurally equipped to prevent digit width jitter
    });

    test('4.3 Dual-theme switching (industrialDarkTheme and industrialLightTheme) instantiates cleanly', () {
      final darkTheme = AppTheme.industrialDarkTheme;
      final lightTheme = AppTheme.industrialLightTheme;

      expect(darkTheme.brightness, Brightness.dark);
      expect(darkTheme.scaffoldBackgroundColor, AppColors.slate900);
      expect(darkTheme.colorScheme.primary, AppColors.cyanTech);

      expect(lightTheme.brightness, Brightness.light);
      expect(lightTheme.scaffoldBackgroundColor, AppColors.slate100);
      expect(lightTheme.colorScheme.primary, AppColors.techBlue);
    });

    test('4.4 EyeCareTheme export re-exports AppColors, AppTypography, and AppTheme transparently', () {
      // Verifies that files importing eye_care_theme.dart have transparent access to modern tokens
      expect(AppColors.slate900, isNotNull);
      expect(AppTypography.epc, isNotNull);
      expect(AppTheme.industrialDarkTheme, isNotNull);
    });
  });
}
