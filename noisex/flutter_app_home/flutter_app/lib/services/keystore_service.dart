import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 硬件密钥库包裹服务：主密钥由系统硬件密钥库（Android KeyStore / OHOS HUKS）
/// 生成并保护、不可导出，Dart 侧仅经平台通道 `noisex/keystore` 触发加解密。
///
/// 用于 CryptoService 落盘 E2EE 房间密钥（v2 信封）：
/// 明文 JSON -> 主密钥 AES-256-GCM 包裹 -> {"v":2,"iv":<b64>,"ct":<b64>}。
/// 明文密钥永不落盘；通道未实现（单元测试 / 未适配平台）或硬件操作失败时
/// 返回 null，调用方应跳过落盘——宁可不落盘（牺牲重启后的解密连续性），
/// 也绝不降级为明文写入。
class KeystoreService {
  static final KeystoreService _instance = KeystoreService._();
  factory KeystoreService() => _instance;
  KeystoreService._();

  static const MethodChannel _channel = MethodChannel('noisex/keystore');

  /// 包裹明文 JSON，返回 v2 信封字符串；失败返回 null。
  Future<String?> encryptJson(String plain) async {
    try {
      final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
          'encrypt', <String, String>{'plain': plain});
      final iv = result?['iv'];
      final ct = result?['ct'];
      if (iv is! String || iv.isEmpty || ct is! String || ct.isEmpty) {
        return null;
      }
      return jsonEncode(<String, dynamic>{'v': 2, 'iv': iv, 'ct': ct});
    } on MissingPluginException {
      return null; // 平台通道未实现（单测环境 / 未适配平台）
    } catch (e) {
      // 仅记异常类型，不落任何密文/明文内容（安全红线：错误不暴露细节）
      debugPrint('[KeystoreService] encrypt failed: ${e.runtimeType}');
      return null;
    }
  }

  /// 解开 v2 信封的 iv/ct，返回明文 JSON；失败（含硬件主密钥被清、密文被篡改）返回 null。
  Future<String?> decryptJson(String iv, String ct) async {
    try {
      return await _channel.invokeMethod<String>(
          'decrypt', <String, String>{'iv': iv, 'ct': ct});
    } on MissingPluginException {
      return null;
    } catch (e) {
      debugPrint('[KeystoreService] decrypt failed: ${e.runtimeType}');
      return null;
    }
  }
}
