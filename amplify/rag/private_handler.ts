import { LIVE_QUESTION_SET } from './question_set';
import { createHash } from 'node:crypto';
import { policy, RagFailure, type Evidence, type GenerateInput, type JevInput, type RagRequest, type RagResponse, type Providers } from './types';
import { isValidIdentifier, parseRequest, decideNoul, validateGenerated } from './contract';
import type { LiveApproval } from './live_policy';
import { JEV_MODEL } from './providers/jev';
import type { ProviderUsage } from './providers/jev';
import { DEEPSEEK_SYSTEM_PROMPT } from './providers/deepseek';
import { deepSeekInputUpperBound, jevInputUpperBound } from './token_fit';
import type { createPhase4Budget } from './budget';
import { RequestDeadline } from './deadline';

export type SyntheticFixture = Readonly<{ id: string; question: string; evidence: Evidence }>;
type Deps = Readonly<{
  fixture: (id: string) => SyntheticFixture | undefined;
  providers: Providers;
  usage: ProviderUsage[];
  budget: ReturnType<typeof createPhase4Budget>;
  approval: (signal: AbortSignal) => Promise<LiveApproval>;
  countOutput: (text: string) => number;
  query: (approval: LiveApproval, actor: string, request: RagRequest, requestId: string, signal: AbortSignal) => Promise<RagResponse>;
}>;

const hash = (text: string) => createHash('sha256').update(text).digest('hex');
const configOf = (approval: LiveApproval) => ({ mode: 'live' as const, model: JEV_MODEL,
  thresholds: approval.thresholds, jevMaxTokens: 32_000, requestTimeoutMs: 26_000 });

/** No caller-authored evidence is accepted: live calibration uses bundled synthetic fixture IDs. */
export function createPrivateHandler(deps: Deps) {
  return async (event: unknown) => {
    if (!event || typeof event !== 'object' || Array.isArray(event)) return { status: 'ERROR', code: 'INVALID_INPUT' };
    const input = event as Record<string, unknown>;
    if (Object.keys(input).some(key => !['operation', 'fixtureId', 'ownerId', 'body', 'requestId'].includes(key))) {
      return { status: 'ERROR', code: 'INVALID_INPUT' };
    }
    const deadline = new RequestDeadline(26_000);
    const started = Date.now();
    deps.usage.length = 0;
    try {
      if (input.operation === 'budget') return { status: 'OK', budget: await deps.budget.read(deadline.signal) };
      if (input.operation === 'query') {
        if (!isValidIdentifier(input.ownerId) || !input.ownerId.startsWith('rag-smoke-') ||
          !isValidIdentifier(input.requestId) || typeof input.body !== 'string') throw new RagFailure('INVALID_INPUT');
        const request = parseRequest(input.body);
        const approval = await deadline.within(() => deps.approval(deadline.signal));
        const response = await deadline.within(() => deps.query(approval, input.ownerId as string, request, input.requestId as string, deadline.signal));
        return { response, usage: deps.usage.slice(), elapsedMs: Date.now() - started };
      }
      if (input.operation !== 'jev-fixture' && input.operation !== 'answer-fixture') throw new RagFailure('INVALID_INPUT');
      if (!isValidIdentifier(input.fixtureId)) throw new RagFailure('INVALID_INPUT');
      const fixture = deps.fixture(input.fixtureId);
      if (!fixture) throw new RagFailure('INVALID_INPUT');
      const jevInput: JevInput = { model: JEV_MODEL, questionSetVersion: LIVE_QUESTION_SET.questionSetVersion,
        questions: LIVE_QUESTION_SET.questions, state: { question: fixture.question, evidence: fixture.evidence.text } };
      const inputBound = jevInputUpperBound(JSON.stringify(jevInput));
      if (inputBound > 32_000) throw new RagFailure('EVIDENCE_VALIDATION_UNAVAILABLE');
      // Answer mode must already have a frozen confirmation receipt; calibration mode cannot generate.
      const approval = input.operation === 'answer-fixture' ? await deadline.within(() => deps.approval(deadline.signal)) : null;
      await deadline.within(() => deps.budget.reserve('jev', inputBound, deadline.signal));
      const jev = await deadline.within(() => deps.providers.jev(jevInput, deadline.signal));
      if (approval === null) return { status: 'EVALUATED', fixtureId: fixture.id, evidenceHash: hash(fixture.evidence.text),
        jev, usage: deps.usage.slice(), elapsedMs: Date.now() - started };
      const verdict = decideNoul(jev, configOf(approval));
      if (verdict !== 'ALLOW') return { status: 'NOT_ENOUGH_CONTEXT', reason: verdict, fixtureId: fixture.id,
        jev, usage: deps.usage.slice(), elapsedMs: Date.now() - started };
      const generate: GenerateInput = { question: fixture.question, evidence: fixture.evidence, maxOutputTokens: 1024 };
      const promptBound = deepSeekInputUpperBound(DEEPSEEK_SYSTEM_PROMPT + JSON.stringify({ question: fixture.question, evidence: fixture.evidence.text }));
      if (promptBound > 32_000) throw new RagFailure('INPUT_TOO_LONG');
      await deadline.within(() => deps.budget.reserve('deepseek', promptBound, deadline.signal));
      const raw = await deadline.within(() => deps.providers.generate(generate, deadline.signal));
      const answer = validateGenerated(raw, fixture.evidence, deps.countOutput);
      return { status: 'ANSWERED', fixtureId: fixture.id, answer: answer.answer, sources: answer.sources,
        jev, evidenceHash: hash(fixture.evidence.text), usage: deps.usage.slice(), elapsedMs: Date.now() - started };
    } catch (error) {
      return { status: 'ERROR', code: error instanceof RagFailure ? error.code : 'PROVIDER_UNAVAILABLE',
        usage: deps.usage.slice(), elapsedMs: Date.now() - started };
    } finally { deadline.close(); }
  };
}
