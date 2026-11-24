# UI43 — Search entry and dashboard states

## Reference basis

- The supporting Web search reference is `notion-web-008-search-overlay.jpg`: a rounded search surface with a clear field hierarchy and compact controls.
- The supporting Android search reference is `215_search-landing-recent-pages-portrait.png`: a bottom search field with search, sort, and close controls. Its floating left rail is Android IME UI and is not part of NoteFlow.
- The current direct Web observation records a quiet white surface, dark primary text, muted secondary text, and restrained separators. The current Android Search observation records the search/sort field and separate circular close immediately above the keyboard, with no large dock gap. The dock refinements use these observations; this is implementation evidence, not a claim of platform parity.
- Date headings and result rows belong to the separately owned search-row/composition work and were not changed here.

## Changes

- Reduced the existing native search dock's margins while preserving its single-row field, search/sort/close controls, callbacks, and 48dp sort/close targets. The narrowest width uses smaller side insets to leave more room for the field.
- Simplified filtered-empty content into a compact left-aligned message with a muted icon and the existing Clear action. The no-notes state now uses secondary hierarchy and tighter spacing while preserving its existing create action.
- Changed the loaded-list inline error from a full error-colored card to the same subtle, bordered surface used by the other dashboard error state. Error emphasis remains on the icon and the existing Retry action.
- Error actions now stack at narrow widths and at larger text scales when the available width is constrained. Existing messages, Retry/clear/create callbacks, keys, and semantics remain.

## Added coverage

`test/presentation/ui43/search_entry43_test.dart` covers the search dock at 320dp and 200% text scale in light/dark themes, 48dp actions, empty-state Clear/Create actions, large-text error stacking and retry callbacks in both themes, and a compact loading placeholder.

These tests were added for the lead to run; this worker did not run Flutter tests or shared analysis/build commands. Current Web/Android similarity gates remain unverified until the lead reviews the combined screens and records paired evidence.
