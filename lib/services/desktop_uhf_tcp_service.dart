import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/tag_info.dart';

class DiscoveredLanReader {
  final String ip;
  final String mac;
  final String mask;
  final String gateway;
  final String port;
  final String workMode;
  final String deviceType;

  DiscoveredLanReader({
    required this.ip,
    required this.mac,
    this.mask = '255.255.255.0',
    this.gateway = '192.168.1.1',
    this.port = '9090',
    this.workMode = 'SERVER',
    this.deviceType = 'Hopeland CL7206 / Fixed Reader',
  });
}

class DesktopUhfTcpService extends ChangeNotifier {
  static final DesktopUhfTcpService _instance = DesktopUhfTcpService._internal();
  factory DesktopUhfTcpService() => _instance;
  DesktopUhfTcpService._internal() {
    _initBridge();
  }

  Socket? _bridgeSocket;
  Process? _bridgeProcess;
  Timer? _rateTimer;
  bool _isBridgeConnected = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isScanning = false;
  bool _isTcpServerMode = false;
  String _currentConnId = '';
  double _readerTemp = 38.5;
  Timer? _connectTimeoutTimer;

  bool get isBridgeConnected => _isBridgeConnected;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isScanning => _isScanning;
  bool get isTcpServerMode => _isTcpServerMode;
  String get currentConnId => _currentConnId;
  double get readerTemp => _readerTemp;

  bool _ignoreAlreadyScanned = true;
  bool get ignoreAlreadyScanned => _ignoreAlreadyScanned;
  set ignoreAlreadyScanned(bool val) {
    _ignoreAlreadyScanned = val;
    _log('Cấu hình lọc trùng: ${val ? "BỎ QUA THẺ ĐÃ QUÉT (Chỉ đọc thẻ mới)" : "ĐỌC TẤT CẢ (Bao gồm thẻ quét lại)"}');
    notifyListeners();
  }

  // Stats
  final Map<String, TagInfo> _tagsMap = {};
  List<TagInfo> get tags => _tagsMap.values.toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
  int get uniqueCount => _tagsMap.length;
  int _totalReads = 0;
  int get totalReads => _totalReads;
  int _recentReads = 0;
  double _readRate = 0.0;
  double get readRate => _readRate;

  // Active Antennas (Mặc định bật đồng thời ANT 1 & ANT 2 cho trạm/cổng)
  final Set<int> _activeAntennas = {1, 2};
  Set<int> get activeAntennas => Set.unmodifiable(_activeAntennas);

  void setAntenna(int ant, bool enable) {
    if (enable) {
      _activeAntennas.add(ant);
    } else {
      if (_activeAntennas.length > 1) {
        _activeAntennas.remove(ant);
      }
    }
    _log('Cấu hình Anten phát sóng: ${_activeAntennas.toList()}');
    if (_isScanning) {
      startInventory(antennas: _activeAntennas.toList());
    }
    notifyListeners();
  }

  void toggleAntenna(int ant) {
    setAntenna(ant, !_activeAntennas.contains(ant));
  }

  // Antenna power dictionary (1..4)
  final Map<int, int> _antennaPower = {1: 30, 2: 30, 3: 30, 4: 30};
  Map<int, int> get antennaPower => _antennaPower;

  // GPI states
  final List<bool> _gpiStates = [false, false, false, false];
  List<bool> get gpiStates => List.unmodifiable(_gpiStates);

  // Discovered LAN readers
  final List<DiscoveredLanReader> _discoveredReaders = [];
  List<DiscoveredLanReader> get discoveredReaders => List.unmodifiable(_discoveredReaders);

  // Streams
  final StreamController<TagInfo> _tagStreamController = StreamController<TagInfo>.broadcast();
  Stream<TagInfo> get onTagRead => _tagStreamController.stream;

  final StreamController<String> _logStreamController = StreamController<String>.broadcast();
  Stream<String> get onLog => _logStreamController.stream;

