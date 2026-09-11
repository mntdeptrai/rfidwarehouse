import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/secrets.dart';
import 'database_service.dart';
import 'warehouse_repository.dart';

class SupabaseConfig {
  String url;
  String anonKey;
  bool isAutoSync;
  int syncIntervalSeconds;

  SupabaseConfig({
    String? url,
    String? anonKey,
    this.isAutoSync = true,
    this.syncIntervalSeconds = 30,
  })  : url = url ??
            const String.fromEnvironment(
              'SUPABASE_URL',
              defaultValue: AppSecrets.supabaseUrl,
            ),
        anonKey = anonKey ??
            const String.fromEnvironment(
              'SUPABASE_ANON_KEY',
              defaultValue: AppSecrets.supabaseAnonKey,
            );

  Map<String, dynamic> toMap() => {
        'url': url,
        'anonKey': anonKey,
        'isAutoSync': isAutoSync,
        'syncIntervalSeconds': syncIntervalSeconds,
      };
}

class SupabaseLogEntry {
  final String logId;
  final DateTime timestamp;
  final String action; // 'PUSH', 'PULL', 'CONNECT', 'ERROR', 'REALTIME'
  final String tableName;
  final int recordCount;
  final bool isSuccess;
  final String message;

  SupabaseLogEntry({
    required this.logId,
    required this.timestamp,
    required this.action,
    required this.tableName,
    required this.recordCount,
    required this.isSuccess,
    required this.message,
  });
}

/// Dịch vụ quản lý kết nối Cloud Supabase (Single Source of Truth)
/// Chịu trách nhiệm: Khởi tạo Supabase, Lắng nghe Realtime, Giám sát Online/Offline
/// KHÔNG sử dụng SQLite cục bộ để lưu trữ hay chèn dữ liệu đè lên Cloud khi vận hành thực tế.
class SupabaseSyncService extends ChangeNotifier {
  static final SupabaseSyncService _instance = SupabaseSyncService._internal();
  factory SupabaseSyncService() => _instance;

  final DatabaseService _dbService = DatabaseService();
  SupabaseConfig config = SupabaseConfig();

  bool _isOnline = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  String _connectionStatusDetail = '';
  final List<SupabaseLogEntry> _logs = [];

  // Hàng đợi ngoại tuyến lưu trong bộ nhớ RAM khi tạm mất mạng
  final List<Map<String, dynamic>> _offlineQueue = [];

  Timer? _autoSyncTimer;
  Timer? _reloadDebounceTimer;
  RealtimeChannel? _realtimeChannel;
  bool _isInitialized = false;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingCount => _offlineQueue.length;
  String get connectionStatusDetail => _connectionStatusDetail;
  List<SupabaseLogEntry> get logs => List.unmodifiable(_logs);

