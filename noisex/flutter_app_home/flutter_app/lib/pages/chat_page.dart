import 'dart:async';
import 'package:flutter/material.dart';
import '../theme/animations.dart';
import '../services/haptic_service.dart';
import '../services/sound_service.dart';
import '../services/debug_log.dart';
import '../services/ws_service.dart';
import '../state/room_manager.dart';
import '../state/typing_manager.dart';
import '../theme/colors.dart';
import '../models/api_types.dart';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/harmony_feedback.dart';
import 'chat/chat_header_bar.dart';
import 'chat/chat_message_list.dart';
import 'chat/chat_input_bar.dart';
import 'chat/chat_info_panel.dart';
import 'chat/chat_menus.dart';

/// 聊天页面
///
/// 重构后的精简版本（约 350 行，原 1200 行），拆分到 chat/ 子目录：
/// - chat_header_bar.dart - 顶部信息栏
/// - chat_message_list.dart - 消息列表
/// - chat_input_bar.dart - 底部输入栏
/// - chat_info_panel.dart - 房间详情展开面板
/// - chat_menus.dart - 对话框和菜单工具类
///
/// 本文件仅保留：
/// - State 生命周期管理
/// - 核心业务逻辑回调
/// - 状态变量管理
class ChatPage extends StatefulWidget {
  final ChatRoom room;
  final VoidCallback onLeave;
  final Future<UnlockResult> Function(String) onUnlock;
  final Future<SaveResult> Function(String, {bool forceConfirm}) onSave;
  final void Function(String) onReport;
  final void Function(String) onConfirmDeep;
  final void Function(String, String) onMarkRead;
  final void Function(String) onBlock;
  final void Function(String, String) onSendMessage;
  final void Function(String, String)? onSaveMoment;
  final double statusBarHeight;

  /// 房间状态源（B15 收尾修复）。
  ///
  /// ChatPage 持有的 [room] 是进入页面时的快照：RoomManager.appendMessage 用
  /// copyWith 生成新对象替换列表项，快照永远看不到新消息（双端联调实锤：对端
  /// 消息与本端已发消息均不显示）。传入 [RoomManager] 后页面监听其变化，
  /// 按 id 解析最新房间对象渲染——对齐鸿蒙端聊天页绑定可观察状态的语义。
  final RoomManager? roomListenable;

  /// 对方是否正在输入。
  ///
  /// 与设计文档 `docs/superpowers/plans/2026-06-15-ux-revamp.md` P0-5 / P1 typing 协议对齐：
  /// - P0 阶段由 [app.dart] 内 `_typingRoomIds` 维护，留接口给 P1 接入 WS `typing_start/typing_stop`
  /// - P1 接入后此值由 WS 事件直接驱动
  ///
  /// ⚠️ 此字段只是进房时刻的静态快照：路由 builder 不随父级 setState 重建，
  /// 进房后才到来的 typing 事件必须经 [typingManager]（Listenable）驱动。
  final bool peerIsTyping;

  /// typing 状态源（TypingManager 是 ChangeNotifier）。与 [peerIsTyping]
  /// 任一为 true 即显示指示器；为空时退回纯静态字段（测试兼容）。
  final TypingManager? typingManager;

