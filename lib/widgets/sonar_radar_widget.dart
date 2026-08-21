import 'package:flutter/material.dart';

class SonarRadarWidget extends StatefulWidget {
  final double rssi; // -90 to -30 dBm
  final bool isTracking;
  final String targetEpc;

  const SonarRadarWidget({
    super.key,
    required this.rssi,
    required this.isTracking,
    required this.targetEpc,
  });

  @override
  State<SonarRadarWidget> createState() => _SonarRadarWidgetState();
}

class _SonarRadarWidgetState extends State<SonarRadarWidget> with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
  }

  @override
  void didUpdateWidget(covariant SonarRadarWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Tăng tốc độ nhịp sóng nếu RSSI càng mạnh (thẻ càng gần)
    if (widget.isTracking) {
      final normalized = ((widget.rssi + 90) / 60).clamp(0.1, 1.0);
      final newDuration = Duration(milliseconds: (1800 - (normalized * 1300)).toInt());
      _pulseController.duration = newDuration;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Chuẩn hóa RSSI sang thang 0.0 -> 1.0
    // -90 dBm = Rất xa (0.0), -30 dBm = Rất gần (1.0)
    final strength = ((widget.rssi + 90) / 60).clamp(0.0, 1.0);

    Color getSignalColor() {
      if (strength > 0.75) return const Color(0xFF10B981); // Xanh lá: Rất gần
      if (strength > 0.45) return const Color(0xFF38BDF8); // Xanh dương: Đang tới gần
      if (strength > 0.2) return const Color(0xFFF59E0B); // Vàng: Xa
      return Colors.white38; // Rất yếu / Chưa thấy
    }

    String getProximityText() {
      if (!widget.isTracking) return 'CHƯA BẬT ĐỊNH VỊ';
      if (strength > 0.85) return '🎯 NGAY TRƯỚC MẶT · < 0.5m';
      if (strength > 0.65) return '🔥 RẤT GẦN · 1 - 2m';
      if (strength > 0.35) return '📍 ĐANG TỚI GẦN · 2 - 4m';
      return '❄️ TÍN HIỆU XA / YẾU · > 4m';
    }

    final signalColor = getSignalColor();

    return Column(
      children: [
        // Sonar Animation Circle
        SizedBox(
          width: 220,
          height: 220,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Vòng tròn cơ sở
              Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0F172A),
                  border: Border.all(color: const Color(0xFF334155), width: 1),
                ),
              ),
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF334155), width: 1),
                ),
              ),
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF334155), width: 1),
                ),
              ),

              // Hiệu ứng sóng lan tỏa
              if (widget.isTracking)
                AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final waveValue = _pulseController.value;
                    return Container(
                      width: 50 + (waveValue * 150),
                      height: 50 + (waveValue * 150),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: signalColor.withValues(alpha: 1.0 - waveValue),
                          width: 2,
                        ),
                      ),
                    );
                  },
                ),

              // Tâm điểm phát sóng
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isTracking ? signalColor : const Color(0xFF334155),
                  boxShadow: widget.isTracking
                      ? [
                          BoxShadow(
                            color: signalColor.withValues(alpha: 0.6),
                            blurRadius: 20,
                            spreadRadius: 4,
                          ),
                        ]
                      : null,
                ),
                child: const Icon(
                  Icons.radar,
                  color: Colors.white,
                  size: 26,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Thanh đo cường độ RSSI (Hot/Cold Gauge)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    getProximityText(),
                    style: TextStyle(
                      color: signalColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    '${widget.rssi.toStringAsFixed(0)} dBm',
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Courier',
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: strength,
                  minHeight: 10,
                  backgroundColor: const Color(0xFF0F172A),
                  valueColor: AlwaysStoppedAnimation<Color>(signalColor),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
