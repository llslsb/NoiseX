import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static final AuthService _instance = AuthService._();
  factory AuthService() => _instance;
  AuthService._();

  String? _jwt;
  String? _userId;

  String? get jwt => _jwt;
  String? get userId => _userId;
  bool get isAuthenticated => _jwt != null && _jwt!.isNotEmpty;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _jwt = prefs.getString('jwt');
    _userId = prefs.getString('userId');
  }

  Future<void> saveAuth(String token, String userId) async {
    _jwt = token;
    _userId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('jwt', token);
    await prefs.setString('userId', userId);
  }

  Future<void> clearAuth() async {
    _jwt = null;
    _userId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('jwt');
    await prefs.remove('userId');
  }

  /// 生成标准 UUID v4（8-4-4-4-12 连字符格式）。
  /// 服务端 AuthRequest 用 ^[0-9a-f]{8}-...-{12}$ 正则强校验，旧版 32 位
  /// 无连字符随机串会被 400 拒收，导致注册永远失败、客户端永远"已离线"。
  String generateUUID() {
    final random = Random.secure();
    String hex(int n) => List.generate(
          n,
          (_) => '0123456789abcdef'[random.nextInt(16)],
        ).join();
    // 版本位固定 4（v4 随机），variant 位限定 8/9/a/b
    final variant = '89ab'[random.nextInt(4)];
    return '${hex(8)}-${hex(4)}-4${hex(3)}-$variant${hex(3)}-${hex(12)}';
  }
}
