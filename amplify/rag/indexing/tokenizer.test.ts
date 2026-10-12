import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {loadTokenCounter} from './tokenizer';
const directory = process.env.RAG_TOKENIZER_DIR;
test('missing/tampered tokenizer fails closed',()=>{
  const dir=mkdtempSync(join(tmpdir(),'rag-tokenizer-test-'));
  assert.throws(()=>loadTokenCounter(dir),/TOKENIZER_UNAVAILABLE/);
  writeFileSync(join(dir,'tokenizer.json'),'{}');
  assert.throws(()=>loadTokenCounter(dir),/TOKENIZER_UNAVAILABLE/);
});
test('pinned tokenizer matches seven Rust goldens plus documented framing margin', {skip:!directory},()=>{
  const counter=loadTokenCounter(directory!);
  const goldens=JSON.parse(readFileSync(new URL('../../../test/fixtures/rag/tokenizer_goldens.json',import.meta.url),'utf8'));
  for(const g of goldens) assert.equal(counter(g.text),g.ids.length+8);
});
