import { UserProfile } from './UserProfile';
import { Message } from './Message';

// 对话房间数据模型
export interface ChatRoom {
  id: string;
  sonarContent: string;
  signalCode: string;
  createdAt: number;
  expiresAt: number;
  messages: Message[];
  unlocked: boolean;
  deepConnectionAchieved: boolean;
  deepConnectionConfirmed: boolean;
  bothDeepConfirmed: boolean;
  saveConnectionConfirmed: boolean;
  bothSaveConfirmed: boolean;
  otherProfile: UserProfile | null;
  lastReadMessageId: string;
  peerReadMessageId: string;
}

export function getDeepConnectionStatusText(achieved: boolean, confirmed: boolean, bothConfirmed: boolean, unlocked: boolean): string {
  if (unlocked) return '✓ 资料已解锁';
  if (bothConfirmed) return '✓ 双方已确认';
  if (confirmed) return '✓ 已确认，等待对方';
  if (achieved) return '✓ 已达成，待确认';
  return '需双方各5条消息';
}

// UI 评审 P1 §6-3：资料改底部半模态 sheet 后只有"查看资料"一个动作
// （Flutter ChatHeaderBar 同步改）
export function getProfileButtonText(): string {
  return '查看资料';
}

// UI 评审 P0 §6-1：空值改拟人化空态"TA 还没有留下X"——解锁换来的
// 不该是三个"未填写"（Flutter chat_info_panel.dart 同文案逐字对齐）
export function getProfileDisplayValue(label: string, value: string): string {
  return value.length > 0 ? value : `TA 还没有留下${label}`;
}

export function getSaveConnectionStatusText(saveConnectionConfirmed: boolean, bothSaveConfirmed: boolean): string {
  if (bothSaveConfirmed) return '连接已保存';
  if (saveConnectionConfirmed) return '等待对方确认';
  return '保存连接';
}

export function canSaveConnection(saveConnectionConfirmed: boolean, bothSaveConfirmed: boolean): boolean {
  return !saveConnectionConfirmed && !bothSaveConfirmed;
}

export function canUnlockProfile(unlocked: boolean, bothDeepConfirmed: boolean, unlockWindowAvailable: boolean,
  createdAt: number): boolean {
  const hasCreatedAt: boolean = createdAt > 0;
  return !unlocked && bothDeepConfirmed && unlockWindowAvailable && hasCreatedAt && isUnlockWindowAvailable(createdAt);
}

export function canRequestSaveConnection(unlocked: boolean, saveConnectionConfirmed: boolean,
  bothSaveConfirmed: boolean): boolean {
  return unlocked && canSaveConnection(saveConnectionConfirmed, bothSaveConfirmed);
}

export function applyServerSaveState(room: ChatRoom, saveConnectionConfirmed: boolean, bothSaveConfirmed: boolean): void {
  room.saveConnectionConfirmed = saveConnectionConfirmed;
  room.bothSaveConfirmed = bothSaveConfirmed;
}

export function normalizeProfileField(value: string | null | undefined): string {
  return value ?? '';
}

export function shouldFetchUnlockedProfile(unlocked: boolean, hasProfile: boolean): boolean {
  return unlocked && !hasProfile;
}

export function shouldShowSaveConfirmedPrompt(roomExists: boolean, wasBothSaveConfirmed: boolean): boolean {
  return roomExists && !wasBothSaveConfirmed;
}

export function getUnreadMessageCount(messages: Message[], lastReadMessageId: string): number {
  let count: number = 0;
  for (let i: number = 0; i < messages.length; i++) {
    const msg: Message = messages[i];
    if (msg.sender === 'other' && (lastReadMessageId.length === 0 || msg.id.localeCompare(lastReadMessageId) > 0)) {
      count++;
    }
  }
  return count;
}

export function getRoomCardRenderKey(room: ChatRoom): string {
  const lastMessageId: string = room.messages.length > 0 ? room.messages[room.messages.length - 1].id : '';
  return `${room.id}:${room.lastReadMessageId}:${getUnreadMessageCount(room.messages, room.lastReadMessageId)}:${lastMessageId}:${room.saveConnectionConfirmed}:${room.bothSaveConfirmed}`;
}

// 24h 解锁窗口相关
const UNLOCK_WINDOW_MS: number = 24 * 3600 * 1000;

export function isUnlockWindowAvailable(createdAt: number): boolean {
  return getNow() < createdAt + UNLOCK_WINDOW_MS;
}

export function getUnlockWindowRemainingMs(createdAt: number): number {
  const deadline: number = createdAt + UNLOCK_WINDOW_MS;
  const remaining: number = deadline - getNow();
  return remaining > 0 ? remaining : 0;
}

// 服务端时间偏移 — offset = serverTime - localTime，getServerTime() = Date.now() + offset
let serverTimeOffset: number = 0;

export function setServerTimeOffset(offset: number): void {
  serverTimeOffset = offset;
}

export function getServerTimeOffset(): number {
  return serverTimeOffset;
}

export function getNow(): number {
  return Date.now() + serverTimeOffset;
}
