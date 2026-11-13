import { ChatRoom, getUnreadMessageCount, isUnlockWindowAvailable } from '../model/ChatRoom';
import { Message } from '../model/Message';
import { Utils } from '../common/Utils';
import { Curve } from '../model/AnimationTokens';

// 房间卡片组件
@Component
export struct RoomCard {
  @Prop room: ChatRoom = {
    id: '',
    sonarContent: '',
    signalCode: '',
    createdAt: 0,
    expiresAt: 0,
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
  @Prop now: number = Date.now();
  @State isHovered: boolean = false;
  @State hoverOffset: number = 0;
  @State expiringPulse: number = 1;
  @State fadeIn: number = 0;
  @State slideY: number = 20;
  onEnter: (roomId: string) => void = () => {};
  private pulseTimer: number = -1;
  private pulsePhase: number = 0;

  aboutToAppear(): void {
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.fadeIn = 1;
      this.slideY = 0;
    });
    this.pulseTimer = setInterval(() => {
      this.pulsePhase = (this.pulsePhase + 1) % 20;
      if (this.pulsePhase < 10) {
        this.expiringPulse = 1 - 0.5 * (this.pulsePhase / 10);
      } else {
        this.expiringPulse = 0.5 + 0.5 * ((this.pulsePhase - 10) / 10);
      }
    }, 100);
  }

  aboutToDisappear(): void {
    if (this.pulseTimer !== -1) {
      clearInterval(this.pulseTimer);
    }
  }

  build() {
    Column() {
      // 头部
      Row() {
        Column() {
          Row() {
            Text(this.room.signalCode)
              .fontSize(12)
              .fontColor($r('app.color.primary'))

            Text(this.room.unlocked ? '🔓' : '🔒')
              .fontSize(12)
              .margin({ left: 8 })

            if (Utils.isCriticalExpiring(this.room.expiresAt, this.now)) {
              Text('⚠️')
                .fontSize(12)
                .fontColor($r('app.color.error'))
                .margin({ left: 8 })
            }
          }

          Text(`原始声呐: "${this.room.sonarContent}"`)
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row() {
          Text('💬')
            .fontSize(14)

          if (this.getUnreadCount() > 0) {
            Text(`${this.getUnreadCount()}`)
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.bg_base'))
              .backgroundColor($r('app.color.error'))
              .borderRadius(8)
              .constraintSize({ minWidth: 16 })
              .height(16)
              .textAlign(TextAlign.Center)
              .margin({ left: 4 })
          }
        }
      }

      // 最后消息
      if (this.room.messages.length > 0) {
        Text() {
          Span(`${this.getLastMessageSender()}: `)
            .fontColor($r('app.color.text_secondary'))
          Span(this.getLastMessageContent())
            .fontColor('#CCE8E8EA')
        }
        .fontSize(14)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ top: 8, bottom: 12 })
      }

      // 时间进度
      Row() {
        Text() {
          if (Utils.isCriticalExpiring(this.room.expiresAt, this.now)) {
            Span('⚠️ ')
          }
          Span(`剩余: ${Utils.formatTimeRemainingCN(this.room.expiresAt, this.now)}`)
        }
        .fontSize(12)
        // UI 评审 P0：倒计时三档色（>24h 灰 / <24h 橙 / <6h 红）
        .fontColor(this.getTierColor())

        if (this.room.deepConnectionAchieved && !this.room.unlocked) {
          Text('● 可解锁')
            .fontSize(10)
            .fontColor($r('app.color.primary'))
            .margin({ left: 8 })
        } else if (this.room.bothSaveConfirmed) {
          Text('❤️ 已保存')
            .fontSize(10)
            .fontColor($r('app.color.primary'))
            .margin({ left: 8 })
        } else if (!this.room.unlocked && !this.room.deepConnectionAchieved &&
          this.room.createdAt > 0 && !isUnlockWindowAvailable(this.room.createdAt)) {
          Text('● 窗口已关闭')
            .fontSize(10)
            .fontColor($r('app.color.text_secondary'))
            .margin({ left: 8 })
        }
      }
      .width('100%')
      .margin({ bottom: 4 })

      // 进度条
      Progress({
        value: Utils.getHourglassProgress(this.room.expiresAt, this.now),
        total: 100,
        type: ProgressType.Linear
      })
        .color(this.getTierColor())
        .backgroundColor($r('app.color.bg_muted'))
        .height(4)
        // UI 评审 P0：脉冲呼吸只属红色警戒档（<6h）
        .opacity(Utils.isCriticalExpiring(this.room.expiresAt, this.now) ? this.expiringPulse : 1)
    }
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(8)
    .border({ width: 1, color: this.isHovered ? $r('app.color.card_border_hover') : $r('app.color.card_border') })
    .shadow(this.isHovered ? { radius: 20, color: '#1AFF6B35', offsetX: 0, offsetY: 0 } : { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
    .opacity(this.fadeIn)
    .translate({ y: this.slideY + this.hoverOffset })
    .animation({ duration: 300, curve: Curve.EaseOut })
    .onClick(() => { this.onEnter(this.room.id); })
    .onHover((isHover: boolean) => {
      this.isHovered = isHover;
      this.hoverOffset = isHover ? -2 : 0;
    })
  }

  private getUnreadCount(): number {
    return getUnreadMessageCount(this.room.messages, this.room.lastReadMessageId);
  }

  private getTierColor(): ResourceStr {
    const tier: string = Utils.expiryTier(this.room.expiresAt, this.now);
    if (tier === 'critical') {
      return $r('app.color.error');
    }
    if (tier === 'warning') {
      return $r('app.color.primary');
    }
    return $r('app.color.text_secondary');
  }

  // UI 评审 P1（§4-5）：房号是系统词汇，预览人称改"对方"（Flutter 端同步）
  private getLastMessageSender(): string {
    const lastMsg: Message = this.room.messages[this.room.messages.length - 1];
    return lastMsg.sender === 'me' ? '你' : '对方';
  }

  private getLastMessageContent(): string {
    const lastMsg: Message = this.room.messages[this.room.messages.length - 1];
    return lastMsg.content;
  }
}
