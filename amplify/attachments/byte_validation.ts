import { createHash } from 'node:crypto';
import { AttachmentError } from './models';
import type { FileMetadata } from './models';
export type ByteReader = (start: number, end: number) => AsyncIterable<Uint8Array>;

/** Validate actual bounded bytes, including UTF8 and H.264/AAC MP4 structure. */
export async function validateBytes(m: FileMetadata, read: ByteReader) {
  const hash = createHash('sha256'); let total = 0;
  const text = m.mimeType.startsWith('text/') ? new TextDecoder('utf-8', {fatal: true}) : null;
  for await (const chunk of read(0, m.sizeBytes)) {
    total += chunk.length;
    if (total > m.sizeBytes || text && chunk.includes(0)) throw new AttachmentError('invalid');
    hash.update(chunk);
    try { text?.decode(chunk, {stream: true}); } catch { throw new AttachmentError('invalid'); }
  }
  try { text?.decode(); } catch { throw new AttachmentError('invalid'); }
  if (total !== m.sizeBytes || hash.digest('hex') !== m.sha256) throw new AttachmentError('invalid');
  if (text) return;
  const bounded = async (start: number, end: number) => {
    if (start < 0 || end > m.sizeBytes || end < start || end - start > 1024 * 1024) throw new AttachmentError('invalid');
    const data = Buffer.alloc(end - start); let n = 0;
    for await (const part of read(start, end)) {
      if (n + part.length > data.length) throw new AttachmentError('invalid');
      data.set(part, n); n += part.length;
    }
    if (n !== data.length) throw new AttachmentError('invalid'); return data;
  };
  const h = await bounded(0, Math.min(m.sizeBytes, 32));
  const starts = (magic: number[]) => h.length >= magic.length && magic.every((x, i) => h[i] === x);
  const valid = m.mimeType === 'image/jpeg' ? starts([255, 216, 255]) :
    m.mimeType === 'image/png' ? starts([137, 80, 78, 71, 13, 10, 26, 10]) :
    m.mimeType === 'image/webp' ? h.length >= 16 && h.toString('ascii', 0, 4) === 'RIFF' && h.toString('ascii', 8, 12) === 'WEBP' :
    m.mimeType === 'application/pdf' ? starts([37, 80, 68, 70, 45]) :
    m.mimeType === 'video/mp4' ? await new Mp4Validation(m.sizeBytes, bounded).validate() : false;
  if (!valid) throw new AttachmentError('invalid');
}
type Box = {type: string; body: number; end: number};
class Mp4Validation {
  remaining = 2048;
  constructor(readonly size: number, readonly read: (start: number, end: number) => Promise<Buffer>) {}
  async boxes(start: number, end: number): Promise<Box[]> {
    const out: Box[] = [];
    while (start < end) {
      if (--this.remaining < 0 || end - start < 8) throw new AttachmentError('invalid');
      const h = await this.read(start, start + 8); let size = h.readUInt32BE(), header = 8;
      if (size === 1) {
        if (end - start < 16) throw new AttachmentError('invalid');
        const big = await this.read(start + 8, start + 16);
        if (big.readUInt32BE() !== 0) throw new AttachmentError('invalid');
        size = big.readUInt32BE(4); header = 16;
      } else if (!size) size = end - start;
      if (size < header || start + size > end) throw new AttachmentError('invalid');
      out.push({type: h.toString('ascii', 4, 8), body: start + header, end: start + size}); start += size;
    }
    return out;
  }
  one(boxes: Box[], kind: string): Box {
    const xs = boxes.filter(x => x.type === kind);
    if (xs.length !== 1) throw new AttachmentError('invalid'); return xs[0];
  }
  children(b: Box) { return this.boxes(b.body, b.end); }
  async validate(): Promise<boolean> {
    try {
      const root = await this.boxes(0, this.size), ftyp = this.one(root, 'ftyp');
      if (ftyp.end - ftyp.body < 8) return false;
      const movie = await this.children(this.one(root, 'moov')); let videos = 0;
      for (const track of movie.filter(b => b.type === 'trak')) {
        const media = await this.children(this.one(await this.children(track), 'mdia'));
        const handler = this.one(media, 'hdlr'); if (handler.end - handler.body < 12) return false;
        const kind = (await this.read(handler.body, handler.body + 12)).toString('ascii', 8, 12);
        if (kind !== 'vide' && kind !== 'soun') return false;
        const table = this.one(await this.children(this.one(media, 'minf')), 'stbl');
        const description = this.one(await this.children(table), 'stsd');
        if (description.end - description.body < 8) return false;
        const entriesHeader = await this.read(description.body, description.body + 8);
        const entries = await this.boxes(description.body + 8, description.end);
        if (!entries.length || entries.length !== entriesHeader.readUInt32BE(4)) return false;
        for (const e of entries) {
          if (kind === 'vide') {
            if (!['avc1', 'avc3'].includes(e.type) || e.end - e.body < 78) return false;
            const c = this.one(await this.boxes(e.body + 78, e.end), 'avcC');
            if (c.end - c.body < 7 || (await this.read(c.body, c.body + 1))[0] !== 1) return false;
          } else {
            if (e.type !== 'mp4a' || e.end - e.body < 28) return false;
            const esds = this.one(await this.boxes(e.body + 28, e.end), 'esds');
            if (esds.end - esds.body > 1024 || !this.aac(await this.read(esds.body, esds.end))) return false;
          }
        }
        if (kind === 'vide') videos++;
      }
      return videos > 0;
    } catch { return false; }
  }
  aac(bytes: Buffer) {
    let p = 4;
    const descriptor = (tag: number) => {
      if (p >= bytes.length || bytes[p++] !== tag) throw new AttachmentError('invalid'); let size = 0;
      for (let i = 0; i < 4; i++) {
        if (p >= bytes.length) throw new AttachmentError('invalid'); const b = bytes[p++];
        size = (size << 7) | (b & 127);
        if (!(b & 128)) { if (p + size > bytes.length) throw new AttachmentError('invalid'); return p + size; }
      }
      throw new AttachmentError('invalid');
    };
    const esEnd = descriptor(3); if (p + 3 > esEnd) return false;
    const flags = bytes[p + 2]; p += 3;
    if (flags & 128) p += 2;
    if (flags & 64) { if (p >= esEnd) return false; p += 1 + bytes[p]; }
    if (flags & 32) p += 2;
    const configEnd = descriptor(4);
    if (configEnd > esEnd || p + 13 > configEnd || bytes[p] !== 0x40) return false;
    p += 13; const specificEnd = descriptor(5);
    return specificEnd <= configEnd && specificEnd - p >= 2 && [2, 5, 29].includes(bytes[p] >> 3);
  }
}
