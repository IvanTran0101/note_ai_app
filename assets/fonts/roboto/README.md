# Heading font

Unmodified Roboto Medium/Bold and italic faces from the Flutter SDK's
`bin/cache/artifacts/material_fonts` bundle. Original Apache2 license is copied
verbatim to roboto_license.txt and included in app assets. Flutter heading
family alias: NoteFlowHeading; only Web rich block headings use it. Native
keeps its existing system font. Main title/body retain NoteFlowSans on Web.

Direct Notion Web inspection at1480x668 on21 October2026: Heading1/2/3 use
30/24/20px, weight600, line-height1.3. Their text advances are132.85/110/91.66px
for the matched synthetic sample. Arimo Bold was143.36/114.69/95.58px; Roboto
Medium is136.45/109.16/90.97px before shaping. Slightly tighter H1 tracking
and Medium weight approximate that visual system without fetching fonts at
runtime. This is a measured approximation, not a whole-platform95% claim.
