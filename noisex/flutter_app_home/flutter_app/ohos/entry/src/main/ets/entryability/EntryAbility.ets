import { abilityAccessCtrl, Permissions, bundleManager, common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { huks } from '@kit.UniversalKeystoreKit';
import { util } from '@kit.ArkTS';
import { window } from '@kit.ArkUI';
import { pushService } from '@kit.PushKit';
import { notificationManager } from '@kit.NotificationKit';
import geoLocationManager from '@ohos.geoLocationManager';
import {
  FlutterAbility,
  FlutterEngine,
  MethodCall,
  MethodCallHandler,
  MethodChannel,
  MethodResult
} from '@ohos/flutter_ohos';
import { GeneratedPluginRegistrant } from '../plugins/GeneratedPluginRegistrant';

/** 自建定位桥通道名（lib/services/location_service.dart 单源同款，勿单边改） */
const NATIVE_LOCATION_CHANNEL: string = 'noisex/native_location';

/** 自建系统行为通道（lib/app.dart 单源同款，勿单边改） */
const NATIVE_SYSTEM_CHANNEL: string = 'noisex/system';

/** 自建硬件密钥库通道（lib/services/keystore_service.dart 单源同款，勿单边改） */
const KEYSTORE_CHANNEL: string = 'noisex/keystore';

/** 自建推送桥通道（lib/services/push_service.dart 单源同款，勿单边改） */
const NATIVE_PUSH_CHANNEL: string = 'noisex/push';

/** 主密钥别名（与鸿蒙原生端 KeystoreService.ets 单源同款） */
const MASTER_KEY_ALIAS: string = 'noisex_e2ee_master';

const GCM_TAG_LEN: number = 16;
const NONCE_LEN: number = 12;

/** encrypt 返回对：iv(b64) + ct(b64, 密文||tag)，与 Android 端约定一致 */
interface IvCtPair {
  iv: string;
  ct: string;
}

/**
 * 系统行为桥处理器：moveToBackground = 应用退到后台。
 * 对齐鸿蒙端首页返回键默认语义（进程保留、回到桌面）；
 * Flutter 根路由默认 SystemNavigator.pop 会终止 Ability，导致"返回即退出 App"（B22）。
 */
class SystemBridgeHandler implements MethodCallHandler {
  private readonly ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'moveToBackground') {
      try {
        this.ctx.moveAbilityToBackground();
        result.success(true);
      } catch (e) {
        result.error('move_background_error', String(e), null);
      }
      return;
    }
    if (call.method === 'exitApp') {
      // 隐私协议"不同意并退出"专用：terminateSelf 走标准 Ability 生命周期，
      // 下次冷启动正常重建。SystemNavigator.pop 在 fork 里落 router.back()，
      // Ability UI 状态被破坏且热重启黑屏（2026-11-01 模拟器实证）。
      try {
        this.ctx.terminateSelf();
        result.success(true);
      } catch (e) {
        result.error('exit_app_error', String(e), null);
      }
      return;
    }
    result.notImplemented();
  }
}

/**
 * 定位桥处理器（MethodCallHandler 是接口，ArkTS 禁箭头函数直赋——
 * 10505001 编译实锤，参考 ShouyiPetCare NativeBridgeHandler 同款类实现）。
 * CPF 生态缺 geolocator ohos 实现，Dart 侧 Geolocator 抛 MissingPluginException
 * 后经此通道走 geoLocationManager 兜底。
 */
