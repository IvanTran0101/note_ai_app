/** Run production-code mocked checks; no live fetch or AWS calls. */
import { runBoundaryChecks } from './boundaries.test';
import { runContractChecks } from './contract.test';
import { runProviderChecks } from './provider.test';
import { runProviderIoChecks } from './provider_io.test';
import { runHandlerChecks } from './handler.test';
import { runHandlerTransportChecks } from './handler_transport.test';
import { passed, show } from './test_support';
declare const process: { on(event: string, listener: (reason: unknown) => void): unknown; exitCode: number ;};
const main = async (): Promise<void> => {
  const globalWithFetch = globalThis as unknown as { fetch: typeof fetch; };
  const originalFetch = globalWithFetch.fetch;
  let liveFetchCalls = 0;
  globalWithFetch.fetch = (async () => {
    liveFetchCalls += 1;
    throw new Error('live fetch trap: inject fetchImpl explicitly');
  }) as unknown as typeof fetch;
  const unhandled: unknown[] = [];
  process.on('unhandledRejection', (reason: unknown) => {
    unhandled.push(reason);
  });
  const capturedLogs: string[] = [];
  const originalConsole = { info: console.info, warn: console.warn, error: console.error };
  console.info = (...args: unknown[]) => {
    capturedLogs.push(show(args));
  };
  console.warn = (...args: unknown[]) => {
    capturedLogs.push(show(args));
  };
  console.error = (...args: unknown[]) => {
    capturedLogs.push(show(args));
  };
  const context = { capturedLogs, liveFetchCalls: () => liveFetchCalls, unhandled };
  try {
    await runContractChecks(context);
    await runProviderChecks(context);
    await runProviderIoChecks(context);
    await runHandlerChecks(context);
    await runHandlerTransportChecks(context);
    await runBoundaryChecks(context);
    await new Promise(resolve => setTimeout(resolve, 25));
    if (liveFetchCalls !== 0 || unhandled.length !== 0) throw new Error('Live fetch or unhandled rejection detected');
  } finally {
    console.info = originalConsole.info;
    console.warn = originalConsole.warn;
    console.error = originalConsole.error;
    globalWithFetch.fetch = originalFetch;
  }
  console.log(`${passed} summary runtime checks passed`);
};
main().catch(error => { console.error(error); process.exitCode = 1; });
