# UI43 — 20 Luna Max ownership and integration plan

26 October 2026. User explicitly resumed M09 UI/UX with at least20 Luna Max workers and lead implementation/final review. Baseline24000ff, final-tuankiet, tracked tree clean; preserve .playwright-cli/ and final_project.md. No worktrees or dependency/config/lockfile changes.

## Shared contract

- UI/UX of EXISTING capabilities only. No new feature from Notion refs; proposals go to Notion for approval. Basic blocks13, no Page/Link to page, existing Media/File and size12-48 remain.
- Preserve public constructors, named params, callbacks, keys, semantics meaning, permissions/local-first writer and UI41/42 fixes. No Domain/Application/Infrastructure/storage/codec changes from workers.
- Visual grammar: warm quiet surfaces, neutral hierarchy, body Web16/24, native16 scalable; header/title and compact controls as actual reference. Native touch48dp except established nonoverlap toggle target, safe above IME/system bars. Existing profile/AI/security use adaptation, not invented Notion capabilities.
- Every worker reads current owned sources in full before editing. Parent graph Tier2 project D-kiet-hk7-flutter-midterm-note_ai_app-note-ai-app, generation2026-10-24T15:27:12Z.44 paths checked, all no_recorded_issue but metadata_changed; exact-source fallback REQUIRED. No completeness claim. Broad positive search paged100/211; not exhaustive. DashboardNoteCard inbound from DashboardContent._buildNoteCollection/_buildSearchResults; constructors unchanged.
- Workers are not alone. Do not revert/format/edit another owner's files. No shared tests/build/analyze/pub/Git/ADB/browser/Notion writes. Parent owns those resources. dart format OWN files only is allowed. Add tests but root runs them.
- Each worker owns its listed source files, test/presentation/ui43/<task>_test.dart and docs/m09/ui43/<task>.md. No other runtime file creation without lead allocation. If no evidenced gap exists, report no change rather than churn.
- Start read-only audit/local-ref inspection now. Wait for lead's current direct Notion observations in LIVE_REFERENCE.md or message before changing visual values. Preserve private ref account/text; synthetic data only in app/evidence.
- Report changed files, measured/grounded mismatch, fix, test scenarios, unrun checks, integration risks. No unsupported >=95% or PASS claims. Lead reviews every diff and actual combined runtime.

## Exclusive ownership

