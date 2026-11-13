import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/sonar_logo.dart';
import 'haptic_service.dart';
import 'sound_service.dart';
import 'storage_service.dart';

/// 仪式感动效服务
///
/// 负责三大仪式的视觉动效：
/// - 发送脉冲：全屏扩散波纹（每次发送都播放）
/// - 匹配成功：双 ping 撞击（每次匹配都播放）
/// - 风干仪式：淡出消散效果（房间过期时播放）
class RitualAnimationService {
  RitualAnimationService._();

  static final RitualAnimationService instance = RitualAnimationService._();

  /// 仪式动效开关键（默认开启）。用户可在设置页关闭。
  static const String _keyAnimEnabled = 'ritual_animation_enabled';

  /// 旧版本遗留的"首次"标志键。升级后清理，避免残留。
  /// （历史上这两个动效只播放一次，现已改为每次都播放。）
  static const String _legacyKeyFirstSonar = 'ritual_first_sonar_completed';
  static const String _legacyKeyFirstMatch = 'ritual_first_match_completed';

  /// Overlay 入口
  static OverlayEntry? _overlayEntry;

  /// 清理旧版本遗留的"首次"标志。
  ///
  /// 应在 app 启动初始化阶段调用一次（幂等，可重复调用）。
  /// 旧版本会把发送脉冲/匹配成功动效设为只播一次，标志持久化后导致
  /// 升级用户再也看不到动效。这里主动清除，让升级用户恢复体验。
  Future<void> cleanupLegacyFirstFlags() async {
    await StorageService().remove(_legacyKeyFirstSonar);
    await StorageService().remove(_legacyKeyFirstMatch);
  }

  /// 读取仪式动效开关（默认开启）。
  bool get ritualAnimationEnabled =>
      StorageService().getBool(_keyAnimEnabled, defaultValue: true);

  /// 设置仪式动效开关。
  Future<void> setRitualAnimationEnabled(bool enabled) =>
      StorageService().setBool(_keyAnimEnabled, enabled);

  /// 显示发送脉冲动效（每次发送声呐都播放）
  ///
  /// 调用时机：发送声呐成功后
  Future<void> showFirstPulse(BuildContext context) async {
    if (!ritualAnimationEnabled) return;
    if (_overlayEntry != null) return; // 防止重复

    // 创建全屏 Overlay
    _overlayEntry = OverlayEntry(
      builder: (context) => const _FirstPulseAnimation(
        onEnd: _removeOverlay,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
    HapticService.instance.heavy();
    SoundService.instance.playPulse();
  }

  /// 显示匹配成功动效（每次匹配都播放）
  ///
  /// 调用时机：匹配成功时（matched WS 事件）
  Future<void> showFirstMatch(BuildContext context) async {
    if (!ritualAnimationEnabled) return;
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => const _FirstMatchAnimation(
        onEnd: _removeOverlay,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  /// 显示风干仪式动效
  ///
  /// 调用时机：房间过期时（room_expired WS 事件）
  void showWithering(BuildContext context, String roomId) {
    if (!ritualAnimationEnabled) return;
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (context) => _WitheringAnimation(
        roomId: roomId,
        onEnd: _removeOverlay,
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  /// 移除 Overlay
  static void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }
}

/// 首次脉冲全屏动效
class _FirstPulseAnimation extends StatefulWidget {
  final VoidCallback onEnd;

  const _FirstPulseAnimation({required this.onEnd});

  @override
  State<_FirstPulseAnimation> createState() => _FirstPulseAnimationState();
}

class _FirstPulseAnimationState extends State<_FirstPulseAnimation>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;
  late Animation<double> _opacity;
  late Animation<double> _textOpacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    );

    _scale = Tween<double>(begin: 0.0, end: 3.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );

    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.5, 1.0)),
    );

