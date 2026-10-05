# M03 local setup and AWS handoff

## Local application

Use the existing M06 debug composition, which now includes the M03 routes and
encrypted local object fixture. No AWS credentials are needed.

```powershell
python tool/run_m06_local.py
```

Open http://127.0.0.1:8776/?devUser=owner and an isolated browser profile at
http://127.0.0.1:8776/?devUser=recipient. The synthetic recipient address is
recipient@example.invalid. Existing output/m06-local encrypted state, key and
attachments/objects.key must survive restart. Do not delete them to fix a test.

For Android use SDK D:/tools/AndroidSdk and the existing NoteFlow_API35 emulator.
Reverse8796/8797, install-r a current main_dev.dart debug APK and preserve app data.
Use R: only as a SUBST alias to this primary checkout for the native build.
Run Flutter builds/tests sequentially: their shared native hook lock is exclusive.
Keep VM/browser/Web runs on the same checkout spelling to avoid rebuilding host
native assets merely from switching D:/R: paths.

Plain flutter run -d chrome does not start this backend or load .env; use the
launcher or follow docs/m06/DEV_SETUP.md. Local fixture auth is synthetic and
does not prove Cognito/S3 deployment behavior.

## Leader deployment inputs

Follow docs/m06/DEV_SETUP.md and LIVE_GATE.md for operator profile/region,
Cognito/AppSync/HTTP outputs and the existing .env public client configuration.
Operator credentials stay server-side in ignored .env/profile, never in Flutter.

Current M03 CDK source is composed from amplify/backend.ts and
amplify/attachments/infrastructure.ts. Set CDK context attachmentUploadOrigins
to the exact comma-separated HTTPS browser origins that may perform staging PUT.
An empty list intentionally disables browser S3 PUT CORS. No wildcard/public read
or signed GET is enabled. The Lambda receives ATTACHMENT_BUCKET from composition;
it is not a client secret/configuration value. Public custom outputs publish
attachmentApiEndpoint alongside syncApiEndpoint and attachmentProtocolVersion1.
The current client uses the configured Sync/Security API base for attachment
routes, so both outputs must identify this matching deployment.

Deploy the coordinated M02/M03/M04/M05/M06 backend before upgrading clients.
Keep Note schema6/envelopeAAD3 and the extended binary key packet compatible;
old clients must reject unsupported packets rather than erase them.
storage.template.json is the older standalone storage foundation and is not the
full API deployment: use the current CDK composition/routes.

## Live acceptance gate (leader; source/local receipts are separate)

- Verify private/versioned/TLS S3, retained final objects, bounded staging expiry,
  signer/verifier Range and staging-only cleanup IAM against the actual account.
- Real Cognito owner/viewer/editor: fresh ACL, protection scopes, revocation,
  stale JWT/grant/epoch and direct URL/bypass denial before and after Range reads.
- Actual S3 PUT CORS/checksum/version pinning, expiry/overwrite/lost ACK, verify,
  immutable association, legacy/mixed-client replay and reference-safe unlink.
- Chrome and Android authenticated206/Range/seek, large-file memory/progress,
  cancellation, offline encrypted reopen, password rotation and interrupted export.
- Preserve real data and blocked old-grant drafts; stage no operator keys or logs.

Source/setup delivery does not authorize deployment or claim these live gates pass.
