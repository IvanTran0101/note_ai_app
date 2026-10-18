# M09 current work

## Current priority - 18 October2026

User wants visible reference styling now; avoid another repeated full-regression
loop before visual scope is settled. Continue existing-feature-only M09 work.
Local-first canonical writer/access guards and unrelated files stay intact.

## Visible UI checkpoint

Branch final-tuankiet. Runtime811 fingerprint
88194311c59324df3e5bed84cc5903b0317da823601978a7faefe116d279974c
(output/m09/p5-ref-final-source.json). This record is committed with that source.

Implemented: sidebar270/neutral selection/search field/New note header icon;
reading column704; Web Add/Undo/Redo below body; saved-note metadata disclosure
with children kept mounted, actual summary/progress retained; responsive
share panel top-right Web/bottom compact and compact invite form. Existing
callbacks, DTOs, access checks and writer retained. No new product capability.

Web debug build86s and APK61s succeed. Native install-r/device SHA256 EXACT
93612F2599C3F071897C9289C83CD5814FABECAB15153F6BBB1818428040FAF5.
Actual installed Chrome155 at1363x936: retained Unicode/emoji and heading,
Saved/All synced; utility expansion reveals labels/files; share Ready and controls
enabled, then Close. Actual Native API35/1080x2400/420dpi/font1/gesture: same
retained content, utility expand/collapse and Ready sharing panel. Current captures:
- output/playwright/p5-ref-final-web-note.png, web-share.png, web-details.png
  (all use full prefix p5-ref-final-).
- output/m09/p5-ref-final-native-note.png, native-share.png, native-details.png.
No final score or full M09 acceptance. Notion evidence is being published.

## Next

1. Finish remaining visual comparisons: search/settings/protection/selection
   toolbar, dark/locale/rotation/keyboard and small/large-scale layouts.
2. Resolve observed cold-start navigation finding: clicking Notes immediately
   after fresh load remained Loading notes; Home then opening a card worked.
   This has NOT been fixed or accepted. Size-popup/selection final UI matrix
   also remains open; an automation wait for28pt alone is not a product finding.
3. Once visual scope settles, affected regression and one final full matrix,
   separate11-criterion Web/Android scores >=95, Notion ticks and final handoff.

## Earlier verification - bounded predecessor

Runtime810 b775db4b...2a80832 before this reference pass: VM1926/5 configured
skips/0fail, Chrome1728/2 skips on204 mains/17 VM-only exclusions, actual HTTP
rich sync/share/revoke/protected read PASS, analyzer6 scopes clean212.7s.
Actual Chrome all13/Undo returned Saved/All synced; visible tooltip has one
accessible name. Native13 touch choices completed with Unicode retained.
Not every intermediate native header capture confirmed Saved; no full timing
acceptance from that batch. Old noisy timing/viewport experiments are superseded.

Earlier fixes retained: compact phone landscape and delayed caret scroll,48dp
targets, real button semantics, decorative icon scale, open Settings EN->VI,
host English fallback for absent vendor vi catalog, save feedback derived from
dirty state without controller callback context lookup. Two real-crypto tests
use5min budgets (assertions/production600k PBKDF2 unchanged).

## Runtime / tooling

Static8776 serves p5-ref-final-web (session85822). Fixture8796/7/8 retained.
Chrome owner profile output/playwright/m09-chrome-owner. NoteFlow_API35 installed
current APK, original font1.0/density420/accel1/rotation0/gestural unchanged.
R: SUBST is the same D checkout, no new worktree. Preserve local data.
Node Playwright helpers must receive Page parameters; old closures may hold
closed tabs. Native utility label includes Collapsed/Expanded suffix; use fresh
UI hierarchy. Native_tap bare label failure was a harness mismatch, not app error.
Graph Transport closed on list/search/coverage; targeted source fallback used.
_agent_ops pack absent; continuity is in this file, MUST_REMEMBER and acceptance
receipt. Do not stage .playwright-cli/ or final_project.md.

Source/local UI is not live AWS/AppSync/RAG, real GGUF, actual iOS or Wasm proof.
Notion under final flutter: progress3f8f9c7a1aa0817a8f08e793aaaae83d,
main3e9f9c7a1aa080bb85a8d4973595bc21, editor3f5f9c7a1aa0817f9e0bdbe52bb091fe,
score3f7f9c7a1aa0816ab867faaefb40454b. Keep final checkboxes/scores open.
