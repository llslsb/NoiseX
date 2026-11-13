import { pushService } from '@kit.PushKit';
import { notificationManager } from '@kit.NotificationKit';
import { wantAgent, Want } from '@kit.AbilityKit';
import type { WantAgent } from '@kit.AbilityKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { AuthService } from './AuthService';
import { ApiService } from './ApiService';
import { Logger } from '../common/Logger';
import { Constants } from '../model/Constants';

interface PushNotificationData {
  roomId: string;
  type: string;
}

interface LocalNotification {
  title: string;
  text: string;
  roomId: string;
  slotType: notificationManager.SlotType;
}

export class PushService {
  private static instance: PushService;
  private context: common.UIAbilityContext | null = null;
  private ability: UIAbility | null = null;
  private currentToken: string = '';
  private notificationIdCounter: number = 1;

  private constructor() {}

  public static getInstance(): PushService {
    if (!PushService.instance) {
      PushService.instance = new PushService();
    }
    return PushService.instance;
  }

  public setContext(context: common.UIAbilityContext): void {
    this.context = context;
  }

  public setAbility(ability: UIAbility): void {
    this.ability = ability;
  }

  public async init(): Promise<void> {
    if (this.context === null) {
      Logger.error('[PushService] Context not set');
      return;
    }
    try {
      // 创建通知渠道
      this.createNotificationChannels();

      // 检查通知权限状态
      const isEnabled: boolean = await notificationManager.isNotificationEnabled();
      Logger.info(`[PushService] Notification enabled status: ${isEnabled}`);

      if (!isEnabled) {
        // 请求通知权限（会弹出用户授权弹窗）
        await notificationManager.requestEnableNotification(this.context);
        Logger.info('[PushService] Notification permission requested');
      } else {
        Logger.info('[PushService] Notification already enabled');
      }

      // 获取 Push Token
      const token: string = await pushService.getToken();
      if (token.length > 0) {
        this.currentToken = token;
        await this.registerToken(token);
        Logger.info(`[PushService] Token registered: ${token.substring(0, 20)}...`);
      } else {
        Logger.warn('[PushService] Token is empty');
      }

      // 监听 Token 刷新
      this.listenTokenUpdate();
    } catch (e) {
      Logger.error(`[PushService] Init failed: ${e}`);
    }
  }

