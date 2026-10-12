import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Tokenizer } from '@huggingface/tokenizers';
import { sha256Hex } from './snapshot';
import { IndexFailure } from './types';
import type { Counter } from '../types';

import manifest from '../../../docs/rag/tokenizer_manifest.json';
export const TOKENIZER_REVISION = manifest.revision;
export const TOKENIZER_FILES = Object.freeze(manifest.files);
export function loadTokenCounter(directory: string): Counter {
  try {
    const pinned = Object.entries(TOKENIZER_FILES).map(([file, digest]) => {
      const bytes = readFileSync(join(directory, file), 'utf8');
      if (sha256Hex(bytes) !== digest) throw new Error('hash');
      const object: unknown = JSON.parse(bytes);
      if (!object || typeof object !== 'object' || Array.isArray(object)) throw new Error('schema');
      return object;
    });
    const tokenizer = new Tokenizer(pinned[0], pinned[1]);
    // Includes CLS/SEP; reserve 8 more tokens for provider-side input-type framing.
    return text => tokenizer.encode(text).ids.length + manifest.framingMarginTokens;
  } catch { throw new IndexFailure('TOKENIZER_UNAVAILABLE'); }
}
