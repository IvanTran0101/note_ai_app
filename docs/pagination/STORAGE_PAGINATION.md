# Encrypted storage pagination

Authorized 13 November 2026, after the delivered query/UI checkpoint. This is
the second tranche; historical query/UI evidence in VERIFICATION.md is separate.

## Read contract

`ILocalNotePageStore.withNotePageView` lends one generation of metadata headers,
label catalog and an asynchronous payload reader. The callback must be read-only:
it may run again after a cross-tab/process generation change. No snapshot/view
may be retained outside the callback. `NoteRepository` filters/sorts headers,
decrypts selected payloads and checks account/session/generation before return.
Normal 50-row pages fetch up to50 payloads; unprotected detail fetches one.
Label catalog reads fetch none. Protected list/detail metadata fetches none.

Full-text search scans authorized payloads sequentially. Only matching metadata
and selected page payloads survive; selected hits may be read a second time.
Metadata is O(note count), not O(50). No latency/RAM benchmark is claimed.

## Encryption and protection

Index and records use existing device envelope key storage and AEAD primitives.
Index AAD binds account and random generation; record AAD binds account and
opaque record key. A record key contains SHA256(actor/owner/id) and a keyed HMAC
of the complete payload. A changed payload gets a new key; unchanged ciphertext
can be reused. Missing keys are never regenerated over existing ciphertext.

Index headers have no title, body, document or attachment descriptors. Protected
or unavailable content is redacted, including private label memberships. Protected
payloads have no account-key page record, even when the password vault is open.
Unlock and protected detail continue through the existing vault/access guards.
The epoch check spans payload awaits and cache repair retries; locking cancels
an in-flight query instead of allowing a new-epoch retry.

## Atomic publication and compatibility

Canonical encrypted state remains the sole writer for notes/outbox/conflicts,
drafts, cursor, labels, preferences and protection changes. The index/records are
derived, not a second writer. First activation reads the old envelope once.

- Web upgrades IndexedDB to3. One readwrite transaction spans canonical state,
  page metadata (head/index) and encrypted records. Crypto awaits happen before
  the transaction. Exact canonical CAS prevents lost updates. Old2 connections
  receive versionchange/close; attempts to reopen2 fail. Record reads check the
  small generation head in the same readonly transaction.
- Native keeps the original process queue and OS lock. It flushes changed records,
  index and canonical generation files, then atomically renames a small schema4
  manifest at the original state path. Old readers reject schema4; an in-flight
  old writer's raw CAS no longer matches the manifest. New readers resolve only
  the named generation. Current record/index/canonical files exist before ACK.
- Pre-publication failures leave the prior commit pointer intact. Post-publication
  garbage collection is best effort and cannot turn a committed write into an
  error. Only recognized derived ciphertext filenames are collected, under the
  existing lock. Power-loss durability beyond platform flush/rename is not claimed.
- A new adapter's basic canonical CAS invalidates the derived index atomically.
  The next page rebuilds it; a stale cache is never presented as current.

Corrupt/missing derived records rebuild through canonical CAS. Failed rebuilds
never seed empty state. Missing native manifest with existing generation files,
or missing Web canonical with existing page head, fails closed. Corrupt canonical
and missing device keys require recovery; no destructive automatic reset exists.
Derived cache repair during a save preserves that pending canonical transaction.

## Boundaries

Canonical sync, mutation, password-vault and sync-status ACK flows can still read
the whole account. The sync Presentation projection currently needs saved text
for editor ACK rebasing and can retain ordinary payloads. Removing that text
without a replacement ACK contract would change behavior; it is not disguised
as a completed whole-app O(50) memory optimization. Existing legacy/custom stores
without physical paging retain their fallback read path. No cloud deployment,
whole-app offline asset-bootstrap, iOS runtime or M09 similarity claim is made.

## Verification status

Scoped page/detail/catalog reads are verified on Chrome and Android API35.
Final focused VM30/30, Chrome47/47, scoped analyzer clean; real platform1,000-note
runtime/cold read and preservation proof recorded in STORAGE_VERIFICATION.md.
Historical intermediate failures and their fixes are retained there. Canonical
whole-account boundaries above remain explicit; no whole-app O(50) claim.
