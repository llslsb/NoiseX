import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// huawei_push 与 flutter_local_notifications 存在同名导出（Importance/Visibility），
// 本文件这些名字一律取 FLN 版，HMS 侧只用 Push 类
import 'package:huawei_push/huawei_push.dart' hide Importance, Visibility;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/constants.dart';
import '../services/debug_log.dart';
import 'api_service.dart';

/// OHOS 原生推送桥通道（ohos/entry/.../EntryAbility.ets 单源同款，勿单边改）：
/// - getToken：@kit.PushKit pushService.getToken()
/// - requestNotificationAuth：通知授权引导（1600004=用户拒绝）
/// - isNotificationEnabled / openNotificationSettings：设置页引导跳转
const MethodChannel _ohosPushChannel = MethodChannel('noisex/push');

/// 推送通知服务
/// 双通道（2026-11-05 推送修复轮；2026-11-06 上架前移除未启用的 Firebase，勿加回）：
/// - OHOS（Flutter-ohos）：自建 MethodChannel 桥 → @kit.PushKit，channel='ohos'
///   （服务端按 channel 路由：'ohos'→鸿蒙 v3 接口，报成 'hms' 会打不进鸿蒙设备）
/// - Android HMS 设备：huawei_push 真包（原空壳 HuaweiPush 代理类已删），channel='hms'
/// 无 HMS Core 的安卓机没有离线推送，只有 App 存活时的本地通知（FCM 从未配置过
/// google-services.json、国内也不可用，留着只会让商店的 SDK 扫描误报）。
class PushService {
  static final PushService _instance = PushService._();
  factory PushService() => _instance;
  PushService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  String? _currentToken;
  String _channel = 'unknown';
  bool _initialized = false;
  bool _pushEnabled = true;
  String? _currentRoomId;
  StreamSubscription<String>? _hmsTokenRefreshSubscription;

  /// 通知授权状态缓存（OHOS 用，granted/refused/unknown）
  String? _notificationAuth;

  static const String _authGranted = 'granted';
  static const String _authRefused = 'refused';
  static const String _authUnknown = 'unknown';

  void Function(String roomId)? onNotificationClick;

  bool get isEnabled => _pushEnabled;
  String get channel => _channel;

