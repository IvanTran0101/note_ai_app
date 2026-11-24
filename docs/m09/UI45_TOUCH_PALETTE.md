# UI45 — touch-open native palette

27 October2026, lead continuation after published UI44. No additional agents:
the20 real Luna Max UI43 deliveries remain documented/reviewed in UI43_REVIEW.
M09 Web>=95% and Android>=95% remain UNVERIFIED.

Actual Notion Android0.6.4222 opens its + palette with flat unselected rows.
NoteFlow55 still painted Text selected because controller.selected starts at0.
The menu now hides that initial native visual selection until navigation changes
the selected index. Keyboard feedback and scroll-to-choice remain. Controller
replacement resets the local presentation flag. Web selection behavior,13 Basic
choices+File, guards, callbacks, storage and local-first writers are unchanged.

Runtime files: basic_block_menu.dart and its basic_block_menu_choices.dart part.
Existing test/presentation/ui43/block_menu43_test.dart now asserts transparent
initial Text and retains keyboard/200%/IME/File48dp/short-screen checks. No new
feature, dependency, lockfile, Domain or Infrastructure change.

## Evidence

-2/2 focused palette tests pass, ui45-native-palette-tests.log. Strict analyzer
  for the two sources and test: no issues, ui45-analysis56.log.
- Final56 Web91.0s/APK69.8s.1076 runtime paths/source fingerprint
  b6bc570876cd7590db960fafbec978b688540d345e7d025960127c9f95643dd8,
  source drift[]. Build/source receipts stay ignored under output/m09.
- Chrome installed executable received21,440,443 bytes/main.dart.js, SHA256
  24718e23ae49cbe9c8817191cab1c1a3d14b86094073a6efde57612b54b00bd1,
  matching packaged56. Chooser2 checkboxes/Cancel, Share/Close, contextual+
  menu13 Basic+File/Escape operate with zero collected console errors. No invite.
- Installed Android APK SHA256 matches
  2010930531d89c0663ac689e37d33923abbd40ad140cb41a47921b17a3bafe40.
  Native56 settled palette inspected against current actual Notion reference,
  both1080x2400/420dpi/font1/dark/3-button navigation. Text target
  [42,1655][527,1781]; no initial filled tile. Scroll viewport ends at2274,
  above system navigation. Initial post-tap frames were transitional; use
  ui45-native56-flat-palette-settled.png and its fresh XML. Screenshot attached
  to Notion comparison board; prior46 images retained.

ADB stalled after install and was restarted via the official daemon. A stale
white splash disappeared after a rotation refresh despite widget tree/first
frame already being present. Cause is not established; no startup code changed.
Rotation restored1/0, no app data cleared; temporary VM forward removed. Native
Notion data retained, original stay-awake3 retained. Build emits existing Kotlin
plugin migration notices; successful build is not a migration-completion claim.

The new matched synthetic fixture is only paragraph/H1: later Web input lost
focus in automation. No full typing or complete paired-fixture pass is claimed.
Whole light/dark/empty/error/resize/focus/dialog/safe-area matrix and actual iOS
remain open. Continue visual refinements before broad functional acceptance.

## Closure receipt

| Record | Resolution |
| --- | --- |
| MUST_REMEMBER.md | Updated current56 and continuation boundary. |
| CURRENT_WORK.md | Source/runtime checks, recovery, partial fixture and next column comparison. |
| VISUAL_REVIEW.md | Scoped UI45 evidence; both95% gates remain open. |
| AGENT_IMPLEMENTATION_20261019.md | Lead-only follow-up after20-worker review. |
| ui43/LIVE_REFERENCE.md | Current Notion column and flat palette observations. |
| _agent_ops/* | Not needed: runtime pack and session tool absent, verified; no fictional records. |

Publication is a component checkpoint; overall M09 is PARTIAL.
