import { vibrator } from '@kit.SensorServiceKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/Constants';

export class Haptics {
  static vibrate(durationMs: number): void {
    try {
      vibrator.startVibration({ type: 'time', duration: durationMs }, { id: 0, usage: 'notification' })
        .catch((err: Error) => {
          hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Vibration failed: %{public}s', JSON.stringify(err));
        });
    } catch (err) {
      hilog.warn(Constants.LOG_DOMAIN, Constants.LOG_TAG, 'Vibration failed: %{public}s', JSON.stringify(err));
    }
  }
}
