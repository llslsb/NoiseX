class Constants {
  Constants._();

  // 开源默认：指向本机自建后端（Android 模拟器用 10.0.2.2 访问宿主机 127.0.0.1；
  // 真机调试改回局域网 IP）。自建后换成你的域名，REST 与 WebSocket 同域（Nginx TLS 反代 127.0.0.1:7070）。
  static const String apiBaseUrl = 'http://10.0.2.2:7070';
  static const String wsUrl = 'ws://10.0.2.2:7070/ws';

  static const int sonarMaxLength = 140;
  static const int sonarMaxPerHour = 3;
  static const int sonarCooldownSeconds = 60;

  static const int roomLifetimeHours = 72;
  static const int roomExpiringThresholdHours = 12;
  static const int unlockWindowHours = 24;
  static const int deepConnectionTotalThreshold = 20;
  static const int deepConnectionPerUserThreshold = 5;
  static const int deepConnectionMinMessageLength = 5;

  /// 深度交流总数阈值（圆环/提示语口径）。
  ///
  /// 对齐鸿蒙端 DEEP_CONNECTION_THRESHOLD 与服务端 unlock-threshold-messages：
  /// 两者均为 20（总数 ≥20 且双方各 ≥5）。此前误别名到 PerUserThreshold(5)，
  /// 导致聊天页圆环显示 "N/5"、提示语按 5 计算，与底部"你再发 N 条/对方再发
  /// N 条"（按双方各 5）口径互相矛盾。
  static const int deepConnectionThreshold = deepConnectionTotalThreshold;

  static const int defaultGeohashPrecision = 6;

  static const double pulseButtonSize = 160;
  static const double radarSize = 320;
  static const double tabBarHeight = 64;
  static const double chatHeaderHeight = 56;
  static const double inputHeight = 40;
  static const double progressBarWidth = 256;

  static const int radarSpinDuration = 4000;
  static const int pingDuration = 2000;
  static const int fadeInUpDuration = 300;

  static const String prefsName = 'noisex_prefs';
  static const String prefsKeyPushEnabled = 'push_enabled';

  /// 上次成功上报的推送 token（存 "channel:token"，token 变化才重新上报）
  static const String prefsKeyPushReportedToken = 'push_reported_token';

  /// 通知授权状态（granted / refused / unknown，OHOS requestEnableNotification 结果）
  static const String prefsKeyNotificationAuth = 'notification_auth_state';

  /// 首启《用户协议》《隐私政策》同意标记（版本化键）。
  ///
  /// 政策重大变更时把 vN 加一，老用户下次启动会重新弹出协议门、重新确认。
  /// v2（2026-11-06）：改自建网页版隐私政策——补处理者真名、保存的片段（明文）、日志信息、
  /// 华为推送第三方服务、存储地点与重置身份删除范围。
  static const String prefsKeyPrivacyAgreed = 'privacy_agreed_v2';

  /// 收听模式开关（true=收听 / false=静默），重启后沿用用户上次的选择。
  ///
  /// 2026-11-06 修：原先不持久化，每次启动默认开启并静默登记收听，用户关掉也白关。
  /// 新装默认开启（读取时 defaultValue: true）。
  static const String prefsKeyListeningEnabled = 'listening_enabled';
  static const String dbName = 'noisex.db';
}
