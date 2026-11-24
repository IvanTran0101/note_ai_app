import { Sha256 } from '@aws-crypto/sha256-js';
import { defaultProvider } from '@aws-sdk/credential-provider-node';
import { SignatureV4 } from '@smithy/signature-v4';
import { MAX_PUBLISH_MS, type RelayPublisher, type RevisionSignal } from './relay';

type Credentials = Readonly<{ accessKeyId: string; secretAccessKey: string; sessionToken?: string }>;
type CredentialsProvider = () => Promise<Credentials>;

const channelActor = (value: string) =>
  /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,48}[A-Za-z0-9])?$/.test(value);

function raceAbort<T>(work: Promise<T>, signal: AbortSignal): Promise<T> {
  if (signal.aborted) return Promise.reject(signal.reason);
  return new Promise<T>((resolve, reject) => {
    const abort = () => reject(signal.reason);
    signal.addEventListener('abort', abort, { once: true });
    work.then((value) => { signal.removeEventListener('abort', abort); resolve(value); },
      (error) => { signal.removeEventListener('abort', abort); reject(error); });
  });
}

/** IAM signer is the SDK implementation; no client publish permission. */
export class AppSyncPublisher implements RelayPublisher {
  readonly signer: SignatureV4;
  readonly url: URL;
  private readonly region: string;
  private readonly credentials: CredentialsProvider;
  constructor(endpoint: string, region: string, readonly transport = fetch,
    credentials: CredentialsProvider = defaultProvider()) {
    this.url = new URL(endpoint);
    if (this.url.protocol !== 'https:' || this.url.pathname !== '/event') throw new Error('Invalid event endpoint');
    this.region = region;
    this.credentials = credentials;
    this.signer = new SignatureV4({ service: 'appsync', region, sha256: Sha256, credentials });
  }
  async publish(actor: string, signal: RevisionSignal, requestSignal?: AbortSignal): Promise<void> {
    if (!channelActor(actor)) throw new Error('Invalid channel');
    const timeout = AbortSignal.timeout(MAX_PUBLISH_MS);
    const deadline = requestSignal ? AbortSignal.any([requestSignal, timeout]) : timeout;
    deadline.throwIfAborted();
    const body = JSON.stringify({ channel: `/notes/${actor}`, events: [JSON.stringify(signal)] });
    const signer = new SignatureV4({ service: 'appsync', region: this.region, sha256: Sha256,
      credentials: async () => {
        deadline.throwIfAborted();
        const credentials = await raceAbort(this.credentials(), deadline);
        deadline.throwIfAborted();
        return credentials;
      } });
    const request = await signer.sign({ method: 'POST', protocol: this.url.protocol,
      hostname: this.url.hostname, path: this.url.pathname,
      headers: { host: this.url.host, 'content-type': 'application/json' }, body });
    deadline.throwIfAborted();
    const response = await this.transport(this.url, { method: 'POST', headers: request.headers,
      body, signal: deadline });
    deadline.throwIfAborted();
    const reply = await raceAbort(response.json() as Promise<{ failed?: unknown[] }>, deadline);
    deadline.throwIfAborted();
    if (!response.ok) throw new Error('Event publication unavailable');
    if (!Array.isArray(reply.failed) || reply.failed.length) throw new Error('Event publication rejected');
  }
}
