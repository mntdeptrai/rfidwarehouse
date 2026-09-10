import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/wms_models.dart';

/// DatabaseService thuần In-Memory (Bộ nhớ RAM) - Đã loại bỏ hoàn toàn SQLite
/// 
/// Dữ liệu vận hành thực tế được quản lý trực tiếp qua Supabase Cloud (Single Source of Truth).
/// DatabaseService đóng vai trò là một in-memory local data store siêu tốc trong RAM,
/// không tạo bất kỳ file .db nào trên ổ đĩa PC hay thiết bị tay cầm PDA.
class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  // In-Memory Storage Maps
  final Map<String, Product> _products = {};
  final Map<String, Location> _locations = {};
  final Map<String, Pallet> _pallets = {};
  final Map<String, Item> _items = {};
  final Map<String, InboundOrder> _inboundOrders = {};
  final Map<String, OutboundOrder> _outboundOrders = {};
  final Map<String, WmsUser> _users = {};
  final Map<String, String> _userPasswords = {};
  final Map<String, Customer> _customers = {};
  final Map<String, DeliveryNote> _deliveryNotes = {};
  final Map<String, InventorySession> _inventorySessions = {};
  final Map<String, String> _systemConfig = {};
  final List<Map<String, dynamic>> _syncQueue = [];
  int _nextQueueId = 1;

  Future<String> getDatabaseDirectory() async {
    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    if (isTest) return '';
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      try {
        final dir = await getApplicationSupportDirectory();
        final dbDir = Directory(p.join(dir.path, 'databases'));
        if (!dbDir.existsSync()) {
          dbDir.createSync(recursive: true);
        }
        return dbDir.path;
      } catch (e) {
        final appData = Platform.environment['APPDATA'] ?? Platform.environment['USERPROFILE'] ?? '.';
        final dbDir = Directory(p.join(appData, 'RFIDWarehouse', 'databases'));
        if (!dbDir.existsSync()) {
          dbDir.createSync(recursive: true);
        }
        return dbDir.path;
      }
    } else {
      try {
        final dir = await getApplicationDocumentsDirectory();
        return dir.path;
      } catch (_) {
        return '';
      }
    }
  }

  /// Xóa sạch triệt để toàn bộ các file SQLite vật lý cũ còn sót lại trên thiết bị (cả PDA và Desktop)
  static Future<void> wipePhysicalSqliteDatabases() async {
    if (kIsWeb || Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final List<String> dirsToClean = [];
      try {
        dirsToClean.add(await DatabaseService().getDatabaseDirectory());
      } catch (_) {}
      try {
        final appData = Platform.environment['APPDATA'];
        if (appData != null && appData.isNotEmpty) {
          dirsToClean.add(p.join(appData, 'com.example', 'uhf', 'databases'));
          dirsToClean.add(p.join(appData, 'RFIDWarehouse', 'databases'));
        }
      } catch (_) {}
      try {
        final docDir = await getApplicationDocumentsDirectory();
        dirsToClean.add(p.join(docDir.path, 'databases'));
      } catch (_) {}
      dirsToClean.add(p.join(Directory.current.path, '.dart_tool', 'sqflite_common_ffi', 'databases'));

      for (final dirPath in dirsToClean) {
        final dir = Directory(dirPath);
        if (dir.existsSync()) {
          final files = dir.listSync();
          for (final f in files) {
            if (f is File && (f.path.endsWith('.db') || f.path.endsWith('.db-wal') || f.path.endsWith('.db-shm'))) {
              try {
                f.deleteSync();
                debugPrint('✓ Đã xóa vĩnh viễn file SQLite vật lý: ${f.path}');
              } catch (e) {
                debugPrint('Lỗi khi xóa file SQLite ${f.path}: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('wipePhysicalSqliteDatabases error: $e');
    }
  }

  /// Alias tương thích ngược cho handheld
  static Future<void> wipeHandheldSqliteDatabase() async {
    await wipePhysicalSqliteDatabases();
  }

  // --- SYSTEM CONFIG ---
  Future<String?> getSystemConfig(String key) async {
    return _systemConfig[key];
  }

  Future<void> setSystemConfig(String key, String value) async {
    _systemConfig[key] = value;
  }

  // --- CLEANUP ---
  Future<void> clearAllData() async {
    _products.clear();
    _locations.clear();
    _pallets.clear();
    _items.clear();
    _inboundOrders.clear();
    _outboundOrders.clear();
    _users.clear();
    _userPasswords.clear();
    _customers.clear();
    _deliveryNotes.clear();
    _inventorySessions.clear();
    _systemConfig.clear();
    _syncQueue.clear();
  }

  // --- CHECK EXISTING EPCS ---
  Future<Set<String>> checkExistingEpcs(List<String> epcs) async {
    if (epcs.isEmpty) return {};
    final cleanSet = epcs.map((e) => e.trim().toUpperCase()).toSet();
    final matched = <String>{};
    for (final item in _items.values) {
      final epcUpper = item.epc.trim().toUpperCase();
      if (cleanSet.contains(epcUpper)) {
        matched.add(epcUpper);
      }
    }
    return matched;
  }

  // --- PRODUCTS ---
  Future<List<Product>> getProducts() async {
    return _products.values.toList();
  }

  Future<void> insertProduct(Product product) async {
    _products[product.productId] = product;
    // Map sku as well if needed
    for (final existing in _products.values.toList()) {
      if (existing.sku == product.sku && existing.productId != product.productId) {
        _products.remove(existing.productId);
      }
    }
    _products[product.productId] = product;
  }

  Future<void> insertProductsBatch(List<Product> products) async {
    for (final p in products) {
      await insertProduct(p);
    }
  }

  Future<void> insertProducts(List<Product> products) => insertProductsBatch(products);

  Future<int> deleteProduct(String productId) async {
    final clean = productId.trim();
    int count = 0;
    _products.removeWhere((id, p) {
      if (id == clean || p.sku == clean) {
        count++;
        return true;
      }
      return false;
    });
    return count;
  }

  // --- ITEMS ---
  Future<int> deleteItem(String epc) async {
    final clean = epc.trim().toUpperCase();
    int count = 0;
    _items.removeWhere((id, it) {
      if (it.epc.toUpperCase() == clean) {
        count++;
        return true;
      }
      return false;
    });
    return count;
  }

  Future<List<Item>> getItems() async {
    return _items.values.toList();
  }

  Future<void> insertItem(Item item) async {
    _items[item.itemId] = item;
  }

  Future<void> insertItems(List<Item> items) async {
    for (final it in items) {
      _items[it.itemId] = it;
    }
  }

  Future<void> updateItemLocationAndPallet(String epc, String? locationId, String? palletId, {String? status}) async {
    final clean = epc.trim().toUpperCase();
    for (final it in _items.values) {
      if (it.epc.toUpperCase() == clean) {
        it.locationId = locationId;
        it.palletId = palletId;
        if (status != null) {
          it.status = ItemStatus.values.firstWhere(
            (s) => s.code == status,
            orElse: () => it.status,
          );
        }
      }
    }
  }

  Future<void> updateItemsLocationAndPallet(List<String> epcs, String? locationId, String? palletId, {String? status}) async {
    final epcSet = epcs.map((e) => e.trim().toUpperCase()).toSet();
    for (final it in _items.values) {
      if (epcSet.contains(it.epc.toUpperCase())) {
        it.locationId = locationId;
        it.palletId = palletId;
        if (status != null) {
          it.status = ItemStatus.values.firstWhere(
            (s) => s.code == status,
            orElse: () => it.status,
          );
        }
      }
    }
  }

  Future<void> updateItemStatus(String epc, ItemStatus status) async {
    final clean = epc.trim().toUpperCase();
    for (final it in _items.values) {
      if (it.epc.toUpperCase() == clean) {
        it.status = status;
      }
    }
  }

  // --- LOCATIONS ---
  Future<List<Location>> getLocations() async {
    final list = _locations.values.toList();
    list.sort((a, b) {
      final s = a.sortOrder.compareTo(b.sortOrder);
      if (s != 0) return s;
      final z = a.zone.compareTo(b.zone);
      if (z != 0) return z;
      final sh = a.shelf.compareTo(b.shelf);
      if (sh != 0) return sh;
      final l = a.level.compareTo(b.level);
      if (l != 0) return l;
      return a.locationCode.compareTo(b.locationCode);
    });
    return list;
  }

  Future<void> insertLocation(Location l) async {
    _locations[l.locationId] = l;
  }

  Future<WarehouseFloorPlanConfig> getWarehouseLayoutConfig() async {
    try {
      final val = await getSystemConfig('warehouse_floor_plan_config');
      if (val != null && val.isNotEmpty) {
        final map = jsonDecode(val) as Map<String, dynamic>;
        return WarehouseFloorPlanConfig.fromJson(map);
      }
    } catch (e) {
      debugPrint('DatabaseService.getWarehouseLayoutConfig error: $e');
    }
    return WarehouseFloorPlanConfig.defaultConfig();
  }

  Future<void> saveWarehouseLayoutConfig(WarehouseFloorPlanConfig config) async {
    try {
      final val = jsonEncode(config.toJson());
      await setSystemConfig('warehouse_floor_plan_config', val);
    } catch (e) {
      debugPrint('DatabaseService.saveWarehouseLayoutConfig error: $e');
    }
  }

  Future<void> updateLocationStatus(String locationId, String status) async {
    final clean = locationId.trim().toUpperCase();
    final stripped = clean.startsWith('LOC-') ? clean.substring(4) : clean;
    final withLoc = clean.startsWith('LOC-') ? clean : 'LOC-$clean';
    for (final loc in _locations.values) {
      final locCode = loc.locationCode.trim().toUpperCase();
      final locId = loc.locationId.trim().toUpperCase();
      if (locId == clean || locCode == clean || locId == stripped || locCode == stripped || locId == withLoc || locCode == withLoc) {
        loc.status = status;
      }
    }
  }

  Future<void> deleteLocation(String locationIdOrCode) async {
    final clean = locationIdOrCode.trim().toUpperCase();
    _locations.removeWhere((id, loc) =>
        id.toUpperCase() == clean || loc.locationCode.toUpperCase() == clean);
  }

  Future<void> deleteAllLocations() async {
    _locations.clear();
    for (final p in _pallets.values) {
      p.locationId = null;
    }
    for (final it in _items.values) {
      it.locationId = null;
    }
  }

  // --- PALLETS ---
  Future<void> savePalletsBackup(List<Pallet> pallets) async {}

  Future<List<Pallet>> loadPalletsBackup() async => [];

  Future<List<Pallet>> getPallets() async {
    return _pallets.values.toList();
  }

  Future<void> insertPallet(Pallet pallet) async {
    _pallets[pallet.palletId] = pallet;
  }

  Future<void> updatePalletLocation(String palletId, String? locationId) async {
    final p = _pallets[palletId];
    if (p != null) {
      p.locationId = locationId;
    }
  }

  Future<void> deletePallet(String identifier) async {
    final clean = identifier.trim().toUpperCase();
    _pallets.removeWhere((id, p) =>
        id.toUpperCase() == clean ||
        p.palletCode.toUpperCase() == clean ||
        id.toUpperCase() == 'PAL-$clean');
  }

  // --- INBOUND ORDERS ---
  Future<List<InboundOrder>> getInboundOrders() async {
    return _inboundOrders.values.toList();
  }

  Future<void> insertInboundOrder(InboundOrder order) async {
    _inboundOrders[order.inboundOrderId] = order;
  }

  Future<void> updateInboundOrderStatus(String inboundOrderId, InboundOrderStatus status, {String? palletId, String? locationId}) async {
    final order = _inboundOrders[inboundOrderId];
    if (order != null) {
      order.status = status;
    }
  }

  Future<void> deleteInboundOrder(String orderId) async {
    final clean = orderId.trim();
    _inboundOrders.removeWhere((id, o) => id == clean || o.orderNo == clean);
    _items.removeWhere((id, it) => it.orderNo == clean);
  }

  // --- OUTBOUND ORDERS ---
  Future<List<OutboundOrder>> getOutboundOrders() async {
    return _outboundOrders.values.toList();
  }

  Future<void> insertOutboundOrder(OutboundOrder order) async {
    _outboundOrders[order.outboundOrderId] = order;
  }

  Future<void> updateOutboundOrderStatus(String outboundOrderId, OutboundOrderStatus status) async {
    final order = _outboundOrders[outboundOrderId];
    if (order != null) {
      order.status = status;
    }
  }

  Future<void> deleteOutboundOrder(String orderId) async {
    final clean = orderId.trim();
    _outboundOrders.removeWhere((id, o) => id == clean || o.poNo == clean);
  }

  // --- SYNC QUEUE (IN-MEMORY FOR TESTS / TEMPORARY HOLD) ---
  Future<int> enqueueSync({
    required String tableName,
    required String recordId,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final qId = _nextQueueId++;
    _syncQueue.add({
      'queue_id': qId,
      'table_name': tableName,
      'record_id': recordId,
      'action': action,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'status': 0, // PENDING
      'retry_count': 0,
    });
    return qId;
  }

  Future<void> enqueueSyncBatch(List<Map<String, dynamic>> items) async {
    if (items.isEmpty) return;
    final nowStr = DateTime.now().toIso8601String();
    for (final it in items) {
      final qId = _nextQueueId++;
      _syncQueue.add({
        'queue_id': qId,
        'table_name': it['table_name'],
        'record_id': it['record_id'],
        'action': it['action'],
        'payload': it['payload'] is String ? it['payload'] : jsonEncode(it['payload']),
        'created_at': nowStr,
        'status': 0,
        'retry_count': 0,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getPendingSyncItems({int limit = 100}) async {
    final pending = _syncQueue.where((it) => it['status'] == 0).take(limit).toList();
    return pending;
  }

  Future<int> getPendingSyncCount() async {
    return _syncQueue.where((it) => it['status'] == 0).length;
  }

  Future<void> markSyncItemSynced(int queueId) async {
    for (final it in _syncQueue) {
      if (it['queue_id'] == queueId) {
        it['status'] = 1; // SYNCED
        break;
      }
    }
  }

  Future<void> markSyncItemFailed(int queueId, String error) async {
    for (final it in _syncQueue) {
      if (it['queue_id'] == queueId) {
        it['status'] = 2; // FAILED
        it['retry_count'] = ((it['retry_count'] as int?) ?? 0) + 1;
        it['error_message'] = error;
        break;
      }
    }
  }

  Future<void> clearCompletedSyncQueue() async {
    _syncQueue.removeWhere((it) => it['status'] == 1);
  }

  // --- USERS ---
  Future<List<WmsUser>> getUsers() async {
    return _users.values.toList();
  }

  Future<void> insertUser(WmsUser user) async {
    _users[user.userId] = user;
  }

  Future<void> insertUserWithPassword(WmsUser user, String passwordHash) async {
    _users[user.userId] = user;
    _userPasswords[user.userId] = passwordHash;
    _userPasswords[user.username] = passwordHash;
  }

  Future<Map<String, dynamic>?> getUserAuth(String username) async {
    final clean = username.trim().toLowerCase();
    for (final u in _users.values) {
      if (u.username.toLowerCase() == clean || (u.email != null && u.email!.toLowerCase() == clean)) {
        final map = u.toMap();
        map['password_hash'] = _userPasswords[u.userId] ?? _userPasswords[u.username];
        return map;
      }
    }
    return null;
  }

  Future<WmsUser?> getUserById(String userId) async {
    final clean = userId.trim();
    return _users[clean];
  }

  Future<int> deleteUser(String userId) async {
    final clean = userId.trim();
    int count = 0;
    _users.removeWhere((id, u) {
      if (id == clean || u.username == clean) {
        count++;
        return true;
      }
      return false;
    });
    _userPasswords.remove(clean);
    return count;
  }

  Future<void> updateUser(WmsUser user) async {
    _users[user.userId] = user;
  }

  Future<void> updateUserPassword(String userId, String passwordHash) async {
    _userPasswords[userId] = passwordHash;
    final u = _users[userId];
    if (u != null) {
      _userPasswords[u.username] = passwordHash;
    }
  }

  // --- CUSTOMERS ---
  Future<List<Customer>> getCustomers() async {
    return _customers.values.toList();
  }

  Future<void> insertCustomer(Customer customer) async {
    _customers[customer.customerId] = customer;
  }

  Future<int> deleteCustomer(String customerId) async {
    final clean = customerId.trim();
    int count = 0;
    _customers.removeWhere((id, c) {
      if (id == clean || c.customerCode == clean) {
        count++;
        return true;
      }
      return false;
    });
    return count;
  }

  // --- DELIVERY NOTES ---
  Future<List<DeliveryNote>> getDeliveryNotes() async {
    return _deliveryNotes.values.toList();
  }

  Future<void> insertDeliveryNote(DeliveryNote note) async {
    _deliveryNotes[note.deliveryId] = note;
  }

  Future<int> deleteDeliveryNote(String deliveryId) async {
    final clean = deliveryId.trim();
    int count = 0;
    _deliveryNotes.removeWhere((id, d) {
      if (id == clean || d.deliveryNo == clean) {
        count++;
        return true;
      }
      return false;
    });
    return count;
  }

  // --- INVENTORY SESSIONS ---
  Future<List<InventorySession>> getInventorySessions() async {
    return _inventorySessions.values.toList();
  }

  Future<void> insertInventorySession(InventorySession session) async {
    _inventorySessions[session.sessionId] = session;
  }

  Future<int> deleteInventorySession(String sessionId) async {
    final clean = sessionId.trim();
    int count = 0;
    _inventorySessions.removeWhere((id, s) {
      if (id == clean || s.sessionCode == clean) {
        count++;
        return true;
      }
      return false;
    });
    return count;
  }
}
