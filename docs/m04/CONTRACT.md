# M04.1 — approved contract

Decision date:2026-10-04. User approved collaborator A/A/A. Sources:
https://app.notion.com/p/3eff9c7a1aa08010a0b3c177d7322a03
and https://app.notion.com/p/3e9f9c7a1aa080ed97c5ece6a879d3d3.

## Catalog and association

Label identity is `(ownerId,id)`, independent of its name. Duplicate active
names are allowed. Names are trimmed, nonblank, at most64 Unicode code points;
control characters are rejected. No implicit case/accent/Unicode normalization.
IDs are nonblank, bounded128 characters and control-character free. Note stores
a sorted immutable set of at most32 label IDs. Attach/detach and identical rename
are no-ops. Deleted Labels are tombstones: deletion never deletes or rewrites
Notes. A stale ID survives text edits, while views omit confirmed tombstones.

Only owner can manage catalog or Note associations, including on Editor shares.
New associations validate fresh active same-owner Labels inside the canonical
Note writer's existing store transaction. No second Note writer or native store.
Rename updates ID-resolved chips without changing Note content/revision or AI
inputs. Concurrent text, pin, attachments, protection, sharing and drafts survive.

## Local schema and sync protocol

Inner schema5→6 adds catalog, typed Label outbox/conflicts and Note label metadata.
Supported2/3/4→5 migration remains strict. Migration preserves IDs, preferences,
cursor, Notes, attempted mutation bytes, drafts and conflicts. Outer encrypted
packet/AAD3 and keys stay unchanged. All catalog data shares the existing actor
encrypted document. Account/session fences reject late work.

Wire v1 stays available for previously attempted requests. New Label and
label-aware Note requests use explicit v2 routes; older servers cannot silently
accept them and discard metadata. V2 GET returns an explicit version and typed
Note/Label changes. Only consumed contiguous feed prefixes advance the cursor;
v1 skips Label entries without decoding them as Notes. V2 bootstrap replays the
feed from its beginning once for upgraded v1 cursors, then uses the same durable
cursor/coordinator. An interrupted bootstrap resumes its committed prefix.

Entity type participates in resource identity, fingerprints, ACK/conflict checks
and stopped-resource keys. Same-string Note/Label IDs cannot collide. Attempted
mutations are immutable and idempotently replayed; definitive repairs get fresh
IDs. Label create ACK precedes dependent Note pushes, even if Note queue position
is earlier. Entity failures do not block unrelated resources; auth failure ends
the pass. Label conflict exposes explicit local/cloud decisions, never ID merging.

Backend validates newly added IDs with same-owner active Label conditions at
commit. Unchanged tombstone IDs do not block text edits. Legacy Note writes
preserve label metadata or reject unsafe changes. M03 manifest guard remains
closed until collaborator's verified-object association implementation exists.
Deploy v2 backend before enabling client v2 in production; this batch tests
matching local source and prepares leader setup, without live AWS deployment.

## Query and privacy

Filter = readable projection AND (title OR content keyword) AND ALL selected
Labels. Empty selection means keyword only; no Search button or network/DB call
per key. Common query serves Notes/Dashboard, list/grid; filter before pin-first
ordering. Vietnamese/case behavior is explicit and covered by fixtures.

Recipients see sanitized names only for the currently readable shared Note,
never its owner's full catalog. Lock/revoke removes labels from chips, search,
filter membership and counts; encrypted retained drafts remain. Account change
clears catalog/filter state and ignores late async responses. Unknown/loading or
failed catalog is not deletion and must not erase raw IDs. Confirmed deleted
selected Labels may be pruned from the effective filter.

## Acceptance and publication

M04.2 Domain → M04.3 local transactions → M04.4 sync/backend → M04.5 UI/query →
M04.6 privacy → M04.7 tests/actual Chrome+Android → M04.8 source/setup receipt.
Update progress and push after each accepted milestone. Tick rubric only from
evidence, separating automated, actual UI and live-provider gates. M09 deferred.
