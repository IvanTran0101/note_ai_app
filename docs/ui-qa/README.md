# UI Visual QA — Step 10 (2026-09-22)

Captures run against the release web build served locally (Chrome 153,
DPR 1). Two builds were used: `--dart-define=NOTEFLOW_AUTH_MODE=local` for
workspace states and the default Cognito build for auth states. Reference
anchors come from `docs/notion-reference-matrix.md` (live-measured
2026-09-22).

## Capture inventory

| File | State | Viewport | Theme |
| --- | --- | --- | --- |
| `01-dashboard-empty-1440-light.png` | dashboard first load | 1440×900 | light |
| `02-notes-1440-light.png` | notes workspace, list empty+error | 1440×900 | light |
| `03-editor-new-1440-light.png` | new note editor (no Save, Summarize disabled) | 1440×900 | light |
| `04-editor-dirty-1440-light.png` | editor with title/content + dirty indicator | 1440×900 | light |
| `05-editor-dirty-1440-dark.png` | editor dirty | 1440×900 | dark |
| `06-dashboard-1440-dark.png` | dashboard | 1440×900 | dark |
| `07-notes-medium-768-light.png` | notes workspace with rail | 768×1024 | light |
| `08-compact-393-light.png` | compact single-surface | 393×852 | light |
| `09-dashboard-compact-393-light.png` | compact dashboard | 393×852 | light |
| `10-settings-sheet-1440-light.png` | appearance/settings bottom sheet | 1440×900 | light |
| `11-login-1440-light.png` | Login panel | 1440×900 | light |
| `12-register-1440-light.png` | Register panel | 1440×900 | light |
| `13-login-compact-393-light.png` | Login compact | 393×852 | light |

Workflow coverage per plan §Step 10: Login/Sign up (initial), dashboard
(loading→empty/error/retry), notes (empty/error/new/dirty), editor states
(new/dirty/summarize-disabled), sidebar open + collapse affordance, More
menu and delete/back confirmations (widget-tested; dialog captures omitted),
settings sheet, dark/light. Summary ready/stale and model-provisioning
states are covered by widget tests (`note_detail_page_test`,
`model_provisioning_status_panel_test`) — see limitations.

## Fidelity score (plan §6, worst case per group)

| Nhóm | Điểm | Nhận xét |
| --- | ---: | --- |
| Cấu trúc và hierarchy | 24/25 | Sidebar 248, top bar 44, list/detail/editor đúng vùng; editor cap 720 ≈ reference 708–720. −1: workspace vẫn có hai thanh header (AppBar "NoteFlow · Notes" + header list) so với một top bar của Notion. |
| Màu và surface | 14/15 | Token khớp số đo live (#FFF/#191919, selected gray, muted, divider hairline) ở cả light/dark. −1: nhãn field khi focus dùng màu link xanh — sôi động hơn focus treatment của Notion (giữ làm focus affordance). |
| Typography | 15/15 | Title 40/700/lh48 khớp đo; body 16/24 khớp đo; font stack nền tảng ≈ stack của Notion web. |
| Spacing và geometry | 14/15 | Scale 4–48 nhất quán, row/touch ≥44, radius 6/8/12 đúng nhóm. −1: khối hint summary cách editor một khoảng do vùng minLines của content field. |
| Component states | 10/10 | hover/pressed/selected/disabled/loading/dirty/saving/error/empty/summary-stale đều có treatment rõ và có test. |
| Responsive/platform | 8/10 | Layout contract đạt tại 320–1440 (widget test + capture web); compact/medium/expanded đúng breakpoint; không overflow ở 2.0x text. −2: chưa chạy được trên thiết bị Android/iOS/macOS vật lý (máy không có runner). |
| Accessibility/localization | 5/5 | Semantics label thân thiện (kiểm chứng live trên web), tooltip đủ, EN/VI + text scale 1.0–2.0 có test, không lộ key nội bộ. |
| Regression behavior | 5/5 | 586 tests xanh, 1 skip (native-DLL smoke); toàn bộ callback/route/save/delete/auth giữ nguyên. |
| **Tổng** | **95/100** | Đạt gate tối thiểu; các khoản trừ đều được nêu tên ở trên. |

## Known limitations (không che giấu)

1. **Thiết bị vật lý**: Android/iPhone/iPad/macOS chưa được chụp trực tiếp
   (máy QA chỉ có Windows + Chrome). Safe-area/keyboard overlap được cover
   bằng widget test và SafeArea usage, nhưng phải kiểm tra lại trên thiết bị
   thật trước khi release theo plan §4.4.
2. **Data layer trên web local mode** khiến các screenshot chủ yếu ở trạng thái
   empty/error; trạng thái list đầy đủ/summary/provisioning được cover bằng
   widget test thay vì screenshot (infrastructure issue nằm ngoài phạm vi UI).
3. **Sidebar/Share/menu đầy đủ của Notion** không chụp được từ trang reference
   (view-only); đối chiếu theo docs + inventory của plan §2.3 như đã ghi trong
   reference matrix.
4. Build native (`apk`/`ios`/`macos`) và `flutter build web` full regression
   thuộc Step 11; build web đã pass cả hai chế độ auth trong QA này.
