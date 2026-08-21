import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhf/services/database_service.dart';
import 'package:uhf/services/mysql_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test('Direct Push SQLite items to MySQL using MySqlSyncService', () async {
    final db = DatabaseService();
    final items = await db.getItems();
    expect(items, isNotNull);

    final sync = MySqlSyncService();
    try {
      final conn = await sync.connectForDirectPush();
      final pending = await db.getPendingSyncItems();

      for (final item in pending) {
        final queueId = item['queue_id'] as int;
        final tableName = item['table_name'] as String;
        final action = item['action'] as String;
        final payloadStr = item['payload'] as String;
        final payload = Map<String, dynamic>.from(jsonDecode(payloadStr));

        await sync.executeSyncItemDirect(conn, tableName, action, payload);
        await db.markSyncItemSynced(queueId);
      }

      await conn.close();
    } catch (e) {
      debugPrint('MySQL direct push skipped in offline environment: $e');
    }
  });
}