class LocationBridgeHandler implements MethodCallHandler {
  private readonly ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'getLocation') {
      // 只查不弹：未授权时回错误交 Dart 侧降级。2026-11-06 用户定则（勿回退）：
      // 收听开关等日常路径绝不触发授权弹窗——旧实现每次 getLocation 都无条件
      // requestPermissionsFromUser，导致重新开启收听时再次弹授权框
      this.locateIfPermitted(result);
      return;
    }
    if (call.method === 'checkLocationPermission') {
      this.hasLocationPermission().then((granted: boolean): void => {
        result.success({ 'granted': granted });
      });
      return;
    }
    if (call.method === 'ensureLocationPermission') {
      // 唯一允许弹授权框的路径：启动首登 / 发送声呐（Dart getGeohash 调用）
      this.ensureLocationPermission(result);
      return;
    }
    result.notImplemented();
  }

  /** 全部定位权限已授予才返回 true；只查不弹，任何异常按未授予处理 */
  private async hasLocationPermission(): Promise<boolean> {
    try {
      const atManager: abilityAccessCtrl.AtManager =
        abilityAccessCtrl.createAtManager();
      const bundleInfo = await bundleManager.getBundleInfoForSelf(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
      const tokenId: number = bundleInfo.appInfo.accessTokenId;
      const permissions: Array<Permissions> = [
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.LOCATION'
      ];
      for (const p of permissions) {
        const status = await atManager.verifyAccessToken(tokenId, p);
        if (status !== abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          return false;
        }
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /** 已授权才定位；未授权回错误，本方法永不弹框 */
  private locateIfPermitted(result: MethodResult): void {
    this.hasLocationPermission().then((granted: boolean): void => {
      if (!granted) {
        result.error('permission_denied', 'location permission not granted', null);
        return;
      }
      this.getCurrent(result);
    });
  }

  /** 缺失的权限补弹一次授权框（只弹不定位），结果以 granted 布尔回传 */
  private ensureLocationPermission(result: MethodResult): void {
    this.hasLocationPermission().then((granted: boolean): void => {
      if (granted) {
        result.success({ 'granted': true });
        return;
      }
      const atManager: abilityAccessCtrl.AtManager =
        abilityAccessCtrl.createAtManager();
      const permissions: Array<Permissions> = [
        'ohos.permission.APPROXIMATELY_LOCATION',
        'ohos.permission.LOCATION'
      ];
      atManager.requestPermissionsFromUser(this.ctx, permissions)
        .then((res) => {
          const ok: boolean =
            res.authResults.length > 0 && res.authResults.every((r) => r === 0);
          result.success({ 'granted': ok });
        })
        .catch((e: BusinessError): void => {
          result.error('permission_error', `${e.code}: ${e.message}`, null);
        });
    });
  }

  private getCurrent(result: MethodResult): void {
    const request: geoLocationManager.CurrentLocationRequest = {
      priority: geoLocationManager.LocationRequestPriority.FIRST_FIX,
      scenario: geoLocationManager.LocationRequestScenario.UNSET
    };
    try {
      geoLocationManager.getCurrentLocation(request)
        .then((loc: geoLocationManager.Location): void => {
          result.success({
            'latitude': loc.latitude,
            'longitude': loc.longitude
          });
        })
        .catch((e: BusinessError): void => {
          result.error('location_error', `${e.code}: ${e.message}`, null);
        });
    } catch (e) {
      result.error('location_error', String(e), null);
    }
  }
}

/**
 * 硬件密钥库桥处理器：主密钥由 HUKS 生成保护、不可导出，Dart 侧仅经
 * 通道触发对 E2EE 密钥信封的 AES-256-GCM 加解密（明文密钥不跨进程）。
 * 会话流程对齐官方 huks 加解密示例（AES/GCM/NoPadding）：
 * 加密 outData = 密文||tag（末 16 字节），解密以 HUKS_TAG_AE_TAG 传 tag。
 */
class KeystoreBridgeHandler implements MethodCallHandler {
  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'encrypt') {
      const plain: string = call.argument('plain') as string;
      this.encryptB64(plain).then((pair: IvCtPair | null): void => {
        if (pair === null) {
          result.error('keystore_error', 'wrap failed', null);
          return;
        }
        result.success(pair);
      });
      return;
    }
    if (call.method === 'decrypt') {
      const iv: string = call.argument('iv') as string;
      const ct: string = call.argument('ct') as string;
      this.decryptB64(iv, ct).then((plain: string | null): void => {
        if (plain === null) {
          result.error('keystore_error', 'unwrap failed', null);
          return;
        }
        result.success(plain);
      });
      return;
    }
    result.notImplemented();
  }

  private async encryptB64(plain: string): Promise<IvCtPair | null> {
    try {
      await this.ensureMasterKey();
      const nonce: Uint8Array = this.randomBytes(NONCE_LEN);
      const out: Uint8Array | null = await this.gcmSession(
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT, nonce, null,
        this.textEncode(plain));
      if (out === null || out.length < GCM_TAG_LEN) {
        return null;
      }
      const base64: util.Base64Helper = new util.Base64Helper();
      const pair: IvCtPair = {
        iv: base64.encodeToStringSync(nonce),
        ct: base64.encodeToStringSync(out)
      };
      return pair;
    } catch (e) {
      console.error(`[KeystoreBridge] wrap failed: ${e}`);
      return null;
    }
  }

  private async decryptB64(iv: string, ct: string): Promise<string | null> {
    try {
      const base64: util.Base64Helper = new util.Base64Helper();
      const nonce: Uint8Array = base64.decodeSync(iv);
      const combined: Uint8Array = base64.decodeSync(ct);
      if (nonce.length !== NONCE_LEN || combined.length < GCM_TAG_LEN) {
        return null;
      }
      const tag: Uint8Array = combined.slice(combined.length - GCM_TAG_LEN);
      const ctOnly: Uint8Array = combined.slice(0, combined.length - GCM_TAG_LEN);
      await this.ensureMasterKey();
      const out: Uint8Array | null = await this.gcmSession(
        huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT, nonce, tag, ctOnly);
      if (out === null) {
        return null;
      }
      return this.textDecode(out);
    } catch (e) {
      // 主密钥被清 / 密文被篡改：返回错误由 Dart 侧丢弃落盘信封
      console.error(`[KeystoreBridge] unwrap failed: ${e}`);
      return null;
    }
  }

  private async gcmSession(purpose: huks.HuksKeyPurpose, nonce: Uint8Array,
    tag: Uint8Array | null, inData: Uint8Array): Promise<Uint8Array | null> {
    const props: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: purpose },
      { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_NONE },
      { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_GCM },
      { tag: huks.HuksTag.HUKS_TAG_NONCE, value: nonce }
    ];
    if (tag !== null) {
      const tagParam: huks.HuksParam =
        { tag: huks.HuksTag.HUKS_TAG_AE_TAG, value: tag };
      props.push(tagParam);
    }
    const options: huks.HuksOptions = { properties: props, inData: inData };
    const initResult = await huks.initSession(MASTER_KEY_ALIAS, options);
    const finishResult = await huks.finishSession(initResult.handle, options);
    return finishResult.outData as Uint8Array;
  }

  private async ensureMasterKey(): Promise<void> {
    try {
      const exist: boolean =
        await huks.isKeyItemExist(MASTER_KEY_ALIAS, { properties: [] });
      if (exist) {
        return;
      }
    } catch (_) {
      // 查询失败不阻断，继续尝试生成（已存在时生成会失败，由后续会话验证）
    }
    const genProps: huks.HuksParam[] = [
      { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
      { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_256 },
      {
        tag: huks.HuksTag.HUKS_TAG_PURPOSE,
        value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT |
          huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT
      }
    ];
    try {
      await huks.generateKeyItem(MASTER_KEY_ALIAS, { properties: genProps });
    } catch (_) {
      // 已存在（或设备不支持）：由后续加解密会话给出最终结论
    }
  }

  private randomBytes(len: number): Uint8Array {
    const rand: cryptoFramework.Random = cryptoFramework.createRandom();
    return rand.generateRandomSync(len).data;
  }

  private textEncode(str: string): Uint8Array {
    const encoder: util.TextEncoder = new util.TextEncoder();
    return encoder.encodeInto(str);
  }

  private textDecode(bytes: Uint8Array): string {
    const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
    return decoder.decodeToString(bytes);
  }
}

