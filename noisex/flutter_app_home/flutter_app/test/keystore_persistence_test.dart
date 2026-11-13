import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/services/crypto_service.dart';
import 'package:noisex/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 硬件密钥库通道测试桩：encrypt/decrypt 用内存字符串模拟往返。
/// - failDecrypt：decrypt 恒返回 null（模拟主密钥被清 / 密文被篡改）；
/// - forcedDecrypt：decrypt 恒返回该明文（用于直接种 v2 信封内容）；
/// - 未安装桩时通道抛 MissingPluginException（等价硬件不可用）。
class KeystoreMock {
  String? lastEncryptedPlain;
  bool failDecrypt = false;
  String? forcedDecrypt;
}

KeystoreMock installKeystoreMock({bool failDecrypt = false}) {
  final mock = KeystoreMock()
    ..failDecrypt = failDecrypt;
  const channel = MethodChannel('noisex/keystore');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'encrypt':
        mock.lastEncryptedPlain = (call.arguments as Map)['plain'] as String;
        return <String, String>{'iv': 'aXZpdml2aXZpdg==', 'ct': 'c3R1Yg=='};
      case 'decrypt':
        if (mock.failDecrypt) return null;
        return mock.forcedDecrypt ?? mock.lastEncryptedPlain;
    }
    return null;
  });
  return mock;
}

void clearKeystoreMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(const MethodChannel('noisex/keystore'), null);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const prefKey = 'noisex_e2ee_keys';
  final crypto = CryptoService();

  Future<void> freshStorage() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await StorageService().init();
  }

  /// 合法的 32 字节 raw key（Base64）
  String validKeyB64() => base64Encode(List<int>.generate(32, (i) => i));

  group('B18 密钥持久化（经硬件密钥库桩）', () {
    const persistRoomId = 'persist-room-001';

    setUp(() async {
      await freshStorage();
      installKeystoreMock();
    });
    tearDown(clearKeystoreMock);

    test('derive 后持久化为 v2 信封，清内存后可恢复并继续解密', () async {
      crypto.clearRoomKey(persistRoomId);
      await crypto.flushPersistChain();

      final pubKey = await crypto.generateKeyPair(persistRoomId);
      expect(await crypto.deriveSharedKey(persistRoomId, pubKey), isTrue);
      await crypto.flushPersistChain();

      // 落盘是 v2 包裹信封，不含明文密钥结构
      final raw = StorageService().getString(prefKey);
      expect(raw, isNotEmpty);
      final blob = jsonDecode(raw) as Map;
      expect(blob['v'], 2);
      expect(blob['iv'] as String, isNotEmpty);
      expect(blob['ct'] as String, isNotEmpty);
      expect(raw.contains(validKeyB64()), isFalse);

      final encrypted = await crypto.encrypt(persistRoomId, 'persist test');
      expect(encrypted, isNotNull);

      // 模拟重启：仅内存密钥丢失，持久化仍在
      crypto.clearRoomKeyMemoryOnly(persistRoomId);
      expect(crypto.hasSharedKey(persistRoomId), isFalse);

      await crypto.restorePersistedKeys();
      expect(crypto.hasSharedKey(persistRoomId), isTrue);
      expect(await crypto.decrypt(persistRoomId, encrypted!), 'persist test');
    });

    test('clearRoomKey 连持久化一并清除', () async {
      crypto.clearRoomKey(persistRoomId);
      await crypto.flushPersistChain();

      final pubKey = await crypto.generateKeyPair(persistRoomId);
      expect(await crypto.deriveSharedKey(persistRoomId, pubKey), isTrue);
      await crypto.flushPersistChain();
      expect(crypto.hasSharedKey(persistRoomId), isTrue);

      crypto.clearRoomKey(persistRoomId);
      await crypto.flushPersistChain();

      await crypto.restorePersistedKeys();
      expect(crypto.hasSharedKey(persistRoomId), isFalse);
    });

    test('restore 对损坏的持久化数据保持健壮', () async {
      // 键名与 CryptoService._persistedKeysKey 一致（私有，此处直接写字面量）
      await StorageService().setString(prefKey, '{corrupted-not-json');
      await crypto.flushPersistChain();

      await crypto.restorePersistedKeys();
      expect(crypto.hasSharedKey(persistRoomId), isFalse);
    });
  });

  group('B18+ v2 硬件包裹迁移与反追踪时间界', () {
    setUp(freshStorage);
    tearDown(clearKeystoreMock);

    test('v1 明文信封启动时自动迁移为 v2 包裹', () async {
      installKeystoreMock();
      await StorageService()
          .setString(prefKey, jsonEncode(<String, String>{'legacy-room': validKeyB64()}));

      await crypto.restorePersistedKeys();

      expect(crypto.hasSharedKey('legacy-room'), isTrue);
      final raw = StorageService().getString(prefKey);
      final blob = jsonDecode(raw) as Map;
      expect(blob['v'], 2);
      // 迁移后落盘不再有裸 key
      expect(raw.contains(validKeyB64()), isFalse);
    });

    test('v2 硬件解密失败：丢弃落盘信封，绝不降级明文', () async {
      installKeystoreMock();
      final pubKey = await crypto.generateKeyPair('wipe-room');
      await crypto.deriveSharedKey('wipe-room', pubKey);
      await crypto.flushPersistChain();
      expect(StorageService().getString(prefKey), isNotEmpty);

      // 主密钥丢失：解密恒失败 → 信封自毁
      installKeystoreMock(failDecrypt: true);
      crypto.clearRoomKeyMemoryOnly('wipe-room'); // 先清内存，验证恢复链路
      await crypto.restorePersistedKeys();
      expect(crypto.hasSharedKey('wipe-room'), isFalse);
      expect(StorageService().getString(prefKey), isEmpty);
    });

    test('硬件密钥库不可用：不落盘明文（宁缺毋滥），内存密钥仍可用', () async {
      // 不安装桩 → MissingPluginException → encryptJson 返回 null
      final pubKey = await crypto.generateKeyPair('no-keystore-room');
      await crypto.deriveSharedKey('no-keystore-room', pubKey);
      await crypto.flushPersistChain();

      expect(StorageService().getString(prefKey), isEmpty);
      expect(await crypto.encrypt('no-keystore-room', 'hello'), isNotNull);
    });

    test('距最后确认活跃超 73h 的房间密钥恢复时不复活', () async {
      final oldT = DateTime.now()
          .subtract(const Duration(hours: 74))
          .millisecondsSinceEpoch;
      final freshT = DateTime.now().millisecondsSinceEpoch;
      final envelope = jsonEncode(<String, Map<String, dynamic>>{
        'stale-room': <String, dynamic>{'k': validKeyB64(), 't': oldT},
        'fresh-room': <String, dynamic>{'k': validKeyB64(), 't': freshT},
      });
      final mock = installKeystoreMock();
      mock.forcedDecrypt = envelope;
      await StorageService().setString(
          prefKey, jsonEncode(<String, dynamic>{'v': 2, 'iv': 'aXZpdg==', 'ct': 'c3R1Yg=='}));

      await crypto.restorePersistedKeys();

      expect(crypto.hasSharedKey('stale-room'), isFalse);
      expect(crypto.hasSharedKey('fresh-room'), isTrue);
    });

    test('retainPersistedKeysOnly：非空列表清理离群密钥并迁移落盘', () async {
      final mock = installKeystoreMock();
      await StorageService().setString(
          prefKey,
          jsonEncode(<String, String>{
            'keep-room': validKeyB64(),
            'drop-room': validKeyB64(),
          }));

      crypto.retainPersistedKeysOnly(<String>['keep-room']);
      await crypto.flushPersistChain();

      // 落盘已是 v2 包裹
      final blob = jsonDecode(StorageService().getString(prefKey)) as Map;
      expect(blob['v'], 2);
      // 包裹明文只保留活跃房间
      final envelope = jsonDecode(mock.lastEncryptedPlain!) as Map;
      expect(envelope.containsKey('keep-room'), isTrue);
      expect(envelope.containsKey('drop-room'), isFalse);
      expect((envelope['keep-room'] as Map)['t'], greaterThan(0));
    });

    test('retainPersistedKeysOnly：空列表视为不可信，不动任何密钥', () async {
      final mock = installKeystoreMock();
      await StorageService().setString(
          prefKey, jsonEncode(<String, String>{'solo-room': validKeyB64()}));

      crypto.retainPersistedKeysOnly(<String>[]);
      await crypto.flushPersistChain();

      final envelope = jsonDecode(mock.lastEncryptedPlain!) as Map;
      expect(envelope.containsKey('solo-room'), isTrue);
    });

    test('retainPersistedKeysOnly：活跃房间 t 按节流阈值触碰', () async {
      final mock = installKeystoreMock();
      final oldT = DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch;
      mock.forcedDecrypt = jsonEncode(<String, Map<String, dynamic>>{
        'keep-room': <String, dynamic>{'k': validKeyB64(), 't': oldT},
      });
      await StorageService().setString(
          prefKey, jsonEncode(<String, dynamic>{'v': 2, 'iv': 'aXZpdg==', 'ct': 'c3R1Yg=='}));

      crypto.retainPersistedKeysOnly(<String>['keep-room']);
      await crypto.flushPersistChain();

      final next = jsonDecode(mock.lastEncryptedPlain!) as Map;
      expect((next['keep-room'] as Map)['t'], greaterThan(oldT));
    });
  });
}
