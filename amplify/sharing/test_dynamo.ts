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
  beforeTransaction?: () => void;
  put(row: Row) { this.rows.set(rowKey(row), structuredClone(row)); }
  get(owner: string, sort: string) { return this.rows.get(rowKey({ ownerId: `OWNER#${owner}`, noteId: sort })); }
  client = { send: async (c: any) => this.send(c) } as unknown as DynamoDBDocumentClient;
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
    const match = /^([\w#.]+) (=|>|<) (:\w+)$/.exec(e);
    assert.ok(match, `Unsupported test condition ${e}`);
    const left = this.value(match[1], row ?? {}, names), right = v[match[3]];
    return match[2] === '=' ? left === right : match[2] === '>' ? left > right : left < right;
  }
  private apply(op: Row) {
    if (op.Item) this.put(op.Item);
    else if (op.UpdateExpression) {
      const row = { ...op.Key, ...this.rows.get(rowKey(op.Key)) };
      for (const assignment of op.UpdateExpression.replace(/^SET /, '').split(',')) {
        const [name, value] = assignment.trim().split(' = ');
        row[op.ExpressionAttributeNames?.[name] ?? name] = op.ExpressionAttributeValues[value];
      }
      this.put(row);
    }
  }
  private async send(c: any): Promise<Row> {
    if (c instanceof GetCommand) return { Item: structuredClone(this.rows.get(rowKey(c.input.Key!))) };
    if (c instanceof QueryCommand) {
      const v = c.input.ExpressionAttributeValues!;
      const rows = [...this.rows.values()].filter(row => c.input.IndexName
        ? row.changeOwnerId === v[':ownerKey'] && row.changeSequence > v[':after']
        : row.ownerId === v[':owner'] && row.noteId.startsWith(v[':prefix']));
      rows.sort((a, b) => c.input.IndexName ? a.changeSequence - b.changeSequence : a.noteId.localeCompare(b.noteId));
      return { Items: structuredClone(rows.slice(0, c.input.Limit ?? rows.length)) };
    }
    if (c instanceof TransactWriteCommand) {
      const hook = this.beforeTransaction; this.beforeTransaction = undefined; hook?.();
      const items = c.input.TransactItems!;
      const keys = items.map(x => rowKey((x.Put?.Item ?? x.Update?.Key ?? x.ConditionCheck?.Key)!));
      assert.equal(new Set(keys).size, keys.length, 'Dynamo forbids two operations on one item');
      assert.ok(items.length <= 100);
      for (const item of items) {
        const op = item.Put ?? item.Update ?? item.ConditionCheck!;
        const old = this.rows.get(rowKey((item.Put?.Item ?? item.Update?.Key ?? item.ConditionCheck?.Key)!));
        if (!this.check(op.ConditionExpression, old, op.ExpressionAttributeNames, op.ExpressionAttributeValues)) {
          throw new TransactionCanceledException({ message: 'Conditional', $metadata: {},
            CancellationReasons: [{ Code: 'ConditionalCheckFailed' }] });
        }
      }
      this.transactions.push(c); for (const item of items) if (item.Put ?? item.Update) this.apply(item.Put ?? item.Update!);
      return {};
    }
    assert.ok(c instanceof PutCommand || c instanceof UpdateCommand);
    const op = c.input as Row;
    if (!this.check(op.ConditionExpression, this.rows.get(rowKey(op.Item ?? op.Key)), op.ExpressionAttributeNames, op.ExpressionAttributeValues)) {
      throw Object.assign(new Error('Conditional'), { name: 'ConditionalCheckFailedException' });
    }
    this.apply(op); return {};
  }
}
