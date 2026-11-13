import { preferences } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { Logger } from '../common/Logger';
import { Constants } from '../model/Constants';
import { ApiService } from './ApiService';
import { WsService } from './WsService';
import { StorageService } from './StorageService';
import { CryptoService } from './CryptoService';

// 匿名认证服务
export class AuthService {
  private static instance: AuthService;
  private token: string = '';
  private anonymousUuid: string = '';
  private prefs: preferences.Preferences | null = null;
  // 隐私协议同意标记（privacy_agreed_v1）：未同意前不发起任何网络请求
  //（register = 上报匿名标识，属采集行为），华为审核硬要求"未同意不采集"
  private privacyAgreed: boolean = false;

  private constructor() {}

  public static getInstance(): AuthService {
    if (!AuthService.instance) {
      AuthService.instance = new AuthService();
    }
    return AuthService.instance;
  }

  public async init(context: Context): Promise<void> {
    try {
      this.prefs = await preferences.getPreferences(context, Constants.PREFS_NAME);

      // 尝试读取已保存的 UUID
      this.anonymousUuid = await this.prefs.get('anonymous_uuid', '') as string;
      this.token = await this.prefs.get('jwt_token', '') as string;
      // 协议同意标记与鉴权信息同库（Constants.PREFS_NAME）
      this.privacyAgreed = await this.prefs.get('privacy_agreed_v1', false) as boolean;

      // 如果没有 UUID，生成新的
      if (this.anonymousUuid.length === 0) {
        this.anonymousUuid = this.generateUuid();
        await this.prefs.put('anonymous_uuid', this.anonymousUuid);
        await this.prefs.flush();
        Logger.info(`[AuthService] Generated new UUID: ${this.anonymousUuid}`);
      } else {
        Logger.info(`[AuthService] Loaded existing UUID`);
      }

      // 关键修复：本地校验 JWT 过期时间。旧版只读取不校验，导致拿着过期 12 天的 token
      // 继续启动：REST 请求因服务端旧 bug 降级为 anonymousUser 返回 200（看似成功），
      // WS 握手却被 WebSocketInterceptor 拒绝（"JWT expired"），客户端永远收不到 sonar_received。
      // 这里在启动早期就发现过期并重新注册，确保后续 WS 握手拿到有效 token。
      if (this.token.length > 0 && this.isTokenExpired(this.token)) {
        Logger.warn('[AuthService] Loaded JWT is expired, clearing token');
        this.token = '';
        if (this.prefs !== null) {
          await this.prefs.delete('jwt_token');
          await this.prefs.flush();
        }
        // 隐私合规：注册（上报匿名标识）是采集行为，未同意协议前不得发起，
        // 延后到同意后的 Index.initAfterSplash（其本身会无条件 register 补票）
        if (!this.privacyAgreed) {
          Logger.info('[AuthService] Privacy not agreed, defer registration');
        } else {
          // 用已有 UUID 重新注册拿新 token（register 内部会 setToken 持久化）
          await ApiService.getInstance().register(this.anonymousUuid);
          Logger.info('[AuthService] Re-registered with fresh token after expiry');
        }
      }
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.error(`[AuthService] Init error: ${e.message}`);
    }
  }

  public isPrivacyAgreed(): boolean {
    return this.privacyAgreed;
  }

  /**
   * 写入协议同意标记（内存 + preferences）。
   * 调用时机：首启授权门"同意并继续"（Index 同意回调）。
   */
  public async setPrivacyAgreed(agreed: boolean): Promise<void> {
    this.privacyAgreed = agreed;
    if (this.prefs !== null) {
      await this.prefs.put('privacy_agreed_v1', agreed);
      await this.prefs.flush();
    }
  }

  /**
   * 本地校验 JWT 是否已过期，避免带着过期 token 启动 WS/REST 调用。
   *
   * <p>只解析不验签（验签由服务端负责），读 payload 的 exp 字段比对当前秒级时间戳。
   * 任何解析异常都视为"不可信，需重新登录"，返回 true 让上层清 token 重注册。
   */
  private isTokenExpired(token: string): boolean {
    try {
      const parts: string[] = token.split('.');
      if (parts.length < 2) return true;
      // JWT payload 是 base64url，补齐 padding 后解码
      let payloadB64: string = parts[1].replace(/-/g, '+').replace(/_/g, '/');
      const pad: number = payloadB64.length % 4;
      if (pad > 0) {
        payloadB64 += '='.repeat(4 - pad);
      }
      const base64: util.Base64Helper = new util.Base64Helper();
      const payloadBytes: Uint8Array = base64.decodeSync(payloadB64);
      const decoder: util.TextDecoder = new util.TextDecoder('utf-8');
      const payloadJson: string = decoder.decodeToString(payloadBytes);
      const payload: Record<string, Object> = JSON.parse(payloadJson) as Record<string, Object>;
      const expValue: Object | undefined = payload['exp'];
      if (expValue === undefined || expValue === null) return true;
      // exp 是秒级 Unix 时间戳
      const exp: number = Number(expValue);
      if (!Number.isFinite(exp)) return true;
      const nowSeconds: number = Math.floor(Date.now() / 1000);
      return exp < nowSeconds;
    } catch (e) {
      Logger.warn(`[AuthService] JWT expiry check failed, treat as expired: ${e}`);
      return true;
    }
  }

  public getUuid(): string {
    return this.anonymousUuid;
  }

  public getToken(): string {
    return this.token;
  }

  public setToken(token: string): void {
    this.token = token;
    // 异步持久化 token 到 preferences
    if (this.prefs !== null) {
      this.prefs.put('jwt_token', token).then(() => {
        return this.prefs!.flush();
      }).catch((err: BusinessError) => {
        Logger.error(`[AuthService] Persist token failed: ${err.message}`);
      });
    }
  }

  // 重置匿名身份：清除所有数据，生成新 UUID 重新开始
  public async resetIdentity(): Promise<void> {
    // 1. 调用后端清除服务端数据
    await ApiService.getInstance().resetIdentity();

    // 2. 断开 WebSocket
    WsService.getInstance().disconnect();

    // 3. 清除本地数据
    await this.clearLocalData();

    // 4. 生成新 UUID
    this.anonymousUuid = this.generateUuid();
    if (this.prefs !== null) {
      await this.prefs.put('anonymous_uuid', this.anonymousUuid);
      await this.prefs.flush();
    }
    this.token = '';

    // 5. 用新 UUID 注册
    await ApiService.getInstance().register(this.anonymousUuid);

    // 6. 重新连接 WebSocket
    WsService.getInstance().connect();

    Logger.info(`[AuthService] Identity reset completed, new UUID: ${this.anonymousUuid}`);
  }

  private async clearLocalData(): Promise<void> {
    // 清除 preferences 中的 JWT
    if (this.prefs !== null) {
      await this.prefs.delete('jwt_token');
      await this.prefs.flush();
    }

    // 清除所有本地消息
    await StorageService.getInstance().deleteAllMessages();

    // 清除所有 E2EE 密钥
    CryptoService.getInstance().clearAllKeys();
  }

  // 生成简单 UUID（演示用，生产环境应使用 cryptoFramework）
  private generateUuid(): string {
    const chars: string = '0123456789abcdef';
    const sections: number[] = [8, 4, 4, 4, 12];
    let uuid: string = '';

    for (let i: number = 0; i < sections.length; i++) {
      if (i > 0) {
        uuid += '-';
      }
      for (let j: number = 0; j < sections[i]; j++) {
        uuid += chars.charAt(Math.floor(Math.random() * chars.length));
      }
    }
    return uuid;
  }
}
