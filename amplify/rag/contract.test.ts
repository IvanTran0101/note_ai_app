import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  MAX_JSON_DEPTH,
  REQUEST_MAX_BYTES,
  decideNoul,
  parseRequest,
  validateGenerated,
  validateNoul,
} from './contract';
import { RagFailure } from './types';
import type { Counter, Evidence, RuntimeConfig, Source } from './types';

const config: RuntimeConfig = {
  mode: 'mock',
  model: 'jev-fixture',
  thresholds: { answerabilityMin: 0.9, conflictMax: 0.1 },
  jevMaxTokens: 2000,
  requestTimeoutMs: 26000,
};

const body = (question: string, scope: unknown = { type: 'account' }): string =>
  JSON.stringify({ wireVersion: 1, question, scope });

const codeOf = (run: () => unknown): string => {
  try {
    run();
  } catch (error) {
    if (error instanceof RagFailure) return error.code;
    throw error;
  }
  throw new Error('expected a RagFailure');
};

const noul = (support: number, conflict: number): unknown => ({
  model: 'jev-fixture',
  answers: {
    answerable_from_evidence: { type: 'noul', noul: support },
    has_unresolved_conflict: { type: 'noul', noul: conflict },
  },
  usage: { input_tokens: 100, output_tokens: 10 },
});

const source = (sourceId: string, quote: string, over: Partial<Source> = {}): Source => ({
  sourceId,
  noteId: 'n-watch',
  revision: 1,
  title: 'SLGH031',
  startOffset: 0,
  endOffset: quote.length,
  quote,
  ...over,
});

const evidenceOf = (...sources: Source[]): Evidence => ({
  sources: Object.freeze(sources),
  text: sources.map((entry) => `[${entry.sourceId}] ${entry.title}\n${entry.quote}`).join('\n\n'),
});

const generated = (
  answer: string,
  sources: readonly Source[],
  over: Record<string, unknown> = {},
): Record<string, unknown> => ({ answer, sources: sources.map((entry) => ({ ...entry })), ...over });

const shapedCounter: Counter = (text) => text.length;

test('parseRequest accepts both approved scopes and preserves the question text', () => {
  const question = '  SLGH031 chạy bao lâu khi lên cót đầy?  ';
  const account = parseRequest(body(question));
  assert.deepEqual(account, { wireVersion: 1, question, scope: { type: 'account' } });
  const note = parseRequest(body('q', { type: 'note', noteId: 'n-watch' }));
  assert.deepEqual(note.scope, { type: 'note', noteId: 'n-watch' });
});

test('parseRequest refuses client-owned identity, provider, consent and evidence fields', () => {
  for (const field of ['ownerId', 'model', 'consent', 'evidence', 'thresholds', 'questionSetVersion', 'actor']) {
    const value = { wireVersion: 1, question: 'q', scope: { type: 'account' }, [field]: 'x' };
    assert.equal(codeOf(() => parseRequest(JSON.stringify(value))), 'INVALID_INPUT', field);
  }
});

test('parseRequest refuses duplicate JSON keys, including escaped identical keys', () => {
  const rawDuplicate = '{"wireVersion":1,"question":"first","question":"second","scope":{"type":"account"}}';
  assert.equal(codeOf(() => parseRequest(rawDuplicate)), 'INVALID_INPUT');
  const escapedDuplicate =
    '{"wireVersion":1,"question":"q","scope":{"type":"account"},"\\u0071uestion":"again"}';
  assert.equal(codeOf(() => parseRequest(escapedDuplicate)), 'INVALID_INPUT');
  const nestedEscaped = '{"wireVersion":1,"question":"q","scope":{"type":"account","\\u0074ype":"note"}}';
  assert.equal(codeOf(() => parseRequest(nestedEscaped)), 'INVALID_INPUT');
  // An escaped key that is not a duplicate still parses (the escape is decoded, not guessed).
  const escapedValue = '{"wireVersion":1,"question":"caf\\u00e9","scope":{"type":"account"}}';
  assert.equal(parseRequest(escapedValue).question, 'café');
});

test('parseRequest bounds JSON depth instead of trusting JSON.parse with deep nesting', () => {
  const nest = (depth: number): string => '['.repeat(depth) + ']'.repeat(depth);
  assert.equal(codeOf(() => parseRequest(nest(MAX_JSON_DEPTH + 1))), 'INVALID_INPUT');
  assert.equal(codeOf(() => parseRequest(nest(5_000))), 'INVALID_INPUT');
  assert.equal(codeOf(() => parseRequest(nest(50_000))), 'INPUT_TOO_LONG');
});

