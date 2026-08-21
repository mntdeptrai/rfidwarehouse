import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:uhf/services/database_service.dart';
import 'package:uhf/services/mysql_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Direct Push SQLite items to MySQL using MySqlSyncService', () async {
    final db = DatabaseService();
    final items = await db.getItems();
    print('Found ${items.length} items in SQLite');

    // Also push the 10 chips from CARTONTEST0001 that the user mentioned
    final testCartonEpcs = [
      'ABCDEF000000000000000010',
      'ABCDEF000000000000000008',
      'ABCDEF000000000000000009',
      'ABCDEF000000000000000006',
      'ABCDEF000000000000000007',
      'ABCDEF000000000000000005',
      'ABCDEF000000000000000003',
      'ABCDEF000000000000000004',
      'ABCDEF000000000000000002',
      'ABCDEF000000000000000001',
    ];

    await db.enqueueSync(
      tableName: 'inbound_transactions',
      recordId: 'CARTONTEST0001',
      action: 'INBOUND_PDA_CONFIRM',
      payload: {
        'orderNo': 'CARTONTEST0001',
        'palletCode': 'PL-01',
        'locationId': 'LOC-A1-01-01',
        'epcs': testCartonEpcs,
        'sku': '8930000000001',
        'productName': 'Product Test 01',
        'performedBy': 'Thủ kho PDA',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    final sync = MySqlSyncService();
    final conn = await sync.connectForDirectPush();
    final pending = await db.getPendingSyncItems();
    print('Pending sync items count: ${pending.length}');

    for (final item in pending) {
      final queueId = item['queue_id'] as int;
      final tableName = item['table_name'] as String;
      final action = item['action'] as String;
      final payloadStr = item['payload'] as String;
      final payload = Map<String, dynamic>.from(jsonDecode(payloadStr));

      await sync.executeSyncItemDirect(conn, tableName, action, payload);
      await db.markSyncItemSynced(queueId);
      print('Direct synced item $queueId on $tableName');
    }

    await conn.close();
    print('All items successfully pushed to MySQL!');
  });
}
