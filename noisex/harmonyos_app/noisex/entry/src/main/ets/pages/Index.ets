import { SonarPage } from './SonarPage';
import { ReceiverPage } from './ReceiverPage';
import { HourglassPage } from './HourglassPage';
import { ChatPage } from './ChatPage';
import { SplashPage } from './SplashPage';
import { ProfilePage } from './ProfilePage';
import { ReportPage } from './ReportPage';
import { BlockedListPage } from './BlockedListPage';
import { TabBar } from '../components/TabBar';
import { Sonar } from '../model/Sonar';
import { ChatRoom, applyServerSaveState, getUnreadMessageCount, normalizeProfileField, shouldFetchUnlockedProfile, shouldShowSaveConfirmedPrompt, setServerTimeOffset } from '../model/ChatRoom';
import { Message, applyPeerReadReceipt, applyDeliveredReceipt, replaceLatestLocalMessageId, toLocalMessage } from '../model/Message';
import { ReceivedSonarData, RoomData, MessageData, NearbyActivityData, UnlockResult, SaveResult } from '../model/ApiTypes';
import { WsService } from '../service/WsService';
import { ApiService } from '../service/ApiService';
import { AuthService } from '../service/AuthService';
import { LocationService } from '../service/LocationService';
import { StorageService } from '../service/StorageService';
import { CryptoService } from '../service/CryptoService';
import { PushService } from '../service/PushService';
import { RitualAnimationService, FirstPulseAnimation, FirstMatchAnimation, WitheringAnimation } from '../service/RitualAnimationService';
import { HapticService } from '../service/HapticService';
import { Utils } from '../common/Utils';
import { getFriendlyErrorMessage, mapApiErrorToFriendly } from '../common/ApiErrorMessages';
import { Constants } from '../model/Constants';
import { shouldStartListening } from '../model/ListeningRegistration';
import { Logger } from '../common/Logger';
import { promptAction } from '@kit.ArkUI';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { USER_AGREEMENT_TEXT, USER_AGREEMENT_TITLE, PRIVACY_POLICY_TEXT, PRIVACY_POLICY_TITLE, getAgreementHighlights } from '../model/AgreementTexts';
import EntryAbility from '../entryability/EntryAbility';

export interface NavRoomParam {
  roomId: string;
  sonarContent: string;
  signalCode: string;
  createdAt: number;
  expiresAt: number;
  unlocked: boolean;
  deepConnectionAchieved: boolean;
  deepConnectionConfirmed: boolean;
  bothDeepConfirmed: boolean;
  saveConnectionConfirmed: boolean;
  bothSaveConfirmed: boolean;
  otherSignature: string;
  otherCity: string;
  otherContact: string;
}

export interface ChatController {
  onLeave: (roomId: string) => void;
  // F1-5：返回 Promise<UnlockResult>，让 ChatPage 可以根据 ok/err 切换三阶段反馈。
  onUnlock: (roomId: string) => Promise<UnlockResult>;
  // F1-5：返回 Promise<SaveResult>，forceConfirm=true 用于自动同意保存请求。
  onSave: (roomId: string, forceConfirm?: boolean) => Promise<SaveResult>;
  onReport: (roomId: string) => void;
  onConfirmDeep: (roomId: string) => void;
  onMarkRead: (roomId: string, messageId: string) => void;
  onBlock: (roomId: string) => void;
  onSaveMoment: (roomId: string, content: string) => void;
  getMessages: (roomId: string) => Message[];
  addMessage: (roomId: string, msg: Message) => void;
  getRoomState: (roomId: string) => RoomState | null;
}

export interface RoomState {
  unlocked: boolean;
  deepConnectionAchieved: boolean;
  deepConnectionConfirmed: boolean;
  bothDeepConfirmed: boolean;
  saveConnectionConfirmed: boolean;
  bothSaveConfirmed: boolean;
  otherSignature: string;
  otherCity: string;
  otherContact: string;
}

@Builder
function NavDestinationBuilder(name: string, param: Object) {
  if (name === 'Profile') {
    ProfilePage();
  } else if (name === 'Report') {
    // UI 评审 P0：界面只显示匿名信号码，内部 roomId 不再上屏
    //（@Builder 内不允许局部变量声明，直接内联取参）
    ReportPage({
      roomId: (param as Record<string, string>)['roomId'] ?? '',
      signalCode: (param as Record<string, string>)['signalCode'] ?? ''
    });
  } else if (name === 'Chat') {
    ChatPage({ navParam: param as NavRoomParam });
  } else if (name === 'BlockedList') {
    BlockedListPage();
  }
}

@Entry
@Component
struct Index {
  @State showSplash: boolean = true;
  // 首启隐私协议授权门（华为审核：首启须弹出《用户协议》与《隐私政策》，
  // 同意才能使用；bindContentCover 全屏模态 + onWillDismiss 拦截返回绕过）
  @State showPrivacyCover: boolean = false;
  // 协议门内视图切换：'' = 摘要门 | 'user'/'privacy' = 对应全文（单层模态内自导航，
  // 避免弹窗套弹窗；全文不可走 NavPathStack push——会被全屏模态盖住）
  @State privacyDocName: string = '';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  // F3-2：activeTab: string('sonar'|'receiver'|'hourglass') → activeTabIndex: number(0|1|2)，
  // 与 ArkUI Tabs/TabContent 的 index 协议对齐，使 TabBar 切换走系统 Tabs 平滑过渡（250ms）。
  @State activeTabIndex: number = 0;
  private tabsController: TabsController = new TabsController();
  @State receivedSonars: Sonar[] = [];
  @StorageLink('chatRooms') chatRooms: ChatRoom[] = [];
  @Provide('navPathStack') navPathStack: NavPathStack = new NavPathStack();
  @State isWsConnected: boolean = false;
  @State isOffline: boolean = false;
  @State sonarCooldown: number = 0;
  @StorageLink('pushNavigateRoomId') pushNavigateRoomId: string = '';
  private sonarCooldownTimer: number = -1;
  private roomIndexMap: Record<string, number> = {};
  // P1-B：typing 4s 超时定时器（防对方掉线导致 typing 状态滞留）
  private typingTimeouts: Map<string, number> = new Map<string, number>();

  // P2-A：仪式感动效状态
  @State showFirstPulse: boolean = false;
  @State showFirstMatch: boolean = false;
  @State showWithering: boolean = false;
  @State witheringRoomId: string = '';
  @State sendingSonar: boolean = false;  // TASK-003: 发送脉冲 loading 态
  // P2-B：附近活跃用户数（雷达 blip 真实化）
  @State nearbyCount: number = 0;   // 附近活跃用户数（真实计数）
  @State nearbyLoaded: boolean = false;  // 是否已加载过（false=探测中，true 后 0 也如实显示）
  @State blipCount: number = 0;     // 雷达信号点数量（0..8，随真实计数，无占位假点）
  private nearbyActivityTimer: number = -1;
  private listeningGeohash: string = '';
  private listeningOperationId: number = 0;
  private saveConfirmingRoomIds: Set<string> = new Set<string>();

  aboutToAppear(): void {
    AppStorage.setOrCreate<ChatRoom[]>('chatRooms', []);
    const listeningEnabled: boolean | undefined = AppStorage.get<boolean>('sonarListeningEnabled');
    if (listeningEnabled === undefined) {
      AppStorage.setOrCreate<boolean>('sonarListeningEnabled', true);
    }
    this.setupChatController();
    this.setupWsCallbacks();
    this.setupLocationCallbacks();
    this.listenPushNavigation();
    this.initStatusBarHeight();
  }

