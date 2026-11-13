// F2-3/F2-4：解析 WS peer_left 事件 payload 的纯函数。
//
// 设计动机：WsService.handleMessage 是 private 且依赖 WebSocket 实例，做集成测试成本很高。
// 把 "payload → 用户可见字段" 的纯映射抽出到此工具，可在不构造 WebSocket 的前提下
// 通过单元测试验证：
// - 通知/Toast 文案不会出现 `undefined` / `null`（修复用户反馈 bug：离开房间提示中的对方为 undefined）。
// - 缺 roomId 时早期返回，不触发副作用。
// - signalCode 兜底为 "对方"。
//
// 与 Flutter 端 lib/utils/peer_left_parser.dart 行为一致。
// 对应计划 docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F2-3/F2-4。

export interface PeerLeftEvent {
  // 房间 ID。空字符串表示 payload 不完整，调用方应忽略本事件。
  roomId: string;
  // 对方匿名 signalCode（如 RX-1234）。即便 payload 里缺失也保证非空——
  // 兜底为 "对方"，避免推送/通知出现 undefined 文案。
  signalCode: string;
  // 对方离开时刻（毫秒时间戳）。缺失或非数字时为 0。
  leftAt: number;
}

// 从 WS payload 解析，所有字段都做防御性兜底。
export function parsePeerLeftPayload(msg: Record<string, Object>): PeerLeftEvent {
  const roomId: string = (msg['roomId'] as string) ?? '';
  const rawSignalCode: string = (msg['signalCode'] as string) ?? '';
  const signalCode: string = rawSignalCode.length > 0 ? rawSignalCode : '对方';
  const rawLeftAt: Object | undefined = msg['leftAt'];
  const leftAt: number = (typeof rawLeftAt === 'number') ? rawLeftAt as number : 0;
  return { roomId, signalCode, leftAt };
}

// payload 是否足够触发副作用（仅依赖 roomId 是否为真实房间 ID）。
export function isPeerLeftValid(ev: PeerLeftEvent): boolean {
  return ev.roomId.length > 0 && ev.roomId !== 'undefined';
}

// 通知 body 文案。当 signalCode 来自服务端时形如 "RX-1234 已离开对话"，
// 兜底情况形如 "对方 已离开对话"，永远不会渲染 undefined / null。
export function getPeerLeftNotificationBody(ev: PeerLeftEvent): string {
  return `${ev.signalCode} 已离开对话`;
}
