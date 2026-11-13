import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:pointycastle/export.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/key_generators/ec_key_generator.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/pointycastle.dart';
import 'keystore_service.dart';
import 'storage_service.dart';

/// 端到端加密服务 (ECDH + AES-256-GCM)
/// 与鸿蒙端 CryptoService.ets 对齐
class CryptoService {
  static final CryptoService _instance = CryptoService._();
  factory CryptoService() => _instance;
  CryptoService._();

  // roomId -> 共享密钥 (AES-256, 32 bytes)
  final Map<String, Uint8List> _sharedKeys = {};
  // roomId -> 本方 ECDH 密钥对（临时，交换后可清除）
  final Map<String, AsymmetricKeyPair<PublicKey, PrivateKey>> _keyPairs = {};

  final SecureRandom _secureRandom = _initSecureRandom();

  // B18+：已派生共享密钥的应用内持久化。存于应用私有 Preferences，不上传服务端；
  // 身份重置时随 clearAllKeys 一并清除；Android 端 allowBackup=false 禁止云备份。
  //
  // 落盘格式（B18 时为明文 v1，现升级为硬件密钥库包裹的 v2）：
  // - v1（历史）：明文 JSON Map：roomId -> Base64(raw key)
  // - v2：{"v":2,"iv":<b64>,"ct":<b64>}，包裹明文为
  //   JSON Map：roomId -> {"k": Base64(raw key), "t": 最后确认活跃的 epoch 毫秒}
  // 主密钥由系统硬件密钥库（AndroidKeyStore / HUKS）保护、不可导出；
  // t 用于反追踪：距最后确认活跃超过 73h 的房间密钥在恢复时不再复活。
  static const String _persistedKeysKey = 'noisex_e2ee_keys';
  static const int _persistVersion = 2;

  /// 房间密钥保留时间界：72h 房间寿命 + 1h 刷新宽限
  static const Duration _keyRetention = Duration(hours: 73);

  /// 活跃房间"最后确认时间"触碰节流
  static const int _touchIntervalMs = 60 * 60 * 1000;

  // 写链串行化：并发派生时避免 read-modify-write 丢更新（与 DebugLog 同款模式）
  Future<void> _persistChain = Future.value();

  static SecureRandom _initSecureRandom() {
    final random = FortunaRandom();
    final seeds = Uint8List(32);
    final rng = math.Random.secure();
    for (var i = 0; i < 32; i++) {
      seeds[i] = rng.nextInt(256);
    }
    random.seed(KeyParameter(seeds));
    return random;
  }

  /// 生成 ECDH 密钥对，返回 Base64 编码的公钥
  Future<String> generateKeyPair(String roomId) async {
    try {
      final domain = ECCurve_secp256r1();
      final keyGen = ECKeyGenerator()
        ..init(ParametersWithRandom(
          ECKeyGeneratorParameters(domain),
          _secureRandom,
        ));
      final pair = keyGen.generateKeyPair();
      _keyPairs[roomId] = pair;

      // 导出公钥为 Base64 (未压缩格式: 04 + x + y)
      final publicKey = pair.publicKey as ECPublicKey;
      final q = publicKey.Q!;
      final xBytes = _bigIntToBytes(q.x!.toBigInteger()!, 32);
      final yBytes = _bigIntToBytes(q.y!.toBigInteger()!, 32);
      final uncompressed = Uint8List(65);
      uncompressed[0] = 0x04;
      uncompressed.setRange(1, 33, xBytes);
      uncompressed.setRange(33, 65, yBytes);

      return base64Encode(uncompressed);
    } catch (e) {
      return '';
    }
  }

