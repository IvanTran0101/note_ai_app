# M04 source/setup handoff

2026-10-05. Approved collaborator A/A/A; implementation on final-tuankiet.
Local and source evidence lives in ACCEPTANCE.md and UI_QA.md. AWS deployment
and registered-user/provider acceptance remain a separate leader task. M09 is
deferred. Incoming partial M03 is03b5326, merged with M02/M05/M06 atcc4dc04.
Product source0919ccf / QA receipt3b789f5: VM1151/2 skips, Chrome956/1 skip,
backend64, dev config14/14, TypeScript and analyzer clean. All18 canonical
M04 rubric criteria have source/local evidence; the remaining checklist below
is for live infrastructure. No confirmed recorded defect remains open.

## Source map

| Responsibility | Source |
| --- | --- |
| Stable IDs, lifecycle,64 Unicode code points/name,32 IDs/note | lib/domain/labels/label.dart, label_membership.dart; lib/domain/notes/note.dart |
| Actor/session use cases and one atomic writer | lib/application/labels/label_application.dart, label_local_write.dart; lib/infrastructure/notes/note_repository.dart |
| Catalog, typed dispatch/ACK/conflicts | lib/application/labels/local_label_state.dart, normalize_label_dispatch.dart, label_local_write.dart; lib/application/sync/label_sync_reconciliation.dart |
| Pure query shared by Notes and Home | lib/application/labels/note_query.dart; lib/presentation/notes/note_ordering.dart |
| Own catalog, scoped chips/filter/manager/chooser | lib/presentation/labels/; lib/presentation/dashboard/ |
| Metadata schema and HTTP transport | lib/infrastructure/labels/label_codec.dart; lib/infrastructure/sync/; lib/infrastructure/security/ |
| Catalog/association/scoped projection backend | amplify/labels/; amplify/sync/handler.ts, dynamo_sync_store.ts |
| JWT routes, table IAM and public outputs | amplify/sync/http_api.ts, sync_function.ts; amplify/backend.ts |
| Public configuration and local runtime | .env.example; tool/m06_dev_config.py, run_m06_local.py; lib/main_dev.dart |

The original plan's repository names were proposed seams. LocalLabelWriter
is the inward port implemented by the existing canonical NoteRepository on the
same cached actor store. This avoids adding a competing native file writer.
Label conflict DTOs/resolver use their own typed namespace, not fake Note IDs.

## Run the local app

From the repository root with Node, Python and Flutter on PATH:

```powershell
python tool/run_m06_local.py
```

Keep that terminal open. Owner: http://127.0.0.1:8776/?devUser=owner;
recipient: http://127.0.0.1:8776/?devUser=recipient. Use isolated browser profiles
for independent sessions. Manage labels is visible on Notes and Home; select
labels to filter by ALL, optionally with a title/body keyword. Labels become
available locally before sync ACK. Only an owner can organize a Note.

For an existing Android emulator:

```powershell
# Terminal1:
python tool/run_m06_local.py --serve-only
# Forward this project's local demo transports to emulator-5554:
adb -s emulator-5554 reverse tcp:8796 tcp:8796
adb -s emulator-5554 reverse tcp:8797 tcp:8797
# Terminal2:
flutter run -d emulator-5554 -t lib/main_dev.dart --dart-define=NOTEFLOW_AUTH_MODE=local
```

Use the existing AVD/data. An ordinary main.dart run does not start these
services or select synthetic sharing actors. Do not reset browser IndexedDB,
emulator app data or output/m06-local state/key to reproduce a sync issue.
The fixture uses actual app/HTTP/socket/use-case flows with synthetic auth,
recipient resolution and a Dynamo SDK double. It sends no recovery email.

## Schema and migration owner

- Inner actor document is schema6. Strict readers migrate supported older
  schema2/3/4/5 shapes, preserving Notes, pin/preferences, pending/attempted
  bytes, conflicts, cursor and attachment descriptors.
- Outer encryption envelope/AAD remains3; existing keys are retained. Catalog
  and memberships share the existing encrypted store. Protected memberships
  are hidden together with content when locked.
- V1 requests already attempted retain their exact wire shape. New label-aware
  traffic uses explicit v2 routes. A migrated v1 cursor bootstraps typed feed
  once; committed contiguous prefixes resume without data reset.
- Label identity/replay is independent of Note identity. Catalog changes do not
  fan out Note text/revision writes. Label creation ACK precedes associated Note
  dispatch even when queue order has coalesced earlier.
- A confirmed tombstone may normalize only NEVER-sent association intent;
  unknown catalog and attempted requests are never silently rewritten.
