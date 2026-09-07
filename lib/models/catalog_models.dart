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
