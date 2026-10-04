# M04.7 — integrated acceptance

2026-10-05, final-tuankiet. Source0919ccf includes M03 partial03b5326, the existing
M02/M05/M06 core and the approved M04 A/A/A implementation. This receipt describes
source tests and actual Chrome/Android flows against the matching local fixture.
It does not certify a deployed AWS backend or the unfinished M03 cloud routes.

## Fresh regression

| Check | Result | Ignored evidence |
| --- | --- | --- |
| Full VM suite | 1151 PASS,2 configured skips,0 failures | output/m04-integration/m04-final-regression-v3.log |
| Chrome107 compatible original targets | 956 PASS,1 configured skip,0 failures | m04-chrome-app-final.log (275), m04-chrome-storage-final.log (387/1), m04-chrome-ui-final.log (294) |
| Final analyzer | No issues,142.1s | m04-final-analyze-v3.log |
| All backend test files | 64 Node test nodes PASS,0 failures | m04-backend-final-v3.log |
| Backend TypeScript | typecheck clean | m04-typecheck-final-v3.log |
| Public dev configuration | 14/14 PASS | m04-config-final-v3.log |
| New HTTP owner regression + general adapter | 39/39 PASS, included in VM | m04-owned-projection-after.log |
| Shared label/pending regression | 98/98 focused PASS, included in VM | m04-shared-refresh-after.log |
| Android source0919ccf APK | build51.7s, install-r/cold reopen/actual query PASS; HEAD unchanged | m04-apk-0919ccf.log |

The two VM skips are the unconfigured real-model smoke and browser-only
IndexedDB target. Chrome exercised the real IndexedDB platform and encrypted
Web storage tests; its only skip is the unconfigured model smoke. The browser
groups use the existing isolated tools overlay for the SDK Windows URI issue,
without editing the installed SDK or product/compiler/browser implementation.
Browser-specific acceptance is recorded separately below;
source/platform/doubles are not counted as independent live AWS evidence.
Focused historical subsets are included where noted, not added to the full VM.

## Verification matrix

| Plan | Evidence and accepted behavior |
| --- | --- |
| V01 query/order | note_query_test + dashboard/ordering widgets: title OR body, Vietnamese lowercase without accent folding, empty/ALL, owner/ID collisions, pin/date ties. Actual Notes/Home list/grid filtering and Chrome keyboard search; no HTTP request per key. |
| V02 CRUD/atomic | Domain Label and label_application_test: duplicate names, stable IDs, no-op/tombstone/limits, fresh association/delete races and metadata preservation. Actual duplicate, rename, delete, attach/detach and chip propagation on Chrome/Android. |
| V03 actor/writers | Session/store/repository/privacy widgets cover late work, actor changes and one fresh atomic writer across M02/M03/M04. Actual isolated owner/recipient profiles and native cached actor data; unrelated catalog stays hidden. |
| V04 typed intent | label_sync_test/label_dispatch_test and coordinator tests: same-string Note/Label IDs, create prerequisites, later ACK/edits, lost ACK/definitive repair, immutable attempted bytes, unrelated entity continuation. |
| V05 compatibility | Schema codecs/security/store + backend parser/cursor/feed tests: legacy metadata absent versus empty, migration2–5→6, envelope/AAD3 retained, cursor bootstrap and contiguous gaps; pin/attachments/preferences/drafts preserved. |
| V06 server denial | labels.test.ts, security/local-first backend tests: foreign/deleted newly added IDs denied at commit; unchanged stale IDs allowed for text/detach; scoped ACL/read-grant/final revoke checks. Name uniqueness race is inapplicable: duplicates were approved. |
| V07 cache/offline | Catalog loading/error/unknown/tombstone and dirty editor widgets; actual Chrome offline text/association edits and Android cold offline query/filter/association/Pending file retention, followed by reconnect. |
| V08 Summary | Full DTO/snapshot/Summary guard tests preserve membership and fences; association changes invalidate snapshots conservatively; rename does not rewrite Note revision or AI input. No real provider invocation implied. |

## Actual browser and emulator

- Chrome owner and recipient are separate persistent headed browser profiles;
  Android is emulator-5554, com.example.note_ai_app, existing app data retained.
  The loopback fixture uses production flows with synthetic auth/Dynamo double.
- Both clients created labels. Duplicate names remained distinct choices;
  associated rename propagated to filters/chips. Deleting an associated label
  preserved Note body/pin and pruned confirmed selected tombstones.
- Notes and Home list/grid combined a body keyword with ALL labels. One label
  matched; adding an unassociated label gave No matching notes. Chrome physical
  keyboard search reached the matching Note and the filtered empty state without
  a network request. A bounded53-pixel semantic input rectangle is now tested.
