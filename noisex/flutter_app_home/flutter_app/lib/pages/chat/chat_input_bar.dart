import 'dart:async';
import 'package:flutter/material.dart';
import '../../models/chat_room.dart';
import '../../models/message.dart';
import '../../services/haptic_service.dart';
import '../../services/offline_queue.dart';
import '../../services/sound_service.dart';
import '../../theme/colors.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/tab_bar.dart';

/// 聊天输入栏组件
///
/// 负责渲染：
/// - 引用消息预览条
/// - 文本输入框
/// - 发送按钮
/// - 深度交流进度提示
///
/// 从 `chat_page.dart` 拆分出的独立组件，约 250 行。
class ChatInputBar extends StatefulWidget {
  final ChatRoom room;
  final TextEditingController inputController;
  final Message? quotedMessage;
  final void Function(String) onSendMessage;
  final VoidCallback onQuoteClear;
  final void Function(String) onTypingChange;

  const ChatInputBar({
    super.key,
    required this.room,
    required this.inputController,
    required this.onSendMessage,
    this.quotedMessage,
    required this.onQuoteClear,
    required this.onTypingChange,
  });

  @override
  State<ChatInputBar> createState() => _ChatInputBarState();
}

class _ChatInputBarState extends State<ChatInputBar> {
  final FocusNode _focusNode = FocusNode();
  StreamSubscription<bool>? _offlineSubscription;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    // 监听离线状态
    _offlineSubscription = OfflineQueue().offlineStateStream.listen((offline) {
      if (mounted) setState(() => _isOffline = offline);
    });
    // 获取初始状态
    _isOffline = OfflineQueue().isOffline;
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _offlineSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    // 底部避让（AGC UX 自检修复 2026-11-08，勿回退）：键盘弹出时只让键盘高度；
    // 键盘收起时输入栏贴屏底，要让出系统导航条——与 AppTabBar 同一保底值
    //（Flutter-OH 全屏布局下 padding.bottom 常为 0，只信系统上报会贴底）。
    final systemBottom = MediaQuery.paddingOf(context).bottom;
    final navAvoid = systemBottom > AppTabBar.minBottomAvoid
        ? systemBottom
        : AppTabBar.minBottomAvoid;
    final bottomPadding = bottomInset > 0 ? bottomInset : navAvoid;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: GlassContainer(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        borderRadius: 0,
        child: Column(
          children: [
            // 引用预览条
            if (widget.quotedMessage != null) _buildQuotePreview(widget.quotedMessage!),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.inputController,
                    focusNode: _focusNode,
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    cursorColor: AppColors.primary,
                    decoration: InputDecoration(
                      hintText: _isOffline ? '网络已断开，正在重连...' : '输入消息...',
                      hintStyle: TextStyle(
                        color: _isOffline ? AppColors.error : AppColors.textMuted,
                      ),
                      filled: true,
                      fillColor: AppColors.bgCard,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(21),
                        borderSide: _isOffline
                            ? const BorderSide(color: AppColors.error, width: 1)
                            : const BorderSide(
                                color: AppColors.primaryBorder, width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(21),
                        borderSide: _isOffline
                            ? const BorderSide(color: AppColors.error, width: 1)
                            : const BorderSide(
                                color: AppColors.primaryBorder, width: 1),
                      ),
                    ),
                    maxLines: null,
                    textInputAction: TextInputAction.send,
                    onChanged: widget.onTypingChange,
                    onSubmitted: (_) => _handleSend(),
                  ),
                ),
                const SizedBox(width: 10),
                // 圆形发送按钮：实心主色圆底 + 底色箭头，与输入胶囊等高成组；
                // 替换原裸露 IconButton——无底色无轮廓，视觉上"悬浮"不像按钮
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _isOffline ? null : _handleSend,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _isOffline ? AppColors.bgCard : AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.send_rounded,
                      size: 20,
                      color: _isOffline ? AppColors.textMuted : AppColors.bgBase,
                    ),
                  ),
                ),
              ],
            ),
            // 深度交流提示（输入框下方，常显——对齐鸿蒙端 ChatPage.ets
            // ChatInputBuilder：未达成显示进度文案，达成后显示状态文案。
            // 2026-11-02 用户反馈：两端都曾按"达成即隐藏"处理，房间刚达成
            // 深度交流时提示一起消失，用户视角 = "提示被改没了"）
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                widget.room.deepConnectionAchieved
                    ? '深度交流已达成，可解锁资料卡或保存连接'
                    : widget.room.deepConnectionHint,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            // 连续发送提示（达到4条时提醒，5条时警告）
            // 双端统一行为（AGENTS 口径：4 提醒 / 5 拦截）
            if (widget.room.myConsecutiveCount >= 4)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  widget.room.myConsecutiveCount >= 5
                      ? '请等待对方回应后再继续发送'
                      : '已连续发送 ${widget.room.myConsecutiveCount} 条消息，请注意交流节奏',
                  style: TextStyle(
                    fontSize: 11,
                    color: widget.room.myConsecutiveCount >= 5
                        ? AppColors.error
                        : AppColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 引用消息预览条
  Widget _buildQuotePreview(Message msg) {
    final isMe = msg.isMe;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bgBase,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isMe ? AppColors.primary.withOpacity(0.3) : AppColors.primaryBorder,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 32,
            decoration: BoxDecoration(
              color: isMe ? AppColors.primary : AppColors.textSecondary,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isMe ? '引用我的消息' : '引用对方消息',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  msg.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
            onPressed: widget.onQuoteClear,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  void _handleSend() {
    final text = widget.inputController.text.trim();
    if (text.isEmpty) return;
    HapticService.instance.light();
    SoundService.instance.playMessageOut();
    widget.onSendMessage(text);
  }
}
