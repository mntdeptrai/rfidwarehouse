import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mysql_client/mysql_client.dart';
import '../models/wms_models.dart';
import 'database_service.dart';
import 'warehouse_repository.dart';

class SyncLogEntry {
  final String logId;
  final DateTime timestamp;
  final String action; // 'PUSH', 'PULL', 'CONNECT', 'ERROR'
  final String tableName;
  final int recordCount;
  final bool isSuccess;
  final String message;

  SyncLogEntry({
    required this.logId,
    required this.timestamp,
    required this.action,
    required this.tableName,
    required this.recordCount,
    required this.isSuccess,
    required this.message,
  });
}

class MySqlConfig {
  String host;
  int port;
  String database;
  String username;
  String password;
  bool isAutoSync;
  int syncIntervalSeconds;

  MySqlConfig({
    this.host = '127.0.0.1',
    this.port = 3306,
    this.database = 'rfidwarehouse',
    this.username = 'root',
    this.password = '',
    this.isAutoSync = true,
    this.syncIntervalSeconds = 5,
  });

  Map<String, dynamic> toMap() => {
    'host': host,
    'port': port,
    'database': database,
    'username': username,
    'password': password,
    'isAutoSync': isAutoSync,
    'syncIntervalSeconds': syncIntervalSeconds,
  };
}

class MySqlSyncService extends ChangeNotifier {
  static final MySqlSyncService _instance = MySqlSyncService._internal();
  factory MySqlSyncService() => _instance;

  final DatabaseService _dbService = DatabaseService();

  MySqlConfig config = MySqlConfig();

  bool _isOnline = false;
  bool _isWifiConnected = false;
  String _pdaIpAddress = '';
  String _connectionStatusDetail = '';
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _pendingCount = 0;
  final List<SyncLogEntry> _logs = [];

  Timer? _autoSyncTimer;

  bool get isOnline => _isOnline;
  bool get isWifiConnected => _isWifiConnected;
  String get pdaIpAddress => _pdaIpAddress;
  String get connectionStatusDetail => _connectionStatusDetail;
  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  int get pendingCount => _pendingCount;
  List<SyncLogEntry> get logs => List.unmodifiable(_logs);

  bool _isCheckingConnectivity = false;
  DateTime _lastNetworkInterfaceCheck = DateTime.fromMillisecondsSinceEpoch(0);

  MySqlSyncService._internal() {
    _refreshPendingCount();
    _startAutoSyncTimer();
    checkConnectivity();
  }

