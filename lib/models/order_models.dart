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
  final List<String>? epcList; // Danh sách mã EPC cụ thể nếu là đơn xuất lẻ

  OutboundOrderDetail({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.requiredQty,
    this.pickedQty = 0,
    this.epcList,
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

/// Thông tin Khách hàng (Customer)
class Customer {
  final String customerId;
  final String customerCode;
  final String customerName;
  final String? phone;
  final String? email;
  final String? address;
  final String? taxCode;
  final String? contactPerson;
  final String? notes;
  final DateTime? createdAt;

  const Customer({
    required this.customerId,
    required this.customerCode,
    required this.customerName,
    this.phone,
    this.email,
    this.address,
    this.taxCode,
    this.contactPerson,
    this.notes,
    this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'customer_id': customerId,
    'customer_code': customerCode,
    'customer_name': customerName,
    'phone': phone,
    'email': email,
    'address': address,
    'tax_code': taxCode,
    'contact_person': contactPerson,
    'notes': notes,
    'created_at': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
  };

  factory Customer.fromMap(Map<String, dynamic> map) => Customer(
    customerId: map['customer_id'] as String,
    customerCode: map['customer_code'] as String,
    customerName: map['customer_name'] as String,
    phone: map['phone'] as String?,
    email: map['email'] as String?,
    address: map['address'] as String?,
    taxCode: map['tax_code'] as String?,
    contactPerson: map['contact_person'] as String?,
    notes: map['notes'] as String?,
    createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
  );
}

/// Chi tiết Phiếu Xuất Hàng (Delivery Note Detail)
class DeliveryNoteDetail {
  final int? id;
  final String deliveryId;
  final String productId;
  final String sku;
  final String productName;
  final int quantity;
  final String? cartonCode;

  const DeliveryNoteDetail({
    this.id,
    required this.deliveryId,
    required this.productId,
    required this.sku,
    required this.productName,
    required this.quantity,
    this.cartonCode,
  });

  Map<String, dynamic> toMap() => {
    if (id != null) 'id': id,
    'delivery_id': deliveryId,
    'product_id': productId,
    'sku': sku,
    'product_name': productName,
    'quantity': quantity,
    'carton_code': cartonCode,
  };

  factory DeliveryNoteDetail.fromMap(Map<String, dynamic> map) => DeliveryNoteDetail(
    id: map['id'] as int?,
    deliveryId: map['delivery_id'] as String,
    productId: map['product_id'] as String,
    sku: map['sku'] as String,
    productName: map['product_name'] as String,
    quantity: map['quantity'] as int? ?? 1,
    cartonCode: map['carton_code'] as String?,
  );
}

/// Phiếu Xuất Hàng / Vận Đơn (Delivery Note / Shipment)
class DeliveryNote {
  final String deliveryId;
  final String deliveryNo;
  final String? poNo;
  final String? customerId;
  final String customerName;
  final String status; // 'DRAFT', 'PREPARED', 'SHIPPED', 'DELIVERED', 'CANCELLED'
  final String? carrier;
  final String? trackingNo;
  final int totalCartons;
  final int totalQty;
  final String? createdBy;
  final DateTime? shippedAt;
  final String? notes;
  final DateTime? createdAt;
  final List<DeliveryNoteDetail> details;

  const DeliveryNote({
    required this.deliveryId,
    required this.deliveryNo,
    this.poNo,
    this.customerId,
    required this.customerName,
    this.status = 'DRAFT',
    this.carrier,
    this.trackingNo,
    this.totalCartons = 0,
    this.totalQty = 0,
    this.createdBy,
    this.shippedAt,
    this.notes,
    this.createdAt,
    this.details = const [],
  });

  Map<String, dynamic> toMap() => {
    'delivery_id': deliveryId,
    'delivery_no': deliveryNo,
    'po_no': poNo,
    'customer_id': customerId,
    'customer_name': customerName,
    'status': status,
    'carrier': carrier,
    'tracking_no': trackingNo,
    'total_cartons': totalCartons,
    'total_qty': totalQty,
    'created_by': createdBy,
    'shipped_at': shippedAt?.toIso8601String(),
    'notes': notes,
    'created_at': createdAt?.toIso8601String() ?? DateTime.now().toIso8601String(),
  };

  factory DeliveryNote.fromMap(Map<String, dynamic> map, {List<DeliveryNoteDetail> details = const []}) => DeliveryNote(
    deliveryId: map['delivery_id'] as String,
    deliveryNo: map['delivery_no'] as String,
    poNo: map['po_no'] as String?,
    customerId: map['customer_id'] as String?,
    customerName: map['customer_name'] as String,
    status: map['status'] as String? ?? 'DRAFT',
    carrier: map['carrier'] as String?,
    trackingNo: map['tracking_no'] as String?,
    totalCartons: map['total_cartons'] as int? ?? 0,
    totalQty: map['total_qty'] as int? ?? 0,
    createdBy: map['created_by'] as String?,
    shippedAt: map['shipped_at'] != null ? DateTime.tryParse(map['shipped_at'].toString()) : null,
    notes: map['notes'] as String?,
    createdAt: map['created_at'] != null ? DateTime.tryParse(map['created_at'].toString()) : null,
    details: details,
  );
}
