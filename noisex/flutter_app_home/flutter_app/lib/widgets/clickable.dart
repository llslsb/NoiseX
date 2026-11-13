import 'package:flutter/material.dart';
import '../theme/animations.dart';

/// 统一跨平台按压态组件
///
/// 🔒 设计规范：
/// - 按下时叠加 10% 黑色遮罩
/// - 150ms standard easing 淡入淡出动画
/// - 移除 Material 涟漪效果，确保 Flutter/鸿蒙两端视觉完全一致
class Clickable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final bool enabled;

  const Clickable({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.enabled = true,
  });

  @override
  State<Clickable> createState() => _ClickableState();
}

class _ClickableState extends State<Clickable>
    with SingleTickerProviderStateMixin {
  static const _overlayColor = Color(0x1A000000); // 10% 黑色

  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.fast, // 150ms
    );
    _colorAnimation = ColorTween(
      begin: Colors.transparent,
      end: _overlayColor,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: AppAnimations.standardCurve,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.enabled) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.enabled) {
      _controller.reverse();
    }
  }

  void _onTapCancel() {
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.enabled ? widget.onTap : null,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _colorAnimation,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              color: _colorAnimation.value,
              borderRadius: widget.borderRadius,
            ),
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
