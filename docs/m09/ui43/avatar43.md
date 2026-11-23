# UI43 avatar popup refinement

## Evidence boundary

The lead's current `LIVE_REFERENCE.md` records a real Notion Web document and a
quiet popup grammar: white elevated surface, rounded corners, a restrained
separator, and compact existing actions. It does not record a direct Web
avatar-menu capture. The lead also directly inspected the Android avatar menu
on 26 October (`ui43-notion-native-avatar`): a dark elevated popup below the
avatar, about 288dp wide, with roughly 48dp icon-and-label rows and a divider
after the first workspace-switch item. NoteFlow has no workspace-switch
action, so the existing quick-action group remains in that position without
adding a new action. The mapped Android workspace-menu references
`100_03_workspace-menu-current-account-portrait.png`,
`073_03_profile-workspace-menu-portrait.png`, and
`061_03_workspace-menu-landscape.png` show a menu attached near the avatar,
icon-and-label rows, and a subtle group separator. These are supporting local
references. The separate account-switcher sheet is not part of this change.

## Change

`compact_workspace_menu.dart` keeps the existing items, order, keys, semantics,
callbacks, and public API. Group dividers now leave a small amount of breathing
room. The menu anchor is aligned to the avatar's lower-left edge and clamped to
the safe viewport. Its height uses the larger safe space above or below the
anchor after system and keyboard insets, allowing the existing menu scroll view
to handle constrained screens. The item text inherits the theme's body style
and text scaling; rows retain a 48dp minimum target. Opening the menu requests
focus for keyboard traversal.

## Added checks (not run)

- A short viewport with a bottom inset and 200% text scale can scroll to the
  final existing action without layout exceptions; item rows remain at least
  48dp tall and existing group dividers remain present.
- Keyboard arrow and Enter input can select an existing action from the popup.

The lead owns test execution and combined Web/Android review. This patch has no
test, analyzer, build, or NoteFlow device result yet. The direct Notion Android
avatar menu is observed; the combined NoteFlow visual review and both M09
similarity gates remain unverified.
