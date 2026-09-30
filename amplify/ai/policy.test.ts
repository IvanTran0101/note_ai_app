import golden from '../../test/fixtures/summary_policy_golden.json';
import policy from '../../assets/summary_policy.json';
import {
  buildSummaryMessages, estimateSummaryInputTokens, maxOutputTokensForStage,
  MAX_INPUT_TOKENS_PER_CALL, ESTIMATE_FRAMING_HEADROOM_TOKENS, MAX_BODY_BYTES_UTF8,
  CONSENT_VERSION, type SummaryStage
} from './summary_contract';

const equal = (actual: unknown, expected: unknown, label: string): void => {
  if (actual !== expected) throw new Error(`Summary policy mismatch: ${label}`);
};

equal(policy.schemaVersion, 1, 'version');
equal(MAX_INPUT_TOKENS_PER_CALL, 16000, 'frozen input cap');
equal(ESTIMATE_FRAMING_HEADROOM_TOKENS, 256, 'framing');
equal(MAX_BODY_BYTES_UTF8, 262144, 'body cap');
equal(CONSENT_VERSION, 'summary-cloud-v1', 'consent');
equal(policy.maxChunks, 4, 'chunks');
equal(policy.maxGenerationCalls, 5, 'calls');
for (const stage of ['direct', 'section', 'merge'] as const) {
  equal(maxOutputTokensForStage(stage), stage === 'section' ? 128 : 256, stage);
}
for (const sample of golden.cases) {
  const inputs = sample.repeatInput
    ? [sample.repeatInput.unit.repeat(sample.repeatInput.count)]
    : sample.inputs;
  if (!inputs) throw new Error(`Missing golden input: ${sample.id}`);
  const request = { stage: sample.stage as SummaryStage, inputs };
  if (sample.expectedMessagesJson !== undefined) {
    equal(JSON.stringify(buildSummaryMessages(request)), sample.expectedMessagesJson, sample.id + ': messages');
  }
  const estimate = estimateSummaryInputTokens(request);
  equal(estimate, sample.expectedEstimate, sample.id + ': estimate');
  equal(estimate <= MAX_INPUT_TOKENS_PER_CALL, sample.expectedFits, sample.id + ': fit');
}
console.log(`${golden.cases.length} pre-extraction backend policy goldens passed; no provider call.`);
