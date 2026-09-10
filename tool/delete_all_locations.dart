// ignore_for_file: avoid_print
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;
  final paths = [
    'C:\\Users\\admin\\AppData\\Roaming\\com.example\\uhf\\databases\\c72e_wms_clean_v3.db',
    'C:\\Users\\admin\\AppData\\Roaming\\RFIDWarehouse\\databases\\c72e_wms_clean_v3.db',
  ];

  for (final dbPath in paths) {
    if (!File(dbPath).existsSync()) continue;
    print('--- Deleting locations in: $dbPath ---');
    final db = await databaseFactory.openDatabase(dbPath);
    
    final res1 = await db.rawQuery('SELECT count(*) as cnt FROM locations');
    print('Locations before: ${res1.first['cnt']}');

    await db.delete('locations');
    await db.rawUpdate('UPDATE pallets SET location_id = NULL');
    await db.rawUpdate('UPDATE items SET location_id = NULL');

    final res2 = await db.rawQuery('SELECT count(*) as cnt FROM locations');
    print('Locations after: ${res2.first['cnt']}');
    await db.close();
  }
  print('✅ Hoàn tất xóa sạch toàn bộ kệ trong cơ sở dữ liệu!');
  exit(0);
}