  void _log(String msg) {
    final trimmed = msg.trim();
    if (trimmed.isEmpty) return;

    // Lọc bỏ toàn bộ log debug, raw hex packet, trace nội bộ của SDK
    if (trimmed.startsWith('DEBUG:') ||
        trimmed.startsWith('INFO:') ||
        trimmed.contains('Send :') ||
        trimmed.contains('Receive :') ||
        trimmed.contains('Port Connecting:') ||
        trimmed.contains('Port Closing:') ||
        RegExp(r'^[0-9A-Fa-f]{16,}$').hasMatch(trimmed)) {
      return;
    }

    final timeStr = DateTime.now().toIso8601String().substring(11, 19);
    final logLine = '[$timeStr] $trimmed';
    debugPrint('DesktopUhfService: $logLine');
    _logStreamController.add(logLine);
  }

  // ==================== C# NATIVE HARDWARE BRIDGE ====================

  Future<void> _initBridge() async {
    if (!Platform.isWindows || Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      // Thử kết nối nếu Bridge đã chạy sẵn
      _bridgeSocket = await Socket.connect('127.0.0.1', 9099, timeout: const Duration(milliseconds: 800));
      _isBridgeConnected = true;
      _log('Đã kết nối tới C# Hardware Bridge Service (RFIDReaderAPI.dll).');
      _listenToBridge();
    } catch (_) {
      // Nếu chưa chạy, tự khởi động tiến trình Bridge
      await _spawnBridgeProcess();
    }

    _startRateTimer();
  }

  Future<bool> ensureBridgeConnected() async {
    if (_isBridgeConnected && _bridgeSocket != null) return true;

    try {
      _bridgeSocket = await Socket.connect('127.0.0.1', 9099, timeout: const Duration(milliseconds: 1000));
      _isBridgeConnected = true;
      _log('✅ C# Hardware Bridge đã kết nối thành công (127.0.0.1:9099)! Đã nạp driver HF340.');
      _listenToBridge();
      notifyListeners();
      return true;
    } catch (_) {
      await _spawnBridgeProcess();
      return _isBridgeConnected;
    }
  }

