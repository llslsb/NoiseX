import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noisex/pages/agreement_doc_page.dart';
import 'package:noisex/pages/onboarding_page.dart';
import 'package:noisex/pages/privacy_agreement_page.dart';

void main() {
  group('PrivacyAgreementPage', () {
    testWidgets('同意按钮触发 onAgree，不同意按钮触发 onDisagree', (tester) async {
      var agreed = false;
      var disagreed = false;
      await tester.pumpWidget(MaterialApp(
        home: PrivacyAgreementPage(
          onAgree: () => agreed = true,
          onDisagree: () => disagreed = true,
        ),
      ));

      await tester.tap(find.text('同意并继续'));
      await tester.tap(find.text('不同意并退出'));
      await tester.pump();

      expect(agreed, isTrue);
      expect(disagreed, isTrue);
    });

    testWidgets('《用户协议》《隐私政策》可打开全文页（审核要求政策可正常浏览）',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PrivacyAgreementPage(onAgree: () {}, onDisagree: () {}),
      ));

      await tester.tap(find.text('《用户协议》'));
      await tester.pumpAndSettle();
      expect(find.byType(AgreementDocPage), findsOneWidget);
      expect(find.textContaining('服务说明'), findsOneWidget);

      // 自绘返回箭头（GestureDetector + arrow_back 图标）
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      await tester.tap(find.text('《隐私政策》'));
      await tester.pumpAndSettle();
      expect(find.textContaining('我们收集的信息'), findsOneWidget);
    });

    testWidgets('返回手势不可绕过授权门（PopScope canPop=false）', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: PrivacyAgreementPage(onAgree: () {}, onDisagree: () {}),
      ));

      // 模拟系统返回：canPop=false 时路由不会被弹出
      await tester.binding.handlePopRoute();
      await tester.pump();

      expect(find.byType(PrivacyAgreementPage), findsOneWidget);
    });
  });

  group('OnboardingPage', () {
    testWidgets('末屏"开始使用"不再被假权限勾选拦截', (tester) async {
      var completed = false;
      await tester.pumpWidget(MaterialApp(
        home: OnboardingPage(onComplete: () => completed = true),
      ));

      // 滑到最后一屏（4 屏，向左滑 3 次）
      for (var i = 0; i < 3; i++) {
        await tester.drag(find.byType(PageView), const Offset(-600, 0));
        await tester.pumpAndSettle();
      }
      expect(find.text('需要两项权限'), findsOneWidget);

      await tester.tap(find.text('开始使用'));
      await tester.pump();

      expect(completed, isTrue);
    });

    // 2026-11-07：引导页说法必须与真实弹框时机、隐私政策【四、我们申请的权限】一致——
    // 收听默认开启→进首页即申请定位，推送默认开启→进首页即申请通知。
    // 旧文案「不会在启动时申请任何权限」与实际不符（华为审核会核对说明与弹框时机），勿回退。
    testWidgets('末屏如实告知通知与定位两项权限，小屏 360×640 不溢出', (tester) async {
      tester.view.physicalSize = const Size(720, 1280);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: OnboardingPage(onComplete: () {}),
      ));

      // 逐屏检查：任何一屏都不许再出现与实际不符的旧说法
      bool textHas(String s) => find
          .byWidgetPredicate((w) => w is Text && (w.data ?? '').contains(s))
          .evaluate()
          .isNotEmpty;
      for (var i = 0; i < 4; i++) {
        expect(textHas('不会在启动时'), isFalse, reason: '第 ${i + 1} 屏');
        expect(textHas('所有数据'), isFalse, reason: '第 ${i + 1} 屏');
        if (i < 3) {
          await tester.drag(find.byType(PageView), const Offset(-600, 0));
          await tester.pumpAndSettle();
        }
      }

      // 末屏说明：同一段里讲清通知、定位，以及收听默认开启这个申请定位的原因
      final permissionText = find.byWidgetPredicate((w) =>
          w is Text &&
          (w.data ?? '').contains('通知') &&
          (w.data ?? '').contains('定位') &&
          (w.data ?? '').contains('收听默认开启'));
      expect(permissionText, findsOneWidget);
      // 布局溢出会以异常形式抛出，此处必须为空
      expect(tester.takeException(), isNull);
    });
  });
}