  private createNotificationChannels(): void {
    try {
      notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION, (err) => {
        if (err) {
          Logger.error('[PushService] Add SOCIAL_COMMUNICATION slot failed');
        }
      });
      notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION, (err) => {
        if (err) {
          Logger.error('[PushService] Add SERVICE_INFORMATION slot failed');
        }
      });
      Logger.info('[PushService] Notification channels created');
    } catch (e) {
      Logger.error(`[PushService] Create channels failed: ${e}`);
    }
  }

  private async registerToken(token: string): Promise<void> {
    try {
      await ApiService.getInstance().registerPushToken(token);
    } catch (e) {
      Logger.error(`[PushService] Register token failed: ${e}`);
    }
  }

  public async unregisterToken(): Promise<void> {
    try {
      // 1. 删除华为 Push Kit Token
      if (this.currentToken.length > 0) {
        await pushService.deleteToken();
        Logger.info('[PushService] Push Kit token deleted');
      }

      // 2. 删除服务端注册的 Token
      await ApiService.getInstance().unregisterPushToken();
      this.currentToken = '';
      Logger.info('[PushService] Token unregistered from server');
    } catch (e) {
      Logger.error(`[PushService] Unregister token failed: ${e}`);
    }
  }

  /**
   * TASK-005: 检查是否启用推送
   * 注意：声呐推送的接收与否由服务端控制（通过 startListening/stopListening API）
   * 本方法仅检查本地 Push Token 是否存在，不代表收听模式状态
   */
  public isPushEnabled(): boolean {
    return this.currentToken.length > 0;
  }

  public async reRegisterToken(): Promise<void> {
    if (this.context === null) {
      Logger.error('[PushService] Context not set');
      return;
    }
    try {
      // 重新获取 Push Token
      const token: string = await pushService.getToken();
      if (token.length > 0) {
        this.currentToken = token;
        await this.registerToken(token);
        Logger.info(`[PushService] Token re-registered: ${token.substring(0, 20)}...`);
      }
    } catch (e) {
      Logger.error(`[PushService] Re-register token failed: ${e}`);
    }
  }

  private listenTokenUpdate(): void {
    if (this.ability === null) {
      Logger.warn('[PushService] No ability set, skip tokenUpdate listener');
      return;
    }
    try {
      pushService.on('tokenUpdate', this.ability, (token: string) => {
        if (token.length > 0 && token !== this.currentToken) {
          Logger.info('[PushService] Token updated');
          this.currentToken = token;
          this.registerToken(token).catch(() => {
            Logger.error('[PushService] Re-register token failed');
          });
        }
      });
    } catch (e) {
      Logger.error(`[PushService] Listen tokenUpdate failed: ${e}`);
    }
  }

  public handleNotificationClick(data: PushNotificationData): void {
    if (data.roomId.length > 0) {
      Logger.info(`[PushService] Notification clicked: type=${data.type}, roomId=${data.roomId}`);
      AppStorage.setOrCreate<string>('pushNavigateRoomId', data.roomId);
    }
  }

  // 发布本地前台通知
  public async showLocalNotification(notification: LocalNotification): Promise<void> {
    if (this.context === null) {
      Logger.warn('[PushService] No context, skip local notification');
      return;
    }
    try {
      const wantAgentObj: WantAgent = await this.buildNavigateWantAgent(notification.roomId);
      const request: notificationManager.NotificationRequest = {
        id: this.notificationIdCounter,
        notificationSlotType: notification.slotType,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: notification.title,
            text: notification.text
          }
        },
        wantAgent: wantAgentObj
      };
      this.notificationIdCounter = (this.notificationIdCounter + 1) % 10000;
      await notificationManager.publish(request);
      Logger.info(`[PushService] Local notification published: ${notification.title}`);
    } catch (e) {
      Logger.error(`[PushService] Publish local notification failed: ${e}`);
    }
  }

  // 构建 WantAgent：点击通知后跳转到 EntryAbility 并传递 roomId
  private async buildNavigateWantAgent(roomId: string): Promise<WantAgent> {
    if (this.context === null || this.context.abilityInfo === null) {
      throw new Error('PushService context not initialized');
    }
    const want: Want = {
      bundleName: this.context.abilityInfo.bundleName,
      abilityName: 'EntryAbility',
      parameters: {
        'roomId': roomId,
        'type': 'local_notification'
      }
    } as Want;
    const info: wantAgent.WantAgentInfo = {
      wants: [want],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    return wantAgent.getWantAgent(info);
  }

  // 便捷方法：新消息通知
  public async notifyNewMessage(roomId: string, signalCode: string, preview: string): Promise<void> {
    await this.showLocalNotification({
      title: `${signalCode} 发来消息`,
      text: preview.length > 50 ? preview.substring(0, 50) + '...' : preview,
      roomId: roomId,
      slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
    });
  }

  // 便捷方法：匹配成功通知
  public async notifyMatched(roomId: string, signalCode: string): Promise<void> {
    await this.showLocalNotification({
      title: '匹配成功',
      text: `与 ${signalCode} 建立了新对话`,
      roomId: roomId,
      slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
    });
  }

  // 便捷方法：房间即将过期通知
  public async notifyRoomExpiring(roomId: string, remainingHours: number): Promise<void> {
    await this.showLocalNotification({
      title: '对话即将过期',
      text: `与 ${roomId.substring(0, 8)}... 的对话将在 ${remainingHours.toFixed(1)} 小时后过期`,
      roomId: roomId,
      slotType: notificationManager.SlotType.SERVICE_INFORMATION
    });
  }

  // 便捷方法：保存连接请求通知
  public async notifySaveRequest(roomId: string, fromSignalCode: string): Promise<void> {
    await this.showLocalNotification({
      title: '保存连接请求',
      text: `${fromSignalCode} 希望与你保存连接`,
      roomId: roomId,
      slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
    });
  }

  // 便捷方法：深度交流已确认通知
  public async notifyDeepConfirmed(roomId: string): Promise<void> {
    await this.showLocalNotification({
      title: '深度交流已确认',
      text: '双方已确认深度交流，可解锁资料',
      roomId: roomId,
      slotType: notificationManager.SlotType.SOCIAL_COMMUNICATION
    });
  }

  // 取消所有本地通知
  public async cancelAllNotifications(): Promise<void> {
    try {
      await notificationManager.cancelAll();
      Logger.info('[PushService] All notifications cancelled');
    } catch (e) {
      Logger.error(`[PushService] Cancel all notifications failed: ${e}`);
    }
  }
}
