import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

      // Dọn dẹp triệt để dữ liệu rác, lệnh scanner và các dữ liệu mẫu kiểm thử cũ
      bool isTestProduct(Product p) {
        final pSku = p.sku.toUpperCase();
        final pId = p.productId.toUpperCase();
        final pName = p.productName.toUpperCase();
        return bogusCommandNames.contains(pId) ||
            bogusCommandNames.contains(pSku) ||
            pSku == '7A0B5FD0B4F31DD5' ||
            pSku.startsWith('SKU-POLO') ||
            pSku.startsWith('SKU-JEAN') ||
            pSku.startsWith('SKU-SNEAKER') ||
            pSku.startsWith('SKU-ELEC-') ||
            pSku.startsWith('SKU-TEXT-') ||
            pSku.startsWith('SKU-PHARM-') ||
            pSku.contains('SAMPLE') ||
            pSku.contains('TEST') ||
            pId == 'PROD-001' ||
            pId == 'PROD-002' ||
            pId.startsWith('PROD-') ||
            pName.contains('ÁO POLO RFID') ||
            pName.contains('SAMPLE') ||
            pName.contains('TEST') ||
            pName.contains('MẪU');
      }

      bool isTestItem(Item i) {
        final epc = i.epc.toUpperCase();
        final sku = i.sku.toUpperCase();
        final orderNo = (i.orderNo ?? '').toUpperCase();
        final itemId = i.itemId.toUpperCase();
        final pName = i.productName.toUpperCase();
        return epc == 'E28011600000000000099888' ||
            epc == 'E28032F9666D00012F50' ||
            epc == 'E2803295B8FA00017846' ||
            epc.startsWith('ABCDEF') ||
            epc.startsWith('E280119120000000000000') ||
            itemId.startsWith('ITEM-SAMPLE-') ||
            itemId.startsWith('ITEM-TEST-') ||
            itemId.startsWith('ITEM-00') ||
            orderNo == 'CARTONTEST0001' ||
            orderNo.startsWith('THUNG-') ||
            orderNo.startsWith('INB-2026-') ||
            orderNo == 'INB-001' ||
            pName.contains('ÁO POLO RFID') ||
            pName.contains('SAMPLE') ||
            pName.contains('TEST') ||
            pName.contains('MẪU') ||
            sku.contains('SAMPLE') ||
            sku.contains('TEST') ||
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
      for (final o in dbInboundOrders) {
        if (o.orderNo == 'CARTONTEST0001' ||
            o.orderNo.startsWith('THUNG-') ||
            o.orderNo.startsWith('INB-2026-') ||
            o.orderNo == 'INB-001') {
          await _dbService.deleteInboundOrder(o.inboundOrderId);
        }
      }
      for (final o in dbOutboundOrders) {
        if (o.poNo == 'PO-2026-001' ||
            o.poNo == 'PO-2026-002' ||
            o.poNo == 'PO-2026-003' ||
            o.poNo == 'OUT-001') {
          await _dbService.deleteOutboundOrder(o.outboundOrderId);
        }
      }

      final cleanProducts = await _dbService.getProducts();
      final cleanItems = await _dbService.getItems();
      final cleanPallets = await _dbService.getPallets();
      final backupPallets = await _dbService.loadPalletsBackup();
      final cleanInboundOrders = await _dbService.getInboundOrders();
      final cleanOutboundOrders = await _dbService.getOutboundOrders();
      final dbUsers = await _dbService.getUsers();
      final dbCustomers = await _dbService.getCustomers();
      final dbDeliveryNotes = await _dbService.getDeliveryNotes();
      final dbInventorySessions = await _dbService.getInventorySessions();

      _products.clear();
      _products.addAll(cleanProducts);

      final cleanLocations = List<Location>.from(dbLocations);
      cleanLocations.sort((a, b) {
        final z = a.zone.compareTo(b.zone);
        if (z != 0) return z;
        final s = a.shelf.compareTo(b.shelf);
        if (s != 0) return s;
        final l = a.level.compareTo(b.level);
        if (l != 0) return l;
        return a.locationCode.compareTo(b.locationCode);
      });

      _locations.clear();
      _locations.addAll(cleanLocations);

      // KHÔNG BAO GIỜ XÓA PALLET ĐÃ KHAI BÁO CỦA NGƯỜI DÙNG: Khai báo 1 lần dùng vĩnh viễn
      // Đồng bộ 2 lớp: SQLite B-Tree Index + Permanent Master Backup File
      final Map<String, Pallet> mergedPallets = {};
      for (final p in backupPallets) {
        mergedPallets[p.palletCode.toUpperCase()] = p;
      }
      for (final p in cleanPallets) {
        final existing = mergedPallets[p.palletCode.toUpperCase()];
        if (existing != null && (p.rfidEpc == null || p.rfidEpc!.isEmpty) && existing.rfidEpc != null) {
          p.rfidEpc = existing.rfidEpc;
        }
        mergedPallets[p.palletCode.toUpperCase()] = p;
      }

      // Đảm bảo SQLite có đầy đủ các Pallet đã được lưu
      for (final p in mergedPallets.values) {
        await _dbService.insertPallet(p);
      }

      _pallets.clear();
      _pallets.addAll(mergedPallets.values);
      await _dbService.savePalletsBackup(_pallets);

      // Xóa tất cả các thẻ pendingInbound cũ còn sót lại từ các lần test trước
      for (final orphan in cleanItems.where((i) => i.status == ItemStatus.pendingInbound || isTestItem(i))) {
        await _dbService.deleteItem(orphan.epc);
      }

      _items.clear();
      _items.addAll(cleanItems.where((i) => !isTestItem(i) && i.status != ItemStatus.pendingInbound));
      for (final p in _pallets) {
        p.itemIds.clear();
        p.itemIds.addAll(_items.where((i) => i.palletId == p.palletId).map((i) => i.itemId));
      }

      _inboundOrders.clear();
      _inboundOrders.addAll(cleanInboundOrders.where((o) =>
          o.orderNo != 'CARTONTEST0001' &&
          !o.orderNo.startsWith('THUNG-') &&
          !o.orderNo.startsWith('INB-2026-') &&
          o.orderNo != 'INB-001'));

      _outboundOrders.clear();
      _outboundOrders.addAll(cleanOutboundOrders.where((o) =>
          o.poNo != 'PO-2026-001' &&
          o.poNo != 'PO-2026-002' &&
          o.poNo != 'PO-2026-003' &&
          o.poNo != 'OUT-001'));

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

  Future<void> updateProduct(Product updatedProd) async {
    await _dbService.insertProduct(updatedProd);
    final idx = _products.indexWhere((p) => p.productId == updatedProd.productId || p.sku == updatedProd.sku);
    if (idx >= 0) {
      _products[idx] = updatedProd;
    } else {
      _products.add(updatedProd);
    }
    await _syncDirectOrQueue(
      tableName: 'products',
      recordId: updatedProd.productId,
      action: 'UPDATE',
      payload: {
        'product_id': updatedProd.productId,
        'sku': updatedProd.sku,
        'product_name': updatedProd.productName,
        'unit': updatedProd.unit,
        'category': updatedProd.category,
      },
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

  Future<void> updateInboundOrderBarcode(String orderNo, String newBarcode) async {
    final cleanNo = orderNo.trim().toUpperCase();
    final cleanBarcode = newBarcode.trim().toUpperCase();

    final order = _inboundOrders.where((o) =>
      o.orderNo.trim().toUpperCase() == cleanNo ||
      o.inboundOrderId.trim().toUpperCase() == cleanNo
    ).firstOrNull;

    if (order != null) {
      final updatedDetails = order.details.map((d) => InboundOrderDetail(
        productId: cleanBarcode,
        sku: cleanBarcode,
        productName: d.productName,
        requiredQty: d.requiredQty,
        receivedQty: d.receivedQty,
      )).toList();
      order.details.clear();
      order.details.addAll(updatedDetails);
      await _dbService.insertInboundOrder(order);
      await _syncDirectOrQueue(
        tableName: 'inbound_orders',
        recordId: order.inboundOrderId,
        action: 'UPDATE',
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
    }

    final orderItems = _items.where((i) =>
      i.orderNo != null &&
      (i.orderNo!.trim().toUpperCase() == cleanNo ||
       (order != null && i.orderNo!.trim().toUpperCase() == order.inboundOrderId.trim().toUpperCase()))
    ).toList();

    for (var it in orderItems) {
      it.sku = cleanBarcode;
      it.productId = cleanBarcode;
      await _dbService.insertItem(it);
      await _syncDirectOrQueue(
        tableName: 'items',
        recordId: it.itemId,
        action: 'UPDATE',
        payload: {
          'itemId': it.itemId,
          'productId': it.productId,
          'sku': it.sku,
          'productName': it.productName,
          'serialNumber': it.serialNumber,
          'epc': it.epc,
          'status': it.status.code,
          'orderNo': it.orderNo,
          'palletId': it.palletId,
          'locationId': it.locationId,
          'inboundTime': it.inboundTime?.toIso8601String(),
        },
      );
    }

    // Đảm bảo Product record tồn tại
    final existingProd = _products.where((p) => p.sku == cleanBarcode || p.productId == cleanBarcode).firstOrNull;
    if (existingProd == null) {
      final pName = order?.details.firstOrNull?.productName ?? 'Kiện hàng $cleanBarcode';
      final newProd = Product(
        productId: cleanBarcode,
        sku: cleanBarcode,
        productName: pName,
        unit: 'Cái',
        category: 'Hàng nhập qua cổng RFID',
      );
      _products.add(newProd);
      await _dbService.insertProduct(newProd);
      await _syncDirectOrQueue(
        tableName: 'products',
        recordId: newProd.productId,
        action: 'INSERT',
        payload: {
          'productId': newProd.productId,
          'sku': newProd.sku,
          'productName': newProd.productName,
          'unit': newProd.unit,
          'category': newProd.category,
        },
      );
    }

    _triggerBackgroundSync();
    notifyListeners();
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

  Future<void> insertDirectItems(List<Item> items) async {
    if (items.isEmpty) return;
    final epcSet = items.map((i) => i.epc.toUpperCase()).toSet();
    _items.removeWhere((i) => epcSet.contains(i.epc.toUpperCase()));
    _items.addAll(items);
    await _dbService.insertItems(items);

    final syncRecords = items.map((item) => {
      'table_name': 'items',
      'record_id': item.itemId,
      'action': 'INSERT',
      'payload': {
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
    }).toList();
    await _dbService.enqueueSyncBatch(syncRecords);

    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> addProductsBatch(List<Product> newProds) async {
    if (newProds.isEmpty) return;
    final toAdd = <Product>[];
    for (final p in newProds) {
      final existing = _products.where((ex) => ex.productId == p.productId || ex.sku == p.sku).firstOrNull;
      if (existing == null) {
        toAdd.add(p);
      }
    }
    if (toAdd.isEmpty) return;

    await _dbService.insertProducts(toAdd);
    _products.addAll(toAdd);

    final syncRecords = toAdd.map((p) => {
      'table_name': 'products',
      'record_id': p.productId,
      'action': 'INSERT',
      'payload': {
        'productId': p.productId,
        'sku': p.sku,
        'productName': p.productName,
        'unit': p.unit,
        'category': p.category,
        'description': p.description,
      },
    }).toList();
    await _dbService.enqueueSyncBatch(syncRecords);

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
    _locations.removeWhere((l) =>
        l.locationCode.toUpperCase() == location.locationCode.toUpperCase() ||
        l.locationId.toUpperCase() == location.locationId.toUpperCase());
    _locations.add(location);
    await _dbService.insertLocation(location);
    await _syncDirectOrQueue(
      tableName: 'locations',
      recordId: location.locationId,
      action: 'INSERT',
      payload: {
        'location_id': location.locationId,
        'location_code': location.locationCode,
        'zone': location.zone,
        'shelf': location.shelf,
        'level': location.level,
      'max_pallet_capacity': location.maxPalletCapacity,
      'current_pallets': location.currentPallets,
      'status': location.status,
      },
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> deleteLocation(String locationIdOrCode) async {
    final clean = locationIdOrCode.trim().toUpperCase();
    _locations.removeWhere((l) =>
        l.locationCode.toUpperCase() == clean ||
        l.locationId.toUpperCase() == clean);
    await _dbService.deleteLocation(clean);
    await _syncDirectOrQueue(
      tableName: 'locations',
      recordId: clean,
      action: 'DELETE',
      payload: {'location_id': clean, 'location_code': clean},
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  /// Khởi tạo nhanh sơ đồ kho mẫu gồm Khu A và Khu B (mỗi khu 8-12 ô kệ)
  Future<int> generateSampleWarehouseLayout() async {
    final zones = ['Khu A', 'Khu B'];
    final createdLocs = <Location>[];

    for (final zone in zones) {
      final prefix = zone.replaceAll('Khu ', '').trim().toUpperCase();
      for (int s = 1; s <= 2; s++) {
        final shelfStr = s.toString().padLeft(2, '0');
        for (int lv = 1; lv <= 3; lv++) {
          final levelStr = lv.toString().padLeft(2, '0');
          final code = '$prefix-$shelfStr-$levelStr';
          if (!_locations.any((l) => l.locationCode.toUpperCase() == code)) {
            final loc = Location(
              locationId: 'LOC-$code',
              locationCode: code,
              zone: zone,
              shelf: 'Kệ $shelfStr',
              level: 'Tầng $lv',
              maxPalletCapacity: 2,
              currentPallets: 0,
            );
            createdLocs.add(loc);
            _locations.add(loc);
            await _dbService.insertLocation(loc);
          }
        }
      }
    }

    notifyListeners();
    return createdLocs.length;
  }

  /// Đếm chính xác số lượng Pallet đang được xếp tại vị trí kệ này
  int getPalletCountForLocation(Location loc) {
    final cleanCode = loc.locationCode.trim().toUpperCase();
    final cleanId = loc.locationId.trim().toUpperCase();
    return _pallets.where((p) =>
      p.locationId != null &&
      (p.locationId!.trim().toUpperCase() == cleanCode || p.locationId!.trim().toUpperCase() == cleanId)
    ).length;
  }

  /// Danh sách các Pallet đang nằm tại vị trí kệ này
  List<Pallet> getPalletsForLocation(Location loc) {
    final cleanCode = loc.locationCode.trim().toUpperCase();
    final cleanId = loc.locationId.trim().toUpperCase();
    return _pallets.where((p) =>
      p.locationId != null &&
      (p.locationId!.trim().toUpperCase() == cleanCode || p.locationId!.trim().toUpperCase() == cleanId)
    ).toList();
  }

  Future<void> updateLocationStatus(String locationId, String status) async {
    final cleanId = locationId.trim().toUpperCase();
    final loc = _locations.where((l) =>
        l.locationId.trim().toUpperCase() == cleanId ||
        l.locationCode.trim().toUpperCase() == cleanId
    ).firstOrNull;

    if (loc != null) {
      loc.status = status;
    }

    await _dbService.updateLocationStatus(locationId, status);

    await _syncDirectOrQueue(
      tableName: 'locations',
      recordId: loc?.locationId ?? locationId,
      action: 'UPDATE',
      payload: {
        'locationId': loc?.locationId ?? locationId,
        'status': status,
      },
    );

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

  void triggerBackgroundSync() => _triggerBackgroundSync();

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
    _inventorySessions.insert(0, session);
    _syncDirectOrQueue(
      tableName: 'inventory_sessions',
      recordId: session.sessionId,
      action: 'INSERT',
      payload: {
        'session_id': session.sessionId,
        'session_code': session.sessionCode,
        'zone': session.zone,
        'location_code': session.locationCode,
        'started_at': session.startedAt.toIso8601String(),
        'completed_at': session.completedAt?.toIso8601String(),
        'is_completed': session.isCompleted ? 1 : 0,
      },
    );
    for (final r in session.results) {
      _dbService.enqueueSync(
        tableName: 'inventory_session_details',
        recordId: '${session.sessionId}-${r.epc}',
        action: 'INSERT',
        payload: {
          'session_id': session.sessionId,
          'epc': r.epc,
          'sku': r.sku,
          'product_name': r.productName,
          'expected_location': r.expectedLocation,
          'actual_location': r.actualLocation,
          'result_type': r.resultType.code,
          'read_at': r.readAt.toIso8601String(),
        },
      );
    }
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
      payload: user.toMap(),
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

  /// Tra cứu xe Pallet theo mã thẻ RFID (EPC) hoặc Hex ASCII của tên Pallet
  Pallet? findPalletByRfid(String epc) {
    final clean = epc.trim().toUpperCase();
    if (clean.isEmpty) return null;
    for (final p in _pallets) {
      if (p.rfidEpc != null && p.rfidEpc!.trim().toUpperCase() == clean) {
        return p;
      }
      if (p.palletCode.toUpperCase() == clean || p.palletId.toUpperCase() == clean) {
        return p;
      }
      // Hex ASCII matching
      final hexCode = p.palletCode.codeUnits.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');
      if (clean == hexCode || clean.startsWith(hexCode) || (clean.length >= 8 && hexCode.startsWith(clean))) {
        return p;
      }
    }
    return null;
  }

  /// Tra cứu bất đồng bộ có đối soát trực tiếp với SQLite để chống mất pallet
  Future<Pallet?> findPalletByRfidAsync(String epc) async {
    final direct = findPalletByRfid(epc);
    if (direct != null) return direct;

    try {
      final dbPallets = await _dbService.getPallets();
      final clean = epc.trim().toUpperCase();
      for (final p in dbPallets) {
        if ((p.rfidEpc != null && p.rfidEpc!.trim().toUpperCase() == clean) ||
            p.palletCode.toUpperCase() == clean ||
            p.palletId.toUpperCase() == clean) {
          if (!_pallets.any((x) => x.palletId == p.palletId)) {
            _pallets.add(p);
            notifyListeners();
          }
          return p;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Đăng ký hoặc cập nhật mã thẻ RFID, mã xe Pallet (lưu cố định vĩnh viễn vào Database)
  Future<void> registerOrUpdatePallet({
    required String palletCode,
    required String rfidEpc,
    String? locationId,
    String? oldPalletCode,
  }) async {
    final cleanCode = palletCode.trim().toUpperCase();
    final cleanEpc = rfidEpc.trim().toUpperCase();
    final cleanOldCode = oldPalletCode?.trim().toUpperCase();

    // Nếu sửa đổi tên/mã từ một Pallet cũ đã có
    if (cleanOldCode != null && cleanOldCode.isNotEmpty && cleanOldCode != cleanCode) {
      await _dbService.deletePallet(cleanOldCode);
      _pallets.removeWhere((p) =>
          p.palletCode.toUpperCase() == cleanOldCode ||
          p.palletId.toUpperCase() == cleanOldCode ||
          p.palletId.toUpperCase() == 'PAL-$cleanOldCode');

      // Chuyển quyền sở hữu các Item sang mã Pallet mới
      for (final item in _items.where((it) => it.palletId == 'PAL-$cleanOldCode' || it.palletId == cleanOldCode)) {
        item.palletId = 'PAL-$cleanCode';
        await _dbService.insertItem(item);
      }
    }

    final existing = _pallets.where((p) =>
        p.palletCode.toUpperCase() == cleanCode ||
        p.palletId.toUpperCase() == cleanCode ||
        p.palletId.toUpperCase() == 'PAL-$cleanCode').firstOrNull;
    if (existing != null) {
      existing.palletCode = cleanCode;
      existing.rfidEpc = cleanEpc;
      if (locationId != null) existing.locationId = locationId;
      await _dbService.insertPallet(existing);
    } else {
      final newP = Pallet(
        palletId: 'PAL-$cleanCode',
        palletCode: cleanCode,
        rfidEpc: cleanEpc,
        locationId: locationId,
        inboundTime: DateTime.now(),
      );
      _pallets.add(newP);
      await _dbService.insertPallet(newP);
    }

    // Lưu backup vĩnh viễn
    await _dbService.savePalletsBackup(_pallets);

    // Đồng bộ lên Supabase nếu có mạng
    final palToSync = _pallets.firstWhere((p) => p.palletCode.toUpperCase() == cleanCode);
    await _syncDirectOrQueue(
      tableName: 'pallets',
      recordId: palToSync.palletId,
      action: 'INSERT',
      payload: {
        'pallet_id': palToSync.palletId,
        'pallet_code': palToSync.palletCode,
        'location_id': palToSync.locationId,
        'inbound_time': palToSync.inboundTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
        'is_multi_sku': palToSync.isMultiSku ? 1 : 0,
      },
    );

    notifyListeners();
  }

  /// Xóa xe Pallet khỏi danh mục (xóa triệt để cả trong Database SQLite, File Backup và Cloud)
  Future<void> deletePalletFromMaster(String palletCode) async {
    final clean = palletCode.trim().toUpperCase();
    _pallets.removeWhere((p) =>
        p.palletCode.toUpperCase() == clean ||
        p.palletId.toUpperCase() == clean ||
        p.palletId.toUpperCase() == 'PAL-$clean');

    // 1. Xóa triệt để khỏi SQLite Database theo cả ID và Code
    await _dbService.deletePallet(clean);

    // 2. Cập nhật lại file backup vĩnh viễn
    await _dbService.savePalletsBackup(_pallets);

    // 3. Đồng bộ lệnh xóa lên Supabase Cloud
    await _syncDirectOrQueue(
      tableName: 'pallets',
      recordId: 'PAL-$clean',
      action: 'DELETE',
      payload: {'pallet_id': 'PAL-$clean', 'pallet_code': clean},
    );

    notifyListeners();
  }

  /// Gán trực tiếp danh sách các Item (theo danh sách mã EPC) vào một Pallet cụ thể
  Future<Pallet> assignItemsToPallet({
    required String palletCode,
    String? rfidEpc,
    required List<String> itemEpcs,
  }) async {
    final cleanPallet = palletCode.trim().toUpperCase();
    final cleanEpcs = itemEpcs.map((e) => e.trim().toUpperCase()).toSet();

    Pallet pallet = _pallets.firstWhere(
      (p) => p.palletCode.toUpperCase() == cleanPallet || p.palletId.toUpperCase() == cleanPallet,
      orElse: () {
        final newP = Pallet(
          palletId: 'PAL-$cleanPallet',
          palletCode: cleanPallet,
          rfidEpc: rfidEpc,
          inboundTime: DateTime.now(),
        );
        _pallets.add(newP);
        return newP;
      },
    );

    if (rfidEpc != null && rfidEpc.isNotEmpty) {
      pallet.rfidEpc = rfidEpc.trim().toUpperCase();
    }

    final updatedEpcs = <String>[];
    for (var it in _items.toList()) {
      if (cleanEpcs.contains(it.epc.toUpperCase())) {
        it.palletId = pallet.palletCode;
        if (!pallet.itemIds.contains(it.itemId)) {
          pallet.itemIds.add(it.itemId);
        }
        updatedEpcs.add(it.epc);
      }
    }
    if (updatedEpcs.isNotEmpty) {
      await _dbService.updateItemsLocationAndPallet(updatedEpcs, null, pallet.palletCode);
    }

    await _dbService.insertPallet(pallet);
    notifyListeners();
    return pallet;
  }

  /// Gán danh sách các thùng hàng (cartonCodes) lên một Pallet cụ thể
  Future<Pallet> assignCartonsToPallet({
    required String palletCode,
    String? rfidEpc,
    required List<String> cartonCodes,
  }) async {
    final cleanPallet = palletCode.trim().toUpperCase();
    final cleanCartons = cartonCodes.map((c) => c.trim().toUpperCase()).toSet();

    Pallet pallet = _pallets.firstWhere(
      (p) => p.palletCode.toUpperCase() == cleanPallet || p.palletId.toUpperCase() == cleanPallet,
      orElse: () {
        final newP = Pallet(
          palletId: 'PAL-$cleanPallet-${DateTime.now().millisecondsSinceEpoch}',
          palletCode: cleanPallet,
          inboundTime: DateTime.now(),
        );
        _pallets.add(newP);
        return newP;
      },
    );

    final updatedCartonEpcs = <String>[];
    for (var it in _items) {
      final itemCarton = it.palletId?.toUpperCase() ?? '';
      final itemOrder = it.orderNo?.toUpperCase() ?? '';
      if (cleanCartons.contains(itemCarton) || cleanCartons.contains(itemOrder)) {
        it.palletId = pallet.palletCode;
        if (!pallet.itemIds.contains(it.itemId)) {
          pallet.itemIds.add(it.itemId);
        }
        updatedCartonEpcs.add(it.epc);
      }
    }
    if (updatedCartonEpcs.isNotEmpty) {
      await _dbService.updateItemsLocationAndPallet(updatedCartonEpcs, null, pallet.palletCode);
    }

    await _dbService.insertPallet(pallet);
    notifyListeners();
    return pallet;
  }

  /// Cất Pallet vào vị trí ô kệ trống trong kho
  Future<int> putawayPalletToLocation({
    required String palletCodeOrId,
    required String locationId,
    String performedBy = 'Thủ kho Desktop',
  }) async {
    final cleanPallet = palletCodeOrId.trim().toUpperCase();
    Pallet pallet = _pallets.firstWhere(
      (p) => p.palletCode.toUpperCase() == cleanPallet || p.palletId.toUpperCase() == cleanPallet,
      orElse: () {
        final newP = Pallet(
          palletId: 'PAL-$cleanPallet-${DateTime.now().millisecondsSinceEpoch}',
          palletCode: cleanPallet,
          locationId: locationId,
          inboundTime: DateTime.now(),
        );
        _pallets.add(newP);
        return newP;
      },
    );

    pallet.locationId = locationId;
    await _dbService.updatePalletLocation(pallet.palletId, locationId);

    // Tìm tất cả các items thuộc pallet này
    final matchedItems = _items.where((it) =>
      it.palletId != null &&
      (it.palletId!.toUpperCase() == pallet.palletId.toUpperCase() ||
       it.palletId!.toUpperCase() == cleanPallet ||
       pallet.itemIds.contains(it.itemId))
    ).toList();

    for (var it in matchedItems) {
      it.locationId = locationId;
      it.status = ItemStatus.inStock;
      it.palletId = pallet.palletCode;
      await _dbService.updateItemLocationAndPallet(
        it.epc,
        locationId,
        pallet.palletCode,
        status: ItemStatus.inStock.code,
      );
    }

    // Cập nhật số lượng chứa cho Location
    final loc = _locations.where((l) =>
      l.locationId.toUpperCase() == locationId.toUpperCase() ||
      l.locationCode.toUpperCase() == locationId.toUpperCase()
    ).firstOrNull;
    if (loc != null) {
      loc.currentPallets = _pallets.where((p) => p.locationId == loc.locationId || p.locationId == loc.locationCode).length;
      await _dbService.insertLocation(loc);
    }

    notifyListeners();
    return matchedItems.length;
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

    // Nếu các mặt hàng này đã có mã Barcode Hex sinh sẵn lúc nạp danh sách nhập hàng, giữ nguyên mã đó
    final existingItemBarcode = matchedItems
        .map((i) => i.sku)
        .where((s) => s.isNotEmpty && s != cleanOrderNo && RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(s))
        .firstOrNull;

    // Sinh mã Barcode 128 chuẩn Hex (A-F và 0-9) nếu chưa có mã thùng cụ thể
    final effectiveCartonCode = (cartonCode != null && cartonCode.trim().isNotEmpty)
        ? cartonCode.trim().toUpperCase()
        : (existingItemBarcode ?? generateHexBarcode128());

    for (var it in matchedItems) {
      it.status = ItemStatus.waitingPutaway;
      // Barcode của hàng hóa được gắn theo barcode của thùng được sinh lúc nhập kho qua cổng
      it.palletId = effectiveCartonCode;
      it.sku = effectiveCartonCode;
      it.productId = effectiveCartonCode;
      it.locationId = null;
      it.inboundTime = now;
      if (it.orderNo == null || it.orderNo!.isEmpty) {
        it.orderNo = cleanOrderNo;
      }

      // Đảm bảo có bản ghi Product tương ứng cho mã Barcode mới sinh
      final existingProd = _products.where((p) => p.sku == effectiveCartonCode || p.productId == effectiveCartonCode).firstOrNull;
      if (existingProd == null) {
        // Tìm tên sản phẩm chuẩn hóa cho thùng hàng: Nếu tất cả item cùng 1 tên thì lấy tên đó, nếu nhiều tên khác nhau thì đặt 'Kiện hàng $effectiveCartonCode'
        final distinctNames = matchedItems
            .map((i) => i.productName.trim())
            .where((n) => n.isNotEmpty && n != 'Sản phẩm mẫu' && n != 'Item')
            .toSet()
            .toList();

        final String cartonProductName = distinctNames.length == 1
            ? distinctNames.first
            : 'Kiện hàng $effectiveCartonCode';

        final newProd = Product(
          productId: effectiveCartonCode,
          sku: effectiveCartonCode,
          productName: cartonProductName,
          unit: 'Cái',
          category: 'Hàng nhập qua cổng RFID',
        );
        _products.add(newProd);
        await _dbService.insertProduct(newProd);
        await _syncDirectOrQueue(
          tableName: 'products',
          recordId: newProd.productId,
          action: 'INSERT',
          payload: {
            'product_id': newProd.productId,
            'sku': newProd.sku,
            'product_name': newProd.productName,
            'unit': newProd.unit,
            'category': newProd.category,
          },
        );
      }

      await _dbService.insertItem(it);
      await _syncDirectOrQueue(
        tableName: 'items',
        recordId: it.itemId,
        action: 'UPDATE',
        payload: {
          'item_id': it.itemId,
          'product_id': it.productId,
          'sku': it.sku,
          'status': ItemStatus.waitingPutaway.code,
          'location_id': null,
          'pallet_id': it.palletId,
          'order_no': it.orderNo,
          'inbound_time': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
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
          'inbound_order_id': order.inboundOrderId,
          'status': InboundOrderStatus.waitingPutaway.code,
          'updated_at': now.toIso8601String(),
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

    // 1. Tìm theo InboundOrder tương ứng (theo orderNo, inboundOrderId HOẶC SKU trong details)
    if (matchedItems.isEmpty) {
      final matchedOrders = _inboundOrders.where((o) =>
        o.orderNo.trim().toUpperCase() == cleanBarcode ||
        o.inboundOrderId.trim().toUpperCase() == cleanBarcode ||
        o.details.any((d) => d.sku.trim().toUpperCase() == cleanBarcode || d.productId.trim().toUpperCase() == cleanBarcode)
      ).toList();

      if (matchedOrders.isNotEmpty) {
        final orderNos = matchedOrders.map((o) => o.orderNo.trim().toUpperCase()).toSet();
        final orderIds = matchedOrders.map((o) => o.inboundOrderId.trim().toUpperCase()).toSet();
        matchedItems = _items.where((it) =>
          it.orderNo != null &&
          (orderNos.contains(it.orderNo!.trim().toUpperCase()) ||
           orderIds.contains(it.orderNo!.trim().toUpperCase()))
        ).toList();
      }
    }

    // 2. Tra cứu trực tiếp từ SQLite theo LIKE / orderNo nếu bộ nhớ RAM chưa load kịp
    if (matchedItems.isEmpty) {
      final dbItems = await _dbService.getItems();
      final pulledFromDb = dbItems.where((it) =>
        (it.orderNo != null && it.orderNo!.trim().toUpperCase() == cleanBarcode) ||
        (it.palletId != null && it.palletId!.trim().toUpperCase() == cleanBarcode) ||
        it.sku.trim().toUpperCase() == cleanBarcode
      ).toList();
      if (pulledFromDb.isNotEmpty) {
        matchedItems = pulledFromDb;
        for (var pItem in pulledFromDb) {
          _items.removeWhere((i) => i.epc == pItem.epc);
          _items.add(pItem);
        }
      }
    }

    // 3. Nếu trên thiết bị PDA chưa có trong SQLite nội bộ, tra cứu Realtime từ Supabase Cloud
    if (matchedItems.isEmpty && SupabaseSyncService().isOnline) {
      try {
        final supa = Supabase.instance.client;
        final supaItems = await supa.from('items').select().or('sku.eq.$cleanBarcode,pallet_id.eq.$cleanBarcode,order_no.eq.$cleanBarcode,epc.eq.$cleanBarcode');
        if (supaItems.isNotEmpty) {
          final pulled = <Item>[];
          for (var row in supaItems) {
            final item = Item(
              itemId: row['item_id'] ?? '',
              productId: row['product_id'] ?? '',
              sku: row['sku'] ?? '',
              productName: row['product_name'] ?? '',
              serialNumber: row['serial_number'] ?? '',
              epc: row['epc'] ?? '',
              status: ItemStatus.values.firstWhere((s) => s.code == row['status'], orElse: () => ItemStatus.inStock),
              orderNo: row['order_no'],
              palletId: row['pallet_id'],
              locationId: row['location_id'],
              inboundTime: row['inbound_time'] != null ? DateTime.tryParse(row['inbound_time']) : null,
            );
            pulled.add(item);
            _items.removeWhere((i) => i.epc == item.epc);
            _items.add(item);
            await _dbService.insertItem(item);
          }
          matchedItems = pulled;
        } else {
          final supaOrders = await supa.from('inbound_orders').select().or('order_no.eq.$cleanBarcode,inbound_order_id.eq.$cleanBarcode');
          if (supaOrders.isNotEmpty) {
            for (var oRow in supaOrders) {
              final oNo = oRow['order_no'] ?? '';
              final relatedItems = await supa.from('items').select().eq('order_no', oNo);
              for (var row in relatedItems) {
                final item = Item(
                  itemId: row['item_id'] ?? '',
                  productId: row['product_id'] ?? '',
                  sku: row['sku'] ?? '',
                  productName: row['product_name'] ?? '',
                  serialNumber: row['serial_number'] ?? '',
                  epc: row['epc'] ?? '',
                  status: ItemStatus.values.firstWhere((s) => s.code == row['status'], orElse: () => ItemStatus.inStock),
                  orderNo: row['order_no'],
                  palletId: row['pallet_id'],
                  locationId: row['location_id'],
                  inboundTime: row['inbound_time'] != null ? DateTime.tryParse(row['inbound_time']) : null,
                );
                matchedItems.add(item);
                _items.removeWhere((i) => i.epc == item.epc);
                _items.add(item);
                await _dbService.insertItem(item);
              }
            }
          }
        }
      } catch (e) {
        debugPrint('Cloud fallback putaway search error: $e');
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

  /// Tự động tìm đơn xuất kho (Outbound Order) đang chờ xuất khớp với danh sách EPC quét được tại cổng
  OutboundOrder? findMatchingOutboundOrder(List<String> scannedEpcs) {
    if (scannedEpcs.isEmpty) return null;

    final pendingOrders = _outboundOrders.where((o) =>
      o.status != OutboundOrderStatus.shipped
    ).toList();

    if (pendingOrders.isEmpty) return null;

    final cleanScanned = scannedEpcs.map((e) => e.toUpperCase()).toSet();

    // 1. Ưu tiên cao nhất: Đơn xuất lẻ có chứa chính xác mã EPC trong danh sách epcList
    for (var order in pendingOrders) {
      for (var d in order.details) {
        if (d.epcList != null && d.epcList!.isNotEmpty) {
          final orderEpcs = d.epcList!.map((e) => e.toUpperCase()).toSet();
          if (cleanScanned.any((epc) => orderEpcs.contains(epc))) {
            return order;
          }
        }
      }
    }

    // 2. Tìm theo SKU / Mã sản phẩm / Thùng Pallet của các chip quét được
    final scannedItems = _items.where((it) => cleanScanned.contains(it.epc.toUpperCase())).toList();
    if (scannedItems.isEmpty) return null;

    final scannedSkus = scannedItems.map((it) => it.sku.toUpperCase()).toSet();
    final scannedProductIds = scannedItems.map((it) => it.productId.toUpperCase()).toSet();
    final scannedPalletIds = scannedItems.where((it) => it.palletId != null).map((it) => it.palletId!.toUpperCase()).toSet();

    OutboundOrder? bestOrder;
    int bestScore = 0;

    for (var order in pendingOrders) {
      int score = 0;
      for (var d in order.details) {
        final dSku = d.sku.toUpperCase();
        final dProd = d.productId.toUpperCase();
        if (scannedSkus.contains(dSku) || scannedProductIds.contains(dProd) || scannedPalletIds.contains(dSku)) {
          score += d.requiredQty;
        }
      }
      if (score > bestScore) {
        bestScore = score;
        bestOrder = order;
      }
    }

    return bestOrder;
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

    // Kiểm tra xem đơn có gán danh sách EPC cụ thể không (đơn xuất lẻ)
    final Set<String> explicitExpectedEpcs = {};
    for (var d in order.details) {
      if (d.epcList != null && d.epcList!.isNotEmpty) {
        explicitExpectedEpcs.addAll(d.epcList!.map((e) => e.toUpperCase()));
      }
    }

    final allowedSkus = order.details.map((d) => d.sku.toUpperCase()).toSet();

    final List<SkuVerificationBreakdown> breakdowns = [];
    bool allMatched = true;

    for (var epc in uniqueEpcs) {
      final item = _items.where((it) => it.epc.toUpperCase() == epc.toUpperCase()).firstOrNull;

      if (item == null) {
        unexpectedEpcs.add(epc);
      } else if (explicitExpectedEpcs.isNotEmpty && !explicitExpectedEpcs.contains(epc.toUpperCase())) {
        // Sai mã EPC lẻ
        unexpectedEpcs.add(epc);
      } else if (explicitExpectedEpcs.isEmpty && !allowedSkus.contains(item.sku.toUpperCase()) && !allowedSkus.contains(item.productId.toUpperCase()) && !(item.palletId != null && allowedSkus.contains(item.palletId!.toUpperCase()))) {
        // Sai SKU/Thùng
        unexpectedEpcs.add(epc);
      } else if (!isItemStockedInLocation(item)) {
        unstockedEpcs.add(epc);
        allMatched = false;
      } else {
        final matchedSku = order.details.where((d) =>
          d.sku.toUpperCase() == item.sku.toUpperCase() ||
          d.sku.toUpperCase() == item.productId.toUpperCase() ||
          (item.palletId != null && d.sku.toUpperCase() == item.palletId!.toUpperCase()) ||
          (d.epcList != null && d.epcList!.map((e) => e.toUpperCase()).contains(epc.toUpperCase()))
        ).firstOrNull?.sku ?? item.sku;

        actualSkuCounts[matchedSku] = (actualSkuCounts[matchedSku] ?? 0) + 1;
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

  Future<bool> confirmOutboundCompletion({
    required String poNo,
    required List<String> shippedEpcs,
    required String performedBy,
  }) async {
    final order = _outboundOrders.firstWhere((o) => o.poNo == poNo);

    final unstocked = shippedEpcs.where((epc) {
      final item = _items.where((it) => it.epc == epc).firstOrNull;
      if (item == null) return true;
      return !isItemStockedInLocation(item);
    }).toList();

    if (unstocked.isNotEmpty) {
      throw Exception('Không thể xuất kho: Có ${unstocked.length} sản phẩm chưa được xếp vào kệ nào trong kho (Đang chờ xếp kệ hoặc chưa gán vị trí)!');
    }

    final now = DateTime.now();

    for (var epc in shippedEpcs) {
      final item = _items.firstWhere((it) => it.epc == epc);
      item.status = ItemStatus.out;
      item.locationId = null;
      if (item.palletId != null) {
        final pal = _pallets.where((p) => p.palletId == item.palletId).firstOrNull;
        pal?.itemIds.remove(item.itemId);
      }
      await _dbService.updateItemStatus(epc, ItemStatus.out);
      await _dbService.updateItemLocationAndPallet(epc, null, item.palletId);
      await _dbService.insertItem(item);
    }

    order.status = OutboundOrderStatus.shipped;
    await _dbService.updateOutboundOrderStatus(order.outboundOrderId, OutboundOrderStatus.shipped);

    for (var d in order.details) {
      _transactions.insert(
        0,
        InventoryTransaction(
          transactionId: 'TX-${now.millisecondsSinceEpoch}-${d.sku}',
          type: TransactionType.outbound,
          documentNo: poNo,
          sku: d.sku,
          productName: d.productName,
          quantity: d.requiredQty,
          fromLocation: 'KHO_TONG',
          toLocation: 'KHACH_HANG: ${order.customer}',
          performedBy: performedBy,
          timestamp: now,
          notes: 'Xuất kho thành công, Gate OUTBOUND PASS',
        ),
      );
    }

    ErpBravoService().pushOutboundCompleted(poNo, shippedEpcs.length);

    await _syncDirectOrQueue(
      tableName: 'outbound_transactions',
      recordId: poNo,
      action: 'OUTBOUND_CONFIRM',
      payload: {
        'poNo': poNo,
        'shippedEpcs': shippedEpcs,
        'performedBy': performedBy,
        'timestamp': now.toIso8601String(),
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
        item.locationId = null;
        if (item.palletId != null) {
          final pal = _pallets.where((p) => p.palletId == item.palletId).firstOrNull;
          pal?.itemIds.remove(item.itemId);
        }
        await _dbService.updateItemStatus(epc, ItemStatus.out);
        await _dbService.updateItemLocationAndPallet(epc, null, item.palletId);
        await _dbService.insertItem(item);
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
    _dbService.insertInventorySession(session);
    _syncDirectOrQueue(
      tableName: 'inventory_sessions',
      recordId: session.sessionId,
      action: 'INSERT',
      payload: {
        'session_id': session.sessionId,
        'session_code': session.sessionCode,
        'zone': session.zone,
        'location_code': session.locationCode,
        'started_at': session.startedAt.toIso8601String(),
        'completed_at': null,
        'is_completed': 0,
      },
    );
    _triggerBackgroundSync();
    notifyListeners();
    return session;
  }

  void processAuditScan({
    required String sessionId,
    required List<String> scannedEpcs,
  }) {
    final session = _inventorySessions.where((s) => s.sessionId == sessionId).firstOrNull;
    if (session == null || session.isCompleted) return;
    session.results.clear();

    final uniqueScannedEpcs = scannedEpcs.toSet();

    final isAllWarehouse = session.zone.trim().toLowerCase().contains('toàn bộ') ||
        session.zone.trim().toUpperCase() == 'ALL' ||
        (session.locationCode == null && session.zone.isEmpty);

    final expectedItems = _items.where((it) {
      if (it.status != ItemStatus.inStock) return false;
      if (isAllWarehouse) return true;
      final loc = _locations.firstWhere((l) => l.locationId == it.locationId, orElse: () => Location(locationId: '', locationCode: '', zone: '', shelf: '', level: ''));
      if (session.locationCode != null && session.locationCode!.isNotEmpty) {
        return loc.locationCode.trim().toUpperCase() == session.locationCode!.trim().toUpperCase();
      }
      return loc.zone.trim().toUpperCase() == session.zone.trim().toUpperCase() ||
             loc.locationCode.trim().toUpperCase().startsWith(session.zone.trim().toUpperCase());
    }).toList();

    final expectedEpcs = expectedItems.map((e) => e.epc).toSet();

    for (var epc in uniqueScannedEpcs) {
      final item = _items.firstWhere(
        (it) => it.epc == epc,
        orElse: () => Item(itemId: '', productId: '', sku: 'UNKNOWN', productName: 'Thẻ chưa khai báo', serialNumber: '', epc: epc),
      );

      if (item.sku == 'UNKNOWN' || item.itemId.isEmpty) {
        session.results.add(
          InventoryItemResult(
            epc: epc,
            resultType: InventoryVarianceType.unknownEpc,
            readAt: DateTime.now(),
          ),
        );
      } else if (isAllWarehouse || expectedEpcs.contains(epc)) {
        final actualLoc = _locations.firstWhere((l) => l.locationId == item.locationId, orElse: () => Location(locationId: '', locationCode: item.locationId ?? 'Chưa gán kệ', zone: '', shelf: '', level: ''));
        session.results.add(
          InventoryItemResult(
            epc: epc,
            sku: item.sku,
            productName: item.productName,
            expectedLocation: actualLoc.locationCode,
            actualLocation: actualLoc.locationCode,
            resultType: InventoryVarianceType.match,
            readAt: DateTime.now(),
          ),
        );
      } else {
        final actualLoc = _locations.firstWhere((l) => l.locationId == item.locationId, orElse: () => Location(locationId: '', locationCode: item.locationId ?? 'Chưa rõ', zone: '', shelf: '', level: ''));
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
        final actualLoc = _locations.firstWhere((l) => l.locationId == expItem.locationId, orElse: () => Location(locationId: '', locationCode: expItem.locationId ?? 'Chưa gán kệ', zone: '', shelf: '', level: ''));
        session.results.add(
          InventoryItemResult(
            epc: expItem.epc,
            sku: expItem.sku,
            productName: expItem.productName,
            expectedLocation: actualLoc.locationCode,
            actualLocation: 'Không thấy',
            resultType: InventoryVarianceType.missing,
            readAt: DateTime.now(),
          ),
        );
      }
    }

    _dbService.insertInventorySession(session);
    notifyListeners();
  }

  Future<void> completeInventorySession(String sessionId, String approvedBy) async {
    final session = _inventorySessions.firstWhere((s) => s.sessionId == sessionId);
    session.isCompleted = true;
    session.completedAt = DateTime.now();

    // 1. Lưu SQLite
    await _dbService.insertInventorySession(session);

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

    // 2. Đồng bộ Supabase qua hàng đợi nền (cực nhanh, không block UI thread)
    _syncDirectOrQueue(
      tableName: 'inventory_sessions',
      recordId: session.sessionId,
      action: 'INSERT',
      payload: {
        'session_id': session.sessionId,
        'session_code': session.sessionCode,
        'zone': session.zone,
        'location_code': session.locationCode,
        'started_at': session.startedAt.toIso8601String(),
        'completed_at': session.completedAt?.toIso8601String(),
        'is_completed': 1,
        'created_by': approvedBy,
      },
    );

    for (final r in session.results) {
      _dbService.enqueueSync(
        tableName: 'inventory_session_details',
        recordId: '${session.sessionId}-${r.epc}',
        action: 'INSERT',
        payload: {
          'session_id': session.sessionId,
          'epc': r.epc,
          'sku': r.sku,
          'product_name': r.productName,
          'expected_location': r.expectedLocation,
          'actual_location': r.actualLocation,
          'result_type': r.resultType.code,
          'read_at': r.readAt.toIso8601String(),
        },
      );
    }

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

  Future<void> deletePallet(String palletId) async {
    final cleanId = palletId.trim().toUpperCase();
    _pallets.removeWhere((p) => p.palletId.toUpperCase() == cleanId || p.palletCode.toUpperCase() == cleanId);
    await _dbService.deletePallet(cleanId);
    await _syncDirectOrQueue(
      tableName: 'pallets',
      recordId: cleanId,
      action: 'DELETE',
      payload: {'pallet_id': cleanId},
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<bool> mergePallets({
    required String sourcePalletId,
    required String targetPalletId,
    required String performedBy,
    bool deleteSourcePallet = false,
  }) async {
    final cleanSource = sourcePalletId.trim().toUpperCase();
    final cleanTarget = targetPalletId.trim().toUpperCase();

    if (cleanSource == cleanTarget) {
      throw Exception('Không thể gộp một Pallet vào chính nó.');
    }

    final sourcePallet = _pallets.firstWhere(
      (p) => p.palletId.toUpperCase() == cleanSource || p.palletCode.toUpperCase() == cleanSource,
      orElse: () => throw Exception('Không tìm thấy Pallet nguồn: $sourcePalletId'),
    );

    final targetPallet = _pallets.firstWhere(
      (p) => p.palletId.toUpperCase() == cleanTarget || p.palletCode.toUpperCase() == cleanTarget,
      orElse: () => throw Exception('Không tìm thấy Pallet đích: $targetPalletId'),
    );

    // Tìm tất cả các mặt hàng thuộc Pallet nguồn
    final itemsToMove = _items.where((it) =>
      it.palletId != null &&
      (it.palletId!.toUpperCase() == sourcePallet.palletId.toUpperCase() ||
       it.palletId!.toUpperCase() == sourcePallet.palletCode.toUpperCase() ||
       sourcePallet.itemIds.contains(it.itemId))
    ).toList();

    if (itemsToMove.isEmpty) {
      throw Exception('Pallet nguồn ${sourcePallet.palletCode} hiện không có mặt hàng nào để gộp.');
    }

    final movedItemCount = itemsToMove.length;
    final targetLocationId = targetPallet.locationId;

    // Chuyển toàn bộ hàng sang Pallet đích
    for (var item in itemsToMove) {
      item.palletId = targetPallet.palletId;
      item.locationId = targetLocationId;

      await _dbService.updateItemLocationAndPallet(item.epc, targetLocationId, targetPallet.palletId);

      if (!targetPallet.itemIds.contains(item.itemId)) {
        targetPallet.itemIds.add(item.itemId);
      }

      await _syncDirectOrQueue(
        tableName: 'items',
        recordId: item.itemId,
        action: 'UPDATE',
        payload: {
          'itemId': item.itemId,
          'palletId': targetPallet.palletId,
          'locationId': targetLocationId,
        },
      );
    }

    // Làm rỗng Pallet nguồn
    sourcePallet.itemIds.clear();
    sourcePallet.isMultiSku = false;

    // Đánh giá lại isMultiSku cho Pallet đích
    final allTargetItems = _items.where((it) => it.palletId == targetPallet.palletId).toList();
    targetPallet.isMultiSku = allTargetItems.map((e) => e.sku).toSet().length > 1;

    await _dbService.insertPallet(targetPallet);
    await _syncDirectOrQueue(
      tableName: 'pallets',
      recordId: targetPallet.palletId,
      action: 'UPDATE',
      payload: {
        'pallet_id': targetPallet.palletId,
        'pallet_code': targetPallet.palletCode,
        'location_id': targetPallet.locationId,
        'is_multi_sku': targetPallet.isMultiSku ? 1 : 0,
      },
    );

    // Xử lý Pallet nguồn sau gộp
    if (deleteSourcePallet) {
      _pallets.removeWhere((p) => p.palletId == sourcePallet.palletId);
      await _dbService.deletePallet(sourcePallet.palletId);
      await _syncDirectOrQueue(
        tableName: 'pallets',
        recordId: sourcePallet.palletId,
        action: 'DELETE',
        payload: {'pallet_id': sourcePallet.palletId},
      );
    } else {
      await _dbService.insertPallet(sourcePallet);
      await _syncDirectOrQueue(
        tableName: 'pallets',
        recordId: sourcePallet.palletId,
        action: 'UPDATE',
        payload: {
          'pallet_id': sourcePallet.palletId,
          'pallet_code': sourcePallet.palletCode,
          'location_id': sourcePallet.locationId,
          'is_multi_sku': 0,
        },
      );
    }

    // Ghi nhận nhật ký chuyển kho / gộp pallet
    _transactions.insert(
      0,
      InventoryTransaction(
        transactionId: 'TX-MERGE-${DateTime.now().millisecondsSinceEpoch}',
        type: TransactionType.movement,
        documentNo: 'MERGE-${sourcePallet.palletCode}->${targetPallet.palletCode}',
        sku: 'PALLET_MERGE',
        productName: 'Gộp $movedItemCount mặt hàng từ ${sourcePallet.palletCode} sang ${targetPallet.palletCode}',
        quantity: movedItemCount,
        fromLocation: sourcePallet.locationId ?? 'N/A',
        toLocation: targetPallet.locationId ?? 'N/A',
        palletCode: targetPallet.palletCode,
        performedBy: performedBy,
        timestamp: DateTime.now(),
        notes: 'Nhập gộp $movedItemCount sản phẩm từ Pallet ${sourcePallet.palletCode} vào Pallet ${targetPallet.palletCode}',
      ),
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
