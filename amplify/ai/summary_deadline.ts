import { SummaryFailure } from './summary_contract';

/** One deadline covers authorization, quota, provider and authorized release. */
export class SummaryRequestDeadline {
  private readonly end: number;
  constructor(durationMs: number, private readonly now: () => number = Date.now) {
    if (!Number.isSafeInteger(durationMs) || durationMs < 1000 || durationMs > 26_000) {
      throw new SummaryFailure('unexpected', 'Request deadline is invalid');
    }
    this.end = now() + durationMs;
  }

  providerBudget(): number {
    // Reserve time for three bounded authority reads and the output transaction.
    const budget = Math.min(15_000, this.end - this.now() - 9000);
    if (budget < 1000) throw new SummaryFailure('timeout', 'Request deadline exceeded');
    return budget;
  }

  async within<T>(operation: () => Promise<T>): Promise<T> {
    const remaining = this.end - this.now();
    if (remaining <= 0) throw new SummaryFailure('timeout', 'Request deadline exceeded');
    let timer: ReturnType<typeof setTimeout> | undefined;
    try {
      const deadline = new Promise<never>((_, reject) => {
        timer = setTimeout(() => reject(new SummaryFailure('timeout', 'Request deadline exceeded')), remaining);
      });
      const result = await Promise.race([operation(), deadline]);
      if (this.end <= this.now()) throw new SummaryFailure('timeout', 'Request deadline exceeded');
      return result;
    } finally {
      if (timer !== undefined) clearTimeout(timer);
    }
  }
}
