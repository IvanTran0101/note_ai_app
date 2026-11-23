/**
 * Deterministic content hashing for calibration provenance.
 *
 * The hash must depend on content only, never on key insertion order or object identity, so a
 * hand-edited fixture or recording file always changes it and a stale freeze is detectable.
 */
import { createHash } from 'node:crypto';

/** Recursively sorts object keys; arrays keep their order because fixture order is contract. */
export function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (typeof value === 'object' && value !== null) {
    const source = value as Record<string, unknown>;
    const sorted: Record<string, unknown> = {};
    for (const key of Object.keys(source).sort()) sorted[key] = canonicalize(source[key]);
    return sorted;
  }
  return value;
}

/** SHA-256 over canonical JSON, prefixed so a hash is self-describing in reports and receipts. */
export function contentHash(value: unknown): string {
  return `sha256:${createHash('sha256').update(JSON.stringify(canonicalize(value)), 'utf8').digest('hex')}`;
}