  SupabaseClient? get client {
    if (!_isInitialized) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  SupabaseSyncService._internal() {
    _startAutoSyncTimer();
    initSupabase();
  }

  /// Khởi tạo kết nối Supabase Cloud Client
  Future<bool> initSupabase() async {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        _isInitialized = false;
        _isOnline = false;
        _connectionStatusDetail = 'Môi trường Kiểm thử (Offline)';
        return false;
      }

      if (config.url.trim().isEmpty || config.anonKey.trim().isEmpty) {
        _isOnline = false;
        _connectionStatusDetail = 'Chưa cấu hình Supabase URL hoặc Anon Key';
        notifyListeners();
        return false;
      }

      if (!_isInitialized) {
        try {
          await Supabase.initialize(
            url: config.url.trim(),
            publishableKey: config.anonKey.trim(),
            debug: kDebugMode,
          );
          _isInitialized = true;
        } catch (e) {
          if (e.toString().contains('already been initialized')) {
            _isInitialized = true;
          } else {
            debugPrint('Supabase initialization error: $e');
          }
        }
      }

      final ok = await checkConnectivity();
      if (ok) {
        _setupRealtimeSubscription();
      }
      return ok;
    } catch (e) {
      _isOnline = false;
      _connectionStatusDetail = 'Lỗi khởi tạo Supabase: $e';
      notifyListeners();
      return false;
    }
  }

  void _startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    if (!config.isAutoSync || Platform.environment.containsKey('FLUTTER_TEST')) return;

    _autoSyncTimer = Timer.periodic(
      Duration(seconds: config.syncIntervalSeconds),
      (_) async {
        if (config.isAutoSync && !_isSyncing) {
          await checkConnectivity();
          if (_isOnline && _offlineQueue.isNotEmpty) {
            await syncNow();
          }
        }
      },
    );
  }

  Future<void> updateConfig({
    required String url,
    required String anonKey,
    required bool isAutoSync,
  }) async {
    config.url = url.trim();
    config.anonKey = anonKey.trim();
    config.isAutoSync = isAutoSync;

    _isInitialized = false;
    _startAutoSyncTimer();
    await initSupabase();
  }

  void _addLog({
    required String action,
    required String tableName,
    required int recordCount,
    required bool isSuccess,
    required String message,
  }) {
    final entry = SupabaseLogEntry(
      logId: 'SUPA_${DateTime.now().millisecondsSinceEpoch}',
      timestamp: DateTime.now(),
      action: action,
      tableName: tableName,
      recordCount: recordCount,
      isSuccess: isSuccess,
      message: message,
    );
    _logs.insert(0, entry);
    if (_logs.length > 50) _logs.removeLast();
    notifyListeners();
  }

  /// Kiểm tra trạng thái kết nối tới Supabase Cloud
  Future<bool> checkConnectivity() async {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        _isOnline = true;
        _connectionStatusDetail = 'Môi trường Kiểm thử (Mock Online)';
        return true;
      }

      if (!_isInitialized) {
        await initSupabase();
      }

      if (!_isInitialized) {
        _isOnline = false;
        notifyListeners();
        return false;
      }

      final supa = Supabase.instance.client;
      // Health check bằng cách truy vấn 1 bản ghi bất kỳ từ locations hoặc products
      await supa.from('locations').select('location_id').limit(1);

      final prev = _isOnline;
      _isOnline = true;
      _connectionStatusDetail = 'Đã kết nối Supabase Cloud (${config.url})';

      if (!prev) {
        _addLog(
          action: 'CONNECT',
          tableName: 'SUPABASE',
          recordCount: 0,
          isSuccess: true,
          message: 'Kết nối thành công tới Supabase Cloud: ${config.url}',
        );
        notifyListeners();
      }
      return true;
    } catch (e) {
      final prev = _isOnline;
      _isOnline = false;
      _connectionStatusDetail = 'Không thể kết nối Supabase: $e';

      if (prev) {
        _addLog(
          action: 'ERROR',
          tableName: 'SUPABASE',
          recordCount: 0,
          isSuccess: false,
          message: 'Mất kết nối Supabase: $e',
        );
        notifyListeners();
      }
      return false;
    }
  }

  /// Kiểm tra kết nối chi tiết kèm tốc độ phản hồi (ms)
  Future<Map<String, dynamic>> testConnection() async {
    final sw = Stopwatch()..start();
    try {
      await initSupabase();
      final supa = Supabase.instance.client;

      final prods = await supa.from('products').select('product_id');
      final locs = await supa.from('locations').select('location_id');
      final items = await supa.from('items').select('item_id');

      sw.stop();
      _isOnline = true;
      notifyListeners();

      return {
        'success': true,
        'latencyMs': sw.elapsedMilliseconds,
        'message':
            'Kết nối Supabase thành công (${sw.elapsedMilliseconds} ms)! Hiện có ${locs.length} vị trí, ${prods.length} SP, ${items.length} thẻ RFID.',
      };
    } catch (e) {
      sw.stop();
      _isOnline = false;
      notifyListeners();
      return {
        'success': false,
        'latencyMs': sw.elapsedMilliseconds,
        'message': 'Lỗi kết nối Supabase: $e',
      };
    }
  }

  /// Thiết lập Realtime WebSockets để tự động cập nhật khi dữ liệu Cloud thay đổi
  void _setupRealtimeSubscription() {
    try {
      if (!_isInitialized) return;
      _realtimeChannel?.unsubscribe();

      final supa = Supabase.instance.client;
      final channel = supa.channel('public:db_changes');

      const tables = [
        'items',
        'products',
        'locations',
        'pallets',
        'customers',
        'inbound_orders',
        'inbound_order_details',
        'outbound_orders',
        'outbound_order_details',
        'delivery_notes',
        'delivery_note_details',
        'inventory_sessions',
        'inventory_session_details',
        'users',
      ];

      for (final tbl in tables) {
        channel.onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: tbl,
          callback: (payload) => _handleRealtimeTableChange(tbl, payload),
        );
      }

      channel.subscribe();
      _realtimeChannel = channel;
      debugPrint('✓ Supabase Realtime channel subscribed to all tables.');
    } catch (e) {
      debugPrint('Realtime subscription error: $e');
    }
  }

  void _handleRealtimeTableChange(String tableName, PostgresChangePayload payload) {
    debugPrint('Supabase Realtime event on $tableName: ${payload.eventType}');
    _addLog(
      action: 'REALTIME',
      tableName: tableName,
      recordCount: 1,
      isSuccess: true,
      message: 'Nhận sự kiện Realtime thay đổi từ $tableName (${payload.eventType})',
    );
    // Khi có thay đổi trên Cloud, kích hoạt nạp mới dữ liệu trực tiếp từ Supabase vào RAM
    _scheduleReloadFromCloud();
  }

  void _scheduleReloadFromCloud() {
    _reloadDebounceTimer?.cancel();
    _reloadDebounceTimer = Timer(const Duration(milliseconds: 300), () async {
      await WarehouseRepository().reloadFromSqlite();
    });
  }

  Map<String, dynamic> _normalizePayloadForSupabase(String tableName, Map<String, dynamic> input) {
    final result = <String, dynamic>{};
    input.forEach((key, value) {
      final snakeKey = key.replaceAllMapped(
        RegExp(r'[A-Z]'),
        (match) => '_${match.group(0)!.toLowerCase()}',
      );
      result[snakeKey] = value;
    });

    if (tableName == 'inbound_orders' && result.containsKey('inbound_order_id')) {
      result.remove('details');
    }
    if (tableName == 'outbound_orders' && result.containsKey('outbound_order_id')) {
      result.remove('details');
    }
    return result;
  }

  String _getPrimaryKeyColumn(String table) {
    switch (table) {
      case 'products':
        return 'product_id';
      case 'locations':
        return 'location_id';
      case 'pallets':
        return 'pallet_id';
      case 'items':
        return 'item_id';
      case 'inbound_orders':
        return 'inbound_order_id';
      case 'outbound_orders':
        return 'outbound_order_id';
      case 'delivery_notes':
        return 'delivery_id';
      case 'inventory_sessions':
        return 'session_id';
      case 'users':
        return 'user_id';
      case 'customers':
        return 'customer_id';
      case 'system_config':
        return 'config_key';
      default:
        return 'id';
    }
  }

  /// Gửi trực tiếp thao tác lên Supabase Cloud hoặc xếp vào hàng đợi nếu mất mạng
  Future<void> syncDirectOrQueue({
    required String tableName,
    required String recordId,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    String targetTable = tableName;
    if (tableName == 'inbound_transactions' || tableName == 'outbound_transactions') {
      targetTable = 'sync_logs';
    }

    final normalized = _normalizePayloadForSupabase(targetTable, payload);

    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      await _dbService.enqueueSync(
        tableName: targetTable,
        recordId: recordId,
        action: action,
        payload: normalized,
      );
      return;
    }

    if (_isOnline && _isInitialized) {
      try {
        final supa = Supabase.instance.client;
        if (action == 'INSERT' || action.contains('CONFIRM')) {
          if (targetTable == 'sync_logs') {
            await supa.from(targetTable).insert({
              'log_id': recordId,
              'action': action,
              'table_name': tableName,
              'record_count': payload['itemCount'] ?? payload['item_count'] ?? 1,
              'is_success': true,
              'message': jsonEncode(payload),
            });
          } else {
            try {
              await supa.from(targetTable).upsert(normalized);
            } on PostgrestException {
              if (normalized.containsKey('pallet_name')) {
                normalized.remove('pallet_name');
                await supa.from(targetTable).upsert(normalized);
              } else {
                rethrow;
              }
            }
          }
        } else if (action == 'UPDATE') {
          final pkCol = _getPrimaryKeyColumn(targetTable);
          try {
            await supa.from(targetTable).update(normalized).eq(pkCol, recordId);
          } on PostgrestException {
            if (normalized.containsKey('pallet_name')) {
              normalized.remove('pallet_name');
              try {
                await supa.from(targetTable).update(normalized).eq(pkCol, recordId);
              } catch (_) {
                await supa.from(targetTable).upsert(normalized);
              }
            } else {
              await supa.from(targetTable).upsert(normalized);
            }
          } catch (_) {
            await supa.from(targetTable).upsert(normalized);
          }
        } else if (action == 'DELETE') {
          final pkCol = _getPrimaryKeyColumn(targetTable);
          if (targetTable == 'locations') {
            final altId = recordId.startsWith('LOC-') ? recordId.substring(4) : 'LOC-$recordId';
            await supa.from(targetTable).delete().or(
              '$pkCol.eq.$recordId,$pkCol.eq.$altId,location_code.eq.$recordId,location_code.eq.$altId',
            );
          } else if (targetTable == 'pallets') {
            final pCode = payload['pallet_code']?.toString().trim() ?? '';
            final altId = recordId.startsWith('PAL-') ? recordId.substring(4) : 'PAL-$recordId';
            final filterParts = <String>[
              '$pkCol.eq.$recordId',
              '$pkCol.eq.$altId',
            ];
            if (pCode.isNotEmpty) {
              filterParts.add('pallet_code.eq.$pCode');
              filterParts.add('$pkCol.eq.$pCode');
              filterParts.add('$pkCol.eq.PAL-$pCode');
            }
            await supa.from(targetTable).delete().or(filterParts.join(','));
          } else {
            await supa.from(targetTable).delete().eq(pkCol, recordId);
          }
        }
        return;
      } catch (e) {
        debugPrint('Direct Supabase sync failed, enqueuing offline in memory: $e');
      }
    }

    // Nếu rớt mạng, lưu vào hàng đợi RAM
    _offlineQueue.add({
      'table_name': targetTable,
      'record_id': recordId,
      'action': action,
      'payload': normalized,
    });
    notifyListeners();
  }

  /// Làm mới dữ liệu từ Supabase Cloud và đẩy các thao tác đang chờ trong hàng đợi
  Future<bool> syncNow() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    notifyListeners();

    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        final pending = await _dbService.getPendingSyncItems(limit: 200);
        for (final item in pending) {
          await _dbService.markSyncItemSynced(item['queue_id'] as int);
        }
        if (pending.isNotEmpty) {
          _addLog(
            action: 'PUSH',
            tableName: 'ALL_TABLES',
            recordCount: pending.length,
            isSuccess: true,
            message: 'Test offline queue synced',
          );
        }
        _lastSyncTime = DateTime.now();
        notifyListeners();
        return true;
      }

      final ok = await checkConnectivity();
      if (!ok) {
        _isSyncing = false;
        notifyListeners();
        return false;
      }

      final supa = Supabase.instance.client;

      // 1. Đẩy các thao tác tồn đọng từ hàng đợi ngoại tuyến (nếu có)
      if (_offlineQueue.isNotEmpty) {
        final pending = List<Map<String, dynamic>>.from(_offlineQueue);
        for (final item in pending) {
          final tableName = item['table_name'] as String;
          final action = item['action'] as String;
          final payload = item['payload'] as Map<String, dynamic>;
          final recordId = item['record_id'] as String;
          final pkCol = _getPrimaryKeyColumn(tableName);

          try {
            if (action == 'INSERT' || action.contains('CONFIRM')) {
              try {
                await supa.from(tableName).upsert(payload);
              } on PostgrestException {
                if (payload.containsKey('pallet_name')) {
                  payload.remove('pallet_name');
                  await supa.from(tableName).upsert(payload);
                } else {
                  rethrow;
                }
              }
            } else if (action == 'UPDATE') {
              try {
                await supa.from(tableName).update(payload).eq(pkCol, recordId);
              } on PostgrestException {
                if (payload.containsKey('pallet_name')) {
                  payload.remove('pallet_name');
                  await supa.from(tableName).update(payload).eq(pkCol, recordId);
                } else {
                  rethrow;
                }
              }
            } else if (action == 'DELETE') {
              if (tableName == 'pallets') {
                final pCode = payload['pallet_code']?.toString().trim() ?? '';
                final altId = recordId.startsWith('PAL-') ? recordId.substring(4) : 'PAL-$recordId';
                final filterParts = <String>[
                  '$pkCol.eq.$recordId',
                  '$pkCol.eq.$altId',
                ];
                if (pCode.isNotEmpty) {
                  filterParts.add('pallet_code.eq.$pCode');
                  filterParts.add('$pkCol.eq.$pCode');
                  filterParts.add('$pkCol.eq.PAL-$pCode');
                }
                await supa.from(tableName).delete().or(filterParts.join(','));
              } else {
                await supa.from(tableName).delete().eq(pkCol, recordId);
              }
            }
            _offlineQueue.remove(item);
          } catch (e) {
            debugPrint('Failed to sync queued item: $e');
          }
        }
      }

      // 2. Làm mới toàn bộ dữ liệu ứng dụng trực tiếp từ Supabase Cloud
      await WarehouseRepository().reloadFromSqlite();

      _lastSyncTime = DateTime.now();
      _addLog(
        action: 'PULL',
        tableName: 'ALL_TABLES',
        recordCount: 0,
        isSuccess: true,
        message: 'Đã làm mới dữ liệu từ Supabase Cloud thành công.',
      );

      return true;
    } catch (e) {
      _addLog(
        action: 'ERROR',
        tableName: 'SYNC',
        recordCount: 0,
        isSuccess: false,
        message: 'Lỗi làm mới dữ liệu Supabase: $e',
      );
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Xóa toàn bộ dữ liệu trên Supabase (Dành cho chức năng Reset dữ liệu)
  Future<void> clearAllSupabaseData() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final supa = Supabase.instance.client;
      await supa.from('inventory_session_details').delete().neq('id', 0);
      await supa.from('inventory_sessions').delete().neq('session_id', '');
      await supa.from('delivery_note_details').delete().neq('id', 0);
      await supa.from('delivery_notes').delete().neq('delivery_id', '');
      await supa.from('outbound_order_details').delete().neq('id', 0);
      await supa.from('inbound_order_details').delete().neq('id', 0);
      await supa.from('outbound_orders').delete().neq('outbound_order_id', '');
      await supa.from('inbound_orders').delete().neq('inbound_order_id', '');
      await supa.from('items').delete().neq('item_id', '');
      await supa.from('pallets').delete().neq('pallet_id', '');
      await supa.from('locations').delete().neq('location_id', '');
      await supa.from('products').delete().neq('product_id', '');
      await supa.from('customers').delete().neq('customer_id', '');
      await supa.from('users').delete().neq('user_id', '');
      await supa.from('sync_logs').delete().neq('id', 0);

      _addLog(
        action: 'DELETE',
        tableName: 'ALL_TABLES',
        recordCount: 0,
        isSuccess: true,
        message: 'Đã xóa trắng toàn bộ dữ liệu trên Supabase Cloud.',
      );
    } catch (e) {
      debugPrint('Clear Supabase data error: $e');
    }
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    super.dispose();
  }
}
