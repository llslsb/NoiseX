/// F2-3：解析 WS peer_left 事件 payload 的纯函数。
///
/// 设计动机：`_handleWsPeerLeft` 处于 `_MainPageState` 内部，依赖 `setState` /
/// PushService / CryptoService / StorageService 等单例，做 widget 集成测试成本很高。
/// 把"payload → 用户可见字段"的纯映射抽出到此工具，可在不构造 widget 树的前提下
/// 通过单元测试验证：
/// - 通知文案不会出现 `undefined` / `null`（修复用户反馈 bug：离开房间提示中的对方为
///   `undefined`）。
/// - 缺 `roomId` 时早期返回，不触发副作用。
/// - signalCode 兜底为 "对方"。
///
/// 对应计划 docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F2-3。
String roomExpiredNotificationBody(String roomId) => '对话已风干，散入夜空';

class PeerLeftEvent {
  /// 房间 ID。空字符串表示 payload 不完整，调用方应忽略本事件。
  final String roomId;

  /// 对方匿名 signalCode（如 `RX-1234`）。即便 payload 里缺失也保证非空——
  /// 兜底为 "对方"，避免推送/通知出现 `undefined` 文案。
  final String signalCode;

  /// 对方离开时刻（毫秒时间戳）。缺失或非数字时为 0。
  final int leftAt;

  /// 通知 body 文案。当 [signalCode] 来自服务端时形如 `RX-1234 已离开对话`，
  /// 兜底情况形如 `对方 已离开对话`，永远不会渲染 `undefined / null`。
  String get notificationBody => '$signalCode 已离开对话';

  /// payload 是否足够触发副作用（仅依赖 [roomId] 是否非空）。
  bool get isValid => roomId.isNotEmpty;

  const PeerLeftEvent({
    required this.roomId,
    required this.signalCode,
    required this.leftAt,
  });

  /// 从 WS payload Map 解析，所有字段都做防御性兜底。
  factory PeerLeftEvent.fromPayload(Map<String, dynamic> data) {
    final roomId = (data['roomId'] as String?) ?? '';
    final rawSignal = (data['signalCode'] as String?) ?? '';
    final signalCode = rawSignal.isNotEmpty ? rawSignal : '对方';
    final leftAt = (data['leftAt'] is num)
        ? (data['leftAt'] as num).toInt()
        : 0;
    return PeerLeftEvent(
      roomId: roomId,
      signalCode: signalCode,
      leftAt: leftAt,
    );
  }
}
