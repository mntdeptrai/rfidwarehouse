import 'package:flutter/material.dart';

/// Enterprise Warm Stone & Industrial Modern Design System Colors.
///
/// Includes Warm Stone Enterprise Light palette + Royal Blue (#2563EB) primary brand tokens,
/// Deep Slate scale, and 5 standardized RFID hardware status colors.
class AppColors {
  AppColors._();

  // ==========================================
  // WARM STONE & ENTERPRISE ROYAL BLUE PALETTE
  // (Active Default Theme: Sáng Ấm Áp + Xanh Dương Doanh Nghiệp)
  // ==========================================
  /// Main Scaffold background: Warm Stone 100 (#F5F5F4) — dịu mắt, ấm áp, sang trọng.
  static const Color warmBgDeep = Color(0xFFF5F5F4);

  /// Primary Card & Sidebar surface: Warm Alabaster White (#FAFAF9).
  static const Color warmBgCard = Color(0xFFFAFAF9);

  /// Elevated container / Input fill / Secondary box: Warm Stone 150 (#EFEDE8).
  static const Color warmBgElevated = Color(0xFFEFEDE8);

  /// Primary card & table border: Warm Stone 300 (#D6D3D1).
  static const Color warmBorder = Color(0xFFD6D3D1);

  /// Subtle divider / inner border: Warm Stone 200 (#E7E5E4).
  static const Color warmBorderLight = Color(0xFFE7E5E4);

  /// Primary heading & body text: Warm Stone 900 (#1C1917) — high contrast > 15:1.
  static const Color warmTextPrimary = Color(0xFF1C1917);

  /// Secondary text & labels: Warm Stone 600 (#57534E).
  static const Color warmTextSecondary = Color(0xFF57534E);

  /// Muted hints & captions: Warm Stone 500 (#78716C).
  static const Color warmTextMuted = Color(0xFF78716C);

  /// Enterprise Royal Blue (#2563EB) — Primary brand & button color (chữ trắng rõ nét).
  static const Color royalBlue = Color(0xFF2563EB);

  /// Deep Royal Blue (#1D4ED8) — Active/hover & high-contrast links.
  static const Color royalBlueDark = Color(0xFF1D4ED8);

  /// Soft Royal Blue tint (#DBEAFE) — Selected pill/badge background.
  static const Color royalBlueLight = Color(0xFFDBEAFE);

  /// Enterprise semantic status colors tuned for Warm Light surfaces
  static const Color emeraldEnterprise = Color(0xFF059669);
  static const Color amberEnterprise = Color(0xFFD97706);
  static const Color coralEnterprise = Color(0xFFDC2626);

  // ==========================================
  // DEEP SLATE PALETTE (Dark Telemetry & Radar Surfaces)
  // ==========================================
  /// Deepest slate black: viewfinder, background underlays, modal barriers.
  static const Color slate950 = Color(0xFF020617);

  /// Main Dark Scaffold background.
  static const Color slate900 = Color(0xFF0F172A);

  /// Elevated dark card background / nested container surface.
  static const Color slate850 = Color(0xFF172033);

  /// Primary Dark Card background / Sheet container.
  static const Color slate800 = Color(0xFF1E293B);

  /// Card hover / highlighted item / active selection.
  static const Color slate750 = Color(0xFF24334A);

  /// Primary dividing line / standard card border.
  static const Color slate700 = Color(0xFF334155);

  /// Subtle border / inactive control boundary.
  static const Color slate600 = Color(0xFF475569);

  /// Muted icons / disabled control fill / subtle placeholder.
  static const Color slate500 = Color(0xFF64748B);

  /// Secondary text / labels / telemetry units.
  static const Color slate400 = Color(0xFF94A3B8);

  /// Readout sub-headers / secondary data columns.
  static const Color slate300 = Color(0xFFCBD5E1);

  /// Light slate background / pill tags background.
  static const Color slate200 = Color(0xFFE2E8F0);

  /// Primary body text / regular values.
  static const Color slate100 = Color(0xFFF1F5F9);

  /// Crisp white-slate text / high-contrast titles.
  static const Color slate50 = Color(0xFFF8FAFC);

