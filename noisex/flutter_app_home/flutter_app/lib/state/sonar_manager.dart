import 'dart:async';
import 'package:flutter/material.dart';
import '../models/constants.dart';
import '../models/sonar.dart';
import '../models/chat_room.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/ritual_animation_service.dart';
import '../services/storage_service.dart';
import '../utils/error_messages.dart';
import '../theme/colors.dart';

/// 声呐状态管理器
///
/// 职责：
/// - 发送声呐脉冲
/// - 收听/取消收听附近声呐
/// - 管理收到的声呐列表
/// - 管理声呐冷却计时
class SonarManager extends ChangeNotifier {
  List<Sonar> _receivedSonars = [];

  /// 收听开关：从本地存储恢复用户上次的选择（新装默认开启），勿改回写死 true——
  /// 写死会让每次重启都静默恢复收听，用户关掉也白关（2026-11-06 用户实锤 bug）。
  bool _isListening = StorageService()
      .getBool(Constants.prefsKeyListeningEnabled, defaultValue: true);
  int _sonarCooldown = 0;
  String _listeningGeohash = '';
  Timer? _cooldownTimer;
  Timer? _refreshTimer;

  /// 收到的声呐列表
  List<Sonar> get receivedSonars => _receivedSonars;

  /// 是否正在收听
  bool get isListening => _isListening;

  /// 剩余冷却秒数（0 表示不在冷却中）
  int get sonarCooldown => _sonarCooldown;

  /// 当前收听的 geohash
  String get listeningGeohash => _listeningGeohash;

  /// 发送声呐
  Future<bool> sendSonar(BuildContext context, String content) async {
    final geohash = await LocationService().getGeohash();
    // 2026-11-02 幽灵格子修复：无真实 fix 禁止发送/注册——
    // 原 'wx4g0s'（北京开发默认格子）兜底把声呐和监听静默发到错误位置，
    // 与原生端 DEFAULT_GEOHASH 同款缺陷（"附近 0 人/幽灵异地"实锤根因）。
    if (geohash.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('正在定位中，请稍后再试'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
      return false;
    }

    final result = await ApiService().sendSonar(content, geohash);
    if (result.isSuccess) {
      if (_isListening) {
        await _startListeningAt(geohash);
      }
      await refreshReceivedSonars();
      _startCooldown();

      // 仪式感：每次发送声呐都触发全屏脉冲动效
      if (context.mounted) {
        unawaited(RitualAnimationService.instance.showFirstPulse(context));
      }

      return true;
    } else {
      if (context.mounted) {
        final msg = ErrorMessages.friendly(result.code, result.message);
        ErrorMessages.showErrorSnackBar(context, msg);
      }
      return false;
    }
  }

  /// 开始收听指定位置的声呐
  Future<void> _startListeningAt(String geohash) async {
    _listeningGeohash = geohash;
    notifyListeners();
  }

  /// 切换收听状态——纯标志位（2026-11-06 用户定则，勿回退）。
  ///
  /// 只翻本地状态并持久化，**不取定位、不碰授权**：收听开关只决定「别人能不能搜到我、
  /// 我能不能收到脉冲」，和定位权限无关。服务端登记/注销由 app.dart 的
  /// _handleToggleListening 负责，关闭时它会先确认服务端注销成功再调本方法。
  /// 旧版开启时调 getGeohash，会再次弹系统授权框，并在拿不到定位时把开关自动弹回关闭。
  Future<void> toggleListening(bool value) async {
    _isListening = value;
    await StorageService().setBool(Constants.prefsKeyListeningEnabled, value);
    if (value) {
      _startAutoRefresh();
    } else {
      _stopAutoRefresh();
      _listeningGeohash = '';
      _receivedSonars = [];
    }
    notifyListeners();
  }

  /// 刷新收到的声呐列表。
  ///
  /// 静默模式下直接清空并返回、不请求服务端（勿删此闸门）：长连接 sonar_received 推送、
  /// 切到接收器 Tab、断线重连都会调本方法，没有闸门时关掉收听仍会把声呐列表拉回来
  /// （2026-11-06 用户实锤：「收听模式都关闭了，为啥还能收到脉冲」）。
  Future<void> refreshReceivedSonars() async {
    if (!_isListening) {
      if (_receivedSonars.isNotEmpty) {
        _receivedSonars = [];
        notifyListeners();
      }
      return;
    }
    final result = await ApiService().getReceivedSonars();
    if (result.isSuccess && result.data != null) {
      _receivedSonars = result.data!
          .map((s) => Sonar(
                id: s.id,
                content: s.content,
                distance: s.distance,
                timestamp: DateTime.fromMillisecondsSinceEpoch(s.timestamp),
              ))
          .toList();
      notifyListeners();
    }
  }

  /// 接受声呐
  Future<ChatRoom?> acceptSonar(BuildContext context, Sonar sonar) async {
    final result = await ApiService().acceptSonar(sonar.id);
    if (result.isSuccess && result.data != null) {
      await refreshReceivedSonars();
      return ChatRoom(
        id: result.data!.roomId,
        sonarContent: result.data!.sonarContent,
        signalCode: result.data!.signalCode,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(result.data!.expiresAt),
      );
    } else {
      if (context.mounted) {
        final msg = ErrorMessages.friendly(result.code, result.message);
        ErrorMessages.showErrorSnackBar(context, msg);
      }
      return null;
    }
  }

  /// 忽略声呐
  Future<bool> ignoreSonar(BuildContext context, String sonarId) async {
    final result = await ApiService().ignoreSonar(sonarId);
    if (result.isSuccess) {
      _receivedSonars = _receivedSonars.where((s) => s.id != sonarId).toList();
      notifyListeners();
      return true;
    } else {
      if (context.mounted) {
        final msg = ErrorMessages.friendly(result.code, result.message);
        ErrorMessages.showErrorSnackBar(context, msg);
      }
      return false;
    }
  }

  /// 开始冷却计时
  void _startCooldown() {
    _sonarCooldown = 300; // 5分钟冷却
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_sonarCooldown > 0) {
        _sonarCooldown--;
        notifyListeners();
      } else {
        timer.cancel();
      }
    });
  }

  /// 开始自动刷新声呐列表
  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      refreshReceivedSonars();
    });
  }

  /// 停止自动刷新
  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
  }

  /// 清空所有状态
  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _refreshTimer?.cancel();
    super.dispose();
  }

  /// 重置身份时清空
  void clear() {
    _receivedSonars = [];
    _sonarCooldown = 0;
    _cooldownTimer?.cancel();
    _refreshTimer?.cancel();
    notifyListeners();
  }
}