  /// 收到对方公钥后，协商共享密钥
  Future<bool> deriveSharedKey(String roomId, String peerPubKeyB64) async {
    try {
      final pair = _keyPairs[roomId];
      if (pair == null) return false;

      // 解码对方公钥
      final peerPubKeyBytes = base64Decode(peerPubKeyB64);
      final domain = ECCurve_secp256r1();
      BigInt x, y;
      // 兼容两种编码：65 字节裸点(0x04||X||Y)与 ArkTS getEncoded() 的
      // X.509/SPKI DER 包装（P-256 恒为 91 字节，EC 点固定在末尾 65 字节）
      if (peerPubKeyBytes.length == 65 && peerPubKeyBytes[0] == 0x04) {
        x = _bytesToBigInt(peerPubKeyBytes.sublist(1, 33));
        y = _bytesToBigInt(peerPubKeyBytes.sublist(33, 65));
      } else if (peerPubKeyBytes.length > 65 && peerPubKeyBytes[0] == 0x30) {
        final point = peerPubKeyBytes.sublist(peerPubKeyBytes.length - 65);
        if (point[0] != 0x04) return false;
        x = _bytesToBigInt(point.sublist(1, 33));
        y = _bytesToBigInt(point.sublist(33, 65));
      } else {
        return false;
      }
      final peerQ = domain.curve.createPoint(x, y);
      final peerPublicKey = ECPublicKey(peerQ, domain);

      // ECDH 密钥协商: sharedSecret = privateKey * peerPublicKey
      final privateKey = pair.privateKey as ECPrivateKey;
      final sharedPoint = peerPublicKey.Q! * privateKey.d!;
      if (sharedPoint == null) return false;
      final xCoord = sharedPoint.x;
      if (xCoord == null) return false;
      final sharedSecret = _bigIntToBytes(xCoord.toBigInteger()!, 32);

      // 从共享密钥派生 AES-256 密钥 (简化 HKDF: 取前 32 字节)
      final aesKey = _deriveAesKey(sharedSecret);
      _sharedKeys[roomId] = aesKey;
      // B18：持久化共享密钥，App 重启后历史消息可解密、加密会话可续
      _persistKey(roomId, aesKey);

      // 清除临时密钥对
      _keyPairs.remove(roomId);
      return true;
    } catch (e) {
      return false;
    }
  }

