# UI42 — first-line gutter, toggle and File removal

Scope: the three items requested on 23 October, resumed on 24 October 2026.
Status: **PASS for these three bounded items on final50**. Publish, then stop.
Whole-platform Web/Android >=95% similarity remains UNVERIFIED. This is not
whole-M09 acceptance or live AWS verification.

## Implementation and review

- Gutter placement uses the editor's public cursor-at-zero rectangle converted
  to the block coordinate system. It includes heading padding, text scale and
  inline sizes. One shared hover target prevents parent/child duplicate +.
  Final50 uses Flutter's official `OverlayPortal.overlayChildLayoutBuilder` to
  establish paint, pointer and accessibility positions during layout. Actual49
  revealed a paint-only follower's DOM hit box overlapping the toggle arrow;
  widget geometry checks alone had not detected it.49 is superseded for Web.
- Toggle uses a small rotating filled triangle; new empty toggles start closed.
  Expanded empty toggles expose the existing add-child action as a muted hint.
  Titles grow naturally; children remain below wrapped/48px titles. Web title
  and child inset is32dp, native24dp. Native disclosure target is24dp wide and
  at least48dp high, without covering the title. It is not48x48.
- Enter at the title end prepends a child. Collapsing with a child selection
  moves the caret to the title. Expansion remains transient view state and
  does not save the document; viewers can still expand/collapse.
- Explicit removal prunes all matching positioned File blocks together with
  the attachment manifest through the canonical Note writer. Pending local
  cancellation uses the same writer. Other text, formatting and files remain.
- `onCommitted` reports the canonical DTO before asynchronous encrypted-cache
  cleanup. Presentation immediately fences autosave, waits for IME completion
  and applies targeted editor deletes. ACKs are processed in delivery order.
  A cleanup failure reports the committed DTO and an actionable error once.
- Irreversible attachment removal starts a new undo/redo segment: old engine
  operations cannot be safely rebased and must not restore a missing binary.
  Removing the sole File creates an editable virtual paragraph. Ordinary File
  insertion/binding still uses the existing undo system.
- Real unavailable/revoked content remains guarded; no blanket hiding of
  missing files, metadata, access checks or transfer errors was introduced.

## Direct Notion reference

Actual Notion Web and the Notion Android app were inspected, using only the
synthetic reference notes. Web new toggle starts closed; opening it shows a
clickable empty hint. Clicking it adds an indented child; Enter at the title
end adds the first child. Web heading1 + center matched its first text line.
Native title inset measured about24.8dp. Notion's native disclosure itself is
smaller than48dp; NoteFlow retains a48dp-high touch area while matching inset.
Temporary reference blocks/text were restored, retaining original file67B,
headings/body and slash. Native stay-awake restored to its original value1;
Notion emulator5556 closed with its data retained.

## Ownership

Two actual Luna Max workers, with disjoint files:

| Worker | Responsibility | Lead review |
| --- | --- | --- |
| toggle42 | Container renderer, nested command, shortcut and toggle tests | Rejected fixed-height overflow; required natural height, platform insets and public cursor geometry for mixed-size text |
| file_remove42 | Domain/Application removal, panel/page ACK, live editor prune and tests | Required atomic pending cancel, typed cleanup failure, original-path caret transforms, history boundary and pre-cleanup ACK/autosave fence |

Lead implemented gutter geometry/shared hover, reviewed both deliveries, fixed
compilation/test harness issues, added the page draft/autosave regression,
caret-on-collapse and ordered ACK processing, and owns builds, actual UI QA,
Notion evidence and Git publication. Workers did not run shared builds or Git.

## Checks and provenance

Latest focused VM:36/36 pass, `p6-ui42-vm50.log`. Covers nested/duplicate refs,
pending cancellation, canonical-write and post-commit cleanup failures, existing
removal recovery, current Upload/picker lifecycle, selection/history, wrapped
and mixed-size toggles, viewer guards and ordered page ACKs/newer dirty text.
Chrome50:15/15 pass, `p6-ui42-chrome50.log`, including first-line gutter kinds
at100%/150%, nested hover arbitration, toggle, File menu/focus and ordered ACK.
Scoped13-target analysis49 was clean; the sole subsequent runtime change was
the gutter, whose50 analysis also passed. Final packaged checks below passed.

Early invalid const factories and EdgeInsets return type were corrected.
Pending-file tests were updated from the removed Add attachment footer and
direct Retry icon to the actual inline Upload and action menu. No assertions
about access/errors were dropped. Overlapping stale native-hook compilation
produced Windows linker failures; those attempts were not counted as passes.

Runtime48 source1074 paths, no drift. Web80.2s/APK69.8s. Its actual browser bundle
and installed APK hashes matched.49 adds ordered ACK handling after review;
final runtime identity must be recorded below before publication.

## Actual interaction evidence

On48, installed Chrome local1280x740: new /toggle, closed/open empty hint,
click-to-add child, nested + -> File -> actual67B picker, Remove attachment,
no unavailable tombstone and offline Back/reopen. Heading1 gutter was observed.
Android native1080x2400/420dpi: new /toggle, hint/child and collapse; associated
file removal kept three other file rows and `Before`. After removing API reverse
mapping AND cold restart, the app displayed Offline. A new file was Pending on
this device; Remove local attachment removed its block. Another cold offline
reopen retained three old rows/text and no removed File. API mapping was restored
and Retry returned All synced. Existing empty placeholders were preserved.

