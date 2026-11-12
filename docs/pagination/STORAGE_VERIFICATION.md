# Storage pagination — verified delivery

13 November 2026. **PASS for the scoped local page/detail/catalog read path**
on Chrome and Android API35 emulator. This follows the historical query/UI
checkpoint in VERIFICATION.md. It is not a whole-app O(50) memory guarantee.

## Behavior and checks

| Check | Evidence |
| --- | --- |
| Broad regression | VM285 pass/2 configured skips before final targeted guards |
| Final focused VM | 30/30: cache/migration/password/CAS/session/catalog plus repository/label regression |
| Final Chrome aggregate | 47/47 across8 original targets: real IDB, crypto, repository, labels, UI pages and M06 |
| Analyzer | All21 changed Dart paths clean; integration-only teardown delta separately clean |
| Storage faults | Failed preparation/CAS preserves canonical; corrupt/missing derived data repairs; missing key/pointer fails closed; outbox/conflicts/cursor retained |
| Protection | Enabling password removes active account-key payload record; cold offline password unlock remains in vault; protected search/facets remain masked |
| Concurrency | Native/Web atomic CAS, old DB version rejection, manifest rejected by legacy codec, stale generation retry, lock during payload await, account change at final await denied |
| Actual Chrome integration | Installed Chrome, real encrypted1,000-note store; final driver result true/failureDetails[]; cold page19 reads50 payloads/0 canonical decodes, detail adds1 |
| Actual Chrome manual | Hash-matched final bundle; cold50/0, Next100/0; global marker999 total1101 reads/0 canonical; Notes/Home search inspected, no observed pageerrors |
| Actual Android | Retained1,000-note account: Next/Previous, marker999 in Notes/Home, no-results/Clear, page footer48dp above navbar/IME |
| Android migration | Physical root3→manifest4;1,000 encrypted records; canonical512,343bytes/SHA256 unchanged |
| Android cold reopen | Force-stop/relaunch:1,000 notes, canonical decodes0/payload reads50; canonical and manifest hashes unchanged |
| Restoration | Final product APK installed-r, pulled hash matched; process observed; original font1.0/auto1/rotation0/nav0 verified; emulator closed, all data retained |

Final focused VM/Chrome behavioral runs precede one braces-only lint fix.
The final runtime/builds include that fix. No iOS, release build, live AWS,
latency/RAM benchmark, whole-M09 visual gate or UI53 completion is implied.

## Artifact provenance

- Final integration JS:18,421,309bytes,
  `6c9fdddafff9528369b33dbabd87b5e0e65240ea06a13a0d1d1d7161862cf63b`.
- Final manual JS:17,788,153bytes,
  `016eb6930a4d2977a73d190df446ccc1c2e5f9b601a6b89121831e413023683d`.
- QA APK:235,956,574bytes,
  `cbe274bcca5ea1890b4e7d93ad8db9e4d823a45f6bef79fe171502480c1ac211`.
  Installed/pulled bytes matched.
- Product main_dev APK:240,261,649bytes,
  `c0582366f6938c0600ca1394ab74d61e0c458ff1eb48e37db6d7edf142d530ae`.
  Restored installed/pulled bytes matched.
- Native canonical before/after migration/search/reopen/product restoration:
  `2857de690b92b87a615f2de3feff4c521550fb8302319cbfd04cb826c9ed50ce`.
- Production freeze913 paths:
  `764ca6fd5ec2585a7888c128d44f68c65897405c63d5faed0de01ddacac9d83e`.
  Subsequent change was only integration-test teardown, unreachable from the
  manual/product entrypoints. Final runtime inventory913 paths:
  `124fbd6bbe052fea3c3287608849c0b8fcd846b94359d47ec3881454abfa378a`;
  final drift empty, no production drift from APK/manual builds.

Builds include preserved pre-existing dirty UI53 source. They are not artifacts
of an otherwise clean commit. QA uses a separate synthetic account; no account
tables, credentials, search exports or binary/cache artifacts are committed.

## Findings resolved

- Lock during payload await could be treated as corruption and retried in a new
  epoch. The operation now retains one epoch across awaits and repair retries.
- Repository/catalog account checks needed to run after the store's final await;
  precise account-switch regressions cover both callers.
- Missing derived records could block an otherwise valid save. Re-sealing cache
  records preserves the same pending canonical CAS transaction.
- Missing manifest/canonical must not be interpreted as an empty account while
  page data remains. These cases fail closed.
- Legacy Web probe incorrectly coupled a missing version with an upgrade callback.
  The helper now opens the current database, upgrading only an empty legacy probe.
- Initial multi-folder server loaded an old root bundle through base-href. That
  run was discarded; final artifacts each used a dedicated root and fetched hash.
- Integration teardown emitted FocusManager-after-dispose after test completion.
  Unfocus/unmount/drain fixed the test lifecycle; final driver was read twice clean.

Canonical sync/mutations/vault/status ACK still use whole-account state; status
ACK can retain ordinary saved text for editor rebase. Full-text queries scan
payloads sequentially and metadata remains O(note count). The completed boundary
is paginated reads, not elimination of every account-sized operation.

## Publication

Initial storage checkpoint88ce76f was pushed with25 explicitly owned paths.
Final review fixes and the runtime receipt were pushed as
70a066fbfa59d092e2fb2f0007e075e13b3ad399 (12 explicit paths; remote matched).
Notion S0-S5 is checked and authoritative progress/limits updated. This later
docs-only closure records the publication without changing runtime source.
No new agents/worktrees were used for pagination. Graph transport/coverage was
unavailable; exact source/tests were used. _agent_ops is absent in this checkout;
continuity is maintained in MUST_REMEMBER.md and docs/pagination/CURRENT_WORK.md.