  private setupChatController(): void {
    const controller: ChatController = {
      onLeave: (roomId: string) => { this.handleLeaveRoom(roomId); },
      // F1-5：直接 return Promise，让 ChatPage 拿到 UnlockResult/SaveResult 渲染三阶段反馈。
      onUnlock: (roomId: string): Promise<UnlockResult> => this.handleUnlock(roomId),
      onSave: (roomId: string, forceConfirm?: boolean): Promise<SaveResult> => this.handleSave(roomId, forceConfirm ?? false),
      onReport: (roomId: string) => {
        // UI 评审 P0：界面只显示匿名信号码，内部 roomId 不再上屏
        const room: ChatRoom | null = this.findRoom(roomId);
        const param: Record<string, string> = {
          'roomId': roomId,
          'signalCode': room !== null ? room.signalCode : ''
        };
        this.navPathStack.pushPathByName('Report', param);
      },
      onConfirmDeep: (roomId: string) => { this.handleConfirmDeep(roomId); },
      onMarkRead: (roomId: string, messageId: string) => {
        const room: ChatRoom | null = this.findRoom(roomId);
        if (room !== null) {
          room.lastReadMessageId = messageId;
          this.chatRooms = this.chatRooms.concat();
        }
        WsService.getInstance().sendReadReceipt(roomId, messageId);
      },
      onBlock: (roomId: string) => { this.handleBlock(roomId); },
      onSaveMoment: (roomId: string, content: string) => {
        this.handleSaveMoment(roomId, content);
      },
      getMessages: (roomId: string): Message[] => {
        const room: ChatRoom | null = this.findRoom(roomId);
        return room?.messages ?? [];
      },
      addMessage: (roomId: string, msg: Message): void => {
        const room: ChatRoom | null = this.findRoom(roomId);
        if (room !== null) {
          room.messages = room.messages.concat(msg);
          this.chatRooms = this.chatRooms.concat();
          StorageService.getInstance().saveMessage(
            msg.id, msg.roomId, msg.sender, msg.content, msg.timestamp
          ).catch(() => {});
        }
      },
      getRoomState: (roomId: string): RoomState | null => {
        const room: ChatRoom | null = this.findRoom(roomId);
        if (room === null) return null;
        return {
          unlocked: room.unlocked,
          deepConnectionAchieved: room.deepConnectionAchieved,
          deepConnectionConfirmed: room.deepConnectionConfirmed,
          bothDeepConfirmed: room.bothDeepConfirmed,
          saveConnectionConfirmed: room.saveConnectionConfirmed,
          bothSaveConfirmed: room.bothSaveConfirmed,
          otherSignature: room.otherProfile?.signature ?? '',
          otherCity: room.otherProfile?.city ?? '',
          otherContact: room.otherProfile?.contact ?? ''
        } as RoomState;
      }
    };
    AppStorage.setOrCreate<ChatController>('chatController', controller);
  }

  private setupLocationCallbacks(): void {
    LocationService.getInstance().onGeohashChanged = (geohash: string) => {
      const token: string = AuthService.getInstance().getToken();
      const listeningEnabled: boolean = AppStorage.get<boolean>('sonarListeningEnabled') ?? true;
      if (token.length > 0 && listeningEnabled) {
        void this.startListeningAt(geohash, false);
      }
    };
  }

  // AGC UX 检测（2026-09-20）：底部 Tab 文字落入系统导航条区（避让 <28vp 判不通过）。
  // 全屏沉浸（layoutFullScreen）下系统不做自动避让，底部固定控件必须自行抬升，
  // 高度来源 = 窗口避让区 TYPE_NAVIGATION_INDICATOR（底部导航条/手势指示条）。
  private avoidAreaChangeCallback: ((info: window.AvoidAreaOptions) => void) | null = null;

