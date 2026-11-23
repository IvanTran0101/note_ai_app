/**
 * Test-only fakes for the Phase 4 provider adapter unit tests: a recording `fetch` plus response
 * bodies that stall, cancel, or stream past the byte cap. Not imported by production code.
 */
export type RecordedCall = Readonly<{ url: string; init: RequestInit }>;

export const recordingFetch = (
  respond: (call: RecordedCall, index: number) => Promise<Response> | Response,
): Readonly<{ impl: typeof fetch; calls: RecordedCall[] }> => {
  const calls: RecordedCall[] = [];
  let index = 0;
  const impl = (async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const call: RecordedCall = { url: String(input), init: init ?? {} };
    calls.push(call);
    return respond(call, index++);
  }) as typeof fetch;
  return { impl, calls };
};

export const jsonResponse = (value: unknown, status = 200): Response =>
  new Response(JSON.stringify(value), { status, headers: { 'content-type': 'application/json' } });

export const requestJson = (call: RecordedCall): Record<string, unknown> =>
  JSON.parse(String(call.init.body)) as Record<string, unknown>;

export const neverSettle = (): Promise<Response> => new Promise<Response>(() => undefined);

/** A body whose reads never resolve, recording whether the adapter cancelled it. */
export const hangingBody = (): Readonly<{ response: Response; wasCancelled: () => boolean }> => {
  let cancelled = false;
  const stream = new ReadableStream<Uint8Array>({
    start() {
      // Never enqueue and never close: `read()` stays pending until cancelled.
    },
    cancel() {
      cancelled = true;
    },
  });
  return { response: new Response(stream, { status: 200 }), wasCancelled: () => cancelled };
};

/** A chunked body with no `Content-Length` that streams past the 65536-byte cap. */
export const oversizedChunkedBody = (): Response => {
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      for (let index = 0; index < 8; index += 1) controller.enqueue(new Uint8Array(16 * 1024));
      controller.close();
    },
  });
  return new Response(stream, { status: 200 });
};
