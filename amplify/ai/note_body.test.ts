import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { noteBodyText } from './note_body';

const cases = JSON.parse(readFileSync('test/fixtures/note_body_cases.json', 'utf8')) as
  Array<{name: string; content: string; text: string}>;
for (const item of cases) {
  test(`client/server body codec parity: ${item.name}`, () => {
    assert.equal(noteBodyText(item.content), item.text);
  });
}
