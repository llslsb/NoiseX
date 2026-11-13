import 'dart:math';

import '../../models/constants.dart';
import 'package:flutter/material.dart';
import '../../models/chat_room.dart';
import '../../models/message.dart';
import '../../theme/colors.dart';
import '../../widgets/message_bubble.dart';
import '../../widgets/typing_indicator.dart';

/// 聊天消息列表组件
///
/// 负责渲染：
/// - 房间过期倒计时（顶部）
/// - 声呐触发消息（首条消息前）
/// - 消息气泡列表（带入场动画）
/// - 对方正在输入指示器
///
/// 从 `chat_page.dart` 拆分出的独立组件，约 150 行。
class ChatMessageList extends StatefulWidget {
  final ChatRoom room;
  final void Function(Message message)? onMessageLongPress;
  final ScrollController scrollController;
  final bool peerIsTyping;

  const ChatMessageList({
    super.key,
    required this.room,
    required this.scrollController,
    this.onMessageLongPress,
    this.peerIsTyping = false,
  });

  @override
  State<ChatMessageList> createState() => _ChatMessageListState();
}

class _ChatMessageListState extends State<ChatMessageList> {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: widget.scrollController,
      reverse: false,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: widget.room.messages.length + 3, // +1 声呐头 +1 typing +1 进度指示器
      itemBuilder: (context, index) {
        // 第 0 项：触发声呐（房间倒计时已上移到 ChatHeaderBar 第二行，
        // 对齐鸿蒙端 ChatPage——列表内不再重复渲染）
        if (index == 0) {
          return _buildSonarTrigger();
        }
        // ========== TASK-002: 第 1 项：深度交流进度指示器 ==========
        if (index == 1) {
          if (!widget.room.deepConnectionAchieved) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: _buildDeepConnectionProgress(),
            );
          }
          return const SizedBox.shrink();
        }
        // 最后一项：对方正在输入指示器
        if (index == widget.room.messages.length + 2) {
          return widget.peerIsTyping
              ? Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8, left: 16),
                  child: TypingIndicator(peerSignalCode: widget.room.signalCode),
                )
              : const SizedBox.shrink();
        }
        // 真正的消息（index=2 开始，减去前 2 个固定项；已达成时指示器槽位
        // 仍占 index 1，故两种状态统一 index-2——旧版 achieved 分支 index-1
        // 会跳过首条消息，一并修正）
        final msgIndex = index - 2;
        if (msgIndex < 0 || msgIndex >= widget.room.messages.length) {
          return const SizedBox.shrink();
        }
        final msg = widget.room.messages[msgIndex];
        final prev = msgIndex > 0 ? widget.room.messages[msgIndex - 1] : null;

        // UI 评审 P1（§5-2）：跨天插日期分隔条；相邻 1 分钟内隐藏时间戳
        final children = <Widget>[];
        final separator = _buildDateSeparatorIfNeeded(msg, prev);
        if (separator != null) children.add(separator);
        children.add(MessageBubble(
          message: msg,
          onLongPress: widget.onMessageLongPress,
          showTime: _shouldShowTime(msg, prev),
          index: index - 1,
          totalCount: widget.room.messages.length,
        ));
        return Column(children: children);
      },
    );
  }

  /// 跨天（或首条）时渲染日期分隔条，如"11月3日"。
  Widget? _buildDateSeparatorIfNeeded(Message msg, Message? prev) {
    if (prev != null && _sameDay(prev.timestamp, msg.timestamp)) return null;
    final t = msg.timestamp;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.bgMuted,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${t.month}月${t.day}日',
            style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ),
      ),
    );
  }

  /// 相邻消息 1 分钟内且同天且**同一发送者** → 隐藏时间戳
  /// （首条始终显示）。2026-11-03 补同发送者条件：对方秒回我时，
  /// 我方消息不应被吞掉时间戳（会连带吞掉发送状态对号）。
  bool _shouldShowTime(Message msg, Message? prev) {
    if (prev == null) return true;
    if (!_sameDay(prev.timestamp, msg.timestamp)) return true;
    if (prev.isMe != msg.isMe) return true;
    return msg.timestamp.difference(prev.timestamp).inMinutes.abs() >= 1;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// 触发声呐提示
  Widget _buildSonarTrigger() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bgCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primaryBorder),
        ),
        child: Column(
          children: [
            const Text('触发声呐:',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            Text('"${widget.room.sonarContent}"',
                style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
          ],
        ),
      ),
    );
  }

  /// ========== TASK-002: 深度交流进度指示器 ==========
  /// 与鸿蒙端 ChatPage.ets DeepConnectionProgressBuilder 视觉对齐
  Widget _buildDeepConnectionProgress() {
    final progress = widget.room.deepConnectionProgress;
    final current = widget.room.totalMessageCount;
    final threshold = Constants.deepConnectionThreshold;

    return Center(
      // 与鸿蒙端 ChatPage.ets DeepConnectionProgressBuilder 对齐：外层上下 16 padding
      child: Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 16),
        child: Column(
        children: [
          // 环形进度条
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 背景环
                CircularProgressIndicator(
                  value: 1.0,
                  strokeWidth: 3,
                  color: AppColors.bgMuted,
                ),
                // 进度环
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  color: AppColors.primary,
                  backgroundColor: Colors.transparent,
                ),
                // 中心数字（min 防止超过阈值显示 21/20）
                Center(
                  child: Text(
                    '${min(current, threshold)}/$threshold',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 提示文案
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              widget.room.deepConnectionHint,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
            ),
          ),
        ],
        ),
      ),
    );
  }
}
