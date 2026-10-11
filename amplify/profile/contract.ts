/**
 * Profile/avatar wire contract (M01.1): DTO, bounds, error envelope and the
 * actual-bytes image inspection for the two avatar formats the app accepts.
 *
 * Frozen in `docs/contracts/profile_api_v1.md`. No SDK, credentials, storage
 * keys, versions or presigned URLs cross this boundary: `avatarReference` is an
 * opaque association id, and `ProfileRow.avatar` (store.ts) stays server-side.
 */
import type { APIGatewayProxyStructuredResultV2 } from 'aws-lambda';

export const MAX_NAME_POINTS = 100;
export const MAX_METADATA_BYTES = 8 * 1024;
export const MAX_AVATAR_BYTES = 1024 * 1024;
export const MAX_AVATAR_DIMENSION = 2048;
export const AVATAR_MIMES = ['image/png', 'image/jpeg'] as const;
export type AvatarMime = (typeof AVATAR_MIMES)[number];

export type ProfileDTO = Readonly<{
  userId: string;
  displayName: string;
  avatarReference: string | null;
  revision: number;
  updatedAt: string;
}>;

export type ProfileErrorCode =
  | 'PROFILE_MISSING'
  | 'PROFILE_AVATAR_MISSING'
  | 'PROFILE_INVALID'
  | 'PROFILE_CONFLICT'
  | 'PROFILE_UNAVAILABLE'
  | 'PROFILE_UNAUTHORIZED';

/** `retryable` is explicit so a client never retries a rejected write. */
export class ProfileError extends Error {
  constructor(readonly code: ProfileErrorCode, readonly retryable = false) {
    super(`ProfileError:${code}`);
    this.name = 'ProfileError';
  }
}

export const profileErrorStatus = (code: ProfileErrorCode): number =>
  (code === 'PROFILE_MISSING' || code === 'PROFILE_AVATAR_MISSING') ? 404
  : code === 'PROFILE_UNAUTHORIZED' ? 403
  : code === 'PROFILE_CONFLICT' ? 409
  : code === 'PROFILE_UNAVAILABLE' ? 503
  : 422;

export const jsonResponse = (statusCode: number, body: unknown): APIGatewayProxyStructuredResultV2 => ({
  statusCode,
  headers: { 'content-type': 'application/json' },
  body: JSON.stringify(body),
});

/** Frozen envelope: `{code}` only, so no provider text can leak through a body. */
export const profileErrorResponse = (error: ProfileError): APIGatewayProxyStructuredResultV2 =>
  jsonResponse(profileErrorStatus(error.code), { code: error.code });

const isPlainObject = (value: unknown): value is Record<string, unknown> =>
  !!value && typeof value === 'object' && !Array.isArray(value);

/** UUID or bounded opaque token; stable across client retries of one action. */
export function requestIdOf(value: unknown): string {
  if (typeof value !== 'string' || !/^[A-Za-z0-9_-]{8,128}$/.test(value)) throw new ProfileError('PROFILE_INVALID');
  return value;
}

export function revisionOf(value: unknown): number {
  if (!Number.isSafeInteger(value) || (value as number) < 0) throw new ProfileError('PROFILE_INVALID');
  return value as number;
}

/** Trim before measuring so whitespace alone cannot satisfy the 1..100 rule. */
export function displayNameOf(value: unknown): string {
  if (typeof value !== 'string') throw new ProfileError('PROFILE_INVALID');
  const name = value.trim();
  if (!name || [...name].length > MAX_NAME_POINTS) throw new ProfileError('PROFILE_INVALID');
  return name;
}

export function avatarReferenceOf(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'string' || !/^av_[a-f0-9]{32}$/.test(value)) throw new ProfileError('PROFILE_INVALID');
  return value;
}

export function avatarIntentOf(value: unknown): Readonly<{
  requestId: string; expectedProfileRevision: number; mime: AvatarMime; sizeBytes: number; sha256: string;
}> {
  if (!isPlainObject(value) || Object.keys(value).length !== 5) throw new ProfileError('PROFILE_INVALID');
  const { requestId, expectedProfileRevision, mime, sizeBytes, sha256 } = value;
  if (!AVATAR_MIMES.includes(mime as AvatarMime)) throw new ProfileError('PROFILE_INVALID');
  if (!Number.isSafeInteger(sizeBytes) || (sizeBytes as number) < 1 || (sizeBytes as number) > MAX_AVATAR_BYTES) {
    throw new ProfileError('PROFILE_INVALID');
  }
  if (typeof sha256 !== 'string' || !/^[a-f0-9]{64}$/.test(sha256)) throw new ProfileError('PROFILE_INVALID');
  return {
    requestId: requestIdOf(requestId),
    expectedProfileRevision: revisionOf(expectedProfileRevision),
    mime: mime as AvatarMime,
    sizeBytes: sizeBytes as number,
    sha256,
  };
}

