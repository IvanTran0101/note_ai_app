# M06.2 server contract and evidence

Backend source acceptance 2026-10-02: 75/75 backend checks (11 new sharing,
64 existing M05/sync/Summary), TypeScript typecheck and diff whitespace check pass.
SDK doubles evaluate conditional transactions; Cognito response doubles exercise
verified-recipient lookup. These are local tests, not deployed AWS acceptance.

## Transport

- GET /notes/{id}/shares?ownerId={canonicalOwner} lists ACL records for owner.
- POST same path accepts requestId, action create/role/revoke, role viewer/editor,
  expectedAccessRevision, and email for create OR recipientId for role/revoke.
- JWT actor, current owner authority and M05 manage grant are independent of body.
- POST /sync/shared-mutations requires ownerId/accessRevision and update only.
  It never falls back to the owned route. Older backend returns 404, preventing
  accidental writes under the recipient namespace. Owned routes reject these
  shared fields; existing owned mutation fingerprints/IDs remain compatible.
- Content/protection paths carry canonical owner in the existing ownerId query;
  recipients obtain their own grant. Summary context adds accessRevision only for
  shared notes; owned legacy context remains compatible.

## Durable authority

ACL is read consistently and pinned in each editor/output transaction. Note
sharingRevision separately guards membership changes while building fanout; every
canonical content write preserves it. Receipt namespace is actor + canonical pair;
lost ACK replay rechecks role and original access epoch. Share admin receipt returns
current ACL on replay, so an old success cannot restore a revoked role.

One actor cursor contains owned and received changes. Share/revoke/role seeds a
feed record without altering content revision. Historical rows are projected
against current ACL/protection; revoke sends only removal metadata, not an owner
tombstone. Protection changes fan out and invalidate grants for all actors.

Feed/canonical/ACL/receipt and metadata-only EVENT intent commit together. M06.4
will wire the relay; no external publication occurs in this checkpoint.

## Bounded fanout

20 active recipients per note keeps the atomic transaction below DynamoDB's
100-item cap (two feed writes per actor plus canonical/ACL/receipt/authority/event).
Queries paginate all ACL history; no silent truncation. Further scale requires a
separate durable fanout design, not raising this bound blindly.

## Remaining acceptance

M06.3 UI/HTTP mappings/encrypted offline and M06.4 relay/subscription are pending.
Real Chrome/Android end-to-end tests and live AppSync/Cognito spike are distinct
gates. No functional rubric is ticked from these backend-only tests alone.
