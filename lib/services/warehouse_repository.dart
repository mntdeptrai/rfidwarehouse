import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/wms_models.dart';
import 'erp_bravo_service.dart';
import 'database_service.dart';
import 'supabase_sync_service.dart';

class WarehouseRepository extends ChangeNotifier {
  static final WarehouseRepository _instance = WarehouseRepository._internal();
  factory WarehouseRepository() => _instance;

  final DatabaseService _dbService = DatabaseService();

  Future<void>? _initFuture;

  WarehouseRepository._internal() {
    _initFuture = _loadFromSqlite();
  }

  Future<void> ensureInitialized() async {
    if (_initFuture != null) await _initFuture;
  }

  Future<void> reloadFromSqlite() async {
    await _loadFromSqlite();
  }

  Future<void> _loadFromSqlite() async {
    try {
      final dbProducts = await _dbService.getProducts();
      final dbLocations = await _dbService.getLocations();
      final dbPallets = await _dbService.getPallets();
      final dbItems = await _dbService.getItems();
      final dbInboundOrders = await _dbService.getInboundOrders();
      final dbOutboundOrders = await _dbService.getOutboundOrders();
      const bogusCommandNames = {
        'ACTION_SCAN',
        'ACTION_STOP_SCAN',
        'SCANNER_START',
        'SCANNER_STOP',
        'START_SCAN',
        'STOP_SCAN',
        'SCAN',
        'KEY_CONTROL',
        'KEY_CONTROL_DISABLED',
        'TRUE',
        'FALSE',
      };

      // Chỉ xóa dữ liệu rác do đầu đọc gửi lệnh bị ghi nhầm thành sản phẩm
      // KHÔNG xóa các mã EPC/đơn hàng nhập từ file Excel (ABCDEF..., CARTONTEST..., PRODUCT TEST...)
      bool isTestProduct(Product p) {
        final pSku = p.sku.toUpperCase();
        final pId = p.productId.toUpperCase();
        return bogusCommandNames.contains(pId) ||
            bogusCommandNames.contains(pSku);
      }

      bool isTestItem(Item i) {
        final epc = i.epc.toUpperCase();
        final sku = i.sku.toUpperCase();
        final orderNo = (i.orderNo ?? '').toUpperCase();
        // Chỉ xóa: lệnh scanner bị ghi nhầm + chip phần cứng kiểm thử cố định
        return epc == 'E28011600000000000099888' ||
            epc == 'E28032F9666D00012F50' ||
            epc == 'E2803295B8FA00017846' ||
            bogusCommandNames.contains(sku) ||
            bogusCommandNames.contains(orderNo);
      }

      for (final p in dbProducts) {
        if (isTestProduct(p)) {
          await _dbService.deleteProduct(p.productId);
        }
      }
      for (final i in dbItems) {
        if (isTestItem(i)) {
          await _dbService.deleteItem(i.epc);
        }
      }

      final cleanProducts = await _dbService.getProducts();
      final cleanItems = await _dbService.getItems();
      final dbUsers = await _dbService.getUsers();
      final dbCustomers = await _dbService.getCustomers();
      final dbDeliveryNotes = await _dbService.getDeliveryNotes();
      final dbInventorySessions = await _dbService.getInventorySessions();

      _products.clear();
      _products.addAll(cleanProducts.where((p) => !isTestProduct(p)));

      _locations.clear();
      _locations.addAll(dbLocations);

      _pallets.clear();
      _pallets.addAll(dbPallets);

      _items.clear();
      _items.addAll(cleanItems.where((i) => !isTestItem(i)));
      for (final p in _pallets) {
        p.itemIds.clear();
        p.itemIds.addAll(_items.where((i) => i.palletId == p.palletId).map((i) => i.itemId));
      }

      _inboundOrders.clear();
      _inboundOrders.addAll(dbInboundOrders);

      _outboundOrders.clear();
      _outboundOrders.addAll(dbOutboundOrders);

      // Tự động dọn dẹp thẻ mồ côi chưa nhập kho không thuộc bất kỳ đơn nhập nào
      final activeInboundOrderNos = _inboundOrders.map((o) => o.orderNo.toUpperCase()).toSet();
      final orphanPending = _items.where((i) => i.status == ItemStatus.pendingInbound && (i.orderNo == null || !activeInboundOrderNos.contains(i.orderNo!.toUpperCase()))).toList();
      for (final orphan in orphanPending) {
        _items.remove(orphan);
        await _dbService.deleteItem(orphan.epc);
      }

      _users.clear();
      _users.addAll(dbUsers);

      _customers.clear();
      _customers.addAll(dbCustomers);

      _deliveryNotes.clear();
      _deliveryNotes.addAll(dbDeliveryNotes);

      _inventorySessions.clear();
      _inventorySessions.addAll(dbInventorySessions);

      notifyListeners();
    } catch (e) {
      debugPrint('WarehouseRepository: SQLite load error: $e');
    }
  }

  Future<void> refreshFromDatabase() => _loadFromSqlite();

  /// Kiểm tra siêu tốc danh sách EPC đã tồn tại (kết hợp RAM HashSet O(1) và SQLite B-Tree Index)
  Future<Set<String>> checkExistingEpcs(List<String> epcs) async {
    if (epcs.isEmpty) return {};
    final cleanEpcs = epcs.map((e) => e.trim().toUpperCase()).where((e) => e.isNotEmpty).toList();

    // 1. So khớp siêu tốc trong RAM (Hash Set O(1))
    final inMemorySet = _items.map((i) => i.epc.toUpperCase()).toSet();
    final Set<String> matched = cleanEpcs.where((e) => inMemorySet.contains(e)).toSet();

    // 2. So khớp trực tiếp CSDL SQLite qua B-Tree Index
    final dbMatched = await _dbService.checkExistingEpcs(cleanEpcs);
    matched.addAll(dbMatched);

    return matched;
  }

  Future<void> deleteInboundOrder(String orderId) async {
    final cleanId = orderId.trim();
    final targetOrder = _inboundOrders.where((o) => o.inboundOrderId == cleanId || o.orderNo == cleanId).firstOrNull;
    final orderNo = targetOrder?.orderNo ?? cleanId;
    final orderIdVal = targetOrder?.inboundOrderId ?? cleanId;

    await _dbService.deleteInboundOrder(orderIdVal);
    _inboundOrders.removeWhere((o) => o.inboundOrderId == orderIdVal || o.orderNo == orderNo);
    _items.removeWhere((i) => i.orderNo == orderNo || i.orderNo == orderIdVal || i.orderNo == cleanId);

    await _syncDirectOrQueue(
      tableName: 'inbound_orders',
      recordId: orderIdVal,
      action: 'DELETE',
      payload: {'orderId': orderIdVal},
    );

    notifyListeners();
  }

  Future<void> deleteProduct(String productId) async {
    final cleanId = productId.trim();
    await _dbService.deleteProduct(cleanId);
    _products.removeWhere((p) => p.productId == cleanId || p.sku == cleanId);
    _items.removeWhere((i) => i.productId == cleanId || i.sku == cleanId);

    await _syncDirectOrQueue(
      tableName: 'products',
      recordId: cleanId,
      action: 'DELETE',
      payload: {'productId': cleanId},
    );

    notifyListeners();
  }

  Future<void> clearAllData({bool alsoClearCloud = true}) async {
    await _dbService.clearAllData();
    _products.clear();
    _locations.clear();
    _pallets.clear();
    _items.clear();
    _inboundOrders.clear();
    _outboundOrders.clear();
    _pickingPlans.clear();
    _inventorySessions.clear();
    _transactions.clear();
    _users.clear();
    _customers.clear();
    _deliveryNotes.clear();

    if (alsoClearCloud) {
      await SupabaseSyncService().clearAllSupabaseData();
    }

    notifyListeners();
  }

