import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'desktop_uhf_tcp_service.dart';

/// Màu tín hiệu của tháp đèn CTP50-3T-D-J
enum TowerLightColor {
  off,
  red,    // Đỏ: Thiếu hàng, sai hàng, thừa hàng
  yellow, // Vàng: Lỗi hệ thống ở 1 bộ phận nào đó
  green,  // Xanh: Đủ hàng thông qua (100% khớp)
}

/// Trạng thái hiện tại của tháp đèn
class TowerLightStatus {
  final TowerLightColor color;
  final bool isBuzzerOn;
  final bool isBlinking;
  final String reason;
  final DateTime timestamp;

  const TowerLightStatus({
    this.color = TowerLightColor.off,
    this.isBuzzerOn = false,
    this.isBlinking = false,
    this.reason = 'Sẵn sàng (Standby)',
    required this.timestamp,
  });

  bool get isRed => color == TowerLightColor.red;
  bool get isYellow => color == TowerLightColor.yellow;
  bool get isGreen => color == TowerLightColor.green;
  bool get isOff => color == TowerLightColor.off;

  bool get isRedBlinking => isRed && isBlinking;
  bool get isYellowBlinking => isYellow && isBlinking;
  bool get isGreenBlinking => isGreen && isBlinking;
}

/// Cấu hình chân GPO / Relay của Tháp đèn CTP50-3T-D-J
class TowerLightPinConfig {
  int redPin;    // GPO 4 (L2 - Đèn Đỏ)
  int greenPin;  // GPO 3 (L3 - Đèn Xanh)
  int yellowPin; // GPO 2 (L4 - Đèn Vàng)
  int buzzerPin; // GPO 1 (Dự phòng / Còi)
  int pulseDurationSeconds; // Thời gian duy trì tín hiệu trước khi về trạng thái chờ (0 = giữ liên tục)

  TowerLightPinConfig({
    this.redPin = 4,
    this.greenPin = 3,
    this.yellowPin = 2,
    this.buzzerPin = 1,
    this.pulseDurationSeconds = 4,
  });

  Map<String, dynamic> toMap() => {
    'redPin': redPin,
    'greenPin': greenPin,
    'yellowPin': yellowPin,
    'buzzerPin': buzzerPin,
    'pulseDurationSeconds': pulseDurationSeconds,
  };

  factory TowerLightPinConfig.fromMap(Map<String, dynamic> map) => TowerLightPinConfig(
    redPin: (map['redPin'] as num?)?.toInt() ?? 4,
    greenPin: (map['greenPin'] as num?)?.toInt() ?? 3,
    yellowPin: (map['yellowPin'] as num?)?.toInt() ?? 2,
    buzzerPin: (map['buzzerPin'] as num?)?.toInt() ?? 1,
    pulseDurationSeconds: (map['pulseDurationSeconds'] as num?)?.toInt() ?? 4,
  );
}

/// Dịch vụ quản lý và điều khiển Tháp đèn tín hiệu công nghiệp CTP50-3T-D-J
class TowerLightService extends ChangeNotifier {
  static final TowerLightService _instance = TowerLightService._internal();
  factory TowerLightService() => _instance;
  TowerLightService._internal() {
    loadConfig();
  }

  final DesktopUhfTcpService _uhfTcp = DesktopUhfTcpService();

  TowerLightPinConfig config = TowerLightPinConfig();

  TowerLightStatus _currentStatus = TowerLightStatus(timestamp: DateTime.now());
  TowerLightStatus get currentStatus => _currentStatus;