  const ChatPage({
    super.key,
    required this.room,
    required this.onLeave,
    required this.onUnlock,
    required this.onSave,
    required this.onReport,
    required this.onConfirmDeep,
    required this.onMarkRead,
    required this.onBlock,
    required this.onSendMessage,
    this.onSaveMoment,
    this.statusBarHeight = 0,
    this.peerIsTyping = false,
    this.typingManager,
    this.roomListenable,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  // 资料展示已改半模态 sheet（UI 评审 P1 §6-3），原 _showInfo 内嵌态移除
  Timer? _countdownTimer;
  DateTime _now = DateTime.now();

  // P1-C：本端 typing 节流——首字发 typing_start，3s 静默后发 typing_stop
  bool _typingStartSent = false;
  Timer? _typingStopTimer;

  // P2-C：消息长按上下文菜单 → 引用预览
  Message? _quotedMessage;

  // F1-3：解锁/保存连接 in-flight 节流（防抖 + 三阶段反馈）
  // 与计划文档 docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F1-3 对齐。
  bool _unlockInFlight = false;
  bool _saveInFlight = false;

  // 深度交流达成自动弹窗（对齐鸿蒙端 ChatPage.ets deepConfirmDialogShown 守卫）：
  // 仅在页面打开期间观察到 false→true 转变时弹一次；进入时已达成的房间不弹。
  bool _deepConfirmDialogShown = false;
  bool? _lastDeepAchieved;

  /// 当前房间：优先从 [RoomManager] 解析最新对象，管理器没有时退回快照。
  ChatRoom get _chatRoom =>
      widget.roomListenable?.findRoom(widget.room.id) ?? widget.room;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    // 对齐鸿蒙端 ChatPage.ets:258——消息列表变化（含页面开着收到新消息）时重标已读。
    // _markLastMessageRead 内部按 lastReadMessageId 幂等，重复通知无副作用。
    widget.roomListenable?.addListener(_onRoomChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _markLastMessageRead();
      _scrollToBottom();
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  void _onRoomChanged() {
    DebugLog().write('[markRead] onRoomChanged fired');
    if (!mounted) return;
    _markLastMessageRead();
    // 对齐鸿蒙端 refreshMessageList（ChatPage.ets:254）：消息变化后滚到底部。
    // 否则对方来新消息时列表停在原位，新消息在视口外看不到（用户实测反馈）。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scrollToBottom();
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels <= 50 &&
        _scrollController.position.minScrollExtent < 0) {
      // 修正：原直发 onMarkRead(roomId, '') 空 messageId，服务端校验直接丢弃。
      _markLastMessageRead();
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: AppAnimations.fast,
        curve: AppAnimations.decelerateCurve,
      );
    }
  }

  void _markLastMessageRead() {
    final room = _chatRoom;
    if (room.messages.isEmpty) {
      DebugLog().write('[markRead] skip: messages empty');
      return;
    }
    // 对齐鸿蒙端 markLastMessageRead（ChatPage.ets:1012）：从后往前找最后一条
    // "对方"消息——与最后一条是否本端消息无关。原实现只看 messages.last，
    // 最后一条是本端消息时整个跳过，导致对方视角永远看不到已读。
    String lastOtherId = '';
    for (final m in room.messages.reversed) {
      if (m.sender == 'other') {
        lastOtherId = m.id;
        break;
      }
    }
    DebugLog().write(
        '[markRead] lastOtherId=$lastOtherId, lastReadMessageId=${room.lastReadMessageId}, '
        'count=${room.messages.length}, lastSender=${room.messages.last.sender}');
    if (lastOtherId.isNotEmpty && lastOtherId != room.lastReadMessageId) {
      // 乐观更新本地未读基准（与服务端将写入的指针同值）：
      // 幂等门控，防止 onRoomChanged 每次触发都重发 read 帧
      widget.roomListenable?.updateMyReadPointer(room.id, lastOtherId);
      widget.onMarkRead(room.id, lastOtherId);
    }
  }

  @override
  void dispose() {
    widget.roomListenable?.removeListener(_onRoomChanged);
    WidgetsBinding.instance.removeObserver(this);
    _inputController.dispose();
    _scrollController.dispose();
    _countdownTimer?.cancel();
    _flushTypingStop();
    super.dispose();
  }

  /// P1-C：onChanged 节流。
  /// - 文本由空 → 非空：发 typing_start
  /// - 持续输入：每次重置 3s 停顿定时器
  /// - 3s 没改动 / 文本被清空：发 typing_stop
  void _handleTypingChange(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      _flushTypingStop();
      return;
    }
    if (!_typingStartSent) {
      _typingStartSent = true;
      WsService().sendTyping(widget.room.id, isStart: true);
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 3), () {
      _flushTypingStop();
    });
  }

  void _flushTypingStop() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;
    if (_typingStartSent) {
      WsService().sendTyping(widget.room.id, isStart: false);
      _typingStartSent = false;
    }
  }

  @override
  void didChangeMetrics() {
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _sendMessage(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (!_chatRoom.canSendMessage) {
      DebugLog().write(
          'Chat send blocked: consecutive=${_chatRoom.myConsecutiveCount} room=${_chatRoom.id}');
      unawaited(showHarmonyToast(context, '请等待对方回应后再继续发送',
          duration: const Duration(milliseconds: 1500)));
      return;
    }
    HapticService.instance.light();
    SoundService.instance.playMessageOut();
    _flushTypingStop();

    // P2-C：若存在引用消息，发送时拼接为 `> 原文摘要\n用户输入`
    final payload = _quotedMessage == null
        ? trimmed
        : '> ${ChatMenus.quotePreviewText(_quotedMessage!)}\n$trimmed';

    widget.onSendMessage(widget.room.id, payload);
    _inputController.clear();
    if (_quotedMessage != null) {
      setState(() => _quotedMessage = null);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  /// P2-C：长按消息 → 弹出复制 / 引用 / 举报底部菜单。
  Future<void> _showMessageContextMenu(Message msg) async {
    await ChatMenus.showMessageContextMenu(
      context: context,
      message: msg,
      onCopy: () => ChatMenus.copyMessageToClipboard(context: context, message: msg),
      onQuote: () => setState(() => _quotedMessage = msg),
      onReport: () => widget.onReport(widget.room.id),
    );
  }

  Future<void> _handleUnlock() async {
    if (_unlockInFlight) return;

    setState(() => _unlockInFlight = true);
    HapticService.instance.light();
    // 与鸿蒙端 onUnlockTap 一致：in-flight → success/error 三段反馈
    // （2026-11-03 换鸿蒙 toast 样式，对齐 ArkTS promptAction.showToast）
    unawaited(showHarmonyToast(context, '正在解锁资料…',
        duration: const Duration(milliseconds: 1000)));

    final result = await widget.onUnlock(widget.room.id);
    if (!mounted) return;

    setState(() => _unlockInFlight = false);
    if (result.ok) {
      HapticService.instance.medium();
      unawaited(showHarmonyToast(
          context, '已解锁 ${_chatRoom.signalCode} 的资料'));
    } else {
      HapticService.instance.heavy();
      final reason = (result.errorMessage != null && result.errorMessage!.isNotEmpty)
          ? result.errorMessage!
          : '请稍后再试';
      unawaited(showHarmonyToast(context, '解锁失败：$reason'));
    }
  }

  Future<void> _handleSave() async {
    if (_saveInFlight) return;

    setState(() => _saveInFlight = true);
    HapticService.instance.light();
    unawaited(showHarmonyToast(context, '请求保存…',
        duration: const Duration(milliseconds: 1000)));

    final result = await widget.onSave(widget.room.id);
    if (!mounted) return;

    setState(() => _saveInFlight = false);
    if (result.ok) {
      HapticService.instance.medium();
      final msg = widget.room.bothSaveConfirmed
          ? '连接已保存'
          : '保存请求已发送，等待对方确认';
      unawaited(showHarmonyToast(context, msg));
    } else {
      HapticService.instance.heavy();
      final reason = (result.errorMessage != null && result.errorMessage!.isNotEmpty)
          ? result.errorMessage!
          : '请稍后再试';
      unawaited(showHarmonyToast(context, '保存失败：$reason'));
    }
  }

  /// 返回导航（对齐鸿蒙端 ChatPage 返回箭头/系统返回语义：仅返回上一页，
  /// 不离开房间、无确认弹窗。房间保留在沙漏列表；离开走菜单"离开房间"确认流程。
  /// 旧版把返回箭头接到离开流程属语义错位，且是 B22 返回键不稳定的表现之一）
  void _navigateBack() {
    Navigator.of(context).pop();
  }

  /// 菜单"离开房间"入口：离开=永久关闭聊天室（不可逆），二次确认后触发 onLeave
  Future<void> _confirmLeaveRoom() async {
    final confirmed = await ChatMenus.showLeaveRoomDialog(context);
    if (confirmed) {
      widget.onLeave();
    }
  }

  Future<void> _handleSaveMoment() async {
    final content = await ChatMenus.showSaveMomentDialog(context);
    if (content != null && mounted) {
      widget.onSaveMoment?.call(widget.room.id, content);
    }
  }

  bool _shouldShowSaveMomentOption(ChatRoom room) {
    // 房间剩余时间 < 2 小时显示保存片段入口
    final remaining = room.expiresAt.difference(DateTime.now());
    return remaining.inHours < 2;
  }

  @override
  Widget build(BuildContext context) {
    // B15 收尾：监听 RoomManager，房间对象被 appendMessage/copyWith 替换时重建
    final listenable = widget.roomListenable;
    if (listenable == null) {
      return _buildChatScaffold(context);
    }
    return AnimatedBuilder(
      animation: listenable,
      builder: (context, _) => _buildChatScaffold(context),
    );
  }

  /// 深度交流达成自动弹窗（对齐鸿蒙端 ChatPage.ets：达成且双方未确认、
  /// 本次会话未弹过时弹一次）。在 build 期间只记录转变，post-frame 再弹。
  void _maybeAutoShowDeepConfirm(ChatRoom room) {
    final achieved = room.deepConnectionAchieved;
    if (!_deepConfirmDialogShown &&
        _lastDeepAchieved == false &&
        achieved &&
        !room.deepConnectionConfirmed) {
      _deepConfirmDialogShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _handleConfirmDeep();
      });
    }
    _lastDeepAchieved = achieved;
  }

  /// 资料半模态 sheet（UI 评审 P1 §6-3：资料查看是低频动作，改底部
  /// 半模态弹出，不再内嵌挤压消息列表；鸿蒙端 ChatPage.ets bindSheet 同步）
  Future<void> _openProfileSheet() async {
    final room = _chatRoom;
    // D2-v2（2026-11-03 真机实测实锤）：头部"查看资料"此前只负责开面板，
    // 解锁 REST 只挂在 ⋮ 菜单的条件项上——房间已解锁后菜单项不再渲染，
    // 重启/重装后"已解锁但本地无资料"的房间永远拿不到资料，面板只会
    // 显示空态。现在：已解锁且本地无资料时先走解锁拉取（复用 in-flight
    // 防抖 + 反馈 toast + RoomManager 合并），拿到资料再展示面板。
    if (room.unlocked && room.otherProfile == null && !_unlockInFlight) {
      await _handleUnlock();
      if (!mounted) return;
    }
    final fresh = _chatRoom;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 半模态 grabber（iOS 风格，鸿蒙端同款 36×4）
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 4),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ChatInfoPanel(room: fresh),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// 深度进度徽章点按：滚回列表顶部的环形规则说明（UI 评审 P0 §5-4）
  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildChatScaffold(BuildContext context) {
    // 每次 build 解析最新房间对象，消息列表/进度/按钮态均来自实时数据
    final room = _chatRoom;
    _maybeAutoShowDeepConfirm(room);

    return Scaffold(
      backgroundColor: AppColors.bgBase,
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(top: widget.statusBarHeight),
            child: Column(
              children: [
                ChatHeaderBar(
                  room: room,
                  now: _now,
                  onDeepBadgeTap: _scrollToTop,
                  onBack: _navigateBack,
                  onToggleInfo: _openProfileSheet,
                  onUnlock: _handleUnlock,
                  onSave: _handleSave,
                  onReport: () => widget.onReport(room.id),
                  onBlock: _handleBlock,
                  onConfirmDeep: _handleConfirmDeep,
                  onLeave: _confirmLeaveRoom,
                  unlockInFlight: _unlockInFlight,
                  saveInFlight: _saveInFlight,
                ),
                if (_shouldShowSaveMomentOption(room))
                  _buildSaveMomentOption(room),
                Expanded(
                  child: ChatMessageList(
                    room: room,
                    scrollController: _scrollController,
                    onMessageLongPress: _showMessageContextMenu,
                  ),
                ),
                if (widget.typingManager != null)
                  ListenableBuilder(
                    listenable: widget.typingManager!,
                    builder: (context, _) =>
                        (widget.peerIsTyping ||
                            widget.typingManager!.isTyping(widget.room.id))
                        ? TypingIndicator(peerSignalCode: room.signalCode)
                        : const SizedBox.shrink(),
                  )
                else if (widget.peerIsTyping)
                  TypingIndicator(peerSignalCode: room.signalCode),
                ChatInputBar(
                  room: room,
                  inputController: _inputController,
                  quotedMessage: _quotedMessage,
                  onSendMessage: _sendMessage,
                  onQuoteClear: () => setState(() => _quotedMessage = null),
                  onTypingChange: _handleTypingChange,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 拉黑确认弹窗（与鸿蒙端 ChatPage.showBlockConfirmDialog 文案逐字一致）。
  /// 拉黑会关闭聊天室且只能进拉黑列表解除，属不可逆操作，必须二次确认。
  /// 2026-11-03 换鸿蒙系统风格深色弹窗（danger=确认红）。
  Future<void> _handleBlock() async {
    final confirmed = await showHarmonyConfirmDialog(
      context,
      title: '确认拉黑',
      message: '拉黑后将关闭当前聊天室，对方将无法继续联系你。此操作只能在拉黑列表中解除。',
      confirmText: '确认拉黑',
      cancelText: '取消',
      danger: true,
    );
    if (confirmed) {
      widget.onBlock(widget.room.id);
    }
  }

  /// 深度交流确认弹窗（与鸿蒙端 ChatPage.showDeepConfirmDialog 文案逐字一致）
  /// 2026-11-03 换鸿蒙系统风格深色弹窗（稍后再说灰/确认橙）。
  Future<void> _handleConfirmDeep() async {
    final confirmed = await showHarmonyConfirmDialog(
      context,
      title: '深度交流已达成',
      message: '你们已达到深度交流条件！确认深度交流后，双方都确认即可解锁对方资料。',
      confirmText: '确认深度交流',
      cancelText: '稍后再说',
    );
    if (confirmed) {
      widget.onConfirmDeep(widget.room.id);
    }
  }

  Widget _buildSaveMomentOption(ChatRoom room) {
    return GestureDetector(
      onTap: _handleSaveMoment,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: AppColors.bgCard,
        child: Row(
          children: [
            const Text('📝', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            const Text(
              '保存临终片段',
              style: TextStyle(fontSize: 13, color: AppColors.primary),
            ),
            const Spacer(),
            const Text(
              '房间即将关闭，保存这段对话中最有意义的一句话',
              style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, size: 16, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}
