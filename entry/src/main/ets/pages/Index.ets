import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { Constants } from '../common/Constants';
import { Format } from '../common/Format';
import { LogEntry, Logger, LogLevel } from '../common/Logger';
import { SampleFilter, SampleVerdict } from '../model/SampleFilter';
import { SourceMode, WearState } from '../model/WearState';
import { WorkoutSession, WorkoutState } from '../model/WorkoutSession';
import { Haptics } from '../service/Haptics';
import { HeartRateSource } from '../service/HeartRateSource';
import { WearStateMonitor } from '../service/WearStateMonitor';

const PERMISSION_HEART: Permissions = 'ohos.permission.READ_HEALTH_DATA';

@Component
struct ToggleRow {
  @Prop label: Resource;
  @Prop isOn: boolean;
  @Prop isEnabled: boolean = true;
  onToggle: (isOn: boolean) => void = () => {};

  build() {
    Row() {
      Text(this.label)
        .fontSize(14)
        .fontColor(this.isEnabled ? Color.White : $r('app.color.neutral'))
        .layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.isOn })
        .selectedColor($r('app.color.success'))
        .enabled(this.isEnabled)
        .onChange((isOn: boolean) => this.onToggle(isOn))
    }
    .width('78%')
    .height(40)
  }
}

@Component
struct SummaryRow {
  @Prop label: Resource;
  @Prop value: string;

  build() {
    Row() {
      Text(this.label)
        .fontSize(13)
        .fontColor('#C7C7CC')
        .layoutWeight(1)
      Text(this.value)
        .fontSize(14)
        .fontColor(Color.White)
    }
    .width('100%')
    .height(24)
  }
}

@Entry
@Component
struct Index {
  @State session: WorkoutSession = new WorkoutSession();
  @State filter: SampleFilter = new SampleFilter();
  @State wearState: WearState = WearState.UNKNOWN;
  @State wearMode: SourceMode = SourceMode.OFF;
  @State hrMode: SourceMode = SourceMode.OFF;
  @State currentBpm: number = 0;
  @State lastVerdict: SampleVerdict | undefined = undefined;
  @State now: number = Date.now();
  @State removalDeadline: number = 0;
  @State resumePrompt: boolean = false;
  @State autoPauseSeconds: number = Constants.DEFAULT_AUTO_PAUSE_S;
  @State autoResume: boolean = true;
  @State simulate: boolean = false;
  @State activeSubscriptions: number = 0;
  @State logs: LogEntry[] = [];

  private wear: WearStateMonitor = new WearStateMonitor({
    onWearChange: (state: WearState) => this.onWearChange(state),
    onLog: (message: string, level: LogLevel) => this.addLog(message, level)
  });
  private heartRate: HeartRateSource = new HeartRateSource({
    onSample: (bpm: number) => this.onSample(bpm),
    onLog: (message: string, level: LogLevel) => this.addLog(message, level)
  });
  private heartAllowed: boolean = false;
  private permissionChecked: boolean = false;
  private tickerId: number = -1;
  private autoPauseTimerId: number = -1;

  aboutToAppear(): void {
    this.addLog('Ready. Tap Start to begin a workout.');
  }

  aboutToDisappear(): void {
    // Safety net: never leave sensor subscriptions behind.
    this.cancelCountdown();
    this.stopTicker();
    this.stopSources();
  }

  // ---------- Workout flow ----------

  private async startWorkout(): Promise<void> {
    if (!this.simulate && !this.permissionChecked) {
      await this.requestPermission();
    }
    const now = Date.now();
    if (!this.session.start(now)) {
      return;
    }
    this.filter.reset();
    this.currentBpm = 0;
    this.lastVerdict = undefined;
    this.resumePrompt = false;
    this.wearState = WearState.UNKNOWN;
    this.now = now;

    this.wearMode = this.wear.start(this.simulate);
    if (this.wearMode === SourceMode.UNSUPPORTED) {
      this.filter.filteringEnabled = false;
      this.addLog('Wear detection is missing: data is not filtered', LogLevel.WARN);
    }
    this.hrMode = this.heartRate.start(this.simulate, this.heartAllowed);
    this.refreshSubscriptions();
    this.startTicker();
    this.addLog('Workout started');
  }

  private togglePause(): void {
    const now = Date.now();
    if (this.session.state === WorkoutState.RUNNING) {
      this.session.pause(now, false);
      this.cancelCountdown();
      this.addLog('Workout paused');
    } else if (this.session.isPaused()) {
      this.resumeWorkout('manual');
    }
  }

