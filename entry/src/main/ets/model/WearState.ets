export enum WearState {
  // No event received yet. Treated like WORN: there is no evidence that the watch is off.
  UNKNOWN = 'UNKNOWN',
  WORN = 'WORN',
  REMOVED = 'REMOVED'
}

export enum SourceMode {
  OFF = 'off',
  REAL = 'real',
  SIM = 'sim',
  // The sensor is missing on this device.
  UNSUPPORTED = 'unsupported'
}
