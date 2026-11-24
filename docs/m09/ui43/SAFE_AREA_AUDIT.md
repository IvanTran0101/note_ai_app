# UI43 workspace and editor safe-area audit

Date: 26 October 2026
Scope: read-only runtime-source audit of the workspace shell, embedded and standalone note editor host, compact workspace menu, and editor/confirmation dialogs. Owned output: `test/presentation/workspace/ui43_safe_area_audit_test.dart` and this report. No runtime source was changed.

## Result

Root's VM widget-test log confirmed one shell/IME defect: before the current integration change, with the note editor active in 3-button portrait, the compact Search action ended at y=836 while the keyboard started at y=564 (`output/m09/ui43-widget-tests.log`, lines 713–716). Current shared source now excludes the compact bar when a compact note editor is active and the inherited IME inset is nonzero (`workspace_shell.dart:301–307`). The revised test keeps ordinary shell-action geometry checks for non-editor states and asserts a representative editor-rail fixture stays visible, at least 48dp, and tappable above the keyboard. This source change still needs the root rerun; the fixture checks shell viewport geometry, not the production editor rail.

One unconfirmed dialog risk remains: `editor_value_dialog.dart` builds equation mode from a 3-line input plus a rendered preview inside an `AlertDialog` whose content is not marked scrollable. No existing test covers short landscape + IME + enlarged text for this surface. The first root run stopped this scenario at Flutter's foundation debug-variable invariant before evaluating dialog geometry; the test now uses `TargetPlatformVariant` and awaits a rerun.

This report does not establish Android device behavior, iOS runtime behavior, or either M09 visual-similarity gate. Synthetic iOS metrics are data-only test inputs; iOS safe-area acceptance still requires a supported actual iOS runtime.

## Source evidence and lead fix points

- [`workspace_shell.dart`](../../../lib/presentation/workspace/workspace_shell.dart): `WorkspaceShellState.build` selects compact mode and composes the root `Scaffold` (lines 329–378). Its full-width `SafeArea(top: true)` reserves the status/notch strip (343–359); the body removes only the already-consumed top padding, then uses `SafeArea(bottom: compact && !compactBottomBarVisible)` (362–378). Current source's editor+IME visibility guard is at 301–307; the Scaffold places the bar at 337–339, and `_buildCompactBottomBar` owns its 48dp controls and bottom `SafeArea` at 575–659. The guard's behavior remains unverified until the root rerun.
- [`notes_theme_tokens.dart`](../../../lib/presentation/notes/notes_theme_tokens.dart): `NoteFlowLayout.isNativePhone` uses the shortest side, so native phones remain in compact layout after rotation (75–97). `keyboardInset` reads physical view insets and compares them with inherited insets; compact editor top inset subtracts the stable top view padding (93–97, 172–175). This is a root-owned geometry decision if the real device matrix reveals a mismatch.
- [`note_detail_surface.dart`](../../../lib/presentation/notes/note_detail_surface.dart): the surface owns no `Scaffold`. Its plain editor path is a keyboard-dismissable `SingleChildScrollView`; the rich editor path puts the content/footer inside its host builder. It hides the page header when a native short editor has an IME inset (around lines 152–300).
- [`note_detail_view.dart`](../../../lib/presentation/notes/note_detail_view.dart): embedded note pages use a `Column` and do not add another `Scaffold`; separately pushed pages use one `Scaffold` with `resizeToAvoidBottomInset` enabled outside the security-busy state (around lines 14–26). The composition root owns this integration path.
- [`editor_popup_guard.dart`](../../../lib/presentation/editor/editor_popup_guard.dart): guarded editor dialogs use `showDialog`'s default safe-area route; guarded sheets opt into `useSafeArea` and add a bottom `SafeArea`. [`editor_value_dialog.dart`](../../../lib/presentation/editor/editor_value_dialog.dart) uses `AlertDialog` with a 3-line input and equation preview in a non-scrollable vertical `Column` (74–105); the callout dialog opts into scrolling.
- [`LIVE_REFERENCE.md`](LIVE_REFERENCE.md): current direct Web observations are available; Android inspection is still in progress. The lead's current safe-area contract requires menus/dialogs to fit after safe insets and IME, scroll when space or text scale is constrained, and preserve native 48dp touch targets.

## Existing evidence

- `test/presentation/notes/note_detail_confirmation_dialog_test.dart` already lays out back/delete confirmation dialogs at 360×640 with a synthetic 220px keyboard inset and checks that the dialog surface ends above the keyboard in light and dark themes. This audit did not run that test.
- `test/presentation/workspace/compact_workspace_menu_test.dart` already covers narrow/large-text menu content with synthetic safe padding and an inset, plus dismissal after rotation or keyboard-metric changes. This audit did not run that test.
- `test/presentation/workspace/workspace_shell_test.dart` covers selected navigation semantics and compact action target size, but it does not inject top/bottom system insets or combine those metrics with portrait/landscape and IME states.

## New regression coverage

`ui43_safe_area_audit_test.dart` adds static widget scenarios for:

- synthetic iOS top/left/right/bottom insets around compact shell controls;
- Android-like 3-button and gesture-style inset matrices in portrait and landscape, with the IME open and closed; during editor+IME states, the shell bar must be absent and a representative editor-rail fixture remains ≥48dp and tappable above the IME;
- an editor equation dialog with a short landscape viewport, synthetic IME inset, and 2× text;
- accessible Search and New note labels.

The scenarios use injected `MediaQuery` metrics and per-test `TargetPlatformVariant`s. The previous exact `find.bySemanticsLabel('Search')` lookup returned no match, so the revised accessibility check inspects the target semantics data for a tap action and a label containing the localized Search/New note copy. These widget inputs do not imitate or certify a real operating system. Root owns test execution and should retain any failing case as an integration finding before changing the shared shell.

## Remaining runtime checks

On Android, verify current-build shell and editor geometry in portrait and landscape with both 3-button and gesture navigation; repeat with the keyboard open and closed, the final scroll position, text scale increased, and any bottom toolbar or sheet open. Confirm all final controls stay visible and tappable above both system navigation and the IME, with no duplicated padding. Inspect the real Android system-bar transitions after changing navigation mode; widget tests cannot validate the OS chrome.

For iOS, retain the top status/notch/Dynamic Island and bottom Home Indicator checks until a real supported iOS environment is available. The synthetic iOS widget case is not runtime evidence. No platform PASS, M09 completion, or similarity percentage is claimed.
