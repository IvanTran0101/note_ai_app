# M09.RT.P1 pure document and Application snapshot

2026-10-14. Foundation accepted; encrypted/wire/UI adoption belongs to P2–P4.

Domain owns immutable NoteDocument1 blocks, table rows/cells, text/math runs,
semantic marks and size12–48. IDs are unique, structure/runs/projection bounded,
links/math validated. All13 approved choices, nested content and deterministic
plain projection are independent of Flutter/AppFlowy/Infrastructure.

Note owns optional document and exact derived content. Format-only changes
count; true no-ops do not. Legacy title-only writes preserve the document;
plain-body replacement cannot silently discard rich content. Metadata-only DTOs
contain neither plain content nor document. Empty rich documents are valid.

saveDocumentSnapshot uses the existing atomic mutation path and selected snapshot,
session/access fences. A repository must advertise documentVersion1 or it fails
before mutation. Production NoteRepository deliberately does not advertise this
yet. There is no new writer or public rich editor in the main app at this phase.

## Verification

27/27 focused VM PASS:12 Domain/aggregate,11 Application snapshot and4 existing
editor snapshot regression. Scoped Domain and Application analyzers clean.
Cases include format-only persistence/sync notification, no-op, same-body/time
format drift, Viewer denial, canonical Editor owner, lock/session/access change
at commit, masked DTO refusal, storage failure rollback and legacy writer refusal.
The snapshot test double proves these fences, not encryption or cloud roundtrip.

Logs: ignored output/m09/p1-snapshot-vm.log, p1-domain-analyze.log and
p1-application-analyze.log. Full root regression has also been launched; native
hook rebuild is still running. It is not counted as a completed receipt here.
No M09 UI score assigned. P2 codec must add canonicalJSON180000/full-note300000
byte validation and the complete encrypted note/draft/outbox pipeline before
enabling production writer capability.
