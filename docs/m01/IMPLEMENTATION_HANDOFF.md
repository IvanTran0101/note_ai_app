# Module 01 — implementation handoff (09/10/2026)

## Current gate

| Slice | Status | Evidence |
| --- | --- | --- |
| M01.1 | Source/mock PASS; sandbox deployed | Profile routes, self-only access JWT, CAS, replay fingerprint, clock expiry, stable version-pinned avatar; 28 related backend tests and typecheck |
| M01.2 | PASS source + real Web signup/profile initialization | Shared HTTP repository replaces Web stub in production Cognito composition; partial profile-setup result; SDK/actor/generation fences; actual signup → auto-login → canonical name |
| M01.3 | PASS source/mock + real Web/Native cloud slice | HTTPS Web pick → PNG metadata stripping → signed S3 staging → exact version/checksum verification → CAS association → authenticated MemoryImage, Saved visible |
| M01.4 | PASS source/mock + Web reload + Native disk/root recreation | Existing account-local encrypted preferences, serialized theme/layout writes, generation fences, preserve notes/outbox/font/color/layout |
| M01.5 | Open | Web verification and user-completed reset → manual login PASS; change-password, Native auth matrix and OS cold restart remain open |

279 tests in 18 explicit VM files; 86 Chrome tests with one filesystem-photo fixture skipped on Chrome (tested on VM); 28 Profile/affected-sync/storage backend tests. Analyzer and backend typecheck PASS. Root/router/shell follow-up: 34 tests PASS; hydration/root/theme follow-up: 14 tests PASS. Latest analyzer PASS (8.6s). Full >900-file test suite was not run. No commit/push. No application Summary/RAG generation.

## Run the reviewed staging app

From the repository root:

```sh
flutter build web --release --dart-define-from-file=output/aws-smoke/dart-defines.json
python3 tool/serve_https_web.py --cert output/m01/https/localhost.pem --key output/m01/https/localhost-key.pem --port 8782
```

Open https://localhost:8782 → Settings → Profile. For a clean machine, use a trusted local development certificate first; do not bypass certificate warnings. `mkcert` certificates/private keys are ignored under output/m01/https; the installed development CA was reused, not replaced.

Public Cognito/Sync outputs are in output/aws-smoke/amplify_outputs.json and dart-defines.json. They contain no provider key. Deployment target remains noteflow-dev / ap-southeast-1 / noteflow-smoke. Exact upload origin https://localhost:8782 is configured on the existing bucket. The S3 bucket and DynamoDB table physical IDs were verified unchanged after UPDATE_COMPLETE. No new Lambda/table/bucket or public hosting was created.

## Behavior and compatibility

1. Profile/Avatar canonical data lives in existing AWS resources, shared by Web and Native. Refresh on login/restore/open/resume/save; unsaved name drafts retain their loaded revision until explicit reload. No Profile realtime or offline outbox.
2. Names trim to 1–100 Unicode code points. Input PNG/JPEG <=1MiB, each edge <=2048. Flutter decodes/re-encodes PNG to strip original metadata; the server checks bounded headers/container/checksum and exact object versions. Failed/canceled replacement keeps the old association.
3. Metadata uses revision CAS, stable request IDs and payload fingerprints. Missing canonical Profile and missing Avatar have distinct envelopes; unknown 404 cannot create phantom setup. Avatar requires explicit name setup first. Pending intents/intent requests expire after one hour independently of DynamoDB TTL lag; profile-write replay rows last24h. Profile rows never expire.
4. Theme is per account/device in the existing preferences envelope. It preserves layout/font/color/notes/outbox/cursor/conflicts. Profile cloud failure leaves cached notes usable. Legacy native Profile JSON remains untouched; it is never auto-imported over AWS canonical records.
5. Auth-success/Profile-failure returns setup-pending and keeps login usable. Retrying setup does not call signup again. SDK Hub epochs and final provider identity checks prevent stale signup/account results; the unverified warning is shown on Home and Profile until verification; the actual Web warning cleared after verification.

## Actual acceptance receipt

- Web signup → auto-login → canonical name → private avatar upload/read PASS. The browser JPEG fixture was decoded/re-encoded to PNG before upload.
- iOS Simulator production main/Cognito/Profile/S3 integration PASS: read the Web name/avatar, write Native name/avatar; Web then displayed the Native profile. Latest live integration: one test PASS in18s after21.6s Xcode build.
- Theme Dark survived actual Web reload. Native encrypted preferences survived a fresh repository read and production composition-root recreation with SDK session restore. This is not an OS-process cold-restart receipt.
- Web verification completed with a human-supplied code; Home/Profile warning cleared. Reset email was requested; the human entered/submitted the new credential; the browser returned to login and then authenticated workspace. No password or OTP is recorded here.
- Source evidence: output/m01/acceptance-receipt.json. Screenshot: output/m01/verified-profile.png. Private runtime credential fixtures were removed after Native testing; the main-email account and all notes remain intact.

## Next manual acceptance

The browser is prepared at https://localhost:8782/#/settings/change-password with empty credential fields. The human must enter the current/new/confirmation password and submit; no new credential is entered by the agent. Reset and subsequent manual login are already verified on Web.

## Remaining acceptance limits

- Full M01.5 remains open: actual change-password and Native verification/reset/account-isolation/OS-process cold-restart matrix have not all been completed. Focused mocks do not replace those platform receipts.
- macOS build needs its development provisioning profile. Automatic approval review rejected -allowProvisioningUpdates because external Apple team signing/provisioning mutation was not explicitly approved; no signing settings or Apple assets were changed. iOS Simulator is the safer Native test lane.
- Existing main-email account/password were preserved. A separate Gmail +tag account is used for testing; it delivers to the same mailbox ([Google](https://gmail.googleblog.com/2008/03/2-hidden-ways-to-get-more-from-your.html)). No test password, token, OTP or real photo is written to this document or receipts.
- Avatar final versions remain private in S3 after replace/clear; reference-safe final-object GC, cloud preferences, crop/camera, shared/public profile directory and full release are outside this batch.
- AWS $5 remains a manual staging threshold, not a hard cap. Pre-update Cost Explorer was estimated/account-wide and approximately0USD; it cannot certify final staging spend.

## Worker receipt

Three DeepSeek implementation lanes were requested and used. HTTP/Application completed through the connector. UI/theme timed out after20min and its partial files were preserved and finished/reviewed by the control plane. Backend connector lost transport; the third lane completed with the same local DeepSeek Harness headless CLI. Control review corrected Web codec incompatibility, real DynamoDB expression validity, Unicode counting, replay binding/expiry, exact final-version verification and router refresh before deployment.
