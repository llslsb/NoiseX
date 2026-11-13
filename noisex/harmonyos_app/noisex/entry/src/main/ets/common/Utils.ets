// 通用工具函数
export class Utils {
  // 格式化相对时间（几分钟前/几小时前）
  static formatRelativeTime(timestamp: number): string {
    const diff: number = Date.now() - timestamp;
    const minutes: number = Math.floor(diff / 60000);
    if (minutes < 1) {
      return '刚刚';
    }
    if (minutes < 60) {
      return `${minutes}分钟前`;
    }
    const hours: number = Math.floor(minutes / 60);
    if (hours < 24) {
      return `${hours}小时前`;
    }
    const days: number = Math.floor(hours / 24);
    return `${days}天前`;
  }

  // 格式化剩余时间（Xh Xm）
  static formatTimeRemaining(expiresAt: number, now: number): string {
    const diff: number = expiresAt - now;
    if (diff <= 0) {
      return '已过期';
    }
    const hours: number = Math.floor(diff / (1000 * 60 * 60));
    const minutes: number = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
    if (hours > 0) {
      return `${hours}h ${minutes}m`;
    }
    return `${minutes}m`;
  }

  // 格式化剩余时间（中文）
  static formatTimeRemainingCN(expiresAt: number, now: number): string {
    const diff: number = expiresAt - now;
    if (diff <= 0) {
      return '已过期';
    }
    const hours: number = Math.floor(diff / (1000 * 60 * 60));
    const minutes: number = Math.floor((diff % (1000 * 60 * 60)) / (1000 * 60));
    if (hours > 0) {
      return `${hours}小时${minutes}分钟`;
    }
    return `${minutes}分钟`;
  }

  // 格式化消息时间（HH:MM）
  static formatMessageTime(timestamp: number): string {
    const date: Date = new Date(timestamp);
    const hours: string = date.getHours().toString().padStart(2, '0');
    const minutes: string = date.getMinutes().toString().padStart(2, '0');
    return `${hours}:${minutes}`;
  }

  // 计算沙漏进度百分比
  static getHourglassProgress(expiresAt: number, now: number): number {
    const total: number = 72 * 60 * 60 * 1000;
    const remaining: number = expiresAt - now;
    return Math.max(0, Math.min(100, (remaining / total) * 100));
  }

  // 判断是否即将过期（<12小时）
  static isExpiringSoon(expiresAt: number, now: number): boolean {
    return (expiresAt - now) < 12 * 60 * 60 * 1000;
  }

  // 红色警戒档（<6h）：⚠️ 标记与进度条脉冲动画的唯一门槛
  // （UI 评审 P0：倒计时三档，与 Flutter Utils.isCriticalExpiring 逐项对齐）
  static isCriticalExpiring(expiresAt: number, now: number): boolean {
    const remaining: number = expiresAt - now;
    return remaining > 0 && remaining < 6 * 60 * 60 * 1000;
  }

  // 倒计时状态三档色判断：返回 'critical' | 'warning' | 'normal'
  // （>24h 灰 / <24h 橙 / <6h 红；调用方映射为各自 color token）
  static expiryTier(expiresAt: number, now: number): string {
    if (Utils.isCriticalExpiring(expiresAt, now)) {
      return 'critical';
    }
    const remaining: number = expiresAt - now;
    if (remaining > 0 && remaining < 24 * 60 * 60 * 1000) {
      return 'warning';
    }
    return 'normal';
  }

  // 格式化冷却倒计时（m:ss，UI 评审 P0：裸秒数→格式化恢复时刻；
  // 与 Flutter PulseButton._formatCooldown 逐字对齐）
  static formatCooldown(seconds: number): string {
    const m: number = Math.floor(seconds / 60);
    const s: number = seconds % 60;
    return `${m}:${s.toString().padStart(2, '0')}`;
  }

  static generateId(): string {
    const timestamp: number = Date.now();
    const random: number = Math.floor(Math.random() * 10000);
    return `${timestamp}-${random}`;
  }

  // Geohash 编码（简化实现）
  static toGeohash(lat: number, lon: number, precision: number): string {
    const BASE32: string = '0123456789bcdefghjkmnpqrstuvwxyz';
    let hash: string = '';
    let minLat: number = -90;
    let maxLat: number = 90;
    let minLon: number = -180;
    let maxLon: number = 180;
    let isLon: boolean = true;
    let bit: number = 0;
    let charIndex: number = 0;

    while (hash.length < precision) {
      if (isLon) {
        const mid: number = (minLon + maxLon) / 2;
        if (lon >= mid) {
          charIndex = charIndex * 2 + 1;
          minLon = mid;
        } else {
          charIndex = charIndex * 2;
          maxLon = mid;
        }
      } else {
        const mid: number = (minLat + maxLat) / 2;
        if (lat >= mid) {
          charIndex = charIndex * 2 + 1;
          minLat = mid;
        } else {
          charIndex = charIndex * 2;
          maxLat = mid;
        }
      }
      isLon = !isLon;
      bit++;
      if (bit === 5) {
        hash += BASE32[charIndex];
        bit = 0;
        charIndex = 0;
      }
    }
    return hash;
  }
}