  private resumeWorkout(reason: string): void {
    const now = Date.now();
    if (!this.session.resume(now)) {
      return;
    }
    this.resumePrompt = false;
    this.addLog(`Workout resumed (${reason})`);
    if (this.filter.filteringEnabled && this.wearState === WearState.REMOVED) {
      this.startCountdown(now);
    }
  }

  private finishWorkout(): void {
    const now = Date.now();
    this.cancelCountdown();
    this.stopSources();
    this.session.finish(now);
    this.stopTicker();
    this.now = now;
    this.resumePrompt = false;
    this.addLog(`Workout finished: ${Format.duration(this.session.activeTime(now))} active, ` +
      `${this.filter.valid} valid / ${this.filter.rejected} rejected samples`);
  }

  private newWorkout(): void {
    this.session.reset();
    this.filter.reset();
    this.currentBpm = 0;
    this.lastVerdict = undefined;
    this.wearState = WearState.UNKNOWN;
    this.wearMode = SourceMode.OFF;
    this.hrMode = SourceMode.OFF;
  }

  private stopSources(): void {
    this.wear.stop();
    this.heartRate.stop();
    this.wearMode = SourceMode.OFF;
    this.hrMode = SourceMode.OFF;
    this.refreshSubscriptions();
  }

  private refreshSubscriptions(): void {
    this.activeSubscriptions = (this.wear.isSubscribed() ? 1 : 0) + (this.heartRate.isSubscribed() ? 1 : 0);
  }

  // ---------- Wear detection ----------

  private onWearChange(state: WearState): void {
    const previous = this.wearState;
    const now = Date.now();
    this.wearState = state;

    if (state === WearState.REMOVED) {
      this.addLog('Watch removed', LogLevel.WARN);
      this.session.markRemoved(now);
      Haptics.vibrate(Constants.VIBRATE_REMOVED_MS);
      if (this.session.state === WorkoutState.RUNNING) {
        this.startCountdown(now);
      }
      return;
    }

    this.addLog('Watch on the wrist');
    this.session.markWorn(now);
    if (previous !== WearState.REMOVED) {
      return;
    }
    this.filter.startWarmup(now);
    this.cancelCountdown();
    if (this.session.state === WorkoutState.AUTO_PAUSED) {
      if (this.autoResume) {
        this.resumeWorkout('auto');
      } else {
        this.resumePrompt = true;
      }
    }
  }

  private startCountdown(now: number): void {
    this.cancelCountdown();
    const delayMs = this.autoPauseSeconds * 1000;
    this.removalDeadline = now + delayMs;
    this.autoPauseTimerId = setTimeout(() => this.autoPause(), delayMs);
  }

  private cancelCountdown(): void {
    if (this.autoPauseTimerId !== -1) {
      clearTimeout(this.autoPauseTimerId);
      this.autoPauseTimerId = -1;
    }
    this.removalDeadline = 0;
  }

  private autoPause(): void {
    this.autoPauseTimerId = -1;
    this.removalDeadline = 0;
    if (this.session.pause(Date.now(), true)) {
      Haptics.vibrate(Constants.VIBRATE_AUTO_PAUSE_MS);
      this.addLog(`Auto-paused: watch removed for ${this.autoPauseSeconds} s`, LogLevel.WARN);
    }
  }

  // ---------- Heart rate ----------

  private onSample(bpm: number): void {
    this.currentBpm = bpm;
    if (this.session.state !== WorkoutState.RUNNING) {
      // Paused: samples are not recorded at all.
      this.lastVerdict = undefined;
      return;
    }
    const verdict = this.filter.evaluate(bpm, this.wearState, Date.now());
    if (verdict !== this.lastVerdict) {
      this.addLog(verdict === SampleVerdict.ACCEPTED ? 'Samples accepted' : `Samples rejected: ${verdict}`,
        verdict === SampleVerdict.ACCEPTED ? LogLevel.INFO : LogLevel.WARN);
    }
    this.lastVerdict = verdict;
  }

  private async requestPermission(): Promise<void> {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    try {
      const result = await abilityAccessCtrl.createAtManager().requestPermissionsFromUser(context, [PERMISSION_HEART]);
      this.heartAllowed = result.authResults[0] === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
    } catch (err) {
      this.addLog(`Permission request failed: ${JSON.stringify(err)}`, LogLevel.ERROR);
    }
    this.permissionChecked = true;
    this.addLog(`Heart rate permission: ${this.heartAllowed ? 'granted' : 'denied'}`,
      this.heartAllowed ? LogLevel.INFO : LogLevel.WARN);
  }

  // ---------- Ticker & log ----------

