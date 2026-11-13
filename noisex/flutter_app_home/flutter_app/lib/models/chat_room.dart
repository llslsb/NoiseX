import 'dart:math';

import 'constants.dart';
import 'message.dart';

int _serverTimeOffsetMillis = 0;
bool _serverTimeOffsetSynced = false;

bool get hasServerTimeOffset => _serverTimeOffsetSynced;

void updateServerTimeOffset(int serverTimeMillis) {
  _serverTimeOffsetMillis =
      serverTimeMillis - DateTime.now().millisecondsSinceEpoch;
  _serverTimeOffsetSynced = true;
}

void resetServerTimeOffset() {
  _serverTimeOffsetMillis = 0;
  _serverTimeOffsetSynced = false;
}

DateTime serverNow() {
  final nowMillis = DateTime.now().millisecondsSinceEpoch;
  return DateTime.fromMillisecondsSinceEpoch(
      nowMillis + _serverTimeOffsetMillis);
}

class ChatRoom {
  final String id;
  final String sonarContent;
  final String signalCode;
  final DateTime expiresAt;
  final DateTime createdAt;
  final List<Message> messages;
  final bool unlocked;
  final bool deepConnectionAchieved;
  final bool deepConnectionConfirmed;
  final bool bothDeepConfirmed;
  final bool savedConnection;
  final bool mySaveConfirmed;
  final bool bothSaveConfirmed;
  final UserProfile? otherProfile;
  final String lastReadMessageId;

  /// 对方（peer）的已读指针：指向对方最后读到的一条消息（通常是我方消息）。
  /// 与 [lastReadMessageId]（我方指针，未读数计算基准）必须分开存——
  /// 曾把 read_receipt 推来的对方指针写进 lastReadMessageId，未读数计算
  /// 基准被污染，列表徽标在两个指针间来回跳（0↔N 闪烁）。
  final String peerReadMessageId;

  ChatRoom({
    required this.id,
    required this.sonarContent,
    required this.signalCode,
    required this.expiresAt,
    DateTime? createdAt,
    this.messages = const [],
    this.unlocked = false,
    this.deepConnectionAchieved = false,
    this.deepConnectionConfirmed = false,
    this.bothDeepConfirmed = false,
    this.savedConnection = false,
    this.mySaveConfirmed = false,
    this.bothSaveConfirmed = false,
    this.otherProfile,
    this.lastReadMessageId = '',
    this.peerReadMessageId = '',
  }) : createdAt = createdAt ??
            expiresAt
                .subtract(const Duration(hours: Constants.roomLifetimeHours));

  int get remainingHours {
    final diff = expiresAt.difference(serverNow());
    if (diff.isNegative) return 0;
    return diff.inHours;
  }

  bool get isUnlockWindowOpen {
    if (unlocked) return false;
    return unlockWindowRemaining.inMilliseconds > 0;
  }

  Duration get unlockWindowRemaining {
    final unlockDeadline =
        createdAt.add(const Duration(hours: Constants.unlockWindowHours));
    final diff = unlockDeadline.difference(serverNow());
    if (diff.isNegative) return Duration.zero;
    return diff;
  }

  int get remainingUnlockHours => unlockWindowRemaining.inHours;

  String get displayName => '匿名用户';

  String? get lastMessage => messages.isNotEmpty ? messages.last.content : null;

  bool get canSaveConnection => !mySaveConfirmed && !bothSaveConfirmed;

  // ========== TASK-002: 深度交流进度计算（与鸿蒙端对齐） ==========
  int get myMessageCount => messages.where((m) => m.sender == 'me').length;

  /// 未读消息数（对齐鸿蒙端 getUnreadMessageCount：对方消息且 id > lastReadMessageId，
  /// lastReadMessageId 为空时计全部对方消息）
  ///
  /// 两条防御（2026-11-02 幻影未读 96 实锤）：
  /// - 按 id 去重：历史 bug 时代同一条对方消息在本地缓存里留下几十份拷贝，
  ///   逐行计数会把徽标顶成幻影值；
  /// - 跳过 'msg-' 前缀 id：真实对方消息一律持服务端流 id，'msg-' 前缀
  ///   只可能是本地临时 id 时代的脏数据（字符串比较恒大于数字 id）。
  int get unreadCount {
    final otherIds = messages
        .where((m) => m.sender == 'other' && !m.id.startsWith('msg-'))
        .map((m) => m.id)
        .toSet();
    if (lastReadMessageId.isEmpty) return otherIds.length;
    return otherIds.where((id) => id.compareTo(lastReadMessageId) > 0).length;
  }

