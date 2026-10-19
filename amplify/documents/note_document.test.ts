import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {fileURLToPath} from 'node:url';

import {parseNoteDocument, projectDocument} from './note_document';
import {InvalidDocumentError} from './document_models';

const paragraph = (id = 'p', runs: unknown[] = [{type: 'text', text: 'Việt 📝'}]) => ({id, type: 'paragraph', runs});
const document = (blocks: unknown[] = [paragraph()]) => ({version: 1, blocks});

test('shared Dart/backend golden has canonical structure, marks and exact projection', () => {
  const source = JSON.parse(readFileSync(fileURLToPath(new URL('../../test/fixtures/m09_document_v1.json', import.meta.url)), 'utf8'));
  const parsed = parseNoteDocument(source.document);
  assert.deepEqual(parsed, source.document);
  assert.equal(projectDocument(parsed), source.projection);
  assert.deepEqual(parseNoteDocument(JSON.parse(JSON.stringify(parsed))), parsed);
});

test('all13 approved choices parse, no Page or Link to page', () => {
  const blocks = [paragraph(), ...[1, 2, 3, 4].map(level => ({id: `h${level}`, type: 'heading', level, runs: []})),
    ...['bulletedList', 'numberedList', 'toggle', 'quote', 'callout'].map(type => ({id: type, type, runs: []})),
    {id: 'todo', type: 'todo', checked: false, runs: []}, {id: 'divider', type: 'divider'},
    {id: 'table', type: 'table', rows: [{id: 'r', cells: [{id: 'c', runs: []}]}]}];
  assert.equal(parseNoteDocument(document(blocks)).blocks.length, 13);
  for (const type of ['page', 'linkToPage', 'image', 'codeBlock']) {
    assert.throws(() => parseNoteDocument(document([{id: 'p', type, runs: []}])), InvalidDocumentError);
  }
});

test('run normalization merges only matching text marks and keeps math atoms', () => {
  const parsed = parseNoteDocument(document([paragraph('p', [
    {type: 'text', text: 'A', marks: {}}, {type: 'text', text: 'B'},
    {type: 'text', text: ''}, {type: 'math', expression: 'x^2'}, {type: 'text', text: 'C'},
  ])]));
  assert.deepEqual(parsed.blocks[0].runs, [
    {type: 'text', text: 'AB'}, {type: 'math', expression: 'x^2'}, {type: 'text', text: 'C'},
  ]);
});

test('hostile schemas, IDs, marks, cycles and sparse arrays refuse without private values', () => {
  const cycle: unknown[] = []; cycle.push(cycle);
  const invalid: unknown[] = [
    {version: 2, blocks: []}, {...document(), engine: {}}, document([paragraph(), paragraph()]),
    document([{id: 'p', type: 'paragraph', runs: [], level: 1}]), document([{id: 'd', type: 'divider', children: []}]),
    document([{id: 't', type: 'table', rows: []}]), document(cycle), document(new Array(3)),
  ];
  for (const marks of [{fontSize: 11}, {fontSize: 49}, {fontSize: null}, {fontSize: Number.NaN},
    {bold: 'yes'}, {color: 'default'}, {fontFamily: 'external'}, {link: 'javascript:privateSecret'}]) {
    invalid.push(document([paragraph('p', [{type: 'text', text: 'privateSecret', marks}])]));
  }
  for (const value of invalid) {
    assert.throws(() => parseNoteDocument(value), (error: unknown) =>
      error instanceof InvalidDocumentError && !error.message.includes('privateSecret'));
  }
});

test('equations are bounded, grouped and cannot carry link/code or external commands', () => {
  for (const expression of [String.raw`\input{private}`, 'x'.repeat(513), '{'.repeat(9) + '}'.repeat(9), '}']) {
    assert.throws(() => parseNoteDocument(document([paragraph('p', [{type: 'math', expression}])])), InvalidDocumentError);
  }
  for (const marks of [{inlineCode: true}, {link: 'https://example.invalid/'}]) {
    assert.throws(() => parseNoteDocument(document([paragraph('p', [{type: 'math', expression: 'x', marks}])])), InvalidDocumentError);
  }
});

test('depth, raw run count and escaped UTF8 bytes are bounded', () => {
  let nested: unknown = paragraph('leaf');
  for (let i = 0; i < 8; i++) nested = {...paragraph(`p${i}`), children: [nested]};
  assert.throws(() => parseNoteDocument(document([nested])), InvalidDocumentError);
  assert.throws(() => parseNoteDocument(document([paragraph('p', Array.from({length: 4097}, () => ({type: 'text', text: ''})))])), InvalidDocumentError);
  assert.throws(() => parseNoteDocument(document([paragraph('p', [{type: 'text', text: '\u0001'.repeat(40000)}])])), InvalidDocumentError);
});
