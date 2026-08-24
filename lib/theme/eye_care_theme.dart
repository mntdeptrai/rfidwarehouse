import 'package:flutter/material.dart';

enum EyeCareMode {
  softSepia, // Giấy mộc sáng dịu (Không chói lóa mắt, êm dịu làm việc lâu dài)
}

class EyeCareColors {
  final EyeCareMode mode;
  final Color bgDeep;
  final Color bgCard;
  final Color bgCardElevated;
  final Color border;
  final Color borderLight;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color rfidCyan;
  final Color rfidBlue;
  final Color successEmerald;
  final Color warningAmber;
  final Color errorCoral;
  final Color overlayTint;

  const EyeCareColors({
    this.mode = EyeCareMode.softSepia,
    this.bgDeep = const Color(0xFFF4EFE6),
    this.bgCard = const Color(0xFFE9E2D5),
    this.bgCardElevated = const Color(0xFFDFD6C7),
    this.border = const Color(0xFFC7BDAF),
    this.borderLight = const Color(0xFFB5A999),
    this.textPrimary = const Color(0xFF2C251E),
    this.textSecondary = const Color(0xFF6B5D4D),
    this.textMuted = const Color(0xFF8F8070),
    this.rfidCyan = const Color(0xFF0284C7),
    this.rfidBlue = const Color(0xFF0369A1),
    this.successEmerald = const Color(0xFF047857),
    this.warningAmber = const Color(0xFFB45309),
    this.errorCoral = const Color(0xFFBE123C),
    this.overlayTint = Colors.transparent,
  });

  static const EyeCareColors softSepia = EyeCareColors();
  static const EyeCareColors warmDark = EyeCareColors();
  static const EyeCareColors amberNight = EyeCareColors();
}

class EyeCareThemeService extends ChangeNotifier {
  static final EyeCareThemeService _instance = EyeCareThemeService._internal();
  factory EyeCareThemeService() => _instance;

  EyeCareThemeService._internal();

  final EyeCareMode _mode = EyeCareMode.softSepia;

  EyeCareMode get mode => _mode;
  EyeCareColors get colors => EyeCareColors.softSepia;

  void setMode(EyeCareMode newMode) {}
  void toggleNextMode() {}

  String get modeName => 'Giấy Mộc Dịu Mắt';

  ThemeData get themeData {
    const c = EyeCareColors.softSepia;

    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: c.bgDeep,
      cardColor: c.bgCard,
      dividerColor: c.border,
      colorScheme: ColorScheme.light(
        primary: c.rfidBlue,
        secondary: c.rfidCyan,
        surface: c.bgCard,
        error: c.errorCoral,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: c.bgDeep,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: c.textPrimary),
        titleTextStyle: TextStyle(
          color: c.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
