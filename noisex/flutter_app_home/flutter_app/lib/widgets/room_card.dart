import 'package:flutter/material.dart';
import '../theme/colors.dart';
import '../theme/animations.dart';
import '../models/chat_room.dart';
import '../utils/utils.dart';

/// 房间卡片组件（结构逐项对齐鸿蒙端 RoomCard.ets）
///
/// - 头部：signalCode + 🔓/🔒 + ⚠️（临期）| 原始声呐："…"；右侧 💬 + 未读数徽标
/// - 最后消息：`你: …` / `signalCode: …`（带发送者前缀，仅房间有消息时显示）
/// - 时间进度：⚠️ 剩余: X小时Y分钟 + 状态标签（● 可解锁 / ❤️ 已保存 / ● 窗口已关闭）
/// - 进度条：72h 口径，临期红色+脉冲呼吸
/// 旧版缺原始声呐行/未读徽标/发送者前缀/状态标签，倒计时口径也与鸿蒙端不一致。
class RoomCard extends StatefulWidget {
  final ChatRoom room;
  final DateTime? now;
  final VoidCallback onEnter;

  const RoomCard({
    super.key,
    required this.room,
    this.now,
    required this.onEnter,
  });

  @override
  State<RoomCard> createState() => _RoomCardState();
}

/// 必须用 TickerProviderStateMixin（多计时器版），勿改回 SingleTickerProviderStateMixin：
/// 本卡片可同时持有两个动画控制器——入场淡入 + <6h 红色警戒档的呼吸脉冲。
/// 单计时器版只许创建一个，2026-11-06 安卓 debug 真机实锤：剩 3 小时的房间整卡红屏
/// 断言「multiple tickers were created」、点不进房间（release 剥掉断言后静默顶替跟踪）。
class _RoomCardState extends State<RoomCard> with TickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late AnimationController? _expiringPulseController;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.fadeInUp,
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.fadeInUpCurve),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.fadeInUpCurve),
    );
    _controller.forward();

    // 即将过期脉冲动画（鸿蒙端 2s 呼吸周期同款；UI 评审 P0：脉冲只属红色警戒档 <6h）
    if (Utils.isCriticalExpiring(widget.room.expiresAt, widget.now)) {
      _expiringPulseController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 1),
      )..repeat(reverse: true);
    } else {
      _expiringPulseController = null;
    }
  }

  @override
  void didUpdateWidget(RoomCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final isCritical = Utils.isCriticalExpiring(widget.room.expiresAt, widget.now);
    if (isCritical && _expiringPulseController == null) {
      _expiringPulseController = AnimationController(
        vsync: this,
        duration: const Duration(seconds: 1),
      )..repeat(reverse: true);
    } else if (!isCritical && _expiringPulseController != null) {
      _expiringPulseController!.dispose();
      _expiringPulseController = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _expiringPulseController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final now = widget.now ?? DateTime.now();
    final isCritical = Utils.isCriticalExpiring(room.expiresAt, now);
    final unreadCount = room.unreadCount;

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: Transform.translate(
            offset: Offset(0, _isHovered ? -2 : 0),
            child: GestureDetector(
              onTap: widget.onEnter,
              child: AnimatedContainer(
                duration: AppAnimations.normal,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _isHovered ? AppColors.cardBorderHover : AppColors.primaryBorder,
                    width: 1,
                  ),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.1),
                            blurRadius: 20,
                            spreadRadius: 0,
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(room, isCritical, unreadCount),
                    if (room.messages.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildLastMessage(room),
                    ],
                    const SizedBox(height: 8),
                    _buildTimeProgressRow(room, now, isCritical),
                    const SizedBox(height: 4),
                    _buildProgressBar(room, now, isCritical),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 头部：signalCode + 锁 + ⚠️ | 原始声呐；右侧 💬 + 未读徽标
  Widget _buildHeader(ChatRoom room, bool isExpiring, int unreadCount) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      room.signalCode,
                      style: const TextStyle(fontSize: 12, color: AppColors.primary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    room.unlocked ? '🔓' : '🔒',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (isExpiring) ...[
                    const SizedBox(width: 8),
                    const Text('⚠️', style: TextStyle(fontSize: 12)),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '原始声呐: "${room.sonarContent}"',
                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💬', style: TextStyle(fontSize: 14)),
            if (unreadCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                constraints: const BoxConstraints(minWidth: 16),
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$unreadCount',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.bgBase,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 最后消息：`你: …`（本人）/ `对方: …`——房号是系统词汇，不该当人称
  /// 泄漏到预览里（UI 评审 §4-5，鸿蒙端 RoomCard.ets 同步改）
  Widget _buildLastMessage(ChatRoom room) {
    final last = room.messages.last;
    final sender = last.sender == 'me' ? '你' : '对方';
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$sender: ',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          TextSpan(
            text: last.content,
            style: const TextStyle(color: Color(0xFFE8E8EA)),
          ),
        ],
      ),
      style: const TextStyle(fontSize: 14),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 时间进度行：剩余时间（三档色）+ 状态标签（鸿蒙端三种标签逐项对齐）
  Widget _buildTimeProgressRow(ChatRoom room, DateTime now, bool isCritical) {
    final windowClosed = !room.unlocked &&
        !room.deepConnectionAchieved &&
        room.unlockWindowRemaining <= Duration.zero;
    final tierColor = Utils.expiryTierColor(room.expiresAt, now);

    return Row(
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                if (isCritical) const TextSpan(text: '⚠️ '),
                TextSpan(text: '剩余: ${Utils.formatTimeRemainingCN(room.expiresAt, now)}'),
              ],
            ),
            style: TextStyle(
              fontSize: 12,
              color: tierColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (room.deepConnectionAchieved && !room.unlocked) ...[
          const SizedBox(width: 8),
          const Text('● 可解锁',
              style: TextStyle(fontSize: 10, color: AppColors.primary)),
        ] else if (room.bothSaveConfirmed) ...[
          const SizedBox(width: 8),
          const Text('❤️ 已保存',
              style: TextStyle(fontSize: 10, color: AppColors.primary)),
        ] else if (windowClosed) ...[
          const SizedBox(width: 8),
          const Text('● 窗口已关闭',
              style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ],
    );
  }

  /// 进度条：72h 口径 + 三档色，<6h 红色+脉冲呼吸（鸿蒙端 expiringPulse 同款）
  Widget _buildProgressBar(ChatRoom room, DateTime now, bool isCritical) {
    final progressColor = Utils.expiryTierColor(room.expiresAt, now);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: _expiringPulseController != null
          ? AnimatedBuilder(
              animation: _expiringPulseController!,
              builder: (context, child) {
                // 鸿蒙端 expiringPulse：透明度 1→0.5→1 呼吸（2s 周期）
                return Opacity(
                  opacity: 0.5 + 0.5 * _expiringPulseController!.value,
                  child: LinearProgressIndicator(
                    value: Utils.getExpiryProgress(room.expiresAt, now: now),
                    backgroundColor: AppColors.bgMuted,
                    valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                    minHeight: 4,
                  ),
                );
              },
            )
          : LinearProgressIndicator(
              value: Utils.getExpiryProgress(room.expiresAt, now: now),
              backgroundColor: AppColors.bgMuted,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
              minHeight: 4,
            ),
    );
  }
}
