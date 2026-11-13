/// API 错误友好文案映射。
///
/// 后端返回的 code/message 偏服务端语义，UI 层统一转成用户可理解的中文提示。
export class ApiBusinessError extends Error {
  public readonly code: number;
  public readonly rawMessage: string;

  constructor(code: number, rawMessage: string, fallbackMessage: string = '操作失败，请重试') {
    super(rawMessage.length > 0 ? rawMessage : fallbackMessage);
    this.code = code;
    this.rawMessage = rawMessage;
  }
}

export function mapApiErrorToFriendly(code: number, defaultMessage: string): string {
  switch (code) {
    case 40301:
      return '发送太频繁，请稍后再试';
    case 40101:
    case 40102:
      return '登录已过期，请重启应用';
    case 40901:
      return '声呐已过期，请重新发送';
    case 40902:
      return '聊天室已关闭';
    case 40401:
      return '未找到对应内容';
    case 40001:
      if (defaultMessage.indexOf('重复') >= 0) {
        return '请勿发送重复内容的声呐';
      }
      if (defaultMessage.indexOf('深度交流') >= 0) {
        return '还没有达到解锁条件，请先完成深度交流';
      }
      if (defaultMessage.indexOf('资料尚未解锁') >= 0) {
        return '资料解锁后才能保存连接';
      }
      return '请求参数有误';
    case 50001:
      return '服务器开小差了，请稍后再试';
    default:
      return defaultMessage.length > 0 ? defaultMessage : '操作失败，请重试';
  }
}

export function getFriendlyErrorMessage(error: ApiBusinessError | Error, fallbackMessage: string): string {
  if (error instanceof ApiBusinessError) {
    return mapApiErrorToFriendly(error.code, error.rawMessage);
  }
  return fallbackMessage.length > 0 ? fallbackMessage : '操作失败，请重试';
}