- Native M03 picker survived its lifecycle pause, retained a58-byte Pending text
  attachment and opened its real preview. Retry clearly reported cloud unavailable
  under the partial M03 contract. Offline reopen retained bytes and descriptor.
- Chrome offline text/association writes saved locally. Android disabled wifi/data
  AND removed both ADB loopback forwards, attached a label to an existing cached
  synthetic Note, stopped/reopened the app, then keyword+selected-label filtering
  returned that Note with its chip and1 durable pending change. Restored network
  and Retry reached All synced; Chrome received the same chip without a reload.
- A new synthetic labeled Note was protected online on Android, locked without
  exposing title/body/chip, reopened cold offline, rejected a wrong password and
  accepted the correct cached unlock. An encrypted offline edit survived and
  online scoped unlock/reconnect kept the updated body and label. The final APK
  reached All synced after manual refresh, fixing the owner projection defect.
- Recipient only received attached readable shared names; unrelated owner catalog
  was hidden. Shared Editor had no Note label chooser or protection/attachment
  owner tools. Offline draft was retained encrypted on revoke; title/body/chip
  became unavailable. Regrant as Viewer showed cloud text and did not replay the
  old grant's draft. The corrected access-retained copy has a widget regression.
- Final source0919ccf recipient refresh returned HTTP200 with one readable
  Viewer projection. Filter and list/detail chips now show that label; current
  cloud text remains displayed, blocked old-grant pending count stays1, and no
  organize control appears. Selecting the scoped label returns only that Note.
- Final native source0919ccf APK retained pin/protected masking/catalog and the
 58-byte Pending attachment after install-r/cold reopen. Physical keyboard body
  query plus selected label returned the matching cached Note with All synced.

## Confirmed fixes and excluded attempts

1. M03 native picker pause prematurely invalidated unprotected attachment binding:
   fresh actor/session/resource/content/access fences now preserve that flow.
2. Filtered empty results used first-note onboarding copy: separate localized
   No matching notes copy now applies.
3. Manual/partial failed sync did not notify catalog views: coordinator terminal
   notifications use the captured actor/session; deleted chips refresh in place.
4. Query/filter state and defensive catalog owner checks now clear on actor change.
5. Search accessibility rectangle inherited the entire Notes area: bounded
   semantics now gives the input its own geometry and accessible name.
6. Revoked unprotected draft copy incorrectly referred to a password state:
   access-lost copy is distinguished and covered independently.
7. Protected owned refresh incorrectly required an explicit wire ownerId:
   bind the implicit owner to expected authenticated actor only. The new test
   reproduced forbidden before the fix; an explicit foreign owner remains denied.
8. Shared label metadata was suppressed behind an old-grant blocked draft when
   the owner changed association and advanced the Note revision. Fresh currently
   readable shared metadata now refreshes independently while retaining body/base
   revision and pending bytes. Label/sync98/98 PASS includes Viewer blocked draft,
   current Editor draft and older snapshot rejection. Actual recipient retest
   restored filter/list/detail chips with old draft blocked and cloud body intact.

Cold server reload replaced old Flutter DDC pages after development restarts;
disposed-view/duplicate-module/stale UI-reference events are excluded. Browser
accessibility text can lag rendered groups: fresh role snapshots/screenshots
were checked. Input only placed in a DOM proxy is not accepted as a Note edit.
Interrupted old Gradle builds are not final APK evidence; native asset rebuild
completed on the final tested source without changing the local LLM module.

## Rubric and limits

ORG-FR01–10, NFR01–04 and all4 Done When conditions have source/local and the
actual UI evidence above. Tick them with this scope on Notion. M04.8 source/setup
handoff is HANDOFF.md; final deployment gates remain unchecked.

- Native password administration remains the original online M05 flow. Web
  enable/change/disable is local-first; native cached offline unlock/edit passed.
- Loaded Web app offline behavior passed. Cold offline PWA shell installation
  was not verified. Native app cold offline persistence was verified.
- Real Cognito/AWS IAM/Dynamo races/AppSync events, SES recovery, real model/cloud
  Summary invocation and M03 verified upload/read/Range need their own live gates.
- Existing M02 CRUD/pin/dirty review/access/diagnostics/logout QA remains in
  docs/m06/UI_QA.md. This integrated full regression covers its source behavior;
  M04 actual runs added organization/protection/share/attachment intersections.
- No M09 UI redesign, AWS deployment, user data reset or provider key was used.

No confirmed defect remains open in the scenarios recorded here. This is a
bounded acceptance receipt, not a claim that every device/provider/timing is
bug-free. Artifacts and profiles contain only the synthetic QA flow and are
ignored; no local logs, APKs, keys or user content are included in the commit.
