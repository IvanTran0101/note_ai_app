# M09.RT.P2 encrypted local document pipeline

2026-10-14. Status: source/local storage foundation accepted. Main rich editor
is still P4; typed backend transport is still P3.

## Implementation

- Inner schema7; packet/AAD3 and existing key lifecycle remain. Versions2–6
  migrate without inflating virtual documents or changing attempted payload/ID.
  Encrypted v6 cutover reseals by the existing CAS; it never seeds empty state.
- Canonical strict document1 codec, bounded preflight/cycles/fields/depth/counts,
  semantic marks and deterministic projection. JSON180000, projection100000 and
  full rich local note300000 UTF8 bytes. Oversize writes refuse without truncation.
- LocalNoteState/DTO/SyncNotePayload/SyncNoteSnapshot carry typed document and
  explicit presence. Existing one writer commits document/projection/outbox,
  preserves files/pin/labels/share/protection and refuses plain writers stripping
  existing rich data. Format-only changes are durable; no-op adds no mutation.
- Draft evidence, password wrapping/unwrapping, redaction and retained shared
  work carry document. Revoke masks it and blocks old-grant replay; ciphertext
  and recovery evidence remain. Metadata-only projections contain no document.
- ACK/pull/hydrate/conflict/local-copy/protection/label normalization retain the
  document. ACK without required typed presence refuses without dropping outbox.
  Legacy responses cannot replace a rich body with another plain body.
- Copy/Undo adapters preserve rich snapshots; mismatched plain drafts refuse
  before copy. Empty rich note creation needs no fake nonempty body.
- Production writer advertises document1 locally. Until P3, legacy HTTP encoder
  explicitly refuses rich payloads before any request instead of stripping them.
  No main editor UI or deployed AWS capability is claimed at this phase.

Repository mapping/direct saves and encrypted migration are separate files by
responsibility. They share the same durable writer; no second state owner.

## Verification receipts

Final full VM1752 PASS /4 configured skips; scoped analyzer clean. Installed
Chrome aggregate93/93 PASS across nine target mains, including actual IndexedDB
document persistence and encrypted v6→v7 reseal. Android emulator actual
file/device-key integration2/2 PASS via m09_document_storage_test.dart; no mock
device key channel on native, NoteFlow_API35 data retained. This is storage
integration, distinct from the final human editor UI matrix in P6.
Native integration APK SHA256:
`CC154251C03A6E463174D1A2D838AE58A416D956754C152E14DEB7154A7FA7E2`.
Build394.7s, installed-r; test runtime6s. This artifact launches the test harness,
not the final M09 product editor.
Earlier focused76/76 preceded final copy/empty-note additions. Three full-run
failures were two obsolete optional-field assertions and a controller adapter
compile gap; corrected and under retest. Logs are ignored under output/m09.

Platform integration uses fresh synthetic account namespaces, actual platform
store and device key APIs, with no user data reset. Browser test channel key mock
is distinguished from native real key custody. P4–P6 will exercise the completed
editor through actual Chrome/Android UI and score each platform separately.
