import {blockTypes, colors, type DocumentBlock, type DocumentColor, type DocumentRow, type NoteDocument} from './document_models';
import {DocumentReader} from './document_reader';
import {parseRuns, projectRuns} from './document_inline';

export function parseNoteDocument(raw: unknown): NoteDocument {
  const reader = new DocumentReader(); reader.inspect(raw);
  const root = reader.object(raw, ['version', 'blocks']);
  if (reader.int(root.version) !== 1) reader.fail();
  const document: NoteDocument = {version: 1, blocks: reader.list(root.blocks, 512).map(value => block(value, reader, 1))};
  if (Buffer.byteLength(projectDocument(document), 'utf8') > 100000 ||
      Buffer.byteLength(JSON.stringify(document), 'utf8') > 180000) reader.fail();
  return document;
}

function rows(raw: unknown, reader: DocumentReader): readonly DocumentRow[] {
  const result = reader.list(raw, 32).map(value => {
    const row = reader.object(value, ['id', 'cells']);
    return {id: reader.identify(row.id), cells: reader.list(row.cells, 12).map(value => {
      if (++reader.cells > 512) reader.fail();
      const cell = reader.object(value, ['id', 'runs']);
      return {id: reader.identify(cell.id), runs: parseRuns(cell.runs, reader)};
    })};
  });
  if (!result.length || !result[0].cells.length || result.some(row => row.cells.length !== result[0].cells.length)) reader.fail();
  return result;
}

function block(raw: unknown, reader: DocumentReader, depth: number): DocumentBlock {
  if (++reader.blocks > 512 || depth > 8) reader.fail();
  const value = reader.object(raw, ['id', 'type'], ['runs', 'children', 'level', 'checked', 'icon', 'tone', 'rows', 'headerRow', 'headerColumn']);
  const id = reader.identify(value.id);
  const type = reader.str(value.type) as DocumentBlock['type'];
  if (!(blockTypes as readonly string[]).includes(type)) reader.fail();
  const table = type === 'table', divider = type === 'divider';
  const has = (key: string) => Object.hasOwn(value, key);
  if ((table || divider) && (has('runs') || has('children')) ||
      type !== 'heading' && has('level') || type !== 'todo' && has('checked') ||
      type !== 'callout' && (has('icon') || has('tone')) ||
      !table && ['rows', 'headerRow', 'headerColumn'].some(has)) reader.fail();
  const result: { -readonly [K in keyof DocumentBlock]: DocumentBlock[K] } = {id, type};
  if (!table && !divider) result.runs = parseRuns(value.runs, reader);
  if (has('children')) {
    const children = reader.list(value.children, 512).map(child => block(child, reader, depth + 1));
    if (children.length) result.children = children;
  }
  if (type === 'heading') {
    const level = reader.int(value.level); if (level < 1 || level > 4) reader.fail(); result.level = level;
  }
  if (type === 'todo') result.checked = reader.bool(value.checked);
  if (has('icon')) {
    const icon = reader.str(value.icon);
    if (!icon.length || [...icon].length > 16 || /[\x00-\x1f\x7f]/.test(icon)) reader.fail(); result.icon = icon;
  }
  if (has('tone')) {
    const tone = reader.str(value.tone); if (!(colors as readonly string[]).includes(tone)) reader.fail(); result.tone = tone as DocumentColor;
  }
  if (table) {
    result.rows = rows(value.rows, reader);
    if (has('headerRow') && reader.bool(value.headerRow)) result.headerRow = true;
    if (has('headerColumn') && reader.bool(value.headerColumn)) result.headerColumn = true;
  }
  return result;
}

function projectBlock(block: DocumentBlock): string {
  if (block.type === 'table') return block.rows!.map(row => row.cells.map(cell => projectRuns(cell.runs)).join('\t')).join('\n');
  return [projectRuns(block.runs ?? []), ...(block.children ?? []).map(projectBlock)].join('\n');
}
export const projectDocument = (document: NoteDocument): string => document.blocks.map(projectBlock).join('\n');
