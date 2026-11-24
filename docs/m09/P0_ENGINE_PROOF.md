# M09.RT.P0 editor engine proof

2026-10-14. Scope: synthetic app `tool/m09_editor_spike`, separate native ID
`app.noteflow.qa.m09_editor_spike`. The primary app has no engine dependency yet.
This receipt chooses an engine/adaptation approach; it does not accept M09 UI.

## Adopted candidate

AppFlowy Editor6.2.0 vendored under `packages/noteflow_editor_engine`, MPL2
source/license included. Upstream archive SHA256:
`c2367acdd93c7eeefaf6c58e5fed1a1c62cf02b8368102b786b5c6a0d1c583cf`.
`NOTEFLOW_PATCHES.md` lists dependency/API/lifecycle shims. The host uses engine
selection, transactions, delta diff and history; it does not implement input.
Forced old picker/Win32 override was rejected after compile failures.

## Evidence

| Check | Result |
| --- | --- |
| VM proof | 10/10 PASS: 13 kinds/JSON, H4/nesting/math/table, IME composition, selected size+undo, accessible text+undo, collapse, readonly/late input, row-major Tab buffer, autofill null scope |
| Scoped analyzer | Clean after removing redundant test import |
| Installed Chrome widget suite | 10/10 PASS using existing Windows SDK-overlay runner; p0-spike-chrome-overlay.log |
| Installed Chrome via authorized Playwright | Typed Unicode/emoji, selected Size24, Undo/Redo, math retained, round-trip, A1 FIRST then Tab B1 SECOND B1 painted; no new console error |
| Android emulator actual UI | Touch/long-press, selected Size24/Undo/Redo, round-trip, readonly rejects DENIED_P0, A1 NATIVE_CELL then Tab SECOND_NATIVEB1, rotation keeps FINAL_NATIVE; scoped Flutter errors0 |

Native UI artifact SHA256:
`5DA7C48BA81501114116FB3CC45AD71CAA513E46D9A8C41C248BB8C294F41774`.
It predates the final autofill getter shim (covered by VM); refresh native builds
when adopting into production. Manual native Telex composition is still a P6
check; the current composing proof drives framework input deltas.

Local evidence lives in ignored `output/m09`: p0-spike-vm/analyze logs,
p0-chrome-input-size-undo.png, p0-chrome-table-navigation.png,
android-proof-selection/size.png, android-proof-readonly/landscape.xml and
p0-native-flutter.log. Synthetic profiles/emulator data are retained.

## Defects found and corrected

- Semantic focus must wait for framework/view focus to settle; decorate public
  builders to include nested/table paragraphs, with engine-backed actions.
- Web block changes require a fresh input connection: same-client semantic-field
  switches erased B1's buffer. Actual Chrome and native table retests retain it.
- Readonly must reach platform input config and semantic actions; reject late IME.
- Metrics debounce must be instance-scoped, cancelled on dispose and fenced.
- No autofill group means null scope, not an SDK getter exception.

## Production work remaining

P1–P3 typed business document, encrypted persistence and transport. Raw engine
JSON is proof only. P4 owns stable business IDs through the public synchronous
before-transaction hook, actor-only toggle expansion, bounded conversion,
plain paste/command allowlist and session/access/IME/selection guards. P5/P6 own
ref styling, screen-reader usability, keyboard/touch matrix and >=95 scoring.
No UI score assigned. Earlier direct Chrome widget runner attempts stalled
before loading and are not passes. The final Windows SDK-overlay run loaded and
passed all10 tests, using installed Chrome and unchanged product/engine code.