    _textOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 10),
    ]).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

    _controller.forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onEnd();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () => widget.onEnd(), // 允许点击跳过
        child: SizedBox.expand(
          child: Stack(
            children: [
              // 黑色背景渐显
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Container(
                    color: Colors.black.withOpacity(_controller.value * 0.8),
                  );
                },
              ),
              // 扩散波纹
              Center(
                child: AnimatedBuilder(
                  animation: _scale,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _opacity.value,
                      child: Container(
                        width: size.shortestSide * _scale.value,
                        height: size.shortestSide * _scale.value,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.primary,
                            width: 4,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // 中心文字
              Center(
                child: AnimatedBuilder(
                  animation: _textOpacity,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _textOpacity.value,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SonarLogo(size: 80),
                          SizedBox(height: 24),
                          Text(
                            '声呐已发送',
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '等待信号回响',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 首次匹配双 ping 撞击动效
class _FirstMatchAnimation extends StatefulWidget {
  final VoidCallback onEnd;

  const _FirstMatchAnimation({required this.onEnd});

  @override
  State<_FirstMatchAnimation> createState() => _FirstMatchAnimationState();
}

class _FirstMatchAnimationState extends State<_FirstMatchAnimation>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _leftPingX;
  late Animation<double> _rightPingX;
  late Animation<double> _scale;
  late Animation<double> _flashOpacity;
  late Animation<double> _textOpacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    // 左侧 ping 从左向右移动
    _leftPingX = Tween<double>(begin: -200, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );

    // 右侧 ping 从右向左移动
    _rightPingX = Tween<double>(begin: 200, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: const Interval(0.0, 0.5, curve: Curves.easeOut)),
    );

    // 碰撞后的缩放
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.5), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _controller, curve: const Interval(0.4, 0.8)));

    // 碰撞闪光
    _flashOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 5),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 10),
    ]).animate(_controller);

    // 文字渐显
    _textOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 30),
    ]).animate(_controller);

    _controller.forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onEnd();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onTap: () => widget.onEnd(),
        child: SizedBox.expand(
          child: Stack(
            children: [
              // 半透明黑色背景
              Container(color: Colors.black.withOpacity(0.7)),
              // 碰撞闪光
              AnimatedBuilder(
                animation: _flashOpacity,
                builder: (context, child) {
                  return Opacity(
                    opacity: _flashOpacity.value,
                    child: Container(
                      color: AppColors.primary.withOpacity(0.3),
                    ),
                  );
                },
              ),
              // 左侧 ping
              AnimatedBuilder(
                animation: _leftPingX,
                builder: (context, child) {
                  return Positioned(
                    left: size.width / 2 + _leftPingX.value - 40,
                    top: size.height / 2 - 40,
                    child: _buildPing(_controller.value < 0.5),
                  );
                },
              ),
              // 右侧 ping
              AnimatedBuilder(
                animation: _rightPingX,
                builder: (context, child) {
                  return Positioned(
                    left: size.width / 2 + _rightPingX.value - 40,
                    top: size.height / 2 - 40,
                    child: _buildPing(_controller.value < 0.5),
                  );
                },
              ),
              // 中心碰撞效果
              Center(
                child: AnimatedBuilder(
                  animation: _scale,
                  builder: (context, child) {
                    return Transform.scale(
                      scale: _scale.value,
                      child: _buildPing(true),
                    );
                  },
                ),
              ),
              // 文字提示
              Center(
                child: AnimatedBuilder(
                  animation: _textOpacity,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _textOpacity.value,
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '⚡',
                            style: TextStyle(fontSize: 60),
                          ),
                          SizedBox(height: 16),
                          Text(
                            '信号共振',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '与附近的人建立连接',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPing(bool visible) {
    return Visibility(
      visible: visible,
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.primary, width: 4),
          color: AppColors.primary.withOpacity(0.2),
        ),
      ),
    );
  }
}

/// 风干仪式动效
class _WitheringAnimation extends StatefulWidget {
  final String roomId;
  final VoidCallback onEnd;

  const _WitheringAnimation({
    required this.roomId,
    required this.onEnd,
  });

  @override
  State<_WitheringAnimation> createState() => _WitheringAnimationState();
}

class _WitheringAnimationState extends State<_WitheringAnimation>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<double> _grainOpacity;
  late Animation<double> _textOpacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

    // 整体淡出
    _opacity = Tween<double>(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // 噪点渐显
    _grainOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.3), weight: 30),
      TweenSequenceItem(tween: ConstantTween(0.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 0.3, end: 0.0), weight: 30),
    ]).animate(_controller);

    // 文字渐显渐隐
    _textOpacity = TweenSequence<double>([
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 20),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 40),
    ]).animate(_controller);

    _controller.forward();

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onEnd();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final roomIdShort = widget.roomId.substring(0, 8);

    return Material(
      color: Colors.transparent,
      child: SizedBox.expand(
        child: Stack(
          children: [
            // 黑色背景
            Container(color: Colors.black),
            // 噪点效果（模拟风干）
            AnimatedBuilder(
              animation: _grainOpacity,
              builder: (context, child) {
                return Opacity(
                  opacity: _grainOpacity.value,
                  child: _buildGrain(size),
                );
              },
            ),
            // 中心文字
            Center(
              child: AnimatedBuilder(
                animation: _textOpacity,
                builder: (context, child) {
                  return Opacity(
                    opacity: _textOpacity.value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '💨',
                          style: TextStyle(fontSize: 60),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '对话已风干',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '与 $roomIdShort... 的信号已消散',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // 淡出遮罩
            AnimatedBuilder(
              animation: _opacity,
              builder: (context, child) {
                return Container(
                  color: Colors.black.withOpacity(1 - _opacity.value),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 构建噪点效果
  Widget _buildGrain(Size size) {
    return CustomPaint(
      size: size,
      painter: _GrainPainter(),
    );
  }
}

/// 噪点绘制器
class _GrainPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x10FFFFFF);

    final rng = DateTime.now().millisecondsSinceEpoch;
    for (int i = 0; i < 500; i++) {
      final x = (rng * (i + 1) % size.width).toDouble();
      final y = (rng * (i + 2) % size.height).toDouble();
      canvas.drawCircle(Offset(x, y), 1, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
