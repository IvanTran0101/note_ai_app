/**
 * Contract tests for the frozen Phase 4 fixture file: distribution, identity, source-span truth,
 * synthetic provenance, rejected tampering and the malicious/prompt-injection rules. These labels
 * are synthetic and author-claimed; no test here may assert human review.
 */
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { CalibrationFailure } from './errors';
import {
  EMBEDDED_INSTRUCTION, SYNTHETIC_MARKER, TOTAL_FIXTURES, assertNoGroupLeak, evidenceTextFor,
  hashFixtures, loadFixtureFile, readFixtureFile, validateDistribution, validateFixture, validateFixtureSet,
} from './fixtures';
import { CATEGORIES, LABEL_PROVENANCE, LANGUAGES, SPLITS, TRAITS, type Category, type Language, type Split } from './types';

const FIXTURE_PATH = fileURLToPath(new URL('../../../test/fixtures/rag/phase4/fixtures.json', import.meta.url));
const rawFile = JSON.parse(readFileSync(FIXTURE_PATH, 'utf8')) as Record<string, unknown>;
const rawFixtures = rawFile['fixtures'] as Record<string, unknown>[];
const set = readFixtureFile(FIXTURE_PATH);

const codeOf = (run: () => unknown): string => {
  try {
    run();
  } catch (error) {
    return error instanceof CalibrationFailure ? error.code : `unexpected:${String(error)}`;
  }
  return 'no-throw';
};

test('corrected fixture distribution keeps64/split/language coverage without forcing Hanh into insufficient', () => {
  assert.equal(set.fixtures.length, TOTAL_FIXTURES);
  const counts = validateDistribution(set.fixtures);
  assert.deepEqual(counts.bySplit, { development: 32, confirmation: 32 } satisfies Record<Split, number>);
  assert.deepEqual(counts.byLanguage, { vi: 32, en: 32 } satisfies Record<Language, number>);
  for (const category of CATEGORIES) {
    const correction = category === 'answerable' ? 1 : category === 'insufficient' ? -1 : 0;
    assert.equal(counts.byCategory[category], 16 + correction, category);
    for (const language of LANGUAGES) assert.equal(counts.byCategoryLanguage[`${category}/${language}`], 8 + (language === 'vi' ? correction : 0), `${category}/${language}`);
  }
  for (const split of SPLITS) for (const language of LANGUAGES) assert.equal(counts.bySplitLanguage[`${split}/${language}`], 16, `${split}/${language}`);
  for (const trait of TRAITS) assert.ok(counts.traits[trait] >= 8, `trait ${trait} = ${counts.traits[trait]}`);
  assert.match(set.fixtureHash, /^sha256:[0-9a-f]{64}$/);
  assert.equal(set.fixtureHash, hashFixtures(set.fixtures));
  assert.notEqual(set.developmentHash, set.confirmationHash);
  assert.equal(set.humanReviewed, false);
  assert.equal(set.labelProvenance, LABEL_PROVENANCE);
  assert.match(set.disclaimer, /not human-reviewed/);
});

test('every fixture id encodes its own split, language and category, and no group crosses a split', () => {
  const prefix: Record<Category, string> = { answerable: 'ans', insufficient: 'ins', conflict: 'con', ambiguous: 'amb' };
  const short: Record<Split, string> = { development: 'dev', confirmation: 'conf' };
  const ids = new Set<string>();
  for (const fixture of set.fixtures) {
    assert.match(fixture.id, /^fx-(dev|conf)-(vi|en)-(ans|ins|con|amb)-\d{2}$/);
    assert.ok(fixture.id.includes(`-${short[fixture.split]}-${fixture.language}-${prefix[fixture.category]}-`), fixture.id);
    assert.match(fixture.groupId, new RegExp(`^g-${short[fixture.split]}-${fixture.language}-[a-z0-9-]+$`));
    assert.equal(ids.has(fixture.id), false, `duplicate ${fixture.id}`);
    ids.add(fixture.id);
    assert.equal(fixture.provenance, LABEL_PROVENANCE);
    assert.equal(fixture.notes.length >= 1 && fixture.evidence.sources.length >= 1, true);
  }
  assertNoGroupLeak(set.fixtures);
  assert.equal(new Set(set.fixtures.map((fixture) => fixture.groupId)).size < set.fixtures.length, true, 'related variants must share a group');
});

