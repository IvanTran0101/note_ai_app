/** Local dev ONLY: fixed synthetic users, production use cases, no AWS clients. */
import { createServer, type IncomingMessage } from 'node:http';
import { DynamoLabelStore } from '../labels/dynamo_label_store';
import { parseLabelMutation } from '../labels/label_models';
import { labelProjectionResponse } from '../labels/label_projection_handler';
import { noteV2MutationResponse } from '../sync/sync_response';
import { DynamoSyncStore, SyncInvalidCursorError, SyncInvalidMutationError } from '../sync/dynamo_sync_store';
import { DynamoNoteAcl } from '../sharing/dynamo_note_acl';
import { DynamoShareStore } from '../sharing/dynamo_share_store';
import { ShareUseCases } from '../sharing/share_use_cases';
import { ShareError } from '../sharing/share_models';
import { ProtectionUseCases } from '../protection/use_cases';
import { DynamoProtectionStore } from '../protection/dynamo_protection_store';
import { Argon2idPasswordHasher } from '../protection/argon2id_password_hasher';
import { NoteSecurityError } from '../protection/protection_store';
import { handleProtection, securityErrorResponse, unlockGrantOf } from '../protection/handler';
import { handleShares } from '../sharing/share_handler';
import { parseChangesQuery, parseMutationBody } from '../sync/request_parser';
import { appliedMutationResponse, changesResponse, conflictResponse, jsonResponse } from '../sync/sync_response';
import { DynamoRelayStore } from '../realtime/dynamo_relay_store';
import { RevisionRelay } from '../realtime/relay';
import { LocalDatabase } from './local_database';
import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';

export const USERS = { 'owner@example.invalid': 'm06-dev-owner', 'recipient@example.invalid': 'm06-dev-recipient' };
export function localActor(credential: string | undefined) {
  try {
    const parts = credential?.replace(/^Bearer /, '').split('.');
    if (!credential?.startsWith('Bearer ') || parts?.length !== 3 || parts[2] !== 'local-dev') return null;
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url').toString());
    if (!Object.values(USERS).includes(claims.sub) || claims.iss !== 'm06-local-dev' ||
        claims.token_use !== 'access' || !Number.isSafeInteger(claims.exp) || claims.exp <= Date.now() / 1000) return null;
    return claims.sub as string;
  } catch { return null; }
}

const disk = new LocalDatabase('output/m06-local');
const db = disk.db, acl = new DynamoNoteAcl('local-dev', db.client);
const security = new ProtectionUseCases(new DynamoProtectionStore('local-dev', db.client, true),
  new Argon2idPasswordHasher(), acl, { async sendCode() { throw new NoteSecurityError('unavailable'); } });
const shares = new ShareUseCases(new DynamoShareStore('local-dev', db.client), {
  async resolve(email) {
    const user = USERS[email as keyof typeof USERS];
    if (!user) throw new ShareError('recipientUnavailable');
    return user;
  },
}, security);
const sync = new DynamoSyncStore({ tableName: 'local-dev', documentClient: db.client, security, sharing: true });
const labels = new DynamoLabelStore('local-dev', db.client);
const relay = new RevisionRelay(new DynamoRelayStore('local-dev', db.client), {
  async read(actor, owner, note) { const s = await acl.read(actor, owner, note); return s?.status === 'active' ? s.accessRevision : null; },
}, { async publish(actor, signal) {
  const reply = await fetch('http://127.0.0.1:8798/publish', { method: 'POST',
    headers: { 'content-type': 'application/json' }, body: JSON.stringify({ actor, signal }), signal: AbortSignal.timeout(2000) });
  if (!reply.ok) throw Error('Local socket unavailable');
} });

// One owner of HTTP/relay state and its disk ACK. Failed disk writes stop serving.
let chain = Promise.resolve();
let failed = false;
function serialized<T>(work: () => Promise<T>): Promise<T> {
  const next = chain.then(async () => {
    if (failed) throw Error('Local persistence unavailable');
    const result = await work();
    try { disk.save(); } catch { failed = true; throw Error('Local persistence unavailable'); }
    return result;
  });
  chain = next.then(() => {}, () => {});
  return next;
}