| Worker | Source ownership | Responsibility |
| --- | --- | --- |
| cards43 | lib/presentation/dashboard/dashboard_note_card.dart | Home cards: density, title/snippet hierarchy, muted file/note icons, hover/focus and compact/native sizing. |
| recents43 | lib/presentation/dashboard/dashboard_recent_rail.dart | Home recents rail: Notion-like compact cards, consistent gaps and clipping/keyboard-safe access. |
| search_entry43 | lib/presentation/dashboard/dashboard_search_dock.dart<br>lib/presentation/dashboard/dashboard_state_views.dart | Search entry + loading/empty/error UI: quiet surfaces, existing Retry states and accessible resizing. |
| search_rows43 | lib/presentation/dashboard/dashboard_search_sections.dart | Search result rows: hierarchy, density, grouping and hover/selection without changing query/filter behavior. |
| notes_list43 | lib/presentation/notes/notes_list_panel.dart<br>lib/presentation/notes/animated_note_list.dart | Notes list UI: consistent list/grid/pin/action density and narrow/text-scaled layout. |
| label_chips43 | lib/presentation/labels/note_label_chips.dart<br>lib/presentation/labels/label_filter_bar.dart | Labels/filter chips: minimal Notion adaptation, readable compact selected/remove controls and touch safety. |
| label_dialogs43 | lib/presentation/labels/note_label_editor.dart<br>lib/presentation/labels/label_manager_dialog.dart | Label chooser/manager: restrained popover/dialog spacing, keyboard focus, narrow width and no overflow. |
| settings43 | lib/presentation/common/note_flow_settings.dart<br>lib/presentation/common/note_flow_settings_choices.dart | Settings UI: Notion-like grouping, compact choices, dark/light and small-screen/IME/text-scale resilience. |
| profile43 | lib/presentation/profile/profile_page.dart<br>lib/presentation/profile/profile_page_sections.dart | Existing Profile UI: apply neutral form hierarchy and adaptive layout, preserve avatar/account actions and honest errors. |
| safe_audit43 | Audit/test only; no runtime writes | Read-only safe-area/accessibility audit of workspace shell, editor, dialogs; own only test/presentation/workspace/ui43_safe_area_audit_test.dart and docs/m09/ui43/SAFE_AREA_AUDIT.md. Identify exact gaps for lead; no runtime edits. |
| avatar43 | lib/presentation/workspace/compact_workspace_menu.dart | Avatar menu: align Notion minimal popup groups, spacing, anchors, scrolling/focus and touch targets. |
| blocks43 | lib/presentation/editor/editor_renderers.dart<br>lib/presentation/editor/accessible_builders.dart | Existing rich block appearance: heading/list/task/quote typography/spacing/colors and accessible rendering. Preserve UI42 gutter and toggle. |
| editor_controls43 | lib/presentation/editor/native_editor_rail.dart<br>lib/presentation/editor/web_editor_controls.dart<br>lib/presentation/editor/editor_controls.dart | Editor controls: quiet Notion rail/menus for existing +/redo/undo, safe above IME, hover/focus/touch sizing. |
| selection43 | lib/presentation/editor/selection_toolbar.dart<br>lib/presentation/editor/selection_toolbar_layout.dart<br>lib/presentation/editor/selection_toolbar_dialogs.dart | Selection toolbar/format dialogs: Notion styling, selection-size presets/custom12-48 preserved; fit narrow/IME/text scale, no new formatting. |
| block_menu43 | lib/presentation/editor/basic_block_grid.dart<br>lib/presentation/editor/basic_block_menu.dart<br>lib/presentation/editor/basic_block_menu_choices.dart | Slash/+ palette: Basic13 + existing Media/File; Notion list/grid/prompt, selected/hover state and compact safe scroll; no Page/Link to page. |
| file_ui43 | lib/presentation/notes/attachment_file_row.dart<br>lib/presentation/notes/attachment_inline_picker.dart<br>lib/presentation/notes/attachment_document_controls.dart | Existing file UI: restrained row/actions and Upload chooser adapted to Notion; long name/size, states, keyboard/touch safe. Preserve UI41/42 inline/removal behavior. |
| password43 | lib/presentation/notes/note_security_dialog.dart<br>lib/presentation/notes/note_security_panel.dart | Password-note UI: minimal Notion-style form/sheet, clear labels/errors, keyboard-safe scroll, current set/change/remove/unlock actions unchanged. |
| sharing43 | lib/presentation/notes/share_management_dialog.dart<br>lib/presentation/notes/share_management_surface.dart | Existing share dialog/sheet: match Notion invite/member permission presentation, dense neutral Web + accessible native, no Publish/new roles. |
| rag_ui43 | lib/presentation/rag/rag_page.dart<br>lib/presentation/rag/rag_answer_cards.dart<br>lib/presentation/rag/rag_scope_selector.dart | Existing Ask notes UI: apply Notion visual grammar to prompt/results/citations/scope, preserve unavailable/consent states; no new AI features/API. |
| summary_ui43 | lib/presentation/notes/note_summary_feedback.dart<br>lib/presentation/notes/note_summary_content_motion.dart<br>lib/presentation/notes/summary_consent_dialog.dart | Existing summarization feedback/consent UI: calm readable hierarchy, adaptive error/actions, motion accessibility, no generation behavior changes. |

## Lead work in parallel

Root exclusively owns workspace_shell.dart/sidebar/safe-area integration, DashboardContent/DashboardPage composition, note-detail surface/editor form/view, all shared tokens/theme/primitives/localization/config/dependencies, root continuity records, LIVE_REFERENCE.md, Notion progress, browsers/ADB, package builds, tests and final publication. Current live reference, integration checks and source fingerprints are required before claim. UI similarity >=95% separately Web/Android remains unverified until paired evidence covers mandatory screens/states; no broad functional acceptance before that gate.

## Handoff and final review27Oct

All20 workers delivered; root now owns review repairs in every handed-off file.
Explicit helper allocations: label_dialog_layout.dart to label_dialogs43, then
root repair; share_management_desktop.dart exclusively root after actual Chrome
intrinsic-layout failure. Root-only tests sharing_desktop43_test.dart and
workspace/ui43_navigation_targets_test.dart supplement worker tests. Source53
passed scoped checks and actual popup/IME smoke; consolidated evidence and
remaining gates are in ../UI43_REVIEW.md. Worker reports retain their historical
unrun-check statements; the consolidated lead ledger records subsequent runs.
