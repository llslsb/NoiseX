import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../widgets/sonar_logo.dart';
import 'agreement_doc_page.dart';

/// 首启《用户协议》与《隐私政策》授权门（对齐华为应用市场审核要求）：
/// - 应用首次启动须以显著方式提示阅读协议与政策，征得同意后才能进入应用
/// - 本页位于一切初始化（注册鉴权/网络连接/定位）之前：同意前不采集任何信息
/// - 返回键不可绕过（PopScope 拦截）；不同意则退出应用
/// - 同意后持久化（app.dart 写入 Constants.prefsKeyPrivacyAgreed，版本化键），后续启动不再弹出
class PrivacyAgreementPage extends StatelessWidget {
  final VoidCallback onAgree;
  final VoidCallback onDisagree;

  const PrivacyAgreementPage({
    super.key,
    required this.onAgree,
    required this.onDisagree,
  });

  void _openDoc(BuildContext context, String title, String body) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => AgreementDocPage(title: title, body: body),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: PopScope(
        // 审核要求：协议弹窗不可通过返回手势绕过
        canPop: false,
        child: Container(
          color: AppColors.bgBase,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  // Logo 与标题
                  const SonarLogo(size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    '欢迎使用 NoiseX',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 协议摘要（可滚动，确保小屏完整可读）
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.all(Radius.circular(8)),
                        border: Border.fromBorderSide(
                            BorderSide(color: AppColors.primaryBorder)),
                      ),
                      child: const SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '在使用前，请阅读并了解以下要点：',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.textPrimary),
                            ),
                            SizedBox(height: 12),
                            _Point(
                                text: '匿名使用：无需手机号注册，'
                                    '设备本地生成匿名身份'),
                            _Point(
                                text: '就近匹配：约 1km 优先，'
                                    '最远同城约 20km，精确坐标不上传'),
                            _Point(
                                text: '消息保护：端到端加密，'
                                    '只有你和对方能读取内容'),
                            _Point(
                                text: '自动销毁：聊天室 72 小时后'
                                    '自动过期，消息随之清除'),
                            _Point(
                                text: '反追踪：不收集设备指纹，'
                                    '不做行为分析与用户画像'),
                            SizedBox(height: 12),
                            Text(
                              '点击《用户协议》与《隐私政策》可查看完整内容。'
                              '你发送声呐或接收提醒时，才会向系统申请定位或'
                              '通知权限，并可随时在系统设置中撤销。',
                              style: TextStyle(
                                  fontSize: 12,
                                  height: 1.6,
                                  color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 协议链接行
                  Text.rich(
                    TextSpan(
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                      children: [
                        const TextSpan(text: '我已阅读并同意 '),
                        _docLink(context, '《用户协议》', kUserAgreementText),
                        const TextSpan(text: ' 和 '),
                        _docLink(context, '《隐私政策》', kPrivacyPolicyText),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  // 主操作：同意并继续
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: ElevatedButton(
                      onPressed: onAgree,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.bgBase,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text(
                        '同意并继续',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // 次操作：不同意并退出
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      onPressed: onDisagree,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        side: const BorderSide(color: AppColors.primaryBorder),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      child: const Text('不同意并退出', style: TextStyle(fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  InlineSpan _docLink(
      BuildContext context, String label, String body) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: GestureDetector(
        onTap: () => _openDoc(context, label.replaceAll('《', '').replaceAll('》', ''), body),
        child: Text(
          label,
          style: const TextStyle(
              fontSize: 13, color: AppColors.primary),
        ),
      ),
    );
  }
}

/// 协议摘要条目：橙色圆点 + 文本
class _Point extends StatelessWidget {
  final String text;

  const _Point({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 6),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
