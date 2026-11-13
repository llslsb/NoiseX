/**
 * NoiseX 统一动画 Design Token
 *
 * 所有动画参数必须从这里引用，禁止硬编码数值。
 * 与 Flutter 端 lib/theme/animations.dart 保持 1:1 对齐。
 */

/**
 * Material Design 3 标准曲线枚举（字符串形式兼容 ArkUI 内置曲线）
 * 与 Flutter 端 lib/theme/animations.dart 保持 1:1 对齐
 */
export enum Curve {
  EaseIn = 'easeIn',
  EaseOut = 'easeOut',
  EaseInOut = 'easeInOut',
  EaseInOutSine = 'easeInOutSine',
  Spring = 'spring',
}

export class AnimationTokens {
  // ============================================================
  // 基础时长 Token (ms)
  // ============================================================

  /** 最快的微交互动画（按钮按下、状态切换） */
  static readonly FAST: number = 150

  /** 标准过渡动画（页面转场、Tab 切换） */
  static readonly NORMAL: number = 250

  /** 较慢的动画（模态弹出、面板展开） */
  static readonly SLOW: number = 300

  /** 缓慢动画（仪式感动效、雷达扫描） */
  static readonly VERY_SLOW: number = 2000

  // ============================================================
  // 场景化时长 Token
  // ============================================================

  /** 页面 push 转场时长 */
  static readonly PAGE_PUSH: number = 300

  /** 页面 pop 转场时长 */
  static readonly PAGE_POP: number = 250

  /** Tab 切换时长 */
  static readonly TAB_ACTIVATE: number = 250

  /** 打开弹窗时长 */
  static readonly OPEN_MODAL: number = 220

  /** 关闭弹窗时长 */
  static readonly CLOSE_MODAL: number = 180

  /** 列表项插入/移除时长 */
  static readonly LIST_ITEM: number = 200

  /** 消息气泡入场时长 */
  static readonly MESSAGE_BUBBLE_ENTER: number = 250

  /** 列表交错动画延迟（每条消息） */
  static readonly STAGGER_DELAY: number = 50

  /** 呼吸脉冲周期 */
  static readonly PULSE: number = 2000

  /** 房间即将过期脉冲 */
  static readonly EXPIRING_PULSE: number = 1000

  /** 雷达扫描周期 */
  static readonly RADAR_SWEEP: number = 4000

  /** 网络 Ping 动画 */
  static readonly PING: number = 2000

  /** 淡入淡出时长 */
  static readonly FADE_IN: number = 500
  static readonly FADE_IN_UP: number = 300
  static readonly SLIDE_UP: number = 300

  /** 打字指示器相位延迟 */
  static readonly TYPING_PHASE_DELAY: number = 200

  /** 触摸反馈微振动 */
  static readonly HAPTIC_FEEDBACK: number = 30

  // ============================================================
  // 标准曲线枚举（供 animateTo 使用，与 ArkTS 内置兼容）
  // ============================================================

  /** 标准缓入缓出 - Material Design 3 standard easing */
  static readonly CURVE_STANDARD: Curve = Curve.EaseInOut

  /** 减速曲线（元素入场：从快到慢）- Material Design 3 decelerate easing */
  static readonly CURVE_DECELERATE: Curve = Curve.EaseOut

  /** 加速曲线（元素离场：从慢到快）- Material Design 3 accelerate easing */
  static readonly CURVE_ACCELERATE: Curve = Curve.EaseIn

  /** 弹簧曲线（按钮、交互元素） */
  static readonly CURVE_SPRING: Curve = Curve.Spring

  /** 呼吸脉冲曲线 */
  static readonly CURVE_PULSE: Curve = Curve.EaseInOutSine

  /** 枚举值引用（用于组件内避免未类型化对象字面量） */
  static readonly CURVE_STANDARD_ENUM = Curve.EaseInOut
  static readonly CURVE_DECELERATE_ENUM = Curve.EaseOut
  static readonly CURVE_ACCELERATE_ENUM = Curve.EaseIn

  // ============================================================
  // 几何参数
  // ============================================================

  /** 消息气泡入场 Y 轴偏移量 */
  static readonly MESSAGE_BUBBLE_OFFSET_Y: number = 20

  /** 页面转场滑入偏移量 */
  static readonly PAGE_TRANSITION_OFFSET_X: number = 100

  /** Tab 图标呼吸透明度范围 */
  static readonly PULSE_MIN_OPACITY: number = 0.5
  static readonly PULSE_MAX_OPACITY: number = 1.0
}
