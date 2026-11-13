import { MessageBubble } from '../components/MessageBubble';
import { HourglassTimer } from '../components/HourglassTimer';
import { ChatRoom, canRequestSaveConnection, canUnlockProfile, getDeepConnectionStatusText, getNow, getProfileDisplayValue, getSaveConnectionStatusText, isUnlockWindowAvailable } from '../model/ChatRoom';
import { Message, getMessageBubbleRenderKey } from '../model/Message';
import { UnlockResult, SaveResult } from '../model/ApiTypes';
import { Utils } from '../common/Utils';
import { WsService } from '../service/WsService';
import { CryptoService } from '../service/CryptoService';
import { ApiService } from '../service/ApiService';
import { HapticService } from '../service/HapticService';
import { Constants } from '../model/Constants';
import { Logger } from '../common/Logger';
import { NavRoomParam, ChatController, RoomState } from './Index';
import { AnimationTokens, Curve } from '../model/AnimationTokens';
import { KeyboardAvoidMode } from '@kit.ArkUI';
import pasteboard from '@ohos.pasteboard';
import promptAction from '@ohos.promptAction';

@Component
export struct ChatPage {
  @Consume('navPathStack') navPathStack: NavPathStack;
  @Prop navParam: NavRoomParam | null = null;
  @State inputText: string = '';
  @State showInfo: boolean = false;
  @State showMoreMenu: boolean = false;
  @State moreMenuScale: number = 0.9;
  @State moreMenuOpacity: number = 0;
  @State roomId: string = '';
  @State sonarContent: string = '';
  @State signalCode: string = '';
  @State expiresAt: number = 0;
  @State createdAt: number = 0;
  @State unlocked: boolean = false;
  @State deepConnectionAchieved: boolean = false;
  @State deepConnectionConfirmed: boolean = false;
  @State bothDeepConfirmed: boolean = false;
  @State saveConnectionConfirmed: boolean = false;
  @State bothSaveConfirmed: boolean = false;
  @State deepConfirmDialogShown: boolean = false;
  @State otherSignature: string = '';
  @State otherCity: string = '';
  @State otherContact: string = '';
  @State messageList: Message[] = [];
  // P1-J：临终保存片段
  @State showSaveMomentDialog: boolean = false;
  @State momentContent: string = '';
  // P2-C：长按消息上下文菜单（复制 / 引用 / 举报）
  @State quotedMessage: Message | null = null;
  @State showQuotePreview: boolean = false;
  @State quotePreviewOpacity: number = 0;
  @State quotePreviewScale: number = 0.9;
  @State quotePreviewTranslateY: number = 10;
  @State showMessageMenu: boolean = false;
  @State menuTargetMessage: Message | null = null;
  @State messageMenuTranslateY: number = 100;  // 动画：从底部滑入
  // F1-6：解锁资料 / 保存连接 in-flight 节流（防抖 + 三阶段反馈）
  // 修复用户反馈 bug：聊天页点击 "解锁资料" / "保存连接" 没有任何反馈，
  // 现在 await chatController.onUnlock/onSave 拿到 UnlockResult/SaveResult，
  // 并用 promptAction.showToast 渲染 in-flight → success/error 三段提示。
  @State unlockInFlight: boolean = false;
  @State saveInFlight: boolean = false;
  // P1-B：对方正在输入状态。AppStorage 由 Index 维护（onTypingStart/Stop + 4s 兜底）
  @StorageLink('peerTypingRoomId') peerTypingRoomId: string = '';
  @StorageLink('chatController') chatController: ChatController | null = null;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  // 底部导航条避让高度（Index.refreshAvoidAreas 维护）：输入栏必须抬到导航条之上
  @StorageProp('bottomAvoidHeight') bottomAvoidHeight: number = 32;
  private scroller: Scroller = new Scroller();
  private messageRefreshTimer: number = -1;
  // P1-B：本端 typing 节流：连续输入只在第一次发 typing_start，停顿 ≥3s 后发 typing_stop
  private typingStartSent: boolean = false;
  private typingStopTimer: number = -1;
  private previousKeyboardAvoidMode: KeyboardAvoidMode | null = null;
  // 聊天发送频率防抖：记录上次发送时间戳，与服务端 msg-rate-seconds 对齐。
  // 防止"发送太快"被服务端 RATE_LIMIT 拒绝（拒绝时服务端只回 error 给发送方，
  // 客户端旧实现乐观插入的消息不会回滚 → 幽灵消息 + 发送方互动数虚高）。
  private lastSendTime: number = 0;

  aboutToAppear(): void {
    this.applyChatKeyboardAvoidance();

    if (this.navParam !== null && this.navParam !== undefined) {
      const p: NavRoomParam = this.navParam as NavRoomParam;
      this.roomId = (p.roomId !== null && p.roomId !== undefined) ? p.roomId : '';
      this.sonarContent = (p.sonarContent !== null && p.sonarContent !== undefined) ? p.sonarContent : '';
      this.signalCode = (p.signalCode !== null && p.signalCode !== undefined) ? p.signalCode : '';
      this.expiresAt = (p.expiresAt !== null && p.expiresAt !== undefined) ? p.expiresAt : 0;
      this.createdAt = (p.createdAt !== null && p.createdAt !== undefined) ? p.createdAt : 0;
      this.unlocked = p.unlocked ?? false;
      this.deepConnectionAchieved = p.deepConnectionAchieved ?? false;
      this.deepConnectionConfirmed = p.deepConnectionConfirmed ?? false;
      this.bothDeepConfirmed = p.bothDeepConfirmed ?? this.unlocked;
      this.saveConnectionConfirmed = p.saveConnectionConfirmed ?? false;
      this.bothSaveConfirmed = p.bothSaveConfirmed ?? false;
      this.otherSignature = (p.otherSignature !== null && p.otherSignature !== undefined) ? p.otherSignature : '';
      this.otherCity = (p.otherCity !== null && p.otherCity !== undefined) ? p.otherCity : '';
      this.otherContact = (p.otherContact !== null && p.otherContact !== undefined) ? p.otherContact : '';
    }

    // B18：进入房间发现既无共享密钥也无临时对（清数据/重装场景）时
    // 主动发起 E2EE 重协商，对方以新对回应后双方派生新密钥恢复加密
    if (this.roomId.length > 0 &&
      !CryptoService.getInstance().hasSharedKey(this.roomId) &&
      !CryptoService.getInstance().hasKeyPair(this.roomId)) {
      CryptoService.getInstance().generateKeyPair(this.roomId).then((pubKey: string) => {
        if (pubKey.length > 0) {
          WsService.getInstance().sendKeyExchange(this.roomId, pubKey);
        }
      }).catch(() => {
        Logger.error('[ChatPage] Key re-exchange init failed');
      });
    }

    this.refreshMessageList();
    // 进入聊天页面立即标记所有消息已读
    this.markLastMessageRead();
    this.messageRefreshTimer = setInterval(() => {
      this.refreshMessageList();
    }, 1000);
  }

