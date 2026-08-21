import 'package:flutter/material.dart';

enum EyeCareMode {
  warmDark,   // Nền đen than ấm chống mỏi mắt (Mặc định cho kho bãi)
  amberNight, // Tăng cường lọc ánh sáng xanh (Ấm vàng thư giãn mắt)
  softSepia,  // Giấy mộc sáng dịu (Không chói lóa khi làm việc ngoài trời)
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
    required this.mode,
    required this.bgDeep,
    required this.bgCard,
    required this.bgCardElevated,
    required this.border,
    required this.borderLight,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.rfidCyan,
    required this.rfidBlue,
    required this.successEmerald,
    required this.warningAmber,
    required this.errorCoral,
    this.overlayTint = Colors.transparent,
  });

  // 1. Chế độ Warm Dark: Nền than xám ấm, khử 100% độ chói trắng, tương phản công thái học 7:1
  static const EyeCareColors warmDark = EyeCareColors(
    mode: EyeCareMode.warmDark,
    bgDeep: Color(0xFF0F172A),
    bgCard: Color(0xFF1E293B),
    bgCardElevated: Color(0xFF253349),
    border: Color(0xFF334155),
    borderLight: Color(0xFF475569),
    textPrimary: Color(0xFFF1F5F9), // Trắng ngà dịu mắt
    textSecondary: Color(0xFF94A3B8), // Xám bạc dịu nhẹ
    textMuted: Color(0xFF64748B),
    rfidCyan: Color(0xFF38BDF8),
    rfidBlue: Color(0xFF0284C7),
    successEmerald: Color(0xFF10B981),
    warningAmber: Color(0xFFF59E0B),
    errorCoral: Color(0xFFF87171),
    overlayTint: Colors.transparent,
  );

  // 2. Chế độ Amber Night: Tăng tông ấm hổ phách, triệt tiêu bức xạ ánh sáng xanh có hại
  static const EyeCareColors amberNight = EyeCareColors(
    mode: EyeCareMode.amberNight,
    bgDeep: Color(0xFF14120E),
    bgCard: Color(0xFF241F18),
    bgCardElevated: Color(0xFF312A20),
    border: Color(0xFF453929),
    borderLight: Color(0xFF5E4E37),
    textPrimary: Color(0xFFFDF6E2), // Trắng vàng ấm
    textSecondary: Color(0xFFD4C3A3), // Vàng cát dịu
    textMuted: Color(0xFF968770),
    rfidCyan: Color(0xFF38BDF8),
    rfidBlue: Color(0xFF3B82F6),
    successEmerald: Color(0xFF10B981),
    warningAmber: Color(0xFFF59E0B),
    errorCoral: Color(0xFFFB7185),
    overlayTint: Color(0x14F59E0B),
  );

  // 3. Chế độ Soft Sepia: Tông giấy mộc cổ điển, không lóa mắt khi môi trường nhiều ánh sáng
  static const EyeCareColors softSepia = EyeCareColors(
    mode: EyeCareMode.softSepia,
    bgDeep: Color(0xFFF4EFE6),
    bgCard: Color(0xFFE9E2D5),
    bgCardElevated: Color(0xFFDFD6C7),
    border: Color(0xFFC7BDAF),
    borderLight: Color(0xFFB5A999),
    textPrimary: Color(0xFF2C251E), // Nâu sẫm chống lóa
    textSecondary: Color(0xFF6B5D4D),
    textMuted: Color(0xFF8F8070),
    rfidCyan: Color(0xFF0284C7),
    rfidBlue: Color(0xFF0369A1),
    successEmerald: Color(0xFF047857),
    warningAmber: Color(0xFFB45309),
    errorCoral: Color(0xFFBE123C),
    overlayTint: Colors.transparent,
  );
}

class EyeCareThemeService extends ChangeNotifier {
  static final EyeCareThemeService _instance = EyeCareThemeService._internal();
  factory EyeCareThemeService() => _instance;

  EyeCareThemeService._internal();

  EyeCareMode _mode = EyeCareMode.warmDark;

  EyeCareMode get mode => _mode;
  EyeCareColors get colors {
    switch (_mode) {
      case EyeCareMode.warmDark:
        return EyeCareColors.warmDark;
      case EyeCareMode.amberNight:
        return EyeCareColors.amberNight;
      case EyeCareMode.softSepia:
        return EyeCareColors.softSepia;
    }
  }

  void setMode(EyeCareMode newMode) {
    if (_mode == newMode) return;
    _mode = newMode;
    notifyListeners();
  }

  void toggleNextMode() {
    switch (_mode) {
      case EyeCareMode.warmDark:
        setMode(EyeCareMode.amberNight);
        break;
      case EyeCareMode.amberNight:
        setMode(EyeCareMode.softSepia);
        break;
      case EyeCareMode.softSepia:
        setMode(EyeCareMode.warmDark);
        break;
    }
  }

  String get modeName {
    switch (_mode) {
      case EyeCareMode.warmDark:
        return 'Than Ấm (Warm Dark)';
      case EyeCareMode.amberNight:
        return 'Lọc Ánh Sáng Xanh (Amber)';
      case EyeCareMode.softSepia:
        return 'Giấy Mộc Dịu Mắt (Sepia)';
    }
  }

  ThemeData get themeData {
    final c = colors;
    final isDark = _mode != EyeCareMode.softSepia;

    return ThemeData(
      brightness: isDark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: c.bgDeep,
      cardColor: c.bgCard,
      dividerColor: c.border,
      colorScheme: isDark
          ? ColorScheme.dark(
              primary: c.rfidCyan,
              secondary: c.rfidBlue,
              surface: c.bgCard,
              error: c.errorCoral,
            )
          : ColorScheme.light(
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
