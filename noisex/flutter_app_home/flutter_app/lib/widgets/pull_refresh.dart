import 'dart:async';

import 'package:flutter/material.dart';
import '../services/debug_log.dart';
import '../theme/scroll_physics.dart';
import '../theme/animations.dart';
import '../theme/colors.dart';

/// 统一跨平台下拉刷新组件
///
/// 🔒 设计规范：
/// - 阻尼公式：有效拉伸距离 = 0.5 * 滑动距离 / (1 + 滑动距离 / 200)
/// - 触发阈值：原始拉伸 80dp（阻尼仅用于视觉形变；按阻尼后值判定永远达不到）
/// - 回弹动画：300ms standard easing
/// - 与鸿蒙端 PullRefresh.ets 1:1 对齐
class PullRefresh extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onRefresh;
  final double triggerDistance;

  const PullRefresh({
    super.key,
    required this.child,
    required this.onRefresh,
    this.triggerDistance = 80.0,
  });

  @override
  State<PullRefresh> createState() => _PullRefreshState();
}

class _PullRefreshState extends State<PullRefresh>
    with SingleTickerProviderStateMixin {
  /// 原始滑动距离（未应用阻尼）
  double _dragDistance = 0.0;

  /// 是否正在刷新
  bool _isRefreshing = false;

  /// 是否已经触发刷新
  bool _triggered = false;

  /// 动画控制器（用于回弹）
  late AnimationController _bounceController;

  /// 手势停止看门狗：部分环境手势结束不派发 ScrollEndNotification
  /// （OHOS 模拟器注入滑动实锤：列表冻结在拉伸态永不回弹），停更
  /// [_dragIdleTimer] 时长后按"手势已结束"兜底。
  Timer? _dragIdleTimer;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: AppAnimations.slow, // 300ms
    );
  }

  @override
  void dispose() {
    _dragIdleTimer?.cancel();
    _bounceController.dispose();
    super.dispose();
  }

  /// 应用统一阻尼公式
  double get _effectiveDistance {
    return UnifiedScrollPhysics.applyDamping(_dragDistance);
  }

  /// 是否达到触发阈值：对【原始拉伸距离】判定（阻尼只用于视觉形变）。
  /// 旧实现拿阻尼后距离比阈值——阻尼公式渐近上限 ~100dp，80dp 阈值
  /// 实际永远达不到，组件接线后从未真正触发过刷新。
  bool get _canTrigger => _dragDistance >= widget.triggerDistance;

  void _handleDragUpdate(double delta) {
    if (_isRefreshing) return;
    _dragIdleTimer?.cancel();
    _dragIdleTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted && !_isRefreshing && _dragDistance > 0) {
        DebugLog().write('PullRefresh watchdog fires at $_dragDistance');
        _handleDragEnd();
      }
    });
    setState(() {
      _dragDistance = (_dragDistance + delta).clamp(0.0, 250.0);
      _triggered = false;
    });
  }

  void _handleDragEnd() async {
    _dragIdleTimer?.cancel();
    if (_isRefreshing) return;
    DebugLog().write(
        'PullRefresh dragEnd: dist=$_dragDistance canTrigger=$_canTrigger');

    if (_canTrigger && !_triggered) {
      _triggered = true;
      // 回弹到刷新位置
      await _bounceToRefreshPosition();
      // 执行刷新
      await _performRefresh();
    } else {
      // 回弹到起始位置
      await _bounceBack();
    }
  }

  /// 回弹到刷新位置
  Future<void> _bounceToRefreshPosition() async {
    final targetDistance = widget.triggerDistance;
    final startDistance = _dragDistance;
    final anim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _bounceController,
      curve: AppAnimations.standardCurve,
    ));

    _bounceController.reset();
    anim.addListener(() {
      setState(() {
        _dragDistance = startDistance +
            (targetDistance - startDistance) * anim.value;
      });
    });

    DebugLog().write('PullRefresh bounceToRefresh start');
    await _bounceController.forward();
    DebugLog().write('PullRefresh bounceToRefresh done');
  }

  /// 回弹到起始位置
  Future<void> _bounceBack() async {
    final startDistance = _dragDistance;
    final anim = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(
      parent: _bounceController,
      curve: AppAnimations.standardCurve,
    ));

    _bounceController.reset();
    anim.addListener(() {
      setState(() {
        _dragDistance = startDistance * (1 - anim.value);
      });
    });

    await _bounceController.forward();
    setState(() {
      _dragDistance = 0;
    });
  }

  /// 执行刷新逻辑
  Future<void> _performRefresh() async {
    DebugLog().write('PullRefresh refresh start');
    setState(() {
      _isRefreshing = true;
    });

    try {
      await widget.onRefresh();
      DebugLog().write('PullRefresh refresh ok');
    } finally {
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
        // 刷新完成后回弹
        await _bounceBack();
        DebugLog().write('PullRefresh bounceBack done');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 列表内容
        Positioned.fill(
          child: Transform.translate(
            offset: Offset(0, _effectiveDistance),
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is OverscrollNotification &&
                    notification.overscroll < 0) {
                  // Clamping 物理（Android/OHOS）：顶部继续下拉时 pixels 不变负，
                  // 越界量以 OverscrollNotification（overscroll<0）通报，必须
                  // 在此累计拉伸——只听 ScrollUpdate 会让刷新手势在双端彻底失灵
                  _handleDragUpdate(-notification.overscroll);
                } else if (notification is ScrollUpdateNotification &&
                    notification.metrics.pixels <= 0) {
                  // Bouncing 物理（iOS/macOS）：顶部越界时 pixels 变负，
                  // 以 ScrollUpdateNotification 通报
                  if (notification.scrollDelta != null &&
                      notification.scrollDelta! < 0) {
                    _handleDragUpdate(-notification.scrollDelta!);
                  }
                } else if (notification is ScrollEndNotification) {
                  _handleDragEnd();
                }
                return false;
              },
              child: widget.child,
            ),
          ),
        ),
        // 刷新指示器（位于列表上方，随下拉出现）
        if (_effectiveDistance > 0 || _isRefreshing)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Transform.translate(
              offset: Offset(0, _effectiveDistance - widget.triggerDistance),
              child: Container(
                height: widget.triggerDistance,
                alignment: Alignment.center,
                child: _RefreshIndicator(
                  progress: _isRefreshing
                      ? null
                      : (_effectiveDistance / widget.triggerDistance).clamp(0.0, 1.0),
                  canTrigger: _canTrigger,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 刷新指示器动画
class _RefreshIndicator extends StatelessWidget {
  final double? progress;
  final bool canTrigger;

  const _RefreshIndicator({
    this.progress,
    this.canTrigger = false,
  });

  @override
  Widget build(BuildContext context) {
    final isAnimating = progress == null;
    final p = progress ?? 1.0;

    return SizedBox(
      width: 32,
      height: 32,
      child: CircularProgressIndicator(
        value: isAnimating ? null : p,
        strokeWidth: 2.5,
        color: canTrigger ? AppColors.primary : AppColors.textSecondary,
        backgroundColor: AppColors.bgMuted.withOpacity(0.3),
      ),
    );
  }
}
