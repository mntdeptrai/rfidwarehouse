import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/wms_models.dart';

class ApiService extends ChangeNotifier {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final HttpClient _httpClient = HttpClient()
    ..connectionTimeout = const Duration(seconds: 4);

  String _baseUrl = 'http://127.0.0.1:3000/api';
  String get baseUrl => _baseUrl;

  bool _isServerOnline = false;
  bool get isServerOnline => _isServerOnline;

  String? _lastError;
  String? get lastError => _lastError;

  void setBaseUrl(String url) {
    String clean = url.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'http://$clean';
    }
    if (!clean.endsWith('/api')) {
      clean = '$clean/api';
    }
    _baseUrl = clean;
    checkHealth();
    notifyListeners();
  }

  Future<dynamic> _get(String endpoint) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      final request = await _httpClient.getUrl(uri);
      final response = await request.close().timeout(const Duration(seconds: 4));
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        return jsonDecode(responseBody);
      }
    } catch (e) {
      debugPrint('ApiService GET $endpoint error: $e');
    }
    return null;
  }

  Future<dynamic> _post(String endpoint, Map<String, dynamic> body) async {
    try {
      final uri = Uri.parse('$_baseUrl$endpoint');
      final request = await _httpClient.postUrl(uri);
      request.headers.set('Content-Type', 'application/json; charset=UTF-8');
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 4));
      final responseBody = await response.transform(utf8.decoder).join();
      if (response.statusCode == 200) {
        return jsonDecode(responseBody);
      }
    } catch (e) {
      debugPrint('ApiService POST $endpoint error: $e');
    }
    return null;
  }

  /// Kiểm tra trạng thái máy chủ REST API
  Future<bool> checkHealth() async {
    try {
      final json = await _get('/health');
      if (json != null && json['database'] == 'CONNECTED') {
        _isServerOnline = true;
        _lastError = null;
      } else {
        _isServerOnline = false;
        _lastError = 'Không kết nối được database';
      }
    } catch (e) {
      _isServerOnline = false;
      _lastError = e.toString();
    }
    notifyListeners();
    return _isServerOnline;
  }

  /// Lấy danh sách Vị trí kệ kho từ REST API
  Future<List<Location>> fetchLocations() async {
    try {
      final json = await _get('/locations');
      if (json != null && json['data'] is List) {
        final List list = json['data'];
        return list.map((m) => Location(
          locationId: m['location_id']?.toString() ?? '',
          locationCode: m['location_code']?.toString() ?? '',
          zone: m['zone']?.toString() ?? '',
          shelf: m['shelf']?.toString() ?? '',
          level: m['level']?.toString() ?? '',
          currentPallets: (m['current_pallets'] as num?)?.toInt() ?? 0,
        )).toList();
      }
    } catch (e) {
      debugPrint('ApiService fetchLocations error: $e');
    }
    return [];
  }

  /// Giai đoạn 1: Cổng RFID Gate gửi tiếp nhận kiện hàng qua REST API
  Future<Map<String, dynamic>?> gateReceive({
    required String orderNo,
    required List<String> scannedEpcs,
    String performedBy = 'Cổng RFID Desktop',
  }) async {
    final result = await _post('/gate/receive', {
      'order_no': orderNo,
      'scanned_epcs': scannedEpcs,
      'performed_by': performedBy,
    });
    if (result != null && result is Map<String, dynamic>) {
      return result;
    }
    return null;
  }

  /// Giai đoạn 2: Tay cầm PDA gửi xác nhận cất thùng lên kệ qua REST API
  Future<Map<String, dynamic>?> pdaPutaway({
    required String cartonBarcode,
    required String locationId,
    String performedBy = 'Thủ kho PDA',
  }) async {
    final result = await _post('/pda/putaway', {
      'carton_barcode': cartonBarcode,
      'location_id': locationId,
      'performed_by': performedBy,
    });
    if (result != null && result is Map<String, dynamic>) {
      return result;
    }
    return null;
  }

  /// Lấy danh sách Đơn nhập kho
  Future<List<dynamic>> fetchInboundOrders({String? status}) async {
    final endpoint = status != null ? '/inbound-orders?status=$status' : '/inbound-orders';
    final json = await _get(endpoint);
    if (json != null && json['data'] is List) {
      return json['data'];
    }
    return [];
  }

  /// Tra cứu thông tin thẻ chip RFID EPC qua REST API
  Future<Map<String, dynamic>?> lookupEpc(String epc) async {
    final json = await _get('/items/epc/$epc');
    if (json != null && json['data'] is Map<String, dynamic>) {
      return json['data'];
    }
    return null;
  }
}