test('every source quote is the exact UTF-16 end-exclusive slice of a synthetic note', () => {
  for (const fixture of set.fixtures) {
    assert.equal(fixture.evidence.text, evidenceTextFor(fixture.evidence.sources), fixture.id);
    assert.match(fixture.evidence.text, /SYNTHETIC/);
    assert.match(fixture.question, fixture.language === 'vi' ? /[ăâđêôơưàáảãạằắẳẵặầấẩẫậèéẻẽẹềếểễệìíỉĩịòóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ]/i : /^[\u0000-\u007f]+$/);
    for (const source of fixture.evidence.sources) {
      const note = fixture.notes.find((candidate) => candidate.noteId === source.noteId);
      assert.ok(note, `${fixture.id} ${source.sourceId}`);
      assert.equal(note.content.slice(source.startOffset, source.endOffset), source.quote, `${fixture.id} ${source.sourceId}`);
      assert.equal(source.quote.length, source.endOffset - source.startOffset);
      assert.equal(note.revision, source.revision);
      assert.equal(note.title, source.title);
      assert.ok(source.quote.includes(SYNTHETIC_MARKER));
    }
    for (const note of fixture.notes) assert.ok(note.content.includes(SYNTHETIC_MARKER), `${fixture.id} ${note.noteId}`);
  }
});

test('gold labels match the category and only answerable fixtures carry facts, labels and checks', () => {
  for (const fixture of set.fixtures) {
    const gold = fixture.gold;
    if (fixture.category === 'answerable') {
      assert.equal(gold.answerable, true, fixture.id);
      assert.equal(gold.conflict, false, fixture.id);
      assert.ok(gold.expectedFacts.length >= 2);
      assert.ok(gold.citationLabels.length >= 1);
      assert.ok(gold.semanticChecks.length >= 2);
      for (const label of gold.citationLabels) {
        const index = Number(label.slice(1));
        assert.ok(index >= 1 && index <= fixture.evidence.sources.length, `${fixture.id} cites ${label}`);
      }
    } else if (fixture.category === 'insufficient') {
      assert.equal(gold.answerable, false, fixture.id);
      assert.equal(gold.conflict, false, fixture.id);
    } else if (fixture.category === 'conflict') {
      assert.equal(gold.answerable, null, fixture.id);
      assert.equal(gold.conflict, true, fixture.id);
    } else {
      assert.equal(gold.answerable, null, fixture.id);
      assert.equal(gold.conflict, null, fixture.id);
    }
    if (fixture.category !== 'answerable') {
      assert.deepEqual(gold.expectedFacts, [], fixture.id);
      assert.deepEqual(gold.citationLabels, [], fixture.id);
      assert.ok(gold.semanticChecks.length >= 1, fixture.id);
    }
  }
});

test('traits cover negation, entity mixups, multi-part, conflict, injection and missing fields in both languages and splits', () => {
  for (const fixture of set.fixtures) {
    assert.ok(fixture.traits.length >= 1 && fixture.traits.length <= 3, fixture.id);
    if (fixture.traits.includes('unresolved_conflict')) assert.equal(fixture.category, 'conflict', fixture.id);
    if (fixture.traits.includes('resolved_conflict')) assert.equal(fixture.category, 'answerable', fixture.id);
    if (fixture.traits.includes('prompt_like_instruction')) {
      assert.ok(fixture.notes.some((note) => EMBEDDED_INSTRUCTION.test(note.content)), fixture.id);
      assert.ok(fixture.gold.semanticChecks.some((check) => /instruction|hướng dẫn/i.test(check)), fixture.id);
    }
  }
  for (const trait of TRAITS) {
    for (const split of SPLITS) for (const language of LANGUAGES) {
      const hits = set.fixtures.filter((fixture) => fixture.traits.includes(trait) && fixture.split === split && fixture.language === language).length;
      assert.ok(hits >= 1, `${trait} missing from ${split}/${language}`);
    }
  }
});

