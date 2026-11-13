import 'package:flutter/material.dart';
import '../theme/colors.dart';

/// 《用户协议》与《隐私政策》全文（首启隐私弹窗引用，华为审核要求"政策可正常打开浏览"）。
///
/// 【同源纪律，勿破】网页版 legal/privacy.html、legal/terms.html 由 legal/gen_legal_html.py 从本文件
/// 两个常量生成（部署到 https://www.yiyiguanzhi.cn/noisex/，AGC 自定义隐私政策填这个网址）；
/// 改这里的文字 → 重跑生成器 → test/legal_html_sync_test.dart 逐段比对必须通过 → 再部署网页。
/// 法律主体写真名：处理者/签约方=李龙生，贯一只作括注品牌（工作区 AGENTS.md 本区补充，违者返工）。
///
/// 内容与产品实际数据实践逐条对应（2026-11-06 逐项核过代码与服务器）：
/// - 匿名身份（本地 UUID + 24h JWT），无手机号注册
/// - 位置仅 Geohash-6 网格上传（约 1.2km × 0.6km），精确坐标只在设备端换算
/// - 消息 E2EE（X25519 + AES-256-GCM），服务器只转发密文；「保存的片段」是用户主动提交的明文
/// - 房间/消息 Redis 72h TTL 自动销毁；声呐队列 1h 过期
/// - 长期数据：资料卡/保存的连接/保存的片段/拉黑/举报(手机号 AES-256-GCM)/推送令牌——重置身份全删
/// - 日志：Nginx 访问日志不记查询串（10 天轮转）、journald 30 天上限
class AgreementDocPage extends StatelessWidget {
  final String title;
  final String body;

