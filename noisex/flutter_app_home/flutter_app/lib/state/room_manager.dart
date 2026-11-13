import 'package:flutter/material.dart';
import '../models/chat_room.dart';
import '../models/message.dart';
import '../services/debug_log.dart';

/// 房间列表管理器
///
/// 职责：
/// - 房间列表的增删改查
/// - 房间消息的追加与更新
/// - 房间状态维护（深度连接、解锁、保存状态）
class RoomManager extends ChangeNotifier {
  final List<ChatRoom> _rooms = [];
  ChatRoom? _currentRoom;

  // D-M9-1 兜底（2026-11-05 双端实测）：拉黑后服务端 getRooms 不过滤已拉黑
  // 用户的房间（BlockService 只写 user_block，ChatService.getRooms 零过滤），
  // 客户端本地 removeRoom 后任何列表刷新都会把房间"复活"。会话内记录已拉黑
  // 房间 id，upsert 时拒收。局限（归服务端修复）：重启后集合丢失，已拉黑房间
  // 会随列表重新出现；且同一对方开新房（新 roomId）不在集合内。
  final Set<String> _blockedRoomIds = <String>{};

  List<ChatRoom> get rooms => _rooms;
  ChatRoom? get currentRoom => _currentRoom;
  bool get hasCurrentRoom => _currentRoom != null;

  /// 插入或更新房间
  void upsertRoom(ChatRoom room, {bool moveToTop = true}) {
    // 已拉黑房间拒收：列表刷新/WS 事件重新带出时静默丢弃（含 currentRoom 清理）
    if (_blockedRoomIds.contains(room.id)) {
      _rooms.removeWhere((r) => r.id == room.id);
      if (_currentRoom?.id == room.id) {
        _currentRoom = null;
      }
      notifyListeners();
      return;
    }
    final index = _rooms.indexWhere((r) => r.id == room.id);
    if (index >= 0) {
      if (moveToTop) {
        _rooms.removeAt(index);
        _rooms.insert(0, room);
      } else {
        _rooms[index] = room;
      }
    } else {
      if (moveToTop) {
        _rooms.insert(0, room);
      } else {
        _rooms.add(room);
      }
    }

    // 如果是当前房间，同步更新
    if (_currentRoom?.id == room.id) {
      _currentRoom = room;
    }

    notifyListeners();
  }

  /// 设置当前房间
  void setCurrentRoom(ChatRoom? room) {
    _currentRoom = room;
    notifyListeners();
  }

  /// 根据 ID 查找房间
  ChatRoom? findRoom(String roomId) {
    try {
      return _rooms.firstWhere((r) => r.id == roomId);
    } catch (e) {
      return null;
    }
  }

  /// 移除房间
  void removeRoom(String roomId, {bool blocked = false}) {
    if (blocked) _blockedRoomIds.add(roomId);
    _rooms.removeWhere((r) => r.id == roomId);
    if (_currentRoom?.id == roomId) {
      _currentRoom = null;
    }
    notifyListeners();
  }

  /// 向指定房间追加消息
  void appendMessage(String roomId, Message message) {
    final room = findRoom(roomId);
    if (room == null) return;

    final updated = room.copyWith(
      messages: [...room.messages, message],
    );
    upsertRoom(updated, moveToTop: true);
  }

  /// 更新消息送达状态
  void updateMessageDelivered(String roomId, String messageId) {
    final room = findRoom(roomId);
    if (room == null) return;

    final updatedMessages = room.messages.map((m) {
      if (m.id == messageId && m.isMe && m.sendStatus != MessageSendStatus.read) {
        return m.copyWith(sendStatus: MessageSendStatus.delivered);
      }
      return m;
    }).toList();

    upsertRoom(room.copyWith(messages: updatedMessages), moveToTop: false);
  }

