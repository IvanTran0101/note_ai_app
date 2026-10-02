import { Sha256 } from '@aws-crypto/sha256-js';
import { defaultProvider } from '@aws-sdk/credential-provider-node';
import { SignatureV4 } from '@smithy/signature-v4';
import type { RelayPublisher, RevisionSignal } from './relay';

/** IAM signer is the SDK implementation; no client publish permission. */
export class AppSyncPublisher implements RelayPublisher {
  readonly signer: SignatureV4;
  readonly url: URL;
  constructor(endpoint: string, region: string, readonly transport = fetch) {
    this.url = new URL(endpoint);
    if (this.url.protocol !== 'https:' || this.url.pathname !== '/event') throw new Error('Invalid event endpoint');
    this.signer = new SignatureV4({ service: 'appsync', region, sha256: Sha256,
      credentials: defaultProvider() });
  }
  async publish(actor: string, signal: RevisionSignal): Promise<void> {
    if (!/^[A-Za-z0-9](?:[A-Za-z0-9-]{0,48}[A-Za-z0-9])?$/.test(actor)) throw new Error('Invalid channel');
    const body = JSON.stringify({ channel: `/notes/${actor}`, events: [JSON.stringify(signal)] });
    const request = await this.signer.sign({ method: 'POST', protocol: this.url.protocol,
      hostname: this.url.hostname, path: this.url.pathname,
      headers: { host: this.url.host, 'content-type': 'application/json' }, body });
    const response = await this.transport(this.url, { method: 'POST', headers: request.headers,
      body, signal: AbortSignal.timeout(10_000) });
    if (!response.ok) throw new Error('Event publication unavailable');
    const reply = await response.json() as { failed?: unknown[] };
    if (!Array.isArray(reply.failed) || reply.failed.length) throw new Error('Event publication rejected');
  }
}
