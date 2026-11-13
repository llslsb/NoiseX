import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/services/crypto_service.dart';
import 'package:noisex/services/storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('CryptoService', () {
    final crypto = CryptoService();
    const testRoomId = 'test-room-001';

    setUp(() async {
      crypto.clearRoomKey(testRoomId);
      final pubKey = await crypto.generateKeyPair(testRoomId);
      final derived = await crypto.deriveSharedKey(testRoomId, pubKey);
      expect(derived, isTrue);
    });

    tearDown(() {
      crypto.clearRoomKey(testRoomId);
    });

    test('encrypt then decrypt returns original plaintext', () async {
      const plaintext = 'Hello, NoiseX!';
      final encrypted = await crypto.encrypt(testRoomId, plaintext);
      expect(encrypted, isNotNull);
      final decrypted = await crypto.decrypt(testRoomId, encrypted!);
      expect(decrypted, equals(plaintext));
    });

    test('encrypt/decrypt works with empty string', () async {
      const plaintext = '';
      final encrypted = await crypto.encrypt(testRoomId, plaintext);
      expect(encrypted, isNotNull);
      final decrypted = await crypto.decrypt(testRoomId, encrypted!);
      expect(decrypted, equals(plaintext));
    });

    test('encrypt/decrypt works with unicode content', () async {
      const plaintext = '你好，世界！🎉';
      final encrypted = await crypto.encrypt(testRoomId, plaintext);
      expect(encrypted, isNotNull);
      final decrypted = await crypto.decrypt(testRoomId, encrypted!);
      expect(decrypted, equals(plaintext));
    });

    test('encrypt returns null when no shared key', () async {
      crypto.clearRoomKey(testRoomId);
      final result = await crypto.encrypt(testRoomId, 'test');
      expect(result, isNull);
    });

    test('decrypt returns null when no shared key', () async {
      crypto.clearRoomKey(testRoomId);
      final result = await crypto.decrypt(testRoomId, 'dGVzdA==');
      expect(result, isNull);
    });

    test('decrypt returns null for invalid ciphertext', () async {
      final result = await crypto.decrypt(testRoomId, 'not-valid-base64!!!');
      expect(result, isNull);
    });

    test('decrypt returns null for tampered ciphertext', () async {
      final encrypted = await crypto.encrypt(testRoomId, 'secret');
      expect(encrypted, isNotNull);
      final tampered = encrypted!.substring(0, encrypted.length - 4) + 'XXXX';
      final result = await crypto.decrypt(testRoomId, tampered);
      expect(result, isNull);
    });

    test('different encrypt calls produce different ciphertext', () async {
      const plaintext = 'same input';
      final encrypted1 = await crypto.encrypt(testRoomId, plaintext);
      final encrypted2 = await crypto.encrypt(testRoomId, plaintext);
      expect(encrypted1, isNotNull);
      expect(encrypted2, isNotNull);
      expect(encrypted1, isNot(equals(encrypted2)));
    });

    test('hasSharedKey returns correct state', () {
      expect(crypto.hasSharedKey(testRoomId), isTrue);
      crypto.clearRoomKey(testRoomId);
      expect(crypto.hasSharedKey(testRoomId), isFalse);
    });
  });

  group('公钥互操作（双端联调，持久化用例见 keystore_persistence_test.dart）', () {
    final crypto = CryptoService();

    test('deriveSharedKey 接受 X.509/SPKI DER 包装的对端公钥（双端联调）', () async {
      SharedPreferences.setMockInitialValues({});
      await StorageService().init();
      const derRoomId = 'der-room-001';
      crypto.clearRoomKey(derRoomId);
      await crypto.flushPersistChain();

      // 本方密钥对
      final myPub = await crypto.generateKeyPair(derRoomId);
      expect(myPub, isNotEmpty);

      // 模拟 ArkTS PubKey.getEncoded()：对裸点加 P-256 SPKI 固定 26 字节头
      final peerPubRaw = await crypto.generateKeyPair('der-peer-tmp');
      final peerBytes = base64Decode(peerPubRaw);
      expect(peerBytes.length, 65);
      expect(peerBytes[0], 0x04);
      const spkiHeader = <int>[
        0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2a, 0x86, 0x48, 0xce, //
        0x3d, 0x02, 0x01, 0x06, 0x08, 0x2a, 0x86, 0x48, 0xce, 0x3d, //
        0x03, 0x01, 0x07, 0x03, 0x42, 0x00, //
      ];
      final peerPubDer =
          base64Encode(Uint8List.fromList(<int>[...spkiHeader, ...peerBytes]));

      final derived = await crypto.deriveSharedKey(derRoomId, peerPubDer);
      expect(derived, isTrue);
      expect(crypto.hasSharedKey(derRoomId), isTrue);

      final encrypted = await crypto.encrypt(derRoomId, 'der test');
      expect(encrypted, isNotNull);
      final decrypted = await crypto.decrypt(derRoomId, encrypted!);
      expect(decrypted, equals('der test'));

      crypto.clearRoomKey(derRoomId);
      crypto.clearRoomKey('der-peer-tmp');
    });
  });
}
