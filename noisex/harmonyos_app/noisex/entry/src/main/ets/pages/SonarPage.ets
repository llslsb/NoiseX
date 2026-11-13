import { RadarAnimation } from '../components/RadarAnimation';
import { PulseButton } from '../components/PulseButton';
import { Constants } from '../model/Constants';
import { SonarInputTransitionState, createSonarInputTransitionState } from '../model/SonarTransition';
import { HapticService } from '../service/HapticService';
import { AnimationTokens, Curve } from '../model/AnimationTokens';

// 声呐主界面
//
// UI 评审 P2（§2-1）：占位示例每次打开轮换一句（示例池与 Flutter
// kSonarPlaceholderExamples 逐句对齐）；P0（§1-2）：冷却态补原因说明。

// 发送弹窗占位示例轮换池
const SONAR_PLACEHOLDER_EXAMPLES: string[] = [
  '有人看过昨晚的极光新闻吗？',
  '此时此刻你在想什么？',
  '这座城市的深夜是什么样的？',
  '有什么话必须此刻说出口？',
  '今天最后一个想分享的念头？',
];

@Component
export struct SonarPage {
  @StorageLink('sonarListeningEnabled') isListening: boolean = true;
  @State showInput: boolean = false;
  @State sonarContent: string = '';
  @State placeholderText: string = SONAR_PLACEHOLDER_EXAMPLES[0];
  @State inputTransition: SonarInputTransitionState = createSonarInputTransitionState(false);
  @State inputAnimating: boolean = false;
  private hideInputTimer: number = -1;
  @Prop cooldown: number = 0;
  @Prop nearbyCount: number = 0;  // P2-B：附近活跃用户数（真实计数）
  @Prop nearbyLoaded: boolean = false;  // false=探测中，true 后 0 人也如实显示
  @Prop blipCount: number = 0;    // P2-B：雷达信号点数量（0..8，随真实计数）
  @Prop sendingSonar: boolean = false;  // TASK-003: 发送中状态
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  public onSonarSent: ((content: string) => void) | null = null;
  public onOpenProfile: (() => void) | null = null;
  public onListeningChanged: ((enabled: boolean) => void) | null = null;

  aboutToDisappear(): void {
    if (this.hideInputTimer !== -1) {
      clearTimeout(this.hideInputTimer);
      this.hideInputTimer = -1;
    }
  }

  private revealInput(): void {
    if (this.inputAnimating || this.showInput) {
      return;
    }
    if (this.hideInputTimer !== -1) {
      clearTimeout(this.hideInputTimer);
      this.hideInputTimer = -1;
    }
    HapticService.getInstance().light();
    this.inputAnimating = true;
    this.showInput = true;
    // UI 评审 P2：每次打开轮换一条占位示例
    this.placeholderText =
      SONAR_PLACEHOLDER_EXAMPLES[Math.floor(Math.random() * SONAR_PLACEHOLDER_EXAMPLES.length)];
    this.inputTransition = createSonarInputTransitionState(false);
    // 统一使用 standard 缓动曲线，NOMRAL 时长 250ms
    this.getUIContext().animateTo({
      duration: AnimationTokens.NORMAL,
      curve: AnimationTokens.CURVE_STANDARD
    }, () => {
      this.inputTransition = createSonarInputTransitionState(true);
    });
    setTimeout(() => {
      this.inputAnimating = false;
    }, AnimationTokens.NORMAL);
  }

  private hideInput(): void {
    if (this.inputAnimating) {
      return;
    }
    this.inputAnimating = true;
    // 与打开动画完全对称：250ms，same curve，true → false
    this.getUIContext().animateTo({
      duration: AnimationTokens.NORMAL,
      curve: AnimationTokens.CURVE_STANDARD
    }, () => {
      this.inputTransition = createSonarInputTransitionState(false);
    });
    // 动画完成后清理状态
    this.hideInputTimer = setTimeout(() => {
      this.showInput = false;
      this.sonarContent = '';
      this.inputAnimating = false;
      this.hideInputTimer = -1;
    }, AnimationTokens.NORMAL);
  }

  build() {
    Stack() {
      // 雷达背景
      Stack() {
        RadarAnimation({ isActive: this.isListening, blipCount: this.blipCount })
      }
      .width('100%')
      .height('100%')
      .opacity(0.15)

      // 主内容
      Column() {
        // 顶部操作栏
        Row() {
          Blank()
          Row() {
            Text('设置')
              .fontSize(14)
              .fontColor($r('app.color.primary'))
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .borderRadius(16)
              .backgroundColor('rgba(255, 107, 53, 0.1)')
              .border({ width: 1, color: $r('app.color.primary_border') })
              .onClick(() => {
                if (this.onOpenProfile) {
                  this.onOpenProfile();
                }
              })
          }
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: this.statusBarHeight + 8 })

        // 状态文字
        Text('NOISEX')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.primary'))
          .letterSpacing(3.6)

        Text(this.isListening ? '> 收听模式已开启' : '> 静默模式')
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8, bottom: 32 })

