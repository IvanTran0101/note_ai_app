# Native visual and lifecycle audit — 21 October 2026

## Scope and evidence

Read `MUST_REMEMBER.md`, `docs/m09/CURRENT_WORK.md`, and
`docs/m09/VISUAL_REVIEW.md` before reviewing the current working-tree source.
This is a source review of the source16 Basic Blocks sheet/rail changes only.
No runtime, test, emulator, browser, build, or Git command was run for this audit.

Direct Notion Android evidence: `output/m09/notion-native21-grid.png` and
`notion-native21-focused.png` show the existing editor rail above the Basic
blocks sheet / IME. Existing app evidence is source15:
`p6-parallel15-native-grid.png` and `p6-parallel15-native-h2.png`.
Source15 predates the rail-in-sheet change; it is not source16 visual proof.
The older source9 three-button capture is also not source16 proof.

The visible source16 structure now places existing Add/Undo/Redo controls and
Close in a 48dp row above the Basic blocks heading. `toolbarOwnsClose` removes
the duplicate close button. Transparent barrier styling preserves the visible
note behind the sheet. This is closer to the observed Notion hierarchy. The
actual Notion rail contains additional actions that this app does not have;
they remain excluded under the existing-features-only rule. No similarity
percentage can be assigned from this bounded review.

The graph index is dated 18 October 2026 and does not represent this latest
working tree. A current-path coverage call failed with MCP “Transport closed”;
findings below come from direct reads of the current source, not graph claims.

## Findings and follow-up

1. **[P2, verify] Stale slash state on pre-route rejection.** In
   `rich_note_editor.dart:121-130`, the original selection snapshot is checked
   again after hiding the IME. If the editor is still mounted but that snapshot
   has expired, the method returns without calling `slash.close(cancel: true)`.
   No block command is applied, and `SlashCommandController` listens for adapter
   changes, so this is only a possible ephemeral stale-menu state. Close the
   touch menu state on this mounted/rejected branch and verify revoke/revision
   change during IME dismissal leaves no stuck slash state and applies no block.

2. **[P2, layout risk] Short landscape sheet height.** The native menu computes
   its sheet height as 240–320dp in `basic_block_menu.dart:121-128`; the new
   rail adds 48dp in `rich_note_editor.dart:156-186`. The route uses
   `isScrollControlled`, `useSafeArea`, and a bottom `SafeArea`, and the grid
   itself scrolls, which covers ordinary portrait geometry. No source16
   landscape capture is available. Confirm the combined sheet fits a short
   landscape viewport with both gesture and three-button navigation. If it
   does not, cap the grid's available height from the parent constraints; keep
   the grid scrollable.

3. **[P2, accessibility layout risk] Fixed Basic blocks header at large text
   scale.** The native header remains 48dp and adds 14dp top padding
   (`basic_block_menu.dart:194-213`). The grid switches to one column and
   grows row height above 1.5x (`basic_block_grid.dart:23-39`), but the header
   does not grow. Verify 2.0x and larger text scaling; if clipped, remove the
   fixed top padding or size/center the header from the scaled text height.
   The menu rows remain scrollable and use at least 48dp targets.

4. **[P3, accessibility polish] Close tooltip is not localized.** The new
   source16 close button uses the literal English “Close block menu”
   (`rich_note_editor.dart:169-172`), while the existing menu labels localize.
   Use the existing localized string for the tooltip; this does not affect
   command behavior.

## Guard and safe-area review

The touch flow captures `slash.snapshot` and `slashStart` before hiding the
keyboard, checks `adapter.accepts(... popupOwnsFocus: true)`, passes the same
snapshot into `guardedEditorSheet`, then applies the selected existing command
against that snapshot. `EditorPopupGuard` closes its route when the adapter
is inactive or no longer accepts the snapshot. This remains fail-closed.
`_controls` still returns no controls for a non-editable adapter, and the
normal editor controls/history callbacks remain owned by `EditorControls`.

The sheet helper uses scroll-controlled routing plus SafeArea. The floating
caret rail uses `EditorPopupArea` bounds that subtract top padding, bottom
navigation padding, and IME inset, then places the 48dp controls above the
keyboard margin. This is sound at source level. Source15 gesture-mode and
source9 three-button images provide historical geometry evidence only; capture
source16 on both navigation modes before recording this pass as verified.

## Decision

Source16 is a promising hierarchy correction, not a tested visual acceptance.
Resolve the stale-state branch and inspect source16 at portrait, landscape,
font scale 1x/2x, gesture navigation, and three-button navigation. Keep both
platform similarity gates **UNVERIFIED**; this audit does not authorize broad
functional regression or acceptance.