  /// 更新消息已读状态（对方读了我的消息 → read_receipt）。
  ///
  /// 只把指针写进 [ChatRoom.peerReadMessageId] 并给气泡标 isRead——
  /// 严禁写 [ChatRoom.lastReadMessageId]：那是"我"的未读数计算基准，
  /// 混用会让列表未读徽标在两个指针之间来回跳（0↔2 闪烁实锤根因）。
  void updateMessageRead(String roomId, String lastReadMsgId) {
    final room = findRoom(roomId);
    if (room == null) return;

    final lastReadIndex = room.messages.indexWhere((m) => m.id == lastReadMsgId);
    DebugLog().write(
        '[roomMgr] updateMessageRead: target=$lastReadMsgId, foundAt=$lastReadIndex, '
        'meMsgs=${room.messages.where((m) => m.isMe).map((m) => '${m.id.length > 13 ? m.id.substring(0, 13) : m.id}:${m.isRead ? 'R' : 'notR'}').join(', ')}');
    if (lastReadIndex < 0) return;

    final updatedMessages = room.messages.asMap().entries.map((e) {
      if (e.key <= lastReadIndex && e.value.isMe) {
        return e.value.copyWith(isRead: true);
      }
      return e.value;
    }).toList();

    upsertRoom(
      room.copyWith(
        messages: updatedMessages,
        peerReadMessageId: lastReadMsgId,
      ),
      moveToTop: false,
    );
  }

  /// 我方已读指针的乐观本地更新：进入聊天页看到最后一条对方消息时调用，
  /// 与随后 WsService.sendRead 写入的服务端指针同值。幂等（同值直接跳过），
  /// 避免 onRoomChanged 每次触发都重发 read 帧。
  void updateMyReadPointer(String roomId, String messageId) {
    final room = findRoom(roomId);
    if (room == null || messageId.isEmpty) return;
    if (room.lastReadMessageId.compareTo(messageId) >= 0) return;
    upsertRoom(
      room.copyWith(lastReadMessageId: messageId),
      moveToTop: false,
    );
  }

  /// 用 REST 拿到的对方已读指针补齐气泡已读态（重进聊天/刷新列表时，
  /// 服务端重建的消息列表不带 isRead，靠指针恢复 ✓✓）。
  void applyPeerReadPointer(String roomId, String peerMessageId) {
    final room = findRoom(roomId);
    if (room == null || peerMessageId.isEmpty) return;
    if (peerMessageId == room.peerReadMessageId &&
        room.messages.every((m) => !m.isMe || m.isRead)) {
      return;
    }
    final idx = room.messages.indexWhere((m) => m.id == peerMessageId);
    final updatedMessages = idx < 0
        ? room.messages
        : room.messages.asMap().entries.map((e) {
            if (e.key <= idx && e.value.isMe) {
              return e.value.copyWith(isRead: true);
            }
            return e.value;
          }).toList();
    upsertRoom(
      room.copyWith(messages: updatedMessages, peerReadMessageId: peerMessageId),
      moveToTop: false,
    );
  }

  /// B17 sent_ack 对账：把最新一条仍持本地临时 id（'msg-' 前缀）的 me 消息
  /// 替换为服务端流 id（对齐鸿蒙端 replaceLatestLocalMessageId）。
  void resolveLatestLocalMessageId(String roomId, String serverMessageId) {
    final room = findRoom(roomId);
    if (room == null) return;

    int targetIndex = -1;
    for (int i = room.messages.length - 1; i >= 0; i--) {
      final m = room.messages[i];
      if (m.isMe && m.id.startsWith('msg-')) {
        targetIndex = i;
        break;
      }
    }
    if (targetIndex < 0) return;

    final updatedMessages = List<Message>.from(room.messages);
    updatedMessages[targetIndex] =
        updatedMessages[targetIndex].copyWith(id: serverMessageId);
    upsertRoom(room.copyWith(messages: updatedMessages), moveToTop: false);
  }

  /// 批量同步房间列表
  void syncRooms(List<ChatRoom> newRooms) {
    _rooms.clear();
    _rooms.addAll(newRooms);
    notifyListeners();
  }

  /// 清空所有房间
  void clear() {
    _rooms.clear();
    _currentRoom = null;
    notifyListeners();
  }

  @override
  void dispose() {
    clear();
    super.dispose();
  }
}
