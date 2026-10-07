import 'dart:math' as math;

/// Đại diện cho một mẫu đo không gian tại một thời điểm
class _SpatialSample {
  final double headingDeg;
  final double rssi;
  final DateTime time;

  _SpatialSample({
    required this.headingDeg,
    required this.rssi,
    required this.time,
  });
}

/// Bộ theo dõi không gian và hướng vector 360 độ của chip RFID (Spatial RSSI Tracker).
/// Sử dụng cửa sổ trượt động (Dynamic Rolling Window) kết hợp cảm biến góc quay con quay hồi chuyển
/// với cường độ tín hiệu RSSI qua búp sóng để bám đuổi chip theo thời gian thực (phong cách Apple AirTag).
class RadarSpatialTracker {
  /// Cửa sổ thời gian lưu mẫu (1800ms = 1.8 giây)
  /// Đủ dài để quét mượt qua các góc, đủ nhanh để lập tức thích ứng khi chip di chuyển
  static const int windowMs = 1800;

  /// Danh sách mẫu đo trong cửa sổ trượt
  final List<_SpatialSample> _recentSamples = [];

  /// Góc quay la bàn / con quay hiện tại của thiết bị (0..360 độ)
  double _deviceHeadingDeg = 0.0;
  double get deviceHeadingDeg => _deviceHeadingDeg;

  /// Vector tích lũy không gian
  double _vectorX = 0.0;
  double _vectorY = 0.0;
  double _totalWeight = 0.0;

  /// Đỉnh RSSI cao nhất trong cửa sổ hiện tại (dBm)
  double _peakRssi = -90.0;
  double get peakRssi => _peakRssi;

  /// Thời điểm nhận gói tin gần nhất
  DateTime? _lastSampleTime;
  DateTime? get lastSampleTime => _lastSampleTime;

  /// Số lượng mẫu quét hợp lệ
  int _sampleCount = 0;
  int get sampleCount => _sampleCount;

  bool _hasReceivedHeading = false;
  bool get hasReceivedHeading => _hasReceivedHeading;

  /// Hướng góc gần nhất được tính toán (giữ lại để chống giật khi sóng ngắt quãng)
  double? _lastKnownTargetAzimuthDeg;

  /// Đỉnh sóng mạnh nhất từng ghi nhận và hướng tương ứng (Persistent Peak Latching)
  double _strongestPeakRssi = -90.0;
  double? _strongestPeakHeadingDeg;
  DateTime? _strongestPeakTime;

  /// Góc tuyệt đối ước tính của chip trong không gian (0..360 độ)
  double? get targetAzimuthDeg {
    final now = _lastSampleTime ?? DateTime.now();

    // 1. Nếu có hướng đỉnh sóng mạnh nhất còn hiệu lực (trong vòng 8 giây)
    if (_strongestPeakHeadingDeg != null && _strongestPeakTime != null) {
      final ageMs = now.difference(_strongestPeakTime!).inMilliseconds;
      if (ageMs <= 8000) {
        return _strongestPeakHeadingDeg;
      }
    }

    // 2. Fallback theo bộ đệm gần nhất nếu chưa quá 6 giây
    if (_recentSamples.isEmpty || _totalWeight < 0.1) {
      if (_lastSampleTime != null &&
          now.difference(_lastSampleTime!).inMilliseconds <= 6000) {
        return _lastKnownTargetAzimuthDeg;
      }
      return null;
    }
    final rad = math.atan2(_vectorY, _vectorX);
    var deg = rad * (180.0 / math.pi);
    if (deg < 0) deg += 360.0;
    _lastKnownTargetAzimuthDeg = deg;
    return deg;
  }

  /// Mức độ tin cậy của hướng chip (0.0 .. 1.0)
  double get confidence {
    final now = _lastSampleTime ?? DateTime.now();
    if (_recentSamples.isEmpty || _totalWeight < 0.1) {
      if (_lastSampleTime != null &&
          now.difference(_lastSampleTime!).inMilliseconds <= 6000) {
        return 0.5;
      }
      return 0.0;
    }
    if (_recentSamples.length == 1) return 0.6;
    final r = math.sqrt(_vectorX * _vectorX + _vectorY * _vectorY);
    // Tỷ lệ vector kết quả trên tổng trọng số (Circular Variance measure)
    final consistency = (r / _totalWeight).clamp(0.0, 1.0);
    final countWeight = (_recentSamples.length / 4.0).clamp(0.4, 1.0);
    return (consistency * countWeight).clamp(0.0, 1.0);
  }

  /// Đã quét đủ góc và đạt độ tin cậy để bám theo chip chưa (có đỉnh sóng hoặc ít nhất 2 mẫu đo)
  bool get hasLockedTarget =>
      targetAzimuthDeg != null &&
      (_strongestPeakHeadingDeg != null || (confidence >= 0.40 && _sampleCount >= 2) || _sampleCount >= 3);

  /// Góc tương đối của chip so với mũi súng (-180..+180 độ)
  /// Trả về null nếu chưa xác định được góc chip trong không gian (tránh giả mạo 0 độ phía trước)
  double? get relativeAngleDeg {
    final target = targetAzimuthDeg;
    if (target == null) return null;

    double diff = target - _deviceHeadingDeg;
    // Chuẩn hóa về khoảng [-180..+180]
    diff = ((diff + 180.0) % 360.0) - 180.0;
    return diff;
  }

