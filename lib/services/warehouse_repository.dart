import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/wms_models.dart';
import 'erp_bravo_service.dart';
import 'database_service.dart';
import 'mysql_sync_service.dart';

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

  Future<void> _loadFromSqlite() async {
    try {
      final dbProducts = await _dbService.getProducts();
      final dbLocations = await _dbService.getLocations();
      final dbPallets = await _dbService.getPallets();
      final dbItems = await _dbService.getItems();
      final dbInboundOrders = await _dbService.getInboundOrders();
      final dbOutboundOrders = await _dbService.getOutboundOrders();

      _products.clear();
      _products.addAll(dbProducts);

      _locations.clear();
      _locations.addAll(dbLocations);

      _pallets.clear();
      _pallets.addAll(dbPallets);

      _items.clear();
      _items.addAll(dbItems);
      for (final p in _pallets) {
        p.itemIds.clear();
        p.itemIds.addAll(_items.where((i) => i.palletId == p.palletId).map((i) => i.itemId));
      }

      _inboundOrders.clear();
      _inboundOrders.addAll(dbInboundOrders);

      _outboundOrders.clear();
      _outboundOrders.addAll(dbOutboundOrders);

      notifyListeners();
    } catch (e) {
      debugPrint('WarehouseRepository: SQLite load error: $e');
    }
  }

  Future<void> refreshFromDatabase() => _loadFromSqlite();

  Future<void> deleteInboundOrder(String orderId) async {
    final cleanId = orderId.trim();
    await _dbService.deleteInboundOrder(cleanId);
    _inboundOrders.removeWhere((o) => o.inboundOrderId == cleanId || o.orderNo == cleanId);
    _items.removeWhere((i) => i.orderNo == cleanId);

    // Enqueue sync delete or direct MySQL delete
    await _dbService.enqueueSync(
      tableName: 'inbound_orders',
      recordId: cleanId,
      action: 'DELETE',
      payload: {'orderId': cleanId},
    );

    notifyListeners();
  }

  Future<void> clearAllData({bool alsoClearMySql = true}) async {
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

    if (alsoClearMySql) {
      await MySqlSyncService().clearAllMySqlData();
    }

    notifyListeners();
  }


  /// Tạo mã EPC 96-bit (24 ký tự Hex) chuẩn Gen2 duy nhất cho từng sản phẩm
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

  /// Lấy danh sách các Item (Mã EPC) thuộc về một Đơn Nhập kho
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

  /// Tạo Phiếu Nhập Kho & Tự động sinh danh sách mã EPC duy nhất ở trạng thái CHƯA NHẬP KHO
  Future<List<Item>> addInboundOrder(InboundOrder order, {bool autoGenerateEpcs = true}) async {
    await _dbService.insertInboundOrder(order);
    _inboundOrders.add(order);
    await _dbService.enqueueSync(
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
            status: ItemStatus.pendingInbound, // Trạng thái: "Chưa nhập kho" (Chờ quét qua cổng/trạm)
            orderNo: order.orderNo,
            palletId: null,
            locationId: null,
            inboundTime: null,
          );
          generatedItems.add(item);
          _items.add(item);
          await _dbService.insertItem(item);
          await _dbService.enqueueSync(
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

  /// Import danh sách nhiều đơn nhập hàng loạt từ Excel & tự động sinh toàn bộ mã EPC
  Future<List<Item>> batchImportInboundOrders(List<InboundOrder> orders) async {
    final List<Item> allGeneratedItems = [];
    for (var order in orders) {
      final items = await addInboundOrder(order, autoGenerateEpcs: true);
      allGeneratedItems.addAll(items);
    }
    return allGeneratedItems;
  }

  /// Thêm trực tiếp 1 Item (từ file Excel có sẵn Serial/EPC) vào kho & SQLite
  Future<void> insertDirectItem(Item item) async {
    _items.removeWhere((i) => i.epc == item.epc);
    _items.add(item);
    await _dbService.insertItem(item);
    await _dbService.enqueueSync(
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
    await _dbService.enqueueSync(
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

  Future<void> addProduct(Product product) async {
    await _dbService.insertProduct(product);
    _products.add(product);
    await _dbService.enqueueSync(
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
    await _dbService.enqueueSync(
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

  void _triggerBackgroundSync() {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final syncService = MySqlSyncService();
      if (syncService.config.isAutoSync) {
        syncService.syncNow();
      }
    } catch (_) {}
  }

  // Danh mục dữ liệu (Bắt đầu hoàn toàn trống 100% trong SQLite)
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

  // Getters
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

  // ==========================================
  // 2. NGHIỆP VỤ NHẬP KHO (INBOUND)
  // ==========================================

  /// Khởi tạo các Item mới cho lệnh nhập và mã hóa tem
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

  /// Gán Item vào Pallet và Location tạm
  Pallet createOrAssignPallet({
    required String palletCode,
    required String locationId,
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
      if (!_items.any((it) => it.epc == item.epc)) {
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

  /// Đối chiếu tại RFID Gate - INBOUND
  GateVerificationResult verifyGateInbound({
    required String orderNo,
    required List<String> scannedEpcs,
  }) {
    final order = _inboundOrders.firstWhere((o) => o.orderNo == orderNo);
    // Khử trùng danh sách EPC
    final uniqueEpcs = scannedEpcs.toSet().toList();

    // Map EPC sang Item
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

    // So sánh chi tiết từng SKU
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

    // Nếu có thẻ lạ hoặc SKU không thuộc đơn thì FAIL
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

  /// Xác nhận hoàn tất nhập kho
  bool confirmInboundCompletion({
    required String orderNo,
    required String palletCode,
    required String locationId,
    required String performedBy,
  }) {
    final order = _inboundOrders.firstWhere((o) => o.orderNo == orderNo);
    final pallet = _pallets.firstWhere((p) => p.palletCode == palletCode);
    final location = _locations.firstWhere((l) => l.locationId == locationId);

    // Chuyển Item sang IN_STOCK
    for (var itemId in pallet.itemIds) {
      final item = _items.firstWhere((it) => it.itemId == itemId);
      item.status = ItemStatus.inStock;
      item.inboundTime = DateTime.now();
      item.locationId = locationId;
      _dbService.updateItemLocationAndPallet(item.epc, locationId, pallet.palletId);
      _dbService.updateItemStatus(item.epc, ItemStatus.inStock);
    }

    // Cập nhật lệnh nhập
    order.status = InboundOrderStatus.completed;
    _dbService.updateInboundOrderStatus(order.inboundOrderId, InboundOrderStatus.completed, locationId: locationId, palletId: pallet.palletId);
    for (var d in order.details) {
      d.receivedQty = d.requiredQty;
    }

    // Cập nhật vị trí lưu pallet
    pallet.locationId = locationId;
    _dbService.updatePalletLocation(pallet.palletId, locationId);
    location.currentPallets++;

    // Ghi log giao dịch
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

    // Bắn sync về ERP Bravo
    ErpBravoService().pushInboundCompleted(orderNo, pallet.itemIds.length);

    // Lưu vào hàng đợi đồng bộ MySQL (Offline-first)
    _dbService.enqueueSync(
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

  /// Giai đoạn 1: Kiện hàng đi qua Cổng RFID Gate -> Quét đủ thẻ -> Chuyển thành CHỜ XẾP KHO (WAITING_PUTAWAY)
  Future<int> confirmGateReceiveToWaitingPutaway({
    required String orderNo,
    required List<String> scannedEpcs,
    String? cartonCode,
    String performedBy = 'Cổng RFID Gate',
  }) async {
    final cleanOrderNo = orderNo.trim().toUpperCase();
    final uniqueEpcs = scannedEpcs.toSet().toList();
    final now = DateTime.now();

    // 1. Tìm đơn nhập kho
    final order = _inboundOrders.where((o) =>
      o.orderNo.trim().toUpperCase() == cleanOrderNo ||
      o.inboundOrderId.trim().toUpperCase() == cleanOrderNo
    ).firstOrNull;

    // 2. Chuyển trạng thái các Items sang WAITING_PUTAWAY (Chờ xếp kho)
    //    KHÔNG gán locationId hay palletId — chỉ PDA putaway mới gán
    final matchedItems = _items.where((it) {
      if (uniqueEpcs.contains(it.epc)) return true;
      if (it.orderNo != null && it.orderNo!.trim().toUpperCase() == cleanOrderNo) return true;
      return false;
    }).toList();

    for (var it in matchedItems) {
      it.status = ItemStatus.waitingPutaway;
      it.palletId = null;
      it.locationId = null;
      it.inboundTime = now;
      if (it.orderNo == null || it.orderNo!.isEmpty) {
        it.orderNo = cleanOrderNo;
      }
      await _dbService.insertItem(it);
      await _dbService.enqueueSync(
        tableName: 'items',
        recordId: it.itemId,
        action: 'UPDATE',
        payload: {
          'itemId': it.itemId,
          'status': ItemStatus.waitingPutaway.code,
          'locationId': null,
          'palletId': null,
          'orderNo': it.orderNo,
          'inboundTime': now.toIso8601String(),
        },
      );
    }

    // 3. Cập nhật trạng thái Đơn hàng sang WAITING_PUTAWAY
    if (order != null) {
      order.status = InboundOrderStatus.waitingPutaway;
      for (var d in order.details) {
        d.receivedQty = d.requiredQty;
      }
      await _dbService.updateInboundOrderStatus(order.inboundOrderId, InboundOrderStatus.waitingPutaway);
      await _dbService.enqueueSync(
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

    // 4. Ghi nhận giao dịch Cổng tiếp nhận
    _dbService.enqueueSync(
      tableName: 'inbound_transactions',
      recordId: cleanOrderNo,
      action: 'GATE_RECEIVE_WAITING_PUTAWAY',
      payload: {
        'orderNo': cleanOrderNo,
        'cartonCode': cartonCode ?? cleanOrderNo,
        'itemCount': matchedItems.length,
        'performedBy': performedBy,
        'timestamp': now.toIso8601String(),
      },
    );

    _triggerBackgroundSync();
    notifyListeners();
    return matchedItems.length;
  }

  /// Giai đoạn 2: Thủ kho cầm PDA quét Barcode Vị trí kệ và quét Barcode Thùng hàng -> Xác nhận vị trí & Chuyển sang TRONG KHO (IN_STOCK)
  Future<int> confirmPdaPutawayByCarton({
    required String cartonOrOrderBarcode,
    required String locationId,
    String performedBy = 'Thủ kho PDA',
  }) async {
    final cleanBarcode = cartonOrOrderBarcode.trim().toUpperCase();
    final now = DateTime.now();

    // 1. Tìm vị trí kệ
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

    // 2. Tìm tất cả items thuộc thùng hàng, mã barcode ngoài thùng hoặc mã EPC này
    final matchedItems = _items.where((it) {
      if (it.orderNo != null && it.orderNo!.trim().toUpperCase() == cleanBarcode) return true;
      if (it.palletId != null && it.palletId!.trim().toUpperCase() == cleanBarcode) return true;
      if (it.sku.trim().toUpperCase() == cleanBarcode) return true;
      if (it.epc.trim().toUpperCase() == cleanBarcode || it.serialNumber.trim().toUpperCase() == cleanBarcode) return true;
      return false;
    }).toList();

    if (matchedItems.isEmpty) return 0;

    // 3. Cập nhật tất cả Item trong thùng sang IN_STOCK và lưu vị trí kệ mới nhất
    for (var it in matchedItems) {
      final oldLoc = it.locationId ?? 'LOC-GATE-IN';
      it.status = ItemStatus.inStock;
      it.locationId = loc.locationId;
      it.inboundTime ??= now;

      await _dbService.updateItemLocationAndPallet(it.epc, loc.locationId, it.palletId);
      await _dbService.updateItemStatus(it.epc, ItemStatus.inStock);

      await _dbService.enqueueSync(
        tableName: 'items',
        recordId: it.itemId,
        action: 'UPDATE',
        payload: {
          'itemId': it.itemId,
          'status': ItemStatus.inStock.code,
          'locationId': loc.locationId,
          'updatedAt': now.toIso8601String(),
        },
      );

      // Ghi log biến động vị trí (Putaway)
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

    // 4. Cập nhật trạng thái Đơn hàng sang COMPLETED (Hoàn tất nhập kho)
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
      await _dbService.enqueueSync(
        tableName: 'inbound_orders',
        recordId: order.inboundOrderId,
        action: 'UPDATE',
        payload: {
          'inboundOrderId': order.inboundOrderId,
          'status': InboundOrderStatus.completed.code,
          'locationId': loc.locationId,
          'updatedAt': now.toIso8601String(),
        },
      );
    }

    // 5. Ghi nhận giao dịch hoàn tất Putaway
    _dbService.enqueueSync(
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

  /// Nhập kho trực tiếp bằng súng quét tay cầm Chainway C72e
  Future<int> confirmHandheldInbound({
    String? orderNo,
    required String palletCode,
    required String locationId,
    required List<String> scannedEpcs,
    String? defaultSku,
    String? defaultProductName,
    String performedBy = 'Thủ kho PDA',
  }) async {
    final uniqueEpcs = scannedEpcs.toSet().toList();
    if (uniqueEpcs.isEmpty) return 0;

    final loc = _locations.where((l) => l.locationId == locationId).firstOrNull ??
        Location(locationId: locationId, locationCode: locationId, zone: 'Khu vực Nhập', shelf: 'Kệ 01', level: 'Tầng 1');

    // Tạo hoặc lấy Pallet
    final pallet = createOrAssignPallet(
      palletCode: palletCode,
      locationId: locationId,
      newItems: [],
    );

    final now = DateTime.now();
    int count = 0;

    for (var epc in uniqueEpcs) {
      count++;
      Item? item = _items.where((it) => it.epc == epc).firstOrNull;
      if (item != null) {
        item.status = ItemStatus.inStock;
        item.locationId = locationId;
        item.palletId = pallet.palletId;
        item.inboundTime = now;
        await _dbService.insertItem(item);
      } else {
        final newItem = Item(
          itemId: 'ITEM-${now.millisecondsSinceEpoch}-$count',
          productId: 'PROD-$count',
          sku: defaultSku ?? 'SKU-INBOUND',
          productName: defaultProductName ?? 'Hàng nhập thực tế',
          serialNumber: 'SN-${epc.length > 6 ? epc.substring(epc.length - 6) : epc}',
          epc: epc,
          status: ItemStatus.inStock,
          palletId: pallet.palletId,
          locationId: locationId,
          inboundTime: now,
        );
        _items.add(newItem);
        if (!pallet.itemIds.contains(newItem.itemId)) {
          pallet.itemIds.add(newItem.itemId);
        }
        await _dbService.insertItem(newItem);
      }
    }

    // Cập nhật trạng thái đơn nếu có
    if (orderNo != null) {
      final orderIndex = _inboundOrders.indexWhere((o) => o.orderNo == orderNo);
      if (orderIndex != -1) {
        final order = _inboundOrders[orderIndex];
        order.status = InboundOrderStatus.completed;
        for (var d in order.details) {
          d.receivedQty = d.requiredQty;
        }
        await _dbService.updateInboundOrderStatus(order.inboundOrderId, InboundOrderStatus.completed, locationId: locationId, palletId: pallet.palletId);
      }
    }

    // Ghi nhận lịch sử giao dịch
    _transactions.insert(
      0,
      InventoryTransaction(
        transactionId: 'TX-${DateTime.now().millisecondsSinceEpoch}',
        type: TransactionType.inbound,
        documentNo: orderNo ?? 'PDA-DIRECT-IN',
        sku: defaultSku ?? 'MULTI-SKU',
        productName: defaultProductName ?? 'Nhập kho quét RFID',
        quantity: uniqueEpcs.length,
        toLocation: loc.locationCode,
        palletCode: palletCode,
        performedBy: performedBy,
        timestamp: now,
        notes: 'Nhập $count thẻ RFID qua PDA vào Pallet $palletCode - Vị trí ${loc.locationCode}',
      ),
    );

    // Đồng bộ ERP Bravo
    ErpBravoService().pushInboundCompleted(orderNo ?? 'PDA-DIRECT-IN', uniqueEpcs.length);

    // Lưu vào hàng đợi đồng bộ MySQL (Offline-first)
    _dbService.enqueueSync(
      tableName: 'inbound_transactions',
      recordId: orderNo ?? 'PDA-DIRECT-${now.millisecondsSinceEpoch}',
      action: 'INBOUND_PDA_CONFIRM',
      payload: {
        'orderNo': orderNo,
        'palletCode': palletCode,
        'locationId': locationId,
        'epcs': uniqueEpcs,
        'sku': defaultSku,
        'productName': defaultProductName,
        'performedBy': performedBy,
        'timestamp': now.toIso8601String(),
      },
    );
    _triggerBackgroundSync();

    notifyListeners();
    return uniqueEpcs.length;
  }

  // ==========================================
  // 3. THUẬT TOÁN GỢI Ý XUẤT THEO FIFO
  // ==========================================

  /// Tính toán kế hoạch lấy hàng (Picking Plan) theo nguyên tắc FIFO
  PickingPlan generateFifoPickingPlan(String outboundOrderId) {
    final order = _outboundOrders.firstWhere((o) => o.outboundOrderId == outboundOrderId);
    final List<PickingPlanLine> lines = [];

    for (var detail in order.details) {
      int remainingQtyNeeded = detail.requiredQty;

      // 1. Lấy tất cả Item khả dụng của SKU này
      final availableItems = _items.where(
        (it) => it.productId == detail.productId && it.status == ItemStatus.inStock && it.palletId != null,
      ).toList();

      // 2. Nhóm theo Pallet
      final Map<String, List<Item>> palletGroups = {};
      for (var it in availableItems) {
        palletGroups.putIfAbsent(it.palletId!, () => []).add(it);
      }

      // 3. Sắp xếp các Pallet theo ngày nhập tăng dần (Nhập trước -> Xuất trước)
      final sortedPalletIds = palletGroups.keys.toList()
        ..sort((a, b) {
          final pA = _pallets.firstWhere((p) => p.palletId == a);
          final pB = _pallets.firstWhere((p) => p.palletId == b);
          final timeA = pA.inboundTime ?? DateTime.now();
          final timeB = pB.inboundTime ?? DateTime.now();
          return timeA.compareTo(timeB);
        });

      // 4. Bóc tách từng Pallet cho đến khi đủ số lượng
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

        // Đánh dấu Item tạm khóa sang ALLOCATED
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

  /// Xác nhận đã lấy hàng theo dòng picking
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

  /// Đối chiếu tại RFID Gate - OUTBOUND
  GateVerificationResult verifyGateOutbound({
    required String poNo,
    required List<String> scannedEpcs,
  }) {
    final order = _outboundOrders.firstWhere((o) => o.poNo == poNo);
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
      mode: GateMode.outbound,
      documentNo: poNo,
      totalRequiredQty: totalReq,
      totalActualQty: totalAct,
      skuBreakdowns: breakdowns,
      unexpectedEpcs: unexpectedEpcs,
      missingEpcs: [],
      verifiedAt: DateTime.now(),
    );
  }

  /// Xác nhận hoàn tất xuất kho
  bool confirmOutboundCompletion({
    required String poNo,
    required List<String> shippedEpcs,
    required String performedBy,
  }) {
    final order = _outboundOrders.firstWhere((o) => o.poNo == poNo);

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

    // Bắn sync về ERP Bravo
    ErpBravoService().pushOutboundCompleted(poNo, shippedEpcs.length);

    // Lưu vào hàng đợi đồng bộ MySQL (Offline-first)
    _dbService.enqueueSync(
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

  /// Xuất kho trực tiếp (Không bắt buộc theo đơn PO trước)
  Future<int> confirmDirectOutbound({
    String? poNo,
    required List<String> scannedEpcs,
    String performedBy = 'Thủ kho Desktop',
  }) async {
    final uniqueEpcs = scannedEpcs.toSet().toList();
    if (uniqueEpcs.isEmpty) return 0;
    final now = DateTime.now();

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

    // Đồng bộ MySQL
    _dbService.enqueueSync(
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

  // ==========================================
  // 4. KIỂM KÊ KHO (INVENTORY AUDIT)
  // ==========================================

  /// Tạo phiên kiểm kê mới
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

  /// Xử lý quét đối chiếu kiểm kê
  void processAuditScan({
    required String sessionId,
    required List<String> scannedEpcs,
  }) {
    final session = _inventorySessions.firstWhere((s) => s.sessionId == sessionId);
    session.results.clear();

    final uniqueScannedEpcs = scannedEpcs.toSet();

    // 1. Lấy danh sách Item mong đợi tại khu vực này
    final expectedItems = _items.where((it) {
      if (it.status != ItemStatus.inStock) return false;
      final loc = _locations.firstWhere((l) => l.locationId == it.locationId, orElse: () => Location(locationId: '', locationCode: '', zone: '', shelf: '', level: ''));
      if (session.locationCode != null && session.locationCode!.isNotEmpty) {
        return loc.locationCode == session.locationCode;
      }
      return loc.zone == session.zone;
    }).toList();

    final expectedEpcs = expectedItems.map((e) => e.epc).toSet();

    // MATCH & WRONG_LOCATION & UNKNOWN_EPC
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
        // Đọc thấy nhưng trên hệ thống đang ghi ở vị trí khác
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

    // MISSING: Mong đợi mà không đọc thấy
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

  /// Chốt phiên kiểm kê
  void completeInventorySession(String sessionId, String approvedBy) {
    final session = _inventorySessions.firstWhere((s) => s.sessionId == sessionId);
    session.isCompleted = true;
    session.completedAt = DateTime.now();

    // Ghi log giao dịch điều chỉnh kiểm kê
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

    // Lưu vào hàng đợi đồng bộ MySQL (Offline-first)
    _dbService.enqueueSync(
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

  // ==========================================
  // 5. QUẢN LÝ LƯU KHO & DI CHUYỂN PALLET
  // ==========================================

  /// Di chuyển Pallet sang Location mới
  bool movePallet({
    required String palletId,
    required String newLocationId,
    required String performedBy,
  }) {
    final pallet = _pallets.firstWhere((p) => p.palletId == palletId);
    final oldLocation = _locations.firstWhere((l) => l.locationId == pallet.locationId, orElse: () => Location(locationId: '', locationCode: 'N/A', zone: '', shelf: '', level: ''));
    final newLocation = _locations.firstWhere((l) => l.locationId == newLocationId);

    // Cập nhật vị trí pallet
    pallet.locationId = newLocationId;
    _dbService.updatePalletLocation(palletId, newLocationId);
    if (oldLocation.currentPallets > 0) oldLocation.currentPallets--;
    newLocation.currentPallets++;

    // Cập nhật toàn bộ Item trên pallet
    for (var itemId in pallet.itemIds) {
      final item = _items.firstWhere((it) => it.itemId == itemId);
      item.locationId = newLocationId;
      _dbService.updateItemLocationAndPallet(item.epc, newLocationId, palletId);
    }

    // Ghi log giao dịch
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

    // Lưu vào hàng đợi đồng bộ MySQL (Offline-first)
    _dbService.enqueueSync(
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

  /// Tra cứu tổng hợp tồn kho theo SKU
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
