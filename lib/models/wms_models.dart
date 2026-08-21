/// Trạng thái của từng sản phẩm vật lý (Item)
enum ItemStatus {
  pendingInbound('PENDING_INBOUND', 'Chờ nhập kho'),
  waitingPutaway('WAITING_PUTAWAY', 'Chờ xếp kệ'),
  inStock('IN_STOCK', 'Trong kho'),
  allocated('ALLOCATED', 'Đã giữ cho PO'),
  picked('PICKED', 'Đã lấy hàng'),
  waitingShipment('WAITING_SHIPMENT', 'Chờ giao hàng'),
  out('OUT', 'Đã xuất kho');

  final String code;
  final String label;
  const ItemStatus(this.code, this.label);
}

/// Trạng thái Lệnh Nhập kho
enum InboundOrderStatus {
  newOrder('NEW', 'Mới tạo'),
  waitingPutaway('WAITING_PUTAWAY', 'Chờ xếp kho'),
  processing('PROCESSING', 'Đang xử lý'),
  completed('COMPLETED', 'Trong kho'),
  cancelled('CANCELLED', 'Đã hủy');

  final String code;
  final String label;
  const InboundOrderStatus(this.code, this.label);
}

/// Trạng thái PO Xuất kho
enum OutboundOrderStatus {
  newOrder('NEW', 'Mới tiếp nhận'),
  processing('PROCESSING', 'Đang xử lý'),
  prepared('PREPARED', 'Đã chuẩn bị'),
  waitingShipment('WAITING_SHIPMENT', 'Chờ vận chuyển'),
  shipped('SHIPPED', 'Đã xuất hàng');

  final String code;
  final String label;
  const OutboundOrderStatus(this.code, this.label);
}

/// Phân loại sai lệch kiểm kê
enum InventoryVarianceType {
  match('MATCH', 'Khớp hoàn toàn', 0xFF10B981),
  missing('MISSING', 'Thiếu thực tế', 0xFFEF4444),
  wrongLocation('WRONG_LOCATION', 'Sai vị trí', 0xFFF59E0B),
  unknownEpc('UNKNOWN_EPC', 'Thẻ chưa khai báo', 0xFF8B5CF6);

  final String code;
  final String label;
  final int colorValue;
  const InventoryVarianceType(this.code, this.label, this.colorValue);
}

/// Chế độ hoạt động của RFID Gate HF340
enum GateMode {
  inbound('INBOUND', 'Cổng Nhập Kho'),
  outbound('OUTBOUND', 'Cổng Xuất Kho');

  final String code;
  final String label;
  const GateMode(this.code, this.label);
}

/// Loại thiết bị phần cứng RFID
enum DeviceType {
  printerGx3r('GX3r', 'Máy in & Encode RFID GX3r'),
  gateHf340('HF340', 'RFID Gate HF340 (02 Antenna)'),
  handheldUtouch2('Utouch 2', 'Máy quét Handheld Utouch 2'),
  desktopLjyzn105('LJYZN-105', 'Đầu đọc để bàn LJYZN-105');

  final String model;
  final String name;
  const DeviceType(this.model, this.name);
}

/// Loại giao dịch biến động kho
enum TransactionType {
  inbound('IN', 'Nhập kho'),
  outbound('OUT', 'Xuất kho'),
  movement('MOVE', 'Di chuyển vị trí'),
  auditAdjustment('ADJUST', 'Điều chỉnh kiểm kê');

  final String code;
  final String label;
  const TransactionType(this.code, this.label);
}

/// Danh mục sản phẩm (SKU)
class Product {
  final String productId;
  final String sku;
  final String productName;
  final String unit;
  final String category;
  final String? description;

  const Product({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.unit,
    required this.category,
    this.description,
  });

  Map<String, dynamic> toJson() => {
    'productId': productId,
    'sku': sku,
    'productName': productName,
    'unit': unit,
    'category': category,
    'description': description,
  };
}

