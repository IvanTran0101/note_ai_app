# UI44 — native block palette and clipboard reference repair

27 October2026. Continuation after UI43 commit0910db2 on final-tuankiet.
Lead owns this slice; all20 earlier workers handed off and no child is running.
The broader M09 Web/Android>=95% similarity gates remain UNVERIFIED.

## Direct comparison

Actual Notion Android and installed NoteFlow53:1080x2400/420dpi, font1, dark,
portrait,3-button navigation. Synthetic paragraph Local first comparison.
Opened/visually inspected native selected word, normal editing rail, plus palette
and Share. Raw captures remain ignored under output/m09; no private account
Share screenshot is published. See ui43/LIVE_REFERENCE.md for full observations.

- Notion palette: flat #202020 background, neutral-gray icon/label rows in two
  columns, no dark rectangle behind each unselected choice. Panel from roughly
  y1517 to2274 (~288dp); row separation138px (~52.6dp).
- NoteFlow53: unwanted #191919 tiles, panel y1458 to2274 (~311dp). Existing label
  anchors and two-column order already track the ref. Page/Link to page remain
  excluded, so fifth-row Callout is intentional, not a missing Page capability.
- Notion selected-text OS capsule stays light on its dark document; NoteFlow53
  incorrectly switched to dark gray. Keep the existing Cut/Copy/Paste subset;
  OS Read aloud/Ask Gemini and Notion AI/comment/emoji are not app additions.

## Implementation

Only four Presentation runtime files change:

- basic_block_grid.dart: transparent unselected row fill, muted legible native
  foreground. Selected keyboard row feedback/48dp targets/callbacks stay.
- basic_block_menu.dart: native panel capped288dp, still bounded by available
  safe height on short/rotated/IME hosts; Web keeps its existing dimensions.
- basic_block_menu_choices.dart: owns its label/icon constants, moved out of
  menu composition to keep that file below400lines. Same choices and ordering.
- native_android_clipboard_menu.dart: light neutral capsule/dark readable labels
  in both document themes. Anchors, permission checks and action owners stay.

Actual54 scroll-to-bottom revealed a pre-existing compact ListTile reduction of
File to~44dp. Explicit48dp minimum/standard row density now applies to that row.
The existing palette test uses the actual compact density and checks its full
touch height. This last change requires55;54 is superseded for final proof.

No new features, storage, service or access-policy changes. This is UI refinement,
not the deferred broad functional acceptance phase.

## Verification

- Focused existing palette and File-menu regression:6/6pass,
  output/m09/ui44-palette-tests.log (includes200%+IME/short-screen scroll and
  existing File insertion/deletion/undo behavior).
- Existing native clipboard suites:9/9pass,
  output/m09/ui44-clipboard-tests.log (touch/anchor/reflow, guarded copy/cut/paste,
  read-only/revoke/focus/route behavior).
- Strict analyzer4 changed runtime files: no issues,
  output/m09/ui44-analysis54.log.
-54 built Web72.1s/APK33.4s, source1076/b4152401...67eca, drift[]. Actual54 shows
  palette top1518 vs ref1517; Text ink ref[182,1707,249,1734], app[185,1705,255,1731]
  in physical px, from simple neutral-text threshold inside the same label ROI.
  This is a component anchor measurement, not a platform similarity percentage.
  Unselected rows are now flat; selected keyboard feedback intentionally remains.
  Clipboard capsule is visibly light/readable, existing3 actions unchanged.
-55 target rerun2/2pass under compact density, output/m09/ui44-file-target55-tests.log.
  These repeat the two palette cases, not two new unique cases.15 distinct scoped
  cases total across the palette/File and clipboard runs; final55 changed only
  File-row target density after54. Strict final analyzer5 source/test paths clean,
  output/m09/ui44-analysis55.log.
- Final55: Web61.5s/APK31.0s,1076 paths/source
  ae3a621f028b1249547e5129a5ca84a380fe8957cbcfc2fde77a0ae91a97e4da,
  source drift[]. Chrome received21,440,080 bytes/main.dart.js
  SHA8f47ff330c857c55fc186c1e175e2483c39eef4ca9ba090261a92103b3d3e86e.
  APK/device SHA0500a120932e02e849daa1afaa2bdf0bc50c017173dee8e73ea09251ec2a3b41
  match. Source/build manifests and runtime receipts stay ignored in output/m09.
- Actual55 native: opened the palette, scrolled to the final File row, measured
  its semantics target[0,2148][1080,2274] =126px/2.625 =48dp, ending at the system
  navbar boundary rather than underneath it. Closed/reopened editing; selected
  word shows the light capsule and format rail above Gboard. Images
  ui44-native55-palette.png, -file-target.png and -selected.png were inspected.
- Actual55 Chrome: chooser2 separate checkboxes/Cancel and Share/Close work with
  zero console errors. First54 reload raced local server startup; connection
  refusal was a harness transition, then response hashes and UI were verified.
  No invitation sent. Original Android font1/auto-rotation1/user_rotation0
  retained; Notion AVD stay-awake restored1 and that QA instance closed.

## Current decision and continuation

Scoped UI44 repair passes the checks above. Overall M09 remains PARTIAL; whole-platform95% gates
stay unverified after these component checks. Continue remaining paired
visual-state review before broader typing/function acceptance. Actual iOS remains
unverified. Do not turn15 test passes into a similarity percentage.

Closure receipt: MUST_REMEMBER/CURRENT_WORK and ui43/LIVE_REFERENCE updated with
current source/state/observations; this report records evidence/limits.
VISUAL_REVIEW and AGENT_IMPLEMENTATION record this lead-only continuation;
UI43_REVIEW retains the reviewed20-agent checkpoint/publication receipt.
_agent_ops remains absent; no fictional records or teams created. No config,
dependencies, lockfiles or unrelated personal files touched.
