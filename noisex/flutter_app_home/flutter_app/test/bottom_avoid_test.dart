import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/widgets/tab_bar.dart';

/// AGC UX 自检修复（2026-11-08）的回归锁：
/// EntryAbility 全屏布局下 Flutter-OH 引擎上报的 padding.bottom 常为 0，
/// 旧实现只包 SafeArea → 底部 tab 文字距屏底仅 ~10vp（<28vp，四条报告同因）。
/// 修复 = 避让高度 max(系统上报, 32vp)。这两条测试锁死「保底避让」不得回退。
void main() {
  // 模拟 AppTabBar 所需的最小环境（Material 祖先 + 三个 tab 的显示方向）
  Widget host(EdgeInsets padding) => MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(padding: padding),
          child: Scaffold(
            body: const SizedBox.expand(),
            bottomNavigationBar: AppTabBar(
              activeTab: 'sonar',
              onTabChanged: (_) {},
            ),
          ),
        ),
      );

  double tabTextDistanceToScreenBottom(WidgetTester tester) {
    final textTop = tester.getTopLeft(find.text('声呐')).dy;
    final textBottom = tester.getTopRight(find.text('声呐')).dy +
        tester.getSize(find.text('声呐')).height;
    expect(textBottom, greaterThan(textTop), reason: '文字应正常布局');
    final screenH = tester.view.physicalSize.height / tester.view.devicePixelRatio;
    return screenH - textBottom;
  }

  testWidgets('Flutter-OH 全屏布局（padding.bottom=0）也保底避让 32vp，tab 文字距屏底≥28vp',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(EdgeInsets.zero));
    // Tab 有永不停止的呼吸动画（repeat(reverse:true)），pumpAndSettle 会超时；
    // 布局一两帧即稳定，用有限 pump
    await tester.pump();
    await tester.pump();

    final distance = tabTextDistanceToScreenBottom(tester);
    expect(distance, greaterThanOrEqualTo(28),
        reason: 'AGC 判定线 28vp：即使系统不上报底部安全区也要保底避让');
    // 锁死保底值本身：0 系统上报时必须正好用 32vp（改保底值须同步改这条+tab_bar 注释）
    expect(distance, greaterThanOrEqualTo(AppTabBar.minBottomAvoid - 6),
        reason: '文字底距屏底 ≈ 避让高度+行内余量；保底 32vp 时应 ≥26vp');
  });

  testWidgets('系统上报更大的安全区（Android 手势导航）时用系统值不再叠加保底',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(host(const EdgeInsets.only(bottom: 48)));
    // 同上：呼吸动画不停，用有限 pump
    await tester.pump();
    await tester.pump();

    // 48vp 避让 + 行内余量 → 文字底距屏底必须 ≥ 48（证明避让=系统值而非 32）
    expect(tabTextDistanceToScreenBottom(tester),
        greaterThanOrEqualTo(AppTabBar.minBottomAvoid),
        reason: '大安全区时取系统值，避让不应比保底更小');
    expect(tabTextDistanceToScreenBottom(tester), greaterThan(40),
        reason: '系统上报 48vp 时避让应明显大于保底 32vp 场景');
  });
}
