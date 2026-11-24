# M04.6 access and privacy acceptance

2026-10-05, source/local fixture; M04.5 source827285e.

Labels use the existing canonical NoteAccessPolicy/security boundaries. Owner
catalog is actor-scoped; only owner can attach/detach or manage organization.
HTTP scoped resolver performs fresh ACL before content/association projection
and final fresh ACL/protection/share/grant checks before release. Protected read
grants stay transient in request body; no full owner catalog is sent to a share
recipient. Ordinary feed and locked/revoked DTOs mask Label IDs/names. UI query,
chips and counts consume only currently readable projections.

## Fresh evidence

- Entire VM suite1145 PASS/2 configured skips at827285e; backend51 Node test
  nodes and tsc clean from M04.4, including scoped denial/final revoke tests.
- Source query tests cover locked/revoked keyword/filter exclusion, unrelated
  sanitized projection rejection and current-name resolution.
- Actual Chrome isolated recipient profile saw only QA-M04-Renamed attached to
  the shared QA Note; both unrelated duplicate QA-M04-Web catalog rows stayed
  hidden. Shared Editor showed chip/body but no Choose note labels, catalog
  management, attachment owner tools or protection administration.
- Recipient typed a synthetic encrypted local draft offline. Owner revoked the
  synthetic grant using Manage sharing. Reconnect detected revoke, immediately
  replaced title/body/chip with Note unavailable and retained-encrypted-draft
  notice. No private label remained on the unavailable detail surface.
- New native APK at827285e installed with data preserved and restored catalog
  names/body/Pending file. Final protected lock/unlock and projection refresh UI
  checks continue in UI_QA.md before ticking overall actual QA.

This milestone is source/local privacy acceptance. Final UI regression and AWS
registered-user/deployment gates have their own receipts.
