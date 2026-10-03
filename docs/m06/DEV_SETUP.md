# M06 development configuration

M06 source/local acceptance is complete. This setup prepares local development
and a later AWS dev handoff without editing committed account identifiers.
The assistant has no independent AWS dev account. Real provider acceptance still
needs the project owner's dev deployment and registered test users.

## Start locally

From the repository root, copy `.env.example` to the ignored `.env` once. Preserve
an existing `.env` instead of replacing it. Leave NOTEFLOW_AUTH_MODE=local:

```powershell
python tool/m06_dev_config.py prepare
flutter run -d chrome --dart-define-from-file=output/m06-dev/dart-defines.json
# Or use the existing Android emulator, without uninstalling/resetting app data:
flutter run -d emulator-5554 --dart-define-from-file=output/m06-dev/dart-defines.json
```

The helper uses Python3.10+ standard libraries. It makes no AWS call. Local mode
emits only NOTEFLOW_AUTH_MODE=local and uses the existing encrypted local store.
It does not grant a cloud recipient or emulate real Cognito authorization.

## Switch to the intended dev deployment

1. Obtain its generated **public** Amplify outputs JSON. Save it as the ignored
   `.env.amplify-outputs.json`; retain the auth section and custom endpoints.
2. Change only these settings in `.env`:

```dotenv
NOTEFLOW_AUTH_MODE=cognito
NOTEFLOW_AMPLIFY_OUTPUTS_FILE=.env.amplify-outputs.json
```

3. Outputs must contain auth.aws_region, auth.user_pool_id and
   auth.user_pool_client_id, plus custom.syncApiEndpoint, eventHttpEndpoint and
   eventSocketEndpoint. Optional NOTEFLOW_SYNC_API/EVENT_HTTP/EVENT_SOCKET values
   override those endpoints. HTTP uses HTTPS and the realtime socket uses WSS.
4. Run `prepare` again and rebuild/run with the same commands above. The root's
   NOTEFLOW_AMPLIFY_OUTPUTS define now supplies that deployment's public config;
   without the define, existing generated lib/amplify_outputs.dart is preserved.
5. Sign into the intended registered Cognito test user in the app. AWS operator
   credentials and note-sharing users are different identities; an AWS profile
   alone cannot create a share between application users.

Changing the public deployment file selects its Cognito pool and endpoints.
Changing AWS credentials alone does not redirect an already built Flutter app.
No account or note data is migrated/reset by this helper. Local/canonical storage,
outbox/cursor and independent backend permission checks keep their existing owners.

## Backend operator credentials

Use an existing AWS CLI/SSO profile via AWS_PROFILE, or a temporary
AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY pair with AWS_SESSION_TOKEN when required.
AWS_REGION selects the backend command's region. The helper rejects mixed methods
and incomplete key pairs. With a profile it clears inherited access keys; with
temporary keys it clears an inherited profile/token before spawning the child.

```powershell
# Explicit read-only identity check, after installing/configuring AWS CLI:
python tool/m06_dev_config.py backend -- aws sts get-caller-identity
```

The `backend -- <command>` wrapper supplies auth to that explicit child process,
without changing the parent shell or global environment. It does not deploy by
itself. The command's own behavior/output is the caller's responsibility. Use the
actual account/region/stack diff and authorization workflow in LIVE_GATE.md
before a deployment command. No AWS CLI/account is provisioned by this setup.

Never pass `.env` directly to Flutter's --dart-define-from-file or add it to
pubspec assets. `prepare` writes only allowlisted public defines under ignored
output/. Private AWS fields in the public outputs are rejected. The public
endpoints/pool identifiers will be visible in a client build; operator keys,
passwords, tokens and unlock grants must stay outside that configuration.

## Local verification

```powershell
python -m unittest discover -s tool -p test_m06_dev_config.py -v
flutter test test/composition/amplify_environment_test.dart --no-pub
```

Tests use only synthetic values. They cover public/secret separation, selecting
outputs, profile/key precedence, no parent environment mutation, safe error
messages, endpoint validation and the ignored output boundary. Scoped VM/Chrome
composition runs also cover generated fallback and selected public outputs.
The four live Notion criteria remain pending actual AWS acceptance; see
[ACCEPTANCE.md](ACCEPTANCE.md) and [LIVE_GATE.md](LIVE_GATE.md).

Receipt03/10/2026:13 Python checks passed; composition default/selected outputs
passed twice on VM and twice on real Chrome. Scoped analyzer reported no issues
(155.7s), formatter/diff checks passed. Chrome used the existing isolated SDK
tools overlay for Windows URL separators, with unchanged product/assertions.
Only synthetic values were used; the ignored local .env was created with blank
operator fields and local mode. A previous absent R: alias was restored to the
same D checkout; no worktree or installed SDK was changed.

References: [Dart compilation environment declarations](https://dart.dev/libraries/core/environment-declarations)
and [AWS Node credential provider chain](https://docs.aws.amazon.com/sdk-for-javascript/v3/developer-guide/setting-credentials-node.html).
