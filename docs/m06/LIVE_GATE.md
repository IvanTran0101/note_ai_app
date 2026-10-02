# M06 live AWS acceptance gate

Local acceptance uses real Chrome/Android clients and storage, production HTTP,
ACL and relay code, and synthetic credentials/SDK doubles. It does not prove
deployed Cognito, API Gateway, DynamoDB Streams/GSI, IAM or AppSync behavior.
No deployment has occurred. M09 remains deferred.

## Concrete deployment changes to review

The source checkpoint315caf4 adds:

- Existing notes table: NEW_IMAGE stream and sparse PendingRelays GSI. Preserve
  all note, ACL, feed, cursor and receipt data; no table replacement or reset.
- One AppSync Events API with the existing Cognito pool/client. Cognito connects
  and subscribes; only IAM publishes. The notes namespace permits exactly the
  current subject's channel and rejects foreign/wildcard subscriptions.
- One Node22 relay Lambda: namespace-scoped EventPublish, GetItem/UpdateItem and
  the PendingRelays Query. EVENT INSERT stream trigger, conditional lease,
  metadata-only delivery and scheduled minute recovery share the same relay.
- HTTP event and realtime socket custom outputs. Deploy the accepted M05/M06
  shared/protected HTTP routes and Summary authorization alongside the relay.

Run `npx tsx tool/m06_cloud_review.ts` for a concrete local CloudFormation
resource template in output/m06-cloud-review/realtime.template.json. It uses a
fictional account/pool, makes no AWS call and is not a diff against the real stack.

Before any deployment, select the actual AWS account, region and existing stack,
capture its CloudFormation diff and confirm that it preserves the table. No AWS
profile/credentials were found in the local default config during acceptance;
do not guess a target account or create credentials. MUST_REMEMBER.md requires
separate deployment authorization; source/push authorization is already granted.

Legacy EVENT rows without relayQueue/relayDueAt need an explicitly reviewed,
bounded backfill if they must be delivered. Never auto-scan/reset/backfill notes.

## Required evidence after approved deployment

- [ ] Two real registered, verified Cognito accounts: owner/email share; editor
  can edit; viewer direct API writes fail. Unknown/unverified/self/duplicate
  email cases fail without exposing a directory or changing existing grants.
- [ ] Own-sub AppSync subscription succeeds. Foreign/wildcard/anonymous
  subscriptions and client publication fail under the deployed auth modes.
- [ ] Chrome + Android see committed edits without refresh/reopen. Disconnect,
  token expiry/resume and a dropped notification recover via the saved cursor.
- [ ] A post-commit publication failure is retried by the durable relay; lost
  ACK duplicates remain harmless. GSI visibility lag cannot advance past a gap.
- [ ] Downgrade/revoke reaches the active recipient. Direct/replayed/stale-epoch
  writes fail; content/Summary clears while encrypted drafts survive locally.
- [ ] Protected recipient needs their own password grant. Owner grants, stale
  protection epochs and revoked access fail on content, replay and Summary.

Retain sanitized results, revisions and success/failure classes only. Never
record passwords, tokens, unlock grants, note bodies or provider credentials.

## Separate collaborator integration

M03 attachment access/cache and other collaborator routes still need their own
integration regression after both collaborators finish. Pull their work together
only at that requested checkpoint, test all functions, then replan M09 UI/UX.