/**
 * 推送桥处理器（2026-11-05 推送修复根因②）：Flutter-OHOS 的
 * Platform.operatingSystem='ohos'，Dart 侧 isIOS/isAndroid 全不命中，
 * 鸿蒙端此前连 getToken 都没尝试过。按《华为Push Kit的通知消息.md》：
 * - getToken：每次启动由 Dart 侧发起（Push Token 仅卸载重装/恢复出厂变更）
 * - requestNotificationAuth：步骤3 通知授权引导，1600004=用户拒绝后
 *   对话框不再弹，只能走 openNotificationSettings 去设置页开启
 */
class PushBridgeHandler implements MethodCallHandler {
  private readonly ctx: common.UIAbilityContext;

  constructor(ctx: common.UIAbilityContext) {
    this.ctx = ctx;
  }

  onMethodCall(call: MethodCall, result: MethodResult): void {
    if (call.method === 'getToken') {
      pushService.getToken()
        .then((token: string): void => {
          result.success(token);
        })
        .catch((err: BusinessError): void => {
          // 1000900010=应用身份验证失败（Profile 未含推送服务需重新生成签名）
          result.error('token_error', `${err.code}: ${err.message}`, null);
        });
      return;
    }
    if (call.method === 'requestNotificationAuth') {
      this.requestAuth(result);
      return;
    }
    if (call.method === 'isNotificationEnabled') {
      notificationManager.isNotificationEnabled()
        .then((enabled: boolean): void => {
          result.success(enabled);
        })
        .catch((err: BusinessError): void => {
          result.error('auth_check_error', `${err.code}: ${err.message}`, null);
        });
      return;
    }
    if (call.method === 'openNotificationSettings') {
      // API26 WithResult：半模态关闭时带回最终授权态，免二次查询竞态
      notificationManager.openNotificationSettingsWithResult(this.ctx)
        .then((setting: notificationManager.NotificationSetting): void => {
          result.success(setting.notificationEnabled === true);
        })
        .catch((err: BusinessError): void => {
          result.error('settings_error', `${err.code}: ${err.message}`, null);
        });
      return;
    }
    if (call.method === 'showLocalNotification') {
      this.publishLocalNotification(call, result);
      return;
    }
    result.notImplemented();
  }