  const AgreementDocPage({super.key, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        color: AppColors.bgBase,
        child: SafeArea(
          child: Column(
            children: [
              // 顶部导航栏（结构与 ReportPage 头部一致）
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: AppColors.bgCard,
                  border: Border(
                      bottom: BorderSide(color: AppColors.primaryBorder)),
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Icon(Icons.arrow_back,
                          color: AppColors.textPrimary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      title,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _buildParagraphs(body),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 以【】开头的段落为小节：首行（【…】）用标题样式，其余行用正文样式。
  ///
  /// 文字源里小节标题与正文同处一段（只隔单换行），旧版把整段都按标题加粗，
  /// 八条收集清单整块粗体难以阅读（2026-11-06 改）。仍是一段一个 Text 组件，
  /// 网页版生成器 legal/gen_legal_html.py 按同一规则拆「标题 + 正文行」。
  List<Widget> _buildParagraphs(String body) {
    const headingStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.6,
      color: AppColors.textPrimary,
    );
    const bodyStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      height: 1.6,
      color: AppColors.textSecondary,
    );
    final widgets = <Widget>[];
    for (final paragraph in body.split('\n\n')) {
      final text = paragraph.trim();
      if (text.isEmpty) continue;
      final isHeading = text.startsWith('【') && text.contains('】');
      final newline = text.indexOf('\n');
      final headingText =
          !isHeading ? '' : (newline < 0 ? text : text.substring(0, newline));
      final bodyText =
          !isHeading ? text : (newline < 0 ? '' : text.substring(newline + 1));
      widgets.add(Text.rich(TextSpan(children: [
        if (headingText.isNotEmpty)
          TextSpan(
            text: bodyText.isEmpty ? headingText : '$headingText\n',
            style: headingStyle,
          ),
        if (bodyText.isNotEmpty) TextSpan(text: bodyText, style: bodyStyle),
      ])));
      widgets.add(const SizedBox(height: 12));
    }
    if (widgets.isNotEmpty) widgets.removeLast();
    return widgets;
  }
}

/// 《用户协议》全文
const String kUserAgreementText = '''
更新日期：2026年11月6日
生效日期：2026年11月6日

欢迎使用 NoiseX（以下简称"本应用"）。本协议是你与本应用的开发运营者——个人开发者李龙生（品牌名"贯一"，以下简称"我们"）之间关于使用本应用的约定。请你仔细阅读本协议，你点击"同意并继续"即视为已阅读并同意本协议全部内容。我们如何处理你的个人信息，请见《隐私政策》。

【一、服务说明】
本应用是一款基于地理位置与时间的匿名社交应用：你发布一条不超过 140 字的"声呐"，与附近的陌生人随机匹配，建立有效期 72 小时的临时聊天室。本应用需要联网使用；无推荐算法、无用户画像、无声望体系，聊天室到期自动销毁。

【二、匿名身份】
本应用无需手机号或第三方账号注册。首次使用时应用会在设备本地生成一个随机匿名标识用于鉴权，该标识不与你的真实身份关联。你可以随时在设置页「重置身份」，删除当前匿名身份及其关联数据；清除应用数据后，本机的匿名身份也会消失，历史房间随之无法访问。

【三、用户行为规范】
你承诺不发布、不传输法律法规禁止的内容，不骚扰、恐吓、人肉其他用户，不利用本应用从事诈骗等违法活动。你可以对任意聊天房间发起举报，我们将进行审核处理；情节严重的，相关匿名身份将被限制使用。

【四、服务的变更与中断】
因系统维护、升级等原因，本应用可能暂停部分服务。基于产品"反囤积"理念，聊天关系在 72 小时后自然失效属于设计行为，不视为服务中断。

【五、免责声明】
本应用仅提供信息交流渠道，不保证其他用户发布内容的真实性。你与其他用户的线下交往行为属于个人行为，请自行注意人身与财产安全。

【六、协议的更新】
本协议更新后会在应用内显著提示；若你继续使用，视为接受更新后的协议。若你不同意更新内容，可停止使用并清除应用数据。

【七、联系我们】
对本协议或本应用有任何疑问，可通过聊天房间内的举报入口提交反馈，或发送邮件至 guanyi@yiyiguanzhi.cn。
''';

/// 《隐私政策》全文
const String kPrivacyPolicyText = '''
更新日期：2026年11月6日
生效日期：2026年11月6日

NoiseX（以下简称"本应用"）由个人开发者李龙生（品牌名"贯一"）开发运营（以下简称"我们"）。我们深知个人信息对你的重要性。本政策说明我们如何收集、使用、存储、共享与保护你的个人信息，以及你享有的权利，适用于本应用的鸿蒙版与安卓版。你点击"同意并继续"即表示你已阅读并同意我们按本政策处理你的个人信息。

【一、我们收集的信息】
1. 匿名标识（必要）：首次使用时由你的设备随机生成的标识符，用于登录鉴权、识别你的匿名身份。它不含设备指纹，不与你的手机号、姓名等真实身份信息关联。
2. 位置信息（必要）：仅在你发送声呐时以及开启收听期间获取你的精确位置。精确位置只在你的设备上换算为地理网格编码（约 1.2 公里 × 0.6 公里的区域），上传的只有网格编码，精确经纬度不上传、不存储。网格编码用于就近匹配：优先匹配约 1 公里内的用户，无结果时逐步扩展至约 5 公里，最远不超过同城范围（约 20 公里）。之所以需要精确位置：模糊位置的误差可达数公里，无法换算到约 1 公里的网格；若你只允许模糊位置，就近匹配的准确度会下降，可能匹配不到附近的人。关闭收听（静默模式）后，我们停止获取你的位置，你不会收到其他人的声呐，也不会被计入他人看到的附近人数。
3. 你主动发布的内容（必要）：声呐文字（不超过 140 字）与聊天消息。聊天消息经端到端加密（X25519 密钥交换 + AES-256-GCM），服务器只转发和暂存密文，我们无法读取内容。
4. 保存的片段（可选）：房间到期前，你可以主动保存一段文字作为片段，供日后查看。片段由你主动填写提交，以明文形式保存在服务器上，不受端到端加密保护。
5. 资料卡（可选）：你在设置页填写的签名、城市、联系方式，仅在你与对方达成深度交流并解锁后向对方展示。
6. 举报信息（可选）：你发起举报时填写的举报原因（必填）与手机号（选填，用于必要时的法律追溯）。手机号采用 AES-256-GCM 加密存储。
7. 推送令牌（可选）：在你允许通知后，系统推送服务为你的设备生成推送令牌，仅用于在本应用处于后台或离线时向你送达"收到新消息"一类的提醒，提醒内容不含聊天正文。
8. 日志信息（必要）：为保障服务安全、排查故障，服务器会自动记录网络访问日志（访问时间、IP 地址、访问的接口路径，不含登录凭证等请求参数），以及含匿名标识与地理网格编码的服务运行日志。

【二、我们不收集的信息】
我们不收集你的姓名、通讯录、相册、通话记录，不收集设备指纹（如 IMEI 等设备唯一标识），除举报时你自愿填写外不收集手机号；不进行行为分析，不建立用户画像，不做个性化推荐，不接入任何第三方统计或广告 SDK。

【三、第三方服务】
为向你送达消息提醒，本应用使用华为推送服务：鸿蒙版使用系统内置的华为推送服务（Push Kit），安卓版集成华为推送 SDK（HMS Core Push Kit）。提供方为华为软件技术有限公司，用途为送达消息提醒，涉及推送令牌以及推送服务运行所需的应用与设备基础信息，具体以华为推送服务的隐私声明为准。
华为推送 SDK 隐私声明：https://developer.huawei.com/consumer/cn/doc/development/HMSCore-Guides/sdk-data-security-0000001050042177
除此之外，本应用未接入其他会处理你个人信息的第三方服务。

【四、我们申请的权限】
1. 位置（精确位置、模糊位置）：仅在你发送声呐或开启收听时申请，用于就近匹配。拒绝后无法匹配附近的人，其余功能不受影响。
2. 通知：用于接收新消息提醒，在你需要时申请；拒绝后仅影响消息提醒。
3. 网络：用于联网收发消息，并在网络恢复时自动重连。安卓版另含振动与保持唤醒权限，用于新消息提醒振动及推送到达时的短暂处理。
本应用不申请相机、麦克风、通讯录、相册、存储、电话等权限。你可以随时在系统设置中修改或撤销已授予的权限。

【五、信息的使用】
上述信息仅用于：声呐匹配与聊天室建立、消息投递与提醒、附近收听人数统计（只统计数量，不展示身份）、资料卡解锁展示、举报处理与拉黑生效、保障服务安全。我们不将你的信息用于推荐、排序、营销或任何商业化用途。

【六、信息的存储地点与期限】
1. 存储地点：你的信息存储于中华人民共和国境内的服务器（阿里云），不向境外传输。
2. 声呐：完成匹配或约 1 小时无人接收后自动删除。
3. 聊天室与聊天消息（密文）：有效期 72 小时，到期自动销毁，服务器与本地同步清除。
4. 日志信息：最长保存 30 天，到期自动删除。
5. 匿名标识与鉴权凭证：随应用数据存续，清除应用数据或重置身份即删除。
6. 资料卡、已保存的连接、保存的片段、拉黑名单、你提交的举报记录、推送令牌：保存至你重置身份时删除。

【七、信息的共享、委托处理与公开披露】
1. 我们不向任何第三方出售、出租或共享你的个人信息。
2. 消息提醒经华为推送服务送达（见第三条）：我们向推送服务提交的仅有提醒文案与推送令牌，不含聊天内容。
3. 仅在法律法规规定，或司法、行政机关依法定程序要求时，我们才在必要范围内提供相关信息。
4. 我们不会公开披露你的个人信息。

【八、你的权利】
1. 查阅与更正：在设置页的资料卡中查看、修改签名、城市、联系方式。
2. 删除：在设置页点击「重置身份」，将永久删除你的匿名标识、资料卡、已保存的连接、保存的片段、拉黑名单、举报记录与推送令牌，并关闭你进行中的聊天室（对方会收到房间关闭提示）；清除应用数据可删除本地缓存。
3. 撤回同意：在系统设置中关闭位置、通知权限即可撤回相应授权；你也可以重置身份或卸载本应用。撤回同意不影响撤回前基于你的同意已进行的处理。
4. 注销：本应用无需注册账号，「重置身份」即等同于注销；重置后你可以生成新的匿名身份继续使用。
5. 拉黑管理：在设置页的拉黑列表中查看、解除拉黑。
6. 其他请求：如需行使其他权利或有疑问，可通过第十二条的方式联系我们，我们将在 15 个工作日内答复。

【九、信息安全】
我们采取以下措施保护你的信息：客户端与服务器之间全程使用 HTTPS/TLS 加密传输；聊天消息端到端加密；举报手机号加密存储；访问日志不记录登录凭证等请求参数；服务器仅允许密钥登录，数据库与缓存服务不对公网开放。如发生个人信息安全事件，我们将依法及时告知你，并向主管部门报告。

【十、未成年人保护】
本应用面向 18 周岁以上的成年人。若你未满 18 周岁，请勿使用本应用。如我们发现在未获得监护人同意的情况下处理了未成年人的个人信息，将尽快删除相关数据。

【十一、本政策的更新】
本政策发生重大变更时，我们将在应用内以弹窗等显著方式提示你重新阅读并确认，并同步更新网页版本。

【十二、联系我们】
个人信息处理者：李龙生（个人开发者，品牌名"贯一"）
联系邮箱：guanyi@yiyiguanzhi.cn
你也可以通过聊天房间内的举报入口提交反馈。我们将在收到你的请求后 15 个工作日内答复。如你对答复不满意，或认为我们的处理行为损害了你的合法权益，可以向网信、工信等主管部门投诉，或向有管辖权的人民法院提起诉讼。
''';
