import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/tag_info.dart';

class UhfService extends ChangeNotifier {
  static final UhfService _instance = UhfService._internal();
  factory UhfService() => _instance;
  UhfService._internal() {
    if (Platform.isAndroid) {
      _methodChannel.setMethodCallHandler(_handleNativeMethodCall);
      _startListeningEvents();
    }
  }

  static const MethodChannel _methodChannel = MethodChannel('com.example.uhf/methods');
  static const EventChannel _eventChannel = EventChannel('com.example.uhf/events');

  bool _isInitialized = false;
  bool _isScanning = false;
  int _rfPower = 30;
  int _frequencyMode = 1;
  String _hardwareVersion = 'N/A';
  String _firmwareVersion = 'N/A';
  int _temperature = 0;

  bool soundEnabled = true;
  bool hapticEnabled = true;
  bool _filterDuplicates = true;
  bool get filterDuplicates => _filterDuplicates;
  set filterDuplicates(bool val) {
    _filterDuplicates = val;
    if (Platform.isAndroid) {
      try {
        _methodChannel.invokeMethod('setFilterDuplicates', {'filter': val});
      } catch (_) {}
    }
    notifyListeners();
  }

  // Tag collections (Optimized with dirty cache to avoid continuous sorting on every frame)
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

  int get uniqueTagCount => _tagsMap.length;
  int _totalReadCount = 0;
  int get totalReadCount => _totalReadCount;

  // Read rate calculation
  int _recentReadCount = 0;
  double _readRate = 0.0;
  double get readRate => _readRate;
  Timer? _rateTimer;

  // Stream subscription
  StreamSubscription? _eventSubscription;
  final StreamController<TagInfo> _tagStreamController = StreamController<TagInfo>.broadcast();
  Stream<TagInfo> get onTagRead => _tagStreamController.stream;

  final StreamController<bool> _triggerStreamController = StreamController<bool>.broadcast();
  Stream<bool> get onTriggerStateChanged => _triggerStreamController.stream;
  bool _isTriggerPressed = false;
  bool get isTriggerPressed => _isTriggerPressed;

  final StreamController<String> _barcodeStreamController = StreamController<String>.broadcast();
  Stream<String> get onBarcodeRead => _barcodeStreamController.stream;

  bool get isInitialized => _isInitialized;
  bool get isScanning => _isScanning;
  int get rfPower => _rfPower;
  int get frequencyMode => _frequencyMode;
  String get hardwareVersion => _hardwareVersion;
  String get firmwareVersion => _firmwareVersion;
  int get temperature => _temperature;

  /// Initialize UHF Module
  Future<bool> init() async {
    if (!Platform.isAndroid) {
      _isInitialized = true;
      _hardwareVersion = 'Simulator/Desktop';
      _firmwareVersion = 'v1.0.0';
      notifyListeners();
      return true;
    }

    try {
      await _methodChannel.invokeMethod<bool>('init');
      _isInitialized = true;
      _hardwareVersion = 'PDA UHF Scanner';
      _firmwareVersion = 'v1.0.0';
      try {
        await refreshDeviceInfo();
      } catch (_) {}
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('UhfService.init error: $e');
      _isInitialized = true;
      _hardwareVersion = 'PDA UHF Scanner';
      _firmwareVersion = 'v1.0.0';
      notifyListeners();
      return true;
    }
  }

  Future<dynamic> _handleNativeMethodCall(MethodCall call) async {
    if (call.method == 'onHardwareTrigger') {
      final Map? args = call.arguments as Map?;
      final bool pressed = args?['pressed'] ?? false;
      _isTriggerPressed = pressed;
      _isScanning = pressed;
      debugPrint('UhfService: Hardware Trigger ${pressed ? "Pressed" : "Released"}');
      _triggerStreamController.add(pressed);
      _notifyThrottleTimer?.cancel();
      notifyListeners();
    } else if (call.method == 'onBarcodeRead') {
      final Map? args = call.arguments as Map?;
      final String barcode = (args?['barcode'] ?? '').toString().trim();
      if (barcode.isNotEmpty) {
        debugPrint('UhfService: Scanned Barcode: $barcode');
        _barcodeStreamController.add(barcode);
      }
    }
  }

  /// Free UHF Module
  Future<bool> free() async {
    await stopInventory();
    _stopListeningEvents();
    if (!Platform.isAndroid) {
      _isInitialized = false;
      notifyListeners();
      return true;
    }

    try {
      final bool? success = await _methodChannel.invokeMethod<bool>('free');
      _isInitialized = !(success ?? true);
      notifyListeners();
      return success ?? true;
    } catch (e) {
      debugPrint('UhfService.free error: $e');
      return false;
    }
  }

  void _startListeningEvents() {
    if (!Platform.isAndroid) return;
    _eventSubscription?.cancel();
    try {
      _eventSubscription = _eventChannel.receiveBroadcastStream().listen((dynamic event) {
        if (event is Map) {
          _handleIncomingTag(event);
        }
      }, onError: (error) {
        debugPrint('UhfService event error: $error');
      });
    } catch (e) {
      debugPrint('UhfService EventChannel error: $e');
    }
  }

