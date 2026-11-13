import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/animations.dart';
import '../services/haptic_service.dart';
import '../services/sound_service.dart';

/// Onboarding 引导页（4 屏）
///
/// 与设计文档 P1-E 对齐：
/// - 第 1 屏：产品理念（无算法、无推荐、无排序）
/// - 第 2 屏：声呐原理（随机 + 地理邻近）
/// - 第 3 屏：隐私保护（72h 自动过期、匿名认证、E2EE）
/// - 第 4 屏：权限说明（如实告知「开始使用」后会申请的两项权限、用途与拒绝影响；
///   不在此申请、不设门槛——权限弹窗必须发生在用户同意隐私政策之后且对应用途触发时，
///   任何"勾选即授权"的本地开关既无实际作用也不符合华为审核要求）
///
/// 文案口径必须与真实弹框时机、隐私政策【四、我们申请的权限】一致（2026-11-07，勿回退）：
/// 收听默认开启 → 进入首页即申请定位（app.dart 初始化）；推送默认开启 → 进入首页即申请通知
/// （PushService.init）。旧文案「不会在启动时申请任何权限 / 发送声呐时才申请定位」与此不符，
/// 审核会核对说明与弹框时机；第 2 屏同理只说「聊天记录」销毁——保存的片段与连接不随房间销毁。
class OnboardingPage extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingPage({super.key, required this.onComplete});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _currentPage = 0;
  late PageController _pageController;

  static const List<_OnboardingSlide> _slides = [
    _OnboardingSlide(
      icon: Icons.block,
      title: '无算法推荐',
      description: '没有智能推荐，没有排序算法，\n没有用户画像，没有历史记录。\n\n纯粹的随机与地理邻近。',
      keyword: '反算法',
    ),
    _OnboardingSlide(
      icon: Icons.radar,
      title: '声呐匹配',
      description: '点击发送声呐脉冲，发现附近陌生人。\n\n匹配后自动建立 72 小时临时聊天室，\n房间过期后聊天记录自动销毁。',
      keyword: '随机',
    ),
    _OnboardingSlide(
      icon: Icons.security,
      title: '隐私优先',
      description: '房间创建 72 小时后自动过期。\n匿名认证，无需注册账号。\n\n端到端加密，只有你和对方能读取消息。',
      keyword: '自动过期',
    ),
    _OnboardingSlide(
      icon: Icons.verified_user,
      title: '需要两项权限',
      description: '开始使用后，会向系统申请：\n\n• 通知：新消息提醒\n• 定位：匹配附近的声呐\n（收听默认开启，关闭即停止获取位置）\n\n拒绝通知只影响提醒，拒绝定位将无法匹配附近的人。\n可随时在系统设置中修改或撤销。',
      keyword: '可随时撤销',
    ),
  ];

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    HapticService.instance.light();
    if (_currentPage < _slides.length - 1) {
      _pageController.animateToPage(
        _currentPage + 1,
        duration: AppAnimations.pageTransition,
        curve: AppAnimations.pageTransitionCurve,
      );
    } else {
      _completeOnboarding();
    }
  }

  void _skip() {
    HapticService.instance.light();
    _completeOnboarding();
  }

  void _completeOnboarding() {
    SoundService.instance.playDeepConfirm();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    // Material 透明祖先：消除 debug 模式无 Material 祖先的黄色双下划线告警
    return Material(
      type: MaterialType.transparency,
      child: Container(
      color: AppColors.bgBase,
      child: SafeArea(
        child: Column(
          children: [
            // 顶部跳过按钮
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _skip,
                    child: const Text(
                      '跳过',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
            // PageView 内容
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemCount: _slides.length,
                itemBuilder: (context, index) {
                  final slide = _slides[index];
                  return _buildSlide(slide, index);
                },
              ),
            ),
            // 底部导航
            _buildBottomNav(),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildSlide(_OnboardingSlide slide, int index) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      // B14：小屏真机上第 4 屏（含两个权限按钮）会溢出 ~189px。
      // 改为"可滚动 + 最小高度撑满"：内容放得下时仍垂直居中，放不下时可滚动。
      child: LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // 图标
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.primary.withOpacity(0.15),
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                    child: Icon(slide.icon, size: 56, color: AppColors.primary),
                  ),
                  const SizedBox(height: 40),
                  // 标题
                  Text(
                    slide.title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 关键词标签
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.primary, width: 1),
                    ),
                    child: Text(
                      slide.keyword,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.primary,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // 描述
                  Text(
                    slide.description,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBottomNav() {
    final isLastPage = _currentPage == _slides.length - 1;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          // 页面指示器
          Expanded(
            child: Row(
              children: List.generate(_slides.length, (index) {
                final isActive = index == _currentPage;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(right: index < _slides.length - 1 ? 8 : 0),
                    height: 4,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.primary
                          : AppColors.bgMuted,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(width: 16),
          // 下一步/完成按钮
          ElevatedButton(
            onPressed: _nextPage,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.bgBase,
              disabledBackgroundColor: AppColors.bgMuted,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              isLastPage ? '开始使用' : '下一步',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingSlide {
  final IconData icon;
  final String title;
  final String description;
  final String keyword;

  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.description,
    required this.keyword,
  });
}
