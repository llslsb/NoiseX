import { vibrator } from '@kit.SensorServiceKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';

/// 触觉反馈服务
///
/// 封装 @kit.SensorServiceKit vibrator API，对齐 Flutter 端 HapticFeedback 语义：
/// - selection(): 选择切换（Tab、列表项），最轻
/// - light():     轻触确认（按钮、loading 起始），中等偏轻
/// - medium():    中度强调（成功、达成阶段）
/// - heavy():     重度警示（错误、不可逆操作）
///
/// 通过全局开关 `enabled` 控制；用户在 ProfilePage 关闭后所有调用直接返回。
/// 设备不支持或调用失败时静默降级，不阻断 UI 流。
export class HapticService {
  private static instance: HapticService;
  private enabled: boolean = true;

  private constructor() {}

  public static getInstance(): HapticService {
    if (!HapticService.instance) {
      HapticService.instance = new HapticService();
    }
    return HapticService.instance;
  }

  /// 设置全局触觉反馈开关
  public setEnabled(enabled: boolean): void {
    this.enabled = enabled;
  }

  public isEnabled(): boolean {
    return this.enabled;
  }

  /// 选择性触觉（Tab 切换、选项切换）
  public selection(): void {
    this.preset('haptic.effect.soft', 10);
  }

  /// 轻触觉（按钮按下、loading 起始）
  public light(): void {
    this.preset('haptic.effect.soft', 20);
  }

  /// 中度触觉（成功、阶段达成）
  public medium(): void {
    this.preset('haptic.effect.sharp', 35);
  }

  /// 重度触觉（错误、警示）
  public heavy(): void {
    this.preset('haptic.effect.hard', 60);
  }

  /// 长振动（即将过期等关键提醒）
  public vibrate(): void {
    this.vibrateByTime(500);
  }

  private preset(effectId: string, fallbackDurationMs: number): void {
    if (!this.enabled) {
      return;
    }
    try {
      if (!vibrator.isSupportEffectSync(effectId)) {
        this.vibrateByTime(fallbackDurationMs);
        return;
      }
      vibrator.startVibration(
        {
          type: 'preset',
          effectId: effectId,
          count: 1
        },
        {
          id: 0,
          usage: 'touch'
        },
        (err: BusinessError) => {
          if (err) {
            this.vibrateByTime(fallbackDurationMs);
          }
        }
      );
    } catch (e) {
      this.vibrateByTime(fallbackDurationMs);
    }
  }

  private vibrateByTime(durationMs: number): void {
    if (!this.enabled) {
      return;
    }
    try {
      vibrator.startVibration(
        {
          type: 'time',
          duration: durationMs
        },
        {
          id: 0,
          usage: 'touch'
        },
        (err: BusinessError) => {
          if (err) {
            // 设备不支持或权限缺失：静默降级
            Logger.debug(`[Haptic] vibrate(${durationMs}ms) skipped: ${err.code} ${err.message}`);
          }
        }
      );
    } catch (e) {
      Logger.debug(`[Haptic] vibrate(${durationMs}ms) threw: ${e}`);
    }
  }
}
