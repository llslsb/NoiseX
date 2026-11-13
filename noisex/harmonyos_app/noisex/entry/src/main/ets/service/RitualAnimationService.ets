import { preferences } from '@kit.ArkData';
import { Logger } from '../common/Logger';
import { Constants } from '../model/Constants';

/// 仪式感动效服务
///
/// 负责三大仪式的视觉动效：
/// - 发送脉冲：全屏扩散波纹（每次发送都播放）
/// - 匹配成功：双 ping 撞击（每次匹配都播放）
/// - 风干仪式：淡出消散效果（房间过期时播放）
export class RitualAnimationService {
  private static instance: RitualAnimationService;

  private constructor() {}

  public static getInstance(): RitualAnimationService {
    if (!RitualAnimationService.instance) {
      RitualAnimationService.instance = new RitualAnimationService();
    }
    return RitualAnimationService.instance;
  }

  /// 旧版本遗留的"首次"标志键。升级后清理，避免残留。
  /// （历史上这两个动效只播放一次，现已改为每次都播放。）
  private static readonly LEGACY_KEY_FIRST_SONAR: string = 'ritual_first_sonar_completed';
  private static readonly LEGACY_KEY_FIRST_MATCH: string = 'ritual_first_match_completed';

  /// 仪式动效开关键（默认开启）。用户可在设置页关闭。
  private static readonly KEY_ANIM_ENABLED: string = 'ritual_animation_enabled';

  /// 清理旧版本遗留的"首次"标志。
  ///
  /// 应在应用启动阶段（EntryAbility）调用一次（幂等，可重复调用）。
  /// 旧版本会把发送脉冲/匹配成功动效设为只播一次，标志持久化后导致
  /// 升级用户再也看不到动效。这里主动清除，让升级用户恢复体验。
  public async cleanupLegacyFirstFlags(): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(getContext(), Constants.PREFS_NAME);
      await prefs.delete(RitualAnimationService.LEGACY_KEY_FIRST_SONAR);
      await prefs.delete(RitualAnimationService.LEGACY_KEY_FIRST_MATCH);
      await prefs.flush();
    } catch (e) {
      Logger.error(`[RitualAnimation] Cleanup legacy first flags failed: ${e}`);
    }
  }

  /// 读取仪式动效开关（默认开启）。
  public async isRitualAnimationEnabled(): Promise<boolean> {
    try {
      const prefs = await preferences.getPreferences(getContext(), Constants.PREFS_NAME);
      return await prefs.get(RitualAnimationService.KEY_ANIM_ENABLED, true) as boolean;
    } catch (e) {
      Logger.error(`[RitualAnimation] Read anim enabled failed: ${e}`);
      return true;
    }
  }

  /// 设置仪式动效开关。
  public async setRitualAnimationEnabled(enabled: boolean): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(getContext(), Constants.PREFS_NAME);
      await prefs.put(RitualAnimationService.KEY_ANIM_ENABLED, enabled);
      await prefs.flush();
    } catch (e) {
      Logger.error(`[RitualAnimation] Write anim enabled failed: ${e}`);
    }
  }
}

/// 首次脉冲全屏动效组件
@Builder
export function FirstPulseAnimation(onEnd: () => void): void {
  FirstPulseComponent({ onEnd: onEnd })
}

@Component
struct FirstPulseComponent {
  onEnd: () => void = () => {};
  @State textVisible: boolean = false;

  aboutToAppear(): void {
    // 渐显文字
    setTimeout(() => {
      this.textVisible = true;
    }, 300);

    // 自动结束
    setTimeout(() => {
      this.onEnd();
    }, 2000);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 半透明黑色背景
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.8)')

      // 扩散波纹（简化为静态圆环）
      Column() {
        ForEach([1, 2, 3], (item: number) => {
          Column()
            .width(`${120 + item * 40}%`)
            .height(`${120 + item * 40}%`)
            .border({
              color: '#FF6B35',
              width: 2
            })
            .borderRadius('50%')
            .opacity(0.5 - item * 0.15)
        }, (item: number) => item.toString())
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)

