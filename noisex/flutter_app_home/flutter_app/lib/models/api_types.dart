class ApiResponse<T> {
  final int code;
  final String message;
  final T? data;

  const ApiResponse({this.code = 0, this.message = '', this.data});

  bool get isSuccess => code == 0;
}

class AuthData {
  final String token;
  final int expiresIn;

  const AuthData({required this.token, required this.expiresIn});
}

class SonarSendData {
  final String sonarId;
  final int remainingQuota;

  const SonarSendData({required this.sonarId, required this.remainingQuota});
}

class ReceivedSonarData {
  final String id;
  final String content;
  final String distance;
  final int timestamp;

  const ReceivedSonarData({
    required this.id,
    required this.content,
    required this.distance,
    required this.timestamp,
  });
}

class AcceptSonarData {
  final String roomId;
  final String signalCode;
  final String sonarContent;
  final int expiresAt;

  const AcceptSonarData({
    required this.roomId,
    required this.signalCode,
    required this.sonarContent,
    required this.expiresAt,
  });
}

class RoomData {
  final String id;
  final String signalCode;
  final String sonarContent;
  final MessageData? lastMessage;
  final int expiresAt;
  final int createdAt;
  final bool unlocked;
  final bool deepConnectionAchieved;
  final bool deepConnectionConfirmed;
  final bool bothDeepConfirmed;
  final bool savedConnection;
  final bool mySaveConfirmed;
  final bool bothSaveConfirmed;
  final int messageCount;
  final String lastReadMessageId;

  /// 对方已读指针（RoomResponse.peerReadMessageId）：重进聊天/刷新列表时
  /// 恢复气泡 ✓✓ 用（服务端重建的消息列表不带 isRead）。
  final String peerReadMessageId;

  const RoomData({
    required this.id,
    required this.signalCode,
    required this.sonarContent,
    this.lastMessage,
    required this.expiresAt,
    this.createdAt = 0,
    this.unlocked = false,
    this.deepConnectionAchieved = false,
    this.deepConnectionConfirmed = false,
    this.bothDeepConfirmed = false,
    this.savedConnection = false,
    this.mySaveConfirmed = false,
    this.bothSaveConfirmed = false,
    this.messageCount = 0,
    this.lastReadMessageId = '',
    this.peerReadMessageId = '',
  });
}

class ServerTimeData {
  final int serverTime;

  const ServerTimeData({required this.serverTime});
}

class MessageData {
  final String id;
  final String sender;
  final String content;
  final int timestamp;

  const MessageData({
    required this.id,
    required this.sender,
    required this.content,
    required this.timestamp,
  });
}

class MessagesData {
  final List<MessageData> messages;
  final bool hasMore;

  const MessagesData({required this.messages, this.hasMore = false});
}

class UnlockData {
  final bool unlocked;
  final ProfileData? profile;

  const UnlockData({required this.unlocked, this.profile});
}

class SaveConnectionData {
  final String status;
  final String message;

  const SaveConnectionData({required this.status, required this.message});
}

class ProfileData {
  final String signature;
  final String city;
  final String contact;

  const ProfileData({required this.signature, required this.city, required this.contact});
}

class ReportData {
  final String reportId;

  const ReportData({required this.reportId});
}

class NearbyActivityData {
  final int nearbyCount;
  final int blipCount;

  const NearbyActivityData({required this.nearbyCount, required this.blipCount});
}

class SavedMomentData {
  final String id;
  final String roomId;
  final String content;
  final int createdAt;

  const SavedMomentData({
    required this.id,
    required this.roomId,
    required this.content,
    required this.createdAt,
  });
}

/// F1-1：解锁资料异步结果（仅客户端使用，不参与 API 序列化）。
///
/// 修复用户反馈 bug：聊天页点击 "解锁资料" / "保存连接" 没有任何反馈，
/// 现把 `_handleUnlock` 的 `Future<void>` 改为 `Future<UnlockResult>`，
/// 让 ChatPage 能根据 ok/err 切换 in-flight → success/error 三阶段反馈。
///
/// 与计划文档 docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F1-1 对齐。
class UnlockResult {
  final bool ok;
  final ProfileData? profile;
  final String? errorMessage;
  const UnlockResult.ok(this.profile)
      : ok = true,
        errorMessage = null;
  const UnlockResult.err(this.errorMessage)
      : ok = false,
        profile = null;
}

/// F1-1：保存连接异步结果（仅客户端使用，不参与 API 序列化）。
class SaveResult {
  final bool ok;
  final String? errorMessage;
  const SaveResult.ok()
      : ok = true,
        errorMessage = null;
  const SaveResult.err(this.errorMessage) : ok = false;
}
