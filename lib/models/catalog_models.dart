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

  Location({
    required this.locationId,
    required this.locationCode,
    required this.zone,
    required this.shelf,
    required this.level,
    this.maxPalletCapacity = 1,
    this.currentPallets = 0,
    this.status = 'AVAILABLE',
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
}
