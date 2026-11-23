/** Named failure for calibration analysis; never a wire error code and never a fake verdict. */
export type CalibrationErrorCode =
  | 'INVALID_FIXTURES'
  | 'DISTRIBUTION_INVALID'
  | 'GROUP_LEAK'
  | 'RECORDING_REUSE_DENIED'
  | 'INVALID_RECORDING'
  | 'RECORDING_INCOMPLETE'
  | 'MODEL_MIX'
  | 'POLICY_NOT_FROZEN'
  | 'POLICY_MISMATCH'
  | 'UNSATISFIABLE'
  | 'SPLIT_DENIED';

export class CalibrationFailure extends Error {
  constructor(
    public readonly code: CalibrationErrorCode,
    public readonly detail: string,
  ) {
    super(`${code}: ${detail}`);
    this.name = 'CalibrationFailure';
  }
}

/** Path-shaped detail ("fixtures[3].gold.answerable") so a bad fixture is findable by hand. */
export function fail(code: CalibrationErrorCode, detail: string): never {
  throw new CalibrationFailure(code, detail);
}
