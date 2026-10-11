/**
 * HTTP routing for the `/me/*` profile endpoints (M01.1).
 *
 * `amplify/sync/handler.ts` (root-owned) already checks the JWT `sub` and
 * `token_use=access` before dispatching here; this module repeats the sub check
 * as defence in depth and never accepts an owner from the body or query string.
 * Routes, bodies, statuses and error codes are frozen in
 * `docs/contracts/profile_api_v1.md`.
 */
import type {
  APIGatewayProxyEventV2WithJWTAuthorizer as Event,
  APIGatewayProxyStructuredResultV2,
} from 'aws-lambda';
import { jsonResponse, MAX_METADATA_BYTES, ProfileError, profileErrorResponse } from './contract';
import type { AvatarBinary, ProfileService } from './profile_service';

export { createProfileService, ProfileServiceImpl } from './profile_service';
export type { AvatarBinary, AvatarIntent, ProfileService } from './profile_service';
export { ProfileError } from './contract';
export type { ProfileDTO } from './contract';

const PROFILE_PATH = '/me/profile';
const INTENTS_PATH = '/me/avatar-intents';
const AVATAR_PATH = '/me/avatar';
const COMPLETE_PATH = /^\/me\/avatar-intents\/([A-Za-z0-9_-]{1,128})\/complete$/;

export const isProfilePath = (path: string): boolean =>
  path === PROFILE_PATH || path === INTENTS_PATH || path === AVATAR_PATH || COMPLETE_PATH.test(path);

const notFound = (): APIGatewayProxyStructuredResultV2 => jsonResponse(404, { code: 'PROFILE_UNAVAILABLE' });

const bodyOf = (event: Event, emptyAllowed = false): Record<string, unknown> => {
  if (!event.body) {
    if (emptyAllowed) return {};
    throw new ProfileError('PROFILE_INVALID');
  }
  if (event.isBase64Encoded || Buffer.byteLength(event.body, 'utf8') > MAX_METADATA_BYTES) throw new ProfileError('PROFILE_INVALID');
  let parsed: unknown;
  try {
    parsed = JSON.parse(event.body);
  } catch {
    throw new ProfileError('PROFILE_INVALID');
  }
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new ProfileError('PROFILE_INVALID');
  return parsed as Record<string, unknown>;
};

/** Exact-version private bytes; no signed GET URL, no client-supplied key. */
const avatarResponse = (avatar: AvatarBinary): APIGatewayProxyStructuredResultV2 => {
  try {
    return {
      statusCode: 200,
      isBase64Encoded: true,
      headers: {
        'content-type': avatar.mime,
        'content-length': String(avatar.bytes.length),
        'cache-control': 'no-store',
        'x-content-type-options': 'nosniff',
      },
      body: avatar.bytes.toString('base64'),
    };
  } finally {
    avatar.bytes.fill(0);
  }
};

export async function handleProfile(
  event: Event,
  actor: string,
  service: ProfileService,
): Promise<APIGatewayProxyStructuredResultV2> {
  try {
    const claims = event.requestContext?.authorizer?.jwt?.claims;
    if (!claims?.sub || claims.sub !== actor || claims.token_use !== 'access') throw new ProfileError('PROFILE_UNAUTHORIZED');
    const path = event.rawPath ?? '';
    const method = event.requestContext?.http?.method?.toUpperCase() ?? '';
    const allows = (expected: string) => method === expected;

    if (path === PROFILE_PATH && (allows('GET') || allows('POST'))) {
      return method === 'POST'
        ? jsonResponse(200, { profile: await service.writeProfile(actor, bodyOf(event)) })
        : jsonResponse(200, { profile: await service.getProfile(actor) });
    }
    if (path === INTENTS_PATH && allows('POST')) {
      return jsonResponse(200, await service.createAvatarIntent(actor, bodyOf(event)));
    }
    const complete = COMPLETE_PATH.exec(path);
    if (complete && allows('POST')) {
      // The client never supplies key or version: only the intent id.
      if (Object.keys(bodyOf(event, true)).length) throw new ProfileError('PROFILE_INVALID');
      return jsonResponse(200, { profile: await service.completeAvatarIntent(actor, complete[1]) });
    }
    if (path === AVATAR_PATH && allows('GET')) {
      return avatarResponse(await service.readAvatar(actor));
    }
    return notFound();
  } catch (error) {
    if (error instanceof ProfileError) return profileErrorResponse(error);
    return jsonResponse(503, { code: 'PROFILE_UNAVAILABLE', retryable: true });
  }
}
