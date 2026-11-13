import 'dart:async';

import 'package:flutter/material.dart';
import '../services/haptic_service.dart';
import '../theme/colors.dart';
import '../models/sonar.dart';
import '../widgets/pull_refresh.dart';
import '../widgets/sonar_card.dart';
import '../widgets/sonar_logo.dart';
import '../widgets/harmony_feedback.dart';

/// 接收器页：列出收到的声呐。
///
/// 与鸿蒙端 ReceiverPage.ets 行为对齐（AGENTS 红线：不允许单端发明交互）：
/// - 单条忽略（左滑）直接执行，无撤销窗口、无提示；
///   UI 评审 P1（§3-1）：卡片上不再放"忽略"按钮——手势为主路径，
///   卡片只保留"响应"唯一主 CTA（双端同步）；
/// - 顶栏【全部响应】【全部忽略】带二次确认对话框（鸿蒙深色风格）；
///   批量忽略执行后提示"已忽略 N 条声呐"。
class ReceiverPage extends StatefulWidget {
  final List<Sonar> sonars;
  final void Function(Sonar) onAccept;

  /// 真正执行"忽略"——上层应在此调用 API 并把卡片从持久状态删除。
  final void Function(String sonarId) onIgnore;

  /// 下拉刷新（对齐鸿蒙端 PullRefresh.ets）：重拉收到的声呐列表。
  final Future<void> Function() onRefresh;

  /// UI 评审 P1（§3-4）：空态行动出口——跳回声呐页。
  final VoidCallback? onGoToSonar;

  final double statusBarHeight;

  const ReceiverPage({
    super.key,
    required this.sonars,
    required this.onAccept,
    required this.onIgnore,
    required this.onRefresh,
    this.onGoToSonar,
    this.statusBarHeight = 0,
  });

  @override
  State<ReceiverPage> createState() => _ReceiverPageState();
}

class _ReceiverPageState extends State<ReceiverPage> {
  // ========== 单条忽略（左滑） ==========

  void _handleIgnoreSwipe(Sonar sonar) {
    HapticService.instance.selection();
    widget.onIgnore(sonar.id);
  }

  // ========== 批量决策 ==========

  Future<bool> _confirmBatch({
    required String title,
    required String message,
    required String confirmLabel,
    bool danger = false,
  }) async {
    return showHarmonyConfirmDialog(
      context,
      title: title,
      message: message,
      confirmText: confirmLabel,
      cancelText: '取消',
      danger: danger,
    );
  }

  Future<void> _handleAcceptAll(List<Sonar> visible) async {
    if (visible.isEmpty) return;
    final ok = await _confirmBatch(
      title: '全部响应',
      message: '将依次响应当前 ${visible.length} 个声呐信号，并创建临时对话房间。',
      confirmLabel: '全部响应',
    );
    if (!ok || !mounted) return;
    HapticService.instance.heavy();
    // 一次性快照避免在迭代中被父端 setState 修改
    final snapshot = List<Sonar>.from(visible);
    for (final s in snapshot) {
      widget.onAccept(s);
    }
  }

  Future<void> _handleIgnoreAll(List<Sonar> visible) async {
    if (visible.isEmpty) return;
    final ok = await _confirmBatch(
      title: '全部忽略',
      message: '将忽略当前 ${visible.length} 个声呐信号。',
      confirmLabel: '全部忽略',
      danger: true,
    );
    if (!ok || !mounted) return;
    HapticService.instance.medium();
    final snapshot = List<Sonar>.from(visible);
    for (final s in snapshot) {
      widget.onIgnore(s.id);
    }
    if (!mounted) return;
    unawaited(showHarmonyToast(context, '已忽略 ${snapshot.length} 条声呐'));
  }

