# UI43 RAG UI

Status: scoped UI adaptation implemented; Web/Android review and the lead's
shared checks are pending. This is not a Notion parity or similarity claim.

## Scope

Owned runtime files:

- `lib/presentation/rag/rag_page.dart`
- `lib/presentation/rag/rag_answer_cards.dart`
- `lib/presentation/rag/rag_scope_selector.dart`

The assigned test path is `test/presentation/ui43/rag_ui43_test.dart`. The
assigned report is this file. Keep the change to existing Ask notes UI; preserve
constructors, callbacks, keys, state behavior, consent, and source-open guards.
No endpoint, AI capability, localization, shared token, or service changes are
in scope.

## Current source behavior

- `RagPage` renders the existing consent tile, scope, multiline question field,
  Ask/Cancel actions, typed failure, and the current answer/refusal result in a
  constrained scroll view. Ctrl/Cmd+Enter submits; plain Enter remains a line
  break. The page forwards scope and question intent to the existing service.
- The question field now keeps extra scroll clearance around its caret, and
  dragging the page dismisses the IME so lower controls can be reached on a
  short viewport.
- `RagScopeSelector` displays only the route's allowed note/account choices and
  reports a selection to the page. Its chips wrap at narrow widths and use a
  padded target in compact layouts.
- `RagAnswerCard` shows the exact question and selectable answer. Citation rows
  retain the exact source ID, title, and quote and call the existing navigation
  owner. The ID, title, and quote now stack for narrow and enlarged text; the
  busy source and refused-open message remain visible. The answer and refusal
  surfaces use the quiet subtle surface, and typed errors have a wrapped,
  live-region treatment with an error icon. The `NOT_ENOUGH_CONTEXT` card
  continues to display the question and localized safe response.
- The consent tile remains the canonical control. Its current loading, known,
  unknown/refresh, error, disclosure, allow, and revoke states stay owned by
  that widget and `RagAppService`.

The three owned runtime files were read in full after graph coverage reported
`metadata_changed`. The current graph generation is 2026-10-26T09:59:10Z;
coverage is best-effort and does not prove completeness. The new UI43 test is
not tracked by that graph generation and was read directly.

## Reference and adaptation

The local Web search capture (`hinhanh/UI_web_ref/notion-web-008-search-overlay.jpg`)
shows a roomy search overlay with a leading query field, compact filter row,
grouped results, and a separate preview. The Android search capture
(`hinhanh/UI_android_ref/215_search-landing-recent-pages-portrait.png`) shows a
large Search heading, a prominent Ask entry, grouped recent rows, and a query
field above the navigation gesture bar; the floating rail is Android IME UI.
These are supporting search references, not a direct pair for this Ask notes
route. Private reference text and account details are not app content.

The lead's current Web observation in `docs/m09/ui43/LIVE_REFERENCE.md` records
a white document surface, quiet 44px top strip, muted secondary text, light
separators, and restrained blue actions. The direct observation does not
contain a like-for-like RAG screen; Android inspection is still in progress.
These RAG changes adapt that visual grammar to the existing route. They do not
claim to match an AI/search screen or establish platform similarity.

## Existing test coverage and pending checks

`test/presentation/rag/rag_page_test.dart` covers consent-gated Ask, exact
question/scope forwarding, cancel, answer/failure retention, scope clearing,
refusal, and typed failures. `test/presentation/rag/rag_page_accessibility_test.dart`
covers a 320px viewport at 2x text scale, keyboard submission, source-button
semantics, and disposal behavior.

The assigned UI43 test file now covers synthetic citation reflow at a 320px
viewport with a simulated 260px IME inset and 2x text scale, compact scope
target size, plus an unavailable-query message at 1.6x text scale. Tests were
not run by this worker. No analysis, builds, browser checks, or Android checks
were run either; the lead runs shared verification and reviews the combined
runtime. Web/Android similarity remains unverified.
