import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../model/Constants';

// 日志封装
export class Logger {
  static info(msg: string): void {
    hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', msg);
  }

  static error(msg: string): void {
    hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', msg);
  }

  static warn(msg: string): void {
    hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', msg);
  }

  static debug(msg: string): void {
    hilog.debug(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', msg);
  }
}
