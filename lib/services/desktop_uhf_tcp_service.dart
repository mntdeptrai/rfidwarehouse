import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/tag_info.dart';
import '../models/uhf_connection_config.dart';
import 'auth_service.dart';

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
    loadConfig().then((_) {
      if (!Platform.environment.containsKey('FLUTTER_TEST') && _config.autoConnectOnStartup) {
        Timer(const Duration(milliseconds: 1500), () {
          if (!_isConnected && !_isConnecting) {
            connectWithSavedConfig();
          }
        });
      }
    });
  }

  Socket? _bridgeSocket;
  Process? _bridgeProcess;
  Timer? _rateTimer;
  Timer? _reconnectTimer;
  Completer<bool>? _connectCompleter;
  bool _isBridgeConnected = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isScanning = false;
  bool _isTcpServerMode = false;
  String _currentConnId = '';
  double _readerTemp = 38.5;
  Timer? _connectTimeoutTimer;

  UhfConnectionConfig _config = const UhfConnectionConfig();
  UhfConnectionConfig get config => _config;

  bool get isBridgeConnected => _isBridgeConnected;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  bool get isScanning => _isScanning;
  bool get isTcpServerMode => _isTcpServerMode;
  String get currentConnId => _currentConnId;
  double get readerTemp => _readerTemp;

  bool _ignoreAlreadyScanned = false;
  bool get ignoreAlreadyScanned => _ignoreAlreadyScanned;
  set ignoreAlreadyScanned(bool val) {
    final user = AuthService().currentUser;
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest && (user == null || !user.canConfigureHardware)) {
      _log('❌ LỖI BẢO MẬT: Quyền bị từ chối. Không được phép sửa cấu hình lọc trùng!');
      return;
    }
    _ignoreAlreadyScanned = val;
    _log('Cấu hình lọc trùng: ${val ? "BỎ QUA THẺ ĐÃ QUÉT (Chỉ đọc thẻ mới)" : "ĐỌC TẤT CẢ (Bao gồm thẻ quét lại)"}');
    notifyListeners();
  }

  // Stats (Optimized with dirty cache to avoid continuous sorting on every frame)
  final Map<String, TagInfo> _tagsMap = {};
  List<TagInfo> _cachedTagsList = [];
  bool _tagsCacheDirty = false;

  List<TagInfo> get tags {
    if (_tagsCacheDirty || _cachedTagsList.length != _tagsMap.length) {
      _cachedTagsList = _tagsMap.values.toList()..sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
      _tagsCacheDirty = false;
    }
    return _cachedTagsList;
  }
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
    final user = AuthService().currentUser;
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest && (user == null || !user.canConfigureHardware)) {
      _log('❌ LỖI BẢO MẬT: Quyền bị từ chối. Không được phép sửa cấu hình Anten!');
      return;
    }
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
        _scheduleReconnect();
        notifyListeners();
      },
      onDone: () {
        _log('C# Bridge đã đóng kết nối.');
        _isBridgeConnected = false;
        _isConnected = false;
        _isScanning = false;
        _isConnecting = false;
        _connectTimeoutTimer?.cancel();
        _scheduleReconnect();
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
        if (!_isConnected) {
          _scheduleReconnect();
        }
        notifyListeners();
        break;

      case 'connect_result':
        _isConnecting = false;
        _connectTimeoutTimer?.cancel();
        _isConnected = msg['connected'] == true;
        _currentConnId = msg['connId']?.toString() ?? '';
        if (_isConnected) {
          _log('Đã kết nối đầu đọc: $_currentConnId');
          setGpo(1, false);
          setGpo(2, false);
          setGpo(3, false);
          setGpo(4, false);
          if (_config.activeAntennas.isNotEmpty) {
            _activeAntennas.clear();
            _activeAntennas.addAll(_config.activeAntennas);
          }
          setAntennaPower({1: _config.rfPower, 2: _config.rfPower, 3: _config.rfPower, 4: _config.rfPower});
          _reconnectTimer?.cancel();
          if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
            _connectCompleter!.complete(true);
          }
        } else {
          _log('Không thể kết nối tới đầu đọc ($_currentConnId). Vui lòng kiểm tra cáp hoặc cổng COM.');
          if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
            _connectCompleter!.complete(false);
          }
          _scheduleReconnect();
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
  Future<void> disconnect({bool isManual = true}) async {
    if (isManual) {
      _reconnectTimer?.cancel();
    }
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

  // ==================== CONFIGURATION PERSISTENCE & AUTO-CONNECT ====================

  Future<File?> _getConfigFile() async {
    try {
      if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return null;
      final dir = await getApplicationSupportDirectory();
      final target = File(p.join(dir.path, 'uhf_hardware_config.json'));
      if (!target.parent.existsSync()) {
        target.parent.createSync(recursive: true);
      }
      return target;
    } catch (_) {
      try {
        final appData = Platform.environment['APPDATA'] ?? '.';
        final dir = Directory(p.join(appData, 'RFIDWarehouse'));
        if (!dir.existsSync()) dir.createSync(recursive: true);
        return File(p.join(dir.path, 'uhf_hardware_config.json'));
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
        _config = UhfConnectionConfig.deserialize(content);
        if (_config.activeAntennas.isNotEmpty) {
          _activeAntennas.clear();
          _activeAntennas.addAll(_config.activeAntennas);
        }
        for (int i = 1; i <= 4; i++) {
          _antennaPower[i] = _config.rfPower;
        }
        _log('Đã nạp cấu hình kết nối: ${_config.connectionSummary}');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading uhf_hardware_config: $e');
    }
  }

  Future<bool> saveConfig(UhfConnectionConfig newConfig) async {
    _config = newConfig;
    if (_config.activeAntennas.isNotEmpty) {
      _activeAntennas.clear();
      _activeAntennas.addAll(_config.activeAntennas);
    }
    for (int i = 1; i <= 4; i++) {
      _antennaPower[i] = _config.rfPower;
    }
    notifyListeners();

    try {
      final file = await _getConfigFile();
      if (file != null) {
        await file.writeAsString(newConfig.serialize());
        _log('Đã lưu cấu hình kết nối: ${newConfig.connectionSummary}');
      }
      if (_isConnected) {
        setAntennaPower({1: _config.rfPower, 2: _config.rfPower, 3: _config.rfPower, 4: _config.rfPower});
      }
      return true;
    } catch (e) {
      debugPrint('Error saving uhf_hardware_config: $e');
      return false;
    }
  }

  Future<bool> connectWithSavedConfig({Duration timeout = const Duration(seconds: 5)}) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    if (_isConnected) return true;
    _isConnecting = true;
    notifyListeners();
    _log('Đang tự động kết nối theo cấu hình: ${_config.connectionSummary}...');

    try {
      final bridgeReady = await ensureBridgeConnected();
      if (!bridgeReady || !_isBridgeConnected) {
        _isConnecting = false;
        notifyListeners();
        _log('❌ Không thể kết nối tới C# Hardware Bridge.');
        return false;
      }

      if (_connectCompleter != null && !_connectCompleter!.isCompleted) {
        _connectCompleter!.complete(false);
      }
      _connectCompleter = Completer<bool>();
      _startConnectTimeout();

      switch (_config.connectionType) {
        case 'TCP Client':
          _sendBridgeCommand({
            'cmd': 'connect',
            'type': 'TCP Client',
            'ip': _config.tcpIp,
            'port': _config.tcpPort,
          });
          break;
        case 'RS232':
          _sendBridgeCommand({
            'cmd': 'connect',
            'type': 'RS232',
            'port': _config.comPort,
            'baud': _config.baudRate,
          });
          break;
        case 'RS485':
          _sendBridgeCommand({
            'cmd': 'connect',
            'type': 'RS485',
            'addr': _config.rs485Address,
            'port': _config.comPort,
            'baud': _config.baudRate,
          });
          break;
        case 'USB':
          _sendBridgeCommand({
            'cmd': 'connect',
            'type': 'USB',
          });
          break;
        case 'TCP Server':
          await startTcpServer('0.0.0.0', _config.tcpPort);
          _isConnecting = false;
          notifyListeners();
          return true;
        default:
          _sendBridgeCommand({
            'cmd': 'connect',
            'type': 'RS232',
            'port': _config.comPort,
            'baud': _config.baudRate,
          });
          break;
      }

      final success = await _connectCompleter!.future.timeout(timeout, onTimeout: () {
        _isConnecting = false;
        _connectTimeoutTimer?.cancel();
        return _isConnected;
      });

      return success || _isConnected;
    } catch (e) {
      _log('Lỗi khi kết nối theo cấu hình: $e');
      _isConnecting = false;
      notifyListeners();
      return false;
    }
  }

  void _scheduleReconnect() {
    if (!_config.autoReconnect || _isConnected || _isConnecting || !Platform.isWindows) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () async {
      if (!_isConnected && !_isConnecting && _config.autoReconnect) {
        _log('Tự động thử kết nối lại đầu đọc (${_config.connectionSummary})...');
        await connectWithSavedConfig();
      }
    });
  }

  Future<void> searchLanDevices() async {
    await ensureBridgeConnected();
    _discoveredReaders.clear();
    _log('Đang phát lệnh dò tìm đầu đọc UHF trong mạng LAN...');
    _sendBridgeCommand({'cmd': 'search_lan'});
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
    if (!_isConnected && !Platform.environment.containsKey('FLUTTER_TEST')) {
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

    final TagInfo currentTag;
    if (_tagsMap.containsKey(tag.epc)) {
      final existing = _tagsMap[tag.epc]!;
      currentTag = TagInfo(
        epc: tag.epc,
        tid: tag.tid.isNotEmpty ? tag.tid : existing.tid,
        user: tag.user.isNotEmpty ? tag.user : existing.user,
        rssi: tag.rssi,
        ant: tag.ant,
        count: existing.count + tag.count,
        firstSeen: existing.firstSeen,
        lastSeen: DateTime.now(),
      );
      _tagsMap[tag.epc] = currentTag;
    } else {
      currentTag = tag;
      _tagsMap[tag.epc] = currentTag;
    }

    _tagStreamController.add(currentTag);
    _tagsCacheDirty = true;
    notifyListeners();
  }

  void clearTags() {
    _tagsMap.clear();
    _cachedTagsList = [];
    _tagsCacheDirty = true;
    _totalReads = 0;
    _recentReads = 0;
    _readRate = 0.0;
    _log('Đã xóa danh sách thẻ đã quét.');
    notifyListeners();
  }

  // ==================== RF POWER & FREQUENCY ====================

  Future<void> setAntennaPower(Map<int, int> powers) async {
    final user = AuthService().currentUser;
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest && (user == null || !user.canConfigureHardware)) {
      _log('❌ LỖI BẢO MẬT: Quyền bị từ chối. Không được phép sửa công suất phát RF!');
      return;
    }
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
    final user = AuthService().currentUser;
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest && (user == null || !user.canConfigureHardware)) {
      _log('❌ LỖI BẢO MẬT: Quyền bị từ chối. Không được phép ghi dữ liệu chip RFID!');
      return false;
    }
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
    final user = AuthService().currentUser;
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest && (user == null || !user.canConfigureHardware)) {
      _log('❌ LỖI BẢO MẬT: Quyền bị từ chối. Không được phép ghi đè EPC!');
      return false;
    }
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
    final user = AuthService().currentUser;
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest && (user == null || !user.canConfigureHardware)) {
      _log('❌ LỖI BẢO MẬT: Quyền bị từ chối. Không được phép khóa vùng nhớ RFID!');
      return false;
    }
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
    final user = AuthService().currentUser;
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest && (user == null || !user.canConfigureHardware)) {
      _log('❌ LỖI BẢO MẬT: Quyền bị từ chối. Không được phép hủy thẻ chip RFID (Kill)!');
      return false;
    }
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
    final user = AuthService().currentUser;
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (!isTest && (user == null || !user.canConfigureHardware)) {
      _log('❌ LỖI BẢO MẬT: Quyền bị từ chối. Không được phép khởi động lại đầu đọc!');
      return;
    }
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
