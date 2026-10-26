# UI43 search grouping and heading audit

## Scope

This slice audits and tests `dashboardSearchSections`. It does not change the
search query, filters, sorting, permissions, access masking, or persistence.
The helper already preserves the incoming result order within each group, so
no production source edit was needed.

## Existing grouping contract

- `byCreatedAt` selects `createdAt`; otherwise the helper uses `updatedAt`.
- Dates are converted to local time before the day bucket is chosen.
- A pinned note uses the existing Pinned label regardless of its date.
- Day offsets are Today (0), Yesterday (1), Past week (2–6), and Past 30 days
  (7–29). All other dates, including future dates, use the localized compact
  date label.
- Group heading order follows the first occurrence of each label in the
  already ordered input. Notes retain their relative order within a group.
- Empty input returns an empty map.

The regression suite in `test/presentation/ui43/search_rows43_test.dart` covers
bucket boundaries, pinned override, first-seen heading order, within-group
ordering, created-versus-updated date selection, and empty input. Root owns
running shared tests and builds; this worker did not run them.

## Heading guidance for integration

The checked-in Search map points to Web008 and Android215. Those local captures
show a compact muted date label on Web and a broader quiet Today band on the
Android recent-search screen. The Android floating rail is IME UI, not app
content. Apply these as presentation treatments for the helper's existing
labels, without reordering the groups or inventing new search behavior.

At report time, `LIVE_REFERENCE.md` contains direct Web editor observations and
says direct Search and Android inspection will follow. Search-specific heading
recommendations above are therefore supporting local-reference guidance only;
they are not a direct live Notion comparison or a similarity result. Root owns
Search heading composition and final confirmation.

## Verification boundary

The test file was added for the root-run verification pass and was not executed
by this worker. No Web/Android app flow, broad regression, build, or similarity
score is claimed here.
