import 'package:flutter/material.dart';
import '../services/haptic_service.dart';
import '../theme/animations.dart';
import '../theme/colors.dart';

/// 底部 TabBar。
///
/// 与设计文档对齐：
/// - P0-10：适配底部安全区，避免角标被系统手势条遮挡；
///   切 Tab 时触发 [HapticFeedback.selectionClick]；每个 tab 加 [Semantics] 标签。
/// - F3-1（2026-06-16-ux-feedback-and-immersive-tab-design）：统一深色平面风格 —
///   移除玻璃效果以提升低端设备性能，同时与产品"无线电静默"气质契合；
///   顶部 0.5px 高光分隔（白色 10% 透明）与 HarmonyOS 端对齐。
/// - AGC UX 自检修复（2026-11-08，勿回退）：EntryAbility 是全屏布局
///   （setWindowLayoutFullScreen），Flutter-OH 引擎上报的 padding.bottom 常为 0，
///   旧实现只包 SafeArea → 三台真机 tab 文字距屏底仅 ~10vp（AGC 四条「<28vp」同因）。
///   对齐鸿蒙原生端 Index.refreshAvoidAreas：避让高度 = max(系统上报, 保底 32vp)，
///   TabBar 深色底自然延伸到导航条后面（背景色与窗口底一致，无割裂）。
class AppTabBar extends StatelessWidget {
  /// 底部导航条保底避让高度（vp）。
  ///
  /// 与鸿蒙原生端 bottomAvoidHeight 保底值一致（32 = indicator 高 + 余量的兜底）；
  /// AGC 判定线是控件底边距屏底 ≥28vp，32 留出余量。勿降回 28 以下。
  static const double minBottomAvoid = 32;

  final String activeTab;
  final ValueChanged<String> onTabChanged;
  final int receiverCount;
  final int roomCount;

  const AppTabBar({
    super.key,
    required this.activeTab,
    required this.onTabChanged,
    this.receiverCount = 0,
    this.roomCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    // 避让高度：优先用系统上报的安全区（Android 真机/手势导航下是真导航条高度，
    // 三键导航下更高）；Flutter-OH 全屏布局下常为 0，此时用保底值。
    final systemBottom = MediaQuery.of(context).padding.bottom;
    final bottomAvoid =
        systemBottom > minBottomAvoid ? systemBottom : minBottomAvoid;
    return Container(
      width: double.infinity,
      // 深色底延伸到导航条后面（沉浸式背景），内容区再让出避让高度
      color: AppColors.bgBase,
      padding: EdgeInsets.only(bottom: bottomAvoid),
      child: Container(
        height: 64,
        decoration: const BoxDecoration(
          // 对齐鸿蒙端 TabBar：bg_base + 顶部 0.5px 白色 10% 高光
          color: AppColors.bgBase,
          border: Border(
            top: BorderSide(
              color: AppColors.tabBarTopHighlight,
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: [
            _TabItem(
              icon: '📡',
              label: '声呐',
              isActive: activeTab == 'sonar',
              onTap: () {
                HapticService.instance.selection();
                onTabChanged('sonar');
              },
            ),
            _TabItem(
              icon: '🎤',
              label: '接收器',
              isActive: activeTab == 'receiver',
              badge: receiverCount,
              onTap: () {
                HapticService.instance.selection();
                onTabChanged('receiver');
              },
            ),
            _TabItem(
              icon: '⏳',
              label: '沙漏',
              isActive: activeTab == 'hourglass',
              badge: roomCount,
              onTap: () {
                HapticService.instance.selection();
                onTabChanged('hourglass');
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TabItem extends StatefulWidget {
  final String icon;
  final String label;
  final bool isActive;
  final int badge;
  final VoidCallback onTap;

  const _TabItem({
    required this.icon,
    required this.label,
    required this.isActive,
    this.badge = 0,
    required this.onTap,
  });

  @override
  State<_TabItem> createState() => _TabItemState();
}

class _TabItemState extends State<_TabItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseOpacity;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: AppAnimations.pulse,
    )..repeat(reverse: true);
    _pulseOpacity = Tween<double>(
      begin: AppAnimations.pulseMaxOpacity,
      end: AppAnimations.pulseMinOpacity,
    ).animate(
      CurvedAnimation(parent: _pulseController, curve: AppAnimations.pulseCurve),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final semantic = widget.badge > 0
        ? '${widget.label}，${widget.badge} 项未读'
        : widget.label;
    return Expanded(
      child: Semantics(
        button: true,
        selected: widget.isActive,
        label: semantic,
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            // 居中对齐：宽屏（折叠机内屏）下每格很宽，Stack 默认 topLeft
            // 会把图标+文字挤到格子左侧（Mate X7 联调实锤）
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 角标锚定图标右上角（锚定整格会在宽屏下漂移到格边缘）
                Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseOpacity,
                      builder: (context, child) {
                        return Opacity(
                          opacity:
                              widget.isActive ? _pulseOpacity.value : 1.0,
                          child: ExcludeSemantics(
                            child: Text(
                              widget.icon,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                        );
                      },
                    ),
                    if (widget.badge > 0)
                      Positioned(
                        top: -6,
                        right: -10,
                        child: Container(
                          // 对齐鸿蒙端：16×16 圆形徽章
                          width: 16,
                          height: 16,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: ExcludeSemantics(
                              child: Text(
                                '${widget.badge}',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.bgBase,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  style: TextStyle(
                    // 对齐鸿蒙端：11px，未选中 text_secondary
                    fontSize: 11,
                    color: widget.isActive
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
