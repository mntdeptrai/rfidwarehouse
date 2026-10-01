import 'dart:math' as math;
import 'package:flutter/material.dart';

class SonarRadarWidget extends StatefulWidget {
  final double rssi; // -95 to -25 dBm
  final bool isTracking;
  final String targetEpc;
  final String? productName;
  final String? sku;
  final String? locationDisplay;
  final double? previousRssi;
  final double? readsPerSecond;

  const SonarRadarWidget({
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
  State<SonarRadarWidget> createState() => _SonarRadarWidgetState();
}

class _SonarRadarWidgetState extends State<SonarRadarWidget> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _sweepController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    if (widget.isTracking) {
      _pulseController.repeat();
      _sweepController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant SonarRadarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTracking != oldWidget.isTracking) {
      if (widget.isTracking) {
        _pulseController.repeat();
        _sweepController.repeat();
      } else {
        _pulseController.stop();
        _sweepController.stop();
      }
    }

    if (widget.isTracking) {
      // Tần suất nhịp sóng tăng dần khi thẻ càng gần (RSSI càng mạnh)
      final normalized = ((widget.rssi + 90) / 60).clamp(0.1, 1.0);
      final newDuration = Duration(milliseconds: (1600 - (normalized * 1250)).toInt());
      if (_pulseController.duration != newDuration) {
        _pulseController.duration = newDuration;
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _sweepController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Chuẩn hóa RSSI sang thang 0.0 -> 1.0 (-90 dBm = 0.0, -25 dBm = 1.0)
    final strength = ((widget.rssi + 90) / 65).clamp(0.0, 1.0);
    // Chạm đích (< 20 cm) khi RSSI >= -35 dBm
    final isVeryClose = widget.isTracking && widget.rssi >= -35.0;
    // Cự ly gần (< 1.0 m, đo từng cm) khi RSSI >= -48 dBm
    final isClose = widget.isTracking && widget.rssi >= -48.0;
    // Cự ly trung bình (1.0m - 3.0m) khi RSSI >= -65 dBm
    final isModerate = widget.isTracking && widget.rssi >= -65.0;

    Color getSignalColor() {
      if (!widget.isTracking) return const Color(0xFF64748B);
      if (isVeryClose) return const Color(0xFF10B981); // Emerald Green (AirTag Success)
      if (isClose) return const Color(0xFF06B6D4);     // Cyan / Electric Blue
      if (isModerate) return const Color(0xFF0284C7);  // Sky Blue
      return const Color(0xFFF59E0B);                 // Amber (Far)
    }

    // Tính cự ly theo mô hình Log-Distance Path Loss chuẩn sóng vô tuyến UHF:
    // d = 10 ^ ((-48 - RSSI) / 20)
    // Khi d < 1.0m: cập nhật từng centimet (cm)
    // Khi d >= 1.0m: cập nhật theo mét (m)
    String getDistanceEstimate() {
      if (!widget.isTracking || widget.rssi <= -88.0) return '---';
      
      // Áp dụng công thức suy hao không gian tự do hiệu chuẩn cho SEUIC UTouch 2
      final rawMeters = math.pow(10.0, (-48.0 - widget.rssi) / 20.0).toDouble();
      
      if (rawMeters < 0.10) {
        return '< 10 cm';
      } else if (rawMeters < 1.0) {
        final cm = (rawMeters * 100).round();
        return '$cm cm';
      } else if (rawMeters <= 4.5) {
        return '${rawMeters.toStringAsFixed(1)} m';
      } else {
        return '> 4.5 m';
      }
    }

    double diff = 0.0;
    if (widget.isTracking && widget.previousRssi != null && widget.rssi > -88.0) {
      diff = widget.rssi - widget.previousRssi!;
    }

    // Xác định hướng lia súng theo Gradient cường độ sóng thời gian thực (Realtime Sweep Direction)
    IconData getDirectionIcon() {
      if (!widget.isTracking) return Icons.sensors_off_rounded;
      // Khi quay lệch hướng khỏi búp sóng (sóng tụt), cảnh báo ngay lập tức dù đang ở cự ly nào
      if (diff <= -1.0) return Icons.sync_problem_rounded;
      if (diff >= 0.7) return Icons.arrow_upward_rounded; // Đang lia đúng hướng (sóng tăng)
      if (isVeryClose) return Icons.check_circle_rounded; // Chạm đích rất gần và sóng ổn định
      return Icons.radar_rounded;
    }

    String getDirectionHintText() {
      if (!widget.isTracking) return 'CHƯA BẬT ĐỊNH VỊ';
      if (widget.rssi <= -88.0) return 'ĐANG DÒ TÍN HIỆU...';
      if (diff <= -1.0) return '🔄 LỆCH HƯỚNG · LIA GÓC KHÁC';
      if (diff >= 0.7) return '⬆️ ĐÚNG HƯỚNG · TIẾN LÊN';
      if (isVeryClose) return '🎯 ĐÃ CHẠM MỤC TIÊU (< 15 cm)';
      return '➡️ GIỮ HƯỚNG QUÉT ỔN ĐỊNH';
    }

    String getTrendText() {
      if (!widget.isTracking || widget.previousRssi == null || widget.rssi <= -88.0) {
        return '---';
      }
      if (diff > 1.0) return '🔥 NÓNG DẦN (Tiến gần)';
      if (diff < -1.0) return '❄️ LẠNH DẦN (Xa ra / Lệch)';
      return '➡️ ỔN ĐỊNH';
    }

    final signalColor = getSignalColor();
    final directionIcon = getDirectionIcon();
    final directionHint = getDirectionHintText();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 1. Vòng Tròn Sonar Radar phong cách Apple AirTag / Find My
        Container(
          width: 250,
          height: 250,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                signalColor.withValues(alpha: widget.isTracking ? 0.22 : 0.06),
                const Color(0xFF1E293B).withValues(alpha: 0.1),
                Colors.transparent,
              ],
              stops: const [0.0, 0.65, 1.0],
            ),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Vòng tròn định vị cơ sở (Concentric rings)
              _buildRadarRing(230, const Color(0xFFC7BDAF).withValues(alpha: 0.4), isDashed: true),
              _buildRadarRing(175, const Color(0xFFC7BDAF).withValues(alpha: 0.5)),
              _buildRadarRing(120, const Color(0xFFC7BDAF).withValues(alpha: 0.65)),
              _buildRadarRing(65, const Color(0xFFC7BDAF).withValues(alpha: 0.8)),

              // Trục chữ thập định hướng (Crosshair guide)
              CustomPaint(
                size: const Size(230, 230),
                painter: _RadarCrosshairPainter(
                  lineColor: const Color(0xFFC7BDAF).withValues(alpha: 0.35),
                ),
              ),

              // Tia quét radar xoay tròn (Rotating Sweep Beam)
              if (widget.isTracking)
                RotationTransition(
                  turns: _sweepController,
                  child: CustomPaint(
                    size: const Size(230, 230),
                    painter: _RadarSweepPainter(
                      color: signalColor.withValues(alpha: 0.4),
                    ),
                  ),
                ),

              // Hiệu ứng sóng lan tỏa (Pulsing Sonar Ripple)
              if (widget.isTracking)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, _) {
                    final t = _pulseController.value;
                    return Container(
                      width: 55 + (t * 165),
                      height: 55 + (t * 165),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: signalColor.withValues(alpha: (1.0 - t).clamp(0.0, 1.0)),
                          width: isVeryClose ? 3.0 : 2.0,
                        ),
                        boxShadow: isVeryClose
                            ? [
                                BoxShadow(
                                  color: signalColor.withValues(alpha: (1.0 - t) * 0.5),
                                  blurRadius: 10,
                                  spreadRadius: 2,
                                )
                              ]
                            : null,
                      ),
                    );
                  },
                ),

              // Tâm điểm phát sóng & Mũi tên chỉ hướng (AirTag Center Puck with Direction Arrow)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: isVeryClose ? 64 : 56,
                height: isVeryClose ? 64 : 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isTracking
                      ? (diff <= -1.2 ? const Color(0xFFF59E0B) : signalColor)
                      : const Color(0xFF94A3B8),
                  boxShadow: widget.isTracking
                      ? [
                          BoxShadow(
                            color: (diff <= -1.2 ? const Color(0xFFF59E0B) : signalColor)
                                .withValues(alpha: isVeryClose ? 0.85 : 0.45),
                            blurRadius: isVeryClose ? 26 : 14,
                            spreadRadius: isVeryClose ? 6 : 2,
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Icon(
                    directionIcon,
                    color: Colors.white,
                    size: isVeryClose ? 34 : (diff >= 0.8 ? 32 : 26),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // 2. Thẻ hiển thị khoảng cách và trạng thái Find My
        Container(
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
              // Badge chỉ hướng theo búp sóng (Directional Pointer Badge)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: (diff <= -1.2 ? const Color(0xFFF59E0B) : signalColor).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: diff <= -1.2 ? const Color(0xFFF59E0B) : signalColor,
                    width: 1.3,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      directionIcon,
                      size: 15,
                      color: diff <= -1.2 ? const Color(0xFFD97706) : signalColor,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        directionHint,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: diff <= -1.2 ? const Color(0xFFB45309) : signalColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Khoảng cách ước tính lớn theo phong cách Apple AirTag (Cập nhật từng cm khi < 1m)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    getDistanceEstimate(),
                    style: TextStyle(
                      color: isVeryClose ? const Color(0xFF10B981) : const Color(0xFF2C251E),
                      fontSize: 34,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.5,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 4),

              // Chỉ số dBm & Xu hướng Nóng/Lạnh
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Cường độ: ${widget.rssi.toStringAsFixed(0)} dBm',
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
                        color: diff <= -1.0 ? const Color(0xFFD97706) : signalColor,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Thanh đo sóng trực quan (Hot/Cold Gauge)
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: widget.isTracking ? strength : 0.0,
                  minHeight: 8,
                  backgroundColor: const Color(0xFFF4EFE6),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    diff <= -1.2 ? const Color(0xFFF59E0B) : signalColor,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 3. Banner thông báo thành công khi tìm thấy (< 0.5m)
        if (isVeryClose) ...[
          const SizedBox(height: 10),
          Container(
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
                        widget.locationDisplay != null && widget.locationDisplay!.isNotEmpty
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
          ),
        ],
        // 4. Hộp hướng dẫn quét nan quạt chỉ hướng & đo cm
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF4EFE6),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE2D9CC)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.tips_and_updates_rounded, size: 16, color: Color(0xFFD97706)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Mẹo chỉ hướng: Bóp cò & lia súng hình nan quạt (trái ↔ phải). Hướng nào sóng tăng và mũi tên ⬆ xanh sáng là hướng của mã EPC. Khi cự ly < 1m, cự ly sẽ nhảy số chính xác từng centimet (cm).',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF6B5D4D),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRadarRing(double size, Color color, {bool isDashed = false}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 1.0),
      ),
    );
  }
}

class _RadarCrosshairPainter extends CustomPainter {
  final Color lineColor;
  _RadarCrosshairPainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);
    // Đường ngang
    canvas.drawLine(Offset(0, center.dy), Offset(size.width, center.dy), paint);
    // Đường dọc
    canvas.drawLine(Offset(center.dx, 0), Offset(center.dx, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant _RadarCrosshairPainter oldDelegate) => false;
}

class _RadarSweepPainter extends CustomPainter {
  final Color color;
  _RadarSweepPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final paint = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.0),
          color.withValues(alpha: 0.6),
        ],
        stops: const [0.75, 1.0],
      ).createShader(rect);

    canvas.drawCircle(Offset(size.width / 2, size.height / 2), size.width / 2, paint);
  }

  @override
  bool shouldRepaint(covariant _RadarSweepPainter oldDelegate) => false;
}
