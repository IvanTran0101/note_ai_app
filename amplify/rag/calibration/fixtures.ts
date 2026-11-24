/**
 * Validated fixture loader.
 *
 * The fixture file is contract data, so it is validated as untrusted input: exact key sets,
 * category/gold consistency, UTF-16 end-exclusive source spans that really slice the referenced
 * synthetic note, an explicitly synthetic marker in every note and quote, no real-user-data
 * shapes, the frozen split/language distribution with the approved Hanh gold correction, and no group or note content crossing splits.
 * A file that claims human review or drops the disclaimer is refused outright.
 */
import { readFileSync } from 'node:fs';
import { countUnicodeCharacters, isSafeInteger, isWellFormed } from '../chunking';
import { isValidIdentifier } from '../contract';
import { fail } from './errors';
import { contentHash } from './hash';
import {
  CATEGORIES,
  FIXTURE_VERSION,
  LABEL_PROVENANCE,
  LANGUAGES,
  SPLITS,
  TRAITS,
  type Category,
  type Fixture,
  type FixtureGold,
  type FixtureSet,
  type Language,
  type Split,
  type Trait,
} from './types';

const FILE_KEYS = ['fixtureVersion', 'labelProvenance', 'humanReviewed', 'confirmationPurpose', 'disclaimer', 'fixtures'] as const;
const SET_KEYS = [...FILE_KEYS, 'fixtureHash', 'developmentHash', 'confirmationHash'] as const;
const FIXTURE_KEYS = ['id', 'groupId', 'language', 'split', 'category', 'question', 'notes', 'evidence', 'gold', 'traits', 'provenance'] as const;
const NOTE_KEYS = ['noteId', 'revision', 'title', 'content'] as const;
const SOURCE_KEYS = ['sourceId', 'noteId', 'revision', 'title', 'startOffset', 'endOffset', 'quote'] as const;
const GOLD_KEYS = ['answerable', 'conflict', 'expectedFacts', 'citationLabels', 'semanticChecks'] as const;

export const SYNTHETIC_MARKER = 'SYNTHETIC';
export const TOTAL_FIXTURES = 64;
const CATEGORY_PREFIX: Readonly<Record<Category, string>> = {
  answerable: 'ans', insufficient: 'ins', conflict: 'con', ambiguous: 'amb',
};
const GOLD_BY_CATEGORY: Readonly<Record<Category, readonly [boolean | null, boolean | null]>> = {
  answerable: [true, false], insufficient: [false, false], conflict: [null, true], ambiguous: [null, null],
};
/** Embedded adversarial instruction: recognised so a prompt-injection fixture can be asserted. */
export const EMBEDDED_INSTRUCTION = /ignore [^.]{0,60}(instruction|note|context)|disregard [^.]{0,60}instruction|bỏ qua [^.]{0,60}hướng dẫn|quên [^.]{0,60}hướng dẫn|system prompt|hidden instruction|assistant instruction|hướng dẫn nhúng/i;
export const INSTRUCTION_CHECK = /instruction|hướng dẫn/i;
const EMAIL = /[\w.+-]+@[\w-]+\.[a-z]{2,}/i;
const URL = /https?:\/\//i;
const PHONE = /\b(?:\+?84|0)(?:[\s.-]?\d){9,10}\b|\b\d{11,}\b/;
const VI_CHAR = /[ăâđêôơưàáảãạằắẳẵặầấẩẫậèéẻẽẹềếểễệìíỉĩịòóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ]/i;
const ID_PATTERN = /^fx-(dev|conf)-(vi|en)-(ans|ins|con|amb)-(\d{2})$/;
const GROUP_PATTERN = /^g-(dev|conf)-(vi|en)-[a-z0-9-]+$/;
const LABEL_PATTERN = /^S([1-9]\d*)$/;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === 'object' && value !== null && !Array.isArray(value);

const hasExactKeys = (value: Record<string, unknown>, keys: readonly string[]): boolean =>
  Object.keys(value).length === keys.length && keys.every((key) => Object.hasOwn(value, key));

const isText = (value: unknown): value is string =>
  typeof value === 'string' && value.trim().length > 0 && isWellFormed(value);

