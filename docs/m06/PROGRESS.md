# M06 — Implementation progress

Updated 2026-10-02. Active scope: M06 only, after M05 accepted and pushed at
22587a5954c182c202d07923ec8be1e3060fa42d. Read MUST_REMEMBER.md before coding.

- [Source plan](https://app.notion.com/p/3e8f9c7a1aa08193b4f9d1fbf42999ed)
- [Progress page](https://app.notion.com/p/3edf9c7a1aa0817fb5fedd1e18b52ab2)
- [Frozen contract](CONTRACT.md)
- [Delivery branch](https://github.com/IvanTran0101/note_ai_app/tree/final-tuankiet)

## Milestones

| Milestone | State | Evidence/next step |
| --- | --- | --- |
| M06.0 | Complete contract/evidence freeze | Notion decisions and current source inspected; CONTRACT.md |
| M06.1 | In progress | Add pair identity, role/grant/policy and actor projection/storage |
| M06.2 | Planned | Verified recipient, fresh ACL/conditional writes, actor feed |
| M06.3 | Planned | Sharing management + Shared With Me, encrypted offline |
| M06.4 | Planned | Durable AppSync relay and cursor/session recovery |
| M06.5 | Planned | Full tests + two clients on Web/Android; distinguish live cloud spike |

All 15 SHARE-FR/NFR rubric criteria remain unchecked. No M06 runtime feature is
claimed implemented or accepted at contract freeze. Update this record DURING
work with files, confirmed failures and the next step; after each completed M06.x
or M/P criterion, update Notion, explicit-stage commit/push and verify remote SHA.

## M06.0 evidence

Graph Tier2 source/coverage findings and compatibility requirements are recorded
in CONTRACT.md. Canonical identity crosses every layer; bare-id maps and owner-only
gates are known existing limitations to replace, not permission to remove guards.
M05 tests passed: VM921/2skip, Chrome797/1skip, Android12 and real Web-plugin12;
backend57, root analyzer and typecheck. Additional native bridge smoke6 and
Chrome stub1 also passed; no model loaded. No deployment was performed.

## Current work

Next: implement M06.1 domain types, preserve owned-note compatibility, add tests
for same noteId across two owners and foreign projection validation; then extend
vault/codec identity without relabeling existing authenticated ciphertext.
