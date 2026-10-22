# M09 — parallel implementation, 19 October 2026

## Objective and current phase

Actual Notion Web AND native Android comparison -> existing UI refinement ->
evidence of >=95% similarity on EACH -> functional regression/fix/retest ->
verified Notion updates and final-tuankiet milestones. Current similarity is
unverified; no old score carried forward. Lead controls browser/ADB sessions.

All work uses the existing D: checkout, preserving prior uncommitted changes.
No C: worktrees. Agents must not revert others' changes, modify files outside
their allocation, commit/push, run broad tests/builds or control shared UI.
First phase is source/reference review; await lead's direct-reference findings
before changing visual values. Lead alone changes dependencies/config/tokens.

## Ownership (no overlapping writes)

###22 October priority continuation

UI36 continuation actually used four Luna Max agents. header_history28 removed
diagnostics after root identified/fixed the shell recognizer; both diagnostic
files now match their clean published baseline. priority28_review delivered
theme invalidation, native clipboard wrapper/helper and tests. Root reviewed,
corrected API/layout/48dp issues, wired production editor and owns all delivered
source now. web_pair35_review wrote only WEB35_CURRENT_PAIR_REVIEW.md;
ui36_matrix_audit wrote only UI36_EVIDENCE_COVERAGE.md. Both reports are bounded
reviews, not new live inspections or percentages. All agents are frozen; root
owns shared layout/config, current source, build36, Chrome/ADB, docs and Git.
Root37/37 focused VM UI cases pass and thirteen-item analyzer is clean. Both
whole-platform95% gates remain unverified; no broad functional QA yet.

Historical allocations below have been superseded by the ownership transfer.

Two actual Luna Max agents reused: header_history28 implemented guarded Web
history/header and later native-only handle style; priority28_review independently
reviewed Label/File/controls and worker lifecycle, then fixed Web generic tap
semantics. Root reviewed source and ran focused checks/actual UI.

Current allocation: header_history28 owns only the two native handle diagnostic
engine files and new mobile_handle_hit_test.dart (if needed); TEMP logs must be
removed before publishing those files. priority28_review owns only engine
editor_component/service/editor.dart plus editor_renderer_theme_test.dart for
renderer-map invalidation after theme change. Root owns all other delivered
files, bridge/public assets/config/docs, builds and actual Chrome/ADB/Git. No
agent may edit another allocation. Both95 gates remain open; no broad QA.

###21 October review continuation

Six fresh Luna Max workers were actually used: web_review21, native_review21,
shell_review21, dialogs_review21, ui_tests_review21, guard_review21. Each wrote
only its named *_20261021.md audit. Lead reviewed all six, correcting box/ink
and nominal-font assumptions; both visual gates stay unverified. This is six
concurrent21 workers in addition to the historical19 cohort, not six-ever.

After reports, web_review21 alone owned EditorStyle/PageBlockComponent and new
editor_block_padding_test.dart to add optional per-node layout padding with
the existing default preserved in both rendering branches. It delivered and
froze those three files. Lead owns all remaining source/config/tests and has
reviewed that patch; focused test27668 is running, no pass claimed yet. No other
worker is editing runtime files, and all ADB/browser/build/Git stay lead-owned.

| Agent | Allowed code files / responsibility |
| --- | --- |
| 1 Shell | lib/presentation/workspace/workspace_shell.dart; new workspace_shell_reference_*.dart parts only; shell/navigation/system safe zones |
| 2 List/Search | lib/presentation/dashboard/dashboard_page.dart, dashboard_content.dart, dashboard_note_card.dart; lib/presentation/notes/notes_list_panel.dart; lib/presentation/labels/label_filter_bar.dart, notes_query_panel.dart |
| 3 Note canvas | lib/presentation/notes/note_detail_surface.dart, note_detail_document.dart, note_detail_editor_form.dart; lib/presentation/editor/rich_note_editor.dart; existing canvas/block typography only |
| 4 Editor chrome | lib/presentation/editor/selection_toolbar.dart, selection_toolbar_layout.dart, basic_block_menu.dart, editor_controls.dart, editor_icon_button.dart, editor_popup_area.dart; formatting/slash surfaces only |
| 5 Dialogs | lib/presentation/common/note_flow_settings.dart; lib/presentation/notes/share_management_dialog.dart, share_management_surface.dart (new stateless layout), note_security_dialog.dart; existing dialogs/sheets only |
| 6 Independent review | docs/m09/INDEPENDENT_UI_REVIEW_20261019.md only; source/ref review and concrete gaps, no app/runtime writes |
| Lead | MUST_REMEMBER.md; other docs/m09 records; workspace_ui_tokens.dart, notes_theme_tokens.dart, note_flow_primitives.dart, main.dart/main_dev.dart; remaining integration, config and tests |

Do not change public constructors/contracts/callbacks without lead agreement.
Keep business rules, persistence, guards and local-first semantics unchanged.
Safe zone: Android bottom gesture AND3-button navbar/IME; iOS top status bar,
notch/Dynamic Island and retained bottom Home Indicator. No unsupported iOS
test claim. New features require Notion proposal and explicit user approval.

## Graph evidence handed to agents

Tier2; project D-kiet-hk7-flutter-midterm-note_ai_app-note-ai-app, generation
2026-10-18T13:23:32Z, ready (78124 nodes/360268 edges). Parent search found
WorkspaceShell/WorkspaceShellState, DashboardPage/State, NotesListPanel,
NoteDetailSurface, RichNoteEditor/State, SelectionToolbar/Layout,
BasicBlockMenu, ShareManagementDialog/State, NoteFlowSettingsSurface/Choice.
Initial named-symbol search returned35 rows, no continuation. Additional
workspace search38/45 rows and editor24/331 rows were output-budget truncated;
these are discovery leads, not exhaustive impact analysis. Read source for DI/
part wiring. Short-name trace WorkspaceShellState.build did not resolve;
use the fully qualified qn from graph search for any trace.

Parent coverage checked23 planned code paths: no recorded parse gaps, but ALL
report metadata_changed/read_source_and_reindex. Therefore every agent must
read the CURRENT full owned source before relying on graph snippets. The
graph cannot prove current visual values. Parent read shell imports/constants,
workspace tokens, surface imports/contracts and menu/dialog entry points.
Recheck coverage for additional files. Do not claim graph access if unavailable.

## Handoff requirements

### Follow-up ownership transfer

The original shell/dialog agents delivered their initial patches. Their later
follow-up turns failed with model-capacity errors and made no edits. Lead now
owns their follow-up changes to workspace_shell.dart and note_flow_settings.dart,
plus the already lead-owned common/note_flow_primitives.dart. Agent2 retains
dashboard files for Search surface/Grid naming follow-up. No concurrent writers
to these files. Candidate3 build completed before releasing the next UI edits.
Agent2 has now delivered/frozen its phase4 Search/Grid refinements. Lead owns
integration review and the two scoped analyzer deprecation corrections in
dashboard_content.dart; no agent is writing that file concurrently.
After candidate4, lead owns all delivered/frozen source for integration.
Lead's next slice is compact note header/More presentation, reusing the same
security/RAG/summary callbacks, and the directly sampled native Home surface.
No agent is editing those paths. Agent6 follow-up review also hit capacity;
lead must review the new slice directly and cannot claim that follow-up ran.

Report exact files/diff, ref image actually viewed, proposed/implemented visual
changes and measured geometry rationale, preserved callback/state ownership,
safe-zone impact and unresolved gaps. No invented percentage or PASS. Wait for
lead review and integrate corrections. Lead will publish paired evidence and
review every diff before any acceptance claim.