async function dispatch(req: IncomingMessage, url: URL, actor: string, body: string) {
  const v2 = url.pathname.startsWith('/sync/v2/');
  const path = url.pathname.replace('/sync/v2/', '/sync/');
  const event = { rawPath: url.pathname, body,
    headers: req.headers, queryStringParameters: Object.fromEntries(url.searchParams),
    requestContext: { http: { method: req.method } } } as unknown as Event;
  if (url.pathname.startsWith('/notes/')) return url.pathname.endsWith('/shares')
    ? handleShares(event, actor, shares)
    : handleProtection(event, actor, security, async () => { throw new NoteSecurityError('unavailable'); });
  if (req.method === 'POST' && url.pathname === '/sync/v2/label-projections') {
    return labelProjectionResponse(actor, JSON.parse(body), 'local-dev', db.client, security);
  }
  if (req.method === 'GET' && path === '/sync/changes') {
    const parsed = parseChangesQuery(event.queryStringParameters);
    return parsed.ok ? changesResponse(await sync.listChanges(actor, parsed.cursor, parsed.limit, v2 ? 2 : 1))
      : jsonResponse(422, { code: 'INVALID_REQUEST', retryable: false });
  }
  if (req.method === 'POST' && ['/sync/mutations', '/sync/shared-mutations', '/sync/protected-mutations', '/sync/protection-predecessor'].includes(path)) {
    if (v2 && path === '/sync/mutations') {
      const decoded = JSON.parse(body);
      if (decoded?.entityType === 'label') {
        const result = await labels.apply(actor, parseLabelMutation(decoded));
        return jsonResponse(result.status === 'applied' ? 200 : 409, result);
      }
    }
    const parsed = parseMutationBody(body, path === '/sync/protected-mutations', path === '/sync/shared-mutations', v2 ? 2 : 1);
    if (!parsed.ok) return jsonResponse(422, { code: 'INVALID_REQUEST', retryable: false });
    const result = await sync.applyMutation(parsed.mutation.ownerId ?? actor, parsed.mutation,
      { actorId: actor, grant: unlockGrantOf(event), inspectOnly: path === '/sync/protection-predecessor' });
    return v2 ? noteV2MutationResponse(result) : result.status === 'applied' ? appliedMutationResponse(result) : conflictResponse(result);
  }
  return jsonResponse(404, { code: 'NOT_FOUND', retryable: false });
}

export const server = createServer(async (req, res) => {
  const origin = req.headers.origin;
  if (req.headers.host !== '127.0.0.1:8796' ||
      (origin && !/^http:\/\/(127\.0\.0\.1|localhost):8776$/.test(origin))) {
    res.writeHead(403); res.end(); return;
  }
  if (origin) { res.setHeader('access-control-allow-origin', origin); res.setHeader('vary', 'Origin'); }
  res.setHeader('access-control-allow-headers', 'authorization,content-type,x-note-unlock-grant');
  res.setHeader('access-control-allow-methods', 'GET,POST,OPTIONS');
  res.setHeader('cache-control', 'no-store');
  if (req.method === 'OPTIONS') { res.writeHead(204); res.end(); return; }
  try {
    const url = new URL(req.url!, 'http://127.0.0.1:8796');
    if (req.method === 'GET' && url.pathname === '/dev/health') {
      res.writeHead(failed ? 503 : 200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ kind: 'm06-local-dev', version: 1 })); return;
    }
    const actor = localActor(req.headers.authorization);
    if (!actor) { res.writeHead(401); res.end(); return; }
    let body = ''; for await (const part of req) { body += part; if (Buffer.byteLength(body) > 65536) throw Error('Too large'); }
    const reply = await serialized(() => dispatch(req, url, actor, body));
    res.writeHead(reply.statusCode!, { 'content-type': 'application/json' }); res.end(reply.body);
  } catch (error) {
    const reply = error instanceof NoteSecurityError ? securityErrorResponse(error)
      : jsonResponse(error instanceof SyncInvalidCursorError || error instanceof SyncInvalidMutationError ? 422 : 503,
        { code: 'LOCAL_DEV_UNAVAILABLE', retryable: true });
    res.writeHead(reply.statusCode!, { 'content-type': 'application/json' }); res.end(reply.body);
  }
});
server.requestTimeout = 30000;
server.listen(8796, '127.0.0.1', () => console.log('M06 local dev ready: http://127.0.0.1:8796/dev/health'));
const recovery = setInterval(() => { void serialized(async () => { await relay.recover(); }).catch(() => {}); }, 500);
server.on('close', () => clearInterval(recovery));