  /// 初始化推送通知
  Future<void> init() async {
    if (_initialized) return;

    await _loadPushPreference();

    // 本地通知插件只有 Android/iOS 实现：OHOS 上 initialize 抛 MissingPluginException，
    // 旧实现让整条 init 链死在 token 注册之前——鸿蒙端从未尝试拿 token 的深层根因。
    // 分平台包裹后 OHOS 才能走到自己的 _registerOhosToken。
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
        const iosSettings = DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        );
        const initSettings = InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        );
        await _plugin.initialize(
          initSettings,
          onDidReceiveNotificationResponse: _onNotificationResponse,
        );
        await _createChannels();
      } catch (e) {
        DebugLog().write('Push: local notification init failed: $e');
      }
    }

    // 注册远程推送 Token
    if (_pushEnabled) {
      await _registerRemoteToken();
    }

    _initialized = true;
  }

  Future<void> _loadPushPreference() async {
    final prefs = await SharedPreferences.getInstance();
    _pushEnabled = prefs.getBool(Constants.prefsKeyPushEnabled) ?? true;
  }

  Future<void> setEnabled(bool enabled) async {
    final changed = _pushEnabled != enabled;
    _pushEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(Constants.prefsKeyPushEnabled, enabled);

    if (!enabled) {
      await unregisterToken();
      return;
    }

    if (changed && _initialized) {
      await _registerRemoteToken();
    }
  }

  void setCurrentRoom(String? roomId) {
    _currentRoomId = roomId;
  }

  bool shouldShowNotificationForRoom(String roomId) {
    if (!_pushEnabled) return false;
    return roomId != _currentRoomId;
  }

  String notificationTitleForType(String type, String fallbackTitle) {
    return type == 'chat' ? '新消息' : fallbackTitle;
  }

  String notificationBodyForType(String type, String fallbackBody) {
    return type == 'chat' ? '收到新消息' : fallbackBody;
  }

  Future<void> _createChannels() async {
    const socialChannel = AndroidNotificationChannel(
      'social_communication',
      '社交通知',
      description: '消息、匹配等社交通知',
      importance: Importance.high,
      enableLights: true,
      enableVibration: true,
    );

    const serviceChannel = AndroidNotificationChannel(
      'service_information',
      '服务提醒',
      description: '房间过期、深度连接等服务提醒',
      importance: Importance.defaultImportance,
      enableLights: true,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(socialChannel);
      await android.createNotificationChannel(serviceChannel);
    }
  }

  /// 注册远程推送 Token（按平台选通道）
  ///
  /// ❗Flutter-OHOS 的 Platform.operatingSystem 是 'ohos'，isIOS/isAndroid 都
  /// 不命中——旧实现只判这两个，鸿蒙端连尝试都没有（推送修复根因②）。
  Future<void> _registerRemoteToken() async {
    try {
      if (Platform.isAndroid) {
        await _registerAndroidToken();
      } else if (Platform.operatingSystem == 'ohos') {
        await _registerOhosToken();
      } else {
        DebugLog().write(
            'Push: unsupported platform ${Platform.operatingSystem}');
      }
    } catch (e) {
      DebugLog().write('Push: remote token registration failed: $e');
    }
  }

  // ================= OHOS：自建桥 → @kit.PushKit =================

  /// OHOS：每次启动都调 getToken，token 变化才重新上报（channel='ohos'）。
  /// Push Token 一般不变，仅卸载重装/恢复出厂/deleteToken 后变更。
  Future<void> _registerOhosToken() async {
    _channel = 'ohos';
    try {
      final token = await _ohosPushChannel.invokeMethod<String>('getToken');
      if (token != null && token.isNotEmpty) {
        _currentToken = token;
        await _reportTokenIfChanged('ohos', token);
      } else {
        DebugLog().write('Push: OHOS getToken empty');
      }
    } catch (e) {
      // 常见：1000900010=应用身份验证失败（Profile 未含推送服务，需重新生成签名）
      DebugLog().write('Push: OHOS getToken failed: $e');
    }
    await ensureNotificationAuth();
  }

  /// 通知授权引导（OHOS）：已开启直接返回 granted；未开启弹系统授权框；
  /// 1600004=用户拒绝——对话框此后不再弹，只能经 openNotificationSettings 引导。
  Future<String> ensureNotificationAuth() async {
    if (Platform.operatingSystem != 'ohos') return _authGranted;
    try {
      final state = await _ohosPushChannel.invokeMethod<String>(
          'requestNotificationAuth');
      final s = (state == 'granted') ? _authGranted : _authUnknown;
      await _storeNotificationAuth(s);
      return s;
    } on PlatformException catch (e) {
      final s = e.code == 'notification_refused' ? _authRefused : _authUnknown;
      await _storeNotificationAuth(s);
      DebugLog().write('Push: notification auth refused/failed: ${e.code}');
      return s;
    } catch (e) {
      await _storeNotificationAuth(_authUnknown);
      return _authUnknown;
    }
  }

  /// 当前通知授权状态（granted/refused/unknown；先查缓存再落盘值）
  Future<String> notificationAuthState() async {
    if (_notificationAuth != null) return _notificationAuth!;
    if (Platform.operatingSystem != 'ohos') return _authGranted;
    final prefs = await SharedPreferences.getInstance();
    _notificationAuth =
        prefs.getString(Constants.prefsKeyNotificationAuth) ?? _authUnknown;
    return _notificationAuth!;
  }

  /// 跳系统通知设置（OHOS 半模态窗口，API26 关闭时带回最终授权态）并刷新
  /// 落盘状态；返回最终是否已授权。
  /// ❗超时兜底：模拟器镜像对 WithResult 接口可能既不开窗也不 reject
  /// （2026-11-05 TestPhone 实锤：Promise 挂起无任何回调），10s 后退回
  /// 重查授权态；真机窗口正常打开/关闭不受影响。
  Future<bool> openNotificationSettingsAndRefresh() async {
    if (Platform.operatingSystem != 'ohos') return false;
    try {
      final enabled =
          await _ohosPushChannel.invokeMethod<bool>('openNotificationSettings')
              .timeout(const Duration(seconds: 10));
      final granted = enabled == true;
      await _storeNotificationAuth(granted ? _authGranted : _authRefused);
      return granted;
    } on TimeoutException {
      DebugLog().write('Push: openNotificationSettings timeout, re-checking');
      final s = await refreshNotificationAuth();
      return s == _authGranted;
    } catch (e) {
      // 半模态不可用（801 capability not supported 等）：退回重查授权态
      DebugLog().write('Push: openNotificationSettings failed: $e');
      final s = await refreshNotificationAuth();
      return s == _authGranted;
    }
  }

  /// 设置页跳转回来后重查授权状态并刷新落盘
  Future<String> refreshNotificationAuth() async {
    if (Platform.operatingSystem != 'ohos') return _authGranted;
    try {
      final enabled =
          await _ohosPushChannel.invokeMethod<bool>('isNotificationEnabled');
      final s = (enabled == true) ? _authGranted : _authRefused;
      await _storeNotificationAuth(s);
      return s;
    } catch (e) {
      return _authUnknown;
    }
  }

  Future<void> _storeNotificationAuth(String state) async {
    _notificationAuth = state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(Constants.prefsKeyNotificationAuth, state);
  }

  // ================= Android：HMS 真包 =================

  /// Android: 有 HMS Core 才注册离线推送，否则只保留本地通知
  ///
  /// ❗探测必须带超时：GMS-only 设备上 HMS SDK 的 AGConnect 探测
  /// 可能无限重试网络不返回（GMS 模拟器实锤：getAAID 挂起无日志），
  /// 无超时会卡死整条 init 链。
  Future<void> _registerAndroidToken() async {
    await _requestAndroidNotificationPermission();
    final isHms = await _isHmsDevice();
    DebugLog().write('Push: Android device HMS=$isHms');
    if (isHms) {
      await _registerHmsToken();
    }
  }

  /// Android 13+ 通知运行时权限（POST_NOTIFICATIONS，展示通知必需）
  Future<void> _requestAndroidNotificationPermission() async {
    DebugLog().write('Push: Android requesting notification permission');
    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission().timeout(
            const Duration(seconds: 8),
            onTimeout: () => Future<bool>.value(false),
          );
    } catch (e) {
      DebugLog().write('Push: Android notification permission failed: $e');
    }
  }

  /// 检测是否为 HMS 设备（无 GMS）：getAAID 仅在 HMS Core 可用时成功。
  /// 6s 超时视作非 HMS（GMS-only 设备上 HMS 探测可能挂起）。
  Future<bool> _isHmsDevice() async {
    try {
      final aaId = await Push.getAAID().timeout(
        const Duration(seconds: 6),
        onTimeout: () => null,
      );
      return aaId != null && aaId.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  /// 华为 HMS Push（安卓端，真包 huawei_push）：
  /// getToken 无同步返回值，token 经 getTokenStream 异步送达。
  /// 流报错（如 907135003=无 HMS 推送服务，GMS-only 模拟器实锤）时只记日志：
  /// getAAID 探测只证明本地 AAID 生成能力，不代表 HMS Core 推送可用。
  /// 此前会回落 FCM，2026-11-06 上架前已移除 Firebase——这类设备只有本地通知。
  Future<void> _registerHmsToken() async {
    _channel = 'hms';
    await _hmsTokenRefreshSubscription?.cancel();
    _hmsTokenRefreshSubscription = Push.getTokenStream.listen((token) async {
      if (!_pushEnabled || token.isEmpty) return;
      _currentToken = token;
      try {
        await _reportTokenIfChanged('hms', token);
      } catch (_) {}
    }, onError: (e) async {
      DebugLog().write('Push: HMS token stream error (no remote push): $e');
    });
    Push.getToken('');
    DebugLog().write('Push: HMS getToken requested');
  }

  // ================= token 上报 =================

  /// token 变化才重新上报：存 "channel:token"，相同则跳过（服务端按
  /// channel 路由到对应接口）。unregisterToken 会清除记录，
  /// 关开推送/重置身份后即使 token 不变也会重新上报（重绑用户）。
  Future<void> _reportTokenIfChanged(String channel, String token) async {
    final prefs = await SharedPreferences.getInstance();
    final recorded = prefs.getString(Constants.prefsKeyPushReportedToken);
    if (recorded == '$channel:$token') {
      DebugLog().write(
          'Push: token unchanged (channel=$channel len=${token.length}), skip report');
      return;
    }
    try {
      await ApiService().registerPushToken(token, channel: channel);
      await prefs.setString(
          Constants.prefsKeyPushReportedToken, '$channel:$token');
      // 安全红线：不记录明文推送 token，仅记长度与通道
      DebugLog().write(
          'Push: token reported channel=$channel len=${token.length}');
    } catch (e) {
      DebugLog().write('Push: token report failed channel=$channel: $e');
      rethrow;
    }
  }

  Future<void> dispose() async {
    await _hmsTokenRefreshSubscription?.cancel();
    _hmsTokenRefreshSubscription = null;
    _initialized = false;
  }

  /// 注销推送 Token（关推送/重置身份）：服务端解除绑定 + 清本地"已上报"
  /// 记录，保证下次开启/注册时即使 token 未变也会重新上报到新用户。
  Future<void> unregisterToken() async {
    await _hmsTokenRefreshSubscription?.cancel();
    _hmsTokenRefreshSubscription = null;

    if (_currentToken != null) {
      try {
        await ApiService().unregisterPushToken();
      } catch (e) {
        debugPrint('[PushService] Unregister push token failed: $e');
      }
      _currentToken = null;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(Constants.prefsKeyPushReportedToken);
  }

  /// 显示本地通知（Android/iOS 走 flutter_local_notifications；OHOS 走自建桥
  /// 的系统 Notification Kit——该插件无 OHOS 实现，2026-11-05 前鸿蒙端
  /// 后台/非聊天页的本地通知从不弹出，靠此桥补齐，勿删）
  Future<void> showNotification({
    required String title,
    required String body,
    required String roomId,
    String channelId = 'social_communication',
  }) async {
    if (!_initialized || !shouldShowNotificationForRoom(roomId)) return;
    // OHOS：自建桥 noisex/push → EntryAbility.showLocalNotification（Notification Kit）
    if (Platform.operatingSystem == 'ohos') {
      try {
        const MethodChannel('noisex/push').invokeMethod(
          'showLocalNotification',
          {'title': title, 'body': body, 'roomId': roomId},
        );
      } catch (e) {
        DebugLog().write('Push: OHOS local notification failed: $e');
      }
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS) return;

    await _plugin.show(
      roomId.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelId == 'social_communication' ? '社交通知' : '服务提醒',
          importance: Importance.high,
          priority: Priority.high,
          autoCancel: true,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode({'roomId': roomId}),
    );
  }

  /// 通知点击处理
  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        final roomId = data['roomId'] as String? ?? '';
        if (roomId.isNotEmpty && onNotificationClick != null) {
          onNotificationClick!(roomId);
        }
      } catch (_) {}
    }
  }
}
