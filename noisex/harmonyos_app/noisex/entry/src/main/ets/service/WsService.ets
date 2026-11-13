import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AuthService } from './AuthService';
import { Logger } from '../common/Logger';
import { Constants } from '../model/Constants';
import { parsePeerLeftPayload, isPeerLeftValid, PeerLeftEvent } from '../model/PeerLeftEvent';

// WebSocket 实时通信服务
export class WsService {
  private static instance: WsService;
  private ws: webSocket.WebSocket | null = null;
  private isConnected: boolean = false;
  private isConnecting: boolean = false;
  private heartbeatTimer: number = -1;
  private reconnectTimer: number = -1;
  private reconnectAttempts: number = 0;
  private intentionalDisconnect: boolean = false;
  private static readonly HEARTBEAT_INTERVAL: number = 30000; // 30秒心跳
  private static readonly RECONNECT_BASE_DELAY: number = 1000; // 初始1秒
  private static readonly RECONNECT_MAX_DELAY: number = 30000; // 最大30秒
  private static readonly RECONNECT_MAX_ATTEMPTS: number = 10; // 最多重试10次

  // 消息回调
  public onMessageReceived: ((roomId: string, messageId: string, content: string, sender: string) => void) | null = null;
  public onMatched: ((roomId: string, signalCode: string, sonarContent: string) => void) | null = null;
  public onRoomExpired: ((roomId: string) => void) | null = null;
  // F2-2/F2-4：对方主动离开房间。区别于 room_expired（TTL 自然到期，双方都收），
  // peer_left 仅留下的一端收，使用 signalCode（非 userId）保护匿名身份。
  // 与计划文档 docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F2 对齐。
  public onPeerLeft: ((roomId: string, signalCode: string, leftAt: number) => void) | null = null;
  public onDeepConfirmed: ((roomId: string, deepConnectionConfirmed: boolean, bothDeepConfirmed: boolean, unlocked: boolean) => void) | null = null;
  public onSaveRequest: ((roomId: string, fromSignalCode: string) => void) | null = null;
  public onSaveConfirmed: ((roomId: string) => void) | null = null;
  public onSaveRefused: ((roomId: string) => void) | null = null;
  public onRoomExpiring: ((roomId: string, remainingHours: number) => void) | null = null;
  public onConnectionChanged: ((connected: boolean) => void) | null = null;
  public onReadReceipt: ((roomId: string, messageId: string) => void) | null = null;
  public onKeyExchange: ((roomId: string, pubKey: string) => void) | null = null;
  public onSonarReceived: (() => void) | null = null;
  public onReconnected: (() => void) | null = null;
  public onError: ((action: string, roomId: string, message: string) => void) | null = null;
  // P1-A 协议接入：与计划文档 docs/superpowers/plans/2026-06-15-ux-revamp.md P1 typing/delivered 对齐
  public onTypingStart: ((roomId: string, sender: string) => void) | null = null;
  public onTypingStop: ((roomId: string, sender: string) => void) | null = null;
  public onDelivered: ((roomId: string, messageId: string) => void) | null = null;
  // B17 sent_ack：服务端流 id 回填本端乐观消息（'local-' 前缀）专用通道
  public onSentAck: ((roomId: string, messageId: string) => void) | null = null;
  private hasConnectedBefore: boolean = false;

  private constructor() {}

  public static getInstance(): WsService {
    if (!WsService.instance) {
      WsService.instance = new WsService();
    }
    return WsService.instance;
  }

