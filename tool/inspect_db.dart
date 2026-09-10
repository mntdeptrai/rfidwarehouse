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
    print('--- Checking: $dbPath ---');
    if (!File(dbPath).existsSync()) {
      print('File not found!');
      continue;
    }
    final db = await databaseFactory.openDatabase(dbPath);
    final locs = await db.query('locations');
    print('Total locations: ${locs.length}');
    for (var l in locs) {
      print('  loc: ${l['location_id']} | code: ${l['location_code']} | shelf: ${l['shelf']} | zone: ${l['zone']}');
    }
    await db.close();
  }
  exit(0);
}