const isTextArray = (value: unknown): value is string[] =>
  Array.isArray(value) && value.every(isText);

/** Real-user-data shapes are refused rather than reviewed: a synthetic fixture can never need them. */
function assertNoRealUserData(where: string, values: readonly string[]): void {
  for (const value of values) {
    if (EMAIL.test(value) || URL.test(value) || PHONE.test(value)) {
      fail('INVALID_FIXTURES', `${where} looks like real-user data (email/url/phone)`);
    }
  }
}

function assertLanguage(where: string, language: Language, question: string): void {
  if (language === 'vi') {
    if (!VI_CHAR.test(question)) fail('INVALID_FIXTURES', `${where}.question has no Vietnamese diacritics`);
  } else if (/[^\u0000-\u007f]/.test(question)) {
    fail('INVALID_FIXTURES', `${where}.question is not ASCII for language "en"`);
  }
}

function validateNotes(where: string, value: unknown): readonly { noteId: string; revision: number; title: string; content: string }[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 3) fail('INVALID_FIXTURES', `${where}.notes must hold 1-3 notes`);
  const seen = new Set<string>();
  return value.map((raw, index) => {
    const at = `${where}.notes[${index}]`;
    if (!isRecord(raw) || !hasExactKeys(raw, NOTE_KEYS)) fail('INVALID_FIXTURES', `${at} must be exactly {${NOTE_KEYS.join(', ')}}`);
    if (!isValidIdentifier(raw['noteId']) || seen.has(raw['noteId'] as string)) fail('INVALID_FIXTURES', `${at}.noteId missing or duplicated`);
    seen.add(raw['noteId'] as string);
    if (!isSafeInteger(raw['revision']) || (raw['revision'] as number) < 1) fail('INVALID_FIXTURES', `${at}.revision must be a positive integer`);
    if (!isText(raw['title'])) fail('INVALID_FIXTURES', `${at}.title must be non-blank text`);
    if (!isText(raw['content']) || !(raw['content'] as string).includes(SYNTHETIC_MARKER)) {
      fail('INVALID_FIXTURES', `${at}.content must be non-blank and explicitly synthetic`);
    }
    return {
      noteId: raw['noteId'] as string, revision: raw['revision'] as number,
      title: raw['title'] as string, content: raw['content'] as string,
    };
  });
}

function validateSources(
  where: string,
  value: unknown,
  notes: readonly { noteId: string; revision: number; title: string; content: string }[],
): readonly Fixture['evidence']['sources'][number][] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 3) fail('INVALID_FIXTURES', `${where}.sources must hold 1-3 sources`);
  const labels = new Set<string>();
  return value.map((raw, index) => {
    const at = `${where}.sources[${index}]`;
    if (!isRecord(raw) || !hasExactKeys(raw, SOURCE_KEYS)) fail('INVALID_FIXTURES', `${at} must be exactly {${SOURCE_KEYS.join(', ')}}`);
    if (raw['sourceId'] !== `S${index + 1}` || labels.has(raw['sourceId'] as string)) fail('INVALID_FIXTURES', `${at}.sourceId must match its rendered label`);
    labels.add(raw['sourceId'] as string);
    const note = notes.find((candidate) => candidate.noteId === raw['noteId']);
    if (note === undefined) fail('INVALID_FIXTURES', `${at}.noteId does not reference a note in this fixture`);
    if (raw['revision'] !== note.revision || raw['title'] !== note.title) fail('INVALID_FIXTURES', `${at} revision/title do not match the referenced note`);
    const start = raw['startOffset'];
    const end = raw['endOffset'];
    const quote = raw['quote'];
    if (!isSafeInteger(start) || !isSafeInteger(end) || start < 0 || end <= start) {
      fail('INVALID_FIXTURES', `${at} offsets must be UTF-16 start < end with end exclusive`);
    }
    if (!isText(quote) || quote.length !== end - start || note.content.slice(start, end) !== quote) {
      fail('INVALID_FIXTURES', `${at}.quote must be the exact UTF-16 end-exclusive slice of the referenced note`);
    }
    if (!quote.includes(SYNTHETIC_MARKER)) fail('INVALID_FIXTURES', `${at}.quote must be explicitly synthetic`);
    return {
      sourceId: raw['sourceId'] as string, noteId: note.noteId, revision: note.revision, title: note.title,
      startOffset: start, endOffset: end, quote,
    };
  });
}

