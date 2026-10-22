# M09 Android38 Home, menu, and Theme review — 22 October 2026

## Evidence boundary

This is a static visual comparison of current app38 light captures against the
latest direct Notion37 light references. The app38 package/device SHA matched
(`0705d4527f19df07c07f887a656cdfdc14e87304b85b5d21c753e359c4731a4e`); its
source checkpoint is 1057 / `7e8b4dbce95416342968f1326fa7201a189c147155884dd92c0808b791afcebc`.
All six files are 1080×2400. I did not compare app38 dark captures with the
light Notion references. The lead already verified the outside-tap, reopen,
then Settings sequence; this review does not repeat UI interaction.

For vertical anchors in all three app38 captures, subtract the 52.5 px
`LOCAL DEV` strip before comparing with Notion. The Settings Theme control is
compared by its own bounds, so this vertical offset does not affect its size
measurement.

## Measured comparison

| State | Measurement | Residual reading |
| --- | --- | --- |
| Home destination pills | App Home and Notes pills each measure about 197×105 px. Notion Home is about 197×103 px; after removing the app strip, their top/bottom anchors differ by at most about 2 px. At this capture density, 197 px is the intended 75 dp width. | Width and capsule treatment are aligned. Keep the app's two existing destinations; do not add Notion's Chat, Calendar, or Inbox destinations. |
| Common Home note title | With grayscale threshold 150 over the full title regions, `M09 UI comparison Android` ink is 531×39 px in app38 and 524×39 px in Notion37: app ink is 7 px (1.34%) wider, with the same height. The app ink begins at x=167 and Notion at x=235. | The width difference is small; this pair does not support further title shrink. The 68 px left-origin difference comes from Notion's disclosure gutter; these are independent notes, so do not add child chevrons. Vertical y is not a valid alignment check here: the same note is fourth in the app list and first in the Notion list, and the app's labels/Manage row is an approved adaptation. |
| Avatar popup | Both are rounded white popups about 755–758 px wide, with their left/right edges within roughly 3 px. App panel top is y≈296; after the strip adjustment it is y≈243.5, within 1 px of Notion's y≈244. App panel height is about 965 px versus about 706 px in Notion (roughly 259 px taller). | Anchor and width are closely matched. Height reflects different action sets and grouping (app has seven existing actions in three groups; Notion has six in two groups), plus looser app row spacing. Ordinary app label-start spacing is about 126 px versus 116 px in Notion, around 10 px / 9% larger; the two app section jumps are about 170 and 168 px. Keep the app's current action set, but the excess row and group spacing is a real geometry gap. App shadow also appears heavier; corner shape is otherwise close. |
| Shared popup typography | The shared `Settings` label measures 159×39 px in app38 and 147×39 px in Notion37 at threshold 150: app is about 8.2% wider, with equal height. | Menu text remains wider even though line height matches. The menu's labels and actions are product-specific; use the shared label only as a typography anchor. |
| Settings → Theme | The app's outlined Light control is about 188×84 px (≈72×32 dp); Notion's is about 197×95 px (≈75×36 dp). Both right edges are at x≈1032, so the app control is about 9 px / 3 dp narrower and 11 px / 4 dp shorter. The `Light` ink itself measures 79×35 px in both. | Text, caret, and right alignment are close; the visible control outline remains smaller in app38. The screenshots establish painted bounds, not the app's 48 dp tap target. Notion's capture is scrolled, so do not compare page-level y positions. |

## Carry-forward

- Keep the 75 dp Home pills; their width and adjusted vertical placement match.
- Do not reduce Home title size further based on the 1.34% width difference in
  this full-region pair; the title heights already match.
- If popup geometry is tuned, tighten row/section padding while preserving only
  NoteFlow's existing Search, New note, Ask notes, Home, Notes, Diagnostics, and
  Settings actions. Do not add workspace, member, upgrade, trash, or other Notion
  capabilities.
- Align the visible Theme outline more closely with the roughly 75×36 dp Notion
  control while retaining the existing touch-target behavior.
- Preserve labels as a neutral adaptation and files as note-level metadata.

These findings describe Home, popup, and Theme-control differences only. They
do not establish a whole-platform similarity percentage or close either ≥95%
gate.