  private refreshAvoidAreas(win: window.Window): void {
    const sysArea: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
    const sysPx: number = sysArea.topRect.height;
    AppStorage.setOrCreate<number>('statusBarHeight', sysPx > 0 ? px2vp(sysPx) : 48);
    const indicator: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);
    const bottomPx: number = indicator.bottomRect.height;
    // +4vp 余量：保证控件底边明确高于导航条判定线，深色底继续延伸到条下保持沉浸
    AppStorage.setOrCreate<number>('bottomAvoidHeight', bottomPx > 0 ? px2vp(bottomPx) + 4 : 32);
  }

  private initStatusBarHeight(): void {
    try {
      const win: window.Window = window.findWindow('EntryAbility');
      this.refreshAvoidAreas(win);
      // 折叠屏展开收起、导航条形态切换时系统派发 avoidAreaChange，同步刷新两个避让高度
      this.avoidAreaChangeCallback = (info: window.AvoidAreaOptions) => {
        try {
          this.refreshAvoidAreas(window.findWindow('EntryAbility'));
        } catch (err) {
          Logger.error(`[Index] Refresh avoid area failed: ${err}`);
        }
      };
      win.on('avoidAreaChange', this.avoidAreaChangeCallback);
    } catch (e) {
      Logger.error(`[Index] Get status bar height failed: ${e}`);
      AppStorage.setOrCreate<number>('statusBarHeight', 48);
      AppStorage.setOrCreate<number>('bottomAvoidHeight', 32);
    }
  }

  aboutToDisappear(): void {
    if (this.avoidAreaChangeCallback !== null) {
      try {
        window.findWindow('EntryAbility').off('avoidAreaChange', this.avoidAreaChangeCallback);
      } catch (e) {
        Logger.error(`[Index] Off avoidAreaChange failed: ${e}`);
      }
      this.avoidAreaChangeCallback = null;
    }
    WsService.getInstance().disconnect();
    LocationService.getInstance().onGeohashChanged = null;
    LocationService.getInstance().stopLocation();
    if (this.nearbyActivityTimer !== -1) {
      clearInterval(this.nearbyActivityTimer);
      this.nearbyActivityTimer = -1;
    }
  }

  private setupWsCallbacks(): void {
    const ws: WsService = WsService.getInstance();

    ws.onMessageReceived = (roomId: string, messageId: string, content: string, sender: string) => {
      Logger.info(`[Index] WS message received: roomId=${roomId}, messageId=${messageId}, sender=${sender}, contentLen=${content.length}`);
      const room: ChatRoom | null = this.findRoom(roomId);
      if (room === null) {
        Logger.warn(`[Index] Room not found for message, roomId=${roomId}, rooms=${this.chatRooms.length}`);
        this.refreshRooms();
        return;
      }

      // E2EE: 尝试解密
      const decryptPromise: Promise<string> = CryptoService.getInstance().decrypt(roomId, content);
      decryptPromise.then((decrypted: string) => {
        this.applyIncomingChatMessage(room, roomId, messageId, sender, decrypted, true);
      }).catch(() => {
        Logger.warn('[Index] Decrypt message failed, showing raw content');
        this.applyIncomingChatMessage(room, roomId, messageId, sender, content, false);
      });
    };

    ws.onMatched = (roomId: string, signalCode: string, sonarContent: string) => {
      Logger.info(`[Index] Matched: roomId=${roomId}, signalCode=${signalCode}, sonarContent=${sonarContent}`);
      // 防重复：handleAcceptSonar 可能已经添加过同一房间
      const existing: ChatRoom | null = this.findRoom(roomId);
      if (existing !== null) {
        Logger.info(`[Index] Matched: room ${roomId} already exists, skip duplicate add`);
        return;
      }
      const newRoom: ChatRoom = {
        id: roomId,
        sonarContent: sonarContent,
        signalCode: signalCode,
        createdAt: Date.now(),
        expiresAt: Date.now() + Constants.ROOM_LIFETIME_HOURS * 60 * 60 * 1000,
        messages: [],
        unlocked: false,
        deepConnectionAchieved: false,
        deepConnectionConfirmed: false,
        bothDeepConfirmed: false,
        saveConnectionConfirmed: false,
        bothSaveConfirmed: false,
        otherProfile: null,
        lastReadMessageId: '',
        peerReadMessageId: ''
      };
      this.chatRooms = this.chatRooms.concat(newRoom);
      this.rebuildRoomIndex();

      // 匹配成功本地通知
      PushService.getInstance().notifyMatched(roomId, signalCode);

      // P2-A：匹配成功时触发双 ping 撞击动效（受仪式动效开关控制）
      RitualAnimationService.getInstance().isRitualAnimationEnabled().then((enabled: boolean) => {
        if (enabled) {
          this.showFirstMatch = true;
        }
      });

      // 发起 E2EE 密钥交换
      CryptoService.getInstance().generateKeyPair(roomId).then((pubKey: string) => {
        if (pubKey.length > 0) {
          WsService.getInstance().sendKeyExchange(roomId, pubKey);
        }
      }).catch(() => {
        Logger.error('[Index] Key exchange init failed');
      });
    };

    ws.onRoomExpired = (roomId: string) => {
      if (roomId.length === 0 || roomId === 'undefined') {
        Logger.warn(`[Index] Ignore room_expired with invalid roomId: ${roomId}`);
        return;
      }
      // P2-A：风干仪式动效（受仪式动效开关控制）
      RitualAnimationService.getInstance().isRitualAnimationEnabled().then((enabled: boolean) => {
        if (enabled) {
          this.showWithering = true;
          this.witheringRoomId = roomId;
        }
      });

      this.chatRooms = this.chatRooms.filter((r: ChatRoom) => r.id !== roomId);
      this.rebuildRoomIndex();
      CryptoService.getInstance().clearRoomKey(roomId);
      StorageService.getInstance().deleteRoomMessages(roomId).catch(() => {});
      if (this.navPathStack.size() > 0) {
        this.navPathStack.pop();
      }
      promptAction.showToast({ message: '对话已过期' });
    };

    // F2-4：对方主动离开（区别于 room_expired TTL 自然到期，TTL 双方都收，peer_left 仅留下方收）。
    // 复用风干仪式动效与房间清理路径，但 Toast 文案使用 signalCode 兜底（WsService 已兜底为 "对方"），
    // 修复用户反馈 bug：之前 toast/通知出现 "undefined 已离开"。
    // 与计划文档 docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F2-4 对齐。
    ws.onPeerLeft = (roomId: string, signalCode: string, leftAt: number) => {
      if (roomId.length === 0 || roomId === 'undefined') {
        Logger.warn(`[Index] Ignore peer_left with invalid roomId: ${roomId}`);
        return;
      }
      RitualAnimationService.getInstance().isRitualAnimationEnabled().then((enabled: boolean) => {
        if (enabled) {
          this.showWithering = true;
          this.witheringRoomId = roomId;
        }
      });

      this.chatRooms = this.chatRooms.filter((r: ChatRoom) => r.id !== roomId);
      this.rebuildRoomIndex();
      CryptoService.getInstance().clearRoomKey(roomId);
      StorageService.getInstance().deleteRoomMessages(roomId).catch(() => {});
      if (this.navPathStack.size() > 0) {
        this.navPathStack.pop();
      }
      promptAction.showToast({ message: `${signalCode} 已离开` });
    };

    ws.onDeepConfirmed = (roomId: string, deepConnectionConfirmed: boolean, bothDeepConfirmed: boolean, unlocked: boolean) => {
      const room: ChatRoom | null = this.findRoom(roomId);
      if (room !== null) {
        room.deepConnectionAchieved = true;
        if (deepConnectionConfirmed) {
          room.deepConnectionConfirmed = true;
        }
        if (bothDeepConfirmed) {
          room.bothDeepConfirmed = true;
          room.unlocked = unlocked;
          void this.handleUnlock(roomId);
          PushService.getInstance().notifyDeepConfirmed(roomId);
        }
        this.chatRooms = this.chatRooms.concat();
      }
    };

    ws.onSaveRequest = (roomId: string, fromSignalCode: string) => {
      const saveRoomId: string = roomId;
      // 如果当前用户已发起保存，说明双方都点了保存，直接自动同意，不弹窗
      const room: ChatRoom | null = this.findRoom(roomId);
      if (room === null || room.bothSaveConfirmed) return;
      if (room.saveConnectionConfirmed) {
        Logger.info(`[Index] Save request: already confirmed, auto-accept for room ${roomId}`);
        void this.handleSave(saveRoomId, true);
        return;
      }
      PushService.getInstance().notifySaveRequest(roomId, fromSignalCode);
      this.getUIContext().getPromptAction().showDialog({
        title: '保存连接请求',
        message: `${fromSignalCode} 希望与你保存连接，同意吗？`,
        buttons: [
          { text: '拒绝', color: '#999999' },
          { text: '同意', color: '#FF6B35' }
        ]
      }, (err, data) => {
        if (err) {
          Logger.error(`[Index] Save confirm dialog error: ${err.message}`);
          return;
        }
        if (data.index === 1) {
          void this.handleSave(saveRoomId);
        } else {
          void this.handleSaveRefuse(saveRoomId);
        }
      });
    };

    ws.onSaveConfirmed = (roomId: string) => {
      Logger.info(`[Index] Connection saved confirmed for room ${roomId}`);
      const room: ChatRoom | null = this.findRoom(roomId);
      const shouldShowPrompt: boolean = shouldShowSaveConfirmedPrompt(room !== null, room?.bothSaveConfirmed ?? false);
      if (room !== null) {
        room.saveConnectionConfirmed = true;
        room.bothSaveConfirmed = true;
        this.chatRooms = this.chatRooms.concat();
      }
      if (shouldShowPrompt) {
        promptAction.showToast({ message: '连接已保存' });
      }
    };

    ws.onSaveRefused = (roomId: string) => {
      Logger.info(`[Index] Save connection refused for room ${roomId}`);
      promptAction.showToast({ message: '对方拒绝了保存连接' });
    };

    ws.onRoomExpiring = (roomId: string, remainingHours: number) => {
      Logger.info(`[Index] Room ${roomId} expiring in ${remainingHours.toFixed(1)}h`);
      promptAction.showToast({ message: `对话即将过期，剩余 ${remainingHours.toFixed(1)} 小时` });
      PushService.getInstance().notifyRoomExpiring(roomId, remainingHours);
    };

    ws.onReadReceipt = (roomId: string, messageId: string) => {
      const room: ChatRoom | null = this.findRoom(roomId);
      if (room === null) return;
      const updatedMessages: Message[] = applyPeerReadReceipt(room.messages, messageId);
      if (updatedMessages === room.messages) {
        // applyPeerReadReceipt 的 found 守卫：指针消息不在本端列表（如本端发送的
        // 消息 id 尚未对账为流 id）时返回原数组。留日志便于排查"自己消息不翻已读"。
        Logger.warn(`[Index] read_receipt no-op: roomId=${roomId}, messageId=${messageId} (pointer message not found in local list)`);
        return;
      }
      room.peerReadMessageId = messageId;
      room.messages = updatedMessages;
      this.chatRooms = this.chatRooms.concat();
    };

    // B17 sent_ack：服务端流 id 回填本端乐观消息（'local-' 前缀）。不对账则
    // delivered/read 回执按流 id 精确匹配永远失配，自己发的消息永远停在单 ✓。
    ws.onSentAck = (roomId: string, messageId: string) => {
      const room: ChatRoom | null = this.findRoom(roomId);
      if (room === null) return;
      const updatedMessages: Message[] =
        replaceLatestLocalMessageId(room.messages, messageId, null);
      if (updatedMessages === room.messages) {
        Logger.warn(`[Index] sent_ack no-op: roomId=${roomId}, messageId=${messageId} (no local- id message to reconcile)`);
        return;
      }
      room.messages = updatedMessages;
      this.chatRooms = this.chatRooms.concat();
    };

    // P1-B：服务端在对方在线时回 delivered，把对应 me 消息标记为 delivered
    ws.onDelivered = (roomId: string, messageId: string) => {
      const room: ChatRoom | null = this.findRoom(roomId);
      if (room === null) return;
      const updated: Message[] = applyDeliveredReceipt(room.messages, messageId);
      if (updated === room.messages) return;
      room.messages = updated;
      this.chatRooms = this.chatRooms.concat();
    };

    // P1-B：服务端转发对方 typing 信令；写到 AppStorage 让 ChatPage 订阅展示
    // 同时 4s 自动清除（防止对方掉线导致 typing 状态滞留）
    ws.onTypingStart = (roomId: string, sender: string) => {
      AppStorage.setOrCreate<string>('peerTypingRoomId', roomId);
      this.scheduleTypingTimeout(roomId);
    };

    ws.onTypingStop = (roomId: string, sender: string) => {
      const current: string = AppStorage.get<string>('peerTypingRoomId') ?? '';
      if (current === roomId) {
        AppStorage.setOrCreate<string>('peerTypingRoomId', '');
      }
      this.cancelTypingTimeout(roomId);
    };

    ws.onKeyExchange = (roomId: string, pubKey: string) => {
      if (roomId.length === 0 || pubKey.length === 0) {
        return;
      }
      if (CryptoService.getInstance().hasKeyPair(roomId)) {
        // 双方同时发起：各持临时对，直接派生
        CryptoService.getInstance().deriveSharedKey(roomId, pubKey).then((ok: boolean) => {
          if (ok) {
            Logger.info(`[Index] E2EE key established for room ${roomId}`);
          }
        }).catch(() => {
          Logger.error('[Index] Key derivation failed');
        });
        return;
      }
      // B18：初次交换或一方丢钥（清数据/重装）——生成新对、回应公钥，
      // 并同轮用对方公钥派生新密钥。旧逻辑以 hasSharedKey 挡掉回应，
      // 持有密钥一方永不回公钥，丢钥方的重协商会永久死锁。
      CryptoService.getInstance().generateKeyPair(roomId).then((myPubKey: string) => {
        if (myPubKey.length > 0) {
          WsService.getInstance().sendKeyExchange(roomId, myPubKey);
        }
        CryptoService.getInstance().deriveSharedKey(roomId, pubKey).catch(() => {
          Logger.error('[Index] Key derivation failed on re-exchange');
        });
      }).catch(() => {
        Logger.error('[Index] Key re-exchange failed');
      });
    };

    ws.onConnectionChanged = (connected: boolean) => {
      this.isWsConnected = connected;
      this.isOffline = !connected;
    };

    ws.onSonarReceived = () => {
      Logger.info('[Index] Sonar received via WS');
      this.refreshReceivedSonars();
    };

    ws.onReconnected = () => {
      Logger.info('[Index] Reconnected — syncing data');
      void this.refreshListeningRegistration();
      this.refreshRooms();
      this.refreshReceivedSonars();
      if (this.navPathStack.size() > 0) {
        const allNames: string[] = this.navPathStack.getAllPathName();
        const topName: string = allNames[allNames.length - 1];
        if (topName === 'Chat') {
          const topParam: Object = this.navPathStack.getParamByIndex(this.navPathStack.size() - 1) as Object;
          const p: NavRoomParam = topParam as NavRoomParam;
          if (p.roomId !== undefined) {
            this.handleEnterRoom(p.roomId);
          }
        }
      }
    };

    ws.onError = (action: string, roomId: string, message: string) => {
      Logger.warn(`[Index] WS error: action=${action}, roomId=${roomId}, msg=${message}`);
      promptAction.showToast({ message: message, duration: 2000 });
      // 回滚被服务端拒绝的乐观消息（chat 发送被 RATE_LIMIT / 重复内容 / 长度等拒绝）。
      // 旧实现只 toast 不回滚，导致发送方列表残留"已发送 ✓"幽灵消息 + 互动数虚高，
      // 而接收方从未收到（服务端拒绝时不持久化、不推送）。这里删除该房间最后一条
      // local- 前缀的乐观消息，让计数和列表都回到发送前状态。
      if (action === 'chat' && roomId.length > 0) {
        this.rollbackLastOptimisticMessage(roomId);
      }
    };
  }

  /**
   * 回滚指定房间最后一条乐观插入的消息（id 以 'local-' 开头的 sender==='me' 消息）。
   *
   * <p>触发场景：服务端 sendMessage 抛异常（RATE_LIMIT "发送过快" / 重复内容 / 长度超限 /
   * 连续 5 条等），NoiseXWebSocketHandler 只回 type=error 给发送方，客户端必须主动移除
   * 那条已 concat 进 messageList 的幽灵消息，否则发送方互动数虚高、显示"已发送"却没人收到。
   */
  private rollbackLastOptimisticMessage(roomId: string): void {
    const room: ChatRoom | null = this.findRoom(roomId);
    if (room === null || room.messages.length === 0) return;
    let rollbackIndex: number = -1;
    for (let i: number = room.messages.length - 1; i >= 0; i--) {
      const m: Message = room.messages[i];
      if (m.sender === 'me' && m.id.indexOf('local-') === 0) {
        rollbackIndex = i;
        break;
      }
    }
    if (rollbackIndex < 0) return;
    const removedId: string = room.messages[rollbackIndex].id;
    const updated: Message[] = room.messages.slice();
    updated.splice(rollbackIndex, 1);
    room.messages = updated;
    this.chatRooms = this.chatRooms.concat();
    // 同步删除本地 SQLite 中的乐观记录（addMessage 时已持久化）
    StorageService.getInstance().deleteMessage(removedId).catch(() => {});
    Logger.info(`[Index] Rolled back optimistic message ${removedId} in room ${roomId}`);
  }

  private switchTab(index: number): void {
    if (index < 0 || index > 2 || index === this.activeTabIndex) {
      return;
    }
    this.tabsController.changeIndex(index);
  }

  private listenPushNavigation(): void {
    setInterval(() => {
      if (this.pushNavigateRoomId.length > 0) {
        const roomId: string = this.pushNavigateRoomId;
        this.pushNavigateRoomId = '';
        this.navigateToRoom(roomId);
        this.switchTab(2);
      }
    }, 500);
  }

  private navigateToRoom(roomId: string): void {
    const room: ChatRoom | null = this.findRoom(roomId);
    if (room === null) return;
    const param: NavRoomParam = {
      roomId: room.id,
      sonarContent: room.sonarContent,
      signalCode: room.signalCode,
      createdAt: room.createdAt,
      expiresAt: room.expiresAt,
      unlocked: room.unlocked,
      deepConnectionAchieved: room.deepConnectionAchieved,
      deepConnectionConfirmed: room.deepConnectionConfirmed,
      bothDeepConfirmed: room.bothDeepConfirmed,
      saveConnectionConfirmed: room.saveConnectionConfirmed,
      bothSaveConfirmed: room.bothSaveConfirmed,
      otherSignature: room.otherProfile?.signature ?? '',
      otherCity: room.otherProfile?.city ?? '',
      otherContact: room.otherProfile?.contact ?? ''
    };
    this.navPathStack.pushPathByName('Chat', param);
  }

  private isCurrentChatRoom(roomId: string): boolean {
    if (this.navPathStack.size() === 0) return false;
    const allNames: string[] = this.navPathStack.getAllPathName();
    const topName: string = allNames[allNames.length - 1];
    if (topName !== 'Chat') return false;
    const topParam: Object = this.navPathStack.getParamByIndex(this.navPathStack.size() - 1) as Object;
    const p: NavRoomParam = topParam as NavRoomParam;
    return p.roomId === roomId;
  }

  private applyIncomingChatMessage(room: ChatRoom, roomId: string, messageId: string, sender: string, content: string, encrypted: boolean): void {
    const resolvedMessageId: string = messageId.length > 0 ? messageId : Utils.generateId();
    for (let i: number = 0; i < room.messages.length; i++) {
      if (room.messages[i].id === resolvedMessageId) return;
    }

    if (sender === 'me') {
      const updatedMessages: Message[] = replaceLatestLocalMessageId(room.messages, resolvedMessageId, encrypted);
      if (updatedMessages !== room.messages) {
        room.messages = updatedMessages;
        this.chatRooms = this.chatRooms.concat();
        for (let i: number = 0; i < updatedMessages.length; i++) {
          if (updatedMessages[i].id === resolvedMessageId) {
            const msg: Message = updatedMessages[i];
            StorageService.getInstance().saveMessage(
              msg.id, msg.roomId, msg.sender, msg.content, msg.timestamp
            ).catch(() => {});
            break;
          }
        }
      }
      return;
    }

    const msg: Message = {
      id: resolvedMessageId,
      roomId: roomId,
      sender: 'other',
      content: content,
      timestamp: Date.now(),
      read: false,
      encrypted: encrypted
    };
    room.messages = room.messages.concat(msg);
    this.chatRooms = this.chatRooms.concat();
    StorageService.getInstance().saveMessage(
      msg.id, msg.roomId, msg.sender, msg.content, msg.timestamp
    ).catch(() => {});

    if (!this.isCurrentChatRoom(roomId)) {
      PushService.getInstance().notifyNewMessage(roomId, room.signalCode, content).catch(() => {});
    }
  }

  private findRoom(roomId: string): ChatRoom | null {
    const idx: number = this.roomIndexMap[roomId];
    if (idx !== undefined && idx >= 0 && idx < this.chatRooms.length && this.chatRooms[idx].id === roomId) {
      return this.chatRooms[idx];
    }
    // fallback: 线性查找并修复索引
    for (let i: number = 0; i < this.chatRooms.length; i++) {
      if (this.chatRooms[i].id === roomId) {
        this.roomIndexMap[roomId] = i;
        return this.chatRooms[i];
      }
    }
    return null;
  }

  /**
   * P1-B：4 秒后自动清除"对方正在输入"状态。
   *
   * 服务端不持久化 typing 状态；如果对方掉线或 typing_stop 信令丢失，
   * 客户端必须自行兜底，避免 typing 状态滞留导致 UI 错觉。
   */
  private scheduleTypingTimeout(roomId: string): void {
    this.cancelTypingTimeout(roomId);
    const timerId: number = setTimeout(() => {
      const current: string = AppStorage.get<string>('peerTypingRoomId') ?? '';
      if (current === roomId) {
        AppStorage.setOrCreate<string>('peerTypingRoomId', '');
      }
      this.typingTimeouts.delete(roomId);
    }, 4000);
    this.typingTimeouts.set(roomId, timerId);
  }

  private cancelTypingTimeout(roomId: string): void {
    const t: number | undefined = this.typingTimeouts.get(roomId);
    if (t !== undefined) {
      clearTimeout(t);
      this.typingTimeouts.delete(roomId);
    }
  }

  private rebuildRoomIndex(): void {
    this.roomIndexMap = {};
    for (let i: number = 0; i < this.chatRooms.length; i++) {
      this.roomIndexMap[this.chatRooms[i].id] = i;
    }
  }

  private handleListeningChanged(enabled: boolean): void {
    if (enabled) {
      const geohash: string = LocationService.getInstance().getGeohash();
      // 2026-11-02 幽灵格子修复：定位未就绪时绝不兜底注册——
      // 原 `|| Constants.DEFAULT_GEOHASH`（北京 wx4g0s）把无 fix 的设备
      // 静默注册进错误格子（真机"漂到北京"实锤根因）。
      // 等 onGeohashChanged 首个真实 fix 到达后再注册。
      if (geohash.length === 0) {
        Logger.warn('[Index] Listening enabled but no location fix yet; defer registration');
        return;
      }
      void this.startListeningAt(geohash, false);
      return;
    }
    void this.stopListening();
  }

  private async stopListening(): Promise<void> {
    this.listeningOperationId++;
    const operationId: number = this.listeningOperationId;
    const previousGeohash: string = this.listeningGeohash;
    this.listeningGeohash = '';
    if (previousGeohash.length === 0) return;
    try {
      await ApiService.getInstance().stopListening(previousGeohash);
    } catch (e) {
      if (operationId === this.listeningOperationId) {
        Logger.warn(`[Index] Stop listening failed: ${previousGeohash}`);
      }
    }
  }

  private async refreshListeningRegistration(): Promise<void> {
    const listeningEnabled: boolean = AppStorage.get<boolean>('sonarListeningEnabled') ?? true;
    if (!listeningEnabled) return;
    const geohash: string = LocationService.getInstance().getGeohash();
    // 幽灵格子修复：无真实 fix 不重注册（等 onGeohashChanged 真实值）
    if (geohash.length === 0) {
      Logger.warn('[Index] Refresh listening skipped: no location fix yet');
      return;
    }
    await this.startListeningAt(geohash, true);
  }

  private async startListeningAt(geohash: string, force: boolean): Promise<void> {
    if (!shouldStartListening(this.listeningGeohash, geohash, force)) return;
    this.listeningOperationId++;
    const operationId: number = this.listeningOperationId;
    const previousGeohash: string = force ? '' : this.listeningGeohash;
    this.listeningGeohash = geohash;
    if (previousGeohash.length > 0) {
      try {
        await ApiService.getInstance().stopListening(previousGeohash);
      } catch (e) {
        Logger.warn(`[Index] Stop previous listening failed: ${previousGeohash}`);
      }
    }
    if (operationId !== this.listeningOperationId) return;
    try {
      await ApiService.getInstance().startListening(geohash);
      if (operationId === this.listeningOperationId) {
        Logger.info(`[Index] Start listening at ${geohash}`);
        // geohash 生效后启动附近活跃用户数轮询（雷达 blip 真实化）
        this.startNearbyActivityPolling();
      }
    } catch (e) {
      if (operationId === this.listeningOperationId) {
        this.listeningGeohash = '';
        Logger.error('[Index] Start listening failed');
      }
    }
  }

  // P2-B：附近活跃用户数周期轮询（30s），geohash 生效/变化/重连时重置
  private startNearbyActivityPolling(): void {
    if (this.nearbyActivityTimer !== -1) {
      clearInterval(this.nearbyActivityTimer);
    }
    this.nearbyActivityTimer = setInterval(() => {
      this.refreshNearbyActivity();
    }, 30000);
    this.refreshNearbyActivity();
  }

  private async refreshNearbyActivity(): Promise<void> {
    const geohash: string = this.listeningGeohash;
    if (geohash.length === 0) return;
    const token: string = AuthService.getInstance().getToken();
    if (token.length === 0) return;
    try {
      const data: NearbyActivityData | null = await ApiService.getInstance().getNearbyActivity(geohash);
      if (data !== null) {
        this.nearbyCount = data.nearbyCount;
        this.blipCount = data.blipCount;
        this.nearbyLoaded = true;
      }
    } catch (e) {
      Logger.warn(`[Index] Refresh nearby activity failed: ${e}`);
    }
  }

  private async handleSonarSent(content: string): Promise<void> {
    if (this.sendingSonar) return;  // TASK-003: 防抖，防止重复点击
    this.sendingSonar = true;

    // TASK-003: 触觉反馈（立即，提供响应感知）
    HapticService.getInstance().light();

    try {
      const geohash: string = LocationService.getInstance().getGeohash();
      // 幽灵格子修复：无真实 fix 禁止发送声呐——声呐按 geohash 匹配，
      // 兜底格子会把声呐发到错误位置（原北京 wx4g0s 实锤）
      if (geohash.length === 0) {
        promptAction.showToast({ message: '正在定位中，请稍后再试', duration: 1500 });
        this.sendingSonar = false;
        return;
      }
      const result = await ApiService.getInstance().sendSonar(content, geohash);
      if (result.code === 0 && result.data !== null) {
        Logger.info('[Index] Sonar sent successfully');
        this.refreshReceivedSonars();
        this.startSonarCooldown();

        // 成功反馈：Toast（先于仪式动效，提供即时确认）
        promptAction.showToast({ message: '声纳已发送', duration: 1200 });

        // P2-A：发送声呐时触发全屏脉冲动效（受仪式动效开关控制）
        const animEnabled = await RitualAnimationService.getInstance().isRitualAnimationEnabled();
        if (animEnabled) {
          setTimeout(() => {
            this.showFirstPulse = true;
          }, 200);
        }
      } else {
        HapticService.getInstance().selection();
        promptAction.showToast({ message: mapApiErrorToFriendly(result.code, result.message) });
      }
    } finally {
      this.sendingSonar = false;
    }
  }

  private startSonarCooldown(): void {
    if (this.sonarCooldownTimer !== -1) {
      clearInterval(this.sonarCooldownTimer);
    }
    this.sonarCooldown = Constants.SONAR_COOLDOWN_SECONDS;
    this.sonarCooldownTimer = setInterval(() => {
      this.sonarCooldown--;
      if (this.sonarCooldown <= 0) {
        this.sonarCooldown = 0;
        if (this.sonarCooldownTimer !== -1) {
          clearInterval(this.sonarCooldownTimer);
          this.sonarCooldownTimer = -1;
        }
      }
    }, 1000);
  }

  // 接收声呐处理
  private async handleAcceptSonar(sonar: Sonar): Promise<void> {
    try {
      const result = await ApiService.getInstance().acceptSonar(sonar.id);
      this.receivedSonars = this.receivedSonars.filter((s: Sonar) => s.id !== sonar.id);
      // 防重复：WS onMatched 可能已经通过 matched 通知添加了同一房间
      const existing: ChatRoom | null = this.findRoom(result.roomId);
      if (existing === null) {
        const newRoom: ChatRoom = {
          id: result.roomId,
          sonarContent: result.sonarContent,
          signalCode: result.signalCode,
          createdAt: Date.now(),
          expiresAt: result.expiresAt,
          messages: [],
          unlocked: false,
          deepConnectionAchieved: false,
          deepConnectionConfirmed: false,
          bothDeepConfirmed: false,
          saveConnectionConfirmed: false,
          bothSaveConfirmed: false,
          otherProfile: null,
          lastReadMessageId: '',
          peerReadMessageId: ''
        };
        this.chatRooms = this.chatRooms.concat(newRoom);
        this.rebuildRoomIndex();
      }
      this.switchTab(2);

      // 发起 E2EE 密钥交换
      CryptoService.getInstance().generateKeyPair(result.roomId).then((pubKey: string) => {
        if (pubKey.length > 0) {
          WsService.getInstance().sendKeyExchange(result.roomId, pubKey);
        }
      }).catch(() => {
        Logger.error('[Index] Key exchange init failed on accept sonar');
      });
    } catch (e) {
      Logger.error(`[Index] Accept sonar failed: ${e}`);
    }
  }

  // 忽略声呐
  private async handleIgnoreSonar(sonarId: string): Promise<void> {
    try {
      await ApiService.getInstance().ignoreSonar(sonarId);
      this.receivedSonars = this.receivedSonars.filter((s: Sonar) => s.id !== sonarId);
    } catch (e) {
      Logger.error(`[Index] Ignore sonar failed: ${e}`);
    }
  }

  private async handleEnterRoom(roomId: string): Promise<void> {
    try {
      const roomData = await ApiService.getInstance().getRoom(roomId);
      const room: ChatRoom | null = this.findRoom(roomId);
      if (room !== null) {
        room.unlocked = roomData.unlocked;
        room.deepConnectionAchieved = roomData.deepConnectionAchieved;
        room.deepConnectionConfirmed = roomData.deepConnectionConfirmed;
        room.bothDeepConfirmed = roomData.bothDeepConfirmed ?? roomData.unlocked;
        applyServerSaveState(room, roomData.saveConnectionConfirmed, roomData.bothSaveConfirmed ?? false);
        room.expiresAt = roomData.expiresAt;
        room.lastReadMessageId = roomData.lastReadMessageId ?? room.lastReadMessageId;
        room.peerReadMessageId = roomData.peerReadMessageId ?? room.peerReadMessageId;
        this.chatRooms = this.chatRooms.concat();
        if (shouldFetchUnlockedProfile(room.unlocked, room.otherProfile !== null)) {
          await this.handleUnlock(roomId);
        }
      }

      const result = await ApiService.getInstance().getMessages(roomId, 0, 50);
      if (room !== null && result !== null && result !== undefined && result.messages !== undefined) {
        const converted: Message[] = this.convertMessages(result.messages, roomId, room.peerReadMessageId);
        // B16：服务端存的是 E2EE 密文，本地有共享密钥时逐条解密后再渲染/入库。
        // decrypt 失败（GCM 认证错/非 Base64 的明文历史）会原样返回，安全兜底。
        if (CryptoService.getInstance().hasSharedKey(roomId)) {
          for (let i: number = 0; i < converted.length; i++) {
            converted[i].content =
              await CryptoService.getInstance().decrypt(roomId, converted[i].content);
          }
        }
        room.messages = converted;
        this.chatRooms = this.chatRooms.concat();

        for (let i: number = 0; i < room.messages.length; i++) {
          const m: Message = room.messages[i];
          StorageService.getInstance().saveMessage(
            m.id, m.roomId, m.sender, m.content, m.timestamp
          ).catch(() => {});
        }
      }

      this.navigateToRoom(roomId);
    } catch (e) {
      Logger.warn(`[Index] Load messages from API failed, trying local cache: ${e}`);
      try {
        const resultSet = await StorageService.getInstance().getMessages(roomId);
        const room: ChatRoom | null = this.findRoom(roomId);
        try {
          if (room !== null && resultSet.rowCount > 0) {
            const cachedMessages: Message[] = [];
            while (resultSet.goToNextRow()) {
              const rawSender: string = resultSet.getString(2);
              const msg: Message = {
                id: resultSet.getString(0),
                roomId: resultSet.getString(1),
                sender: rawSender === 'me' ? 'me' : 'other',
                content: resultSet.getString(3),
                timestamp: resultSet.getLong(4),
                read: false,
                encrypted: true
              };
              cachedMessages.push(msg);
            }
            room.messages = cachedMessages;
            this.chatRooms = this.chatRooms.concat();
          }
        } finally {
          resultSet.close();
        }
      } catch (cacheErr) {
        Logger.error(`[Index] Load from local cache also failed: ${cacheErr}`);
      }
      this.navigateToRoom(roomId);
    }
  }

  private async handleLeaveRoom(roomId: string): Promise<void> {
    if (roomId.length > 0) {
      try {
        await ApiService.getInstance().leaveRoom(roomId);
        this.chatRooms = this.chatRooms.filter((r: ChatRoom) => r.id !== roomId);
        this.rebuildRoomIndex();
        CryptoService.getInstance().clearRoomKey(roomId);
        StorageService.getInstance().deleteRoomMessages(roomId).catch(() => {});
      } catch (e) {
        Logger.error(`[Index] Leave room failed: ${e}`);
      }
    }
    if (this.navPathStack.size() > 0) {
      this.navPathStack.pop();
    }
  }

  // 解锁资料
  // F1-5：返回 Promise<UnlockResult>，让 ChatPage 切换 in-flight → success/error 三阶段反馈。
  // 计划文档：docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F1-5
  private async handleUnlock(roomId: string): Promise<UnlockResult> {
    try {
      const result = await ApiService.getInstance().unlockProfile(roomId);
      if (result.unlocked && result.profile !== null) {
        // ChatRoom.otherProfile 使用 UserProfile（字段为 string）；UnlockResult.profile 使用
        // ApiTypes.ProfileData（字段为 string | null）。两边类型不同，分别构造。
        const signature: string = normalizeProfileField(result.profile.signature);
        const city: string = normalizeProfileField(result.profile.city);
        const contact: string = normalizeProfileField(result.profile.contact);
        const room: ChatRoom | null = this.findRoom(roomId);
        if (room !== null) {
          room.unlocked = true;
          room.bothDeepConfirmed = true;
          room.otherProfile = { signature, city, contact };
          this.chatRooms = this.chatRooms.concat();
        }
        return { ok: true, profile: { signature, city, contact } };
      }
      // 服务端未返回解锁结果（可能未达条件），明确报错给 ChatPage 渲染失败提示。
      return { ok: false, errorMessage: '资料尚未可解锁' };
    } catch (e) {
      Logger.error(`[Index] Unlock profile failed: ${e}`);
      const message: string = getFriendlyErrorMessage(e as Error, '解锁失败，请稍后再试');
      return { ok: false, errorMessage: message };
    }
  }

  // 确认深度交流
  private handleConfirmDeep(roomId: string): void {
    const room: ChatRoom | null = this.findRoom(roomId);
    if (room !== null) {
      room.deepConnectionConfirmed = true;
      this.chatRooms = this.chatRooms.concat();
    }
    WsService.getInstance().confirmDeepConnection(roomId);
  }

  private async handleBlock(roomId: string): Promise<void> {
    try {
      await ApiService.getInstance().blockUser(roomId);
      await this.handleLeaveRoom(roomId);
      Logger.info('[Index] User blocked and room left');
    } catch (e) {
      Logger.error(`[Index] Block user failed: ${e}`);
    }
  }

  // 重置匿名身份
  private async handleResetIdentity(): Promise<void> {
    try {
      // 清空 UI 状态
      this.chatRooms = [];
      this.receivedSonars = [];
      this.rebuildRoomIndex();

      // 执行重置（清除服务端数据 + 本地数据 + 重新注册）
      await AuthService.getInstance().resetIdentity();

      // 重新初始化
      await this.refreshReceivedSonars();
      await this.refreshRooms();
      void this.refreshListeningRegistration();

      promptAction.showToast({ message: '身份已重置' });
      Logger.info('[Index] Identity reset completed');
    } catch (e) {
      Logger.error(`[Index] Reset identity failed: ${e}`);
      promptAction.showToast({ message: '重置失败，请重试' });
    }
  }

  // 保存连接
  // F1-5：返回 Promise<SaveResult>，由 ChatPage 渲染 in-flight → success/error 三阶段反馈，
  // 后端原本通过 promptAction.showToast 渲染的"连接已保存 / 等待对方确认"提示交由 ChatPage 完成。
  // 计划文档：docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F1-5
  private async handleSave(roomId: string, forceConfirm: boolean = false): Promise<SaveResult> {
    const room: ChatRoom | null = this.findRoom(roomId);
    if (room === null) {
      return { ok: false, errorMessage: '聊天室不存在' };
    }
    if (room.bothSaveConfirmed) {
      // 双方已保存：UI 不再触发，直接返回 ok。forceConfirm 路径同样视为 ok。
      return { ok: true };
    }
    if (!forceConfirm && room.saveConnectionConfirmed) {
      // 已经发起过保存请求，等待对方确认。返回 ok 由 ChatPage 渲染统一文案。
      return { ok: true };
    }
    if (this.saveConfirmingRoomIds.has(roomId)) {
      // 短路并发：仍作为 ok 返回，避免 ChatPage 显示失败。
      return { ok: true };
    }

    this.saveConfirmingRoomIds.add(roomId);
    try {
      const result = await ApiService.getInstance().saveConnection(roomId);
      Logger.info(`[Index] Save connection: ${result.status}`);
      const updatedRoom: ChatRoom | null = this.findRoom(roomId);
      if (updatedRoom !== null) {
        updatedRoom.saveConnectionConfirmed = true;
        if (result.status === 'confirmed') {
          updatedRoom.bothSaveConfirmed = true;
        }
        this.chatRooms = this.chatRooms.concat();
      }
      return { ok: true };
    } catch (e) {
      Logger.error(`[Index] Save connection failed: ${e}`);
      const message: string = getFriendlyErrorMessage(e as Error, '保存失败，请稍后再试');
      return { ok: false, errorMessage: message };
    } finally {
      this.saveConfirmingRoomIds.delete(roomId);
    }
  }

  // 拒绝保存连接
  private async handleSaveRefuse(roomId: string): Promise<void> {
    try {
      const result = await ApiService.getInstance().refuseSaveConnection(roomId);
      Logger.info(`[Index] Save connection refused: ${result.status}`);
    } catch (e) {
      Logger.error(`[Index] Save connection refuse failed: ${e}`);
    }
  }

  // 临终保存片段
  private async handleSaveMoment(roomId: string, content: string): Promise<void> {
    try {
      const result = await ApiService.getInstance().saveMoment(roomId, content);
      Logger.info(`[Index] Moment saved: ${result.id}`);
    } catch (e) {
      Logger.error(`[Index] Save moment failed: ${e}`);
    }
  }

  // 转换 API 消息为本地 Message
  private convertMessages(apiMsgs: MessageData[], roomId: string, peerReadMsgId: string): Message[] {
    const result: Message[] = [];
    for (let i: number = 0; i < apiMsgs.length; i++) {
      result.push(toLocalMessage(apiMsgs[i], roomId, peerReadMsgId));
    }
    return result;
  }

  // 转换 API 声呐为本地 Sonar
  private convertSonars(apiSonars: ReceivedSonarData[]): Sonar[] {
    const result: Sonar[] = [];
    for (let i: number = 0; i < apiSonars.length; i++) {
      const s: ReceivedSonarData = apiSonars[i];
      const sonar: Sonar = {
        id: s.id,
        content: s.content,
        distance: s.distance,
        timestamp: s.timestamp,
        geohash: ''
      };
      result.push(sonar);
    }
    return result;
  }

  // 刷新收到的声呐列表
  private async refreshReceivedSonars(): Promise<void> {
    try {
      const sonars = await ApiService.getInstance().getReceivedSonars();
      this.receivedSonars = this.convertSonars(sonars);
    } catch (e) {
      Logger.error(`[Index] Refresh sonars failed: ${e}`);
    }
  }

  // 刷新房间列表
  private async refreshRooms(): Promise<void> {
    try {
      const rooms = await ApiService.getInstance().getRooms();
      const updatedRooms: ChatRoom[] = [];
      for (let i: number = 0; i < rooms.length; i++) {
        const r: RoomData = rooms[i];
        const existing: ChatRoom | null = this.findRoom(r.id);
        const room: ChatRoom = {
          id: r.id,
          sonarContent: r.sonarContent,
          signalCode: r.signalCode,
          createdAt: r.createdAt ?? 0,
          expiresAt: r.expiresAt,
          messages: existing !== null ? existing.messages : [],
          unlocked: r.unlocked,
          deepConnectionAchieved: r.deepConnectionAchieved,
          deepConnectionConfirmed: r.deepConnectionConfirmed,
          bothDeepConfirmed: r.bothDeepConfirmed ?? r.unlocked,
          saveConnectionConfirmed: r.saveConnectionConfirmed,
          bothSaveConfirmed: r.bothSaveConfirmed ?? false,
          otherProfile: existing !== null ? existing.otherProfile : null,
          lastReadMessageId: r.lastReadMessageId ?? (existing !== null ? existing.lastReadMessageId : ''),
          peerReadMessageId: r.peerReadMessageId ?? (existing !== null ? existing.peerReadMessageId : '')
        };
        updatedRooms.push(room);
      }
      this.chatRooms = updatedRooms;
      this.rebuildRoomIndex();
      // 反追踪兜底：以服务端列表为准清理落盘残留（离线过期 / 进程重启自愈；
      // 空列表只清消息不动密钥，防服务端异常误伤——见 StorageService.deleteMessagesNotIn）
      const activeRoomIds: string[] = rooms.map((r: RoomData): string => r.id);
      StorageService.getInstance().deleteMessagesNotIn(activeRoomIds).catch(() => {});
      CryptoService.getInstance().retainKeysOnly(activeRoomIds);
    } catch (e) {
      Logger.error(`[Index] Refresh rooms failed: ${e}`);
    }
  }

  // 启动页完成后的初始化
  private async initAfterSplash(): Promise<void> {
    Logger.info('[Index] initAfterSplash started');
    await EntryAbility.getInitPromise();
    Logger.info('[Index] initAfterSplash: initPromise resolved');
    const auth: AuthService = AuthService.getInstance();
    Logger.info(`[Index] initAfterSplash: uuid=${auth.getUuid().length}, token=${auth.getToken().length}`);
    try {
      if (auth.getUuid().length === 0) {
        Logger.error('[Index] UUID is empty after init, cannot register');
        return;
      }
      await ApiService.getInstance().register(auth.getUuid());
      Logger.info('[Index] Registered successfully');
    } catch (e) {
      Logger.error(`[Index] Auth init failed: ${e}`);
      return;
    }

    const token: string = auth.getToken();
    // 同步服务端时间偏移，用于倒计时校准
    try {
      const serverTime: number = await ApiService.getInstance().getServerTime();
      const localTime: number = Date.now();
      setServerTimeOffset(serverTime - localTime);
      Logger.info(`[Index] Server time offset: ${serverTime - localTime}ms`);
    } catch (e) {
      Logger.warn(`[Index] Server time sync failed: ${e}`);
    }
    if (token.length > 0) {
      WsService.getInstance().connect();
      void this.refreshListeningRegistration();
    } else {
      Logger.warn('[Index] Skip WS connect: no token after auth');
    }
    await this.refreshReceivedSonars();
    await this.refreshRooms();
  }

  build() {
    Stack() {
      if (this.isOffline && !this.showSplash) {
        Text('网络已断开，正在重连...')
          .fontSize(12)
          .fontColor('#FFFFFF')
          .backgroundColor('#E53E3E')
          .width('100%')
          .height(24)
          .textAlign(TextAlign.Center)
          .zIndex(999)
      }
      if (this.showSplash) {
        SplashPage({
          onComplete: () => {
            this.checkPrivacyGate();
          }
        })
      } else {
        Navigation(this.navPathStack) {
          Column() {
            // F3-2：if/else 三段 → Tabs/TabContent；隐藏自带 TabBar，外层切换由底部 TabBar 触发，
            // 切换时 ArkUI 自带 250ms 平滑过渡，与 Flutter 端 AnimatedSwitcher 体感对齐。
            // 三个 TabContent 的 page 构造参数完全保持不变（仅外层从 if/else 换成 TabContent）。
            Tabs({ index: this.activeTabIndex, controller: this.tabsController }) {
              TabContent() {
                SonarPage({
                  cooldown: this.sonarCooldown,
                  nearbyCount: this.nearbyCount,
                  nearbyLoaded: this.nearbyLoaded,
                  blipCount: this.blipCount,
                  sendingSonar: this.sendingSonar,
                  onSonarSent: (content: string) => { this.handleSonarSent(content); },
                  onOpenProfile: () => { this.navPathStack.pushPathByName('Profile', null); },
                  onListeningChanged: (enabled: boolean) => { this.handleListeningChanged(enabled); }
                })
              }

              TabContent() {
                ReceiverPage({
                  sonars: this.receivedSonars,
                  onAccept: (sonar: Sonar) => { this.handleAcceptSonar(sonar); },
                  onIgnore: (sonarId: string) => { this.handleIgnoreSonar(sonarId); },
                  // UI 评审 P1：空态行动出口——跳回声呐页
                  onGoToSonar: () => { this.activeTabIndex = 0; }
                })
              }

              TabContent() {
                HourglassPage({
                  rooms: this.chatRooms,
                  onEnterRoom: (roomId: string) => { this.handleEnterRoom(roomId); }
                })
              }
            }
            .barHeight(0)
            .scrollable(false)
            .animationDuration(250)
            .layoutWeight(1)
            .onChange((index: number) => { this.activeTabIndex = index; })

            TabBar({
              activeTabIndex: $activeTabIndex,
              receiverCount: this.receivedSonars.length,
              roomCount: this.chatRooms.filter((room: ChatRoom) =>
                getUnreadMessageCount(room.messages, room.lastReadMessageId) > 0
              ).length,
              onTabSelected: (index: number) => { this.switchTab(index); }
            })
          }
          .width('100%')
          .height('100%')
        }
        .mode(NavigationMode.Stack)
        .navBarWidth('100%')
        .navDestination(NavDestinationBuilder)
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }

      // P2-A：仪式感动效
      if (this.showFirstPulse) {
        FirstPulseAnimation(() => {
          this.showFirstPulse = false;
        })
      }

      if (this.showFirstMatch) {
        FirstMatchAnimation(() => {
          this.showFirstMatch = false;
        })
      }

      if (this.showWithering) {
        WitheringAnimation(this.witheringRoomId, () => {
          this.showWithering = false;
          this.witheringRoomId = '';
        })
      }

      // 首启隐私协议授权门：全屏覆盖层盖住主页（zIndex 最高）。华为审核要求
      // 首启弹出《用户协议》与《隐私政策》、同意才能使用；返回键由 onBackPress
      // 拦截。未同意时 initAfterSplash 不会被调用（不注册、不连 WS、不定位）。
      if (this.showPrivacyCover) {
        Column() {
          if (this.privacyDocName === '') {
            this.PrivacyGateContent()
          } else {
            this.AgreementDocContent(
              this.privacyDocName === 'user' ? USER_AGREEMENT_TITLE : PRIVACY_POLICY_TITLE,
              this.privacyDocName === 'user' ? USER_AGREEMENT_TEXT : PRIVACY_POLICY_TEXT
            )
          }
        }
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.bg_base'))
        .zIndex(1000)
      }
    }
    .width('100%')
    .height('100%')
  }

  /**
   * @Entry 页面返回键：协议门展示期间一律拦截（华为审核要求"不可通过返回
   * 手势绕过协议弹窗"）；全文视图下返回键回到协议门而非退出应用。
   */
  onBackPress(): boolean {
    if (this.showPrivacyCover) {
      if (this.privacyDocName !== '') {
        this.privacyDocName = '';
      }
      return true;
    }
    return false;
  }

  /**
   * 启动页完成后的隐私协议门检查：
   * 已同意 → 正常初始化；未同意 → 弹出全屏协议门（初始化延后，未同意不采集）。
   */
  private checkPrivacyGate(): void {
    this.showSplash = false;
    if (AuthService.getInstance().isPrivacyAgreed()) {
      this.initAfterSplash();
    } else {
      this.showPrivacyCover = true;
    }
  }

  private async handlePrivacyAgree(): Promise<void> {
    await AuthService.getInstance().setPrivacyAgreed(true);
    // 推送 SDK 初始化在 onCreate 被协议标记拦下，同意后此处补挂
    PushService.getInstance().init().catch(() => {
      Logger.error('PushService init failed');
    });
    // 定位权限申请在窗口加载完成时被协议标记拦下，同意后此处补做
    EntryAbility.requestLocationPermissionIfAgreed();
    this.privacyDocName = '';
    this.showPrivacyCover = false;
    this.initAfterSplash();
  }

  private handlePrivacyDisagree(): void {
    promptAction.showDialog({
      title: '温馨提示',
      message: '不同意《用户协议》与《隐私政策》将无法使用 NoiseX，确定要退出应用吗？',
      buttons: [
        { text: '再看看', color: '#FF6B35' },
        { text: '退出应用', color: '#A0A5B0' }
      ]
    }).then((result: promptAction.ShowDialogSuccessResponse): void => {
      if (result.index === 1) {
        // terminateSelf 走标准 Ability 生命周期，进程由系统回收；下次冷启动重新弹协议门
        const ctx = this.getUIContext().getHostContext() as common.UIAbilityContext;
        ctx.terminateSelf();
      }
    }).catch((): void => {
      Logger.error('[Index] privacy disagree dialog failed');
    });
  }

  @Builder
  PrivacyGateContent() {
    Blank().height(this.statusBarHeight)

    Scroll() {
      Column() {
        Text('📡')
          .fontSize(56)
          .margin({ top: 40 })

        Text('欢迎使用 NoiseX')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 16 })

        Column() {
          Text('在使用前，请阅读并了解以下要点：')
            .fontSize(13)
            .fontColor($r('app.color.text_primary'))

          ForEach(getAgreementHighlights(), (item: string[]) => {
            Row() {
              Circle()
                .width(6)
                .height(6)
                .fill($r('app.color.primary'))
                .margin({ top: 7 })

              Text(`${item[0]}：${item[1]}`)
                .fontSize(13)
                .fontColor($r('app.color.text_primary'))
                .lineHeight(20)
                .layoutWeight(1)
                .margin({ left: 10 })
            }
            .alignItems(VerticalAlign.Top)
            .width('100%')
            .margin({ top: 12 })
          }, (item: string[]) => item[0])

          Text('点击《用户协议》与《隐私政策》可查看完整内容。你发送声呐或接收提醒时，才会向系统申请定位或通知权限，并可随时在系统设置中撤销。')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .lineHeight(19)
            .margin({ top: 12 })
        }
        .width('100%')
        .padding(16)
        .borderRadius(8)
        .backgroundColor($r('app.color.bg_card'))
        .border({ width: 1, color: $r('app.color.primary_border') })
        .margin({ top: 24 })

        Row() {
          Text('我已阅读并同意 ')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text('《用户协议》')
            .fontSize(13)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              this.privacyDocName = 'user';
            })
          Text(' 和 ')
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
          Text('《隐私政策》')
            .fontSize(13)
            .fontColor($r('app.color.primary'))
            .onClick(() => {
              this.privacyDocName = 'privacy';
            })
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .margin({ top: 16 })

        Button('同意并继续')
          .width('100%')
          .height(44)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.bg_base'))
          .backgroundColor($r('app.color.primary'))
          .borderRadius(8)
          .margin({ top: 20 })
          .onClick(() => {
            this.handlePrivacyAgree();
          })

        Button('不同意并退出')
          .width('100%')
          .height(44)
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .backgroundColor(Color.Transparent)
          .borderRadius(8)
          .border({ width: 1, color: $r('app.color.primary_border') })
          .margin({ top: 12 })
          .onClick(() => {
            this.handlePrivacyDisagree();
          })

        Blank().height(24)
      }
      .width('100%')
      .padding({ left: 24, right: 24 })
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
  }

  @Builder
  AgreementDocContent(title: string, body: string) {
    Column() {
      Blank().height(this.statusBarHeight)

      Row() {
        Button({ type: ButtonType.Normal }) {
          Text('←')
            .fontSize(20)
            .fontColor($r('app.color.text_primary'))
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.privacyDocName = '';
        })

        Text(title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 10, bottom: 10 })

      Scroll() {
        Text(body)
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
          .lineHeight(22)
          .width('100%')
          .padding(16)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_base'))
  }
}
