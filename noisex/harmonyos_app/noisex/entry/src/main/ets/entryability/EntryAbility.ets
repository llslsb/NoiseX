import { AbilityConstant, ConfigurationConstant, UIAbility, Want, abilityAccessCtrl, common, Permissions, wantAgent } from '@kit.AbilityKit';
import type { WantAgent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';
import backgroundTaskManager from '@ohos.resourceschedule.backgroundTaskManager';
import { AuthService } from '../service/AuthService';
import { LocationService } from '../service/LocationService';
import { WsService } from '../service/WsService';
import { StorageService } from '../service/StorageService';
import { CryptoService } from '../service/CryptoService';
import { PushService } from '../service/PushService';
import { RitualAnimationService } from '../service/RitualAnimationService';
import { Logger } from '../common/Logger';
import { Constants } from '../model/Constants';

export default class EntryAbility extends UIAbility {
  private backgroundTaskId: number = -1;
  // 供协议门"同意"回调补做定位权限申请（onCreate 阶段的申请已按协议标记延后）
  private static appContext: common.UIAbilityContext | null = null;
  private static initPromise: Promise<void> = Promise.resolve();

  public static getInitPromise(): Promise<void> {
    return EntryAbility.initPromise;
  }

  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      this.context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
    } catch (err) {
      Logger.error('Failed to set colorMode');
    }
    Logger.info('Ability onCreate');
    EntryAbility.appContext = this.context;

    EntryAbility.initPromise = Promise.all([
      AuthService.getInstance().init(this.context),
      StorageService.getInstance().init(this.context)
    ]).then(() => {
      Logger.info('AuthService & StorageService initialized');
      // B18：恢复持久化的 E2EE 共享密钥（重启后历史可解密、加密会话可续）
      return CryptoService.getInstance().restorePersistedKeys();
    }).then(() => {
      // 清理旧版本遗留的"首次仪式"标志（旧版动效只播一次，现已改为每次都播）
      return RitualAnimationService.getInstance().cleanupLegacyFirstFlags();
    }).then(() => {
      // 隐私合规：推送 SDK 初始化涉及网络与设备信息上报，华为审核要求
      // "未同意隐私政策不得初始化采集 SDK"。已同意（老用户）此处直接 init；
      // 未同意（首装）由 Index 协议门"同意"回调补 init。
      if (AuthService.getInstance().isPrivacyAgreed()) {
        return PushService.getInstance().init();
      }
      Logger.info('PushService init deferred: privacy not agreed');
      return Promise.resolve();
    }).catch((err: Object) => {
      Logger.error(`Init failed: ${err}`);
    });

    // 仅注入依赖（纯赋值不联网）；init 已按协议标记延后（见 initPromise 链尾）
    PushService.getInstance().setContext(this.context);
    PushService.getInstance().setAbility(this);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    Logger.info('Ability onNewWant');
    // 处理推送通知点击跳转
    if (want.parameters !== null && want.parameters !== undefined) {
      const roomId: string = (want.parameters['roomId'] as string) ?? '';
      const pushType: string = (want.parameters['type'] as string) ?? '';
      if (roomId.length > 0) {
        PushService.getInstance().handleNotificationClick({ roomId: roomId, type: pushType });
      }
    }
  }

  onDestroy(): void {
    Logger.info('Ability onDestroy');

    // 清理服务
    WsService.getInstance().disconnect();
    LocationService.getInstance().stopLocation();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    Logger.info('Ability onWindowStageCreate');

    // 设置窗口全屏沉浸式
    windowStage.getMainWindow().then((win: window.Window) => {
      win.setWindowLayoutFullScreen(true);
      const sysBarProps: window.SystemBarProperties = {
        statusBarColor: '#00000000',
        statusBarContentColor: '#FF6B35'
      };
      win.setWindowSystemBarProperties(sysBarProps);
    }).catch(() => {
      Logger.error('Failed to set window properties');
    });

    windowStage.loadContent('pages/Index', (err, data) => {
      if (err !== null && err.code) {
        Logger.error('Failed to load the content');
        return;
      }
      Logger.info('Succeeded in loading the content');
      // 隐私合规：定位权限申请必须发生在用户同意协议之后（华为审核案例：
      // "未经用户同意已开始收集个人信息（包括提前申请权限）"属驳回项）。
      // 首装未同意时延后，由 Index 协议门"同意"回调经 requestLocationPermissionIfAgreed 补做。
      if (AuthService.getInstance().isPrivacyAgreed()) {
        this.requestLocationPermission();
      } else {
        Logger.info('Location permission request deferred: privacy not agreed');
      }
    });
  }

  onWindowStageDestroy(): void {
    Logger.info('Ability onWindowStageDestroy');
  }

  onForeground(): void {
    Logger.info('Ability onForeground');

    if (this.backgroundTaskId !== -1) {
      try {
        backgroundTaskManager.stopBackgroundRunning(this.context, (err: BusinessError) => {
          if (err) {
            Logger.error(`Stop background task failed: ${err.message}`);
          } else {
            Logger.info('Background task stopped');
            this.backgroundTaskId = -1;
          }
        });
      } catch (e) {
        Logger.error(`Stop background task exception: ${e}`);
      }
    }

    // 前台重启定位前须已同意协议（协议门展示期间回前台不得绕过"同意才采集"）。
    // 冷启动竞态修复（2026-11-02 真机实锤）：privacyAgreed 由 AuthService.init()
    // 异步加载，onForeground 先于 init 完成执行（实测早 73ms），同步判定恒为
    // false → startLocation 从不执行 → 定位流死流、雷达永远"探测中"。
    // 必须等 initPromise 完成后再判定（与下方 WS connect 同款写法）。
    EntryAbility.initPromise.then(() => {
      if (AuthService.getInstance().isPrivacyAgreed()) {
        LocationService.getInstance().startLocation();
      }
    });

    EntryAbility.initPromise.then(() => {
      const token: string = AuthService.getInstance().getToken();
      if (token.length > 0) {
        WsService.getInstance().connect();
      } else {
        Logger.warn('[EntryAbility] Skip WS connect: token not ready');
      }
    });
  }

  onBackground(): void {
    Logger.info('Ability onBackground');

    // 申请后台长连接任务，保持 WebSocket 心跳
    try {
      // 构建 WantAgent 用于通知点击跳转回应用
      const wantAgentInfo: wantAgent.WantAgentInfo = {
        wants: [
          {
            bundleName: this.context.abilityInfo.bundleName,
            abilityName: 'EntryAbility'
          }
        ],
        operationType: wantAgent.OperationType.START_ABILITY,
        requestCode: 0,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };

      wantAgent.getWantAgent(wantAgentInfo).then((wantAgentObj: WantAgent) => {
        backgroundTaskManager.startBackgroundRunning(
          this.context,
          backgroundTaskManager.BackgroundMode.DATA_TRANSFER,
          wantAgentObj,
          (err: BusinessError) => {
            if (err) {
              Logger.error(`Start background task failed: ${err.message}`);
            } else {
              Logger.info('Background task started for WebSocket keep-alive');
              this.backgroundTaskId = 1;
            }
          }
        );
      }).catch((err: BusinessError) => {
        Logger.error(`Get WantAgent failed: ${err.message}`);
      });
    } catch (e) {
      Logger.error(`Start background task exception: ${e}`);
    }

    // 后台时停止定位，保持 WebSocket 连接
    LocationService.getInstance().stopLocation();
  }

  // 运行时申请位置权限
  private requestLocationPermission(): void {
    EntryAbility.requestLocationPermissionOn(EntryAbility.appContext);
  }

  /**
   * 隐私协议"同意"回调补做定位权限申请。首装首启场景 onCreate 阶段的申请
   * 已按协议标记延后（华为审核："未经用户同意已开始申请权限"属驳回项），
   * 由 Index 协议门"同意并继续"经此入口补齐。
   */
  public static requestLocationPermissionIfAgreed(): void {
    EntryAbility.requestLocationPermissionOn(EntryAbility.appContext);
  }

  private static requestLocationPermissionOn(ctx: common.UIAbilityContext | null): void {
    if (ctx === null) {
      return;
    }
    const permissions: Permissions[] = [
      'ohos.permission.APPROXIMATELY_LOCATION',
      'ohos.permission.LOCATION'
    ];
    const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
    atManager.requestPermissionsFromUser(ctx, permissions).then((data) => {
      const grantStatus: number[] = data.authResults;
      let allGranted: boolean = true;
      for (let i: number = 0; i < grantStatus.length; i++) {
        if (grantStatus[i] !== 0) {
          allGranted = false;
          Logger.warn(`Permission ${permissions[i]} denied`);
        }
      }
      if (allGranted) {
        Logger.info('Location permissions granted');
        LocationService.getInstance().startLocation();
      }
    }).catch((err: BusinessError) => {
      Logger.error(`Request permissions failed: ${err.message}`);
    });
  }
}