test('the fixture file carries no real-user-data shapes and never claims human review', () => {
  const serialized = JSON.stringify(rawFile);
  assert.equal(/"?human_?[Rr]eviewed"?\s*:\s*true/.test(serialized), false, 'human-review claim');
  assert.equal(/[\w.+-]+@[\w-]+\.[a-z]{2,}/i.test(serialized), false, 'email-shaped value');
  assert.equal(/https?:\/\//i.test(serialized), false, 'url-shaped value');
  assert.equal(/\b(?:\+?84|0)(?:[\s.-]?\d){9,10}\b/.test(serialized), false, 'phone-shaped value');
  for (const fixture of set.fixtures) {
    assert.equal(fixture.provenance, LABEL_PROVENANCE, fixture.id);
    assert.equal(Object.hasOwn(fixture, 'humanReviewed'), false, fixture.id);
    assert.equal(Object.hasOwn(fixture, 'human_reviewed'), false, fixture.id);
  }
});

test('tampered fixture files are refused instead of loaded', () => {
  const clone = (): Record<string, unknown> => JSON.parse(JSON.stringify(rawFile)) as Record<string, unknown>;
  assert.equal(codeOf(() => loadFixtureFile(clone())), 'no-throw');
  const humanClaim = clone();
  humanClaim['humanReviewed'] = true;
  assert.equal(codeOf(() => loadFixtureFile(humanClaim)), 'INVALID_FIXTURES');
  const shifted = clone();
  (((shifted['fixtures'] as Record<string, unknown>[])[0]!['notes'] as Record<string, unknown>[])[0]!)['content'] = 'plain text without the marker';
  assert.equal(codeOf(() => loadFixtureFile(shifted)), 'INVALID_FIXTURES');
  const badOffset = clone();
  const sources = ((badOffset['fixtures'] as Record<string, unknown>[])[0]!['evidence'] as Record<string, unknown>)['sources'] as Record<string, unknown>[];
  sources[0]!['endOffset'] = (sources[0]!['endOffset'] as number) - 1;
  assert.equal(codeOf(() => loadFixtureFile(badOffset)), 'INVALID_FIXTURES');
  const short = clone();
  (short['fixtures'] as unknown[]).pop();
  assert.equal(codeOf(() => loadFixtureFile(short)), 'DISTRIBUTION_INVALID');
  const rebalanced = clone();
  const stolen = (rebalanced['fixtures'] as Record<string, unknown>[])[0]!;
  stolen['id'] = 'fx-dev-vi-ins-99';
  stolen['category'] = 'insufficient';
  stolen['gold'] = { answerable: false, conflict: false, expectedFacts: [], citationLabels: [], semanticChecks: ['must not invent an amount'] };
  stolen['traits'] = ['missing_field'];
  assert.equal(codeOf(() => loadFixtureFile(rebalanced)), 'DISTRIBUTION_INVALID');
  const leaked = clone();
  const developmentNote = ((leaked['fixtures'] as Record<string, unknown>[])[0]!['notes'] as Record<string, unknown>[])[0]!;
  const confirmationFixture = (leaked['fixtures'] as Record<string, unknown>[]).find((fixture) => fixture['split'] === 'confirmation')!;
  (confirmationFixture['notes'] as Record<string, unknown>[]).push({ noteId: 'n-leak-01', revision: 1, title: 'Leaked note', content: developmentNote['content'] });
  assert.equal(codeOf(() => loadFixtureFile(leaked)), 'GROUP_LEAK');
});

test('a fixture set with edited hashes is refused by the scoring pre-check', () => {
  const tampered = { ...set, confirmationHash: `sha256:${'0'.repeat(64)}` };
  assert.equal(codeOf(() => validateFixtureSet(tampered)), 'INVALID_FIXTURES');
  assert.equal(codeOf(() => validateFixtureSet(set)), 'no-throw');
  assert.equal(codeOf(() => validateFixture(rawFixtures[0]!, 0)), 'no-throw');
});

 test('negative factual answer is answerable: Hanh gold keeps source truth and polarity',()=>{
 const h=set.fixtures.find(f=>f.id==='fx-dev-vi-ans-05')!;
 assert.ok(h);assert.equal(h.category,'answerable');assert.equal(h.gold.answerable,true);
 assert.equal(h.gold.conflict,false);assert.match(h.evidence.text,/chưa bao giờ tham gia/);
 assert.ok(h.gold.expectedFacts.some(f=>f.includes('chưa hoàn thành')));
 assert.deepEqual(h.gold.citationLabels,['S1']);assert.equal(set.confirmationPurpose,'heldout');
 assert.equal(set.fixtures.filter(f=>f.split==='development'&&f.category==='answerable').length,9);
 assert.equal(set.fixtures.some(f=>f.id==='fx-dev-vi-ins-03'),false);
 });
