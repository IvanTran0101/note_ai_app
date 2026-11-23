import { test } from 'node:test';
import assert from 'node:assert/strict';
import wire from '../../test/fixtures/rag/wire_cases.json';
import { parseRequest, validateNoul } from './contract';

test('Phase 1 wire request fixtures remain the TypeScript implementation contract', () => {
  for (const fixture of wire.requests) {
    const run = () => parseRequest(JSON.stringify(fixture.payload));
    if (fixture.valid) assert.doesNotThrow(run, fixture.id);
    else assert.throws(run, fixture.id);
  }
});
test('Phase 1 typed Noul fixtures remain the TypeScript implementation contract', () => {
  for (const fixture of wire.nouls) {
    const run = () => validateNoul(fixture.payload, 'jev-fixture');
    if (fixture.valid) assert.doesNotThrow(run, fixture.id);
    else assert.throws(run, fixture.id);
  }
});
