export class Constants {
  // Heart rate samples in this window after the watch is put back on are not valid yet.
  static readonly WARMUP_MS: number = 5000;
  static readonly AUTO_PAUSE_OPTIONS_S: number[] = [5, 10, 30];
  static readonly DEFAULT_AUTO_PAUSE_S: number = 10;

  // Heart rate sampling interval in nanoseconds (1 s).
  static readonly HR_INTERVAL_NS: number = 1000000000;
  static readonly SIM_HR_INTERVAL_MS: number = 1000;
  static readonly TICK_MS: number = 1000;

  static readonly VIBRATE_REMOVED_MS: number = 300;
  static readonly VIBRATE_AUTO_PAUSE_MS: number = 600;

  static readonly LOG_LIMIT: number = 20;
  static readonly LOG_DOMAIN: number = 0x0011;
  static readonly LOG_TAG: string = 'WornCheck';
}
