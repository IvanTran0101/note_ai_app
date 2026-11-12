# M09 Settings, Share, and Password UI Audit

**Date:** 21 October 2026
**Purpose:** record current visual evidence and remaining comparison gaps for Settings, Share, and note security.
**Decision:** visual similarity remains **UNVERIFIED**; this audit assigns no percentage and does not open the M09 UI gate.

## Evidence reviewed

| Surface | Actual Notion reference | NoteFlow capture | Evidence limit |
| --- | --- | --- | --- |
| Android Settings | `output/m09/notion-native13-settings.png`; earlier scroll pair `notion-gpu-settings.png`, `notion-settings-gpu-scroll.png` | `output/m09/p6-parallel13-native-settings.png` | NoteFlow capture is round13; workspace source is round15. Scroll positions and network states differ. |
| Android Share | `output/m09/notion-native-share-oct19.png` | `output/m09/p6-parallel10-native-share.png` | NoteFlow capture is round10 and has no recipients; Notion shows the signed-in owner and Notion-only sections. |
| Web Settings | Direct Notion measurements recorded in `docs/m09/CURRENT_WORK.md` and `docs/m09/VISUAL_REVIEW.md` | `output/playwright/p6-parallel7-web-settings.png` | App image is round7; no paired round15 screenshot. |
| Web Share | Direct Notion DOM measurement: 456px wide, top 44px, radius 12px, background RGB(37,37,37) | `output/playwright/p6-parallel9-web-share.png` | App image predates round10 sizing/color corrections; no paired round15 screenshot. |
| Note password/security | No matched direct Notion capture in this evidence set | No current paired NoteFlow capture | Cannot compare or score this flow yet. |

The native reference/app screenshots use the 1080x2400, 420dpi Android 35 AVD. Its physical top cutout/status inset is 128px (48.76dp); the gesture navbar is about 63px and three-button navbar about 126px. NoteFlow captures include the 20dp `LOCAL DEV` strip (52.5px at this density); subtract that strip only when comparing screen geometry. Private account details in the native Notion Share screenshot stay local and must not be uploaded to Notion or Git.

## Findings

### Android Settings

- Both captures use the warm light surface and a centered Settings header with a back control. After accounting for the local development strip, the 48dp NoteFlow header aligns closely with the Notion header. Keeping a 48dp touch target is a reasonable native adaptation to Notion's approximately44dp header.
- The body states do not match. Notion is scrolled to **Preferences** (with the preceding notification rows partly visible); NoteFlow is at the top of **Appearance and language**. NoteFlow also shows an offline Ask-notes permission error while the reference is in a clean state. Do not interpret these captures as a whole-screen comparison.
- NoteFlow currently orders Theme and Language before Ask-notes, Profile, Change password, and Log out. The reference's visible Preferences order begins with Password/Passkeys, then Theme. Only existing NoteFlow controls may be rearranged; do not add Passkeys, notification integrations, or other Notion-only settings.
- The round13 image shows a double-chevron dropdown icon. Current compact source uses a single down-chevron, so this source change still needs a fresh rendered capture. The screenshot is stale evidence for that detail.

### Share

- Native Notion opens a light sheet at about168px from the physical top (64dp total from screen top), with rounded top corners and a centered title. NoteFlow round10 opens at about223px; subtracting the 52.5px development strip gives about170.5px, within roughly1dp of the reference. Its `64dp - actual safeTop` spacing plus the route's top `SafeArea` accounts for the 128px cutout without assuming a 24dp status bar.
- NoteFlow's compact sheet paints behind the navigation bar and puts its scroll content inside bottom `SafeArea`. The supplied screenshot has an empty recipient state, so it does not demonstrate the last row/action with a long recipient list or the keyboard open. Gesture and three-button modes still need current-source visual evidence.
- The screenshots show different data: Notion displays its owner row and account-level General access/Advanced/Share link sections; NoteFlow displays its existing invite/role/Share controls and “No recipients yet.” Compare only the shared invite/member concepts. Do not add Publish, general-link access, Advanced, or Share link features to NoteFlow.
- Web source was adjusted in round10 to the measured 456px width, 44px top offset, 12px radius, and `#252525` dark surface. The available Web image is round9, before those changes (about458px and the earlier surface color); a current-source browser capture is required before calling the match verified.

### Note password/security

- The current flow uses the existing `NoteSecurityService` actions and remains a scrollable `AlertDialog`; the image set contains no matched Notion lock/unlock or password-change state. Do not score this surface from the unrelated account-password row in Notion Settings.
- The dialog keeps the existing masked password fields, validation, offline-unlock option gating, cancel/apply behavior, busy-state barrier, and session-change cleanup. No new security action is implied by this visual audit.
- At larger text scales the Share header grows from48dp to64dp and allows two title lines. Settings and password dialogs still need paired captures at increased text scale and with the keyboard open to verify that controls remain visible and scrollable.

## Existing callbacks and access/session fences reviewed

- `NoteFlowSettingsSurface` and `NoteFlowSettingsChoice` provide layout around the existing settings children. The Theme callback still rejects stale session generations and persists through the existing application service; the UI extraction does not create a new preference write path.
- Opening Share still saves a dirty note first, checks `canManage`, and requires the existing sharing service. The dialog receives the same note identity and only stays current while the widget is mounted, the service instance is unchanged, the security session generation matches, and `canManage` remains true.
- Share list/change/revoke/reactivate state is updated only after the service confirms the command; session events close the dialog, and stale requests are ignored. Offline/unavailable errors remain explicit.
- Security still saves pending note edits before the action, cancels an active summary, passes session changes and `isCurrent` into the existing dialog, and rereads the protected note afterward. A session change clears password/OTP controllers and closes the dialog.

## Remaining blockers before visual acceptance

1. Capture the **current round15** NoteFlow source on Web and Android; the images listed above predate it.
2. Capture matching light/dark Settings states at the same scroll position and network state. Compare only capabilities NoteFlow already has; retain the 48dp Android touch target and safe insets.
3. Capture Share with equivalent invite/recipient state on both sides. On Android, include keyboard open, long recipient list, gesture navbar, and three-button navbar; verify the last actionable row stays above IME/navbar.
4. Capture NoteFlow password/lock UI against a directly inspected equivalent state where one exists. If there is no equivalent, record the intentional functional difference and keep the similarity contribution unverified rather than comparing it with account settings.
5. Recheck Web dark Share after round10 and collect the matching current-source screenshot. Recheck Web/Android at increased text scale and ensure headings, actions, and safe areas remain visible.
6. iOS top cutout/Status bar/Dynamic Island and Home Indicator remain unverified; Android evidence cannot close that requirement.

No tests, runtime changes, or rating were made for this document-only review. The old Web/Android self-ratings remain withdrawn; both `>=95%` gates remain open.
