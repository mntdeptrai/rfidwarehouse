import 'dart:async';
import '../models/wms_models.dart';
import '../services/warehouse_repository.dart';

/// Đặc tả cấu hình của tài sản trong kịch bản Demo
class DemoAssetSpec {
  final String sku;
  final String name;
  final String category;
  final String unit;
  final String tagGroup;
  final int maxQty;
  final List<String> fixedEpcs;

  const DemoAssetSpec({
    required this.sku,
    required this.name,
    required this.category,
    required this.unit,
    required this.tagGroup,
    required this.maxQty,
    required this.fixedEpcs,
  });
}

/// Gói dữ liệu phiếu nhập demo được sinh tự động theo số lượng và tài sản được chọn
class DemoInboundPackage {
  final InboundOrder order;
  final List<Item> items;
  final List<Product> products;
  final String palletCode;
  final String supplier;

  DemoInboundPackage({
    required this.order,
    required this.items,
    required this.products,
    required this.palletCode,
    required this.supplier,
  });
}

/// Service quản lý kịch bản tạo phiếu nhập kho và tự sinh các mã EPC cố định
class InboundDemoScenarioService {
  /// Chuẩn hóa mã EPC (chuyển chữ thường sang hoa, thay chữ O thành số 0)
  static String normalizeEpc(String epc) {
    return epc.trim().toUpperCase().replaceAll('O', '0');
  }

  /// Tài sản 1: Thiết bị tủ rack (1-3 bộ)
  static const DemoAssetSpec rackUnit = DemoAssetSpec(
    sku: 'RACK-SRV-01',
    name: 'Thiết bị tủ rack',
    category: 'Linh kiện tủ server',
    unit: 'Bộ',
    tagGroup: 'Thẻ On-Metal: Dán linh kiện tủ server',
    maxQty: 3,
    fixedEpcs: [
      'E28011C0A500006673BC32E3',
      'E28011C0A500006673BC6213',
      'E28011C0A500006673BC6223',
    ],
  );

  /// Tài sản 2: Hộp sắt đựng chứng từ (1-10 hộp)
  static const DemoAssetSpec metalBox = DemoAssetSpec(
    sku: 'BOX-MET-01',
    name: 'Hộp sắt đựng chứng từ',
    category: 'Hộp kim loại / Hồ sơ chứng từ',
    unit: 'Hộp',
    tagGroup: 'Thẻ On-Metal: Dán hộp kim loại, gáy hồ sơ chứng từ',
    maxQty: 10,
    fixedEpcs: [
      'E280689400005024B0765C5A',
      'E280689400005024B0765C5C',
      'E280689400004024B0765C5B',
      'E280689400004024B0765C5D',
      'E280689400004024B0765C5E',
      'E280689400005024B0765C5F',
      'E280689400005024B0765C60',
      'E280689400004024B0765C61',
      'E280689400004024B0765C62',
      'E280689400005024B0765C63',
    ],
  );

  /// Danh sách toàn bộ các cấu hình tài sản demo
  static const List<DemoAssetSpec> allAssetSpecs = [rackUnit, metalBox];