Ignoring a removed reverse mapping alone is insufficient to prove offline:
existing HTTP tunnels can survive. Only the cold run with explicit Offline
status is treated as the native offline proof.

Known broader observation: typing immediately after an async heading conversion
kept only the first character in one48 automation attempt. A subsequent harness
action also targeted the wrong Text block instead of Heading1. These do not
establish full typing acceptance; the pre-existing focus/typing backlog remains
open. No claim of every editor function or overall95% follows from these checks.

## Final50 / publication

49 actual: associated removal2->1 Web file rows, no unavailable tombstone,
explicit Use local conflict resolution after cross-device QA edits, All synced,
then offline Back/reopen retained the remaining file and Before. Native49
associated3->2 and pure pending offline cancellation/cold reopen retained2
other files and Before. Its API mapping was restored afterwards. Temporary
reverse-map removal without restarting did not prove offline and is not used.

Final50 actual Chrome: normal semantic click collapsed and expanded the toggle;
the + also opened/filtered the File palette without force-click. Public DOM
rectangles: arrow x415.5/w24; + x387.5/w26 (2dp separation). The49 bug exposed
the + at x418.15, over the arrow. `app50-web-toggle-hit.png` records the fix.
`app50-web-callout-plus.png` and `app50-web-task-plus.png` show first-line gutters.
Chrome50 actual /file -> picker67B with browser offline -> Pending on this device
-> Remove local attachment removed the entire File block. Offline Back/reopen
retained NativeToggle/NativeChild, with zero file rows or File unavailable.
`app50-web-offline-reopened.png` is the post-reopen evidence. Networking restored.
Native50 APK installed with matching hash; actual collapse/open retained its
child (`app50-native-toggle-open.png`). Native49 removal code was unchanged in50.

| Final check | Evidence |
| --- | --- |
| VM |36/36, p6-ui42-vm50.log |
| Installed Chrome tests |15/15, p6-ui42-chrome50.log |
| Static analysis |13 targets49 + sole changed gutter50, both clean |
| Web/APK debug local builds |81.7s /31.4s, no source drift |
| Actual Chrome |Toggle + nonoverlapping hit regions, + palette, callout/task gutter, pending offline removal/reopen |
| Actual native |49 associated/pending removal/cold offline reopen;50 installed toggle smoke, same removal core |
| Backend/TypeScript |Not needed: no TypeScript or wire/schema change in this slice |

Source1074 paths:
`ab4bdfc0af180c83388baf8011e4c4bcfbcd1fd62d2da8e7076074efe9ba45f1`.
Chrome main.dart.js21,410,128 bytes/SHA256
`5367dde72d47a13912d0210c5bc46fe10a8dab400626200b5ba666e980b24018`
matches the packaged file. APK/device SHA256 both
`c71ba9995792ef3f71e307ff664a6d22913e439f53107ba4226d6b757a633eb1`.
Receipts: p6-parallel50-source.json, p6-parallel50-build.json and
ui42-final-browser-bundle.json under ignored output/m09.

Notion board: exactly3 UI42 items checked,39 images total; all31 prior images
preserved,8 new images. Progress remains under final flutter; both >=95% gates
remain explicitly UNVERIFIED. Graph status/search/coverage returned Transport
closed, so the bounded changed sources and relevant engine/API code were read
directly. No graph-completeness or live AWS/security-regression claim is made.

Publication: explicit source/test/docs paths only; preserve unrelated untracked
.playwright-cli/ and final_project.md. Do not stage output, uploads or logs.
Stop after this milestone is pushed; wait for the user's next request.

Source checkpoint842e814933d28894515742af3f0affc55bff185e was pushed and verified
against origin/final-tuankiet with0/0 divergence. Notion progress includes its
commit link and stop state. The followup documentation commit records only this
publication and QA Chrome closure; runtime50 source/hash evidence is unchanged.

## Closure receipt

| Continuity record | Resolution |
| --- | --- |
| MUST_REMEMBER.md |Updated: scoped completion and stop rule |
| docs/m09/CURRENT_WORK.md |Updated: final50 evidence, runtime and next allowed action |
| docs/m09/AGENT_IMPLEMENTATION_20261019.md |Updated: actual2 Luna Max ownership and lead review |
| docs/m09/VISUAL_REVIEW.md |Updated: scoped result, whole95% gate still open |
| docs/m09/EDITOR_POLISH_UI42.md |Created: implementation, tests, actual evidence, limitations and receipt |
| _agent_ops/HANDOFF.md |Not needed: runtime pack file absent |
| _agent_ops/SESSION_BRIEF.md |Not needed: runtime pack file absent |
| _agent_ops/OPERATING_RULES.md |Not needed: runtime pack file absent |
| _agent_ops/CURRENT_TASK.md |Not needed: absent; existing CURRENT_WORK used |
| _agent_ops/INDEX.md |Not needed: runtime pack file absent |
| _agent_ops/REPO_MAP.md |Not needed: absent; graph attempted, exact-source fallback used |
| _agent_ops/SESSION_PROTOCOL.md |Not needed: absent; receipt recorded here |

session_start.py was attempted and absent. No named pack team or routing
playbook was invented. No worktree or dependency change was made.
