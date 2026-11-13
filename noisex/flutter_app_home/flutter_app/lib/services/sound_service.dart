import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// NoiseX 全局短音效服务。
///
/// 与设计文档 `docs/superpowers/plans/2026-06-15-ux-revamp.md` P0-2 对齐。
///
/// 设计原则：
/// - 所有播放调用是非阻塞的；资源缺失或平台不支持时**静默失败**，不抛异常
/// - 音色冷峻、无人声、电报/雷达感（资源由美术替换；当前为占位空文件）
/// - 提供全局静音开关，遵从用户设置；系统静音由 [audioplayers] 处理
/// - 单例模式，与项目其他 `*Service` 一致
///
/// 资源映射：
/// | 方法 | 资源文件 | 时长 | 触发场景 |
/// |------|---------|------|---------|
/// | [playPulse] | `pulse.mp3` | ~250ms | 发送声呐脉冲 |
/// | [playCooldownReady] | `cooldown_ready.mp3` | ~80ms | 冷却结束按钮复活 |
/// | [playBlipReceived] | `blip.mp3` | ~80ms | 收到声呐 |
/// | [playMatchSuccess] | `match.mp3` | ~600ms | 双声呐共振匹配成功 |
/// | [playMessageOut] | `msg_out.mp3` | ~30ms | 发送消息 |
/// | [playMessageIn] | `msg_in.mp3` | ~30ms | 收到消息（前台） |
/// | [playDeepConfirm] | `deep_confirm.mp3` | ~500ms | 深度交流双方确认 |
/// | [playUnlock] | `unlock.mp3` | ~400ms | 解锁资料 |
/// | [playExpiringWarn] | `expiring.mp3` | ~300ms | 房间剩余 < 1h 警告 |
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  bool _enabled = true;
  bool _initialized = false;

  /// 同时只保留一个 player 防止冲突。
  late final AudioPlayer _player;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      _player = AudioPlayer();
      // ReleaseMode.stop：播完即释放，避免内存泄漏
      await _player.setReleaseMode(ReleaseMode.stop);
      // 用低延迟模式获得更接近 UI 的反馈感
      await _player.setPlayerMode(PlayerMode.lowLatency);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[SoundService] init failed: $e');
      }
    }
  }

  /// 用户全局静音开关。
  void setEnabled(bool value) {
    _enabled = value;
  }

  bool get isEnabled => _enabled;

  Future<void> _play(String asset) async {
    if (!_enabled || !_initialized) return;
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/$asset'));
    } catch (_) {
      // 资源缺失时静默失败：在文档化的占位资源全部到位前，是预期行为
    }
  }

  Future<void> playPulse() => _play('pulse.mp3');
  Future<void> playCooldownReady() => _play('cooldown_ready.mp3');
  Future<void> playBlipReceived() => _play('blip.mp3');
  Future<void> playMatchSuccess() => _play('match.mp3');
  Future<void> playMessageOut() => _play('msg_out.mp3');
  Future<void> playMessageIn() => _play('msg_in.mp3');
  Future<void> playDeepConfirm() => _play('deep_confirm.mp3');
  Future<void> playUnlock() => _play('unlock.mp3');
  Future<void> playExpiringWarn() => _play('expiring.mp3');

  Future<void> dispose() async {
    if (!_initialized) return;
    try {
      await _player.dispose();
    } catch (_) {}
    _initialized = false;
  }
}
