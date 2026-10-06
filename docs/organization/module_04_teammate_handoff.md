# Module 04 — Search, Labels & Organization — Ready implementation plan

Chốt 2026-10-02. **READY FOR ORDERED IMPLEMENTATION** cho scope owned/unprotected. Đây là plan đã quyết định, không claim source/runtime đã hoàn thành. Business O0 decisions đã đóng; dependency PRs dưới đây phải được implement/merge theo thứ tự.

Authority:
- [Common Module02–03–04 contract](../contracts/modules_02_03_04_contract.md).
- [Wire2/schema4/bootstrap specification](../contracts/sync_wire_v2_labels.md).
- [Historical review, không dùng làm instruction](archive/module_04_review_2026_10_01.md).

## 1. Baseline đúng và prerequisite bắt buộc

Reviewed source: [16ee44b247d42119b4912ff38cf3f551fa0a8434 — Implement Module02](https://github.com/IvanTran0101/note_ai_app/commit/16ee44b247d42119b4912ff38cf3f551fa0a8434), đọc qua GitHub. Checkout tạo plan vẫn6ce2afe; không pull/checkout/source edit trong planning task. Teammate làm từ agreed branch containing16ee44b rồi cập nhật baseline sau mỗi prerequisite PR.

Đã có pin/atomic update, schema3/userPreferences và Application sortNotes. Chưa có Label runtime. **Đã có atomic method không đồng nghĩa đã khớp target contract:**

| Source16 hiện có | Target cần trong PR-C0 |
| --- | --- |
| updateById(String id, expectedAccountUserId, change:void) → Future<Note?> | Named noteId/ownerId/expectedAccountUserId/change/canCommit → Future<Note>; synchronous callback trả fresh Note |
| Account-ID guard | Actor + sessionGeneration + policy expiry fence; không dùng actor làm owner |
| sortNotes ở Application, equal-pin fallback date/id | One Presentation helper; pin time DESC, equal pin → owner/id; unpinned selected created/updated DESC |
| SummaryRunGuard manual DTO + hasSameTextAs | One full metadata mapping + common conservative snapshot policy |
| Manual LocalSyncState constructors ở nhiều writers | One preservation helper, explicit cursor-null semantics và coordinated schema fields |

PR-C0 của shared-core owner phải merge trước Label integration. M04 không tự tạo overload/adaptor giữ hai Note contracts cạnh nhau.

## 2. Scope, policy và giới hạn đã chốt

1. Keyword title OR content substring, trim/lowercase; ALL selected label IDs AND keyword; sort pin-first dùng chung list/grid. Không search service/network mỗi key, ANY/fuzzy/accent-fold/semantic search.
2. Label ID stable, name chỉ ở catalog. **Tên có thể trùng**; CRUD/selection/chips keyed by ID, không merge IDs theo tên. UI duplicate names có secondary created-time hint và unique semantic keys. Không NameClaim/unique-name transaction hoặc name-conflict workflow.
3. Name reject C0/DEL/C1 control characters trước trim, rồi 1..64 Unicode code points; preserve case, dấu và internal spaces. Dart runes/JS code-point count có shared Unicode/trim fixtures; không NFC/case-fold dependency. Label IDs dùng existing injected ID generator, nonblank và bounded như existing IDs.
4. Max32 unique raw label IDs/Note request; sorted canonical wire encoding. Một genuine association edit có thể compact refs đã verified tombstone trước add để reclaim capacity. Không fan-out Notes khi delete Label; unknown refs không bị prune; attempted payload không đổi. No-op duplicate attach/absent detach không timestamp/outbox.
5. Owned/unprotected organization hiện tại: organize owner-only; catalog CRUD own actor/session. Shared/private-owner catalog, recipient organization và protected cached search fail closed cho tới M05/M06 integration. Scope limitation không được gọi là full Final-project sharing/security acceptance.

V2 payload cost300,000bytes và composed Note snapshot cost350,000bytes (raw text + encoded other fields), request/response body cap2,500,000bytes, default50/max100rawrows theo shared protocol. Tests giữ valid legacy escaped text và Lambda envelope headroom. Preserve pinnedAt, attachments và userPreferences; không binary/credentials/signed URL trong Note/outbox. M03 metadata contract được consume, binary feature không implement ở M04.

## 3. Data/transaction behavior

- NEW Label aggregate + ILabelRepository; Note giữ readonly labelIds. Label rename ID-stable, real change UTC updatedAt; delete tombstone giữ name/id; không hồi sinh ID. findByOwnerId/listLabels public active catalog, internal stored catalog giữ tombstones.
- Same cached ILocalSyncStore instance trong main cho Note/Label/preferences/coordinator. No separate native queue/file writer; no Label database/sync engine.
- Fresh Note + Label existence/owner/active check và Note + outbox commit cùng synchronous store.update. Async access/token/picker checks nằm ngoài transaction.
- Create Label/catalog/outbox atomic; callback/fence/storage failure không partial state. Lost ACK retry same request; revision conflict local/remote/later rõ, không auto merge.
- Never-sent Label create bị delete có thể remove create queue, giữ tombstone. Attempted create phải settle trước successor delete. Save-as-new sau remote deletion tạo ID mới bằng explicit action, không remap Notes tự động.
- All state writers phải preserve labels/labelConflicts/catalog phase/cursor version/preferences. copyWith/helper semantics: omitted giữ current; explicit cursor=null clears. Existing Note conflict resolver vẫn chỉ xử lý Note; Label resolver riêng.

**Bổ sung writer bị thiếu trong report:** lib/infrastructure/users/local_user_preferences_repository.dart. Source16 save dựng lại entire state; nếu không migrate writer này, layout/preference save có thể reset catalog mới. Cũng update NoteRepository._stateWith, SyncStateReconciliation.copyState, SyncConflictResolver, mock/storage builders theo cùng helper.

## 4. Catalog/query state machine đã chốt

Catalog phase persisted: needsBootstrap → replaying → ready. Network error/offline là view/status riêng, không biến loaded catalog thành deleted/empty. Wire2 bootstrap H/cursor rules theo spec linked; hasMore=false không đủ để Ready.

- selectedLabelIds giữ nguyên trong Loading/Error hoặc metadata chưa hydrate. Không lấy selected ∩ partial active catalog rồi truyền [] để vô tình mở rộng filter.
- Nếu có complete cached catalog và Note label metadata known, query/filter offline bình thường; background/foreground refresh không reset selection.
- Nếu selected IDs hoặc matching Note label metadata chưa biết, render waiting/error metadata state; không claim zero results hay bỏ filters. Keyword-only search vẫn hoạt động trên readable loaded Note text.
- Chỉ verified Label tombstone clear active selection; effective Note associations resolve raw IDs với known active catalog. Missing entry ≠ deleted.
- Local-created Labels/Notes được lưu và hiện Pending kể cả lúc chưa online; existing remote Note cần labelIdsKnown trước organize. Unknown metadata autosave omit fields để preserve server associations. No labelsAllowed flag giả để vượt guard.

LabelController capture actor/generation cho async loads/mutations, ignore stale response. Catalog notifications update chips/filter results by ID lookup, không gọi full Workspace.reload đóng/reset dirty editor. Label rename không rewrite Note.updatedAt/text/attachments/pin hoặc tự đưa names vào AI.

## 5. Schema/wire rollout và bootstrap đã chốt

Chọn **A — backward-compatible preservation**, không reject toàn bộ legacy clients. Local4 migrate2/3; typed wire2 cho new mutations; existing attempted wire1 giữ ID/body semantics. No DB reset, không mất preferences hoặc old conflicts.

- Server v2 trước production client. GET v2 validates wire2 before new v2 dispatch; v1 requests/responses/journal vẫn giữ encoder/shape. Missing metadata preserves, explicit empty clears.
- V1 feed Note-only, nhưng cursor advances through consumed contiguous raw Label rows. V2 bootstrap replay từ0 captures fixed H và có caughtUp bit, resume checkpoint, không false Ready ở GSI gaps.
- labelsKnown/attachmentsKnown facts distinguish legacy unknown from true empty; new local Notes known empty, authoritative v2 hydrate known. Metadata hydration không rewrite pending text/intents/attempted bodies/base revisions.
- Label create server ACK trước dependent Note; scheduler defer đúng tuple, unrelated tiếp tục. Per-resource invalid association/conflict không dừng toàn bộ account; auth/session/protocol failure dừng safe run.
- Note/Label same ID không collision vì keys typed/scoped. V2 fingerprint gồm type/resource/payload/presence; label set sorted. No duplicate-name collision state.

No feed/tombstone garbage collection trong slice: full replay depends on retained history. Nếu deployment có retention/permanent missing history, bootstrap stays unavailable/pending và cần replacement contract; không sửa bằng clear data.

## 6. PR order và file ownership — một writer cho shared paths

Role owners phải được teammate gán cho người thật trước coding; không cần thêm kiến trúc choice. Branch prefix codex/. Cùng một shared-core writer giữ các common paths; M04/M03 gửi targeted delta cho writer đó, không concurrent commits vào shared files.

| PR | Writer | Phạm vi | Depends / exit gate |
| --- | --- | --- | --- |
| PR-C0 — Core compatibility | CORE M02/M11 | Domain Note port; common guards/fences; shared DTO factory/equality; pin/query helper; preservation helper/preference writer | Base containing16ee44b; named API/fence/full-snapshot/pin tests pass; source compatibility ready |
| PR-L1 — Label types | M04 domain/application | NEW domain/labels and Application Label DTO/state/payload/snapshot/conflict models; no shared-file edits | C0 interfaces; Domain/policy/value equality tests pass |
| PR-C1 — Metadata + typed engine | CORE, consume L1/M03 metadata contract | Note.labelIds/metadata codecs; local4; typed ports/outbox/reconciliation/scheduler/HTTP/runtime/main integration | C0+L1; migrations, writer-preservation, unknown/presence and dependency tests pass |
| PR-B1 — Server compatibility | CORE server + M04 NEW Label helpers | Shared parser/dispatcher/cursor/feed/journal transaction; M04 Label validation/CRUD/association helpers | C1 wire fixtures; legacy replay/bootstrap/liveness/access/byte-cap checks pass; deploy later only with intended-env approval |
| PR-L2 — Local repository + UI | M04 feature, CORE integrates shared surfaces | NEW LabelRepository/service/controller/panel/picker/chips/reconcile helpers; requested Dashboard/Workspace/main delta | C1+B1 protocol support; local/reconnect/UI/guard tests pass; enable after server verification |

These are ordered implementation PRs, not already-created GitHub PRs. Pure new-file L1 work có thể được review trước server deployment; production feature activation vẫn follows B1 deploy verify. M03 binary work có thể parallel chỉ ở M03-owned new files.

| Path group | Exclusive writer |
| --- | --- |
| lib/domain/notes/*; lib/application/notes/*; common access/query/mapping | CORE |
| lib/application/sync/*; infrastructure/sync/*; NoteRepository; LocalUserPreferencesRepository; shared main/Note/Dashboard/Workspace/Sync surfaces | CORE |
| amplify/sync existing files; resource/main wiring; docs/contracts/*; shared fixtures | CORE |
| NEW lib/domain/labels/*, application/labels/*, infrastructure/labels/*, presentation/labels/* và their tests | M04 |
| NEW M03 binary/storage/picker/control paths; metadata contract changes coordinated via CORE | M03 |

Shared files changed via one owner or explicitly serialized handoff, không two active writers. No independent schema4 variants. Existing large repository/store files split by real Note/Label/transaction responsibilities when needed; no generic registry/framework/database.

## 7. Exact change list và integration obligations

Use existing changed-path groups from report, add:
- lib/infrastructure/users/local_user_preferences_repository.dart, all state-copy helpers/builders.
- lib/application/sync/remote_note_data_source.dart, typed snapshot/page/result/failure/status/report and account_sync_runtime.
- lib/application/note_intelligence/summary_run_guard.dart + summary snapshot/runtime fixtures for full-metadata factory.
- common note_query.dart (CORE-owned), migrate existing Application sortNotes/DashboardSort callers, no date fallback when equal pinnedAt.
- docs/sync_api_contract.md, wire golden fixtures and README policy/commands.

M04 consumer signature không thay common updateById/require. Association before commit checks fresh catalog, not detached Label object before await. UI observes joined catalog without overwrite draft. All setters preserve other metadata. Requirements mapping stays ORG-FR-01–10; no Attachment/pin/AI business feature duplicated.

## 8. Acceptance checklist — actual checks before completion

| Group | Required evidence |
| --- | --- |
| Core + preservation | Named API migration all callers/fakes; pre-write fence abort and late-session discard; text/pin/Label/Attachment intent; label create → layout save → ACK/pull/conflict leaves catalog intact |
| Catalog + policy | 0/32/33 IDs; 0/64/65 Unicode code points; duplicate names allowed distinct IDs; trim/no-op; fresh attach/delete race; no Note cascade; deleted ID no resurrection |
| Protocol + bootstrap | Attempted v1 replay/pin absence; missing vs []; owner/type same-id; multi-page H/bootstrap interruption; legacy skip upgrade; no false Ready at gap; response byte cap; queued Label prerequisite; unrelated sync continues |
| UI + access | ALL+keyword/pin ties owner/id, full loaded list, list/grid; partial catalog selection not broadened; stale session discard; chips rename while editor dirty; direct foreign/unsupported protected/shared actions deny |
| Runtime + regression | Web and used Native targets offline/reopen/reconnect; userPreferences survives; full DTO/summary factory parity/conservative changes; verify deployed v1/v2 compatibility separately from mocks |

Dart format touched files; flutter analyze; focused tests first then flutter test per AGENTS; relevant Chrome tests, backend checks from package.json, git diff --check. No feature tests have been run by this planning update. Source mocks do not prove live AWS/platform acceptance.

## 9. Prompt teammate có thể dùng ngay

```text
Read AGENTS.md, docs/contracts/modules_02_03_04_contract.md,
docs/contracts/sync_wire_v2_labels.md and this current M04 plan.
Use source16ee44b as the reviewed base; verify your actual branch/HEAD/delta.
Do not implement from the archived review.

Business choices are settled: ALL labels AND keyword/pin-first; duplicate label
names allowed and IDs stable; max32IDs/Note and64Unicode-code-points/name; local
schema4/wire2, legacy preserve metadata, bootstrap replay from0 with high-water/
caughtUp. Scope owned/unprotected, other policies fail closed. Do not reopen these
choices or add name claims/extra packages/engines without a new requirement.

Start PR-C0 shared-core compatibility before M04 integration. Agree the human
owner of CORE/M04 paths, keep one writer for shared source and preserve existing
dirty work. M04 can write only its own new Label files until core prerequisites
merge. Include the preferences repository and every state-copy writer.

Implement the assigned PRs in order, using version-pinned fixtures, fresh atomic
Note+Label checks, stable attempted requests and explicit conflicts. No fake
Label-as-Note records, implicit unknown=[] clears, missing=catalog-deleted,
concurrent schema variants, metadata drops or allow-all protected/shared guard.
Typing/persisting stays local-first; no per-key HTTP/DB.

Run required source checks, report source/mock/runtime/deployed evidence
separately. This document is implementation-ready planning, not completed code.
Do not deploy AWS, change secrets/signing, merge/commit/push without the
corresponding authorization.
```

## 10. Plan readiness receipt

READY: policy/filter/limits/legacy-version/bootstrap/schema/ownership/PR sequence/tests specified; old review is separate history.
DEPENDENCIES: C0/C1/B1 are real implementation work, not claims that APIs already match.
DEFERRED BY SCOPE: full shared/protected organization and M03 binary feature.
NOT CLAIMED: source implemented, tests run, deploy or Final-project completion.
