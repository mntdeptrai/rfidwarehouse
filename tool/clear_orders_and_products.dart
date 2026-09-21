import 'package:supabase/supabase.dart';

void main() async {
  print('Connecting to Supabase...');
  final supa = SupabaseClient(
    'https://zhtcfuiukbapwohxbfst.supabase.co',
    'sb_publishable_pDziBQC31EC32FzD-EuauA_3Lamf5JT',
  );

  print('\n=== BẮT ĐẦU XÓA SẠCH DỮ LIỆU ĐƠN HÀNG VÀ SẢN PHẨM ===\n');

  // Thứ tự xóa theo quan hệ phụ thuộc Foreign Keys:
  // 1. Chi tiết phiếu xuất -> Phiếu xuất
  // 2. Chi tiết đơn xuất (PO) -> Đơn xuất
  // 3. Chi tiết đơn nhập -> Đơn nhập
  // 4. Chi tiết phiên kiểm kê -> Phiên kiểm kê
  // 5. Giao dịch biến động kho & sync logs
  // 6. Chi tiết hàng hóa / thẻ RFID (items)
  // 7. Danh mục mặt hàng / sản phẩm (products)

  final steps = [
    {'table': 'delivery_note_details', 'pk': 'id', 'label': 'Chi tiết phiếu xuất kho'},
    {'table': 'delivery_notes', 'pk': 'delivery_id', 'label': 'Phiếu xuất kho'},
    {'table': 'outbound_order_details', 'pk': 'id', 'label': 'Chi tiết đơn hàng xuất (PO)'},
    {'table': 'outbound_orders', 'pk': 'outbound_order_id', 'label': 'Đơn hàng xuất kho'},
    {'table': 'inbound_order_details', 'pk': 'id', 'label': 'Chi tiết đơn hàng nhập'},
    {'table': 'inbound_orders', 'pk': 'inbound_order_id', 'label': 'Đơn hàng nhập kho'},
    {'table': 'inventory_session_details', 'pk': 'id', 'label': 'Chi tiết phiên kiểm kê'},
    {'table': 'inventory_sessions', 'pk': 'session_id', 'label': 'Phiên kiểm kê'},
    {'table': 'inventory_transactions', 'pk': 'transaction_id', 'label': 'Lịch sử giao dịch kho'},
    {'table': 'sync_logs', 'pk': 'id', 'label': 'Nhật ký đồng bộ'},
    {'table': 'items', 'pk': 'item_id', 'label': 'Danh sách hàng hóa & thẻ RFID (items)'},
    {'table': 'products', 'pk': 'product_id', 'label': 'Danh mục sản phẩm (products)'},
  ];

  for (final step in steps) {
    final table = step['table']!;
    final pk = step['pk']!;
    final label = step['label']!;

    try {
      final rows = await supa.from(table).select(pk);
      final count = rows.length;
      if (count == 0) {
        print('✓ $label ($table): 0 bản ghi (đã rỗng)');
        continue;
      }

      print('-> Đang xóa $count bản ghi từ $label ($table)...');
      for (final r in rows) {
        final idVal = r[pk];
        await supa.from(table).delete().eq(pk, idVal);
      }
      print('✓ ĐÃ XÓA THÀNH CÔNG $count bản ghi từ $label ($table)');
    } catch (e) {
      print('✗ Lỗi khi xóa $label ($table): $e');
    }
  }

  // Cập nhật lại pallet: reset về trạng thái trống (0 hàng hóa)
  try {
    print('\n-> Đang kiểm tra danh sách Pallet...');
    final pallets = await supa.from('pallets').select();
    print('  Số lượng Pallet: ${pallets.length}');
    for (final p in pallets) {
      final pId = p['pallet_id'];
      await supa.from('pallets').update({
        'status': 'EMPTY',
        'current_items': 0,
      }).eq('pallet_id', pId);
    }
    print('✓ Đã cập nhật trạng thái các Pallet về EMPTY (0 hàng hóa).');
  } catch (e) {
    print('✗ Lỗi khi cập nhật pallet: $e');
  }

  // Cập nhật lại trạng thái các kệ kho: reset về AVAILABLE
  try {
    print('\n-> Đang kiểm tra trạng thái Kệ kho (locations)...');
    final locs = await supa.from('locations').select();
    print('  Số lượng Kệ kho: ${locs.length}');
    for (final l in locs) {
      final lId = l['location_id'];
      await supa.from('locations').update({
        'status': 'AVAILABLE',
        'current_pallets': 0,
      }).eq('location_id', lId);
    }
    print('✓ Đã cập nhật trạng thái các Kệ kho về AVAILABLE (Trống).');
  } catch (e) {
    print('✗ Lỗi khi cập nhật kệ kho: $e');
  }

  print('\n=== KIỂM TRA LẠI SỐ LƯỢNG BẢN GHI SAU KHI XÓA ===\n');
  for (final step in steps) {
    final table = step['table']!;
    final label = step['label']!;
    try {
      final res = await supa.from(table).select();
      print('  $label ($table): ${res.length} bản ghi');
    } catch (e) {
      print('  $label ($table): ERROR ($e)');
    }
  }
  print('\n=== HOÀN TẤT DỌN DẸP DỮ LIỆU ===');
}
