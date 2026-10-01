import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Widget mũi tên chỉ hướng lớn + khoảng cách — thay thế Radar Sonar trên PDA.
/// Liên tục cập nhật hướng đi, khoảng cách, trạng thái khi quét tìm thẻ RFID.
class DirectionArrowWidget extends StatefulWidget {
  final double rssi; // -90 to -25 dBm
  final bool isTracking;
  final String targetEpc;
  final String? productName;
  final String? sku;
  final String? locationDisplay;
  final double? previousRssi;
  final double? readsPerSecond;

  const DirectionArrowWidget({
    super.key,
    required this.rssi,
    required this.isTracking,
    required this.targetEpc,
    this.productName,
    this.sku,
    this.locationDisplay,
    this.previousRssi,
    this.readsPerSecond,
  });

  @override
  State<DirectionArrowWidget> createState() => _DirectionArrowWidgetState();
}

class _DirectionArrowWidgetState extends State<DirectionArrowWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _arrowBounceController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _arrowBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    if (widget.isTracking) {
      _pulseController.repeat();
      _arrowBounceController.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant DirectionArrowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTracking != oldWidget.isTracking) {
      if (widget.isTracking) {
        _pulseController.repeat();
        _arrowBounceController.repeat(reverse: true);
      } else {
        _pulseController.stop();
        _arrowBounceController.stop();
      }
    }

    if (widget.isTracking) {
      // Tốc độ nhịp pulse nhanh hơn khi gần hơn
      final normalized = ((widget.rssi + 90) / 60).clamp(0.1, 1.0);
      final newDuration =
          Duration(milliseconds: (1600 - (normalized * 1250)).toInt());
      if (_pulseController.duration != newDuration) {
        _pulseController.duration = newDuration;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _arrowBounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strength = ((widget.rssi + 90) / 65).clamp(0.0, 1.0);
    final isVeryClose = widget.isTracking && widget.rssi >= -35.0;
    final isClose = widget.isTracking && widget.rssi >= -48.0;
    final isModerate = widget.isTracking && widget.rssi >= -65.0;
    final noSignal = !widget.isTracking || widget.rssi <= -88.0;

    Color getSignalColor() {
      if (!widget.isTracking) return const Color(0xFF64748B);
      if (isVeryClose) return const Color(0xFF10B981);
      if (isClose) return const Color(0xFF06B6D4);
      if (isModerate) return const Color(0xFF0284C7);
      return const Color(0xFFF59E0B);
    }

    // Cự ly ước tính (Log-Distance Path Loss)
    String getDistanceEstimate() {
      if (noSignal) return '---';
      final rawMeters =
          math.pow(10.0, (-48.0 - widget.rssi) / 20.0).toDouble();
      if (rawMeters < 0.10) return '< 10 cm';
      if (rawMeters < 1.0) return '${(rawMeters * 100).round()} cm';
      if (rawMeters <= 4.5) return '${rawMeters.toStringAsFixed(1)} m';
      return '> 4.5 m';
    }

    double diff = 0.0;
    if (widget.isTracking &&
        widget.previousRssi != null &&
        widget.rssi > -88.0) {
      diff = widget.rssi - widget.previousRssi!;
    }

    // Trạng thái hướng đi
    _ArrowDirection direction;
    if (!widget.isTracking) {
      direction = _ArrowDirection.idle;
    } else if (noSignal) {
      direction = _ArrowDirection.searching;
    } else if (isVeryClose) {
      direction = _ArrowDirection.found;
    } else if (diff <= -1.0) {
      direction = _ArrowDirection.wrong;
    } else if (diff >= 0.7) {
      direction = _ArrowDirection.right;
    } else {
      direction = _ArrowDirection.stable;
    }

    final signalColor = getSignalColor();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // === MŨI TÊN LỚN Ở GIỮA ===
        _buildArrowZone(signalColor, direction, diff, strength, isVeryClose,
            noSignal, getDistanceEstimate()),

        const SizedBox(height: 14),

        // === THANH TRẠNG THÁI & HƯỚNG DẪN ===
        _buildStatusCard(signalColor, direction, diff, strength, isVeryClose,
            noSignal, getDistanceEstimate()),

        // === BANNER THÀNH CÔNG ===
        if (isVeryClose) ...[
          const SizedBox(height: 10),
          _buildSuccessBanner(),
        ],
      ],
    );
  }

  Widget _buildArrowZone(
    Color signalColor,
    _ArrowDirection direction,
    double diff,
    double strength,
    bool isVeryClose,
    bool noSignal,
    String distanceText,
  ) {
    // Kích thước vùng mũi tên
    const double zoneSize = 260.0;

    // Góc xoay mũi tên dựa trên hướng
    double arrowAngle;
    switch (direction) {
      case _ArrowDirection.right:
        arrowAngle = 0; // Lên (đúng hướng)
        break;
      case _ArrowDirection.wrong:
        arrowAngle = math.pi; // Xuống (sai hướng)
        break;
      case _ArrowDirection.found:
        arrowAngle = 0; // Lên (tìm thấy)
        break;
      default:
        arrowAngle = 0;
    }

    // Màu mũi tên
    Color arrowColor;
    switch (direction) {
      case _ArrowDirection.idle:
        arrowColor = const Color(0xFF94A3B8);
        break;
      case _ArrowDirection.searching:
        arrowColor = const Color(0xFFF59E0B);
        break;
      case _ArrowDirection.right:
        arrowColor = const Color(0xFF10B981);
        break;
      case _ArrowDirection.wrong:
        arrowColor = const Color(0xFFEF4444);
        break;
      case _ArrowDirection.stable:
        arrowColor = signalColor;
        break;
      case _ArrowDirection.found:
        arrowColor = const Color(0xFF10B981);
        break;
    }

    return SizedBox(
      width: zoneSize,
      height: zoneSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Vòng tròn nền gradient nhẹ
          Container(
            width: zoneSize,
            height: zoneSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  arrowColor.withValues(alpha: widget.isTracking ? 0.15 : 0.05),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),

          // Vòng tròn viền ngoài cùng
          Container(
            width: zoneSize - 10,
            height: zoneSize - 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: arrowColor.withValues(alpha: 0.25),
                width: 2,
              ),
            ),
          ),

          // Vòng tròn viền giữa
          Container(
            width: zoneSize - 60,
            height: zoneSize - 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: arrowColor.withValues(alpha: 0.15),
                width: 1.5,
              ),
            ),
          ),

          // Pulse animation khi tracking
          if (widget.isTracking)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final t = _pulseController.value;
                return Container(
                  width: 80 + (t * 140),
                  height: 80 + (t * 140),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: arrowColor
                          .withValues(alpha: (1.0 - t).clamp(0.0, 0.6)),
                      width: isVeryClose ? 3.0 : 2.0,
                    ),
                  ),
                );
              },
            ),

          // === MŨI TÊN TO ĐÙNG ===
          if (direction == _ArrowDirection.searching)
            // Đang dò tín hiệu: hiển thị icon radar nhấp nháy
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return Opacity(
                  opacity: 0.4 + (_pulseController.value * 0.6),
                  child: Icon(
                    Icons.sensors_rounded,
                    size: 80,
                    color: arrowColor,
                  ),
                );
              },
            )
          else if (direction == _ArrowDirection.found)
            // Tìm thấy: icon check lớn
            Icon(
              Icons.check_circle_rounded,
              size: 90,
              color: arrowColor,
            )
          else if (direction == _ArrowDirection.idle)
            // Chưa bật
            Icon(
              Icons.navigation_rounded,
              size: 80,
              color: arrowColor.withValues(alpha: 0.5),
            )
          else
            // Đang dò: MŨI TÊN LỚN xoay theo hướng
            AnimatedBuilder(
              animation: _arrowBounceController,
              builder: (context, _) {
                final bounce = direction == _ArrowDirection.right
                    ? -_arrowBounceController.value * 8
                    : (direction == _ArrowDirection.wrong
                        ? _arrowBounceController.value * 6
                        : 0.0);
                return Transform.translate(
                  offset: Offset(0, bounce),
                  child: Transform.rotate(
                    angle: arrowAngle,
                    child: CustomPaint(
                      size: const Size(100, 120),
                      painter: _BigArrowPainter(
                        color: arrowColor,
                        glowIntensity: strength,
                      ),
                    ),
                  ),
                );
              },
            ),

          // === KHOẢNG CÁCH HIỂN THỊ DƯỚI MŨI TÊN ===
          if (!noSignal && direction != _ArrowDirection.idle)
            Positioned(
              bottom: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: arrowColor.withValues(alpha: 0.6),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: arrowColor.withValues(alpha: 0.3),
                      blurRadius: 12,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Text(
                  distanceText,
                  style: TextStyle(
                    color: arrowColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'monospace',
                    letterSpacing: -0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(
    Color signalColor,
    _ArrowDirection direction,
    double diff,
    double strength,
    bool isVeryClose,
    bool noSignal,
    String distanceText,
  ) {
    // Trạng thái text
    String statusText;
    IconData statusIcon;
    Color statusColor;

    switch (direction) {
      case _ArrowDirection.idle:
        statusText = 'BÓP CÒ SÚNG ĐỂ BẮT ĐẦU DÒ TÌM';
        statusIcon = Icons.sensors_off_rounded;
        statusColor = const Color(0xFF94A3B8);
        break;
      case _ArrowDirection.searching:
        statusText = 'ĐANG DÒ TÍN HIỆU...';
        statusIcon = Icons.wifi_find_rounded;
        statusColor = const Color(0xFFF59E0B);
        break;
      case _ArrowDirection.right:
        statusText = '⬆️ ĐÚNG HƯỚNG · TIẾN LÊN';
        statusIcon = Icons.trending_up_rounded;
        statusColor = const Color(0xFF10B981);
        break;
      case _ArrowDirection.wrong:
        statusText = '🔄 LỆCH HƯỚNG · QUAY LẠI';
        statusIcon = Icons.trending_down_rounded;
        statusColor = const Color(0xFFEF4444);
        break;
      case _ArrowDirection.stable:
        statusText = '➡️ GIỮ HƯỚNG · QUÉT ỔN ĐỊNH';
        statusIcon = Icons.swap_horiz_rounded;
        statusColor = signalColor;
        break;
      case _ArrowDirection.found:
        statusText = '🎯 ĐÃ TÌM THẤY! NGAY TRƯỚC MẶT';
        statusIcon = Icons.check_circle_rounded;
        statusColor = const Color(0xFF10B981);
        break;
    }

    // Xu hướng
    String getTrendText() {
      if (noSignal) return '---';
      if (diff > 1.0) return '🔥 NÓNG DẦN';
      if (diff < -1.0) return '❄️ LẠNH DẦN';
      return '➡️ ỔN ĐỊNH';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFE9E2D5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isVeryClose ? const Color(0xFF10B981) : const Color(0xFFC7BDAF),
          width: isVeryClose ? 2.0 : 1.0,
        ),
        boxShadow: isVeryClose
            ? [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                )
              ]
            : null,
      ),
      child: Column(
        children: [
          // Badge trạng thái hướng đi (cập nhật liên tục)
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: statusColor, width: 1.3),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(statusIcon, size: 18, color: statusColor),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    statusText,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Chỉ số dBm & Xu hướng & Tốc độ đọc
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sóng: ${widget.rssi.toStringAsFixed(0)} dBm',
                style: const TextStyle(
                  color: Color(0xFF6B5D4D),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.isTracking && (widget.readsPerSecond ?? 0) > 0)
                Text(
                  '⚡ ${(widget.readsPerSecond ?? 0).toStringAsFixed(0)} gói/s',
                  style: const TextStyle(
                    color: Color(0xFF0D9488),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              Flexible(
                child: Text(
                  getTrendText(),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Thanh cường độ sóng
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: widget.isTracking ? strength : 0.0,
              minHeight: 8,
              backgroundColor: const Color(0xFFF4EFE6),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981), width: 1.5),
      ),
      child: Row(
        children: [
          const Icon(Icons.stars_rounded, color: Color(0xFF10B981), size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ĐÃ TÌM THẤY MỤC TIÊU!',
                  style: TextStyle(
                    color: Color(0xFF047857),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  widget.locationDisplay != null &&
                          widget.locationDisplay!.isNotEmpty
                      ? 'Vị trí đăng ký: ${widget.locationDisplay}'
                      : 'Thẻ RFID đang nằm ngay sát đầu đọc súng PDA.',
                  style: const TextStyle(color: Color(0xFF2C251E), fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

enum _ArrowDirection { idle, searching, right, wrong, stable, found }

/// Custom painter vẽ mũi tên lớn chỉ hướng
class _BigArrowPainter extends CustomPainter {
  final Color color;
  final double glowIntensity;

  _BigArrowPainter({required this.color, required this.glowIntensity});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Vẽ mũi tên tam giác lớn hướng lên
    final arrowPath = Path()
      ..moveTo(cx, 0) // Đỉnh mũi tên
      ..lineTo(w, h * 0.45) // Góc phải
      ..lineTo(w * 0.65, h * 0.45) // Vai phải
      ..lineTo(w * 0.65, h) // Chân phải
      ..lineTo(w * 0.35, h) // Chân trái
      ..lineTo(w * 0.35, h * 0.45) // Vai trái
      ..lineTo(0, h * 0.45) // Góc trái
      ..close();

    // Glow effect
    if (glowIntensity > 0.2) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: glowIntensity * 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12);
      canvas.drawPath(arrowPath, glowPaint);
    }

    // Fill chính
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(arrowPath, fillPaint);

    // Viền sáng
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(arrowPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _BigArrowPainter oldDelegate) =>
      color != oldDelegate.color || glowIntensity != oldDelegate.glowIntensity;
}
