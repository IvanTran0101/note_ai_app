# Label position and Notion file presentation — 23 October 2026

## Scope

The user resumed only two items: labels immediately below the note title, and
attachment presentation closer to actual Notion. Stop after this slice and wait
for the next instruction. No remainder of M09 is accepted by this checkpoint.

## Direct reference and implementation

- Actual Notion Web was inspected on the existing synthetic reference page.
  Its file row is28px, filename16px/24px, size12px/16px with6px separation,
  an outlined document/upload glyph and no Ready or dot separators.
  Local reference: output/m09/notion40-web-file-light.png.
- Actual Notion Android was reopened, unlocked normally and inspected in Dark:
  1080x2400,420dpi, portrait, font1,3-button navigation. The synthetic file is
  m09-ui-sample.txt,67B. Local reference: notion40-file-settled.png/XML.
- Labels now have a separate surface/form header slot between title and body.
  The existing label editor, identities, callback and all capability/conflict
  gates are forwarded unchanged. It occurs once, including the rich editor's
  separate header/footer composition. Attachments retain the existing note
  metadata association and preview/transfer owners.
- Files now use a flat outlined glyph/name/inline size hierarchy. Desktop rows
  are28px; native rows/actions retain48dp targets. Ready is retained in tooltip
  feedback, while pending/progress remains on a secondary line. Desktop More
  appears on hover, descendant focus or accessible navigation, with no extra
  Tab stop and no invisible pointer target. Add attachment is flat and quiet.
- Existing choose-files/gallery/camera, open, retry, download, cancellation and
  remove callbacks and their authorization owners remain in place. No new
  document block, database, file schema or local-first/sync behavior was added.

## Ownership and review

One actual Luna Max worker, file_ui40, owned only attachment_file_row.dart,
attachment_editor_rows.dart and its reference test. Lead owned the four label
placement files, integration, runtime sessions and all checks/Notion/Git.
Lead reviewed the handoff, required outlined glyph and focus/pointer/accessibility
corrections, then added filename/size alphabetic baseline alignment. All files
were handed back before checks; there were no overlapping writers.
The worker then independently read the integrated label/header/footer and
attachment callback/access paths without edits; its bounded source review
reported no actionable issue. Lead still owns runtime verification.

## Checks and evidence

Initial placement tests2/2 passed. Related VM suite initially had41 passes and
four stale expectations: native title32 vs already-established34, and page
header anchor80 vs72. Those source values are unchanged by this slice; only
the expectations were aligned. Rerun45/45 passed, including narrow/200% UI,
label actor fences and file actions. Chrome focused UI10/10 then passed using
the existing normalized tools overlay. Dart analysis and Flutter analyze7
items are clean (Flutter26.5s). Web60.8s and APK66.4s built from1058 runtime
paths, fingerprint
`7e977026cb521df016ba14ed38aafc79fcc4c5bac199bcd74514d1c9e825072a`,
source drift[]. Installed APK/device SHA matched
`a1c93ce2f584e1856dc342227f6e0db43f36f49476fd62ba6731cd0c459091d2`.

Actual Web40 received21233619 main.dart.js bytes after an explicit reload;
the initial navigation had reused Web39 and is not new UI proof. The required
attachment media worker stayed enabled. Real mouse/keyboard on1280x740 and
390x844 confirmed labels below title, label chooser/selection,67B file picking,
contextual menu, open/close preview and download. Chrome export67B matches
SHA256 `96fbf4c9f79c7137d7f3c424b45ac08fb21ee21f344dfe6b74cb815a0ecc7278`,
failure:null, page errors[]. A new synthetic UI40 Labels and files QA note was
used for this upload, leaving existing notes/attachments intact.

Actual Android40 confirmed labels between title/body, chooser open/cancel,
48dp file/More targets (126 physical px), all four existing add sources, file
menu, TXT preview and export to Downloads/NoteFlow. Pulled native export is
also67B with the same hash. An initial exec-out read with a quoted spaced
filename returned shell error text; adb pull verified the actual file bytes.
Portrait controls/file remain above the3-button navbar. Gesture/landscape/iOS
acceptance is not inferred from these bounded checks.

Local screenshots: app40-web-label-title-dark.png,
app40-web-label-file-final.png, app40-web-compact-label-file.png,
app40-native-title-label-proof.png, app40-native-final.png,
app40-native-preview.png and app40-native-add-menu.png.

Existing queued focus observation remains outside this slice: first slow title
entry on a new QA note retained only the first character; re-entering the saved
title succeeded. Cause was not isolated here and is not attributed to the label
change. Do not claim whole-editor typing or broad functional QA PASS.

The graph generation is18October; path coverage marked source metadata_changed
or not_tracked. Lead read current source directly. This is a bounded source/UI
review, not an exhaustive graph audit or live cloud verification.

Both whole-platform >=95% similarity gates remain UNVERIFIED. Broad functional
regression and the rest of the visual backlog are outside this slice.
