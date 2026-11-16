import { sensor } from '@kit.SensorServiceKit';
import { LogLevel } from '../common/Logger';
import { SourceMode, WearState } from '../model/WearState';

export interface WearStateListener {
  onWearChange: (state: WearState) => void;
  onLog: (message: string, level: LogLevel) => void;
}

/**
 * Subscribes to the WEAR_DETECTION sensor (value 1 = worn, 0 = not worn).
 * In simulation mode, `toggleSim()` stands in for the sensor.
 */
export class WearStateMonitor {
  private listener: WearStateListener;
  private mode: SourceMode = SourceMode.OFF;
  private state: WearState = WearState.UNKNOWN;
  private callback = (data: sensor.WearDetectionResponse): void => {
    this.update(data.value === 1 ? WearState.WORN : WearState.REMOVED);
  };

  constructor(listener: WearStateListener) {
    this.listener = listener;
  }

  getMode(): SourceMode {
    return this.mode;
  }

  getState(): WearState {
    return this.state;
  }

  /** True while a real or simulated subscription exists. */
  isSubscribed(): boolean {
    return this.mode === SourceMode.REAL || this.mode === SourceMode.SIM;
  }

  start(simulate: boolean): SourceMode {
    this.stop();
    this.state = WearState.UNKNOWN;
    if (simulate) {
      this.mode = SourceMode.SIM;
      this.update(WearState.WORN);
      this.listener.onLog('Simulated wear detection started', LogLevel.INFO);
      return this.mode;
    }
    try {
      sensor.getSingleSensorSync(sensor.SensorId.WEAR_DETECTION);
    } catch (err) {
      this.mode = SourceMode.UNSUPPORTED;
      this.listener.onLog('WEAR_DETECTION is not available on this device', LogLevel.WARN);
      return this.mode;
    }
    try {
      sensor.on(sensor.SensorId.WEAR_DETECTION, this.callback);
      this.mode = SourceMode.REAL;
      this.listener.onLog('sensor.on(WEAR_DETECTION)', LogLevel.INFO);
    } catch (err) {
      this.mode = SourceMode.UNSUPPORTED;
      this.listener.onLog(`sensor.on(WEAR_DETECTION) failed: ${JSON.stringify(err)}`, LogLevel.ERROR);
    }
    return this.mode;
  }

  stop(): void {
    if (this.mode === SourceMode.REAL) {
      try {
        sensor.off(sensor.SensorId.WEAR_DETECTION, this.callback);
        this.listener.onLog('sensor.off(WEAR_DETECTION)', LogLevel.INFO);
      } catch (err) {
        this.listener.onLog(`sensor.off(WEAR_DETECTION) failed: ${JSON.stringify(err)}`, LogLevel.ERROR);
      }
    } else if (this.mode === SourceMode.SIM) {
      this.listener.onLog('Simulated wear detection stopped', LogLevel.INFO);
    }
    this.mode = SourceMode.OFF;
  }

  toggleSim(): void {
    if (this.mode !== SourceMode.SIM) {
      return;
    }
    this.update(this.state === WearState.REMOVED ? WearState.WORN : WearState.REMOVED);
  }

  private update(next: WearState): void {
    if (next === this.state) {
      return;
    }
    this.state = next;
    this.listener.onWearChange(next);
  }
}
