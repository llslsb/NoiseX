import { Sonar } from '../model/Sonar';
import { Utils } from '../common/Utils';
import { Curve } from '../model/AnimationTokens';

// 声呐卡片组件
// UI 评审 P1（§3）：主路径二选一——忽略纯靠左滑（ReceiverPage.ets ListItem
// swipeAction），卡片只保留"响应"唯一主 CTA（与 Flutter SonarCard 同步）。
// 时间戳相对化自动刷新（30s）+ 随陈旧度衰减色：
// ≤5min 高亮 / ≤30min 次 灰 / 更旧更暗（Flutter 端 _timestampColor 同口径）。
@Component
export struct SonarCard {
  @Prop sonar: Sonar = { id: '', content: '', distance: '', timestamp: 0, geohash: '' };
  @State isHovered: boolean = false;
  @State hoverOffset: number = 0;
  @State fadeIn: number = 0;
  @State slideY: number = 20;
  @State now: number = Date.now();
  onAccept: (sonarId: string) => void = () => {};
  private refreshTimer: number = -1;

  aboutToAppear(): void {
    animateTo({ duration: 300, curve: Curve.EaseOut }, () => {
      this.fadeIn = 1;
      this.slideY = 0;
    });
    this.refreshTimer = setInterval(() => {
      this.now = Date.now();
    }, 30000);
  }

  aboutToDisappear(): void {
    if (this.refreshTimer !== -1) {
      clearInterval(this.refreshTimer);
      this.refreshTimer = -1;
    }
  }

  private timestampColor(): ResourceStr {
    const age: number = this.now - this.sonar.timestamp;
    if (age < 5 * 60 * 1000) {
      return $r('app.color.text_primary');
    }
    if (age < 30 * 60 * 1000) {
      return $r('app.color.text_muted');
    }
    return $r('app.color.text_secondary');
  }

  build() {
    Column() {
      // 元数据行
      Row() {
        Row() {
          Text('📍')
            .fontSize(12)
            .fontColor($r('app.color.primary'))

          Text(this.sonar.distance)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
        }

        Row() {
          Text('⏰')
            .fontSize(12)
            .fontColor($r('app.color.primary'))

          Text(Utils.formatRelativeTime(this.sonar.timestamp))
            .fontSize(12)
            .fontColor(this.timestampColor())
        }
        .margin({ left: 16 })
      }
      .margin({ bottom: 12 })

      // 声呐内容
      Text(`"${this.sonar.content}"`)
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .lineHeight(22.4)
        .margin({ bottom: 12 })

      // UI 评审 P1：唯一主 CTA——"响应"；忽略走卡片左滑
      Button('响应')
        .width('100%')
        .height(36)
        .backgroundColor($r('app.color.primary'))
        .fontColor($r('app.color.bg_base'))
        .fontSize(14)
        .fontFamily('monospace')
        .borderRadius(4)
        .margin({ top: 8 })
        .onClick(() => { this.onAccept(this.sonar.id); })
    }
    .padding(16)
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(8)
    .border({ width: 1, color: this.isHovered ? $r('app.color.card_border_hover') : $r('app.color.card_border') })
    .shadow(this.isHovered ? { radius: 20, color: '#1AFF6B35', offsetX: 0, offsetY: 0 } : { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
    .opacity(this.fadeIn)
    .translate({ y: this.slideY + this.hoverOffset })
    .animation({ duration: 300, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.isHovered = isHover;
      this.hoverOffset = isHover ? -2 : 0;
    })
  }
}
