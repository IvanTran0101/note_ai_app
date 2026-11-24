# P4 editor QA inventory

Status: in progress; no final platform score or P4 acceptance.

Verified807 checkpoint: full VM1898/5 configured skips/0fail; installed
Chrome1700/2 configured skips/0fail on199 mains including real local HTTP;
full scoped static plus modified TableCol clean. Native matching A76328E3
physical row4->5->4->5->4 and popup no longer covers Q. Cold reopen keeps
equation/color/table and Q28/H4/Unicode. P4_EDITOR_CHECKPOINT.md is the bounded
receipt. P5 Native landscape/spacing, full current UI matrix and separate
reference scores remain open; this does not claim full M09 acceptance.

17Oct follow-up9949cc54: new4-case AX regression fails4/4 before fixes;
after fixes focused82/82 and full VM1891 PASS/5 configured skips/0fail (2m41).
Final static/build/197-main Chrome with local HTTP opt-in still pending.
No runtime edit during current serial build. Current installed805 Native
functional matrix selected ALL13 choices through actual + sheet, using fresh
UI hierarchy for every action. H1/H2/H3/H4 show distinct painted heights;
Text/list/numbered/todo/toggle/callout/quote/divider/table preserve test body.
Todo checked=true then UI Undo checked=false; toggle collapse/expand worked.
Receipts output/m09/p6-native-block-*-observed plus h1/h2-verified and todo files.
Early rapid H2/H3/H4 coordinate batch raced repaint/Undo; it is rejected evidence,
not a product/data-loss defect. Final new APK UI/core smoke remains required.

17Oct806: full VM1887 PASS/5 configured skips/0fail (2m58), including new
EN/VI size49 refusal/28 apply and semantic action ownership assertions. Focused
layout/sync/shell68/68 and action/header3/3 also pass. Source806 fingerprint
f8b39fd4c002371b6858c31a0c85baceee2f8dedbda7762c9efa514026f255cb.
Broader196-main Chrome matrix is running; no final browser receipt yet. Refs
and baseline805 captures now recorded in Notion scorecard; both platform totals
remain unscored. Source806 is newer than installed805 APK and served805 Web.

16Oct native fixes: oversized/fractional caret auto-scroll reproduced (before
fractional8pass/16fail), fixed by viewport-bounded padding/step, no-progress stop
and next-frame yield. VM24/24, installed Chrome24/24 pass. Chrome runner Windows
URI bugs handled in an ignored copy of Flutter tools; same assertions/SDK
CanvasKit, installed SDK untouched. See CURRENT_WORK for reproducible invocation.
Actual B029 Android: full/h4 -> touch Heading4 -> continuation, fresh idle
hierarchy, no ANR; local saved/synced. Stop API8796 reverse, force-stop/reopen,
H4 survives; append_OFFLINE16 -> Saved locally/1pending; force-stop/reopen again
retains text/format/pending; restore8796/Retry -> All synced. Synthetic note only.
Images p4-final-scroll-*.png and p4-offline-*.png (ignored output/m09).

Next discovered touch+ menu frame bug: controller visible while no repaint
scheduled. New widget regression fails before fix; requesting visual update
after queuing menu callback passes. Combined menu/autoscroll/controls27/27 VM.
New APK72763 building; retest touch+ before full P4 acceptance. Native keyboard
Enter inserts newline; actual conversion uses the touch menu. No hardware-Enter
parity, Vietnamese Telex or final platform-score claim from these receipts.

Latest16Oct: clean-source full VM1830 PASS/5 configured skips/0 failures;
focus/capacity subset VM15/15 and installed Chrome15/15 PASS. Scoped analyzer
No issues found. Broader installed Chrome21 mains is in progress. Actual Chrome
Title -> /h4 -> Unicode/emoji and /table -> Enter -> A1/B1 Tab/ShiftTab -> local
autosave/reopen passed before trace cleanup. Clean-source actual retest/native
still required. See CURRENT_WORK.md for exact receipts and rejected focus fixes.
Maximum512-block/71,569-character Web debug widget fixture builds1633ms,
scrolls119ms, edits476ms including test pumps/semantics. This proves capacity,
not a profile-mode responsiveness grade. No UI score inferred from timings.

Latest automated checkpoint15Oct: focused editor + RAG composition/sharing/
security81/81 PASS, and actual painted font28 across all8 textual block renderers
8/8 PASS (including accessible checked-todo toggle + undo). First broad run
1802 PASS/5 configured skips/8 failures used old TextField expectations; those
eight are migrated to the rich editor with the same permission/draft/citation
assertions. Fresh broad retest is running; no full acceptance from focused counts.