  aboutToDisappear(): void {
    if (this.messageRefreshTimer !== -1) {
      clearInterval(this.messageRefreshTimer);
      this.messageRefreshTimer = -1;
    }
    // P1-B：离开聊天页前停止 typing 信令并清理本端节流定时器
    this.flushTypingStop();
    this.restorePageKeyboardAvoidance();
  }

  /**
   * P1-B：用户改动输入文本时的 typing 节流。
   *
   * - 文本由空 → 非空：发 typing_start，记录 typingStartSent
   * - 持续输入：每次重置 3s 停顿定时器
   * - 3s 没改动 / 文本被清空：发 typing_stop
   */
  private handleTypingChange(value: string): void {
    if (this.roomId.length === 0) return;
    const trimmed: string = value.trim();
    if (trimmed.length === 0) {
      this.flushTypingStop();
      return;
    }
    if (!this.typingStartSent) {
      this.typingStartSent = true;
      WsService.getInstance().sendTyping(this.roomId, true);
    }
    if (this.typingStopTimer !== -1) {
      clearTimeout(this.typingStopTimer);
    }
    this.typingStopTimer = setTimeout(() => {
      this.flushTypingStop();
    }, 3000);
  }

  /** P1-B：发送 typing_stop（如果之前发过 typing_start）并清理节流状态 */
  private flushTypingStop(): void {
    if (this.typingStopTimer !== -1) {
      clearTimeout(this.typingStopTimer);
      this.typingStopTimer = -1;
    }
    if (this.typingStartSent && this.roomId.length > 0) {
      WsService.getInstance().sendTyping(this.roomId, false);
    }
    this.typingStartSent = false;
  }

  private applyChatKeyboardAvoidance(): void {
    try {
      this.previousKeyboardAvoidMode = this.getUIContext().getKeyboardAvoidMode();
      this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    } catch (e) {
      Logger.error(`[ChatPage] Apply keyboard avoidance failed: ${e}`);
    }
  }

  private restorePageKeyboardAvoidance(): void {
    if (this.previousKeyboardAvoidMode === null) return;
    try {
      this.getUIContext().setKeyboardAvoidMode(this.previousKeyboardAvoidMode);
      this.previousKeyboardAvoidMode = null;
    } catch (e) {
      Logger.error(`[ChatPage] Restore keyboard avoidance failed: ${e}`);
    }
  }

  /**
   * TASK-002: 深度交流进度指示器
   * 总数 ≥20 且双方各 ≥5 条时自动隐藏
   */
  @Builder
  DeepConnectionProgressBuilder() {
    Column() {
      // 环形进度条
      Stack({ alignContent: Alignment.Center }) {
        // 环形进度条（使用 Progress 组件，符合官方 API）
        Progress({
          value: Math.min(1,
            (this.getMyMessageCount() + this.getOtherMessageCount())
            / Constants.DEEP_CONNECTION_THRESHOLD
          ) * 100,
          total: 100,
          type: ProgressType.Ring
        })
          .width(64)
          .height(64)
          .color($r('app.color.primary'))
          .backgroundColor($r('app.color.bg_muted'))
          .style({ strokeWidth: 3 })

        // 中心数字：当前/目标（Math.min 防止超过阈值显示 21/20）
        Text(`${Math.min(this.getMyMessageCount() + this.getOtherMessageCount(), Constants.DEEP_CONNECTION_THRESHOLD)}/${Constants.DEEP_CONNECTION_THRESHOLD}`)
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
      }

      // 提示文案（复用原有 getDeepConnectionHint()）
      Text(this.getDeepConnectionHint())
        .fontSize(11)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
        .maxLines(2)
        .textAlign(TextAlign.Center)
    }
    .width('100%')
    .padding({ top: 16, bottom: 16 })
    .alignItems(HorizontalAlign.Center)
    .visibility(this.deepConnectionAchieved ? Visibility.None : Visibility.Visible)
  }

  private refreshMessageList(): void {
    if (this.chatController !== null && this.roomId.length > 0) {
      const msgs: Message[] = this.chatController.getMessages(this.roomId);
      // 比较是否有变化：长度、最后一条ID、或任何消息的已读状态
      let changed: boolean = msgs.length !== this.messageList.length;
      if (!changed && msgs.length > 0 && this.messageList.length > 0) {
        if (msgs[msgs.length - 1].id !== this.messageList[this.messageList.length - 1].id) {
          changed = true;
        }
      }
      if (!changed) {
        for (let i: number = 0; i < msgs.length; i++) {
          if (msgs[i].read !== this.messageList[i].read) {
            changed = true;
            break;
          }
        }
      }
      if (changed) {
        this.messageList = msgs;
        setTimeout(() => {
          this.scroller.scrollEdge(Edge.Bottom);
        }, 50);
        // 消息有变化时立即标记已读（用户正在聊天页面查看）
        this.markLastMessageRead();
      }
      // 同步房间状态（解锁、深度交流等）
      const state: RoomState | null = this.chatController.getRoomState(this.roomId);
      if (state !== null) {
        if (this.unlocked !== state.unlocked) this.unlocked = state.unlocked;
        if (this.deepConnectionAchieved !== state.deepConnectionAchieved) {
          this.deepConnectionAchieved = state.deepConnectionAchieved;
          // 深度交流刚达成，自动弹窗提示确认
          if (state.deepConnectionAchieved && !state.deepConnectionConfirmed && !this.deepConfirmDialogShown) {
            this.deepConfirmDialogShown = true;
            this.showDeepConfirmDialog();
          }
        }
        if (this.deepConnectionConfirmed !== state.deepConnectionConfirmed) this.deepConnectionConfirmed = state.deepConnectionConfirmed;
        if (this.bothDeepConfirmed !== state.bothDeepConfirmed) this.bothDeepConfirmed = state.bothDeepConfirmed;
        if (this.saveConnectionConfirmed !== state.saveConnectionConfirmed) this.saveConnectionConfirmed = state.saveConnectionConfirmed;
        if (this.bothSaveConfirmed !== state.bothSaveConfirmed) this.bothSaveConfirmed = state.bothSaveConfirmed;
        if (this.otherSignature !== state.otherSignature) this.otherSignature = state.otherSignature;
        if (this.otherCity !== state.otherCity) this.otherCity = state.otherCity;
        if (this.otherContact !== state.otherContact) this.otherContact = state.otherContact;
      }
    }
  }

