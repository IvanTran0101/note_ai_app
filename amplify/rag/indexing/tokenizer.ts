import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { Tokenizer } from '@huggingface/tokenizers';
import { sha256Hex } from './snapshot';
import { IndexFailure } from './types';
import type { Counter } from '../types';

import manifest from '../../../docs/rag/tokenizer_manifest.json';
import embeddingGemmaManifest from '../../../docs/rag/embeddinggemma_tokenizer_manifest.json';

export const TOKENIZER_REVISION = manifest.revision;
export const TOKENIZER_FILES = Object.freeze(manifest.files);
export const EMBEDDINGGEMMA_TOKENIZER_REVISION = embeddingGemmaManifest.revision;
export const EMBEDDINGGEMMA_TOKENIZER_FILES = Object.freeze(embeddingGemmaManifest.files);
/** The pinned EmbeddingGemma tokenizer already emits BOS/EOS; llama-server does the same. */
export const EMBEDDINGGEMMA_FRAMING_MARGIN_TOKENS = embeddingGemmaManifest.framingMarginTokens;

function loadPinnedCounter(
  directory: string,
  files: Readonly<Record<string, string>>,
  framingMarginTokens: number,
): Counter {
  try {
    const pinned = Object.entries(files).map(([file, digest]) => {
      const bytes = readFileSync(join(directory, file), 'utf8');
      if (sha256Hex(bytes) !== digest) throw new Error('hash');
      const object: unknown = JSON.parse(bytes);
      if (!object || typeof object !== 'object' || Array.isArray(object)) throw new Error('schema');
      return object;
    });
    const tokenizer = new Tokenizer(pinned[0], pinned[1]);
    return text => tokenizer.encode(text).ids.length + framingMarginTokens;
  } catch { throw new IndexFailure('TOKENIZER_UNAVAILABLE'); }
}

/** Cohere v3 legacy counter; kept frozen so historical fixtures remain meaningful. */
export function loadTokenCounter(directory: string): Counter {
  return loadPinnedCounter(directory, TOKENIZER_FILES, manifest.framingMarginTokens);
}

/** EmbeddingGemma-2 counter: BOS/EOS included, no extra framing margin. */
export function loadEmbeddingGemmaTokenCounter(directory: string): Counter {
  return loadPinnedCounter(
    directory,
    EMBEDDINGGEMMA_TOKENIZER_FILES,
    EMBEDDINGGEMMA_FRAMING_MARGIN_TOKENS,
  );
}
