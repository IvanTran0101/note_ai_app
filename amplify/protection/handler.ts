import type { APIGatewayProxyEventV2WithJWTAuthorizer as Event } from 'aws-lambda';
import { jsonResponse, noteBodyOf, notFoundResponse } from '../sync/sync_response';
import { NOTE_OPERATIONS, NoteSecurityError, identifier } from './protection_store';
import type { NoteOperation, NoteSecurityCode } from './protection_store';
import type { ProtectionUseCases } from './use_cases';
import { requirePassword } from './argon2id_password_hasher';

const failures: Record<NoteSecurityCode, readonly [number, string]> = {
  locked: [423, 'NOTE_LOCKED'], denied: [403, 'NOTE_ACCESS_DENIED'],
  expired: [403, 'NOTE_GRANT_EXPIRED'], staleRevision: [409, 'NOTE_SECURITY_STALE'],
  invalidPassword: [403, 'NOTE_PASSWORD_INVALID'], rateLimited: [429, 'NOTE_RATE_LIMITED'],
  unavailable: [503, 'NOTE_SECURITY_UNAVAILABLE'], invalidChallenge: [403, 'NOTE_CHALLENGE_INVALID'],
  invalidInput: [422, 'NOTE_SECURITY_INPUT_INVALID'],
};

export const securityErrorResponse = (error: NoteSecurityError) => {
  const [status, code] = failures[error.code];
  return jsonResponse(status, { code, retryable: error.code === 'unavailable' });
};

export const unlockGrantOf = (event: Event): string | undefined => {
  const grant = Object.entries(event.headers ?? {}).find(([k]) => k.toLowerCase() === 'x-note-unlock-grant')?.[1];
  if (grant && (grant.length > 128 || !/^[A-Za-z0-9_-]{43}$/.test(grant))) throw new NoteSecurityError('invalidInput');
  return grant;
};

const bodyOf = (event: Event, allowed: readonly string[]): Record<string, unknown> => {
  if (!event.body || event.isBase64Encoded || event.body.length > 4096) throw new NoteSecurityError('invalidInput');
  try {
    const body = JSON.parse(event.body);
    if (!body || typeof body !== 'object' || Array.isArray(body) ||
        Object.keys(body).some(k => !allowed.includes(k))) throw new Error();
    return body;
  } catch { throw new NoteSecurityError('invalidInput'); }
};
const revision = (value: unknown): number => {
  if (typeof value !== 'number' || !Number.isSafeInteger(value) || value < 0) throw new NoteSecurityError('invalidInput');
  return value;
};
const password = (value: unknown): string => {
  if (typeof value !== 'string') throw new NoteSecurityError('invalidInput');
  requirePassword(value); return value;
};
const operations = (value: unknown): readonly NoteOperation[] => {
  if (!Array.isArray(value) || !value.length || value.length > NOTE_OPERATIONS.length ||
      value.some(op => !NOTE_OPERATIONS.includes(op))) throw new NoteSecurityError('invalidInput');
  return value;
};

/** Only verified JWT identity/mailbox enter the use cases. No body identity is accepted. */
export const handleProtection = async (event: Event, actor: string, service: ProtectionUseCases) => {
  try {
    const match = /^\/notes\/([^/]+)\/(content|protection(?:\/(enable|unlock|change|disable|reset\/request|reset\/confirm))?)$/.exec(event.rawPath);
    if (!match) return notFoundResponse();
    let noteId: string;
    try { noteId = identifier(decodeURIComponent(match[1])); } catch { throw new NoteSecurityError('invalidInput'); }
    const owner = identifier(event.queryStringParameters?.ownerId ?? actor);
    const method = event.requestContext.http.method.toUpperCase();
    const action = match[3];
    const grant = unlockGrantOf(event);
    if (method === 'GET' && match[2] === 'content') return jsonResponse(200, noteBodyOf(await service.content(actor, owner, noteId, grant), true));
    if (method === 'GET' && !action) return jsonResponse(200, await service.metadata(actor, owner, noteId));
    if (method !== 'POST' || !action) return notFoundResponse();
    return jsonResponse(200, await dispatch(action, event, actor, owner, noteId, grant, service));
  } catch (error) {
    return securityErrorResponse(error instanceof NoteSecurityError ? error : new NoteSecurityError('unavailable'));
  }
};

const dispatch = async (action: string, event: Event, actor: string, owner: string,
  id: string, grant: string | undefined, service: ProtectionUseCases) => {
  switch (action) {
    case 'enable': {
      const b = bodyOf(event, ['password', 'expectedContentRevision']);
      return service.enable(actor, owner, id, password(b.password), revision(b.expectedContentRevision));
    }
    case 'unlock': {
      const b = bodyOf(event, ['password', 'operations']);
      return service.unlock(actor, owner, id, password(b.password), operations(b.operations));
    }
    case 'change': {
      const b = bodyOf(event, ['currentPassword', 'newPassword', 'expectedProtectionRevision']);
      return service.change(actor, owner, id, password(b.currentPassword), password(b.newPassword), revision(b.expectedProtectionRevision), grant);
    }
    case 'disable': {
      const b = bodyOf(event, ['currentPassword', 'expectedProtectionRevision']);
      return service.disable(actor, owner, id, password(b.currentPassword), revision(b.expectedProtectionRevision), grant);
    }
    case 'reset/request': {
      bodyOf(event, []);
      return service.requestRecovery(actor, owner, id, mailboxOf(event));
    }
    case 'reset/confirm': {
      const b = bodyOf(event, ['challengeId', 'code', 'newPassword']);
      if (typeof b.code !== 'string') throw new NoteSecurityError('invalidInput');
      return service.confirmRecovery(actor, owner, id, mailboxOf(event), identifier(b.challengeId), b.code, password(b.newPassword));
    }
    default: throw new NoteSecurityError('invalidInput');
  }
};
const mailboxOf = (event: Event): string => {
  const email = event.requestContext.authorizer.jwt.claims['email'];
  if (typeof email !== 'string' || email.length > 254) throw new NoteSecurityError('invalidInput');
  return email;
};