  void _startAutoSyncTimer() {
    _autoSyncTimer?.cancel();
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      return;
    }
    // Chạy chu kỳ 5 giây một lần để đồng bộ 2 chiều (Đẩy dữ liệu PDA lên và Kéo cập nhật từ MySQL về)
    _autoSyncTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (config.isAutoSync && !_isSyncing && !_isCheckingConnectivity) {
        await checkConnectivity();
        if (_isOnline) {
          await syncNow();
        }
      }
    });
  }

  Future<void> updateConfig({
    required String host,
    required int port,
    required String database,
    required String username,
    required String password,
    required bool isAutoSync,
  }) async {
    config.host = host.trim();
    config.port = port;
    config.database = database.trim();
    config.username = username.trim();
    config.password = password;
    config.isAutoSync = isAutoSync;
    _startAutoSyncTimer();
    notifyListeners();
    await checkConnectivity(forceIpRefresh: true);
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
    final entry = SyncLogEntry(
      logId: 'SYNC_${DateTime.now().millisecondsSinceEpoch}',
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

  /// Kiểm tra trạng thái kết nối mạng & cổng MySQL an toàn, không block UI
  Future<bool> checkConnectivity({bool forceIpRefresh = false}) async {
    if (_isCheckingConnectivity) return _isOnline;
    _isCheckingConnectivity = true;

    try {
      if (kIsWeb) {
        _isOnline = false;
        _isWifiConnected = false;
        _connectionStatusDetail = 'Môi trường Web';
        notifyListeners();
        return false;
      }

      if (Platform.environment.containsKey('FLUTTER_TEST')) {
        _isOnline = true;
        _isWifiConnected = true;
        _pdaIpAddress = '192.168.1.50';
        _connectionStatusDetail = 'Test Environment';
        notifyListeners();
        return true;
      }

      // 1. Kiểm tra IP Wi-Fi nội bộ (Chỉ truy vấn tối đa 1 lần / 30 giây để tránh lag Android JNI)
      final now = DateTime.now();
      if (forceIpRefresh || _pdaIpAddress.isEmpty || now.difference(_lastNetworkInterfaceCheck).inSeconds > 30) {
        _lastNetworkInterfaceCheck = now;
        bool wifiFound = false;
        String currentPdaIp = '';
        try {
          final interfaces = await NetworkInterface.list(
            includeLoopback: false,
            type: InternetAddressType.IPv4,
          ).timeout(const Duration(milliseconds: 800));

          for (var iface in interfaces) {
            for (var addr in iface.addresses) {
              if (!addr.isLoopback && addr.address.isNotEmpty && !addr.address.startsWith('127.')) {
                wifiFound = true;
                currentPdaIp = addr.address;
                break;
              }
            }
            if (wifiFound) break;
          }
        } catch (_) {}

        _isWifiConnected = wifiFound;
        if (currentPdaIp.isNotEmpty) {
          _pdaIpAddress = currentPdaIp;
        }
      }

      final prevWifi = _isWifiConnected;
      final prevPdaIp = _pdaIpAddress;

      // 2. Kiểm tra thông cổng tới Máy chủ MySQL Server
      final host = config.host.trim();
      final port = config.port;

      // Nếu chạy trên Android mà host đang để 127.0.0.1 thì bỏ qua ngay để không tốn timeout socket
      if (Platform.isAndroid && (host == '127.0.0.1' || host == 'localhost')) {
        final previous = _isOnline;
        _isOnline = false;
        _connectionStatusDetail = '127.0.0.1 là IP của tay cầm. Hãy nhập IP máy tính (${_pdaIpAddress.isNotEmpty ? "cùng dải $_pdaIpAddress" : "Wi-Fi"})';
        if (previous || prevWifi != _isWifiConnected || prevPdaIp != _pdaIpAddress) {
          notifyListeners();
        }
        return false;
      }

      if (host.isEmpty) {
        final previous = _isOnline;
        _isOnline = false;
        _connectionStatusDetail = _isWifiConnected
            ? 'Đã kết nối Wi-Fi ($_pdaIpAddress) - Chưa cấu hình IP MySQL'
            : 'Chưa kết nối Wi-Fi';
        if (previous || prevWifi != _isWifiConnected || prevPdaIp != _pdaIpAddress) {
          notifyListeners();
        }
        return false;
      }

      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(milliseconds: 800),
        );
        await socket.close();

        final previous = _isOnline;
        _isOnline = true;
        _connectionStatusDetail = 'Đã kết nối MySQL ($host:$port)';

        if (!previous || prevWifi != _isWifiConnected || prevPdaIp != _pdaIpAddress) {
          _addLog(
            action: 'CONNECT',
            tableName: 'NETWORK',
            recordCount: 0,
            isSuccess: true,
            message: 'Đã nhận diện Wi-Fi ($_pdaIpAddress) và kết nối tới MySQL ($host:$port)',
          );
          notifyListeners();

          // Tự động đồng bộ ngay lập tức khi phát hiện có mạng Wi-Fi (không cần bấm nút)
          if (config.isAutoSync && !_isSyncing && !Platform.environment.containsKey('FLUTTER_TEST')) {
            Future.microtask(() async {
              final count = await _dbService.getPendingSyncCount();
              if (count > 0) {
                await syncNow();
              }
            });
          }
        }
        return true;
      } catch (e) {
        final previous = _isOnline;
        _isOnline = false;
        _connectionStatusDetail = _isWifiConnected
            ? 'Đã có Wi-Fi ($_pdaIpAddress) - Không thể kết nối tới MySQL $host:$port'
            : 'Chưa kết nối Wi-Fi';

        if (previous || prevWifi != _isWifiConnected || prevPdaIp != _pdaIpAddress) {
          notifyListeners();
        }
        return false;
      }
    } finally {
      _isCheckingConnectivity = false;
    }
  }

  /// Kiểm tra kết nối thử nghiệm với kết quả chi tiết
  Future<Map<String, dynamic>> testConnection() async {
    final stopwatch = Stopwatch()..start();
    try {
      final host = config.host.trim();
      final port = config.port;
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 3),
      );
      await socket.close();
      stopwatch.stop();

      _isOnline = true;
      notifyListeners();

      return {
        'success': true,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'message': 'Kết nối MySQL (${config.host}:${config.port}) thành công (${stopwatch.elapsedMilliseconds} ms)!',
      };
    } catch (e) {
      stopwatch.stop();
      _isOnline = false;
      notifyListeners();
      return {
        'success': false,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'message': 'Không thể kết nối tới MySQL (${config.host}:${config.port}): $e',
      };
    }
  }

  /// Thực hiện Đồng bộ 2 chiều (Push offline changes -> Pull latest master data)
  Future<bool> syncNow() async {
    if (_isSyncing) return false;
    _isSyncing = true;
    notifyListeners();

    try {
      final connected = await checkConnectivity();
      if (!connected) {
        _addLog(
          action: 'ERROR',
          tableName: 'NETWORK',
          recordCount: 0,
          isSuccess: false,
          message: 'Không có mạng kết nối MySQL. Chuyển sang lưu tạm SQLite offline.',
        );
        _isSyncing = false;
        await _refreshPendingCount();
        notifyListeners();
        return false;
      }

      final isTestEnv = Platform.environment.containsKey('FLUTTER_TEST');

      // ==========================================
      // BƯỚC 1: PUSH DỮ LIỆU TỪ SQLITE LÊN MYSQL
      // ==========================================
      final pendingItems = await _dbService.getPendingSyncItems(limit: 200);
      int pushedCount = 0;

      if (pendingItems.isNotEmpty) {
        MySQLConnection? conn;

        if (!isTestEnv) {
          try {
            conn = await _connectMySql();
          } catch (connErr) {
            _addLog(
              action: 'ERROR',
              tableName: 'MYSQL',
              recordCount: 0,
              isSuccess: false,
              message: 'Không thể mở kết nối MySQL ($config.host:$config.port): $connErr',
            );
            _isSyncing = false;
            await _refreshPendingCount();
            notifyListeners();
            return false;
          }
        }

        for (final item in pendingItems) {
          final queueId = item['queue_id'] as int;
          final tableName = item['table_name'] as String;
          final action = item['action'] as String;
          final payloadStr = item['payload'] as String;

          try {
            final payload = jsonDecode(payloadStr) as Map<String, dynamic>;

            if (conn != null) {
              await _executeMySqlSyncItem(conn, tableName, action, payload);
            }

            debugPrint('Synced [MySQL]: $action on table $tableName (ID: ${item['record_id']})');
            await _dbService.markSyncItemSynced(queueId);
            pushedCount++;
          } catch (err) {
            debugPrint('Sync error on item $queueId ($tableName): $err');
            await _dbService.markSyncItemFailed(queueId, err.toString());
          }
        }

        if (conn != null) {
          try {
            await conn.close();
          } catch (_) {}
        }
      }

      if (pushedCount > 0) {
        _addLog(
          action: 'PUSH',
          tableName: 'ALL_TABLES',
          recordCount: pushedCount,
          isSuccess: true,
          message: 'Đã đẩy thành công $pushedCount bản ghi từ SQLite lên MySQL rfidwarehouse',
        );
      }

      // ==========================================
      // BƯỚC 2: PULL DỮ LIỆU MỚI TỪ MYSQL VỀ SQLITE
      // ==========================================
      int pulledCount = 0;
      if (!isTestEnv) {
        MySQLConnection? pullConn;
        try {
          pullConn = await _connectMySql();
          pulledCount = await _pullMasterDataFromMySql(pullConn);
        } catch (pullErr) {
          debugPrint('Pull error from MySQL: $pullErr');
        } finally {
          if (pullConn != null) {
            try {
              await pullConn.close();
            } catch (_) {}
          }
        }
      }

      await WarehouseRepository().refreshFromDatabase();

      _addLog(
        action: 'PULL',
        tableName: 'MASTER_DATA',
        recordCount: pulledCount,
        isSuccess: true,
        message: 'Đã đồng bộ $pulledCount danh mục & phiếu nhập từ MySQL về SQLite cục bộ',
      );

      _lastSyncTime = DateTime.now();
      await _dbService.clearCompletedSyncQueue();
      await _refreshPendingCount();

      _isSyncing = false;
      notifyListeners();
      return true;
    } catch (e) {
      _addLog(
        action: 'ERROR',
        tableName: 'SYNC',
        recordCount: 0,
        isSuccess: false,
        message: 'Lỗi trong quá trình đồng bộ: $e',
      );
      _isSyncing = false;
      await _refreshPendingCount();
      notifyListeners();
      return false;
    }
  }

  Future<MySQLConnection> connectForDirectPush() => _connectMySql();
  Future<void> executeSyncItemDirect(MySQLConnection conn, String tableName, String action, Map<String, dynamic> payload) => _executeMySqlSyncItem(conn, tableName, action, payload);

  Future<int> _pullMasterDataFromMySql(MySQLConnection conn) async {
    int pulledRecords = 0;
    try {
      // 1. Pull Products
      final prodResult = await conn.execute("SELECT product_id, sku, product_name, unit, category, description FROM products");
      for (final row in prodResult.rows) {
        final m = row.assoc();
        final p = Product(
          productId: m['product_id'] ?? '',
          sku: m['sku'] ?? '',
          productName: m['product_name'] ?? '',
          unit: m['unit'] ?? 'Cái',
          category: m['category'] ?? 'Chung',
          description: m['description'],
        );
        if (p.productId.isNotEmpty) {
          await _dbService.insertProduct(p);
          pulledRecords++;
        }
      }

      // 2. Pull Locations
      final locResult = await conn.execute("SELECT location_id, location_code, zone, shelf, level, current_pallets FROM locations");
      for (final row in locResult.rows) {
        final m = row.assoc();
        final l = Location(
          locationId: m['location_id'] ?? '',
          locationCode: m['location_code'] ?? '',
          zone: m['zone'] ?? 'A',
          shelf: m['shelf'] ?? '01',
          level: m['level'] ?? '01',
          currentPallets: int.tryParse(m['current_pallets'] ?? '0') ?? 0,
        );
        if (l.locationId.isNotEmpty) {
          await _dbService.insertLocation(l);
          pulledRecords++;
        }
      }

      // 3. Pull Pallets
      final palResult = await conn.execute("SELECT pallet_id, pallet_code, location_id, inbound_time, is_multi_sku FROM pallets");
      for (final row in palResult.rows) {
        final m = row.assoc();
        final p = Pallet(
          palletId: m['pallet_id'] ?? '',
          palletCode: m['pallet_code'] ?? '',
          locationId: m['location_id'],
          inboundTime: DateTime.tryParse(m['inbound_time'] ?? '') ?? DateTime.now(),
          isMultiSku: (m['is_multi_sku'] == '1' || m['is_multi_sku'] == 'true'),
        );
        if (p.palletId.isNotEmpty) {
          await _dbService.insertPallet(p);
          pulledRecords++;
        }
      }

      // 4. Pull Inbound Orders & Details
      final orderResult = await conn.execute("SELECT inbound_order_id, order_no, source_supplier, status, created_at FROM inbound_orders");
      for (final row in orderResult.rows) {
        final m = row.assoc();
        final orderId = m['inbound_order_id'] ?? '';
        final orderNo = m['order_no'] ?? orderId;
        final statusStr = m['status'] ?? 'NEW';
        final status = InboundOrderStatus.values.firstWhere(
          (s) => s.code == statusStr,
          orElse: () => InboundOrderStatus.newOrder,
        );

        final detailResult = await conn.execute(
          "SELECT product_id, sku, product_name, required_qty, received_qty FROM inbound_order_details WHERE order_id = :oid",
          {"oid": orderId},
        );

        final List<InboundOrderDetail> details = [];
        for (final dRow in detailResult.rows) {
          final dm = dRow.assoc();
          details.add(InboundOrderDetail(
            productId: dm['product_id'] ?? '',
            sku: dm['sku'] ?? '',
            productName: dm['product_name'] ?? '',
            requiredQty: int.tryParse(dm['required_qty'] ?? '0') ?? 0,
            receivedQty: int.tryParse(dm['received_qty'] ?? '0') ?? 0,
          ));
        }

        final order = InboundOrder(
          inboundOrderId: orderId,
          orderNo: orderNo,
          sourceSupplier: m['source_supplier'] ?? 'Nhà cung cấp',
          status: status,
          createdAt: DateTime.tryParse(m['created_at'] ?? '') ?? DateTime.now(),
          details: details,
        );
        if (order.inboundOrderId.isNotEmpty) {
          await _dbService.insertInboundOrder(order);
          pulledRecords++;
        }
      }

      // 5. Pull Items
      final itemResult = await conn.execute("SELECT item_id, product_id, sku, product_name, serial_number, epc, status, order_no, pallet_id, location_id, inbound_time, allocated_time FROM items");
      for (final row in itemResult.rows) {
        final m = row.assoc();
        final epc = m['epc'] ?? '';
        if (epc.isNotEmpty) {
          final statusStr = m['status'] ?? 'IN_STOCK';
          final status = ItemStatus.values.firstWhere(
            (s) => s.code == statusStr,
            orElse: () => ItemStatus.inStock,
          );
          final it = Item(
            itemId: m['item_id'] ?? 'ITEM-$epc',
            productId: m['product_id'] ?? '',
            sku: m['sku'] ?? '',
            productName: m['product_name'] ?? '',
            serialNumber: m['serial_number'] ?? epc,
            epc: epc,
            status: status,
            orderNo: m['order_no'],
            palletId: m['pallet_id'],
            locationId: m['location_id'],
            inboundTime: DateTime.tryParse(m['inbound_time'] ?? ''),
            allocatedTime: DateTime.tryParse(m['allocated_time'] ?? ''),
          );
          await _dbService.insertItem(it);
          pulledRecords++;
        }
      }
    } catch (err) {
      debugPrint('Error pulling master data from MySQL: $err');
    }
    return pulledRecords;
  }

  Future<MySQLConnection> _connectMySql() async {
    try {
      final conn = await MySQLConnection.createConnection(
        host: config.host.trim().isEmpty ? '127.0.0.1' : config.host.trim(),
        port: config.port,
        userName: config.username.trim().isEmpty ? 'root' : config.username.trim(),
        password: config.password,
        databaseName: config.database.trim().isEmpty ? 'rfidwarehouse' : config.database.trim(),
        secure: false,
      );
      await conn.connect();
      return conn;
    } catch (primaryErr) {
      // Fallback kết nối bằng tài khoản rfid / 123456
      try {
        final fallbackConn = await MySQLConnection.createConnection(
          host: config.host.trim().isEmpty ? '127.0.0.1' : config.host.trim(),
          port: config.port,
          userName: 'rfid',
          password: '123456',
          databaseName: config.database.trim().isEmpty ? 'rfidwarehouse' : config.database.trim(),
          secure: false,
        );
        await fallbackConn.connect();
        return fallbackConn;
      } catch (_) {
        rethrow;
      }
    }
  }

  Future<void> _executeMySqlSyncItem(
    MySQLConnection conn,
    String tableName,
    String action,
    Map<String, dynamic> payload,
  ) async {
    switch (tableName) {
      case 'products':
        final prodId = payload['productId']?.toString() ?? 'PROD-AUTO';
        final sku = payload['sku']?.toString() ?? prodId;
        final pName = payload['productName']?.toString() ?? sku;
        final unit = payload['unit']?.toString() ?? 'Cái';
        final cat = payload['category']?.toString() ?? 'Chung';
        final desc = payload['description']?.toString() ?? '';
        await conn.execute(
          "INSERT INTO products (product_id, sku, product_name, unit, category, description) VALUES (:id, :sku, :name, :unit, :cat, :desc) ON DUPLICATE KEY UPDATE sku=VALUES(sku), product_name=VALUES(product_name), unit=VALUES(unit), category=VALUES(category), description=VALUES(description)",
          {"id": prodId, "sku": sku, "name": pName, "unit": unit, "cat": cat, "desc": desc},
        );
        break;

      case 'locations':
        final locId = payload['locationId']?.toString() ?? 'LOC-01';
        final locCode = payload['locationCode']?.toString() ?? locId;
        final zone = payload['zone']?.toString() ?? 'A';
        final shelf = payload['shelf']?.toString() ?? '01';
        final level = payload['level']?.toString() ?? '01';
        await conn.execute(
          "INSERT INTO locations (location_id, location_code, zone, shelf, level, max_pallets, current_pallets, status) VALUES (:id, :code, :zone, :shelf, :level, 2, 0, 'AVAILABLE') ON DUPLICATE KEY UPDATE zone=VALUES(zone), shelf=VALUES(shelf), level=VALUES(level)",
          {"id": locId, "code": locCode, "zone": zone, "shelf": shelf, "level": level},
        );
        break;

      case 'pallets':
        final rawPallet = payload['palletId']?.toString().trim() ?? payload['palletCode']?.toString().trim();
        final palletId = (rawPallet != null && rawPallet.isNotEmpty) ? rawPallet : 'PAL-PL-01';
        final palletCode = payload['palletCode']?.toString().trim() ?? palletId;
        final rawLoc = payload['locationId']?.toString().trim();
        final locId = (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : 'LOC-A1-01-01';
        final isMulti = payload['isMultiSku'] == true ? 1 : 0;
        final status = payload['status']?.toString() ?? 'IN_STOCK';

        await conn.execute(
          "INSERT INTO locations (location_id, location_code, zone, shelf, level, status) VALUES (:id, :code, 'A', '01', '01', 'AVAILABLE') ON DUPLICATE KEY UPDATE status=VALUES(status)",
          {"id": locId, "code": locId},
        );

        await conn.execute(
          "INSERT INTO pallets (pallet_id, pallet_code, location_id, is_multi_sku, status) VALUES (:id, :code, :loc, :multi, :status) ON DUPLICATE KEY UPDATE location_id=VALUES(location_id), status=VALUES(status)",
          {"id": palletId, "code": palletCode, "loc": locId, "multi": isMulti, "status": status},
        );
        break;

      case 'items':
        final prodId = payload['productId']?.toString() ?? 'PROD-AUTO';
        final sku = payload['sku']?.toString() ?? 'SKU-INBOUND';
        final pName = payload['productName']?.toString() ?? 'Hàng hóa';
        await conn.execute(
          "INSERT INTO products (product_id, sku, product_name, unit, category) VALUES (:id, :sku, :name, 'Cái', 'Tự Động') ON DUPLICATE KEY UPDATE product_name=VALUES(product_name)",
          {"id": prodId, "sku": sku, "name": pName},
        );

        final itemId = payload['itemId']?.toString() ?? 'ITEM-${payload['epc']}';
        final epc = payload['epc']?.toString() ?? '';
        final sn = payload['serialNumber']?.toString() ?? (epc.length > 6 ? epc.substring(epc.length - 6) : epc);
        final status = payload['status']?.toString() ?? 'IN_STOCK';
        final rawPal = payload['palletId']?.toString().trim();
        final palletId = (rawPal != null && rawPal.isNotEmpty) ? rawPal : 'PAL-PL-01';
        final rawLoc = payload['locationId']?.toString().trim();
        final locId = (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : 'LOC-A1-01-01';

        await conn.execute(
          "INSERT INTO locations (location_id, location_code, zone, shelf, level, status) VALUES (:id, :code, 'A', '01', '01', 'AVAILABLE') ON DUPLICATE KEY UPDATE status=VALUES(status)",
          {"id": locId, "code": locId},
        );

        await conn.execute(
          "INSERT INTO pallets (pallet_id, pallet_code, location_id, status) VALUES (:id, :code, :loc, 'IN_STOCK') ON DUPLICATE KEY UPDATE status=VALUES(status)",
          {"id": palletId, "code": palletId, "loc": locId},
        );

        final orderNo = payload['orderNo']?.toString();

        await conn.execute(
          "INSERT INTO items (item_id, product_id, sku, product_name, serial_number, epc, status, order_no, pallet_id, location_id, inbound_time) VALUES (:id, :prod_id, :sku, :name, :sn, :epc, :status, :order_no, :pal, :loc, NOW()) ON DUPLICATE KEY UPDATE status=VALUES(status), order_no=COALESCE(VALUES(order_no), order_no), pallet_id=VALUES(pallet_id), location_id=VALUES(location_id), inbound_time=NOW()",
          {
            "id": itemId,
            "prod_id": prodId,
            "sku": sku,
            "name": pName,
            "sn": sn,
            "epc": epc,
            "status": status,
            "order_no": orderNo,
            "pal": palletId,
            "loc": locId,
          },
        );
        break;

      case 'inbound_transactions':
        final orderNo = payload['orderNo']?.toString();
        final rawPal = payload['palletCode']?.toString().trim();
        final palletCode = (rawPal != null && rawPal.isNotEmpty) ? rawPal : 'PL-01';
        final palletId = 'PAL-$palletCode';
        final rawLoc = payload['locationId']?.toString().trim();
        final locId = (rawLoc != null && rawLoc.isNotEmpty) ? rawLoc : 'LOC-A1-01-01';
        final sku = payload['sku']?.toString() ?? 'SKU-INBOUND';
        final pName = payload['productName']?.toString() ?? 'Hàng nhập kho';
        final prodId = 'PROD-$sku';
        final user = payload['performedBy']?.toString() ?? 'Thủ kho';
        final epcs = (payload['epcs'] as List?)?.map((e) => e.toString()).toList() ?? [];

        // 1. Đảm bảo Product tồn tại
        await conn.execute(
          "INSERT INTO products (product_id, sku, product_name, unit, category) VALUES (:id, :sku, :name, 'Bộ', 'Nhập Kho') ON DUPLICATE KEY UPDATE product_name=VALUES(product_name)",
          {"id": prodId, "sku": sku, "name": pName},
        );

        // 2. Đảm bảo Location tồn tại
        await conn.execute(
          "INSERT INTO locations (location_id, location_code, zone, shelf, level, status) VALUES (:id, :code, 'A', '01', '01', 'OCCUPIED') ON DUPLICATE KEY UPDATE current_pallets=1, status='OCCUPIED'",
          {"id": locId, "code": locId},
        );

        // 3. Đảm bảo Pallet tồn tại
        await conn.execute(
          "INSERT INTO pallets (pallet_id, pallet_code, location_id, status) VALUES (:id, :code, :loc, 'IN_STOCK') ON DUPLICATE KEY UPDATE location_id=VALUES(location_id), status='IN_STOCK'",
          {"id": palletId, "code": palletCode, "loc": locId},
        );

        // 4. Cập nhật đơn nhập nếu có
        if (orderNo != null && orderNo.isNotEmpty) {
          try {
            await conn.execute(
              "UPDATE inbound_orders SET status='COMPLETED', total_received = :cnt WHERE order_no = :order_no",
              {"cnt": epcs.length, "order_no": orderNo},
            );
          } catch (_) {}
        }

        // 5. Ghi từng thẻ EPC vào items, rfid_scan_logs, inventory_transactions
        for (var i = 0; i < epcs.length; i++) {
          final epc = epcs[i];
          final itemId = 'ITEM-$epc';
          final sn = 'SN-${epc.length > 6 ? epc.substring(epc.length - 6) : epc}';

          await conn.execute(
            "INSERT INTO items (item_id, product_id, sku, product_name, serial_number, epc, status, pallet_id, location_id, inbound_time) VALUES (:id, :prod_id, :sku, :name, :sn, :epc, 'IN_STOCK', :pal, :loc, NOW()) ON DUPLICATE KEY UPDATE status='IN_STOCK', pallet_id=VALUES(pallet_id), location_id=VALUES(location_id), inbound_time=NOW()",
            {"id": itemId, "prod_id": prodId, "sku": sku, "name": pName, "sn": sn, "epc": epc, "pal": palletId, "loc": locId},
          );

          try {
            await conn.execute(
              "INSERT INTO rfid_scan_logs (device_id, epc, rssi, antenna, scan_type, result_status) VALUES ('DEV-GATE-01', :epc, '-50', '1', 'INBOUND', 'MATCH')",
              {"epc": epc},
            );
          } catch (_) {}

          try {
            final txId = 'TX-${DateTime.now().millisecondsSinceEpoch}-${i + 1}';
            await conn.execute(
              "INSERT INTO inventory_transactions (transaction_id, transaction_type, item_id, epc, to_location_id, to_pallet_id, order_ref, performed_by, note) VALUES (:tx_id, 'IN', :item_id, :epc, :to_loc, :to_pal, :order_ref, :user, 'Nhập kho thành công')",
              {
                "tx_id": txId,
                "item_id": itemId,
                "epc": epc,
                "to_loc": locId,
                "to_pal": palletId,
                "order_ref": orderNo ?? 'DIRECT-IN',
                "user": user,
              },
            );
          } catch (_) {}
        }
        break;

      case 'inbound_orders':
        final orderId = payload['inboundOrderId']?.toString() ?? '';
        final orderNo = payload['orderNo']?.toString() ?? orderId;
        final supplier = payload['sourceSupplier']?.toString() ?? 'Nhà cung cấp';
        final status = payload['status']?.toString() ?? 'NEW';
        final totalReq = (payload['totalRequired'] as num?)?.toInt() ?? 0;
        final totalRec = (payload['totalReceived'] as num?)?.toInt() ?? 0;
        final note = payload['note']?.toString() ?? '';

        await conn.execute(
          "INSERT INTO inbound_orders (inbound_order_id, order_no, source_supplier, status, total_required, total_received, note, created_at) VALUES (:id, :order_no, :supplier, :status, :req, :rec, :note, NOW()) ON DUPLICATE KEY UPDATE status=VALUES(status), total_received=VALUES(total_received)",
          {"id": orderId, "order_no": orderNo, "supplier": supplier, "status": status, "req": totalReq, "rec": totalRec, "note": note},
        );

        final details = (payload['details'] as List?) ?? [];
        for (var d in details) {
          final sku = d['sku']?.toString() ?? 'SKU-01';
          final prodId = d['productId']?.toString() ?? 'PROD-$sku';
          final pName = d['productName']?.toString() ?? sku;
          final reqQty = (d['requiredQty'] as num?)?.toInt() ?? 0;
          final recQty = (d['receivedQty'] as num?)?.toInt() ?? 0;

          await conn.execute(
            "INSERT INTO products (product_id, sku, product_name, unit, category) VALUES (:id, :sku, :name, 'Cái', 'Đơn nhập') ON DUPLICATE KEY UPDATE product_name=VALUES(product_name)",
            {"id": prodId, "sku": sku, "name": pName},
          );

          await conn.execute(
            "INSERT INTO inbound_order_details (order_id, product_id, sku, product_name, required_qty, received_qty) VALUES (:order_id, :prod_id, :sku, :name, :req, :rec)",
            {"order_id": orderId, "prod_id": prodId, "sku": sku, "name": pName, "req": reqQty, "rec": recQty},
          );
        }
        break;

      case 'outbound_orders':
        final orderId = payload['outboundOrderId']?.toString() ?? '';
        final poNo = payload['poNo']?.toString() ?? orderId;
        final customer = payload['customer']?.toString() ?? 'Khách hàng';
        final status = payload['status']?.toString() ?? 'NEW';

        await conn.execute(
          "INSERT INTO outbound_orders (outbound_order_id, po_no, customer, status, created_at) VALUES (:id, :po_no, :customer, :status, NOW()) ON DUPLICATE KEY UPDATE status=VALUES(status)",
          {"id": orderId, "po_no": poNo, "customer": customer, "status": status},
        );
        break;

      default:
        debugPrint('Unknown sync table: $tableName');
    }
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _autoSyncTimer?.cancel();
    super.dispose();
  }
}