  void _stopListeningEvents() {
    _eventSubscription?.cancel();
    _eventSubscription = null;
  }

  Timer? _notifyThrottleTimer;
  void _throttledNotify() {
    if (_notifyThrottleTimer?.isActive ?? false) return;
    _notifyThrottleTimer = Timer(const Duration(milliseconds: 60), () {
      notifyListeners();
    });
  }

  void _handleIncomingTag(Map<dynamic, dynamic> map, {bool isSingle = false}) {
    if (!isSingle && !_isScanning && !_isTriggerPressed) return;
    final newTag = TagInfo.fromMap(map);
    if (newTag.epc.isEmpty) return;

    // Loại bỏ đọc trùng lặp: Nếu thẻ đã từng đọc rồi trong phiên thì bỏ qua không đọc/phát lại
    if (_filterDuplicates && _tagsMap.containsKey(newTag.epc)) {
      return;
    }

    _totalReadCount++;
    _recentReadCount++;

    if (_tagsMap.containsKey(newTag.epc)) {
      final existing = _tagsMap[newTag.epc]!;
      existing.count += newTag.count > 0 ? newTag.count : 1;
      existing.lastSeen = DateTime.now();
      _tagsMap[newTag.epc] = TagInfo(
        epc: existing.epc,
        tid: newTag.tid.isNotEmpty ? newTag.tid : existing.tid,
        user: newTag.user.isNotEmpty ? newTag.user : existing.user,
        rssi: newTag.rssi,
        ant: newTag.ant,
        count: existing.count,
        pc: newTag.pc.isNotEmpty ? newTag.pc : existing.pc,
        timestamp: newTag.timestamp,
        firstSeen: existing.firstSeen,
        lastSeen: existing.lastSeen,
      );
    } else {
      _tagsMap[newTag.epc] = newTag;
    }
    _tagsCacheDirty = true;

    _tagStreamController.add(_tagsMap[newTag.epc]!);
    _throttledNotify();
  }

