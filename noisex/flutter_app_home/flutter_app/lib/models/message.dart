/// 消息发送状态机。
///
/// 与设计文档 `docs/superpowers/plans/2026-06-15-ux-revamp.md` P0-4 对齐。
///
/// - [sending] 本地刚追加，尚未收到 WS ack
/// - [sent] 服务端入库（WS ack 或 REST 200）
/// - [delivered] 对端在线已收到（暂留：依赖 P1 后端 `delivered` WS 协议）
/// - [read] 对端读了消息（已有 `read_receipt` 协议支持）
/// - [failed] 发送失败（用于离线重试列表显示）
enum MessageSendStatus { sending, sent, delivered, read, failed }

class Message {
  final String id;
  final String roomId;
  final String sender;
  final String content;
  final DateTime timestamp;
  final bool isRead;

  /// 发送状态。仅对 `isMe == true` 的消息显示三态符号；
  /// 对方消息此字段无意义，外层应忽略。
  final MessageSendStatus sendStatus;

  const Message({
    required this.id,
    required this.roomId,
    required this.sender,
    required this.content,
    required this.timestamp,
    this.isRead = false,
    this.sendStatus = MessageSendStatus.sent,
  });

  bool get isMe => sender == 'me';

  Message copyWith({
    String? id,
    String? roomId,
    String? sender,
    String? content,
    DateTime? timestamp,
    bool? isRead,
    MessageSendStatus? sendStatus,
  }) {
    return Message(
      id: id ?? this.id,
      roomId: roomId ?? this.roomId,
      sender: sender ?? this.sender,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      sendStatus: sendStatus ?? this.sendStatus,
    );
  }
}