  onDidBuild(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.Bottom);
    }, 50);
  }

  // ========== UI 评审 P1 §5-2：时间戳分组与日期分隔 ==========

  private isSameDay(a: number, b: number): boolean {
    const da: Date = new Date(a);
    const db: Date = new Date(b);
    return da.getFullYear() === db.getFullYear() &&
      da.getMonth() === db.getMonth() && da.getDate() === db.getDate();
  }

  private shouldShowDateSeparator(index: number): boolean {
    if (index <= 0 || index > this.messageList.length) {
      return true;
    }
    return !this.isSameDay(this.messageList[index - 1].timestamp,
      this.messageList[index].timestamp);
  }

  private formatDateSeparator(index: number): string {
    const t: Date = new Date(this.messageList[index].timestamp);
    return `${t.getMonth() + 1}月${t.getDate()}日`;
  }

  // 相邻消息 1 分钟内且同天且**同一发送者** → 隐藏时间戳（首条始终显示）。
  // 2026-11-03 补同发送者条件（与 Flutter chat_message_list 同步）：对方
  // 秒回我时，我方消息不应被吞掉时间戳（会连带吞掉发送状态对号）
  private shouldShowTime(index: number): boolean {
    if (index <= 0 || index > this.messageList.length) {
      return true;
    }
    const prev: Message = this.messageList[index - 1];
    const cur: Message = this.messageList[index];
    if (!this.isSameDay(prev.timestamp, cur.timestamp)) {
      return true;
    }
    if (prev.sender !== cur.sender) {
      return true;
    }
    return Math.abs(cur.timestamp - prev.timestamp) >= 60 * 1000;
  }

  // ========== UI 评审 P0 §6-3：资料底部半模态 sheet ==========

  private openProfileSheet(): void {
    this.showInfo = true;
  }

  build() {
    NavDestination() {
      Column() {
        this.ChatHeaderBuilder()

        // P1-J：临终保存片段横幅（房间剩余 < 12h 时显示）
        if (this.shouldShowSaveMomentOption()) {
          this.SaveMomentBannerBuilder()
        }

        List({ scroller: this.scroller, space: 12 }) {
          ListItem() {
            Row() {
              Column() {
                Text('触发声呐:')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ bottom: 4 })

                Text(`"${this.sonarContent}"`)
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
              }
              .padding({ left: 16, right: 16, top: 8, bottom: 8 })
              .backgroundColor('rgba(31, 31, 46, 0.5)')
              .borderRadius(8)
              .border({ width: 1, color: $r('app.color.primary_border') })
              .constraintSize({ maxWidth: 320 })
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
          }

          // TASK-002: 深度交流进度指示器（仅未达成时显示）
          if (!this.deepConnectionAchieved) {
            ListItem() {
              this.DeepConnectionProgressBuilder()
            }
          }

          ForEach(this.messageList, (msg: Message, index: number) => {
            ListItem() {
              Column() {
                // UI 评审 P1（§5-2）：跨天插日期分隔条
                if (this.shouldShowDateSeparator(index)) {
                  Text(this.formatDateSeparator(index))
                    .fontSize(11)
                    .fontColor($r('app.color.text_secondary'))
                    .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                    .backgroundColor($r('app.color.bg_muted'))
                    .borderRadius(10)
                    .margin({ bottom: 12 })
                }
                MessageBubble({
                  message: msg,
                  // UI 评审 P1：相邻 1 分钟内隐藏时间戳
                  showTime: this.shouldShowTime(index),
                  onLongPress: (m: Message) => this.showMessageContextMenu(m)
                })
              }
              .width('100%')
            }
          }, (msg: Message) => getMessageBubbleRenderKey(msg))
        }
        .layoutWeight(1)
        .padding({ left: 16, right: 16, top: 16, bottom: 16 })
        .onReachEnd(() => {
          this.markLastMessageRead();
        })

        // P1-B：对方正在输入提示
        if (this.peerTypingRoomId === this.roomId && this.peerTypingRoomId.length > 0) {
          Row() {
            Text(`${this.signalCode} 正在输入...`)
              .fontSize(12)
              .fontColor($r('app.color.text_secondary'))
              .opacity(0.85)
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 4, bottom: 8 })
          .justifyContent(FlexAlign.Start)
        }

        this.ChatInputBuilder()

        // 更多菜单浮层（带半透明遮罩，点击空白关闭）
        if (this.showMoreMenu) {
          Stack({ alignContent: Alignment.Top }) {
            // 半透明遮罩：点击空白关闭菜单
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('rgba(0, 0, 0, 0.4)')
              .opacity(this.moreMenuOpacity)
              .onClick(() => {
                this.closeMoreMenu();
              })

            // 菜单内容（带弹出动画）
            Column() {
              // 仅在双方确认且仍处于 24h 解锁窗口时暴露入口，避免未满足条件时误触发 400。
              if (canUnlockProfile(this.unlocked, this.bothDeepConfirmed,
                this.createdAt <= 0 || isUnlockWindowAvailable(this.createdAt), this.createdAt)) {
                Row() {
                  Text('🔒')
                    .fontSize(18)
                    .margin({ right: 8 })
                  Text('解锁资料')
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                }
                .width('100%')
                .height(44)
                .padding({ left: 16, right: 16 })
                .alignItems(VerticalAlign.Center)
                .onClick(() => {
                  this.onUnlockTap();
                  this.closeMoreMenu();
                })

                Row() {
                  Text('')
                    .width('100%')
                    .height(0.5)
                }
                .padding({ left: 16, right: 16 })
                .backgroundColor($r('app.color.divider'))
              }

              Row() {
                Text(this.bothSaveConfirmed ? '✓' : (this.saveConnectionConfirmed ? '⏳' : '❤️'))
                  .fontSize(18)
                  .margin({ right: 8 })
                Text(this.getSaveButtonText())
                  .fontSize(15)
                  .fontColor(this.saveConnectionConfirmed ? $r('app.color.text_secondary') : $r('app.color.text_primary'))
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 16 })
              .alignItems(VerticalAlign.Center)
              .enabled(canRequestSaveConnection(this.unlocked, this.saveConnectionConfirmed, this.bothSaveConfirmed) && !this.saveInFlight)
              .opacity(canRequestSaveConnection(this.unlocked, this.saveConnectionConfirmed, this.bothSaveConfirmed) && !this.saveInFlight ? 1 : 0.5)
              .onClick(() => {
                if (canRequestSaveConnection(this.unlocked, this.saveConnectionConfirmed, this.bothSaveConfirmed)) {
                  this.onSaveTap();
                }
                this.closeMoreMenu();
              })

              Row() {
                Text('')
                  .width('100%')
                  .height(0.5)
              }
              .padding({ left: 16, right: 16 })
              .backgroundColor($r('app.color.divider'))

              Row() {
                Text('🚩')
                  .fontSize(18)
                  .margin({ right: 8 })
                Text('举报')
                  .fontSize(15)
                  .fontColor($r('app.color.text_primary'))
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 16 })
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                if (this.chatController !== null) {
                  this.chatController.onReport(this.roomId);
                }
                this.closeMoreMenu();
              })

              Row() {
                Text('')
                  .width('100%')
                  .height(0.5)
              }
              .padding({ left: 16, right: 16 })
              .backgroundColor($r('app.color.divider'))

              Row() {
                Text('🚫')
                  .fontSize(18)
                  .margin({ right: 8 })
                Text('拉黑')
                  .fontSize(15)
                  .fontColor('#E84855')
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 16 })
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                this.closeMoreMenu();
                this.showBlockConfirmDialog();
              })

              Row() {
                Text('')
                  .width('100%')
                  .height(0.5)
              }
              .padding({ left: 16, right: 16 })
              .backgroundColor($r('app.color.divider'))

              Row() {
                Text('🚪')
                  .fontSize(18)
                  .margin({ right: 8 })
                Text('离开房间')
                  .fontSize(15)
                  .fontColor('#E84855')
              }
              .width('100%')
              .height(44)
              .padding({ left: 16, right: 16 })
              .alignItems(VerticalAlign.Center)
              .onClick(() => {
                // 离开会永久关闭房间（不可逆），与 Flutter 端一致先二次确认
                this.closeMoreMenu();
                this.showLeaveConfirmDialog();
              })
            }
            .width(170)
            .borderRadius(8)
            .backgroundColor($r('app.color.bg_card'))
            .shadow({
              radius: 12,
              color: '#40000000',
              offsetX: 0,
              offsetY: 4
            })
            .position({ x: '100%', y: this.statusBarHeight + 52 })
            .translate({ x: -182, y: 0 })
            .scale({ x: this.moreMenuScale, y: this.moreMenuScale })
            .opacity(this.moreMenuOpacity)
          }
          .width('100%')
          .height('100%')
          .position({ x: 0, y: 0 })
          .zIndex(100)
        }

        // P1-J：临终保存片段对话框
        if (this.showSaveMomentDialog) {
          this.SaveMomentDialogBuilder()
        }

        // P2-C：长按消息上下文菜单
        if (this.showMessageMenu && this.menuTargetMessage !== null) {
          this.MessageContextMenuBuilder()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_base'))
    }
    .hideTitleBar(true)
    .backgroundColor($r('app.color.bg_base'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    // UI 评审 P1 §6-3：资料改底部半模态 sheet（grabber 内置 dragBar），
    // 不再内嵌挤压消息列表；$$ 双向绑定让下滑关闭自动复位 showInfo
    .bindSheet($$this.showInfo, this.ChatInfoBuilder(), {
      height: 360,
      dragBar: true,
      showClose: false,
      backgroundColor: '#1F1F2E',
      onDisappear: () => {
        this.showInfo = false;
      }
    })
    .onBackPressed(() => {
      this.navPathStack.pop();
      return true;
    })
  }

  @Builder
  ChatHeaderBuilder() {
    Column() {
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
          this.navPathStack.pop();
        })

        Text(this.signalCode)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        // 更多按钮，点击弹出菜单
        Button({ type: ButtonType.Normal }) {
          Text('⋮')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (!this.showMoreMenu) {
            this.openMoreMenu();
          } else {
            this.closeMoreMenu();
          }
        })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Row() {
        HourglassTimer({ expiresAt: this.expiresAt })
          .layoutWeight(1)

        // UI 评审 P0（§5-4）：未达成时常驻进度徽章"🤝 12/20"，
        // 点按滚回列表顶部的环形规则说明（与 Flutter ChatHeaderBar 同款）
        if (!this.deepConnectionAchieved && this.messageList.length > 0) {
          Text(`🤝 ${this.messageList.length}/${Constants.DEEP_CONNECTION_THRESHOLD}`)
            .fontSize(12)
            .fontColor($r('app.color.primary'))
            .height(28)
            .padding({ left: 10, right: 10 })
            .backgroundColor($r('app.color.primary_input'))
            .borderRadius(16)
            .border({ width: 1, color: $r('app.color.primary_border') })
            .margin({ left: 8 })
            .onClick(() => {
              this.scroller.scrollEdge(Edge.Top);
            })
        }

        if (this.deepConnectionAchieved && !this.deepConnectionConfirmed) {
          Button('🤝 确认')
            .fontSize(12)
            .backgroundColor($r('app.color.primary'))
            .fontColor($r('app.color.bg_base'))
            .borderRadius(16)
            .height(28)
            .padding({ left: 8, right: 8 })
            .enabled(this.createdAt <= 0 || isUnlockWindowAvailable(this.createdAt))
            .opacity((this.createdAt <= 0 || isUnlockWindowAvailable(this.createdAt)) ? 1 : 0.4)
            .onClick(() => {
              this.showDeepConfirmDialog();
            })
        }

        if (this.unlocked) {
          Button('👤 查看资料')
            .fontSize(12)
            .backgroundColor($r('app.color.primary'))
            .fontColor($r('app.color.bg_base'))
            .borderRadius(16)
            .height(28)
            .padding({ left: 8, right: 8 })
            .onClick(() => {
              // UI 评审 P1 §6-3：改弹底部半模态 sheet
              this.openProfileSheet();
            })
        } else if (canUnlockProfile(this.unlocked, this.bothDeepConfirmed,
          this.createdAt <= 0 || isUnlockWindowAvailable(this.createdAt), this.createdAt)) {
          Button(this.unlockInFlight ? '解锁中…' : '🔓 解锁')
            .fontSize(12)
            .backgroundColor($r('app.color.primary'))
            .fontColor($r('app.color.bg_base'))
            .borderRadius(16)
            .height(28)
            .padding({ left: 8, right: 8 })
            .enabled(!this.unlockInFlight)
            .opacity(this.unlockInFlight ? 0.6 : 1)
            .onClick(() => {
              this.onUnlockTap();
            })
        }

        if (this.deepConnectionAchieved) {
          Text('● 深度交流已达成')
            .fontSize(12)
            .fontColor($r('app.color.primary'))
            .margin({ left: 8 })
        }
      }
      .width('100%')
      .margin({ top: 8 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding({ left: 12, right: 12, top: this.statusBarHeight + 8, bottom: 8 })
    .backgroundColor($r('app.color.bg_card'))
    // UI 评审 P0：头部底线随倒计时警戒档（<6h 红警示）
    .border({
      width: { bottom: 1 },
      color: Utils.isCriticalExpiring(this.expiresAt, getNow()) ?
        'rgba(255, 56, 56, 0.3)' : $r('app.color.divider')
    })
  }

  @Builder
  ChatInfoBuilder() {
    Column() {
      Row() {
        Text('原始声呐:')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        Text(`"${this.sonarContent}"`)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
      }
      .width('100%')

      Row() {
        Text('消息数:')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        // UI 评审 P1（§6-2）：房号是系统词汇，不当人称——改"对方"
        Text(`你 ${this.getMyMessageCount()} 条 · 对方 ${this.getOtherMessageCount()} 条`)
          .fontSize(12)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 8 })

      Row() {
        Text('深度交流:')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))

        Text(getDeepConnectionStatusText(
          this.deepConnectionAchieved,
          this.deepConnectionConfirmed,
          this.bothDeepConfirmed,
          this.unlocked
        ))
          .fontSize(12)
          .fontColor(this.deepConnectionAchieved ?
            $r('app.color.primary') : $r('app.color.text_secondary'))
          .margin({ left: 8 })
      }
      .width('100%')
      .margin({ top: 8 })

      if (this.unlocked) {
        Column() {
          Text('● 已解锁资料:')
            .fontSize(12)
            .fontColor($r('app.color.primary'))

          Text(getProfileDisplayValue('签名', this.otherSignature))
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 12, top: 4 })

          Text(getProfileDisplayValue('城市', this.otherCity))
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 12, top: 2 })

          Text(getProfileDisplayValue('联系', this.otherContact))
            .fontSize(12)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 12, top: 2 })
        }
        .width('100%')
        .margin({ top: 8 })
        .padding({ top: 8 })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor('rgba(31, 31, 46, 0.5)')
    .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
  }

  @Builder
  ChatInputBuilder() {
    Column() {
      // P2-C：引用预览（在输入框上方）
      if (this.showQuotePreview && this.quotedMessage !== null) {
        this.QuotePreviewBuilder()
      }

      Row() {
        // 2026-11-02 样式对齐 Flutter ChatInputBar：胶囊输入框（圆角 21、
        // bg_card 填充、primary_border 描边）+ 圆形主色发送按钮（纸飞机
        // 矢量路径，对齐 Flutter Icons.send_rounded）——替换原方角输入框
        // + 方角➤按钮的旧样式（用户要求两端一致，以 Flutter 为基准）
        TextInput({ placeholder: '输入消息...', text: this.inputText })
          .layoutWeight(1)
          .height(42)
          .backgroundColor($r('app.color.bg_card'))
          .border({ width: 1, color: $r('app.color.primary_border'), radius: 21 })
          .fontColor($r('app.color.text_primary'))
          .placeholderColor($r('app.color.text_secondary'))
          .onChange((value: string) => {
            this.inputText = value;
            this.handleTypingChange(value);
          })
          .onSubmit(() => { this.sendMessage(); })

        Button() {
          // 系统实心纸飞机符号（与 Flutter Icons.send_rounded 同形——
          // 2026-11-02 并排对比实锤 Path 手绘方案渲染成朝左小三角，弃用）。
          // 符号默认朝上，旋转 90° 对齐 Flutter 的右指纸飞机
          SymbolGlyph($r('sys.symbol.paperplane_fill'))
            .fontSize(20)
            .fontColor([$r('app.color.bg_base')])
            .rotate({ z: 1, angle: 90 })
        }
        .type(ButtonType.Circle)
        .width(42)
        .height(42)
        .backgroundColor($r('app.color.primary'))
        .margin({ left: 10 })
        .onClick(() => { this.sendMessage(); })
      }
      .width('100%')

      // 深度交流提示（常显，2026-11-02 用户反馈：达成后提示消失="改没了"，
      // 未达成显示进度、达成后也要有明确状态文案）
      Text(this.deepConnectionAchieved
        ? '深度交流已达成，可解锁资料卡或保存连接'
        : this.getDeepConnectionHint())
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .textAlign(TextAlign.Center)
        .margin({ top: 8 })

      // 连续发送提示（达到4条时提醒，5条时警告）
      if (this.getMyConsecutiveCount() >= 4) {
        Text(this.getMyConsecutiveCount() >= 5
          ? '请等待对方回应后再继续发送'
          : `已连续发送 ${this.getMyConsecutiveCount()} 条消息，请注意交流节奏`
        )
          .fontSize(11)
          .fontColor(this.getMyConsecutiveCount() >= 5 ? $r('app.color.error') : $r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 4 })
      }
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 10, bottom: 12 + this.bottomAvoidHeight })
    // 2026-11-02 并排对比对齐 Flutter GlassContainer：底带 50% 透明
    // （原 80% 偏灰亮）+ 四周 1px #14FFFFFF 微白描边（原只有顶部分隔线）+
    // 模糊材质强制 DARK（Thin 默认浅色材质，是底带发灰的元凶）
    .backgroundColor('rgba(19, 19, 26, 0.5)')
    .backgroundBlurStyle(BlurStyle.Thin, { colorMode: ThemeColorMode.DARK })
    .border({ width: 1, color: '#14FFFFFF' })
  }

  private sendMessage(): void {
    if (this.inputText.trim().length === 0 || this.roomId.length === 0) return;
    // 频率防抖：与服务端 noisex.chat.msg-rate-seconds 对齐。
    // 在乐观插入之前拦截，避免发出去被拒、客户端却显示"已发送"的幽灵消息。
    const now: number = Date.now();
    const elapsedMs: number = now - this.lastSendTime;
    if (this.lastSendTime > 0 && elapsedMs < Constants.CHAT_MSG_RATE_SECONDS * 1000) {
      const wait: number = Math.ceil((Constants.CHAT_MSG_RATE_SECONDS * 1000 - elapsedMs) / 1000);
      promptAction.showToast({ message: `发送太快，请等待 ${wait} 秒`, duration: 1200 });
      return;
    }
    if (!this.canSendMessage()) {
      promptAction.showToast({ message: '请等待对方回应后再继续发送', duration: 1500 });
      return;
    }
    const trimmed: string = this.inputText.trim();
    // P2-C：若存在引用消息，拼接 "> 单行预览\n" 前缀
    const plaintext: string = this.quotedMessage !== null
      ? `> ${this.quotePreviewText(this.quotedMessage)}\n${trimmed}`
      : trimmed;
    const currentRoomId: string = this.roomId;
    this.inputText = '';
    this.closeQuotePreview();
    // P1-B：发送即停 typing 信令
    this.flushTypingStop();

    const optimisticMsg: Message = {
      id: `local-${Utils.generateId()}`,
      roomId: currentRoomId,
      sender: 'me',
      content: plaintext,
      timestamp: Date.now(),
      read: false,
      encrypted: false
    };

    if (this.chatController !== null) {
      this.chatController.addMessage(currentRoomId, optimisticMsg);
    }
    this.messageList = this.messageList.concat(optimisticMsg);
    setTimeout(() => { this.scroller.scrollEdge(Edge.Bottom); }, 50);
    // 记录发送时刻，供下次 sendMessage 的频率防抖判断（只在真正发起发送后更新）
    this.lastSendTime = now;

    CryptoService.getInstance().encrypt(currentRoomId, plaintext).then((encrypted: string) => {
      WsService.getInstance().sendChatMessage(currentRoomId, encrypted);
    }).catch(() => {
      WsService.getInstance().sendChatMessage(currentRoomId, plaintext);
    });
  }

  private showBlockConfirmDialog(): void {
    AlertDialog.show({
      title: '确认拉黑',
      message: '拉黑后将关闭当前聊天室，对方将无法继续联系你。此操作只能在拉黑列表中解除。',
      primaryButton: {
        value: '确认拉黑',
        action: () => {
          if (this.chatController !== null) {
            this.chatController.onBlock(this.roomId);
          }
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {}
      }
    });
  }

  private showDeepConfirmDialog(): void {
    AlertDialog.show({
      title: '深度交流已达成',
      message: '你们已达到深度交流条件！确认深度交流后，双方都确认即可解锁对方资料。',
      primaryButton: {
        value: '确认深度交流',
        action: () => {
          if (this.chatController !== null) {
            this.chatController.onConfirmDeep(this.roomId);
          }
        }
      },
      secondaryButton: {
        value: '稍后再说',
        action: () => {}
      }
    });
  }

  // 离开房间确认弹窗：离开=永久关闭聊天室（不可逆破坏性操作）。
  // 此前本端直接离开无确认，现与 Flutter 端对齐补二次确认。
  private showLeaveConfirmDialog(): void {
    AlertDialog.show({
      title: '离开房间',
      message: '离开后当前聊天室将关闭，此操作无法撤销。确定离开吗？',
      primaryButton: {
        value: '离开房间',
        action: () => {
          if (this.chatController !== null) {
            this.chatController.onLeave(this.roomId);
          }
        }
      },
      secondaryButton: {
        value: '取消',
        action: () => {}
      }
    });
  }

  private getMyMessageCount(): number {
    return this.messageList.filter((m: Message) => m.sender === 'me').length;
  }

  private getOtherMessageCount(): number {
    return this.messageList.filter((m: Message) => m.sender === 'other').length;
  }

  /**
   * 计算我连续发送的消息数（从后往前找，直到遇到对方消息为止）
   */
  private getMyConsecutiveCount(): number {
    let count: number = 0;
    for (let i: number = this.messageList.length - 1; i >= 0; i--) {
      if (this.messageList[i].sender === 'me') {
        count++;
      } else {
        break;
      }
    }
    return count;
  }

  /**
   * 判断是否可以继续发送消息：连续发送不超过 Constants.CHAT_MAX_CONSECUTIVE 条（与服务端对齐）。
   */
  private canSendMessage(): boolean {
    return this.getMyConsecutiveCount() < Constants.CHAT_MAX_CONSECUTIVE;
  }

  /**
   * 打开更多菜单（带动画）
   * 分层时序：遮罩先淡入（80ms），然后菜单弹入（带轻微过冲）
   */
  private openMoreMenu(): void {
    this.showMoreMenu = true;
    this.moreMenuScale = 0.85;
    this.moreMenuOpacity = 0;
    // 第一阶段：遮罩快速出现
    animateTo({
      duration: 80,
      curve: Curve.EaseOut
    }, () => {
      this.moreMenuOpacity = 1;
    });
    // 第二阶段：菜单弹性弹出
    setTimeout(() => {
      animateTo({
        duration: 220,
        curve: Curve.EaseOut
      }, () => {
        this.moreMenuScale = 1.02;
      });
      // 轻微回弹
      setTimeout(() => {
        animateTo({
          duration: 120,
          curve: Curve.EaseInOut
        }, () => {
          this.moreMenuScale = 1.0;
        });
      }, 200);
    }, 30);
  }

  /**
   * 关闭更多菜单（带动画）
   * 分层时序：菜单先缩小淡出，然后遮罩消失
   */
  private closeMoreMenu(): void {
    // 菜单快速收缩
    animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.moreMenuScale = 0.9;
      this.moreMenuOpacity = 0;
    });
    setTimeout(() => {
      this.showMoreMenu = false;
    }, 180);
  }

  private getSaveButtonText(): string {
    return getSaveConnectionStatusText(this.saveConnectionConfirmed, this.bothSaveConfirmed);
  }

  private getDeepConnectionHint(): string {
    const myCount: number = this.getMyMessageCount();
    const otherCount: number = this.getOtherMessageCount();
    const total: number = myCount + otherCount;
    const threshold: number = Constants.DEEP_CONNECTION_THRESHOLD;
    const minEach: number = 5;
    if (myCount < minEach && otherCount < minEach) {
      return `继续交流以达成深度交流（还需 ${Math.max(0, threshold - total)} 条，双方各至少${minEach}条）`;
    } else if (myCount < minEach) {
      return `继续交流以达成深度交流（你还需至少 ${minEach - myCount} 条参与）`;
    } else if (otherCount < minEach) {
      return `继续交流以达成深度交流（等待对方参与）`;
    } else {
      return `继续交流以达成深度交流（还需 ${Math.max(0, threshold - total)} 条）`;
    }
  }

  private markLastMessageRead(): void {
    const msgs: Message[] = this.messageList;
    if (msgs.length === 0 || this.roomId.length === 0) return;
    // 找到最后一条未读的对方消息，通知服务端我已读
    let lastUnreadId: string = '';
    for (let i: number = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].sender === 'other') {
        lastUnreadId = msgs[i].id;
        break;
      }
    }
    if (lastUnreadId.length > 0 && this.chatController !== null) {
      this.chatController.onMarkRead(this.roomId, lastUnreadId);
    }
  }

  // ========== P1-J：临终保存片段 ==========

  private shouldShowSaveMomentOption(): boolean {
    const now: number = Date.now();
    const remainingMs: number = this.expiresAt - now;
    const remainingHours: number = remainingMs / (1000 * 60 * 60);
    // 房间剩余时间 < 12 小时且 > 0
    return remainingHours < 12 && remainingHours >= 0;
  }

  @Builder
  SaveMomentBannerBuilder() {
    Column() {
      Row() {
        Text('📝')
          .fontSize(18)
          .margin({ right: 8 })

        Column() {
          Text('保存临终片段')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.primary'))

          Text('房间即将关闭，保存这段对话中最有意义的一句话')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Button('保存')
          .fontSize(12)
          .height(28)
          .backgroundColor($r('app.color.primary'))
          .fontColor($r('app.color.bg_base'))
          .onClick(() => {
            this.showSaveMomentDialog = true;
          })
      }
      .width('100%')
      .padding(12)
      .backgroundColor('rgba(255, 120, 0, 0.1)')
      .borderRadius(8)
      .border({ width: 1, color: 'rgba(255, 120, 0, 0.3)' })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
  }

  @Builder
  SaveMomentDialogBuilder() {
    Column() {
      Column() {
        // 半透明背景
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(0, 0, 0, 0.6)')
          .onClick(() => {
            this.showSaveMomentDialog = false;
          })

        // 对话框内容
        Column() {
          Row() {
            Text('📝 保存临终片段')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
              .layoutWeight(1)

            Button({ type: ButtonType.Normal }) {
              Text('×')
                .fontSize(20)
                .fontColor($r('app.color.text_secondary'))
            }
            .width(32)
            .height(32)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.showSaveMomentDialog = false;
            })
          }
          .width('100%')
          .padding({ bottom: 12 })

          TextArea({ placeholder: '记录这段对话中最有意义的一句话...', text: this.momentContent })
            .height(100)
            .maxLength(500)
            .backgroundColor($r('app.color.bg_base'))
            .fontColor($r('app.color.text_primary'))
            .placeholderColor($r('app.color.text_secondary'))
            .borderRadius(8)
            .border({ width: 1, color: $r('app.color.primary_border') })
            .onChange((value: string) => {
              this.momentContent = value;
            })
            .margin({ bottom: 12 })

          Row() {
            Button('取消')
              .fontSize(14)
              .height(32)
              .backgroundColor(Color.Transparent)
              .fontColor($r('app.color.text_secondary'))
              .onClick(() => {
                this.showSaveMomentDialog = false;
                this.momentContent = '';
              })

            Blank().layoutWeight(1)

            Button('保存')
              .fontSize(14)
              .height(32)
              .backgroundColor($r('app.color.primary'))
              .fontColor($r('app.color.bg_base'))
              .onClick(() => {
                this.handleSaveMoment();
              })
          }
          .width('100%')
        }
        .width('90%')
        .padding(16)
        .backgroundColor($r('app.color.bg_card'))
        .borderRadius(16)
        .border({ width: 1, color: $r('app.color.primary_border') })
        .position({ x: '50%', y: '50%' })
        .translate({ x: '-50%', y: '-50%' })
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(200)
  }

  private async handleSaveMoment(): Promise<void> {
    const content: string = this.momentContent.trim();
    if (content.length === 0) {
      return;
    }
    if (content.length > 500) {
      // 超过 500 字符的验证已在 TextArea maxLength 限制
      return;
    }

    try {
      await ApiService.getInstance().saveMoment(this.roomId, content);
      this.showSaveMomentDialog = false;
      this.momentContent = '';
      // 显示成功提示
      // 注意：实际使用时可能需要通过 AppStorage 或事件通知来显示 Toast
    } catch (e) {
      Logger.error(`[ChatPage] Save moment failed: ${JSON.stringify(e)}`);
    }
  }

  // ========== F1-6：解锁资料 / 保存连接 三阶段反馈 ==========
  //
  // 修复用户反馈 bug：聊天页点击 "解锁资料" / "保存连接" 没有任何反馈，不知道成功与否。
  // 现在通过 await chatController.onUnlock/onSave 拿到 UnlockResult/SaveResult，
  // 用 promptAction.showToast 渲染 in-flight → success/error 三阶段反馈，
  // 并通过 unlockInFlight / saveInFlight @State 节流防止重复点击。
  //
  // 与 Flutter 端 lib/pages/chat_page.dart 的 _onUnlockTap / _onSaveTap 行为对齐。
  // 计划文档：docs/superpowers/plans/2026-06-16-ux-feedback-and-immersive-tab-design.md F1-6
  private async onUnlockTap(): Promise<void> {
    if (this.unlockInFlight) return;
    if (this.chatController === null) return;
    this.unlockInFlight = true;
    HapticService.getInstance().light();
    promptAction.showToast({ message: '正在解锁资料…', duration: 1000 });
    try {
      const result: UnlockResult = await this.chatController.onUnlock(this.roomId);
      if (result.ok) {
        promptAction.showToast({ message: `已解锁 ${this.signalCode} 的资料`, duration: 1600 });
      } else {
        HapticService.getInstance().selection();
        const reason: string = result.errorMessage !== null && result.errorMessage !== undefined && result.errorMessage.length > 0
          ? result.errorMessage : '请稍后再试';
        promptAction.showToast({ message: `解锁失败：${reason}`, duration: 1600 });
      }
    } catch (e) {
      HapticService.getInstance().selection();
      promptAction.showToast({ message: '解锁失败：请稍后再试', duration: 1600 });
      Logger.error(`[ChatPage] onUnlockTap failed: ${JSON.stringify(e)}`);
    } finally {
      this.unlockInFlight = false;
    }
  }

  private async onSaveTap(): Promise<void> {
    if (this.saveInFlight) return;
    if (this.chatController === null) return;
    this.saveInFlight = true;
    HapticService.getInstance().light();
    promptAction.showToast({ message: '请求保存…', duration: 1000 });
    try {
      const result: SaveResult = await this.chatController.onSave(this.roomId);
      if (result.ok) {
        const msg: string = this.bothSaveConfirmed ? '连接已保存' : '保存请求已发送，等待对方确认';
        promptAction.showToast({ message: msg, duration: 1600 });
      } else {
        HapticService.getInstance().selection();
        const reason: string = result.errorMessage !== null && result.errorMessage !== undefined && result.errorMessage.length > 0
          ? result.errorMessage : '请稍后再试';
        promptAction.showToast({ message: `保存失败：${reason}`, duration: 1600 });
      }
    } catch (e) {
      HapticService.getInstance().selection();
      promptAction.showToast({ message: '保存失败：请稍后再试', duration: 1600 });
      Logger.error(`[ChatPage] onSaveTap failed: ${JSON.stringify(e)}`);
    } finally {
      this.saveInFlight = false;
    }
  }

  // ========== P2-C：长按消息上下文菜单（复制 / 引用 / 举报） ==========

  /**
   * 单行引用预览（≤30 字，超出加省略号）。
   *
   * 与 Flutter 端 `_quotePreviewText` 行为对齐，保持双端引用文本一致。
   */
  private quotePreviewText(m: Message): string {
    // 折叠多行 → 单行
    const oneLine: string = m.content.replace(/\s+/g, ' ').trim();
    if (oneLine.length <= 30) {
      return oneLine;
    }
    return `${oneLine.substring(0, 30)}…`;
  }

  /** 长按消息时触发：记录目标并展开菜单 */
  /**
   * 打开消息上下文菜单（带动画）
   */
  private showMessageContextMenu(m: Message): void {
    this.menuTargetMessage = m;
    this.messageMenuTranslateY = 100;
    this.showMessageMenu = true;
    animateTo({
      duration: AnimationTokens.NORMAL,
      curve: AnimationTokens.CURVE_STANDARD
    }, () => {
      this.messageMenuTranslateY = 0;
    });
  }

  /**
   * 关闭消息上下文菜单（带动画）
   * 与打开动画对称，相同的曲线和时长
   */
  private closeMessageContextMenu(): void {
    animateTo({
      duration: AnimationTokens.NORMAL,
      curve: AnimationTokens.CURVE_STANDARD
    }, () => {
      this.messageMenuTranslateY = 100;
    });
    setTimeout(() => {
      this.showMessageMenu = false;
      this.menuTargetMessage = null;
    }, AnimationTokens.NORMAL);
  }

  /**
   * 打开引用预览（带动画）
   * 从下往上滑入 + 淡入 + 轻微缩放
   */
  private openQuotePreview(message: Message): void {
    this.quotedMessage = message;
    this.showQuotePreview = true;
    this.quotePreviewOpacity = 0;
    this.quotePreviewScale = 0.9;
    this.quotePreviewTranslateY = 10;
    animateTo({
      duration: 220,
      curve: Curve.EaseOut
    }, () => {
      this.quotePreviewOpacity = 1;
      this.quotePreviewScale = 1;
      this.quotePreviewTranslateY = 0;
    });
  }

  /**
   * 关闭引用预览（带动画）
   * 淡出 + 轻微收缩 + 向下滑出
   */
  private closeQuotePreview(): void {
    animateTo({
      duration: 180,
      curve: Curve.EaseIn
    }, () => {
      this.quotePreviewOpacity = 0;
      this.quotePreviewScale = 0.95;
      this.quotePreviewTranslateY = 8;
    });
    setTimeout(() => {
      this.quotedMessage = null;
      this.showQuotePreview = false;
      // 重置状态便于下次打开
      this.quotePreviewOpacity = 0;
      this.quotePreviewScale = 0.9;
      this.quotePreviewTranslateY = 10;
    }, 180);
  }

  /** 复制消息内容到系统剪贴板 */
  private async copyMessageToClipboard(m: Message): Promise<void> {
    try {
      const data: pasteboard.PasteData = pasteboard.createData(
        pasteboard.MIMETYPE_TEXT_PLAIN,
        m.content
      );
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      await board.setData(data);
      promptAction.showToast({ message: '已复制', duration: 1500 });
    } catch (e) {
      Logger.error(`[ChatPage] Copy to clipboard failed: ${JSON.stringify(e)}`);
    }
  }

  @Builder
  QuotePreviewBuilder() {
    Row() {
      // 左侧彩色竖线（与 Flutter 端对齐：我的消息用 primary，对方用 secondary）
      Column()
        .width(3)
        .height(32)
        .borderRadius(1.5)
        .backgroundColor(
          (this.quotedMessage !== null && this.quotedMessage.sender === 'me')
            ? $r('app.color.primary')
            : $r('app.color.text_secondary')
        )
        .margin({ right: 8 })

      Column() {
        Text(this.quotedMessage !== null && this.quotedMessage.sender === 'me' ? '引用我的消息' : '引用对方消息')
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 2 })

        Text(this.quotedMessage !== null ? this.quotePreviewText(this.quotedMessage) : '')
          .fontSize(13)
          .fontColor($r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Button({ type: ButtonType.Normal }) {
        Text('×')
          .fontSize(16)
          .fontColor($r('app.color.text_secondary'))
      }
      .width(28)
      .height(28)
      .backgroundColor(Color.Transparent)
      .onClick(() => {
        this.closeQuotePreview();
      })
    }
    .width('100%')
    .padding({ left: 12, right: 8, top: 8, bottom: 8 })
    .margin({ bottom: 12 })
    .backgroundColor($r('app.color.bg_base'))
    .borderRadius(8)
    .border({
      width: 1,
      color: (this.quotedMessage !== null && this.quotedMessage.sender === 'me')
        ? 'rgba(255, 107, 53, 0.3)'  // primary 30% 透明度（我的消息）
        : $r('app.color.primary_border')  // 对方消息
    })
    .opacity(this.quotePreviewOpacity)
    .scale({ x: this.quotePreviewScale, y: this.quotePreviewScale })
    .translate({ y: this.quotePreviewTranslateY })
  }

  @Builder
  MessageContextMenuBuilder() {
    Column() {
      // 半透明遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.5)')
        .opacity(1 - this.messageMenuTranslateY / 100)
        .onClick(() => {
          this.closeMessageContextMenu();
        })

      // 菜单内容（底部弹出）
      Column() {
        Row() {
          Text('📋')
            .fontSize(18)
            .margin({ right: 12 })
          Text('复制')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          const target: Message | null = this.menuTargetMessage;
          this.closeMessageContextMenu();
          if (target !== null) {
            this.copyMessageToClipboard(target);
          }
        })

        Row()
          .width('100%')
          .height(0.5)
          .backgroundColor($r('app.color.divider'))

        Row() {
          Text('💬')
            .fontSize(18)
            .margin({ right: 12 })
          Text('引用')
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          const target: Message | null = this.menuTargetMessage;
          this.closeMessageContextMenu();
          if (target !== null) {
            this.openQuotePreview(target);
          }
        })

        Row()
          .width('100%')
          .height(0.5)
          .backgroundColor($r('app.color.divider'))

        Row() {
          Text('🚩')
            .fontSize(18)
            .margin({ right: 12 })
          Text('举报')
            .fontSize(15)
            .fontColor('#E84855')
        }
        .width('100%')
        .height(48)
        .padding({ left: 16, right: 16 })
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.closeMessageContextMenu();
          // 复用房间级举报入口（与 Flutter 端一致，本期不增加单条消息举报字段）
          if (this.chatController !== null) {
            this.chatController.onReport(this.roomId);
          }
        })

        Row()
          .width('100%')
          .height(0.5)
          .backgroundColor($r('app.color.divider'))

        Row() {
          Text('取消')
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .height(48)
        .justifyContent(FlexAlign.Center)
        .alignItems(VerticalAlign.Center)
        .onClick(() => {
          this.closeMessageContextMenu();
        })
      }
      .width('100%')
      .backgroundColor($r('app.color.bg_card'))
      .borderRadius({ topLeft: 12, topRight: 12 })
      .position({ x: 0, y: '100%' })
      .translate({ x: 0, y: -100 + this.messageMenuTranslateY + '%' })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(300)
  }
}
