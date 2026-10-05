import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';
import { identifier, NoteSecurityError } from '../protection/protection_store';
import { unlockGrantOf, securityErrorResponse } from '../protection/handler';
import { jsonResponse, notFoundResponse } from '../sync/sync_response';
import { AttachmentError, CHUNK_BYTES } from './models';
import type { AttachmentUseCases } from './use_cases';
export const isAttachmentPath = (p: string) => /^\/notes\/[^/]+\/attachments(?:\/|$)/.test(p);
const header = (e: Event, name: string) => Object.entries(e.headers ?? {}).find(([k]) => k.toLowerCase() === name)?.[1];
function body(e: Event) {
  if (!e.body || e.isBase64Encoded || e.body.length > 4096) throw new AttachmentError('invalid');
  try {
    const b = JSON.parse(e.body);
    if (!b || typeof b !== 'object' || Array.isArray(b)) throw Error(); return b;
  } catch { throw new AttachmentError('invalid'); }
}
export async function handleAttachments(e: Event, actor: string, service: AttachmentUseCases) {
  try {
    const m = /^\/notes\/([^/]+)\/attachments\/([a-f0-9]{64})(?:\/(begin|status|chunk-url|chunk-ack|verify|cancel|content))$/.exec(e.rawPath);
    if (!m) return notFoundResponse();
    const note = identifier(decodeURIComponent(m[1])), id = m[2], action = m[3];
    const owner = identifier(e.queryStringParameters?.ownerId ?? actor), grant = unlockGrantOf(e);
    const method = e.requestContext.http.method;
    if (action === 'content' && method === 'GET') {
      const mode = e.queryStringParameters?.mode;
      if (mode !== undefined && mode !== 'export') throw new AttachmentError('invalid');
      const range = /^bytes=(\d+)-(\d+)$/.exec(header(e, 'range') ?? '');
      if (!range || Number(range[2]) - Number(range[1]) + 1 > CHUNK_BYTES) throw new AttachmentError('invalid');
      const start = Number(range[1]), end = Number(range[2]) + 1;
      const r = await service.content(actor, owner, note, id, identifier(e.queryStringParameters?.objectVersion), start, end, grant, mode === 'export');
      try { return {statusCode: 206, isBase64Encoded: true, headers: {
        'content-type': r.descriptor.mimeType, 'content-length': String(r.bytes.length),
        'content-range': `bytes ${start}-${end - 1}/${r.descriptor.sizeBytes}`, 'accept-ranges': 'bytes',
        'cache-control': 'no-store', 'x-content-type-options': 'nosniff'}, body: r.bytes.toString('base64')}; }
      finally { r.bytes.fill(0); }
    }
    if (action === 'status' && method === 'GET') return jsonResponse(200, await service.status(actor, owner, note, id, grant));
    if (method !== 'POST') return notFoundResponse();
    const b = body(e); let result;
    switch (action) {
      case 'begin': if (b.id !== id) throw new AttachmentError('invalid'); result = await service.begin(actor, owner, note, b, grant); break;
      case 'chunk-url': result = await service.uploadUrl(actor, owner, note, id, b.index, b.sha256, grant); break;
      case 'chunk-ack': result = await service.confirmChunk(actor, owner, note, id, b.index, b.sha256, grant); break;
      case 'verify': result = await service.verify(actor, owner, note, id, grant); break;
      case 'cancel': result = await service.cancel(actor, owner, note, id, grant); break;
      default: return notFoundResponse();
    }
    return jsonResponse(200, result);
  } catch (e) {
    if (e instanceof NoteSecurityError) return securityErrorResponse(e);
    if (e instanceof AttachmentError) return jsonResponse(e.code === 'denied' ? 403 : e.code === 'stale' || e.code === 'cancelled' ? 409 : e.code === 'unavailable' ? 503 : 422,
      {code: `ATTACHMENT_${e.code.toUpperCase()}`, retryable: e.code === 'unavailable' || e.code === 'stale'});
    return jsonResponse(503, {code: 'ATTACHMENT_UNAVAILABLE', retryable: true});
  }
}
