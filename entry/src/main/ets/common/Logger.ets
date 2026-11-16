import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from './Constants';

export enum LogLevel {
  INFO,
  WARN,
  ERROR
}

export class LogEntry {
  id: number;
  time: string;
  message: string;
  level: LogLevel;

  constructor(id: number, message: string, level: LogLevel) {
    this.id = id;
    this.time = Logger.formatTime(new Date());
    this.message = message;
    this.level = level;
  }
}

export class Logger {
  private static nextId: number = 0;

  /** Writes to hilog and returns an entry for the on-screen event log. */
  static log(message: string, level: LogLevel = LogLevel.INFO): LogEntry {
    switch (level) {
      case LogLevel.ERROR:
        hilog.error(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', message);
        break;
      case LogLevel.WARN:
        hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', message);
        break;
      default:
        hilog.info(Constants.LOG_DOMAIN, Constants.LOG_TAG, '%{public}s', message);
    }
    return new LogEntry(Logger.nextId++, message, level);
  }

  static formatTime(date: Date): string {
    const pad = (n: number, width: number): string => n.toString().padStart(width, '0');
    return `${pad(date.getHours(), 2)}:${pad(date.getMinutes(), 2)}:${pad(date.getSeconds(), 2)}` +
      `.${pad(date.getMilliseconds(), 3)}`;
  }
}
