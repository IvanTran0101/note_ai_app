/** A bounded contiguous prefix keeps rich feed responses predictable.
 * The first row always makes progress, including a larger pre-M09 legacy row.
 * Cursor selection stays with the existing feed owner and returned prefix.
 */
export function boundedChangeRows(rows: Record<string, unknown>[], limit: number,
  byteBudget = 900000): Record<string, unknown>[] {
  const selected: Record<string, unknown>[] = [];
  let bytes = 0;
  for (const row of rows.slice(0, limit)) {
    const size = Buffer.byteLength(JSON.stringify(row), 'utf8');
    if (selected.length > 0 && bytes + size > byteBudget) break;
    selected.push(row); bytes += size;
  }
  return selected;
}