  /// Sinh gói dữ liệu phiếu nhập kho dựa theo số lượng người dùng chỉ định
  static DemoInboundPackage buildDemoPackage({
    required String orderNo,
    String supplier = 'Công ty Cổ phần Thiết Bị Công Nghệ Nhật Minh',
    String palletCode = 'PL01',
    int rackQty = 3,
    int boxQty = 10,
  }) {
    final cleanOrderNo = orderNo.trim().toUpperCase();
    final cleanPallet = palletCode.trim().toUpperCase().isEmpty ? 'PL01' : palletCode.trim().toUpperCase();
    final products = <Product>[];
    final details = <InboundOrderDetail>[];
    final items = <Item>[];
    final now = DateTime.now();

    // 1. Sinh các mã cho Thiết bị tủ rack (tối đa 3 bộ)
    if (rackQty > 0) {
      final actualRackQty = rackQty.clamp(1, rackUnit.fixedEpcs.length);
      final prod = Product(
        productId: 'PROD-RACK-01',
        sku: rackUnit.sku,
        productName: rackUnit.name,
        category: rackUnit.category,
        unit: rackUnit.unit,
        description: rackUnit.tagGroup,
      );
      products.add(prod);

      details.add(InboundOrderDetail(
        productId: prod.productId,
        sku: prod.sku,
        productName: prod.productName,
        requiredQty: actualRackQty,
        receivedQty: 0,
      ));

      for (int i = 0; i < actualRackQty; i++) {
        final epc = normalizeEpc(rackUnit.fixedEpcs[i]);
        final indexStr = (i + 1).toString().padLeft(3, '0');
        items.add(Item(
          itemId: 'ITM-$cleanOrderNo-RACK-$indexStr',
          productId: prod.productId,
          sku: prod.sku,
          productName: prod.productName,
          serialNumber: 'SRV-RK-$indexStr',
          epc: epc,
          status: ItemStatus.pendingInbound,
          orderNo: cleanOrderNo,
          palletId: cleanPallet,
          supplier: supplier,
          cartonCode: 'BOX-RACK-01',
        ));
      }
    }

    // 2. Sinh các mã cho Hộp sắt đựng chứng từ (tối đa 10 hộp)
    if (boxQty > 0) {
      final actualBoxQty = boxQty.clamp(1, metalBox.fixedEpcs.length);
      final prod = Product(
        productId: 'PROD-BOX-01',
        sku: metalBox.sku,
        productName: metalBox.name,
        category: metalBox.category,
        unit: metalBox.unit,
        description: metalBox.tagGroup,
      );
      products.add(prod);

      details.add(InboundOrderDetail(
        productId: prod.productId,
        sku: prod.sku,
        productName: prod.productName,
        requiredQty: actualBoxQty,
        receivedQty: 0,
      ));

      for (int i = 0; i < actualBoxQty; i++) {
        final epc = normalizeEpc(metalBox.fixedEpcs[i]);
        final indexStr = (i + 1).toString().padLeft(3, '0');
        items.add(Item(
          itemId: 'ITM-$cleanOrderNo-BOX-$indexStr',
          productId: prod.productId,
          sku: prod.sku,
          productName: prod.productName,
          serialNumber: 'DOC-BX-$indexStr',
          epc: epc,
          status: ItemStatus.pendingInbound,
          orderNo: cleanOrderNo,
          palletId: cleanPallet,
          supplier: supplier,
          cartonCode: 'BOX-DOC-${(i ~/ 5) + 1}',
        ));
      }
    }

    final order = InboundOrder(
      inboundOrderId: cleanOrderNo,
      orderNo: cleanOrderNo,
      sourceSupplier: supplier,
      status: InboundOrderStatus.newOrder,
      createdAt: now,
      details: details,
    );

    return DemoInboundPackage(
      order: order,
      items: items,
      products: products,
      palletCode: cleanPallet,
      supplier: supplier,
    );
  }

  /// Lưu gói phiếu nhập demo vào In-Memory Repository và đồng bộ trực tiếp Supabase Cloud (Không dùng SQLite)
  static Future<void> saveDemoPackageToRepository(
    WarehouseRepository repo,
    DemoInboundPackage package,
  ) async {
    if (package.products.isNotEmpty) {
      await repo.addProductsBatch(package.products);
    }
    if (package.palletCode.isNotEmpty) {
      await repo.registerOrUpdatePallet(
        palletCode: package.palletCode,
        rfidEpc: '',
      );
    }
    await repo.addInboundOrder(package.order, autoGenerateEpcs: false);
    if (package.items.isNotEmpty) {
      await repo.insertDirectItems(package.items);
    }
  }
}
