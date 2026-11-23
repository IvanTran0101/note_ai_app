# M09 document contract for implementation

Status: P0 contract lock; validation/storage/wire implementation is P1–P3.
Existing note metadata/keys/permissions retain their owners.

## Canonical data

NoteDocument version1, immutable typed tree. Thirteen UI choices correspond to
paragraph, heading(level1–4), bulletedList, numberedList, todo, toggle, callout,
quote, table and divider. Stable block/row/cell IDs are unique within one note,
ASCII letters/digits/underscore/hyphen, length1–64. Block children belong to this
note; no child notes/pages. Table grid is rectangular, each cell has inline runs.
No raw editor/Flutter/HTML objects enter Domain, encrypted storage or wire.

Inline text runs preserve Unicode/newlines exactly. Marks: bold, italic,
underline, strikethrough, inlineCode, semantic color/highlight, size12–48 and
validated http/https/mailto link. Defaults are omitted canonically. Palette:
gray/brown/orange/yellow/green/blue/purple/pink/red, with default text and no
highlight represented by omission. InlineMath keeps expression; editor adapter
uses one UTF16 U+FFFC atom. Ordinary typing must not inherit the math attribute.
Clear-format keeps math; converting/removing math is an explicit command.

Plain projection is deterministic traversal: text and math expression in order,
newline between blocks, tab between cells/newline between rows. Include nested
children even when a toggle is closed; divider projects a line boundary. Visible
link text only, no URL fetch. Exact content equals this projection for rich notes.
Toggle expanded state, caret/selection/menu/history are ephemeral actor UI state,
never persisted into the shared document.

## Budgets for new rich writes

| Limit | Value |
| --- | --- |
| Full canonical note snapshot (document + projection + all metadata) | existing300000 UTF8 bytes |
| Canonical document JSON | 180000 UTF8 bytes |
| Plain projection | 100000 UTF8 bytes |
| Blocks including nested blocks | 512 |
| Container depth | 8 |
| Total inline runs across blocks/cells | 4096 |
| Per-table rows / columns | 32 / 12 |
| Total cells across the document | 512 |
| Link | 2048 UTF8 bytes; no control characters; allowed schemes only |
| Inline equation | 512 UTF16 units, grouping depth8, bounded approved commands |

Validate aggregate bytes too: the independent document/projection limits do not
guarantee space for attachments/title/labels/etc. Reject oversized new writes
without dropping metadata or truncating text. Keep draft and provide recovery.
Reject unknown types/fields/marks, duplicate IDs, ragged tables, forbidden
children/attrs, cycles, invalid sizes/URLs/math and projection mismatches.
Input source may be hostile; codecs must bound traversal before recursive work.

Legacy reads/replays are not subjected to new rich-write limits. Keep original
content and nullable document for legacy notes, with virtual paragraph projection
only in the editor. Do not inflate persisted old notes during migration. If a
new rich conversion exceeds budget, preserve original content/draft and report
the limit. Empty/divider-only documents are valid rich content; do not fake body
text to satisfy legacy nonempty-content validation. Title rules remain separate.

## Persistence, transport and guards

- Inner schema7, existing envelope/AAD3 and key lifecycle. One canonical actor
  writer commits document/projection/metadata/draft/outbox together, encrypted.
- Every note snapshot, draft, conflict/copy, ACK/pull/hydrate path carries typed
  document presence. Metadata-only/revoked/protected-unavailable paths contain
  neither document nor plain content. AppSync remains revision invalidation only.
- Wire3/basicBlocksV1 extends wire2 labels/attachments. Backend capability/source
  first; legacy clients preserve or reject rich writes explicitly. Unsupported
  backend keeps local pending with upgrade feedback; no silent stripping.
- Freeze exact attempted legacy payload, mutation ID and fingerprint. Lost-ACK
  replay is checked before new-write version/shape guards. Whole-note CAS remains.
- Equality includes structure/marks/font/math, so format-only writes are durable.
  Search/preview/Summary use authorized plain projection; AI receives no raw
  document/style JSON. Summary stale follows existing whole-note mutation flow.
- Recheck document/selection/session/access revisions and settled IME before
  commands/save. Lock/revoke/logout closes ephemeral controls and masks private
  content. Viewer stays read-only; encrypted blocked drafts never auto-replay
  under a new grant. Existing attachments/pin/labels/security/share are preserved.