- Old client Note writes preserve label metadata. New active IDs receive fresh
  same-owner conditional checks inside the Note transaction. Unchanged stale
  IDs allow ordinary text edits/detach.

Future collaborator M03 changes must preserve the schema6 fields and typed
discriminators through every clone, codec, snapshot, ACK/conflict and replay.
Use the same fresh atomic Note writer for attachment link/remove. Do not bump
one schema number independently with a different meaning or clear the outbox.

## Leader backend delivery

Production labels default OFF. main_dev opts into the matching loopback v2
source. Deploy matching backend routes before changing the public Boolean
NOTEFLOW_LABELS_ENABLED=true in the prepared public defines:

| Method | Route | Purpose |
| --- | --- | --- |
| GET | /sync/v2/changes | Typed Note/Label feed and catalog bootstrap |
| POST | /sync/v2/mutations | Label or owned label-aware Note |
| POST | /sync/v2/shared-mutations | Canonical shared text with preserved membership |
| POST | /sync/v2/protected-mutations | Atomic local-first protection change |
| POST | /sync/v2/protection-predecessor | Previously attempted protection predecessor |
| POST | /sync/v2/label-projections | Bounded refresh of already cached readable shared/protected Notes |

All v2 routes are explicitly JWT-authorized in the source HTTP API. Label
records/receipts use LABEL#/LABELMUTATION# in the same table and META#SYNC feed,
separate from NOTE#/MUTATION#. Source sync IAM already lists GetItem/PutItem/
UpdateItem/ConditionCheckItem/Query/TransactWriteItems/DescribeTable on that table
and its indexes; M04 needs no second table or S3 permission. These are source
definitions, not a claim about the deployed role.

amplify/backend.ts publishes custom.syncApiEndpoint, aiApiEndpoint,
eventHttpEndpoint and eventSocketEndpoint alongside generated auth outputs.
Use docs/m06/DEV_SETUP.md and LIVE_GATE.md for the existing credential/public
config workflow. .env may select the owner's backend profile or temporary
credentials; m06_dev_config.py emits only allowlisted public client settings.
Never pass .env directly to Flutter or commit credentials/grants/passwords.

Scoped refresh needs a current independent read grant for protected content.
Its request grants remain transient body fields, never URL/cache/outbox values.
The server checks fresh ACL and protection before and after projection. Ordinary
feed still masks locked/revoked names, IDs and content. Shared Editor has no
catalog/association authority. An implicit owned snapshot is bound only to the
authenticated expected actor, never inferred from a requested foreign owner.

## M03 collaborator continuation

Partial M03 local Pending picker, encrypted binary cache and preview/retry UI
are integrated. Its verified cloud upload/finalize/read/Range and object-link
routes are not completed here. Unavailable cloud retry is intentional and does
not silently drop Pending bytes. Existing attachmentRead/attachmentWrite guards
and canonical AttachmentBinding are the seams; local unlock is not a remote
grant. Backend authorization and current ACL/object/attempt checks remain
mandatory. Continue those routes in M03 and replay this regression before merge.

M04 catalog/rename does not add bytes or filenames to Summary AI inputs.
Association changes conservatively invalidate full Note snapshot comparisons;
catalog rename does not rewrite the Note or start a provider request.

## Reproducible source checks

```powershell
flutter test --no-pub --reporter expanded
flutter analyze --no-pub
$m04TestFiles = @(rg --files amplify | Where-Object { $_ -match '\.test\.ts$' })
node --import tsx --test @m04TestFiles
npm run typecheck
python -m unittest discover -s tool -p test_m06_dev_config.py -v
```

Use the primary D checkout for analyzer. This Windows host also uses R: SUBST
for native short paths; it references the same files. Real UI acceptance must
use the matching source/APK and preserve encrypted state. See ACCEPTANCE.md for
scenario evidence and excluded/unfinished provider gates.

## Live checklist for the leader

- [ ] Inspect intended AWS account/region/stack diff and deployed JWT/CORS/IAM.
- [ ] Deploy the matching v2 source and map public outputs before client opt-in.
- [ ] Test two registered Cognito users: owner catalog, scoped shared names,
  Editor text-only organization denial, role/revoke and old-grant draft fencing.
- [ ] Test protected grant/expiry/replay and final authorization during refresh.
- [ ] Verify real Dynamo conditional races, feed/index gaps and legacy replay.
- [ ] Complete M03 verified object/Range routes under its own acceptance plan.
- [ ] Run M06 live realtime/provider gates and SES recovery where configured.

Unchecked live gates remain unchecked on Notion. Source/local acceptance does
not supply an AWS account, deployment or cloud-provider receipt.