  // ==========================================
  // MODERN TECH ACCENTS
  // ==========================================
  /// Electric Cyan: Radar wave & high-contrast dark telemetry accent.
  static const Color electricCyan = Color(0xFF00E5FF);

  /// Soft electric cyan glow for highlights.
  static const Color electricCyanLight = Color(0xFF67E8F9);

  /// Cyan Tech: Secondary tech accent.
  static const Color cyanTech = Color(0xFF06B6D4);

  /// Tech Blue: Sky blue links, info banners, secondary actions.
  static const Color techBlue = Color(0xFF0284C7);

  /// Tech Blue Dark: Deep blue accent, dark status fill.
  static const Color techBlueDark = Color(0xFF0369A1);

  // ==========================================
  // STANDARDIZED RFID STATUS TOKENS (R1)
  // ==========================================
  // 1. Tag đã nhận diện / Khớp đơn / Đạt chuẩn (Emerald Green)
  static const Color rfidMatched = Color(0xFF10B981);
  static const Color rfidMatchedLight = Color(0xFFD1FAE5);
  static const Color rfidMatchedDark = Color(0xFF047857);
  static const Color rfidMatchedGlow = Color(0x6610B981);

  // 2. Đang quét / Sóng RF đang phát / Đang xử lý
  static const Color rfidScanning = Color(0xFF00E5FF);
  static const Color rfidScanningTech = Color(0xFF06B6D4);
  static const Color rfidScanningLight = Color(0xFFCFFAFE);
  static const Color rfidScanningGlow = Color(0x6600E5FF);

  // 3. Cảnh báo lệch vị trí / Chưa khớp / Thiếu hàng (Amber / Orange)
  static const Color rfidWarning = Color(0xFFF59E0B);
  static const Color rfidWarningLight = Color(0xFFFEF3C7);
  static const Color rfidWarningDark = Color(0xFFB45309);
  static const Color rfidWarningGlow = Color(0x66F59E0B);

  // 4. Lỗi / Thẻ lạ ngoài danh mục / Báo động xuất trái phép (Coral Red)
  static const Color rfidError = Color(0xFFEF4444);
  static const Color rfidErrorCoral = Color(0xFFF43F5E);
  static const Color rfidErrorLight = Color(0xFFFEE2E2);
  static const Color rfidErrorDark = Color(0xFFB91C1C);
  static const Color rfidErrorGlow = Color(0x66EF4444);

  // 5. Trùng lặp / Khác Pallet / Đã quét lại (Deep Indigo)
  static const Color rfidDuplicate = Color(0xFF6366F1);
  static const Color rfidDuplicateDeep = Color(0xFF4338CA);
  static const Color rfidDuplicateLight = Color(0xFFE0E7FF);
  static const Color rfidDuplicateGlow = Color(0x666366F1);
}

/// Semantic status aliases for easy access across screens and widgets.
class RfidStatusTokens {
  RfidStatusTokens._();

  static const Color matched = AppColors.rfidMatched;
  static const Color matchedLight = AppColors.rfidMatchedLight;
  static const Color matchedDark = AppColors.rfidMatchedDark;
  static const Color matchedGlow = AppColors.rfidMatchedGlow;

  static const Color scanning = AppColors.rfidScanning;
  static const Color scanningTech = AppColors.rfidScanningTech;
  static const Color scanningLight = AppColors.rfidScanningLight;
  static const Color scanningGlow = AppColors.rfidScanningGlow;

  static const Color warning = AppColors.rfidWarning;
  static const Color warningLight = AppColors.rfidWarningLight;
  static const Color warningDark = AppColors.rfidWarningDark;
  static const Color warningGlow = AppColors.rfidWarningGlow;

  static const Color error = AppColors.rfidError;
  static const Color errorCoral = AppColors.rfidErrorCoral;
  static const Color errorLight = AppColors.rfidErrorLight;
  static const Color errorDark = AppColors.rfidErrorDark;
  static const Color errorGlow = AppColors.rfidErrorGlow;

  static const Color duplicate = AppColors.rfidDuplicate;
  static const Color duplicateDeep = AppColors.rfidDuplicateDeep;
  static const Color duplicateLight = AppColors.rfidDuplicateLight;
  static const Color duplicateGlow = AppColors.rfidDuplicateGlow;
}
