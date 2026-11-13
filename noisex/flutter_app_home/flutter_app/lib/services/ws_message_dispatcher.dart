import 'dart:async';

/// WebSocket 消息类型定义
enum WsMessageType {
  chat,
  matched,
  roomExpired,
  peerLeft,
  roomExpiring,
  deepConfirmed,
  saveRequest,
  saveConfirmed,
  saveRefused,
  readReceipt,
  keyExchange,
  typingStart,
  typingStop,
  delivered,
  reconnected,
}

/// WebSocket 消息分发器
///
/// 类型安全的消息分发机制，替代原来的全局 switch-case 回调。
/// 每个消息类型有独立的处理器注册，支持多监听器。
///
/// 优势：
/// - 编译时类型检查，不会漏处理字段
/// - 每个 handler 只收到自己关心的消息
/// - 新增消息类型时编译报错，提醒实现
/// - 支持按房间过滤消息
///
/// 使用方式：
/// ```dart
/// final dispatcher = WsMessageDispatcher();
///
/// // 注册聊天消息处理器
/// dispatcher.onChat((roomId, message) {
///   print('收到消息: ${message.content}');
/// });
///
/// // 注册 peerLeft 处理器
/// dispatcher.onPeerLeft((event) {
///   print('对方离开了房间: ${event.roomId}');
/// });
///
/// // 分发消息
/// dispatcher.dispatch('chat', {'roomId': 'xxx', 'content': 'hello'});
/// ```
class WsMessageDispatcher {
  final Map<WsMessageType, List<Function>> _handlers = {};

  /// 解析消息类型字符串为枚举
  static WsMessageType? _parseType(String type) {
    switch (type) {
      case 'chat':
        return WsMessageType.chat;
      case 'matched':
        return WsMessageType.matched;
      case 'room_expired':
        return WsMessageType.roomExpired;
      case 'peer_left':
        return WsMessageType.peerLeft;
      case 'room_expiring':
        return WsMessageType.roomExpiring;
      case 'deep_confirmed':
        return WsMessageType.deepConfirmed;
      case 'save_request':
        return WsMessageType.saveRequest;
      case 'save_confirmed':
        return WsMessageType.saveConfirmed;
      case 'save_refused':
        return WsMessageType.saveRefused;
      case 'read_receipt':
        return WsMessageType.readReceipt;
      case 'key_exchange':
        return WsMessageType.keyExchange;
      case 'typing_start':
        return WsMessageType.typingStart;
      case 'typing_stop':
        return WsMessageType.typingStop;
      case 'delivered':
        return WsMessageType.delivered;
      case 'reconnected':
        return WsMessageType.reconnected;
      default:
        return null;
    }
  }

  /// 注册处理器
  void _registerHandler<T>(WsMessageType type, void Function(T) handler) {
    _handlers.putIfAbsent(type, () => []).add(handler);
  }

  /// 分发消息到所有注册的处理器
  void dispatch(String typeStr, Map<String, dynamic> payload) {
    final type = _parseType(typeStr);
    if (type == null) {
      // 未知消息类型，静默忽略
      return;
    }

    final handlers = _handlers[type];
    if (handlers == null || handlers.isEmpty) return;

    for (final handler in handlers) {
      try {
        _dispatchToHandler(type, handler, payload);
      } catch (e, stack) {
        // 单个 handler 失败不影响其他 handler
        Zone.current.print('WsMessageDispatcher error handling $type: $e\n$stack');
      }
    }
  }

