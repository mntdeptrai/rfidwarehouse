import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../models/wms_models.dart';
import 'erp_bravo_service.dart';
import 'database_service.dart';
import 'supabase_sync_service.dart';
import 'auth_service.dart';

class WarehouseRepository extends ChangeNotifier {
  static final WarehouseRepository _instance = WarehouseRepository._internal();
  factory WarehouseRepository() => _instance;

  final DatabaseService _dbService = DatabaseService();

  Future<void>? _initFuture;

  WarehouseRepository._internal() {
    _initFuture = _loadLocalCache();
  }

  Future<void> ensureInitialized() async {
    if (_initFuture != null) await _initFuture;
  }

  Future<void> reloadFromDatabase() async {
    await _loadLocalCache();
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      await _tryLoadFromSupabaseDirect();
    }
  }

  /// Alias tương thích ngược với các cuộc gọi trước đó
  Future<void> reloadFromSqlite() => reloadFromDatabase();

  Future<void> _loadLocalCache() async {
    try {
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

      // Lọc bỏ lệnh scanner vô tình bị quét nhầm thành sản phẩm/hàng hóa
      bool isBogusCommandProduct(Product p) {
        final pSku = p.sku.toUpperCase();
        final pId = p.productId.toUpperCase();
        return bogusCommandNames.contains(pId) || bogusCommandNames.contains(pSku);
      }

      bool isBogusCommandItem(Item i) {
        final epc = i.epc.toUpperCase();
        final sku = i.sku.toUpperCase();
        final orderNo = (i.orderNo ?? '').toUpperCase();
        return bogusCommandNames.contains(epc) ||
            bogusCommandNames.contains(sku) ||
            bogusCommandNames.contains(orderNo);
      }

      // 1. Nạp siêu tốc toàn bộ dữ liệu In-Memory cục bộ vào RAM (~30ms)
      final cleanProducts = await _dbService.getProducts();
      final cleanLocations = List<Location>.from(await _dbService.getLocations());
      final cleanItems = await _dbService.getItems();
      final cleanPallets = await _dbService.getPallets();
      final cleanInboundOrders = await _dbService.getInboundOrders();
      final cleanOutboundOrders = await _dbService.getOutboundOrders();
      final dbUsers = await _dbService.getUsers();
      final dbCustomers = await _dbService.getCustomers();
      final dbDeliveryNotes = await _dbService.getDeliveryNotes();
      final dbInventorySessions = await _dbService.getInventorySessions();
      final dbLocateOrders = await _dbService.getLocateOrders();
      final dbTransactions = await _dbService.getTransactions();
      final dbTagLogs = await _dbService.getTagLifecycleLogs();

      _products.clear();
      _products.addAll(cleanProducts.where((p) => !isBogusCommandProduct(p)));

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
      _floorPlanConfig = await _dbService.getWarehouseLayoutConfig();

      _pallets.clear();
      _pallets.addAll(cleanPallets);

      _items.clear();
      _items.addAll(cleanItems.where((i) => !isBogusCommandItem(i)));

      final Map<String, List<String>> palletItemsMap = {};
      for (final it in _items) {
        if (it.palletId != null && it.palletId!.isNotEmpty) {
          palletItemsMap.putIfAbsent(it.palletId!, () => []).add(it.itemId);
        }
      }
      for (final p in _pallets) {
        p.itemIds.clear();
        final byId = palletItemsMap[p.palletId] ?? [];
        final byCode = palletItemsMap[p.palletCode] ?? [];
        p.itemIds.addAll({...byId, ...byCode});
      }
      _rebuildIndexes();

      _inboundOrders.clear();
      _inboundOrders.addAll(cleanInboundOrders);

      // Đồng bộ trạng thái mặt hàng thuộc các đơn nhập đang chờ cất kệ
      final waitingPutawayOrderNos = _inboundOrders
          .where((o) => o.status == InboundOrderStatus.waitingPutaway)
          .map((o) => o.orderNo.trim().toUpperCase())
          .toSet();
      if (waitingPutawayOrderNos.isNotEmpty) {
        for (final it in _items) {
          if ((it.status == ItemStatus.pendingInbound || it.status == ItemStatus.waitingPalletize) &&
              waitingPutawayOrderNos.contains((it.orderNo ?? '').trim().toUpperCase())) {
            it.status = ItemStatus.waitingPutaway;
          }
        }
      }

      // Tự động hoàn tất đơn nhập kho nếu tất cả các mặt hàng của đơn đã cất vào kệ
      for (final ord in _inboundOrders) {
        if (ord.status != InboundOrderStatus.completed && isInboundOrderPutawayCompleted(ord)) {
          ord.status = InboundOrderStatus.completed;
          for (var d in ord.details) {
            d.receivedQty = d.requiredQty;
          }
        }
      }

      _outboundOrders.clear();
      _outboundOrders.addAll(cleanOutboundOrders);

      _users.clear();
      _users.addAll(dbUsers);

      _customers.clear();
      _customers.addAll(dbCustomers);

      _deliveryNotes.clear();
      _deliveryNotes.addAll(dbDeliveryNotes);

      _inventorySessions.clear();
      for (final s in dbInventorySessions) {
        _sanitizeSessionResults(s);
        _inventorySessions.add(s);
      }

      _locateOrders.clear();
      _locateOrders.addAll(dbLocateOrders);

      _transactions.clear();
      _transactions.addAll(dbTransactions);

      _tagLifecycleLogs.clear();
      _tagLifecycleLogs.addAll(dbTagLogs);

      // Bổ sung chi tiết và số lượng thực xuất cho các đơn xuất kho từ lịch sử biến động kho nếu danh sách chi tiết trống
      for (final ord in _outboundOrders) {
        if (ord.details.isEmpty) {
          final txs = _transactions.where((t) =>
              t.type == TransactionType.outbound &&
              (t.documentNo.trim().toUpperCase() == ord.poNo.trim().toUpperCase() ||
               t.documentNo.trim().toUpperCase() == ord.outboundOrderId.trim().toUpperCase() ||
               (ord.poNo.isNotEmpty && t.transactionId.contains(ord.poNo)) ||
               (ord.outboundOrderId.isNotEmpty && t.transactionId.contains(ord.outboundOrderId)))).toList();
          if (txs.isNotEmpty) {
            for (final tx in txs) {
              ord.details.add(OutboundOrderDetail(
                productId: tx.sku,
                sku: tx.sku,
                productName: tx.productName.isNotEmpty ? tx.productName : 'Sản phẩm xuất kho',
                requiredQty: tx.quantity,
                pickedQty: tx.quantity,
              ));
            }
          }
        }
      }

      // Bổ sung nhà cung cấp (supplier) cho các item từ đơn nhập kho nếu chưa được gán
      for (final it in _items) {
        if ((it.supplier == null || it.supplier!.isEmpty || it.supplier == 'Chưa khai báo') && it.orderNo != null && it.orderNo!.isNotEmpty) {
          final ord = _inboundOrders.where((o) => o.orderNo == it.orderNo || o.inboundOrderId == it.orderNo).firstOrNull;
          if (ord != null && ord.sourceSupplier.trim().isNotEmpty && ord.sourceSupplier.trim() != 'Chưa khai báo') {
            it.supplier = ord.sourceSupplier.trim();
          }
        }
      }

      // Đánh thức UI và các listener ngay lập tức bằng dữ liệu bộ nhớ cục bộ
      notifyListeners();

      // 2. Dọn dẹp lệnh rác scanner ngầm (không chặn UI startup)
      unawaited(Future(() async {
        for (final p in cleanProducts) {
          if (isBogusCommandProduct(p)) {
            await _dbService.deleteProduct(p.productId);
          }
        }
        for (final i in cleanItems) {
          if (isBogusCommandItem(i)) {
            await _dbService.deleteItem(i.epc);
          }
        }
      }));

      // 3. Đồng bộ hóa Supabase Cloud ngầm ở chế độ Non-blocking (Không làm chậm quá trình mở app)
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        unawaited(_tryLoadFromSupabaseDirect().then((supaLoaded) {
          if (supaLoaded) {
            notifyListeners();
          }
        }).catchError((e) {
          debugPrint('WarehouseRepository: Background Supabase load error: $e');
        }));
      }
    } catch (e) {
      debugPrint('WarehouseRepository: Local cache load error: $e');
    }
  }

  Future<bool> _tryLoadFromSupabaseDirect() async {
    try {
      final supaSync = SupabaseSyncService();
      if (!supaSync.isOnline) {
        final ok = await supaSync.checkConnectivity();
        if (!ok) return false;
      }
      final supa = supaSync.client ?? Supabase.instance.client;

      // Nạp song song các bảng từ Supabase Cloud
      final results = await Future.wait([
        supa.from('locations').select(),
        supa.from('pallets').select(),
        supa.from('products').select(),
        supa.from('items').select(),
        supa.from('inbound_orders').select(),
        supa.from('inbound_order_details').select(),
        supa.from('outbound_orders').select(),
        supa.from('outbound_order_details').select(),
        supa.from('users').select(),
        supa.from('customers').select(),
        supa.from('inventory_transactions').select().order('timestamp', ascending: false).limit(200).catchError((_) => <Map<String, dynamic>>[]),
        supa.from('sync_logs').select().eq('table_name', 'inventory_transactions').order('timestamp', ascending: false).limit(200).catchError((_) => <Map<String, dynamic>>[]),
        supa.from('inventory_sessions').select().order('started_at', ascending: false).catchError((_) => <Map<String, dynamic>>[]),
        supa.from('inventory_session_details').select().catchError((_) => <Map<String, dynamic>>[]),
        supa.from('delivery_notes').select().catchError((_) => <Map<String, dynamic>>[]),
        supa.from('delivery_note_details').select().catchError((_) => <Map<String, dynamic>>[]),
        supa.from('locate_orders').select().order('created_at', ascending: false).catchError((_) => <Map<String, dynamic>>[]),
        supa.from('tag_lifecycle_logs').select().order('timestamp', ascending: false).limit(500).catchError((_) => <Map<String, dynamic>>[]),
      ]);

      final locRows = results[0] as List<dynamic>;
      final palRows = results[1] as List<dynamic>;
      final prodRows = results[2] as List<dynamic>;
      final itemRows = results[3] as List<dynamic>;
      final inbRows = results[4] as List<dynamic>;
      final inbDetailRows = results[5] as List<dynamic>;
      final outRows = results[6] as List<dynamic>;
      final outDetailRows = results[7] as List<dynamic>;
      final userRows = results[8] as List<dynamic>;
      final custRows = results[9] as List<dynamic>;
      final txRows = results[10] as List<dynamic>;


      // 1. Locations
      final loadedLocs = locRows.map((m) => Location(
        locationId: (m['location_id'] ?? '').toString(),
        locationCode: (m['location_code'] ?? '').toString(),
        zone: (m['zone'] ?? '').toString(),
        shelf: (m['shelf'] ?? '').toString(),
        level: (m['level'] ?? '').toString(),
        currentPallets: (m['current_pallets'] as num?)?.toInt() ?? 0,
        maxPalletCapacity: (m['max_pallet_capacity'] as num?)?.toInt() ?? 50,
        status: (m['status'] ?? 'AVAILABLE').toString(),
        aisleSide: (m['aisle_side'] ?? 'LEFT').toString(),
        sortOrder: (m['sort_order'] as num?)?.toInt() ?? 0,
        gridRow: (m['grid_row'] as num?)?.toInt() ?? 0,
        gridCol: (m['grid_col'] as num?)?.toInt() ?? 0,
      )).toList();

      loadedLocs.sort((a, b) {
        final z = a.zone.compareTo(b.zone);
        if (z != 0) return z;
        final s = a.shelf.compareTo(b.shelf);
        if (s != 0) return s;
        final l = a.level.compareTo(b.level);
        if (l != 0) return l;
        return a.locationCode.compareTo(b.locationCode);
      });

      // 2. Pallets
      final loadedPallets = palRows.map((m) {
        final inbTimeStr = m['inbound_time'] as String?;
        final pId = (m['pallet_id'] ?? '').toString();
        final pCode = (m['pallet_code'] ?? '').toString();
        // Giữ lại tên pallet đã lưu cục bộ nếu Supabase trả về null/rỗng
        final existingLocal = _pallets.where((p) =>
            (pId.isNotEmpty && p.palletId == pId) ||
            (pCode.isNotEmpty && p.palletCode.toUpperCase() == pCode.toUpperCase())).firstOrNull;
        final rawName = m['pallet_name'] as String?;
        final effectiveName = (rawName != null && rawName.trim().isNotEmpty)
            ? rawName.trim()
            : existingLocal?.palletName;

        return Pallet(
          palletId: pId,
          palletCode: pCode,
          palletName: effectiveName,
          rfidEpc: m['rfid_epc'] as String?,
          locationId: m['location_id'] as String?,
          inboundTime: inbTimeStr != null ? DateTime.tryParse(inbTimeStr) : null,
          isMultiSku: m['is_multi_sku'] == 1 || m['is_multi_sku'] == true,
          placedBy: m['placed_by'] as String?,
        );
      }).toList();

      // Loại bỏ bản ghi trùng lặp mã Pallet từ Supabase nếu có
      final Map<String, Pallet> uniquePalletsMap = {};
      for (final p in loadedPallets) {
        final key = p.palletCode.trim().toUpperCase();
        if (key.isEmpty) continue;
        if (!uniquePalletsMap.containsKey(key)) {
          uniquePalletsMap[key] = p;
        } else {
          final ex = uniquePalletsMap[key]!;
          if ((ex.palletName == null || ex.palletName!.isEmpty) && p.palletName != null && p.palletName!.isNotEmpty) {
            ex.palletName = p.palletName;
          }
          if ((ex.rfidEpc == null || ex.rfidEpc!.isEmpty) && p.rfidEpc != null && p.rfidEpc!.isNotEmpty) {
            ex.rfidEpc = p.rfidEpc;
          }
        }
      }
      final cleanLoadedPallets = uniquePalletsMap.values.toList();

      // 3. Products
      final loadedProds = prodRows.map((m) => Product(
        productId: (m['product_id'] ?? '').toString(),
        sku: (m['sku'] ?? '').toString(),
        productName: (m['product_name'] ?? '').toString(),
        unit: (m['unit'] ?? '').toString(),
        category: (m['category'] ?? '').toString(),
        description: m['description'] as String?,
      )).toList();

      // 4. Items
      final loadedItems = itemRows.map((m) {
        final inbTimeStr = m['inbound_time'] as String?;
        final allocTimeStr = m['allocated_time'] as String?;
        final statusCode = (m['status'] ?? 'IN_STOCK').toString();
        final status = ItemStatus.values.firstWhere(
          (s) => s.code == statusCode,
          orElse: () => ItemStatus.inStock,
        );
        return Item(
          itemId: (m['item_id'] ?? '').toString(),
          productId: (m['product_id'] ?? '').toString(),
          sku: (m['sku'] ?? '').toString(),
          productName: (m['product_name'] ?? '').toString(),
          serialNumber: (m['serial_number'] ?? '').toString(),
          epc: (m['epc'] ?? '').toString(),
          status: status,
          orderNo: m['order_no'] as String?,
          palletId: m['pallet_id'] as String?,
          locationId: m['location_id'] as String?,
          inboundTime: inbTimeStr != null ? DateTime.tryParse(inbTimeStr) : null,
          allocatedTime: allocTimeStr != null ? DateTime.tryParse(allocTimeStr) : null,
          supplier: m['supplier'] as String?,
          cartonCode: m['carton_code'] as String?,
          inboundBy: m['inbound_by'] as String?,
          putawayBy: m['putaway_by'] as String?,
        );
      }).toList();

      // 5. Inbound Orders
      final Map<String, Map<String, InboundOrderDetail>> inbDetailsByOrderAndSku = {};
      final Set<String> inbOrdersWithDuplicates = {};
      for (final d in inbDetailRows) {
        final orderId = (d['order_id'] ?? '').toString();
        if (orderId.isEmpty) continue;
        final sku = (d['sku'] ?? '').toString().trim().toUpperCase();
        final prodId = (d['product_id'] ?? '').toString();
        final key = sku.isNotEmpty ? sku : prodId;
        final req = (d['required_qty'] as num?)?.toInt() ?? 0;
        final rec = (d['received_qty'] as num?)?.toInt() ?? 0;
        final rawProdName = (d['product_name'] ?? '').toString().trim();
        final prodName = rawProdName.replaceFirst(RegExp(r'\s+\d+$'), '').trim();
        if (prodName.isNotEmpty && prodName != rawProdName) {
          inbOrdersWithDuplicates.add(orderId);
        }

        final orderSkuMap = inbDetailsByOrderAndSku.putIfAbsent(orderId, () => {});
        if (orderSkuMap.containsKey(key)) {
          inbOrdersWithDuplicates.add(orderId);
          final cur = orderSkuMap[key]!;
          orderSkuMap[key] = InboundOrderDetail(
            productId: cur.productId.isNotEmpty ? cur.productId : prodId,
            sku: cur.sku.isNotEmpty ? cur.sku : (d['sku'] ?? '').toString(),
            productName: cur.productName.isNotEmpty ? cur.productName : (prodName.isNotEmpty ? prodName : rawProdName),
            requiredQty: cur.requiredQty > 0 ? cur.requiredQty : req,
            receivedQty: cur.receivedQty > rec ? cur.receivedQty : rec,
          );
        } else {
          orderSkuMap[key] = InboundOrderDetail(
            productId: prodId,
            sku: (d['sku'] ?? '').toString(),
            productName: prodName.isNotEmpty ? prodName : rawProdName,
            requiredQty: req,
            receivedQty: rec,
          );
        }
      }
      final Map<String, List<InboundOrderDetail>> inbDetailsMap = {};
      for (final entry in inbDetailsByOrderAndSku.entries) {
        inbDetailsMap[entry.key] = entry.value.values.toList();
      }

      // Tự động làm sạch các dòng trùng lặp trong inbound_order_details trên Supabase Cloud
      if (inbOrdersWithDuplicates.isNotEmpty && !Platform.environment.containsKey('FLUTTER_TEST')) {
        Future.microtask(() async {
          try {
            final supa = Supabase.instance.client;
            for (final dupOrderId in inbOrdersWithDuplicates) {
              final cleanList = inbDetailsMap[dupOrderId] ?? [];
              if (cleanList.isNotEmpty) {
                await supa.from('inbound_order_details').delete().eq('order_id', dupOrderId);
                final newRows = cleanList.map((d) => {
                  'order_id': dupOrderId,
                  'product_id': d.productId,
                  'sku': d.sku,
                  'product_name': d.productName,
                  'required_qty': d.requiredQty,
                  'received_qty': d.receivedQty,
                }).toList();
                await supa.from('inbound_order_details').insert(newRows);
                debugPrint('Tự động dọn sạch duplicate inbound_order_details cho đơn $dupOrderId');
              }
            }
          } catch (e) {
            debugPrint('Lỗi tự động dọn duplicate inbound_order_details: $e');
          }
        });
      }

      final loadedInbOrders = inbRows.map((om) {
        final orderId = (om['inbound_order_id'] ?? '').toString();
        final statusStr = (om['status'] ?? '').toString();
        final status = InboundOrderStatus.values.firstWhere(
          (s) => s.code == statusStr,
          orElse: () => InboundOrderStatus.newOrder,
        );
        return InboundOrder(
          inboundOrderId: orderId,
          orderNo: (om['order_no'] ?? '').toString(),
          sourceSupplier: (om['source_supplier'] ?? '').toString(),
          status: status,
          createdAt: DateTime.tryParse((om['created_at'] ?? '').toString()) ?? DateTime.now(),
          details: inbDetailsMap[orderId] ?? [],
        );
      }).toList();

      // 6. Outbound Orders
      final Map<String, Map<String, OutboundOrderDetail>> outDetailsByOrderAndSku = {};
      final Set<String> outOrdersWithDuplicates = {};
      for (final d in outDetailRows) {
        final orderId = (d['order_id'] ?? '').toString();
        if (orderId.isEmpty) continue;
        final sku = (d['sku'] ?? '').toString().trim().toUpperCase();
        final prodId = (d['product_id'] ?? '').toString();
        final key = sku.isNotEmpty ? sku : prodId;
        final req = (d['required_qty'] as num?)?.toInt() ?? 0;
        final picked = (d['picked_qty'] as num?)?.toInt() ?? 0;
        final rawProdName = (d['product_name'] ?? '').toString().trim();
        final prodName = rawProdName.replaceFirst(RegExp(r'\s+\d+$'), '').trim();
        if (prodName.isNotEmpty && prodName != rawProdName) {
          outOrdersWithDuplicates.add(orderId);
        }

        final orderSkuMap = outDetailsByOrderAndSku.putIfAbsent(orderId, () => {});
        if (orderSkuMap.containsKey(key)) {
          outOrdersWithDuplicates.add(orderId);
          final cur = orderSkuMap[key]!;
          orderSkuMap[key] = OutboundOrderDetail(
            productId: cur.productId.isNotEmpty ? cur.productId : prodId,
            sku: cur.sku.isNotEmpty ? cur.sku : (d['sku'] ?? '').toString(),
            productName: cur.productName.isNotEmpty ? cur.productName : (prodName.isNotEmpty ? prodName : rawProdName),
            requiredQty: cur.requiredQty > 0 ? cur.requiredQty : req,
            pickedQty: cur.pickedQty > picked ? cur.pickedQty : picked,
          );
        } else {
          orderSkuMap[key] = OutboundOrderDetail(
            productId: prodId,
            sku: (d['sku'] ?? '').toString(),
            productName: prodName.isNotEmpty ? prodName : rawProdName,
            requiredQty: req,
            pickedQty: picked,
          );
        }
      }
      final Map<String, List<OutboundOrderDetail>> outDetailsMap = {};
      for (final entry in outDetailsByOrderAndSku.entries) {
        outDetailsMap[entry.key] = entry.value.values.toList();
      }

      // Tự động làm sạch các dòng trùng lặp trong outbound_order_details trên Supabase Cloud
      if (outOrdersWithDuplicates.isNotEmpty && !Platform.environment.containsKey('FLUTTER_TEST')) {
        Future.microtask(() async {
          try {
            final supa = Supabase.instance.client;
            for (final dupOrderId in outOrdersWithDuplicates) {
              final cleanList = outDetailsMap[dupOrderId] ?? [];
              if (cleanList.isNotEmpty) {
                await supa.from('outbound_order_details').delete().eq('order_id', dupOrderId);
                final newRows = cleanList.map((d) => {
                  'order_id': dupOrderId,
                  'product_id': d.productId,
                  'sku': d.sku,
                  'product_name': d.productName,
                  'required_qty': d.requiredQty,
                  'picked_qty': d.pickedQty,
                }).toList();
                await supa.from('outbound_order_details').insert(newRows);
                debugPrint('Tự động dọn sạch duplicate outbound_order_details cho đơn $dupOrderId');
              }
            }
          } catch (e) {
            debugPrint('Lỗi tự động dọn duplicate outbound_order_details: $e');
          }
        });
      }
      final List<OutboundOrder> rawLoadedOutOrders = outRows.map((om) {
        final orderId = (om['outbound_order_id'] ?? '').toString();
        final statusStr = (om['status'] ?? '').toString();
        final status = OutboundOrderStatus.values.firstWhere(
          (s) => s.code == statusStr,
          orElse: () => OutboundOrderStatus.newOrder,
        );
        final details = outDetailsMap[orderId] ?? [];
        return OutboundOrder(
          outboundOrderId: orderId,
          poNo: (om['po_no'] ?? om['order_no'] ?? '').toString(),
          customer: (om['customer'] ?? om['destination_customer'] ?? '').toString(),
          status: status,
          createdAt: DateTime.tryParse((om['created_at'] ?? '').toString()) ?? DateTime.now(),
          details: details,
        );
      }).toList();

      // Tự động phát hiện và dọn dẹp các đơn xuất nháp XK- trùng lặp (0 SP đã nhặt - Mới tiếp nhận)
      // khi đã có đơn XK- cùng khách hàng & cùng SKU+số lượng đã xuất hàng (SHIPPED) hoặc mới hơn
      String outboundSignature(OutboundOrder o) {
        final skuParts = o.details
            .map((d) => '${d.sku.trim().toUpperCase()}:${d.requiredQty}')
            .toList()
          ..sort();
        return '${o.customer.trim().toLowerCase()}|${skuParts.join(",")}';
      }

      final redundantOutOrders = <OutboundOrder>[];
      final List<OutboundOrder> loadedOutOrders = [];
      for (final o in rawLoadedOutOrders) {
        final isUnpickedDraft = o.status == OutboundOrderStatus.newOrder &&
            o.poNo.startsWith('XK-') &&
            o.details.isNotEmpty &&
            o.details.every((d) => d.pickedQty == 0);
        if (isUnpickedDraft) {
          final sig = outboundSignature(o);
          final hasSupersedingOrder = rawLoadedOutOrders.any((other) {
            if (other.outboundOrderId == o.outboundOrderId) return false;
            if (outboundSignature(other) != sig) return false;
            if (other.status == OutboundOrderStatus.shipped || other.status == OutboundOrderStatus.processing) {
              return true;
            }
            return other.createdAt.isAfter(o.createdAt);
          });
          if (hasSupersedingOrder) {
            redundantOutOrders.add(o);
            continue;
          }
        }
        loadedOutOrders.add(o);
      }

      if (redundantOutOrders.isNotEmpty && !Platform.environment.containsKey('FLUTTER_TEST')) {
        Future.microtask(() async {
          try {
            final supa = Supabase.instance.client;
            for (final dup in redundantOutOrders) {
              await _dbService.deleteOutboundOrder(dup.outboundOrderId);
              await supa.from('outbound_order_details').delete().eq('order_id', dup.outboundOrderId);
              await supa.from('outbound_orders').delete().eq('outbound_order_id', dup.outboundOrderId);
              debugPrint('Tự động xóa đơn xuất nháp trùng lặp: ${dup.poNo} (${dup.outboundOrderId})');
            }
          } catch (e) {
            debugPrint('Lỗi tự động xóa đơn xuất nháp trùng lặp: $e');
          }
        });
      }

      // 7. Users
      final List<WmsUser> loadedUsers = userRows.map((u) => WmsUser(
        userId: (u['user_id'] ?? '').toString(),
        username: (u['username'] ?? '').toString(),
        fullName: (u['full_name'] ?? '').toString(),
        email: u['email'] as String?,
        phone: u['phone'] as String?,
        role: (u['role'] ?? 'thukho').toString(),
        isActive: u['is_active'] == 1 || u['is_active'] == true,
        createdAt: DateTime.tryParse((u['created_at'] ?? '').toString()),
      )).toList();

      // 8. Customers
      final List<Customer> loadedCusts = custRows.map((c) => Customer(
        customerId: (c['customer_id'] ?? '').toString(),
        customerCode: (c['customer_code'] ?? '').toString(),
        customerName: (c['customer_name'] ?? '').toString(),
        phone: c['phone'] as String?,
        email: c['email'] as String?,
        address: c['address'] as String?,
        taxCode: c['tax_code'] as String?,
        contactPerson: c['contact_person'] as String?,
        notes: c['notes'] as String?,
        createdAt: DateTime.tryParse((c['created_at'] ?? '').toString()) ?? DateTime.now(),
      )).toList();

      // 9. Inventory Transactions
      final List<InventoryTransaction> loadedTransactions = txRows.map((t) {
        final typeStr = (t['transaction_type'] ?? 'INBOUND').toString().toLowerCase();
        final type = TransactionType.values.firstWhere(
          (e) => e.name.toLowerCase() == typeStr,
          orElse: () => TransactionType.inbound,
        );
        return InventoryTransaction(
          transactionId: (t['transaction_id'] ?? '').toString(),
          type: type,
          documentNo: (t['document_no'] ?? '').toString(),
          sku: (t['sku'] ?? '').toString(),
          productName: (t['product_name'] ?? '').toString(),
          quantity: (t['quantity'] as num?)?.toInt() ?? 1,
          fromLocation: t['from_location'] as String?,
          toLocation: t['to_location'] as String?,
          palletCode: t['pallet_code'] as String?,
          performedBy: (t['performed_by'] ?? 'Hệ thống').toString(),
          timestamp: DateTime.tryParse((t['timestamp'] ?? '').toString()) ?? DateTime.now(),
          notes: t['notes'] as String?,
        );
      }).toList();

      // Nạp thêm các giao dịch từ nhật ký đồng bộ dự phòng (sync_logs) nếu bảng chính bị giới hạn
      final List<dynamic> fallbackTxLogs = results.length > 11 ? results[11] as List<dynamic> : const [];
      for (final log in fallbackTxLogs) {
        try {
          final msg = log['message']?.toString() ?? '';
          if (msg.startsWith('{') && msg.endsWith('}')) {
            final data = jsonDecode(msg) as Map<String, dynamic>;
            final txId = (data['transaction_id'] ?? data['transactionId'] ?? log['log_id'] ?? '').toString();
            if (txId.isNotEmpty && !loadedTransactions.any((t) => t.transactionId == txId)) {
              final typeStr = (data['transaction_type'] ?? data['type'] ?? log['action'] ?? 'MOVEMENT').toString().toLowerCase();
              final type = TransactionType.values.firstWhere(
                (e) => e.name.toLowerCase() == typeStr,
                orElse: () => TransactionType.movement,
              );
              loadedTransactions.add(InventoryTransaction(
                transactionId: txId,
                type: type,
                documentNo: (data['document_no'] ?? data['documentNo'] ?? '').toString(),
                sku: (data['sku'] ?? '').toString(),
                productName: (data['product_name'] ?? data['productName'] ?? '').toString(),
                quantity: (data['quantity'] as num?)?.toInt() ?? (log['record_count'] as num?)?.toInt() ?? 1,
                fromLocation: (data['from_location'] ?? data['fromLocation']) as String?,
                toLocation: (data['to_location'] ?? data['toLocation']) as String?,
                palletCode: (data['pallet_code'] ?? data['palletCode']) as String?,
                performedBy: (data['performed_by'] ?? data['performedBy'] ?? 'Hệ thống').toString(),
                timestamp: DateTime.tryParse((data['timestamp'] ?? log['timestamp'] ?? '').toString()) ?? DateTime.now(),
                notes: (data['notes']) as String?,
              ));
            }
          }
        } catch (_) {}
      }

      // Link pallet items:
      final Map<String, List<String>> palletItemsMap = {};
      for (final it in loadedItems) {
        if (it.palletId != null && it.palletId!.isNotEmpty) {
          palletItemsMap.putIfAbsent(it.palletId!, () => []).add(it.itemId);
        }
      }
      for (final p in loadedPallets) {
        p.itemIds.clear();
        final byId = palletItemsMap[p.palletId] ?? [];
        final byCode = palletItemsMap[p.palletCode] ?? [];
        p.itemIds.addAll({...byId, ...byCode});
      }

      // Commit to RAM state:
      _locations.clear();
      _locations.addAll(loadedLocs);

      _pallets.clear();
      _pallets.addAll(cleanLoadedPallets);

      _products.clear();
      _products.addAll(loadedProds);

      _items.clear();
      _items.addAll(loadedItems);

      _inboundOrders.clear();
      _inboundOrders.addAll(loadedInbOrders);

      // Đồng bộ trạng thái mặt hàng thuộc các đơn nhập đang chờ cất kệ
      final waitingPutawayOrderNos = _inboundOrders
          .where((o) => o.status == InboundOrderStatus.waitingPutaway)
          .map((o) => o.orderNo.trim().toUpperCase())
          .toSet();
      if (waitingPutawayOrderNos.isNotEmpty) {
        for (final it in _items) {
          if ((it.status == ItemStatus.pendingInbound || it.status == ItemStatus.waitingPalletize) &&
              waitingPutawayOrderNos.contains((it.orderNo ?? '').trim().toUpperCase())) {
            it.status = ItemStatus.waitingPutaway;
          }
        }
      }

      // Tự động hoàn tất đơn nhập kho nếu tất cả các mặt hàng của đơn đã cất vào kệ
      for (final ord in _inboundOrders) {
        if (ord.status != InboundOrderStatus.completed && isInboundOrderPutawayCompleted(ord)) {
          ord.status = InboundOrderStatus.completed;
          for (var d in ord.details) {
            d.receivedQty = d.requiredQty;
          }
        }
      }

      // Bổ sung nhà cung cấp (supplier) cho các item từ đơn nhập kho nếu chưa được gán
      for (final it in _items) {
        if ((it.supplier == null || it.supplier!.isEmpty || it.supplier == 'Chưa khai báo') && it.orderNo != null && it.orderNo!.isNotEmpty) {
          final ord = _inboundOrders.where((o) => o.orderNo == it.orderNo || o.inboundOrderId == it.orderNo).firstOrNull;
          if (ord != null && ord.sourceSupplier.trim().isNotEmpty && ord.sourceSupplier.trim() != 'Chưa khai báo') {
            it.supplier = ord.sourceSupplier.trim();
          }
        }
      }

      _outboundOrders.clear();
      _outboundOrders.addAll(loadedOutOrders);
      for (final o in loadedOutOrders) {
        await _dbService.insertOutboundOrder(o);
      }

      _users.clear();
      _users.addAll(loadedUsers);

      _customers.clear();
      _customers.addAll(loadedCusts);

      // Hợp nhất giao dịch Cloud với bộ nhớ cục bộ để bảo toàn dữ liệu offline
      final localTxs = await _dbService.getTransactions();
      final Map<String, InventoryTransaction> mergedTxsMap = {};
      for (final tx in localTxs) {
        mergedTxsMap[tx.transactionId] = tx;
      }
      for (final tx in loadedTransactions) {
        mergedTxsMap[tx.transactionId] = tx;
        await _dbService.insertTransaction(tx);
      }
      final mergedTxList = mergedTxsMap.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
      _transactions.clear();
      _transactions.addAll(mergedTxList);

      // Khôi phục chi tiết số lượng sản phẩm xuất kho từ giao dịch thực tế trên Supabase nếu đơn xuất chưa có bảng chi tiết
      for (final ord in _outboundOrders) {
        if (ord.details.isEmpty) {
          final txs = _transactions.where((t) =>
              t.type == TransactionType.outbound &&
              (t.documentNo.trim().toUpperCase() == ord.poNo.trim().toUpperCase() ||
               t.documentNo.trim().toUpperCase() == ord.outboundOrderId.trim().toUpperCase() ||
               (ord.poNo.isNotEmpty && t.transactionId.contains(ord.poNo)) ||
               (ord.outboundOrderId.isNotEmpty && t.transactionId.contains(ord.outboundOrderId)))).toList();
          if (txs.isNotEmpty) {
            for (final tx in txs) {
              ord.details.add(OutboundOrderDetail(
                productId: tx.sku,
                sku: tx.sku,
                productName: tx.productName.isNotEmpty ? tx.productName : 'Sản phẩm xuất kho',
                requiredQty: tx.quantity,
                pickedQty: tx.quantity,
              ));
            }
          }
        }
      }

      // 10. Inventory Sessions & Details
      final List<dynamic> invSessionRows = results.length > 12 ? results[12] : const [];
      final List<dynamic> invDetailRows = results.length > 13 ? results[13] : const [];
      final Map<String, List<InventoryItemResult>> invDetailsMap = {};
      for (final d in invDetailRows) {
        final sessId = (d['session_id'] ?? '').toString();
        if (sessId.isEmpty) continue;
        final resTypeStr = (d['result_type'] ?? 'MATCH').toString().toUpperCase();
        final resType = InventoryVarianceType.values.firstWhere(
          (v) => v.code.toUpperCase() == resTypeStr,
          orElse: () => InventoryVarianceType.match,
        );
        invDetailsMap.putIfAbsent(sessId, () => []).add(InventoryItemResult(
          epc: (d['epc'] ?? '').toString(),
          sku: d['sku']?.toString(),
          productName: d['product_name']?.toString(),
          expectedLocation: d['expected_location']?.toString(),
          actualLocation: d['actual_location']?.toString(),
          resultType: resType,
          readAt: DateTime.tryParse((d['read_at'] ?? '').toString()) ?? DateTime.now(),
        ));
      }

      final List<InventorySession> loadedSessions = invSessionRows.map((m) {
        final sId = (m['session_id'] ?? '').toString();
        final startedAtStr = (m['started_at'] ?? '').toString();
        final completedAtStr = m['completed_at']?.toString();
        final isComp = m['is_completed'] == true || m['is_completed'] == 1 || m['is_completed'] == 'true';
        final details = invDetailsMap[sId] ?? [];
        final targetSkusRaw = m['target_skus'];
        List<String> targetSkusList = [];
        if (targetSkusRaw is List) {
          targetSkusList = targetSkusRaw.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        } else if (targetSkusRaw is String && targetSkusRaw.trim().isNotEmpty) {
          targetSkusList = targetSkusRaw.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        }

        String? assignedToUserId = m['assigned_to_user_id']?.toString();
        String? assignedToName = m['assigned_to_name']?.toString();
        String? assignedBy = (m['created_by'] ?? m['assigned_by'])?.toString();
        String? notes = m['notes']?.toString();

        final createdByStr = assignedBy?.trim() ?? '';
        if (createdByStr.startsWith('{') && createdByStr.endsWith('}')) {
          try {
            final parsedMeta = jsonDecode(createdByStr) as Map<String, dynamic>;
            assignedBy = parsedMeta['by']?.toString() ?? assignedBy;
            if (assignedToUserId == null || assignedToUserId.trim().isEmpty || assignedToUserId == 'null') {
              assignedToUserId = parsedMeta['to_id']?.toString();
            }
            if (assignedToName == null || assignedToName.trim().isEmpty || assignedToName == 'null') {
              assignedToName = parsedMeta['to_name']?.toString();
            }
            if (notes == null || notes.trim().isEmpty || notes == 'null') {
              notes = parsedMeta['notes']?.toString();
            }
            if (targetSkusList.isEmpty && parsedMeta['skus'] != null) {
              final rawSkus = parsedMeta['skus'];
              if (rawSkus is List) {
                targetSkusList = rawSkus.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
              } else if (rawSkus is String && rawSkus.isNotEmpty) {
                targetSkusList = rawSkus.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
              }
            }
          } catch (_) {}
        }

        return InventorySession(
          sessionId: sId,
          sessionCode: (m['session_code'] ?? sId).toString(),
          zone: (m['zone'] ?? 'Chung').toString(),
          locationCode: m['location_code']?.toString(),
          startedAt: DateTime.tryParse(startedAtStr) ?? DateTime.now(),
          completedAt: completedAtStr != null ? DateTime.tryParse(completedAtStr) : null,
          isCompleted: isComp,
          results: details,
          targetSkus: targetSkusList,
          assignedToUserId: assignedToUserId,
          assignedToName: assignedToName,
          assignedBy: assignedBy,
          notes: notes,
        );
      }).toList();

      final localSessions = await _dbService.getInventorySessions();
      final Map<String, InventorySession> mergedSessionsMap = {};
      for (final s in localSessions) {
        mergedSessionsMap[s.sessionId] = s;
      }
      for (final s in _inventorySessions) {
        mergedSessionsMap[s.sessionId] = s;
      }
      for (final s in loadedSessions) {
        if (mergedSessionsMap.containsKey(s.sessionId)) {
          final existing = mergedSessionsMap[s.sessionId]!;
          if (s.results.isEmpty && existing.results.isNotEmpty) {
            s.results.addAll(existing.results);
          }
        }
        // Nếu phiên kiểm kê chưa có chi tiết được ghi từ trước và phiên CHƯA hoàn tất, nạp danh sách mặt hàng thuộc vị trí kiểm kê
        if (s.results.isEmpty && s.zone.isNotEmpty && !s.isCompleted) {
          final isAllWarehouse = s.zone.trim().toLowerCase().contains('toàn bộ') ||
              s.zone.trim().toUpperCase() == 'ALL' ||
              (s.locationCode == null && s.zone.isEmpty);

          final zoneItems = _items.where((it) {
            if (it.status != ItemStatus.inStock) return false;
            if (isAllWarehouse) return true;
            final loc = resolveItemLocation(it);
            if (loc == null) return false;
            if (s.locationCode != null && s.locationCode!.trim().isNotEmpty) {
              final target = s.locationCode!.trim().toUpperCase();
              return loc.locationCode.trim().toUpperCase() == target ||
                  loc.locationId.trim().toUpperCase() == target;
            }
            return loc.zone.trim().toUpperCase() == s.zone.trim().toUpperCase();
          }).toList();

          if (zoneItems.isNotEmpty) {
            for (final it in zoneItems) {
              s.results.add(InventoryItemResult(
                epc: it.epc,
                sku: it.sku,
                productName: it.productName,
                expectedLocation: s.locationCode ?? s.zone,
                actualLocation: s.locationCode ?? s.zone,
                resultType: InventoryVarianceType.missing,
                readAt: s.completedAt ?? s.startedAt,
              ));
            }
          }
        }
        mergedSessionsMap[s.sessionId] = s;
        await _dbService.insertInventorySession(s);
      }
      _inventorySessions.clear();
      final sortedMerged = mergedSessionsMap.values.toList()
        ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
      for (final s in sortedMerged) {
        _sanitizeSessionResults(s);
        _inventorySessions.add(s);
      }

      // 11. Delivery Notes & Details
      final List<dynamic> deliveryNoteRows = results.length > 14 ? results[14] : const [];
      final List<dynamic> deliveryNoteDetailRows = results.length > 15 ? results[15] : const [];
      final Map<String, List<DeliveryNoteDetail>> deliveryDetailsMap = {};
      for (final d in deliveryNoteDetailRows) {
        final delId = (d['delivery_id'] ?? '').toString();
        if (delId.isEmpty) continue;
        deliveryDetailsMap.putIfAbsent(delId, () => []).add(DeliveryNoteDetail(
          id: d['id'] as int?,
          deliveryId: delId,
          productId: (d['product_id'] ?? '').toString(),
          sku: (d['sku'] ?? '').toString(),
          productName: (d['product_name'] ?? '').toString(),
          quantity: (d['quantity'] as num?)?.toInt() ?? 1,
          cartonCode: d['carton_code']?.toString(),
        ));
      }

      final List<DeliveryNote> loadedDeliveryNotes = deliveryNoteRows.map((m) {
        final dId = (m['delivery_id'] ?? '').toString();
        return DeliveryNote(
          deliveryId: dId,
          deliveryNo: (m['delivery_no'] ?? dId).toString(),
          poNo: m['po_no']?.toString(),
          customerId: m['customer_id']?.toString(),
          customerName: (m['customer_name'] ?? '').toString(),
          status: (m['status'] ?? 'DRAFT').toString(),
          carrier: m['carrier']?.toString(),
          trackingNo: m['tracking_no']?.toString(),
          totalCartons: (m['total_cartons'] as num?)?.toInt() ?? 0,
          totalQty: (m['total_qty'] as num?)?.toInt() ?? 0,
          createdBy: m['created_by']?.toString(),
          shippedAt: m['shipped_at'] != null ? DateTime.tryParse(m['shipped_at'].toString()) : null,
          notes: m['notes']?.toString(),
          createdAt: m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null,
          details: deliveryDetailsMap[dId] ?? [],
        );
      }).toList();

      final localDeliveries = await _dbService.getDeliveryNotes();
      final Map<String, DeliveryNote> mergedDeliveriesMap = {};
      for (final d in localDeliveries) {
        mergedDeliveriesMap[d.deliveryId] = d;
      }
      for (final d in _deliveryNotes) {
        mergedDeliveriesMap[d.deliveryId] = d;
      }
      for (final d in loadedDeliveryNotes) {
        mergedDeliveriesMap[d.deliveryId] = d;
        await _dbService.insertDeliveryNote(d);
      }
      _deliveryNotes.clear();
      _deliveryNotes.addAll(mergedDeliveriesMap.values.toList());

      // 12. Locate Orders (Đơn tìm kiếm)
      final List<dynamic> locateOrderRows = results.length > 16 ? results[16] as List<dynamic> : const [];
      final List<LocateOrder> loadedLocateOrders = locateOrderRows.map((m) {
        return LocateOrder.fromMap(m is Map<String, dynamic> ? m : Map<String, dynamic>.from(m as Map));
      }).toList();

      final localLocateOrders = await _dbService.getLocateOrders();
      final Map<String, LocateOrder> mergedLocateOrdersMap = {};
      for (final o in localLocateOrders) {
        mergedLocateOrdersMap[o.orderId] = o;
      }
      for (final o in _locateOrders) {
        mergedLocateOrdersMap[o.orderId] = o;
      }
      for (final o in loadedLocateOrders) {
        mergedLocateOrdersMap[o.orderId] = o;
        await _dbService.insertLocateOrder(o);
      }
      _locateOrders.clear();
      _locateOrders.addAll(mergedLocateOrdersMap.values.toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));

      // 13. Tag Lifecycle Logs (Nhật ký vòng đời thẻ RFID)
      final List<dynamic> tagLogRows = results.length > 17 ? results[17] as List<dynamic> : const [];
      final List<TagLifecycleLog> loadedTagLogs = tagLogRows.map((m) {
        return TagLifecycleLog.fromMap(m is Map<String, dynamic> ? m : Map<String, dynamic>.from(m as Map));
      }).toList();

      final localTagLogs = await _dbService.getTagLifecycleLogs();
      final Map<String, TagLifecycleLog> mergedTagLogsMap = {};
      for (final l in localTagLogs) {
        mergedTagLogsMap[l.logId] = l;
      }
      for (final l in _tagLifecycleLogs) {
        mergedTagLogsMap[l.logId] = l;
      }
      for (final l in loadedTagLogs) {
        mergedTagLogsMap[l.logId] = l;
        await _dbService.insertTagLifecycleLog(l);
      }
      _tagLifecycleLogs.clear();
      _tagLifecycleLogs.addAll(mergedTagLogsMap.values.toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp)));

      _rebuildIndexes();

      debugPrint('Directly synced from Supabase Cloud: ${_locations.length} locs, ${_pallets.length} pallets, ${_items.length} items, ${_products.length} prods, ${_inventorySessions.length} sessions, ${_transactions.length} txs, ${_tagLifecycleLogs.length} tagLogs');

      return true;
    } catch (e) {
      debugPrint('Supabase direct load error: $e');
      return false;
    }
  }

  Future<void> refreshFromDatabase() => reloadFromDatabase();

  /// Kiểm tra siêu tốc danh sách EPC đã tồn tại (kết hợp RAM HashSet O(1) và DatabaseService)
  Future<Set<String>> checkExistingEpcs(List<String> epcs) async {
    if (epcs.isEmpty) return {};
    final cleanEpcs = epcs.map((e) => e.trim().toUpperCase()).where((e) => e.isNotEmpty).toList();

    // 1. So khớp siêu tốc trong RAM (Hash Set O(1))
    final inMemorySet = _items.map((i) => i.epc.toUpperCase()).toSet();
    final Set<String> matched = cleanEpcs.where((e) => inMemorySet.contains(e)).toSet();

    // 2. So khớp trực tiếp DatabaseService
    final dbMatched = await _dbService.checkExistingEpcs(cleanEpcs);
    matched.addAll(dbMatched);

    return matched;
  }

  Future<void> deleteInboundOrder(String orderId, {List<String>? itemEpcs}) async {
    final cleanId = orderId.trim();
    final targetOrder = _inboundOrders.where((o) => o.inboundOrderId == cleanId || o.orderNo == cleanId).firstOrNull;
    final orderNo = targetOrder?.orderNo ?? cleanId;
    final orderIdVal = targetOrder?.inboundOrderId ?? cleanId;

    final targetEpcs = itemEpcs?.map((e) => e.trim().toUpperCase()).toSet() ?? <String>{};
    final matchingItems = _items.where((i) =>
        i.orderNo == orderNo ||
        i.orderNo == orderIdVal ||
        i.orderNo == cleanId ||
        (i.orderNo != null && (i.orderNo!.startsWith('$orderNo-') || i.orderNo!.startsWith('$orderIdVal-'))) ||
        targetEpcs.contains(i.epc.trim().toUpperCase())).toList();

    for (final it in matchingItems) {
      targetEpcs.add(it.epc.trim().toUpperCase());
    }

    await _dbService.deleteInboundOrder(orderIdVal);
    await _dbService.deleteInboundOrder(orderNo);
    for (final epc in targetEpcs) {
      await _dbService.deleteItem(epc);
    }

    _inboundOrders.removeWhere((o) =>
        o.inboundOrderId == orderIdVal ||
        o.orderNo == orderNo ||
        o.inboundOrderId == cleanId ||
        o.orderNo == cleanId ||
        (o.orderNo.startsWith('$orderNo-')));

    _items.removeWhere((i) =>
        i.orderNo == orderNo ||
        i.orderNo == orderIdVal ||
        i.orderNo == cleanId ||
        (i.orderNo != null && (i.orderNo!.startsWith('$orderNo-') || i.orderNo!.startsWith('$orderIdVal-'))) ||
        targetEpcs.contains(i.epc.trim().toUpperCase()));

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final supa = Supabase.instance.client;
        await supa.from('inbound_order_details').delete().eq('order_id', orderIdVal);
        if (orderNo != orderIdVal) {
          await supa.from('inbound_order_details').delete().eq('order_id', orderNo);
        }
        await supa.from('inbound_orders').delete().eq('inbound_order_id', orderIdVal);
        await supa.from('inbound_orders').delete().eq('order_no', orderNo);
        if (cleanId != orderNo && cleanId != orderIdVal) {
          await supa.from('inbound_orders').delete().eq('order_no', cleanId);
        }
        await supa.from('items').delete().eq('order_no', orderNo);
        if (orderIdVal != orderNo) {
          await supa.from('items').delete().eq('order_no', orderIdVal);
        }
        if (targetEpcs.isNotEmpty) {
          final epcList = targetEpcs.toList();
          for (var i = 0; i < epcList.length; i += 100) {
            final chunk = epcList.sublist(i, i + 100 > epcList.length ? epcList.length : i + 100);
            await supa.from('items').delete().inFilter('epc', chunk);
          }
        }
      } catch (e) {
        debugPrint('deleteInboundOrder Supabase direct error: $e');
      }
    }

    await _syncDirectOrQueue(
      tableName: 'inbound_orders',
      recordId: orderIdVal,
      action: 'DELETE',
      payload: {'orderId': orderIdVal},
    );

    notifyListeners();
  }



  /// Xóa triệt để toàn bộ các đơn hàng nháp (NEW) và chip tạm (PENDING_INBOUND) khỏi DatabaseService, RAM và Supabase Cloud
  Future<void> wipeAllPendingInboundOrdersAndItems() async {
    final draftOrders = _inboundOrders.where((o) => o.status == InboundOrderStatus.newOrder).toList();
    final pendingItems = _items.where((i) => i.status == ItemStatus.pendingInbound).toList();

    final orderNos = <String>{
      for (final o in draftOrders) ...[o.orderNo, o.inboundOrderId],
      for (final it in pendingItems) if (it.orderNo != null && it.orderNo!.isNotEmpty) it.orderNo!,
    };
    final epcs = <String>{
      for (final it in pendingItems) it.epc.trim().toUpperCase(),
    };

    // 1. Xóa DatabaseService
    for (final ordNo in orderNos) {
      await _dbService.deleteInboundOrder(ordNo);
    }
    for (final epc in epcs) {
      await _dbService.deleteItem(epc);
    }

    // 2. Xóa RAM
    _inboundOrders.removeWhere((o) => o.status == InboundOrderStatus.newOrder || orderNos.contains(o.orderNo) || orderNos.contains(o.inboundOrderId));
    _items.removeWhere((i) => i.status == ItemStatus.pendingInbound || epcs.contains(i.epc.trim().toUpperCase()));
    notifyListeners();

    // 3. Xóa Supabase Cloud ngầm siêu tốc (không chặn luồng UI hay file import)
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      Future.microtask(() async {
        try {
          final supa = Supabase.instance.client;

          // Truy vấn trực tiếp Supabase để quét sạch các đơn NEW và item PENDING_INBOUND còn sót từ trước
          try {
            final supaOrders = await supa.from('inbound_orders').select('inbound_order_id, order_no').eq('status', 'NEW').timeout(const Duration(seconds: 4));
            for (final row in supaOrders) {
              final id = row['inbound_order_id']?.toString();
              final no = row['order_no']?.toString();
              if (id != null && id.isNotEmpty) orderNos.add(id);
              if (no != null && no.isNotEmpty) orderNos.add(no);
            }
          } catch (_) {}

          try {
            final supaPendingItems = await supa.from('items').select('epc, order_no').eq('status', 'PENDING_INBOUND').timeout(const Duration(seconds: 4));
            for (final row in supaPendingItems) {
              final e = row['epc']?.toString();
              final no = row['order_no']?.toString();
              if (e != null && e.isNotEmpty) epcs.add(e.trim().toUpperCase());
              if (no != null && no.isNotEmpty) orderNos.add(no);
            }
          } catch (_) {}

          // Xóa items có trạng thái PENDING_INBOUND
          try { await supa.from('items').delete().eq('status', 'PENDING_INBOUND').timeout(const Duration(seconds: 4)); } catch (_) {}
          try { await supa.from('items').delete().eq('status', 'pending_inbound').timeout(const Duration(seconds: 4)); } catch (_) {}

          // Xóa chi tiết đơn và các đơn hàng liên quan theo lô siêu tốc
          if (orderNos.isNotEmpty) {
            final ordList = orderNos.toList();
            for (var i = 0; i < ordList.length; i += 100) {
              final chunk = ordList.sublist(i, i + 100 > ordList.length ? ordList.length : i + 100);
              await Future.wait([
                supa.from('inbound_order_details').delete().inFilter('order_id', chunk).catchError((_) {}),
                supa.from('items').delete().inFilter('order_no', chunk).catchError((_) {}),
                supa.from('inbound_orders').delete().inFilter('order_no', chunk).catchError((_) {}),
                supa.from('inbound_orders').delete().inFilter('inbound_order_id', chunk).catchError((_) {}),
              ]).timeout(const Duration(seconds: 4), onTimeout: () => []);
            }
          }
          try { await supa.from('inbound_orders').delete().eq('status', 'NEW').timeout(const Duration(seconds: 4)); } catch (_) {}

          // Xóa từng chunk 100 EPC song song
          final epcList = epcs.toList();
          if (epcList.isNotEmpty) {
            final futures = <Future>[];
            for (var i = 0; i < epcList.length; i += 100) {
              final chunk = epcList.sublist(i, i + 100 > epcList.length ? epcList.length : i + 100);
              futures.add(supa.from('items').delete().inFilter('epc', chunk).catchError((_) {}));
            }
            await Future.wait(futures).timeout(const Duration(seconds: 4), onTimeout: () => []);
          }
        } catch (e) {
          debugPrint('wipeAllPendingInboundOrdersAndItems Supabase direct error: $e');
        }
      });
    }
  }

  Future<void> deleteItem(String epc) async {
    final cleanEpc = epc.trim().toUpperCase();
    await _dbService.deleteItem(cleanEpc);
    _items.removeWhere((i) => i.epc.toUpperCase() == cleanEpc);

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        await Supabase.instance.client.from('items').delete().eq('epc', cleanEpc);
      } catch (e) {
        debugPrint('deleteItem Supabase direct error: $e');
      }
    }

    await _syncDirectOrQueue(
      tableName: 'items',
      recordId: cleanEpc,
      action: 'DELETE',
      payload: {'epc': cleanEpc},
    );
    notifyListeners();
  }

  Future<void> deleteItemsByEpcs(Iterable<String> epcs) async {
    final epcSet = epcs.map((e) => e.trim().toUpperCase()).toSet();
    for (final epc in epcSet) {
      await _dbService.deleteItem(epc);
    }
    _items.removeWhere((i) => epcSet.contains(i.epc.toUpperCase()));

    if (!Platform.environment.containsKey('FLUTTER_TEST') && epcSet.isNotEmpty) {
      try {
        final supa = Supabase.instance.client;
        for (final epc in epcSet) {
          await supa.from('items').delete().eq('epc', epc);
        }
      } catch (e) {
        debugPrint('deleteItemsByEpcs Supabase direct error: $e');
      }
    }

    for (final epc in epcSet) {
      await _syncDirectOrQueue(
        tableName: 'items',
        recordId: epc,
        action: 'DELETE',
        payload: {'epc': epc},
      );
    }
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
    final Map<String, InboundOrderDetail> dedupMap = {};
    for (final d in order.details) {
      final key = d.sku.trim().toUpperCase().isNotEmpty ? d.sku.trim().toUpperCase() : d.productId;
      final cleanName = getSkuProductName(d.sku, d.productName);
      if (dedupMap.containsKey(key)) {
        final cur = dedupMap[key]!;
        dedupMap[key] = InboundOrderDetail(
          productId: cur.productId.isNotEmpty ? cur.productId : d.productId,
          sku: cur.sku.isNotEmpty ? cur.sku : d.sku,
          productName: cleanName.isNotEmpty ? cleanName : cur.productName,
          requiredQty: cur.requiredQty > d.requiredQty ? cur.requiredQty : d.requiredQty,
          receivedQty: cur.receivedQty > d.receivedQty ? cur.receivedQty : d.receivedQty,
        );
      } else {
        dedupMap[key] = InboundOrderDetail(
          productId: d.productId,
          sku: d.sku,
          productName: cleanName,
          requiredQty: d.requiredQty,
          receivedQty: d.receivedQty,
        );
      }
    }
    order.details
      ..clear()
      ..addAll(dedupMap.values);

    await _dbService.insertInboundOrder(order);
    final existingIdx = _inboundOrders.indexWhere((o) => o.orderNo == order.orderNo || o.inboundOrderId == order.inboundOrderId);
    if (existingIdx >= 0) {
      _inboundOrders[existingIdx] = order;
    } else {
      _inboundOrders.add(order);
    }

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final supa = Supabase.instance.client;
        // Đảm bảo các sản phẩm trong chi tiết đơn hàng đều đã tồn tại trên Supabase trước khi ghi inbound_order_details (tránh lỗi FK 23503)
        final prodRows = order.details.map((d) => {
          'product_id': d.productId,
          'sku': d.sku,
          'product_name': getSkuProductName(d.sku, d.productName),
          'unit': 'Cái',
          'category': 'Hàng nhập kho',
        }).toList();
        if (prodRows.isNotEmpty) {
          await supa.from('products').upsert(prodRows, onConflict: 'product_id');
        }

        await supa.from('inbound_orders').upsert({
          'inbound_order_id': order.inboundOrderId,
          'order_no': order.orderNo,
          'source_supplier': order.sourceSupplier,
          'status': order.status.code,
          'created_at': order.createdAt.toIso8601String(),
        });
        final detailRows = order.details.map((d) => {
          'order_id': order.inboundOrderId,
          'product_id': d.productId,
          'sku': d.sku,
          'product_name': getSkuProductName(d.sku, d.productName),
          'required_qty': d.requiredQty,
          'received_qty': d.receivedQty,
        }).toList();
        if (detailRows.isNotEmpty) {
          await supa.from('inbound_order_details').delete().eq('order_id', order.inboundOrderId);
          if (order.orderNo.isNotEmpty && order.orderNo != order.inboundOrderId) {
            await supa.from('inbound_order_details').delete().eq('order_id', order.orderNo);
          }
          await supa.from('inbound_order_details').insert(detailRows);
        }
      } catch (e) {
        debugPrint('addInboundOrder Supabase direct error: $e');
      }
    }

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
    final existingProd = _products.where((p) => p.productId == item.productId).firstOrNull;
    if (existingProd == null) {
      final newProd = Product(
        productId: item.productId,
        sku: item.sku,
        productName: item.productName,
        category: 'Hàng hoá',
        unit: 'Cái',
      );
      _products.add(newProd);
      await _dbService.insertProduct(newProd);
    }
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

    // Tự động bảo đảm toàn bộ sản phẩm của các item đã tồn tại trong bảng products để ngăn lỗi Foreign Key
    final existingProdIds = _products.map((p) => p.productId).toSet();
    final missingProducts = <Product>[];
    final seen = <String>{};
    for (var item in items) {
      if (!existingProdIds.contains(item.productId) && seen.add(item.productId)) {
        final newProd = Product(
          productId: item.productId,
          sku: item.sku,
          productName: item.productName,
          category: 'Hàng hoá',
          unit: 'Cái',
        );
        missingProducts.add(newProd);
        _products.add(newProd);
      }
    }
    if (missingProducts.isNotEmpty) {
      await _dbService.insertProducts(missingProducts);
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        try {
          final pRows = missingProducts.map((p) => {
            'product_id': p.productId,
            'sku': p.sku,
            'product_name': p.productName,
            'unit': p.unit,
            'category': p.category,
            'description': p.description,
          }).toList();
          await Supabase.instance.client.from('products').upsert(pRows, onConflict: 'product_id');
        } catch (e) {
          debugPrint('insertDirectItems products Supabase direct error: $e');
        }
      }
    }

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
        'supplier': item.supplier,
        'cartonCode': item.cartonCode,
        'inboundBy': item.inboundBy,
        'putawayBy': item.putawayBy,
      },
    }).toList();
    await _dbService.enqueueSyncBatch(syncRecords);

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      final supa = Supabase.instance.client;

      // 1. Bảo đảm các Pallet liên quan đã có trên Cloud để không bị chặn bởi fk_items_pallet
      final referencedPalletKeys = items
          .where((i) => i.palletId != null && i.palletId!.trim().isNotEmpty)
          .map((i) => i.palletId!.trim().toUpperCase())
          .toSet();

      if (referencedPalletKeys.isNotEmpty) {
        final palRows = <Map<String, dynamic>>[];
        for (final key in referencedPalletKeys) {
          final p = _pallets.where((pal) =>
            pal.palletId.toUpperCase() == key ||
            pal.palletCode.toUpperCase() == key ||
            pal.palletId.toUpperCase() == 'PAL-$key'
          ).firstOrNull;
          if (p != null) {
            palRows.add({
              'pallet_id': p.palletId,
              'pallet_code': p.palletCode,
              'rfid_epc': p.rfidEpc,
              'location_id': p.locationId,
              'inbound_time': p.inboundTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
              'is_multi_sku': p.isMultiSku ? 1 : 0,
            });
          } else {
            final cleanCode = key.replaceAll('PAL-', '');
            final palId = key.startsWith('PAL-') ? key : 'PAL-$key';
            palRows.add({
              'pallet_id': palId,
              'pallet_code': cleanCode,
              'rfid_epc': '',
              'location_id': null,
              'inbound_time': DateTime.now().toIso8601String(),
              'is_multi_sku': 0,
            });
          }
        }
        if (palRows.isNotEmpty) {
          try {
            await supa.from('pallets').upsert(palRows, onConflict: 'pallet_id');
          } catch (e) {
            debugPrint('insertDirectItems ensure pallets Supabase error: $e');
          }
        }
      }

      // 2. Chuẩn bị payload chuẩn và map pallet_id sang PAL- format
      try {
        final rows = items.map((item) {
          final rawPallet = item.palletId?.trim();
          String? effectivePalletId;
          if (rawPallet != null && rawPallet.isNotEmpty) {
            final matchedPal = _pallets.where((p) =>
              p.palletId.toUpperCase() == rawPallet.toUpperCase() ||
              p.palletCode.toUpperCase() == rawPallet.toUpperCase() ||
              p.palletId.toUpperCase() == 'PAL-${rawPallet.toUpperCase()}'
            ).firstOrNull;
            effectivePalletId = matchedPal?.palletId ?? (rawPallet.startsWith('PAL-') ? rawPallet : 'PAL-$rawPallet');
          }

          return {
            'item_id': item.itemId,
            'product_id': item.productId,
            'sku': item.sku,
            'product_name': item.productName,
            'serial_number': item.serialNumber,
            'epc': item.epc.toUpperCase(),
            'status': item.status.code,
            'order_no': item.orderNo,
            'pallet_id': effectivePalletId,
            'location_id': item.locationId,
            'inbound_time': item.inboundTime?.toIso8601String(),
            'allocated_time': item.allocatedTime?.toIso8601String(),
            'supplier': item.supplier,
          };
        }).toList();

        await supa.from('items').upsert(rows, onConflict: 'item_id');
        debugPrint('✓ insertDirectItems: Đồng bộ thành công ${rows.length} items lên Supabase Cloud.');
      } catch (e) {
        debugPrint('insertDirectItems Supabase direct error: $e. Thử lại với fallback an toàn không có FK...');
        try {
          final fallbackRows = items.map((item) => {
            'item_id': item.itemId,
            'product_id': item.productId,
            'sku': item.sku,
            'product_name': item.productName,
            'serial_number': item.serialNumber,
            'epc': item.epc.toUpperCase(),
            'status': item.status.code,
            'order_no': item.orderNo,
            'pallet_id': null,
            'location_id': null,
            'inbound_time': item.inboundTime?.toIso8601String(),
            'allocated_time': item.allocatedTime?.toIso8601String(),
            'supplier': item.supplier,
          }).toList();
          await supa.from('items').upsert(fallbackRows, onConflict: 'item_id');
          debugPrint('✓ insertDirectItems: Fallback an toàn (null FK) thành công ${fallbackRows.length} items lên Supabase Cloud.');
        } catch (err2) {
          debugPrint('insertDirectItems Supabase fallback error: $err2');
        }
      }
    }

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
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final rows = newProds.map((p) => {
          'product_id': p.productId,
          'sku': p.sku,
          'product_name': p.productName,
          'unit': p.unit,
          'category': p.category,
          'description': p.description,
        }).toList();
        await Supabase.instance.client.from('products').upsert(rows, onConflict: 'product_id');
      } catch (e) {
        debugPrint('addProductsBatch Supabase direct error: $e');
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
    final Map<String, OutboundOrderDetail> dedupMap = {};
    for (final d in order.details) {
      final key = d.sku.trim().toUpperCase().isNotEmpty ? d.sku.trim().toUpperCase() : d.productId;
      final cleanName = getSkuProductName(d.sku, d.productName);
      if (dedupMap.containsKey(key)) {
        final cur = dedupMap[key]!;
        dedupMap[key] = OutboundOrderDetail(
          productId: cur.productId.isNotEmpty ? cur.productId : d.productId,
          sku: cur.sku.isNotEmpty ? cur.sku : d.sku,
          productName: cleanName.isNotEmpty ? cleanName : cur.productName,
          requiredQty: cur.requiredQty > d.requiredQty ? cur.requiredQty : d.requiredQty,
          pickedQty: cur.pickedQty > d.pickedQty ? cur.pickedQty : d.pickedQty,
          epcList: {...?cur.epcList, ...?d.epcList}.toList(),
          snList: {...?cur.snList, ...?d.snList}.toList(),
        );
      } else {
        dedupMap[key] = OutboundOrderDetail(
          productId: d.productId,
          sku: d.sku,
          productName: cleanName,
          requiredQty: d.requiredQty,
          pickedQty: d.pickedQty,
          epcList: d.epcList,
          snList: d.snList,
        );
      }
    }
    order.details
      ..clear()
      ..addAll(dedupMap.values);

    await _dbService.insertOutboundOrder(order);
    final cleanPo = order.poNo.trim().toUpperCase();
    final cleanId = order.outboundOrderId.trim().toUpperCase();
    final existingIdx = _outboundOrders.indexWhere((o) =>
        (cleanId.isNotEmpty && o.outboundOrderId.trim().toUpperCase() == cleanId) ||
        (cleanPo.isNotEmpty && o.poNo.trim().toUpperCase() == cleanPo));
    if (existingIdx >= 0) {
      _outboundOrders[existingIdx] = order;
    } else {
      _outboundOrders.add(order);
    }
    if (cleanPo.isNotEmpty) {
      _outboundOrders.removeWhere((o) =>
          o.outboundOrderId != order.outboundOrderId &&
          o.poNo.trim().toUpperCase() == cleanPo);
    }

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final supa = Supabase.instance.client;
        // 1. Đảm bảo các sản phẩm trong chi tiết đơn hàng xuất đều đã tồn tại trên Supabase trước khi ghi outbound_order_details (tránh lỗi FK 23503)
        final prodRows = <Map<String, dynamic>>[];
        for (final d in order.details) {
          final matchingProd = _products.where((p) =>
              p.sku.trim().toUpperCase() == d.sku.trim().toUpperCase() ||
              p.productId == d.productId).firstOrNull;
          final prodId = matchingProd?.productId ?? d.productId;
          prodRows.add({
            'product_id': prodId,
            'sku': d.sku,
            'product_name': getSkuProductName(d.sku, d.productName),
            'unit': matchingProd?.unit ?? 'Cái',
            'category': matchingProd?.category ?? 'Hàng xuất kho',
          });
        }
        if (prodRows.isNotEmpty) {
          await supa.from('products').upsert(prodRows, onConflict: 'product_id');
        }

        // 2. Ghi/Cập nhật đơn xuất kho trên Supabase Cloud
        await supa.from('outbound_orders').upsert({
          'outbound_order_id': order.outboundOrderId,
          'po_no': order.poNo,
          'customer': order.customer,
          'status': order.status.code,
          'created_at': order.createdAt.toIso8601String(),
        }, onConflict: 'outbound_order_id');

        // 3. Ghi chi tiết đơn xuất kho vào outbound_order_details (xóa cũ trước để tránh trùng lặp)
        await supa.from('outbound_order_details').delete().eq('order_id', order.outboundOrderId);
        final detailRows = order.details.map((d) {
          final matchingProd = _products.where((p) =>
              p.sku.trim().toUpperCase() == d.sku.trim().toUpperCase() ||
              p.productId == d.productId).firstOrNull;
          final prodId = matchingProd?.productId ?? d.productId;
          return {
            'order_id': order.outboundOrderId,
            'product_id': prodId,
            'sku': d.sku,
            'product_name': getSkuProductName(d.sku, d.productName),
            'required_qty': d.requiredQty,
            'picked_qty': d.pickedQty,
          };
        }).toList();
        if (detailRows.isNotEmpty) {
          await supa.from('outbound_order_details').insert(detailRows);
        }
      } catch (e) {
        debugPrint('addOutboundOrder Supabase direct error: $e');
      }
    }

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

  Future<void> deleteOutboundOrder(String orderId) async {
    final cleanId = orderId.trim();
    final cleanUpper = cleanId.toUpperCase();
    final isExplicitId = _outboundOrders.any((o) => o.outboundOrderId.trim().toUpperCase() == cleanUpper);

    final String resolvedOrderId;
    final String resolvedPoNo;

    if (isExplicitId) {
      final targetOrder = _outboundOrders.firstWhere((o) => o.outboundOrderId.trim().toUpperCase() == cleanUpper);
      resolvedOrderId = targetOrder.outboundOrderId;
      resolvedPoNo = targetOrder.poNo;

      await _dbService.deleteOutboundOrder(resolvedOrderId);
      _outboundOrders.removeWhere((o) => o.outboundOrderId.trim().toUpperCase() == cleanUpper);

      _transactions.removeWhere((t) =>
          t.type == TransactionType.outbound &&
          (t.documentNo.trim().toUpperCase() == resolvedOrderId.trim().toUpperCase() ||
           t.transactionId.trim().toUpperCase() == resolvedOrderId.trim().toUpperCase()));

      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        try {
          final supa = Supabase.instance.client;
          await supa.from('outbound_order_details').delete().eq('order_id', resolvedOrderId);
          await supa.from('outbound_orders').delete().eq('outbound_order_id', resolvedOrderId);
          await supa.from('inventory_transactions').delete().eq('document_no', resolvedOrderId);
        } catch (e) {
          debugPrint('deleteOutboundOrder Supabase direct error: $e');
        }
      }
    } else {
      final targetOrder = _outboundOrders.where((o) => o.poNo.trim().toUpperCase() == cleanUpper).firstOrNull;
      resolvedPoNo = targetOrder?.poNo ?? cleanId;
      resolvedOrderId = targetOrder?.outboundOrderId ?? cleanId;

      await _dbService.deleteOutboundOrder(resolvedOrderId);
      await _dbService.deleteOutboundOrder(resolvedPoNo);

      final poUpper = resolvedPoNo.trim().toUpperCase();
      final idUpper = resolvedOrderId.trim().toUpperCase();
      _outboundOrders.removeWhere((o) =>
          o.outboundOrderId.trim().toUpperCase() == idUpper ||
          o.poNo.trim().toUpperCase() == poUpper ||
          o.outboundOrderId.trim().toUpperCase() == cleanUpper ||
          o.poNo.trim().toUpperCase() == cleanUpper);

      _transactions.removeWhere((t) =>
          t.type == TransactionType.outbound &&
          (t.documentNo.trim().toUpperCase() == poUpper ||
           t.documentNo.trim().toUpperCase() == idUpper ||
           t.documentNo.trim().toUpperCase() == cleanUpper ||
           t.transactionId.trim().toUpperCase() == cleanUpper));

      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        try {
          final supa = Supabase.instance.client;
          await supa.from('outbound_order_details').delete().eq('order_id', resolvedOrderId);
          if (resolvedPoNo != resolvedOrderId) {
            await supa.from('outbound_order_details').delete().eq('order_id', resolvedPoNo);
          }
          await supa.from('outbound_orders').delete().eq('outbound_order_id', resolvedOrderId);
          await supa.from('outbound_orders').delete().eq('po_no', resolvedPoNo);
          if (cleanId != resolvedPoNo && cleanId != resolvedOrderId) {
            await supa.from('outbound_orders').delete().eq('po_no', cleanId);
          }
          await supa.from('inventory_transactions').delete().eq('document_no', resolvedPoNo);
          if (resolvedOrderId != resolvedPoNo) {
            await supa.from('inventory_transactions').delete().eq('document_no', resolvedOrderId);
          }
        } catch (e) {
          debugPrint('deleteOutboundOrder Supabase direct error: $e');
        }
      }
    }

    await _syncDirectOrQueue(
      tableName: 'outbound_orders',
      recordId: resolvedOrderId,
      action: 'DELETE',
      payload: {'outbound_order_id': resolvedOrderId, 'po_no': resolvedPoNo},
    );

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

  /// Xóa toàn bộ danh sách kệ trong kho (CSDL và bộ nhớ) để người dùng tự thiết lập lại
  Future<void> deleteAllLocations() async {
    await _dbService.deleteAllLocations();
    _locations.clear();
    for (final p in _pallets) {
      p.locationId = null;
    }
    for (final it in _items) {
      it.locationId = null;
    }
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

  /// Đảm bảo luôn có sẵn 10 ô vị trí sơ đồ kho (Vị trí 01 đến Vị trí 10)
  Future<void> ensureDefault10Locations() async {
    final defaultSlots = [
      {'code': 'A-01', 'zone': 'Khu A', 'shelf': 'Kệ 01', 'level': 'Tầng 1', 'capacity': 50, 'aisle': 'LEFT', 'order': 1},
      {'code': 'A-02', 'zone': 'Khu A', 'shelf': 'Kệ 02', 'level': 'Tầng 1', 'capacity': 50, 'aisle': 'LEFT', 'order': 2},
      {'code': 'A-03', 'zone': 'Khu A', 'shelf': 'Kệ 03', 'level': 'Tầng 1', 'capacity': 50, 'aisle': 'LEFT', 'order': 3},
      {'code': 'A-04', 'zone': 'Khu A', 'shelf': 'Kệ 04', 'level': 'Tầng 1', 'capacity': 50, 'aisle': 'LEFT', 'order': 4},
      {'code': 'A-05', 'zone': 'Khu A', 'shelf': 'Kệ 05', 'level': 'Tầng 1', 'capacity': 50, 'aisle': 'LEFT', 'order': 5},
      {'code': 'B-01', 'zone': 'Khu B', 'shelf': 'Kệ 01', 'level': 'Tầng 1', 'capacity': 50, 'aisle': 'RIGHT', 'order': 1},
      {'code': 'B-02', 'zone': 'Khu B', 'shelf': 'Kệ 02', 'level': 'Tầng 1', 'capacity': 50, 'aisle': 'RIGHT', 'order': 2},
      {'code': 'B-03', 'zone': 'Khu B', 'shelf': 'Kệ 03', 'level': 'Tầng 1', 'capacity': 50, 'aisle': 'RIGHT', 'order': 3},
      {'code': 'B-04', 'zone': 'Khu B', 'shelf': 'Kệ 04', 'level': 'Tầng 1', 'capacity': 50, 'aisle': 'RIGHT', 'order': 4},
      {'code': 'B-05', 'zone': 'Khu B', 'shelf': 'Kệ 05', 'level': 'Tầng 1', 'capacity': 50, 'aisle': 'RIGHT', 'order': 5},
    ];

    bool changed = false;
    for (int i = 0; i < defaultSlots.length; i++) {
      final slot = defaultSlots[i];
      final code = slot['code'] as String;
      final existingIdx = _locations.indexWhere((l) =>
          l.locationCode.trim().toUpperCase() == code.toUpperCase() ||
          l.locationId.trim().toUpperCase() == 'LOC-$code'.toUpperCase());
      if (existingIdx == -1) {
        if (_locations.length < 10) {
          final loc = Location(
            locationId: 'LOC-$code',
            locationCode: code,
            zone: slot['zone'] as String,
            shelf: slot['shelf'] as String,
            level: slot['level'] as String,
            maxPalletCapacity: (slot['capacity'] as int?) ?? 50,
            currentPallets: 0,
            status: 'AVAILABLE',
            aisleSide: slot['aisle'] as String,
            sortOrder: slot['order'] as int,
          );
          _locations.add(loc);
          await _dbService.insertLocation(loc);
          changed = true;
        }
      } else {
        // Cập nhật bổ sung aisleSide và sortOrder nếu chưa được phân dãy
        final loc = _locations[existingIdx];
        if (loc.aisleSide != slot['aisle'] || loc.sortOrder == 0) {
          final updated = loc.copyWith(
            aisleSide: slot['aisle'] as String,
            sortOrder: slot['order'] as int,
          );
          _locations[existingIdx] = updated;
          await _dbService.insertLocation(updated);
          changed = true;
        }
      }
    }
    if (changed) {
      notifyListeners();
    }
  }

  /// Lưu cấu hình sơ đồ mặt bằng kho thực tế của khách hàng
  Future<void> saveWarehouseLayoutConfig(WarehouseFloorPlanConfig config) async {
    _floorPlanConfig = config;
    await _dbService.saveWarehouseLayoutConfig(config);
    notifyListeners();
  }

  /// Thêm vị trí kệ mới tùy chỉnh cho khách hàng
  Future<void> addCustomLocation(Location loc) async {
    final cleanId = loc.locationId.trim();
    _locations.removeWhere((l) =>
        l.locationId == cleanId ||
        l.locationCode.trim().toUpperCase() == loc.locationCode.trim().toUpperCase());
    _locations.add(loc);
    await _dbService.insertLocation(loc);
    await _syncDirectOrQueue(
      tableName: 'locations',
      recordId: loc.locationId,
      action: 'INSERT',
      payload: loc.toMap(),
    );
    notifyListeners();
  }

  /// Xóa vị trí kệ
  Future<void> deleteCustomLocation(String locationIdOrCode) async {
    final clean = locationIdOrCode.trim().toUpperCase();
    _locations.removeWhere((l) =>
        l.locationId.trim().toUpperCase() == clean ||
        l.locationCode.trim().toUpperCase() == clean);
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

  /// Đặt lại sơ đồ kho theo mẫu định sẵn
  Future<void> resetLayoutToPreset(WarehouseLayoutType type) async {
    _floorPlanConfig = _floorPlanConfig.copyWith(layoutType: type);
    await _dbService.saveWarehouseLayoutConfig(_floorPlanConfig);

    // Bố trí lại các vị trí kệ theo mẫu mới
    if (type == WarehouseLayoutType.parallelAisles) {
      int leftIdx = 1;
      int rightIdx = 1;
      for (int i = 0; i < _locations.length; i++) {
        final loc = _locations[i];
        if (loc.locationCode.startsWith('A') || i % 2 == 0) {
          _locations[i] = loc.copyWith(aisleSide: 'LEFT', sortOrder: leftIdx++);
        } else {
          _locations[i] = loc.copyWith(aisleSide: 'RIGHT', sortOrder: rightIdx++);
        }
        await _dbService.insertLocation(_locations[i]);
      }
    } else if (type == WarehouseLayoutType.uShape) {
      final total = _locations.length;
      final part = (total / 3).ceil();
      for (int i = 0; i < _locations.length; i++) {
        final loc = _locations[i];
        if (i < part) {
          _locations[i] = loc.copyWith(aisleSide: 'LEFT', sortOrder: i + 1);
        } else if (i < part * 2) {
          _locations[i] = loc.copyWith(aisleSide: 'BACK', sortOrder: i - part + 1);
        } else {
          _locations[i] = loc.copyWith(aisleSide: 'RIGHT', sortOrder: i - part * 2 + 1);
        }
        await _dbService.insertLocation(_locations[i]);
      }
    }
    notifyListeners();
  }

  /// Danh sách tất cả sản phẩm (Item) thực tế đang nằm tại vị trí kệ này (trực tiếp hoặc qua Pallet)
  List<Item> getItemsAtLocation(Location loc) {
    final cleanCode = loc.locationCode.trim().toUpperCase();
    final cleanId = loc.locationId.trim().toUpperCase();
    final targetIds = {cleanCode, cleanId};

    final palletIdsAtLoc = _pallets
        .where((p) => p.locationId != null && targetIds.contains(p.locationId!.trim().toUpperCase()))
        .map((p) => p.palletId.trim().toUpperCase())
        .toSet();

    return _items.where((it) {
      if (it.status == ItemStatus.out) return false;
      final itLoc = it.locationId?.trim().toUpperCase();
      if (itLoc != null && targetIds.contains(itLoc)) return true;
      final itPal = it.palletId?.trim().toUpperCase();
      if (itPal != null && palletIdsAtLoc.contains(itPal)) return true;
      return false;
    }).toList();
  }

  /// Cập nhật thông tin chi tiết vị trí kệ (Tên hiển thị, Sức chứa, Khu vực, Trạng thái...)
  Future<void> updateLocationDetails({
    required String locationId,
    required String locationCode,
    required String zone,
    required String shelf,
    required String level,
    required int maxCapacity,
    String? status,
    String? aisleSide,
    int? sortOrder,
  }) async {
    final cleanId = locationId.trim().toUpperCase();
    final idx = _locations.indexWhere((l) =>
        l.locationId.trim().toUpperCase() == cleanId ||
        l.locationCode.trim().toUpperCase() == cleanId);
    if (idx != -1) {
      final old = _locations[idx];
      final updated = old.copyWith(
        locationCode: locationCode.trim(),
        zone: zone.trim(),
        shelf: shelf.trim(),
        level: level.trim(),
        maxPalletCapacity: maxCapacity,
        status: status ?? old.status,
        aisleSide: aisleSide ?? old.aisleSide,
        sortOrder: sortOrder ?? old.sortOrder,
      );
      _locations[idx] = updated;
      await _dbService.insertLocation(updated);
      await _syncDirectOrQueue(
        tableName: 'locations',
        recordId: updated.locationId,
        action: 'UPDATE',
        payload: updated.toMap(),
      );
      _triggerBackgroundSync();
      notifyListeners();
    }
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
    final stripped = cleanId.startsWith('LOC-') ? cleanId.substring(4) : cleanId;
    final withLoc = cleanId.startsWith('LOC-') ? cleanId : 'LOC-$cleanId';

    final loc = _locations.where((l) =>
        l.locationId.trim().toUpperCase() == cleanId ||
        l.locationCode.trim().toUpperCase() == cleanId ||
        l.locationId.trim().toUpperCase() == withLoc ||
        l.locationCode.trim().toUpperCase() == stripped
    ).firstOrNull;

    if (loc != null) {
      loc.status = status;
    }

    final targetId = loc?.locationId ?? locationId;
    final targetCode = loc?.locationCode ?? stripped;
    await _dbService.updateLocationStatus(targetId, status);

    await _syncDirectOrQueue(
      tableName: 'locations',
      recordId: targetId,
      action: 'UPDATE',
      payload: {
        'location_id': targetId,
        'location_code': targetCode,
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

  Future<void> _syncInventoryTransaction(InventoryTransaction tx) async {
    await _dbService.insertTransaction(tx);
    final effectiveRecordId = (tx.documentNo.isNotEmpty && !tx.documentNo.startsWith('PDA-DIRECT'))
        ? tx.documentNo
        : tx.transactionId;
    final payload = {
      'transaction_id': tx.transactionId,
      'transaction_type': tx.type.name.toUpperCase(),
      'document_no': tx.documentNo,
      'sku': tx.sku,
      'product_name': tx.productName,
      'quantity': tx.quantity,
      'from_location': tx.fromLocation,
      'to_location': tx.toLocation,
      'pallet_code': tx.palletCode,
      'performed_by': tx.performedBy,
      'timestamp': tx.timestamp.toIso8601String(),
      'notes': tx.notes,
    };
    try {
      await _syncDirectOrQueue(
        tableName: 'inventory_transactions',
        recordId: effectiveRecordId,
        action: 'INSERT',
        payload: payload,
      );
    } catch (_) {}
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
  final List<LocateOrder> _locateOrders = [];
  final List<InventoryTransaction> _transactions = [];
  final List<TagLifecycleLog> _tagLifecycleLogs = [];
  final List<RfidDevice> _devices = [];
  final List<WmsUser> _users = [];
  final List<Customer> _customers = [];
  final List<DeliveryNote> _deliveryNotes = [];

  final Map<String, Pallet> _palletsByCodeIndex = {};
  final Map<String, Pallet> _palletsByRfidIndex = {};
  final Map<String, Pallet> _palletsByHexIndex = {};
  final Map<String, Item> _itemsByEpcIndex = {};
  bool _indexesDirty = true;

  // PDA high-performance lookup indexes
  final Map<String, List<Item>> _inStockItemsByPalletIndex = {};
  final Map<String, List<Item>> _inStockItemsByLocationIndex = {};
  final Map<String, Location> _locationsByIdOrCodeIndex = {};
  final Map<String, Item> _itemsByIdIndex = {};
  final Map<String, List<Pallet>> _palletsByLocationIndex = {};
  final Map<String, InboundOrder> _inboundOrdersByNoIndex = {};

  void _rebuildIndexes() {
    _inboundOrdersByNoIndex.clear();
    for (final o in _inboundOrders) {
      final oNo = o.orderNo.trim().toUpperCase();
      final oId = o.inboundOrderId.trim().toUpperCase();
      if (oNo.isNotEmpty) _inboundOrdersByNoIndex[oNo] = o;
      if (oId.isNotEmpty) _inboundOrdersByNoIndex[oId] = o;
    }
    _palletsByCodeIndex.clear();
    _palletsByRfidIndex.clear();
    _palletsByHexIndex.clear();
    _palletsByLocationIndex.clear();
    for (final p in _pallets) {
      final pCode = p.palletCode.trim().toUpperCase();
      final pId = p.palletId.trim().toUpperCase();
      if (pCode.isNotEmpty) _palletsByCodeIndex[pCode] = p;
      if (pId.isNotEmpty) _palletsByCodeIndex[pId] = p;
      final rfid = (p.rfidEpc ?? '').trim().toUpperCase();
      if (rfid.isNotEmpty) _palletsByRfidIndex[rfid] = p;
      final hexCode = p.palletCode.codeUnits.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');
      if (hexCode.isNotEmpty) _palletsByHexIndex[hexCode] = p;
      final pLoc = p.locationId?.trim().toUpperCase();
      if (pLoc != null && pLoc.isNotEmpty) {
        _palletsByLocationIndex.putIfAbsent(pLoc, () => []).add(p);
      }
    }

    _locationsByIdOrCodeIndex.clear();
    for (final loc in _locations) {
      final code = loc.locationCode.trim().toUpperCase();
      final id = loc.locationId.trim().toUpperCase();
      if (code.isNotEmpty) _locationsByIdOrCodeIndex[code] = loc;
      if (id.isNotEmpty) _locationsByIdOrCodeIndex[id] = loc;
    }

    _itemsByEpcIndex.clear();
    _itemsByIdIndex.clear();
    _inStockItemsByPalletIndex.clear();
    _inStockItemsByLocationIndex.clear();

    for (final it in _items) {
      final cleanEpc = it.epc.trim().toUpperCase();
      if (cleanEpc.isNotEmpty) _itemsByEpcIndex[cleanEpc] = it;
      if (it.itemId.isNotEmpty) _itemsByIdIndex[it.itemId] = it;

      if (it.status == ItemStatus.inStock) {
        if (it.palletId != null && it.palletId!.trim().isNotEmpty) {
          final pKey = it.palletId!.trim().toUpperCase();
          _inStockItemsByPalletIndex.putIfAbsent(pKey, () => []).add(it);
        }
        if (it.locationId != null && it.locationId!.trim().isNotEmpty) {
          final locKey = it.locationId!.trim().toUpperCase();
          _inStockItemsByLocationIndex.putIfAbsent(locKey, () => []).add(it);
        }
      }
    }
    _indexesDirty = false;
  }

  /// Lazy rebuild: chỉ xây lại indexes khi thực sự cần tra cứu VÀ dữ liệu đã thay đổi
  void _ensureIndexes() {
    if (_indexesDirty) _rebuildIndexes();
  }

  @override
  void notifyListeners() {
    _indexesDirty = true;
    super.notifyListeners();
  }

  /// Tra cứu danh sách mặt hàng đang lưu kho (ItemStatus.inStock) của Pallet - O(1)
  List<Item> getInStockItemsForPallet(String palletId, {String? palletCode, List<String>? itemIds}) {
    _ensureIndexes();
    final List<Item> results = [];
    final seen = <String>{};

    void addFromKey(String key) {
      final list = _inStockItemsByPalletIndex[key.trim().toUpperCase()];
      if (list != null) {
        for (final it in list) {
          if (seen.add(it.itemId)) results.add(it);
        }
      }
    }

    if (palletId.isNotEmpty) addFromKey(palletId);
    if (palletCode != null && palletCode.isNotEmpty) addFromKey(palletCode);

    if (itemIds != null && itemIds.isNotEmpty) {
      for (final id in itemIds) {
        if (!seen.contains(id)) {
          final it = _itemsByIdIndex[id];
          if (it != null && it.status == ItemStatus.inStock) {
            seen.add(it.itemId);
            results.add(it);
          }
        }
      }
    }
    return results;
  }

  /// Kiểm tra nhanh xem Pallet có chứa hàng tồn kho hay không - O(1)
  bool hasInStockItemsOnPallet(Pallet p) {
    _ensureIndexes();
    final pId = p.palletId.trim().toUpperCase();
    final pCode = p.palletCode.trim().toUpperCase();
    if (_inStockItemsByPalletIndex[pId]?.isNotEmpty ?? false) return true;
    if (_inStockItemsByPalletIndex[pCode]?.isNotEmpty ?? false) return true;
    for (final itId in p.itemIds) {
      final it = _itemsByIdIndex[itId];
      if (it != null && it.status == ItemStatus.inStock) return true;
    }
    return false;
  }

  /// Tra cứu danh sách mặt hàng đang lưu kho (ItemStatus.inStock) tại Kệ/Vị trí - O(1)
  List<Item> getInStockItemsAtLocation(String locCode, {String? locId}) {
    _ensureIndexes();
    final List<Item> results = [];
    final seen = <String>{};

    void addFromKey(String key) {
      final list = _inStockItemsByLocationIndex[key.trim().toUpperCase()];
      if (list != null) {
        for (final it in list) {
          if (seen.add(it.itemId)) results.add(it);
        }
      }
    }

    if (locCode.isNotEmpty) addFromKey(locCode);
    if (locId != null && locId.isNotEmpty && locId != locCode) addFromKey(locId);

    return results;
  }

  /// Tra cứu danh sách Pallet đang đặt tại Vị trí/Kệ - O(1)
  List<Pallet> getPalletsAtLocation(String locCode, {String? locId}) {
    _ensureIndexes();
    final c = locCode.trim().toUpperCase();
    final fromCode = _palletsByLocationIndex[c] ?? const <Pallet>[];
    if (locId != null && locId.isNotEmpty && locId.trim().toUpperCase() != c) {
      final fromId = _palletsByLocationIndex[locId.trim().toUpperCase()] ?? const <Pallet>[];
      if (fromId.isNotEmpty) {
        final set = {...fromCode, ...fromId};
        return set.toList();
      }
    }
    return fromCode;
  }

  /// Tra cứu nhanh Pallet theo ID hoặc Mã - O(1)
  Pallet? findPalletFast(String? idOrCode) {
    if (idOrCode == null) return null;
    final clean = idOrCode.trim().toUpperCase();
    if (clean.isEmpty) return null;
    _ensureIndexes();
    return _palletsByCodeIndex[clean];
  }

  /// Tra cứu nhanh Kệ theo ID hoặc Mã - O(1)
  Location? findLocationFast(String? idOrCode) {
    if (idOrCode == null) return null;
    final clean = idOrCode.trim().toUpperCase();
    if (clean.isEmpty) return null;
    _ensureIndexes();
    return _locationsByIdOrCodeIndex[clean];
  }

  WarehouseFloorPlanConfig _floorPlanConfig = WarehouseFloorPlanConfig.defaultConfig();
  WarehouseFloorPlanConfig get floorPlanConfig => _floorPlanConfig;

  List<Product> get products => List.unmodifiable(_products);
  List<Location> get locations => List.unmodifiable(_locations);
  List<Pallet> get pallets => List.unmodifiable(_pallets);
  List<Item> get items => List.unmodifiable(_items);
  List<InboundOrder> get inboundOrders => List.unmodifiable(_inboundOrders);
  List<OutboundOrder> get outboundOrders => List.unmodifiable(_outboundOrders);
  List<PickingPlan> get pickingPlans => List.unmodifiable(_pickingPlans);
  List<InventorySession> get inventorySessions => List.unmodifiable(_inventorySessions);
  List<LocateOrder> get locateOrders => List.unmodifiable(_locateOrders);
  List<InventoryTransaction> get transactions => List.unmodifiable(_transactions);
  List<TagLifecycleLog> get tagLifecycleLogs => List.unmodifiable(_tagLifecycleLogs);
  List<RfidDevice> get devices => List.unmodifiable(_devices);
  List<WmsUser> get users => List.unmodifiable(_users);
  List<Customer> get customers => List.unmodifiable(_customers);
  List<DeliveryNote> get deliveryNotes => List.unmodifiable(_deliveryNotes);

  /// Kiểm tra xem một đơn hàng nhập kho đã được xếp hoàn tất vào kệ lưu trữ hay chưa
  bool isInboundOrderPutawayCompleted(InboundOrder order) {
    if (order.status == InboundOrderStatus.completed) return true;
    final ordNo = order.orderNo.trim().toUpperCase();
    final ordId = order.inboundOrderId.trim().toUpperCase();

    // Tìm tất cả các items thuộc đơn hàng này trong kho
    final orderItems = _items.where((it) {
      final itemOrd = (it.orderNo ?? '').trim().toUpperCase();
      return itemOrd == ordNo ||
          itemOrd == 'INB-$ordNo' ||
          'INB-$itemOrd' == ordNo ||
          (ordId.isNotEmpty && itemOrd == ordId);
    }).toList();

    if (orderItems.isEmpty) {
      return false;
    }

    // Đơn hàng hoàn tất khi tất cả sản phẩm đều đã được cất lên kệ hợp lệ
    final allPutaway = orderItems.every((it) =>
        it.status == ItemStatus.inStock &&
        it.locationId != null &&
        it.locationId!.trim().isNotEmpty &&
        it.locationId != 'LOC-GATE-IN' &&
        it.locationId != 'CỔNG GATE (IN)');

    return allPutaway;
  }

  /// Tự động quét và hoàn tất trạng thái các đơn nhập kho mà toàn bộ mặt hàng đã xếp vào kệ
  Future<void> autoResolveCompletedInboundOrders() async {
    final now = DateTime.now();
    for (final ord in _inboundOrders) {
      if (ord.status != InboundOrderStatus.completed && isInboundOrderPutawayCompleted(ord)) {
        ord.status = InboundOrderStatus.completed;
        for (var d in ord.details) {
          d.receivedQty = d.requiredQty;
        }
        await _dbService.updateInboundOrderStatus(ord.inboundOrderId, InboundOrderStatus.completed);
        await _syncDirectOrQueue(
          tableName: 'inbound_orders',
          recordId: ord.inboundOrderId,
          action: 'UPDATE',
          payload: {
            'inbound_order_id': ord.inboundOrderId,
            'status': InboundOrderStatus.completed.code,
            'updated_at': now.toIso8601String(),
          },
        );
      }
    }
  }

  /// Ghi nhận nhật ký vòng đời thẻ RFID (Tag Lifecycle Log / Audit Trail)
  Future<TagLifecycleLog> recordTagLifecycle({
    required String epc,
    String? itemId,
    String? sku,
    String? productName,
    String? serialNumber,
    required TagLifecycleAction action,
    String? previousStatus,
    required String newStatus,
    String? fromLocation,
    String? toLocation,
    String? fromPallet,
    String? toPallet,
    String? documentNo,
    required String performedBy,
    String? device,
    DateTime? timestamp,
    String? notes,
  }) async {
    final cleanEpc = epc.trim().toUpperCase();
    final item = _items.where((i) => i.epc.trim().toUpperCase() == cleanEpc).firstOrNull;
    final effItemId = itemId ?? item?.itemId;
    final effSku = sku ?? item?.sku;
    final effProdName = productName ?? item?.productName;
    final effSerial = serialNumber ?? item?.serialNumber;

    final log = TagLifecycleLog(
      logId: 'TAGLOG-${DateTime.now().millisecondsSinceEpoch}-${cleanEpc.length >= 6 ? cleanEpc.substring(cleanEpc.length - 6) : cleanEpc}',
      epc: cleanEpc,
      itemId: effItemId,
      sku: effSku,
      productName: effProdName,
      serialNumber: effSerial,
      action: action,
      previousStatus: previousStatus,
      newStatus: newStatus,
      fromLocation: fromLocation,
      toLocation: toLocation,
      fromPallet: fromPallet,
      toPallet: toPallet,
      documentNo: documentNo,
      performedBy: performedBy,
      device: device,
      timestamp: timestamp ?? DateTime.now(),
      notes: notes,
    );

    _tagLifecycleLogs.insert(0, log);
    await _dbService.insertTagLifecycleLog(log);

    await _syncDirectOrQueue(
      tableName: 'tag_lifecycle_logs',
      recordId: log.logId,
      action: 'INSERT',
      payload: log.toMap(),
    );

    notifyListeners();
    return log;
  }

  /// Tra cứu toàn bộ lịch sử vòng đời của thẻ RFID theo mã EPC (hoặc item ID)
  List<TagLifecycleLog> getTagLifecycle(String epc) {
    final cleanEpc = epc.trim().toUpperCase();
    final logs = _tagLifecycleLogs
        .where((l) => l.epc.toUpperCase() == cleanEpc)
        .toList();

    final item = _items.where((it) => it.epc.toUpperCase() == cleanEpc || it.itemId.toUpperCase() == cleanEpc).firstOrNull;

    // Nếu không có item trong kho và không có logs, trả về rỗng
    if (item == null && logs.isEmpty) return const [];
    if (item == null) return logs..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    // Kiểm tra xem các mốc cơ bản đã tồn tại trong logs chưa
    final hasEncoded = logs.any((l) => l.action == TagLifecycleAction.encoded);
    final hasInbound = logs.any((l) => l.action == TagLifecycleAction.inboundGate || l.action == TagLifecycleAction.inboundPda);
    final hasPalletize = logs.any((l) => l.action == TagLifecycleAction.palletize);
    final hasPutaway = logs.any((l) => l.action == TagLifecycleAction.putaway);
    final hasOut = logs.any((l) => l.action == TagLifecycleAction.outboundGate || l.action == TagLifecycleAction.outboundPda);

    final combinedLogs = List<TagLifecycleLog>.from(logs);
    final baseTime = item.inboundTime ?? (logs.isNotEmpty ? logs.last.timestamp.subtract(const Duration(hours: 1)) : DateTime.now().subtract(const Duration(hours: 2)));

    // Xác định Kệ và Pallet ban đầu (trước khi phát sinh các đợt điều chuyển vị trí)
    final transferLogs = logs
        .where((l) => (l.action == TagLifecycleAction.transferLocation || l.action == TagLifecycleAction.mergePallet) &&
                      l.fromLocation != null && l.fromLocation!.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    String? initialLoc = transferLogs.isNotEmpty ? transferLogs.first.fromLocation : item.locationId;
    String? initialPal = transferLogs.isNotEmpty ? (transferLogs.first.fromPallet ?? item.palletId) : item.palletId;
    if ((initialLoc == null || initialLoc.isEmpty) && initialPal != null && initialPal.isNotEmpty) {
      final p = _pallets.where((pal) => pal.palletId == initialPal || pal.palletCode == initialPal).firstOrNull;
      initialLoc = p?.locationId;
    }

    // Mốc 1: Khởi tạo & Gán mã chip RFID (nếu chưa có log gán mã)
    if (!hasEncoded) {
      combinedLogs.add(TagLifecycleLog(
        logId: 'INIT-${item.itemId}',
        epc: item.epc,
        itemId: item.itemId,
        sku: item.sku,
        productName: item.productName,
        serialNumber: item.serialNumber,
        action: TagLifecycleAction.encoded,
        newStatus: ItemStatus.pendingInbound.label,
        documentNo: item.orderNo,
        performedBy: 'Hệ thống khởi tạo',
        device: 'RFID Station',
        timestamp: baseTime.subtract(const Duration(minutes: 30)),
        notes: 'Gán mã chip RFID cho sản phẩm ${item.sku}',
      ));
    }

    // Mốc 2: Nhập kho (nếu chưa có log nhập kho)
    if (!hasInbound) {
      combinedLogs.add(TagLifecycleLog(
        logId: 'INBOUND-${item.itemId}',
        epc: item.epc,
        itemId: item.itemId,
        sku: item.sku,
        productName: item.productName,
        serialNumber: item.serialNumber,
        action: TagLifecycleAction.inboundGate,
        previousStatus: ItemStatus.pendingInbound.label,
        newStatus: (initialPal != null && initialPal.isNotEmpty) ? ItemStatus.waitingPalletize.label : ItemStatus.waitingPutaway.label,
        fromPallet: null,
        toPallet: initialPal,
        toLocation: initialLoc,
        documentNo: item.orderNo,
        performedBy: item.inboundByDisplay,
        device: 'Cổng RFID Gate / PDA',
        timestamp: baseTime,
        notes: 'Xác nhận nhập kho theo đơn ${item.orderNo ?? "PO"}',
      ));
    }

    // Mốc 3: Xếp vào Pallet (nếu có pallet và chưa có log pallet)
    if (!hasPalletize && initialPal != null && initialPal.isNotEmpty) {
      combinedLogs.add(TagLifecycleLog(
        logId: 'PALLET-${item.itemId}',
        epc: item.epc,
        itemId: item.itemId,
        sku: item.sku,
        productName: item.productName,
        serialNumber: item.serialNumber,
        action: TagLifecycleAction.palletize,
        previousStatus: ItemStatus.waitingPalletize.label,
        newStatus: ItemStatus.waitingPutaway.label,
        toPallet: initialPal,
        toLocation: initialLoc,
        performedBy: item.inboundByDisplay,
        timestamp: baseTime.add(const Duration(minutes: 5)),
        notes: 'Xếp sản phẩm vào Pallet $initialPal',
      ));
    }

    // Mốc 4: Cất kệ / Lưu vào vị trí (nếu đã inStock hoặc có locationId và chưa có log cất kệ)
    if (!hasPutaway && (item.status == ItemStatus.inStock || (initialLoc != null && initialLoc.isNotEmpty))) {
      combinedLogs.add(TagLifecycleLog(
        logId: 'PUTAWAY-${item.itemId}',
        epc: item.epc,
        itemId: item.itemId,
        sku: item.sku,
        productName: item.productName,
        serialNumber: item.serialNumber,
        action: TagLifecycleAction.putaway,
        previousStatus: ItemStatus.waitingPutaway.label,
        newStatus: ItemStatus.inStock.label,
        toLocation: initialLoc ?? item.locationId,
        toPallet: initialPal ?? item.palletId,
        performedBy: item.putawayByDisplay,
        device: 'SEUIC UTouch 2 PDA',
        timestamp: baseTime.add(const Duration(minutes: 20)),
        notes: 'Cất hàng lên vị trí kệ ${initialLoc ?? item.locationId ?? ""}',
      ));
    }

    // Mốc 5: Xuất kho (nếu đã out và chưa có log xuất)
    if (!hasOut && item.status == ItemStatus.out) {
      combinedLogs.add(TagLifecycleLog(
        logId: 'OUT-${item.itemId}',
        epc: item.epc,
        itemId: item.itemId,
        sku: item.sku,
        productName: item.productName,
        serialNumber: item.serialNumber,
        action: TagLifecycleAction.outboundGate,
        previousStatus: ItemStatus.inStock.label,
        newStatus: ItemStatus.out.label,
        fromLocation: item.locationId,
        fromPallet: item.palletId,
        performedBy: 'Thủ kho xuất',
        device: 'Cổng RFID Gate Outbound',
        timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
        notes: 'Xuất kho hoàn tất',
      ));
    }

    return combinedLogs..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Tạo chuỗi tóm tắt tiến trình vòng đời thẻ RFID (Tag Lifecycle Summary) phục vụ xuất báo cáo và tra cứu
  /// Bao gồm đầy đủ ngày giờ, chi tiết kệ nào, pallet nào, vị trí chuyển đi/đến, thu hồi, sửa chữa...
  /// [multiline]: Nếu true, mỗi mốc sự kiện sẽ xuống một dòng riêng phục vụ xuất file Excel / CSV.
  String getTagLifecycleSummary(String epc, {bool multiline = false}) {
    final logs = getTagLifecycle(epc);
    if (logs.isEmpty) return 'Chưa có lịch sử';

    final cleanEpc = epc.trim().toUpperCase();
    final item = _items.where((it) => it.epc.toUpperCase() == cleanEpc || it.itemId.toUpperCase() == cleanEpc).firstOrNull;

    // Sắp xếp theo trình tự thời gian từ cũ tới mới (chronological)
    final sorted = logs.toList()..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    String resolveLoc(String? locId) {
      if (locId == null || locId.trim().isEmpty) return '';
      final clean = locId.trim();
      final loc = findLocationFast(clean) ??
          _locations.where((l) => l.locationId.toUpperCase() == clean.toUpperCase() ||
                                  l.locationCode.toUpperCase() == clean.toUpperCase() ||
                                  l.displayName.toUpperCase() == clean.toUpperCase()).firstOrNull;
      if (loc == null) return clean;

      final disp = loc.displayName;
      final z = loc.zone.trim();
      if (z.isNotEmpty && z != '0' && z.toUpperCase() != 'GATE' && z.toUpperCase() != 'DEFAULT') {
        final cleanZ = z.replaceAll(RegExp(r'^(KHU|KHO)\s*', caseSensitive: false), '').trim();
        final isLetterZone = cleanZ.length == 1 && RegExp(r'^[A-Za-z]$').hasMatch(cleanZ);
        final hasZoneInName = isLetterZone
            ? disp.toUpperCase().contains(cleanZ.toUpperCase())
            : disp.toUpperCase().contains(z.toUpperCase());
        if (!hasZoneInName) {
          final prefix = z.toUpperCase().startsWith('KHU') || z.toUpperCase().startsWith('KHO') ? z : 'Kho $z';
          return '$disp ($prefix)';
        }
      }
      return disp;
    }

    String resolvePal(String? palId) {
      if (palId == null || palId.trim().isEmpty) return '';
      final clean = palId.trim();
      final pal = _pallets.where((p) => p.palletId == clean || p.palletCode == clean).firstOrNull;
      return pal?.displayName ?? clean;
    }

    final stages = <String>[];
    for (final l in sorted) {
      final dt = l.timestamp;
      final d = dt.day.toString().padLeft(2, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final y = dt.year.toString();
      final h = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      final timePrefix = '[$d/$m/$y $h:$min]';

      // Tra cứu Pallet và Kệ bổ trợ nếu log chưa có sẵn
      final rawPal = (l.toPallet != null && l.toPallet!.isNotEmpty)
          ? l.toPallet
          : ((l.fromPallet != null && l.fromPallet!.isNotEmpty) ? l.fromPallet : item?.palletId);
      final palName = resolvePal(rawPal);

      String rawLoc = (l.toLocation != null && l.toLocation!.isNotEmpty)
          ? l.toLocation!
          : ((l.fromLocation != null && l.fromLocation!.isNotEmpty) ? l.fromLocation! : '');
      if (rawLoc.isEmpty && rawPal != null && rawPal.isNotEmpty) {
        final palObj = _pallets.where((p) => p.palletId == rawPal || p.palletCode == rawPal).firstOrNull;
        if (palObj != null && palObj.locationId != null && palObj.locationId!.isNotEmpty) {
          rawLoc = palObj.locationId!;
        }
      }
      if (rawLoc.isEmpty && item?.locationId != null && item!.locationId!.isNotEmpty) {
        rawLoc = item.locationId!;
      }
      final locName = resolveLoc(rawLoc);

      String desc;
      switch (l.action) {
        case TagLifecycleAction.encoded:
          desc = '$timePrefix Khởi tạo mã';
          break;
        case TagLifecycleAction.inboundGate:
          if (locName.isNotEmpty && palName.isNotEmpty) {
            desc = '$timePrefix Nhập kho (Cổng RFID) [Kệ: $locName | Pallet: $palName]';
          } else if (palName.isNotEmpty) {
            desc = '$timePrefix Nhập kho (Cổng RFID) [Pallet: $palName]';
          } else if (locName.isNotEmpty) {
            desc = '$timePrefix Nhập kho (Cổng RFID) [Kệ: $locName]';
          } else {
            desc = '$timePrefix Nhập kho (Cổng RFID)';
          }
          break;
        case TagLifecycleAction.inboundPda:
          if (locName.isNotEmpty && palName.isNotEmpty) {
            desc = '$timePrefix Nhập kho (PDA) [Kệ: $locName | Pallet: $palName]';
          } else if (palName.isNotEmpty) {
            desc = '$timePrefix Nhập kho (PDA) [Pallet: $palName]';
          } else if (locName.isNotEmpty) {
            desc = '$timePrefix Nhập kho (PDA) [Kệ: $locName]';
          } else {
            desc = '$timePrefix Nhập kho (PDA)';
          }
          break;
        case TagLifecycleAction.palletize:
          final p = resolvePal(l.toPallet).isNotEmpty ? resolvePal(l.toPallet) : palName;
          final lLoc = resolveLoc(l.toLocation).isNotEmpty ? resolveLoc(l.toLocation) : locName;
          if (lLoc.isNotEmpty && p.isNotEmpty) {
            desc = '$timePrefix Xếp Pallet [$p] (Kệ: $lLoc)';
          } else if (p.isNotEmpty) {
            desc = '$timePrefix Xếp Pallet [$p]';
          } else {
            desc = '$timePrefix Xếp Pallet';
          }
          break;
        case TagLifecycleAction.putaway:
          final toLoc = resolveLoc(l.toLocation).isNotEmpty
              ? resolveLoc(l.toLocation)
              : (resolveLoc(item?.locationId).isNotEmpty ? resolveLoc(item?.locationId) : locName);
          final toPal = resolvePal(l.toPallet).isNotEmpty
              ? resolvePal(l.toPallet)
              : (resolvePal(item?.palletId).isNotEmpty ? resolvePal(item?.palletId) : palName);
          if (toLoc.isNotEmpty && toPal.isNotEmpty) {
            desc = '$timePrefix Cất vào Kệ [$toLoc] (Pallet: $toPal)';
          } else if (toLoc.isNotEmpty) {
            desc = '$timePrefix Cất vào Kệ [$toLoc]';
          } else if (toPal.isNotEmpty) {
            desc = '$timePrefix Cất kệ (Pallet: $toPal)';
          } else {
            desc = '$timePrefix Cất kệ';
          }
          break;
        case TagLifecycleAction.transferLocation:
          final fromLoc = resolveLoc(l.fromLocation);
          final toLoc = resolveLoc(l.toLocation);
          final fromP = resolvePal(l.fromPallet);
          final toP = resolvePal(l.toPallet).isNotEmpty ? resolvePal(l.toPallet) : palName;
          String palSuffix = '';
          if (fromP.isNotEmpty && toP.isNotEmpty && fromP != toP) {
            palSuffix = ' (Pallet: $fromP → $toP)';
          } else if (toP.isNotEmpty) {
            palSuffix = ' (Pallet: $toP)';
          } else if (fromP.isNotEmpty) {
            palSuffix = ' (Pallet: $fromP)';
          }
          if (fromLoc.isNotEmpty && toLoc.isNotEmpty) {
            desc = '$timePrefix Chuyển vị trí [$fromLoc → $toLoc]$palSuffix';
          } else if (toLoc.isNotEmpty) {
            desc = '$timePrefix Chuyển vị trí [→ $toLoc]$palSuffix';
          } else {
            desc = '$timePrefix Chuyển vị trí kệ$palSuffix';
          }
          break;
        case TagLifecycleAction.transferPallet:
          final fromP = resolvePal(l.fromPallet);
          final toP = resolvePal(l.toPallet).isNotEmpty ? resolvePal(l.toPallet) : palName;
          final locSuffix = locName.isNotEmpty ? ' (Kệ: $locName)' : '';
          if (fromP.isNotEmpty && toP.isNotEmpty) {
            desc = '$timePrefix Đổi Pallet [$fromP → $toP]$locSuffix';
          } else if (toP.isNotEmpty) {
            desc = '$timePrefix Đổi Pallet [→ $toP]$locSuffix';
          } else {
            desc = '$timePrefix Đổi Pallet$locSuffix';
          }
          break;
        case TagLifecycleAction.mergePallet:
          final fromP = resolvePal(l.fromPallet);
          final toP = resolvePal(l.toPallet).isNotEmpty ? resolvePal(l.toPallet) : palName;
          final locSuffix = locName.isNotEmpty ? ' (Kệ: $locName)' : '';
          if (fromP.isNotEmpty && toP.isNotEmpty) {
            desc = '$timePrefix Gộp Pallet [$fromP → $toP]$locSuffix';
          } else {
            desc = '$timePrefix Gộp Pallet$locSuffix';
          }
          break;
        case TagLifecycleAction.auditMatch:
          if (locName.isNotEmpty && palName.isNotEmpty) {
            desc = '$timePrefix Kiểm kê khớp [Kệ: $locName | Pallet: $palName]';
          } else if (locName.isNotEmpty) {
            desc = '$timePrefix Kiểm kê khớp [Kệ: $locName]';
          } else {
            desc = '$timePrefix Kiểm kê khớp';
          }
          break;
        case TagLifecycleAction.auditMisplaced:
          final aLoc = resolveLoc(l.toLocation).isNotEmpty ? resolveLoc(l.toLocation) : locName;
          final aPal = resolvePal(l.toPallet).isNotEmpty ? resolvePal(l.toPallet) : palName;
          if (aLoc.isNotEmpty && aPal.isNotEmpty) {
            desc = '$timePrefix Kiểm kê sai vị trí [Kệ: $aLoc | Pallet: $aPal]';
          } else if (aLoc.isNotEmpty) {
            desc = '$timePrefix Kiểm kê sai vị trí [$aLoc]';
          } else {
            desc = '$timePrefix Kiểm kê sai vị trí';
          }
          break;
        case TagLifecycleAction.auditMissing:
          if (locName.isNotEmpty && palName.isNotEmpty) {
            desc = '$timePrefix Báo thiếu kiểm kê [Kệ: $locName | Pallet: $palName]';
          } else if (locName.isNotEmpty) {
            desc = '$timePrefix Báo thiếu kiểm kê [Kệ: $locName]';
          } else {
            desc = '$timePrefix Báo thiếu kiểm kê';
          }
          break;
        case TagLifecycleAction.auditFound:
          if (locName.isNotEmpty && palName.isNotEmpty) {
            desc = '$timePrefix Tìm lại kiểm kê [Kệ: $locName | Pallet: $palName]';
          } else if (locName.isNotEmpty) {
            desc = '$timePrefix Tìm lại kiểm kê [Kệ: $locName]';
          } else {
            desc = '$timePrefix Tìm lại kiểm kê';
          }
          break;
        case TagLifecycleAction.locateFound:
          if (locName.isNotEmpty && palName.isNotEmpty) {
            desc = '$timePrefix Radar tìm thấy [Kệ: $locName | Pallet: $palName]';
          } else if (locName.isNotEmpty) {
            desc = '$timePrefix Radar tìm thấy [Kệ: $locName]';
          } else {
            desc = '$timePrefix Radar tìm thấy';
          }
          break;
        case TagLifecycleAction.allocatePo:
          final locPalSuffix = (locName.isNotEmpty && palName.isNotEmpty)
              ? ' (Kệ: $locName | Pallet: $palName)'
              : (locName.isNotEmpty ? ' (Kệ: $locName)' : '');
          desc = (l.documentNo != null && l.documentNo!.trim().isNotEmpty)
              ? '$timePrefix Giữ chỗ xuất [${l.documentNo}]$locPalSuffix'
              : '$timePrefix Giữ chỗ xuất$locPalSuffix';
          break;
        case TagLifecycleAction.picked:
          final fromLoc = resolveLoc(l.fromLocation).isNotEmpty ? resolveLoc(l.fromLocation) : locName;
          final fromP = resolvePal(l.fromPallet).isNotEmpty ? resolvePal(l.fromPallet) : palName;
          if (fromLoc.isNotEmpty && fromP.isNotEmpty) {
            desc = '$timePrefix Đã lấy hàng [Từ Kệ: $fromLoc | Pallet: $fromP]';
          } else if (fromLoc.isNotEmpty) {
            desc = '$timePrefix Đã lấy hàng [Từ Kệ: $fromLoc]';
          } else {
            desc = '$timePrefix Đã lấy hàng';
          }
          break;
        case TagLifecycleAction.recall:
          final noteSuffix = (l.notes != null && l.notes!.trim().isNotEmpty && l.notes != 'Thu hồi sản phẩm')
              ? ' [${l.notes}]'
              : '';
          final placeSuffix = (locName.isNotEmpty && palName.isNotEmpty)
              ? ' (Kệ: $locName | Pallet: $palName)'
              : (locName.isNotEmpty ? ' (Kệ: $locName)' : (palName.isNotEmpty ? ' (Pallet: $palName)' : ''));
          desc = '$timePrefix Thu hồi sản phẩm$noteSuffix$placeSuffix';
          break;
        case TagLifecycleAction.repair:
          final noteSuffix = (l.notes != null && l.notes!.trim().isNotEmpty && l.notes != 'Gửi sửa chữa / bảo hành')
              ? ' [${l.notes}]'
              : '';
          final placeSuffix = (locName.isNotEmpty && palName.isNotEmpty)
              ? ' (Kệ: $locName | Pallet: $palName)'
              : (locName.isNotEmpty ? ' (Kệ: $locName)' : (palName.isNotEmpty ? ' (Pallet: $palName)' : ''));
          desc = '$timePrefix Gửi sửa chữa / Bảo hành$noteSuffix$placeSuffix';
          break;
        case TagLifecycleAction.repairDone:
          final toLoc = resolveLoc(l.toLocation).isNotEmpty ? resolveLoc(l.toLocation) : locName;
          final toPal = resolvePal(l.toPallet).isNotEmpty ? resolvePal(l.toPallet) : palName;
          if (toLoc.isNotEmpty && toPal.isNotEmpty) {
            desc = '$timePrefix Hoàn trả kho sau sửa chữa [Kệ: $toLoc | Pallet: $toPal]';
          } else if (toLoc.isNotEmpty) {
            desc = '$timePrefix Hoàn trả kho sau sửa chữa [$toLoc]';
          } else {
            desc = '$timePrefix Hoàn trả kho sau sửa chữa';
          }
          break;
        case TagLifecycleAction.outboundGate:
          final outLoc = resolveLoc(l.fromLocation).isNotEmpty ? resolveLoc(l.fromLocation) : locName;
          final outPal = resolvePal(l.fromPallet).isNotEmpty ? resolvePal(l.fromPallet) : palName;
          final placeSuffix = (outLoc.isNotEmpty && outPal.isNotEmpty)
              ? ' [Từ Kệ: $outLoc | Pallet: $outPal]'
              : (outLoc.isNotEmpty ? ' [Từ Kệ: $outLoc]' : (outPal.isNotEmpty ? ' [Pallet: $outPal]' : ''));
          desc = '$timePrefix Xuất kho (Cổng RFID)$placeSuffix';
          break;
        case TagLifecycleAction.outboundPda:
          final outLoc = resolveLoc(l.fromLocation).isNotEmpty ? resolveLoc(l.fromLocation) : locName;
          final outPal = resolvePal(l.fromPallet).isNotEmpty ? resolvePal(l.fromPallet) : palName;
          final placeSuffix = (outLoc.isNotEmpty && outPal.isNotEmpty)
              ? ' [Từ Kệ: $outLoc | Pallet: $outPal]'
              : (outLoc.isNotEmpty ? ' [Từ Kệ: $outLoc]' : (outPal.isNotEmpty ? ' [Pallet: $outPal]' : ''));
          desc = '$timePrefix Xuất kho (PDA)$placeSuffix';
          break;
        case TagLifecycleAction.unauthorizedExit:
          desc = '$timePrefix Cảnh báo ra trái phép';
          break;
        case TagLifecycleAction.statusChange:
          desc = l.newStatus.trim().isNotEmpty ? '$timePrefix Đổi trạng thái [${l.newStatus}]' : '$timePrefix Đổi trạng thái';
          break;
      }

      // Tránh lặp lại giai đoạn giống hệt nhau liên tiếp
      if (stages.isNotEmpty && stages.last == desc) {
        continue;
      }
      stages.add(desc);
    }

    if (stages.isEmpty) return 'Chưa có lịch sử';
    if (!multiline) {
      return stages.join(' → ');
    }
    // Chế độ xuống dòng tự động cho xuất file Excel / CSV:
    final buffer = StringBuffer();
    for (int i = 0; i < stages.length; i++) {
      if (i == 0) {
        buffer.write(stages[i]);
      } else {
        buffer.write('\r\n→ ${stages[i]}');
      }
    }
    return buffer.toString();
  }

  /// Ghi nhận biến động: Thu hồi sản phẩm (Recall)
  Future<bool> recordItemRecall({
    required String epc,
    required String reason,
    required String performedBy,
  }) async {
    final cleanEpc = epc.trim().toUpperCase();
    final item = _items.where((it) => it.epc.toUpperCase() == cleanEpc).firstOrNull;
    if (item == null) return false;

    item.status = ItemStatus.recalled;
    await _dbService.updateItemStatus(item.epc, ItemStatus.recalled);
    await _syncDirectOrQueue(
      tableName: 'items',
      recordId: item.itemId,
      action: 'UPDATE',
      payload: {
        'status': ItemStatus.recalled.code,
      },
    );

    await recordTagLifecycle(
      epc: item.epc,
      itemId: item.itemId,
      sku: item.sku,
      productName: item.productName,
      serialNumber: item.serialNumber,
      action: TagLifecycleAction.recall,
      previousStatus: ItemStatus.inStock.label,
      newStatus: ItemStatus.recalled.label,
      fromLocation: item.locationId,
      fromPallet: item.palletId,
      performedBy: performedBy,
      notes: reason.isNotEmpty ? reason : 'Thu hồi sản phẩm',
    );
    notifyListeners();
    return true;
  }

  /// Ghi nhận biến động: Gửi đi sửa chữa / bảo hành (Repair)
  Future<bool> recordItemRepair({
    required String epc,
    required String reason,
    required String performedBy,
  }) async {
    final cleanEpc = epc.trim().toUpperCase();
    final item = _items.where((it) => it.epc.toUpperCase() == cleanEpc).firstOrNull;
    if (item == null) return false;

    item.status = ItemStatus.underRepair;
    await _dbService.updateItemStatus(item.epc, ItemStatus.underRepair);
    await _syncDirectOrQueue(
      tableName: 'items',
      recordId: item.itemId,
      action: 'UPDATE',
      payload: {
        'status': ItemStatus.underRepair.code,
      },
    );

    await recordTagLifecycle(
      epc: item.epc,
      itemId: item.itemId,
      sku: item.sku,
      productName: item.productName,
      serialNumber: item.serialNumber,
      action: TagLifecycleAction.repair,
      previousStatus: ItemStatus.inStock.label,
      newStatus: ItemStatus.underRepair.label,
      fromLocation: item.locationId,
      fromPallet: item.palletId,
      performedBy: performedBy,
      notes: reason.isNotEmpty ? reason : 'Gửi sửa chữa / bảo hành',
    );
    notifyListeners();
    return true;
  }

  /// Ghi nhận biến động: Hoàn trả lại kho sau khi sửa chữa xong (Repair Done)
  Future<bool> recordItemRepairReturn({
    required String epc,
    required String toLocationId,
    String? toPalletId,
    required String performedBy,
  }) async {
    final cleanEpc = epc.trim().toUpperCase();
    final item = _items.where((it) => it.epc.toUpperCase() == cleanEpc).firstOrNull;
    if (item == null) return false;

    item.status = ItemStatus.inStock;
    item.locationId = toLocationId;
    item.palletId = toPalletId;
    await _dbService.updateItemLocationAndPallet(item.epc, toLocationId, toPalletId ?? '');
    await _dbService.updateItemStatus(item.epc, ItemStatus.inStock);
    await _syncDirectOrQueue(
      tableName: 'items',
      recordId: item.itemId,
      action: 'UPDATE',
      payload: {
        'location_id': toLocationId,
        'pallet_id': toPalletId,
        'status': ItemStatus.inStock.code,
      },
    );

    final loc = _locations.where((l) => l.locationId == toLocationId || l.locationCode == toLocationId).firstOrNull;
    await recordTagLifecycle(
      epc: item.epc,
      itemId: item.itemId,
      sku: item.sku,
      productName: item.productName,
      serialNumber: item.serialNumber,
      action: TagLifecycleAction.repairDone,
      previousStatus: ItemStatus.underRepair.label,
      newStatus: ItemStatus.inStock.label,
      toLocation: loc?.displayName ?? toLocationId,
      toPallet: toPalletId,
      performedBy: performedBy,
      notes: 'Hoàn tất sửa chữa, nhập lại vào vị trí ${loc?.displayName ?? toLocationId}',
    );
    notifyListeners();
    return true;
  }

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
    await _syncDirectOrQueue(
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
        'is_completed': session.isCompleted,
        'target_skus': session.targetSkus.join(','),
        'assigned_to_user_id': session.assignedToUserId,
        'assigned_to_name': session.assignedToName,
        'created_by': session.assignedBy,
        'notes': session.notes,
      },
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      unawaited(() async {
        try {
          final supa = Supabase.instance.client;
          final detailRows = session.results.map((r) => {
            'session_id': session.sessionId,
            'epc': r.epc,
            'sku': r.sku,
            'product_name': r.productName,
            'expected_location': r.expectedLocation,
            'actual_location': r.actualLocation,
            'result_type': r.resultType.code,
            'read_at': r.readAt.toIso8601String(),
          }).toList();
          await supa.from('inventory_session_details').delete().eq('session_id', session.sessionId);
          if (detailRows.isNotEmpty) {
            await supa.from('inventory_session_details').insert(detailRows);
          }
        } catch (e) {
          debugPrint('saveInventorySession Supabase details error: $e');
        }
      }());
    }
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> deleteInventorySession(String sessionId) async {
    final cleanId = sessionId.trim();
    await _dbService.deleteInventorySession(cleanId);
    _inventorySessions.removeWhere((s) => s.sessionId == cleanId || s.sessionCode == cleanId);

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final supa = Supabase.instance.client;
        await supa.from('inventory_session_details').delete().eq('session_id', cleanId);
        await supa.from('inventory_sessions').delete().eq('session_id', cleanId);
      } catch (e) {
        debugPrint('deleteInventorySession Supabase direct error: $e');
      }
    }

    await _syncDirectOrQueue(
      tableName: 'inventory_sessions',
      recordId: cleanId,
      action: 'DELETE',
      payload: {'sessionId': cleanId},
    );
    notifyListeners();
  }

  // ==========================================
  // LOCATE ORDERS (ĐƠN TÌM KIẾM THẺ / HÀNG HÓA)
  // ==========================================
  Future<LocateOrder> createLocateOrder({
    required String title,
    String? targetEpc,
    String? targetSku,
    String? targetProductName,
    String? targetPalletCode,
    String? expectedLocation,
    required String assignedToUserId,
    required String assignedToName,
    String? createdBy,
    String? notes,
  }) async {
    final now = DateTime.now();
    final dStr = '${now.year.toString().substring(2)}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final randCode = (Random().nextInt(900) + 100).toString();
    final order = LocateOrder(
      orderId: 'LOC-TASK-${now.millisecondsSinceEpoch}',
      orderNo: 'TK-$dStr-$randCode',
      title: title,
      targetEpc: targetEpc,
      targetSku: targetSku,
      targetProductName: targetProductName,
      targetPalletCode: targetPalletCode,
      expectedLocation: expectedLocation,
      status: LocateOrderStatus.pending,
      assignedToUserId: assignedToUserId,
      assignedToName: assignedToName,
      createdBy: createdBy ?? (AuthService().currentUser?.fullName ?? 'Thủ kho'),
      createdAt: now,
      notes: notes,
    );

    _locateOrders.insert(0, order);
    await _dbService.insertLocateOrder(order);
    await _syncDirectOrQueue(
      tableName: 'locate_orders',
      recordId: order.orderId,
      action: 'INSERT',
      payload: order.toMap(),
    );
    _triggerBackgroundSync();
    notifyListeners();
    return order;
  }

  Future<void> updateLocateOrderStatus(String orderId, LocateOrderStatus newStatus) async {
    final order = _locateOrders.where((o) => o.orderId == orderId || o.orderNo == orderId).firstOrNull;
    if (order == null) return;
    order.status = newStatus;
    await _dbService.insertLocateOrder(order);
    await _syncDirectOrQueue(
      tableName: 'locate_orders',
      recordId: order.orderId,
      action: 'UPDATE',
      payload: order.toMap(),
    );
    notifyListeners();
  }

  Future<void> completeLocateOrder(
    String orderId, {
    required String foundLocation,
    String? completedBy,
    String? notes,
  }) async {
    final order = _locateOrders.where((o) => o.orderId == orderId || o.orderNo == orderId).firstOrNull;
    if (order == null) return;
    order.status = LocateOrderStatus.completed;
    order.foundLocation = foundLocation;
    order.completedAt = DateTime.now();
    order.completedBy = completedBy ?? (AuthService().currentUser?.fullName ?? order.assignedToName);
    if (notes != null && notes.trim().isNotEmpty) {
      order.notes = (order.notes != null && order.notes!.isNotEmpty)
          ? '${order.notes}\n[Hoàn thành]: $notes'
          : notes;
    }
    await _dbService.insertLocateOrder(order);
    await _syncDirectOrQueue(
      tableName: 'locate_orders',
      recordId: order.orderId,
      action: 'UPDATE',
      payload: order.toMap(),
    );

    if (order.targetEpc != null && order.targetEpc!.isNotEmpty) {
      await recordTagLifecycle(
        epc: order.targetEpc!,
        sku: order.targetSku,
        productName: order.targetProductName,
        action: TagLifecycleAction.locateFound,
        previousStatus: ItemStatus.inStock.label,
        newStatus: ItemStatus.inStock.label,
        fromLocation: order.expectedLocation,
        toLocation: foundLocation,
        documentNo: order.orderNo,
        performedBy: order.completedBy ?? 'Nhân viên PDA',
        device: 'SEUIC UTouch 2 Radar AirTag',
        notes: 'Đã tìm thấy bằng Radar AirTag tại vị trí $foundLocation${notes != null ? " ($notes)" : ""}',
      );
    }

    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> cancelLocateOrder(String orderId) async {
    await updateLocateOrderStatus(orderId, LocateOrderStatus.cancelled);
  }

  Future<void> deleteLocateOrder(String orderId) async {
    final cleanId = orderId.trim();
    await _dbService.deleteLocateOrder(cleanId);
    _locateOrders.removeWhere((o) => o.orderId == cleanId || o.orderNo == cleanId);
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final supa = Supabase.instance.client;
        await supa.from('locate_orders').delete().eq('order_id', cleanId);
      } catch (e) {
        debugPrint('deleteLocateOrder Supabase direct error: $e');
      }
    }
    await _syncDirectOrQueue(
      tableName: 'locate_orders',
      recordId: cleanId,
      action: 'DELETE',
      payload: {'order_id': cleanId},
    );
    notifyListeners();
  }

  Future<void> deleteTransaction(String transactionId) async {
    final cleanId = transactionId.trim();
    final target = _transactions.where((t) => t.transactionId == cleanId || t.documentNo == cleanId).firstOrNull;
    final txId = target?.transactionId ?? cleanId;
    final docNo = target?.documentNo ?? cleanId;

    _transactions.removeWhere((t) => t.transactionId == txId || (docNo.isNotEmpty && t.documentNo == docNo));
    await _dbService.deleteTransaction(txId);

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final supa = Supabase.instance.client;
        await supa.from('inventory_transactions').delete().eq('transaction_id', txId);
        if (docNo.isNotEmpty && docNo != txId) {
          await supa.from('inventory_transactions').delete().eq('document_no', docNo);
        }
      } catch (e) {
        debugPrint('deleteTransaction Supabase direct error: $e');
      }
    }

    await _syncDirectOrQueue(
      tableName: 'inventory_transactions',
      recordId: txId,
      action: 'DELETE',
      payload: {'transaction_id': txId},
    );

    notifyListeners();
  }

  Future<void> addUser(WmsUser user, {String? passwordHash}) async {
    if (passwordHash != null && passwordHash.isNotEmpty) {
      await _dbService.insertUserWithPassword(user, passwordHash);
    } else {
      await _dbService.insertUser(user);
    }
    _users.removeWhere((u) => u.userId == user.userId);
    _users.add(user);

    final payload = user.toMap();
    final hashToSync = passwordHash ?? (await _dbService.getUserAuth(user.username))?['password_hash'];
    if (hashToSync != null) {
      payload['password_hash'] = hashToSync;
    }

    await _syncDirectOrQueue(
      tableName: 'users',
      recordId: user.userId,
      action: 'INSERT',
      payload: payload,
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> updateUser(WmsUser user, {String? passwordHash}) async {
    await _dbService.updateUser(user);
    final idx = _users.indexWhere((u) => u.userId == user.userId || u.username == user.username);
    if (idx >= 0) {
      _users[idx] = user;
    } else {
      _users.add(user);
    }

    final payload = user.toMap();
    final hashToSync = passwordHash ?? (await _dbService.getUserAuth(user.username))?['password_hash'];
    if (hashToSync != null) {
      payload['password_hash'] = hashToSync;
    }

    await _syncDirectOrQueue(
      tableName: 'users',
      recordId: user.userId,
      action: 'UPDATE',
      payload: payload,
    );
    _triggerBackgroundSync();
    notifyListeners();
  }

  Future<void> syncUserPassword(String userId, String passwordHash) async {
    await _dbService.updateUserPassword(userId, passwordHash);
    await _syncDirectOrQueue(
      tableName: 'users',
      recordId: userId,
      action: 'UPDATE',
      payload: {
        'user_id': userId,
        'password_hash': passwordHash,
      },
    );
    _triggerBackgroundSync();
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
    String? placedBy,
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
          placedBy: placedBy ?? 'Thủ kho (Admin)',
        );
        _pallets.add(newP);
        return newP;
      },
    );

    pallet.locationId = locationId;
    if (placedBy != null && placedBy.isNotEmpty) {
      pallet.placedBy = placedBy;
    }
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
    _ensureIndexes();
    final indexed = _palletsByRfidIndex[clean] ?? _palletsByCodeIndex[clean] ?? _palletsByHexIndex[clean];
    if (indexed != null) return indexed;
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

  /// Tra cứu nhanh Item theo mã thẻ RFID (EPC) - O(1)
  Item? findItemByEpc(String epc) {
    final clean = epc.trim().toUpperCase();
    _ensureIndexes();
    return clean.isEmpty ? null : _itemsByEpcIndex[clean];
  }

  /// Lấy thông tin người đặt Pallet lên kệ
  String getPalletPlacedBy(Pallet p) {
    if (p.placedBy != null && p.placedBy!.trim().isNotEmpty) {
      return p.placedBy!;
    }
    // Tra cứu trong nhật ký giao dịch biến động kho của pallet này
    final tx = _transactions.where((t) =>
      (t.palletCode != null && t.palletCode!.toUpperCase() == p.palletCode.toUpperCase()) ||
      (t.documentNo.toUpperCase() == p.palletCode.toUpperCase())
    ).firstOrNull;
    if (tx != null && tx.performedBy.trim().isNotEmpty) {
      return tx.performedBy;
    }
    // Tra cứu từ đơn nhập kho của các mặt hàng trong pallet
    for (final itId in p.itemIds) {
      final item = _items.where((i) => i.itemId == itId).firstOrNull;
      if (item?.orderNo != null) {
        final ord = _inboundOrders.where((o) => o.orderNo == item!.orderNo).firstOrNull;
        if (ord != null && ord.sourceSupplier.trim().isNotEmpty) {
          return 'Nhập từ: ${ord.sourceSupplier}';
        }
      }
    }
    return 'Thủ kho (Admin)';
  }

  /// Lấy thời gian đặt Pallet lên kệ
  DateTime getPalletPlacedTime(Pallet p) {
    if (p.inboundTime != null) {
      return p.inboundTime!;
    }
    final tx = _transactions.where((t) =>
      (t.palletCode != null && t.palletCode!.toUpperCase() == p.palletCode.toUpperCase()) ||
      (t.documentNo.toUpperCase() == p.palletCode.toUpperCase())
    ).firstOrNull;
    if (tx != null) {
      return tx.timestamp;
    }
    return DateTime.now();
  }

  /// Lấy tên sản phẩm chuẩn theo mã SKU (Ưu tiên danh mục sản phẩm chính thức -> Làm sạch số thứ tự cá thể ở đuôi)
  String getSkuProductName(String sku, [String? fallbackName]) {
    final cleanSku = sku.trim();
    if (cleanSku.isNotEmpty) {
      _ensureIndexes();
      final prod = _products.where((p) => p.sku.trim().toLowerCase() == cleanSku.toLowerCase()).firstOrNull;
      if (prod != null && prod.productName.trim().isNotEmpty) {
        final catalogName = prod.productName.trim();
        // Nếu tên danh mục không bị gắn số thứ tự cá thể ở đuôi (ví dụ "Chứng từ 14"), trả về ngay
        if (!RegExp(r'\s+[-#]?\s*\d+$').hasMatch(catalogName)) {
          return catalogName;
        }
      }
    }

    // Nếu có fallbackName (ví dụ lấy từ item đầu tiên như "Chứng từ 14")
    final raw = (fallbackName != null && fallbackName.trim().isNotEmpty)
        ? fallbackName.trim()
        : cleanSku;

    // Loại bỏ hậu tố số thứ tự cá thể của chip (ví dụ "Chứng từ 14" -> "Chứng từ", "Hồ sơ #01" -> "Hồ sơ")
    final cleaned = raw.replaceFirst(RegExp(r'(\s+[-#]?\s*\d+)$'), '').trim();
    return cleaned.isNotEmpty ? cleaned : raw;
  }

  /// Lấy thông tin Nhà cung cấp của một Item (Ưu tiên thuộc tính trên Item -> Tra cứu Đơn PO)
  String getItemSupplier(Item item) {
    if (item.supplier != null && item.supplier!.trim().isNotEmpty && item.supplier!.trim() != 'Chưa khai báo') {
      return item.supplier!.trim();
    }
    if (item.orderNo != null && item.orderNo!.trim().isNotEmpty) {
      _ensureIndexes();
      final ord = _inboundOrdersByNoIndex[item.orderNo!.trim().toUpperCase()] ??
          _inboundOrders.where((o) => o.orderNo == item.orderNo || o.inboundOrderId == item.orderNo).firstOrNull;
      if (ord != null && ord.sourceSupplier.trim().isNotEmpty && ord.sourceSupplier.trim() != 'Chưa khai báo') {
        return ord.sourceSupplier.trim();
      }
    }
    return (item.supplier != null && item.supplier!.trim().isNotEmpty) ? item.supplier!.trim() : 'Nhà cung cấp tổng hợp';
  }

  /// Lấy mã thùng hàng của Item
  String getItemCartonCode(Item item) {
    if (item.cartonCode != null && item.cartonCode!.trim().isNotEmpty) {
      return item.cartonCode!.trim();
    }
    if (item.palletId != null && item.palletId!.trim().isNotEmpty) {
      return item.palletId!.trim();
    }
    return 'Chưa đóng thùng';
  }

  /// Lấy người nhập kho của Item
  String getItemInboundBy(Item item) {
    if (item.inboundBy != null && item.inboundBy!.trim().isNotEmpty && item.inboundBy != 'Cổng RFID Gate') {
      return resolveUserFullName(item.inboundBy, defaultRole: 'thukho');
    }
    if (item.orderNo != null && item.orderNo!.trim().isNotEmpty) {
      final tx = _transactions.where((t) =>
        t.documentNo.trim().toUpperCase() == item.orderNo!.trim().toUpperCase() &&
        (t.type == TransactionType.inbound || t.transactionId.contains('INBOUND') || t.transactionId.contains('GATE'))
      ).firstOrNull;
      if (tx != null && tx.performedBy.trim().isNotEmpty && tx.performedBy != 'Cổng RFID Gate') {
        return resolveUserFullName(tx.performedBy, defaultRole: 'thukho');
      }
    }
    // Ưu tiên hiển thị tên người dùng / thủ kho đang đăng nhập trong phiên hiện tại
    final activeUser = AuthService().currentUser?.fullName;
    if (activeUser != null && activeUser.trim().isNotEmpty) {
      return activeUser.trim();
    }
    return resolveUserFullName(null, defaultRole: 'thukho');
  }

  /// Tra cứu chính xác họ và tên người dùng từ CSDL (bảng users) thay vì hiển thị role/mã kỹ thuật
  String resolveUserFullName(String? rawIdentifier, {String defaultRole = 'handheld'}) {
    const legacyMockIds = {'USER-PDA-001', 'USER-OP-001', 'USER-SEL-001', 'USER-TECH-001'};

    if (rawIdentifier != null && rawIdentifier.trim().isNotEmpty) {
      final trimmed = rawIdentifier.trim();

      // 1. Khớp chính xác fullName của user trong CSDL
      final byFullName = _users.where((u) => u.fullName.trim().toLowerCase() == trimmed.toLowerCase()).firstOrNull;
      if (byFullName != null) return byFullName.fullName.trim();

      // 2. Khớp theo userId
      final byId = _users.where((u) => u.userId.trim().toLowerCase() == trimmed.toLowerCase()).firstOrNull;
      if (byId != null && byId.fullName.trim().isNotEmpty) return byId.fullName.trim();

      // 3. Khớp theo username (ví dụ: 'pda123', 'thukho1', 'admin', 'kythuat1')
      final byUsername = _users.where((u) => u.username.trim().toLowerCase() == trimmed.toLowerCase()).firstOrNull;
      if (byUsername != null && byUsername.fullName.trim().isNotEmpty) return byUsername.fullName.trim();

      // 4. Kiểm tra các từ khóa role cũ để chuyển đổi sang tên thật trong CSDL
      final lower = trimmed.toLowerCase();
      if (lower.contains('pda') || lower.contains('handheld') || lower.contains('cầm tay')) {
        final realPda = _users.where((u) => u.isActive && !legacyMockIds.contains(u.userId) && (u.username == 'pda123' || u.role == 'handheld')).firstOrNull
            ?? _users.where((u) => u.isActive && (u.username == 'pda123' || u.role == 'handheld')).firstOrNull;
        if (realPda != null && realPda.fullName.trim().isNotEmpty) return realPda.fullName.trim();
      }

      if (lower.contains('thukho') || lower.contains('thủ kho')) {
        final realTk = _users.where((u) => u.isActive && !legacyMockIds.contains(u.userId) && (u.username == 'thukho1' || u.role == 'thukho')).firstOrNull
            ?? _users.where((u) => u.isActive && (u.username == 'thukho1' || u.role == 'thukho')).firstOrNull;
        if (realTk != null && realTk.fullName.trim().isNotEmpty) return realTk.fullName.trim();
      }

      if (lower.contains('admin') || lower.contains('quản trị')) {
        final adm = _users.where((u) => u.isActive && u.role == 'admin').firstOrNull;
        if (adm != null && adm.fullName.trim().isNotEmpty) return adm.fullName.trim();
      }

      // Nếu là tên bình thường (không phải role string kỹ thuật), giữ nguyên tên đó
      if (!lower.contains('thủ kho pda') && !lower.contains('thủ kho desktop') && !lower.contains('cổng rfid')) {
        return trimmed;
      }
    }

    // Nếu không có identifier hoặc là role string kỹ thuật:
    // Lấy user tương ứng trong CSDL (ưu tiên role handheld hoặc username pda123)
    final target = _users.where((u) => u.isActive && !legacyMockIds.contains(u.userId) && (u.username == 'pda123' || u.role == defaultRole)).firstOrNull
        ?? _users.where((u) => u.isActive && (u.username == 'pda123' || u.role == defaultRole)).firstOrNull
        ?? _users.where((u) => u.isActive && !legacyMockIds.contains(u.userId)).firstOrNull;

    if (target != null && target.fullName.trim().isNotEmpty) {
      return target.fullName.trim();
    }

    return 'Chưa cất kệ';
  }

  /// Lấy người cất kệ của Item chính xác theo tên trong CSDL (không lấy theo role)
  String getItemPutawayBy(Item item) {
    if (item.status != ItemStatus.inStock && (item.locationId == null || item.locationId!.trim().isEmpty)) {
      return 'Chưa cất kệ';
    }

    // 1. Kiểm tra trực tiếp trên Item
    if (item.putawayBy != null && item.putawayBy!.trim().isNotEmpty) {
      return resolveUserFullName(item.putawayBy);
    }

    // 2. Kiểm tra trên Pallet chứa Item
    if (item.palletId != null && item.palletId!.trim().isNotEmpty) {
      final pal = _pallets.where((p) =>
        p.palletId.toUpperCase() == item.palletId!.toUpperCase() ||
        p.palletCode.toUpperCase() == item.palletId!.toUpperCase()
      ).firstOrNull;
      if (pal != null && pal.placedBy != null && pal.placedBy!.trim().isNotEmpty) {
        return resolveUserFullName(pal.placedBy);
      }
    }

    // 3. Kiểm tra trong Transaction di chuyển / cất kệ
    final tx = _transactions.where((t) =>
      t.sku == item.sku &&
      (t.type == TransactionType.movement || t.transactionId.contains('PUTAWAY'))
    ).firstOrNull;
    if (tx != null && tx.performedBy.trim().isNotEmpty) {
      return resolveUserFullName(tx.performedBy);
    }

    // 4. Nếu hàng đã inStock (đã cất kệ): Lấy chính xác tên người cất kệ (handheld) trong CSDL
    return resolveUserFullName(null, defaultRole: 'handheld');
  }

  /// Lấy thời gian nhập kho của Item
  DateTime getItemInboundTime(Item item) {
    if (item.inboundTime != null) return item.inboundTime!;
    if (item.orderNo != null && item.orderNo!.trim().isNotEmpty) {
      final ord = _inboundOrders.where((o) =>
        o.orderNo.trim().toUpperCase() == item.orderNo!.trim().toUpperCase()
      ).firstOrNull;
      if (ord != null) return ord.createdAt;
    }
    return DateTime.now();
  }

  /// Tra cứu bất đồng bộ có đối soát trực tiếp với DatabaseService để chống mất pallet
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
    String? palletName,
    required String rfidEpc,
    String? locationId,
    String? oldPalletCode,
    String? oldPalletId,
  }) async {
    final cleanCode = palletCode.trim().toUpperCase();
    final cleanName = palletName?.trim();
    final cleanEpc = rfidEpc.trim().toUpperCase();
    final cleanOldCode = oldPalletCode?.trim().toUpperCase();
    final cleanOldId = oldPalletId?.trim().toUpperCase();

    // 1. Nếu sửa đổi mã Barcode/ID từ Pallet cũ sang mã mới
    final isCodeChanged = (cleanOldCode != null && cleanOldCode.isNotEmpty && cleanOldCode != cleanCode) ||
                          (cleanOldId != null && cleanOldId.isNotEmpty && cleanOldId != cleanCode && cleanOldId != 'PAL-$cleanCode');

    if (isCodeChanged) {
      if (cleanOldId != null && cleanOldId.isNotEmpty) {
        await _dbService.deletePallet(cleanOldId);
      }
      if (cleanOldCode != null && cleanOldCode.isNotEmpty) {
        await _dbService.deletePallet(cleanOldCode);
      }
      _pallets.removeWhere((p) =>
          (cleanOldId != null && cleanOldId.isNotEmpty && p.palletId.toUpperCase() == cleanOldId) ||
          (cleanOldCode != null && cleanOldCode.isNotEmpty && p.palletCode.toUpperCase() == cleanOldCode));

      // Xóa pallet cũ khỏi Supabase Cloud để không bị thành bản ghi rác
      final oldSyncId = (cleanOldId != null && cleanOldId.isNotEmpty) ? cleanOldId : (cleanOldCode != null ? 'PAL-$cleanOldCode' : '');
      if (oldSyncId.isNotEmpty) {
        await _syncDirectOrQueue(
          tableName: 'pallets',
          recordId: oldSyncId,
          action: 'DELETE',
          payload: {
            'pallet_id': oldSyncId,
            'pallet_code': cleanOldCode ?? '',
          },
        );
      }

      // Chuyển quyền sở hữu các Item sang mã Pallet mới
      for (final item in _items.where((it) =>
          (cleanOldId != null && it.palletId == cleanOldId) ||
          (cleanOldCode != null && (it.palletId == cleanOldCode || it.palletId == 'PAL-$cleanOldCode')))) {
        item.palletId = 'PAL-$cleanCode';
        await _dbService.insertItem(item);
      }
    }

    // 2. Tìm pallet đang sửa hoặc tìm theo mã
    Pallet? existing;
    if (cleanOldId != null && cleanOldId.isNotEmpty) {
      existing = _pallets.where((p) => p.palletId.toUpperCase() == cleanOldId).firstOrNull;
    }
    existing ??= _pallets.where((p) =>
        p.palletCode.toUpperCase() == cleanCode ||
        p.palletId.toUpperCase() == cleanCode ||
        p.palletId.toUpperCase() == 'PAL-$cleanCode').firstOrNull;

    if (existing != null) {
      existing.palletCode = cleanCode;
      existing.palletName = cleanName?.isNotEmpty == true ? cleanName : null;
      existing.rfidEpc = cleanEpc;
      if (locationId != null) existing.locationId = locationId;
      await _dbService.insertPallet(existing);
    } else {
      final newP = Pallet(
        palletId: 'PAL-$cleanCode',
        palletCode: cleanCode,
        palletName: cleanName?.isNotEmpty == true ? cleanName : null,
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
    final payload = <String, dynamic>{
      'pallet_id': palToSync.palletId,
      'pallet_code': palToSync.palletCode,
      'rfid_epc': palToSync.rfidEpc,
      'location_id': palToSync.locationId,
      'inbound_time': palToSync.inboundTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
      'is_multi_sku': palToSync.isMultiSku ? 1 : 0,
    };
    if (palToSync.palletName != null && palToSync.palletName!.isNotEmpty) {
      payload['pallet_name'] = palToSync.palletName;
    }
    await _syncDirectOrQueue(
      tableName: 'pallets',
      recordId: palToSync.palletId,
      action: 'INSERT',
      payload: payload,
    );

    notifyListeners();
  }

  /// Xóa xe Pallet khỏi danh mục (xóa triệt để đúng 1 Pallet chỉ định cả trong DatabaseService, File Backup và Cloud)
  Future<void> deletePalletFromMaster(String palletCode, {String? palletId}) async {
    final clean = palletCode.trim().toUpperCase();
    final cleanId = palletId?.trim().toUpperCase();

    // 1. Xác định đúng duy nhất Pallet cần xóa, tránh xóa nhầm sang pallet khác
    Pallet? targetPallet;
    if (cleanId != null && cleanId.isNotEmpty) {
      targetPallet = _pallets.where((p) => p.palletId.toUpperCase() == cleanId).firstOrNull;
    }
    targetPallet ??= _pallets.where((p) =>
        (clean.isNotEmpty && p.palletCode.toUpperCase() == clean) ||
        (clean.isNotEmpty && p.palletId.toUpperCase() == clean) ||
        (clean.isNotEmpty && p.palletId.toUpperCase() == 'PAL-$clean')).firstOrNull;

    if (targetPallet != null) {
      final actualId = targetPallet.palletId;
      final actualCode = targetPallet.palletCode;

      // Xóa chính xác 1 pallet này khỏi danh sách RAM
      _pallets.remove(targetPallet);

      // Xóa khỏi DatabaseService theo ID và Code
      await _dbService.deletePallet(actualId);
      if (actualCode.isNotEmpty && actualCode != actualId) {
        await _dbService.deletePallet(actualCode);
      }

      // Cập nhật lại file backup vĩnh viễn
      await _dbService.savePalletsBackup(_pallets);

      // Đồng bộ lệnh xóa lên Supabase Cloud cho cả ID và Code
      await _syncDirectOrQueue(
        tableName: 'pallets',
        recordId: actualId,
        action: 'DELETE',
        payload: {
          'pallet_id': actualId,
          'pallet_code': actualCode,
          'alt_id': 'PAL-$actualCode',
        },
      );
    } else {
      // Fallback nếu không tìm thấy targetPallet
      _pallets.removeWhere((p) =>
          (cleanId != null && cleanId.isNotEmpty && p.palletId.toUpperCase() == cleanId) ||
          (clean.isNotEmpty && p.palletCode.toUpperCase() == clean));
      if (cleanId != null && cleanId.isNotEmpty) await _dbService.deletePallet(cleanId);
      if (clean.isNotEmpty) await _dbService.deletePallet(clean);
      await _dbService.savePalletsBackup(_pallets);
      await _syncDirectOrQueue(
        tableName: 'pallets',
        recordId: cleanId ?? 'PAL-$clean',
        action: 'DELETE',
        payload: {'pallet_id': cleanId ?? 'PAL-$clean', 'pallet_code': clean},
      );
    }

    _triggerBackgroundSync();
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
    final affectedOrderNos = <String>{};
    for (var it in _items.toList()) {
      if (cleanEpcs.contains(it.epc.toUpperCase())) {
        it.palletId = pallet.palletCode;
        if (it.status == ItemStatus.waitingPalletize || it.status == ItemStatus.pendingInbound) {
          it.status = ItemStatus.waitingPutaway;
          await _dbService.updateItemStatus(it.epc, ItemStatus.waitingPutaway);
          await _syncDirectOrQueue(
            tableName: 'items',
            recordId: it.itemId,
            action: 'UPDATE',
            payload: {
              'item_id': it.itemId,
              'status': ItemStatus.waitingPutaway.code,
              'pallet_id': pallet.palletCode,
              'updated_at': DateTime.now().toIso8601String(),
            },
          );
        }
        await recordTagLifecycle(
          epc: it.epc,
          itemId: it.itemId,
          sku: it.sku,
          productName: it.productName,
          serialNumber: it.serialNumber,
          action: TagLifecycleAction.palletize,
          previousStatus: it.status.label,
          newStatus: it.status == ItemStatus.waitingPutaway ? ItemStatus.waitingPutaway.label : it.status.label,
          toPallet: pallet.palletCode,
          performedBy: 'Thủ kho PDA / Trạm Pallet',
          device: 'SEUIC UTouch 2 PDA',
          notes: 'Xếp vào Pallet ${pallet.palletCode}',
        );
        if (it.orderNo != null && it.orderNo!.isNotEmpty) {
          affectedOrderNos.add(it.orderNo!);
        }
        if (!pallet.itemIds.contains(it.itemId)) {
          pallet.itemIds.add(it.itemId);
        }
        updatedEpcs.add(it.epc);
      }
    }
    if (updatedEpcs.isNotEmpty) {
      await _dbService.updateItemsLocationAndPallet(updatedEpcs, null, pallet.palletCode);
    }

    for (var oNo in affectedOrderNos) {
      final order = _inboundOrders.where((o) => o.orderNo == oNo || o.inboundOrderId == oNo).firstOrNull;
      if (order != null && order.status == InboundOrderStatus.waitingPalletize) {
        final orderItems = _items.where((i) => i.orderNo == order.orderNo).toList();
        if (orderItems.isNotEmpty && orderItems.every((i) => i.status != ItemStatus.waitingPalletize && i.status != ItemStatus.pendingInbound)) {
          order.status = InboundOrderStatus.waitingPutaway;
          await _dbService.updateInboundOrderStatus(order.inboundOrderId, InboundOrderStatus.waitingPutaway);
          await _syncDirectOrQueue(
            tableName: 'inbound_orders',
            recordId: order.inboundOrderId,
            action: 'UPDATE',
            payload: {
              'inbound_order_id': order.inboundOrderId,
              'status': InboundOrderStatus.waitingPutaway.code,
              'updated_at': DateTime.now().toIso8601String(),
            },
          );
        }
      }
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
    final affectedOrderNos = <String>{};
    for (var it in _items) {
      final itemCarton = it.cartonCode?.toUpperCase() ?? (it.palletId?.toUpperCase() ?? '');
      final itemOrder = it.orderNo?.toUpperCase() ?? '';
      if (cleanCartons.contains(itemCarton) || cleanCartons.contains(itemOrder)) {
        it.palletId = pallet.palletCode;
        if (it.status == ItemStatus.waitingPalletize || it.status == ItemStatus.pendingInbound) {
          it.status = ItemStatus.waitingPutaway;
          await _dbService.updateItemStatus(it.epc, ItemStatus.waitingPutaway);
          await _syncDirectOrQueue(
            tableName: 'items',
            recordId: it.itemId,
            action: 'UPDATE',
            payload: {
              'item_id': it.itemId,
              'status': ItemStatus.waitingPutaway.code,
              'pallet_id': pallet.palletCode,
              'updated_at': DateTime.now().toIso8601String(),
            },
          );
        }
        if (it.orderNo != null && it.orderNo!.isNotEmpty) {
          affectedOrderNos.add(it.orderNo!);
        }
        if (!pallet.itemIds.contains(it.itemId)) {
          pallet.itemIds.add(it.itemId);
        }
        updatedCartonEpcs.add(it.epc);
      }
    }
    if (updatedCartonEpcs.isNotEmpty) {
      await _dbService.updateItemsLocationAndPallet(updatedCartonEpcs, null, pallet.palletCode);
    }

    for (var oNo in affectedOrderNos) {
      final order = _inboundOrders.where((o) => o.orderNo == oNo || o.inboundOrderId == oNo).firstOrNull;
      if (order != null && order.status == InboundOrderStatus.waitingPalletize) {
        final orderItems = _items.where((i) => i.orderNo == order.orderNo).toList();
        if (orderItems.isNotEmpty && orderItems.every((i) => i.status != ItemStatus.waitingPalletize && i.status != ItemStatus.pendingInbound)) {
          order.status = InboundOrderStatus.waitingPutaway;
          await _dbService.updateInboundOrderStatus(order.inboundOrderId, InboundOrderStatus.waitingPutaway);
          await _syncDirectOrQueue(
            tableName: 'inbound_orders',
            recordId: order.inboundOrderId,
            action: 'UPDATE',
            payload: {
              'inbound_order_id': order.inboundOrderId,
              'status': InboundOrderStatus.waitingPutaway.code,
              'updated_at': DateTime.now().toIso8601String(),
            },
          );
        }
      }
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
      final putawayLoc = findLocationFast(locationId);
      final putawayLocDisplay = putawayLoc?.displayName ?? (putawayLoc?.locationCode ?? locationId);
      await recordTagLifecycle(
        epc: it.epc,
        itemId: it.itemId,
        sku: it.sku,
        productName: it.productName,
        serialNumber: it.serialNumber,
        action: TagLifecycleAction.putaway,
        previousStatus: ItemStatus.waitingPutaway.label,
        newStatus: ItemStatus.inStock.label,
        toLocation: putawayLocDisplay,
        toPallet: pallet.palletCode,
        performedBy: performedBy,
        device: 'Desktop WMS / PDA',
        notes: 'Cất Pallet ${pallet.palletCode} lên vị trí kệ $putawayLocDisplay',
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

    // Tự động kiểm tra và hoàn thành đơn nhập kho nếu tất cả mặt hàng đã cất vào kệ
    final affectedOrderNos = matchedItems
        .map((i) => (i.orderNo ?? '').trim().toUpperCase())
        .where((s) => s.isNotEmpty)
        .toSet();
    for (final oNo in affectedOrderNos) {
      final ord = _inboundOrders.where((o) =>
        o.orderNo.trim().toUpperCase() == oNo ||
        o.inboundOrderId.trim().toUpperCase() == oNo
      ).firstOrNull;
      if (ord != null && ord.status != InboundOrderStatus.completed) {
        if (isInboundOrderPutawayCompleted(ord)) {
          ord.status = InboundOrderStatus.completed;
          for (var d in ord.details) {
            d.receivedQty = d.requiredQty;
          }
          await _dbService.updateInboundOrderStatus(ord.inboundOrderId, InboundOrderStatus.completed, locationId: locationId);
          await _syncDirectOrQueue(
            tableName: 'inbound_orders',
            recordId: ord.inboundOrderId,
            action: 'UPDATE',
            payload: {
              'inbound_order_id': ord.inboundOrderId,
              'status': InboundOrderStatus.completed.code,
              'updated_at': DateTime.now().toIso8601String(),
            },
          );
        }
      }
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
    final location = _locations.where((l) => l.locationId == locationId || l.locationCode == locationId).firstOrNull;

    for (var itemId in pallet.itemIds) {
      final item = _items.firstWhere((it) => it.itemId == itemId);
      item.status = ItemStatus.inStock;
      item.inboundTime = DateTime.now();
      item.locationId = locationId;
      _dbService.updateItemLocationAndPallet(item.epc, locationId, pallet.palletId);
      _dbService.updateItemStatus(item.epc, ItemStatus.inStock);

      recordTagLifecycle(
        epc: item.epc,
        itemId: item.itemId,
        sku: item.sku,
        productName: item.productName,
        serialNumber: item.serialNumber,
        action: TagLifecycleAction.putaway,
        previousStatus: ItemStatus.waitingPutaway.label,
        newStatus: ItemStatus.inStock.label,
        toLocation: location?.displayName ?? locationId,
        toPallet: pallet.displayName,
        performedBy: performedBy,
        device: 'Cổng RFID Gate Inbound',
        notes: 'Cất vào vị trí kệ ${location?.displayName ?? locationId} (Pallet: ${pallet.displayName})',
      );
    }

    order.status = InboundOrderStatus.completed;
    _dbService.updateInboundOrderStatus(order.inboundOrderId, InboundOrderStatus.completed, locationId: locationId, palletId: pallet.palletId);
    for (var d in order.details) {
      d.receivedQty = d.requiredQty;
    }

    pallet.locationId = locationId;
    _dbService.updatePalletLocation(pallet.palletId, locationId);
    if (location != null) location.currentPallets++;

    for (var d in order.details) {
      final tx = InventoryTransaction(
        transactionId: 'TX-${DateTime.now().millisecondsSinceEpoch}-${d.sku}',
        type: TransactionType.inbound,
        documentNo: orderNo,
        sku: d.sku,
        productName: d.productName,
        quantity: d.requiredQty,
        toLocation: location?.locationCode ?? locationId,
        palletCode: palletCode,
        performedBy: performedBy,
        timestamp: DateTime.now(),
        notes: 'Nhập kho thành công, Gate INBOUND PASS',
      );
      _transactions.insert(0, tx);
      _syncInventoryTransaction(tx);
    }

    ErpBravoService().pushInboundCompleted(orderNo, pallet.itemIds.length);
    _triggerBackgroundSync();

    notifyListeners();
    return true;

  }

  Future<int> confirmGateReceiveToWaitingPutaway({
    required String orderNo,
    required List<String> scannedEpcs,
    String? palletCode,
    String? cartonCode,
    String? performedBy,
  }) async {
    final cleanOrderNo = orderNo.trim().toUpperCase();
    final uniqueEpcs = scannedEpcs.toSet().toList();
    final now = DateTime.now();
    final cleanPallet = (palletCode != null && palletCode.trim().isNotEmpty) ? palletCode.trim().toUpperCase() : null;
    final cleanCarton = (cartonCode != null && cartonCode.trim().isNotEmpty) ? cartonCode.trim().toUpperCase() : null;
    final effectivePerformer = (performedBy != null && performedBy.trim().isNotEmpty && performedBy != 'Thủ kho' && performedBy != 'Cổng RFID Gate')
        ? performedBy.trim()
        : (AuthService().currentUser?.fullName ?? resolveUserFullName(null, defaultRole: 'thukho'));

    final order = _inboundOrders.where((o) =>
      o.orderNo.trim().toUpperCase() == cleanOrderNo ||
      o.inboundOrderId.trim().toUpperCase() == cleanOrderNo
    ).firstOrNull;

    final matchedItems = _items.where((it) {
      if (uniqueEpcs.isNotEmpty) {
        return it.epc.isNotEmpty && uniqueEpcs.contains(it.epc.trim().toUpperCase());
      }
      if (cleanPallet != null) {
        return it.palletId != null &&
            (it.palletId!.trim().toUpperCase() == cleanPallet ||
             it.palletId!.trim().toUpperCase() == 'PAL-$cleanPallet');
      }
      if (cleanOrderNo.isNotEmpty && (it.orderNo?.trim().toUpperCase() == cleanOrderNo)) {
        return true;
      }
      if (it.palletId != null && it.palletId!.trim().toUpperCase() == cleanOrderNo) return true;
      return false;
    }).toList();

    // Nếu các mặt hàng này đã có mã Barcode Hex sinh sẵn lúc nạp danh sách nhập hàng, giữ nguyên mã đó
    final existingItemBarcode = matchedItems
        .map((i) => i.sku)
        .where((s) => s.isNotEmpty && s != cleanOrderNo && RegExp(r'^[0-9A-Fa-f]{16}$').hasMatch(s))
        .firstOrNull;

    // Sinh mã Barcode 128 chuẩn Hex (A-F và 0-9) nếu chưa có mã thùng cụ thể
    final effectiveCartonCode = cleanCarton ?? (existingItemBarcode ?? generateHexBarcode128());

    // Kiểm tra xem đơn/hàng có mã pallet trong file import hoặc được truyền vào
    final hasPallet = cleanPallet != null || matchedItems.any((it) => it.palletId != null && it.palletId!.trim().isNotEmpty);
    final targetStatus = hasPallet ? ItemStatus.waitingPutaway : ItemStatus.waitingPalletize;
    final targetOrderStatus = hasPallet ? InboundOrderStatus.waitingPutaway : InboundOrderStatus.waitingPalletize;

    for (var it in matchedItems) {
      it.status = targetStatus;
      if (hasPallet) {
        it.palletId = (it.palletId != null && it.palletId!.trim().isNotEmpty)
            ? it.palletId
            : cleanPallet;
      } else {
        it.palletId = null;
      }
      // Chỉ gán fallback nếu item chưa có SKU hoặc ProductId
      if (it.sku.trim().isEmpty) {
        it.sku = effectiveCartonCode;
      }
      if (it.productId.trim().isEmpty) {
        it.productId = it.sku;
      }
      it.locationId = null;
      it.inboundTime = now;
      if (it.cartonCode == null || it.cartonCode!.trim().isEmpty) {
        it.cartonCode = effectiveCartonCode;
      }
      it.inboundBy = effectivePerformer;
      if (order != null && (it.supplier == null || it.supplier!.isEmpty)) {
        it.supplier = order.sourceSupplier;
      }
      if (it.orderNo == null || it.orderNo!.isEmpty) {
        it.orderNo = cleanOrderNo;
      }

      // Đảm bảo có bản ghi Product tương ứng
      final existingProd = _products.where((p) => p.sku == it.sku || p.productId == it.productId).firstOrNull;
      if (existingProd == null) {
        final productName = it.productName.isNotEmpty && it.productName != 'Sản phẩm mẫu' && it.productName != 'Item'
            ? it.productName
            : 'Sản phẩm ${it.sku}';

        final newProd = Product(
          productId: it.productId,
          sku: it.sku,
          productName: productName,
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
          'status': it.status.code,
          'location_id': null,
          'pallet_id': it.palletId,
          'order_no': it.orderNo,
          'inbound_time': now.toIso8601String(),
          'updated_at': now.toIso8601String(),
        },
      );
    }

    if (!Platform.environment.containsKey('FLUTTER_TEST') && matchedItems.isNotEmpty) {
      try {
        final supa = Supabase.instance.client;
        final matchedIds = matchedItems.map((i) => i.itemId).toList();
        final effectivePalletId = hasPallet
            ? (cleanPallet != null
                ? (cleanPallet.startsWith('PAL-') ? cleanPallet : 'PAL-$cleanPallet')
                : matchedItems.first.palletId)
            : null;

        // Đảm bảo Pallet đã có trên Supabase Cloud
        if (effectivePalletId != null) {
          final matchedPal = _pallets.where((p) =>
            p.palletId.toUpperCase() == effectivePalletId.toUpperCase() ||
            p.palletCode.toUpperCase() == effectivePalletId.toUpperCase() ||
            p.palletId.toUpperCase() == 'PAL-${effectivePalletId.toUpperCase()}'
          ).firstOrNull;
          if (matchedPal != null) {
            try {
              await supa.from('pallets').upsert({
                'pallet_id': matchedPal.palletId,
                'pallet_code': matchedPal.palletCode,
                'rfid_epc': matchedPal.rfidEpc,
                'location_id': matchedPal.locationId,
                'inbound_time': matchedPal.inboundTime?.toIso8601String() ?? now.toIso8601String(),
                'is_multi_sku': matchedPal.isMultiSku ? 1 : 0,
              }, onConflict: 'pallet_id');
            } catch (_) {}
          }
        }

        // Upsert toàn diện từng item lên Supabase để đảm bảo nếu item chưa có thì được tạo mới ngay lập tức
        final upsertRows = matchedItems.map((it) => {
          'item_id': it.itemId,
          'product_id': it.productId,
          'sku': it.sku,
          'product_name': it.productName,
          'serial_number': it.serialNumber,
          'epc': it.epc.toUpperCase(),
          'status': targetStatus.code,
          'order_no': cleanOrderNo,
          'pallet_id': effectivePalletId ?? it.palletId,
          'location_id': it.locationId,
          'inbound_time': now.toIso8601String(),
          'allocated_time': it.allocatedTime?.toIso8601String(),
          'supplier': it.supplier,
          'updated_at': now.toIso8601String(),
        }).toList();

        try {
          await supa.from('items').upsert(upsertRows, onConflict: 'item_id');
          debugPrint('✓ confirmGateReceive: Upsert thành công ${upsertRows.length} items (WAITING_PUTAWAY) lên Supabase.');
        } catch (e) {
          debugPrint('confirmGateReceive: upsert items error: $e. Thử fallback...');
          try {
            final fallbackRows = upsertRows.map((r) => Map<String, dynamic>.from(r)
              ..['pallet_id'] = null
              ..['location_id'] = null
            ).toList();
            await supa.from('items').upsert(fallbackRows, onConflict: 'item_id');
            debugPrint('✓ confirmGateReceive: Fallback upsert thành công (null FK).');
          } catch (err2) {
            debugPrint('confirmGateReceive fallback error: $err2');
          }
        }

        // Cập nhật bổ sung qua update filter để đồng bộ cache Supabase
        try {
          await supa.from('items').update({
            'status': targetStatus.code,
            'pallet_id': effectivePalletId,
            'order_no': cleanOrderNo,
            'inbound_time': now.toIso8601String(),
            'updated_at': now.toIso8601String(),
          }).inFilter('item_id', matchedIds);
        } catch (_) {}
      } catch (e) {
        debugPrint('Direct update items status in confirmGateReceive error: $e');
      }
    }

    for (var it in matchedItems) {
      _transactions.insert(
        0,
        InventoryTransaction(
          transactionId: 'TX-${now.millisecondsSinceEpoch}-${it.sku}',
          type: TransactionType.inbound,
          documentNo: cleanOrderNo,
          sku: it.sku,
          productName: it.productName,
          quantity: 1,
          toLocation: hasPallet ? 'CHỜ XẾP KỆ' : 'XẾP VÀO PALLET',
          palletCode: cleanPallet,
          performedBy: effectivePerformer,
          timestamp: now,
          notes: 'Nhập qua Cổng RFID Gate bởi $effectivePerformer',
        ),
      );
    }

    if (order != null) {
      final allOrderItems = _items.where((i) =>
        (i.orderNo?.trim().toUpperCase() == cleanOrderNo) ||
        (i.orderNo?.trim().toUpperCase() == 'INB-$cleanOrderNo')
      ).toList();

      for (var d in order.details) {
        final receivedCount = allOrderItems.where((i) =>
          i.sku == d.sku && (i.status != ItemStatus.pendingInbound)
        ).length;
        d.receivedQty = receivedCount;
      }

      final hasPendingItems = allOrderItems.any((i) => i.status == ItemStatus.pendingInbound);
      final newOrderStatus = hasPendingItems
          ? InboundOrderStatus.processing
          : targetOrderStatus;

      order.status = newOrderStatus;
      await _dbService.updateInboundOrderStatus(order.inboundOrderId, newOrderStatus);
      if (!Platform.environment.containsKey('FLUTTER_TEST')) {
        try {
          await Supabase.instance.client.from('inbound_orders').update({
            'status': newOrderStatus.code,
            'updated_at': now.toIso8601String(),
          }).or('inbound_order_id.eq.${order.inboundOrderId},order_no.eq.${order.orderNo}');
        } catch (e) {
          debugPrint('Direct update inbound_orders status error: $e');
        }
      }
      await _syncDirectOrQueue(
        tableName: 'inbound_orders',
        recordId: order.inboundOrderId,
        action: 'UPDATE',
        payload: {
          'inbound_order_id': order.inboundOrderId,
          'status': newOrderStatus.code,
          'updated_at': now.toIso8601String(),
        },
      );
    }

    final summaryTx = InventoryTransaction(
      transactionId: 'TX-INB-GATE-${now.millisecondsSinceEpoch}-$cleanOrderNo',
      type: TransactionType.inbound,
      documentNo: cleanOrderNo,
      sku: matchedItems.firstOrNull?.sku ?? 'MULTI-SKU',
      productName: matchedItems.firstOrNull?.productName ?? 'Nhập kho qua cổng',
      quantity: matchedItems.length,
      toLocation: hasPallet ? 'CHỜ XẾP KỆ' : 'XẾP VÀO PALLET',
      palletCode: cleanPallet,
      performedBy: effectivePerformer,
      timestamp: now,
      notes: hasPallet ? 'Đã gán Pallet $cleanPallet - Chờ cất kệ' : 'Chờ đóng pallet sau khi qua cổng',
    );
    await _syncInventoryTransaction(summaryTx);

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

    final cleanPalletNormalized = cleanBarcode.replaceAll('-', '').replaceAll('PAL', '');
    final matchingPalletIds = _pallets
        .where((p) =>
            p.palletCode.trim().toUpperCase() == cleanBarcode ||
            p.palletId.trim().toUpperCase() == cleanBarcode ||
            p.palletId.trim().toUpperCase() == 'PAL-$cleanBarcode' ||
            p.palletId.trim().toUpperCase().replaceAll('-', '') == cleanBarcode.replaceAll('-', '') ||
            (cleanPalletNormalized.isNotEmpty && p.palletId.trim().toUpperCase().replaceAll('-', '').replaceAll('PAL', '') == cleanPalletNormalized) ||
            (p.rfidEpc != null && p.rfidEpc!.trim().toUpperCase() == cleanBarcode))
        .map((p) => p.palletId.trim().toUpperCase())
        .toSet();

    var matchedItems = _items.where((it) {
      if (it.orderNo != null && it.orderNo!.trim().toUpperCase() == cleanBarcode) return true;
      if (it.palletId != null) {
        final itPal = it.palletId!.trim().toUpperCase();
        if (itPal == cleanBarcode ||
            itPal == 'PAL-$cleanBarcode' ||
            itPal.replaceAll('-', '') == cleanBarcode.replaceAll('-', '') ||
            (cleanPalletNormalized.isNotEmpty && itPal.replaceAll('-', '').replaceAll('PAL', '') == cleanPalletNormalized) ||
            matchingPalletIds.contains(itPal)) {
          return true;
        }
      }
      if (it.cartonCode != null && it.cartonCode!.trim().toUpperCase() == cleanBarcode) return true;
      if (it.sku.trim().toUpperCase() == cleanBarcode) return true;
      if (it.productId.trim().toUpperCase() == cleanBarcode) return true;
      if (it.epc.trim().toUpperCase() == cleanBarcode || it.serialNumber.trim().toUpperCase() == cleanBarcode) return true;

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

    // 2. Tra cứu trực tiếp từ DatabaseService theo LIKE / orderNo nếu bộ nhớ RAM chưa load kịp
    if (matchedItems.isEmpty) {
      final dbItems = await _dbService.getItems();
      final pulledFromDb = dbItems.where((it) =>
        (it.orderNo != null && it.orderNo!.trim().toUpperCase() == cleanBarcode) ||
        (it.palletId != null && (
          it.palletId!.trim().toUpperCase() == cleanBarcode ||
          it.palletId!.trim().toUpperCase() == 'PAL-$cleanBarcode' ||
          it.palletId!.trim().toUpperCase().replaceAll('-', '') == cleanBarcode.replaceAll('-', '') ||
          (cleanPalletNormalized.isNotEmpty && it.palletId!.trim().toUpperCase().replaceAll('-', '').replaceAll('PAL', '') == cleanPalletNormalized)
        )) ||
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

    // 3. Nếu trên thiết bị PDA chưa có trong DatabaseService nội bộ, tra cứu Realtime từ Supabase Cloud
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

    final actualPerformer = (performedBy.isNotEmpty && !performedBy.contains('Thủ kho PDA'))
        ? resolveUserFullName(performedBy, defaultRole: 'handheld')
        : resolveUserFullName(null, defaultRole: 'handheld');

    for (var it in matchedItems) {
      final oldLoc = it.locationId ?? 'LOC-GATE-IN';
      it.status = ItemStatus.inStock;
      it.locationId = loc.locationId;
      it.putawayBy = actualPerformer;
      it.inboundTime ??= now;
      if (cleanBarcode.startsWith('PAL') || cleanBarcode.startsWith('PL')) {
        final canonicalPal = cleanBarcode.startsWith('PAL-')
            ? cleanBarcode
            : (cleanBarcode.startsWith('PAL') ? 'PAL-${cleanBarcode.substring(3)}' : 'PAL-$cleanBarcode');
        it.palletId = canonicalPal;
      }

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
          performedBy: actualPerformer,
          timestamp: now,
          notes: 'Xác nhận cất thùng hàng $cleanBarcode lên kệ ${loc.locationCode} bằng PDA Barcode',
        ),
      );

      final oldLocObj = findLocationFast(oldLoc);
      final oldLocDisplay = oldLocObj?.displayName ?? oldLoc;
      final newLocDisplay = loc.displayName;
      final palDisplay = it.palletId != null ? (findPalletFast(it.palletId)?.displayName ?? it.palletId) : null;

      if (oldLoc == 'LOC-GATE-IN' || oldLoc == 'CỔNG GATE (IN)' || oldLoc.isEmpty) {
        await recordTagLifecycle(
          epc: it.epc,
          itemId: it.itemId,
          sku: it.sku,
          productName: it.productName,
          serialNumber: it.serialNumber,
          action: TagLifecycleAction.putaway,
          previousStatus: ItemStatus.waitingPutaway.label,
          newStatus: ItemStatus.inStock.label,
          toLocation: newLocDisplay,
          toPallet: palDisplay,
          performedBy: actualPerformer,
          device: 'SEUIC UTouch 2 PDA',
          notes: 'Cất vào vị trí kệ $newLocDisplay bằng PDA Barcode${palDisplay != null ? " (Pallet: $palDisplay)" : ""}',
        );
      } else {
        await recordTagLifecycle(
          epc: it.epc,
          itemId: it.itemId,
          sku: it.sku,
          productName: it.productName,
          serialNumber: it.serialNumber,
          action: TagLifecycleAction.transferLocation,
          previousStatus: ItemStatus.inStock.label,
          newStatus: ItemStatus.inStock.label,
          fromLocation: oldLocDisplay,
          toLocation: newLocDisplay,
          fromPallet: palDisplay,
          toPallet: palDisplay,
          performedBy: actualPerformer,
          device: 'SEUIC UTouch 2 PDA',
          notes: 'Điều chuyển vị trí từ $oldLocDisplay sang $newLocDisplay bằng PDA Barcode',
        );
      }
    }

    final affectedPalletIds = matchedItems.map((i) => i.palletId).whereType<String>().toSet();
    for (final palId in affectedPalletIds) {
      final pal = _pallets.where((p) =>
          p.palletId.trim().toUpperCase() == palId.trim().toUpperCase() ||
          p.palletCode.trim().toUpperCase() == palId.trim().toUpperCase() ||
          p.palletId.trim().toUpperCase() == 'PAL-${palId.trim().toUpperCase()}').firstOrNull;
      if (pal != null) {
        pal.locationId = loc.locationId;
        await _dbService.insertPallet(pal);
        await _syncDirectOrQueue(
          tableName: 'pallets',
          recordId: pal.palletId,
          action: 'UPDATE',
          payload: {
            'pallet_id': pal.palletId,
            'location_id': pal.locationId,
          },
        );
      }
    }

    final affectedOrderNos = matchedItems.map((i) => i.orderNo).whereType<String>().toSet();
    final directOrder = _inboundOrders.where((o) =>
      o.orderNo.trim().toUpperCase() == cleanBarcode ||
      o.inboundOrderId.trim().toUpperCase() == cleanBarcode
    ).firstOrNull;
    if (directOrder != null) affectedOrderNos.add(directOrder.orderNo);

    for (final oNo in affectedOrderNos) {
      final ord = _inboundOrders.where((o) =>
        o.orderNo.trim().toUpperCase() == oNo.trim().toUpperCase() ||
        o.inboundOrderId.trim().toUpperCase() == oNo.trim().toUpperCase()
      ).firstOrNull;
      if (ord != null) {
        if (isInboundOrderPutawayCompleted(ord)) {
          ord.status = InboundOrderStatus.completed;
          for (var d in ord.details) {
            d.receivedQty = d.requiredQty;
          }
          await _dbService.updateInboundOrderStatus(ord.inboundOrderId, InboundOrderStatus.completed, locationId: loc.locationId);
          await _syncDirectOrQueue(
            tableName: 'inbound_orders',
            recordId: ord.inboundOrderId,
            action: 'UPDATE',
            payload: {
              'inbound_order_id': ord.inboundOrderId,
              'status': InboundOrderStatus.completed.code,
              'updated_at': now.toIso8601String(),
            },
          );
        }
      }
    }

    final putawayTx = InventoryTransaction(
      transactionId: 'TX-PUTAWAY-${now.millisecondsSinceEpoch}-$cleanBarcode',
      type: TransactionType.movement,
      documentNo: directOrder?.orderNo ?? (affectedOrderNos.isNotEmpty ? affectedOrderNos.first : cleanBarcode),
      sku: matchedItems.firstOrNull?.sku ?? 'PALLET-PUTAWAY',
      productName: matchedItems.firstOrNull?.productName ?? 'Cất kệ hàng hóa',
      quantity: matchedItems.length,
      fromLocation: 'Khu vực chờ cất kệ',
      toLocation: loc.locationCode,
      palletCode: cleanBarcode.startsWith('PAL') ? cleanBarcode : (matchedItems.firstOrNull?.palletId ?? cleanBarcode),
      performedBy: performedBy,
      timestamp: now,
      notes: 'Cất kệ thành công qua PDA - Vị trí: ${loc.locationCode}',
    );
    await _syncInventoryTransaction(putawayTx);


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
    final actualPerformer = (performedBy.isNotEmpty && !performedBy.contains('Thủ kho PDA'))
        ? resolveUserFullName(performedBy, defaultRole: 'handheld')
        : resolveUserFullName(null, defaultRole: 'handheld');

    pallet.placedBy = actualPerformer;

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
        'placed_by': actualPerformer,
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
        item.inboundBy = actualPerformer;
        if (locationId != null) {
          item.putawayBy = actualPerformer;
        }
        if (item.cartonCode == null || item.cartonCode!.isEmpty) {
          item.cartonCode = palletCode;
        }
        if (orderNo != null && (item.supplier == null || item.supplier!.isEmpty)) {
          final ord = _inboundOrders.where((o) => o.orderNo == orderNo).firstOrNull;
          if (ord != null) item.supplier = ord.sourceSupplier;
        }
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
    final tx = InventoryTransaction(
      transactionId: 'TX-INB-PDA-${now.millisecondsSinceEpoch}',
      type: TransactionType.inbound,
      documentNo: orderNo ?? 'PDA-DIRECT-IN',
      sku: defaultSku ?? 'MULTI-SKU',
      productName: defaultProductName ?? 'Nhập kho quét RFID',
      quantity: uniqueEpcs.length,
      toLocation: destinationName,
      palletCode: palletCode,
      performedBy: actualPerformer,
      timestamp: now,
      notes: 'Nhập $count thẻ RFID qua PDA vào Pallet $palletCode - Trạng thái: $destinationName',
    );
    _transactions.insert(0, tx);

    ErpBravoService().pushInboundCompleted(orderNo ?? 'PDA-DIRECT-IN', uniqueEpcs.length);

    await _syncInventoryTransaction(tx);

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

      // Sắp xếp các sản phẩm cùng mã theo ngày nhập xa hiện tại nhất (FIFO) lên đầu
      availableItems.sort((a, b) {
        final timeA = a.inboundTime;
        final timeB = b.inboundTime;
        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1;
        if (timeB == null) return -1;
        return timeA.compareTo(timeB);
      });

      final Map<String, List<Item>> palletGroups = {};
      for (var it in availableItems) {
        palletGroups.putIfAbsent(it.palletId!, () => []).add(it);
      }

      final sortedPalletIds = palletGroups.keys.toList()
        ..sort((a, b) {
          final itemsA = palletGroups[a]!;
          final itemsB = palletGroups[b]!;
          final pA = _pallets.firstWhere((p) => p.palletId == a, orElse: () => Pallet(palletId: a, palletCode: a));
          final pB = _pallets.firstWhere((p) => p.palletId == b, orElse: () => Pallet(palletId: b, palletCode: b));
          final earliestA = itemsA.map((i) => i.inboundTime).whereType<DateTime>().fold<DateTime?>(pA.inboundTime, (prev, curr) => prev == null ? curr : (curr.isBefore(prev) ? curr : prev));
          final earliestB = itemsB.map((i) => i.inboundTime).whereType<DateTime>().fold<DateTime?>(pB.inboundTime, (prev, curr) => prev == null ? curr : (curr.isBefore(prev) ? curr : prev));

          if (earliestA == null && earliestB == null) return 0;
          if (earliestA == null) return 1;
          if (earliestB == null) return -1;
          return earliestA.compareTo(earliestB);
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
        final cleanPalId = item.palletId!.trim().toUpperCase();
        final pal = _pallets.where((p) =>
            p.palletId.toUpperCase() == cleanPalId ||
            p.palletCode.toUpperCase() == cleanPalId ||
            p.palletId.toUpperCase() == 'PAL-$cleanPalId').firstOrNull;
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

    final allowedSkus = order.details.map((d) => d.sku.toUpperCase()).toSet();
    final allowedProdIds = order.details.map((d) => d.productId.toUpperCase()).toSet();

    final List<SkuVerificationBreakdown> breakdowns = [];
    bool allMatched = true;

    for (var epc in uniqueEpcs) {
      final item = _items.where((it) => it.epc.toUpperCase() == epc.toUpperCase()).firstOrNull;

      if (item == null) {
        unexpectedEpcs.add(epc);
      } else if (!allowedSkus.contains(item.sku.toUpperCase()) &&
                 !allowedProdIds.contains(item.productId.toUpperCase()) &&
                 !(item.palletId != null && allowedSkus.contains(item.palletId!.toUpperCase()))) {
        // Chip không thuộc mã hàng/SKU nào trong đơn xuất
        unexpectedEpcs.add(epc);
      } else if (!isItemStockedInLocation(item)) {
        unstockedEpcs.add(epc);
        allMatched = false;
      } else {
        final matchedDetail = order.details.where((d) =>
          d.sku.toUpperCase() == item.sku.toUpperCase() ||
          d.productId.toUpperCase() == item.productId.toUpperCase() ||
          d.sku.toUpperCase() == item.productId.toUpperCase() ||
          (item.palletId != null && d.sku.toUpperCase() == item.palletId!.toUpperCase())
        ).firstOrNull;

        final matchedSku = matchedDetail?.sku ?? item.sku;
        final currentCount = actualSkuCounts[matchedSku] ?? 0;
        final maxRequired = matchedDetail?.requiredQty ?? 0;
        actualSkuCounts[matchedSku] = currentCount + 1;

        if (currentCount >= maxRequired) {
          // Vượt quá số lượng yêu cầu của SKU này, chip quét thêm tính là thẻ thừa
          unexpectedEpcs.add(epc);
        }
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
      final item = _items.where((it) => it.epc.toUpperCase() == epc.toUpperCase()).firstOrNull;
      if (item != null) {
        item.status = ItemStatus.out;
        item.locationId = null;
        final oldPalletId = item.palletId;
        item.palletId = null;
        if (oldPalletId != null && oldPalletId.trim().isNotEmpty) {
          final cleanPal = oldPalletId.trim().toUpperCase();
          final pal = _pallets.where((p) => p.palletId.trim().toUpperCase() == cleanPal || p.palletCode.trim().toUpperCase() == cleanPal).firstOrNull;
          if (pal != null) {
            pal.itemIds.remove(item.itemId);
            final remainingInStock = _items.where((it) =>
              it.palletId?.trim().toUpperCase() == cleanPal &&
              it.status == ItemStatus.inStock &&
              it.itemId != item.itemId
            ).length;
            if (remainingInStock == 0 && pal.itemIds.isEmpty) {
              pal.locationId = null;
              await _dbService.insertPallet(pal);
              await _syncDirectOrQueue(
                tableName: 'pallets',
                recordId: pal.palletId,
                action: 'UPDATE',
                payload: {
                  'pallet_id': pal.palletId,
                  'location_id': null,
                  'updated_at': now.toIso8601String(),
                },
              );
            }
          }
        }
        await _dbService.updateItemStatus(item.epc, ItemStatus.out);
        await _dbService.updateItemLocationAndPallet(item.epc, null, null, status: ItemStatus.out.code);
        await _dbService.insertItem(item);
        await _syncDirectOrQueue(
          tableName: 'items',
          recordId: item.itemId,
          action: 'UPDATE',
          payload: {
            'item_id': item.itemId,
            'status': ItemStatus.out.code,
            'location_id': null,
            'pallet_id': null,
            'updated_at': now.toIso8601String(),
          },
        );
        await recordTagLifecycle(
          epc: item.epc,
          itemId: item.itemId,
          sku: item.sku,
          productName: item.productName,
          serialNumber: item.serialNumber,
          action: TagLifecycleAction.outboundGate,
          previousStatus: ItemStatus.inStock.label,
          newStatus: ItemStatus.out.label,
          fromLocation: item.locationId,
          fromPallet: oldPalletId,
          documentNo: order.poNo,
          performedBy: performedBy,
          device: 'Cổng RFID Gate Outbound',
          notes: 'Xuất kho qua cổng RFID theo đơn ${order.poNo}',
        );
      }
    }

    order.status = OutboundOrderStatus.shipped;
    for (var d in order.details) {
      if (d.pickedQty < d.requiredQty) {
        d.pickedQty = d.requiredQty;
      }
    }
    await _dbService.updateOutboundOrderStatus(order.outboundOrderId, OutboundOrderStatus.shipped);

    for (var d in order.details) {
      final tx = InventoryTransaction(
        transactionId: 'TX-OUT-GATE-${now.millisecondsSinceEpoch}-${d.sku}',
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
      );
      _transactions.insert(0, tx);
      await _syncInventoryTransaction(tx);
    }

    ErpBravoService().pushOutboundCompleted(poNo, shippedEpcs.length);
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
      final item = _items.where((it) => it.epc.toUpperCase() == epc.toUpperCase()).firstOrNull;
      if (item != null) {
        item.status = ItemStatus.out;
        item.locationId = null;
        final oldPalletId = item.palletId;
        item.palletId = null;
        if (oldPalletId != null && oldPalletId.trim().isNotEmpty) {
          final cleanPal = oldPalletId.trim().toUpperCase();
          final pal = _pallets.where((p) => p.palletId.trim().toUpperCase() == cleanPal || p.palletCode.trim().toUpperCase() == cleanPal).firstOrNull;
          if (pal != null) {
            pal.itemIds.remove(item.itemId);
            final remainingInStock = _items.where((it) =>
              it.palletId?.trim().toUpperCase() == cleanPal &&
              it.status == ItemStatus.inStock &&
              it.itemId != item.itemId
            ).length;
            if (remainingInStock == 0 && pal.itemIds.isEmpty) {
              pal.locationId = null;
              await _dbService.insertPallet(pal);
              await _syncDirectOrQueue(
                tableName: 'pallets',
                recordId: pal.palletId,
                action: 'UPDATE',
                payload: {
                  'pallet_id': pal.palletId,
                  'location_id': null,
                  'updated_at': now.toIso8601String(),
                },
              );
            }
          }
        }
        await _dbService.updateItemStatus(item.epc, ItemStatus.out);
        await _dbService.updateItemLocationAndPallet(item.epc, null, null, status: ItemStatus.out.code);
        await _dbService.insertItem(item);
        await _syncDirectOrQueue(
          tableName: 'items',
          recordId: item.itemId,
          action: 'UPDATE',
          payload: {
            'item_id': item.itemId,
            'status': ItemStatus.out.code,
            'location_id': null,
            'pallet_id': null,
            'updated_at': now.toIso8601String(),
          },
        );
        await recordTagLifecycle(
          epc: item.epc,
          itemId: item.itemId,
          sku: item.sku,
          productName: item.productName,
          serialNumber: item.serialNumber,
          action: TagLifecycleAction.outboundGate,
          previousStatus: ItemStatus.inStock.label,
          newStatus: ItemStatus.out.label,
          fromLocation: item.locationId,
          fromPallet: oldPalletId,
          documentNo: poNo,
          performedBy: performedBy,
          device: 'Cổng RFID Gate / Desktop',
          notes: 'Xuất kho theo đơn ${poNo ?? "PO"}',
        );
      }
    }

    if (poNo != null) {
      final order = _outboundOrders.where((o) => o.poNo == poNo).firstOrNull;
      if (order != null) {
        order.status = OutboundOrderStatus.shipped;
        if (order.details.isEmpty) {
          order.details.add(OutboundOrderDetail(
            productId: 'MULTI',
            sku: 'MULTI',
            productName: 'Xuất trực tiếp trạm Desktop',
            requiredQty: uniqueEpcs.length,
            pickedQty: uniqueEpcs.length,
            epcList: uniqueEpcs,
          ));
        } else {
          for (var d in order.details) {
            if (d.pickedQty < d.requiredQty) {
              d.pickedQty = d.requiredQty;
            }
          }
        }
        await _dbService.updateOutboundOrderStatus(order.outboundOrderId, OutboundOrderStatus.shipped);
      }
    }

    final tx = InventoryTransaction(
      transactionId: 'TX-OUT-DIRECT-${now.millisecondsSinceEpoch}',
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
    );
    _transactions.insert(0, tx);

    await _syncInventoryTransaction(tx);
    _triggerBackgroundSync();

    notifyListeners();
    return uniqueEpcs.length;
  }


  /// Kiểm tra xem mã EPC hoặc Serial Number (SN) này đã từng được xuất kho (đã xuất đi rồi) hay chưa.
  Item? findShippedItem({String? epc, String? serialNumber}) {
    final cleanEpc = epc?.trim().toUpperCase();
    final cleanSn = serialNumber?.trim().toUpperCase();
    final hasEpc = cleanEpc != null && cleanEpc.isNotEmpty && cleanEpc != '--';
    final hasSn = cleanSn != null && cleanSn.isNotEmpty && cleanSn != '--';
    if (!hasEpc && !hasSn) return null;

    for (final it in _items) {
      if (it.status != ItemStatus.out) continue;
      if (hasEpc && it.epc.trim().toUpperCase() == cleanEpc) {
        return it;
      }
      if (hasSn && it.serialNumber.trim().toUpperCase() == cleanSn) {
        return it;
      }
    }
    return null;
  }

  /// Trả về true nếu mã EPC hoặc Serial Number (SN) này đã được xuất kho trước đó.
  bool isEpcOrSnAlreadyShipped({String? epc, String? serialNumber}) {
    return findShippedItem(epc: epc, serialNumber: serialNumber) != null;
  }

  /// Đối soát danh sách hàng cần xuất kho với tồn kho thực tế và vị trí kệ FIFO:
  /// - Kiểm tra số lượng tồn kho theo từng SKU (`status == ItemStatus.inStock`).
  /// - Nếu hàng có sẵn trong kho: sắp xếp theo FIFO (`inboundTime` tăng dần - hàng nhập trước ưu tiên xuất trước).
  /// Đối soát hàng tồn kho xuất kho và vị trí kệ FIFO:
  /// - Kiểm tra số lượng tồn kho khả dụng (`status == inStock || waitingPutaway || allocated`).
  /// - Ưu tiên đối soát theo thẻ chip EPC trực tiếp nếu file yêu cầu có EPC.
  /// - Nếu không có EPC, đối soát phân bổ theo SKU hoặc Tên sản phẩm theo chuẩn FIFO (`inboundTime` tăng dần).
  /// - Phân giải vị trí kệ (`locationCode`) thực tế từ `locationId` của sản phẩm hoặc pallet chứa sản phẩm.
  /// - Sắp xếp danh sách hàng xuất theo chuẩn FIFO: Hàng có sẵn xếp theo ngày nhập xa nhất/cũ nhất lên đầu.
  /// - Xác định chính xác số lượng thiếu hụt `shortageCount` để cảnh báo nếu không đủ tồn kho.
  OutboundInventoryValidationResult validateOutboundInventoryAndFifo({
    required List<Map<String, dynamic>> requestedItems,
  }) {
    if (requestedItems.isEmpty) {
      return OutboundInventoryValidationResult(
        isStockSufficient: true,
        totalRequested: 0,
        totalInStock: 0,
        shortageCount: 0,
        shortageBySku: {},
        items: [],
      );
    }

    // 1. Tập hợp các sản phẩm khả dụng trong kho (đã cất kệ, chờ cất kệ hoặc đã phân bổ)
    final availableStockItems = _items.where((it) =>
      it.status == ItemStatus.inStock ||
      it.status == ItemStatus.waitingPutaway ||
      it.status == ItemStatus.allocated
    ).toList();

    // Map vị trí kệ: locationId -> locationCode
    final locationCodeMap = <String, String>{};
    for (var loc in _locations) {
      locationCodeMap[loc.locationId] = loc.locationCode;
    }

    // Map vị trí của pallet: palletId / palletCode -> locationCode
    final palletLocationMap = <String, String>{};
    for (var pal in _pallets) {
      if (pal.locationId != null && locationCodeMap.containsKey(pal.locationId)) {
        final locCode = locationCodeMap[pal.locationId]!;
        palletLocationMap[pal.palletId] = locCode;
        palletLocationMap[pal.palletCode] = locCode;
      }
    }

    // Nhóm các sản phẩm tồn kho theo SKU, Tên, Product ID và Item ID, sắp xếp theo FIFO (inboundTime tăng dần)
    final Map<String, List<Item>> inStockBySku = {};
    final Map<String, List<Item>> inStockByName = {};
    final Map<String, List<Item>> inStockByProductId = {};
    final Map<String, List<Item>> inStockByItemId = {};
    for (var it in availableStockItems) {
      final skuKey = it.sku.trim().toUpperCase();
      if (skuKey.isNotEmpty && skuKey != '--') {
        inStockBySku.putIfAbsent(skuKey, () => []).add(it);
      }
      final nameKey = it.productName.trim().toUpperCase();
      if (nameKey.isNotEmpty && nameKey != '--') {
        inStockByName.putIfAbsent(nameKey, () => []).add(it);
      }
      final prodKey = it.productId.trim().toUpperCase();
      if (prodKey.isNotEmpty && prodKey != '--') {
        inStockByProductId.putIfAbsent(prodKey, () => []).add(it);
      }
      final itemKey = it.itemId.trim().toUpperCase();
      if (itemKey.isNotEmpty && itemKey != '--') {
        inStockByItemId.putIfAbsent(itemKey, () => []).add(it);
      }
    }

    // Sắp xếp từng nhóm theo FIFO (cũ nhất / ngày nhập xa nhất đứng đầu)
    for (var list in inStockBySku.values) {
      list.sort((a, b) {
        final timeA = getItemInboundTime(a);
        final timeB = getItemInboundTime(b);
        return timeA.compareTo(timeB);
      });
    }
    for (var list in inStockByName.values) {
      list.sort((a, b) {
        final timeA = getItemInboundTime(a);
        final timeB = getItemInboundTime(b);
        return timeA.compareTo(timeB);
      });
    }
    for (var list in inStockByProductId.values) {
      list.sort((a, b) {
        final timeA = getItemInboundTime(a);
        final timeB = getItemInboundTime(b);
        return timeA.compareTo(timeB);
      });
    }
    for (var list in inStockByItemId.values) {
      list.sort((a, b) {
        final timeA = getItemInboundTime(a);
        final timeB = getItemInboundTime(b);
        return timeA.compareTo(timeB);
      });
    }

    // 2. Cơ chế đối soát 2 pha (2-Phase Matching):
    final Set<String> allocatedItemIds = {};
    final Map<int, Item> matchedByIndex = {};

    // Pha 1: Đối soát ưu tiên tuyệt đối theo mã chip EPC cụ thể nếu file có truyền EPC
    for (int i = 0; i < requestedItems.length; i++) {
      final req = requestedItems[i];
      final reqEpc = (req['epc'] ?? '').toString().trim().toUpperCase();
      if (reqEpc.isNotEmpty && reqEpc != '--') {
        final matched = availableStockItems.where((it) =>
            it.epc.toUpperCase() == reqEpc && !allocatedItemIds.contains(it.itemId)
        ).firstOrNull;
        if (matched != null) {
          matchedByIndex[i] = matched;
          allocatedItemIds.add(matched.itemId);
        }
      }
    }

    // Pha 2: Với các dòng chưa khớp EPC (xuất theo số lượng hoặc không có mã chip EPC cụ thể),
    // tìm sản phẩm trong kho theo SKU, Mã Hàng (Product ID/Item ID) hoặc theo Tên sản phẩm theo thứ tự FIFO
    for (int i = 0; i < requestedItems.length; i++) {
      if (matchedByIndex.containsKey(i)) continue;
      final req = requestedItems[i];
      final skuKey = (req['sku'] ?? '').toString().trim().toUpperCase();
      final prodKey = (req['productId'] ?? '').toString().trim().toUpperCase();
      final itemKey = (req['itemId'] ?? '').toString().trim().toUpperCase();
      final nameKey = (req['productName'] ?? req['name'] ?? '').toString().trim().toUpperCase();

      Item? matched;
      // 1. Thử khớp theo SKU
      if (skuKey.isNotEmpty && skuKey != '--') {
        final candidates = inStockBySku[skuKey] ?? [];
        matched = candidates.where((it) => !allocatedItemIds.contains(it.itemId)).firstOrNull;
      }
      // 2. Thử khớp theo Mã Hàng (Product ID)
      if (matched == null && prodKey.isNotEmpty && prodKey != '--') {
        final candidates = inStockByProductId[prodKey] ?? [];
        matched = candidates.where((it) => !allocatedItemIds.contains(it.itemId)).firstOrNull;
      }
      // 3. Thử khớp theo Mã Hàng cụ thể (Item ID)
      if (matched == null && itemKey.isNotEmpty && itemKey != '--') {
        final candidates = inStockByItemId[itemKey] ?? [];
        matched = candidates.where((it) => !allocatedItemIds.contains(it.itemId)).firstOrNull;
      }
      // 4. Thử khớp chéo qua danh mục sản phẩm (nếu SKU map sang Product ID hoặc ngược lại)
      if (matched == null && (skuKey.isNotEmpty || prodKey.isNotEmpty)) {
        final p = _products.where((p) =>
          (skuKey.isNotEmpty && p.sku.toUpperCase() == skuKey) ||
          (prodKey.isNotEmpty && p.productId.toUpperCase() == prodKey)
        ).firstOrNull;
        if (p != null) {
          final candSku = inStockBySku[p.sku.toUpperCase()] ?? [];
          matched = candSku.where((it) => !allocatedItemIds.contains(it.itemId)).firstOrNull;
          if (matched == null) {
            final candProd = inStockByProductId[p.productId.toUpperCase()] ?? [];
            matched = candProd.where((it) => !allocatedItemIds.contains(it.itemId)).firstOrNull;
          }
        }
      }
      // 5. Thử khớp theo Tên sản phẩm
      if (matched == null && nameKey.isNotEmpty && nameKey != '--') {
        final candidates = inStockByName[nameKey] ?? [];
        matched = candidates.where((it) => !allocatedItemIds.contains(it.itemId)).firstOrNull;
      }

      if (matched != null) {
        matchedByIndex[i] = matched;
        allocatedItemIds.add(matched.itemId);
      }
    }

    // 3. Xây dựng danh sách OutboundValidatedItem chi tiết:
    final List<OutboundValidatedItem> validatedList = [];

    for (int i = 0; i < requestedItems.length; i++) {
      final req = requestedItems[i];
      final sku = (req['sku'] ?? '').toString().trim();
      final skuKey = sku.toUpperCase();
      final reqEpc = (req['epc'] ?? '').toString().trim().toUpperCase();
      final productName = (req['productName'] ?? req['name'] ?? 'Sản phẩm').toString().trim();
      final cartonCode = (req['cartonCode'] ?? '--').toString().trim();
      final palletCode = (req['palletCode'] ?? '--').toString().trim();
      final palletEpc = (req['palletEpc'] ?? '--').toString().trim();
      final supplier = (req['supplier'] ?? '--').toString().trim();
      final customer = (req['customer'] ?? '--').toString().trim();

      final matchedItem = matchedByIndex[i];

      if (matchedItem != null) {
        // Tìm vị trí kệ
        String locCode = '--';
        if (matchedItem.locationId != null && locationCodeMap.containsKey(matchedItem.locationId)) {
          locCode = locationCodeMap[matchedItem.locationId]!;
        } else if (matchedItem.palletId != null && palletLocationMap.containsKey(matchedItem.palletId)) {
          locCode = palletLocationMap[matchedItem.palletId]!;
        }

        // Tính thứ tự ưu tiên FIFO trong các món của cùng SKU này trong kho
        final effectiveSkuKey = matchedItem.sku.trim().toUpperCase();
        final allSkuStock = inStockBySku[effectiveSkuKey] ?? inStockBySku[skuKey] ?? [];
        final fifoIndex = allSkuStock.indexWhere((it) => it.itemId == matchedItem.itemId);
        final fifoPriority = fifoIndex >= 0 ? (fifoIndex + 1) : 1;

        String? fifoWarning;
        if (fifoIndex > 0) {
          fifoWarning = 'Không phải lô nhập cũ nhất (còn $fifoIndex sản phẩm cũ hơn trong kho)';
        }

        final itemInboundTime = getItemInboundTime(matchedItem);

        final effectivePalletCode = (matchedItem.palletId != null && matchedItem.palletId!.isNotEmpty && matchedItem.palletId != '--')
            ? matchedItem.palletId!
            : palletCode;
        String effectivePalletEpc = palletEpc;
        if ((effectivePalletEpc.isEmpty || effectivePalletEpc == '--') && effectivePalletCode.isNotEmpty && effectivePalletCode != '--') {
          final cleanP = effectivePalletCode.toUpperCase();
          final pal = _pallets.where((p) => p.palletCode.toUpperCase() == cleanP || p.palletId.toUpperCase() == cleanP).firstOrNull;
          if (pal?.rfidEpc != null && pal!.rfidEpc!.isNotEmpty) {
            effectivePalletEpc = pal.rfidEpc!;
          }
        }

        validatedList.add(OutboundValidatedItem(
          sku: matchedItem.sku.isNotEmpty ? matchedItem.sku : sku,
          productId: matchedItem.productId.isNotEmpty ? matchedItem.productId : (req['productId']?.toString() ?? sku),
          productName: matchedItem.productName.isNotEmpty ? matchedItem.productName : productName,
          cartonCode: (matchedItem.cartonCode != null && matchedItem.cartonCode!.isNotEmpty && matchedItem.cartonCode != '--')
              ? matchedItem.cartonCode!
              : cartonCode,
          palletCode: effectivePalletCode,
          supplier: supplier.isNotEmpty && supplier != '--' ? supplier : (matchedItem.supplier ?? '--'),
          customer: customer,
          palletEpc: effectivePalletEpc,
          epc: reqEpc.isNotEmpty && reqEpc != '--' ? reqEpc : matchedItem.epc.toUpperCase(),
          isInStock: true,
          locationCode: locCode,
          inboundTime: itemInboundTime,
          fifoPriority: fifoPriority,
          fifoWarning: fifoWarning,
          matchedItemId: matchedItem.itemId,
          serialNumber: matchedItem.serialNumber,
        ));
      } else {
        // Hết hàng tồn kho hoặc đã xuất trước đó cho món này
        final reqSn = (req['serialNumber'] ?? req['sn'])?.toString().trim();
        final shipped = findShippedItem(epc: reqEpc, serialNumber: reqSn);
        final isShipped = shipped != null;

        validatedList.add(OutboundValidatedItem(
          sku: sku,
          productId: (req['productId'] ?? sku).toString().trim(),
          productName: productName,
          cartonCode: cartonCode,
          palletCode: palletCode,
          supplier: supplier,
          customer: customer,
          palletEpc: palletEpc,
          epc: reqEpc.isNotEmpty ? reqEpc : '--',
          serialNumber: (reqSn != null && reqSn.isNotEmpty) ? reqSn : (shipped?.serialNumber ?? '--'),
          isInStock: false,
          isAlreadyShipped: isShipped,
          locationCode: '--',
          inboundTime: null,
          fifoPriority: 999,
          fifoWarning: isShipped
              ? '🚨 LỖI TRÙNG EPC/SN: Hàng hóa [${shipped.productName}] (SN: ${shipped.serialNumber.isNotEmpty ? shipped.serialNumber : "--"}, EPC: ${shipped.epc}) ĐÃ ĐƯỢC XUẤT KHO TRƯỚC ĐÓ!'
              : 'Không đủ hàng tồn trong kho để xuất!',
          matchedItemId: null,
        ));
      }
    }

    // 4. Sắp xếp danh sách theo ngày nhập xa nhất / cũ nhất trước (chuẩn FIFO)
    validatedList.sort((a, b) {
      if (a.isInStock && !b.isInStock) return -1;
      if (!a.isInStock && b.isInStock) return 1;
      if (a.isInStock && b.isInStock) {
        final timeA = a.inboundTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final timeB = b.inboundTime ?? DateTime.fromMillisecondsSinceEpoch(0);
        final cmp = timeA.compareTo(timeB);
        if (cmp != 0) return cmp;
      }
      return 0;
    });

    // 5. Tính toán lượng thiếu hụt thực tế
    final missingItems = validatedList.where((v) => !v.isInStock).toList();
    final int shortageCount = missingItems.length;
    final Map<String, int> shortageBySku = {};
    for (var m in missingItems) {
      final key = m.sku.isNotEmpty && m.sku != '--' ? m.sku : m.productName;
      shortageBySku[key] = (shortageBySku[key] ?? 0) + 1;
    }

    final bool isStockSufficient = (shortageCount == 0);
    final bool hasShippedConflict = validatedList.any((v) => v.isAlreadyShipped);

    return OutboundInventoryValidationResult(
      isStockSufficient: isStockSufficient && !hasShippedConflict,
      totalRequested: requestedItems.length,
      totalInStock: availableStockItems.length,
      shortageCount: shortageCount,
      shortageBySku: shortageBySku,
      items: validatedList,
      hasShippedConflict: hasShippedConflict,
    );
  }

  /// Xác nhận xuất kho đối soát qua cổng RFID Gate (Hàng + Pallet)
  Future<int> confirmGateOutbound({
    String? orderId,
    required String poNo,
    required String customer,
    required List<String> scannedEpcs,
    String performedBy = 'Cổng RFID Gate Outbound',
  }) async {
    final uniqueEpcs = scannedEpcs.toSet().toList();
    if (uniqueEpcs.isEmpty) return 0;
    final now = DateTime.now();

    int updatedCount = 0;
    final List<Item> affectedItems = [];

    // Ghi nhận vị trí kệ ban đầu của từng sản phẩm trước khi xuất kho
    final Map<String, String> itemOrigLocations = {};
    for (var epc in uniqueEpcs) {
      final item = _items.where((it) => it.epc.toUpperCase() == epc.toUpperCase()).firstOrNull;
      if (item != null) {
        final loc = resolveItemLocation(item);
        if (loc != null) {
          itemOrigLocations[item.itemId] = loc.locationCode;
        } else if (item.locationId != null && item.locationId!.trim().isNotEmpty) {
          itemOrigLocations[item.itemId] = item.locationId!.trim();
        }
      }
    }

    for (var epc in uniqueEpcs) {
      final item = _items.where((it) => it.epc.toUpperCase() == epc.toUpperCase()).firstOrNull;
      if (item != null) {
        item.status = ItemStatus.out;
        item.locationId = null;
        item.orderNo = poNo;
        affectedItems.add(item);
        final oldPalletId = item.palletId;
        item.palletId = null;
        if (oldPalletId != null && oldPalletId.trim().isNotEmpty) {
          final cleanPal = oldPalletId.trim().toUpperCase();
          final pal = _pallets.where((p) => p.palletId.trim().toUpperCase() == cleanPal || p.palletCode.trim().toUpperCase() == cleanPal).firstOrNull;
          if (pal != null) {
            pal.itemIds.remove(item.itemId);
            final remainingInStock = _items.where((it) =>
              it.palletId?.trim().toUpperCase() == cleanPal &&
              it.status == ItemStatus.inStock &&
              it.itemId != item.itemId
            ).length;
            if (remainingInStock == 0 && pal.itemIds.isEmpty) {
              final oldLocId = pal.locationId;
              pal.locationId = null;
              await _dbService.insertPallet(pal);
              await _syncDirectOrQueue(
                tableName: 'pallets',
                recordId: pal.palletId,
                action: 'UPDATE',
                payload: {
                  'pallet_id': pal.palletId,
                  'location_id': null,
                  'updated_at': now.toIso8601String(),
                },
              );
              if (oldLocId != null && oldLocId.trim().isNotEmpty) {
                final cleanLoc = oldLocId.trim().toUpperCase();
                final loc = _locations.where((l) =>
                  l.locationId.trim().toUpperCase() == cleanLoc ||
                  l.locationCode.trim().toUpperCase() == cleanLoc
                ).firstOrNull;
                if (loc != null) {
                  loc.currentPallets = _pallets.where((p) =>
                    p.locationId?.trim().toUpperCase() == loc.locationId.toUpperCase() ||
                    p.locationId?.trim().toUpperCase() == loc.locationCode.toUpperCase()
                  ).length;
                  await _dbService.insertLocation(loc);
                }
              }
            }
          }
        }
        await _dbService.updateItemStatus(item.epc, ItemStatus.out);
        await _dbService.updateItemLocationAndPallet(item.epc, null, null, status: ItemStatus.out.code);
        await _dbService.insertItem(item);
        await _syncDirectOrQueue(
          tableName: 'items',
          recordId: item.itemId,
          action: 'UPDATE',
          payload: {
            'item_id': item.itemId,
            'status': ItemStatus.out.code,
            'location_id': null,
            'pallet_id': null,
            'updated_at': now.toIso8601String(),
          },
        );
        await recordTagLifecycle(
          epc: item.epc,
          itemId: item.itemId,
          sku: item.sku,
          productName: item.productName,
          serialNumber: item.serialNumber,
          action: TagLifecycleAction.outboundPda,
          previousStatus: ItemStatus.inStock.label,
          newStatus: ItemStatus.out.label,
          fromLocation: item.locationId,
          fromPallet: oldPalletId,
          documentNo: poNo,
          performedBy: performedBy,
          device: 'SEUIC UTouch 2 PDA',
          notes: 'Xuất lẻ PDA theo đơn $poNo',
        );
        updatedCount++;
      }
    }

    final outboundId = 'OUT-${now.millisecondsSinceEpoch}';

    // Phân rã danh sách chi tiết hàng hóa xuất kho thực tế theo SKU từ các chip đã quét
    final Map<String, OutboundOrderDetail> detailsBySku = {};
    for (var it in affectedItems) {
      final sku = it.sku.isNotEmpty ? it.sku : 'MULTI';
      final pName = getSkuProductName(sku, it.productName.isNotEmpty ? it.productName : 'Sản phẩm xuất kho');
      final pId = it.productId.isNotEmpty ? it.productId : sku;
      final cleanSn = (it.serialNumber.trim().isNotEmpty && it.serialNumber.trim() != '--') ? it.serialNumber.trim() : null;
      if (!detailsBySku.containsKey(sku)) {
        detailsBySku[sku] = OutboundOrderDetail(
          productId: pId,
          sku: sku,
          productName: pName,
          requiredQty: 1,
          pickedQty: 1,
          epcList: [it.epc],
          snList: cleanSn != null ? [cleanSn] : [],
        );
      } else {
        final cur = detailsBySku[sku]!;
        detailsBySku[sku] = OutboundOrderDetail(
          productId: cur.productId,
          sku: cur.sku,
          productName: cur.productName,
          requiredQty: cur.requiredQty + 1,
          pickedQty: cur.pickedQty + 1,
          epcList: [...?cur.epcList, it.epc],
          snList: [...?cur.snList, ?cleanSn],
        );
      }
    }

    if (detailsBySku.isEmpty) {
      detailsBySku['MULTI'] = OutboundOrderDetail(
        productId: 'MULTI',
        sku: 'MULTI',
        productName: 'Xuất kho cổng RFID',
        requiredQty: uniqueEpcs.length,
        pickedQty: uniqueEpcs.length,
        epcList: uniqueEpcs,
      );
    }
    final orderDetails = detailsBySku.values.toList();

    final cleanOrderUpper = (orderId ?? '').trim().toUpperCase();
    final cleanPoUpper = poNo.trim().toUpperCase();
    var existingOrder = _outboundOrders.where((o) =>
        (cleanOrderUpper.isNotEmpty && o.outboundOrderId.trim().toUpperCase() == cleanOrderUpper) ||
        (cleanPoUpper.isNotEmpty &&
         (o.poNo.trim().toUpperCase() == cleanPoUpper ||
          o.outboundOrderId.trim().toUpperCase() == cleanPoUpper))).firstOrNull;

    late final OutboundOrder targetOrder;
    if (existingOrder != null) {
      if (existingOrder.details.isEmpty) {
        existingOrder.details.addAll(orderDetails);
      } else {
        for (var d in existingOrder.details) {
          final countForThisSku = affectedItems.where((it) => it.sku.toUpperCase() == d.sku.toUpperCase()).length;
          if (countForThisSku > 0) {
            d.pickedQty = (d.pickedQty + countForThisSku).clamp(0, d.requiredQty);
          }
        }
      }
      final isAllPicked = existingOrder.details.every((d) => d.pickedQty >= d.requiredQty);
      existingOrder.status = isAllPicked ? OutboundOrderStatus.shipped : OutboundOrderStatus.processing;
      targetOrder = existingOrder;
      await _dbService.insertOutboundOrder(existingOrder);
      await _syncDirectOrQueue(
        tableName: 'outbound_orders',
        recordId: existingOrder.outboundOrderId,
        action: 'UPDATE',
        payload: {
          'outbound_order_id': existingOrder.outboundOrderId,
          'status': targetOrder.status.code,
        },
      );
    } else {
      final newOrder = OutboundOrder(
        outboundOrderId: outboundId,
        poNo: poNo,
        customer: customer,
        status: OutboundOrderStatus.shipped,
        createdAt: now,
        details: orderDetails,
      );
      targetOrder = newOrder;
      _outboundOrders.insert(0, newOrder);
      await _dbService.insertOutboundOrder(newOrder);
      await _syncDirectOrQueue(
        tableName: 'outbound_orders',
        recordId: newOrder.outboundOrderId,
        action: 'INSERT',
        payload: {
          'outbound_order_id': newOrder.outboundOrderId,
          'po_no': newOrder.poNo,
          'customer': newOrder.customer,
          'status': newOrder.status.code,
          'created_at': newOrder.createdAt.toIso8601String(),
        },
      );
    }

    // Dọn dẹp các đơn nháp cùng mã đơn hoặc cùng orderId để không bị tồn tại 2 đơn
    final cleanTargetPo = targetOrder.poNo.trim().toUpperCase();
    final cleanTargetId = targetOrder.outboundOrderId.trim().toUpperCase();
    final redundantDrafts = _outboundOrders.where((o) {
      if (o.outboundOrderId == targetOrder.outboundOrderId) return false;
      if (o.status != OutboundOrderStatus.newOrder) return false;
      final samePo = cleanTargetPo.isNotEmpty && o.poNo.trim().toUpperCase() == cleanTargetPo;
      final sameId = cleanTargetId.isNotEmpty && o.outboundOrderId.trim().toUpperCase() == cleanTargetId;
      return samePo || sameId;
    }).toList();
    for (final dup in redundantDrafts) {
      _outboundOrders.removeWhere((o) => o.outboundOrderId == dup.outboundOrderId);
      await _dbService.deleteOutboundOrder(dup.outboundOrderId);
    }

    // Ghi nhận trực tiếp chi tiết đơn xuất kho vào Supabase nếu kết nối trực tuyến
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final supa = Supabase.instance.client;
        for (final dup in redundantDrafts) {
          await supa.from('outbound_order_details').delete().eq('order_id', dup.outboundOrderId);
          await supa.from('outbound_orders').delete().eq('outbound_order_id', dup.outboundOrderId);
        }
        await supa.from('outbound_orders').upsert({
          'outbound_order_id': targetOrder.outboundOrderId,
          'po_no': targetOrder.poNo,
          'customer': targetOrder.customer,
          'status': targetOrder.status.code,
          'created_at': targetOrder.createdAt.toIso8601String(),
        });
        final validProductIds = _products.map((p) => p.productId).toSet();
        final detailRows = <Map<String, dynamic>>[];
        for (final d in targetOrder.details) {
          final pid = validProductIds.contains(d.productId)
              ? d.productId
              : (_products.where((p) => p.sku == d.sku).firstOrNull?.productId);
          if (pid != null) {
            detailRows.add({
              'order_id': targetOrder.outboundOrderId,
              'product_id': pid,
              'sku': d.sku,
              'product_name': getSkuProductName(d.sku, d.productName),
              'required_qty': d.requiredQty,
              'picked_qty': d.pickedQty,
            });
          }
        }
        if (detailRows.isNotEmpty) {
          await supa.from('outbound_order_details').delete().eq('order_id', targetOrder.outboundOrderId);
          if (targetOrder.poNo.isNotEmpty && targetOrder.poNo != targetOrder.outboundOrderId) {
            await supa.from('outbound_order_details').delete().eq('order_id', targetOrder.poNo);
          }
          await supa.from('outbound_order_details').insert(detailRows);
        }
      } catch (e) {
        debugPrint('confirmGateOutbound Supabase sync detail error: $e');
      }
    }

    final fromLocSet = itemOrigLocations.values.where((l) => l.isNotEmpty && l != '--').toSet();
    final fromLocStr = fromLocSet.isNotEmpty ? fromLocSet.join(', ') : 'KHO_TONG';
    final isPda = performedBy.contains('PDA') || performedBy.contains('Tay Cầm');

    final tx = InventoryTransaction(
      transactionId: 'TX-OUT-GATE-${now.millisecondsSinceEpoch}-$poNo',
      type: TransactionType.outbound,
      documentNo: poNo,
      sku: affectedItems.length == 1 ? affectedItems.first.sku : 'MULTI-SKU',
      productName: affectedItems.length == 1 ? affectedItems.first.productName : 'Xuất kho RFID',
      quantity: uniqueEpcs.length,
      fromLocation: fromLocStr,
      toLocation: customer,
      performedBy: performedBy,
      timestamp: now,
      notes: isPda
          ? 'Xuất hàng lẻ $updatedCount sản phẩm theo vị trí kệ: $fromLocStr qua PDA'
          : 'Xuất $updatedCount sản phẩm qua cổng RFID Gate (vị trí: $fromLocStr)',
    );
    _transactions.insert(0, tx);

    await _syncInventoryTransaction(tx);
    _triggerBackgroundSync();

    notifyListeners();
    return updatedCount > 0 ? updatedCount : uniqueEpcs.length;
  }

  /// Lấy danh sách toàn bộ các mã Serial Number (SN) của hàng hóa đã xuất kho theo đơn
  List<String> getOrderShippedSerialNumbers(OutboundOrder ord) {
    final result = <String>[];
    final cleanPo = ord.poNo.trim().toUpperCase();
    final cleanId = ord.outboundOrderId.trim().toUpperCase();

    // 1. Quét từ bảng items đã xuất theo orderNo
    for (final it in _items) {
      final oNo = it.orderNo?.trim().toUpperCase();
      if (oNo != null && (oNo == cleanPo || oNo == cleanId)) {
        final sn = it.serialNumber.trim();
        if (sn.isNotEmpty && sn != '--' && !result.contains(sn)) {
          result.add(sn);
        }
      }
    }

    // 2. Quét từ details.snList của đơn hàng
    for (final d in ord.details) {
      if (d.snList != null) {
        for (final sn in d.snList!) {
          final s = sn.trim();
          if (s.isNotEmpty && s != '--' && !result.contains(s)) {
            result.add(s);
          }
        }
      }
    }

    // 3. Quét từ epcList trong details của đơn hàng để map sang items
    for (final d in ord.details) {
      if (d.epcList != null) {
        for (final epc in d.epcList!) {
          final it = _items.where((i) => i.epc.trim().toUpperCase() == epc.trim().toUpperCase()).firstOrNull;
          final sn = it?.serialNumber.trim();
          if (sn != null && sn.isNotEmpty && sn != '--' && !result.contains(sn)) {
            result.add(sn);
          }
        }
      }
    }

    // 4. Quét từ tag lifecycle logs theo documentNo
    for (final log in _tagLifecycleLogs) {
      final doc = log.documentNo?.trim().toUpperCase();
      if (doc != null && (doc == cleanPo || doc == cleanId)) {
        final sn = log.serialNumber?.trim();
        if (sn != null && sn.isNotEmpty && sn != '--' && !result.contains(sn)) {
          result.add(sn);
        }
      }
    }

    return result;
  }

  /// Lấy danh sách mã Serial Number (SN) của một SKU cụ thể đã xuất trong đơn
  List<String> getOrderSkuShippedSerialNumbers(OutboundOrder ord, String sku) {
    final result = <String>[];
    final cleanSku = sku.trim().toUpperCase();
    final cleanPo = ord.poNo.trim().toUpperCase();
    final cleanId = ord.outboundOrderId.trim().toUpperCase();

    // 1. Quét từ bảng items đã xuất theo SKU và orderNo
    for (final it in _items) {
      if (it.sku.trim().toUpperCase() == cleanSku) {
        final oNo = it.orderNo?.trim().toUpperCase();
        if (oNo != null && (oNo == cleanPo || oNo == cleanId)) {
          final sn = it.serialNumber.trim();
          if (sn.isNotEmpty && sn != '--' && !result.contains(sn)) {
            result.add(sn);
          }
        }
      }
    }

    // 2. Quét từ details.snList của SKU này trong đơn
    for (final d in ord.details) {
      if (d.sku.trim().toUpperCase() == cleanSku && d.snList != null) {
        for (final sn in d.snList!) {
          final s = sn.trim();
          if (s.isNotEmpty && s != '--' && !result.contains(s)) {
            result.add(s);
          }
        }
      }
    }

    // 3. Quét từ epcList của SKU này trong đơn
    for (final d in ord.details) {
      if (d.sku.trim().toUpperCase() == cleanSku && d.epcList != null) {
        for (final epc in d.epcList!) {
          final it = _items.where((i) => i.epc.trim().toUpperCase() == epc.trim().toUpperCase()).firstOrNull;
          final sn = it?.serialNumber.trim();
          if (sn != null && sn.isNotEmpty && sn != '--' && !result.contains(sn)) {
            result.add(sn);
          }
        }
      }
    }

    // 4. Quét từ tag lifecycle logs
    for (final log in _tagLifecycleLogs) {
      if (log.sku?.trim().toUpperCase() == cleanSku) {
        final doc = log.documentNo?.trim().toUpperCase();
        if (doc != null && (doc == cleanPo || doc == cleanId)) {
          final sn = log.serialNumber?.trim();
          if (sn != null && sn.isNotEmpty && sn != '--' && !result.contains(sn)) {
            result.add(sn);
          }
        }
      }
    }

    return result;
  }


  /// Tra cứu vị trí kệ kho thực tế của sản phẩm (hỗ trợ cả hàng lẻ và hàng trên Pallet)
  Location? resolveItemLocation(Item it) {
    if (it.status == ItemStatus.out) return null;
    String? rawLocId = it.locationId;
    if ((rawLocId == null || rawLocId.trim().isEmpty) && it.palletId != null && it.palletId!.trim().isNotEmpty) {
      final pClean = it.palletId!.trim().toUpperCase();
      final pal = _pallets.where((p) => p.palletId.toUpperCase() == pClean || p.palletCode.toUpperCase() == pClean).firstOrNull;
      rawLocId = pal?.locationId;
    }
    if (rawLocId == null || rawLocId.trim().isEmpty) return null;
    final clean = rawLocId.trim().toUpperCase();
    return _locations.where((l) =>
      l.locationId.toUpperCase() == clean ||
      l.locationCode.toUpperCase() == clean ||
      l.locationId.toUpperCase().replaceAll('LOC-', '') == clean.replaceAll('LOC-', '') ||
      l.locationCode.toUpperCase().replaceAll('LOC-', '') == clean.replaceAll('LOC-', '')
    ).firstOrNull;
  }

  InventorySession startInventorySession({
    required String zone,
    String? locationCode,
    List<String>? targetSkus,
    String? assignedToUserId,
    String? assignedToName,
    String? assignedBy,
    String? notes,
  }) {
    final session = InventorySession(
      sessionId: 'SESS-${DateTime.now().millisecondsSinceEpoch}',
      sessionCode: 'KK-${DateTime.now().month}${DateTime.now().day}-${Random().nextInt(900) + 100}',
      zone: zone,
      locationCode: locationCode,
      startedAt: DateTime.now(),
      targetSkus: targetSkus,
      assignedToUserId: assignedToUserId,
      assignedToName: assignedToName,
      assignedBy: assignedBy,
      notes: notes,
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
        'is_completed': false,
        'target_skus': session.targetSkus.join(','),
        'assigned_to_user_id': session.assignedToUserId,
        'assigned_to_name': session.assignedToName,
        'created_by': session.assignedBy,
        'notes': session.notes,
      },
    );
    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      unawaited(() async {
        try {
          final supa = SupabaseSyncService().client ?? Supabase.instance.client;
          final meta = <String, dynamic>{
            'by': session.assignedBy ?? 'Thủ kho (Admin)',
          };
          if (session.assignedToUserId != null) meta['to_id'] = session.assignedToUserId;
          if (session.assignedToName != null) meta['to_name'] = session.assignedToName;
          if (session.notes != null) meta['notes'] = session.notes;
          if (session.targetSkus.isNotEmpty) meta['skus'] = session.targetSkus;

          await supa.from('inventory_sessions').upsert({
            'session_id': session.sessionId,
            'session_code': session.sessionCode,
            'zone': session.zone,
            'location_code': session.locationCode,
            'started_at': session.startedAt.toIso8601String(),
            'completed_at': null,
            'is_completed': false,
            'created_by': jsonEncode(meta),
          });
          debugPrint('✓ startInventorySession direct upserted to Supabase: ${session.sessionCode}');
        } catch (e) {
          debugPrint('startInventorySession Supabase direct push error: $e');
        }
      }());
    }
    _triggerBackgroundSync();

    // Nạp sẵn danh sách hàng kỳ vọng trên CSDL tại vị trí này (trạng thái missing ban đầu khi chưa quét)
    processAuditScan(sessionId: session.sessionId, scannedEpcs: []);

    notifyListeners();
    return session;
  }

  void processAuditScan({
    required String sessionId,
    required List<String> scannedEpcs,
    InventorySession? targetSession,
    bool notify = false,
  }) {
    _ensureIndexes();
    final session = targetSession ?? _inventorySessions.where((s) => s.sessionId == sessionId).firstOrNull;
    if (session == null || session.isCompleted) return;
    session.results.clear();

    final uniqueScannedEpcs = scannedEpcs.map((e) => e.trim().toUpperCase()).where((e) => e.isNotEmpty).toSet();

    final isAllWarehouse = session.zone.trim().toLowerCase().contains('toàn bộ') ||
        session.zone.trim().toLowerCase().contains('toàn kho') ||
        session.zone.trim().toLowerCase().contains('tất cả') ||
        session.zone.trim().toUpperCase() == 'ALL' ||
        (session.locationCode == null && session.zone.isEmpty);

    final expectedItems = _items.where((it) {
      if (it.status != ItemStatus.inStock) return false;
      // Nếu là phiếu kiểm kê theo SKU cụ thể: chỉ những mặt hàng có SKU mục tiêu mới là expected
      if (session.isSkuSpecific && !session.targetSkus.contains(it.sku)) {
        return false;
      }
      if (isAllWarehouse) return true;
      final loc = resolveItemLocation(it);
      if (loc == null) return false;

      if (session.locationCode != null && session.locationCode!.trim().isNotEmpty) {
        final target = session.locationCode!.trim().toUpperCase();
        return loc.locationCode.trim().toUpperCase() == target ||
               loc.locationId.trim().toUpperCase() == target ||
               loc.locationId.trim().toUpperCase().replaceAll('LOC-', '') == target.replaceAll('LOC-', '');
      }
      if (session.zone.isNotEmpty) {
        final targetZone = session.zone.trim().toUpperCase();
        return loc.zone.trim().toUpperCase() == targetZone ||
               loc.locationCode.trim().toUpperCase().startsWith(targetZone);
      }
      return false;
    }).toList();

    final expectedEpcs = expectedItems.map((e) => e.epc.toUpperCase()).toSet();

    final currentAuditLoc = session.locationCode != null && session.locationCode!.trim().isNotEmpty
        ? _locations.where((l) => l.locationCode == session.locationCode || l.locationId == session.locationCode).firstOrNull
        : null;
    final currentAuditLocDisplay = currentAuditLoc != null
        ? '${currentAuditLoc.locationCode} • ${currentAuditLoc.displayName}'
        : (session.locationCode != null && session.locationCode!.trim().isNotEmpty
            ? session.locationCode!
            : (session.zone.isNotEmpty ? session.zone : 'Toàn bộ kho'));

    for (var epc in uniqueScannedEpcs) {
      final item = _itemsByEpcIndex[epc] ?? _items.where((it) => it.epc.toUpperCase() == epc).firstOrNull;

      if (item == null || item.sku == 'UNKNOWN' || item.itemId.isEmpty) {
        if (session.isSkuSpecific) continue;
        session.results.add(
          InventoryItemResult(
            epc: epc,
            resultType: InventoryVarianceType.unknownEpc,
            readAt: DateTime.now(),
          ),
        );
      } else if (item.status == ItemStatus.out) {
        // Hàng hóa này đã làm thủ tục xuất kho trước đó nhưng vẫn quét thấy chip trong kho
        if (session.isSkuSpecific && !session.targetSkus.contains(item.sku)) {
          continue;
        }
        session.results.add(
          InventoryItemResult(
            epc: item.epc,
            sku: item.sku,
            productName: item.productName,
            expectedLocation: 'ĐÃ XUẤT KHO',
            actualLocation: currentAuditLocDisplay,
            resultType: InventoryVarianceType.unknownEpc,
            readAt: DateTime.now(),
          ),
        );
      } else if (session.isSkuSpecific) {
        // Đơn kiểm kê theo từng mặt hàng cụ thể (SKU):
        // Chỉ cần biết là có đủ hay không (số lượng quét vs tồn CSDL).
        // Còn chip thuộc SKU khác (từ kho khác, kệ khác) thì BỎ QUA HOÀN TOÀN.
        if (!session.targetSkus.contains(item.sku)) {
          continue;
        }

        final actualLoc = resolveItemLocation(item);
        final locDisplay = actualLoc?.displayName ?? (actualLoc?.locationCode ?? item.locationId ?? currentAuditLocDisplay);
        session.results.add(
          InventoryItemResult(
            epc: item.epc,
            sku: item.sku,
            productName: item.productName,
            expectedLocation: locDisplay,
            actualLocation: currentAuditLocDisplay,
            resultType: InventoryVarianceType.match,
            readAt: DateTime.now(),
          ),
        );
      } else if (isAllWarehouse || expectedEpcs.contains(item.epc.toUpperCase())) {
        final actualLoc = resolveItemLocation(item);
        final locDisplay = actualLoc?.displayName ?? (actualLoc?.locationCode ?? item.locationId ?? currentAuditLocDisplay);
        session.results.add(
          InventoryItemResult(
            epc: item.epc,
            sku: item.sku,
            productName: item.productName,
            expectedLocation: locDisplay,
            actualLocation: currentAuditLocDisplay,
            resultType: InventoryVarianceType.match,
            readAt: DateTime.now(),
          ),
        );
      } else {
        // Thuộc KỆ KHÁC / KHO KHÁC trong database (Sai vị trí)
        final actualLoc = resolveItemLocation(item);
        final originLocDisplay = actualLoc != null
            ? '${actualLoc.locationCode} • ${actualLoc.displayName} (${actualLoc.zone})'
            : (item.locationId ?? 'Kệ khác / Chưa gán');

        session.results.add(
          InventoryItemResult(
            epc: item.epc,
            sku: item.sku,
            productName: item.productName,
            expectedLocation: originLocDisplay, // Vị trí gốc trong CSDL
            actualLocation: currentAuditLocDisplay, // Vị trí đang quét thực tế
            resultType: InventoryVarianceType.wrongLocation,
            readAt: DateTime.now(),
          ),
        );
      }
    }

    for (var expItem in expectedItems) {
      if (!uniqueScannedEpcs.contains(expItem.epc.trim().toUpperCase())) {
        final loc = resolveItemLocation(expItem);
        final locDisplay = loc != null ? '${loc.locationCode} • ${loc.displayName}' : (expItem.locationId ?? currentAuditLocDisplay);
        session.results.add(
          InventoryItemResult(
            epc: expItem.epc,
            sku: expItem.sku,
            productName: expItem.productName,
            expectedLocation: locDisplay,
            actualLocation: 'Chưa quét thấy',
            resultType: InventoryVarianceType.missing,
            readAt: DateTime.now(),
          ),
        );
      }
    }

    // Sắp xếp danh sách kết quả ổn định tuyệt đối (Deterministic Stable Sort):
    // 1. Phân loại theo nhóm nghiệp vụ: wrongLocation / unknownEpc -> match / missing.
    // 2. Trong cùng nhóm: giữ nguyên vị trí cố định theo Mã SKU -> Tên sản phẩm -> Mã EPC.
    // Nhờ đó, khi chip RFID được quét trúng, thẻ chỉ chuyển trạng thái từ "Chưa quét" sang "Đã quét"
    // mà KHÔNG bao giờ bị nhảy lung tung, xáo trộn thứ tự trên màn hình PDA!
    session.results.sort((a, b) {
      int typeOrder(InventoryVarianceType t) {
        switch (t) {
          case InventoryVarianceType.wrongLocation:
            return 0;
          case InventoryVarianceType.unknownEpc:
            return 1;
          case InventoryVarianceType.match:
          case InventoryVarianceType.missing:
            return 2;
        }
      }

      final tA = typeOrder(a.resultType);
      final tB = typeOrder(b.resultType);
      if (tA != tB) return tA.compareTo(tB);

      final skuCmp = (a.sku ?? '').compareTo(b.sku ?? '');
      if (skuCmp != 0) return skuCmp;

      final nameCmp = (a.productName ?? '').compareTo(b.productName ?? '');
      if (nameCmp != 0) return nameCmp;

      return a.epc.toUpperCase().compareTo(b.epc.toUpperCase());
    });

    // Đồng bộ ngược lại cho session trong danh mục repo nếu targetSession là instance bên ngoài
    final repoSession = _inventorySessions.where((s) => s.sessionId == sessionId).firstOrNull;
    if (targetSession != null && repoSession != null && targetSession != repoSession) {
      repoSession.results
        ..clear()
        ..addAll(session.results);
    }

    _dbService.insertInventorySession(session);
    if (notify) {
      notifyListeners();
    }
  }

  void _sanitizeSessionResults(InventorySession s) {
    if (s.isSkuSpecific) {
      s.results.removeWhere((r) =>
          r.sku == null ||
          !s.targetSkus.contains(r.sku) ||
          r.resultType == InventoryVarianceType.unknownEpc ||
          r.resultType == InventoryVarianceType.wrongLocation);
    }
  }

  Future<void> completeInventorySession(String sessionId, String approvedBy) async {
    final session = _inventorySessions.firstWhere((s) => s.sessionId == sessionId);
    session.isCompleted = true;
    session.completedAt = DateTime.now();

    _sanitizeSessionResults(session);
    // 1. Lưu DatabaseService
    await _dbService.insertInventorySession(session);

    final tx = InventoryTransaction(
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
    );
    _transactions.insert(0, tx);
    await _syncInventoryTransaction(tx);

    // 2. Đồng bộ Supabase qua hàng đợi nền (cực nhanh, không block UI thread)
    await _syncDirectOrQueue(
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
        'is_completed': true,
        'created_by': approvedBy,
        'target_skus': session.targetSkus.join(','),
      },
    );

    if (!Platform.environment.containsKey('FLUTTER_TEST')) {
      try {
        final supa = SupabaseSyncService().client ?? Supabase.instance.client;
        final detailRows = session.results.map((r) => {
          'session_id': session.sessionId,
          'epc': r.epc,
          'sku': r.sku,
          'product_name': r.productName,
          'expected_location': r.expectedLocation,
          'actual_location': r.actualLocation,
          'result_type': r.resultType.code,
          'read_at': r.readAt.toIso8601String(),
        }).toList();
        await supa.from('inventory_session_details').delete().eq('session_id', session.sessionId);
        if (detailRows.isNotEmpty) {
          for (var i = 0; i < detailRows.length; i += 50) {
            final chunk = detailRows.sublist(i, i + 50 > detailRows.length ? detailRows.length : i + 50);
            await supa.from('inventory_session_details').insert(chunk);
          }
        }
      } catch (e) {
        debugPrint('completeInventorySession Supabase details error: $e');
      }
    }

    for (final r in session.results) {
      TagLifecycleAction act = TagLifecycleAction.auditMatch;
      String note = 'Kiểm kê kho khớp chuẩn tại ${r.actualLocation ?? session.zone}';
      String prevStatus = ItemStatus.inStock.label;
      String newStatus = ItemStatus.inStock.label;

      if (r.expectedLocation == 'ĐÃ XUẤT KHO') {
        act = TagLifecycleAction.unauthorizedExit;
        prevStatus = ItemStatus.out.label;
        newStatus = ItemStatus.out.label;
        note = '🚨 CẢNH BÁO KIỂM KÊ: Phát hiện chip của hàng đã xuất kho trước đó tồn tại ở ${r.actualLocation}';
      } else if (r.resultType == InventoryVarianceType.wrongLocation) {
        act = TagLifecycleAction.auditMisplaced;
        note = 'Kiểm kê sai vị trí: Sổ sách ở ${r.expectedLocation}, quét tại ${r.actualLocation}';
      } else if (r.resultType == InventoryVarianceType.missing) {
        act = TagLifecycleAction.auditMissing;
        note = 'Kiểm kê phát hiện thiếu thực tế tại ${r.expectedLocation}';
      } else if (r.resultType == InventoryVarianceType.unknownEpc) {
        act = TagLifecycleAction.auditFound;
        note = 'Kiểm kê phát hiện thẻ ngoài danh sách tại ${r.actualLocation}';
      }

      await recordTagLifecycle(
        epc: r.epc,
        sku: r.sku,
        productName: r.productName,
        action: act,
        previousStatus: prevStatus,
        newStatus: newStatus,
        fromLocation: r.expectedLocation,
        toLocation: r.actualLocation,
        documentNo: session.sessionCode,
        performedBy: approvedBy,
        device: 'SEUIC UTouch 2 PDA / Desktop',
        notes: note,
      );
    }

    _triggerBackgroundSync();
    notifyListeners();
  }

  /// Tự động nạp chi tiết kiểm kê nếu phiên chưa hoàn tất và chưa có bản ghi kết quả quét
  void _populateSessionResultsIfEmpty(InventorySession session) {
    if (session.results.isNotEmpty || session.isCompleted) return;
    final isAllWarehouse = session.zone.trim().toLowerCase().contains('toàn bộ') ||
        session.zone.trim().toUpperCase() == 'ALL' ||
        (session.locationCode == null && session.zone.isEmpty);

    final zoneItems = _items.where((it) {
      if (it.status != ItemStatus.inStock) return false;
      if (session.isSkuSpecific && !session.targetSkus.contains(it.sku)) return false;
      if (isAllWarehouse) return true;
      final loc = resolveItemLocation(it);
      if (loc == null) return false;
      if (session.locationCode != null && session.locationCode!.trim().isNotEmpty) {
        final target = session.locationCode!.trim().toUpperCase();
        return loc.locationCode.trim().toUpperCase() == target ||
            loc.locationId.trim().toUpperCase() == target ||
            loc.locationId.trim().toUpperCase().replaceAll('LOC-', '') == target.replaceAll('LOC-', '');
      }
      if (session.zone.isNotEmpty) {
        final targetZone = session.zone.trim().toUpperCase();
        return loc.zone.trim().toUpperCase() == targetZone ||
            loc.locationCode.trim().toUpperCase().startsWith(targetZone) ||
            targetZone.contains(loc.zone.trim().toUpperCase()) ||
            loc.zone.trim().toUpperCase().contains(targetZone);
      }
      return false;
    }).toList();

    for (final it in zoneItems) {
      session.results.add(InventoryItemResult(
        epc: it.epc,
        sku: it.sku,
        productName: it.productName,
        expectedLocation: session.locationCode ?? session.zone,
        actualLocation: session.locationCode ?? session.zone,
        resultType: session.isCompleted ? InventoryVarianceType.match : InventoryVarianceType.missing,
        readAt: session.completedAt ?? session.startedAt,
      ));
    }
  }

  /// Tính toán bảng đối soát tồn kho: Tồn dự kiến (Sổ sách) vs Tồn thực tế (Kiểm kê)
  List<SkuStockReconciliationRow> getStockReconciliation({
    String? sessionId,
    String? zone,
  }) {
    if (sessionId != null && sessionId.isNotEmpty && sessionId != 'ALL') {
      final session = _inventorySessions.where((s) => s.sessionId == sessionId || s.sessionCode == sessionId).firstOrNull;
      if (session != null) {
        return buildSessionSkuBreakdown(session, zoneFilter: zone);
      }
    }

    // Nếu chọn ALL: Hợp nhất toàn bộ các đợt kiểm kê đã chốt hoặc đã có kết quả quét thực tế
    if (sessionId == 'ALL' && _inventorySessions.isNotEmpty) {
      final completed = _inventorySessions.where((s) => s.isCompleted).toList();
      final targetSessions = completed.isNotEmpty
          ? completed
          : _inventorySessions.where((s) => s.actualScannedCount > 0).toList();
      if (targetSessions.isNotEmpty) {
        final Map<String, InventoryItemResult> mergedResults = {};
        for (final s in targetSessions) {
          if (s.results.isEmpty) {
            _populateSessionResultsIfEmpty(s);
          }
          for (final r in s.results) {
            mergedResults[r.epc.toUpperCase()] = r;
          }
        }
        final virtualSession = InventorySession(
          sessionId: 'ALL_COMBINED',
          sessionCode: 'TOÀN_KHO',
          zone: zone ?? 'Toàn bộ kho',
          startedAt: targetSessions.last.startedAt,
          completedAt: targetSessions.first.completedAt,
          isCompleted: true,
          results: mergedResults.values.toList(),
        );
        return buildSessionSkuBreakdown(virtualSession, zoneFilter: zone);
      }
    }

    // Nếu không chọn session cụ thể hoặc phiên không tìm thấy: Lấy phiên kiểm kê mới nhất đã hoàn thành hoặc đã quét
    if (_inventorySessions.isNotEmpty && sessionId != 'ALL') {
      final latestSession = _inventorySessions.where((s) => s.isCompleted).firstOrNull ??
          _inventorySessions.where((s) => s.actualScannedCount > 0).firstOrNull ??
          _inventorySessions.first;
      return buildSessionSkuBreakdown(latestSession, zoneFilter: zone);
    }

    // Nếu chưa có phiên kiểm kê nào trong CSDL (hoặc chưa có phiên nào được quét):
    // Chỉ hiển thị Tồn Kho Dự Kiến (Sổ sách) — KHÔNG tính lệch thiếu khi chưa kiểm kê!
    final Map<String, List<Item>> itemsBySku = {};
    for (final it in _items) {
      if (it.status != ItemStatus.inStock) continue;
      final loc = resolveItemLocation(it);
      if (zone != null && zone.isNotEmpty && zone != 'ALL') {
        if (loc == null || (!loc.zone.toUpperCase().contains(zone.toUpperCase()) && !loc.locationCode.toUpperCase().startsWith(zone.toUpperCase()))) {
          continue;
        }
      }
      itemsBySku.putIfAbsent(it.sku, () => []).add(it);
    }

    final List<SkuStockReconciliationRow> rows = [];
    for (final entry in itemsBySku.entries) {
      final sku = entry.key;
      final itList = entry.value;
      final p = _products.where((p) => p.sku == sku).firstOrNull;
      final loc = resolveItemLocation(itList.first);
      final locDisplay = loc != null ? '${loc.locationCode} (${loc.zone})' : (itList.first.locationId ?? 'Chưa gán');

      rows.add(SkuStockReconciliationRow(
        sku: sku,
        productName: p?.productName ?? itList.first.productName,
        unit: p?.unit ?? 'SP',
        zoneOrLocation: locDisplay,
        expectedQty: itList.length,
        actualQty: 0,
        matchedCount: 0,
        missingCount: 0,
        wrongLocationCount: 0,
        unknownCount: 0,
        isAudited: false,
        itemResults: itList.map((it) => InventoryItemResult(
          epc: it.epc,
          sku: it.sku,
          productName: it.productName,
          expectedLocation: locDisplay,
          actualLocation: 'Chưa kiểm kê',
          resultType: InventoryVarianceType.missing,
          readAt: DateTime.now(),
        )).toList(),
      ));
    }
    return rows;
  }

  /// Nhóm kết quả của một đợt kiểm kê theo từng SKU
  List<SkuStockReconciliationRow> buildSessionSkuBreakdown(InventorySession session, {String? zoneFilter}) {
    if (session.results.isEmpty) {
      _populateSessionResultsIfEmpty(session);
    }
    final isSessionAudited = session.isCompleted || session.actualScannedCount > 0;
    final Map<String, List<InventoryItemResult>> map = {};
    for (final r in session.results) {
      // Nếu là kiểm kê theo mặt hàng cụ thể (SKU): chỉ quan tâm đến các SKU mục tiêu, bỏ qua chip khác
      if (session.isSkuSpecific && (r.sku == null || !session.targetSkus.contains(r.sku))) {
        continue;
      }
      if (zoneFilter != null && zoneFilter.isNotEmpty && zoneFilter != 'ALL') {
        final locStr = (r.expectedLocation ?? r.actualLocation ?? '').toUpperCase();
        bool match = locStr.contains(zoneFilter.toUpperCase());
        if (!match) {
          final locObj = _locations.where((l) => l.locationCode.toUpperCase() == locStr || l.locationId.toUpperCase() == locStr).firstOrNull;
          if (locObj != null && locObj.zone.toUpperCase().contains(zoneFilter.toUpperCase())) {
            match = true;
          }
        }
        if (!match) continue;
      }
      final sku = (r.sku != null && r.sku!.isNotEmpty)
          ? r.sku!
          : (r.resultType == InventoryVarianceType.unknownEpc ? 'THẺ_LẠ' : 'CHƯA_GÁN');
      map.putIfAbsent(sku, () => []).add(r);
    }

    final List<SkuStockReconciliationRow> rows = [];
    for (final entry in map.entries) {
      final sku = entry.key;
      final list = entry.value;
      final p = _products.where((prod) => prod.sku == sku).firstOrNull;
      final firstWithLoc = list.where((it) => it.expectedLocation != null && it.expectedLocation!.isNotEmpty).firstOrNull;
      final locDisplay = firstWithLoc?.expectedLocation ?? session.locationCode ?? session.zone;

      int expected = 0;
      int actual = 0;
      int matched = 0;
      int missing = 0;
      int wrongLoc = 0;
      int unknown = 0;

      for (final r in list) {
        if (r.resultType != InventoryVarianceType.unknownEpc) {
          expected++;
        }
        if (r.resultType == InventoryVarianceType.match) {
          actual++;
          matched++;
        } else if (r.resultType == InventoryVarianceType.wrongLocation) {
          actual++;
          wrongLoc++;
        } else if (r.resultType == InventoryVarianceType.missing) {
          if (isSessionAudited) {
            missing++;
          }
        } else if (r.resultType == InventoryVarianceType.unknownEpc) {
          actual++;
          unknown++;
        }
      }

      rows.add(SkuStockReconciliationRow(
        sku: sku,
        productName: p?.productName ?? list.first.productName ?? (sku == 'THẺ_LẠ' ? 'Thẻ RFID lạ chưa khai báo' : sku),
        unit: p?.unit ?? 'SP',
        zoneOrLocation: locDisplay,
        expectedQty: expected,
        actualQty: actual,
        matchedCount: matched,
        missingCount: missing,
        wrongLocationCount: wrongLoc,
        unknownCount: unknown,
        isAudited: isSessionAudited,
        itemResults: list,
      ));
    }
    return rows;
  }

  bool movePallet({
    required String palletId,
    required String newLocationId,
    required String performedBy,
  }) {
    final pallet = _pallets.firstWhere((p) => p.palletId == palletId);
    final oldLocation = _locations.firstWhere((l) => l.locationId == pallet.locationId, orElse: () => Location(locationId: '', locationCode: 'N/A', zone: '', shelf: '', level: ''));
    final newLocation = _locations.where((l) => l.locationId == newLocationId || l.locationCode == newLocationId).firstOrNull;

    pallet.locationId = newLocationId;
    pallet.placedBy = performedBy;
    pallet.inboundTime = DateTime.now();
    _dbService.updatePalletLocation(palletId, newLocationId);
    _dbService.insertPallet(pallet);
    if (oldLocation.currentPallets > 0) oldLocation.currentPallets--;
    if (newLocation != null) newLocation.currentPallets++;

    for (var itemId in pallet.itemIds) {
      final item = _items.firstWhere((it) => it.itemId == itemId);
      item.locationId = newLocationId;
      _dbService.updateItemLocationAndPallet(item.epc, newLocationId, palletId);

      recordTagLifecycle(
        epc: item.epc,
        itemId: item.itemId,
        sku: item.sku,
        productName: item.productName,
        serialNumber: item.serialNumber,
        action: TagLifecycleAction.transferLocation,
        previousStatus: ItemStatus.inStock.label,
        newStatus: ItemStatus.inStock.label,
        fromLocation: oldLocation.displayName,
        toLocation: newLocation?.displayName ?? newLocationId,
        fromPallet: pallet.displayName,
        toPallet: pallet.displayName,
        performedBy: performedBy,
        device: 'Desktop WMS / PDA',
        notes: 'Di chuyển Pallet ${pallet.displayName} từ ${oldLocation.displayName} sang ${newLocation?.displayName ?? newLocationId}',
      );
    }

    final tx = InventoryTransaction(
      transactionId: 'TX-MOVE-${DateTime.now().millisecondsSinceEpoch}',
      type: TransactionType.movement,
      documentNo: pallet.palletCode,
      sku: 'PALLET_${pallet.palletCode}',
      productName: 'Di chuyển ${pallet.itemIds.length} Items',
      quantity: pallet.itemIds.length,
      fromLocation: oldLocation.locationCode,
      toLocation: newLocation?.locationCode ?? newLocationId,
      palletCode: pallet.palletCode,
      performedBy: performedBy,
      timestamp: DateTime.now(),
      notes: 'Di chuyển Pallet từ ${oldLocation.locationCode} sang ${newLocation?.locationCode ?? newLocationId}',
    );
    _transactions.insert(0, tx);
    _syncInventoryTransaction(tx);

    _syncDirectOrQueue(
      tableName: 'pallet_moves',
      recordId: palletId,
      action: 'PALLET_MOVE',
      payload: {
        'palletId': palletId,
        'palletCode': pallet.palletCode,
        'fromLocation': oldLocation.locationCode,
        'toLocation': newLocation?.locationCode ?? newLocationId,
        'itemCount': pallet.itemIds.length,
        'performedBy': performedBy,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    _triggerBackgroundSync();

    notifyListeners();
    return true;
  }

  /// Chuyển kho PDA: tìm pallet qua EPC chip của pallet, cập nhật location_id
  /// cho pallet và toàn bộ items thuộc pallet đó lên Supabase.
  /// Trả về số items đã được chuyển kho.
  Future<int> transferPalletToLocation({
    required String palletEpc,
    required String newLocationId,
    required String performedBy,
  }) async {
    final cleanEpc = palletEpc.trim().toUpperCase();

    // Tìm pallet qua rfidEpc, palletId hoặc palletCode
    Pallet? pallet = _pallets.where((p) {
      final epcMatch = (p.rfidEpc ?? '').toUpperCase() == cleanEpc ||
          p.palletId.toUpperCase() == cleanEpc ||
          p.palletCode.toUpperCase() == cleanEpc ||
          'PAL-${p.palletCode.toUpperCase()}' == cleanEpc;
      return epcMatch;
    }).firstOrNull;

    if (pallet == null) return 0;

    final oldLocationId = pallet.locationId;
    final oldLocation = _locations
        .where((l) => l.locationId == oldLocationId)
        .firstOrNull;
    final newLocation = _locations
        .where((l) => l.locationId == newLocationId || l.locationCode == newLocationId)
        .firstOrNull;
    final effectiveNewLocId = newLocation?.locationId ?? newLocationId;

    final actualPerformer = (performedBy.isNotEmpty && !performedBy.contains('Thủ kho PDA'))
        ? resolveUserFullName(performedBy, defaultRole: 'handheld')
        : resolveUserFullName(null, defaultRole: 'handheld');

    // Cập nhật RAM
    pallet.locationId = effectiveNewLocId;
    pallet.placedBy = actualPerformer;
    if (oldLocation != null && oldLocation.currentPallets > 0) {
      oldLocation.currentPallets--;
    }
    if (newLocation != null) newLocation.currentPallets++;

    // Đồng bộ pallet lên Supabase
    await _syncDirectOrQueue(
      tableName: 'pallets',
      recordId: pallet.palletId,
      action: 'UPDATE',
      payload: {
        'pallet_id': pallet.palletId,
        'location_id': effectiveNewLocId,
        'placed_by': actualPerformer,
      },
    );

    // Cập nhật tất cả items thuộc pallet này
    final palletItems = _items
        .where((it) => it.palletId == pallet.palletId || it.palletId == pallet.palletCode)
        .toList();

    final oldLocDisplay = oldLocation?.displayName ?? (oldLocation?.locationCode ?? (oldLocationId ?? ''));
    final newLocDisplay = newLocation?.displayName ?? (newLocation?.locationCode ?? newLocationId);

    for (final item in palletItems) {
      item.locationId = effectiveNewLocId;
      item.status = ItemStatus.inStock;
      item.putawayBy = actualPerformer;
      _dbService.updateItemLocationAndPallet(item.epc, effectiveNewLocId, pallet.palletId);
      await _syncDirectOrQueue(
        tableName: 'items',
        recordId: item.itemId,
        action: 'UPDATE',
        payload: {
          'item_id': item.itemId,
          'location_id': effectiveNewLocId,
          'status': ItemStatus.inStock.code,
        },
      );
      await recordTagLifecycle(
        epc: item.epc,
        itemId: item.itemId,
        sku: item.sku,
        productName: item.productName,
        serialNumber: item.serialNumber,
        action: TagLifecycleAction.transferLocation,
        previousStatus: ItemStatus.inStock.label,
        newStatus: ItemStatus.inStock.label,
        fromLocation: oldLocDisplay.isNotEmpty ? oldLocDisplay : null,
        toLocation: newLocDisplay,
        fromPallet: pallet.palletCode,
        toPallet: pallet.palletCode,
        performedBy: actualPerformer,
        device: 'SEUIC UTouch 2 PDA',
        notes: 'Chuyển Pallet ${pallet.palletCode} từ ${oldLocDisplay.isNotEmpty ? oldLocDisplay : "kệ cũ"} sang $newLocDisplay',
      );
    }

    // Ghi transaction
    final tx = InventoryTransaction(
      transactionId: 'TX-TRANSFER-${DateTime.now().millisecondsSinceEpoch}',
      type: TransactionType.movement,
      documentNo: pallet.palletCode,
      sku: 'PALLET_${pallet.palletCode}',
      productName: 'Chuyển kho ${palletItems.length} Items',
      quantity: palletItems.length,
      fromLocation: oldLocation?.locationCode ?? (oldLocationId ?? ''),
      toLocation: newLocation?.locationCode ?? newLocationId,
      palletCode: pallet.palletCode,
      performedBy: actualPerformer,
      timestamp: DateTime.now(),
      notes: 'Chuyển kho PDA: ${oldLocation?.locationCode ?? oldLocationId} → ${newLocation?.locationCode ?? newLocationId}',
    );
    _transactions.insert(0, tx);
    await _syncInventoryTransaction(tx);

    _triggerBackgroundSync();
    notifyListeners();
    return palletItems.length;
  }

  /// Chuyển kho theo danh sách items cụ thể (không theo pallet).
  /// Dùng khi nhân viên quét từng chip item EPC trên tay cầm.
  Future<int> transferItemsToLocation({
    required List<String> itemEpcs,
    required String newLocationId,
    required String performedBy,
  }) async {
    if (itemEpcs.isEmpty) return 0;

    final newLocation = _locations
        .where((l) => l.locationId == newLocationId || l.locationCode == newLocationId)
        .firstOrNull;
    final effectiveNewLocId = newLocation?.locationId ?? newLocationId;
    final actualPerformer = (performedBy.isNotEmpty && !performedBy.contains('Thủ kho PDA'))
        ? resolveUserFullName(performedBy, defaultRole: 'handheld')
        : resolveUserFullName(null, defaultRole: 'handheld');
    int count = 0;

    for (final epc in itemEpcs) {
      final item = _items.where((it) => it.epc.toUpperCase() == epc.toUpperCase()).firstOrNull;
      if (item == null) continue;

      final oldLocId = item.locationId ?? '';
      final oldLoc = _locations.where((l) => l.locationId == oldLocId || l.locationCode == oldLocId).firstOrNull;
      final oldLocDisplay = oldLoc?.displayName ?? (oldLocId.isNotEmpty ? oldLocId : null);

      item.locationId = effectiveNewLocId;
      item.status = ItemStatus.inStock;
      item.putawayBy = actualPerformer;
      _dbService.updateItemLocationAndPallet(item.epc, effectiveNewLocId, item.palletId ?? '');
      await _syncDirectOrQueue(
        tableName: 'items',
        recordId: item.itemId,
        action: 'UPDATE',
        payload: {
          'item_id': item.itemId,
          'location_id': effectiveNewLocId,
          'status': ItemStatus.inStock.code,
        },
      );
      await recordTagLifecycle(
        epc: item.epc,
        itemId: item.itemId,
        sku: item.sku,
        productName: item.productName,
        serialNumber: item.serialNumber,
        action: TagLifecycleAction.transferLocation,
        previousStatus: ItemStatus.inStock.label,
        newStatus: ItemStatus.inStock.label,
        fromLocation: oldLocDisplay,
        toLocation: newLocation?.displayName ?? newLocationId,
        fromPallet: item.palletId,
        toPallet: item.palletId,
        performedBy: actualPerformer,
        device: 'SEUIC UTouch 2 PDA',
        notes: 'Chuyển vị trí kho từ ${oldLocDisplay ?? "kệ cũ"} đến ${newLocation?.displayName ?? newLocationId}',
      );
      count++;
    }

    if (count > 0) {
      final tx = InventoryTransaction(
        transactionId: 'TX-TRANSFER-${DateTime.now().millisecondsSinceEpoch}',
        type: TransactionType.movement,
        documentNo: 'MANUAL-TRANSFER',
        sku: 'ĐA_SKU',
        productName: 'Chuyển kho $count Items',
        quantity: count,
        fromLocation: '',
        toLocation: newLocation?.locationCode ?? newLocationId,
        performedBy: actualPerformer,
        timestamp: DateTime.now(),
        notes: 'Chuyển kho PDA (quét từng item): $count items → ${newLocation?.locationCode ?? newLocationId}',
      );
      _transactions.insert(0, tx);
      await _syncInventoryTransaction(tx);
      _triggerBackgroundSync();
      notifyListeners();
    }

    return count;
  }

  /// Di chuyển 1 sản phẩm riêng lẻ đến vị trí kệ kho hoặc pallet mới.
  Future<bool> moveItemIndividual({
    required String epc,
    required String newLocationId,
    String? newPalletId,
    required String performedBy,
  }) async {
    final cleanEpc = epc.trim().toUpperCase();
    final item = _items.where((it) => it.epc.toUpperCase() == cleanEpc).firstOrNull;
    if (item == null) return false;

    final newLocation = _locations
        .where((l) => l.locationId == newLocationId || l.locationCode == newLocationId)
        .firstOrNull;
    final effectiveLocId = newLocation?.locationId ?? newLocationId;

    final oldLocationId = item.locationId ?? '';
    final oldLocation = _locations
        .where((l) => l.locationId == oldLocationId || l.locationCode == oldLocationId)
        .firstOrNull;
    final oldPalletId = item.palletId;

    final actualPerformer = (performedBy.isNotEmpty && !performedBy.contains('Thủ kho PDA'))
        ? resolveUserFullName(performedBy, defaultRole: 'handheld')
        : resolveUserFullName(null, defaultRole: 'handheld');

    // Xử lý Pallet cũ và Pallet mới
    final targetPalletId = (newPalletId != null && newPalletId.trim().isNotEmpty) ? newPalletId.trim() : null;

    if (oldPalletId != null && oldPalletId.isNotEmpty && oldPalletId != targetPalletId) {
      final oldPallet = _pallets
          .where((p) => p.palletId == oldPalletId || p.palletCode == oldPalletId)
          .firstOrNull;
      if (oldPallet != null) {
        oldPallet.itemIds.remove(item.itemId);
      }
    }

    String? effectivePalletId = targetPalletId;
    if (effectivePalletId != null) {
      final newPallet = _pallets
          .where((p) => p.palletId == effectivePalletId || p.palletCode == effectivePalletId)
          .firstOrNull;
      if (newPallet != null && !newPallet.itemIds.contains(item.itemId)) {
        newPallet.itemIds.add(item.itemId);
      }
    }

    item.locationId = effectiveLocId;
    item.palletId = effectivePalletId;
    item.status = ItemStatus.inStock;
    item.putawayBy = actualPerformer;

    await _dbService.updateItemLocationAndPallet(item.epc, effectiveLocId, effectivePalletId);
    await _syncDirectOrQueue(
      tableName: 'items',
      recordId: item.itemId,
      action: 'UPDATE',
      payload: {
        'item_id': item.itemId,
        'location_id': effectiveLocId,
        'pallet_id': effectivePalletId,
        'status': ItemStatus.inStock.code,
      },
    );

    final tx = InventoryTransaction(
      transactionId: 'TX-ITEM-MOVE-${DateTime.now().millisecondsSinceEpoch}',
      type: TransactionType.movement,
      documentNo: item.sku,
      sku: item.sku,
      productName: 'Chuyển sản phẩm: ${item.productName}',
      quantity: 1,
      fromLocation: oldLocation?.locationCode ?? oldLocationId,
      toLocation: newLocation?.locationCode ?? newLocationId,
      palletCode: effectivePalletId,
      performedBy: actualPerformer,
      timestamp: DateTime.now(),
      notes: 'Chuyển SP riêng lẻ [${item.sku} - EPC: ${item.epc}] từ ${oldLocation?.displayName ?? oldLocationId} sang ${newLocation?.displayName ?? newLocationId}${effectivePalletId != null ? " (Pallet: $effectivePalletId)" : ""}',
    );
    _transactions.insert(0, tx);
    await _syncInventoryTransaction(tx);

    final oldPal = findPalletFast(oldPalletId);
    final newPal = findPalletFast(effectivePalletId);
    final oldPalDisplay = oldPal?.palletCode ?? oldPalletId;
    final newPalDisplay = newPal?.palletCode ?? effectivePalletId;

    await recordTagLifecycle(
      epc: item.epc,
      itemId: item.itemId,
      sku: item.sku,
      productName: item.productName,
      serialNumber: item.serialNumber,
      action: TagLifecycleAction.transferLocation,
      previousStatus: ItemStatus.inStock.label,
      newStatus: ItemStatus.inStock.label,
      fromLocation: oldLocation?.displayName ?? oldLocationId,
      toLocation: newLocation?.displayName ?? newLocationId,
      fromPallet: oldPalDisplay,
      toPallet: newPalDisplay,
      performedBy: actualPerformer,
      device: 'SEUIC UTouch 2 PDA',
      notes: 'Điều chuyển vị trí từ ${oldLocation?.displayName ?? oldLocationId} sang ${newLocation?.displayName ?? newLocationId}',
    );

    _triggerBackgroundSync();
    notifyListeners();
    return true;
  }

  Future<void> deletePallet(String palletId) async {
    final cleanId = palletId.trim().toUpperCase();
    final target = _pallets.where((p) => p.palletId.toUpperCase() == cleanId || p.palletCode.toUpperCase() == cleanId).firstOrNull;
    if (target != null) {
      _pallets.remove(target);
      await _dbService.deletePallet(target.palletId);
      if (target.palletCode.isNotEmpty && target.palletCode != target.palletId) {
        await _dbService.deletePallet(target.palletCode);
      }
      await _dbService.savePalletsBackup(_pallets);
      await _syncDirectOrQueue(
        tableName: 'pallets',
        recordId: target.palletId,
        action: 'DELETE',
        payload: {
          'pallet_id': target.palletId,
          'pallet_code': target.palletCode,
          'alt_id': 'PAL-${target.palletCode}',
        },
      );
    } else {
      _pallets.removeWhere((p) => p.palletId.toUpperCase() == cleanId || p.palletCode.toUpperCase() == cleanId);
      await _dbService.deletePallet(cleanId);
      await _dbService.savePalletsBackup(_pallets);
      await _syncDirectOrQueue(
        tableName: 'pallets',
        recordId: cleanId,
        action: 'DELETE',
        payload: {'pallet_id': cleanId},
      );
    }
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

      await recordTagLifecycle(
        epc: item.epc,
        itemId: item.itemId,
        sku: item.sku,
        productName: item.productName,
        serialNumber: item.serialNumber,
        action: TagLifecycleAction.mergePallet,
        previousStatus: ItemStatus.inStock.label,
        newStatus: ItemStatus.inStock.label,
        fromPallet: sourcePallet.palletCode,
        toPallet: targetPallet.palletCode,
        fromLocation: sourcePallet.locationId,
        toLocation: targetLocationId,
        performedBy: performedBy,
        device: 'SEUIC UTouch 2 PDA',
        notes: 'Dồn gộp từ Pallet ${sourcePallet.palletCode} sang ${targetPallet.palletCode}',
      );
    }

    // Làm rỗng Pallet nguồn: Mặc định chuyển về trạng thái trống hàng (0 items)
    sourcePallet.itemIds.clear();
    sourcePallet.isMultiSku = false;

    // Đảm bảo Pallet nguồn luôn lưu giữ vị trí được cập nhật lần cuối cùng của nó
    if (sourcePallet.locationId == null || sourcePallet.locationId!.trim().isEmpty) {
      final lastTx = _transactions.where((t) =>
        (t.palletCode != null && t.palletCode!.toUpperCase() == sourcePallet.palletCode.toUpperCase()) ||
        (t.documentNo.toUpperCase() == sourcePallet.palletCode.toUpperCase())
      ).firstOrNull;
      if (lastTx != null) {
        sourcePallet.locationId = lastTx.toLocation ?? lastTx.fromLocation;
      }
    }

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

    // Xử lý Pallet nguồn sau gộp: Mặc định luôn giữ lại làm Pallet rỗng tại vị trí cập nhật lần cuối
    if (deleteSourcePallet) {
      _pallets.removeWhere((p) => p.palletId == sourcePallet.palletId);
      await _dbService.deletePallet(sourcePallet.palletId);
      await _dbService.savePalletsBackup(_pallets);
      await _syncDirectOrQueue(
        tableName: 'pallets',
        recordId: sourcePallet.palletId,
        action: 'DELETE',
        payload: {'pallet_id': sourcePallet.palletId},
      );
    } else {
      await _dbService.insertPallet(sourcePallet);
      await _dbService.savePalletsBackup(_pallets);
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
    final tx = InventoryTransaction(
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
    );
    _transactions.insert(0, tx);
    await _syncInventoryTransaction(tx);

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
