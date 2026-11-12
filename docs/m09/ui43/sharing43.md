# UI43 — sharing surface

## Direct reference and scope

On 26 October 2026 the lead inspected the authenticated Notion Web Share panel
at 1280×720. It is a white, rounded, elevated popup anchored at the upper right,
about456px wide, with a Share header and divider. The invite row has a focused
email field about356×34px and a blue Share action about64×32px. Member rows put
the identity at left with muted secondary text and the current permission at
right with a chevron.

This adaptation keeps the existing Editor/Viewer selector as a separate
control, placed below the invite row when the panel is constrained. The current
permission is now visible on the Web member control; its menu keeps the existing
Editor, Viewer and Revoke actions. `NoteShareGrant` exposes a recipient ID but
no recipient display-name or avatar data, so the row displays that ID and the
existing status/update metadata. No profile lookup, avatar, public link,
general-access setting or Publish action was added.

## Changes

- Kept the desktop invite field and blue Share button on one row; used the
  separate role control below it to preserve the existing invite contract.
- Matched the Web field focus border and Share action sizing to the observed
  panel. Kept native controls at least48dp and made the invite layout wrap at
  narrow widths or large text.
- Allowed long member IDs and status metadata to wrap, with a tooltip for the
  full ID. Added a current-role permission menu that calls the existing role
  change or revoke callbacks.
- Made the native sheet header grow with large text and its content scroll
  while the IME is open. Made the Web dialog content scroll independently of
  its actions.
- Presented localized errors in a live-region notice and kept the existing
  online-only guidance and retry path visible in their existing states.

## Verification boundary

`test/presentation/ui43/sharing43_test.dart` covers large text with a simulated
IME, the native field target size, the long-recipient layout, and existing role
and revoke choices. The root owns running this test and shared analysis/builds.
Android Share reference inspection and combined runtime review remain pending.
This report makes no PASS or platform-similarity claim.