  public connect(): void {
    if (this.isConnected && this.ws !== null) return;
    if (this.isConnecting) {
      Logger.info('[WsService] Connect already in progress, skipping');
      return;
    }
    this.isConnecting = true;
    this.intentionalDisconnect = false;

    const token: string = AuthService.getInstance().getToken();
    if (token.length === 0) {
      Logger.warn('[WsService] No token available, skip connect');
      this.isConnecting = false;
      return;
    }

    this.ws = webSocket.createWebSocket();
    const url: string = `${Constants.WS_URL}?token=${token}`;

    this.ws.on('open', () => {
      const isReconnect: boolean = this.hasConnectedBefore;
      this.isConnected = true;
      this.isConnecting = false;
      this.hasConnectedBefore = true;
      this.reconnectAttempts = 0;
      Logger.info('[WsService] Connected');
      if (this.onConnectionChanged) {
        this.onConnectionChanged(true);
      }
      this.startHeartbeat();
      if (isReconnect && this.onReconnected) {
        this.onReconnected();
      }
    });

    this.ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (err) return;
      const msg: string = typeof value === 'string' ? value : '';
      if (msg.length > 0) {
        this.handleMessage(msg);
      }
    });

    this.ws.on('close', () => {
      this.isConnected = false;
      this.isConnecting = false;
      this.stopHeartbeat();
      Logger.info('[WsService] Disconnected');
      if (this.onConnectionChanged) {
        this.onConnectionChanged(false);
      }
      if (!this.intentionalDisconnect) {
        this.scheduleReconnect();
      }
    });

    this.ws.on('error', (err: BusinessError) => {
      this.isConnecting = false;
      Logger.error(`[WsService] Error: ${err.message}`);
      // 连接失败（从未 open）不会触发 close 事件，error 路径必须同样续上重连链，
      // 否则服务端重启期间首次重连失败后重连链永久断裂，客户端永远停在"正在重连"
      if (!this.intentionalDisconnect && !this.isConnected) {
        this.scheduleReconnect();
      }
    });

    this.ws.connect(url, (err: BusinessError, value: boolean) => {
      if (err) {
        this.isConnecting = false;
        Logger.error(`[WsService] Connect failed: ${err.message}`);
        // 同上：connect 回调失败也需续上重连链（scheduleReconnect 幂等防重入）
        if (!this.intentionalDisconnect) {
          this.scheduleReconnect();
        }
      }
    });
  }

  public disconnect(): void {
    this.intentionalDisconnect = true;
    this.isConnected = false;
    this.isConnecting = false;
    this.stopHeartbeat();
    this.cancelReconnect();
    if (this.ws !== null) {
      try {
        this.ws.close();
      } catch (e) {
        Logger.error('[WsService] Close error');
      }
      this.ws = null;
    }
  }

  public reconnect(): void {
    this.disconnect();
    setTimeout(() => {
      this.connect();
    }, 1000);
  }

  // 发送聊天消息
  public sendChatMessage(roomId: string, content: string): void {
    if (this.ws === null || !this.isConnected) return;
    const payload: Record<string, Object> = {
      'type': 'chat' as Object,
      'roomId': roomId as Object,
      'content': content as Object
    };
    try {
      this.ws.send(JSON.stringify(payload));
    } catch (e) {
      Logger.error('[WsService] Send chat error');
    }
  }

  // 确认深度交流
  public confirmDeepConnection(roomId: string): void {
    if (this.ws === null || !this.isConnected) return;
    const payload: Record<string, Object> = {
      'type': 'deep_confirm' as Object,
      'roomId': roomId as Object
    };
    try {
      this.ws.send(JSON.stringify(payload));
    } catch (e) {
      Logger.error('[WsService] Send deep_confirm error');
    }
  }

  // 发送已读回执
  public sendReadReceipt(roomId: string, messageId: string): void {
    if (this.ws === null || !this.isConnected) return;
    const payload: Record<string, Object> = {
      'type': 'read' as Object,
      'roomId': roomId as Object,
      'messageId': messageId as Object
    };
    try {
      this.ws.send(JSON.stringify(payload));
    } catch (e) {
      Logger.error('[WsService] Send read receipt error');
    }
  }

  // 发送密钥交换（公钥）
  public sendKeyExchange(roomId: string, pubKey: string): void {
    if (this.ws === null || !this.isConnected) return;
    const payload: Record<string, Object> = {
      'type': 'key_exchange' as Object,
      'roomId': roomId as Object,
      'pubKey': pubKey as Object
    };
    try {
      this.ws.send(JSON.stringify(payload));
    } catch (e) {
      Logger.error('[WsService] Send key exchange error');
    }
  }

  // 发送 typing 信令（不持久化，4s 后客户端自行清除）。
  // 与计划文档 docs/superpowers/plans/2026-06-15-ux-revamp.md P1 typing 协议对齐。
  public sendTyping(roomId: string, isStart: boolean): void {
    if (this.ws === null || !this.isConnected) return;
    const payload: Record<string, Object> = {
      'type': (isStart ? 'typing_start' : 'typing_stop') as Object,
      'roomId': roomId as Object
    };
    try {
      this.ws.send(JSON.stringify(payload));
    } catch (e) {
      Logger.error('[WsService] Send typing error');
    }
  }

  // 发送心跳
  public sendPing(): void {
    if (this.ws === null || !this.isConnected) return;
    const payload: Record<string, Object> = {
      'type': 'ping' as Object
    };
    try {
      this.ws.send(JSON.stringify(payload));
    } catch (e) {
      Logger.error('[WsService] Send ping error');
    }
  }

  // 启动心跳定时器
  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      this.sendPing();
    }, WsService.HEARTBEAT_INTERVAL);
  }

  // 停止心跳定时器
  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  // 调度自动重连（指数退避）
  private scheduleReconnect(): void {
    // 防重入：error 与 close 可能先后到达，已挂起的重连定时器不重复调度
    if (this.reconnectTimer !== -1) {
      return;
    }
    if (this.reconnectAttempts >= WsService.RECONNECT_MAX_ATTEMPTS) {
      Logger.warn('[WsService] Max reconnect attempts reached, will retry on network restore');
      // 达上限后每 30 秒尝试一次，等待网络恢复
      this.reconnectTimer = setTimeout(() => {
        this.reconnectAttempts = WsService.RECONNECT_MAX_ATTEMPTS - 1;
        this.reconnectTimer = -1;
        this.connect();
      }, 30000);
      return;
    }
    this.cancelReconnect();
    const delay: number = WsService.computeReconnectDelay(this.reconnectAttempts);
    this.reconnectAttempts++;
    Logger.info(`[WsService] Reconnect in ${delay}ms (attempt ${this.reconnectAttempts})`);
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = -1;
      this.connect();
    }, delay);
  }

  // 取消重连定时器
  private cancelReconnect(): void {
    if (this.reconnectTimer !== -1) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = -1;
    }
  }

  // 重连退避延迟：1s 起指数翻倍，封顶 30s。独立成纯函数便于单测
  static computeReconnectDelay(attempts: number): number {
    return Math.min(
      WsService.RECONNECT_BASE_DELAY * Math.pow(2, attempts),
      WsService.RECONNECT_MAX_DELAY
    );
  }

  public getIsConnected(): boolean {
    return this.isConnected;
  }

  // 重连计数观察口：供 ohosTest 断言重连链是否延续（回归 9f96bba 修复的 error/连接失败路径）
  public getReconnectAttempts(): number {
    return this.reconnectAttempts;
  }

  private handleMessage(raw: string): void {
    try {
      const msg: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const type: string = (msg['type'] as string) ?? '';

      switch (type) {
        case 'chat':
          if (this.onMessageReceived) {
            this.onMessageReceived(
              (msg['roomId'] as string) ?? '',
              (msg['messageId'] as string) ?? '',
              (msg['content'] as string) ?? '',
              (msg['sender'] as string) ?? ''
            );
          }
          break;
        case 'sent_ack':
          // B17：发送确认帧携带服务端流 id，供本端乐观消息（'local-' 前缀）对账。
          // 不对账则 delivered/read 回执按流 id 精确匹配永远失配。
          if (this.onSentAck) {
            this.onSentAck(
              (msg['roomId'] as string) ?? '',
              (msg['messageId'] as string) ?? ''
            );
          }
          break;
        case 'matched':
          if (this.onMatched) {
            const matchedRoomId: string = (msg['roomId'] as string) ?? '';
            const matchedSignalCode: string = (msg['signalCode'] as string) ?? '';
            const matchedSonarContent: Object | undefined = msg['sonarContent'];
            const sonarText: string = (matchedSonarContent !== null && matchedSonarContent !== undefined) ?
              (matchedSonarContent as string) : '';
            this.onMatched(matchedRoomId, matchedSignalCode, sonarText);
          }
          break;
        case 'room_expired':
          if (this.onRoomExpired) {
            this.onRoomExpired((msg['roomId'] as string) ?? '');
          }
          break;
        case 'peer_left':
          // F2-4：对方主动离开。signalCode 缺失时兜底为 "对方"，保证 Toast/通知文案不出现 undefined / null。
          // 解析逻辑抽到 PeerLeftEvent.ets 便于单测覆盖（与 Flutter peer_left_parser.dart 对齐）。
          if (this.onPeerLeft) {
            const peerLeftEvent: PeerLeftEvent = parsePeerLeftPayload(msg);
            if (isPeerLeftValid(peerLeftEvent)) {
              this.onPeerLeft(peerLeftEvent.roomId, peerLeftEvent.signalCode, peerLeftEvent.leftAt);
            }
          }
          break;
        case 'deep_confirmed':
          if (this.onDeepConfirmed) {
            const bothDeepConfirmed: boolean = (msg['bothDeepConfirmed'] as boolean) ?? ((msg['bothConfirmed'] as boolean) ?? false);
            this.onDeepConfirmed(
              (msg['roomId'] as string) ?? '',
              (msg['deepConnectionConfirmed'] as boolean) ?? bothDeepConfirmed,
              bothDeepConfirmed,
              (msg['unlocked'] as boolean) ?? bothDeepConfirmed
            );
          }
          break;
        case 'save_request':
          if (this.onSaveRequest) {
            this.onSaveRequest(
              (msg['roomId'] as string) ?? '',
              (msg['fromSignalCode'] as string) ?? ''
            );
          }
          break;
        case 'save_confirmed':
          if (this.onSaveConfirmed) {
            this.onSaveConfirmed((msg['roomId'] as string) ?? '');
          }
          break;
        case 'save_refused':
          if (this.onSaveRefused) {
            this.onSaveRefused((msg['roomId'] as string) ?? '');
          }
          break;
        case 'room_expiring':
          if (this.onRoomExpiring) {
            this.onRoomExpiring(
              (msg['roomId'] as string) ?? '',
              (msg['remainingHours'] as number) ?? 0
            );
          }
          break;
        case 'read_receipt':
          if (this.onReadReceipt) {
            this.onReadReceipt(
              (msg['roomId'] as string) ?? '',
              (msg['messageId'] as string) ?? ''
            );
          }
          break;
        case 'key_exchange':
          if (this.onKeyExchange) {
            this.onKeyExchange(
              (msg['roomId'] as string) ?? '',
              (msg['pubKey'] as string) ?? ''
            );
          }
          break;
        case 'sonar_received':
          Logger.info('[WsService] Received sonar notification');
          if (this.onSonarReceived) {
            this.onSonarReceived();
          }
          break;
        case 'typing_start':
          if (this.onTypingStart) {
            this.onTypingStart(
              (msg['roomId'] as string) ?? '',
              (msg['sender'] as string) ?? ''
            );
          }
          break;
        case 'typing_stop':
          if (this.onTypingStop) {
            this.onTypingStop(
              (msg['roomId'] as string) ?? '',
              (msg['sender'] as string) ?? ''
            );
          }
          break;
        case 'delivered':
          if (this.onDelivered) {
            this.onDelivered(
              (msg['roomId'] as string) ?? '',
              (msg['messageId'] as string) ?? ''
            );
          }
          break;
        case 'pong':
          Logger.info('[WsService] Received pong');
          break;
        case 'error':
          if (this.onError) {
            this.onError(
              (msg['action'] as string) ?? '',
              (msg['roomId'] as string) ?? '',
              (msg['message'] as string) ?? ''
            );
          }
          break;
      }
    } catch (e) {
      Logger.error(`[WsService] Parse error`);
    }
  }
}
