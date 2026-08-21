import 'package:flutter_test/flutter_test.dart';
import 'package:uhf/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ApiService Tests', () {
    test('ApiService singleton and baseUrl configuration', () {
      final api = ApiService();
      expect(api.baseUrl, contains('/api'));

      api.setBaseUrl('192.168.1.50:3000');
      expect(api.baseUrl, equals('http://192.168.1.50:3000/api'));

      api.setBaseUrl('http://127.0.0.1:3000');
      expect(api.baseUrl, equals('http://127.0.0.1:3000/api'));
    });
  });
}