Actual Chrome evidence: custom49 refused/28 applied; executable URL refused/
HTTPS applied; incomplete fraction refused; valid fraction+root applies while
API8796 is aborted, Saved locally/pending1, Back/open preserves painted math/28.
Retry after reconnect reaches All synced. This proves offline API editing,
not full offline-browser startup. Screenshots in ignored output/playwright.
Native P4 product UI, full block/toolbar matrix and final scores remain pending.

Plan reconciliation: Vietnamese accent-insensitive aliases, outside-click slash
cancel, callout icon/tone chooser, touch divider delete, equation-to-expression
with per-run styles, table exit paragraph, mixed format labels and paste limit
feedback are implemented; their new command tests pass. Full actual UI pending.

Current source is uncommitted on final-tuankiet after P3 23f3652.
Synthetic notes only; preserve existing user and QA data.

| Claim/control | Functional check on Chrome and Android | Visual evidence/state |
| --- | --- | --- |
| Local rich editing | Offline type/format/save, cold reopen, reconnect preserves marks/block IDs | Open note + Saved/header; no error |
| Slash13 and touch + | Filter H4, arrows/Enter, Esc literal text, URL slash, 13 exact choices | Menu near caret, viewport/keyboard fit |
| Text/Heading1–4, lists/todo | Convert, newline, indent/outdent, checkbox, undo/redo retains IDs/text | Typography and selected state |
| Toggle/callout/quote/divider | Nested children, expand/collapse Viewer without mutation, convert preserving children | Container and readonly controls |
| Selection marks | B/I/U/strike/code/color/highlight/clear, mixed selection, one undo | Floating toolbar adjacent selected range |
| Font size | Presets12/14/16/18/24/32, custom12–48, invalid/cancel/reset, selected range only | Mixed/picker labels, no overflow |
| Link | Create/edit/remove, valid HTTPS/mailto; executable URL refuses | Link styling/dialog error |
| Inline equation | Create/edit/offline preview/invalid/cancel; atom and plain projection | Painted math/error and selection |
| Table | Inline multiline cells, Tab/ShiftTab, add/remove rows/columns, header flags/overflow | Header tint, long grid horizontal scroll |
| Clipboard/IME | External plain paste; Vietnamese/emoji/newlines, composition not interrupted | Real keyboard + selection, stable cursor |
| Security/sharing | Owner lock/unlock; Viewer readonly/expand; Editor format; revoke/logout clear selection/content and retain encrypted draft | Masked note, no stale popup apply |
| Remote edits/conflicts | Dirty format-only local draft vs same-text rich remote; explicit cloud/local/copy | Notice + choice; no lost formatting |
| Search/AI citations | Derived projection incl equations/tables/closed toggles; reveal without mutation | Correct visible selection after reveal |
| Adaptive/accessibility | Resize/rotation, keyboard insets, long title, text scale, semantics/focus | Paired screenshots and accessibility state |

Exploratory cases: stale size/link popup during access change; large/plain HTML
paste; Enter in an empty document; last table cell and single-row/column delete;
rapid save/undo; scroll to a citation in a collapsed offscreen toggle.

## Automated receipts

- Foundation expansion initially19 PASS/2 failures: slash undo and table position
  failed. Fixed replacement transaction coordinates; no skips added.
- First actual host tests80 PASS/3 failures exposed the editor Overlay requiring
  bounded height. Production surface now uses the upstream document scroller
  with the title/summary/attachments in its header, rather than unbounded nesting.
- Fresh focused VM83/83 PASS (`output/m09/p4-editor-vm-4.txt`), including legacy
  no-inflation, format-only autosave, title-only rich preserve, new empty document,
  command undo/redo, table IDs, projection and prior detail/RAG/layout cases.
- Actual Chrome/native and final regression remain pending below.

Further receipts: focused VM113/113 including prior workspace/RAG/detail cases;
actual installed Chrome found new-note editor reuse after autosave and input/
selection loss during UI/ACK rebuilds. Workspace identity and stable engine/ACK
retention fixed (5/5 regression). Actual slash /h4 filter/Enter, typed Vietnamese/
emoji, H4 selection and size picker24 work; rendering test now covers explicit
range size overriding heading defaults. Toolbar clipping and modal stacking are
being corrected. No platform score or full P4 acceptance yet.