/** The evidence text is contract: labels S1..Sn in source order, then the exact quoted slice. */
export const evidenceTextFor = (sources: readonly { title: string; quote: string }[]): string =>
  sources.map((source, index) => `[S${index + 1}] ${source.title}\n${source.quote}`).join('\n');

function validateGold(where: string, value: unknown, category: Category, sourceCount: number): FixtureGold {
  if (!isRecord(value) || !hasExactKeys(value, GOLD_KEYS)) fail('INVALID_FIXTURES', `${where}.gold must be exactly {${GOLD_KEYS.join(', ')}}`);
  const expected = GOLD_BY_CATEGORY[category];
  if (value['answerable'] !== expected[0] || value['conflict'] !== expected[1]) {
    fail('INVALID_FIXTURES', `${where}.gold contradicts category "${category}" (answerable=${String(expected[0])}, conflict=${String(expected[1])})`);
  }
  for (const key of ['expectedFacts', 'citationLabels', 'semanticChecks'] as const) {
    if (!isTextArray(value[key])) fail('INVALID_FIXTURES', `${where}.gold.${key} must be a string array`);
  }
  const facts = value['expectedFacts'] as string[];
  const citations = value['citationLabels'] as string[];
  const checks = value['semanticChecks'] as string[];
  if (category === 'answerable') {
    if (facts.length < 2) fail('INVALID_FIXTURES', `${where}.gold.expectedFacts needs >=2 answerable facts`);
    if (citations.length < 1) fail('INVALID_FIXTURES', `${where}.gold.citationLabels needs the labels the answer must cite`);
    if (checks.length < 2) fail('INVALID_FIXTURES', `${where}.gold.semanticChecks needs >=2 checks`);
  } else {
    if (facts.length !== 0) fail('INVALID_FIXTURES', `${where}.gold.expectedFacts must stay empty when the fixture is not answerable`);
    if (citations.length !== 0) fail('INVALID_FIXTURES', `${where}.gold.citationLabels must stay empty when the fixture is not answerable`);
    if (checks.length < 1) fail('INVALID_FIXTURES', `${where}.gold.semanticChecks must say what must not be invented`);
  }
  for (const label of citations) {
    const match = LABEL_PATTERN.exec(label);
    if (match === null || Number(match[1]) > sourceCount) fail('INVALID_FIXTURES', `${where}.gold.citationLabels has "${label}" outside S1..S${sourceCount}`);
  }
  return { answerable: expected[0], conflict: expected[1], expectedFacts: facts, citationLabels: citations, semanticChecks: checks };
}

function validateTraits(where: string, value: unknown, category: Category, notes: readonly { content: string }[], checks: readonly string[]): readonly Trait[] {
  if (!Array.isArray(value) || value.length < 1 || value.length > 3) fail('INVALID_FIXTURES', `${where}.traits must hold 1-3 traits`);
  const traits = value as Trait[];
  if (new Set(traits).size !== traits.length) fail('INVALID_FIXTURES', `${where}.traits contains duplicates`);
  for (const trait of traits) {
    if (!(TRAITS as readonly string[]).includes(trait)) fail('INVALID_FIXTURES', `${where}.traits has unknown trait "${String(trait)}"`);
    if (trait === 'unresolved_conflict' && category !== 'conflict') fail('INVALID_FIXTURES', `${where} trait unresolved_conflict needs category "conflict"`);
    if (trait === 'resolved_conflict' && category !== 'answerable') fail('INVALID_FIXTURES', `${where} trait resolved_conflict needs category "answerable"`);
  }
  if (traits.includes('prompt_like_instruction')) {
    if (!notes.some((note) => EMBEDDED_INSTRUCTION.test(note.content))) fail('INVALID_FIXTURES', `${where} trait prompt_like_instruction needs an embedded instruction in a note`);
    if (!checks.some((check) => INSTRUCTION_CHECK.test(check))) fail('INVALID_FIXTURES', `${where} trait prompt_like_instruction needs a semantic check about not obeying instructions`);
  }
  return Object.freeze([...traits]);
}

