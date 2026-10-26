import assert from 'node:assert/strict';
import { TransactionCanceledException } from '@aws-sdk/client-dynamodb';
import { GetCommand, QueryCommand, PutCommand, UpdateCommand, TransactWriteCommand,
  type DynamoDBDocumentClient } from '@aws-sdk/lib-dynamodb';

type Row = Record<string, any>;
const rowKey = (r: Row) => JSON.stringify([r.ownerId, r.noteId]);
/** Conditional SDK double; evaluates the production expression subset, atomically. */
export class TestDynamo {
  rows = new Map<string, Row>();
  transactions: TransactWriteCommand[] = [];
  updates: UpdateCommand[] = [];
  beforeTransaction?: () => void;
  afterTransaction?: () => void;
  /** Inject one command failure without weakening condition/update semantics. */
  failWhen?: (command: any) => Error | undefined;
  put(row: Row) { this.rows.set(rowKey(row), structuredClone(row)); }
  get(owner: string, sort: string) { return this.rows.get(rowKey({ ownerId: `OWNER#${owner}`, noteId: sort })); }
  client = { send: async (c: any, options?: { abortSignal?: AbortSignal }) => {
    options?.abortSignal?.throwIfAborted();
    return this.send(c);
  } } as unknown as DynamoDBDocumentClient;
  private value(path: string, row: Row, names: Row) {
    return path.trim().split('.').reduce((r, p) => r?.[names[p] ?? p], row as any);
  }
  private check(expression: string | undefined, row: Row | undefined, names: Row = {}, v: Row = {}): boolean {
    if (!expression) return true;
    // Split only at the top level; parenthesized OR guards are kept together.
    const split = (s: string, op: string): string[] => {
      let depth = 0, start = 0; const pieces: string[] = [];
      for (let i = 0; i < s.length; i++) {
        if (s[i] === '(') depth++;
        if (s[i] === ')') depth--;
        if (!depth && s.slice(i, i + op.length) === op) { pieces.push(s.slice(start, i)); start = i + op.length; }
      }
      return [...pieces, s.slice(start)];
    };
    const e = expression.trim();
    const ors = split(e, ' OR '); if (ors.length > 1) return ors.some(s => this.check(s, row, names, v));
    const ands = split(e, ' AND '); if (ands.length > 1) return ands.every(s => this.check(s, row, names, v));
    if (e.startsWith('(') && e.endsWith(')')) return this.check(e.slice(1, -1), row, names, v);
    const attribute = /^attribute_(not_)?exists\((.+)\)$/.exec(e);
    if (attribute) return (this.value(attribute[2], row ?? {}, names) !== undefined) !== !!attribute[1];
    const contains = /^contains\((.+), (:.+)\)$/.exec(e);
    if (contains) return this.value(contains[1], row ?? {}, names)?.includes(v[contains[2]]) ?? false;
    const match = /^([\w#.]+) (=|>|<|<=|>=) (:\w+)$/.exec(e);
    assert.ok(match, `Unsupported test condition ${e}`);
    const left = this.value(match[1], row ?? {}, names), right = v[match[3]];
    return match[2] === '=' ? left === right : match[2] === '>' ? left > right :
      match[2] === '<' ? left < right : match[2] === '<=' ? left <= right : left >= right;
  }
  private apply(op: Row) {
    if (op.Item) this.put(op.Item);
    else if (op.UpdateExpression) {
      const row = { ...op.Key, ...this.rows.get(rowKey(op.Key)) };
      const sections = op.UpdateExpression.split(/\b(SET|REMOVE|ADD)\b/);
      for (let i = 1; i < sections.length; i += 2) {
        for (const assignment of sections[i + 1].trim().split(',')) {
          const [name, value] = assignment.trim().split(sections[i] === 'SET' ? ' = ' : ' ');
          const field = op.ExpressionAttributeNames?.[name] ?? name;
          if (sections[i] === 'REMOVE') delete row[field];
          else if (sections[i] === 'ADD') {
            const current = row[field] ?? 0;
            if (typeof current !== 'number' || typeof op.ExpressionAttributeValues[value] !== 'number') {
              throw Object.assign(new Error('Invalid UpdateExpression: ADD requires numbers'),
                { name: 'ValidationException' });
            }
            row[field] = current + op.ExpressionAttributeValues[value];
          } else row[field] = op.ExpressionAttributeValues[value];
        }
      }
      this.put(row);
    }
  }
  private async send(c: any): Promise<Row> {
    const failure = this.failWhen?.(c); if (failure) throw failure;
    if (c instanceof GetCommand) return { Item: structuredClone(this.rows.get(rowKey(c.input.Key!))) };
    if (c instanceof QueryCommand) {
      const v = c.input.ExpressionAttributeValues!;
      const rows = [...this.rows.values()].filter(row => c.input.IndexName === 'PendingRelays'
        ? row.relayQueue === v[':pending'] && row.relayDueAt <= v[':now'] : c.input.IndexName
        ? row.changeOwnerId === v[':ownerKey'] && row.changeSequence > v[':after']
        : row.ownerId === v[':owner'] && row.noteId.startsWith(v[':prefix']));
      rows.sort((a, b) => c.input.IndexName === 'PendingRelays' ? a.relayDueAt - b.relayDueAt :
        c.input.IndexName ? a.changeSequence - b.changeSequence : a.noteId.localeCompare(b.noteId));
      const offset = c.input.ExclusiveStartKey ? rows.findIndex(r => rowKey(r) === rowKey(c.input.ExclusiveStartKey!)) + 1 : 0;
      const items = rows.slice(offset, offset + (c.input.Limit ?? rows.length));
      const last = items.at(-1);
      return { Items: structuredClone(items), ...(last && offset + items.length < rows.length ?
        { LastEvaluatedKey: { ownerId: last.ownerId, noteId: last.noteId } } : {}) };
    }
    if (c instanceof TransactWriteCommand) {
      const hook = this.beforeTransaction; this.beforeTransaction = undefined; hook?.();
      const items = c.input.TransactItems!;
      const keys = items.map(x => rowKey((x.Put?.Item ?? x.Update?.Key ?? x.ConditionCheck?.Key)!));
      assert.equal(new Set(keys).size, keys.length, 'Dynamo forbids two operations on one item');
      assert.ok(items.length <= 100);
      const reasons = items.map((item) => {
        const op = item.Put ?? item.Update ?? item.ConditionCheck!;
        const old = this.rows.get(rowKey((item.Put?.Item ?? item.Update?.Key ?? item.ConditionCheck?.Key)!));
        return this.check(op.ConditionExpression, old, op.ExpressionAttributeNames, op.ExpressionAttributeValues)
          ? { Code: 'None' } : { Code: 'ConditionalCheckFailed' };
      });
      if (reasons.some(reason => reason.Code === 'ConditionalCheckFailed')) {
        throw new TransactionCanceledException({ message: 'Conditional', $metadata: {},
          CancellationReasons: reasons });
      }
      this.transactions.push(c); for (const item of items) if (item.Put ?? item.Update) this.apply(item.Put ?? item.Update!);
      const after = this.afterTransaction; this.afterTransaction = undefined; after?.();
      return {};
    }
    assert.ok(c instanceof PutCommand || c instanceof UpdateCommand);
    const op = c.input as Row;
    if (c instanceof UpdateCommand) this.updates.push(c);
    if (!this.check(op.ConditionExpression, this.rows.get(rowKey(op.Item ?? op.Key)), op.ExpressionAttributeNames, op.ExpressionAttributeValues)) {
      throw Object.assign(new Error('Conditional'), { name: 'ConditionalCheckFailedException' });
    }
    this.apply(op); return c.input.ReturnValues === 'ALL_NEW' ?
      { Attributes: structuredClone(this.rows.get(rowKey(op.Key))) } : {};
  }
}
