import 'package:flutter/material.dart';
import '../services/haptic_service.dart';
import '../services/sound_service.dart';
import '../theme/colors.dart';

/// 声呐脉冲按钮。
///
/// 设计目标（详见 `docs/superpowers/plans/2026-06-15-ux-revamp.md` P0-1/P0-8/P0-10）：
/// - 点击带中等触觉 + 短"咚"音效（音效在 SoundService 内若资源缺失静默失败）
/// - 冷却时显示剩余秒数 + "冷却中"（对齐鸿蒙端 PulseButton，无进度环）
/// - 倒计时归零瞬间触发 selectionClick + 复活脉冲
/// - 加 Semantics label 供屏幕阅读器使用
class PulseButton extends StatefulWidget {
  /// 当前剩余冷却秒数，0 表示可用。
  final int cooldown;

  /// 冷却起始的总秒数（保留参数位，当前仅用于语义标注）。
  final int cooldownTotal;

  /// 是否显示扩散 ping。空闲时为 true，冷却时为 false。
  final bool isActive;

  /// 点击回调；外层负责实际"发出脉冲"逻辑。
  final VoidCallback onPulse;

  const PulseButton({
    super.key,
    this.cooldown = 0,
    this.cooldownTotal = 0,
    this.isActive = true,
    required this.onPulse,
  });

  @override
  State<PulseButton> createState() => _PulseButtonState();
}

class _PulseButtonState extends State<PulseButton>
    with TickerProviderStateMixin {
  late AnimationController _pingController;
  late AnimationController _breathController;
  late Animation<double> _pingScale1;
  late Animation<double> _pingOpacity1;
  late Animation<double> _pingScale2;
  late Animation<double> _pingOpacity2;
  late Animation<double> _pingScale3;
  late Animation<double> _pingOpacity3;
  late Animation<double> _breathScale;
  double _pressScale = 1.0;
  double _hoverScale = 1.0;
  int _lastCooldown = 0;

  @override
  void initState() {
    super.initState();
    _lastCooldown = widget.cooldown;

    _pingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    _pingScale1 = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _pingController, curve: const Interval(0.0, 0.5)),
    );
    _pingOpacity1 = Tween<double>(begin: 0.3, end: 0.0).animate(
      CurvedAnimation(parent: _pingController, curve: const Interval(0.0, 0.5)),
    );

    _pingScale2 = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _pingController, curve: const Interval(0.25, 0.75)),
    );
    _pingOpacity2 = Tween<double>(begin: 0.2, end: 0.0).animate(
      CurvedAnimation(parent: _pingController, curve: const Interval(0.25, 0.75)),
    );

    _pingScale3 = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _pingController, curve: const Interval(0.5, 1.0)),
    );
    _pingOpacity3 = Tween<double>(begin: 0.15, end: 0.0).animate(
      CurvedAnimation(parent: _pingController, curve: const Interval(0.5, 1.0)),
    );

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _breathScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.97), weight: 20),
      TweenSequenceItem(tween: Tween(begin: 0.97, end: 1.0), weight: 30),
      TweenSequenceItem(tween: ConstantTween(1.0), weight: 50),
    ]).animate(_breathController);
  }

  @override
  void didUpdateWidget(covariant PulseButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 倒计时归零瞬间：触发轻触觉 + 短音
    if (_lastCooldown > 0 && widget.cooldown == 0) {
      HapticService.instance.selection();
      SoundService.instance.playCooldownReady();
    }
    _lastCooldown = widget.cooldown;
  }

  @override
  void dispose() {
    _pingController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  /// `mm:ss` 倒计时显示。
  String _formatCooldown(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _handleTap() {
    HapticService.instance.medium();
    SoundService.instance.playPulse();
    widget.onPulse();
  }

  @override
  Widget build(BuildContext context) {
    final isDisabled = widget.cooldown > 0;
    final showPing = widget.isActive && !isDisabled;

    final semanticsLabel = isDisabled
        ? '声呐脉冲冷却中，剩余 ${_formatCooldown(widget.cooldown)}'
        : '发送声呐脉冲';

    return Semantics(
      button: true,
      enabled: !isDisabled,
      label: semanticsLabel,
      child: SizedBox(
        width: 132,
        height: 132,
        child: AnimatedBuilder(
          animation: Listenable.merge([_pingController, _breathController]),
          builder: (context, child) {
            final mainScale = isDisabled
                ? 1.0
                : _breathScale.value * _pressScale * _hoverScale;

            return GestureDetector(
              onTapDown: isDisabled
                  ? null
                  : (_) => setState(() => _pressScale = 0.95),
              onTapUp: isDisabled
                  ? null
                  : (_) => setState(() => _pressScale = 1.0),
              onTapCancel: () => setState(() => _pressScale = 1.0),
              onTap: isDisabled ? null : _handleTap,
              child: MouseRegion(
                onEnter: isDisabled
                    ? null
                    : (_) => setState(() => _hoverScale = 1.05),
                onExit: isDisabled
                    ? null
                    : (_) => setState(() => _hoverScale = 1.0),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (showPing) _buildPing(_pingScale1, _pingOpacity1),
                    if (showPing) _buildPing(_pingScale2, _pingOpacity2),
                    if (showPing) _buildPing(_pingScale3, _pingOpacity3),
                    // 主按钮圆（对齐鸿蒙端：120×120，描边 4px）
                    Transform.scale(
                      scale: mainScale,
                      child: SizedBox(
                        width: 120,
                        height: 120,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            // 对齐鸿蒙端：空闲 primary_input(10% 橙)、冷却 bg_muted
                            color: isDisabled
                                ? AppColors.bgMuted
                                : AppColors.primaryInput,
                            border: Border.all(
                              color: isDisabled
                                  ? AppColors.bgAccent
                                  : AppColors.primary,
                              width: 4,
                            ),
                            boxShadow: showPing
                                ? [
                                    const BoxShadow(
                                      color: Color(0x33FF6B35),
                                      blurRadius: 40,
                                      spreadRadius: 0,
                                    ),
                                  ]
                                : null,
                          ),
                          child: Center(
                            child: isDisabled
                                  ? Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // UI 评审 P0：格式化恢复时刻（m:ss）替代裸秒数，
                                      // 双端同款（鸿蒙端 PulseButton.ets 同步改）
                                      Text(
                                        _formatCooldown(widget.cooldown),
                                        style: const TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        '冷却中',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  )
                                : const Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text('📡',
                                          style: TextStyle(fontSize: 40)),
                                      SizedBox(height: 6),
                                      Text(
                                        '发送脉冲',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPing(Animation<double> scale, Animation<double> opacity) {
    return Transform.scale(
      scale: scale.value,
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFFFF6B35).withOpacity(opacity.value),
            width: 1,
          ),
        ),
      ),
    );
  }
}
