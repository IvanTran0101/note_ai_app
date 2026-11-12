import {test} from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync, mkdtempSync, writeFileSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {
  EMBEDDINGGEMMA_FRAMING_MARGIN_TOKENS,
  EMBEDDINGGEMMA_TOKENIZER_FILES,
  EMBEDDINGGEMMA_TOKENIZER_REVISION,
  loadEmbeddingGemmaTokenCounter,
  loadTokenCounter,
} from './tokenizer';
const directory = process.env.RAG_TOKENIZER_DIR;
const embeddingGemmaDirectory = process.env.RAG_EMBEDDINGGEMMA_TOKENIZER_DIR;

test('missing/tampered tokenizer fails closed',()=>{
  const dir=mkdtempSync(join(tmpdir(),'rag-tokenizer-test-'));
  assert.throws(()=>loadTokenCounter(dir),/TOKENIZER_UNAVAILABLE/);
  writeFileSync(join(dir,'tokenizer.json'),'{}');
  assert.throws(()=>loadTokenCounter(dir),/TOKENIZER_UNAVAILABLE/);
});
test('missing/tampered EmbeddingGemma tokenizer fails closed',()=>{
  const dir=mkdtempSync(join(tmpdir(),'rag-embeddinggemma-tokenizer-test-'));
  assert.throws(()=>loadEmbeddingGemmaTokenCounter(dir),/TOKENIZER_UNAVAILABLE/);
  writeFileSync(join(dir,'tokenizer.json'),'{}');
  assert.throws(()=>loadEmbeddingGemmaTokenCounter(dir),/TOKENIZER_UNAVAILABLE/);
});
test('pinned tokenizer matches seven Rust goldens plus documented framing margin', {skip:!directory},()=>{
  const counter=loadTokenCounter(directory!);
  const goldens=JSON.parse(readFileSync(new URL('../../../test/fixtures/rag/tokenizer_goldens.json',import.meta.url),'utf8'));
  for(const g of goldens) assert.equal(counter(g.text),g.ids.length+8);
});
test('EmbeddingGemma manifest pins the official revision and file hashes',()=>{
  assert.equal(EMBEDDINGGEMMA_TOKENIZER_REVISION,'914f7f89142e33e77833254d9c9b90c3cef7303b');
  assert.equal(EMBEDDINGGEMMA_FRAMING_MARGIN_TOKENS,0);
  assert.deepEqual(EMBEDDINGGEMMA_TOKENIZER_FILES,{
    'tokenizer.json':'4d777ef5bdc1aa36227abdfb77c3e49e7b9c892d16e1b6bda41c393504828be4',
    'tokenizer_config.json':'17bd5d6e9364ca49a534e1502076593317c298d4a663623091ed45388f004874',
  });
});
// Counts verified against localhost llama-server /tokenize with add_special=true (build b11706).
test('pinned EmbeddingGemma tokenizer matches llama-server goldens',{skip:!embeddingGemmaDirectory},()=>{
  const counter=loadEmbeddingGemmaTokenCounter(embeddingGemmaDirectory!);
  const goldens=[
    ['Hello world',4],
    ['title: none | text: Xin chào thế giới',12],
    ['task: search result | query: what is RAG?',14],
    ['Xin chào Việt Nam! Đây là một ghi chú.',13],
    ['😀🧠 emoji test 🎉',7],
    ['  whitespace   and\nnewlines  ',9],
    ['a'.repeat(2048),258],
  ] as const;
  for(const [text,count] of goldens) assert.equal(counter(text),count,JSON.stringify(text.slice(0,40)));
});