  /// Sinh mã Barcode 128 chuẩn Hex (chỉ chứa các ký tự 0-9 và A-F)
  String generateHexBarcode128({int length = 16}) {
    const chars = '0123456789ABCDEF';
    final rnd = Random();
    final now = DateTime.now();
    // 8 ký tự hex từ timestamp mili-giây (0-9, A-F)
    final timeHex = (now.millisecondsSinceEpoch % 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase();
    final remaining = (length > 8) ? length - 8 : 4;
    final randomHex = List.generate(remaining, (_) => chars[rnd.nextInt(chars.length)]).join();
    return '$timeHex$randomHex'.toUpperCase();
  }

  String generateUniqueEpc({String? sku, int sequence = 1}) {
    final existingEpcs = _items.map((i) => i.epc.toUpperCase()).toSet();
    final timeHex = (DateTime.now().millisecondsSinceEpoch % 0xFFFFFFFF).toRadixString(16).padLeft(8, '0').toUpperCase();
    final seqHex = (sequence % 0xFFFF).toRadixString(16).padLeft(4, '0').toUpperCase();
    final rndHex = (Random().nextInt(0xFFFF)).toRadixString(16).padLeft(4, '0').toUpperCase();

    String epcCandidate = 'E280$timeHex$seqHex$rndHex'.toUpperCase();
    while (existingEpcs.contains(epcCandidate)) {
      final extraRnd = Random().nextInt(0xFFFF).toRadixString(16).padLeft(4, '0').toUpperCase();
      epcCandidate = 'E280$timeHex$seqHex$extraRnd'.toUpperCase();
    }
    return epcCandidate;
  }

  List<Item> getItemsByOrderNo(String orderNo) {
    final cleanNo = orderNo.trim().toUpperCase();
    final order = _inboundOrders.where((o) => o.orderNo.trim().toUpperCase() == cleanNo || o.inboundOrderId.trim().toUpperCase() == cleanNo).firstOrNull;
    return _items.where((i) {
      if (i.orderNo == null) return false;
      final itNo = i.orderNo!.trim().toUpperCase();
      if (itNo == cleanNo) return true;
      if (order != null && (itNo == order.orderNo.trim().toUpperCase() || itNo == order.inboundOrderId.trim().toUpperCase())) return true;
      return false;
    }).toList();
  }

  Future<List<Item>> addInboundOrder(InboundOrder order, {bool autoGenerateEpcs = true}) async {
    await _dbService.insertInboundOrder(order);
    _inboundOrders.add(order);
    await _syncDirectOrQueue(
      tableName: 'inbound_orders',
      recordId: order.inboundOrderId,
      action: 'INSERT',
      payload: {
        'inboundOrderId': order.inboundOrderId,
        'orderNo': order.orderNo,
        'sourceSupplier': order.sourceSupplier,
        'status': order.status.code,
        'createdAt': order.createdAt.toIso8601String(),
        'details': order.details.map((d) => {
          'productId': d.productId,
          'sku': d.sku,
          'productName': d.productName,
          'requiredQty': d.requiredQty,
          'receivedQty': d.receivedQty,
        }).toList(),
      },
    );

    final List<Item> generatedItems = [];
    if (autoGenerateEpcs) {
      int globalSeq = 1;
      final now = DateTime.now();
      for (var detail in order.details) {
        for (int i = 0; i < detail.requiredQty; i++) {
          final epc = generateUniqueEpc(sku: detail.sku, sequence: globalSeq++);
          final item = Item(
            itemId: 'ITEM-${now.millisecondsSinceEpoch}-$globalSeq',
            productId: detail.productId,
            sku: detail.sku,
            productName: detail.productName,
            serialNumber: 'SN-${detail.sku}-${now.millisecondsSinceEpoch.toRadixString(16).toUpperCase()}-$globalSeq',
            epc: epc,
            status: ItemStatus.pendingInbound,
            orderNo: order.orderNo,
            palletId: null,
            locationId: null,
            inboundTime: null,
          );
          generatedItems.add(item);
          _items.add(item);
          await _dbService.insertItem(item);
          await _syncDirectOrQueue(
            tableName: 'items',
            recordId: item.itemId,
            action: 'INSERT',
            payload: {
              'itemId': item.itemId,
              'productId': item.productId,
              'sku': item.sku,
              'productName': item.productName,
              'serialNumber': item.serialNumber,
              'epc': item.epc,
              'status': item.status.code,
              'orderNo': item.orderNo,
              'palletId': item.palletId,
              'locationId': item.locationId,
              'inboundTime': item.inboundTime?.toIso8601String(),
            },
          );
        }
      }
    }

    _triggerBackgroundSync();
    notifyListeners();
    return generatedItems;
  }

  Future<List<Item>> batchImportInboundOrders(List<InboundOrder> orders) async {
    final List<Item> allGeneratedItems = [];
    for (var order in orders) {
      final items = await addInboundOrder(order, autoGenerateEpcs: true);
      allGeneratedItems.addAll(items);
    }
    return allGeneratedItems;
  }

  Future<void> insertDirectItem(Item item) async {
    _items.removeWhere((i) => i.epc == item.epc);
    _items.add(item);
    await _dbService.insertItem(item);
    await _syncDirectOrQueue(
      tableName: 'items',
      recordId: item.itemId,
      action: 'INSERT',
      payload: {
        'itemId': item.itemId,
        'productId': item.productId,
        'sku': item.sku,
        'productName': item.productName,
        'serialNumber': item.serialNumber,
        'epc': item.epc,
        'status': item.status.code,
        'orderNo': item.orderNo,
        'palletId': item.palletId,
        'locationId': item.locationId,
        'inboundTime': item.inboundTime?.toIso8601String(),
      },
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> addOutboundOrder(OutboundOrder order) async {
    await _dbService.insertOutboundOrder(order);
    _outboundOrders.add(order);
    await _syncDirectOrQueue(
      tableName: 'outbound_orders',
      recordId: order.outboundOrderId,
      action: 'INSERT',
      payload: {
        'outboundOrderId': order.outboundOrderId,
        'poNo': order.poNo,
        'customer': order.customer,
        'status': order.status.code,
        'createdAt': order.createdAt.toIso8601String(),
        'details': order.details.map((d) => {
          'productId': d.productId,
          'sku': d.sku,
          'productName': d.productName,
          'requiredQty': d.requiredQty,
          'pickedQty': d.pickedQty,
        }).toList(),
      },
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> addItem(Item item) async {
    await _dbService.insertItem(item);
    _items.add(item);
    notifyListeners();
  }

  Future<void> addProduct(Product product) async {
    await _dbService.insertProduct(product);
    _products.add(product);
    await _syncDirectOrQueue(
      tableName: 'products',
      recordId: product.productId,
      action: 'INSERT',
      payload: {
        'productId': product.productId,
        'sku': product.sku,
        'productName': product.productName,
        'unit': product.unit,
        'category': product.category,
        'description': product.description,
      },
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> addLocation(Location location) async {
    await _dbService.insertLocation(location);
    _locations.add(location);
    await _syncDirectOrQueue(
      tableName: 'locations',
      recordId: location.locationId,
      action: 'INSERT',
      payload: {
        'locationId': location.locationId,
        'locationCode': location.locationCode,
        'zone': location.zone,
        'shelf': location.shelf,
        'level': location.level,
      },
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> _syncDirectOrQueue({
    required String tableName,
    required String recordId,
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    try {
      await SupabaseSyncService().syncDirectOrQueue(
        tableName: tableName,
        recordId: recordId,
        action: action,
        payload: payload,
      );
    } catch (_) {
      await _dbService.enqueueSync(
        tableName: tableName,
        recordId: recordId,
        action: action,
        payload: payload,
      );
    }
  }

  void _triggerBackgroundSync() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final supabaseSync = SupabaseSyncService();
      if (supabaseSync.config.isAutoSync) {
        supabaseSync.syncNow();
      }
    } catch (_) {}
  }

  final List<Product> _products = [];
  final List<Location> _locations = [];
  final List<Pallet> _pallets = [];
  final List<Item> _items = [];
  final List<InboundOrder> _inboundOrders = [];
  final List<OutboundOrder> _outboundOrders = [];
  final List<PickingPlan> _pickingPlans = [];
  final List<InventorySession> _inventorySessions = [];
  final List<InventoryTransaction> _transactions = [];
  final List<RfidDevice> _devices = [];
  final List<WmsUser> _users = [];
  final List<Customer> _customers = [];
  final List<DeliveryNote> _deliveryNotes = [];

  List<Product> get products => List.unmodifiable(_products);
  List<Location> get locations => List.unmodifiable(_locations);
  List<Pallet> get pallets => List.unmodifiable(_pallets);
  List<Item> get items => List.unmodifiable(_items);
  List<InboundOrder> get inboundOrders => List.unmodifiable(_inboundOrders);
  List<OutboundOrder> get outboundOrders => List.unmodifiable(_outboundOrders);
  List<PickingPlan> get pickingPlans => List.unmodifiable(_pickingPlans);
  List<InventorySession> get inventorySessions => List.unmodifiable(_inventorySessions);
  List<InventoryTransaction> get transactions => List.unmodifiable(_transactions);
  List<RfidDevice> get devices => List.unmodifiable(_devices);
  List<WmsUser> get users => List.unmodifiable(_users);
  List<Customer> get customers => List.unmodifiable(_customers);
  List<DeliveryNote> get deliveryNotes => List.unmodifiable(_deliveryNotes);

  Future<void> addCustomer(Customer customer) async {
    await _dbService.insertCustomer(customer);
    _customers.removeWhere((c) => c.customerId == customer.customerId || c.customerCode == customer.customerCode);
    _customers.add(customer);
    await _syncDirectOrQueue(
      tableName: 'customers',
      recordId: customer.customerId,
      action: 'INSERT',
      payload: {
        'customerId': customer.customerId,
        'customerCode': customer.customerCode,
        'customerName': customer.customerName,
        'phone': customer.phone,
        'email': customer.email,
        'address': customer.address,
        'taxCode': customer.taxCode,
        'contactPerson': customer.contactPerson,
        'notes': customer.notes,
      },
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> deleteCustomer(String customerId) async {
    final cleanId = customerId.trim();
    await _dbService.deleteCustomer(cleanId);
    _customers.removeWhere((c) => c.customerId == cleanId || c.customerCode == cleanId);
    await _syncDirectOrQueue(
      tableName: 'customers',
      recordId: cleanId,
      action: 'DELETE',
      payload: {'customerId': cleanId},
    );
    notifyListeners();
  }

  Future<void> addDeliveryNote(DeliveryNote note) async {
    await _dbService.insertDeliveryNote(note);
    _deliveryNotes.removeWhere((d) => d.deliveryId == note.deliveryId || d.deliveryNo == note.deliveryNo);
    _deliveryNotes.add(note);
    await _syncDirectOrQueue(
      tableName: 'delivery_notes',
      recordId: note.deliveryId,
      action: 'INSERT',
      payload: {
        'deliveryId': note.deliveryId,
        'deliveryNo': note.deliveryNo,
        'poNo': note.poNo,
        'customerId': note.customerId,
        'customerName': note.customerName,
        'status': note.status,
        'carrier': note.carrier,
        'trackingNo': note.trackingNo,
        'totalCartons': note.totalCartons,
        'totalQty': note.totalQty,
        'createdBy': note.createdBy,
        'shippedAt': note.shippedAt?.toIso8601String(),
        'notes': note.notes,
      },
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> deleteDeliveryNote(String deliveryId) async {
    final cleanId = deliveryId.trim();
    await _dbService.deleteDeliveryNote(cleanId);
    _deliveryNotes.removeWhere((d) => d.deliveryId == cleanId || d.deliveryNo == cleanId);
    await _syncDirectOrQueue(
      tableName: 'delivery_notes',
      recordId: cleanId,
      action: 'DELETE',
      payload: {'deliveryId': cleanId},
    );
    notifyListeners();
  }

  Future<void> saveInventorySession(InventorySession session) async {
    await _dbService.insertInventorySession(session);
    _inventorySessions.removeWhere((s) => s.sessionId == session.sessionId || s.sessionCode == session.sessionCode);
    _inventorySessions.add(session);
    await _syncDirectOrQueue(
      tableName: 'inventory_sessions',
      recordId: session.sessionId,
      action: 'INSERT',
      payload: {
        'sessionId': session.sessionId,
        'sessionCode': session.sessionCode,
        'zone': session.zone,
        'locationCode': session.locationCode,
        'startedAt': session.startedAt.toIso8601String(),
        'completedAt': session.completedAt?.toIso8601String(),
        'isCompleted': session.isCompleted,
      },
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> deleteInventorySession(String sessionId) async {
    final cleanId = sessionId.trim();
    await _dbService.deleteInventorySession(cleanId);
    _inventorySessions.removeWhere((s) => s.sessionId == cleanId || s.sessionCode == cleanId);
    await _syncDirectOrQueue(
      tableName: 'inventory_sessions',
      recordId: cleanId,
      action: 'DELETE',
      payload: {'sessionId': cleanId},
    );
    notifyListeners();
  }

  Future<void> addUser(WmsUser user) async {
    await _dbService.insertUser(user);
    _users.removeWhere((u) => u.userId == user.userId);
    _users.add(user);
    await _syncDirectOrQueue(
      tableName: 'users',
      recordId: user.userId,
      action: 'INSERT',
      payload: {
        'userId': user.userId,
        'username': user.username,
        'fullName': user.fullName,
        'email': user.email,
        'phone': user.phone,
        'role': user.role,
        'isActive': user.isActive,
      },
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> deleteUser(String userId) async {
    final cleanId = userId.trim();
    await _dbService.deleteUser(cleanId);
    _users.removeWhere((u) => u.userId == cleanId || u.username == cleanId);
    await _syncDirectOrQueue(
      tableName: 'users',
      recordId: cleanId,
      action: 'DELETE',
      payload: {'userId': cleanId},
    );
    notifyListeners();
  }

  List<Item> generateItemsForInbound(InboundOrder order) {
    final existing = _items.where((i) => i.orderNo == order.orderNo).toList();
    if (existing.isNotEmpty) return existing;

    final List<Item> newItems = [];
    int counter = _items.length + 1000;

    for (var detail in order.details) {
      for (int i = 0; i < detail.requiredQty; i++) {
        counter++;
        final epc = generateUniqueEpc(sku: detail.sku, sequence: counter);
        final item = Item(
          itemId: 'ITEM-$counter',
          productId: detail.productId,
          sku: detail.sku,
          productName: detail.productName,
          serialNumber: 'SN-${detail.sku}-$counter',
          epc: epc,
          status: ItemStatus.pendingInbound,
          orderNo: order.orderNo,
        );
        newItems.add(item);
      }
    }
    return newItems;
  }

  Pallet createOrAssignPallet({
    required String palletCode,
    String? locationId,
    required List<Item> newItems,
  }) {
    Pallet? pallet = _pallets.firstWhere(
      (p) => p.palletCode.toUpperCase() == palletCode.toUpperCase(),
      orElse: () {
        final newP = Pallet(
          palletId: 'PAL-${palletCode.toUpperCase()}-${DateTime.now().microsecondsSinceEpoch}',
          palletCode: palletCode.toUpperCase(),
          locationId: locationId,
          inboundTime: DateTime.now(),
          isMultiSku: newItems.map((e) => e.sku).toSet().length > 1,
        );
        _pallets.add(newP);
        return newP;
      },
    );

    pallet.locationId = locationId;
    for (var item in newItems) {
      item.palletId = pallet.palletId;
      item.locationId = locationId;
      final existing = _items.where((it) => it.epc == item.epc).firstOrNull;
      if (existing != null) {
        existing.palletId = pallet.palletId;
        existing.locationId = locationId;
        existing.status = item.status;
      } else {
        _items.add(item);
      }
      if (!pallet.itemIds.contains(item.itemId)) {
        pallet.itemIds.add(item.itemId);
      }
      _dbService.insertItem(item);
    }

    _dbService.insertPallet(pallet);

    notifyListeners();
    return pallet;
  }

  GateVerificationResult verifyGateInbound({
    required String orderNo,
    required List<String> scannedEpcs,
  }) {
    final order = _inboundOrders.firstWhere((o) => o.orderNo == orderNo);
    final uniqueEpcs = scannedEpcs.toSet().toList();

    final Map<String, int> actualSkuCounts = {};
    final List<String> unexpectedEpcs = [];

    for (var epc in uniqueEpcs) {
      final item = _items.firstWhere(
        (it) => it.epc == epc,
        orElse: () => Item(
          itemId: 'UNKNOWN',
          productId: '',
          sku: 'UNKNOWN',
          productName: 'Thẻ chưa khai báo',
          serialNumber: '',
          epc: epc,
        ),
      );

      if (item.sku == 'UNKNOWN') {
        unexpectedEpcs.add(epc);
      } else {
        actualSkuCounts[item.sku] = (actualSkuCounts[item.sku] ?? 0) + 1;
      }
    }

    final List<SkuVerificationBreakdown> breakdowns = [];
    bool allMatched = true;

    for (var detail in order.details) {
      final actualQty = actualSkuCounts[detail.sku] ?? 0;
      final isMatch = actualQty == detail.requiredQty;
      if (!isMatch) allMatched = false;

      breakdowns.add(
        SkuVerificationBreakdown(
          sku: detail.sku,
          productName: detail.productName,
          requiredQty: detail.requiredQty,
          actualQty: actualQty,
          isMatched: isMatch,
        ),
      );
    }

    if (unexpectedEpcs.isNotEmpty) allMatched = false;

    int totalReq = order.details.fold(0, (sum, d) => sum + d.requiredQty);
    int totalAct = uniqueEpcs.length;

    return GateVerificationResult(
      isPass: allMatched,
      mode: GateMode.inbound,
      documentNo: orderNo,
      totalRequiredQty: totalReq,
      totalActualQty: totalAct,
      skuBreakdowns: breakdowns,
      unexpectedEpcs: unexpectedEpcs,
      missingEpcs: [],
      verifiedAt: DateTime.now(),
    );
  }

  bool confirmInboundCompletion({
    required String orderNo,
    required String palletCode,
    required String locationId,
    required String performedBy,
  }) {
    final order = _inboundOrders.firstWhere((o) => o.orderNo == orderNo);
    final pallet = _pallets.firstWhere((p) => p.palletCode == palletCode);
    final location = _locations.firstWhere((l) => l.locationId == locationId);

    for (var itemId in pallet.itemIds) {
      final item = _items.firstWhere((it) => it.itemId == itemId);
      item.status = ItemStatus.inStock;
      item.inboundTime = DateTime.now();
      item.locationId = locationId;
      _dbService.updateItemLocationAndPallet(item.epc, locationId, pallet.palletId);
      _dbService.updateItemStatus(item.epc, ItemStatus.inStock);
    }

    order.status = InboundOrderStatus.completed;
    _dbService.updateInboundOrderStatus(order.inboundOrderId, InboundOrderStatus.completed, locationId: locationId, palletId: pallet.palletId);
    for (var d in order.details) {
      d.receivedQty = d.requiredQty;
    }

    pallet.locationId = locationId;
    _dbService.updatePalletLocation(pallet.palletId, locationId);
    location.currentPallets++;

    for (var d in order.details) {
      _transactions.insert(
        0,
        InventoryTransaction(
          transactionId: 'TX-${DateTime.now().millisecondsSinceEpoch}-${d.sku}',
          type: TransactionType.inbound,
          documentNo: orderNo,
          sku: d.sku,
          productName: d.productName,
          quantity: d.requiredQty,
          toLocation: location.locationCode,
          palletCode: palletCode,
          performedBy: performedBy,
          timestamp: DateTime.now(),
          notes: 'Nhập kho thành công, Gate INBOUND PASS',
        ),
      );
    }

    ErpBravoService().pushInboundCompleted(orderNo, pallet.itemIds.length);

    _syncDirectOrQueue(
      tableName: 'inbound_transactions',
      recordId: orderNo,
      action: 'INBOUND_GATE_CONFIRM',
      payload: {
        'orderNo': orderNo,
        'palletCode': palletCode,
        'locationId': locationId,
        'performedBy': performedBy,
        'itemCount': pallet.itemIds.length,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _triggerBackgroundSync();

    notifyListeners();
    return true;
  }

  Future<int> confirmGateReceiveToWaitingPutaway({
    required String orderNo,
    required List<String> scannedEpcs,
    String? cartonCode,
    String performedBy = 'Cổng RFID Gate',
  }) async {
    final cleanOrderNo = orderNo.trim().toUpperCase();
    final uniqueEpcs = scannedEpcs.toSet().toList();
    final now = DateTime.now();

    // Sinh mã Barcode 128 chuẩn Hex (A-F và 0-9) nếu chưa có mã thùng cụ thể
    final effectiveCartonCode = (cartonCode != null && cartonCode.trim().isNotEmpty)
        ? cartonCode.trim().toUpperCase()
        : generateHexBarcode128();

    final order = _inboundOrders.where((o) =>
      o.orderNo.trim().toUpperCase() == cleanOrderNo ||
      o.inboundOrderId.trim().toUpperCase() == cleanOrderNo
    ).firstOrNull;

    final matchedItems = _items.where((it) {
      if (uniqueEpcs.contains(it.epc)) return true;
      if (it.orderNo != null && it.orderNo!.trim().toUpperCase() == cleanOrderNo) return true;
      if (it.palletId != null && it.palletId!.trim().toUpperCase() == cleanOrderNo) return true;
      return false;
    }).toList();

    for (var it in matchedItems) {
      it.status = ItemStatus.waitingPutaway;
      // Gán mã thùng Barcode 128 vào palletId (hoặc giữ mã thùng đã khai báo trước đó nếu có)
      it.palletId = (cartonCode != null && cartonCode.trim().isNotEmpty)
          ? effectiveCartonCode
          : (it.palletId != null && it.palletId!.trim().isNotEmpty ? it.palletId : effectiveCartonCode);
      it.locationId = null;
      it.inboundTime = now;
      if (it.orderNo == null || it.orderNo!.isEmpty) {
        it.orderNo = cleanOrderNo;
      }
      await _dbService.insertItem(it);
      await _syncDirectOrQueue(
        tableName: 'items',
        recordId: it.itemId,
        action: 'UPDATE',
        payload: {
          'itemId': it.itemId,
          'status': ItemStatus.waitingPutaway.code,
          'locationId': null,
          'palletId': it.palletId,
          'orderNo': it.orderNo,
          'inboundTime': now.toIso8601String(),
        },
      );
    }

    if (order != null) {
      order.status = InboundOrderStatus.waitingPutaway;
      for (var d in order.details) {
        d.receivedQty = d.requiredQty;
      }
      await _dbService.updateInboundOrderStatus(order.inboundOrderId, InboundOrderStatus.waitingPutaway);
      await _syncDirectOrQueue(
        tableName: 'inbound_orders',
        recordId: order.inboundOrderId,
        action: 'UPDATE',
        payload: {
          'inboundOrderId': order.inboundOrderId,
          'status': InboundOrderStatus.waitingPutaway.code,
          'updatedAt': now.toIso8601String(),
        },
      );
    }

    await _syncDirectOrQueue(
      tableName: 'inbound_transactions',
      recordId: cleanOrderNo,
      action: 'GATE_RECEIVE_WAITING_PUTAWAY',
      payload: {
        'orderNo': cleanOrderNo,
        'cartonCode': effectiveCartonCode,
        'itemCount': matchedItems.length,
        'performedBy': performedBy,
        'timestamp': now.toIso8601String(),
      },
    );

    _triggerBackgroundSync();
    notifyListeners();
    return matchedItems.length;
  }

  Future<int> confirmPdaPutawayByCarton({
    required String cartonOrOrderBarcode,
    required String locationId,
    String performedBy = 'Thủ kho PDA',
  }) async {
    final cleanBarcode = cartonOrOrderBarcode.trim().toUpperCase();
    const ignoredCommands = {
      'ACTION_SCAN',
      'ACTION_STOP_SCAN',
      'SCANNER_START',
      'SCANNER_STOP',
      'START_SCAN',
      'STOP_SCAN',
      'SCAN',
      'KEY_CONTROL',
      'KEY_CONTROL_DISABLED',
      'TRUE',
      'FALSE',
    };
    if (ignoredCommands.contains(cleanBarcode)) return 0;
    final now = DateTime.now();

    final loc = _locations.where((l) =>
      l.locationId.toUpperCase() == locationId.toUpperCase() ||
      l.locationCode.toUpperCase() == locationId.toUpperCase()
    ).firstOrNull ?? Location(
      locationId: locationId,
      locationCode: locationId,
      zone: 'Khu vực chung',
      shelf: 'Kệ',
      level: 'Tầng 1',
    );

    var matchedItems = _items.where((it) {
      if (it.orderNo != null && it.orderNo!.trim().toUpperCase() == cleanBarcode) return true;
      if (it.palletId != null && it.palletId!.trim().toUpperCase() == cleanBarcode) return true;
      if (it.sku.trim().toUpperCase() == cleanBarcode) return true;
      if (it.epc.trim().toUpperCase() == cleanBarcode || it.serialNumber.trim().toUpperCase() == cleanBarcode) return true;

      final itSkuNorm = it.sku.toUpperCase().replaceAll(RegExp(r'0+'), '0');
      final cBNorm = cleanBarcode.toUpperCase().replaceAll(RegExp(r'0+'), '0');
      if (itSkuNorm == cBNorm) return true;

      return false;
    }).toList();

    // Nếu không khớp trực tiếp, tìm theo InboundOrder tương ứng
    if (matchedItems.isEmpty) {
      final matchedOrder = _inboundOrders.where((o) =>
        o.orderNo.trim().toUpperCase() == cleanBarcode ||
        o.inboundOrderId.trim().toUpperCase() == cleanBarcode
      ).firstOrNull;
      if (matchedOrder != null) {
        matchedItems = _items.where((it) =>
          it.orderNo != null &&
          (it.orderNo!.trim().toUpperCase() == matchedOrder.orderNo.trim().toUpperCase() ||
           it.orderNo!.trim().toUpperCase() == matchedOrder.inboundOrderId.trim().toUpperCase())
        ).toList();
      }
    }

    if (matchedItems.isEmpty) {
      return 0;
    }

    for (var it in matchedItems) {
      final oldLoc = it.locationId ?? 'LOC-GATE-IN';
      it.status = ItemStatus.inStock;
      it.locationId = loc.locationId;
      it.inboundTime ??= now;

      await _dbService.insertItem(it);
      await _dbService.updateItemLocationAndPallet(it.epc, loc.locationId, it.palletId);
      await _dbService.updateItemStatus(it.epc, ItemStatus.inStock);

      await _syncDirectOrQueue(
        tableName: 'items',
        recordId: it.itemId,
        action: 'UPDATE',
        payload: {
          'item_id': it.itemId,
          'status': ItemStatus.inStock.code,
          'location_id': loc.locationId,
          'pallet_id': it.palletId,
          'updated_at': now.toIso8601String(),
        },
      );

      _transactions.insert(
        0,
        InventoryTransaction(
          transactionId: 'TX-PUTAWAY-${now.millisecondsSinceEpoch}-${it.sku}',
          type: TransactionType.movement,
          documentNo: it.orderNo ?? cleanBarcode,
          sku: it.sku,
          productName: it.productName,
          quantity: 1,
          fromLocation: oldLoc,
          toLocation: loc.locationCode,
          performedBy: performedBy,
          timestamp: now,
          notes: 'Xác nhận cất thùng hàng $cleanBarcode lên kệ ${loc.locationCode} bằng PDA Barcode',
        ),
      );
    }

    final order = _inboundOrders.where((o) =>
      o.orderNo.trim().toUpperCase() == cleanBarcode ||
      o.inboundOrderId.trim().toUpperCase() == cleanBarcode
    ).firstOrNull;

    if (order != null) {
      order.status = InboundOrderStatus.completed;
      for (var d in order.details) {
        d.receivedQty = d.requiredQty;
      }
      await _dbService.updateInboundOrderStatus(order.inboundOrderId, InboundOrderStatus.completed, locationId: loc.locationId);
      await _syncDirectOrQueue(
        tableName: 'inbound_orders',
        recordId: order.inboundOrderId,
        action: 'UPDATE',
        payload: {
          'inbound_order_id': order.inboundOrderId,
          'status': InboundOrderStatus.completed.code,
          'updated_at': now.toIso8601String(),
        },
      );
    }

    await _syncDirectOrQueue(
      tableName: 'inbound_transactions',
      recordId: cleanBarcode,
      action: 'PDA_PUTAWAY_CONFIRM',
      payload: {
        'cartonBarcode': cleanBarcode,
        'orderNo': order?.orderNo ?? cleanBarcode,
        'locationId': loc.locationId,
        'locationCode': loc.locationCode,
        'itemCount': matchedItems.length,
        'performedBy': performedBy,
        'timestamp': now.toIso8601String(),
      },
    );

    _triggerBackgroundSync();
    notifyListeners();
    return matchedItems.length;
  }

  Future<int> confirmHandheldInbound({
    String? orderNo,
    required String palletCode,
    String? locationId,
    required List<String> scannedEpcs,
    String? defaultSku,
    String? defaultProductName,
    String performedBy = 'Thủ kho PDA',
  }) async {
    final uniqueEpcs = scannedEpcs.toSet().toList();
    if (uniqueEpcs.isEmpty) return 0;

    final pallet = createOrAssignPallet(
      palletCode: palletCode,
      locationId: locationId,
      newItems: [],
    );

    final now = DateTime.now();
    int count = 0;
    final effectiveStatus = locationId != null ? ItemStatus.inStock : ItemStatus.waitingPutaway;

    await _syncDirectOrQueue(
      tableName: 'pallets',
      recordId: pallet.palletId,
      action: 'INSERT',
      payload: {
        'pallet_id': pallet.palletId,
        'pallet_code': pallet.palletCode,
        'location_id': pallet.locationId,
        'inbound_time': pallet.inboundTime?.toIso8601String() ?? now.toIso8601String(),
        'is_multi_sku': pallet.isMultiSku ? 1 : 0,
      },
    );

    for (var epc in uniqueEpcs) {
      count++;
      Item? item = _items.where((it) => it.epc == epc).firstOrNull;
      if (item != null) {
        item.status = effectiveStatus;
        item.locationId = locationId;
        item.palletId = pallet.palletId;
        item.inboundTime = now;
        await _dbService.insertItem(item);
        await _syncDirectOrQueue(
          tableName: 'items',
          recordId: item.itemId,
          action: 'UPDATE',
          payload: {
            'item_id': item.itemId,
            'product_id': item.productId,
            'sku': item.sku,
            'product_name': item.productName,
            'serial_number': item.serialNumber,
            'epc': item.epc,
            'status': item.status.code,
            'order_no': item.orderNo ?? orderNo,
            'pallet_id': pallet.palletId,
            'location_id': locationId,
            'inbound_time': now.toIso8601String(),
          },
        );
      }
    }

    if (orderNo != null) {
      final orderIndex = _inboundOrders.indexWhere((o) => o.orderNo == orderNo);
      if (orderIndex != -1) {
        final order = _inboundOrders[orderIndex];
        final orderStatus = locationId != null ? InboundOrderStatus.completed : InboundOrderStatus.waitingPutaway;
        order.status = orderStatus;
        for (var d in order.details) {
          d.receivedQty = d.requiredQty;
        }
        await _dbService.updateInboundOrderStatus(order.inboundOrderId, orderStatus, locationId: locationId, palletId: pallet.palletId);
        await _syncDirectOrQueue(
          tableName: 'inbound_orders',
          recordId: order.inboundOrderId,
          action: 'UPDATE',
          payload: {
            'inbound_order_id': order.inboundOrderId,
            'status': orderStatus.code,
            'location_id': locationId,
            'pallet_id': pallet.palletId,
            'updated_at': now.toIso8601String(),
          },
        );
      }
    }

    final destinationName = locationId != null ? (_locations.where((l) => l.locationId == locationId).firstOrNull?.locationCode ?? locationId) : 'Chờ xếp kệ';
    _transactions.insert(
      0,
      InventoryTransaction(
        transactionId: 'TX-${DateTime.now().millisecondsSinceEpoch}',
        type: TransactionType.inbound,
        documentNo: orderNo ?? 'PDA-DIRECT-IN',
        sku: defaultSku ?? 'MULTI-SKU',
        productName: defaultProductName ?? 'Nhập kho quét RFID',
        quantity: uniqueEpcs.length,
        toLocation: destinationName,
        palletCode: palletCode,
        performedBy: performedBy,
        timestamp: now,
        notes: 'Nhập $count thẻ RFID qua PDA vào Pallet $palletCode - Trạng thái: $destinationName',
      ),
    );

    ErpBravoService().pushInboundCompleted(orderNo ?? 'PDA-DIRECT-IN', uniqueEpcs.length);

    await _syncDirectOrQueue(
      tableName: 'sync_logs',
      recordId: orderNo ?? 'PDA-DIRECT-${now.millisecondsSinceEpoch}',
      action: 'INBOUND_PDA_CONFIRM',
      payload: {
        'order_no': orderNo,
        'pallet_code': palletCode,
        'location_id': locationId,
        'epcs': uniqueEpcs,
        'sku': defaultSku,
        'product_name': defaultProductName,
        'performed_by': performedBy,
        'item_count': uniqueEpcs.length,
        'timestamp': now.toIso8601String(),
      },
    );

    _triggerBackgroundSync();
    notifyListeners();
    return uniqueEpcs.length;
  }

  PickingPlan generateFifoPickingPlan(String outboundOrderId) {
    final order = _outboundOrders.firstWhere((o) => o.outboundOrderId == outboundOrderId);
    final List<PickingPlanLine> lines = [];

    for (var detail in order.details) {
      int remainingQtyNeeded = detail.requiredQty;

      final availableItems = _items.where(
        (it) => it.productId == detail.productId && it.status == ItemStatus.inStock && it.palletId != null,
      ).toList();

      final Map<String, List<Item>> palletGroups = {};
      for (var it in availableItems) {
        palletGroups.putIfAbsent(it.palletId!, () => []).add(it);
      }

      final sortedPalletIds = palletGroups.keys.toList()
        ..sort((a, b) {
          final pA = _pallets.firstWhere((p) => p.palletId == a);
          final pB = _pallets.firstWhere((p) => p.palletId == b);
          final timeA = pA.inboundTime ?? DateTime.now();
          final timeB = pB.inboundTime ?? DateTime.now();
          return timeA.compareTo(timeB);
        });

      for (var palId in sortedPalletIds) {
        if (remainingQtyNeeded <= 0) break;

        final palItems = palletGroups[palId]!;
        final pallet = _pallets.firstWhere((p) => p.palletId == palId);
        final loc = _locations.firstWhere(
          (l) => l.locationId == pallet.locationId,
          orElse: () => Location(locationId: '', locationCode: 'UNKNOWN', zone: '', shelf: '', level: ''),
        );

        final qtyFromThisPallet = min(remainingQtyNeeded, palItems.length);
        final targetItems = palItems.take(qtyFromThisPallet).toList();

        for (var item in targetItems) {
          item.status = ItemStatus.allocated;
          item.allocatedTime = DateTime.now();
        }

        lines.add(
          PickingPlanLine(
            productId: detail.productId,
            sku: detail.sku,
            productName: detail.productName,
            palletId: pallet.palletId,
            palletCode: pallet.palletCode,
            locationCode: loc.locationCode,
            quantityToPick: qtyFromThisPallet,
            targetItemIds: targetItems.map((e) => e.itemId).toList(),
          ),
        );

        remainingQtyNeeded -= qtyFromThisPallet;
      }
    }

    final plan = PickingPlan(
      planId: 'PLAN-${DateTime.now().millisecondsSinceEpoch}',
      outboundOrderId: outboundOrderId,
      poNo: order.poNo,
      createdAt: DateTime.now(),
      lines: lines,
    );

    _pickingPlans.add(plan);
    order.status = OutboundOrderStatus.processing;
    notifyListeners();
    return plan;
  }

  void markPickingLineCompleted(String planId, String palletCode, String sku) {
    final plan = _pickingPlans.firstWhere((p) => p.planId == planId);
    for (var line in plan.lines) {
      if (line.palletCode == palletCode && line.sku == sku) {
        line.isPicked = true;
        for (var itemId in line.targetItemIds) {
          final it = _items.firstWhere((item) => item.itemId == itemId);
          it.status = ItemStatus.picked;
        }
      }
    }
    if (plan.lines.every((l) => l.isPicked)) {
      plan.isCompleted = true;
      final order = _outboundOrders.firstWhere((o) => o.outboundOrderId == plan.outboundOrderId);
      order.status = OutboundOrderStatus.prepared;
    }
    notifyListeners();
  }

  /// Kiểm tra xem sản phẩm có nằm hợp lệ trên kệ kho hay không (đã putaway inStock hoặc allocated cho đơn xuất, và có locationId)
  bool isItemStockedInLocation(Item item) {
    if (item.status != ItemStatus.inStock && item.status != ItemStatus.allocated) return false;
    String? locId = item.locationId;
    if (locId == null || locId.trim().isEmpty) {
      if (item.palletId != null) {
        final pal = _pallets.where((p) => p.palletId == item.palletId).firstOrNull;
        locId = pal?.locationId;
      }
    }
    if (locId == null || locId.trim().isEmpty) return false;
    final loc = locId.trim().toUpperCase();
    if (loc == 'LOC-GATE-IN' || loc == 'LOC-GATE-OUT') return false;
    return true;
  }

  GateVerificationResult verifyGateOutbound({
    required String poNo,
    required List<String> scannedEpcs,
  }) {
    final order = _outboundOrders.firstWhere((o) => o.poNo == poNo);
    final uniqueEpcs = scannedEpcs.toSet().toList();

    final Map<String, int> actualSkuCounts = {};
    final List<String> unexpectedEpcs = [];
    final List<String> unstockedEpcs = [];

    final List<SkuVerificationBreakdown> breakdowns = [];
    bool allMatched = true;

    for (var epc in uniqueEpcs) {
      final item = _items.firstWhere(
        (it) => it.epc == epc,
        orElse: () => Item(
          itemId: 'UNKNOWN',
          productId: '',
          sku: 'UNKNOWN',
          productName: 'Thẻ chưa khai báo',
          serialNumber: '',
          epc: epc,
        ),
      );

      if (item.sku == 'UNKNOWN') {
        unexpectedEpcs.add(epc);
      } else if (!isItemStockedInLocation(item)) {
        unstockedEpcs.add(epc);
        allMatched = false;
      } else {
        actualSkuCounts[item.sku] = (actualSkuCounts[item.sku] ?? 0) + 1;
      }
    }

    for (var detail in order.details) {
      final actualQty = actualSkuCounts[detail.sku] ?? 0;
      final isMatch = actualQty == detail.requiredQty;
      if (!isMatch) allMatched = false;

      breakdowns.add(
        SkuVerificationBreakdown(
          sku: detail.sku,
          productName: detail.productName,
          requiredQty: detail.requiredQty,
          actualQty: actualQty,
          isMatched: isMatch,
        ),
      );
    }

    if (unexpectedEpcs.isNotEmpty || unstockedEpcs.isNotEmpty) allMatched = false;

    int totalReq = order.details.fold(0, (sum, d) => sum + d.requiredQty);
    int totalAct = uniqueEpcs.length;

    return GateVerificationResult(
      isPass: allMatched,
      mode: GateMode.outbound,
      documentNo: poNo,
      totalRequiredQty: totalReq,
      totalActualQty: totalAct,
      skuBreakdowns: breakdowns,
      unexpectedEpcs: unexpectedEpcs,
      unstockedEpcs: unstockedEpcs,
      missingEpcs: [],
      verifiedAt: DateTime.now(),
    );
  }

  bool confirmOutboundCompletion({
    required String poNo,
    required List<String> shippedEpcs,
    required String performedBy,
  }) {
    final order = _outboundOrders.firstWhere((o) => o.poNo == poNo);

    final unstocked = shippedEpcs.where((epc) {
      final item = _items.where((it) => it.epc == epc).firstOrNull;
      if (item == null) return true;
      return !isItemStockedInLocation(item);
    }).toList();

    if (unstocked.isNotEmpty) {
      throw Exception('Không thể xuất kho: Có ${unstocked.length} sản phẩm chưa được xếp vào kệ nào trong kho (Đang chờ xếp kệ hoặc chưa gán vị trí)!');
    }

    for (var epc in shippedEpcs) {
      final item = _items.firstWhere((it) => it.epc == epc);
      item.status = ItemStatus.out;
      if (item.palletId != null) {
        final pal = _pallets.firstWhere((p) => p.palletId == item.palletId);
        pal.itemIds.remove(item.itemId);
      }
    }

    order.status = OutboundOrderStatus.shipped;

    for (var d in order.details) {
      _transactions.insert(
        0,
        InventoryTransaction(
          transactionId: 'TX-${DateTime.now().millisecondsSinceEpoch}-${d.sku}',
          type: TransactionType.outbound,
          documentNo: poNo,
          sku: d.sku,
          productName: d.productName,
          quantity: d.requiredQty,
          fromLocation: 'KHO_TONG',
          toLocation: 'KHACH_HANG: ${order.customer}',
          performedBy: performedBy,
          timestamp: DateTime.now(),
          notes: 'Xuất kho thành công, Gate OUTBOUND PASS',
        ),
      );
    }

    ErpBravoService().pushOutboundCompleted(poNo, shippedEpcs.length);

    _syncDirectOrQueue(
      tableName: 'outbound_transactions',
      recordId: poNo,
      action: 'OUTBOUND_CONFIRM',
      payload: {
        'poNo': poNo,
        'shippedEpcs': shippedEpcs,
        'performedBy': performedBy,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _triggerBackgroundSync();

    notifyListeners();
    return true;
  }

  Future<int> confirmDirectOutbound({
    String? poNo,
    required List<String> scannedEpcs,
    String performedBy = 'Thủ kho Desktop',
  }) async {
    final uniqueEpcs = scannedEpcs.toSet().toList();
    if (uniqueEpcs.isEmpty) return 0;
    final now = DateTime.now();

    final unstocked = uniqueEpcs.where((epc) {
      final item = _items.where((it) => it.epc == epc).firstOrNull;
      if (item == null) return true;
      return !isItemStockedInLocation(item);
    }).toList();

    if (unstocked.isNotEmpty) {
      throw Exception('Không thể xuất kho: Có ${unstocked.length} sản phẩm chưa nằm trong kệ kho nào (Vị trí trống hoặc chưa xếp kho)!');
    }

    for (var epc in uniqueEpcs) {
      final item = _items.where((it) => it.epc == epc).firstOrNull;
      if (item != null) {
        item.status = ItemStatus.out;
        if (item.palletId != null) {
          final pal = _pallets.where((p) => p.palletId == item.palletId).firstOrNull;
          pal?.itemIds.remove(item.itemId);
        }
        await _dbService.updateItemStatus(epc, ItemStatus.out);
      }
    }

    if (poNo != null) {
      final order = _outboundOrders.where((o) => o.poNo == poNo).firstOrNull;
      if (order != null) {
        order.status = OutboundOrderStatus.shipped;
        await _dbService.updateOutboundOrderStatus(order.outboundOrderId, OutboundOrderStatus.shipped);
      }
    }

    _transactions.insert(
      0,
      InventoryTransaction(
        transactionId: 'TX-${now.millisecondsSinceEpoch}',
        type: TransactionType.outbound,
        documentNo: poNo ?? 'DIRECT-OUT',
        sku: 'MULTI-SKU',
        productName: 'Xuất kho RFID',
        quantity: uniqueEpcs.length,
        fromLocation: 'KHO_TONG',
        toLocation: 'XUẤT_GIAO',
        performedBy: performedBy,
        timestamp: now,
        notes: 'Xuất trực tiếp ${uniqueEpcs.length} chip RFID qua trạm Desktop',
      ),
    );

    await _syncDirectOrQueue(
      tableName: 'outbound_transactions',
      recordId: poNo ?? 'DIRECT-OUT-${now.millisecondsSinceEpoch}',
      action: 'OUTBOUND_CONFIRM',
      payload: {
        'poNo': poNo ?? 'DIRECT-OUT',
        'epcs': uniqueEpcs,
        'performedBy': performedBy,
        'timestamp': now.toIso8601String(),
      },
    );
    _triggerBackgroundSync();

    notifyListeners();
    return uniqueEpcs.length;
  }

  InventorySession startInventorySession({required String zone, String? locationCode}) {
    final session = InventorySession(
      sessionId: 'SESS-${DateTime.now().millisecondsSinceEpoch}',
      sessionCode: 'KK-${DateTime.now().month}${DateTime.now().day}-${Random().nextInt(900) + 100}',
      zone: zone,
      locationCode: locationCode,
      startedAt: DateTime.now(),
    );
    _inventorySessions.insert(0, session);
    notifyListeners();
    return session;
  }

  void processAuditScan({
    required String sessionId,
    required List<String> scannedEpcs,
  }) {
    final session = _inventorySessions.firstWhere((s) => s.sessionId == sessionId);
    session.results.clear();

    final uniqueScannedEpcs = scannedEpcs.toSet();

    final expectedItems = _items.where((it) {
      if (it.status != ItemStatus.inStock) return false;
      final loc = _locations.firstWhere((l) => l.locationId == it.locationId, orElse: () => Location(locationId: '', locationCode: '', zone: '', shelf: '', level: ''));
      if (session.locationCode != null && session.locationCode!.isNotEmpty) {
        return loc.locationCode == session.locationCode;
      }
      return loc.zone == session.zone;
    }).toList();

    final expectedEpcs = expectedItems.map((e) => e.epc).toSet();

    for (var epc in uniqueScannedEpcs) {
      final item = _items.firstWhere(
        (it) => it.epc == epc,
        orElse: () => Item(itemId: '', productId: '', sku: 'UNKNOWN', productName: 'Thẻ chưa khai báo', serialNumber: '', epc: epc),
      );

      if (item.sku == 'UNKNOWN') {
        session.results.add(
          InventoryItemResult(
            epc: epc,
            resultType: InventoryVarianceType.unknownEpc,
            readAt: DateTime.now(),
          ),
        );
      } else if (expectedEpcs.contains(epc)) {
        session.results.add(
          InventoryItemResult(
            epc: epc,
            sku: item.sku,
            productName: item.productName,
            expectedLocation: session.locationCode ?? session.zone,
            actualLocation: session.locationCode ?? session.zone,
            resultType: InventoryVarianceType.match,
            readAt: DateTime.now(),
          ),
        );
      } else {
        final actualLoc = _locations.firstWhere((l) => l.locationId == item.locationId, orElse: () => Location(locationId: '', locationCode: 'Chưa rõ', zone: '', shelf: '', level: ''));
        session.results.add(
          InventoryItemResult(
            epc: epc,
            sku: item.sku,
            productName: item.productName,
            expectedLocation: actualLoc.locationCode,
            actualLocation: session.locationCode ?? session.zone,
            resultType: InventoryVarianceType.wrongLocation,
            readAt: DateTime.now(),
          ),
        );
      }
    }

    for (var expItem in expectedItems) {
      if (!uniqueScannedEpcs.contains(expItem.epc)) {
        session.results.add(
          InventoryItemResult(
            epc: expItem.epc,
            sku: expItem.sku,
            productName: expItem.productName,
            expectedLocation: session.locationCode ?? session.zone,
            actualLocation: 'Không thấy',
            resultType: InventoryVarianceType.missing,
            readAt: DateTime.now(),
          ),
        );
      }
    }

    notifyListeners();
  }

  void completeInventorySession(String sessionId, String approvedBy) {
    final session = _inventorySessions.firstWhere((s) => s.sessionId == sessionId);
    session.isCompleted = true;
    session.completedAt = DateTime.now();

    _transactions.insert(
      0,
      InventoryTransaction(
        transactionId: 'TX-AUDIT-${DateTime.now().millisecondsSinceEpoch}',
        type: TransactionType.auditAdjustment,
        documentNo: session.sessionCode,
        sku: 'ĐA_SKU',
        productName: 'Phiên kiểm kê ${session.sessionCode}',
        quantity: session.results.length,
        fromLocation: session.zone,
        toLocation: session.zone,
        performedBy: approvedBy,
        timestamp: DateTime.now(),
        notes: 'Chốt kiểm kê: ${session.matchCount} khớp, ${session.missingCount} thiếu, ${session.wrongLocationCount} sai vị trí, ${session.unknownEpcCount} thẻ lạ',
      ),
    );

    _syncDirectOrQueue(
      tableName: 'inventory_sessions',
      recordId: session.sessionId,
      action: 'AUDIT_COMPLETE',
      payload: {
        'sessionId': session.sessionId,
        'sessionCode': session.sessionCode,
        'zone': session.zone,
        'locationCode': session.locationCode,
        'matchCount': session.matchCount,
        'missingCount': session.missingCount,
        'wrongLocationCount': session.wrongLocationCount,
        'unknownEpcCount': session.unknownEpcCount,
        'approvedBy': approvedBy,
        'completedAt': session.completedAt?.toIso8601String(),
      },
    );
    _triggerBackgroundSync();

    notifyListeners();
  }

  bool movePallet({
    required String palletId,
    required String newLocationId,
    required String performedBy,
  }) {
    final pallet = _pallets.firstWhere((p) => p.palletId == palletId);
    final oldLocation = _locations.firstWhere((l) => l.locationId == pallet.locationId, orElse: () => Location(locationId: '', locationCode: 'N/A', zone: '', shelf: '', level: ''));
    final newLocation = _locations.firstWhere((l) => l.locationId == newLocationId);

    pallet.locationId = newLocationId;
    _dbService.updatePalletLocation(palletId, newLocationId);
    if (oldLocation.currentPallets > 0) oldLocation.currentPallets--;
    newLocation.currentPallets++;

    for (var itemId in pallet.itemIds) {
      final item = _items.firstWhere((it) => it.itemId == itemId);
      item.locationId = newLocationId;
      _dbService.updateItemLocationAndPallet(item.epc, newLocationId, palletId);
    }

    _transactions.insert(
      0,
      InventoryTransaction(
        transactionId: 'TX-MOVE-${DateTime.now().millisecondsSinceEpoch}',
        type: TransactionType.movement,
        documentNo: pallet.palletCode,
        sku: 'PALLET_${pallet.palletCode}',
        productName: 'Di chuyển ${pallet.itemIds.length} Items',
        quantity: pallet.itemIds.length,
        fromLocation: oldLocation.locationCode,
        toLocation: newLocation.locationCode,
        palletCode: pallet.palletCode,
        performedBy: performedBy,
        timestamp: DateTime.now(),
        notes: 'Di chuyển Pallet từ ${oldLocation.locationCode} sang ${newLocation.locationCode}',
      ),
    );

    _syncDirectOrQueue(
      tableName: 'pallet_moves',
      recordId: palletId,
      action: 'PALLET_MOVE',
      payload: {
        'palletId': palletId,
        'palletCode': pallet.palletCode,
        'fromLocation': oldLocation.locationCode,
        'toLocation': newLocation.locationCode,
        'itemCount': pallet.itemIds.length,
        'performedBy': performedBy,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _triggerBackgroundSync();

    notifyListeners();
    return true;
  }

  Map<String, Map<String, dynamic>> getStockSummary() {
    final Map<String, Map<String, dynamic>> summary = {};
    for (var p in _products) {
      final inStockItems = _items.where((it) => it.productId == p.productId && it.status == ItemStatus.inStock).toList();
      final allocatedItems = _items.where((it) => it.productId == p.productId && (it.status == ItemStatus.allocated || it.status == ItemStatus.picked)).toList();
      final totalItems = inStockItems.length + allocatedItems.length;

      summary[p.sku] = {
        'product': p,
        'inStock': inStockItems.length,
        'allocated': allocatedItems.length,
        'total': totalItems,
      };
    }
    return summary;
  }
}