/// Sản phẩm vật lý cụ thể (Item)
class Item {
  final String itemId;
  final String productId;
  final String sku;
  final String productName;
  final String serialNumber;
  final String epc;
  ItemStatus status;
  String? orderNo;
  String? palletId;
  String? locationId;
  DateTime? inboundTime;
  DateTime? allocatedTime;

  Item({
    required this.itemId,
    required this.productId,
    required this.sku,
    required this.productName,
    required this.serialNumber,
    required this.epc,
    this.status = ItemStatus.inStock,
    this.orderNo,
    this.palletId,
    this.locationId,
    this.inboundTime,
    this.allocatedTime,
  });
}

/// Vị trí lưu kho (Location)
class Location {
  final String locationId;
  final String locationCode;
  final String zone;
  final String shelf;
  final String level;
  final int maxPalletCapacity;
  int currentPallets;

  Location({
    required this.locationId,
    required this.locationCode,
    required this.zone,
    required this.shelf,
    required this.level,
    this.maxPalletCapacity = 1,
    this.currentPallets = 0,
  });
}

/// Pallet lưu trữ hàng hóa
class Pallet {
  final String palletId;
  final String palletCode;
  String? locationId;
  DateTime? inboundTime;
  bool isMultiSku;
  List<String> itemIds;

  Pallet({
    required this.palletId,
    required this.palletCode,
    this.locationId,
    this.inboundTime,
    this.isMultiSku = false,
    List<String>? itemIds,
  }) : itemIds = itemIds ?? [];
}

/// Chi tiết Lệnh Nhập kho
class InboundOrderDetail {
  final String productId;
  final String sku;
  final String productName;
  final int requiredQty;
  int receivedQty;

  InboundOrderDetail({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.requiredQty,
    this.receivedQty = 0,
  });
}

/// Lệnh Nhập kho (Inbound Order)
class InboundOrder {
  final String inboundOrderId;
  final String orderNo;
  final String sourceSupplier;
  InboundOrderStatus status;
  final DateTime createdAt;
  final List<InboundOrderDetail> details;

