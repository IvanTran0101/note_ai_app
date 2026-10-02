import { SummaryFailure } from './summary_contract';

export type SummaryNoteContext = Readonly<{
  ownerId: string; noteId: string; contentRevision: number; protectionRevision: number;
  runId: string; sectionIndex: number; sourceStart: number | null; sourceEnd: number | null;
  accessRevision?: number;
}>;

const invalid = (): never => { throw new SummaryFailure('invalidInput', 'Invalid note lineage'); };
export const parseSummaryNoteContext = (value: unknown): SummaryNoteContext => {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return invalid();
  const v = value as Record<string, unknown>;
  const keys = ['ownerId', 'noteId', 'contentRevision', 'protectionRevision',
    'runId', 'sectionIndex', 'sourceStart', 'sourceEnd'];
  if (Object.keys(v).some(k => ![...keys, 'accessRevision'].includes(k)) || keys.some(k => !Object.hasOwn(v, k))) return invalid();
  if (v.accessRevision !== undefined && (!Number.isSafeInteger(v.accessRevision) || (v.accessRevision as number) < 1)) return invalid();
  for (const key of ['ownerId', 'noteId']) {
    if (typeof v[key] !== 'string' || !v[key].trim() || v[key].length > 128 ||
        /[\u0000-\u001f\u007f]/.test(v[key])) return invalid();
  }
  if (typeof v.runId !== 'string' || !/^[A-Za-z0-9_-]{32}$/.test(v.runId)) return invalid();
  for (const key of ['contentRevision', 'protectionRevision', 'sectionIndex']) {
    if (!Number.isSafeInteger(v[key]) || (v[key] as number) < 0) return invalid();
  }
  if ((v.contentRevision as number) < 1 || (v.sectionIndex as number) > 4) return invalid();
  for (const key of ['sourceStart', 'sourceEnd']) {
    if (v[key] !== null && (!Number.isSafeInteger(v[key]) || (v[key] as number) < 0)) return invalid();
  }
  return v as SummaryNoteContext;
};
