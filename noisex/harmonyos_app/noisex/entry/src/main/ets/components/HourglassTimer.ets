import { Constants } from '../model/Constants';
import { Utils } from '../common/Utils';
import { getNow } from '../model/ChatRoom';

@Component
export struct HourglassTimer {
  @Prop expiresAt: number;
  @State now: number = getNow();
  private timer: number = -1;

  aboutToAppear(): void {
    this.now = getNow();
    this.timer = setInterval(() => {
      this.now = getNow();
    }, 10000);
  }

  aboutToDisappear(): void {
    if (this.timer !== -1) {
      clearInterval(this.timer);
      this.timer = -1;
    }
  }

  build() {
    Row() {
      Text(Utils.isCriticalExpiring(this.expiresAt, this.now) ? '⚠️' : '⏳')
        .fontSize(16)

      Text(this.expiresAt > 0 ? Utils.formatTimeRemainingCN(this.expiresAt, this.now) : '--')
        .fontSize(14)
        .fontColor(this.getTimerColor())
        .margin({ left: 8 })

      if (this.expiresAt > 0) {
        Progress({
          value: Utils.getHourglassProgress(this.expiresAt, this.now),
          total: 100,
          type: ProgressType.Linear
        })
          .width(120)
          .height(8)
          .color(this.getProgressColor())
          .backgroundColor('rgba(255, 255, 255, 0.1)')
          .margin({ left: 8 })
          .borderRadius(4)
      }
    }
    .alignItems(VerticalAlign.Center)
  }

  private getTimerColor(): ResourceStr {
    if (this.expiresAt <= 0) {
      return $r('app.color.text_secondary');
    }
    // UI 评审 P0：倒计时三档色（>24h 灰 / <24h 橙 / <6h 红）
    const tier: string = Utils.expiryTier(this.expiresAt, this.now);
    if (tier === 'critical') {
      return $r('app.color.error');
    }
    if (tier === 'warning') {
      return $r('app.color.primary');
    }
    return $r('app.color.text_secondary');
  }

  private getProgressColor(): ResourceStr {
    const tier: string = Utils.expiryTier(this.expiresAt, this.now);
    if (tier === 'critical') {
      return $r('app.color.error');
    }
    if (tier === 'warning') {
      return $r('app.color.primary');
    }
    // >24h 灰档：进度条也降灰，与文本同档（Flutter 端同口径）
    return $r('app.color.text_secondary');
  }
}
