import {InvalidDocumentError} from './document_models';

export class DocumentReader {
  blocks = 0; cells = 0; runs = 0; bytes = 0;
  private readonly ancestors = new Set<object>();
  private readonly ids = new Set<string>();
  fail(): never { throw new InvalidDocumentError(); }

  inspect(value: unknown, depth = 0): void {
    if (depth > 36 || this.bytes > 180000) this.fail();
    if (typeof value === 'string') {
      if (value.length > 180000) this.fail();
      this.bytes += Buffer.byteLength(JSON.stringify(value), 'utf8');
    } else if (value !== null && typeof value === 'object') {
      if (this.ancestors.has(value)) this.fail();
      this.ancestors.add(value);
      const array = Array.isArray(value);
      const keys = Object.keys(value);
      if (array && keys.length !== value.length) this.fail();
      if (keys.length > (array ? 4096 : 16)) this.fail();
      for (const key of keys) {
        if (!array) { this.inspect(key, depth + 1); this.bytes++; }
        this.inspect((value as Record<string, unknown>)[key], depth + 1);
      }
      this.bytes += 2 + Math.max(0, keys.length - 1);
      this.ancestors.delete(value);
    } else if (value === null || typeof value === 'boolean' || typeof value === 'number') {
      if (typeof value === 'number' && !Number.isFinite(value)) this.fail();
      this.bytes += JSON.stringify(value).length;
    } else this.fail();
    if (this.bytes > 180000) this.fail();
  }

  object(value: unknown, required: readonly string[], optional: readonly string[] = []): Record<string, unknown> {
    if (value === null || typeof value !== 'object' || Array.isArray(value)) this.fail();
    const object = value as Record<string, unknown>;
    if (required.some(key => !Object.hasOwn(object, key)) ||
        Object.keys(object).some(key => !required.includes(key) && !optional.includes(key))) this.fail();
    return object;
  }
  list(value: unknown, max: number): unknown[] {
    if (!Array.isArray(value) || value.length > max) this.fail();
    return value;
  }
  str(value: unknown): string { if (typeof value !== 'string') this.fail(); return value; }
  bool(value: unknown): boolean { if (typeof value !== 'boolean') this.fail(); return value; }
  int(value: unknown): number { if (typeof value !== 'number' || !Number.isSafeInteger(value)) this.fail(); return value; }
  identify(value: unknown): string {
    const id = this.str(value);
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(id) || this.ids.has(id)) this.fail();
    this.ids.add(id); return id;
  }
}
