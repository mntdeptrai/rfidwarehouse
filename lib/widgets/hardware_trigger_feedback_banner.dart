import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/uhf_service.dart';
import '../theme/eye_care_theme.dart';

/// Enterprise Warm Stone & Royal Blue Hardware Trigger Feedback Banner
/// Specialized for Seuic AUTOID UTouch 2 & UTouch C Pistol-Grip Handhelds.
///
/// Reactively listens to [UhfService.onTriggerStateChanged] and [UhfService.isTriggerPressed]
/// to provide immediate eye-level visual & haptic confirmation when the physical gun trigger
/// is pulled in warehouse aisles.
class HardwareTriggerFeedbackBanner extends StatefulWidget {
  final bool compact;
  final bool? externalIsScanning;
  final int? scannedCount;
  final String? customIdleLabel;
  final VoidCallback? onSimulateTriggerTap;

  const HardwareTriggerFeedbackBanner({
    super.key,
    this.compact = false,
    this.externalIsScanning,
    this.scannedCount,
    this.customIdleLabel,
    this.onSimulateTriggerTap,
  });

  @override
  State<HardwareTriggerFeedbackBanner> createState() =>
      _HardwareTriggerFeedbackBannerState();
}

class _HardwareTriggerFeedbackBannerState
    extends State<HardwareTriggerFeedbackBanner> {
  final UhfService _uhf = UhfService();
  final EyeCareThemeService _eyeCare = EyeCareThemeService();
  StreamSubscription<bool>? _triggerSub;
  bool _isTriggerPressed = false;

  @override
  void initState() {
    super.initState();
    _isTriggerPressed = _uhf.isTriggerPressed;

    _uhf.addListener(_onUhfChanged);
    _eyeCare.addListener(_onUhfChanged);
    _triggerSub = _uhf.onTriggerStateChanged.listen((pressed) {
      if (!mounted) return;
      if (pressed && !_isTriggerPressed) {
        HapticFeedback.selectionClick();
      }
      setState(() {
        _isTriggerPressed = pressed;
      });
    });
  }

  bool get _isActive =>
      _isTriggerPressed ||
      (widget.externalIsScanning ?? false) ||
      _uhf.isScanning;

  void _onUhfChanged() {
    if (!mounted) return;
    final currentTrigger = _uhf.isTriggerPressed;
    if (currentTrigger != _isTriggerPressed) {
      _isTriggerPressed = currentTrigger;
    }
    setState(() {});
  }

  @override
  void dispose() {
    _triggerSub?.cancel();
    _uhf.removeListener(_onUhfChanged);
    _eyeCare.removeListener(_onUhfChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _eyeCare.colors;
    final isTrigger = _isTriggerPressed;
    final isScanning = _isActive;
    final readRate = _uhf.readRate;
    final tagCount = widget.scannedCount ?? _uhf.uniqueTagCount;
    final powerDbm = _uhf.rfPower;

    final Color activeAccent = isTrigger
        ? c.rfidCyan
        : (isScanning ? c.successEmerald : c.textSecondary);

    final Color bgFill = isTrigger
        ? c.rfidCyan.withValues(alpha: 0.12)
        : (isScanning
            ? c.successEmerald.withValues(alpha: 0.10)
            : c.bgCard);

    final String statusText = isTrigger
        ? '⚡ ĐANG GIỮ CÒ SÚNG QUÉT'
        : (isScanning
            ? '📡 ĐANG PHÁT SÓNG UHF RFID'
            : (widget.customIdleLabel ?? 'CÒ SÚNG SẴN SÀNG • BÓP CÒ ĐỂ QUÉT'));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 10 : 12,
        vertical: widget.compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: bgFill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isScanning
              ? activeAccent.withValues(alpha: 0.75)
              : c.border,
          width: isScanning ? 1.5 : 1.0,
        ),
        boxShadow: isScanning
            ? [
                BoxShadow(
                  color: activeAccent.withValues(alpha: 0.16),
                  blurRadius: 8,
                  spreadRadius: 0.5,
                ),
              ]
            : null,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 290;
          return Row(
            children: [
              Container(
                width: widget.compact ? 24 : 28,
                height: widget.compact ? 24 : 28,
                decoration: BoxDecoration(
                  color: isScanning
                      ? activeAccent.withValues(alpha: 0.15)
                      : c.bgCardElevated,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isScanning ? activeAccent : c.border,
                    width: 1.2,
                  ),
                ),
                child: Icon(
                  isTrigger
                      ? Icons.radar_rounded
                      : (isScanning
                          ? Icons.sensors_rounded
                          : Icons.gps_fixed_rounded),
                  size: widget.compact ? 14 : 16,
                  color: isScanning ? activeAccent : c.rfidCyan,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      statusText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isScanning ? activeAccent : c.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: widget.compact ? 11.0 : 12.0,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (!widget.compact) ...[
                      const SizedBox(height: 2),
                      Text(
                        isTrigger
                            ? 'Seuic UTouch 2/C • Cò súng vật lý đang kích hoạt'
                            : 'Seuic UTouch 2/C • Công suất $powerDbm dBm',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!isNarrow) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: isScanning
                        ? activeAccent.withValues(alpha: 0.12)
                        : c.bgCardElevated,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isScanning
                          ? activeAccent.withValues(alpha: 0.45)
                          : c.border,
                    ),
                  ),
                  child: Text(
                    isScanning ? '$readRate tag/s' : '$tagCount tags',
                    style: AppTypography.monospaceTabular(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: isScanning ? activeAccent : c.textPrimary,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
