import 'package:flutter/services.dart';

/// 全局触觉反馈服务。
///
/// 用法：[HapticService.instance.selection()]、[HapticService.instance.medium()] 等。
/// 通过 [setEnabled] 提供全局开关；默认开启。
///
/// 与设计文档 `docs/superpowers/plans/2026-06-15-ux-revamp.md` 中
/// P0-1 任务对齐。在不支持触觉的平台上自动 no-op。
class HapticService {
  HapticService._();
  static final HapticService instance = HapticService._();

  bool _enabled = true;

  /// 用户全局开关。
  void setEnabled(bool value) {
    _enabled = value;
  }

  bool get isEnabled => _enabled;

  /// 极轻反馈，用于切换 Tab、勾选、冷却归零等"信息层"事件。
  Future<void> selection() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {
      // 平台不支持时静默失败
    }
  }

  /// 轻反馈，用于发送消息这类高频低权重事件。
  Future<void> light() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// 中等反馈，用于"发送脉冲""确认深度交流"这类有承诺感的动作。
  Future<void> medium() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// 强反馈，用于"解锁资料""保存连接""房间即将过期警告"这类决定性事件。
  Future<void> heavy() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// 振动反馈（更长，约 500ms）。仅用于即将过期的关键提醒。
  Future<void> vibrate() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.vibrate();
    } catch (_) {}
  }
}
