/**
 * 统一跨平台滚动物理参数
 *
 * 🔒 设计规范：
 * - Fling 摩擦系数 μ = 2.5
 * - 下拉刷新阻尼：有效拉伸距离 = 0.5 * 滑动距离 / (1 + 滑动距离 / 200)
 * - 与 Flutter 端 lib/theme/scroll_physics.dart 1:1 对齐
 */

export class ScrollPhysics {
  /** Fling 摩擦系数（Material Design 3 推荐值） */
  static readonly FLING_FRICTION: number = 2.5

  /** 阻尼系数（下拉刷新时的弹性） */
  static readonly DAMPING_FACTOR: number = 0.5

  /** 渐近极限距离（vp） */
  static readonly ASYMPTOTIC_LIMIT: number = 200.0

  /**
   * 计算下拉刷新时的阻尼有效距离
   * @param dragDistance 原始滑动距离
   * @returns 应用阻尼后的有效距离
   */
  static applyDamping(dragDistance: number): number {
    return ScrollPhysics.DAMPING_FACTOR * dragDistance /
      (1 + dragDistance / ScrollPhysics.ASYMPTOTIC_LIMIT)
  }
}

/**
 * List 滚动配置接口
 */
export interface ScrollConfigType {
  edgeEffect: EdgeEffect;
  scrollBar: boolean;
  nestedScroll: boolean;
}

/**
 * List 滚动配置
 * 在使用 Scroll/List 组件时应用此配置
 */
export const ScrollConfig: ScrollConfigType = {
  /** 边缘效果类型 */
  edgeEffect: EdgeEffect.None,
  /** 是否启用滚动条 */
  scrollBar: false,
  /** 嵌套滚动启用 */
  nestedScroll: true,
}
