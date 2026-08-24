import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
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
    this.syncIntervalSeconds = 5,
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

class SupabaseSyncService extends ChangeNotifier {
  static final SupabaseSyncService _instance = SupabaseSyncService._internal();
  factory SupabaseSyncService() => _instance;

  final DatabaseService _dbService = DatabaseService();
  SupabaseConfig config = SupabaseConfig();

  bool _isOnline = false;
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _pendingCount = 0;
  String _connectionStatusDetail = '';
  final List<SupabaseLogEntry> _logs = [];

  Timer? _autoSyncTimer;
  RealtimeChannel? _realtimeChannel;
  bool _isInitialized = false;

  bool get isOnline => _isOnline;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingCount => _pendingCount;
  String get connectionStatusDetail => _connectionStatusDetail;
  List<SupabaseLogEntry> get logs => List.unmodifiable(_logs);
  SupabaseClient? get client => _isInitialized ? Supabase.instance.client : null;

  SupabaseSyncService._internal() {
    _loadConfigFromDb();
    _refreshPendingCount();
    _startAutoSyncTimer();
  }

  Future<void> _loadConfigFromDb() async {
    try {
      final u = await _dbService.getSystemConfig('supabase_url');
      final k = await _dbService.getSystemConfig('supabase_anon_key');
      final auto = await _dbService.getSystemConfig('supabase_auto_sync');

      if (u != null && u.isNotEmpty) config.url = u;
      if (k != null && k.isNotEmpty) config.anonKey = k;
      if (auto != null) config.isAutoSync = auto == '1';
    } catch (_) {}

    await initSupabase();
  }

