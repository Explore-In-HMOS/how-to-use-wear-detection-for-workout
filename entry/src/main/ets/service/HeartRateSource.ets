import { sensor } from '@kit.SensorServiceKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { Constants } from '../common/Constants';
import { LogLevel } from '../common/Logger';
import { SourceMode } from '../model/WearState';

export interface HeartRateListener {
  onSample: (bpm: number) => void;
  onLog: (message: string, level: LogLevel) => void;
}

/**
 * Heart rate samples from the HEART_RATE sensor, or simulated samples when
 * simulation is on or the sensor is missing.
 */
export class HeartRateSource {
  private listener: HeartRateListener;
  private mode: SourceMode = SourceMode.OFF;
  private simTimerId: number = -1;
  private simBpm: number = 110;
  private random: cryptoFramework.Random = cryptoFramework.createRandom();
  private callback = (data: sensor.HeartRateResponse): void => {
    this.listener.onSample(Math.round(data.heartRate));
  };

  constructor(listener: HeartRateListener) {
    this.listener = listener;
  }

  getMode(): SourceMode {
    return this.mode;
  }

  isSubscribed(): boolean {
    return this.mode === SourceMode.REAL || this.mode === SourceMode.SIM;
  }

  start(simulate: boolean, allowed: boolean): SourceMode {
    this.stop();
    if (!simulate && allowed && this.subscribeReal()) {
      this.mode = SourceMode.REAL;
      return this.mode;
    }
    if (!simulate && !allowed) {
      this.listener.onLog('No heart rate permission, using simulated heart rate', LogLevel.WARN);
    }
    this.mode = SourceMode.SIM;
    this.simTimerId = setInterval(() => this.simTick(), Constants.SIM_HR_INTERVAL_MS);
    this.listener.onLog('Simulated heart rate started', LogLevel.INFO);
    return this.mode;
  }

  stop(): void {
    if (this.mode === SourceMode.REAL) {
      try {
        sensor.off(sensor.SensorId.HEART_RATE, this.callback);
        this.listener.onLog('sensor.off(HEART_RATE)', LogLevel.INFO);
      } catch (err) {
        this.listener.onLog(`sensor.off(HEART_RATE) failed: ${JSON.stringify(err)}`, LogLevel.ERROR);
      }
    } else if (this.mode === SourceMode.SIM) {
      clearInterval(this.simTimerId);
      this.simTimerId = -1;
      this.listener.onLog('Simulated heart rate stopped', LogLevel.INFO);
    }
    this.mode = SourceMode.OFF;
  }

  private subscribeReal(): boolean {
    try {
      sensor.getSingleSensorSync(sensor.SensorId.HEART_RATE);
    } catch (err) {
      this.listener.onLog('HEART_RATE is not available, using simulated heart rate', LogLevel.WARN);
      return false;
    }
    try {
      sensor.on(sensor.SensorId.HEART_RATE, this.callback, { interval: Constants.HR_INTERVAL_NS });
      this.listener.onLog('sensor.on(HEART_RATE)', LogLevel.INFO);
      return true;
    } catch (err) {
      this.listener.onLog(`sensor.on(HEART_RATE) failed: ${JSON.stringify(err)}`, LogLevel.ERROR);
      return false;
    }
  }

  private simTick(): void {
    const byte = this.random.generateRandomSync(1).data[0];
    const delta = (byte % 7) - 3;
    this.simBpm = Math.min(Math.max(this.simBpm + delta, 90), 165);
    this.listener.onSample(this.simBpm);
  }
}
