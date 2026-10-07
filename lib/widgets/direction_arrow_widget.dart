import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Widget định vị AirTag / Find My chỉ hướng và cự ly thời gian thực.
/// Mô phỏng trải nghiệm Precision Finding của Apple AirTag:
/// - Mũi tên chỉ hướng xoay mượt mà theo gradient tín hiệu RSSI.
/// - Hiển thị cự ly (cm / m) rõ ràng, cập nhật liên tục.
/// - Hiệu ứng sóng radar đồng tâm tỏa ra khi tìm kiếm và chevrons chuyển động khi tiếp cận.
/// - Trạng thái "NGAY TẠI ĐÂY" (Here) hào quang xanh ngọc rực rỡ khi chạm đích.
class DirectionArrowWidget extends StatefulWidget {
  final double rssi; // -90 to -25 dBm
  final bool isTracking;
  final String targetEpc;
  final String? productName;
  final String? sku;
  final String? locationDisplay;
  final double? previousRssi;
  final double? readsPerSecond;
  final bool isPallet;
  final double? targetAzimuthDeg;
  final double? relativeAngleDeg;
  final bool hasLockedTarget;

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
    this.isPallet = false,
    this.targetAzimuthDeg,
    this.relativeAngleDeg,
    this.hasLockedTarget = false,
  });

  @override
  State<DirectionArrowWidget> createState() => _DirectionArrowWidgetState();
}