/** Only the declared keys are accepted, so a body cannot smuggle storage keys. */
export function profileWriteOf(value: unknown, actor: string): Readonly<{
  requestId: string; expectedRevision: number; displayName: string; avatarReference: string | null;
}> {
  if (!isPlainObject(value)) throw new ProfileError('PROFILE_INVALID');
  const allowed = new Set(['requestId', 'expectedRevision', 'displayName', 'avatarReference']);
  for (const [key, raw] of Object.entries(value)) {
    if (allowed.has(key)) continue;
    if (['ownerId', 'userId', 'actor', 'sub'].includes(key) && typeof raw === 'string' && raw !== actor) {
      throw new ProfileError('PROFILE_UNAUTHORIZED');
    }
    throw new ProfileError('PROFILE_INVALID');
  }
  for (const key of allowed) if (!(key in value)) throw new ProfileError('PROFILE_INVALID');
  return {
    requestId: requestIdOf(value.requestId),
    expectedRevision: revisionOf(value.expectedRevision),
    displayName: displayNameOf(value.displayName),
    avatarReference: avatarReferenceOf(value.avatarReference),
  };
}

/** Inspect bounded container headers and dimensions before association; Flutter decodes pixels. */
export function inspectImage(bytes: Buffer, mime: AvatarMime): Readonly<{ width: number; height: number }> {
  const size = bytes.length;
  if (size < 45 || size > MAX_AVATAR_BYTES ||
      !Number.isSafeInteger(MAX_AVATAR_DIMENSION)) throw new ProfileError('PROFILE_INVALID');
  const dims = mime === 'image/png' ? pngSize(bytes) : mime === 'image/jpeg' ? jpegSize(bytes) : null;
  if (!dims || dims.width < 1 || dims.height < 1 ||
      dims.width > MAX_AVATAR_DIMENSION || dims.height > MAX_AVATAR_DIMENSION) {
    throw new ProfileError('PROFILE_INVALID');
  }
  return dims;
}

const PNG_SIGNATURE = [137, 80, 78, 71, 13, 10, 26, 10];

function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ ((crc & 1) ? 0xedb88320 : 0);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function pngSize(bytes: Buffer): Readonly<{ width: number; height: number }> | null {
  if (!PNG_SIGNATURE.every((b, i) => bytes[i] === b)) return null;
  let pos = 8, seenData = false;
  let dimensions: {width: number; height: number} | null = null;
  while (pos + 12 <= bytes.length) {
    const length = bytes.readUInt32BE(pos);
    if (length > bytes.length - pos - 12) return null;
    const type = bytes.toString('ascii', pos + 4, pos + 8);
    if (crc32(bytes.subarray(pos + 4, pos + 8 + length)) !== bytes.readUInt32BE(pos + 8 + length)) return null;
    if (pos === 8 && type !== 'IHDR') return null;
    if (type === 'IHDR') {
      if (dimensions || length !== 13) return null;
      const depth = bytes[pos + 16], color = bytes[pos + 17];
      const depths: Record<number, number[]> = {0:[1,2,4,8,16],2:[8,16],3:[1,2,4,8],4:[8,16],6:[8,16]};
      if (!depths[color]?.includes(depth) || bytes[pos + 18] !== 0 || bytes[pos + 19] !== 0 || bytes[pos + 20] > 1) return null;
      dimensions = {width: bytes.readUInt32BE(pos + 8), height: bytes.readUInt32BE(pos + 12)};
    }
    if (type === 'IDAT' && length > 0) seenData = true;
    if (type === 'IEND') return length === 0 && pos + 12 === bytes.length && seenData ? dimensions : null;
    pos += length + 12;
  }
  return null;
}

function jpegSize(bytes: Buffer): Readonly<{ width: number; height: number }> | null {
  if (bytes.length < 45 || bytes[0] !== 0xff || bytes[1] !== 0xd8 || bytes[bytes.length - 2] !== 0xff || bytes[bytes.length - 1] !== 0xd9) return null;
  let pos = 2;
  let dimensions: {width: number; height: number} | null = null;
  while (pos + 4 <= bytes.length) {
    if (bytes[pos] !== 0xff) return null;
    while (pos < bytes.length && bytes[pos] === 0xff) pos++;
    if (pos >= bytes.length) return null;
    const marker = bytes[pos++];
    if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (pos + 2 > bytes.length) return null;
    const length = bytes.readUInt16BE(pos);
    if (length < 2 || pos + length > bytes.length) return null;
    if (marker >= 0xc0 && marker <= 0xcf && marker !== 0xc4 && marker !== 0xc8 && marker !== 0xcc) {
      if (dimensions || length < 8 || length !== 8 + 3 * bytes[pos + 7]) return null;
      dimensions = {height: bytes.readUInt16BE(pos + 3), width: bytes.readUInt16BE(pos + 5)};
    }
    if (marker === 0xda) return dimensions && length >= 6 && pos + length < bytes.length - 2 ? dimensions : null;
    pos += length;
  }
  return null;
}
