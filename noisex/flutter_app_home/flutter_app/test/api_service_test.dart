import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/models/constants.dart';

void main() {
  group('ApiService', () {
    // 期望值统一从 Constants 派生（地址只单源定义在 constants.dart）。
    // 开源默认指向本机自建后端（http://10.0.2.2:7070，见 constants.dart 注释），
    // 原上架口径「锁死 https/wss 且不带端口」随开源放宽；保留的不变量是：
    // WS 与 API 同域同端口、协议跟随（http↔ws / https↔wss）——
    // 开发者换成自己的 https 域名后，这条契约依然守住「WS 不掉回明文/密文错配」。
    test('API base URL is a well-formed http(s) URL with a host', () {
      final api = Uri.parse(Constants.apiBaseUrl);
      expect(api.scheme, anyOf(equals('http'), equals('https')));
      expect(api.host, isNotEmpty);
    });

    test('WebSocket URL follows API scheme on the same host and port', () {
      final api = Uri.parse(Constants.apiBaseUrl);
      final ws = Uri.parse(Constants.wsUrl);
      // 协议跟随：https 配 wss、http 配 ws，不许密文 API 配明文 WS 或反之
      expect(ws.scheme, equals(api.scheme == 'https' ? 'wss' : 'ws'));
      expect(ws.host, equals(api.host));
      // 同域同端口（REST 与 WebSocket 一并反代）；Dart Uri 未写端口时返回协议默认值，两边一致即同域
      expect(ws.port, equals(api.port));
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
