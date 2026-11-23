# UI43 editor controls

## Reference and scope

The current lead-owned `LIVE_REFERENCE.md` records an actual Notion Web note at
1280x720: a quiet white document, compact top actions, muted hierarchy, and a
narrow elevated rounded popup for selected text. It does not authorize new
actions. The direct Web control observations in `PRIORITY_UI28.md` record a
quiet Add block affordance while idle, revealed by hover, editor focus, or
keyboard focus; existing Web history remains in More. The mapped Notion
Android editor rail keeps Redo before Undo. Preserve the app's native order:
Add block, Redo, Undo.

## Changes

- Wide Web controls remain quiet on the idle canvas, but become visible when
  text is enlarged so the icon-only affordance is discoverable. Existing hover,
  editor-focus, keyboard-focus, and accessible-navigation reveal behavior stays
  intact; compact layouts remain visible.
- Wide-Web icon targets expand from 28px to 48px when text is enlarged or
  accessible navigation is enabled. Default wide-Web sizing stays compact;
  native sizing, callbacks, history ownership, and native order are unchanged.
- `native_editor_rail.dart` required no geometry change: it reserves a 48px
  slot and derives the root-overlay rail position from the IME inset and safe
  padding. New coverage checks the controls remain above the keyboard.

## Added widget coverage

`test/presentation/ui43/editor_controls43_test.dart` covers wide-Web hover and
semantics reveal, visibility at 150% text scale, native Add/Redo/Undo order and
semantics with a 280px keyboard inset, and wide-Web 28px/48px target sizing for
default, enlarged-text, and accessible-navigation modes. The wide-Web target
test is browser-only; the native rail test is skipped on Web.

The root agent owns running these checks, analysis, builds, and actual Web /
Android interaction. They have not been run in this worker turn. No platform
PASS or similarity percentage is claimed.
