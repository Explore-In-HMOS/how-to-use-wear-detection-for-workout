import { Constants } from '../common/Constants';
import { WearState } from './WearState';

export enum SampleVerdict {
  ACCEPTED = 'accepted',
  INVALID = 'invalid value',
  NOT_WORN = 'watch not worn',
  WARMUP = 'warm-up after putting the watch on'
}

/**
 * Decides if a heart rate sample is valid for the workout. Only accepted
 * samples go into the average and the maximum.
 */
@Observed
export class SampleFilter {
  // False when the device has no wear detection sensor: all valid values are accepted.
  filteringEnabled: boolean = true;
  valid: number = 0;
  rejected: number = 0;
  max: number = 0;
  private sum: number = 0;
  private wornSince: number = 0;

  /** Starts the warm-up window. Call it when the watch goes from REMOVED to WORN. */
  startWarmup(now: number): void {
    this.wornSince = now;
  }

  evaluate(bpm: number, wear: WearState, now: number): SampleVerdict {
    let verdict = SampleVerdict.ACCEPTED;
    if (bpm <= 0) {
      verdict = SampleVerdict.INVALID;
    } else if (this.filteringEnabled && wear === WearState.REMOVED) {
      verdict = SampleVerdict.NOT_WORN;
    } else if (this.filteringEnabled && this.wornSince > 0 && now - this.wornSince < Constants.WARMUP_MS) {
      verdict = SampleVerdict.WARMUP;
    }

    if (verdict === SampleVerdict.ACCEPTED) {
      this.valid++;
      this.sum += bpm;
      this.max = Math.max(this.max, bpm);
    } else {
      this.rejected++;
    }
    return verdict;
  }

  average(): number {
    return this.valid > 0 ? Math.round(this.sum / this.valid) : 0;
  }

  reset(): void {
    this.filteringEnabled = true;
    this.valid = 0;
    this.rejected = 0;
    this.max = 0;
    this.sum = 0;
    this.wornSince = 0;
  }
}
