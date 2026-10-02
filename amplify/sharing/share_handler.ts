import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';
import { identifier, NoteSecurityError } from '../protection/protection_store';
import { securityErrorResponse, unlockGrantOf } from '../protection/handler';
import { jsonResponse, notFoundResponse } from '../sync/sync_response';
import { ShareError } from './share_models';
import type { ShareCommand } from './share_models';
import type { ShareUseCases } from './share_use_cases';

export function shareCommand(body: string | undefined | null): ShareCommand {
  try {
    if (!body || body.length > 4096) throw new Error();
    const value = JSON.parse(body);
    if (!value || typeof value !== 'object' || Array.isArray(value) ||
        Object.keys(value).some(k => !['requestId', 'action', 'email', 'recipientId', 'role', 'expectedAccessRevision'].includes(k))) throw new Error();
    return value;
  } catch { throw new ShareError('invalidInput'); }
}
export async function handleShares(e: Event, actor: string, service: ShareUseCases) {
  try {
    const m = /^\/notes\/([^/]+)\/shares$/.exec(e.rawPath);
    if (!m || e.isBase64Encoded) return notFoundResponse();
    const id = identifier(decodeURIComponent(m[1]));
    const owner = identifier(e.queryStringParameters?.ownerId ?? actor);
    const grant = unlockGrantOf(e);
    const method = e.requestContext.http.method.toUpperCase();
    if (method === 'GET') return jsonResponse(200, { shares: await service.list(actor, owner, id, grant) });
    if (method === 'POST') return jsonResponse(200, { share: await service.apply(actor, owner, id, shareCommand(e.body), grant) });
    return notFoundResponse();
  } catch (error) {
    if (error instanceof NoteSecurityError) return securityErrorResponse(error);
    const code = error instanceof ShareError ? error.code : 'unavailable';
    const status = code === 'unavailable' ? 503 : ['duplicate', 'staleAccess'].includes(code) ? 409 : 422;
    return jsonResponse(status, { code: `SHARE_${code.replace(/[A-Z]/g, x => `_${x}`).toUpperCase()}`, retryable: status === 503 });
  }
}