test('parseRequest enforces the 16 KiB raw body cap on real bytes', () => {
  const base = body('q?');
  const size = new TextEncoder().encode(base).byteLength;
  const atCap = base + ' '.repeat(REQUEST_MAX_BYTES - size);
  assert.equal(new TextEncoder().encode(atCap).byteLength, REQUEST_MAX_BYTES);
  assert.doesNotThrow(() => parseRequest(atCap));
  assert.equal(codeOf(() => parseRequest(`${atCap} `)), 'INPUT_TOO_LONG');
});

test('parseRequest enforces the question code point and UTF-8 byte caps separately', () => {
  assert.doesNotThrow(() => parseRequest(body('a'.repeat(2048))));
  assert.equal(codeOf(() => parseRequest(body('a'.repeat(2049)))), 'INPUT_TOO_LONG');
  assert.doesNotThrow(() => parseRequest(body('🧠'.repeat(1024))));
  assert.equal(codeOf(() => parseRequest(body('🧠'.repeat(1025)))), 'INPUT_TOO_LONG');
});

test('parseRequest refuses lone surrogates instead of replacing them', () => {
  assert.equal(codeOf(() => parseRequest(body('bad \uD800 text'))), 'INVALID_INPUT');
  assert.equal(codeOf(() => parseRequest(`${body('q?')}\uDC00`)), 'INVALID_INPUT');
  assert.doesNotThrow(() => parseRequest(body('valid 🧠 pair')));
});

test('parseRequest rejects non-object, non-string, blank and version-invalid requests', () => {
  for (const raw of ['[]', 'null', '1', '{}', '{"wireVersion":1}', '{"wireVersion":1,"question":"q"}']) {
    assert.equal(codeOf(() => parseRequest(raw)), 'INVALID_INPUT', raw);
  }
  for (const raw of [
    '{"wireVersion":true,"question":"q","scope":{"type":"account"}}',
    '{"wireVersion":1.5,"question":"q","scope":{"type":"account"}}',
    '{"wireVersion":1e999,"question":"q","scope":{"type":"account"}}',
    '{"wireVersion":2,"question":"q","scope":{"type":"account"}}',
    '{"wireVersion":1,"question":" \\n ","scope":{"type":"account"}}',
    '{"wireVersion":1,"question":null,"scope":{"type":"account"}}',
    '{"wireVersion":1,"question":123,"scope":{"type":"account"}}',
  ]) {
    assert.equal(codeOf(() => parseRequest(raw)), 'INVALID_INPUT', raw);
  }
  assert.equal(parseRequest('{"wireVersion":1.0,"question":"q","scope":{"type":"account"}}').wireVersion, 1);
});

test('parseRequest scope is exact: account has no noteId, note needs a trimmed identifier', () => {
  const withNoteId = { type: 'account', noteId: 'n-watch' };
  assert.equal(codeOf(() => parseRequest(body('q', withNoteId))), 'INVALID_INPUT');
  for (const type of ['all', '', null, 1]) {
    assert.equal(codeOf(() => parseRequest(body('q', { type }))), 'INVALID_INPUT', String(type));
  }
  for (const noteId of [false, '', '   ', ' n-watch', 'n-watch ', 'bad\u0000id', 'bad\uD800id', 'a'.repeat(129)]) {
    assert.equal(codeOf(() => parseRequest(body('q', { type: 'note', noteId }))), 'INVALID_INPUT', String(noteId));
  }
  assert.doesNotThrow(() => parseRequest(body('q', { type: 'note', noteId: 'a'.repeat(128) })));
});

test('validateNoul accepts only the exact two-answer envelope from the configured model', () => {
  const envelope = validateNoul(noul(0.96, 0.03), 'jev-fixture');
  assert.equal(envelope.answers.answerable_from_evidence.noul, 0.96);
  assert.equal(envelope.answers.has_unresolved_conflict.noul, 0.03);
  assert.deepEqual(envelope.usage, { input_tokens: 100, output_tokens: 10 });
});

