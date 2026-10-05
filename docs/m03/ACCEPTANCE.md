# M03 — integrated source/local acceptance

2026-10-06, final-tuankiet. Product source47f7ad5 includes M02/M04/M05/M06 and
the completed attachment flows. Final regression at29e8e60 passed; no product
source differs from47f7ad5, the matching APK used for actual native QA.
M03.8 source/local is accepted. M03.9 publication and final HEAD artifact refresh
follow separately. Leader AWS live acceptance remains an external gate.

## Final regression

| Check | Current receipt | Ignored evidence under output/m04-integration |
| --- | --- | --- |
| Full VM | 1213 PASS,4 configured skips,0 failures;170.1s | m03-final-vm.log |
| Chrome127 compatible original targets | 1075 PASS,1 configured skip,0 failures;353 application/domain,412 storage/sharing,310 UI | m03-final-chrome-*.log |
| All15 backend files | 87 PASS,0 failures;30.0s runner/20.3s Node | m03-final-backend.log |
| TypeScript | Clean;20.0s runner | m03-final-tsc.log |
| Public dev configuration | 14/14 PASS;0.320s test/10.0s runner | m03-final-dev-config.log |
| Full analyzer | No issues;140.2s analyzer/150.1s runner | m03-final-analyze.log |
| Matching product47 native APK/UI | Build29.3s,sourceDirty=false; actual pickers/protection/PDF/large/offline/cold/reconnect PASS | m03-47f7-apk-provenance.json; UI_QA.md |
| Final HEAD artifact refresh | Post-publication exact revision/hash/install-r smoke recorded in local JSON and Notion progress | m03-final-apk-provenance.json |

VM skips: two attachment browser IndexedDB cases, one existing Web-store case
and the unconfigured real-model smoke. Chrome runs real IndexedDB and canonical
encrypted Web storage; its real-model smoke stays unconfigured. Focused and
historical suites overlap with these totals and are not added to them. The
Chrome runner isolates Windows SDK test-server URL fixes without editing the
installed SDK. Native FFI adapters run in VM/native, not browser stubs.

## Plan verification

| Plan | Accepted source/local evidence and limits |
| --- | --- |
| V01 pick/open/cancel | Actual Chrome multiple image/video/file selection; Android Documents/Gallery/Photo/Record video. Native cancel and camera denial return safely with no draft; portable Web cancellation widgets are separate from actual browser chooser evidence. |
| V02 validation/bypass | Native fake-MIME and21MiB TXT show clear rejection; Web invalid selections retain existing file and oversize advice. Backend verifies actual bytes/type/size/checksum independently of client metadata. |
| V03 fresh atomic writer | Domain/application/canonical transaction regressions cover concurrent text/link/remove, tombstone and delete/upload races; actual remove preserves body and reaches All synced. |
| V04 local/reopen/session | Real Chrome IndexedDB encrypted chunks/reopen/concurrent quota; actual native offline new-note multi-select before create ACK, cold reopen, image/video and reconnect Ready. Session and same-user relogin fences tested. |
| V05 recovery | Stable attempt, lost verify/link ACK, cancel/finalize/remove retry, absent staging renewal and transient storage ACK retention tested. Actual Web interrupted upload retains draft and explicit retry reaches one Ready. |
| V06 compatibility | Schema6/envelopeAAD3, typed attachment-only and empty-unlink routing; legacy metadata preservation, later ACK and explicit Pending conflict-copy binding tested. Actual Web/native receive the same8-file protected manifest. |
| V07 authorization/key/cache | Backend fresh ACL/own exact M05 grant/object binding tests; actual protected owner export, Viewer/Editor read-only WebP, active role/revoke mask and lock. Web offline rotate/disable/enable preserves cached pixels and later sync; native online admin/offline cached unlock tested. |
| V08 Range/seek/revoke | Actual Chrome/native40s video Play/seek, Chrome authenticated206 ranges <=262144bytes and direct unauthenticated401. Actual active shared WebP revoke closes preview; per-request video Range revoke covered by source/backend tests. A single combined shared-video seek/revoke UI run is not claimed. Previously delivered bytes cannot be recalled; subsequent requests reauthorize. |
| V09 immutable object/cleanup | Backend pinned staging expiry/reuse/overwrite, immutable final versions, CAS association/unlink and reference-safe cleanup tests. Actual previews/export use guarded readers; no signed GET or private persistent plaintext viewer cache. |
| V10 large/progress/memory | Actual28,511,765byte MP4 on Chrome/native plays/seeks/exports with exact original SHA256. Chrome numeric upload/download progress, interruption and retry recorded. JS heap and native PSS/RSS samples are debug samples, not full-process peak/leak proof; bounded plaintext chunks have separate source/test evidence. |
| V11 Summary | Full integrated snapshot/session/mapping tests preserve pin/labels/attachments/protection/sharing; no bytes/filename/preview added to AI inputs. No real provider/model invocation implied. |