export function validateFixture(value: unknown, index: number): Fixture {
  const where = `fixtures[${index}]`;
  if (!isRecord(value) || !hasExactKeys(value, FIXTURE_KEYS)) fail('INVALID_FIXTURES', `${where} must be exactly {${FIXTURE_KEYS.join(', ')}}`);
  const id = value['id'];
  const match = typeof id === 'string' ? ID_PATTERN.exec(id) : null;
  if (match === null) fail('INVALID_FIXTURES', `${where}.id must match fx-<dev|conf>-<vi|en>-<ans|ins|con|amb>-NN`);
  const fixtureId = id as string;
  const split: Split = match[1] === 'dev' ? 'development' : 'confirmation';
  const language: Language = match[2] as Language;
  const category = (Object.keys(CATEGORY_PREFIX) as Category[]).find((key) => CATEGORY_PREFIX[key] === match[3]) as Category;
  if (value['split'] !== split || value['language'] !== language || value['category'] !== category) {
    fail('INVALID_FIXTURES', `${where}.id encodes ${split}/${language}/${category} but the fields disagree`);
  }
  if (!LANGUAGES.includes(language) || !SPLITS.includes(split) || !CATEGORIES.includes(category)) fail('INVALID_FIXTURES', `${where} has an unknown split/language/category`);
  const groupId = value['groupId'];
  const groupMatch = typeof groupId === 'string' ? GROUP_PATTERN.exec(groupId) : null;
  if (groupMatch === null || groupMatch[1] !== match[1] || groupMatch[2] !== match[2]) {
    fail('INVALID_FIXTURES', `${where}.groupId must be g-<dev|conf>-<vi|en>-<topic> and share the fixture's split and language`);
  }
  const fixtureGroupId = groupId as string;
  const question = value['question'];
  if (!isText(question) || countUnicodeCharacters(question as string) > 2048) fail('INVALID_FIXTURES', `${where}.question must be non-blank, well-formed and <=2048 code points`);
  if (value['provenance'] !== LABEL_PROVENANCE) fail('INVALID_FIXTURES', `${where}.provenance must be "${LABEL_PROVENANCE}"`);
  assertLanguage(where, language, question as string);
  const notes = validateNotes(where, value['notes']);
  const evidenceValue = value['evidence'];
  if (!isRecord(evidenceValue) || !hasExactKeys(evidenceValue, ['sources', 'text'])) fail('INVALID_FIXTURES', `${where}.evidence must be exactly {sources, text}`);
  const sources = validateSources(`${where}.evidence`, evidenceValue['sources'], notes);
  const text = evidenceValue['text'];
  if (!isText(text) || text !== evidenceTextFor(sources)) fail('INVALID_FIXTURES', `${where}.evidence.text must be the exact [S1] title/quote reconstruction in source order`);
  const gold = validateGold(where, value['gold'], category, sources.length);
  const traits = validateTraits(where, value['traits'], category, notes, gold.semanticChecks);
  assertNoRealUserData(where, [question as string, text, ...notes.flatMap((note) => [note.title, note.content]), ...sources.map((source) => source.quote), ...gold.expectedFacts, ...gold.semanticChecks]);
  return Object.freeze({ id: fixtureId, groupId: fixtureGroupId, language, split, category, question: question as string, notes: Object.freeze(notes), evidence: Object.freeze({ sources: Object.freeze(sources), text }), gold, traits, provenance: LABEL_PROVENANCE });
}

export type DistributionCounts = Readonly<{
  total: number;
  byCategory: Readonly<Record<Category, number>>;
  byLanguage: Readonly<Record<Language, number>>;
  bySplit: Readonly<Record<Split, number>>;
  byCategoryLanguage: Readonly<Record<string, number>>;
  bySplitLanguage: Readonly<Record<string, number>>;
  traits: Readonly<Record<Trait, number>>;
}>;

