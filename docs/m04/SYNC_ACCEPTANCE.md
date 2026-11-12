# M04.4 — typed sync and backend acceptance

## Implemented

Label uses its own typed identity/revision/tombstone/replay receipts within the
existing actor outbox/feed/cursor. Never-sent creates can be canceled; only
verified tombstones normalize never-sent Note IDs. Attempted bytes are immutable.
Label dependencies precede Note association. Legacy writes preserve membership;
server conditionally checks newly added owned active IDs at transaction commit.
Empty detach requires an explicit label-aware ACK. Foreign/shared editors cannot
organize labels. Catalog operations never grant Note access or rewrite its text.

Scoped shared/protected label refresh uses fresh ACL and independent M05 read
grants, rechecking protection/access before response. Client rechecks local grant
after HTTP. Recipients receive attached names only; lock/revoke masks IDs/names.
Rename refresh does not bump Note revision or reset a dirty editor. Recipients
refresh on the existing sync path; no new Label-as-Note realtime grant is created.

Production opt-in requires matching explicit /sync/v2 routes before enabling
NOTEFLOW_LABELS_ENABLED. main_dev enables them against the loopback source only.

## Evidence — 2026-10-05

- New Application/query/HTTP tests26/26 PASS (query acceptance belongs M04.5).
- Backend sync/sharing/protection/attachment/Label regression51 Node test nodes
  PASS; individual script checks are not added to this number.
- Label backend12/12 PASS, included in backend total: ID namespaces/replay,
  schema/legacy preservation, association race, rename, revoke, scoped privacy
  and protected shared read grants.
- Backend TypeScript typecheck clean.
- Actual Chrome/Android and final full regression are still running; no live AWS
  deployment or completion of the collaborator's remaining M03 cloud is claimed.
