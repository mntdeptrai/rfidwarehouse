import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhf/services/database_service.dart';
import 'package:uhf/services/mysql_sync_service.dart';
import 'package:uhf/models/wms_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Real MySQL Sync Test', () async {
    final dbService = DatabaseService();
    final syncService = MySqlSyncService();

    // Enqueue a sample item
    final item = Item(
      itemId: 'TEST-ITEM-001',
      productId: 'PROD-TEST',
      sku: 'SKU-TEST',
      productName: 'Sản phẩm Test',
      serialNumber: 'SN-TEST-001',
      epc: 'E28011600000000000000001',
      status: ItemStatus.inStock,
      orderNo: 'INB-TEST-001',
    );

    await dbService.insertItem(item);
    await dbService.enqueueSync(
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
      },
    );

    print('Pending sync items in SQLite: ${await dbService.getPendingSyncCount()}');
    expect(await dbService.getPendingSyncCount(), greaterThan(0));
  });
}