  /// Góc tương đối theo đơn vị Radian (-pi..+pi)
  double? get relativeAngleRad {
    final rel = relativeAngleDeg;
    return rel != null ? rel * (math.pi / 180.0) : null;
  }

  /// Cập nhật góc la bàn / con quay hồi chuyển của thiết bị (0..360 độ)
  void updateHeading(double headingDeg) {
    // Offset anten UTouch C (búp sóng chính hướng dọc thân máy phía trước)
    const antennaOffset = 0.0;
    _deviceHeadingDeg = ((headingDeg + antennaOffset) % 360.0 + 360.0) % 360.0;
    _hasReceivedHeading = true;
  }

  /// Ghi nhận gói tin RFID đọc được từ thẻ mục tiêu
  void recordTagSample(double rssi, {DateTime? time}) {
    final now = time ?? DateTime.now();
    _sampleCount++;
    _lastSampleTime = now;

    final clampedRssi = rssi.clamp(-90.0, -25.0);

    // Cập nhật đỉnh sóng mạnh nhất (Peak Latch):
    // Đỉnh cũ tự động suy hao nhẹ sau 3s để thích ứng khi chip di chuyển sang vị trí mới
    final peakAgeSec = _strongestPeakTime != null ? now.difference(_strongestPeakTime!).inSeconds : 999;
    final decayedPeak = _strongestPeakRssi - (peakAgeSec > 3 ? (peakAgeSec - 3) * 0.8 : 0.0);

    // Nới lỏng điều kiện cập nhật đỉnh sóng (3.0 dBm) để bắt trọn búp sóng chính khi lia máy
    if (clampedRssi >= decayedPeak - 3.0) {
      _strongestPeakRssi = clampedRssi;
      _strongestPeakHeadingDeg = _deviceHeadingDeg;
      _strongestPeakTime = now;
    }
    _recentSamples.add(_SpatialSample(
      headingDeg: _deviceHeadingDeg,
      rssi: clampedRssi,
      time: now,
    ));

    _pruneOldSamples(now);
    _recompute();
  }

  void _pruneOldSamples(DateTime now) {
    // Xóa toàn bộ các mẫu cũ hơn windowMs (4.0 giây) để thích ứng tốt cự ly xa
    _recentSamples.removeWhere((s) {
      return now.difference(s.time).inMilliseconds > windowMs;
    });
    // Giới hạn số mẫu tối đa để tối ưu bộ nhớ và CPU
    if (_recentSamples.length > 40) {
      _recentSamples.removeRange(0, _recentSamples.length - 40);
    }
  }

  void _recompute() {
    if (_recentSamples.isEmpty) {
      _vectorX = 0.0;
      _vectorY = 0.0;
      _totalWeight = 0.0;
      _peakRssi = -90.0;
      return;
    }

    // 1. Tìm đỉnh sóng trong cửa sổ trượt hiện tại
    double maxRssi = -90.0;
    for (final s in _recentSamples) {
      if (s.rssi > maxRssi) maxRssi = s.rssi;
    }
    _peakRssi = maxRssi;

    // 2. Tích lũy vector không gian có trọng số động
    final now = _recentSamples.last.time;
    double vx = 0.0;
    double vy = 0.0;
    double totalW = 0.0;

    for (final s in _recentSamples) {
      // Trọng số hàm mũ theo cường độ sóng
      final baseWeight = math.pow(10.0, (s.rssi + 90.0) / 25.0).toDouble();

      // Mẫu mới hơn có trọng số cao hơn để thích ứng nhanh với chuyển động
      final ageMs = now.difference(s.time).inMilliseconds.clamp(0, windowMs);
      final timeFactor = 1.0 - (0.4 * (ageMs / windowMs));

      // Boresight Boost: Mẫu gần đỉnh sóng (trong vòng 2.0 dBm) được tăng 3.0x trọng số
      // Vì đó là hướng súng chĩa thẳng vào chip!
      final isNearPeak = s.rssi >= maxRssi - 2.0;
      final boost = isNearPeak ? 3.0 : 1.0;

      final w = baseWeight * timeFactor * boost;
      final rad = s.headingDeg * (math.pi / 180.0);

      vx += w * math.cos(rad);
      vy += w * math.sin(rad);
      totalW += w;
    }

    _vectorX = vx;
    _vectorY = vy;
    _totalWeight = totalW;
  }

  /// Làm suy hao từ từ khi người dùng lia máy sang góc không bắt được sóng
  void decayWithoutSignal() {
    final now = DateTime.now();
    _pruneOldSamples(now);
    _recompute();
  }

  /// Đặt lại khi chuyển mục tiêu hoặc dừng quét
  void reset() {
    _recentSamples.clear();
    _vectorX = 0.0;
    _vectorY = 0.0;
    _totalWeight = 0.0;
    _peakRssi = -90.0;
    _sampleCount = 0;
    _lastSampleTime = null;
    _lastKnownTargetAzimuthDeg = null;
    _strongestPeakRssi = -90.0;
    _strongestPeakHeadingDeg = null;
    _strongestPeakTime = null;
  }
}
