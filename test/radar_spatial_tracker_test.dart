import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/services/radar_spatial_tracker.dart';

void main() {
  group('RadarSpatialTracker: Thuật toán xác định vector hướng 360 độ của chip RFID', () {
    late RadarSpatialTracker tracker;

    setUp(() {
      tracker = RadarSpatialTracker();
    });

    test('1. Ban đầu chưa có dữ liệu quét: targetAzimuth và relativeAngle trả về null', () {
      expect(tracker.targetAzimuthDeg, isNull);
      expect(tracker.hasLockedTarget, isFalse);
      expect(tracker.relativeAngleDeg, isNull);
      expect(tracker.relativeAngleRad, isNull);
    });

    test('2. Quét quét qua các góc: Nhận diện chính xác góc đỉnh sóng tại 60 độ (Northeast)', () {
      // Giả lập người dùng lia súng từ 0 độ đến 120 độ
      // Tại 0 độ (Bắc): Sóng yếu (-75 dBm)
      tracker.updateHeading(0.0);
      tracker.recordTagSample(-75.0);

      // Tại 30 độ: Sóng trung bình (-60 dBm)
      tracker.updateHeading(30.0);
      tracker.recordTagSample(-60.0);

      // Tại 60 độ: ĐỈNH SÓNG MẠNH NHẤT (-42 dBm) -> Hướng của chip!
      tracker.updateHeading(60.0);
      tracker.recordTagSample(-42.0);
      tracker.recordTagSample(-43.0);

      // Tại 90 độ: Sóng yếu đi (-62 dBm)
      tracker.updateHeading(90.0);
      tracker.recordTagSample(-62.0);

      // Tại 120 độ: Sóng rất yếu (-78 dBm)
      tracker.updateHeading(120.0);
      tracker.recordTagSample(-78.0);

      // Xác nhận góc ước tính của chip tiệm cận góc đỉnh sóng 60 độ (sai số < 5 độ)
      expect(tracker.targetAzimuthDeg, isNotNull);
      final estimated = tracker.targetAzimuthDeg!;
      expect((estimated - 60.0).abs() < 6.0, isTrue, reason: 'Estimated $estimated should be close to 60 deg');
      expect(tracker.hasLockedTarget, isTrue);

      // Bây giờ người dùng quay súng đi các góc khác nhau:
      // A. Chĩa súng hướng Bắc (0 độ) -> Mũi tên phải chỉ lệch sang PHẢI khoảng +60 độ
      tracker.updateHeading(0.0);
      expect((tracker.relativeAngleDeg! - 60.0).abs() < 6.0, isTrue);

      // B. Chĩa súng thẳng vào chip (60 độ) -> Mũi tên phải chỉ THẲNG TẮP (0 độ)
      tracker.updateHeading(60.0);
      expect(tracker.relativeAngleDeg!.abs() < 6.0, isTrue);

      // C. Chĩa súng lệch sang Đông (90 độ) -> Mũi tên phải chỉ lệch sang TRÁI khoảng -30 độ
      tracker.updateHeading(90.0);
      expect((tracker.relativeAngleDeg! - (-30.0)).abs() < 6.0, isTrue);

      // D. Quay người sang hướng Tây Nam (240 độ) -> Mũi tên phải chỉ ĐẰNG SAU LƯNG (~180 độ)
      tracker.updateHeading(240.0);
      expect((tracker.relativeAngleDeg!.abs() - 180.0).abs() < 8.0, isTrue);
    });

    test('3. Reset đưa toàn bộ trạng thái về ban đầu', () {
      tracker.updateHeading(45.0);
      tracker.recordTagSample(-50.0);
      expect(tracker.sampleCount, equals(1));

      tracker.reset();
      expect(tracker.sampleCount, equals(0));
      expect(tracker.targetAzimuthDeg, isNull);
      expect(tracker.relativeAngleDeg, isNull);
    });

    test('4. Khi di chuyển chip sang vị trí mới (từ 60 độ sang 180 độ): Bộ theo dõi thích ứng nhanh chóng theo hướng mới', () {
      final baseTime = DateTime(2026, 10, 7, 8, 0, 0);

      // Ban đầu chip ở 60 độ
      tracker.updateHeading(60.0);
      tracker.recordTagSample(-42.0, time: baseTime);
      tracker.recordTagSample(-43.0, time: baseTime.add(const Duration(milliseconds: 100)));
      expect((tracker.targetAzimuthDeg! - 60.0).abs() < 5.0, isTrue);

      // Sau đó chip được di chuyển sang 180 độ (South)
      // Người dùng lia súng sang 180 độ và bắt được sóng mạnh tại vị trí mới
      final moveTime = baseTime.add(const Duration(milliseconds: 2000));
      tracker.updateHeading(180.0);
      tracker.recordTagSample(-40.0, time: moveTime);
      tracker.recordTagSample(-41.0, time: moveTime.add(const Duration(milliseconds: 100)));

      // Các mẫu cũ ở 60 độ đã quá 1800ms nên bị prune, hướng mới phải khóa ngay vào 180 độ
      expect(tracker.targetAzimuthDeg, isNotNull);
      final newEstimated = tracker.targetAzimuthDeg!;
      expect((newEstimated - 180.0).abs() < 6.0, isTrue, reason: 'Estimated $newEstimated should adapt to 180 deg');

      // Khi chĩa thẳng vào 180 độ -> góc tương đối phải là 0 độ (CHÍNH DIỆN)
      expect(tracker.relativeAngleDeg!.abs() < 6.0, isTrue);
    });
  });
}
