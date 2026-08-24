import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wms_models.dart';

/// Sự kiện Realtime từ Cổng RFID Gate Monitor
class GateRealtimeEvent {
  final String orderNo;
  final List<String> epcs;
  final String passType; // 'INBOUND', 'OUTBOUND'
  final bool isPass;
  final String message;
  final DateTime timestamp;

  GateRealtimeEvent({
    required this.orderNo,
    required this.epcs,
    required this.passType,
    required this.isPass,
    required this.message,
    required this.timestamp,
  });

  factory GateRealtimeEvent.fromMap(Map<String, dynamic> map) {
    return GateRealtimeEvent(
      orderNo: map['order_no']?.toString() ?? '',
      epcs: (map['epcs'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [],
      passType: map['pass_type']?.toString() ?? 'INBOUND',
      isPass: map['is_pass'] as bool? ?? false,
      message: map['message']?.toString() ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'order_no': orderNo,
        'epcs': epcs,
        'pass_type': passType,
        'is_pass': isPass,
        'message': message,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Sự kiện Realtime khi PDA thực hiện Xếp kệ (Putaway)
class PutawayRealtimeEvent {
  final String palletCode;
  final String locationCode;
  final int itemCount;
  final String performedBy;
  final DateTime timestamp;

  PutawayRealtimeEvent({
    required this.palletCode,
    required this.locationCode,
    required this.itemCount,
    required this.performedBy,
    required this.timestamp,
  });

  factory PutawayRealtimeEvent.fromMap(Map<String, dynamic> map) {
    return PutawayRealtimeEvent(
      palletCode: map['pallet_code']?.toString() ?? '',
      locationCode: map['location_code']?.toString() ?? '',
      itemCount: (map['item_count'] as num?)?.toInt() ?? 0,
      performedBy: map['performed_by']?.toString() ?? '',
      timestamp: map['timestamp'] != null
          ? DateTime.tryParse(map['timestamp'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'pallet_code': palletCode,
        'location_code': locationCode,
        'item_count': itemCount,
        'performed_by': performedBy,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// Lớp dịch vụ API Supabase chuyên biệt cho hệ thống RFID WMS
/// Cung cấp toàn bộ các API truy vấn, ghi dữ liệu tốc độ cao (Batch) và Realtime Event Bus
class ApiService extends ChangeNotifier {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  bool _isInitialized = false;
  RealtimeChannel? _broadcastChannel;

  // StreamControllers cho Realtime Broadcast Events
  final StreamController<GateRealtimeEvent> _gateEventController =
      StreamController<GateRealtimeEvent>.broadcast();
  final StreamController<PutawayRealtimeEvent> _putawayEventController =
      StreamController<PutawayRealtimeEvent>.broadcast();
  final StreamController<Map<String, dynamic>> _towerLightController =
      StreamController<Map<String, dynamic>>.broadcast();

  Stream<GateRealtimeEvent> get onGateEvent => _gateEventController.stream;
  Stream<PutawayRealtimeEvent> get onPutawayEvent => _putawayEventController.stream;
  Stream<Map<String, dynamic>> get onTowerLightTrigger => _towerLightController.stream;

  SupabaseClient? get _client {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  /// Khởi tạo và kết nối Realtime Channel
  Future<void> init() async {
    if (_isInitialized || Platform.environment.containsKey('FLUTTER_TEST')) return;

    try {
      final supa = _client;
      if (supa == null) return;

      _broadcastChannel = supa.channel('wms:realtime_events')
        ..onBroadcast(
          event: 'gate_pass',
          callback: (payload) {
            try {
              final event = GateRealtimeEvent.fromMap(payload);
              _gateEventController.add(event);
              notifyListeners();
            } catch (e) {
              debugPrint('Error parsing gate_pass event: $e');
            }
          },
        )
        ..onBroadcast(
          event: 'putaway_confirm',
          callback: (payload) {
            try {
              final event = PutawayRealtimeEvent.fromMap(payload);
              _putawayEventController.add(event);
              notifyListeners();
            } catch (e) {
              debugPrint('Error parsing putaway_confirm event: $e');
            }
          },
        )
        ..onBroadcast(
          event: 'tower_light_trigger',
          callback: (payload) {
            _towerLightController.add(payload);
            notifyListeners();
          },
        )
        ..subscribe();

      _isInitialized = true;
    } catch (e) {
      debugPrint('ApiService init error: $e');
    }
  }

  // ===========================================================================
  // ⚡ 1. REALTIME BROADCAST APIS (Độ trễ mili-giây giữa Desktop & PDA)
  // ===========================================================================

  /// Cổng RFID phát tín hiệu kiện hàng vừa đi qua
  Future<void> broadcastGatePass(GateRealtimeEvent event) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _gateEventController.add(event);
      return;
    }
    try {
      await _broadcastChannel?.sendBroadcastMessage(
        event: 'gate_pass',
        payload: event.toMap(),
      );
    } catch (e) {
      debugPrint('broadcastGatePass error: $e');
    }
  }

  /// PDA phát tín hiệu xếp hàng thành công lên vị trí kệ
  Future<void> broadcastPutaway(PutawayRealtimeEvent event) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _putawayEventController.add(event);
      return;
    }
    try {
      await _broadcastChannel?.sendBroadcastMessage(
        event: 'putaway_confirm',
        payload: event.toMap(),
      );
    } catch (e) {
      debugPrint('broadcastPutaway error: $e');
    }
  }

  /// Kích hoạt tháp đèn tín hiệu & còi báo Realtime
  Future<void> triggerTowerLight({
    required String color, // 'GREEN', 'RED', 'YELLOW'
    required bool buzzer,
    int durationMs = 1500,
  }) async {
    final payload = {
      'color': color,
      'buzzer': buzzer,
      'duration_ms': durationMs,
      'timestamp': DateTime.now().toIso8601String(),
    };
    if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _towerLightController.add(payload);
      return;
    }
    try {
      await _broadcastChannel?.sendBroadcastMessage(
        event: 'tower_light_trigger',
        payload: payload,
      );
    } catch (e) {
      debugPrint('triggerTowerLight error: $e');
    }
  }

  // ===========================================================================
  // 📦 2. HIGH-THROUGHPUT RFID DATA APIS (PostgREST)
  // ===========================================================================

  /// Ghi hàng loạt (Batch Upsert) danh sách thẻ chip RFID vào Supabase
  Future<bool> batchUpsertItems(List<Item> items) async {
    if (items.isEmpty) return true;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return true;

    try {
      final supa = _client;
      if (supa == null) return false;

      final rows = items.map((item) => {
            'item_id': item.itemId,
            'product_id': item.productId,
            'sku': item.sku,
            'product_name': item.productName,
            'serial_number': item.serialNumber,
            'epc': item.epc.toUpperCase(),
            'status': item.status.code,
            'order_no': item.orderNo,
            'pallet_id': item.palletId,
            'location_id': item.locationId,
            'inbound_time': item.inboundTime?.toIso8601String(),
            'allocated_time': item.allocatedTime?.toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          }).toList();

      await supa.from('items').upsert(rows);
      return true;
    } catch (e) {
      debugPrint('ApiService batchUpsertItems error: $e');
      return false;
    }
  }

  /// Lấy toàn bộ danh sách Vị trí kho từ Supabase
  Future<List<Location>> fetchLocations() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return [];

    try {
      final supa = _client;
      if (supa == null) return [];

      final List<dynamic> res = await supa.from('locations').select();
      return res.map((m) => Location(
            locationId: m['location_id']?.toString() ?? '',
            locationCode: m['location_code']?.toString() ?? '',
            zone: m['zone']?.toString() ?? '',
            shelf: m['shelf']?.toString() ?? '',
            level: m['level']?.toString() ?? '',
            currentPallets: (m['current_pallets'] as num?)?.toInt() ?? 0,
          )).toList();
    } catch (e) {
      debugPrint('ApiService fetchLocations error: $e');
      return [];
    }
  }

  /// Lấy danh sách Sản phẩm từ Supabase
  Future<List<Product>> fetchProducts() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return [];

    try {
      final supa = _client;
      if (supa == null) return [];

      final List<dynamic> res = await supa.from('products').select();
      return res.map((m) => Product(
            productId: m['product_id']?.toString() ?? '',
            sku: m['sku']?.toString() ?? '',
            productName: m['product_name']?.toString() ?? '',
            unit: m['unit']?.toString() ?? '',
            category: m['category']?.toString() ?? '',
            description: m['description']?.toString(),
          )).toList();
    } catch (e) {
      debugPrint('ApiService fetchProducts error: $e');
      return [];
    }
  }

  /// Lấy danh mục Pallet từ Supabase
  Future<List<Pallet>> fetchPallets() async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return [];

    try {
      final supa = _client;
      if (supa == null) return [];

      final List<dynamic> res = await supa.from('pallets').select();
      return res.map((m) => Pallet(
            palletId: m['pallet_id']?.toString() ?? '',
            palletCode: m['pallet_code']?.toString() ?? '',
            locationId: m['location_id']?.toString(),
            inboundTime: m['inbound_time'] != null
                ? DateTime.tryParse(m['inbound_time'].toString())
                : null,
            isMultiSku: m['is_multi_sku'] == 1 || m['is_multi_sku'] == true,
          )).toList();
    } catch (e) {
      debugPrint('ApiService fetchPallets error: $e');
      return [];
    }
  }

  /// Lấy danh sách Đơn Nhập kho
  Future<List<InboundOrder>> fetchInboundOrders({String? status}) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return [];

    try {
      final supa = _client;
      if (supa == null) return [];

      var query = supa.from('inbound_orders').select('*, inbound_order_details(*)');
      if (status != null) {
        query = query.eq('status', status);
      }

      final List<dynamic> res = await query;
      return res.map((m) {
        final detailsList = (m['inbound_order_details'] as List<dynamic>?) ?? [];
        final details = detailsList.map((d) => InboundOrderDetail(
              productId: d['product_id']?.toString() ?? '',
              sku: d['sku']?.toString() ?? '',
              productName: d['product_name']?.toString() ?? '',
              requiredQty: (d['required_qty'] as num?)?.toInt() ?? 0,
              receivedQty: (d['received_qty'] as num?)?.toInt() ?? 0,
            )).toList();

        return InboundOrder(
          inboundOrderId: m['inbound_order_id']?.toString() ?? '',
          orderNo: m['order_no']?.toString() ?? '',
          sourceSupplier: m['source_supplier']?.toString() ?? '',
          status: InboundOrderStatus.values.firstWhere(
            (s) => s.code == m['status'],
            orElse: () => InboundOrderStatus.newOrder,
          ),
          createdAt: DateTime.tryParse(m['created_at'].toString()) ?? DateTime.now(),
          details: details,
        );
      }).toList();
    } catch (e) {
      debugPrint('ApiService fetchInboundOrders error: $e');
      return [];
    }
  }

  /// Lấy danh sách Đơn Xuất kho
  Future<List<OutboundOrder>> fetchOutboundOrders({String? status}) async {
    if (Platform.environment.containsKey('FLUTTER_TEST')) return [];

    try {
      final supa = _client;
      if (supa == null) return [];

      var query = supa.from('outbound_orders').select('*, outbound_order_details(*)');
      if (status != null) {
        query = query.eq('status', status);
      }

      final List<dynamic> res = await query;
      return res.map((m) {
        final detailsList = (m['outbound_order_details'] as List<dynamic>?) ?? [];
        final details = detailsList.map((d) => OutboundOrderDetail(
              productId: d['product_id']?.toString() ?? '',
              sku: d['sku']?.toString() ?? '',
              productName: d['product_name']?.toString() ?? '',
              requiredQty: (d['required_qty'] as num?)?.toInt() ?? 0,
              pickedQty: (d['picked_qty'] as num?)?.toInt() ?? 0,
            )).toList();

        return OutboundOrder(
          outboundOrderId: m['outbound_order_id']?.toString() ?? '',
          poNo: m['po_no']?.toString() ?? '',
          customer: m['customer']?.toString() ?? '',
          status: OutboundOrderStatus.values.firstWhere(
            (s) => s.code == m['status'],
            orElse: () => OutboundOrderStatus.newOrder,
          ),
          createdAt: DateTime.tryParse(m['created_at'].toString()) ?? DateTime.now(),
          details: details,
        );
      }).toList();
    } catch (e) {
      debugPrint('ApiService fetchOutboundOrders error: $e');
      return [];
    }
  }

  /// Xác nhận Cổng tiếp nhận hàng và phát sóng Realtime
  Future<bool> gateReceive({
    required String orderNo,
    required List<String> scannedEpcs,
    String performedBy = 'Cổng RFID Desktop',
  }) async {
    final event = GateRealtimeEvent(
      orderNo: orderNo,
      epcs: scannedEpcs,
      passType: 'INBOUND',
      isPass: true,
      message: 'Cổng tiếp nhận thành công ${scannedEpcs.length} kiện hàng.',
      timestamp: DateTime.now(),
    );

    await broadcastGatePass(event);
    return true;
  }

  /// Xác nhận PDA xếp kệ (Putaway) và phát sóng Realtime
  Future<bool> pdaPutaway({
    required String palletCode,
    required String locationCode,
    int itemCount = 0,
    String performedBy = 'Thủ kho PDA',
  }) async {
    final event = PutawayRealtimeEvent(
      palletCode: palletCode,
      locationCode: locationCode,
      itemCount: itemCount,
      performedBy: performedBy,
      timestamp: DateTime.now(),
    );

    await broadcastPutaway(event);
    return true;
  }

  @override
  void dispose() {
    _gateEventController.close();
    _putawayEventController.close();
    _towerLightController.close();
    _broadcastChannel?.unsubscribe();
    super.dispose();
  }
}
