# NoteFlow runtime architecture

Open `noteflow-runtime.html` in a browser. It is a standalone interactive Architecture diagram with theme and export controls, component source badges, and five supporting detail cards below the drawing.

- Source: original project `/Volumes/Kingsman/Projects/Schools/NoteFlow/note_ai_app`, branch `final-tuankiet`, revision `6f37931a9d82b74d400581af8b169d37be842729`.
- Scope: 11 components; one emphasized cloud Summary path; 3 ownership/trust boundaries; 12 core relations; 5 cards. Native local inference and hosting/RAG proposals are supporting scope notes.
- Main path: Flutter UI -> client runtime -> JWT HTTP API -> guarded Summary Lambda -> DeepSeek API. Client orchestrates chunks/merge; server owns canonical authority and provider credentials.
- Boundaries represent ownership/trust, not VPC security groups. Source links intentionally use local-only mode; no remote commit publication is claimed.

## Evidence

`candidate.json` is the editable, source-pinned specification. `review-3/noteflow-runtime.finalize-summary.json` is the final automated receipt; validate, deliver, strict provenance check and real-browser check all PASS. No diagnostics. Archify installed/available versions3.0.1, no update notice required.

`visual-check/` contains four light/dark viewport captures and a contact sheet. The capture receipt reports perceptual review pending by design; `perceptual-review.json` records the actual manual inspection of1440light and2048dark. The main diagram is visible and the green path is distinct; two resolved crossovers and one longer feedback route remain. Card wording and source evidence were reviewed in the candidate; no scrolled-card screenshot was inspected.

A single optional placement-only review was tried because Archify suggested reducing crossings. It failed desktop readability, so the initial passing candidate was restored and finalized with separate review-3 evidence. Failed review-2 receipts remain for transparency; the HTML and current candidate are the final PASS pair. No extra placement loop or topology edits.

## Repository analysis limits

Graph MCP unavailable. Local JS/TS index rebuilt at6f37931; Dart and material behaviors verified with exact source/call-site reads, not exhaustive graph coverage. This is runtime wiring from committed code, not a fresh AWS/provider test. No product source, credential, deployment, generation, commit or push changes.

## Closure Receipt

- CURRENT_TASK.md: updated with artifact, source snapshot, checks and complete state.
- IMPLEMENTATION_LOG.md: appended runtime diagram/evidence result.
- SESSION_BRIEF.md: current task/state and Last Verified Commit6f37931 refreshed.
- PROJECT_CONTEXT_CARD.md: not needed; descriptive artifact does not change product milestone.
- DECISION_LOG.md: not needed; no architecture/product decision introduced.
- RISK_REGISTER.md: not needed; existing Dart graph-coverage risk disclosed in artifact.
- REPO_MAP.md: regenerated with local code index at6f37931.
