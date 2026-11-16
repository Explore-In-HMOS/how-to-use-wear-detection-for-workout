export enum WorkoutState {
  IDLE = 'IDLE',
  RUNNING = 'RUNNING',
  PAUSED = 'PAUSED',
  AUTO_PAUSED = 'AUTO_PAUSED',
  FINISHED = 'FINISHED'
}

/**
 * Workout state machine:
 * IDLE -> RUNNING <-> PAUSED | AUTO_PAUSED -> FINISHED.
 * Active time grows only in RUNNING. Removal time and count are tracked for
 * the whole workout, also while paused.
 */
@Observed
export class WorkoutSession {
  state: WorkoutState = WorkoutState.IDLE;
  removals: number = 0;
  private activeMs: number = 0;
  private runningSince: number = 0;
  private removedMs: number = 0;
  private removedSince: number = 0;

  isActive(): boolean {
    return this.state === WorkoutState.RUNNING || this.state === WorkoutState.PAUSED ||
      this.state === WorkoutState.AUTO_PAUSED;
  }

  isPaused(): boolean {
    return this.state === WorkoutState.PAUSED || this.state === WorkoutState.AUTO_PAUSED;
  }

  start(now: number): boolean {
    if (this.isActive()) {
      return false;
    }
    this.reset();
    this.state = WorkoutState.RUNNING;
    this.runningSince = now;
    return true;
  }

  pause(now: number, auto: boolean): boolean {
    if (this.state !== WorkoutState.RUNNING) {
      return false;
    }
    this.activeMs += now - this.runningSince;
    this.state = auto ? WorkoutState.AUTO_PAUSED : WorkoutState.PAUSED;
    return true;
  }

  resume(now: number): boolean {
    if (!this.isPaused()) {
      return false;
    }
    this.state = WorkoutState.RUNNING;
    this.runningSince = now;
    return true;
  }

  finish(now: number): boolean {
    if (!this.isActive()) {
      return false;
    }
    if (this.state === WorkoutState.RUNNING) {
      this.activeMs += now - this.runningSince;
    }
    this.markWorn(now);
    this.state = WorkoutState.FINISHED;
    return true;
  }

  markRemoved(now: number): void {
    if (!this.isActive() || this.removedSince > 0) {
      return;
    }
    this.removals++;
    this.removedSince = now;
  }

  markWorn(now: number): void {
    if (this.removedSince > 0) {
      this.removedMs += now - this.removedSince;
      this.removedSince = 0;
    }
  }

  activeTime(now: number): number {
    return this.activeMs + (this.state === WorkoutState.RUNNING ? now - this.runningSince : 0);
  }

  removedTime(now: number): number {
    return this.removedMs + (this.removedSince > 0 ? now - this.removedSince : 0);
  }

  reset(): void {
    this.state = WorkoutState.IDLE;
    this.removals = 0;
    this.activeMs = 0;
    this.runningSince = 0;
    this.removedMs = 0;
    this.removedSince = 0;
  }
}
