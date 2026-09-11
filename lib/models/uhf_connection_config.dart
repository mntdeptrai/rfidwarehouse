import 'dart:convert';

/// Cấu hình kết nối phần cứng đầu đọc UHF RFID cố định / để bàn
class UhfConnectionConfig {
  /// Loại kết nối: 'TCP Client', 'RS232', 'RS485', 'USB', 'TCP Server'
  final String connectionType;

  /// Cấu hình TCP Client (Mạng LAN Ethernet / Switch / Wifi)
  final String tcpIp;
  final int tcpPort;

  /// Cấu hình Cổng COM Nối tiếp (RS232 / USB-to-Serial)
  final String comPort;
  final int baudRate;

  /// Cấu hình RS485 Công nghiệp
  final int rs485Address;

  /// Tự động kết nối khi khởi động phần mềm
  final bool autoConnectOnStartup;

  /// Tự động kết nối lại khi mất mạng / rớt cáp
  final bool autoReconnect;

  /// Tự động kết nối ngay khi bấm Quét tại cổng Nhập/Xuất
  final bool autoConnectOnScan;

  /// Danh sách Anten hoạt động (1..4)
  final List<int> activeAntennas;

  /// Công suất phát sóng RF (dBm, từ 10 đến 33 dBm)
  final int rfPower;

  const UhfConnectionConfig({
    this.connectionType = 'TCP Client',
    this.tcpIp = '192.168.1.116',
    this.tcpPort = 9090,
    this.comPort = 'COM3',
    this.baudRate = 115200,
    this.rs485Address = 1,
    this.autoConnectOnStartup = true,
    this.autoReconnect = true,
    this.autoConnectOnScan = true,
    this.activeAntennas = const [1, 2],
    this.rfPower = 30,
  });

  /// Mô tả ngắn gọn cổng đang cấu hình
  String get connectionSummary {
    switch (connectionType) {
      case 'TCP Client':
        return 'LAN $tcpIp:$tcpPort';
      case 'RS232':
        return '$comPort @ $baudRate';
      case 'RS485':
        return 'RS485 #$rs485Address ($comPort)';
      case 'USB':
        return 'USB HID';
      case 'TCP Server':
        return 'TCP Server :$tcpPort';
      default:
        return '$connectionType ($comPort)';
    }
  }

  UhfConnectionConfig copyWith({
    String? connectionType,
    String? tcpIp,
    int? tcpPort,
    String? comPort,
    int? baudRate,
    int? rs485Address,
    bool? autoConnectOnStartup,
    bool? autoReconnect,
    bool? autoConnectOnScan,
    List<int>? activeAntennas,
    int? rfPower,
  }) {
    return UhfConnectionConfig(
      connectionType: connectionType ?? this.connectionType,
      tcpIp: tcpIp ?? this.tcpIp,
      tcpPort: tcpPort ?? this.tcpPort,
      comPort: comPort ?? this.comPort,
      baudRate: baudRate ?? this.baudRate,
      rs485Address: rs485Address ?? this.rs485Address,
      autoConnectOnStartup: autoConnectOnStartup ?? this.autoConnectOnStartup,
      autoReconnect: autoReconnect ?? this.autoReconnect,
      autoConnectOnScan: autoConnectOnScan ?? this.autoConnectOnScan,
      activeAntennas: activeAntennas ?? List<int>.from(this.activeAntennas),
      rfPower: rfPower ?? this.rfPower,
    );
  }

  Map<String, dynamic> toJson() => {
    'connectionType': connectionType,
    'tcpIp': tcpIp,
    'tcpPort': tcpPort,
    'comPort': comPort,
    'baudRate': baudRate,
    'rs485Address': rs485Address,
    'autoConnectOnStartup': autoConnectOnStartup,
    'autoReconnect': autoReconnect,
    'autoConnectOnScan': autoConnectOnScan,
    'activeAntennas': activeAntennas,
    'rfPower': rfPower,
  };

  factory UhfConnectionConfig.fromJson(Map<String, dynamic> json) {
    List<int> ants = [1, 2];
    if (json['activeAntennas'] is List) {
      ants = (json['activeAntennas'] as List)
          .map((e) => int.tryParse(e.toString()) ?? 1)
          .toList();
      if (ants.isEmpty) ants = [1, 2];
    }

    return UhfConnectionConfig(
      connectionType: (json['connectionType'] ?? 'TCP Client').toString(),
      tcpIp: (json['tcpIp'] ?? '192.168.1.116').toString(),
      tcpPort: int.tryParse(json['tcpPort']?.toString() ?? '') ?? 9090,
      comPort: (json['comPort'] ?? 'COM3').toString(),
      baudRate: int.tryParse(json['baudRate']?.toString() ?? '') ?? 115200,
      rs485Address: int.tryParse(json['rs485Address']?.toString() ?? '') ?? 1,
      autoConnectOnStartup: json['autoConnectOnStartup'] != false,
      autoReconnect: json['autoReconnect'] != false,
      autoConnectOnScan: json['autoConnectOnScan'] != false,
      activeAntennas: ants,
      rfPower: int.tryParse(json['rfPower']?.toString() ?? '') ?? 30,
    );
  }

  String serialize() => jsonEncode(toJson());

  factory UhfConnectionConfig.deserialize(String jsonStr) {
    try {
      final decoded = jsonDecode(jsonStr);
      if (decoded is Map<String, dynamic>) {
        return UhfConnectionConfig.fromJson(decoded);
      }
    } catch (_) {}
    return const UhfConnectionConfig();
  }
}
