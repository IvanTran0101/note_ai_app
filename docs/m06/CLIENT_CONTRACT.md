# M06.3 client checkpoint

Shared notes remain canonical owner/note pairs in the encrypted actor store.
Owned and Shared With Me lists are separate; selection, status, conflicts,
password grants, Summary lineage and HTTP shared updates preserve that pair.

Viewer can read and summarize; editor can change title/content. Neither can
delete, export, change protection or administer recipients. The current local
share governs offline writes; the server independently checks every operation.
Owner sharing administration requires a synced note and server confirmation.
Uncertain transport retry reuses its original request ID/command. No local
optimistic ACL, email directory, raw password or persistent unlock grant exists.

The editor saves both fields in one local compare-and-save/outbox operation.
The comparison includes the captured server revision, original local fields,
timestamp, share epoch and protection. A remote/local concurrent writer causes
explicit cloud/local review; automatic refresh preserves dirty text/selection.
Access loss takes precedence, clears private UI/Summary and retains unsaved
editor evidence encrypted, without creating an unauthorized mutation. Received
note removal never deletes the owner's note or an owned note with the same ID.

Acceptance on 2026-10-02: 56 scenarios in real Chrome and Android emulator,
including IndexedDB/platform secure storage, UI, retry, atomic concurrency,
encrypted draft reopen, access-first blocking and legacy ciphertext bindings.
VM scoped regressions 408 (+1 skip), and final editor/UI/repository147 passed.
Backend M06.2 remains 75 checks accepted at 08809ed; no live AWS deployment or
AppSync success is claimed. Realtime relay/session transport is M06.4.

A stale existing Web output contained only the prior40 scenarios and was
excluded. Fresh acceptance outputs used unique build directories/defines; the
Flutter request_data result was true with an empty failureDetails array.
Logs stay in TEMP and ignored output/; no synthetic/user records are committed.
