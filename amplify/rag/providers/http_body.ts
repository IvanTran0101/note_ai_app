/**
 * Bounded HTTP body and per-call deadline helpers shared by the Phase 4 live RAG provider
 * adapters (Jev gate, DeepSeek generation).
 *
 * Owns the transport-level guarantees only: one caller-supplied `fetch`, a fixed approved byte
 * cap counted on bytes actually read, a hard per-call deadline that also aborts the request and
 * a body read a stalled provider would otherwise leave pending, and a fatal UTF-8 / JSON decode.
 * It never echoes provider text, headers or bodies; every failure is a typed `RagFailure` code
 * chosen by the adapter's `fail` factory.
 *
 * The byte cap is on bytes read, not on the declared `Content-Length`; the declared length is
 * only a cheap early refusal, so a chunked response with no length cannot outrun the cap.
 */
import { RagFailure } from '../types';

/** Contract cap on a provider response body; callers may only lower it. */
export const DEFAULT_MAX_RESPONSE_BYTES = 65536;

/** Adapter-owned mapping from a transport/schema problem to a typed `RagFailure` code. */
export type FailFactory = (message: string) => Error;

export const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

/** Best-effort body release; a body that cannot be cancelled is already unusable. */
export const cancelBody = (response: Response): void => {
  const body: ReadableStream<Uint8Array> | null | undefined = response.body;
  if (body === null || body === undefined) return;
  try {
    void body.cancel().catch(() => undefined);
  } catch {
    // Nothing left to report: the response is being discarded either way.
  }
};

const contentLengthOf = (headers: Headers | undefined): number | undefined => {
  const raw = headers?.get?.('content-length');
  if (typeof raw !== 'string' || !/^\d+$/.test(raw.trim())) return undefined;
  const length = Number(raw.trim());
  return Number.isSafeInteger(length) && length >= 0 ? length : undefined;
};

const concatBytes = (chunks: readonly Uint8Array[], total: number): Uint8Array => {
  const joined = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    joined.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return joined;
};

/**
 * Reads the response body with a hard byte bound, enforcing the bound while streaming so an
 * oversized body is cancelled instead of buffered. `registerCancel` hands the adapter a way to
 * abandon a read that a stalled body (or an expired deadline) leaves pending.
 */
export const readBoundedBody = async (
  response: Response,
  maxBytes: number,
  registerCancel: (cancel: () => void) => void,
  fail: FailFactory,
): Promise<Uint8Array> => {
  const declared = contentLengthOf(response.headers);
  if (declared !== undefined && declared > maxBytes) {
    cancelBody(response);
    throw fail('provider response is too large');
  }

  const body = response.body;
  if (body === null || typeof body?.getReader !== 'function') {
    throw fail('provider response has no readable body');
  }

  const reader = body.getReader();
  registerCancel(() => {
    void reader.cancel().catch(() => undefined);
  });
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    if (value === undefined || value === null) continue;
    total += value.byteLength;
    if (total > maxBytes) {
      void reader.cancel().catch(() => undefined);
      throw fail('provider response is too large');
    }
    chunks.push(value);
  }
  return concatBytes(chunks, total);
};

/** Fatal UTF-8 decode: replacement characters would silently rewrite provider text. */
export const decodeUtf8 = (bytes: Uint8Array, fail: FailFactory): string => {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    throw fail('provider response is not valid UTF-8');
  }
};

/** Decodes one provider payload into a JSON object; malformed or non-object roots fail closed. */
export const parseJsonObject = (text: string, fail: FailFactory): Record<string, unknown> => {
  let decoded: unknown;
  try {
    decoded = JSON.parse(text);
  } catch {
    throw fail('provider response is not valid JSON');
  }
  if (!isRecord(decoded)) throw fail('provider response must be a JSON object');
  return decoded;
};

export type Deadline = Readonly<{
  /** Combined signal for `fetch`: expires on the adapter deadline or the caller's abort. */
  signal: AbortSignal;
  /** Rejects with `TIMEOUT` when the adapter deadline fires. */
  promise: Promise<never>;
  /** True once the adapter deadline fired or the caller already aborted. */
  expired: () => boolean;
  /** Clears the timer and the caller-signal listener; always call in `finally`. */
  settle: () => void;
}>;

/**
 * A per-call deadline that aborts the outbound request. `expired` makes the failure mapping
 * deterministic when an abort and a rejection race, and the internal catch keeps the losing
 * deadline from surfacing as an unhandled rejection. The caller signal is composed in, so an
 * account-level abort stops the fetch and any pending body read immediately instead of waiting
 * for the adapter timeout.
 */
export const startDeadline = (timeoutMs: number, callerSignal: AbortSignal): Deadline => {
  const controller = new AbortController();
  let fired = false;
  let rejectDeadline: (error: unknown) => void = () => undefined;
  const promise = new Promise<never>((_resolve, reject) => {
    rejectDeadline = reject;
  });
  void promise.catch(() => undefined);

  const expire = (): void => {
    if (fired) return;
    fired = true;
    if (!controller.signal.aborted) controller.abort();
    rejectDeadline(new RagFailure('TIMEOUT'));
  };
  const onCallerAbort = (): void => {
    if (!controller.signal.aborted) controller.abort();
    expire();
  };
  if (callerSignal.aborted) onCallerAbort();
  else callerSignal.addEventListener('abort', onCallerAbort, { once: true });

  const timer = setTimeout(expire, timeoutMs);

  return {
    signal: controller.signal,
    promise,
    expired: () => fired || callerSignal.aborted,
    settle: () => {
      clearTimeout(timer);
      callerSignal.removeEventListener('abort', onCallerAbort);
    },
  };
};

/** Runs one request under the deadline; every non-timeout failure is mapped by the caller. */
export const withinDeadline = async <T>(
  deadline: Deadline,
  attempt: Promise<T>,
  cancelPendingRead: () => void,
  mapFailure: (error: unknown) => Error,
): Promise<T> => {
  // The attempt may settle after losing the race; handle it so a late rejection or an ignored
  // abort never becomes an unhandled rejection.
  void attempt.catch(() => undefined);
  try {
    const value = await Promise.race([attempt, deadline.promise]);
    if (deadline.expired()) throw new RagFailure('TIMEOUT');
    return value;
  } catch (error) {
    if (deadline.expired()) throw new RagFailure('TIMEOUT');
    throw mapFailure(error);
  } finally {
    deadline.settle();
    // Only an abandoned read needs cancelling; a completed one is already closed, and the
    // over-size path cancels the reader itself.
    if (deadline.expired()) cancelPendingRead();
  }
};
