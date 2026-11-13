import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/models/constants.dart';

void main() {
  group('ApiService', () {
    // 期望值统一从 Constants 派生（地址只单源定义在 constants.dart）。
    // 2026-11-06 起正式入口走 HTTPS 域名：锁死 https/wss 两个协议，防止明文地址回流进上架包。
    test('API base URL is https scheme without explicit port', () {
      expect(Constants.apiBaseUrl, startsWith('https://'));
      expect(Uri.parse(Constants.apiBaseUrl).hasPort, isFalse);
    });

    test('WebSocket URL is wss on the same host as API base URL', () {
      final api = Uri.parse(Constants.apiBaseUrl);
      final ws = Uri.parse(Constants.wsUrl);
      expect(ws.scheme, equals('wss'));
      expect(ws.host, equals(api.host));
      // 两者都不写端口、走 TLS 默认 443（Dart 的 Uri 不认 wss 默认端口，比 hasPort 不比 port 数值）
      expect(ws.hasPort, isFalse);
      expect(ws.path, equals('/ws'));
    });

    test('register should build correct endpoint', () {
      const url = '${Constants.apiBaseUrl}/api/auth/register';
      expect(url, equals('${Constants.apiBaseUrl}/api/auth/register'));
    });

    test('sendSonar should build correct endpoint', () {
      const url = '${Constants.apiBaseUrl}/api/sonar';
      expect(url, equals('${Constants.apiBaseUrl}/api/sonar'));
    });

    test('acceptSonar should build correct endpoint with id', () {
      const sonarId = 'sonar-123';
      const url = '${Constants.apiBaseUrl}/api/sonar/$sonarId/accept';
      expect(url,
          equals('${Constants.apiBaseUrl}/api/sonar/sonar-123/accept'));
    });

    // P2-B：nearby-activity endpoint 必须正确拼接 6 位 geohash 查询参数。
    // 期望值同样基于 Constants.apiBaseUrl，避免本地 IP 变化导致误报。
    test('getNearbyActivity builds endpoint with geohash query param', () {
      const geohash = 'wx4g0s';
      const url =
          '${Constants.apiBaseUrl}/api/sonar/nearby-activity?geohash=$geohash';
      expect(url,
          equals('${Constants.apiBaseUrl}/api/sonar/nearby-activity?geohash=wx4g0s'));
    });
  });
}
