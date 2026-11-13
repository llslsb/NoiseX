// API 响应通用结构
export interface ApiResponse<T> {
  code: number;
  data: T | null;
  message: string;
}

// 服务端时间响应
export interface ServerTimeData {
  serverTime: number;
}

// 认证响应
export interface AuthData {
  token: string;
  expiresIn: number;
}

// 声呐发送响应
export interface SonarSendData {
  sonarId: string;
  remainingQuota: number;
}

// 收到的声呐
export interface ReceivedSonarData {
  id: string;
  content: string;
  distance: string;
  timestamp: number;
}

// 响应声呐结果
export interface AcceptSonarData {
  roomId: string;
  signalCode: string;
  sonarContent: string;
  expiresAt: number;
}

// 消息项
export interface MessageData {
  id: string;
  sender: string;
  content: string;
  timestamp: number;
}

// 房间项
export interface RoomData {
  id: string;
  signalCode: string;
  sonarContent: string;
  lastMessage: MessageData | null;
  createdAt: number;
  expiresAt: number;
  unlocked: boolean;
  deepConnectionAchieved: boolean;
  deepConnectionConfirmed: boolean;
  bothDeepConfirmed?: boolean;
  saveConnectionConfirmed: boolean;
  bothSaveConfirmed?: boolean;
  messageCount: number;
  lastReadMessageId?: string;
  peerReadMessageId?: string;
}

// 消息列表响应
export interface MessagesData {
  messages: MessageData[];
  hasMore: boolean;
}

// 解锁资料响应
export interface UnlockData {
  unlocked: boolean;
  profile: ProfileData | null;
}

// 资料卡数据
export interface ProfileData {
  signature: string | null;
  city: string | null;
  contact: string | null;
}

// 保存连接响应
export interface SaveConnectionData {
  status: string;
  message: string;
}

// 举报响应
export interface ReportData {
  reportId: string;
}

// ========== 请求体 ==========

export interface RegisterRequest {
  anonymousUuid: string;
}

export interface SendSonarRequest {
  content: string;
  geohash: string;
}

export interface SaveConnectionRequestBody {
  agree: boolean;
}

export interface UpdateProfileRequest {
  signature: string;
  city: string;
  contact: string;
}

export interface ReportRequest {
  roomId: string;
  reason: string;
  phoneNumber: string;
}

// 临终保存片段
export interface SavedMomentData {
  id: string;
  roomId: string;
  content: string;
  createdAt: number;
}

export interface SaveMomentRequest {
  roomId: string;
  content: string;
}

// 附近活跃用户数（雷达 blip 真实化）
export interface NearbyActivityData {
  // 模糊化后的附近活跃用户数（不含自己），已经过最小阈值/上限处理
  nearbyCount: number;
  // 雷达动画展示的 blip 数（0..8，已 clamp 到 UI 友好范围）
  blipCount: number;
}

// F1-1：解锁资料异步结果（仅客户端使用，不参与 API 序列化）。
//
// 修复用户反馈 bug：聊天页点击 "解锁资料" / "保存连接" 没有任何反馈，
// 现把 Index.handleUnlock 的 Promise<void> 改为 Promise<UnlockResult>，
// 让 ChatPage 能根据 ok/err 切换 in-flight → success/error 三阶段反馈。
//
// 与计划文档 docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F1-4 对齐。
export interface UnlockResult {
  ok: boolean;
  profile?: ProfileData;
  errorMessage?: string;
}

// F1-1：保存连接异步结果（仅客户端使用，不参与 API 序列化）。
export interface SaveResult {
  ok: boolean;
  errorMessage?: string;
}