## Actual UI receipts

Detailed chronological receipts and screenshots are in UI_QA.md and ignored
output/playwright/m03-20261005 and output/playwright/qa-20261004. Both headed
Chrome and Android emulator use the real app UI/writer/cache/transport against
production backend use cases with synthetic identity/Dynamo and encrypted local
objects. No app database was seeded or reset for these UI flows.

- Owner protected TXT export75bytes on both platforms:
  SHA2569D467DD58D9B40F0D2246CCC21E5660158DED08AC95F4122DB0962E63714FCF0.
- Large MP4 export28,511,765bytes on both platforms:
  SHA25639E568A52EF3FA09AD1A5BE83E4616CA32B9BD635720A6F26F331896FF3C7F8E.
- Web interrupted upload at22020096/28511765bytes -> Retry needed -> one Ready;
  interrupted download at262144bytes -> canceled -> full checksum-correct retry.
- Native protected PDF Next paints Page2, reaches Page3 boundary, Previous works;
  Lock removes the active document. Android camera H264/AMR is normalized to
  H264/AAC using owned bounded scratch; actual Ready/export/play/seek passed.
- Web offline password05->06, Lock/Unlock06 and cached WebP; Disable06/Enable05
  persist locally, canonical reconnect drains predecessor operations, fresh05
  online unlock gives8 Ready/All synced. Native cached offline unlock and online
  rotate/disable were tested; native offline password administration is outside
  the existing Web-only local-first administration composition.

## Defects fixed and retested

| Commit | Confirmed fix |
| --- | --- |
| 2d2e302 | Debug composition staging PUT, inaccessible dismiss semantics and Web HTML-fallback export (3 defects). |
| d45e02a | Attachment-only typed route, explicit historical protection rejection recovery, initial/predecessor owner export scopes (3 defects). |
| 71a2795 | Runtime export-operation whitelist (owner only). |
| 29516d7 | Normal pre-create ACK waiting reported as file/quota error. |
| e0411dc | Native picker failure feedback lost after lifecycle pause. |
| 2ec1abf | Android camera AMR audio rejected by settled H264/AAC policy. |
| 47f7ad5 | Native PDF page navigation competing with editor scrolling. |

Eleven confirmed product defects were fixed. SDK URL/CanvasKit loading, CLI
modal/locator mistakes and fake-clock fixtures are harness issues. Old owned
Chrome profile crashes on any download, including public TXT outside the app;
fresh-profile actual export passes. The old profile/data/drafts were preserved.
Web chooser Cancel through CLI is not claimed: its upload command requires a
nonempty list; actual native cancellation and Chrome widget tests are separate.

## Remaining external acceptance

DEV_SETUP.md and HANDOFF.md list actual-account S3/IAM/Cognito/CORS/deployment
checks. Local fixture or source tests cannot tick those leader live gates.
M09 remains deferred. These receipts establish the listed scenarios, not a
guarantee that every possible platform/provider failure has been eliminated.

## Closure receipt

M03.8 regression/UI accepted; M03.9 publication remains next. _agent_ops/ is absent in this checkout;
CURRENT_WORK.md is the active continuity record and PROGRESS.md the milestone
record. No unavailable pack records or named teams are claimed.
