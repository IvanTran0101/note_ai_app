# UI52 — Share popup on Web

30 October2026. Source72 scoped Web/native UI verified; whole M09 remains open.
Whole M09 is PARTIAL; Web>=95% and Android>=95% similarity remain UNVERIFIED.

## Direct reference and corrections

Notion Web was opened on the synthetic reference note. At1280 the popup is456px
wide at y44, radius12. Its right edge follows the Share trigger; measured x values
changed with that trigger (723.84 and355.04), so a universal100px right inset is
not the contract. At700 the popup remains456px; at390 it is366.4px at11.6,44,
rather than a native bottom sheet. The root implementation follows the actual
app trigger and clamps to12px gutters.

Header40px plus0.8px divider; label14px/16.8/w500; underline1.6px, all measured
from rendered DOM. Input outer box32px at x16 within the popup; the24px inner
input at x22 is not its border size. Focus uses1px inset plus1px outside shadow.
Submit32px high, about60px wide, radius6, backgroundRGB39/131/222, foreground
243/249/253. Only existing Share/role/recipient/retry/Close controls are used.
Unsupported Publish/help/public-sharing capabilities are not added.

Actual app63 at the fixture's allowed origin had a24px Share button and a28px
visible input border. Candidate69 corrected the header and button60x32; its
field still reserved a label slot (semantic38px, border28px), and narrow Web
still became the native sheet. It is superseded; no APK69 was built or installed.

## Current implementation (70; padding corrected in71)

- Every Web width uses the bounded popup; native phones retain the existing
  compact surface, retry ownership and route/safe-area treatment. Web popup
  placement uses the triggering button's render box in the root navigator
  overlay, measured before async save. Width456 clamps to available width with
  12px gutters; top44 is measured within the product route, excluding dev strip.
- Builder reaches its descendant render object, confirmed against the installed
  Flutter framework source. An initial contrary reviewer inference was retracted;
  no unnecessary GlobalKey/reparenting state was introduced.
- Existing header is extracted unchanged for native/non-Web; Web uses the
  existing localized Share label with underline/divider. Field/submit styles are
  scoped to the Web popup. An excluded visible hint and persistent semantic
  label avoid the floating-label slot without losing the accessible field name.
  Native defaults/import API remain available through the surface re-export.
- Share state alone owns/disposes the email focus node. Initial successful load
  requests focus once after build, checking live/session/route before context
  access. Focus already moved inside the dialog is respected; apply/revoke does
  not request focus. Existing save, authorization, request, session, role, retry,
  revoke/reactivate and mutation guards remain unchanged.
- The field moved into its own small presentation file at the responsibility
  boundary; the old import path re-exports it. No dependency/config/lockfile or
  persistence/schema changes are part of this checkpoint.

## Verification and evidence limits

Final Chrome70 six distinct cases pass: wide/short200%+IME/narrow390 multiplied
by loaded/error states. They check bounded Web popup instead of native sheet,
presence of existing controls, accessible target sizes, one retry and Close.
The first70 run incorrectly required a32px TextField hitbox, which is48px;
that assertion was corrected to minimum32. Visible borders must be checked in
the actual app, not inferred from semantic/hitbox geometry. Earlier69 four-case
runs are subsets/history, not additional distinct final cases.

VM70 six cases pass; strict70 seven paths are clean after a braces-only lint
fix. That fix follows the Chrome70/VM70 tests without a behavior change.
Web70 built in80.8s, source1083/fingerprint
`dfbb804b0ead0058d7fad27fa8e971143b5bcc2ab3984601ea44cb710827736e`, drift[].
Actual Chrome21,473,912bytes matched packaged SHA256
`c49d057422f245214f7bd97fb40eb34299554bad332643337bf3596f23effce0`.
Popup right1240 matches trigger right1240 at1280;700 trigger right660 also
matches after reopening. At390 the popup is366px/gutter12 and Close is48px.
Initial email focus and one accessible field name persist through typing/clear.
Role Editor then Viewer only changed local form state; no invite was submitted.

The actual70 screenshot still shows a28px painted input border: the32px minimum
on InputDecoration constrains its overall layout, not the painted container.
The installed SDK computes dense container height from input20 plus padding8.
Root rejected70, changed Web vertical padding from4 to6, and added a regression
against InputDecorator.containerOf(EditableText).size.height ==32. Candidate71
Chrome6/strict7/Web are now running sequentially; no APK69/70 was built.
Do not publish70 as final or infer border size from its38px semantic field.

