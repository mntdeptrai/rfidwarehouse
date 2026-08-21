import 'dart:async';
import 'package:flutter/foundation.dart';

class BravoIntegrationLog {
  final String logId;
  final String action;
  final String documentNo;
  final bool isSuccess;
  final String message;
  final DateTime timestamp;

  BravoIntegrationLog({
    required this.logId,
    required this.action,
    required this.documentNo,
    required this.isSuccess,
    required this.message,
    required this.timestamp,
  });
}

class ErpBravoService extends ChangeNotifier {
  static final ErpBravoService _instance = ErpBravoService._internal();
  factory ErpBravoService() => _instance;
  ErpBravoService._internal();

  bool _isConnected = true;
  String _serverUrl = 'https://erp.bravo.com.vn/api/v2';
  DateTime _lastSyncTime = DateTime.now().subtract(const Duration(minutes: 5));
  final List<BravoIntegrationLog> _logs = [];

  bool get isConnected => _isConnected;
  String get serverUrl => _serverUrl;
  DateTime get lastSyncTime => _lastSyncTime;
  List<BravoIntegrationLog> get logs => List.unmodifiable(_logs);

  void setServerUrl(String url) {
    _serverUrl = url;
    notifyListeners();
  }

  void toggleConnection(bool connected) {
    _isConnected = connected;
    notifyListeners();
  }

  void addLog({
    required String action,
    required String documentNo,
    required bool isSuccess,
    required String message,
  }) {
    _logs.insert(
      0,
      BravoIntegrationLog(
        logId: 'LOG-${DateTime.now().millisecondsSinceEpoch}',
        action: action,
        documentNo: documentNo,
        isSuccess: isSuccess,
        message: message,
        timestamp: DateTime.now(),
      ),
    );
    if (_logs.length > 50) _logs.removeLast();
    _lastSyncTime = DateTime.now();
    notifyListeners();
  }

  /// Đồng bộ kéo Lệnh Nhập mới từ Bravo
  Future<bool> pullInboundOrders() async {
    await Future.delayed(const Duration(milliseconds: 600));
    addLog(
      action: 'PULL_INBOUND',
      documentNo: 'SYNC_ALL',
      isSuccess: true,
      message: 'Đã nhận danh sách Lệnh nhập kho mới nhất từ Bravo ERP',
    );
    return true;
  }

  /// Đồng bộ kéo PO Xuất mới từ Bravo
  Future<bool> pullOutboundOrders() async {
    await Future.delayed(const Duration(milliseconds: 600));
    addLog(
      action: 'PULL_OUTBOUND',
      documentNo: 'SYNC_ALL',
      isSuccess: true,
      message: 'Đã nhận danh sách PO Xuất kho mới nhất từ Bravo ERP',
    );
    return true;
  }

  /// Bắn trạng thái Hoàn tất Nhập kho về Bravo
  Future<bool> pushInboundCompleted(String orderNo, int totalItems) async {
    await Future.delayed(const Duration(milliseconds: 400));
    addLog(
      action: 'PUSH_INBOUND_COMPLETE',
      documentNo: orderNo,
      isSuccess: true,
      message: 'Cập nhật Bravo: Lệnh nhập $orderNo đã hoàn tất ($totalItems Item)',
    );
    return true;
  }

  /// Bắn trạng thái Hoàn tất Xuất kho về Bravo
  Future<bool> pushOutboundCompleted(String poNo, int totalItems) async {
    await Future.delayed(const Duration(milliseconds: 400));
    addLog(
      action: 'PUSH_OUTBOUND_COMPLETE',
      documentNo: poNo,
      isSuccess: true,
      message: 'Cập nhật Bravo: PO $poNo đã xuất kho thành công ($totalItems Item)',
    );
    return true;
  }
}
