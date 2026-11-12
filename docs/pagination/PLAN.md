# Local-first note pagination

Authorized 12 November 2026. Notion:
https://app.notion.com/p/416f9c7a1aa0811ab6a0e33a3819c5d8

## Contract and user flow

`NotePageQuery` defaults to 50 rows, page zero, owned notes. Valid page sizes
are 1–100. `NotePage` returns immutable rows, total, effective page, page size
and authorized global label choices. Previous/Next show the current result
range, remain keyboard accessible and retain minimum 48dp targets. Home and
Notes navigation stays outside the result scroll; Web Search uses its footer.

Production `NoteRepository` implements the optional Application reader, and
Application checks account/session before and after it. Existing custom
controllers without that capability retain their legacy list interface; the
production controller advertises paging only when its repository implements it.

The repository reads its account snapshot under its existing queue, checks the
account/session/access fence, excludes tombstones and unauthorized/revoked
shared rows, applies full keyword/label filters, sorts and then converts only
the page slice into aggregates/DTOs. Matching is case-insensitive title/body,
with AND across owner-qualified label selections. Protected list projections
remain masked and do not contribute private search hits or label choices.

Pin-first ordering is unchanged: pin time descending, otherwise updated/created
date descending, then canonical owner/id. Overview recent rows use updated time
without pin-first ordering, matching the original overview semantics. The main
production overview asks for 20 rows. Home recent cards use a separate bounded
first slice, independent from the currently selected result page.

## Refresh, selection and errors

- Query/filter/sort/tab changes return to page zero. A dataset shrink clamps an
  out-of-range request to the last valid page; an empty dataset uses page zero.
- This is a fresh local query, not a frozen snapshot cursor. Sync or mutations
  can move a note between pages; refresh reflects current order. No guarantee
  of stable page membership across concurrent writes is made.
- Generation checks discard obsolete asynchronous results and failures. A
  session change rejects a pending repository/Application read.
- Moving a selected note out of the result page does not imply access loss.
  Its authoritative detail read is independent. Denied/missing content retains
  only redacted evidence. External note/citation opens do not append row 51.
- Save/delete/pin/sync refresh the query. Failed page reads retain old rows,
  expose the existing error and allow retry of the intended query/page.
- Filter chips receive authorized global facets, including labels on rows
  outside the visible page. Existing own-catalog management remains unchanged.

## Storage and performance boundary

The encrypted store still exposes one whole account document through
`ILocalSyncStore.read`. Its envelope, outbox, drafts, conflicts and CAS writer
are unchanged. A query still decodes this document and sorts matching row
references. Therefore this batch bounds list DTOs/rendering, not total decoded
memory or disk reads. It is not per-record IndexedDB pagination and makes no
1,000-note latency, RAM or offline asset-bootstrap guarantee.

Per-note encrypted record migration would require a separate atomic storage,
key/epoch, outbox, crash and legacy-writer design. No ad-hoc plaintext index or
second state writer is introduced here. Cloud sync retains its existing cursor
pagination. No new dependency or schema/version change is needed.

## Verification

1. 1,000 synthetic stable notes, 20 pages of 50, no gaps or duplicate identities.
2. Search/label filter finds a note outside page one; global authorized facets.
3. Protected note masking/no secret search or labels; owner/shared identity and
   revoked rows; delayed session-change rejection.
4. Pin order, date order, tie-breaks, invalid bounds, empty and clamped pages.
5. Notes/Home page gestures, query reset, failure/retry and out-of-order results.
6. Existing Dashboard, Notes selection/security/dirty-close, label and repository
   regression. Preserve original assertions except demonstrated stale geometry.
7. Chrome and actual Android platform storage integration on an isolated
   synthetic account. Never wipe existing app/AVD data; no cloud calls required.

## Current evidence

See CURRENT_WORK.md for final receipts. Initial focused VM9 passed after fixing
invalid revoked test data and a test-only encoding defect. The first broad run
found an existing Recents fixture expectation (20px versus actual baseline26).
The baseline DashboardContent, temporarily restored with additive constructor
slots only, reproduced the same failure. Current source bytes were restored in
`finally`; the test now reflects the unchanged 26px/native-muted/w400 style.
The subsequent broad VM run passed 128 cases with one configured skip.

Whole-M09 >=95% similarity, UI53 completion and live AWS remain separate gates.
