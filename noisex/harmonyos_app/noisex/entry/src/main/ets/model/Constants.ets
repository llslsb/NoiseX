// NoiseX 全局常量
export class Constants {
  // API 默认值
  static readonly DEFAULT_API_BASE_URL: string = 'http://192.168.3.178:7070';
  static readonly DEFAULT_WS_URL: string = 'ws://192.168.3.178:7070/ws';

  // API（支持 AppStorage 运行时覆盖）
  static get API_BASE_URL(): string {
    const override: string | undefined = AppStorage.get<string>('apiBaseUrl');
    return override !== undefined && override.length > 0 ? override : Constants.DEFAULT_API_BASE_URL;
  }

  static get WS_URL(): string {
    const override: string | undefined = AppStorage.get<string>('wsUrl');
    return override !== undefined && override.length > 0 ? override : Constants.DEFAULT_WS_URL;
  }

  // 声呐
  static readonly SONAR_MAX_LENGTH: number = 140;
  static readonly SONAR_MAX_PER_HOUR: number = 3;
  static readonly SONAR_COOLDOWN_SECONDS: number = 60; // 演示用60秒

  // 房间
  static readonly ROOM_LIFETIME_HOURS: number = 72;
  static readonly ROOM_EXPIRING_THRESHOLD_HOURS: number = 12;
  static readonly DEEP_CONNECTION_THRESHOLD: number = 20; // 与服务端 unlock-threshold-messages 对齐
  // 聊天发送频率：与服务端 noisex.chat.msg-rate-seconds 对齐（默认 2s）。
  // 客户端在本地按此窗口防抖，避免乐观插入后被服务端 RATE_LIMIT 拒绝导致"幽灵消息"。
  static readonly CHAT_MSG_RATE_SECONDS: number = 2;
  // 连续发送上限：与服务端 ChatService.maxConsecutiveMessages 对齐（深度交流未达成前 5 条）。
  static readonly CHAT_MAX_CONSECUTIVE: number = 5;

  // Geohash
  static readonly DEFAULT_GEOHASH_PRECISION: number = 6;
  // DEFAULT_GEOHASH（'wx4g0s' 北京开发默认格子）已删除（2026-11-02）：
  // 定位缺失时的兜底注册曾把设备静默注册进北京格（"幽灵异地"实锤根因）。
  // 无 fix 一律不注册/不发送，等 onGeohashChanged 真实值。

  // UI 尺寸
  static readonly PULSE_BUTTON_SIZE: number = 160;
  static readonly RADAR_SIZE: number = 320;
  static readonly TAB_BAR_HEIGHT: number = 64;
  static readonly CHAT_HEADER_HEIGHT: number = 88;
  static readonly INPUT_HEIGHT: number = 40;
  static readonly PROGRESS_BAR_WIDTH: number = 256;

  // 动画
  static readonly RADAR_SPIN_DURATION: number = 4000; // 4秒一圈
  static readonly PING_DURATION: number = 2000;
  static readonly FADE_IN_UP_DURATION: number = 300;

  // 存储
  static readonly PREFS_NAME: string = 'noisex_prefs';
  static readonly DB_NAME: string = 'noisex.db';

  // 日志
  static readonly LOG_DOMAIN: number = 0x0000;
  static readonly LOG_TAG: string = 'NoiseX';
}
