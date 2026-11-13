import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// 雷达扫描动画组件（含信号点随机出现/消失）
/// 与鸿蒙端 RadarAnimation.ets 对齐
///
/// [blipCount] 由后端 nearby-activity 接口提供（已 clamp 至 0..8），
/// 决定雷达上同时存在的信号点数量，反映附近真实活跃人数。
///
/// 布局自适应：Positioned.fill 铺满父容器时以父容器实际尺寸取圆心
/// （旧版硬编码 320 盒子坐标，宽屏折叠机上指针/信号点飘到左上角——
/// Mate X7 联调实锤）；信号点存极坐标，尺寸变化无需重生成。
class RadarAnimation extends StatefulWidget {
  final bool isActive;
  final double size;
  final int blipCount;

  const RadarAnimation({
    super.key,
    this.isActive = true,
    this.size = 320,
    this.blipCount = 3,
  });

  @override
  State<RadarAnimation> createState() => _RadarAnimationState();
}

class _RadarAnimationState extends State<RadarAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _sweepController;
  Timer? _blipTimer;
  int _blipPhase = 0;
  List<_Blip> _blips = const [];

  /// 每个相位（0..5）对应的可见信号点比例，营造"呼吸式"出现/消失。
  static const List<double> _phaseRatios = [0.34, 0.5, 0.67, 0.84, 1.0, 0.5];

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _regenerateBlips();
    _startBlips();
  }

  @override
  void didUpdateWidget(covariant RadarAnimation oldWidget) {
    super.didUpdateWidget(oldWidget);
    // blipCount 变化时立即刷新，不必等下个 tick
    if (oldWidget.blipCount != widget.blipCount) {
      _regenerateBlips();
    }
  }

  @override
  void dispose() {
    _sweepController.dispose();
    _blipTimer?.cancel();
    super.dispose();
  }

  void _startBlips() {
    _blipTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!widget.isActive || !mounted) return;
      _regenerateBlips();
    });
  }

  /// 根据 widget.blipCount 重新生成信号点：数量反映附近活跃人数，
  /// 可见数量按当前相位比例缩放。位置存极坐标（角度 + 0.3~1.0 半径比例），
  /// 绘制时按实际雷达半径缩放，任何容器尺寸都保持居中同心。
  void _regenerateBlips() {
    final count = widget.blipCount.clamp(0, 8);
    if (count == 0) {
      if (mounted) setState(() => _blips = const []);
      return;
    }
    _blipPhase = (_blipPhase + 1) % 6;
    final rng = math.Random();

    // 当前相位应可见的数量
    final visibleN = (count * _phaseRatios[_blipPhase]).round().clamp(0, count);
    // 随机挑选哪些 index 可见，避免每次都是同一批信号点
    final order = List<int>.generate(count, (i) => i)..shuffle(rng);
    final visibleSet = order.take(visibleN).toSet();

    final List<_Blip> next = <_Blip>[];
    for (var i = 0; i < count; i++) {
      next.add(_Blip(
        angle: rng.nextDouble() * math.pi * 2,
        // 0.35~1.0：落在最内环之外、最外环之内
        radiusFactor: 0.35 + rng.nextDouble() * 0.65,
        visible: visibleSet.contains(i),
      ));
    }
    if (mounted) setState(() => _blips = next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final double w = constraints.maxWidth.isFinite && constraints.maxWidth > 0
          ? constraints.maxWidth
          : widget.size;
      final double h = constraints.maxHeight.isFinite && constraints.maxHeight > 0
          ? constraints.maxHeight
          : widget.size;
      final double cx = w / 2;
      final double cy = h / 2;
      final double radius = math.min(w, h) / 2;

      return SizedBox(
        width: w.isFinite ? w : widget.size,
        height: h.isFinite ? h : widget.size,
        child: Opacity(
          opacity: widget.isActive ? 1.0 : 0.3,
          child: Stack(
            children: [
              _buildCircle(cx, cy, radius * 2, 2, 0.3),
              _buildCircle(cx, cy, radius * 1.5, 1, 0.2),
              _buildCircle(cx, cy, radius * 1.0, 1, 0.2),
              _buildCircle(cx, cy, radius * 0.5, 1, 0.2),

              // 扫描指针：锚定圆心，绕 centerLeft 旋转（渐隐向圆心）
              AnimatedBuilder(
                animation: _sweepController,
                builder: (context, child) {
                  final sweepAngle = _sweepController.value * 360;
                  return Positioned(
                    left: cx,
                    top: cy - 1,
                    child: Transform.rotate(
                      angle: sweepAngle * math.pi / 180,
                      alignment: Alignment.centerLeft,
                      child: Container(
                        width: radius,
                        height: 2,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primary, Colors.transparent],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),

              for (int i = 0; i < _blips.length; i++)
                if (_blips[i].visible)
                  Positioned(
                    left: cx +
                        math.cos(_blips[i].angle) *
                            _blips[i].radiusFactor *
                            radius *
                            0.92 -
                        4,
                    top: cy +
                        math.sin(_blips[i].angle) *
                            _blips[i].radiusFactor *
                            radius *
                            0.92 -
                        4,
                    child: Container(
                      // 最远端（最后一个）信号点更小更淡，营造层次
                      width: _isTail(i) ? 6.0 : 8.0,
                      height: _isTail(i) ? 6.0 : 8.0,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primary
                            .withOpacity(_isTail(i) ? 0.7 : 1.0),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      );
    });
  }

  bool _isTail(int i) => i == _blips.length - 1 && _blips.length > 1;

  Widget _buildCircle(
      double cx, double cy, double diameter, double strokeWidth, double opacity) {
    return Positioned(
      left: cx - diameter / 2,
      top: cy - diameter / 2,
      width: diameter,
      height: diameter,
      child: CustomPaint(
        painter: _CirclePainter(
          color: AppColors.primary.withOpacity(opacity),
          strokeWidth: strokeWidth,
        ),
      ),
    );
  }
}

class _CirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;

  _CirclePainter({required this.color, required this.strokeWidth});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawOval(
      Rect.fromCircle(center: Offset(size.width / 2, size.height / 2), radius: size.width / 2),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CirclePainter oldDelegate) => oldDelegate.color != color;
}

class _Blip {
  final double angle;
  final double radiusFactor;
  final bool visible;

  _Blip({required this.angle, required this.radiusFactor, required this.visible});
}
