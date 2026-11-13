import { preferences } from '@kit.ArkData';
import { relationalStore } from '@kit.ArkData';
import { Context } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Logger } from '../common/Logger';
import { Constants } from '../model/Constants';

// 本地存储服务
export class StorageService {
  private static instance: StorageService;
  private prefs: preferences.Preferences | null = null;
  private rdbStore: relationalStore.RdbStore | null = null;

  private constructor() {}

  public static getInstance(): StorageService {
    if (!StorageService.instance) {
      StorageService.instance = new StorageService();
    }
    return StorageService.instance;
  }

  public async init(context: Context): Promise<void> {
    // 初始化 Preferences
    try {
      this.prefs = await preferences.getPreferences(context, Constants.PREFS_NAME);
      Logger.info('[StorageService] Preferences initialized');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.error(`[StorageService] Preferences error: ${e.message}`);
    }

    // 初始化 RelationalStore
    const config: relationalStore.StoreConfig = {
      name: Constants.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };

    const SQL_CREATE_MESSAGES: string = `
      CREATE TABLE IF NOT EXISTS messages (
        id TEXT PRIMARY KEY,
        room_id TEXT NOT NULL,
        sender TEXT NOT NULL,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL
      )
    `;

    try {
      this.rdbStore = await relationalStore.getRdbStore(context, config);
      await this.rdbStore.executeSql(SQL_CREATE_MESSAGES);
      Logger.info('[StorageService] RdbStore initialized');
    } catch (err) {
      const e: BusinessError = err as BusinessError;
      Logger.error(`[StorageService] RdbStore error: ${e.message}`);
    }
  }

  // Preferences 操作
  public async setPref(key: string, value: string): Promise<void> {
    if (this.prefs === null) return;
    await this.prefs.put(key, value);
    await this.prefs.flush();
  }

  public async getPref(key: string, defaultValue: string): Promise<string> {
    if (this.prefs === null) return defaultValue;
    return await this.prefs.get(key, defaultValue) as string;
  }

  // 保存消息到本地数据库
  public async saveMessage(id: string, roomId: string, sender: string, content: string,
    timestamp: number): Promise<void> {
    if (this.rdbStore === null) return;
    const sql: string = 'INSERT OR REPLACE INTO messages (id, room_id, sender, content, timestamp) VALUES (?, ?, ?, ?, ?)';
    await this.rdbStore.executeSql(sql, [id, roomId, sender, content, timestamp.toString()]);
  }

  // 查询房间消息
  public async getMessages(roomId: string): Promise<relationalStore.ResultSet> {
    if (this.rdbStore === null) {
      throw new Error('RdbStore not initialized');
    }
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('messages');
    predicates.equalTo('room_id', roomId);
    predicates.orderByAsc('timestamp');
    return await this.rdbStore.query(predicates);
  }

  public async deleteRoomMessages(roomId: string): Promise<void> {
    if (this.rdbStore === null) return;
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('messages');
    predicates.equalTo('room_id', roomId);
    await this.rdbStore.delete(predicates);
  }

  // 清除不属于任何活跃房间的缓存消息（反追踪兜底：不保留历史）。
  // 覆盖房间过期事件链路之外的残留：离线过期、进程重启等。
  // 列表为空时全清——空列表只可能意味着全部房间已过期；若为服务端异常，
  // 活跃房间的历史仍可由服务端 Redis（72h TTL）重新拉取解密恢复。
  public async deleteMessagesNotIn(roomIds: string[]): Promise<void> {
    if (this.rdbStore === null) return;
    if (roomIds.length === 0) {
      await this.deleteAllMessages();
      return;
    }
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('messages');
    predicates.notIn('room_id', roomIds);
    await this.rdbStore.delete(predicates);
  }

  // 删除单条消息（按主键 id）。用于回滚被服务端拒绝的乐观消息，避免本地残留幽灵记录。
  public async deleteMessage(id: string): Promise<void> {
    if (this.rdbStore === null) return;
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('messages');
    predicates.equalTo('id', id);
    await this.rdbStore.delete(predicates);
  }

  // 删除所有本地消息（身份重置时调用）
  public async deleteAllMessages(): Promise<void> {
    if (this.rdbStore === null) return;
    const predicates: relationalStore.RdbPredicates =
      new relationalStore.RdbPredicates('messages');
    await this.rdbStore.delete(predicates);
    Logger.info('[StorageService] All messages deleted');
  }
}
