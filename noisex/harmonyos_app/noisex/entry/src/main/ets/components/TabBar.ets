import { AnimationTokens, Curve } from '../model/AnimationTokens';
import { HapticService } from '../service/HapticService';
import { Constants } from '../model/Constants';

/**
 * 底部导航栏组件
 *
 * 与 Flutter 端 1:1 对齐：
 * - 统一深色平面风格（已移除玻璃效果，提升低端设备性能）
 * - 顶部 0.5px 白色 10% 透明高光分隔
 * - 图标统一为 emoji (📡🎤⏳)，大小 22sp
 * - Pulse 动画使用 animateTo() API + easeInOutSine 曲线
 * - 切 Tab 触发选择触觉反馈
 */
@Component
export struct TabBar {
  @Link activeTabIndex: number;
  @Prop receiverCount: number = 0;
  @Prop roomCount: number = 0;
  // 底部导航条避让高度（Index.refreshAvoidAreas 维护，avoidAreaChange 联动刷新）
  @StorageProp('bottomAvoidHeight') bottomAvoidHeight: number = 32;
  onTabSelected: (index: number) => void = () => {};
  @State pulseOpacity: number = AnimationTokens.PULSE_MAX_OPACITY;
  private pulseTimer: number = -1;

  aboutToAppear(): void {
    // 使用 animateTo() 替代 setInterval，60fps 流畅动画
    this.startPulseAnimation();
  }

  aboutToDisappear(): void {
    if (this.pulseTimer !== -1) {
      clearInterval(this.pulseTimer);
    }
  }

  /**
   * 启动 Tab 图标呼吸脉冲动画
   *
   * 使用 animateTo 实现平滑曲线动画，与 Flutter 端
   * AnimationController + Curves.easeInOutSine 效果对齐
   */
  private startPulseAnimation(): void {
    const animatePulse = () => {
      // 暗下去 - ArkTS animateTo 需要两个参数: (options, callback)
      animateTo(
        {
          duration: AnimationTokens.PULSE / 2,
          curve: Curve.EaseInOut,
          tempo: 1.0,
          delay: 0,
          iterations: 1,
          playMode: PlayMode.Normal,
          onFinish: () => {
            // 亮回来
            animateTo(
              {
                duration: AnimationTokens.PULSE / 2,
                curve: Curve.EaseInOut,
                tempo: 1.0,
                delay: 0,
                iterations: 1,
                playMode: PlayMode.Normal,
                onFinish: () => {
                  if (this.pulseTimer !== -1) {
                    animatePulse();
                  }
                }
              },
              () => {
                this.pulseOpacity = AnimationTokens.PULSE_MAX_OPACITY;
              }
            );
          }
        },
        () => {
          this.pulseOpacity = AnimationTokens.PULSE_MIN_OPACITY;
        }
      );
    };

    // 立即启动第一个周期，用 setTimeout 避免与动画系统冲突
    this.pulseTimer = setTimeout(() => {
      animatePulse();
      // 之后每个完整周期用 setInterval 调度
      this.pulseTimer = setInterval(() => {
        animatePulse();
      }, AnimationTokens.PULSE);
    }, 0);
  }

  @Builder
  badgeText(count: number) {
    Text(`${count}`)
      .fontSize(10)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('app.color.bg_base'))
      .backgroundColor($r('app.color.primary'))
      .borderRadius(8)
      .width(16)
      .height(16)
      .textAlign(TextAlign.Center)
      .position({ x: '100%', y: 0 })
      .translate({ x: '-50%', y: '-40%' })
  }

  build() {
    Row() {
      // 声呐 Tab (index 0)
      Column({ space: 2 }) {
        Text('📡')
          .fontSize(22)
          .opacity(this.activeTabIndex === 0 ? this.pulseOpacity : 1)

        Text('声呐')
          .fontSize(11)
          .fontColor(this.activeTabIndex === 0 ?
            $r('app.color.primary') : $r('app.color.text_secondary'))
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .layoutWeight(1)
      .onClick(() => {
        this.onTabSelected(0);
        HapticService.getInstance().selection();
      })

      // 接收器 Tab (index 1)
      Column({ space: 2 }) {
        Stack() {
          Text('🎤')
            .fontSize(22)
            .opacity(this.activeTabIndex === 1 ? this.pulseOpacity : 1)

          if (this.receiverCount > 0) {
            this.badgeText(this.receiverCount)
          }
        }
        .width(26)
        .height(26)
        .alignContent(Alignment.TopEnd)

        Text('接收器')
          .fontSize(11)
          .fontColor(this.activeTabIndex === 1 ?
            $r('app.color.primary') : $r('app.color.text_secondary'))
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.onTabSelected(1);
        HapticService.getInstance().selection();
      })
      .layoutWeight(1)

      // 沙漏 Tab (index 2)
      Column({ space: 2 }) {
        Stack() {
          Text('⏳')
            .fontSize(22)
            .opacity(this.activeTabIndex === 2 ? this.pulseOpacity : 1)

          if (this.roomCount > 0) {
            this.badgeText(this.roomCount)
          }
        }
        .width(26)
        .height(26)
        .alignContent(Alignment.TopEnd)

        Text('沙漏')
          .fontSize(11)
          .fontColor(this.activeTabIndex === 2 ?
            $r('app.color.primary') : $r('app.color.text_secondary'))
      }
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        this.onTabSelected(2);
        HapticService.getInstance().selection();
      })
      .layoutWeight(1)
    }
    // 总高 = 64vp 内容区 + 导航条避让：padding 把图标/文字抬到导航条之上，
    // expandSafeArea 让深色底继续铺到条下（背景融合，不露白）
    .height(Constants.TAB_BAR_HEIGHT + this.bottomAvoidHeight)
    .width('100%')
    .padding({ left: 0, right: 0, top: 0, bottom: this.bottomAvoidHeight })
    .backgroundColor($r('app.color.bg_base'))
    // 与 Flutter 端对齐：顶部 0.5px 白色 10% 透明高光分隔
    .border({ width: { top: 0.5 }, color: '#1AFFFFFF' })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
