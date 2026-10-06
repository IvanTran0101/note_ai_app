# M03 — collaborator and leader handoff

2026-10-06, final-tuankiet. Product source47f7ad5 completes the integrated
attachment flows; final full regression passed at29e8e60 and was published in
8b04637. ACCEPTANCE.md records1213 VM/1075 Chrome/87 backend passes, configured
skips, clean static checks and actual UI evidence. M03.1–9 source/local delivery
is accepted; final post-publication APK/native receipt is recorded on the Notion
progress page and ignored output/m04-integration/m03-final-apk-provenance.json.
M02/M04/M05/M06 remain composed through the same canonical store,
writer/outbox/cursor. M09 is deferred. Prior foundation-only handoff descriptions
are historical and do not describe this completed source.

## Run locally

```powershell
python tool/run_m06_local.py
```

Owner: http://127.0.0.1:8776/?devUser=owner. Recipient in an isolated browser
profile: http://127.0.0.1:8776/?devUser=recipient. Use recipient@example.invalid
for the synthetic recipient. Retain output/m06-local encrypted state/keys and
browser/app data. Plain flutter run -d chrome does not start this backend.
See DEV_SETUP.md and docs/m06/DEV_SETUP.md for Android reverse8796/8797,
main_dev.dart debugAPK, SDK D:/tools/AndroidSdk and R: SUBST native build.
Local actors are fixtures, not Cognito accounts or AWS credentials.

## Settled shared contract

- JPG/PNG/WebP10MiB; MP4 H264/AAC50MiB; PDF/TXT/CSV20MiB.10 files/100MiB per
  Note; encrypted cache250MiB/actor; plaintext transport chunks256KiB.
- Encrypt/stage locally before network, await Note-create ACK before upload,
  stable durable attempt, Ready only after verified immutable association ACK.
  Keep frozen attempted payloads and encrypted drafts through interruption.
- Inner schema6/envelopeAAD3; optional binaryKeys fifth packet field accepts the
  existing4-field packet. Coordinate backend/client rollout; no downgrade that
  erases unsupported metadata/keys. Typed wirev2 handles attachments OR labels,
  including empty unlink; legacy text writes preserve manifest metadata.
- Canonical owner adds/removes/exports. Viewer/Editor can internally read a
  currently permitted shared attachment, without attachmentWrite/export.
  M05 attachmentRead/attachmentWrite/export grants are separate operations;
  local unlock is not remote authorization. Server checks fresh JWT/ACL/epoch,
  Note/attempt/object binding before work and again before releasing reads.
- Stable random binary DEK is rewrapped atomically with M05 password changes;
  migrate old chunk AAD before retiring its key. Lock/revoke/session change
  invalidates reader/preview capability; blocked ciphertext is retained for
  explicit recovery, without device-key fallback or silent old-grant replay.
- Authenticated bounded Range, no signed GET. Previously delivered bytes cannot
  be recalled; next request must reauthorize. Export is an explicit owner action.
  Web private chunks stay encrypted in IDB; viewer assets alone may be cached.
- Durable removal intent precedes the canonical writer; unlink/tombstone ACK
  precedes cancellation/cleanup. Keep referenced/ambiguous objects safely.
  Filename is metadata, never a storage path or Summary input.

CONTRACT.md defines attempts, quotas, version pins and key compatibility;
MEDIA.md defines platform readers, cancellation/export and camera normalization.
The existing Summary snapshot/session rules remain intact.

## Reproduce source checks

```powershell
flutter test --no-pub --reporter expanded
python tool/run_chrome_tests.py --sdk C:/Users/meow/flutter --aggregate <compatible-test-files>
$m03BackendTests = @(rg --files amplify -g '*.test.ts')
node --import tsx --test @m03BackendTests
node node_modules/typescript/bin/tsc --noEmit -p amplify
python tool/test_m06_dev_config.py
flutter analyze --no-pub
```

Serialize Flutter runs. Chrome groups use the Windows SDK URL overlay; native
adapters are tested in VM and actual Android. ACCEPTANCE.md records full totals,
configured skips, actual UI matrix and bounded limitations; UI_QA.md has detailed
evidence. Do not add overlapping focused test counts to the full regression.

## Leader live gate

- [ ] Verify intended AWS account/region/stack diff; deploy matching
  amplify/backend.ts + attachments/infrastructure.ts, not the old standalone
  storage.template.json as the entire API.
- [ ] Set exact HTTPS attachmentUploadOrigins; validate private/versioned/TLS S3,
  version-pinned verifier/read IAM, retained final objects and staging-only cleanup.
- [ ] Map public outputs attachmentApiEndpoint, syncApiEndpoint and protocol1
  into the existing ignored public-client config. Operator credentials remain
  backend-only in ignored profile/.env, never Flutter defines/assets/Git.
- [ ] Test registered Cognito owner/Viewer/Editor, locked/stale/revoked scopes,
  direct-read/export bypass, fresh ACL and protected/shared Range requests.
- [ ] Verify actual S3 PUT CORS/checksums/version pins, expiry/overwrite/lost ACK,
  immutable association, unlink/reference-safe cleanup and mixed-client replay.
- [ ] Run actual Chrome/Android large transfer/seek/offline/revoke matrix against
  that deployment, plus existing M06 AppSync/SES/provider live gates.

Source/local completion does not authorize or certify deployment. M09 begins
only after the user's later integration/replanning request.

Progress inside final flutter:
https://app.notion.com/p/3eff9c7a1aa08170856afa612fd3f271
The exact final Git SHA, APK hash and post-publication native run outcome belong
to that mutable receipt; documentation publication does not rebuild source.
