import 'package:flutter/animation.dart';

/// NoiseX 统一动画 Design Token
///
/// 所有动画参数必须从这里引用，禁止硬编码数值。
/// 与 HarmonyOS 端 model/AnimationTokens.ets 保持 1:1 对齐。
class AppAnimations {
  AppAnimations._();

  // ============================================================
  // 基础时长 Token (ms)
  // ============================================================

  /// 最快的微交互动画（按钮按下、状态切换）
  static const Duration fast = Duration(milliseconds: 150);

  /// 标准过渡动画（页面转场、Tab 切换）
  static const Duration normal = Duration(milliseconds: 250);

  /// 较慢的动画（模态弹出、面板展开）
  static const Duration slow = Duration(milliseconds: 300);

  /// 缓慢动画（仪式感动效、雷达扫描）
  static const Duration verySlow = Duration(seconds: 2);

  // ============================================================
  // 场景化时长 Token
  // ============================================================

  /// 页面转场时长
  static const Duration pageTransition = Duration(milliseconds: 300);

  /// Tab 切换时长
  static const Duration tabActivate = Duration(milliseconds: 250);

  /// 消息气泡入场时长
  static const Duration messageBubbleEnter = Duration(milliseconds: 250);

  /// 列表交错动画延迟（每条消息）
  static const Duration staggerDelay = Duration(milliseconds: 50);

  /// 呼吸脉冲周期
  static const Duration pulse = Duration(seconds: 2);

  /// 房间即将过期脉冲
  static const Duration expiringPulse = Duration(seconds: 1);

  /// 雷达扫描周期
  static const Duration radarSweep = Duration(seconds: 4);

  /// 网络 Ping 动画
  static const Duration ping = Duration(seconds: 2);

  /// 淡入淡出时长
  static const Duration fadeIn = Duration(milliseconds: 500);
  static const Duration fadeInUp = Duration(milliseconds: 300);
  static const Duration slideUp = Duration(milliseconds: 300);

  /// 打字指示器相位延迟
  static const Duration typingPhaseDelay = Duration(milliseconds: 200);

  /// 触摸反馈微振动
  static const Duration hapticFeedback = Duration(milliseconds: 30);

  // ============================================================
  // 标准曲线 Token
  // ============================================================

  /// 标准缓入缓出（页面转场、状态切换）- Material Design 3 standard easing
  static const Curve standardCurve = Cubic(0.2, 0.0, 0.2, 1.0);

  /// 减速曲线（元素入场：从快到慢）- Material Design 3 decelerate easing
  static const Curve decelerateCurve = Cubic(0.0, 0.0, 0.2, 1.0);

  /// 加速曲线（元素离场：从慢到快）- Material Design 3 accelerate easing
  static const Curve accelerateCurve = Cubic(0.4, 0.0, 1.0, 1.0);

  /// 弹簧曲线（按钮、交互元素）
  static const Curve springCurve = Curves.elasticOut;

  /// 呼吸脉冲曲线
  static const Curve pulseCurve = Curves.easeInOutSine;

  // ============================================================
  // 场景化曲线 Token
  // ============================================================

  static const Curve pageTransitionCurve = Cubic(0.2, 0.0, 0.2, 1.0);
  static const Curve fadeInUpCurve = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Curve slideUpCurve = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Curve messageBubbleCurve = Cubic(0.0, 0.0, 0.2, 1.0);
  static const Curve tabSwitchCurve = Cubic(0.2, 0.0, 0.2, 1.0);

  // ============================================================
  // 弹簧物理参数
  // ============================================================

  /// 弹簧阻尼比（0.0-1.0，越大越硬）
  static const double springDamping = 0.82;

  /// 弹簧刚度（越大回弹越快）
  static const double springStiffness = 400.0;

  /// 弹簧质量（越大惯性越大）
  static const double springMass = 1.0;

  // ============================================================
  // 几何参数
  // ============================================================

  /// 消息气泡入场 Y 轴偏移量
  static const double messageBubbleOffsetY = 20.0;

  /// 页面转场滑入偏移量
  static const double pageTransitionOffsetX = 100.0;

  /// Tab 图标呼吸透明度范围
  static const double pulseMinOpacity = 0.5;
  static const double pulseMaxOpacity = 1.0;
}