  /// 根据类型分发到对应处理器
  void _dispatchToHandler(
    WsMessageType type,
    Function handler,
    Map<String, dynamic> payload,
  ) {
    switch (type) {
      case WsMessageType.chat:
        final roomId = payload['roomId'] as String? ?? '';
        final sender = payload['senderId'] as String? ?? '';
        final content = payload['content'] as String? ?? '';
        final timestamp = payload['timestamp'] as int? ??
            DateTime.now().millisecondsSinceEpoch;
        handler(
          ChatMessageEvent(
            roomId: roomId,
            senderId: sender,
            content: content,
            timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
          ),
        );
        break;

      case WsMessageType.matched:
        final roomId = payload['roomId'] as String? ?? '';
        final signalCode = payload['signalCode'] as String? ?? '';
        final sonarContent = payload['sonarContent'] as String? ?? '';
        final expiresAt = payload['expiresAt'] as int? ?? 0;
        final createdAt = payload['createdAt'] as int? ?? 0;
        handler(
          MatchedEvent(
            roomId: roomId,
            signalCode: signalCode,
            sonarContent: sonarContent,
            expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAt),
            createdAt: createdAt > 0
                ? DateTime.fromMillisecondsSinceEpoch(createdAt)
                : null,
          ),
        );
        break;

      case WsMessageType.roomExpired:
        final roomId = payload['roomId'] as String? ?? '';
        handler(RoomExpiredEvent(roomId: roomId));
        break;

      case WsMessageType.peerLeft:
        final roomId = payload['roomId'] as String? ?? '';
        final signalCode = payload['signalCode'] as String? ?? '';
        final leftAt = payload['leftAt'] as int? ?? 0;
        handler(
          PeerLeftEvent(
            roomId: roomId,
            signalCode: signalCode,
            leftAt: leftAt > 0 ? DateTime.fromMillisecondsSinceEpoch(leftAt) : null,
          ),
        );
        break;

      case WsMessageType.roomExpiring:
        final roomId = payload['roomId'] as String? ?? '';
        final remainingHours = payload['remainingHours'] as int? ?? 0;
        handler(
          RoomExpiringEvent(
            roomId: roomId,
            remainingHours: remainingHours,
          ),
        );
        break;

      case WsMessageType.deepConfirmed:
        final roomId = payload['roomId'] as String? ?? '';
        final currentUserConfirmed = payload['deepConnectionConfirmed'] as bool?;
        final bothConfirmed = payload['bothDeepConfirmed'] as bool? ??
            payload['bothConfirmed'] as bool?;
        final unlocked = payload['unlocked'] as bool?;
        final achieved = payload['deepConnectionAchieved'] as bool? ?? true;
        handler(
          DeepConfirmedEvent(
            roomId: roomId,
            currentUserConfirmed: currentUserConfirmed,
            bothConfirmed: bothConfirmed,
            unlocked: unlocked,
            deepConnectionAchieved: achieved,
          ),
        );
        break;

      case WsMessageType.saveRequest:
        final roomId = payload['roomId'] as String? ?? '';
        final fromSignalCode = payload['fromSignalCode'] as String? ?? '';
        handler(
          SaveRequestEvent(
            roomId: roomId,
            fromSignalCode: fromSignalCode,
          ),
        );
        break;

      case WsMessageType.saveConfirmed:
        final roomId = payload['roomId'] as String? ?? '';
        handler(SaveConfirmedEvent(roomId: roomId));
        break;

      case WsMessageType.saveRefused:
        final roomId = payload['roomId'] as String? ?? '';
        handler(SaveRefusedEvent(roomId: roomId));
        break;

      case WsMessageType.readReceipt:
        final roomId = payload['roomId'] as String? ?? '';
        final lastReadMsgId = payload['lastReadMsgId'] as String? ?? '';
        handler(
          ReadReceiptEvent(
            roomId: roomId,
            lastReadMsgId: lastReadMsgId,
          ),
        );
        break;

      case WsMessageType.keyExchange:
        final roomId = payload['roomId'] as String? ?? '';
        final peerPubKey = payload['pubKey'] as String? ?? '';
        handler(
          KeyExchangeEvent(
            roomId: roomId,
            peerPubKey: peerPubKey,
          ),
        );
        break;

      case WsMessageType.typingStart:
        final roomId = payload['roomId'] as String? ?? '';
        handler(TypingStartEvent(roomId: roomId));
        break;

      case WsMessageType.typingStop:
        final roomId = payload['roomId'] as String? ?? '';
        handler(TypingStopEvent(roomId: roomId));
        break;

      case WsMessageType.delivered:
        final roomId = payload['roomId'] as String? ?? '';
        final messageId = payload['messageId'] as String? ?? '';
        handler(
          MessageDeliveredEvent(
            roomId: roomId,
            messageId: messageId,
          ),
        );
        break;

      case WsMessageType.reconnected:
        handler(ReconnectedEvent());
        break;
    }
  }

  // ============ 注册 API ============

  /// 注册聊天消息处理器
  void onChat(void Function(ChatMessageEvent) handler) {
    _registerHandler(WsMessageType.chat, handler);
  }

  /// 注册匹配成功处理器
  void onMatched(void Function(MatchedEvent) handler) {
    _registerHandler(WsMessageType.matched, handler);
  }

  /// 注册房间过期处理器
  void onRoomExpired(void Function(RoomExpiredEvent) handler) {
    _registerHandler(WsMessageType.roomExpired, handler);
  }

  /// 注册对方离开处理器
  void onPeerLeft(void Function(PeerLeftEvent) handler) {
    _registerHandler(WsMessageType.peerLeft, handler);
  }

  /// 注册房间即将过期处理器
  void onRoomExpiring(void Function(RoomExpiringEvent) handler) {
    _registerHandler(WsMessageType.roomExpiring, handler);
  }

  /// 注册深度连接确认处理器
  void onDeepConfirmed(void Function(DeepConfirmedEvent) handler) {
    _registerHandler(WsMessageType.deepConfirmed, handler);
  }

  /// 注册保存连接请求处理器
  void onSaveRequest(void Function(SaveRequestEvent) handler) {
    _registerHandler(WsMessageType.saveRequest, handler);
  }

  /// 注册保存连接确认处理器
  void onSaveConfirmed(void Function(SaveConfirmedEvent) handler) {
    _registerHandler(WsMessageType.saveConfirmed, handler);
  }

  /// 注册保存连接拒绝处理器
  void onSaveRefused(void Function(SaveRefusedEvent) handler) {
    _registerHandler(WsMessageType.saveRefused, handler);
  }

  /// 注册已读回执处理器
  void onReadReceipt(void Function(ReadReceiptEvent) handler) {
    _registerHandler(WsMessageType.readReceipt, handler);
  }

  /// 注册密钥交换处理器
  void onKeyExchange(void Function(KeyExchangeEvent) handler) {
    _registerHandler(WsMessageType.keyExchange, handler);
  }

  /// 注册对方开始输入处理器
  void onTypingStart(void Function(TypingStartEvent) handler) {
    _registerHandler(WsMessageType.typingStart, handler);
  }

  /// 注册对方停止输入处理器
  void onTypingStop(void Function(TypingStopEvent) handler) {
    _registerHandler(WsMessageType.typingStop, handler);
  }

  /// 注册消息送达处理器
  void onMessageDelivered(void Function(MessageDeliveredEvent) handler) {
    _registerHandler(WsMessageType.delivered, handler);
  }

  /// 注册重连成功处理器
  void onReconnected(void Function(ReconnectedEvent) handler) {
    _registerHandler(WsMessageType.reconnected, handler);
  }

  /// 移除指定类型的所有处理器
  void removeHandlers(WsMessageType type) {
    _handlers.remove(type);
  }

  /// 清空所有处理器
  void clear() {
    _handlers.clear();
  }
}

