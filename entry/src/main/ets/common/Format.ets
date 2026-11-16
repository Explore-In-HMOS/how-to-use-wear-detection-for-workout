export class Format {
  /** Formats milliseconds as HH:MM:SS. */
  static duration(ms: number): string {
    const totalSeconds = Math.max(0, Math.floor(ms / 1000));
    const hours = Math.floor(totalSeconds / 3600);
    const minutes = Math.floor((totalSeconds % 3600) / 60);
    const seconds = totalSeconds % 60;
    return `${Format.pad(hours)}:${Format.pad(minutes)}:${Format.pad(seconds)}`;
  }

  static percent(part: number, total: number): string {
    return total > 0 ? `${Math.round(part * 100 / total)}%` : '--';
  }

  private static pad(value: number): string {
    return value.toString().padStart(2, '0');
  }
}
