class TagInfo {
  final String epc;
  final String tid;
  final String user;
  final String rssi;
  final String ant;
  int count;
  final String pc;
  final DateTime timestamp;
  final DateTime firstSeen;
  DateTime lastSeen;

  TagInfo({
    required this.epc,
    this.tid = '',
    this.user = '',
    this.rssi = '0',
    this.ant = '1',
    this.count = 1,
    this.pc = '',
    DateTime? timestamp,
    DateTime? firstSeen,
    DateTime? lastSeen,
  })  : timestamp = timestamp ?? DateTime.now(),
        firstSeen = firstSeen ?? DateTime.now(),
        lastSeen = lastSeen ?? DateTime.now();

  factory TagInfo.fromMap(Map<dynamic, dynamic> map) {
    return TagInfo(
      epc: map['epc']?.toString() ?? '',
      tid: map['tid']?.toString() ?? '',
      user: map['user']?.toString() ?? '',
      rssi: map['rssi']?.toString() ?? '0',
      ant: map['ant']?.toString() ?? '1',
      count: (map['count'] as num?)?.toInt() ?? 1,
      pc: map['pc']?.toString() ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.fromMillisecondsSinceEpoch((map['timestamp'] as num).toInt())
          : DateTime.now(),
    );
  }

  double get rssiValue {
    final parsed = double.tryParse(rssi);
    if (parsed == null) return -70.0;
    // If RSSI is positive (e.g. dBm represented as positive or raw int)
    if (parsed > 0 && parsed <= 100) {
      return -100.0 + parsed;
    }
    return parsed;
  }

  /// Normalized signal strength percentage (0% to 100%)
  double get signalPercent {
    final dbm = rssiValue;
    if (dbm >= -30) return 1.0;
    if (dbm <= -90) return 0.05;
    return ((dbm - (-90)) / 60.0).clamp(0.05, 1.0);
  }

  Map<String, dynamic> toMap() {
    return {
      'epc': epc,
      'tid': tid,
      'user': user,
      'rssi': rssi,
      'ant': ant,
      'count': count,
      'pc': pc,
      'firstSeen': firstSeen.toIso8601String(),
      'lastSeen': lastSeen.toIso8601String(),
    };
  }
}