  int get otherMessageCount => messages.where((m) => m.sender == 'other').length;

  int get totalMessageCount => messages.length;

  double get deepConnectionProgress =>
      totalMessageCount / Constants.deepConnectionThreshold;

  /// 我连续发送的消息数（从后往前找，直到遇到对方消息为止）
  int get myConsecutiveCount {
    int count = 0;
    for (int i = messages.length - 1; i >= 0; i--) {
      if (messages[i].sender == 'me') {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /// 是否可以继续发送消息：连续发送不超过 5 条
  bool get canSendMessage => myConsecutiveCount < 5;

  String get deepConnectionHint {
    const threshold = Constants.deepConnectionThreshold;
    const minEach = 5;
    if (myMessageCount < minEach && otherMessageCount < minEach) {
      return '继续交流以达成深度交流（还需 ${max(0, threshold - totalMessageCount)} 条，双方各至少$minEach条）';
    } else if (myMessageCount < minEach) {
      return '继续交流以达成深度交流（你还需至少 ${minEach - myMessageCount} 条参与）';
    } else if (otherMessageCount < minEach) {
      return '继续交流以达成深度交流（等待对方参与）';
    } else {
      return '继续交流以达成深度交流（还需 ${max(0, threshold - totalMessageCount)} 条）';
    }
  }

  String get saveConnectionLabel {
    if (bothSaveConfirmed) return '连接已保存';
    if (mySaveConfirmed) return '等待对方确认';
    return '保存连接';
  }

  ChatRoom applyServerSaveState({
    required bool savedConnection,
    required bool mySaveConfirmed,
    required bool bothSaveConfirmed,
  }) {
    return copyWith(
      savedConnection: savedConnection,
      mySaveConfirmed: mySaveConfirmed,
      bothSaveConfirmed: bothSaveConfirmed,
    );
  }

  ChatRoom copyWith({
    String? id,
    String? sonarContent,
    String? signalCode,
    DateTime? expiresAt,
    DateTime? createdAt,
    List<Message>? messages,
    bool? unlocked,
    bool? deepConnectionAchieved,
    bool? deepConnectionConfirmed,
    bool? bothDeepConfirmed,
    bool? savedConnection,
    bool? mySaveConfirmed,
    bool? bothSaveConfirmed,
    UserProfile? otherProfile,
    String? lastReadMessageId,
    String? peerReadMessageId,
  }) {
    return ChatRoom(
      id: id ?? this.id,
      sonarContent: sonarContent ?? this.sonarContent,
      signalCode: signalCode ?? this.signalCode,
      expiresAt: expiresAt ?? this.expiresAt,
      createdAt: createdAt ?? this.createdAt,
      messages: messages ?? this.messages,
      unlocked: unlocked ?? this.unlocked,
      deepConnectionAchieved:
          deepConnectionAchieved ?? this.deepConnectionAchieved,
      deepConnectionConfirmed:
          deepConnectionConfirmed ?? this.deepConnectionConfirmed,
      bothDeepConfirmed: bothDeepConfirmed ?? this.bothDeepConfirmed,
      savedConnection: savedConnection ?? this.savedConnection,
      mySaveConfirmed: mySaveConfirmed ?? this.mySaveConfirmed,
      bothSaveConfirmed: bothSaveConfirmed ?? this.bothSaveConfirmed,
      otherProfile: otherProfile ?? this.otherProfile,
      lastReadMessageId: lastReadMessageId ?? this.lastReadMessageId,
      peerReadMessageId: peerReadMessageId ?? this.peerReadMessageId,
    );
  }
}

class UserProfile {
  final String signature;
  final String city;
  final String contact;

  const UserProfile({
    required this.signature,
    required this.city,
    required this.contact,
  });
}
