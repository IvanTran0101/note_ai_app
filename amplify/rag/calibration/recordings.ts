/**
 * Validated loader for recorded Jev Noul envelopes.
 *
 * A recording is evidence about what the real provider returned, so it is loaded as untrusted
 * input and its provenance string is carried into the report verbatim. Envelopes are kept raw
 * here; the evaluator validates each one against the frozen model with `validateNoul` so an
 * invalid or absent envelope is reported as an error instead of being turned into a value.
 */
import { fail } from './errors';
import { contentHash } from './hash';
import { RECORDING_VERSION, type RecordingFile, type RecordedNoul } from './types';

const FILE_KEYS = ['recordingVersion', 'provenance', 'results'] as const;
const RECORDED_KEYS = ['fixtureId', 'status', 'envelope'] as const;
const ERROR_KEYS = ['fixtureId', 'status', 'detail'] as const;
const STATUSES = ['recorded', 'missing', 'provider_error'] as const;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, keys: readonly string[]): boolean =>
  Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));

/** Marks a recording that was not produced by the real provider; it may never be presented as live. */
export const SYNTHETIC_RECORDING_PROVENANCE = 'synthetic-envelopes-not-live-model-output';

export function loadRecordingFile(raw: unknown): RecordingFile {
  if (!isRecord(raw) || !hasExactKeys(raw, FILE_KEYS)) fail('INVALID_RECORDING', `recording file must be exactly {${FILE_KEYS.join(', ')}}`);
  if (raw['recordingVersion'] !== RECORDING_VERSION) fail('INVALID_RECORDING', `recordingVersion must be "${RECORDING_VERSION}"`);
  const provenance = raw['provenance'];
  if (typeof provenance !== 'string' || provenance.trim().length === 0) fail('INVALID_RECORDING', 'provenance must say where the envelopes came from');
  if (!Array.isArray(raw['results'])) fail('INVALID_RECORDING', 'results must be an array');
  const seen = new Set<string>();
  const results = (raw['results'] as unknown[]).map((entry, index): RecordedNoul => {
    const at = `results[${index}]`;
    if (!isRecord(entry)) fail('INVALID_RECORDING', `${at} must be an object`);
    const fixtureId = entry['fixtureId'];
    if (typeof fixtureId !== 'string' || fixtureId.trim().length === 0) fail('INVALID_RECORDING', `${at}.fixtureId must be a non-blank string`);
    if (seen.has(fixtureId)) fail('INVALID_RECORDING', `${at}.fixtureId "${fixtureId}" is recorded twice`);
    seen.add(fixtureId);
    const status = entry['status'];
    if (typeof status !== 'string' || !(STATUSES as readonly string[]).includes(status)) {
      fail('INVALID_RECORDING', `${at}.status must be one of ${STATUSES.join(', ')}`);
    }
    if (status === 'recorded') {
      if (!hasExactKeys(entry, RECORDED_KEYS)) fail('INVALID_RECORDING', `${at} must be exactly {${RECORDED_KEYS.join(', ')}}`);
      return Object.freeze({ fixtureId, status: 'recorded', envelope: entry['envelope'] });
    }
    if (!hasExactKeys(entry, ERROR_KEYS)) fail('INVALID_RECORDING', `${at} must be exactly {${ERROR_KEYS.join(', ')}}`);
    const detail = entry['detail'];
    if (typeof detail !== 'string' || detail.trim().length === 0) fail('INVALID_RECORDING', `${at}.detail must explain the ${status} outcome`);
    return Object.freeze({ fixtureId, status: status as 'missing' | 'provider_error', detail });
  });
  return Object.freeze({ recordingVersion: RECORDING_VERSION, provenance, results: Object.freeze(results) });
}

export const hashRecording = (recording: RecordingFile): string => contentHash(recording.results);

export const recordedById = (recording: RecordingFile): ReadonlyMap<string, RecordedNoul> =>
  new Map(recording.results.map((entry) => [entry.fixtureId, entry]));
