/// Trạng thái của từng sản phẩm vật lý (Item)
enum ItemStatus {
  pendingInbound('PENDING_INBOUND', 'Chờ nhập kho'),
  waitingPalletize('WAITING_PALLETIZE', 'Xếp vào pallet'),
  waitingPutaway('WAITING_PUTAWAY', 'Chờ xếp kệ'),
  inStock('IN_STOCK', 'Đã lưu vào vị trí'),
  allocated('ALLOCATED', 'Đã giữ cho PO'),
  picked('PICKED', 'Đã lấy hàng'),
  waitingShipment('WAITING_SHIPMENT', 'Chờ giao hàng'),
  out('OUT', 'Đã xuất kho'),
  underRepair('UNDER_REPAIR', 'Sửa chữa / Bảo hành'),
  recalled('RECALLED', 'Đã thu hồi');

  final String code;
  final String label;
  const ItemStatus(this.code, this.label);
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

/// Loại thiết bị phần hardware RFID
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

/// Sản phẩm vật lý cụ thể (Item)
class Item {
  final String itemId;
  String productId;
  String sku;
  final String productName;
  final String serialNumber;
  final String epc;
  ItemStatus status;
  String? orderNo;
  String? palletId;
  String? locationId;
  DateTime? inboundTime;
  DateTime? allocatedTime;

  String? supplier;
  String? cartonCode;
  String? inboundBy;
  String? putawayBy;

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
    this.supplier,
    this.cartonCode,
    this.inboundBy,
    this.putawayBy,
  });

  Item copyWith({
    String? itemId,
    String? productId,
    String? sku,
    String? productName,
    String? serialNumber,
    String? epc,
    ItemStatus? status,
    String? orderNo,
    String? palletId,
    String? locationId,
    DateTime? inboundTime,
    DateTime? allocatedTime,
    String? supplier,
    String? cartonCode,
    String? inboundBy,
    String? putawayBy,
  }) {
    return Item(
      itemId: itemId ?? this.itemId,
      productId: productId ?? this.productId,
      sku: sku ?? this.sku,
      productName: productName ?? this.productName,
      serialNumber: serialNumber ?? this.serialNumber,
      epc: epc ?? this.epc,
      status: status ?? this.status,
      orderNo: orderNo ?? this.orderNo,
      palletId: palletId ?? this.palletId,
      locationId: locationId ?? this.locationId,
      inboundTime: inboundTime ?? this.inboundTime,
      allocatedTime: allocatedTime ?? this.allocatedTime,
      supplier: supplier ?? this.supplier,
      cartonCode: cartonCode ?? this.cartonCode,
      inboundBy: inboundBy ?? this.inboundBy,
      putawayBy: putawayBy ?? this.putawayBy,
    );
  }

  /// Tên nhà cung cấp hiển thị
  String get supplierDisplay => (supplier != null && supplier!.trim().isNotEmpty) ? supplier!.trim() : 'Chưa khai báo';

  /// Mã thùng hàng hiển thị
  String get cartonDisplay {
    if (cartonCode != null && cartonCode!.trim().isNotEmpty) return cartonCode!.trim();
    if (palletId != null && palletId!.trim().isNotEmpty) return palletId!.trim();
    return 'Chưa đóng thùng';
  }

  /// Người nhập kho hiển thị
  String get inboundByDisplay => (inboundBy != null && inboundBy!.trim().isNotEmpty && inboundBy != 'Cổng RFID Gate') ? inboundBy!.trim() : 'Thủ kho';

  /// Người cất kệ hiển thị
  String get putawayByDisplay {
    if (putawayBy != null && putawayBy!.trim().isNotEmpty) return putawayBy!.trim();
    if (status == ItemStatus.inStock) return 'Đã cất kệ';
    return 'Chưa cất kệ';
  }

  /// Ngày giờ nhập hiển thị
  String get formattedInboundDate {
    if (inboundTime == null) return '--';
    final t = inboundTime!;
    final d = t.day.toString().padLeft(2, '0');
    final m = t.month.toString().padLeft(2, '0');
    final y = t.year.toString();
    final h = t.hour.toString().padLeft(2, '0');
    final min = t.minute.toString().padLeft(2, '0');
    return '$d/$m/$y $h:$min';
  }

  /// Nhãn trạng thái hiển thị chi tiết (ví dụ: "Đã lưu vào vị trí LOC-A01-01")
  String get statusDisplay {
    if (status == ItemStatus.inStock) {
      if (locationId != null && locationId!.trim().isNotEmpty) {
        return 'Đã lưu vào vị trí ${locationId!.trim()}';
      }
      return 'Đã lưu vào vị trí';
    }
    return status.label;
  }
}

