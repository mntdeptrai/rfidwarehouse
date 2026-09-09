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

/// Vị trí lưu kho (Location)
class Location {
  final String locationId;
  final String locationCode;
  final String zone;
  final String shelf;
  final String level;
  final int maxPalletCapacity;
  int currentPallets;
  String status; // 'AVAILABLE' (Còn trống nhiều), 'NEAR_FULL' (Sắp hết chỗ), 'FULL' (Kệ đầy)


  final String aisleSide; // 'LEFT' (Dãy Trái), 'RIGHT' (Dãy Phải), 'BACK' (Cuối kho), 'CENTER' (Ở giữa)
  final int sortOrder; // Thứ tự dọc theo lối đi từ Cổng vào trong (1, 2, 3...)
  final int gridRow; // Tọa độ hàng (nếu dùng ma trận lưới)
  final int gridCol; // Tọa độ cột (nếu dùng ma trận lưới)

  Location({
    required this.locationId,
    required this.locationCode,
    required this.zone,
    required this.shelf,
    required this.level,
    this.maxPalletCapacity = 1,
    this.currentPallets = 0,
    this.status = 'AVAILABLE',
    this.aisleSide = 'LEFT',
    this.sortOrder = 0,
    this.gridRow = 0,
    this.gridCol = 0,
  });

  /// Tên hiển thị chuẩn của Kệ kho (Ví dụ: "KỆ A1", "KỆ B1", "CỔNG GATE (IN)")
  String get displayName {
    final rawShelf = shelf.trim();
    final isPureNumber = RegExp(r'^\d+$').hasMatch(rawShelf);
    if (!isPureNumber && rawShelf.isNotEmpty) {
      final upper = rawShelf.toUpperCase();
      if (upper.startsWith('KỆ') || upper.startsWith('CỔNG') || upper.startsWith('GATE')) {
        return upper;
      }
      return 'KỆ $upper';
    }

    final code = locationCode.trim().toUpperCase();
    final parts = code.split('-');
    if (parts.length >= 2) {
      final part1 = parts[1];
      if (part1 == 'GATE' || code.contains('GATE')) {
        if (parts.length >= 3 && (parts[2] == 'IN' || parts[2] == 'OUT')) {
          return 'CỔNG GATE (${parts[2]})';
        }
        return 'CỔNG GATE';
      }
      if (part1.isNotEmpty && !RegExp(r'^\d+$').hasMatch(part1)) {
        return 'KỆ $part1';
      }
    }

    if (rawShelf.isNotEmpty && zone.isNotEmpty) {
      final zoneClean = zone.toUpperCase().replaceAll('KHU', '').trim();
      return 'KỆ $zoneClean$rawShelf';
    }

    return rawShelf.isNotEmpty ? 'KỆ $rawShelf' : locationCode;
  }

  /// Thông tin phụ: Khu vực • Tầng (Location Code)
  String get displaySubtitle {
    String zoneStr = zone.trim();
    if (zoneStr.isNotEmpty && !zoneStr.toUpperCase().startsWith('KHU') && zoneStr.toUpperCase() != 'GATE') {
      zoneStr = 'Khu $zoneStr';
    }

    String levelStr = level.trim();
    if (levelStr.isNotEmpty && !levelStr.toUpperCase().startsWith('TẦNG') && levelStr != '00') {
      levelStr = 'Tầng $levelStr';
    } else if (levelStr == '00') {
      levelStr = '';
    }

    final prefix = [zoneStr, levelStr].where((s) => s.isNotEmpty).join(' • ');
    return prefix.isNotEmpty ? '$prefix ($locationCode)' : locationCode;
  }

  Location copyWith({
    String? locationId,
    String? locationCode,
    String? zone,
    String? shelf,
    String? level,
    int? maxPalletCapacity,
    int? currentPallets,
    String? status,
    String? aisleSide,
    int? sortOrder,
    int? gridRow,
    int? gridCol,
  }) {
    return Location(
      locationId: locationId ?? this.locationId,
      locationCode: locationCode ?? this.locationCode,
      zone: zone ?? this.zone,
      shelf: shelf ?? this.shelf,
      level: level ?? this.level,
      maxPalletCapacity: maxPalletCapacity ?? this.maxPalletCapacity,
      currentPallets: currentPallets ?? this.currentPallets,
      status: status ?? this.status,
      aisleSide: aisleSide ?? this.aisleSide,
      sortOrder: sortOrder ?? this.sortOrder,
      gridRow: gridRow ?? this.gridRow,
      gridCol: gridCol ?? this.gridCol,
    );
  }

  Map<String, dynamic> toMap() => {
    'location_id': locationId,
    'location_code': locationCode,
    'zone': zone,
    'shelf': shelf,
    'level': level,
    'max_pallet_capacity': maxPalletCapacity,
    'current_pallets': currentPallets,
    'status': status,
    'aisle_side': aisleSide,
    'sort_order': sortOrder,
    'grid_row': gridRow,
    'grid_col': gridCol,
  };

