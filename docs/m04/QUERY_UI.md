# M04.5 query and UI

The composition root enables LabelApplication on the cached encrypted actor
store. Its catalog host refreshes only Labels, not NotesWorkspace/editor state.
Terminal coordinator notifications also refresh the catalog after manual or
partially failed sync. Captured actor/session fences reject stale dialog intent;
manager/filter catalogs additionally reject rows belonging to another actor.

Notes and Home use the same pure query: title OR body substring, case-insensitive
without accent folding, AND every selected owner-scoped Label ID. Filtering
precedes existing pin-first order. No network/DB lookup occurs per keystroke.
Both list/grid use ID-resolved chips. Confirmed tombstones prune a selected
filter; unknown/error/loading catalogs never imply deletion. Filtered empty
results have separate localized copy. Account changes clear query/selection.

Catalog CRUD supports duplicate names as independent IDs. Note chooser routes
owner mutations through the existing atomic writer; shared Editor cannot
organize. A saved association reuses the editor's unchanged-text ACK rebase,
preserving dirty controllers and retaining concurrent changes as pending.

## Fresh source acceptance, 2026-10-05

- Full VM1144 PASS,2 configured skips before the final defensive stale-catalog
  owner filter; all changed UI/dashboard widgets subsequently52/52 PASS.
- Terminal observer + new Label widgets10/10 PASS; dev public config14/14 PASS.
- Backend remains51 Node test nodes/TypeScript clean from M04.4.
- Analyzer final receipt is in ignored output/m04-integration; actual final
  Chrome/Android/privacy acceptance is tracked separately in UI_QA.md.

Production defaults to v1 until the matching v2 backend is deployed. Explicit
NOTEFLOW_LABELS_ENABLED=true is a public Boolean accepted by m06_dev_config.py;
it contains no operator credentials. main_dev enables Labels automatically for
the matching local backend; use python tool/run_m06_local.py for that fixture.
Do not equate plain flutter run with starting its HTTP/socket services.
