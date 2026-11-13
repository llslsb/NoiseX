import 'dart:async';
import 'package:flutter/material.dart';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../services/ws_service.dart';
import '../services/auth_service.dart';
import '../services/crypto_service.dart';
import '../services/debug_log.dart';
import '../services/sound_service.dart';
import '../services/haptic_service.dart';
import '../services/push_service.dart';
import '../services/storage_service.dart';
import '../services/api_service.dart';
import '../services/ritual_animation_service.dart';
import '../utils/peer_left_parser.dart';
import '../widgets/harmony_feedback.dart';
import 'room_manager.dart';
import 'sonar_manager.dart';
import 'typing_manager.dart';

/// WebSocket 事件处理器
///
/// 职责：
/// - 处理所有 WS 消息类型
/// - 调用对应的业务逻辑
/// - 通知 UI 状态变更
class WsEventHandler extends ChangeNotifier {
  final RoomManager _roomManager;
  final TypingManager _typingManager;
  final SonarManager? _sonarManager;
  BuildContext? _context;
  WsCallback? _registeredCallback;

  WsEventHandler(this._roomManager, this._typingManager,
      {SonarManager? sonarManager})
      : _sonarManager = sonarManager;

  void attach(BuildContext context) {
    _context = context;
  }

  void detach() {
    _context = null;
  }

  /// 注册所有 WS 回调
  void registerCallbacks() {
    if (_registeredCallback != null) return;
    _registeredCallback = _handleMessage;
    WsService().addCallback(_registeredCallback!);
  }

  /// 注销所有 WS 回调
  void unregisterCallbacks() {
    if (_registeredCallback != null) {
      WsService().removeCallback(_registeredCallback!);
      _registeredCallback = null;
    }
  }

  @override
  void dispose() {
    unregisterCallbacks();
    super.dispose();
  }