        // 脉冲按钮或输入框
        if (!this.showInput) {
          Column() {
            PulseButton({
              cooldown: this.cooldown,
              isActive: this.isListening,
              onPulse: () => { this.revealInput(); }
            })
            // UI 评审 P0（§1-2）：冷却态补原因说明（此前只有裸秒数）
            if (this.cooldown > 0) {
              Text('冷却保护：每小时 3 次上限，防止刷屏')
                .fontSize(12)
                .fontColor($r('app.color.text_secondary'))
                .opacity(0.6)
                .margin({ top: 12 })
            }
          }
        } else {
          Stack({ alignContent: Alignment.Center }) {
            if (this.inputTransition.burstVisible) {
              Column()
                .width(120)
                .height(120)
                .borderRadius(60)
                .border({ width: 2, color: $r('app.color.primary') })
                .backgroundColor('rgba(255, 107, 53, 0.08)')
                .opacity(this.inputTransition.ringOpacity)
                .scale({ x: this.inputTransition.ringScale, y: this.inputTransition.ringScale })
                .hitTestBehavior(HitTestMode.None)
            }

            this.SonarInputBuilder()
          }
        }

        // 收听模式开关
        Row() {
          Text('收听模式')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))

          Toggle({ type: ToggleType.Switch, isOn: this.isListening })
            .onChange((isOn: boolean) => {
              this.isListening = isOn;
              if (this.onListeningChanged) {
                this.onListeningChanged(isOn);
              }
            })
            .selectedColor($r('app.color.primary'))
            .margin({ left: 12 })
        }
        .padding({ left: 16, right: 16, top: 8, bottom: 8 })
        .backgroundColor('rgba(19, 19, 26, 0.5)')
        .borderRadius(999)
        .border({ width: 1, color: $r('app.color.primary_border') })
        .margin({ top: 32 })

        // 附近活跃人数（P2-B 雷达 blip 真实化）
        // 三态：探测中 / 0 人如实显示 / 正常计数（2026-10-31 决策：不造假数据）
        // UI 评审 §13：提示类 ≥12px
        Text(this.nearbyLoaded
          ? (this.nearbyCount > 0 ? `附近约 ${this.nearbyCount} 人活跃` : '附近 0 人活跃')
          : '正在探测附近信号...')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .opacity(0.7)
          .margin({ top: 12 })

        // 提示文字（UI 评审 §1-5：与按钮语义重复的引导语替换为产品哲学文案）
        Column() {
          Text('每一次脉冲，只送给此刻在线的人')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))

          Text('匹配基于地理位置和时间，无算法干预')
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .opacity(0.6)
            .margin({ top: 4 })
        }
        .margin({ top: 16 })
        .constraintSize({ maxWidth: 280 })
      }
      .zIndex(10)
    }
    .width('100%')
    .layoutWeight(1)
    .backgroundColor($r('app.color.bg_base'))
    .alignContent(Alignment.Center)
  }

  @Builder
  SonarInputBuilder() {
    Column() {
      Text('> 发出声呐信号')
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 16 })

      TextArea({ placeholder: this.placeholderText, text: this.sonarContent })
        .maxLength(Constants.SONAR_MAX_LENGTH)
        .height(128)
        .backgroundColor($r('app.color.bg_base'))
        .border({ width: 1, color: $r('app.color.primary_border'), radius: 4 })
        .fontColor($r('app.color.text_primary'))
        .placeholderColor($r('app.color.text_secondary'))
        .onChange((value: string) => { this.sonarContent = value; })

      Row() {
        Text(`${this.sonarContent.length}/${Constants.SONAR_MAX_LENGTH}`)
          .fontSize(12)
          // UI 评审 P1：接近上限变色预警（≤120 灰 / 121-139 橙 / 140 红）
          .fontColor(this.sonarContent.length >= Constants.SONAR_MAX_LENGTH ?
            $r('app.color.error') :
            (this.sonarContent.length >= Constants.SONAR_MAX_LENGTH - 20 ?
              $r('app.color.primary') : $r('app.color.text_secondary')))

        Blank()

        Button('取消')
          .backgroundColor($r('app.color.bg_muted'))
          .fontColor($r('app.color.text_secondary'))
          .fontSize(14)
          .borderRadius(4)
          .enabled(!this.inputAnimating)
          .onClick(() => {
            this.hideInput();
          })

        Button(this.sendingSonar ? '发送中...' : '发送')
          .backgroundColor($r('app.color.primary'))
          .fontColor($r('app.color.bg_base'))
          .fontSize(14)
          .borderRadius(4)
          .margin({ left: 8 })
          .enabled(
            !this.inputAnimating &&
            !this.sendingSonar &&
            this.sonarContent.length > 0 &&
            this.sonarContent.length <= Constants.SONAR_MAX_LENGTH
          )
          .opacity(
            !this.inputAnimating &&
            !this.sendingSonar &&
            this.sonarContent.length > 0 &&
            this.sonarContent.length <= Constants.SONAR_MAX_LENGTH
              ? 1 : 0.5
          )
          .onClick(() => {
            if (this.onSonarSent) {
              this.onSonarSent(this.sonarContent);
            }
            this.hideInput();
          })
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
    .constraintSize({ maxWidth: 327 })
    .padding(24)
    .margin({ left: 24, right: 24 })
    .backgroundColor($r('app.color.bg_card'))
    .borderRadius(8)
    .border({ width: 2, color: 'rgba(255, 107, 53, 0.4)' })
    .shadow({ radius: 40, color: '#33FF6B35', offsetX: 0, offsetY: 0 })
    .opacity(this.inputTransition.introVisible ? 1 : 0)
    .scale({ x: this.inputTransition.inputScale, y: this.inputTransition.inputScale })
    .translate({ y: this.inputTransition.inputTranslateY })
  }
}
