import { RagFailure } from './types';

/** The same signal bounds every awaited stage and stops later paid stages. */
export class RequestDeadline {
  private readonly controller = new AbortController();
  private readonly end: number;
  private readonly timer: ReturnType<typeof setTimeout>;
  private readonly onParentAbort = () => this.controller.abort();
  readonly signal = this.controller.signal;
  constructor(duration: number, private readonly now: () => number = Date.now, private readonly parent?: AbortSignal) {
    if (!Number.isSafeInteger(duration) || duration <= 0 || duration > 26_000) {
      throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
    }
    this.end = now() + duration;
    this.timer = setTimeout(() => this.controller.abort(), duration);
    if (parent?.aborted) this.controller.abort();
    else parent?.addEventListener('abort', this.onParentAbort, { once: true });
  }
  check(): void {
    if (this.signal.aborted || this.now() >= this.end) throw new RagFailure('TIMEOUT');
  }
  async within<T>(operation: () => Promise<T>): Promise<T> {
    this.check();
    let onAbort: () => void = () => {};
    const expired = new Promise<never>((_, reject) => {
      onAbort = () => reject(new RagFailure('TIMEOUT'));
      this.signal.addEventListener('abort', onAbort, { once: true });
    });
    try {
      const value = await Promise.race([Promise.resolve().then(() => {
        this.check();
        return operation();
      }), expired]);
      this.check();
      return value;
    } finally { this.signal.removeEventListener('abort', onAbort); }
  }
  close(): void { clearTimeout(this.timer); this.parent?.removeEventListener('abort', this.onParentAbort); this.controller.abort(); }
}