/** Preserve split/language coverage; corrected gold takes priority over the old class quota. */
export function validateDistribution(fixtures: readonly Fixture[]): DistributionCounts {
  if (fixtures.length !== TOTAL_FIXTURES) fail('DISTRIBUTION_INVALID', `expected ${TOTAL_FIXTURES} fixtures, found ${fixtures.length}`);
  const byCategory = Object.fromEntries(CATEGORIES.map((key) => [key, 0])) as Record<Category, number>;
  const byLanguage = Object.fromEntries(LANGUAGES.map((key) => [key, 0])) as Record<Language, number>;
  const bySplit = Object.fromEntries(SPLITS.map((key) => [key, 0])) as Record<Split, number>;
  const byCategoryLanguage: Record<string, number> = {};
  const bySplitLanguage: Record<string, number> = {};
  const traits = Object.fromEntries(TRAITS.map((key) => [key, 0])) as Record<Trait, number>;
  for (const fixture of fixtures) {
    byCategory[fixture.category] += 1;
    byLanguage[fixture.language] += 1;
    bySplit[fixture.split] += 1;
    byCategoryLanguage[`${fixture.category}/${fixture.language}`] = (byCategoryLanguage[`${fixture.category}/${fixture.language}`] ?? 0) + 1;
    bySplitLanguage[`${fixture.split}/${fixture.language}`] = (bySplitLanguage[`${fixture.split}/${fixture.language}`] ?? 0) + 1;
    for (const trait of fixture.traits) traits[trait] += 1;
  }
  for (const category of CATEGORIES) {
    const correction = category === 'answerable' ? 1 : category === 'insufficient' ? -1 : 0;
    if (byCategory[category] !== 16 + correction) fail('DISTRIBUTION_INVALID', `category "${category}" must hold ${16 + correction} fixtures, found ${byCategory[category]}`);
    for (const language of LANGUAGES) {
      const key = `${category}/${language}`;
      const expected = 8 + (language === 'vi' ? correction : 0);
      if (byCategoryLanguage[key] !== expected) fail('DISTRIBUTION_INVALID', `${key} must hold ${expected} fixtures, found ${byCategoryLanguage[key] ?? 0}`);
    }
  }
  for (const language of LANGUAGES) if (byLanguage[language] !== 32) fail('DISTRIBUTION_INVALID', `language "${language}" must hold 32 fixtures, found ${byLanguage[language]}`);
  for (const split of SPLITS) {
    if (bySplit[split] !== 32) fail('DISTRIBUTION_INVALID', `split "${split}" must hold 32 fixtures, found ${bySplit[split]}`);
    for (const language of LANGUAGES) {
      const key = `${split}/${language}`;
      if (bySplitLanguage[key] !== 16) fail('DISTRIBUTION_INVALID', `${key} must hold 16 fixtures, found ${bySplitLanguage[key] ?? 0}`);
    }
  }
  for (const trait of TRAITS) {
    if (traits[trait] < 8) fail('DISTRIBUTION_INVALID', `trait "${trait}" must appear on >=8 fixtures, found ${traits[trait]}`);
    for (const split of SPLITS) {
      for (const language of LANGUAGES) {
        const seen = fixtures.filter((fixture) => fixture.split === split && fixture.language === language && fixture.traits.includes(trait)).length;
        if (seen < 1) fail('DISTRIBUTION_INVALID', `trait "${trait}" is missing from ${split}/${language}`);
      }
    }
  }
  return Object.freeze({ total: fixtures.length, byCategory: Object.freeze(byCategory), byLanguage: Object.freeze(byLanguage), bySplit: Object.freeze(bySplit), byCategoryLanguage: Object.freeze(byCategoryLanguage), bySplitLanguage: Object.freeze(bySplitLanguage), traits: Object.freeze(traits) });
}

