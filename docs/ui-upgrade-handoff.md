# UI Upgrade — Step 11 Handoff (2026-09-22)

Branch `TuanKiet2` (reset to plan baseline `6233e16` = `note-ai-app` HEAD),
one commit per plan step for independent rollback.

## Commits

| Step | Commit | Nội dung |
| --- | --- | --- |
| 0–1 | `b113c71` | baseline + Notion reference matrix (docs) |
| 2 | `2c03f32` | NoteFlowUiTokens, theme chuẩn hóa, 5 primitives + tests |
| 3 | `cc64db0` | workspace shell + sidebar Notion (collapse, rail, compact menu) |
| 4 | `58c0c16` | dashboard Home/Recents, page-row previews |
| 5 | `e0d8e3e` | notes list page rows + list/detail frame |
| 6 | `5710bdd` | page editor (title 40/700, editor 720px, toolbar, callouts) |
| 7 | `893fa86` | menu grammar: More sheet destructive, dialogs |
| 8 | `60e4569` | auth surfaces theo Notion login |
| 9 | `32c24db` | a11y contract tests + quyết định keyboard |
| 10 | `b0255cb` | visual QA matrix 13 screenshots + điểm 95/100 |
| 11 | (commit cuối) | format gate sạch + handoff này |

## Verification commands (đã chạy, 2026-09-22)

```bash
dart format --output=none --set-exit-if-changed lib test   # PASS (0 changed)
flutter analyze lib/main.dart lib/presentation              # PASS (no issues)
flutter analyze                                             # 41 issues — CHỈ
                                                            # packages/local_llm_bridge/test
                                                            # (blocker ngoài UI, y hệt baseline)
flutter test --no-pub        # PASS 586 tests, 1 skip (native-DLL smoke)
flutter test --no-pub test/presentation/workspace test/presentation/notes \
  test/presentation/dashboard test/presentation/auth \
  test/presentation/routing  # PASS 143 tests (regression gate của plan §3.4)
flutter build web            # PASS (cả 2 chế độ auth)
```

Test-gate shim cho Windows: xem `docs/ui-upgrade-baseline.md` (trỏ
`package_config.json` sang bản copy không `hook/` của `local_llm_bridge`, chạy
`--no-pub`). Mọi `flutter pub get` sẽ ghi đè `rootUri`; áp lại dòng ghi shim
để chạy test.

## Diff review (plan §Step 11)

- `git diff --name-only 6233e16..HEAD` chỉ chứa: `lib/presentation/**`,
  `lib/main.dart` (theme/UI wiring), `docs/**`, `test/**`, `plan.md`, và
  format-only trên `lib/amplify_outputs.dart` (file generated — bắt buộc bởi
  chính format gate) + 3 test file format-only.
- Không chạm: `lib/domain`, `lib/application`, `lib/infrastructure`,
  `packages/local_llm_bridge`, auth controller, route path/redirect.
- Không có model/service/repository/API/route mới; mọi control mới đều trỏ
  callback có thật (onOpenSettings/onOpenDiagnostics là optional wiring từ
  composition root); không control Share/Publish/Invite/SSO giả.

## Build matrix

| Target | Kết quả |
| --- | --- |
| `flutter build web` | PASS |
| `flutter build apk --release` | NOT RUN — máy thiếu Android toolchain (cmdline-tools, theo `flutter doctor`); cần chạy ở môi trường có Android SDK + JDK 17 |
| `flutter build macos` / `ios --no-codesign` | NOT RUN — không có macOS runner |

## Known limitations

1. Thiết bị Android/iOS/macOS vật lý chưa QA trực tiếp (xem `docs/ui-qa/README.md`).
2. `packages/local_llm_bridge`: test analyze thiếu `package:test`; hook build
   Windows link lỗi (thiếu advapi32, object trùng tên) — cả hai ngoài phạm vi
   UI, đã ghi ở baseline.
3. Trạng thái summary/provisioning screenshot bằng widget test thay vì ảnh
   (web data layer local mode fail — hạ tầng).
4. `native_toolchain_c` pub cache bị vá `runInShell: false` ở máy này (môi
   trường, không phải repo) — mất khi `pub cache repair`.