  @override
  Widget build(BuildContext context) {
    final sonars = widget.sonars;
    final showBatchActions = sonars.length >= 2;

    return Container(
      color: AppColors.bgBase,
      child: Padding(
        padding: EdgeInsets.only(top: widget.statusBarHeight),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: AppColors.headerBarBg,
                border: Border(bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // 对齐鸿蒙端：ohos_mic 符号 → Material 麦克风图标 18px
                      const Icon(Icons.mic, size: 18, color: AppColors.primary),
                      const SizedBox(width: 8),
                      const Text(
                        '接收器',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const Spacer(),
                      // 批量动作按钮：仅当可见 ≥2 条时显示
                      if (showBatchActions) ...[
                        _BatchActionButton(
                          label: '全部响应',
                          color: AppColors.primary,
                          onTap: () => _handleAcceptAll(sonars),
                        ),
                        const SizedBox(width: 8),
                        // 对齐鸿蒙端：忽略按钮描边为 #9CA3AF66（与文字色 textSecondary 不同源）
                        _BatchActionButton(
                          label: '全部忽略',
                          color: AppColors.textSecondary,
                          borderColor: const Color(0x669CA3AF),
                          onTap: () => _handleIgnoreAll(sonars),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '> ${sonars.length} 个信号等待响应  ·  右滑响应 / 左滑忽略',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            Expanded(
              child: sonars.isEmpty
                  ? SizedBox(
                      height: 256,
                        child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 对齐鸿蒙端：声呐 Logo 64px + 0.2 透明度
                            //（emoji 位图字模放大发糊，改打包高清资源）
                            Opacity(
                              opacity: 0.2,
                              child: const SonarLogo(size: 64),
                            ),
                            const SizedBox(height: 16),
                            // UI 评审 P1（§3-4）：空态标题+副标题去重，
                            // 并给"现在能做什么"的行动出口
                            const Text(
                              '暂无收到的声呐信号',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.textSecondary),
                            ),
                            const SizedBox(height: 12),
                            if (widget.onGoToSonar != null)
                              GestureDetector(
                                onTap: widget.onGoToSonar,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                        color: AppColors.primaryBorder),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: const Text(
                                    '去声呐页发一个脉冲',
                                    style: TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primary),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    )
                  : PullRefresh(
                      onRefresh: widget.onRefresh,
                      child: ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: sonars.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final sonar = sonars[index];
                          // Dismissible 包裹：
                          // - 右滑 → 接受；左滑 → 忽略
                          // 忽略/接受均直接执行；卡片"消失"由父端移除 sonar 触发
                          return Dismissible(
                            key: ValueKey('sonar-${sonar.id}'),
                            background: const _SwipeBackground(
                              color: AppColors.primary,
                              icon: Icons.check_circle_outline,
                              label: '响应',
                              alignment: Alignment.centerLeft,
                            ),
                            secondaryBackground: const _SwipeBackground(
                              color: AppColors.bgMuted,
                              icon: Icons.close,
                              label: '忽略',
                              alignment: Alignment.centerRight,
                            ),
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.startToEnd) {
                                // 接受不需要二次确认，直接触发；返回 false 让卡片回弹，
                                // 真正的"卡片消失"由父端 onAccept → 移除 sonar 触发
                                HapticService.instance.medium();
                                widget.onAccept(sonar);
                                return false;
                              } else {
                                _handleIgnoreSwipe(sonar);
                                // 返回 false 让 Dismissible 不真正销毁
                                return false;
                              }
                            },
                            child: SonarCard(
                              sonar: sonar,
                              onAccept: () {
                                HapticService.instance.medium();
                                widget.onAccept(sonar);
                              },
                            ),
                          );
                        },
                      ),
                    ),
            ),
            // 底部提示（对齐鸿蒙端：仅列表非空时显示，12px textSecondary，
            // bgCard 50% 底 + divider 顶线）
            if (sonars.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.bgCard.withOpacity(0.5),
                  border: const Border(
                      top: BorderSide(color: AppColors.divider)),
                ),
                child: const Text(
                  '响应后将创建临时对话房间（72小时有效期）',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 顶栏批量动作按钮（小巧、可点）。
class _BatchActionButton extends StatelessWidget {
  final String label;
  final Color color;

  /// 描边色；缺省按主色 40% 透明（对齐鸿蒙端 #FF6B3566）
  final Color? borderColor;
  final VoidCallback onTap;

  const _BatchActionButton({
    required this.label,
    required this.color,
    required this.onTap,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(
              color: borderColor ?? color.withOpacity(0.4),
              width: 1,
            ),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// 滑动背景：左/右两侧的颜色块和图标。
class _SwipeBackground extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final Alignment alignment;

  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  @override
  Widget build(BuildContext context) {
    final isStart = alignment == Alignment.centerLeft;
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.18),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      alignment: alignment,
      child: Row(
        mainAxisAlignment:
            isStart ? MainAxisAlignment.start : MainAxisAlignment.end,
        children: [
          if (isStart) Icon(icon, color: color),
          if (isStart) const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          if (!isStart) const SizedBox(width: 8),
          if (!isStart) Icon(icon, color: color),
        ],
      ),
    );
  }
}
