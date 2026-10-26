/** Absolute Lambda invocation budget; one reserve owns state writes after work stops. */
export const WORK_BUDGET_MS = 50_000;
export const BOOKKEEPING_RESERVE_MS = 10_000;
/** Internal deadline stops before the actual Lambda kill so the handler can return. */
export const RETURN_MARGIN_MS = 1_000;

export interface RelayBudget {
  remainingMs(): number;
  expired(): boolean;
  workSignal(capMs?: number): AbortSignal;
  /** Independent of an expired work signal so retry/quarantine bookkeeping still runs. */
  bookkeepingSignal(): AbortSignal;
}

export class InvocationBudget implements RelayBudget {
  private readonly hardDeadline: number;
  private readonly workDeadline: number;
  constructor(private readonly clock: () => number, lambdaRemaining: () => number,
    workCapMs = WORK_BUDGET_MS, reserveMs = BOOKKEEPING_RESERVE_MS,
    private readonly timeoutSignal = (ms: number) => AbortSignal.timeout(ms),
    returnMarginMs = RETURN_MARGIN_MS) {
    const now = clock();
    const remaining = Math.max(0, lambdaRemaining());
    // Stop every in-flight operation before the real kill boundary, then keep the
    // bookkeeping reserve inside that internal deadline rather than past it.
    const internalRemaining = Math.max(0, remaining - returnMarginMs);
    this.hardDeadline = now + internalRemaining;
    this.workDeadline = now + Math.max(0, Math.min(workCapMs, internalRemaining - reserveMs));
  }
  remainingMs(): number { return Math.max(0, this.workDeadline - this.clock()); }
  expired(): boolean { return this.remainingMs() <= 0; }
  workSignal(capMs = Infinity): AbortSignal {
    const remaining = this.remainingMs();
    if (remaining <= 0 || capMs <= 0) return AbortSignal.abort();
    return this.timeoutSignal(Math.max(1, Math.min(remaining, capMs)));
  }
  bookkeepingSignal(): AbortSignal {
    const remaining = this.hardDeadline - this.clock();
    if (remaining <= 0) return AbortSignal.abort();
    return this.timeoutSignal(Math.max(1, remaining));
  }
}
