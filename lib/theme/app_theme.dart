import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Application ThemeData definitions.
///
/// Provides:
/// - [enterpriseWarmLightTheme]: Warm Stone (#F5F5F4 / #FAFAF9) + Enterprise Royal Blue (#2563EB)
/// - [industrialDarkTheme]: Deep Slate dark theme
/// - [industrialLightTheme]: Clean Slate light theme
class AppTheme {
  AppTheme._();

  /// Sáng Ấm Áp (Warm Stone #F5F5F4 / #FAFAF9) + Xanh Dương Doanh Nghiệp (Royal Blue #2563EB).
  /// Dịu mắt khi nhìn lâu, nút xanh chữ trắng rõ nét, chuẩn ERP/WMS hiện đại.
  static ThemeData get enterpriseWarmLightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.warmBgDeep,
      cardColor: AppColors.warmBgCard,
      canvasColor: AppColors.warmBgCard,
      dividerColor: AppColors.warmBorder,
      colorScheme: const ColorScheme.light(
        primary: AppColors.royalBlue,
        onPrimary: Colors.white,
        secondary: AppColors.royalBlueDark,
        onSecondary: Colors.white,
        surface: AppColors.warmBgCard,
        onSurface: AppColors.warmTextPrimary,
        error: AppColors.coralEnterprise,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.warmBgCard,
        foregroundColor: AppColors.warmTextPrimary,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.warmTextPrimary),
        titleTextStyle: TextStyle(
          color: AppColors.warmTextPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.warmBgCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.warmBorder, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.warmBgCard,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.warmBorder, width: 1.2),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.warmTextPrimary,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.warmTextSecondary,
          fontSize: 13.5,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.warmBgElevated,
        hintStyle: const TextStyle(color: AppColors.warmTextMuted, fontSize: 13),
        labelStyle: const TextStyle(color: AppColors.warmTextSecondary, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.warmBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.warmBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.royalBlue, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.coralEnterprise),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.royalBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 48), // Ergonomic PDA touch target >= 48dp
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.warmTextPrimary,
          minimumSize: const Size(64, 48), // Ergonomic PDA touch target >= 48dp
          side: const BorderSide(color: AppColors.warmBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.warmBorder,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        backgroundColor: AppColors.warmTextPrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        dismissDirection: DismissDirection.down,
        showCloseIcon: true,
        closeIconColor: Colors.white70,
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 13),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  /// Industrial Dark Theme (Deep Slate + Electric Cyan/Tech Blue).
  static ThemeData get industrialDarkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.slate900,
      cardColor: AppColors.slate800,
      canvasColor: AppColors.slate800,
      dividerColor: AppColors.slate700,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.cyanTech,
        onPrimary: AppColors.slate950,
        secondary: AppColors.electricCyan,
        onSecondary: AppColors.slate950,
        surface: AppColors.slate800,
        onSurface: AppColors.slate100,
        error: AppColors.rfidError,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.slate900,
        foregroundColor: AppColors.slate50,
        elevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: AppColors.slate100),
        titleTextStyle: TextStyle(
          color: AppColors.slate50,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.slate800,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.slate700, width: 1),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.slate800,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.slate700, width: 1.2),
        ),
        titleTextStyle: const TextStyle(
          color: AppColors.slate50,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
        contentTextStyle: const TextStyle(
          color: AppColors.slate200,
          fontSize: 13.5,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.slate850,
        hintStyle: const TextStyle(color: AppColors.slate500, fontSize: 13),
        labelStyle: const TextStyle(color: AppColors.slate400, fontSize: 13),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.slate700),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.slate700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.cyanTech, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.rfidError),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.cyanTech,
          foregroundColor: AppColors.slate950,
          elevation: 0,
          minimumSize: const Size(64, 48), // Ergonomic PDA touch target >= 48dp
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            letterSpacing: 0.3,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.slate100,
          minimumSize: const Size(64, 48), // Ergonomic PDA touch target >= 48dp
          side: const BorderSide(color: AppColors.slate700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.slate700,
        thickness: 1,
        space: 1,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        elevation: 6,
        backgroundColor: AppColors.slate800,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.slate700),
        ),
        dismissDirection: DismissDirection.down,
        showCloseIcon: true,
        closeIconColor: AppColors.slate400,
        contentTextStyle: const TextStyle(color: AppColors.slate100, fontSize: 13),
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  /// Clean Slate High-Contrast Light Theme.
  static ThemeData get industrialLightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.slate100,
      cardColor: Colors.white,
      canvasColor: Colors.white,
      dividerColor: AppColors.slate200,
      colorScheme: const ColorScheme.light(
        primary: AppColors.techBlue,
        onPrimary: Colors.white,
        secondary: AppColors.cyanTech,
        onSecondary: Colors.white,
        surface: Colors.white,
        onSurface: AppColors.slate900,
        error: AppColors.rfidError,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.slate900,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.techBlue,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(64, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.slate900,
          minimumSize: const Size(64, 48),
          side: const BorderSide(color: AppColors.slate300),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }
}
