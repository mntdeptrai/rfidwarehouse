import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'app_theme.dart';

export 'app_colors.dart';
export 'app_theme.dart';
export 'app_typography.dart';

/// Theme Modes (maintained for 100% compatibility).
enum EyeCareMode {
  softSepia, // Default: Warm Stone (#F5F5F4 / #FAFAF9) + Enterprise Royal Blue (#2563EB)
  warmDark,  // Industrial Dark Slate
  amberNight // Warm Stone Light
}

/// Theme colors provider across Desktop Workstation & Mobile PDA screens.
///
/// Defaults to Sáng Ấm Áp (Warm Stone `#F5F5F4` / `#FAFAF9`) +
/// Xanh Dương Doanh Nghiệp (Royal Blue `#2563EB` với chữ trắng rõ nét).
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
    this.bgDeep = AppColors.warmBgDeep,
    this.bgCard = AppColors.warmBgCard,
    this.bgCardElevated = AppColors.warmBgElevated,
    this.border = AppColors.warmBorder,
    this.borderLight = AppColors.warmBorderLight,
    this.textPrimary = AppColors.warmTextPrimary,
    this.textSecondary = AppColors.warmTextSecondary,
    this.textMuted = AppColors.warmTextMuted,
    this.rfidCyan = AppColors.royalBlue,
    this.rfidBlue = AppColors.royalBlueDark,
    this.successEmerald = AppColors.emeraldEnterprise,
    this.warningAmber = AppColors.amberEnterprise,
    this.errorCoral = AppColors.coralEnterprise,
    this.overlayTint = Colors.transparent,
  });

  static const EyeCareColors softSepia = EyeCareColors();
  static const EyeCareColors warmDark = EyeCareColors();
  static const EyeCareColors amberNight = EyeCareColors();

  // Ergonomic modern token extensions
  Color get duplicateIndigo => AppColors.rfidDuplicate;
  Color get rfidMatched => successEmerald;
  Color get rfidScanning => rfidCyan;
  Color get rfidWarning => warningAmber;
  Color get rfidError => errorCoral;
  Color get rfidDuplicate => AppColors.rfidDuplicate;

  Color get slate950 => AppColors.slate950;
  Color get slate900 => AppColors.slate900;
  Color get slate850 => AppColors.slate850;
  Color get slate800 => AppColors.slate800;
  Color get slate750 => AppColors.slate750;
  Color get slate700 => AppColors.slate700;
  Color get slate600 => AppColors.slate600;
  Color get slate500 => AppColors.slate500;
  Color get slate400 => AppColors.slate400;
  Color get slate300 => AppColors.slate300;
  Color get slate200 => AppColors.slate200;
  Color get slate100 => AppColors.slate100;
  Color get slate50 => AppColors.slate50;
}

/// Service managing application theme and backward compatible bridging.
class EyeCareThemeService extends ChangeNotifier {
  static final EyeCareThemeService _instance = EyeCareThemeService._internal();
  factory EyeCareThemeService() => _instance;

  EyeCareThemeService._internal();

  EyeCareMode _mode = EyeCareMode.softSepia;

  EyeCareMode get mode => _mode;
  EyeCareColors get colors => EyeCareColors.softSepia;

  void setMode(EyeCareMode newMode) {
    _mode = newMode;
    notifyListeners();
  }

  void toggleNextMode() {
    notifyListeners();
  }

  String get modeName => 'Enterprise Warm Light';

  /// Delegated to Enterprise Warm Light ThemeData (Warm Stone + Royal Blue #2563EB).
  ThemeData get themeData => AppTheme.enterpriseWarmLightTheme;
}