  InboundOrder({
    required this.inboundOrderId,
    required this.orderNo,
    required this.sourceSupplier,
    this.status = InboundOrderStatus.newOrder,
    required this.createdAt,
    required this.details,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InboundOrder &&
          runtimeType == other.runtimeType &&
          (inboundOrderId == other.inboundOrderId || orderNo == other.orderNo);

  @override
  int get hashCode => inboundOrderId.hashCode ^ orderNo.hashCode;
}

/// Chi tiết PO Xuất kho
class OutboundOrderDetail {
  final String productId;
  final String sku;
  final String productName;
  final int requiredQty;
  int pickedQty;

  OutboundOrderDetail({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.requiredQty,
    this.pickedQty = 0,
  });
}

/// PO Xuất kho (Outbound Order)
class OutboundOrder {
  final String outboundOrderId;
  final String poNo;
  final String customer;
  OutboundOrderStatus status;
  final DateTime createdAt;
  final List<OutboundOrderDetail> details;

  OutboundOrder({
    required this.outboundOrderId,
    required this.poNo,
    required this.customer,
    this.status = OutboundOrderStatus.newOrder,
    required this.createdAt,
    required this.details,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OutboundOrder &&
          runtimeType == other.runtimeType &&
          (outboundOrderId == other.outboundOrderId || poNo == other.poNo);

  @override
  int get hashCode => outboundOrderId.hashCode ^ poNo.hashCode;
}

/// Dòng gợi ý lấy hàng theo FIFO
class PickingPlanLine {
  final String productId;
  final String sku;
  final String productName;
  final String palletId;
  final String palletCode;
  final String locationCode;
  final int quantityToPick;
  final List<String> targetItemIds;
  bool isPicked;

  PickingPlanLine({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.palletId,
    required this.palletCode,
    required this.locationCode,
    required this.quantityToPick,
    required this.targetItemIds,
    this.isPicked = false,
  });
}

/// Kế hoạch lấy hàng (Picking Plan)
class PickingPlan {
  final String planId;
  final String outboundOrderId;
  final String poNo;
  final DateTime createdAt;
  final List<PickingPlanLine> lines;
  bool isCompleted;

  PickingPlan({
    required this.planId,
    required this.outboundOrderId,
    required this.poNo,
    required this.createdAt,
    required this.lines,
    this.isCompleted = false,
  });

  int get totalRequiredQty => lines.fold(0, (sum, line) => sum + line.quantityToPick);
  int get totalPickedQty => lines.fold(0, (sum, line) => sum + (line.isPicked ? line.quantityToPick : 0));
}

/// Kết quả kiểm kê từng Item
class InventoryItemResult {
  final String epc;
  final String? sku;
  final String? productName;
  final String? expectedLocation;
  final String? actualLocation;
  final InventoryVarianceType resultType;
  final DateTime readAt;

  InventoryItemResult({
    required this.epc,
    this.sku,
    this.productName,
    this.expectedLocation,
    this.actualLocation,
    required this.resultType,
    required this.readAt,
  });
}

/// Phiên kiểm kê (Inventory Session)
class InventorySession {
  final String sessionId;
  final String sessionCode;
  final String zone;
  final String? locationCode;
  final DateTime startedAt;
  DateTime? completedAt;
  bool isCompleted;
  final List<InventoryItemResult> results;

  InventorySession({
    required this.sessionId,
    required this.sessionCode,
    required this.zone,
    this.locationCode,
    required this.startedAt,
    this.completedAt,
    this.isCompleted = false,
    List<InventoryItemResult>? results,
  }) : results = results ?? [];

  int get matchCount => results.where((r) => r.resultType == InventoryVarianceType.match).length;
  int get missingCount => results.where((r) => r.resultType == InventoryVarianceType.missing).length;
  int get wrongLocationCount => results.where((r) => r.resultType == InventoryVarianceType.wrongLocation).length;
  int get unknownEpcCount => results.where((r) => r.resultType == InventoryVarianceType.unknownEpc).length;
}

/// Chi tiết đối chiếu Gate theo từng SKU
class SkuVerificationBreakdown {
  final String sku;
  final String productName;
  final int requiredQty;
  final int actualQty;
  final bool isMatched;

  SkuVerificationBreakdown({
    required this.sku,
    required this.productName,
    required this.requiredQty,
    required this.actualQty,
    required this.isMatched,
  });
}

/// Kết quả xác minh tại Cổng RFID Gate
class GateVerificationResult {
  final bool isPass;
  final GateMode mode;
  final String documentNo;
  final int totalRequiredQty;
  final int totalActualQty;
  final List<SkuVerificationBreakdown> skuBreakdowns;
  final List<String> unexpectedEpcs;
  final List<String> missingEpcs;
  final DateTime verifiedAt;

  GateVerificationResult({
    required this.isPass,
    required this.mode,
    required this.documentNo,
    required this.totalRequiredQty,
    required this.totalActualQty,
    required this.skuBreakdowns,
    required this.unexpectedEpcs,
    required this.missingEpcs,
    required this.verifiedAt,
  });
}

/// Lịch sử biến động kho (Audit Trail)
class InventoryTransaction {
  final String transactionId;
  final TransactionType type;
  final String documentNo;
  final String sku;
  final String productName;
  final int quantity;
  final String? fromLocation;
  final String? toLocation;
  final String? palletCode;
  final String performedBy;
  final DateTime timestamp;
  final String? notes;

  InventoryTransaction({
    required this.transactionId,
    required this.type,
    required this.documentNo,
    required this.sku,
    required this.productName,
    required this.quantity,
    this.fromLocation,
    this.toLocation,
    this.palletCode,
    required this.performedBy,
    required this.timestamp,
    this.notes,
  });
}

/// Thiết bị phần cứng RFID trong hệ thống
class RfidDevice {
  final String deviceId;
  final DeviceType type;
  final String name;
  final String ipOrPort;
  bool isConnected;
  String statusMessage;
  DateTime lastHeartbeat;

  RfidDevice({
    required this.deviceId,
    required this.type,
    required this.name,
    required this.ipOrPort,
    this.isConnected = true,
    this.statusMessage = 'Sẵn sàng',
    required this.lastHeartbeat,
  });
}