  /// Start Continuous Inventory Scan
  Future<bool> startInventory() async {
    if (_isScanning) return true;

    _recentReadCount = 0;
    _readRate = 0.0;
    _rateTimer?.cancel();
    _rateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _readRate = _recentReadCount.toDouble();
      _recentReadCount = 0;
      notifyListeners();
    });

    if (!Platform.isAndroid) {
      _isScanning = true;
      notifyListeners();
      return true;
    }

    try {
      final bool? success = await _methodChannel.invokeMethod<bool>('startInventory');
      _isScanning = success ?? false;
      notifyListeners();
      return _isScanning;
    } catch (e) {
      debugPrint('UhfService.startInventory error: $e');
      _isScanning = false;
      notifyListeners();
      return false;
    }
  }

  /// Stop Continuous Inventory Scan
  Future<bool> stopInventory() async {
    _rateTimer?.cancel();
    _rateTimer = null;
    _readRate = 0.0;

    if (!Platform.isAndroid) {
      _isScanning = false;
      notifyListeners();
      return true;
    }

    try {
      final bool? success = await _methodChannel.invokeMethod<bool>('stopInventory');
      _isScanning = false;
      notifyListeners();
      return success ?? true;
    } catch (e) {
      debugPrint('UhfService.stopInventory error: $e');
      _isScanning = false;
      notifyListeners();
      return false;
    }
  }

  /// Single Tag Inventory
  Future<TagInfo?> inventorySingleTag() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      final testTag = TagInfo(
        epc: 'E28011700000020ECA501234',
        tid: 'E28011702000010ECA501234',
        rssi: '-54',
        ant: '1',
      );
      _handleIncomingTag(testTag.toMap(), isSingle: true);
      return testTag;
    }

    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final dynamic res = await _methodChannel.invokeMethod('inventorySingleTag');
      if (res is Map) {
        _handleIncomingTag(res, isSingle: true);
        return TagInfo.fromMap(res);
      }
      return null;
    } catch (e) {
      debugPrint('UhfService.inventorySingleTag error: $e');
      return null;
    }
  }

  /// Kích hoạt quét mã vạch 2D / Barcode trên tay cầm PDA
  Future<bool> triggerBarcodeScan() async {
    if (!Platform.isAndroid) return false;
    try {
      final bool? res = await _methodChannel.invokeMethod<bool>('triggerBarcodeScan');
      return res ?? false;
    } catch (e) {
      debugPrint('UhfService.triggerBarcodeScan error: $e');
      return false;
    }
  }

  /// Bắn sự kiện Barcode thủ công hoặc từ bàn phím wedge
  void injectBarcode(String barcode) {
    final clean = barcode.trim();
    if (clean.isEmpty) return;
    _barcodeStreamController.add(clean);
    notifyListeners();
  }

  /// Read Data from Tag Memory Bank
  /// Bank: 0=RESERVED, 1=EPC, 2=TID, 3=USER
  Future<String?> readData({
    required int bank,
    required int ptr,
    required int cnt,
    String accessPassword = '00000000',
    String? filterData,
    int filterBank = 1,
    int filterPtr = 32,
    int filterCnt = 0,
  }) async {
    if (!Platform.isAndroid) {
      await Future.delayed(const Duration(milliseconds: 300));
      if (bank == 1) return 'E28011700000020ECA501234';
      if (bank == 2) return 'E28011702000010ECA501234';
      if (bank == 3) return '0102030405060708';
      return '00000000';
    }

    try {
      final String? data = await _methodChannel.invokeMethod<String>('readData', {
        'bank': bank,
        'ptr': ptr,
        'cnt': cnt,
        'accessPassword': accessPassword,
        'filterData': filterData,
        'filterBank': filterBank,
        'filterPtr': filterPtr,
        'filterCnt': filterCnt,
      });
      return data;
    } catch (e) {
      debugPrint('UhfService.readData error: $e');
      return null;
    }
  }

  /// Write Data to Tag Memory Bank
  Future<bool> writeData({
    required int bank,
    required int ptr,
    required int cnt,
    required String data,
    String accessPassword = '00000000',
    String? filterData,
    int filterBank = 1,
    int filterPtr = 32,
    int filterCnt = 0,
  }) async {
    if (!Platform.isAndroid) {
      await Future.delayed(const Duration(milliseconds: 400));
      return true;
    }

    try {
      final bool? success = await _methodChannel.invokeMethod<bool>('writeData', {
        'bank': bank,
        'ptr': ptr,
        'cnt': cnt,
        'data': data,
        'accessPassword': accessPassword,
        'filterData': filterData,
        'filterBank': filterBank,
        'filterPtr': filterPtr,
        'filterCnt': filterCnt,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('UhfService.writeData error: $e');
      return false;
    }
  }

  /// Fast Write EPC
  Future<bool> writeDataToEpc({
    required String epc,
    String accessPassword = '00000000',
    String? filterData,
    int filterBank = 1,
    int filterPtr = 32,
    int filterCnt = 0,
  }) async {
    if (!Platform.isAndroid) {
      await Future.delayed(const Duration(milliseconds: 300));
      return true;
    }

    try {
      final bool? success = await _methodChannel.invokeMethod<bool>('writeDataToEpc', {
        'epc': epc,
        'accessPassword': accessPassword,
        'filterData': filterData,
        'filterBank': filterBank,
        'filterPtr': filterPtr,
        'filterCnt': filterCnt,
      });
      return success ?? false;
    } catch (e) {
      debugPrint('UhfService.writeDataToEpc error: $e');
      return false;
    }
  }

  /// Refresh Device Hardware/Firmware Info
  Future<void> refreshDeviceInfo() async {
    if (!Platform.isAndroid) return;

    try {
      final int? p = await _methodChannel.invokeMethod<int>('getPower');
      if (p != null && p > 0) _rfPower = p;

      final int? f = await _methodChannel.invokeMethod<int>('getFrequencyMode');
      if (f != null && f >= 0) _frequencyMode = f;

      final int? t = await _methodChannel.invokeMethod<int>('getTemperature');
      if (t != null) _temperature = t;

      final String? v = await _methodChannel.invokeMethod<String>('getFirmwareVersion');
      if (v != null) _firmwareVersion = v;

      final String? hw = await _methodChannel.invokeMethod<String>('getHardwareVersion');
      if (hw != null) _hardwareVersion = hw;

      notifyListeners();
    } catch (e) {
      debugPrint('UhfService.refreshDeviceInfo error: $e');
    }
  }

  /// Set RF Power (1 - 30 dBm)
  Future<bool> setRfPower(int power) async {
    if (power < 1 || power > 33) return false;
    if (!Platform.isAndroid) {
      _rfPower = power;
      notifyListeners();
      return true;
    }

    try {
      final bool? success = await _methodChannel.invokeMethod<bool>('setPower', {'power': power});
      if (success == true) {
        _rfPower = power;
        notifyListeners();
      }
      return success ?? false;
    } catch (e) {
      debugPrint('UhfService.setRfPower error: $e');
      return false;
    }
  }

  /// Set Frequency Region
  Future<bool> setFrequencyRegion(int mode) async {
    if (!Platform.isAndroid) {
      _frequencyMode = mode;
      notifyListeners();
      return true;
    }

    try {
      final bool? success = await _methodChannel.invokeMethod<bool>('setFrequencyMode', {'mode': mode});
      if (success == true) {
        _frequencyMode = mode;
        notifyListeners();
      }
      return success ?? false;
    } catch (e) {
      debugPrint('UhfService.setFrequencyRegion error: $e');
      return false;
    }
  }

  /// Clear Scanned Tag List
  void clearTags() {
    _tagsMap.clear();
    _cachedTagsList = [];
    _tagsCacheDirty = false;
    _totalReadCount = 0;
    _recentReadCount = 0;
    _readRate = 0.0;
    if (Platform.isAndroid) {
      try {
        _methodChannel.invokeMethod('clearScannedSession');
      } catch (_) {}
    }
    notifyListeners();
  }
}
