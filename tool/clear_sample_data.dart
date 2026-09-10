// ignore_for_file: avoid_print
import 'dart:io';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() async {
  sqfliteFfiInit();
  final databaseFactory = databaseFactoryFfi;
  final dbPath = 'C:\\Users\\admin\\AppData\\Roaming\\com.example\\uhf\\databases\\c72e_wms_clean_v3.db';
  final db = await databaseFactory.openDatabase(dbPath);

  print('Bắt đầu xóa toàn bộ dữ liệu mẫu trong CSDL...');

  // 1. Xóa toàn bộ đơn nhập/xuất, items, chi tiết
  await db.delete('sync_queue');
  await db.delete('inventory_session_details');
  await db.delete('inventory_sessions');
  await db.delete('delivery_note_details');
  await db.delete('delivery_notes');
  await db.delete('outbound_order_details');
  await db.delete('outbound_orders');
  await db.delete('inbound_order_details');
  await db.delete('inbound_orders');
  await db.delete('items');
  await db.delete('pallets');
  await db.delete('products');
  await db.delete('customers');

  // 2. Xóa toàn bộ vị trí kệ mẫu (CSDL trống hoàn toàn, người dùng tự thêm và sửa)
  await db.delete('locations');

  // 3. Reset file JSON backup pallet
  final jsonPath = 'C:\\Users\\admin\\AppData\\Roaming\\com.example\\uhf\\databases\\pallets_permanent_master.json';
  final jsonFile = File(jsonPath);
  if (jsonFile.existsSync()) {
    await jsonFile.writeAsString('[]');
  }

  print('Đã xóa sạch toàn bộ dữ liệu mẫu trong CSDL (bao gồm sản phẩm, đơn hàng, pallet, vị trí kệ).');
  print('CSDL đã ở trạng thái trống hoàn toàn để người dùng tự thêm và sửa dữ liệu thực tế.');
  await db.close();
  exit(0);
}
