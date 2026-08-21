import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uhf/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  testWidgets('RFID WMS App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RfidWmsApp());
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.byType(RfidWmsApp), findsOneWidget);
  });
}
