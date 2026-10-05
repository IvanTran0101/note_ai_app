# M03 progress

Source/local acceptance is distinct from leader AWS deployment/live acceptance.
Current product source: 47f7ad5 (camera normalization, native PDF controls and
all earlier M03 integration fixes); final full regression is pending.

| Milestone | Source/local status | Evidence |
| --- | --- | --- |
| M03.1 policy/contracts | Accepted | CONTRACT.md, Dart/TS parity |
| M03.2 durable attempts/recovery | Accepted | Backend87, ACK/cancel/expiry/quota races |
| M03.3 canonical manifest/sync | Accepted | Typed v2/migration/legacy preservation; cross-device Ready |
| M03.4 encrypted staging/reopen | Accepted | Real Chrome IndexedDB; native offline Pending/cold/reconnect |
| M03.5 private object/upload/association | Accepted | SDK/CDK/source/local87; exact actual export hashes |
| M03.6 scoped access/key/cache | Accepted | UI_QA.md: owner/export, sharing/revoke, lock, Web offline/native online rotation |
| M03.7 picker/media/transfer UI | Accepted | UI_QA.md: native full pickers/media; Web large progress/interruption/retry/hash/seek/remove |
| M03.8 final regression/UI | In progress | Expanded127 Chrome targets; current VM/backend/static pending |
| M03.9 handoff/remote | In progress | DEV_SETUP/MEDIA exist; final acceptance/handoff pending |
| AWS deployment/live | Leader gate | DEV_SETUP.md; no deployment receipt |

Notion progress (inside final flutter):
https://app.notion.com/p/3eff9c7a1aa08170856afa612fd3f271
Collaborator plan:
https://app.notion.com/p/3eff9c7a1aa080e5979ec1122d5cc88f
Canonical rubric:
https://app.notion.com/p/3e9f9c7a1aa080ec8394d4390367e266

M09 remains deferred. Preserve old QA profiles/drafts and unrelated working files.
Detailed continuation is CURRENT_WORK.md; actual UI evidence is UI_QA.md.

Notion rubric17/17 source/local checked; M03.8–9 and AWS live gate still pending.
M03.6 receipt pushed b395170; source remains47f7ad5, later commits document QA.
