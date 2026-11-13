import { MessageData } from './ApiTypes';

// 消息数据模型（独立文件，供 ChatRoom 引用）
//
// 与计划文档 docs/superpowers/plans/2026-06-15-ux-revamp.md P1 delivered 协议对齐：
// - delivered: 服务端在对方在线时回送（type=delivered），客户端将 sent → delivered
// - read:     收到 read_receipt 后将 delivered → read（已存在）
// 字段 delivered 为可选，存量代码无需迁移
export interface Message {
  id: string;
  roomId: string;
  sender: 'me' | 'other';
  content: string;
  timestamp: number;
  read: boolean;
  encrypted: boolean;
  delivered?: boolean;
}

export function toLocalMessage(apiMessage: MessageData, roomId: string, peerReadMessageId: string): Message {
  const isMine: boolean = apiMessage.sender === 'me';
  return {
    id: apiMessage.id,
    roomId: roomId,
    sender: isMine ? 'me' : 'other',
    content: apiMessage.content,
    timestamp: apiMessage.timestamp,
    read: isMine && peerReadMessageId.length > 0 && apiMessage.id.localeCompare(peerReadMessageId) <= 0,
    encrypted: true
  };
}

export function getMessageBubbleRenderKey(message: Message): string {
  const stateTag: string = message.read ? 'read' : (message.delivered === true ? 'deliv' : 'unread');
  return `${message.id}:${stateTag}`;
}

/**
 * 收到服务端 delivered 事件时，把对应的 me 消息标记为 delivered。
 *
 * 与计划文档 docs/superpowers/plans/2026-06-15-ux-revamp.md P1 delivered 协议对齐：
 * - 仅修改 sender==='me' && id===messageId 的那一条
 * - 已 read 的不回退（保持优先级 read > delivered > sent）
 */
export function applyDeliveredReceipt(messages: Message[], messageId: string): Message[] {
  if (messageId.length === 0) return messages;
  let touched: boolean = false;
  const updated: Message[] = [];
  for (let i: number = 0; i < messages.length; i++) {
    const m: Message = messages[i];
    if (m.sender === 'me' && m.id === messageId && m.read !== true && m.delivered !== true) {
      touched = true;
      updated.push({
        id: m.id,
        roomId: m.roomId,
        sender: m.sender,
        content: m.content,
        timestamp: m.timestamp,
        read: m.read,
        encrypted: m.encrypted,
        delivered: true
      });
    } else {
      updated.push(m);
    }
  }
  return touched ? updated : messages;
}

export function applyPeerReadReceipt(messages: Message[], messageId: string): Message[] {
  let found: boolean = false;
  const updatedMessages: Message[] = [];
  for (let i: number = 0; i < messages.length; i++) {
    const msg: Message = messages[i];
    if (msg.id === messageId) {
      found = true;
    }
    if (msg.sender === 'me' && !msg.read && msg.id.localeCompare(messageId) <= 0) {
      const updated: Message = {
        id: msg.id,
        roomId: msg.roomId,
        sender: msg.sender,
        content: msg.content,
        timestamp: msg.timestamp,
        read: true,
        encrypted: msg.encrypted,
        delivered: msg.delivered
      };
      updatedMessages.push(updated);
    } else {
      updatedMessages.push(msg);
    }
  }
  return found ? updatedMessages : messages;
}

export function replaceLatestLocalMessageId(messages: Message[], serverMessageId: string, encrypted: boolean | null = null): Message[] {
  if (serverMessageId.length === 0) return messages;
  for (let i: number = 0; i < messages.length; i++) {
    if (messages[i].id === serverMessageId) return messages;
  }
  for (let i: number = messages.length - 1; i >= 0; i--) {
    const msg: Message = messages[i];
    if (msg.sender === 'me' && msg.id.indexOf('local-') === 0) {
      const updatedMessages: Message[] = [];
      for (let j: number = 0; j < messages.length; j++) {
        const current: Message = messages[j];
        if (j === i) {
          updatedMessages.push({
            id: serverMessageId,
            roomId: current.roomId,
            sender: current.sender,
            content: current.content,
            timestamp: current.timestamp,
            read: current.read,
            encrypted: encrypted ?? current.encrypted
          });
        } else {
          updatedMessages.push(current);
        }
      }
      return updatedMessages;
    }
  }
  return messages;
}
