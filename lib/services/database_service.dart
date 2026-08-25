import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/wms_models.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  factory DatabaseService() => _instance;
  DatabaseService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _initDatabase();
    return _db!;
  }

  Future<Database> _initDatabase() async {
    // Khởi tạo ffi cho môi trường desktop/test nếu không phải Android/iOS
    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final isTest = Platform.environment.containsKey('FLUTTER_TEST');
    final path = isTest ? inMemoryDatabasePath : p.join(await getDatabasesPath(), 'c72e_wms_clean_v3.db');

    debugPrint('Initializing SQLite Database (isTest=$isTest) at: $path');

    return await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) => _createTables(db),
      onUpgrade: (db, oldVersion, newVersion) => _createTables(db),
      onOpen: (db) async {
        try {
          if (!isTest) {
            await db.execute('PRAGMA journal_mode=WAL;');
            await db.execute('PRAGMA busy_timeout=5000;');
          }
        } catch (_) {}
        await _createTables(db);
      },
    );
  }

  Future<void> _createTables(Database db) async {
    debugPrint('Creating clean SQLite Database tables (No mockdata)...');

    // 1. Bảng Danh mục Sản phẩm (products)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        product_id TEXT PRIMARY KEY,
        sku TEXT NOT NULL UNIQUE,
        product_name TEXT NOT NULL,
        unit TEXT NOT NULL,
        category TEXT NOT NULL,
        description TEXT
      )
    ''');

    // 2. Bảng Vị trí kho (locations)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS locations (
        location_id TEXT PRIMARY KEY,
        location_code TEXT NOT NULL UNIQUE,
        zone TEXT NOT NULL,
        shelf TEXT NOT NULL,
        level TEXT NOT NULL,
        current_pallets INTEGER DEFAULT 0
      )
    ''');

    // 3. Bảng Pallet lưu kho (pallets)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS pallets (
        pallet_id TEXT PRIMARY KEY,
        pallet_code TEXT NOT NULL UNIQUE,
        location_id TEXT,
        inbound_time TEXT NOT NULL,
        is_multi_sku INTEGER DEFAULT 0,
        FOREIGN KEY (location_id) REFERENCES locations (location_id)
      )
    ''');

    // 4. Bảng Mặt hàng cụ thể gắn thẻ RFID Chip (items)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS items (
        item_id TEXT PRIMARY KEY,
        product_id TEXT NOT NULL,
        sku TEXT NOT NULL,
        product_name TEXT NOT NULL,
        serial_number TEXT NOT NULL,
        epc TEXT NOT NULL UNIQUE,
        status TEXT NOT NULL,
        order_no TEXT,
        pallet_id TEXT,
        location_id TEXT,
        inbound_time TEXT,
        allocated_time TEXT,
        FOREIGN KEY (product_id) REFERENCES products (product_id),
        FOREIGN KEY (pallet_id) REFERENCES pallets (pallet_id),
        FOREIGN KEY (location_id) REFERENCES locations (location_id)
      )
    ''');
    try {
      await db.execute('ALTER TABLE items ADD COLUMN order_no TEXT');
    } catch (_) {}

    // 5. Bảng Đơn Nhập kho (inbound_orders)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inbound_orders (
        inbound_order_id TEXT PRIMARY KEY,
        order_no TEXT NOT NULL UNIQUE,
        source_supplier TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 6. Bảng Chi tiết Đơn Nhập (inbound_order_details)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inbound_order_details (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        sku TEXT NOT NULL,
        product_name TEXT NOT NULL,
        required_qty INTEGER NOT NULL,
        received_qty INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (order_id) REFERENCES inbound_orders (inbound_order_id),
        FOREIGN KEY (product_id) REFERENCES products (product_id)
      )
    ''');

    // 7. Bảng PO Đơn Xuất kho (outbound_orders)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outbound_orders (
        outbound_order_id TEXT PRIMARY KEY,
        po_no TEXT NOT NULL UNIQUE,
        customer TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // 8. Bảng Chi tiết PO Đơn Xuất (outbound_order_details)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS outbound_order_details (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        sku TEXT NOT NULL,
        product_name TEXT NOT NULL,
        required_qty INTEGER NOT NULL,
        picked_qty INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (order_id) REFERENCES outbound_orders (outbound_order_id),
        FOREIGN KEY (product_id) REFERENCES products (product_id)
      )
    ''');

    // 9. Bảng Hàng Đợi Đồng Bộ (sync_queue) phục vụ Offline-first SQLite -> Supabase Cloud
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_queue (
        queue_id INTEGER PRIMARY KEY AUTOINCREMENT,
        table_name TEXT NOT NULL,
        record_id TEXT NOT NULL,
        action TEXT NOT NULL,
        payload TEXT NOT NULL,
        created_at TEXT NOT NULL,
        status INTEGER DEFAULT 0,
        retry_count INTEGER DEFAULT 0,
        error_message TEXT
      )
    ''');

    // 10. Bảng Cấu hình hệ thống (system_config)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS system_config (
        config_key TEXT PRIMARY KEY,
        config_val TEXT
      )
    ''');

    // 11. Bảng Người dùng / Nhân viên (users)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        user_id TEXT PRIMARY KEY,
        username TEXT NOT NULL UNIQUE,
        full_name TEXT NOT NULL,
        email TEXT,
        phone TEXT,
        role TEXT NOT NULL DEFAULT 'operator',
        is_active INTEGER DEFAULT 1,
        created_at TEXT
      )
    ''');

    // 12. Bảng Khách Hàng (customers)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        customer_id TEXT PRIMARY KEY,
        customer_code TEXT NOT NULL UNIQUE,
        customer_name TEXT NOT NULL,
        phone TEXT,
        email TEXT,
        address TEXT,
        tax_code TEXT,
        contact_person TEXT,
        notes TEXT,
        created_at TEXT
      )
    ''');

    // 13. Bảng Phiếu Xuất Hàng / Vận Đơn (delivery_notes)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS delivery_notes (
        delivery_id TEXT PRIMARY KEY,
        delivery_no TEXT NOT NULL UNIQUE,
        po_no TEXT,
        customer_id TEXT,
        customer_name TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'DRAFT',
        carrier TEXT,
        tracking_no TEXT,
        total_cartons INTEGER DEFAULT 0,
        total_qty INTEGER DEFAULT 0,
        created_by TEXT,
        shipped_at TEXT,
        notes TEXT,
        created_at TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers (customer_id)
      )
    ''');

    // 14. Bảng Chi tiết Phiếu Xuất Hàng (delivery_note_details)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS delivery_note_details (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        delivery_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        sku TEXT NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        carton_code TEXT,
        FOREIGN KEY (delivery_id) REFERENCES delivery_notes (delivery_id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products (product_id)
      )
    ''');

    // 15. Bảng Phiên Kiểm Kê Kho (inventory_sessions)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_sessions (
        session_id TEXT PRIMARY KEY,
        session_code TEXT NOT NULL UNIQUE,
        zone TEXT NOT NULL,
        location_code TEXT,
        started_at TEXT NOT NULL,
        completed_at TEXT,
        is_completed INTEGER DEFAULT 0,
        created_by TEXT,
        created_at TEXT
      )
    ''');

    // 16. Bảng Chi tiết Sai lệch Kiểm Kê (inventory_session_details)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventory_session_details (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        epc TEXT NOT NULL,
        sku TEXT,
        product_name TEXT,
        expected_location TEXT,
        actual_location TEXT,
        result_type TEXT NOT NULL,
        read_at TEXT,
        FOREIGN KEY (session_id) REFERENCES inventory_sessions (session_id) ON DELETE CASCADE
      )
    ''');

    // 17. B-Tree Indexes siêu tốc cho truy vấn quy mô lớn
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_items_epc ON items(epc);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_items_order_status ON items(order_no, status);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_items_sku ON items(sku);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_items_location ON items(location_id);');
  }

  /// Kiểm tra nhanh danh sách mã EPC xem đã tồn tại trong CSDL SQLite chưa (Chunked Batch Query theo B-Tree Index)
  Future<Set<String>> checkExistingEpcs(List<String> epcs) async {
    if (epcs.isEmpty) return {};
    final db = await database;
    final Set<String> existing = {};
    const int chunkSize = 500;

    for (int i = 0; i < epcs.length; i += chunkSize) {
      final end = (i + chunkSize < epcs.length) ? i + chunkSize : epcs.length;
      final chunk = epcs.sublist(i, end).map((e) => e.trim().toUpperCase()).where((e) => e.isNotEmpty).toList();
      if (chunk.isEmpty) continue;
      final placeholders = List.filled(chunk.length, '?').join(',');
      final res = await db.rawQuery(
        'SELECT epc FROM items WHERE UPPER(epc) IN ($placeholders)',
        chunk,
      );
      for (final row in res) {
        final epc = row['epc'] as String?;
        if (epc != null && epc.isNotEmpty) {
          existing.add(epc.toUpperCase());
        }
      }
    }
    return existing;
  }

  Future<String?> getSystemConfig(String key) async {
    final db = await database;
    final res = await db.query('system_config', where: 'config_key = ?', whereArgs: [key]);
    if (res.isNotEmpty) {
      return res.first['config_val'] as String?;
    }
    return null;
  }

  Future<void> setSystemConfig(String key, String val) async {
    final db = await database;
    await db.insert('system_config', {
      'config_key': key,
      'config_val': val,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('sync_queue');
    await db.delete('inventory_session_details');
    await db.delete('inventory_sessions');
    await db.delete('delivery_note_details');
    await db.delete('delivery_notes');
    await db.delete('outbound_order_details');
    await db.delete('outbound_orders');
    await db.delete('inbound_order_details');
    await db.delete('inbound_orders');
    await db.delete('items');
    await db.delete('pallets');
    await db.delete('locations');
    await db.delete('products');
    await db.delete('customers');
    await db.delete('users');
  }

  // --- CRUD QUERIES ---

  Future<List<Product>> getProducts() async {
    final db = await database;
    final maps = await db.query('products');
    return maps.map((m) => Product(
      productId: m['product_id'] as String,
      sku: m['sku'] as String,
      productName: m['product_name'] as String,
      unit: m['unit'] as String,
      category: m['category'] as String,
      description: m['description'] as String?,
    )).toList();
  }

  Future<void> insertProduct(Product p) async {
    final db = await database;
    await db.insert('products', {
      'product_id': p.productId,
      'sku': p.sku,
      'product_name': p.productName,
      'unit': p.unit,
      'category': p.category,
      'description': p.description,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> deleteProduct(String productId) async {
    final db = await database;
    return await db.delete('products', where: 'product_id = ? OR sku = ?', whereArgs: [productId, productId]);
  }

  Future<int> deleteItem(String epc) async {
    final db = await database;
    return await db.delete('items', where: 'epc = ?', whereArgs: [epc]);
  }

  Future<List<Location>> getLocations() async {
    final db = await database;
    final maps = await db.query('locations');
    return maps.map((m) => Location(
      locationId: m['location_id'] as String,
      locationCode: m['location_code'] as String,
      zone: m['zone'] as String,
      shelf: m['shelf'] as String,
      level: m['level'] as String,
      currentPallets: (m['current_pallets'] as int?) ?? 0,
    )).toList();
  }

  Future<void> insertLocation(Location l) async {
    final db = await database;
    await db.insert('locations', {
      'location_id': l.locationId,
      'location_code': l.locationCode,
      'zone': l.zone,
      'shelf': l.shelf,
      'level': l.level,
      'current_pallets': l.currentPallets,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteLocation(String locationId) async {
    final db = await database;
    await db.delete('locations', where: 'location_id = ?', whereArgs: [locationId]);
  }

  Future<List<Pallet>> getPallets() async {
    final db = await database;
    final maps = await db.query('pallets');
    return maps.map((m) => Pallet(
      palletId: m['pallet_id'] as String,
      palletCode: m['pallet_code'] as String,
      locationId: m['location_id'] as String?,
      inboundTime: DateTime.parse(m['inbound_time'] as String),
      isMultiSku: (m['is_multi_sku'] as int?) == 1,
    )).toList();
  }

  Future<void> insertPallet(Pallet pallet) async {
    final db = await database;
    await db.insert('pallets', {
      'pallet_id': pallet.palletId,
      'pallet_code': pallet.palletCode,
      'location_id': pallet.locationId,
      'inbound_time': pallet.inboundTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'is_multi_sku': pallet.isMultiSku ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updatePalletLocation(String palletId, String? locationId) async {
    final db = await database;
    await db.update(
      'pallets',
      {'location_id': locationId},
      where: 'pallet_id = ?',
      whereArgs: [palletId],
    );
  }

  Future<List<Item>> getItems() async {
    final db = await database;
    final maps = await db.query('items');
    return maps.map((m) {
      final statusStr = m['status'] as String;
      final status = ItemStatus.values.firstWhere(
        (s) => s.code == statusStr,
        orElse: () => ItemStatus.inStock,
      );
      return Item(
        itemId: m['item_id'] as String,
        productId: m['product_id'] as String,
        sku: m['sku'] as String,
        productName: m['product_name'] as String,
        serialNumber: m['serial_number'] as String,
        epc: m['epc'] as String,
        status: status,
        orderNo: m['order_no'] as String?,
        palletId: m['pallet_id'] as String?,
        locationId: m['location_id'] as String?,
        inboundTime: m['inbound_time'] != null ? DateTime.tryParse(m['inbound_time'] as String) : null,
        allocatedTime: m['allocated_time'] != null ? DateTime.tryParse(m['allocated_time'] as String) : null,
      );
    }).toList();
  }

  Future<void> insertItem(Item item) async {
    final db = await database;
    await db.insert('items', {
      'item_id': item.itemId,
      'product_id': item.productId,
      'sku': item.sku,
      'product_name': item.productName,
      'serial_number': item.serialNumber,
      'epc': item.epc,
      'status': item.status.code,
      'order_no': item.orderNo,
      'pallet_id': item.palletId,
      'location_id': item.locationId,
      'inbound_time': item.inboundTime?.toIso8601String(),
      'allocated_time': item.allocatedTime?.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateItemLocationAndPallet(String epc, String? locationId, String? palletId) async {
    final db = await database;
    await db.update(
      'items',
      {
        'location_id': locationId,
        'pallet_id': palletId,
      },
      where: 'epc = ?',
      whereArgs: [epc],
    );
  }

  Future<void> updateItemStatus(String epc, ItemStatus status) async {
    final db = await database;
    await db.update(
      'items',
      {'status': status.code},
      where: 'epc = ?',
      whereArgs: [epc],
    );
  }

  Future<List<InboundOrder>> getInboundOrders() async {
    final db = await database;
    final orderMaps = await db.query('inbound_orders');
    final List<InboundOrder> orders = [];

    for (final om in orderMaps) {
      final orderId = om['inbound_order_id'] as String;
      final detailMaps = await db.query('inbound_order_details', where: 'order_id = ?', whereArgs: [orderId]);
      final details = detailMaps.map((im) => InboundOrderDetail(
        productId: im['product_id'] as String,
        sku: im['sku'] as String,
        productName: im['product_name'] as String,
        requiredQty: im['required_qty'] as int,
        receivedQty: (im['received_qty'] as int?) ?? 0,
      )).toList();

      final statusStr = om['status'] as String;
      final status = InboundOrderStatus.values.firstWhere(
        (s) => s.code == statusStr,
        orElse: () => InboundOrderStatus.newOrder,
      );

      orders.add(InboundOrder(
        inboundOrderId: orderId,
        orderNo: om['order_no'] as String,
        sourceSupplier: om['source_supplier'] as String,
        status: status,
        createdAt: DateTime.parse(om['created_at'] as String),
        details: details,
      ));
    }
    return orders;
  }

  Future<void> insertInboundOrder(InboundOrder order) async {
    final db = await database;
    await db.insert('inbound_orders', {
      'inbound_order_id': order.inboundOrderId,
      'order_no': order.orderNo,
      'source_supplier': order.sourceSupplier,
      'status': order.status.code,
      'created_at': order.createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    for (final d in order.details) {
      await db.insert('inbound_order_details', {
        'order_id': order.inboundOrderId,
        'product_id': d.productId,
        'sku': d.sku,
        'product_name': d.productName,
        'required_qty': d.requiredQty,
        'received_qty': d.receivedQty,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> updateInboundOrderStatus(String inboundOrderId, InboundOrderStatus status, {String? palletId, String? locationId}) async {
    final db = await database;
    final values = <String, dynamic>{'status': status.code};
    await db.update('inbound_orders', values, where: 'inbound_order_id = ?', whereArgs: [inboundOrderId]);
  }

  Future<List<OutboundOrder>> getOutboundOrders() async {
    final db = await database;
    final maps = await db.query('outbound_orders');
    final List<OutboundOrder> orders = [];

    for (final m in maps) {
      final orderId = m['outbound_order_id'] as String;
      final detailMaps = await db.query('outbound_order_details', where: 'order_id = ?', whereArgs: [orderId]);
      final details = detailMaps.map((dm) => OutboundOrderDetail(
        productId: dm['product_id'] as String,
        sku: dm['sku'] as String,
        productName: dm['product_name'] as String,
        requiredQty: dm['required_qty'] as int,
        pickedQty: (dm['picked_qty'] as int?) ?? 0,
      )).toList();

      final statusStr = m['status'] as String;
      final status = OutboundOrderStatus.values.firstWhere(
        (s) => s.code == statusStr,
        orElse: () => OutboundOrderStatus.newOrder,
      );
      orders.add(OutboundOrder(
        outboundOrderId: orderId,
        poNo: m['po_no'] as String,
        customer: m['customer'] as String,
        status: status,
        createdAt: DateTime.parse(m['created_at'] as String),
        details: details,
      ));
    }
    return orders;
  }

  Future<void> insertOutboundOrder(OutboundOrder order) async {
    final db = await database;
    await db.insert('outbound_orders', {
      'outbound_order_id': order.outboundOrderId,
      'po_no': order.poNo,
      'customer': order.customer,
      'status': order.status.code,
      'created_at': order.createdAt.toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);

    for (final d in order.details) {
      await db.insert('outbound_order_details', {
        'order_id': order.outboundOrderId,
        'product_id': d.productId,
        'sku': d.sku,
        'product_name': d.productName,
        'required_qty': d.requiredQty,
        'picked_qty': d.pickedQty,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> updateOutboundOrderStatus(String outboundOrderId, OutboundOrderStatus status) async {
    final db = await database;
    await db.update('outbound_orders', {'status': status.code}, where: 'outbound_order_id = ?', whereArgs: [outboundOrderId]);
  }

  // --- SYNC QUEUE METHODS (OFFLINE-FIRST) ---

  Future<int> enqueueSync({
    required String tableName,
    required String recordId,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final db = await database;
    return await db.insert('sync_queue', {
      'table_name': tableName,
      'record_id': recordId,
      'action': action,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
      'status': 0, // PENDING
      'retry_count': 0,
    });
  }

  Future<List<Map<String, dynamic>>> getPendingSyncItems({int limit = 100}) async {
    final db = await database;
    return await db.query(
      'sync_queue',
      where: 'status = ?',
      whereArgs: [0],
      orderBy: 'queue_id ASC',
      limit: limit,
    );
  }

  Future<int> getPendingSyncCount() async {
    final db = await database;
    final res = await db.rawQuery('SELECT COUNT(*) as count FROM sync_queue WHERE status = 0');
    if (res.isNotEmpty && res.first.values.isNotEmpty) {
      return (res.first.values.first as int?) ?? 0;
    }
    return 0;
  }

  Future<void> markSyncItemSynced(int queueId) async {
    final db = await database;
    await db.update(
      'sync_queue',
      {'status': 1}, // SYNCED
      where: 'queue_id = ?',
      whereArgs: [queueId],
    );
  }

  Future<void> markSyncItemFailed(int queueId, String error) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE sync_queue 
      SET status = 2, retry_count = retry_count + 1, error_message = ?
      WHERE queue_id = ?
    ''', [error, queueId]);
  }

  Future<void> clearCompletedSyncQueue() async {
    final db = await database;
    await db.delete('sync_queue', where: 'status = ?', whereArgs: [1]);
  }

  Future<void> deleteInboundOrder(String orderId) async {
    final db = await database;
    await db.delete('inbound_order_details', where: 'order_id = ?', whereArgs: [orderId]);
    await db.delete('inbound_orders', where: 'inbound_order_id = ?', whereArgs: [orderId]);
    await db.delete('items', where: 'order_no = ?', whereArgs: [orderId]);
  }

  // --- USER QUERIES ---
  Future<List<WmsUser>> getUsers() async {
    final db = await database;
    final maps = await db.query('users');
    return maps.map((m) => WmsUser.fromMap(m)).toList();
  }

  Future<void> insertUser(WmsUser user) async {
    final db = await database;
    await db.insert('users', user.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> deleteUser(String userId) async {
    final db = await database;
    return await db.delete('users', where: 'user_id = ? OR username = ?', whereArgs: [userId, userId]);
  }

  // --- CUSTOMER QUERIES ---
  Future<List<Customer>> getCustomers() async {
    final db = await database;
    final maps = await db.query('customers');
    return maps.map((m) => Customer.fromMap(m)).toList();
  }

  Future<void> insertCustomer(Customer customer) async {
    final db = await database;
    await db.insert('customers', customer.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> deleteCustomer(String customerId) async {
    final db = await database;
    return await db.delete('customers', where: 'customer_id = ? OR customer_code = ?', whereArgs: [customerId, customerId]);
  }

  // --- DELIVERY NOTE QUERIES ---
  Future<List<DeliveryNote>> getDeliveryNotes() async {
    final db = await database;
    final maps = await db.query('delivery_notes');
    final List<DeliveryNote> list = [];
    for (final m in maps) {
      final id = m['delivery_id'] as String;
      final detMaps = await db.query('delivery_note_details', where: 'delivery_id = ?', whereArgs: [id]);
      final details = detMaps.map((d) => DeliveryNoteDetail.fromMap(d)).toList();
      list.add(DeliveryNote.fromMap(m, details: details));
    }
    return list;
  }

  Future<void> insertDeliveryNote(DeliveryNote note) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('delivery_notes', note.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.delete('delivery_note_details', where: 'delivery_id = ?', whereArgs: [note.deliveryId]);
      for (final det in note.details) {
        await txn.insert('delivery_note_details', det.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<int> deleteDeliveryNote(String deliveryId) async {
    final db = await database;
    await db.delete('delivery_note_details', where: 'delivery_id = ?', whereArgs: [deliveryId]);
    return await db.delete('delivery_notes', where: 'delivery_id = ? OR delivery_no = ?', whereArgs: [deliveryId, deliveryId]);
  }

  // --- INVENTORY SESSION QUERIES ---
  Future<List<InventorySession>> getInventorySessions() async {
    final db = await database;
    final maps = await db.query('inventory_sessions');
    final List<InventorySession> list = [];
    for (final m in maps) {
      final sId = m['session_id'] as String;
      final zoneStr = (m['zone'] as String? ?? '').trim();
      final isAllWh = zoneStr.toLowerCase().contains('toàn bộ') || zoneStr.toUpperCase() == 'ALL' || zoneStr.isEmpty;
      final detMaps = await db.query('inventory_session_details', where: 'session_id = ?', whereArgs: [sId]);
      final results = detMaps.map((d) {
        var resType = InventoryVarianceType.values.firstWhere(
          (v) => v.code == d['result_type'],
          orElse: () => InventoryVarianceType.match,
        );
        if (isAllWh && resType == InventoryVarianceType.wrongLocation) {
          resType = InventoryVarianceType.match;
        }
        return InventoryItemResult(
          epc: d['epc'] as String,
          sku: d['sku'] as String?,
          productName: d['product_name'] as String?,
          expectedLocation: d['expected_location'] as String?,
          actualLocation: d['actual_location'] as String?,
          resultType: resType,
          readAt: d['read_at'] != null ? DateTime.tryParse(d['read_at'].toString()) ?? DateTime.now() : DateTime.now(),
        );
      }).toList();

      list.add(InventorySession(
        sessionId: sId,
        sessionCode: m['session_code'] as String,
        zone: m['zone'] as String,
        locationCode: m['location_code'] as String?,
        startedAt: DateTime.tryParse(m['started_at'].toString()) ?? DateTime.now(),
        completedAt: m['completed_at'] != null ? DateTime.tryParse(m['completed_at'].toString()) : null,
        isCompleted: m['is_completed'] == 1 || m['is_completed'] == true,
        results: results,
      ));
    }
    return list;
  }

  Future<void> insertInventorySession(InventorySession session) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.insert('inventory_sessions', {
        'session_id': session.sessionId,
        'session_code': session.sessionCode,
        'zone': session.zone,
        'location_code': session.locationCode,
        'started_at': session.startedAt.toIso8601String(),
        'completed_at': session.completedAt?.toIso8601String(),
        'is_completed': session.isCompleted ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await txn.delete('inventory_session_details', where: 'session_id = ?', whereArgs: [session.sessionId]);
      for (final r in session.results) {
        await txn.insert('inventory_session_details', {
          'session_id': session.sessionId,
          'epc': r.epc,
          'sku': r.sku,
          'product_name': r.productName,
          'expected_location': r.expectedLocation,
          'actual_location': r.actualLocation,
          'result_type': r.resultType.code,
          'read_at': r.readAt.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<int> deleteInventorySession(String sessionId) async {
    final db = await database;
    await db.delete('inventory_session_details', where: 'session_id = ?', whereArgs: [sessionId]);
    return await db.delete('inventory_sessions', where: 'session_id = ?', whereArgs: [sessionId]);
  }
}
