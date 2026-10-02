# M05 testing

Use synthetic accounts/note namespaces. Never clear, uninstall or overwrite an
existing user's application data. Test keys/passwords in fixtures are synthetic.

## Order on Windows

1. Use a short checkout path for native hooks (for example a free SUBST drive).
   The current session uses R: mapped to the managed worktree. Check the drive
   mapping before creating or removing one; never assume a drive is free.
2. Run backend policies and typecheck.
3. Run the complete VM suite, then Chrome tests, then Android integration.
   Avoid overlapping native builds: hook runners share a package build lock.

```powershell
node --import tsx --test amplify/sync/cursor.test.ts amplify/sync/dynamo_sync_store.test.ts amplify/sync/request_parser.test.ts amplify/sync/sync_response.test.ts amplify/protection/use_cases.test.ts amplify/ai/summary_security.test.ts amplify/sync/security.test.ts
npm run typecheck
flutter test --no-pub --reporter expanded
python -X utf8 tool/run_chrome_tests.py --sdk C:/Users/meow/flutter test/security
flutter test integration_test/m05_security_test.dart -d emulator-5554 --no-pub --no-uninstall --reporter expanded
```

`--no-uninstall` is mandatory on an emulator with existing user data. Integration
uses real Android secure storage and file adapters in distinct namespaces. The
Chrome unit suite uses real IndexedDB/crypto with a mocked secure-storage plugin;
that result alone does not verify the browser plugin's key custody. Backend tests
exercise production use cases/transaction conditions with AWS/SES doubles. They
do not claim a live Cognito/DynamoDB/SES/provider deployment.

## Chrome host workaround

The installed Flutter 3.47.5 Windows test host converts browser URL paths to
backslashes, breaking CanvasKit and test selectors. `run_chrome_tests.py` creates
a temporary Flutter-tools overlay, resolves package roots to the installed SDK,
and changes only the two URL handlers to use URI paths. The installed SDK, engine,
compiler, product and Chrome are unchanged. Remove obsolete overlays manually
only after their processes have finished; no recursive cleanup is automated.

The complete browser-compatible suite excludes eight IO-only test files: native
user-profile/configuration/local-sync storage, native hardware fixtures and the four native AI adapter
files. Those files run in the VM suite. Browser-only storage tests run on Chrome.
Scope counts and any further limitations belong in PROGRESS.md/Notion after the
actual run, never inferred from file counts or a successful build.

## Complete Chrome suite and plugin integration

Use `--aggregate` with the browser-compatible targets to register the original
file mains in independent groups. The ignored generated target is inside test/
and does not match `_test.dart`; assertions and production code remain unchanged.
Native fixture files still run on VM. The Web hardware stub has its own test.

After browser unit tests finish, build the real plugin integration into its own
output directory (never concurrently serve build/web while unit tests use it):

```powershell
flutter build web --debug --target integration_test/m05_security_test.dart --output output/m05-browser-integration --no-pub --no-wasm-dry-run
python -m http.server 8766 --bind 127.0.0.1 --directory output/m05-browser-integration
```

The integration target runs all 12 shared scenarios. Request the Flutter driver
result and confirm `result: true` with no failureDetails; a build/loaded page is
insufficient. WidgetTester registers a synthetic keyboard on Web to avoid DOM
blur echo overwriting synthetic text. Browser secure storage and IndexedDB remain
real. Keep logs/screenshots in ignored output/ or the task temporary directory.

## Results

See PROGRESS.md for the latest verified results and pending work. Record a failure
before changing its behavior, keep a regression assertion, then rerun the relevant
suites and platforms. Do not tick the Notion acceptance checklist from static
analysis or build success alone.
