# M04.3 — local catalog and writer acceptance

Approved A/A/A is implemented in the local core: catalog lifecycle, typed outbox,
atomic fresh Note association and schema6 migration. This milestone ships the
inward typed sync seams and reconciliation needed to preserve full metadata.
HTTP/runtime/backend wiring and Presentation remain M04.4–M04.6 work.

## Fresh evidence (2026-10-04)

- Core local regression:325 PASS,1 configured platform skip.
- Label use cases and typed coordinator:13/13 PASS (included in core total).
- M05 crypto/M03 binary/local-first regression:12/12 PASS, separate suite.
- Core Dart analyzer: no issues.
- Migration fixtures now describe the actual published older formats. Decoder
  remains strict; attempted IDs/payloads, cursor, pin, preferences and conflicts
  survive. Wire bootstrap marker starts at1 for migrated data.
- Catalog ciphertext, masked protected membership, unlock/reopen restoration
  and binary descriptor retention are covered by the crypto suite.
- Labels share the existing cached actor store and update transaction; session,
  fresh active catalog validation and failed durability cannot create access.

Actual Chrome/Android acceptance and full final regression remain pending.
Production v2 is enabled only after the matching backend rollout; old calls keep
their immutable v1 request shape. AWS live deployment is outside this batch.