// ============ 事件类型定义 ============

/// 聊天消息事件
class ChatMessageEvent {
  final String roomId;
  final String senderId;
  final String content;
  final DateTime timestamp;

  const ChatMessageEvent({
    required this.roomId,
    required this.senderId,
    required this.content,
    required this.timestamp,
  });
}

/// 匹配成功事件
class MatchedEvent {
  final String roomId;
  final String signalCode;
  final String sonarContent;
  final DateTime expiresAt;
  final DateTime? createdAt;

  const MatchedEvent({
    required this.roomId,
    required this.signalCode,
    required this.sonarContent,
    required this.expiresAt,
    this.createdAt,
  });
}

/// 房间过期事件
class RoomExpiredEvent {
  final String roomId;

  const RoomExpiredEvent({required this.roomId});
}

/// 对方离开事件
class PeerLeftEvent {
  final String roomId;
  final String signalCode;
  final DateTime? leftAt;

  const PeerLeftEvent({
    required this.roomId,
    required this.signalCode,
    this.leftAt,
  });
}

/// 房间即将过期事件
class RoomExpiringEvent {
  final String roomId;
  final int remainingHours;

  const RoomExpiringEvent({
    required this.roomId,
    required this.remainingHours,
  });
}

/// 深度连接确认事件
class DeepConfirmedEvent {
  final String roomId;
  final bool? currentUserConfirmed;
  final bool? bothConfirmed;
  final bool? unlocked;
  final bool deepConnectionAchieved;

  const DeepConfirmedEvent({
    required this.roomId,
    this.currentUserConfirmed,
    this.bothConfirmed,
    this.unlocked,
    this.deepConnectionAchieved = true,
  });
}

/// 保存连接请求事件
class SaveRequestEvent {
  final String roomId;
  final String fromSignalCode;

  const SaveRequestEvent({
    required this.roomId,
    required this.fromSignalCode,
  });
}

/// 保存连接确认事件
class SaveConfirmedEvent {
  final String roomId;

  const SaveConfirmedEvent({required this.roomId});
}

/// 保存连接拒绝事件
class SaveRefusedEvent {
  final String roomId;

  const SaveRefusedEvent({required this.roomId});
}

/// 已读回执事件
class ReadReceiptEvent {
  final String roomId;
  final String lastReadMsgId;

  const ReadReceiptEvent({
    required this.roomId,
    required this.lastReadMsgId,
  });
}

/// 密钥交换事件
class KeyExchangeEvent {
  final String roomId;
  final String peerPubKey;

  const KeyExchangeEvent({
    required this.roomId,
    required this.peerPubKey,
  });
}

/// 对方开始输入事件
class TypingStartEvent {
  final String roomId;

  const TypingStartEvent({required this.roomId});
}

/// 对方停止输入事件
class TypingStopEvent {
  final String roomId;

  const TypingStopEvent({required this.roomId});
}

/// 消息送达事件
class MessageDeliveredEvent {
  final String roomId;
  final String messageId;

  const MessageDeliveredEvent({
    required this.roomId,
    required this.messageId,
  });
}

/// 重连成功事件
class ReconnectedEvent {
  const ReconnectedEvent();
}
