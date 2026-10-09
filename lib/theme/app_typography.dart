import 'package:flutter/material.dart';

/// Industrial Modern Tech Typography Tokens.
///
/// Provides specialized Monospace and Tabular figures font styling for
/// RFID EPC codes, 1D/2D barcodes, and high-speed telemetry numeric counters.
/// Eliminates horizontal jitter during rapid RFID inventory bursts.
class AppTypography {
  AppTypography._();

  static const String monospaceFamily = 'monospace';

  /// Standard font features ensuring equal-width tabular digits.
  static const List<FontFeature> tabularFeature = [
    FontFeature.tabularFigures(),
  ];

  /// Core helper to create tabular monospace text styles.
  static TextStyle monospaceTabular({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return TextStyle(
      fontFamily: monospaceFamily,
      fontFeatures: tabularFeature,
      fontSize: fontSize,
      fontWeight: fontWeight ?? FontWeight.normal,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
    );
  }

  // ==========================================
  // HARDWARE TELEMETRY & FAST NUMERIC COUNTERS
  // ==========================================

  /// Massive KPI readout (e.g., Radar distance, huge scan total).
  static const TextStyle kpiNumberLarge = TextStyle(
    fontFamily: monospaceFamily,
    fontFeatures: tabularFeature,
    fontSize: 32,
    fontWeight: FontWeight.w900,
    letterSpacing: -0.5,
  );

  /// Medium KPI readout (e.g., Tag/s read rate, RSSI dBm).
  static const TextStyle kpiNumberMedium = TextStyle(
    fontFamily: monospaceFamily,
    fontFeatures: tabularFeature,
    fontSize: 20,
    fontWeight: FontWeight.w800,
    letterSpacing: -0.2,
  );

  /// Standard KPI readout (e.g., unique tag count in card tile).
  static const TextStyle kpiNumber = TextStyle(
    fontFamily: monospaceFamily,
    fontFeatures: tabularFeature,
    fontSize: 18,
    fontWeight: FontWeight.bold,
  );

  /// Small numeric counter inside badges / pill indicators.
  static const TextStyle kpiNumberSmall = TextStyle(
    fontFamily: monospaceFamily,
    fontFeatures: tabularFeature,
    fontSize: 14,
    fontWeight: FontWeight.w700,
  );

  // ==========================================
  // IDENTIFIER & CODE FORMATS
  // ==========================================

  /// UHF RFID 96-bit / 128-bit EPC tag hex representation.
  static const TextStyle epc = TextStyle(
    fontFamily: monospaceFamily,
    fontFeatures: tabularFeature,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.8,
  );

  /// High-density EPC readout for data tables.
  static const TextStyle epcCompact = TextStyle(
    fontFamily: monospaceFamily,
    fontFeatures: tabularFeature,
    fontSize: 11.5,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

  /// Standard 1D / 2D Barcode string (SKU, Serial, PO Number).
  static const TextStyle barcode = TextStyle(
    fontFamily: monospaceFamily,
    fontFeatures: tabularFeature,
    fontSize: 13.5,
    fontWeight: FontWeight.bold,
    letterSpacing: 1.0,
  );

  /// Pallet ID, Shelf Bin Location Code (e.g., "PL-0042", "LOC-A1-03").
  static const TextStyle codeLabel = TextStyle(
    fontFamily: monospaceFamily,
    fontFeatures: tabularFeature,
    fontSize: 13,
    fontWeight: FontWeight.bold,
    letterSpacing: 0.5,
  );

  /// Table grid cell containing numeric quantities or codes.
  static const TextStyle dataGridCell = TextStyle(
    fontFamily: monospaceFamily,
    fontFeatures: tabularFeature,
    fontSize: 12.5,
    fontWeight: FontWeight.w500,
  );

  // ==========================================
  // LABELS & INTERFACE METRICS
  // ==========================================

  /// Clean metadata field label (e.g., "TỔNG THẺ ĐỌC", "VỊ TRÍ KỆ").
  static const TextStyle fieldLabel = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.3,
  );

  /// Telemetry unit badge label (e.g., "Tags", "Tag/s", "dBm").
  static const TextStyle unitLabel = TextStyle(
    fontSize: 10,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.2,
  );
}