test('validateNoul refuses malformed envelope, answers, probabilities and usage', () => {
  const mutate = (change: (value: Record<string, unknown>) => void): string =>
    codeOf(() => {
      const value = noul(0.96, 0.03) as Record<string, unknown>;
      change(value);
      validateNoul(value, 'jev-fixture');
    });
  assert.equal(codeOf(() => validateNoul(null, 'jev-fixture')), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.equal(codeOf(() => validateNoul(noul(0.96, 0.03), 'other-model')), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.equal(mutate((value) => (value['model'] = null)), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.equal(mutate((value) => (value['questionSetVersion'] = 'rag-evidence.v1')), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.equal(mutate((value) => delete (value['answers'] as Record<string, unknown>)['has_unresolved_conflict']),
    'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.equal(
    mutate((value) => ((value['answers'] as Record<string, Record<string, unknown>>)['answerable_from_evidence']['confidence'] = 0.9)),
    'EVIDENCE_VALIDATION_UNAVAILABLE',
  );
  assert.equal(
    mutate((value) => ((value['answers'] as Record<string, Record<string, unknown>>)['unrequested'] = { type: 'noul', noul: 0.5 })),
    'EVIDENCE_VALIDATION_UNAVAILABLE',
  );
  for (const probability of [true, '0.9', -0.1, 1.1, Number.POSITIVE_INFINITY, Number.NaN, null]) {
    assert.equal(
      mutate((value) => ((value['answers'] as Record<string, Record<string, unknown>>)['answerable_from_evidence']['noul'] = probability)),
      'EVIDENCE_VALIDATION_UNAVAILABLE',
      String(probability),
    );
  }
  for (const usage of [
    { input_tokens: true, output_tokens: 10 },
    { input_tokens: 1.5, output_tokens: 10 },
    { input_tokens: 2 ** 53, output_tokens: 10 },
    { input_tokens: 1, output_tokens: -1 },
    { input_tokens: 1 },
    { input_tokens: 1, output_tokens: 2, total_tokens: 3 },
  ]) {
    assert.equal(mutate((value) => (value['usage'] = usage)), 'EVIDENCE_VALIDATION_UNAVAILABLE', JSON.stringify(usage));
  }
});

test('decideNoul follows the Phase 1 oracle branch order without averaging', () => {
  assert.equal(decideNoul(noul(0.96, 0.03), config), 'ALLOW');
  assert.equal(decideNoul(noul(0.9, 0.1), config), 'ALLOW');
  assert.equal(decideNoul(noul(0.96, 0.9), config), 'UNRESOLVED_CONFLICT');
  assert.equal(decideNoul(noul(0.1, 1), config), 'UNRESOLVED_CONFLICT');
  assert.equal(decideNoul(noul(0.05, 0.03), config), 'INSUFFICIENT_EVIDENCE');
  assert.equal(decideNoul(noul(0.1, 0.03), config), 'INSUFFICIENT_EVIDENCE');
  assert.equal(decideNoul(noul(0.5, 0.03), config), 'UNCERTAIN');
  assert.equal(decideNoul(noul(0.96, 0.2), config), 'UNCERTAIN');
});

test('decideNoul fails closed with the policy code before it judges the envelope', () => {
  const unconfigured: readonly [string, RuntimeConfig][] = [
    ['null model', { ...config, model: null }],
    ['null thresholds', { ...config, thresholds: null }],
    ['low threshold not above 0.5', { ...config, thresholds: { answerabilityMin: 0.5, conflictMax: 0.1 } }],
    ['conflict threshold too high', { ...config, thresholds: { answerabilityMin: 0.9, conflictMax: 0.5 } }],
    ['non-finite threshold', { ...config, thresholds: { answerabilityMin: Number.NaN, conflictMax: 0.1 } }],
  ];
  for (const [name, runtime] of unconfigured) {
    assert.equal(codeOf(() => decideNoul(noul(0.96, 0.03), runtime)), 'LIVE_POLICY_NOT_CONFIGURED', name);
  }
  assert.equal(codeOf(() => decideNoul(noul(0.96, 0.03), { ...config, model: 'other' })), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.equal(codeOf(() => decideNoul({ ...(noul(0.96, 0.03) as object), model: 'other' }, config)),
    'EVIDENCE_VALIDATION_UNAVAILABLE');
  assert.equal(codeOf(() => decideNoul(null, config)), 'EVIDENCE_VALIDATION_UNAVAILABLE');
});

test('validateGenerated accepts an answer that cites exactly the approved evidence', () => {
  const first = source('S1', 'alpha beta');
  const second = source('S2', 'gamma', { noteId: 'n-meeting', title: 'Buổi demo' });
  const evidence = evidenceOf(first, second);
  const result = validateGenerated(
    generated('Khoảng 80 giờ. [S1] [S2]', [first, second]),
    evidence,
    shapedCounter,
  );
  assert.equal(result.answer, 'Khoảng 80 giờ. [S1] [S2]');
  assert.deepEqual(result.sources, [first, second]);
});

test('validateGenerated refuses forged citations and unreferenced or unclaimed sources', () => {
  const first = source('S1', 'alpha beta');
  const second = source('S2', 'gamma');
  const evidence = evidenceOf(first, second);
  const rejected: readonly [string, unknown][] = [
    ['unknown source id', generated('A. [S9]', [source('S9', 'alpha beta')])],
    ['changed quote', generated('A. [S1]', [{ ...first, quote: 'changed' }])],
    ['changed revision', generated('A. [S1]', [{ ...first, revision: 2 }])],
    ['changed title', generated('A. [S1]', [{ ...first, title: 'Other' }])],
    ['changed noteId', generated('A. [S1]', [{ ...first, noteId: 'n-other' }])],
    ['changed offsets', generated('A. [S1]', [{ ...first, endOffset: 3 }])],
    ['string revision', generated('A. [S1]', [{ ...first, revision: '1' } as unknown as Source])],
    ['extra url field', generated('A. [S1]', [{ ...first, url: 'https://untrusted.example' } as unknown as Source])],
    ['duplicate source id', generated('A. [S1]', [first, first])],
    ['empty sources', generated('A. [S1]', [])],
    ['no citation label', generated('Answer with no source label', [first])],
    ['label for unused source', generated('A. [S2]', [first])],
    ['unreferenced used source', generated('A. [S1]', [first, second])],
    ['unknown extra label', generated('A. [S1] [S9]', [first])],
    ['zero label', generated('A. [S0]', [first])],
    ['blank answer', generated('   ', [first])],
    ['lone surrogate answer', generated('bad \uD800 [S1]', [first])],
    ['extra confidence field', generated('A. [S1]', [first], { confidence: 0.99 })],
    ['extra owner field', generated('A. [S1]', [first], { ownerId: 'actor-b' })],
    ['missing sources', { answer: 'A. [S1]' }],
    ['answer not a string', generated(7 as unknown as string, [first])],
    ['sources not an array', { answer: 'A. [S1]', sources: 'S1' }],
  ];
  for (const [name, value] of rejected) {
    assert.equal(codeOf(() => validateGenerated(value, evidence, shapedCounter)), 'INVALID_PROVIDER_OUTPUT', name);
  }
});

test('validateGenerated bounds output with the guarded counter and fails closed on a bad counter', () => {
  const first = source('S1', 'alpha beta');
  const evidence = evidenceOf(first);
  const value = generated('A. [S1]', [first]);
  assert.equal(validateGenerated(value, evidence, () => 1024).answer, 'A. [S1]');
  assert.equal(codeOf(() => validateGenerated(value, evidence, () => 1025)), 'INVALID_PROVIDER_OUTPUT');
  for (const counter of [
    (() => -1) as Counter,
    (() => 1.5) as Counter,
    (() => Number.NaN) as Counter,
    (() => {
      throw new Error('counter down');
    }) as Counter,
    undefined as unknown as Counter,
  ]) {
    assert.equal(codeOf(() => validateGenerated(value, evidence, counter)), 'EVIDENCE_VALIDATION_UNAVAILABLE');
  }
});

test('validateGenerated treats a broken approved bundle as unavailable evidence, not as provider output', () => {
  const first = source('S1', 'alpha beta');
  const cases: readonly Evidence[] = [
    { sources: Object.freeze([first, first]), text: '' },
    { sources: Object.freeze([{ ...first, quote: 'bad \uD800' }]), text: '' },
    { sources: Object.freeze([{ ...first, extra: true } as unknown as Source]), text: '' },
    { sources: 'nope' as unknown as readonly Source[], text: '' },
  ];
  for (const evidence of cases) {
    assert.equal(codeOf(() => validateGenerated(generated('A. [S1]', [first]), evidence, shapedCounter)),
      'EVIDENCE_VALIDATION_UNAVAILABLE');
  }
});