/// Pallet lưu trữ hàng hóa
class Pallet {
  final String palletId;
  String palletCode;
  String? palletName;
  String? rfidEpc;
  String? locationId;
  DateTime? inboundTime;
  bool isMultiSku;
  List<String> itemIds;
  String? placedBy;

  Pallet({
    required this.palletId,
    required this.palletCode,
    this.palletName,
    this.rfidEpc,
    this.locationId,
    this.inboundTime,
    this.isMultiSku = false,
    List<String>? itemIds,
    this.placedBy,
  }) : itemIds = itemIds ?? [];

  /// Tên hiển thị ưu tiên tên pallet, nếu chưa đặt tên thì dùng mã barcode palletCode
  String get displayName => (palletName != null && palletName!.trim().isNotEmpty) ? palletName!.trim() : palletCode;
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
  final List<String> targetSkus;

  final String? assignedToUserId;
  final String? assignedToName;
  final String? assignedBy;
  final String? notes;

  InventorySession({
    required this.sessionId,
    required this.sessionCode,
    required this.zone,
    this.locationCode,
    required this.startedAt,
    this.completedAt,
    this.isCompleted = false,
    List<InventoryItemResult>? results,
    List<String>? targetSkus,
    this.assignedToUserId,
    this.assignedToName,
    this.assignedBy,
    this.notes,
  })  : results = results ?? [],
        targetSkus = targetSkus ?? const [];

  bool get isSkuSpecific => targetSkus.isNotEmpty;
  String get targetSkusDisplay => targetSkus.isEmpty ? 'Tất cả mặt hàng' : targetSkus.join(', ');

  String get assignedToDisplay => (assignedToName != null && assignedToName!.trim().isNotEmpty)
      ? assignedToName!.trim()
      : 'Chưa chỉ định';

  List<InventoryItemResult> get effectiveResults => isSkuSpecific
      ? results.where((r) => r.sku != null && targetSkus.contains(r.sku)).toList()
      : results;

  int get matchCount => isSkuSpecific
      ? effectiveResults.where((r) => r.resultType == InventoryVarianceType.match).length
      : results.where((r) => r.resultType == InventoryVarianceType.match).length;

  int get missingCount => isSkuSpecific
      ? effectiveResults.where((r) => r.resultType == InventoryVarianceType.missing).length
      : results.where((r) => r.resultType == InventoryVarianceType.missing).length;

  int get wrongLocationCount => isSkuSpecific
      ? 0
      : results.where((r) => r.resultType == InventoryVarianceType.wrongLocation).length;

  int get unknownEpcCount => isSkuSpecific
      ? 0
      : results.where((r) => r.resultType == InventoryVarianceType.unknownEpc).length;

  /// Số lượng chip của hàng đã xuất kho trước đó nhưng vẫn phát hiện trong kho
  int get shippedItemCount => isSkuSpecific
      ? effectiveResults.where((r) => r.expectedLocation == 'ĐÃ XUẤT KHO').length
      : results.where((r) => r.expectedLocation == 'ĐÃ XUẤT KHO').length;

  /// Danh sách kết quả chip của hàng đã xuất kho
  List<InventoryItemResult> get shippedResults => isSkuSpecific
      ? effectiveResults.where((r) => r.expectedLocation == 'ĐÃ XUẤT KHO').toList()
      : results.where((r) => r.expectedLocation == 'ĐÃ XUẤT KHO').toList();

  /// Số lượng thẻ lạ thực sự (không tính chip của hàng đã xuất kho)
  int get trueUnknownEpcCount => isSkuSpecific
      ? 0
      : results.where((r) => r.resultType == InventoryVarianceType.unknownEpc && r.expectedLocation != 'ĐÃ XUẤT KHO').length;

  int get actualScannedCount => isSkuSpecific
      ? matchCount
      : results.where((r) => r.resultType != InventoryVarianceType.missing).length;