  /// AES-256-GCM 加密
  Future<String?> encrypt(String roomId, String plaintext) async {
    try {
      final aesKey = _sharedKeys[roomId];
      if (aesKey == null) return null;

      // 生成 12 字节随机 IV
      final iv = _randomBytes(12);

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          true,
          AEADParameters(
            KeyParameter(aesKey),
            128, // auth tag length in bits
            iv,
            Uint8List(0), // AAD
          ),
        );

      final input = Uint8List.fromList(utf8.encode(plaintext));
      final output = cipher.process(input);

      // 输出格式: Base64(iv + ciphertext + authTag)
      final combined = Uint8List(iv.length + output.length);
      combined.setRange(0, iv.length, iv);
      combined.setRange(iv.length, combined.length, output);

      return base64Encode(combined);
    } catch (e) {
      return null;
    }
  }

  /// AES-256-GCM 解密
  Future<String?> decrypt(String roomId, String ciphertextB64) async {
    try {
      final aesKey = _sharedKeys[roomId];
      if (aesKey == null) return null;

      final combined = base64Decode(ciphertextB64);
      if (combined.length < 12) return null;

      // 提取 IV (前 12 字节) 和密文+authTag
      final iv = Uint8List.fromList(combined.sublist(0, 12));
      final encrypted = Uint8List.fromList(combined.sublist(12));

      final cipher = GCMBlockCipher(AESEngine())
        ..init(
          false,
          AEADParameters(
            KeyParameter(aesKey),
            128,
            iv,
            Uint8List(0),
          ),
        );

      final decrypted = cipher.process(encrypted);
      return utf8.decode(decrypted);
    } catch (e) {
      return null;
    }
  }

  /// 是否已协商密钥
  bool hasSharedKey(String roomId) => _sharedKeys.containsKey(roomId);

  bool hasKeyPair(String roomId) => _keyPairs.containsKey(roomId);

  /// 清除房间密钥（房间过期/离开时调用）
  void clearRoomKey(String roomId) {
    _sharedKeys.remove(roomId);
    _keyPairs.remove(roomId);
    _removePersistedKey(roomId);
  }

  /// 清除所有临时密钥（匿名身份重置时调用）
  void clearAllKeys() {
    _sharedKeys.clear();
    _keyPairs.clear();
    _persistChain =
        _persistChain.then((_) => StorageService().remove(_persistedKeysKey));
  }

  // ============ B18：密钥持久化（v2 硬件密钥库包裹） ============

  /// 读取落盘密钥信封：roomId -> {"k": keyB64, "t": epochMs}。
  /// 兼容 v1 明文（needsRewrite=true，调用方负责重写为 v2）与 v2 包裹信封。
  /// v2 硬件解密失败（主密钥被清 / 密文被篡改）时丢弃落盘并返回空信封，
  /// 绝不降级为明文；等待下一次协商重建。
  Future<({Map<String, Map<String, dynamic>> envelope, bool needsRewrite})>
      _loadEnvelope() async {
    final raw = StorageService().getString(_persistedKeysKey);
    if (raw.isEmpty) {
      return (envelope: <String, Map<String, dynamic>>{}, needsRewrite: false);
    }
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map && parsed['v'] == _persistVersion) {
        final plain = await KeystoreService()
            .decryptJson(parsed['iv'] as String, parsed['ct'] as String);
        if (plain == null) {
          await StorageService().remove(_persistedKeysKey);
          return (
            envelope: <String, Map<String, dynamic>>{},
            needsRewrite: false
          );
        }
        final decoded = jsonDecode(plain) as Map;
        final envelope = <String, Map<String, dynamic>>{};
        decoded.forEach((roomId, entry) {
          if (entry is Map) {
            envelope[roomId.toString()] = Map<String, dynamic>.from(entry);
          }
        });
        return (envelope: envelope, needsRewrite: false);
      }
      if (parsed is Map) {
        // v1 明文信封：原地迁移为 v2（内层补 t = now，迁移后由时间界接管）
        final now = DateTime.now().millisecondsSinceEpoch;
        final envelope = <String, Map<String, dynamic>>{};
        parsed.forEach((roomId, keyB64) {
          envelope[roomId.toString()] =
              <String, dynamic>{'k': keyB64.toString(), 't': now};
        });
        return (envelope: envelope, needsRewrite: true);
      }
      return (envelope: <String, Map<String, dynamic>>{}, needsRewrite: false);
    } catch (_) {
      // 持久化数据损坏时按空信封处理，等待下一次协商重建
      return (envelope: <String, Map<String, dynamic>>{}, needsRewrite: false);
    }
  }

  /// 包裹并落盘信封。硬件保护不可用时返回 false 且不写任何内容。
  Future<bool> _writeEnvelope(
      Map<String, Map<String, dynamic>> envelope) async {
    final wrapped = await KeystoreService().encryptJson(jsonEncode(envelope));
    if (wrapped == null) return false;
    return StorageService().setString(_persistedKeysKey, wrapped);
  }

  void _persistKey(String roomId, Uint8List key) {
    _persistChain = _persistChain.then((_) async {
      try {
        final loaded = await _loadEnvelope();
        loaded.envelope[roomId] = <String, dynamic>{
          'k': base64Encode(key),
          't': DateTime.now().millisecondsSinceEpoch,
        };
        await _writeEnvelope(loaded.envelope);
      } catch (_) {
        // 持久化失败不影响内存密钥可用性，仅丢失重启后的连续性
      }
    });
  }

  void _removePersistedKey(String roomId) {
    _persistChain = _persistChain.then((_) async {
      try {
        final loaded = await _loadEnvelope();
        if (loaded.envelope.remove(roomId) == null) return;
        await _writeEnvelope(loaded.envelope);
      } catch (_) {}
    });
  }

  /// 房间列表同步后的密钥治理（反追踪兜底，与鸿蒙原生端 retainKeysOnly 单源同款）：
  /// - 列表非空：清除不在活跃集合中的房间密钥（覆盖离线过期 / 进程重启残留）；
  /// - 列表为空视为不可信：不动任何密钥（防服务端异常清空误伤），
  ///   残留密钥由 restore 时的 73h 时间界兜底清除；
  /// - 活跃房间的"最后确认时间"按节流阈值触碰。
  void retainPersistedKeysOnly(List<String> activeRoomIds) {
    _persistChain = _persistChain.then((_) async {
      try {
        final loaded = await _loadEnvelope();
        if (loaded.envelope.isEmpty) return;
        final active = activeRoomIds.toSet();
        final now = DateTime.now().millisecondsSinceEpoch;
        var changed = loaded.needsRewrite;
        final next = <String, Map<String, dynamic>>{};
        loaded.envelope.forEach((roomId, entry) {
          final k = entry['k'];
          if (k is! String || k.isEmpty) {
            changed = true; // 剔除损坏条目
            return;
          }
          if (!active.contains(roomId)) {
            if (active.isEmpty) {
              next[roomId] = entry; // 空列表不删键
            } else {
              changed = true;
            }
            return;
          }
          final t = (entry['t'] as num?)?.toInt() ?? 0;
          if (now - t > _touchIntervalMs) {
            entry = <String, dynamic>{'k': k, 't': now};
            changed = true;
          }
          next[roomId] = entry;
        });
        if (!changed) return;
        await _writeEnvelope(next);
      } catch (_) {}
    });
  }

  /// 启动时恢复持久化的共享密钥（仅写内存映射；日志不含密钥材料）。
  /// 同时完成 v1→v2 迁移落盘，以及反追踪时间界清理：
  /// 距最后确认活跃超过 73h 的房间密钥不复活（房间 72h 寿命必已过期）。
  Future<void> restorePersistedKeys() async {
    final loaded = await _loadEnvelope();
    final cutoff =
        DateTime.now().subtract(_keyRetention).millisecondsSinceEpoch;
    var restored = 0;
    loaded.envelope.forEach((roomId, entry) {
      if (_sharedKeys.containsKey(roomId)) return;
      try {
        final k = entry['k'];
        if (k is! String || k.isEmpty) return;
        final key = base64Decode(k);
        if (key.length != 32) return;
        final t = (entry['t'] as num?)?.toInt() ?? 0;
        if (t > 0 && t < cutoff) return;
        _sharedKeys[roomId] = Uint8List.fromList(key);
        restored++;
      } catch (_) {}
    });
    if (restored > 0) {
      debugPrint('[CryptoService] Restored $restored persisted keys');
    }
    if (loaded.needsRewrite) {
      await _writeEnvelope(loaded.envelope);
    }
  }

  /// 仅清除内存密钥、保留持久化（模拟重启后的状态，测试用）
  @visibleForTesting
  void clearRoomKeyMemoryOnly(String roomId) {
    _sharedKeys.remove(roomId);
  }

  /// 等待挂起的持久化写链完成（测试用）
  @visibleForTesting
  Future<void> flushPersistChain() => _persistChain;

  /// 计算安全号码指纹（SHA-256 哈希共享密钥，Base32 编码，5 段显示）
  /// 与设计文档 P1-D E2EE 视觉化对齐
  String? getSafetyNumber(String roomId) {
    final aesKey = _sharedKeys[roomId];
    if (aesKey == null) return null;

    // SHA-256 哈希共享密钥
    final hash = _sha256(aesKey);

    // Base32 编码（RFC 4648，无填充）
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final buffer = StringBuffer();
    for (var i = 0; i < hash.length; i += 5) {
      final chunk = hash.sublist(i, math.min(i + 5, hash.length));
      var value = 0;
      for (var j = 0; j < chunk.length; j++) {
        value = (value << 8) | chunk[j];
      }
      final bits = chunk.length * 8;
      for (var k = 0; k < bits; k += 5) {
        if (k + 5 <= bits) {
          final index = (value >> (bits - k - 5)) & 0x1F;
          buffer.write(alphabet[index]);
        }
      }
    }

    // 格式化为 5 段（每段 4 字符）
    final raw = buffer.toString();
    final parts = <String>[];
    for (var i = 0; i < raw.length && parts.length < 5; i += 4) {
      final end = math.min(i + 4, raw.length);
      final segment = raw.substring(i, end).padRight(4, '=');
      parts.add(segment);
    }
    return parts.take(5).join('-');
  }

  /// 从 ECDH 共享密钥派生 AES-256 密钥 (HKDF-SHA256: Extract-Expand)
  /// salt = "noisex-e2ee-salt", info = "noisex-e2ee-key" (与鸿蒙端对齐)
  Uint8List _deriveAesKey(Uint8List sharedSecret) {
    final info = Uint8List.fromList(utf8.encode('noisex-e2ee-key'));
    final hashLen = 32;

    // Extract: PRK = HMAC-SHA256(salt=HASH("noisex-e2ee-salt"), IKM=sharedSecret)
    final saltInput = Uint8List.fromList(utf8.encode('noisex-e2ee-salt'));
    final saltHash = _sha256(saltInput);
    final prk = _hmacSha256(saltHash, sharedSecret);

    // Expand: T(1) = HMAC-SHA256(PRK, info || 0x01)
    final t1Input = Uint8List(info.length + 1);
    t1Input.setRange(0, info.length, info);
    t1Input[info.length] = 0x01;
    final t1 = _hmacSha256(prk, t1Input);

    return Uint8List.fromList(t1.sublist(0, hashLen));
  }

  /// SHA-256 哈希
  Uint8List _sha256(Uint8List input) {
    final digest = SHA256Digest();
    final output = Uint8List(digest.digestSize);
    digest.update(input, 0, input.length);
    digest.doFinal(output, 0);
    return output;
  }

  Uint8List _hmacSha256(Uint8List key, Uint8List message) {
    final hmac = HMac(SHA256Digest(), 64);
    hmac.init(KeyParameter(key));
    final output = Uint8List(hmac.macSize);
    hmac.update(message, 0, message.length);
    hmac.doFinal(output, 0);
    return output;
  }

  Uint8List _randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextUint8();
    }
    return bytes;
  }

  Uint8List _bigIntToBytes(BigInt value, int length) {
    final bytes = Uint8List(length);
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    for (var i = 0; i < length; i++) {
      bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return bytes;
  }

  BigInt _bytesToBigInt(List<int> bytes) {
    var result = BigInt.zero;
    for (final byte in bytes) {
      result = (result << 8) | BigInt.from(byte);
    }
    return result;
  }
}