  Future<File?> _getConfigFile() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final target = File(p.join(dir.path, 'tower_light_config.json'));
      if (!target.parent.existsSync()) {
        target.parent.createSync(recursive: true);
      }
      return target;
    } catch (_) {
      try {
        final appData = Platform.environment['APPDATA'] ?? '.';
        final dir = Directory(p.join(appData, 'RFIDWarehouse'));
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return File(p.join(dir.path, 'tower_light_config.json'));
      } catch (_) {
        return null;
      }
    }
  }

  Future<void> loadConfig() async {
    try {
      final file = await _getConfigFile();
      if (file != null && await file.exists()) {
        final content = await file.readAsString();
        final map = jsonDecode(content) as Map<String, dynamic>;
        config = TowerLightPinConfig.fromMap(map);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading tower_light_config: $e');
    }
  }

  Future<bool> saveConfig(TowerLightPinConfig newConfig) async {
    config = newConfig;
    notifyListeners();
    try {
      final file = await _getConfigFile();
      if (file != null) {
        await file.writeAsString(jsonEncode(newConfig.toMap()));
      }
      return true;
    } catch (e) {
      debugPrint('Error saving tower_light_config: $e');
      return false;
    }
  }

  Future<void> testIndividualPin(int pin, bool state) async {
    await _uhfTcp.setGpo(pin, state);
  }

  Timer? _pulseTimer;
  bool _hardwareControlEnabled = true;
  bool get isHardwareControlEnabled => _hardwareControlEnabled;

  set hardwareControlEnabled(bool val) {
    _hardwareControlEnabled = val;
    notifyListeners();
  }

  // ==================== CÁC HÀM ĐIỀU KHIỂN TÍN HIỆU ====================

  /// 🟢 ĐÈN XANH: Đủ hàng thông qua (Khớp 100% đơn hàng)
  Future<void> triggerPass({String reason = 'Đủ hàng thông qua (100% khớp)'}) async {
    _pulseTimer?.cancel();
    _currentStatus = TowerLightStatus(
      color: TowerLightColor.green,
      isBuzzerOn: false,
      reason: reason,
      timestamp: DateTime.now(),
    );
    notifyListeners();

    await _sendHardwareCommand(
      red: false,
      yellow: false,
      green: true,
      buzzer: false,
    );

    if (config.pulseDurationSeconds > 0) {
      _pulseTimer = Timer(Duration(seconds: config.pulseDurationSeconds), () {
        turnOffAll(reason: 'Đã hoàn tất thông qua');
      });
    }
  }

  /// 🔴 ĐÈN ĐỎ: Cảnh báo Thiếu hàng / Sai hàng (mã lạ) / Thừa hàng
  Future<void> triggerWarningRed({
    bool withBuzzer = true,
    String reason = 'Cảnh báo: Sai hàng / Thiếu hàng / Thừa hàng',
    bool persistent = false,
  }) async {
    _pulseTimer?.cancel();
    _currentStatus = TowerLightStatus(
      color: TowerLightColor.red,
      isBuzzerOn: withBuzzer,
      reason: reason,
      timestamp: DateTime.now(),
    );
    notifyListeners();

    await _sendHardwareCommand(
      red: true,
      yellow: false,
      green: false,
      buzzer: withBuzzer,
    );

    if (!persistent && config.pulseDurationSeconds > 0) {
      _pulseTimer = Timer(Duration(seconds: config.pulseDurationSeconds), () {
        turnOffAll(reason: 'Sẵn sàng chờ quét tiếp theo');
      });
    }
  }

  /// 🟡 ĐÈN VÀNG: Báo hiệu đang quét đối soát hàng qua cổng RFID
  Future<void> triggerScanning({String reason = 'Đang quét đối soát qua cổng RFID'}) async {
    _pulseTimer?.cancel();
    _currentStatus = TowerLightStatus(
      color: TowerLightColor.yellow,
      isBuzzerOn: false,
      reason: reason,
      timestamp: DateTime.now(),
    );
    notifyListeners();

    await _sendHardwareCommand(
      red: false,
      yellow: true,
      green: false,
      buzzer: false,
    );
  }

  /// 🟡 ĐÈN VÀNG: Cảnh báo Lỗi hệ thống ở một bộ phận nào đó
  Future<void> triggerSystemError({
    String componentName = 'Đầu đọc UHF / Cầu nối TCP',
    String? customReason,
  }) async {
    _pulseTimer?.cancel();
    final reasonText = customReason ?? 'Lỗi hệ thống: Sự cố tại $componentName';

    _currentStatus = TowerLightStatus(
      color: TowerLightColor.yellow,
      isBuzzerOn: false,
      reason: reasonText,
      timestamp: DateTime.now(),
    );
    notifyListeners();

    await _sendHardwareCommand(
      red: false,
      yellow: true,
      green: false,
      buzzer: false,
    );

    if (config.pulseDurationSeconds > 0) {
      _pulseTimer = Timer(Duration(seconds: config.pulseDurationSeconds), () {
        turnOffAll(reason: 'Sẵn sàng (Standby)');
      });
    }
  }

  /// Tắt còi báo động nhưng vẫn duy trì màu đèn cảnh báo hiện tại
  Future<void> silenceBuzzerOnly() async {
    _currentStatus = TowerLightStatus(
      color: _currentStatus.color,
      isBuzzerOn: false,
      reason: '${_currentStatus.reason} (Đã tắt còi)',
      timestamp: DateTime.now(),
    );
    notifyListeners();

    await _sendHardwareCommand(
      red: _currentStatus.color == TowerLightColor.red,
      yellow: _currentStatus.color == TowerLightColor.yellow,
      green: _currentStatus.color == TowerLightColor.green,
      buzzer: false,
    );
  }

  /// Tắt toàn bộ đèn và còi về trạng thái chờ
  Future<void> turnOffAll({String reason = 'Sẵn sàng (Standby)'}) async {
    _pulseTimer?.cancel();
    _currentStatus = TowerLightStatus(
      color: TowerLightColor.off,
      isBuzzerOn: false,
      reason: reason,
      timestamp: DateTime.now(),
    );
    notifyListeners();

    await _sendHardwareCommand(
      red: false,
      yellow: false,
      green: false,
      buzzer: false,
    );
  }

  /// Test thử tín hiệu đèn thủ công
  Future<void> manualTest({
    required TowerLightColor color,
    bool buzzer = false,
    String? testReason,
  }) async {
    _pulseTimer?.cancel();
    final label = switch (color) {
      TowerLightColor.red => 'Thử nghiệm: ĐÈN ĐỎ (Thiếu/Sai/Thừa hàng)',
      TowerLightColor.yellow => 'Thử nghiệm: ĐÈN VÀNG (Lỗi hệ thống)',
      TowerLightColor.green => 'Thử nghiệm: ĐÈN XANH (Đủ hàng thông qua)',
      TowerLightColor.off => 'Tắt tháp đèn',
    };

    _currentStatus = TowerLightStatus(
      color: color,
      isBuzzerOn: buzzer,
      reason: testReason ?? label,
      timestamp: DateTime.now(),
    );
    notifyListeners();

    await _sendHardwareCommand(
      red: color == TowerLightColor.red,
      yellow: color == TowerLightColor.yellow,
      green: color == TowerLightColor.green,
      buzzer: buzzer,
    );

    if (color != TowerLightColor.off && config.pulseDurationSeconds > 0) {
      _pulseTimer = Timer(Duration(seconds: config.pulseDurationSeconds), () {
        turnOffAll();
      });
    }
  }

  // ==================== ĐIỀU KHIỂN PHẦN CỨNG QUA GPO ====================

  Future<void> _sendHardwareCommand({
    required bool red,
    required bool yellow,
    required bool green,
    required bool buzzer,
  }) async {
    if (!_hardwareControlEnabled) return;

    try {
      final pinStates = <int, bool>{1: false, 2: false, 3: false, 4: false};
      if (red) pinStates[config.redPin] = true;
      if (yellow) pinStates[config.yellowPin] = true;
      if (green) pinStates[config.greenPin] = true;
      if (buzzer) pinStates[config.buzzerPin] = true;

      // Điều khiển đồng thời tất cả các chân GPO trong 1 lệnh duy nhất (tránh ghi đè/xung đột chân)
      await _uhfTcp.setAllGpo(pinStates);
    } catch (e) {
      debugPrint('TowerLightService hardware command error: $e');
    }
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    super.dispose();
  }
}