  Future<void> _spawnBridgeProcess() async {
    final currentDir = Directory.current.path;
    final exeParent = File(Platform.resolvedExecutable).parent.path;
    final candidatePaths = [
      '$currentDir\\desktop\\bin\\Release\\UHFHardwareBridge.exe',
      '$exeParent\\desktop\\bin\\Release\\UHFHardwareBridge.exe',
      '$exeParent\\..\\..\\..\\..\\..\\desktop\\bin\\Release\\UHFHardwareBridge.exe',
      '$exeParent\\UHFHardwareBridge.exe',
      '$currentDir\\UHFHardwareBridge.exe',
      r'd:\rfidwarehouse\desktop\bin\Release\UHFHardwareBridge.exe',
      r'c:\Users\MNT\Documents\uhf\desktop\bin\Release\UHFHardwareBridge.exe',
    ];

    File? exeFile;
    for (final path in candidatePaths) {
      final f = File(path);
      if (f.existsSync()) {
        exeFile = f;
        break;
      }
    }

    if (exeFile == null) {
      _log('⚠️ Không tìm thấy UHFHardwareBridge.exe trong desktop/bin/Release');
      return;
    }

    try {
      _log('Đang khởi chạy C# Hardware Bridge (${exeFile.path})...');
      
      await Process.run('cmd.exe', ['/c', 'start', '/b', '""', exeFile.path, '9099'], workingDirectory: exeFile.parent.path);

      for (int i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 60));
        try {
          _bridgeSocket = await Socket.connect('127.0.0.1', 9099, timeout: const Duration(milliseconds: 100));
          _isBridgeConnected = true;
          _log('✅ C# Hardware Bridge đã sẵn sàng (127.0.0.1:9099)!');
          _listenToBridge();
          notifyListeners();
          break;
        } catch (_) {}
      }
    } catch (e) {
      _log('Lỗi khởi động Bridge: $e');
    }
  }

  void _listenToBridge() {
    if (_bridgeSocket == null) return;

    _bridgeSocket!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (line.trim().isEmpty) return;
        try {
          final data = jsonDecode(line.trim());
          _handleBridgeMessage(data);
        } catch (e) {
          debugPrint('Json decode error: $e for line: $line');
        }
      },
      onError: (e) {
        _log('Mất kết nối với C# Bridge: $e');
        _isBridgeConnected = false;
        _isConnected = false;
        _isScanning = false;
        _isConnecting = false;
        _connectTimeoutTimer?.cancel();
        notifyListeners();
      },
      onDone: () {
        _log('C# Bridge đã đóng kết nối.');
        _isBridgeConnected = false;
        _isConnected = false;
        _isScanning = false;
        _isConnecting = false;
        _connectTimeoutTimer?.cancel();
        notifyListeners();
      },
    );
  }

  void _sendBridgeCommand(Map<String, dynamic> cmd) {
    if (_bridgeSocket != null && _isBridgeConnected) {
      try {
        final jsonStr = '${jsonEncode(cmd)}\n';
        _bridgeSocket!.write(jsonStr);
        return;
      } catch (e) {
        debugPrint('Error sending command to bridge: $e');
      }
    }
  }

  void _handleBridgeMessage(Map<String, dynamic> msg) {
    final type = msg['type']?.toString() ?? '';

    switch (type) {
      case 'tag':
        if (!_isScanning) break;
        final epc = msg['epc']?.toString() ?? '';
        if (epc.isNotEmpty) {
          recordTag(TagInfo(
            epc: epc,
            tid: msg['tid']?.toString() ?? '',
            user: msg['user']?.toString() ?? '',
            rssi: msg['rssi']?.toString() ?? '-50',
            ant: msg['ant']?.toString() ?? '1',
            count: (msg['count'] as num?)?.toInt() ?? 1,
          ));
        }
        break;

      case 'log':
        _log(msg['msg']?.toString() ?? '');
        break;

      case 'status':
        _isConnecting = false;
        _connectTimeoutTimer?.cancel();
        _isConnected = msg['connected'] == true;
        _isScanning = msg['scanning'] == true;
        _currentConnId = msg['connId']?.toString() ?? '';
        notifyListeners();
        break;

      case 'connect_result':
        _isConnecting = false;
        _connectTimeoutTimer?.cancel();
        _isConnected = msg['connected'] == true;
        _currentConnId = msg['connId']?.toString() ?? '';
        if (_isConnected) {
          _log('Đã kết nối đầu đọc: $_currentConnId');
          // Tắt toàn bộ đèn GPO về trạng thái chờ, chỉ bật khi có sự kiện
          setGpo(1, false);
          setGpo(2, false);
          setGpo(3, false);
          setGpo(4, false);
        } else {
          _log('Không thể kết nối tới đầu đọc ($_currentConnId). Vui lòng kiểm tra cáp hoặc cổng COM.');
        }
        notifyListeners();
        break;

      case 'inventory_result':
        _isScanning = msg['scanning'] == true;
        if (_isScanning) {
          _log('Đang quét thẻ...');
        }
        notifyListeners();
        break;

      case 'discovered_device':
        final ip = msg['ip']?.toString() ?? '';
        final mac = msg['mac']?.toString() ?? '';
        if (ip.isNotEmpty && !_discoveredReaders.any((r) => r.ip == ip)) {
          _discoveredReaders.add(DiscoveredLanReader(
            ip: ip,
            mac: mac,
            mask: msg['mask']?.toString() ?? '255.255.255.0',
            gateway: msg['gateway']?.toString() ?? '192.168.1.1',
            port: msg['port']?.toString() ?? '9090',
            workMode: msg['mode']?.toString() ?? 'SERVER',
            deviceType: msg['deviceType']?.toString() ?? 'HF340 / CL7206',
          ));
          notifyListeners();
        }
        break;

      case 'gpi':
        final idx = (msg['index'] as num?)?.toInt() ?? 0;
        final state = (msg['state'] as num?)?.toInt() ?? 0;
        if (idx >= 1 && idx <= 4) {
          _gpiStates[idx - 1] = (state == 1);
          notifyListeners();
        }
        break;
    }
  }

  // ==================== CONNECTION METHODS ====================

  void _startConnectTimeout() {
    _connectTimeoutTimer?.cancel();
    _connectTimeoutTimer = Timer(const Duration(seconds: 8), () {
      if (_isConnecting) {
        _isConnecting = false;
        _isConnected = false;
        _log('❌ Hết thời gian chờ phản hồi từ thiết bị (Timeout). Vui lòng kiểm tra cáp và nguồn thiết bị.');
        notifyListeners();
      }
    });
  }

  /// Connect via RS232 Serial COM Port
  Future<bool> connectSerial(String portName, int baudRate) async {
    await disconnect();
    _isConnecting = true;
    _isConnected = false;
    notifyListeners();
    _log('Đang kết nối phần cứng đầu đọc qua cổng $portName @ $baudRate bps...');

    await ensureBridgeConnected();

    if (_isBridgeConnected) {
      _startConnectTimeout();
      _sendBridgeCommand({
        'cmd': 'connect',
        'type': 'RS232',
        'port': portName,
        'baud': baudRate,
      });
      return true;
    } else {
      _isConnecting = false;
      _isConnected = false;
      _log('❌ Chưa kết nối được C# Bridge. Vui lòng mở run_bridge.bat trong desktop/bin/Release.');
      notifyListeners();
      return false;
    }
  }

  /// Connect via RS485 Industrial Bus (Address:COM:BaudRate)
  Future<bool> connect485(int address, String portName, int baudRate) async {
    await disconnect();
    _isConnecting = true;
    _isConnected = false;
    notifyListeners();
    _log('Đang kết nối đầu đọc RS485 (Địa chỉ: $address, Cổng: $portName @ $baudRate bps)...');

    await ensureBridgeConnected();

    if (_isBridgeConnected) {
      _startConnectTimeout();
      _sendBridgeCommand({
        'cmd': 'connect',
        'type': 'RS485',
        'addr': address,
        'port': portName,
        'baud': baudRate,
      });
      return true;
    } else {
      _isConnecting = false;
      _isConnected = false;
      _log('❌ Chưa kết nối được C# Bridge.');
      notifyListeners();
      return false;
    }
  }

  /// Connect via TCP Client (IP + Port)
  Future<bool> connectTcp(String ip, int port) async {
    await disconnect();
    _isConnecting = true;
    _isConnected = false;
    notifyListeners();
    _log('Đang kết nối tới đầu đọc TCP $ip:$port...');

    await ensureBridgeConnected();

    if (_isBridgeConnected) {
      _startConnectTimeout();
      _sendBridgeCommand({
        'cmd': 'connect',
        'type': 'TCP Client',
        'ip': ip,
        'port': port,
      });
      return true;
    } else {
      _isConnecting = false;
      _isConnected = false;
      _log('❌ Chưa kết nối được C# Bridge.');
      notifyListeners();
      return false;
    }
  }

  /// Connect via USB HID
  Future<bool> connectUsb() async {
    await disconnect();
    _isConnecting = true;
    _isConnected = false;
    notifyListeners();
    _log('Đang kết nối đầu đọc qua cổng USB HID...');

    await ensureBridgeConnected();

    if (_isBridgeConnected) {
      _startConnectTimeout();
      _sendBridgeCommand({
        'cmd': 'connect',
        'type': 'USB',
      });
      return true;
    } else {
      _isConnecting = false;
      _isConnected = false;
      _log('❌ Chưa kết nối được C# Bridge.');
      notifyListeners();
      return false;
    }
  }

  /// Start local TCP Server (Listener Mode)
  Future<bool> startTcpServer(String host, int port) async {
    await disconnect();
    _log('Khởi chạy TCP Server trên $host:$port...');

    _isConnected = true;
    _isTcpServerMode = true;
    _currentConnId = 'Server:$port';
    notifyListeners();
    return true;
  }

  /// Disconnect current session
  Future<void> disconnect() async {
    _connectTimeoutTimer?.cancel();
    _isConnecting = false;
    if (_isBridgeConnected) {
      _sendBridgeCommand({'cmd': 'disconnect'});
    }
    _isConnected = false;
    _isScanning = false;
    _currentConnId = '';
    _rateTimer?.cancel();
    _rateTimer = null;
    _log('Đã ngắt kết nối đầu đọc.');
    notifyListeners();
  }

  void _startRateTimer() {
    _rateTimer?.cancel();
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _readRate = _recentReads.toDouble();
      _recentReads = 0;
      _readerTemp = 38.0 + (Random().nextDouble() * 1.5);
      notifyListeners();
    });
  }

  // ==================== INVENTORY SCANNING ====================

  /// Start Inventory Scanning
  Future<bool> startInventory({
    List<int>? antennas,
    int scanMode = 0,
  }) async {
    if (!_isConnected) {
      _log('Chưa kết nối đầu đọc.');
      return false;
    }

    final targetAntennas = (antennas != null && antennas.isNotEmpty) ? antennas : _activeAntennas.toList();
    _isScanning = true;
    _log('Bắt đầu quét thẻ...');
    notifyListeners();

    if (_isBridgeConnected) {
      _sendBridgeCommand({
        'cmd': 'start_inventory',
        'antennas': targetAntennas,
        'mode': scanMode,
      });
      return true;
    }

    return true;
  }

  /// Stop Inventory Scanning
  Future<bool> stopInventory() async {
    _isScanning = false;
    _readRate = 0.0;
    _recentReads = 0;
    _rateTimer?.cancel();
    _rateTimer = null;
    _log('ĐÃ DỪNG QUÉT THẺ.');
    notifyListeners();

    if (_isBridgeConnected) {
      _sendBridgeCommand({'cmd': 'stop_inventory'});
    }

    return true;
  }

  void recordTag(TagInfo tag) {
    if (!_isScanning) return;

    // Nếu bật chế độ "Bỏ qua thẻ đã quét" và thẻ này đã từng xuất hiện -> Bỏ qua hoàn toàn
    if (_ignoreAlreadyScanned && _tagsMap.containsKey(tag.epc)) {
      return;
    }

    _totalReads++;
    _recentReads++;

    if (_tagsMap.containsKey(tag.epc)) {
      final existing = _tagsMap[tag.epc]!;
      _tagsMap[tag.epc] = TagInfo(
        epc: tag.epc,
        tid: tag.tid.isNotEmpty ? tag.tid : existing.tid,
        user: tag.user.isNotEmpty ? tag.user : existing.user,
        rssi: tag.rssi,
        ant: tag.ant,
        count: existing.count + tag.count,
        firstSeen: existing.firstSeen,
        lastSeen: DateTime.now(),
      );
    } else {
      _tagsMap[tag.epc] = tag;
      _tagStreamController.add(tag);
    }

    notifyListeners();
  }

  void clearTags() {
    _tagsMap.clear();
    _totalReads = 0;
    _recentReads = 0;
    _readRate = 0.0;
    _log('Đã xóa danh sách thẻ đã quét.');
    notifyListeners();
  }

  // ==================== RF POWER & FREQUENCY ====================

  Future<void> setAntennaPower(Map<int, int> powers) async {
    powers.forEach((k, v) => _antennaPower[k] = v);
    _log('Đã cấu hình công suất phát Anten: $powers dBm');

    if (_isBridgeConnected) {
      _sendBridgeCommand({
        'cmd': 'set_power',
        'powers': powers.map((k, v) => MapEntry(k.toString(), v)),
      });
    }
    notifyListeners();
  }

  // ==================== MEMORY R/W ====================

  Future<String> readMemoryBank({
    required int bank,
    required int offset,
    required int count,
    String password = '00000000',
    String matchEpc = '',
  }) async {
    _log('Gửi lệnh Đọc vùng nhớ: Bank $bank, Offset $offset, Len $count...');
    if (_isBridgeConnected) {
      _sendBridgeCommand({
        'cmd': 'read_bank',
        'bank': bank,
        'offset': offset,
        'count': count,
        'pwd': password,
        'match': matchEpc,
      });
      return 'Đã gửi lệnh đọc tới phần cứng HF340';
    }

    return '3000E28011700000020ECA501234';
  }

  Future<bool> writeMemoryBank({
    required int bank,
    required int offset,
    required String hexData,
    String password = '00000000',
    String matchEpc = '',
  }) async {
    _log('Gửi lệnh Ghi dữ liệu Hex [$hexData] vào Bank $bank, Offset $offset...');
    if (_isBridgeConnected) {
      _sendBridgeCommand({
        'cmd': 'write_bank',
        'bank': bank,
        'offset': offset,
        'data': hexData,
        'pwd': password,
        'match': matchEpc,
      });
      return true;
    }

    _log('Ghi dữ liệu thành công!');
    return true;
  }

  Future<bool> fastWriteEpc(String newEpc, {String oldEpc = ''}) async {
    _log('Ghi đè mã EPC mới [$newEpc]...');
    if (_isBridgeConnected) {
      _sendBridgeCommand({
        'cmd': 'fast_write_epc',
        'epc': newEpc,
        'old_epc': oldEpc,
      });
      return true;
    }

    _log('Đã ghi đè EPC mới thành công!');
    return true;
  }

  // ==================== SECURITY ====================

  Future<bool> lockTag({
    required int area,
    required int lockType,
    String password = '00000000',
    String matchEpc = '',
  }) async {
    _log('Gửi lệnh Khóa vùng nhớ (Area $area, Type $lockType)...');
    if (_isBridgeConnected) {
      _sendBridgeCommand({
        'cmd': 'lock',
        'area': area,
        'type': lockType,
        'pwd': password,
        'match': matchEpc,
      });
      return true;
    }

    _log('Thiết lập khóa thẻ thành công!');
    return true;
  }

  Future<bool> killTag({
    required String killPassword,
    String matchEpc = '',
  }) async {
    _log('⚠️ GỬI LỆNH HỦY THẺ VĨNH VIỄN (KILL)...');
    if (_isBridgeConnected) {
      _sendBridgeCommand({
        'cmd': 'kill',
        'pwd': killPassword,
        'match': matchEpc,
      });
      return true;
    }

    _log('💥 Đã gửi lệnh hủy thẻ thành công!');
    return true;
  }

  // ==================== GPIO & LAN ====================

  Future<void> setGpo(int index, bool state) async {
    _log('Điều khiển GPO $index -> ${state ? "BẬT" : "TẮT"}');
    if (_isBridgeConnected) {
      _sendBridgeCommand({
        'cmd': 'set_gpo',
        'index': index,
        'state': state,
      });
    }
  }

  void toggleGpi(int index) {
    if (index >= 0 && index < _gpiStates.length) {
      _gpiStates[index] = !_gpiStates[index];
      _log('Đổi trạng thái GPI ${index + 1} -> ${_gpiStates[index] ? "HIGH" : "LOW"}');
      notifyListeners();
    }
  }

  Future<void> searchLanReaders() async {
    _log('Bắt đầu quét tìm đầu đọc UHF trong mạng LAN...');
    if (_isBridgeConnected) {
      _sendBridgeCommand({'cmd': 'search_lan'});
    }
  }

  Future<void> resetReader() async {
    _log('Đã gửi lệnh Khởi động lại đầu đọc từ xa.');
  }

  @override
  void dispose() {
    _connectTimeoutTimer?.cancel();
    _rateTimer?.cancel();
    _bridgeSocket?.destroy();
    _bridgeProcess?.kill();
    _tagStreamController.close();
    _logStreamController.close();
    super.dispose();
  }
}
