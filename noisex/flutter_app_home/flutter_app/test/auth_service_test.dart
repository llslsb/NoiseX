import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/services/auth_service.dart';

void main() {
  group('AuthService', () {
    final auth = AuthService();

    test('generateUUID matches server-side UUID contract', () {
      // 服务端 AuthRequest 正则：^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$
      // 旧版 32 位无连字符随机串会被 400 拒收（注册永远失败，见联调缺陷档案 B7）
      final serverPattern = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$');
      for (var i = 0; i < 100; i++) {
        expect(auth.generateUUID(), matches(serverPattern));
      }
    });

    test('generateUUID is a valid UUID v4 (version and variant bits)', () {
      final uuid = auth.generateUUID().split('-');
      expect(uuid[2][0], equals('4'));
      expect('89ab'.contains(uuid[3][0]), isTrue);
    });

    test('generateUUID generates unique values', () {
      final uuids = <String>{};
      for (var i = 0; i < 100; i++) {
        uuids.add(auth.generateUUID());
      }
      expect(uuids.length, equals(100));
    });

    test('isAuthenticated is false when no JWT', () {
      final freshAuth = AuthService();
      expect(freshAuth.isAuthenticated, isFalse);
    });

    test('jwt is null initially', () {
      final freshAuth = AuthService();
      expect(freshAuth.jwt, isNull);
    });

    test('userId is null initially', () {
      final freshAuth = AuthService();
      expect(freshAuth.userId, isNull);
    });
  });
}