  int get knownInDbCount => isSkuSpecific
      ? matchCount
      : results.where((r) => r.resultType != InventoryVarianceType.missing && r.resultType != InventoryVarianceType.unknownEpc).length;

  int get varianceOrUnknownCount => isSkuSpecific
      ? 0
      : ((actualScannedCount - knownInDbCount) > 0 ? (actualScannedCount - knownInDbCount) : 0);
}

/// Dòng đối soát tồn kho: Tồn dự kiến (Sổ sách) vs Tồn thực tế (Kiểm kê) theo từng SKU
class SkuStockReconciliationRow {
  final String sku;
  final String productName;
  final String unit;
  final String zoneOrLocation;
  final int expectedQty; // Tồn kho dự kiến (Sổ sách / CSDL)
  final int actualQty;   // Tồn kho kiểm kê theo thực tế (Quét RFID)
  final int matchedCount;
  final int missingCount;
  final int wrongLocationCount;
  final int unknownCount;
  final bool isAudited;  // Đã có dữ liệu kiểm kê thực tế hay chưa
  final List<InventoryItemResult> itemResults;

  const SkuStockReconciliationRow({
    required this.sku,
    required this.productName,
    required this.unit,
    required this.zoneOrLocation,
    required this.expectedQty,
    required this.actualQty,
    this.matchedCount = 0,
    this.missingCount = 0,
    this.wrongLocationCount = 0,
    this.unknownCount = 0,
    this.isAudited = true,
    this.itemResults = const [],
  });

  /// Số lượng chip của mặt hàng này đã xuất kho trước đó nhưng bị quét lại
  int get shippedCount => itemResults.where((it) => it.expectedLocation == 'ĐÃ XUẤT KHO').length;

  /// Chênh lệch = Thực tế - Dự kiến (bằng 0 nếu chưa thực hiện kiểm kê)
  int get difference => isAudited ? (actualQty - expectedQty) : 0;

  /// Tỷ lệ chính xác đối soát (%)
  double get accuracyPercent {
    if (!isAudited) return 0.0;
    if (expectedQty == 0 && actualQty == 0) return 100.0;
    if (expectedQty == 0) return 0.0;
    return (matchedCount / expectedQty * 100).clamp(0.0, 100.0);
  }

  /// Nhãn trạng thái đối soát
  String get statusLabel {
    if (!isAudited) return 'Chưa kiểm kê';
    if (shippedCount > 0) return '🚨 Có $shippedCount chip đã xuất';
    if (difference == 0 && wrongLocationCount == 0) return 'Khớp đủ';
    if (difference == 0 && wrongLocationCount > 0) return 'Sai vị trí';
    if (difference < 0) return 'Thiếu ${-difference}';
    return 'Thừa $difference';
  }
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
  final List<String> unstockedEpcs;
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
    this.unstockedEpcs = const [],
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

/// Trạng thái của Đơn tìm kiếm vị trí thẻ / hàng hóa
enum LocateOrderStatus {
  pending('PENDING', 'Chờ tìm kiếm', 0xFFF59E0B),
  inProgress('IN_PROGRESS', 'Đang tìm kiếm', 0xFF0284C7),
  completed('COMPLETED', 'Đã tìm thấy', 0xFF10B981),
  cancelled('CANCELLED', 'Đã hủy', 0xFF64748B);

  final String code;
  final String label;
  final int colorValue;
  const LocateOrderStatus(this.code, this.label, this.colorValue);

  String get display => label;

  static LocateOrderStatus fromCode(String? code) {
    if (code == null) return LocateOrderStatus.pending;
    final upper = code.trim().toUpperCase();
    return LocateOrderStatus.values.firstWhere(
      (s) => s.code == upper,
      orElse: () => LocateOrderStatus.pending,
    );
  }
}

/// Đơn tìm kiếm vị trí thẻ RFID / Sản phẩm / Pallet (Locate Task / Search Order)
class LocateOrder {
  final String orderId;
  final String orderNo;
  final String title;
  final String? targetEpc;
  final String? targetSku;
  final String? targetProductName;
  final String? targetPalletCode;
  final String? expectedLocation;
  LocateOrderStatus status;
  final String assignedToUserId; // ID nhân viên role handheld được chỉ định
  final String assignedToName;   // Tên nhân viên handheld
  final String createdBy;
  final DateTime createdAt;
  DateTime? completedAt;
  String? completedBy;
  String? foundLocation;
  String? notes;

