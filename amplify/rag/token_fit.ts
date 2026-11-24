import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';
import { Tokenizer } from '@huggingface/tokenizers';
import manifest from '../../docs/rag/deepseek_tokenizer_manifest.json';
import { RagFailure, type Counter } from './types';
import { isWellFormed } from './chunking';

/** Raw evidence/output uses the pinned official V4 artifact, never the Cohere tokenizer. */
export function loadDeepSeekCounter(directory: string): Counter {
  try {
    const bytes = Object.fromEntries(Object.entries(manifest.files).map(([name, digest]) => {
      const body = readFileSync(resolve(directory, name));
      if (createHash('sha256').update(body).digest('hex') !== digest) throw new Error('checksum');
      return [name, JSON.parse(body.toString('utf8'))];
    }));
    const tokenizer = new Tokenizer(bytes['tokenizer.json'], bytes['tokenizer_config.json']);
    return (text) => {
      if (!isWellFormed(text)) throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
      return tokenizer.encode(text, { add_special_tokens: false }).ids.length;
    };
  } catch {
    throw new RagFailure('LIVE_POLICY_NOT_CONFIGURED');
  }
}

/** shortcut: Jev has no published tokenizer here; conservative bytes+overhead admission,
 * not an exact token count. Replace only with a provider-pinned tokenizer before production. */
export const jevInputUpperBound: Counter = (text) => {
  if (!isWellFormed(text)) throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
  return Buffer.byteLength(text, 'utf8') + 512;
};

/** Prompt reservation includes role/template overhead; actual billed usage comes from provider. */
export const deepSeekInputUpperBound = (text: string): number => jevInputUpperBound(text);
