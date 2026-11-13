import 'package:flutter/material.dart';
import '../theme/animations.dart';
import '../theme/colors.dart';
import '../models/message.dart';
import '../services/debug_log.dart';

/// 消息气泡。
///
/// 与设计文档 `docs/superpowers/plans/2026-06-15-ux-revamp.md` P0-4/P0-10 / P2-C 对齐：
/// - 三态状态符号：⌛ sending / ✓ sent / ✓✓ delivered (灰) / ✓✓ read (主色) / ! failed
/// - 配 [Semantics] 描述发送者、内容、时间、状态供屏幕阅读器使用
/// - P2-C：长按触发上下文菜单（复制/引用/举报），由父级 [ChatPage] 弹 `showModalBottomSheet`
/// - F3-2：消息气泡入场动画（Y 轴偏移 + 渐显 + 交错延迟）
class MessageBubble extends StatefulWidget {
  final Message message;
  final double maxWidthFraction;

  /// P2-C：长按消息回调。父级在弹出的 bottom sheet 中处理复制/引用/举报。
  /// 为空时不响应长按，保持向后兼容。
  final void Function(Message message)? onLongPress;

  /// UI 评审 P1（§5-2）：相邻 1 分钟内的消息隐藏时间戳（由列表判定传入），
  /// 消除"20 条消息 20 个时间戳"的视觉噪音。
  final bool showTime;

  /// 列表中的索引，用于计算交错动画延迟
  final int index;

  /// 列表总长度，用于计算交错动画延迟（可选）
  final int? totalCount;

  const MessageBubble({
    super.key,
    required this.message,
    this.maxWidthFraction = 0.7,
    this.onLongPress,
    this.showTime = true,
    this.index = 0,
    this.totalCount,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;
  late Animation<Offset> _offset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppAnimations.messageBubbleEnter,
    );

    // 计算交错延迟：最新的消息（索引最大）延迟最短
    // 假设新消息总是在列表底部，索引最大
    final delayMs = _calculateStaggerDelay();

    if (delayMs > 0) {
      Future.delayed(Duration(milliseconds: delayMs), () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.forward();
    }

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.messageBubbleCurve),
    );

    _offset = Tween<Offset>(
      begin: Offset(0, AppAnimations.messageBubbleOffsetY),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: AppAnimations.messageBubbleCurve),
    );
  }

  /// 计算交错延迟
  ///
  /// 新消息在底部，索引越大（越新）延迟越短，让消息从下往上依次"弹入"
  int _calculateStaggerDelay() {
    // 如果没有提供总数量，按索引计算
    final count = widget.totalCount ?? widget.index + 1;
    // 相对位置：0 = 最旧（顶部），1 = 最新（底部）
    final relativePosition = count <= 1 ? 1.0 : (widget.index / (count - 1));
    // 最新的消息立即显示，最旧的消息延迟 50ms * (count - 1)
    return ((1.0 - relativePosition) * AppAnimations.staggerDelay.inMilliseconds).round();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// 状态符号 + 颜色 + 语义文案。返回 null 表示不渲染（对方消息或异常）。
  ///
  /// 颜色对齐鸿蒙端 MessageBubble.ets：本端气泡是橙色、所有文字都是深色
  /// （bg_base 墨色），对号跟随同一墨色保持配色协调（2026-11-03 用户反馈
  /// 纯白对号破坏"橙底深字"节奏）：
  /// - 发出 ✓：bg_base 半透明（"已发出"低调）
  /// - 已读 ✓✓：bg_base 全透明度 + 加粗——与 sent 的区分靠
  ///   "形态(✓/✓✓)+字重+透明度"三重通道，不再靠换色
  ({String glyph, Color color, String semantic})? _statusVisual() {
    if (!widget.message.isMe) return null;
    // 已读优先（read_receipt 真实存在）
    if (widget.message.isRead) {
      return (
        glyph: '✓✓',
        color: AppColors.bgBase,
        semantic: '对方已读',
      );
    }
    switch (widget.message.sendStatus) {
      case MessageSendStatus.sending:
        return (
          glyph: '⌛',
          color: AppColors.bgBase.withOpacity(0.5),
          semantic: '发送中',
        );
      case MessageSendStatus.sent:
        return (
          glyph: '✓',
          color: AppColors.bgBase.withOpacity(0.55),
          semantic: '已送达服务器',
        );
      case MessageSendStatus.delivered:
        return (
          glyph: '✓✓',
          color: AppColors.bgBase.withOpacity(0.55),
          semantic: '对方已收到',
        );
      case MessageSendStatus.read:
        return (
          glyph: '✓✓',
          color: AppColors.bgBase,
          semantic: '对方已读',
        );
      case MessageSendStatus.failed:
        return (
          glyph: '!',
          color: AppColors.error,
          semantic: '发送失败，点击重试',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMe = widget.message.isMe;
    final screenWidth = MediaQuery.of(context).size.width;
    final maxWidth = screenWidth * widget.maxWidthFraction;
    final status = _statusVisual();
    // 排查已读符号不显示：记录气泡实际收到的消息状态（id 前 13 位 + isRead + sendStatus）
    DebugLog().write(
        '[bubble] id=${widget.message.id.length > 13 ? widget.message.id.substring(0, 13) : widget.message.id}, '
        'isMe=$isMe, isRead=${widget.message.isRead}, status=${widget.message.sendStatus.name}');

    final senderLabel = isMe ? '我' : '对方';
    final timeStr = _formatTime(widget.message.timestamp);
    final semanticLabel = isMe
        ? '$senderLabel 说：${widget.message.content}，$timeStr，${status?.semantic ?? ""}'
        : '$senderLabel 说：${widget.message.content}，$timeStr';

    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _offset,
        child: Semantics(
          label: semanticLabel,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              mainAxisAlignment:
                  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onLongPress: widget.onLongPress == null
                      ? null
                      : () => widget.onLongPress!(widget.message),
                  child: Container(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isMe ? AppColors.primary : AppColors.bgCard,
                      borderRadius: BorderRadius.circular(8),
                      border:
                          isMe ? null : Border.all(color: AppColors.primaryBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.message.content,
                          style: TextStyle(
                            fontSize: 14,
                            color:
                                isMe ? AppColors.bgBase : AppColors.textPrimary,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // UI 评审 P1：相邻 1 分钟内隐藏时间戳。
                        // 2026-11-03 用户反馈"对号不显示"修复：状态符号
                        // （✓/✓✓/!）是发送状态不是时间戳，不再跟随
                        // showTime 隐藏——时间隐藏时仅省略时间文字。
                        if (widget.showTime || status != null)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.showTime)
                                Text(
                                  timeStr,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isMe
                                        ? AppColors.bgBase.withOpacity(0.6)
                                        : AppColors.textMuted,
                                  ),
                                ),
                              if (status != null) ...[
                                if (widget.showTime) const SizedBox(width: 6),
                                ExcludeSemantics(
                                  child: Text(
                                    status.glyph,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: status.color,
                                      fontWeight: widget.message.isRead
                                          ? FontWeight.w700
                                          : null,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                      ],
                    ),
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