  LocateOrder({
    required this.orderId,
    required this.orderNo,
    required this.title,
    this.targetEpc,
    this.targetSku,
    this.targetProductName,
    this.targetPalletCode,
    this.expectedLocation,
    this.status = LocateOrderStatus.pending,
    required this.assignedToUserId,
    required this.assignedToName,
    required this.createdBy,
    required this.createdAt,
    this.completedAt,
    this.completedBy,
    this.foundLocation,
    this.notes,
  });

  String get targetDisplay {
    if (targetProductName != null && targetProductName!.trim().isNotEmpty) {
      return targetProductName!.trim();
    }
    if (targetSku != null && targetSku!.trim().isNotEmpty) {
      return 'SKU: ${targetSku!.trim()}';
    }
    if (targetPalletCode != null && targetPalletCode!.trim().isNotEmpty) {
      return 'Pallet: ${targetPalletCode!.trim()}';
    }
    if (targetEpc != null && targetEpc!.trim().isNotEmpty) {
      return 'EPC: ${targetEpc!.trim()}';
    }
    return title;
  }

  Map<String, dynamic> toMap() => {
    'order_id': orderId,
    'order_no': orderNo,
    'title': title,
    'target_epc': targetEpc,
    'target_sku': targetSku,
    'target_product_name': targetProductName,
    'target_pallet_code': targetPalletCode,
    'expected_location': expectedLocation,
    'status': status.code,
    'assigned_to_user_id': assignedToUserId,
    'assigned_to_name': assignedToName,
    'created_by': createdBy,
    'created_at': createdAt.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'completed_by': completedBy,
    'found_location': foundLocation,
    'notes': notes,
  };

  factory LocateOrder.fromMap(Map<String, dynamic> map) => LocateOrder(
    orderId: (map['order_id'] ?? '').toString(),
    orderNo: (map['order_no'] ?? '').toString(),
    title: (map['title'] ?? '').toString(),
    targetEpc: map['target_epc']?.toString(),
    targetSku: map['target_sku']?.toString(),
    targetProductName: map['target_product_name']?.toString(),
    targetPalletCode: map['target_pallet_code']?.toString(),
    expectedLocation: map['expected_location']?.toString(),
    status: LocateOrderStatus.fromCode(map['status']?.toString()),
    assignedToUserId: (map['assigned_to_user_id'] ?? '').toString(),
    assignedToName: (map['assigned_to_name'] ?? 'Nhân viên PDA').toString(),
    createdBy: (map['created_by'] ?? 'Quản lý').toString(),
    createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ?? DateTime.now(),
    completedAt: map['completed_at'] != null ? DateTime.tryParse(map['completed_at'].toString()) : null,
    completedBy: map['completed_by']?.toString(),
    foundLocation: map['found_location']?.toString(),
    notes: map['notes']?.toString(),
  );
}

/// Loại sự kiện vòng đời thẻ RFID
enum TagLifecycleAction {
  encoded('ENCODED', 'Khởi tạo & Gán mã RFID', 0xFF3B82F6),
  inboundGate('INBOUND_GATE', 'Nhập kho qua cổng RFID', 0xFF10B981),
  inboundPda('INBOUND_PDA', 'Nhập kho trên PDA', 0xFF059669),
  palletize('PALLETIZE', 'Xếp vào Pallet', 0xFF0284C7),
  putaway('PUTAWAY', 'Cất lên vị trí kệ', 0xFF0D9488),
  transferLocation('TRANSFER_LOC', 'Điều chuyển vị trí kệ', 0xFFF59E0B),
  transferPallet('TRANSFER_PALLET', 'Chuyển sang Pallet khác', 0xFFD97706),
  mergePallet('MERGE_PALLET', 'Dồn gộp Pallet', 0xFFEA580C),
  auditMatch('AUDIT_MATCH', 'Kiểm kê khớp chuẩn', 0xFF10B981),
  auditMisplaced('AUDIT_MISPLACED', 'Kiểm kê sai vị trí', 0xFFF59E0B),
  auditMissing('AUDIT_MISSING', 'Kiểm kê phát hiện thiếu', 0xFFEF4444),
  auditFound('AUDIT_FOUND', 'Kiểm kê tìm lại được', 0xFF8B5CF6),
  locateFound('LOCATE_FOUND', 'Tìm thấy bằng Radar AirTag', 0xFF06B6D4),
  allocatePo('ALLOCATE_PO', 'Giữ chỗ cho đơn xuất', 0xFF8B5CF6),
  picked('PICKED', 'Đã lấy hàng từ kệ', 0xFFEC4899),
  recall('RECALL', 'Thu hồi sản phẩm', 0xFFDC2626),
  repair('REPAIR', 'Sửa chữa / Bảo hành', 0xFFE11D48),
  repairDone('REPAIR_DONE', 'Hoàn trả kho sau sửa chữa', 0xFF10B981),
  outboundGate('OUTBOUND_GATE', 'Xuất kho qua cổng RFID', 0xFF64748B),
  outboundPda('OUTBOUND_PDA', 'Xuất kho trên PDA', 0xFF475569),
  unauthorizedExit('UNAUTHORIZED_EXIT', 'Cảnh báo qua cổng trái phép', 0xFFEF4444),
  statusChange('STATUS_CHANGE', 'Thay đổi trạng thái', 0xFF6366F1);