  /// 统一消息分发入口
  void _handleMessage(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'chat':
        _handleChat(data);
        break;
      case 'sent_ack':
        _handleSentAck(data);
        break;
      case 'matched':
        _handleMatched(data);
        break;
      case 'room_expired':
        _handleRoomExpired(data);
        break;
      case 'peer_left':
        _handlePeerLeft(data);
        break;
      case 'room_expiring':
        _handleRoomExpiring(data);
        break;
      case 'deep_confirmed':
        _handleDeepConfirmed(data);
        break;
      case 'save_request':
        _handleSaveRequest(data);
        break;
      case 'save_confirmed':
        _handleSaveConfirmed(data);
        break;
      case 'save_refused':
        _handleSaveRefused(data);
        break;
      case 'read_receipt':
        _handleReadReceipt(data);
        break;
      case 'key_exchange':
        _handleKeyExchange(data);
        break;
      case 'typing_start':
        _handleTypingStart(data);
        break;
      case 'typing_stop':
        _handleTypingStop(data);
        break;
      case 'delivered':
        _handleDelivered(data);
        break;
      case 'sonar_received':
        _handleSonarReceived();
        break;
      case 'reconnected':
        unawaited(_handleReconnected());
        break;
    }
  }

  /// B15：收听中新声呐到达（服务端 sonar_received 推送）。
  ///
  /// 对齐鸿蒙端 Index.ets `ws.onSonarReceived = () => this.refreshReceivedSonars()`：
  /// 之前 Flutter 端不认识该事件（分发器静默忽略），接收器列表只有在重启时才刷新。
  /// 原生端仅刷新列表、无额外音效/触感，此处保持一致。
  void _handleSonarReceived() {
    unawaited(_sonarManager?.refreshReceivedSonars());
    notifyListeners();
  }

  // ============ 各消息类型处理器 ============

  Future<void> _handleChat(Map<String, dynamic> data) async {
    final roomId = data['roomId'] as String? ?? '';
    var content = data['content'] as String? ?? '';
    // 服务端 chat 帧的发送者标识是 signalCode（匿名保护），本端无法反查；
    // 已知 userId 时才判 me，否则一律 other。sent_ack 确认帧已改为独立
    // 类型（B17），不会进到本处理器。
    final sender = data['sender'] as String? ?? data['senderId'] as String? ?? '';
    final room = _roomManager.findRoom(roomId);
    if (room == null) return;
    DebugLog().write(
        '[chat] frame sender=$sender, myUuid=${AuthService().userId}, '
        'msgId=${data['messageId']}, resolved=${sender == AuthService().userId ? 'me' : 'other'}');

    // E2EE 解密
    if (CryptoService().hasSharedKey(roomId)) {
      final decrypted = await CryptoService().decrypt(roomId, content);
      if (decrypted != null) {
        content = decrypted;
      }
    }

    final msg = Message(
      // 对齐鸿蒙端 onMessageReceived：使用服务端 messageId（流 id）。
      // 原先生成 'msg-<本地时间戳>'——已读指针引用这种本地 id 后，与原生端
      // 的流 id 无法互比（localeCompare 下 'msg-' 恒大于数字 id），跨端已读错乱。
      id: data['messageId'] as String? ?? 'msg-${DateTime.now().millisecondsSinceEpoch}',
      roomId: roomId,
      sender: sender == AuthService().userId ? 'me' : 'other',
      content: content,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        (data['timestamp'] as int?) ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );

    // 持久化
    StorageService().saveMessage(
      roomId,
      id: msg.id,
      sender: msg.sender,
      content: msg.content,
      timestamp: msg.timestamp.millisecondsSinceEpoch,
    );

    // 更新内存状态
    _roomManager.appendMessage(roomId, msg);

    // 通知或音效
    if (_roomManager.currentRoom?.id != roomId) {
      PushService().showNotification(
        title: '新消息',
        body: '收到新消息',
        roomId: roomId,
      );
    } else {
      SoundService.instance.playMessageIn();
    }
  }

  Future<void> _handleMatched(Map<String, dynamic> data) async {
    final roomId = data['roomId'] as String? ?? '';
    final signalCode = data['signalCode'] as String? ?? '';
    final sonarContent = data['sonarContent'] as String? ?? '';
    final expiresAt = data['expiresAt'] as int? ?? 0;
    final createdAt = data['createdAt'] as int? ?? 0;
    if (roomId.isEmpty) return;

    // 事件重放/重连同步可能对已存在的房间再次触发 matched：
    // 保留本地已积累的消息与双读指针，避免被空列表覆盖
    final existing = _roomManager.findRoom(roomId);
    _roomManager.upsertRoom(ChatRoom(
      id: roomId,
      sonarContent: sonarContent,
      signalCode: signalCode,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
      createdAt: createdAt > 0
          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
          : null,
      messages: existing?.messages ?? const [],
      lastReadMessageId: existing?.lastReadMessageId ?? '',
      peerReadMessageId: existing?.peerReadMessageId ?? '',
    ));

    // 匹配成功反馈
    HapticService.instance.heavy();
    SoundService.instance.playMatchSuccess();

    // 匹配成功仪式感动效（每次匹配都播放）
    if (_context != null && _context!.mounted) {
      unawaited(RitualAnimationService.instance.showFirstMatch(_context!));
    }

    // 自动发起 E2EE 密钥交换
    unawaited(_ensureRoomKeyExchange(roomId));
  }

  Future<void> _ensureRoomKeyExchange(String roomId) async {
    if (CryptoService().hasSharedKey(roomId) ||
        CryptoService().hasKeyPair(roomId)) return;
    final pubKey = await CryptoService().generateKeyPair(roomId);
    if (pubKey.isNotEmpty) {
      WsService().sendKeyExchange(roomId, pubKey);
    }
  }

  Future<void> _handleKeyExchange(Map<String, dynamic> data) async {
    final roomId = data['roomId'] as String? ?? '';
    final peerPubKey = data['pubKey'] as String? ?? '';
    if (roomId.isEmpty || peerPubKey.isEmpty) return;

    if (CryptoService().hasKeyPair(roomId)) {
      // 双方同时发起：各持临时对，直接派生
      await CryptoService().deriveSharedKey(roomId, peerPubKey);
      return;
    }
    // B18：初次交换或一方丢钥（清数据/重装）——生成新对、回应公钥，
    // 并同轮用对方公钥派生新密钥。旧密钥仍在本端时也旋转到新钥，双方收敛。
    // 旧逻辑以 hasSharedKey 挡掉回应，持有密钥一方永不回公钥，交换死锁。
    final myPubKey = await CryptoService().generateKeyPair(roomId);
    if (myPubKey.isNotEmpty) {
      WsService().sendKeyExchange(roomId, myPubKey);
    }
    await CryptoService().deriveSharedKey(roomId, peerPubKey);
  }

  void _handleRoomExpired(Map<String, dynamic> data) {
    final roomId = data['roomId'] as String? ?? '';

    // 风干仪式动效
    if (roomId.isNotEmpty && _context != null && _context!.mounted) {
      RitualAnimationService.instance.showWithering(_context!, roomId);
    }

    final wasInRoom = _roomManager.currentRoom?.id == roomId;
    _roomManager.removeRoom(roomId);
    CryptoService().clearRoomKey(roomId);
    StorageService().deleteRoomMessages(roomId);

    // 自动弹出聊天页
    if (wasInRoom && _context != null && _context!.mounted) {
      Navigator.of(_context!).pop();
    }

    PushService().showNotification(
      title: '对话已过期',
      body: roomExpiredNotificationBody(roomId),
      roomId: roomId,
      channelId: 'service_information',
    );
  }

  void _handlePeerLeft(Map<String, dynamic> data) {
    final ev = PeerLeftEvent.fromPayload(data);
    if (!ev.isValid) return;

    final wasInRoom = _roomManager.currentRoom?.id == ev.roomId;
    _roomManager.removeRoom(ev.roomId);
    CryptoService().clearRoomKey(ev.roomId);
    StorageService().deleteRoomMessages(ev.roomId);

    if (wasInRoom && _context != null && _context!.mounted) {
      Navigator.of(_context!).pop();
    }

    PushService().showNotification(
      title: '对话已结束',
      body: ev.notificationBody,
      roomId: ev.roomId,
      channelId: 'service_information',
    );
  }

  void _handleDeepConfirmed(Map<String, dynamic> data) {
    final roomId = data['roomId'] as String? ?? '';
    final room = _roomManager.findRoom(roomId);
    if (room == null) return;

    final currentUserConfirmed = data['deepConnectionConfirmed'] as bool? ??
        room.deepConnectionConfirmed;
    final bothConfirmed = data['bothDeepConfirmed'] as bool? ??
        data['bothConfirmed'] as bool? ??
        room.bothDeepConfirmed;
    final unlocked =
        data['unlocked'] as bool? ?? (room.unlocked || bothConfirmed);
    final achieved = data['deepConnectionAchieved'] as bool? ?? true;

    _roomManager.upsertRoom(
      room.copyWith(
        deepConnectionAchieved: achieved,
        deepConnectionConfirmed: currentUserConfirmed,
        bothDeepConfirmed: bothConfirmed,
        unlocked: unlocked,
      ),
      moveToTop: false,
    );
  }

  void _handleSaveRequest(Map<String, dynamic> data) {
    final roomId = data['roomId'] as String? ?? '';
    final fromSignalCode = data['fromSignalCode'] as String? ?? '';
    final room = _roomManager.findRoom(roomId);
    if (room == null || room.bothSaveConfirmed) return;

    if (room.mySaveConfirmed) {
      // 我已确认，直接标记双方确认
      unawaited(_handleSaveConfirmation(roomId, forceConfirm: true));
      return;
    }

    if (_context == null || !_context!.mounted) return;
    // 2026-11-03 用户点名：Material 亮色 AlertDialog → 鸿蒙系统风格深色弹窗
    // （拒绝灰/同意橙，对标 ArkTS 端同款弹窗，见 out_test/T17_x7_savereq）
    unawaited(showHarmonyConfirmDialog(
      _context!,
      title: '保存连接请求',
      message: '$fromSignalCode 希望与你保存连接，同意吗？',
      confirmText: '同意',
      cancelText: '拒绝',
      // D3：保存请求必须明确表态，点空白不关闭（防误触=误发拒绝）
      barrierDismissible: false,
    ).then((agreed) {
      if (agreed) {
        _handleSaveConfirmation(roomId);
      } else {
        unawaited(ApiService().saveConnection(roomId, agree: false));
      }
    }));
  }

  Future<void> _handleSaveConfirmation(String roomId,
      {bool forceConfirm = false}) async {
    // 实际的保存确认逻辑会通过 save_confirmed 事件回调回来
    await ApiService().saveConnection(roomId, agree: true);
  }

  void _handleSaveConfirmed(Map<String, dynamic> data) {
    final roomId = data['roomId'] as String? ?? '';
    final room = _roomManager.findRoom(roomId);
    if (room == null) return;

    final wasBothSaveConfirmed = room.bothSaveConfirmed;
    _roomManager.upsertRoom(
      room.copyWith(
        savedConnection: true,
        mySaveConfirmed: true,
        bothSaveConfirmed: true,
      ),
      moveToTop: false,
    );

    if (!wasBothSaveConfirmed && _context != null && _context!.mounted) {
      unawaited(showHarmonyToast(_context!, '连接已保存'));
    }
  }

  void _handleSaveRefused(Map<String, dynamic> data) {
    final roomId = data['roomId'] as String? ?? '';
    final room = _roomManager.findRoom(roomId);
    if (room == null) return;

    _roomManager.upsertRoom(
      room.copyWith(
        savedConnection: false,
        bothSaveConfirmed: false,
      ),
      moveToTop: false,
    );

    if (_context != null && _context!.mounted) {
      unawaited(showHarmonyToast(_context!, '对方拒绝保存连接'));
    }
  }

  void _handleDelivered(Map<String, dynamic> data) {
    final roomId = data['roomId'] as String? ?? '';
    final messageId = data['messageId'] as String? ?? '';
    if (roomId.isEmpty || messageId.isEmpty) return;

    _roomManager.updateMessageDelivered(roomId, messageId);
  }

  void _handleTypingStart(Map<String, dynamic> data) {
    final roomId = data['roomId'] as String? ?? '';
    if (roomId.isEmpty) return;
    _typingManager.startTyping(roomId);
  }

  void _handleTypingStop(Map<String, dynamic> data) {
    final roomId = data['roomId'] as String? ?? '';
    if (roomId.isEmpty) return;
    _typingManager.stopTyping(roomId);
  }

  void _handleReadReceipt(Map<String, dynamic> data) {
    final roomId = data['roomId'] as String? ?? '';
    // 对齐后端 read_receipt 载荷：字段是 messageId（原读的 lastReadMsgId 不存在，
    // 恒为空 → 已读回执从未被处理，自己发的消息永远不翻已读）。
    final messageId = data['messageId'] as String? ?? '';
    if (roomId.isEmpty || messageId.isEmpty) return;

    _roomManager.updateMessageRead(roomId, messageId);
  }

  /// B17 sent_ack：把本端乐观消息（'msg-<本地ts>' 临时 id）替换为服务端流 id。
  /// 与鸿蒙端 replaceLatestLocalMessageId 语义一致（替换最新一条仍持临时 id 的
  /// me 消息）。不替换则 read_receipt/delivered 按 messageId 精确匹配永远失配，
  /// 自己发的消息永远不翻 已读/送达。
  void _handleSentAck(Map<String, dynamic> data) {
    final roomId = data['roomId'] as String? ?? '';
    final messageId = data['messageId'] as String? ?? '';
    if (roomId.isEmpty || messageId.isEmpty) return;

    _roomManager.resolveLatestLocalMessageId(roomId, messageId);
  }

  void _handleRoomExpiring(Map<String, dynamic> data) {
    final roomId = data['roomId'] as String? ?? '';
    final remainingHours = data['remainingHours'] as int? ?? 0;
    final room = _roomManager.findRoom(roomId);
    if (room == null) return;

    if (remainingHours <= 12 && remainingHours > 0 && _context != null && _context!.mounted) {
      unawaited(showHarmonyToast(
        _context!,
        '对话即将在 $remainingHours 小时后风干',
        duration: const Duration(seconds: 3),
      ));
    }
  }

  Future<void> _handleReconnected() async {
    // B15：重连成功后同步服务端数据（对齐鸿蒙端 onReconnected → 同步）；
    // 房间列表的刷新由上层 MainPage 监听 connectionStateStream 完成。
    unawaited(_sonarManager?.refreshReceivedSonars());
    notifyListeners();
  }
}