  /**
   * 本地通知发布（2026-11-05 补鸿蒙端后台/非聊天页通知缺口）：
   * flutter_local_notifications 无 OHOS 实现，Dart 侧 WS 收到非当前房间的
   * 消息时经本桥用系统 Notification Kit 发布；点击通知经 wantAgent 拉起应用。
   */
  private publishLocalNotification(call: MethodCall, result: MethodResult): void {
    const title: string = (call.argument('title') as string) ?? '新消息';
    const text: string = (call.argument('body') as string) ?? '';
    const notifId: number = new Date().getTime() % 1000000000;
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{ bundleName: 'com.lls.noisex', abilityName: 'EntryAbility' }],
      operationType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    wantAgent.getWantAgent(wantAgentInfo)
      .then((agent: WantAgent): Promise<void> => {
        const request: notificationManager.NotificationRequest = {
          id: notifId,
          wantAgent: agent,
          content: {
            notificationContentType:
              notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
            normal: {
              title: title,
              text: text,
              additionalText: 'NoiseX'
            }
          }
        };
        return notificationManager.publish(request);
      })
      .then((): void => {
        result.success(true);
      })
      .catch((err: BusinessError): void => {
        result.error('notify_error', `${err.code}: ${err.message}`, null);
      });
  }

  /** 先查授权态，未开启才弹系统授权框（requestEnableNotification） */
  private requestAuth(result: MethodResult): void {
    notificationManager.isNotificationEnabled()
      .then((enabled: boolean): void => {
        if (enabled) {
          result.success('granted');
          return;
        }
        notificationManager.requestEnableNotification(this.ctx)
          .then((): void => {
            result.success('granted');
          })
          .catch((err: BusinessError): void => {
            if (err.code === 1600004) {
              result.error('notification_refused', '1600004', null);
            } else {
              result.error('auth_error', `${err.code}: ${err.message}`, null);
            }
          });
      })
      .catch((err: BusinessError): void => {
        result.error('auth_check_error', `${err.code}: ${err.message}`, null);
      });
  }
}

export default class EntryAbility extends FlutterAbility {
  private mainWin: window.Window | null = null;