  private startTicker(): void {
    this.stopTicker();
    this.tickerId = setInterval(() => {
      this.now = Date.now();
    }, Constants.TICK_MS);
  }

  private stopTicker(): void {
    if (this.tickerId !== -1) {
      clearInterval(this.tickerId);
      this.tickerId = -1;
    }
  }

  private addLog(message: string, level: LogLevel = LogLevel.INFO): void {
    const entry = Logger.log(message, level);
    this.logs = [entry, ...this.logs].slice(0, Constants.LOG_LIMIT);
  }

  // ---------- View helpers ----------

  private wearLabel(): string {
    switch (this.wearState) {
      case WearState.WORN:
        return 'ON WRIST';
      case WearState.REMOVED:
        return 'OFF WRIST';
      default:
        return this.wearMode === SourceMode.UNSUPPORTED ? 'NO SENSOR' : 'UNKNOWN';
    }
  }

  private wearColor(): ResourceColor {
    switch (this.wearState) {
      case WearState.WORN:
        return $r('app.color.success');
      case WearState.REMOVED:
        return $r('app.color.warning');
      default:
        return $r('app.color.neutral');
    }
  }

  private stateColor(): ResourceColor {
    switch (this.session.state) {
      case WorkoutState.RUNNING:
        return $r('app.color.success');
      case WorkoutState.AUTO_PAUSED:
        return $r('app.color.warning');
      case WorkoutState.PAUSED:
        return $r('app.color.accent');
      default:
        return $r('app.color.neutral');
    }
  }

  private verdictText(): string {
    if (this.session.isPaused()) {
      return 'paused: samples not recorded';
    }
    if (this.lastVerdict === undefined) {
      return '';
    }
    return this.lastVerdict === SampleVerdict.ACCEPTED ? 'sample accepted' : `rejected: ${this.lastVerdict}`;
  }

  private countdownSeconds(): number {
    return Math.max(0, Math.ceil((this.removalDeadline - this.now) / 1000));
  }

  private logColor(level: LogLevel): ResourceColor {
    switch (level) {
      case LogLevel.ERROR:
        return $r('app.color.error');
      case LogLevel.WARN:
        return $r('app.color.warning');
      default:
        return '#AEAEB2';
    }
  }

  // ---------- Layout ----------

  @Builder
  banners() {
    if (this.removalDeadline > 0) {
      Text(`Watch removed · pausing in ${this.countdownSeconds()} s`)
        .width('72%')
        .padding(8)
        .fontSize(13)
        .fontColor(Color.Black)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor($r('app.color.warning'))
    }
    if (this.resumePrompt) {
      Text($r('app.string.banner_back_on_wrist'))
        .width('72%')
        .padding(8)
        .fontSize(13)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor($r('app.color.accent'))
    }
    if (this.session.isActive() && !this.filter.filteringEnabled) {
      Text($r('app.string.banner_unfiltered'))
        .width('72%')
        .padding(8)
        .fontSize(12)
        .fontColor(Color.White)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor($r('app.color.card'))
    }
  }

