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

    final sync = MySqlSyncService();
    final conn = await sync.connectForDirectPush();
    if (conn == null) {
      print('MySQL is not reachable in this test environment, skipping live push.');
      return;
    }

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
    print('All pending items successfully pushed to MySQL!');
  });
}