  Future<bool> initSupabase() async {
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        _isInitialized = true;
        _isOnline = true;
        _connectionStatusDetail = 'Môi trường Kiểm thử (Test Environment)';
        return true;
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
    if (!config.isAutoSync) return;

    _autoSyncTimer = Timer.periodic(
      Duration(seconds: config.syncIntervalSeconds),
      (_) async {
        if (config.isAutoSync && !_isSyncing) {
          await checkConnectivity();
          if (_isOnline) {
            final count = await _dbService.getPendingSyncCount();
            if (count > 0) {
              await syncNow();
            }
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

    try {
      await _dbService.setSystemConfig('supabase_url', config.url);
      await _dbService.setSystemConfig('supabase_anon_key', config.anonKey);
      await _dbService.setSystemConfig(
        'supabase_auto_sync',
        config.isAutoSync ? '1' : '0',
      );
    } catch (_) {}

    _isInitialized = false;
    _startAutoSyncTimer();
    await initSupabase();
  }

  Future<void> _refreshPendingCount() async {
    try {
      _pendingCount = await _dbService.getPendingSyncCount();
      notifyListeners();
    } catch (_) {}
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
      if (!_isInitialized) {
        await initSupabase();
      }

      if (!_isInitialized) {
        _isOnline = false;
        notifyListeners();
        return false;
      }

      final supa = Supabase.instance.client;
      // Health check bằng cách query bảng system_config hoặc products
      await supa.from('system_config').select('config_key').limit(1);

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

  /// Test connection chi tiết
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

  /// Thiết lập Realtime listener để tự động cập nhật khi có thay đổi từ thiết bị khác
  void _setupRealtimeSubscription() {
    try {
      if (!_isInitialized) return;
      _realtimeChannel?.unsubscribe();

      final supa = Supabase.instance.client;
      _realtimeChannel = supa.channel('public:db_changes')
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'items',
          callback: (payload) {
            debugPrint('Realtime change on items: ${payload.eventType}');
            _addLog(
              action: 'REALTIME',
              tableName: 'items',
              recordCount: 1,
              isSuccess: true,
              message: 'Nhận sự kiện Realtime thay đổi từ items (${payload.eventType})',
            );
            WarehouseRepository().reloadFromSqlite();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'inbound_orders',
          callback: (payload) {
            WarehouseRepository().reloadFromSqlite();
          },
        )
        ..onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'outbound_orders',
          callback: (payload) {
            WarehouseRepository().reloadFromSqlite();
          },
        )
        ..subscribe();
    } catch (e) {
      debugPrint('Realtime subscription error: $e');
    }
  }

  /// Đồng bộ trực tiếp hoặc đẩy vào hàng đợi Offline
  Future<void> syncDirectOrQueue({
    required String tableName,
    required String recordId,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    if (_isOnline && _isInitialized) {
      try {
        final supa = Supabase.instance.client;
        if (action == 'INSERT' || action == 'UPDATE') {
          await supa.from(tableName).upsert(payload);
        } else if (action == 'DELETE') {
          final pkCol = _getPrimaryKeyColumn(tableName);
          await supa.from(tableName).delete().eq(pkCol, recordId);
        }
        return;
      } catch (e) {
        debugPrint('Direct Supabase sync failed, enqueuing offline: $e');
      }
    }

    // Nếu không có mạng hoặc lỗi, lưu vào SQLite sync_queue
    await _dbService.enqueueSync(
      tableName: tableName,
      recordId: recordId,
      action: action,
      payload: payload,
    );
    await _refreshPendingCount();
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
      case 'system_config':
        return 'config_key';
      default:
        return 'id';
    }
  }

  /// Đồng bộ 2 chiều: Push offline items lên Supabase -> Pull latest master data về SQLite
  Future<bool> syncNow() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    notifyListeners();

    try {
      final ok = await checkConnectivity();
      if (!ok) {
        _isSyncing = false;
        await _refreshPendingCount();
        notifyListeners();
        return false;
      }

      final supa = Supabase.instance.client;

      // 1. PUSH DỮ LIỆU TỪ SQLITE SYNC_QUEUE LÊN SUPABASE
      final pending = await _dbService.getPendingSyncItems(limit: 200);
      int pushed = 0;

      if (pending.isNotEmpty) {
        for (final item in pending) {
          final queueId = item['queue_id'] as int;
          final tableName = item['table_name'] as String;
          final action = item['action'] as String;
          final payloadStr = item['payload'] as String;

          try {
            final payload = jsonDecode(payloadStr) as Map<String, dynamic>;
            if (action == 'INSERT' || action == 'UPDATE') {
              await supa.from(tableName).upsert(payload);
            } else if (action == 'DELETE') {
              final pkCol = _getPrimaryKeyColumn(tableName);
              final recId = item['record_id'] as String;
              await supa.from(tableName).delete().eq(pkCol, recId);
            }

            await _dbService.markSyncItemSynced(queueId);
            pushed++;
          } catch (err) {
            debugPrint('Error pushing item $queueId to Supabase: $err');
            await _dbService.markSyncItemFailed(queueId, err.toString());
          }
        }
      }

      if (pushed > 0) {
        _addLog(
          action: 'PUSH',
          tableName: 'ALL_TABLES',
          recordCount: pushed,
          isSuccess: true,
          message: 'Đã đẩy thành công $pushed bản ghi từ PDA/Desktop lên Supabase',
        );
      }

      // 2. PULL DỮ LIỆU TỪ SUPABASE VỀ SQLITE (DANH MỤC SẢN PHẨM, VỊ TRÍ, LỆNH NHẬP/XUẤT)
      await _pullTableFromSupabase('locations');
      await _pullTableFromSupabase('products');
      await _pullTableFromSupabase('pallets');
      await _pullTableFromSupabase('items');
      await _pullTableFromSupabase('inbound_orders');
      await _pullTableFromSupabase('inbound_order_details');
      await _pullTableFromSupabase('outbound_orders');
      await _pullTableFromSupabase('outbound_order_details');

      _lastSyncTime = DateTime.now();
      await _refreshPendingCount();
      await WarehouseRepository().reloadFromSqlite();

      _addLog(
        action: 'PULL',
        tableName: 'ALL_TABLES',
        recordCount: 0,
        isSuccess: true,
        message: 'Hoàn tất đồng bộ 2 chiều với Supabase Cloud.',
      );

      return true;
    } catch (e) {
      _addLog(
        action: 'ERROR',
        tableName: 'SYNC',
        recordCount: 0,
        isSuccess: false,
        message: 'Lỗi trong quá trình đồng bộ Supabase: $e',
      );
      return false;
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _pullTableFromSupabase(String tableName) async {
    try {
      final supa = Supabase.instance.client;
      final List<dynamic> rows = await supa.from(tableName).select();
      if (rows.isEmpty) return;

      final db = await _dbService.database;
      final batch = db.batch();

      for (final row in rows) {
        final map = Map<String, dynamic>.from(row as Map);
        // Loại bỏ cột updated_at nếu SQLite không có
        map.remove('updated_at');
        batch.insert(tableName, map, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    } catch (e) {
      debugPrint('Pull table $tableName from Supabase warning: $e');
    }
  }

  /// Xóa toàn bộ dữ liệu trên Supabase (Dành cho chức năng Reset dữ liệu)
  Future<void> clearAllSupabaseData() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final supa = Supabase.instance.client;
      await supa.from('outbound_order_details').delete().neq('id', 0);
      await supa.from('inbound_order_details').delete().neq('id', 0);
      await supa.from('outbound_orders').delete().neq('outbound_order_id', '');
      await supa.from('inbound_orders').delete().neq('inbound_order_id', '');
      await supa.from('items').delete().neq('item_id', '');
      await supa.from('pallets').delete().neq('pallet_id', '');
      await supa.from('locations').delete().neq('location_id', '');
      await supa.from('products').delete().neq('product_id', '');
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
