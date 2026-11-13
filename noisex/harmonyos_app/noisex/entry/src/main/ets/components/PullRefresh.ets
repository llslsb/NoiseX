import { ScrollPhysics } from '../model/ScrollPhysics'
import { AnimationTokens } from '../model/AnimationTokens'

/**
 * 统一跨平台下拉刷新组件
 *
 * 🔒 设计规范：
 * - 阻尼公式：有效拉伸距离 = 0.5 * 滑动距离 / (1 + 滑动距离 / 200)
 * - 触发阈值：80vp（应用阻尼后的值）
 * - 回弹动画：300ms standard easing
 * - 与 Flutter 端 lib/widgets/pull_refresh.dart 1:1 对齐
 */

@Component
export struct PullRefresh {
  @Prop child?: () => void
  onRefresh: () => Promise<void> = () => Promise.resolve()

  @State private dragDistance: number = 0
  @State private isRefreshing: boolean = false
  @State private triggered: boolean = false

  private static readonly TRIGGER_DISTANCE: number = 80.0
  private static readonly MAX_DRAG_DISTANCE: number = 250.0

  /**
   * 应用统一阻尼公式
   */
  private get effectiveDistance(): number {
    return ScrollPhysics.applyDamping(this.dragDistance)
  }

  /**
   * 是否达到触发阈值
   */
  private get canTrigger(): boolean {
    return this.effectiveDistance >= PullRefresh.TRIGGER_DISTANCE
  }

  private handleDragUpdate(deltaY: number): void {
    if (this.isRefreshing) {
      return
    }
    this.dragDistance = Math.max(0, Math.min(
      PullRefresh.MAX_DRAG_DISTANCE,
      this.dragDistance + deltaY
    ))
    this.triggered = false
  }

  private async handleDragEnd(): Promise<void> {
    if (this.isRefreshing) {
      return
    }

    if (this.canTrigger && !this.triggered) {
      this.triggered = true
      // 回弹到刷新位置
      await this.bounceToRefreshPosition()
      // 执行刷新
      await this.performRefresh()
    } else {
      // 回弹到起始位置
      await this.bounceBack()
    }
  }

  /**
   * 回弹到刷新位置
   */
  private async bounceToRefreshPosition(): Promise<void> {
    return new Promise((resolve) => {
      const startDistance = this.dragDistance
      const targetDistance = PullRefresh.TRIGGER_DISTANCE
      const totalDelta = targetDistance - startDistance
      const startTime = Date.now()
      const duration = AnimationTokens.SLOW // 300ms

      const animateStep = () => {
        const elapsed = Date.now() - startTime
        const t = Math.min(1, elapsed / duration)
        // 应用 standard easing 曲线
        const easedT = this.applyStandardEasing(t)
        this.dragDistance = startDistance + totalDelta * easedT

        if (t < 1) {
          setTimeout(animateStep, 16) // ~60fps
        } else {
          resolve()
        }
      }
      animateStep()
    })
  }

  /**
   * 回弹到起始位置
   */
  private async bounceBack(): Promise<void> {
    return new Promise((resolve) => {
      const startDistance = this.dragDistance
      const startTime = Date.now()
      const duration = AnimationTokens.SLOW // 300ms

      const animateStep = () => {
        const elapsed = Date.now() - startTime
        const t = Math.min(1, elapsed / duration)
        // 应用 standard easing 曲线
        const easedT = this.applyStandardEasing(t)
        this.dragDistance = startDistance * (1 - easedT)

        if (t < 1) {
          setTimeout(animateStep, 16) // ~60fps
        } else {
          this.dragDistance = 0
          resolve()
        }
      }
      animateStep()
    })
  }

  /**
   * 标准缓动曲线 Cubic(0.2, 0, 0.2, 1)
   */
  private applyStandardEasing(t: number): number {
    // 三次贝塞尔近似计算
    return t * t * (3 - 2 * t)
  }

  /**
   * 执行刷新逻辑
   */
  private async performRefresh(): Promise<void> {
    this.isRefreshing = true
    try {
      await this.onRefresh()
    } finally {
      this.isRefreshing = false
      // 刷新完成后回弹
      await this.bounceBack()
    }
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      // 列表内容
      if (this.child) {
        this.child()
      }
        .translate({ x: 0, y: this.effectiveDistance })
        .onTouch((event) => {
          switch (event.type) {
            case TouchType.Move:
              this.handleDragUpdate(event.touches[0].y)
              break
            case TouchType.Up:
            case TouchType.Cancel:
              this.handleDragEnd()
              break
          }
        })

      // 刷新指示器（位于列表上方，随下拉出现）
      if (this.effectiveDistance > 0 || this.isRefreshing) {
        Column() {
          LoadingProgress()
            .color(this.canTrigger ? '#FF6B35' : '#8A8A9A')
            .width(32)
            .height(32)
        }
        .width('100%')
        .height(PullRefresh.TRIGGER_DISTANCE)
        .justifyContent(FlexAlign.Center)
        .translate({
          x: 0,
          y: this.effectiveDistance - PullRefresh.TRIGGER_DISTANCE
        })
      }
    }
    .width('100%')
    .height('100%')
  }
}