class _DirectionArrowWidgetState extends State<DirectionArrowWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _arrowBounceController;
  late AnimationController _chevronFlowController;
  late AnimationController _angleController;
  late Animation<double> _angleAnimation;

  double _currentAngle = 0.0;
  double _targetAngle = 0.0;

  @override
  void initState() {
    super.initState();
    // 1. Nhịp thở radar pulse (AirTag Sonar Rings)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    // 2. Độ nảy nhấp nhô của mũi tên hướng tới mục tiêu
    _arrowBounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    // 3. Luồng sóng chevrons di chuyển dọc thân mũi tên (Forward Ripple Wave)
    _chevronFlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    // 4. Xoay góc mũi tên mượt mà theo cảm biến (Fast & Responsive Heading Rotation)
    _angleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 60),
    );
    _angleAnimation = Tween<double>(begin: 0.0, end: 0.0).animate(
      CurvedAnimation(parent: _angleController, curve: Curves.easeOutQuad),
    );

    if (widget.isTracking) {
      _startAnimations();
    }
  }

  void _startAnimations() {
    _pulseController.repeat();
    _arrowBounceController.repeat(reverse: true);
    _chevronFlowController.repeat();
  }

  void _stopAnimations() {
    _pulseController.stop();
    _arrowBounceController.stop();
    _chevronFlowController.stop();
  }

  @override
  void didUpdateWidget(covariant DirectionArrowWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isTracking != oldWidget.isTracking) {
      if (widget.isTracking) {
        _startAnimations();
      } else {
        _stopAnimations();
      }
    }

    if (widget.isTracking) {
      // Nhịp pulse và luồng sóng tăng tốc khi càng đến gần
      final normalized = ((widget.rssi + 90) / 60).clamp(0.1, 1.0);
      final newPulseDuration =
          Duration(milliseconds: (1600 - (normalized * 1250)).toInt());
      if (_pulseController.duration != newPulseDuration) {
        _pulseController.duration = newPulseDuration;
      }

      final newFlowDuration =
          Duration(milliseconds: (1100 - (normalized * 750)).toInt());
      if (_chevronFlowController.duration != newFlowDuration) {
        _chevronFlowController.duration = newFlowDuration;
      }
    }

    // Tính góc xoay mục tiêu dựa trên độ chênh lệch tín hiệu hoặc cảm biến góc quay
    double diff = 0.0;
    if (widget.isTracking &&
        widget.previousRssi != null &&
        widget.rssi > -88.0) {
      diff = widget.rssi - widget.previousRssi!;
    }

    final isVeryClose = widget.isTracking && widget.rssi >= -40.0;
    final noSignal = !widget.isTracking || widget.rssi <= -88.0;

    double nextTargetAngle = 0.0;
    if (!widget.isTracking || isVeryClose) {
      nextTargetAngle = 0.0;
    } else if (widget.relativeAngleDeg != null) {
      // Khi có góc tương đối của chip so với mũi súng PDA: Xoay mũi tên theo góc này
      nextTargetAngle = widget.relativeAngleDeg! * (math.pi / 180.0);
    } else {
      // Chưa có góc: Giữ góc 0.0
      nextTargetAngle = 0.0;
    }

    if ((nextTargetAngle - _targetAngle).abs() > 0.015) {
      _targetAngle = nextTargetAngle;

      // Xoay theo cung góc ngắn nhất để chuyển động cực mượt (Shortest Angular Path)
      final current = _angleAnimation.value;
      double delta = nextTargetAngle - current;
      while (delta < -math.pi) delta += 2 * math.pi;
      while (delta > math.pi) delta -= 2 * math.pi;
      final target = current + delta;

      _angleAnimation = Tween<double>(
        begin: current,
        end: target,
      ).animate(
        CurvedAnimation(parent: _angleController, curve: Curves.easeOutQuad),
      );
      _angleController.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _arrowBounceController.dispose();
    _chevronFlowController.dispose();
    _angleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strength = ((widget.rssi + 90) / 65).clamp(0.0, 1.0);
    final isVeryClose = widget.isTracking && widget.rssi >= -40.0;
    final isClose = widget.isTracking && widget.rssi >= -48.0;
    final isModerate = widget.isTracking && widget.rssi >= -65.0;
    final noSignal = !widget.isTracking || widget.rssi <= -88.0;

    Color getSignalColor() {
      if (!widget.isTracking) return const Color(0xFF64748B);
      if (isVeryClose) return const Color(0xFF10B981); // Emerald Green
      if (isClose) return const Color(0xFF06B6D4); // Cyan
      if (isModerate) return const Color(0xFF0284C7); // Blue
      return const Color(0xFFF59E0B); // Amber
    }

    // Cự ly ước tính theo hàm suy hao tín hiệu (Log-Distance Path Loss)
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
    } else if (isVeryClose) {
      direction = _ArrowDirection.found;
    } else if (widget.relativeAngleDeg != null) {
      final rel = widget.relativeAngleDeg!;
      if (rel.abs() <= 25.0) {
        direction = _ArrowDirection.right; // ⬆️ ĐÚNG HƯỚNG · TIẾN LÊN
      } else if (rel.abs() >= 115.0) {
        direction = _ArrowDirection.wrong; // 🔄 QUAY ĐẰNG SAU
      } else {
        direction = _ArrowDirection.stable; // ➡️ / ⬅️ BÊN PHẢI HOẶC TRÁI
      }
    } else if (noSignal) {
      direction = _ArrowDirection.searching;
    } else {
      // Đang bắt được sóng nhưng chưa có góc: Xoay máy chậm qua lại
      direction = _ArrowDirection.searching;
    }

    final signalColor = getSignalColor();
    final distanceText = getDistanceEstimate();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // === VÙNG ĐỊNH VỊ AIRTAG (PRECISION FINDING ZONE) ===
        _buildAirTagPrecisionZone(
          signalColor: signalColor,
          direction: direction,
          diff: diff,
          strength: strength,
          isVeryClose: isVeryClose,
          noSignal: noSignal,
          distanceText: distanceText,
        ),

        const SizedBox(height: 14),

        // === THANH THÔNG SỐ & CHỈ HƯỚNG CHI TIẾT ===
        _buildStatusCard(
          signalColor: signalColor,
          direction: direction,
          diff: diff,
          strength: strength,
          isVeryClose: isVeryClose,
          noSignal: noSignal,
          distanceText: distanceText,
        ),

        // === BANNER THÀNH CÔNG (KHI ĐẾN SÁT MỤC TIÊU) ===
        if (isVeryClose) ...[
          const SizedBox(height: 10),
          _buildSuccessBanner(),
        ],
      ],
    );
  }

  /// Vùng radar tròn phong cách Apple AirTag với kim chỉ hướng năng động
  Widget _buildAirTagPrecisionZone({
    required Color signalColor,
    required _ArrowDirection direction,
    required double diff,
    required double strength,
    required bool isVeryClose,
    required bool noSignal,
    required String distanceText,
  }) {
    const double zoneSize = 270.0;

    // Màu chủ đạo theo trạng thái
    Color themeColor;
    switch (direction) {
      case _ArrowDirection.idle:
        themeColor = const Color(0xFF94A3B8);
        break;
      case _ArrowDirection.searching:
        themeColor = noSignal ? const Color(0xFFF59E0B) : const Color(0xFF0284C7);
        break;
      case _ArrowDirection.right:
        themeColor = const Color(0xFF10B981);
        break;
      case _ArrowDirection.wrong:
        themeColor = const Color(0xFFEF4444);
        break;
      case _ArrowDirection.stable:
        themeColor = signalColor;
        break;
      case _ArrowDirection.found:
        themeColor = const Color(0xFF10B981);
        break;
    }

    return Container(
      width: zoneSize,
      height: zoneSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF0F172A), // Deep Slate nền đen AirTag
        boxShadow: [
          BoxShadow(
            color: themeColor.withValues(alpha: widget.isTracking ? 0.25 : 0.08),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Vòng tròn nền tỏa sáng (Radial Aura)
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            width: zoneSize,
            height: zoneSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  themeColor.withValues(
                    alpha: isVeryClose ? 0.35 : (widget.isTracking ? 0.20 : 0.05),
                  ),
                  Colors.transparent,
                ],
                stops: const [0.0, 1.0],
              ),
            ),
          ),

          // 2. Các vòng tròn radar đồng tâm mờ
          Container(
            width: zoneSize - 16,
            height: zoneSize - 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: themeColor.withValues(alpha: 0.20),
                width: 1.5,
              ),
            ),
          ),
          Container(
            width: zoneSize - 70,
            height: zoneSize - 70,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: themeColor.withValues(alpha: 0.15),
                width: 1.2,
              ),
            ),
          ),
          Container(
            width: zoneSize - 130,
            height: zoneSize - 130,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: themeColor.withValues(alpha: 0.12),
                width: 1.0,
              ),
            ),
          ),

          // 3. Sóng radar mở rộng khi đang quét (Pulsing Sonar Rings)
          if (widget.isTracking)
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final t = _pulseController.value;
                return Container(
                  width: 80 + (t * 160),
                  height: 80 + (t * 160),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: themeColor.withValues(
                        alpha: (1.0 - t).clamp(0.0, 0.55),
                      ),
                      width: isVeryClose ? 3.0 : 2.0,
                    ),
                  ),
                );
              },
            ),

          // 4. TRUNG TÂM AIRTAG: MŨI TÊN CHỈ HƯỚNG HOẶC TRẠNG THÁI "HERE"
          if (direction == _ArrowDirection.searching)
            // Đang dò sóng hoặc quét tìm góc khóa: biểu tượng radar quét xoay tròn
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final rot = _pulseController.value * 2 * math.pi;
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Transform.rotate(
                      angle: rot,
                      child: Icon(
                        Icons.radar_rounded,
                        size: 76,
                        color: themeColor,
                      ),
                    ),
                    if (!noSignal) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: themeColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: themeColor, width: 1),
                        ),
                        child: Text(
                          'LIA MÁY QUA LẠI',
                          style: TextStyle(
                            color: themeColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            )
          else if (direction == _ArrowDirection.found || isVeryClose)
            // Đã tìm thấy sát nút: Vòng hào quang xanh lá Apple AirTag "HERE"
            _buildHereCelebrationCircle(themeColor)
          else if (direction == _ArrowDirection.idle)
            // Chưa bật dò: Mũi tên chờ
            Icon(
              Icons.navigation_rounded,
              size: 80,
              color: themeColor.withValues(alpha: 0.4),
            )
          else
            // Đang dò mục tiêu: Kim chỉ hướng AirTag xoay mượt mà + luồng sóng chevrons
            AnimatedBuilder(
              animation: Listenable.merge([
                _arrowBounceController,
                _angleController,
                _chevronFlowController,
              ]),
              builder: (context, _) {
                final bounce = direction == _ArrowDirection.right
                    ? -_arrowBounceController.value * 8
                    : (direction == _ArrowDirection.wrong
                        ? _arrowBounceController.value * 6
                        : 0.0);

                final currentAngle = _angleAnimation.value;

                return Transform.translate(
                  offset: Offset(0, bounce),
                  child: Transform.rotate(
                    angle: currentAngle,
                    child: CustomPaint(
                      size: const Size(110, 130),
                      painter: _AirTagPointerPainter(
                        color: themeColor,
                        glowIntensity: strength,
                        flowValue: _chevronFlowController.value,
                        isWrongDirection: direction == _ArrowDirection.wrong,
                      ),
                    ),
                  ),
                );
              },
            ),

          // 5. CHỈ SỐ KHOẢNG CÁCH (HERO DISTANCE) HIỂN THỊ TRỰC QUAN
          if (!noSignal && direction != _ArrowDirection.idle)
            Positioned(
              bottom: 18,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: themeColor.withValues(alpha: 0.8),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: themeColor.withValues(alpha: 0.35),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isVeryClose
                          ? Icons.check_circle_rounded
                          : (direction == _ArrowDirection.wrong
                              ? Icons.near_me_disabled_rounded
                              : Icons.near_me_rounded),
                      size: 18,
                      color: themeColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      distanceText,
                      style: TextStyle(
                        color: themeColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        fontFamily: 'monospace',
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Trạng thái hào quang khi tới cự ly cực gần (< 35cm) của Apple AirTag
  Widget _buildHereCelebrationCircle(Color color) {
    return AnimatedBuilder(
      animation: _arrowBounceController,
      builder: (context, _) {
        final scale = 1.0 + (_arrowBounceController.value * 0.08);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.55),
                  blurRadius: 28,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle_rounded,
                  size: 58,
                  color: Colors.white,
                ),
                SizedBox(height: 2),
                Text(
                  'NGAY TẠI ĐÂY',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 10,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Thẻ trạng thái hướng đi và cường độ dBm
  Widget _buildStatusCard({
    required Color signalColor,
    required _ArrowDirection direction,
    required double diff,
    required double strength,
    required bool isVeryClose,
    required bool noSignal,
    required String distanceText,
  }) {
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
        if (noSignal) {
          statusText = 'ĐANG DÒ TÍN HIỆU...';
          statusIcon = Icons.wifi_find_rounded;
          statusColor = const Color(0xFFF59E0B);
        } else {
          statusText = '🔄 XOAY MÁY CHẬM QUA LẠI ĐỂ KHÓA HƯỚNG';
          statusIcon = Icons.radar_rounded;
          statusColor = const Color(0xFF0284C7);
        }
        break;
      case _ArrowDirection.right:
        statusText = '⬆️ ĐÚNG HƯỚNG · TIẾN LÊN';
        statusIcon = Icons.trending_up_rounded;
        statusColor = const Color(0xFF10B981);
        break;
      case _ArrowDirection.wrong:
        if (widget.relativeAngleDeg != null &&
            widget.relativeAngleDeg!.abs() >= 115.0) {
          statusText = '🔄 CHIP Ở PHÍA SAU · QUAY NGƯỜI LẠI';
          statusIcon = Icons.trending_down_rounded;
          statusColor = const Color(0xFFEF4444);
        } else {
          statusText = '🔄 LỆCH HƯỚNG · XOAY LẠI';
          statusIcon = Icons.trending_down_rounded;
          statusColor = const Color(0xFFEF4444);
        }
        break;
      case _ArrowDirection.stable:
        if (widget.relativeAngleDeg != null) {
          if (widget.relativeAngleDeg! > 0) {
            statusText =
                '➡️ CHIP Ở BÊN PHẢI (${widget.relativeAngleDeg!.round()}°)';
            statusIcon = Icons.turn_right_rounded;
          } else {
            statusText =
                '⬅️ CHIP Ở BÊN TRÁI (${widget.relativeAngleDeg!.abs().round()}°)';
            statusIcon = Icons.turn_left_rounded;
          }
          statusColor = const Color(0xFF0284C7);
        } else {
          statusText = '🔄 XOAY MÁY CHẬM QUA LẠI ĐỂ KHÓA HƯỚNG';
          statusIcon = Icons.radar_rounded;
          statusColor = const Color(0xFF0284C7);
        }
        break;
      case _ArrowDirection.found:
        statusText = '🎯 ĐÃ TÌM THẤY! NGAY TRƯỚC MẶT';
        statusIcon = Icons.check_circle_rounded;
        statusColor = const Color(0xFF10B981);
        break;
    }

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
                noSignal
                    ? 'Sóng: --- dBm'
                    : 'Sóng: ${widget.rssi.toStringAsFixed(0)} dBm',
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
                Text(
                  widget.isPallet ? 'ĐÃ TÌM THẤY PALLET!' : 'ĐÃ TÌM THẤY MỤC TIÊU!',
                  style: const TextStyle(
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

/// Custom painter vẽ mũi tên chỉ hướng phong cách Apple AirTag với luồng sóng di chuyển
class _AirTagPointerPainter extends CustomPainter {
  final Color color;
  final double glowIntensity;
  final double flowValue;
  final bool isWrongDirection;

  _AirTagPointerPainter({
    required this.color,
    required this.glowIntensity,
    required this.flowValue,
    required this.isWrongDirection,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    // Đường viền mũi tên vát nhọn hình học phong cách Apple Industrial
    final arrowPath = Path()
      ..moveTo(cx, 0) // Đỉnh nhọn
      ..lineTo(w * 0.95, h * 0.44) // Cánh phải
      ..lineTo(w * 0.64, h * 0.44) // Khớp phải
      ..lineTo(w * 0.64, h * 0.96) // Chân phải
      ..lineTo(w * 0.36, h * 0.96) // Chân trái
      ..lineTo(w * 0.36, h * 0.44) // Khớp trái
      ..lineTo(w * 0.05, h * 0.44) // Cánh trái
      ..close();

    // Hào quang tỏa sáng (Outer Glow)
    if (glowIntensity > 0.15) {
      final glowPaint = Paint()
        ..color = color.withValues(alpha: (glowIntensity * 0.45).clamp(0.1, 0.7))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16);
      canvas.drawPath(arrowPath, glowPaint);
    }

    // Đổ bóng thân mũi tên
    final fillPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawPath(arrowPath, fillPaint);

    // Viền trắng phản chiếu sắc nét
    final borderPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(arrowPath, borderPaint);

    // Vẽ luồng mũi tên chevrons chuyển động dọc thân (^ ^ ^)
    final chevronPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.65)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.5;

    for (int i = 0; i < 3; i++) {
      final baseProgress = (flowValue + (i * 0.33)) % 1.0;
      final chevronY = (h * 0.88) - (baseProgress * (h * 0.50));
      final chevronAlpha = (1.0 - (baseProgress - 0.5).abs() * 2.0).clamp(0.0, 0.8);

      chevronPaint.color = Colors.white.withValues(alpha: chevronAlpha);

      final chevronPath = Path()
        ..moveTo(cx - 10, chevronY + 6)
        ..lineTo(cx, chevronY)
        ..lineTo(cx + 10, chevronY + 6);

      canvas.drawPath(chevronPath, chevronPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AirTagPointerPainter oldDelegate) =>
      color != oldDelegate.color ||
      glowIntensity != oldDelegate.glowIntensity ||
      flowValue != oldDelegate.flowValue ||
      isWrongDirection != oldDelegate.isWrongDirection;
}