On resume no old server/fixture listeners or processes existed. Root verified
ports8776/8796/8797/8798 free and started new hidden processes with the same
root/origin. This did not kill/retry the previously blocked server stop.
The first page navigation raced server readiness and recorded one connection
refusal; after a deliberate reload with services ready, scoped70 page/console
errors were zero. The same browser profile retained45 notes. All736 previously
existing root files kept their hashes after additive child70 serving.

Final71 Chrome6/6 passes with the painted-container32px regression. The initial
new assertion found52px in four cases because the placeholder wrapped under
wide Ahem glyphs. Root constrained the visible hint to one line with ellipsis;
the accessible label remains complete. Strict7 is clean. Web57.9s/APK65.4s,
source1083/fingerprint
`91e6abca3ad5bcb6bd3271c89097e2e9f106a96b256a3109924f797dcc6aff9b`, drift[].
Actual Chrome21,473,919bytes matches packaged SHA256
`aa41cf1a0b85e66d66ff7adaec0f0d92ba62a933207176e3e596ab505bc5ae28`.
All1104 existing root files remain hash-identical after additive child71.
Actual header crops confirm32px visible border and60x32 submit in Light/Dark.
Typing sequentially retains the full draft when resized to390; one accessible
name and initial focus remain correct. Short700x320 Close is36px/mouse and
reachable;390 Close is48px. Both popup dismissal animations completed.
The actual starting Web theme was Light (historical UI51 said System); it was
restored to Light, with language System unchanged. Reference Notion Light was
also restored after the Dark crop. Four safe headers are on the existing board,
retaining64 images as68. Settings' existing permission/unavailable state remains
visible; this does not establish provider/API acceptance.

Installed/pulled APK71 matches174,215,889bytes/SHA256
`f8bd35b9e89bea7a498fac28112ca591802915d104a561ed7081394d30b48dbd`.
The retained-data emulator rendered Home then Share/No recipients. Portrait
Close/Share/role are126px=48dp at420dpi. Synthetic email typing was local form
state only; no invitation submitted. Font200% and landscape without IME fit.
However landscape200% with IME clips the input to494-520 (26px visible) and
cuts the Share button. Native71 is rejected: root added a focused regression
before changing the constrained sheet header/top gap. Target72 remains pending.
Font1, auto1/user0/navigation0 were restored and re-read, form cancelled and AVD
closed with data retained. A first capture printed a Unicode console error
after writing its fresh XML/PNG; later captures explicitly used UTF-8.
Whole-platform gates remain open; no UI52 push or broad acceptance yet.

## Target72 native correction

The new regression first failed on71: painted field bottom216 was outside the
198px available scroll viewport. Root reproduced the runtime failure rather
than accepting a no-overflow assertion. Below300dp available height after the
physical IME, the surface removes its extra top gap/drag handle, retains the
scaled title and48dp Close, and reduces only the scroll body's top padding.
The existing SingleChildScrollView and SafeArea keep ownership of scrolling
and actual insets; the height calculation only chooses presentation. No double
IME consumption or service/state mutation was added. Normal-height sheet layout
is unchanged, and production Web does not use this native surface.

VM72 all9 focused cases pass, including the red/green regression with full
painted field visibility, scrolling to an existing action, and Close callback.
The two existing native/permission cases and six responsive cases also pass.
Strict8 is clean. Later source change before the72 snapshot is comment-only.
Web72 main.dart.js is byte-identical to71, so the actual71 Web screenshots and
six Chrome cases apply to the same executable. It is not a newly run Chrome72
test suite. Web60.1s/APK58.9s, source1083/fingerprint
`3cc43e74247262aafa2e4632c3794565d5d3b93e4797f07e2a9797f6d4897d51`, drift[].
All1472 previous root files retained their hashes after additive child72.
APK72 is174,215,746bytes/SHA256
`456da989fc1d8d97cf1f41e976f694a0b4cc0793481e08aa1180fae18a161598`.
Actual installed72 could not be checked: the emulator refused startup with
FATAL hasSufficientDiskSpace. C has2.04GB/D2.47GB free; read-only CIM reports
Windows pagefile allocated18242MB. No pagefile/system memory setting change,
cleanup or deletion was attempted. User was asked asynchronously to free5-8GB
on C while root continues independent Web work. The final72 APK is built but
NOT installed; the last actual installed71 still has the documented IME defect.
Do not check native completion or replace the actual71 failure with VM evidence.