  final String code;
  final String label;
  final int colorValue;
  const TagLifecycleAction(this.code, this.label, this.colorValue);

  static TagLifecycleAction fromCode(String? code) {
    if (code == null) return TagLifecycleAction.statusChange;
    final upper = code.trim().toUpperCase();
    return TagLifecycleAction.values.firstWhere(
      (a) => a.code == upper,
      orElse: () => TagLifecycleAction.statusChange,
    );
  }
}

/// Bản ghi nhật ký vòng đời thẻ RFID (Tag Lifecycle Log / Audit Trail)
class TagLifecycleLog {
  final String logId;
  final String epc;
  final String? itemId;
  final String? sku;
  final String? productName;
  final String? serialNumber;
  final TagLifecycleAction action;
  final String? previousStatus;
  final String newStatus;
  final String? fromLocation;
  final String? toLocation;
  final String? fromPallet;
  final String? toPallet;
  final String? documentNo;
  final String performedBy;
  final String? device;
  final DateTime timestamp;
  final String? notes;

  TagLifecycleLog({
    required this.logId,
    required this.epc,
    this.itemId,
    this.sku,
    this.productName,
    this.serialNumber,
    required this.action,
    this.previousStatus,
    required this.newStatus,
    this.fromLocation,
    this.toLocation,
    this.fromPallet,
    this.toPallet,
    this.documentNo,
    required this.performedBy,
    this.device,
    required this.timestamp,
    this.notes,
  });

  Map<String, dynamic> toMap() => {
    'log_id': logId,
    'epc': epc,
    'item_id': itemId,
    'sku': sku,
    'product_name': productName,
    'serial_number': serialNumber,
    'action': action.code,
    'action_label': action.label,
    'previous_status': previousStatus,
    'new_status': newStatus,
    'from_location': fromLocation,
    'to_location': toLocation,
    'from_pallet': fromPallet,
    'to_pallet': toPallet,
    'document_no': documentNo,
    'performed_by': performedBy,
    'device': device,
    'timestamp': timestamp.toIso8601String(),
    'notes': notes,
  };

  factory TagLifecycleLog.fromMap(Map<String, dynamic> map) => TagLifecycleLog(
    logId: (map['log_id'] ?? '').toString(),
    epc: (map['epc'] ?? '').toString(),
    itemId: map['item_id']?.toString(),
    sku: map['sku']?.toString(),
    productName: map['product_name']?.toString(),
    serialNumber: map['serial_number']?.toString(),
    action: TagLifecycleAction.fromCode(map['action']?.toString()),
    previousStatus: map['previous_status']?.toString(),
    newStatus: (map['new_status'] ?? '').toString(),
    fromLocation: map['from_location']?.toString(),
    toLocation: map['to_location']?.toString(),
    fromPallet: map['from_pallet']?.toString(),
    toPallet: map['to_pallet']?.toString(),
    documentNo: map['document_no']?.toString(),
    performedBy: (map['performed_by'] ?? 'Hệ thống').toString(),
    device: map['device']?.toString(),
    timestamp: DateTime.tryParse(map['timestamp']?.toString() ?? '') ?? DateTime.now(),
    notes: map['notes']?.toString(),
  );
}