/** A groupId is one variant family: it may never span a split, a language or two topics. */
export function assertNoGroupLeak(fixtures: readonly Fixture[]): void {
  const groups = new Map<string, { split: Split; language: Language }>();
  const contents = new Map<string, Split>();
  for (const fixture of fixtures) {
    const known = groups.get(fixture.groupId);
    if (known !== undefined && (known.split !== fixture.split || known.language !== fixture.language)) {
      fail('GROUP_LEAK', `groupId "${fixture.groupId}" crosses ${known.split}/${known.language} and ${fixture.split}/${fixture.language}`);
    }
    groups.set(fixture.groupId, { split: fixture.split, language: fixture.language });
    for (const note of fixture.notes) {
      const previous = contents.get(note.content);
      if (previous !== undefined && previous !== fixture.split) fail('GROUP_LEAK', `note content is reused across ${previous} and ${fixture.split} (${fixture.id})`);
      contents.set(note.content, fixture.split);
    }
  }
  if (new Set(fixtures.map((fixture) => fixture.id)).size !== fixtures.length) fail('INVALID_FIXTURES', 'fixture ids must be unique');
}

export const hashFixtures = (fixtures: readonly Fixture[]): string => contentHash(fixtures);

function validateSetContents(raw: Record<string, unknown>): FixtureSet {
  if (raw['fixtureVersion'] !== FIXTURE_VERSION) fail('INVALID_FIXTURES', `fixtureVersion must be "${FIXTURE_VERSION}"`);
  if (raw['labelProvenance'] !== LABEL_PROVENANCE) fail('INVALID_FIXTURES', `labelProvenance must be "${LABEL_PROVENANCE}"`);
  if (raw['humanReviewed'] !== false) fail('INVALID_FIXTURES', 'humanReviewed must be false: these labels are synthetic and not human-reviewed');
  const confirmationPurpose = raw['confirmationPurpose'];
  if (confirmationPurpose !== 'heldout' && confirmationPurpose !== 'regression-only') fail('INVALID_FIXTURES', 'confirmationPurpose must say whether the set is still held-out');
  const disclaimer = raw['disclaimer'];
  if (typeof disclaimer !== 'string' || !disclaimer.includes('not human-reviewed')) fail('INVALID_FIXTURES', 'disclaimer must state that the labels are not human-reviewed');
  if (!Array.isArray(raw['fixtures'])) fail('INVALID_FIXTURES', 'fixtures must be an array');
  const fixtures = (raw['fixtures'] as unknown[]).map(validateFixture);
  validateDistribution(fixtures);
  assertNoGroupLeak(fixtures);
  return Object.freeze({
    fixtureVersion: FIXTURE_VERSION, labelProvenance: LABEL_PROVENANCE, humanReviewed: false, confirmationPurpose, disclaimer,
    fixtures: Object.freeze(fixtures),
    fixtureHash: hashFixtures(fixtures),
    developmentHash: hashFixtures(fixtures.filter((fixture) => fixture.split === 'development')),
    confirmationHash: hashFixtures(fixtures.filter((fixture) => fixture.split === 'confirmation')),
  });
}

/** Raw fixture-file JSON to a validated set; hashes are recomputed, never trusted from the file. */
export function loadFixtureFile(raw: unknown): FixtureSet {
  if (!isRecord(raw) || !hasExactKeys(raw, FILE_KEYS)) fail('INVALID_FIXTURES', `fixture file must be exactly {${FILE_KEYS.join(', ')}}`);
  return validateSetContents(raw);
}

/** Re-validates an already-loaded set (and its hashes) before any scoring trusts it. */
export function validateFixtureSet(raw: unknown): FixtureSet {
  if (!isRecord(raw)) fail('INVALID_FIXTURES', 'fixture set must be an object');
  if (!hasExactKeys(raw, SET_KEYS)) fail('INVALID_FIXTURES', `fixture set must be exactly {${SET_KEYS.join(', ')}}`);
  const set = validateSetContents(raw);
  if (raw['fixtureHash'] !== set.fixtureHash || raw['developmentHash'] !== set.developmentHash || raw['confirmationHash'] !== set.confirmationHash) {
    fail('INVALID_FIXTURES', 'fixture set hashes do not match the fixture content: the file was edited after freezing');
  }
  return set;
}

export function readFixtureFile(path: string): FixtureSet {
  return loadFixtureFile(JSON.parse(readFileSync(path, 'utf8')) as unknown);
}

export const fixturesForSplit = (set: FixtureSet, split: Split): readonly Fixture[] =>
  set.fixtures.filter((fixture) => fixture.split === split);
