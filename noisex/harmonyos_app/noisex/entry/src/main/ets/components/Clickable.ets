import { AnimationTokens } from '../model/AnimationTokens'

/**
 * 统一跨平台按压态组件
 *
 * 🔒 设计规范：
 * - 按下时叠加 10% 黑色遮罩
 * - 150ms standard easing 淡入淡出动画
 * - 与 Flutter 端 lib/widgets/clickable.dart 1:1 对齐
 */

@Component
export struct Clickable {
  @Prop child?: () => void
  @Prop onTap?: () => void
  @Prop borderRadius?: Length | BorderRadiuses
  @Prop enabled: boolean = true

  @State overlayOpacity: number = 0

  private animateToOpacity(opacity: number): void {
    if (!this.enabled) {
      return
    }
    // 使用枚举曲线值避免未类型化对象字面量问题
    animateTo({
      duration: AnimationTokens.FAST,
      curve: AnimationTokens.CURVE_STANDARD_ENUM,
      onFinish: () => {},
    }, () => {
      this.overlayOpacity = opacity
    })
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      if (this.child) {
        this.child()
      }

      // 10% 黑色遮罩层
      Rectangle()
        .width('100%')
        .height('100%')
        .fillColor('#1A000000')
        .opacity(this.overlayOpacity)
        .borderRadius(this.borderRadius || 0)
    }
    .onTouch((event) => {
      if (!this.enabled) {
        return
      }
      switch (event.type) {
        case TouchType.Down:
          this.animateToOpacity(1)
          break
        case TouchType.Up:
          this.animateToOpacity(0)
          if (this.onTap) {
            this.onTap()
          }
          break
        case TouchType.Cancel:
          this.animateToOpacity(0)
          break
      }
    })
  }
}