  @Builder
  controls() {
    if (this.session.state === WorkoutState.IDLE) {
      Button($r('app.string.btn_start'))
        .width(140)
        .height(48)
        .fontSize(18)
        .backgroundColor($r('app.color.success'))
        .onClick(() => {
          this.startWorkout();
        })
    } else if (this.session.isActive()) {
      Row({ space: 8 }) {
        Button(this.session.isPaused() ? $r('app.string.btn_resume') : $r('app.string.btn_pause'))
          .height(44)
          .layoutWeight(1)
          .fontSize(15)
          .backgroundColor(this.session.isPaused() ? $r('app.color.success') : $r('app.color.card'))
          .onClick(() => this.togglePause())
        Button($r('app.string.btn_finish'))
          .height(44)
          .layoutWeight(1)
          .fontSize(15)
          .backgroundColor($r('app.color.error'))
          .onClick(() => this.finishWorkout())
      }
      .width('72%')

      if (this.wearMode === SourceMode.SIM) {
        Button(this.wearState === WearState.REMOVED ? $r('app.string.btn_wear_watch') : $r('app.string.btn_remove_watch'))
          .height(36)
          .fontSize(13)
          .backgroundColor($r('app.color.card'))
          .onClick(() => this.wear.toggleSim())
      }
    } else {
      Column({ space: 2 }) {
        Text($r('app.string.summary'))
          .fontSize(15)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)
          .margin({ bottom: 4 })
        SummaryRow({
          label: $r('app.string.summary_active_time'),
          value: Format.duration(this.session.activeTime(this.now))
        })
        SummaryRow({
          label: $r('app.string.summary_valid_ratio'),
          value: Format.percent(this.filter.valid, this.filter.valid + this.filter.rejected)
        })
        SummaryRow({ label: $r('app.string.summary_removals'), value: `${this.session.removals}` })
        SummaryRow({
          label: $r('app.string.summary_removed_time'),
          value: Format.duration(this.session.removedTime(this.now))
        })
      }
      .width('74%')
      .padding(10)
      .borderRadius(16)
      .backgroundColor($r('app.color.card'))

      Button($r('app.string.btn_new_workout'))
        .height(40)
        .fontSize(14)
        .backgroundColor($r('app.color.accent'))
        .onClick(() => this.newWorkout())
    }
  }

  @Builder
  settings() {
    Text($r('app.string.auto_pause_after'))
      .fontSize(13)
      .fontColor($r('app.color.neutral'))
      .margin({ top: 8 })
    Row({ space: 6 }) {
      ForEach(Constants.AUTO_PAUSE_OPTIONS_S, (seconds: number) => {
        Button(`${seconds} s`)
          .height(34)
          .layoutWeight(1)
          .fontSize(13)
          .backgroundColor(seconds === this.autoPauseSeconds ? $r('app.color.accent') : $r('app.color.card'))
          .onClick(() => {
            this.autoPauseSeconds = seconds;
            this.addLog(`Auto-pause delay set to ${seconds} s`);
          })
      }, (seconds: number) => seconds.toString())
    }
    .width('74%')

    ToggleRow({
      label: $r('app.string.auto_resume'),
      isOn: this.autoResume,
      onToggle: (isOn: boolean) => {
        this.autoResume = isOn;
      }
    })
    ToggleRow({
      label: $r('app.string.simulated_sensors'),
      isOn: this.simulate,
      isEnabled: !this.session.isActive(),
      onToggle: (isOn: boolean) => {
        this.simulate = isOn;
      }
    })

    Row() {
      Text($r('app.string.active_subscriptions'))
        .fontSize(13)
        .fontColor('#C7C7CC')
        .layoutWeight(1)
      Text(`${this.activeSubscriptions}`)
        .fontSize(15)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.activeSubscriptions === 0 ? $r('app.color.success') : Color.White)
    }
    .width('78%')

    Text(`HR: ${this.hrMode} · wear: ${this.wearMode}`)
      .fontSize(12)
      .fontColor(this.hrMode === SourceMode.SIM || this.wearMode === SourceMode.SIM ?
        $r('app.color.warning') : $r('app.color.neutral'))
  }

  build() {
    Scroll() {
      Column({ space: 6 }) {
        this.banners()

        Row({ space: 6 }) {
          Circle()
            .width(10)
            .height(10)
            .fill(this.wearColor())
          Text(this.wearLabel())
            .fontSize(13)
            .fontColor(this.wearColor())
          Text(this.session.state)
            .fontSize(11)
            .fontColor(Color.Black)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .borderRadius(8)
            .backgroundColor(this.stateColor())
        }

        Text(Format.duration(this.session.activeTime(this.now)))
          .fontSize(36)
          .fontWeight(FontWeight.Medium)
          .fontColor(Color.White)

        Row({ space: 6 }) {
          Text('♥')
            .fontSize(22)
            .fontColor(this.lastVerdict === SampleVerdict.ACCEPTED ? $r('app.color.heart') : $r('app.color.neutral'))
          Text(this.currentBpm > 0 ? `${this.currentBpm} bpm` : '-- bpm')
            .fontSize(20)
            .fontColor(Color.White)
        }
        Text(this.verdictText())
          .fontSize(11)
          .fontColor(this.lastVerdict === SampleVerdict.ACCEPTED ? $r('app.color.success') : $r('app.color.warning'))

        Text(`Avg ${this.filter.average() || '--'} · Max ${this.filter.max || '--'}`)
          .fontSize(14)
          .fontColor('#C7C7CC')
        Text(`Valid ${this.filter.valid} · Rejected ${this.filter.rejected}`)
          .fontSize(14)
          .fontColor('#C7C7CC')

        this.controls()
        this.settings()

        Text($r('app.string.event_log'))
          .fontSize(13)
          .fontColor($r('app.color.neutral'))
          .margin({ top: 6 })
        ForEach(this.logs, (entry: LogEntry) => {
          Text(`${entry.time}  ${entry.message}`)
            .width('76%')
            .fontSize(11)
            .fontColor(this.logColor(entry.level))
        }, (entry: LogEntry) => entry.id.toString())
      }
      .width('100%')
      .padding({ top: 40, bottom: 56 })
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .backgroundColor(Color.Black)
  }
}
