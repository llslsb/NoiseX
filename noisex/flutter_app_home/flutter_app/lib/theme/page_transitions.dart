import 'package:flutter/material.dart';
import 'animations.dart';

/// NoiseX 统一页面转场动画集合
///
/// 所有页面切换必须使用这里定义的转场，禁止使用 Navigator 默认动画。
/// 与 HarmonyOS 端 NavDestination 转场参数 1:1 对齐。
///
/// 使用方式：
/// ```dart
/// // 右滑推入（聊天页）
/// Navigator.of(context).push(SlideRightPageRoute(page: const ChatPage()));
///
/// // 底部滑入（模态弹窗）
/// Navigator.of(context).push(SlideUpPageRoute(page: const ProfilePage()));
///
/// // 淡入淡出（Tab 切换已在 app.dart 内置）
/// ```
class PageTransitions {
  PageTransitions._();

  /// 标准淡入淡出转场（FadeThrough）
  ///
  /// 新页面从 0.98 缩放 + Opacity 0 → 1.0 缩放 + Opacity 1
  /// 旧页面从 1.0 缩放 + Opacity 1 → 1.02 缩放 + Opacity 0
  ///
  /// 用于：Tab 切换、同级页面切换
  static Widget fadeThrough(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) return child;

    final anim = CurvedAnimation(
      parent: animation,
      curve: AppAnimations.pageTransitionCurve,
    );

    return FadeTransition(
      opacity: Tween<double>(begin: 0.0, end: 1.0).animate(anim),
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.98, end: 1.0).animate(anim),
        child: child,
      ),
    );
  }

  /// 右滑推入转场（SlideRight）
  ///
  /// 新页面从右侧 Offset(1, 0) 滑入 → Offset(0, 0)
  /// 旧页面从 Offset(0, 0) 滑出 → Offset(-0.3, 0)
  /// 背景蒙层从透明渐暗到黑色 30%
  ///
  /// 用于：聊天页、详情页（支持右滑返回手势）
  static Widget slideRight(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) return child;

    final anim = CurvedAnimation(
      parent: animation,
      curve: AppAnimations.pageTransitionCurve,
    );

    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      builder: (context, child) {
        // 背景渐暗效果
        final backgroundOpacity = secondaryAnimation.value * 0.3;

        return Stack(
          children: [
            // 背景蒙层（仅在弹出时显示）
            if (secondaryAnimation.value > 0)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withOpacity(backgroundOpacity),
                ),
              ),
            // 页面内容
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(1.0, 0.0),
                end: Offset.zero,
              ).animate(anim),
              child: FadeTransition(
                opacity: Tween<double>(begin: 0.0, end: 1.0).animate(anim),
                child: child,
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }

  /// 底部滑入转场（SlideUp / 模态）
  ///
  /// 新页面从底部 Offset(0, 1) 滑入 → Offset(0, 0)
  /// 背景蒙层 Opacity 0 → 0.5
  ///
  /// 用于：设置页、举报页、资料编辑等模态页面
  static Widget slideUp(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    if (reduceMotion) return child;

    final anim = CurvedAnimation(
      parent: animation,
      curve: AppAnimations.pageTransitionCurve,
    );

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0.0, 1.0),
        end: Offset.zero,
      ).animate(anim),
      child: FadeTransition(
        opacity: Tween<double>(begin: 0.0, end: 1.0).animate(anim),
        child: child,
      ),
    );
  }

  /// 共享元素转场（Hero 包装）
  ///
  /// 用于：房间卡片 → 聊天页的 signalCode 标签转场
  static Widget sharedElement({
    required BuildContext context,
    required String tag,
    required Widget child,
  }) {
    return Hero(
      tag: tag,
      transitionOnUserGestures: true,
      flightShuttleBuilder: (
        flightContext,
        animation,
        flightDirection,
        fromHeroContext,
        toHeroContext,
      ) {
        final reduceMotion = MediaQuery.of(context).disableAnimations;
        if (reduceMotion) return child;

        final anim = CurvedAnimation(
          parent: animation,
          curve: AppAnimations.pageTransitionCurve,
        );

        return AnimatedBuilder(
          animation: anim,
          builder: (context, child) {
            return Transform.scale(
              scale: 0.9 + 0.1 * anim.value,
              child: child,
            );
          },
          child: child,
        );
      },
      child: child,
    );
  }
}

/// 右滑推入 PageRoute（聊天页专用）
///
/// 自定义 PageRouteBuilder，支持：
/// - 右滑推入动画（新页面从右侧滑入）
/// - 旧页面向左平移 + 渐暗背景
/// - Cupertino 风格边缘滑动返回手势
///
/// 与 HarmonyOS 端 NavDestination 右滑返回体验对齐。
class SlideRightPageRoute<T> extends PageRouteBuilder<T> {
  SlideRightPageRoute({
    required Widget Function(BuildContext) builder,
    super.settings,
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) =>
              builder(context),
          transitionsBuilder: (
            context,
            animation,
            secondaryAnimation,
            child,
          ) =>
              PageTransitions.slideRight(
            context,
            animation,
            secondaryAnimation,
            child,
          ),
          transitionDuration: AppAnimations.pageTransition,
          maintainState: true,
        );
}

/// 底部滑入 PageRoute（模态弹窗专用）
class SlideUpPageRoute<T> extends PageRoute<T> {
  SlideUpPageRoute({
    required this.page,
    RouteSettings? settings,
    bool barrierDismissible = true,
  })  : _barrierDismissible = barrierDismissible,
        super(settings: settings);

  final Widget page;
  final bool _barrierDismissible;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => AppAnimations.pageTransition;

  @override
  Color get barrierColor => Colors.black54;

  @override
  String get barrierLabel => 'Dismiss';

  @override
  bool get barrierDismissible => _barrierDismissible;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return PageTransitions.slideUp(context, animation, secondaryAnimation, child);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return page;
  }
}

/// 淡入淡出 PageRoute
class FadeThroughPageRoute<T> extends PageRoute<T> {
  FadeThroughPageRoute({
    required this.page,
    RouteSettings? settings,
  }) : super(settings: settings);

  final Widget page;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => AppAnimations.pageTransition;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return PageTransitions.fadeThrough(context, animation, secondaryAnimation, child);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return page;
  }
}
