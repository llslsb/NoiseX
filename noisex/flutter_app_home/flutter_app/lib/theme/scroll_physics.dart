import 'package:flutter/material.dart';

/// 统一跨平台滚动配置
///
/// 🔒 设计规范：
/// - 惯性弹道/边界回弹/越界阻尼全部交给平台默认物理——自研弹道两次实锤翻车：
///   旧版无条件把弹道终点钉在 maxScrollExtent（列表中部往下滑被甩到底部，
///   "滚动像没做"的根因）；2026-11-03 委托 parent 版本因全局配置下 parent
///   为空恒返回 null，越界位置冻结不回弹。平台默认物理即目标行为，不再覆写
/// - 下拉刷新阻尼：有效拉伸距离 = 0.5 * 滑动距离 / (1 + 滑动距离 / 200)
///   （PullRefresh 专用，见 widgets/pull_refresh.dart）
/// - 与鸿蒙端 scroll configuration 1:1 对齐
class UnifiedScrollPhysics {
  /// 阻尼系数（下拉刷新时的弹性）
  static const double dampingFactor = 0.5;

  /// 渐近极限距离（dp）
  static const double asymptoticLimit = 200.0;

  /// 计算下拉刷新时的阻尼有效距离
  static double applyDamping(double dragDistance) {
    return dampingFactor * dragDistance / (1 + dragDistance / asymptoticLimit);
  }
}

/// 全局滚动配置：仅作统一入口标记，滚动物理交平台默认
///（原 copyWith(physics:) 版本即上述两次翻车源头，已移除）
class UnifiedScrollConfiguration extends StatelessWidget {
  final Widget child;

  const UnifiedScrollConfiguration({
    super.key,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: const ScrollBehavior(),
      child: child,
    );
  }
}
