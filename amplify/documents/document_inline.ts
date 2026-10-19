import {colors, type DocumentMarks, type DocumentRun} from './document_models';
import {DocumentReader} from './document_reader';

const commands = new Set(('frac sqrt sum prod int lim sin cos tan log ln exp min max alpha beta gamma delta theta lambda mu pi sigma phi omega Gamma Delta Theta Lambda Pi Sigma Phi Omega infty times cdot div pm mp le leq ge geq ne neq approx equiv in notin subset subseteq cup cap emptyset forall exists partial nabla ldots cdots left right mathbb mathbf mathrm overline underline vec hat bar text').split(' '));

function math(expression: string, reader: DocumentReader): void {
  if (!expression.length || expression.length > 512 || /[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]/.test(expression)) reader.fail();
  let depth = 0;
  for (let index = 0; index < expression.length; index++) {
    if (index && expression[index - 1] === '\\') continue;
    if (expression[index] === '{') depth++;
    if (expression[index] === '}') depth--;
    if (depth < 0 || depth > 8) reader.fail();
  }
  if (depth) reader.fail();
  for (const command of expression.matchAll(/\\([A-Za-z]+)/g)) {
    if (!commands.has(command[1])) reader.fail();
  }
}

function link(value: string, reader: DocumentReader): string {
  if (Buffer.byteLength(value, 'utf8') > 2048 || value.trim() !== value || /[\x00-\x20\x7f]/.test(value)) reader.fail();
  const scheme = /^([a-z][a-z0-9+.-]*):/i.exec(value)?.[1]?.toLowerCase();
  if (!scheme || !['http', 'https', 'mailto'].includes(scheme)) reader.fail();
  if (scheme === 'mailto') {
    if (!value.slice(value.indexOf(':') + 1).split(/[?#]/)[0]) reader.fail();
  } else {
    if (!/^https?:\/\//i.test(value)) reader.fail();
    try { if (!new URL(value).hostname) reader.fail(); } catch { reader.fail(); }
  }
  return value;
}

export function parseMarks(raw: unknown, reader: DocumentReader): DocumentMarks | undefined {
  const flags = ['bold', 'italic', 'underline', 'strikethrough', 'inlineCode'];
  const value = reader.object(raw, [], [...flags, 'color', 'highlight', 'fontSize', 'link']);
  const result: Record<string, unknown> = {};
  for (const flag of flags) if (Object.hasOwn(value, flag) && reader.bool(value[flag])) result[flag] = true;
  for (const key of ['color', 'highlight']) if (Object.hasOwn(value, key)) {
    const color = reader.str(value[key]);
    if (!(colors as readonly string[]).includes(color)) reader.fail();
    result[key] = color;
  }
  if (Object.hasOwn(value, 'fontSize')) {
    const size = value.fontSize;
    if (typeof size !== 'number' || !Number.isFinite(size) || size < 12 || size > 48) reader.fail();
    result.fontSize = size;
  }
  if (Object.hasOwn(value, 'link')) result.link = link(reader.str(value.link), reader);
  return Object.keys(result).length ? result as DocumentMarks : undefined;
}

function run(raw: unknown, reader: DocumentReader): DocumentRun {
  const value = reader.object(raw, ['type'], ['text', 'expression', 'marks']);
  const marks = Object.hasOwn(value, 'marks') ? parseMarks(value.marks, reader) : undefined;
  if (value.type === 'text') {
    if (Object.hasOwn(value, 'expression')) reader.fail();
    return {type: 'text', text: reader.str(value.text), ...(marks ? {marks} : {})};
  }
  if (value.type !== 'math' || Object.hasOwn(value, 'text') || marks?.inlineCode || marks?.link) reader.fail();
  const expression = reader.str(value.expression); math(expression, reader);
  return {type: 'math', expression, ...(marks ? {marks} : {})};
}

export function parseRuns(raw: unknown, reader: DocumentReader): readonly DocumentRun[] {
  const values = reader.list(raw, 4096);
  if ((reader.runs += values.length) > 4096) reader.fail();
  const result: DocumentRun[] = [];
  for (const value of values) {
    const next = run(value, reader);
    if (next.type === 'text' && next.text === '') continue;
    const previous = result.at(-1);
    if (next.type === 'text' && previous?.type === 'text' && JSON.stringify(previous.marks) === JSON.stringify(next.marks)) {
      result[result.length - 1] = {...previous, text: previous.text + next.text};
    } else result.push(next);
  }
  return result;
}

export const projectRuns = (runs: readonly DocumentRun[]): string =>
  runs.map(run => run.type === 'text' ? run.text : run.expression).join('');