  /**
   * 状态栏属性对齐鸿蒙原生端（透明底 + 内容色主题橙 #FF6B35）。
   *
   * 竞态根因（hilog 实证 2026-11-01）：Flutter 框架启动首帧后会主动发一次
   * SystemUiOverlayStyle.light，fork 的 PlatformPlugin 将其映射为
   * statusBarContentColor=#FFFFFF 覆写窗口属性；而 SystemUiOverlayStyle API
   * 没有自定义 contentColor 的通道，无法从 Dart 侧表达橙色。
   * 对策：启动时尽早设一次，之后短周期重试数次压过框架初始写入，
   * 并在每次回到前台（SHOWN/ACTIVE）时再申明一次。
   */
  onWindowStageCreate(windowStage: window.WindowStage): void {
    super.onWindowStageCreate(windowStage);
    windowStage.getMainWindow().then((win: window.Window): void => {
      this.mainWin = win;
      this.applyStatusBarProps();
      // 消除启动白屏（2026-11-02 用户反馈）：Flutter 引擎首帧渲染完成前
      // 露出的是窗口背景，默认白色与暗色主题割裂成一闪而过的白屏层。
      // 设为应用底色 bgBase #0A0A0F（lib/theme/colors.dart 单源同款），
      // 冷启动与前台切换的空档期统一为暗色。
      try {
        // setWindowBackgroundColor 返回 void（非 Promise），异常走 try/catch
        win.setWindowBackgroundColor('#FF0A0A0F');
      } catch (e) {
        console.error(`[EntryAbility] window bg rejected: ${e}`);
      }
      win.setWindowLayoutFullScreen(true)
        .catch((err: BusinessError): void => {
          console.error(`[EntryAbility] fullscreen rejected: ${err.code}: ${err.message}`);
        });
      let retries = 0;
      const retryTimer: number = setInterval((): void => {
        this.applyStatusBarProps();
        retries++;
        if (retries >= 6) {
          clearInterval(retryTimer);
        }
      }, 500);
      try {
        windowStage.on('windowStageEvent', (event: window.WindowStageEventType): void => {
          if (event === window.WindowStageEventType.SHOWN ||
            event === window.WindowStageEventType.ACTIVE) {
            this.applyStatusBarProps();
          }
        });
      } catch (e) {
        console.error(`[EntryAbility] windowStageEvent listener failed: ${e}`);
      }
    }).catch((err: BusinessError): void => {
      console.error(`[EntryAbility] main window failed: ${err.code}: ${err.message}`);
    });
  }

  private applyStatusBarProps(): void {
    if (this.mainWin === null) {
      return;
    }
    const sysBarProps: window.SystemBarProperties = {
      statusBarColor: '#00000000',
      statusBarContentColor: '#FF6B35'
    };
    this.mainWin.setWindowSystemBarProperties(sysBarProps)
      .catch((err: BusinessError): void => {
        console.error(`[EntryAbility] bar props rejected: ${err.code}: ${err.message}`);
      });
  }

  configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    GeneratedPluginRegistrant.registerWith(flutterEngine)
    // 自建定位通道：geolocator 无 ohos 平台实现（pub 无 *_ohos、CPF fork 与
    // 本 fork 编译器不兼容实证），geoLocationManager 是系统已验证链路
    const channel: MethodChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(), NATIVE_LOCATION_CHANNEL);
    channel.setMethodCallHandler(new LocationBridgeHandler(this.context));
    // 系统行为通道：根页返回键退后台（B22）
    const systemChannel: MethodChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(), NATIVE_SYSTEM_CHANNEL);
    systemChannel.setMethodCallHandler(new SystemBridgeHandler(this.context));
    // 硬件密钥库通道：E2EE 房间密钥 HUKS 包裹落盘（B18+）
    const keystoreChannel: MethodChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(), KEYSTORE_CHANNEL);
    keystoreChannel.setMethodCallHandler(new KeystoreBridgeHandler());
    // 推送桥通道：pushService.getToken + 通知授权引导（推送修复根因②③）
    const pushChannel: MethodChannel = new MethodChannel(
      flutterEngine.dartExecutor.getBinaryMessenger(), NATIVE_PUSH_CHANNEL);
    pushChannel.setMethodCallHandler(new PushBridgeHandler(this.context));
  }
}