  Map<String, dynamic> toJson() => toMap();

  factory Location.fromMap(Map<String, dynamic> map) {
    return Location(
      locationId: map['location_id'] as String? ?? '',
      locationCode: map['location_code'] as String? ?? '',
      zone: map['zone'] as String? ?? '',
      shelf: map['shelf'] as String? ?? '',
      level: map['level'] as String? ?? '',
      maxPalletCapacity: (map['max_pallet_capacity'] as int?) ?? 1,
      currentPallets: (map['current_pallets'] as int?) ?? 0,
      status: (map['status'] as String?) ?? 'AVAILABLE',
      aisleSide: (map['aisle_side'] as String?) ?? 'LEFT',
      sortOrder: (map['sort_order'] as int?) ?? 0,
      gridRow: (map['grid_row'] as int?) ?? 0,
      gridCol: (map['grid_col'] as int?) ?? 0,
    );
  }
}

/// Kiểu bố cục sơ đồ mặt bằng kho thực tế
enum WarehouseLayoutType {
  /// 2 Dãy kệ song song, xe nâng chạy lối đi chính ở giữa
  parallelAisles,
  /// Sơ đồ chữ U (Kệ bên trái, kệ cuối kho, kệ bên phải)
  uShape,
  /// Sơ đồ lưới phân khu đa dãy (Grid Matrix)
  multiAisleGrid,
}

/// Cấu hình sơ đồ mặt bằng kho theo thực tế khách hàng
class WarehouseFloorPlanConfig {
  final WarehouseLayoutType layoutType;
  final String warehouseName;
  final String entryGateName;
  final String exitGateName;
  final bool isSingleGate;
  final String mainAisleLabel;
  final int aisleWidth; // 1 to 5 visual scale

  const WarehouseFloorPlanConfig({
    this.layoutType = WarehouseLayoutType.parallelAisles,
    this.warehouseName = 'KHO HÀNG TRUNG TÂM',
    this.entryGateName = 'CỔNG NHẬP (GATE IN)',
    this.exitGateName = 'CỔNG XUẤT (GATE OUT)',
    this.isSingleGate = false,
    this.mainAisleLabel = 'LỐI ĐI CHÍNH XE NÂNG (FORKLIFT AISLE)',
    this.aisleWidth = 2,
  });

  factory WarehouseFloorPlanConfig.defaultConfig() {
    return const WarehouseFloorPlanConfig();
  }

  WarehouseFloorPlanConfig copyWith({
    WarehouseLayoutType? layoutType,
    String? warehouseName,
    String? entryGateName,
    String? exitGateName,
    bool? isSingleGate,
    String? mainAisleLabel,
    int? aisleWidth,
  }) {
    return WarehouseFloorPlanConfig(
      layoutType: layoutType ?? this.layoutType,
      warehouseName: warehouseName ?? this.warehouseName,
      entryGateName: entryGateName ?? this.entryGateName,
      exitGateName: exitGateName ?? this.exitGateName,
      isSingleGate: isSingleGate ?? this.isSingleGate,
      mainAisleLabel: mainAisleLabel ?? this.mainAisleLabel,
      aisleWidth: aisleWidth ?? this.aisleWidth,
    );
  }

  Map<String, dynamic> toJson() => {
    'layoutType': layoutType.name,
    'warehouseName': warehouseName,
    'entryGateName': entryGateName,
    'exitGateName': exitGateName,
    'isSingleGate': isSingleGate,
    'mainAisleLabel': mainAisleLabel,
    'aisleWidth': aisleWidth,
  };

  factory WarehouseFloorPlanConfig.fromJson(Map<String, dynamic> json) {
    WarehouseLayoutType parsedType = WarehouseLayoutType.parallelAisles;
    final typeStr = json['layoutType']?.toString() ?? '';
    for (var t in WarehouseLayoutType.values) {
      if (t.name == typeStr) {
        parsedType = t;
        break;
      }
    }

    return WarehouseFloorPlanConfig(
      layoutType: parsedType,
      warehouseName: json['warehouseName'] as String? ?? 'KHO HÀNG TRUNG TÂM',
      entryGateName: json['entryGateName'] as String? ?? 'CỔNG NHẬP (GATE IN)',
      exitGateName: json['exitGateName'] as String? ?? 'CỔNG XUẤT (GATE OUT)',
      isSingleGate: (json['isSingleGate'] as bool?) ?? false,
      mainAisleLabel: json['mainAisleLabel'] as String? ?? 'LỐI ĐI CHÍNH XE NÂNG (FORKLIFT AISLE)',
      aisleWidth: (json['aisleWidth'] as int?) ?? 2,
    );
  }
}