      // 中心内容
      Column({ space: 24 }) {
        Text('📡')
          .fontSize(80)

        Text('声呐已发送')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF6B35')
          .opacity(this.textVisible ? 1 : 0)

        Text('等待信号回响')
          .fontSize(14)
          .fontColor('#CCE8E8EA')
          .opacity(this.textVisible ? 1 : 0)
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      this.onEnd();
    })
  }
}

/// 首次匹配双 ping 撞击动效组件
@Builder
export function FirstMatchAnimation(onEnd: () => void): void {
  FirstMatchComponent({ onEnd: onEnd })
}

@Component
struct FirstMatchComponent {
  onEnd: () => void = () => {};
  @State textVisible: boolean = false;
  @State showFlash: boolean = false;

  aboutToAppear(): void {
    // 碰撞闪光
    setTimeout(() => {
      this.showFlash = true;
    }, 400);

    setTimeout(() => {
      this.showFlash = false;
    }, 700);

    // 文字渐显
    setTimeout(() => {
      this.textVisible = true;
    }, 900);

    // 自动结束
    setTimeout(() => {
      this.onEnd();
    }, 1800);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 半透明黑色背景
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0, 0, 0, 0.7)')

      // 碰撞闪光
      if (this.showFlash) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('rgba(255, 107, 53, 0.3)')
      }

      // 两个 ping 圆环（左侧和右侧）
      Row() {
        // 左侧 ping
        Column()
          .width(80)
          .height(80)
          .border({
            color: '#FF6B35',
            width: 4
          })
          .borderRadius('50%')
          .backgroundColor('rgba(255, 107, 53, 0.2)')

        Blank()
          .width('40%')

        // 右侧 ping
        Column()
          .width(80)
          .height(80)
          .border({
            color: '#FF6B35',
            width: 4
          })
          .borderRadius('50%')
          .backgroundColor('rgba(255, 107, 53, 0.2)')
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)

      // 中心碰撞效果
      Column()
        .width(80)
        .height(80)
        .border({
          color: '#FF6B35',
          width: 4
        })
        .borderRadius('50%')
        .backgroundColor('rgba(255, 107, 53, 0.2)')

      // 文字提示
      Column({ space: 16 }) {
        Text('⚡')
          .fontSize(60)

        Text('信号共振')
          .fontSize(28)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FF6B35')
          .opacity(this.textVisible ? 1 : 0)

        Text('与附近的人建立连接')
          .fontSize(14)
          .fontColor('#CCE8E8EA')
          .opacity(this.textVisible ? 1 : 0)
      }
    }
    .width('100%')
    .height('100%')
    .onClick(() => {
      this.onEnd();
    })
  }
}

/// 风干仪式动效组件
export function getWitheringSecondaryText(roomId: string): string {
  return '信号已消散';
}

@Builder
export function WitheringAnimation(roomId: string, onEnd: () => void): void {
  WitheringComponent({ roomId: roomId, onEnd: onEnd })
}

@Component
struct WitheringComponent {
  roomId: string = '';
  onEnd: () => void = () => {};
  @State textVisible: boolean = false;

  aboutToAppear(): void {
    // 文字渐显
    setTimeout(() => {
      this.textVisible = true;
    }, 300);

    // 自动结束
    setTimeout(() => {
      this.onEnd();
    }, 3000);
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 黑色背景
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#000000')

      // 中心文字
      Column({ space: 16 }) {
        Text('💨')
          .fontSize(60)

        Text('对话已风干')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor('#CCE8E8EA')
          .opacity(this.textVisible ? 1 : 0)

        Text(getWitheringSecondaryText(this.roomId))
          .fontSize(12)
          .fontColor('#80E8E8EA')
          .opacity(this.textVisible ? 1 : 0)
      }
    }
    .width('100%')
    .height('100%')
  }
}
