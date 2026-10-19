export const colors = ['gray', 'brown', 'orange', 'yellow', 'green', 'blue', 'purple', 'pink', 'red'] as const;
export type DocumentColor = typeof colors[number];
export type DocumentMarks = Readonly<{
  bold?: true; italic?: true; underline?: true; strikethrough?: true; inlineCode?: true;
  color?: DocumentColor; highlight?: DocumentColor; fontSize?: number; link?: string;
}>;
export type DocumentRun = Readonly<({type: 'text'; text: string} | {type: 'math'; expression: string}) & {marks?: DocumentMarks}>;
export const blockTypes = ['paragraph', 'heading', 'bulletedList', 'numberedList', 'todo', 'toggle', 'callout', 'quote', 'table', 'divider'] as const;
export type DocumentCell = Readonly<{id: string; runs: readonly DocumentRun[]}>;
export type DocumentRow = Readonly<{id: string; cells: readonly DocumentCell[]}>;
export type DocumentBlock = Readonly<{
  id: string; type: typeof blockTypes[number]; runs?: readonly DocumentRun[];
  children?: readonly DocumentBlock[]; level?: number; checked?: boolean;
  icon?: string; tone?: DocumentColor; rows?: readonly DocumentRow[];
  headerRow?: true; headerColumn?: true;
}>;
export type NoteDocument = Readonly<{version: 1; blocks: readonly DocumentBlock[]}>;

export class InvalidDocumentError extends Error {
  constructor() { super('Invalid or oversized rich document.'); this.name = 'InvalidDocumentError'; }
}
