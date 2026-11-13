// 脉冲按钮组件（含 ping 扩散动画 - 心跳脉冲效果）
//
// 流畅性重构（2026-11-03 用户反馈"不如 Flutter 端流畅"）：
// 旧版 setInterval 50ms JS 定时器逐帧推进 ping/呼吸共 8 个 @State，且 ping
// 圆环靠改 width/height 每帧触发布局——定时器漂移 + 20Hz 步进 + 布局抖动，
// 帧率上不去。现全部改为渲染引擎驱动的无限 animateTo：ping 用 scale（纯
// 渲染变换，不触发布局）+ opacity，1s 扩散三层 0.5s 错相（setTimeout 一次性
// 偏移 + 无限循环 = 永久错相，对齐 Flutter 2s 周期三段 Interval 的心跳节奏）；
// 呼吸用 PlayMode.Alternate 往返。与 Flutter AnimationController.repeat() 同级丝滑。
//
// 光晕修复（样式不一致实锤）：旧版 .shadow(radius:40) 在 OHOS 上按组件方形
// 边框渲染，按钮背后出现"方形暗板"（Mate X7 截图实锤）。改为径向渐变圆盘
// 模拟 Flutter boxShadow 的圆形光晕。
import { Utils } from '../common/Utils';

@Component
export struct PulseButton {
  @Prop cooldown: number = 0;
  @Prop isActive: boolean = true;
  onPulse: () => void = () => {};
  @State pingScale1: number = 1;
  @State pingOpacity1: number = 0.3;
  @State pingScale2: number = 1;
  @State pingOpacity2: number = 0.2;
  @State pingScale3: number = 1;
  @State pingOpacity3: number = 0.15;
  @State pressScale: number = 1;
  @State hoverScale: number = 1;
  @State breathScale: number = 1;
  private startTimers: number[] = [];

  aboutToAppear(): void {
    // ping 扩散三层：1s 内 scale 1→1.5、opacity 层初始→0，无限循环；
    // iteration 回弹起点瞬间 opacity 已为 0，无跳变感。0/500/1000ms 错相。
    this.startTimers.push(setTimeout(() => {
      this.getUIContext().animateTo({
        duration: 1000, curve: Curve.Linear, iterations: -1
      }, () => {
        this.pingScale1 = 1.5;
        this.pingOpacity1 = 0;
      });
    }, 0));
    this.startTimers.push(setTimeout(() => {
      this.getUIContext().animateTo({
        duration: 1000, curve: Curve.Linear, iterations: -1
      }, () => {
        this.pingScale2 = 1.5;
        this.pingOpacity2 = 0;
      });
    }, 500));
    this.startTimers.push(setTimeout(() => {
      this.getUIContext().animateTo({
        duration: 1000, curve: Curve.Linear, iterations: -1
      }, () => {
        this.pingScale3 = 1.5;
        this.pingOpacity3 = 0;
      });
    }, 1000));

    // 主按钮呼吸：1↔0.97 缓入缓出往返（近似 Flutter TweenSequence 心跳节奏：
    // 快速收缩→缓慢舒张），引擎驱动不占 JS 线程
    this.getUIContext().animateTo({
      duration: 1000,
      curve: Curve.EaseInOut,
      iterations: -1,
      playMode: PlayMode.Alternate
    }, () => {
      this.breathScale = 0.97;
    });
  }

  aboutToDisappear(): void {
    // 只需清理错相用的 setTimeout；无限 animateTo 随组件销毁自动终止
    for (const t of this.startTimers) {
      clearTimeout(t);
    }
    this.startTimers = [];
  }

  // ping/光晕只在空闲且未冷却时可见（对齐 Flutter showPing 口径）
  private pingVisible(): boolean {
    return this.isActive && this.cooldown <= 0;
  }

  build() {
    Stack() {
      // 圆形光晕（径向渐变模拟 Flutter boxShadow blur 40，替代方形 .shadow；
      // 注意必须用普通组件承载 radialGradient——Shape 类 Circle 默认黑 fill
      // 会盖住渐变渲染成黑盘）
      Column()
        .width(200)
        .height(200)
        .borderRadius(100)
        .radialGradient({
          center: ['50%', '50%'],
          radius: 100,
          colors: [['rgba(255,107,53,0.20)', 0], ['rgba(255,107,53,0.0)', 1]]
        })
        .opacity(this.pingVisible() ? 1 : 0)
        .hitTestBehavior(HitTestMode.None)

      // 外围 ping 扩散层1（固定尺寸 + scale 纯渲染变换，不再改 width/height）
      Circle()
        .width(120)
        .height(120)
        .fill(Color.Transparent)
        .stroke($r('app.color.primary'))
        .strokeWidth(1)
        .scale({ x: this.pingScale1, y: this.pingScale1 })
        .opacity(this.pingVisible() ? this.pingOpacity1 : 0)
        .hitTestBehavior(HitTestMode.None)

      // 外围 ping 扩散层2
      Circle()
        .width(120)
        .height(120)
        .fill(Color.Transparent)
        .stroke($r('app.color.primary'))
        .strokeWidth(1)
        .scale({ x: this.pingScale2, y: this.pingScale2 })
        .opacity(this.pingVisible() ? this.pingOpacity2 : 0)
        .hitTestBehavior(HitTestMode.None)

      // 外围 ping 扩散层3
      Circle()
        .width(120)
        .height(120)
        .fill(Color.Transparent)
        .stroke($r('app.color.primary'))
        .strokeWidth(1)
        .scale({ x: this.pingScale3, y: this.pingScale3 })
        .opacity(this.pingVisible() ? this.pingOpacity3 : 0)
        .hitTestBehavior(HitTestMode.None)

      // 主按钮圆（不加 .shadow——OHOS 按方形边框渲染会出方形暗板）
      Circle()
        .width(120)
        .height(120)
        .fill(this.cooldown > 0 ? $r('app.color.bg_muted') : $r('app.color.primary_input'))
        .stroke(this.cooldown > 0 ? $r('app.color.bg_accent') : $r('app.color.primary'))
        .strokeWidth(4)
        .scale({ x: this.cooldown > 0 ? 1 : this.breathScale, y: this.cooldown > 0 ? 1 : this.breathScale })

      // 按钮内容
      Column() {
        if (this.cooldown > 0) {
          // UI 评审 P0：裸秒数→格式化恢复时刻（m:ss），双端同款
          Text(Utils.formatCooldown(this.cooldown))
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_secondary'))

          Text('冷却中')
            .fontSize(11)
            .fontColor($r('app.color.text_secondary'))
            .margin({ top: 4 })
        } else {
          Text('📡')
            .fontSize(40)
            .margin({ bottom: 6 })

          Text('发送脉冲')
            .fontSize(12)
            .fontColor($r('app.color.primary'))
        }
      }
      .hitTestBehavior(HitTestMode.None)
    }
    .width(120)
    .height(120)
    .scale({ x: this.pressScale * this.hoverScale, y: this.pressScale * this.hoverScale })
    .animation({ duration: 150, curve: Curve.EaseOut })
    .onClick(() => {
      if (this.cooldown <= 0) {
        this.onPulse();
      }
    })
    .onHover((isHover: boolean) => {
      if (this.cooldown > 0) return;
      this.hoverScale = isHover ? 1.05 : 1.0;
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressScale = 0.95;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressScale = 1.0;
      }
    })
  }
}