## Final72 installed evidence

After free C was observed at7.76GB, the same emulator passed its normal disk
check. No check bypass or system memory change. Installed/pulled72 matches the
APK above. The first fresh hierarchy was null and rejected; wake/settling gave
a fresh Home. At font200%, stable landscape and IME top520: input181,305-1943,457
is fully visible (152px); Share1964,318-2222,444 and Close2003,155-2243,281 are
126px=48dp. Scrolling dismisses the keyboard by the existing onDrag behavior;
Viewer/Editor menu rows are each126px high and end at x2274/bottom908, inside
the navigation safe region. No invitation was submitted. Normal portrait and
gesture portrait+IME were inspected; dumpsys confirmed input view shown.
Close remains126px. Original font1/auto1,user0/navigation0 were restored/re-read,
the form cancelled, fresh retained-data Home captured and the AVD closed.

A font/rotation transition reset user_rotation once; a premature tap caused
only local empty-email validation. That state was cancelled, not counted as
typed/invitation proof. Final captures use the subsequently stable landscape.
The temporary outer green frame appeared again; its cause is not fixed. Safe
before71/after72 app crops were added to the board, retaining68 images as70.
The runtime receipt is output/m09/ui52-native72-runtime.json (ignored).
Source checkpoint16864ba335c2b17ba5a18e6016a29972d971238e is pushed/remote-verified
0/0; this evidence follow-up contains documentation only.

## Checkpoint result and closure receipt

UI52 scoped UI checks passed with the evidence above. Whole M09 is PARTIAL and
both95% gates remain open: component checks do not establish full similarity.
No live provider/cloud or broad functional signoff. Continue the remaining
editor/reference matrix, keeping the recorded fixture-content differences clear.

| Record | Resolution |
| --- | --- |
| MUST_REMEMBER.md | Source72 evidence, disk blocker, no Android acceptance, continue Web. |
| CURRENT_WORK.md | Exact fingerprints/artifacts, failed candidates, next runtime state and restoration. |
| VISUAL_REVIEW.md | Scoped Share result and both95% gates open. |
| AGENT_IMPLEMENTATION_20261019.md | Root-only edits/review this resume, historical22-worker distinction. |
| ui43/LIVE_REFERENCE.md | Direct Web Share container/anchor metrics and safe reference crops. |
| _agent_ops/* | Not needed: folder/session tools absent; existing records used. |

Candidate69 Web135.1s,1083 source paths, fingerprint
`b7ed6b26cdb5781d9c308bc148c081cee3948ebde04941e47730fe9a75dd51e7`, drift[].
Actual Chrome21,476,260bytes matched packaged SHA256
`ddebaf8fe086f13478431031ef03fc5eaa2f3eb869f8f5e986e687e1f127b3eb`.
Loaded No recipients, existing email typing/clear and narrow-sheet mismatch were
observed with zero page/console errors; no invitation was submitted.

## Local QA serving

The existing static server and all368 original bundle files were preserved,
verified by before/after hashes.69 was added only as a new child bundle with its
own base path at `http://127.0.0.1:8776/ui52-final69/`. This uses the fixture's
already allowed origin; no server stop/replacement, original-file overwrite,
CORS relaxation or fixture restart/data reset.70 repeats the same additive
procedure with a new child path and verifies every existing file. Root service
worker bypass/cache disable are explicit QA options; fetched bundle identity is
verified rather than trusting a page URL or old cache.

UI51 source/native evidence and startup/CORS/profile-service limitations remain
in UI51_SETTINGS.md. Current iOS runtime remains unverified. The Web visual work
does not establish AWS live provider/ACL deployment, whole-platform similarity,
or broad functional acceptance.

## Ownership and review

The same additional Luna Max reviewer from UI51 drafted an isolated proposal and
reviewed UI52 source read-only. Root verified measurements, corrected the inner/
outer padding interpretation, implemented/reviewed all production changes and
owns tests/runtime/Git/Notion. No overlapping writers;22 actual workers since
the20-worker UI43 sequence, one new reviewer in the continuing UI51 session.
Its later visual-gap audit failed due usage limit and produced no accepted
deliverable. Fresh graph generation29Oct13:06Z reports metadata_changed for
all seven candidate paths; all current relied source was read directly.
The _agent_ops folder/session tools remain absent.
