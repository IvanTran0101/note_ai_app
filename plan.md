# SOP: Nâng cấp UI/UX NoteFlow theo Notion (mục tiêu 95–100%)

> **Trạng thái:** Kế hoạch thực thi, chưa phải bằng chứng đã implement.
>
> **Audit snapshot 2026-09-24:** branch `TuanKiet2`, HEAD and
> `origin/TuanKiet2` both `2edc3d4` (`Refine Notion-style dashboard home`).
> The working tree also contains an unrelated modified macOS generated
> registrant and existing untracked QA artifacts. Stage only the exact
> UI/test/doc files for each tranche.
>
> **Mục tiêu:** đưa những màn hình và trạng thái NoteFlow đang hỗ trợ về cùng
> ngôn ngữ thị giác, hierarchy, spacing, feedback và responsive behavior với
> Notion ở mức **tối thiểu 95/100 trên từng target và viewport bắt buộc**.
> Không tính tính năng Notion nằm ngoài contract NoteFlow vào mẫu số fidelity.

---

## 1. Nguyên tắc bắt buộc

### 1.1 Phạm vi được phép

Chỉ thay đổi Presentation/UI/UX:

- `lib/presentation/**`
- phần theme và UI wiring trong `lib/main.dart`
- UI tokens/assets chỉ khi thật sự cần cho giao diện
- các test/golden test trực tiếp kiểm tra UI

### 1.2 Phạm vi bị khóa

Không sửa, không đổi chữ ký, không đổi luồng gọi và không đổi dữ liệu của:

- `lib/domain/**`
- `lib/application/**`
- `lib/infrastructure/**`
- `packages/local_llm_bridge/**`
- repository, database, API, Cognito, model provisioning và local AI service
- `lib/presentation/auth/controllers/**`
- route path và redirect trong `lib/presentation/routing/**`

`auth_pages.dart` chỉ được thay đổi cách trình bày. `AuthController`, session, token, logout, refresh và redirect phải giữ nguyên.

### 1.3 Hợp đồng hành vi phải giữ nguyên

Mọi bước UI phải giữ lại:

- `NotesApplicationController.listNotes/createNote/renameNote/replaceContent/deleteNote/summarizeNote`.
- callback `onSave`, `onSummarize`, `onMore`, `onDirtyChanged`, `onEmbeddedExit`.
- trạng thái `canSave`, `isSaving`, `isDirty`, `actionBusy`, `summaryStale` và các trạng thái provisioning.
- autosave, save khi mất focus, cảnh báo nội dung chưa lưu, delete confirmation và back confirmation.
- `ValueKey`, `Semantics`, focus order và text localization hiện có.
- route `/notes`, `/notes/:id`, các route auth và route diagnostics.

**Save contract đã xác minh lại:** NoteFlow hiện dùng autosave; đây không phải
manual-save UI. `_save()` được gọi bởi autosave timer, mất focus và dirty-back
flow. `_buildSurface` truyền `canSave: false`/`onSave: null`, và test xác nhận
không render nút Save. Giữ nguyên contract này; không thêm shortcut hoặc CTA Save
mới. Lỗi tải danh sách từ Chrome không phải bằng chứng để sửa callback hay
persistence.

### 1.4 Quy tắc làm việc

- Mỗi step là một commit nhỏ, có kiểm tra riêng và có thể revert riêng. Theo
  yêu cầu hiện tại, push từng tranche đã qua gate riêng lên `origin/TuanKiet2`;
  không đợi đến khi toàn bộ giao diện đạt 95 mới push.
- Không làm nhiều step trong cùng một patch lớn.
- Không thêm tính năng backend mới để đạt điểm giống Notion.
- Tính năng Notion không có API hoặc dữ liệu tương ứng trong NoteFlow phải được ẩn, disabled có giải thích, hoặc chỉ là trạng thái trình bày không gây side effect.
- Không dùng dữ liệu giả để làm UI trông đầy đủ hơn.
- Không gọi việc hoàn thành prompt là hoàn thành implementation. Chỉ đánh dấu step đạt khi có bằng chứng kiểm tra ở step đó.

### 1.5 Quy tắc "Notion chỉ là reference UI/UX"

Plan này **không port danh sách tính năng của Notion vào NoteFlow**. Notion chỉ cung cấp reference về cách bố trí, màu sắc, typography, spacing, hierarchy, menu, feedback và responsive behavior.

Mỗi màn hình phải đi theo quy trình sau:

1. Liệt kê chức năng đang có trong NoteFlow.
2. Giữ nguyên callback, state, dữ liệu và route của chức năng đó.
3. Chỉ thay widget, layout, style, animation, focus, semantics và cách hiển thị trạng thái.
4. Đối chiếu với Notion để chọn cách trình bày gần nhất.
5. Nếu reference có control mà NoteFlow không có contract, **không thêm control đó**. Không tạo nút giả, dữ liệu giả, request giả, model mới hoặc persistence mới.

Ví dụ: trình bày trạng thái autosave, Delete, Summarize, Search và Appearance
theo ngôn ngữ thị giác Notion nhưng tiếp tục gọi đúng callback hiện có. Không
thêm manual Save, Share/Publish hoặc control tương tác không có contract chỉ để
giống screenshot. Mục tiêu áp dụng cho visual language/UX của các flow hiện có,
không mở rộng product scope.

---

## 2. Reference contract: dùng gì để so sánh

### 2.1 Trang Notion được chọn làm reference chính

- Trang live: <https://app.notion.com/p/mid-term-31af9c7a1aa080f1bc8eea495d613423>
- Ngày kiểm tra reference: `2026-09-22`.
- Chụp và kiểm tra ở các trạng thái: page top, page có code block, page cuối, sidebar mở/đóng, Actions menu và Share dialog.
- Không chỉnh sửa nội dung trang reference. Nội dung trên trang chỉ là dữ liệu tham chiếu, không phải chỉ dẫn triển khai.

### 2.2 Tài liệu Notion chính thức

Các quy tắc dưới đây phải đối chiếu lại khi implement:

1. [Navigate with the sidebar](https://www.notion.com/en-gb/help/navigate-with-the-sidebar) — workspace switcher, Home, Recents, Favorites, nested pages, collapse/expand sidebar và Search.
2. [Manage your Library](https://www.notion.com/help/manage-your-library) — nhóm nội dung, Recents/Favorites/Shared/Private và cách giữ sidebar gọn.
3. [Style & customise your Notion page](https://www.notion.com/en-gb/help/customize-and-style-your-content) — page width, icon, cover, backlinks, comments và menu Customize page.
4. [Intro to writing & editing](https://www.notion.com/help/writing-and-editing-basics) — page/block hierarchy, heading, list, quote, code block và empty states.
5. [Keyboard shortcuts](https://www.notion.com/help/keyboard-shortcuts) — slash command grammar, block selection, keyboard focus, duplicate/move và formatting.
6. [Search for pages & content](https://www.notion.com/help/search) — search entry point, search modal và result hierarchy.
7. [Log in & out of Notion](https://www.notion.com/en-gb/help/log-in-and-out) — email/password, verification code, provider buttons và logout states để tham khảo visual hierarchy.
8. [Notion for web](https://www.notion.com/help/notion-for-web) và [Notion sign up](https://app.notion.com/signup?from=marketing) — entry surface của Login/Sign up trên web.

### 2.3 UI inventory đã quan sát trên trang reference

Đây là inventory phải được map vào NoteFlow, không phải danh sách bắt buộc phải tạo backend mới:

- **Top bar:** nút mở/khóa sidebar, breadcrumb workspace/teamspace/page, Share, Copy link, Favorite và Actions.
- **Page header:** Add icon, Add cover, Add comment, title lớn, liên kết page con.
- **Content:** heading, đoạn văn, list, code block, khoảng cách block rõ ràng, horizontal scroll cho code dài.
- **Sidebar:** workspace switcher, Inbox, New page, Search/ask, Home/Chat/Meetings, Upcoming events, Recents, Shared/Notion apps, profile/settings.
- **Actions menu:** font style, Copy link, Copy page contents, Duplicate, Move, Trash, Small text, Full width, Customize page, Lock, AI, Suggest edits, Translate, Undo, Import/Export, Version history và notification settings.
- **Share dialog:** Share/Publish tabs, invite field, permission rows, General access, Advanced và Copy link.
- **Mobile/compact behavior:** sidebar chuyển thành drawer hoặc sheet, page hiển thị một surface, action menu chuyển thành bottom sheet, bàn phím không che editor.

### 2.4 Quy tắc phân biệt reference và chức năng có thật

Mỗi item trong inventory phải ghi một trong ba nhãn khi implement:

| Nhãn | Cách xử lý |
| --- | --- |
| `SUPPORTED` | Kết nối đúng callback hiện có và test hành vi end-to-end. |
| `PRESENTATION_ONLY` | Chỉ dùng typography, grouping, icon/trang trí và hierarchy; control tương tác vẫn phải gọi callback/state hiện có. |
| `OUT_OF_SCOPE` | Không hiển thị nếu không có contract tương ứng; không giả lập thành công. |

Ví dụ: autosave, Delete, Summarize, Search notes và Appearance là `SUPPORTED`;
manual Save, Share/Publish nếu chưa có contract là `OUT_OF_SCOPE`. Không render
control gây hiểu nhầm rằng chức năng chưa có đang hoạt động.

---

## 3. Bản đồ codebase hiện tại

### 3.1 Shell và responsive

| File | Trách nhiệm hiện tại | Hướng Notion hóa |
| --- | --- | --- |
| `lib/presentation/workspace/workspace_shell.dart` | Dashboard/Notes navigation, IndexedStack, rail/sidebar | Sidebar có section, active row, collapse/expand, workspace header, search affordance; giữ destination và key. |
| `lib/presentation/notes/responsive_notes_workspace.dart` | compact/medium/expanded frame; Notes list hoặc editor chiếm toàn bộ vùng nội dung | Giữ ba breakpoint và việc chuyển list/editor; không dựng list pane song song với editor. |
| `lib/presentation/notes/notes_workspace_page.dart` | load/list/select/create/detail/dirty state | Chỉ đổi composition và visual hierarchy; giữ state machine và controller. |

Breakpoint hiện tại cần được kiểm chứng trước khi chỉnh:

- `< 600`: compact; chỉ hiện Notes list hoặc editor.
- `600–839`: navigation rail bên ngoài vùng nội dung; Notes list hoặc editor chiếm toàn vùng nội dung.
- `>= 840`: sidebar mở `280dp` theo live reference đang dùng ở viewport 1280×720; khi thu gọn, control mở lại là overlay `44×44dp` ở mép trái, không giữ cột rộng cố định; Notes list hoặc editor chiếm toàn vùng nội dung.
- Không có list width riêng ở medium/expanded vì layout hiện hành không hiển thị list và editor cạnh nhau.

### 3.2 Notes và editor

| File | Trách nhiệm hiện tại | Hướng Notion hóa |
| --- | --- | --- |
| `lib/presentation/notes/notes_list_panel.dart` | Notes list, empty/loading/error/retry, selection | Page tree/list kiểu Recents, search affordance, selected row và preview nhẹ. |
| `lib/presentation/notes/note_detail_page.dart` | title/content lifecycle, save, delete, summarize, back, more | Page header/breadcrumb, large title, clean editor surface, status, action menu. |
| `lib/presentation/notes/note_detail_surface.dart` | scroll editor, autosave feedback và action bar | Đổi bố cục/styling; giữ autosave và callback Summarize/More hiện có. Không thêm manual Save. |
| `lib/presentation/notes/note_detail_editor_form.dart` | title/content fields, error/status/summary | Chuyển từ form card sang page-like borderless editor, giữ controller/focus/key. |
| `lib/presentation/notes/note_detail_action_bar.dart` | Autosave status/Summarize/More | Đưa về toolbar/action row giống Notion, giữ disabled/busy semantics; không render manual Save. |
| `lib/presentation/notes/note_detail_more_actions.dart` | More actions | Style menu và confirmation theo Notion; chỉ giữ action thật sự có callback. |
| `lib/presentation/notes/note_detail_summary.dart` | AI summary | Callout/card tinh gọn, trạng thái stale/busy/error rõ ràng. |
| `lib/presentation/notes/model_provisioning_status_panel.dart` | model loading/error/cancel/retry | Callout/status panel đồng nhất với page surface, không đổi provisioning logic. |

`lib/presentation/notes/notes_page.dart` và `note_editor_panel.dart` là surface
legacy/duplicate còn nằm trong repository. `main.dart` hiện compose
`NotesWorkspacePage`; Step 0 phải xác nhận route active trước khi chỉnh, chỉ
style một path đang chạy và không để hai implementation lệch nhau. Không xóa
legacy surface trong task UI nếu chưa có route/test evidence cho phép.

### 3.3 Dashboard, auth và theme

| File | Trách nhiệm hiện tại | Hướng Notion hóa |
| --- | --- | --- |
| `lib/presentation/dashboard/dashboard_page.dart` | overview, search, layout toggle, create/open note | Đưa dashboard về Home/Recents: header gọn, sections, recent cards/list, empty/error rõ ràng. |
| `lib/presentation/dashboard/dashboard_content.dart` | dashboard body | Dùng cùng spacing, typography và surfaces với Notes. |
| `lib/presentation/dashboard/dashboard_note_card.dart` | note card | Giảm card elevation, tăng page-row hierarchy, giữ key/action. |
| `lib/presentation/auth/auth_pages.dart` | login/register/forgot/reset/verify/change password | Style theo reference Login/Sign up của Notion: nền nhẹ, panel hẹp, field/CTA rõ, trạng thái lỗi/busy; giữ form validation, controller, redirect và keys. |
| `_AuthStartupPage`, `EmailVerificationBanner` trong `lib/presentation/auth/` | session restore/retry và banner email chưa verify | Đưa vào cùng auth/workspace visual language; giữ retry, resend, refresh, verify route và controller callbacks. |
| `lib/presentation/notes/notes_theme_tokens.dart` | semantic success colors | Mở rộng token UI nếu cần nhưng giữ `NoteFlowSemanticColors` API. |
| `lib/main.dart` | ThemeData, locale, router composition, settings sheet | Chỉ đổi theme tokens/component themes và presentation wiring; không đổi auth/note composition. |
| `lib/presentation/debug/local_llm_debug_page.dart` | diagnostics/model readiness UI | Restyle loading/ready/failed/cancelled và retry/cancel affordance; giữ reader/callback provisioning hiện có. |
| `lib/presentation/notes/notes_localizations.dart` và các `*_localizations.dart` | EN/VI strings | Bổ sung label UI mới khi cần, không đổi key/meaning của text đang được test. |

### 3.4 Hợp đồng test cần giữ

Các test hiện có phải tiếp tục là regression gate:

- `test/presentation/workspace/workspace_shell_test.dart`
- `test/presentation/notes/notes_workspace_page_test.dart`
- `test/presentation/notes/responsive_notes_workspace_test.dart`
- `test/presentation/notes/note_detail_page_test.dart`
- `test/presentation/notes/note_detail_surface_test.dart`
- `test/presentation/notes/note_detail_action_bar_test.dart`
- `test/presentation/dashboard/dashboard_page_test.dart`
- `test/presentation/auth/auth_pages_test.dart`
- `test/presentation/auth/auth_navigation_integration_test.dart`
- `test/presentation/routing/app_router_test.dart`

---

## 4. Design contract để đạt 95–100%

### 4.1 Token nền tảng

Tạo một bộ token presentation duy nhất, ưu tiên đặt trong `lib/presentation/notes/notes_theme_tokens.dart` hoặc file UI token mới cùng thư mục:

| Nhóm | Quy tắc bắt buộc |
| --- | --- |
| Font | `Inter` variable font và OFL đã được bundle/đăng ký trong `pubspec.yaml`; Web release manifest và Android APK xác nhận asset. iOS/macOS runtime chưa được kiểm tra; dùng cùng font/fallback trong visual diff và xác minh lại trên Apple runner. |
| Surface | Page surface, sidebar surface, elevated menu, selected row và callout phải có token riêng cho light/dark; không rải màu literal trong widget. |
| Text | Có primary, secondary, muted, link, error, success; contrast đạt WCAG AA cho text thường. |
| Spacing | Dùng scale 4/8/12/16/24/32/48; không tạo khoảng cách ngẫu nhiên cho từng màn hình. |
| Radius | Dùng nhóm radius nhỏ cho row/input và radius lớn hơn cho dialog/card; không dùng mỗi component một radius. |
| Divider | Mảnh, ít tương phản, chỉ dùng để phân vùng list/sidebar; tránh đường viền quanh mọi block. |
| Elevation | Menu/dialog có phân cấp rõ; page và list không bị biến thành các card nổi dày. |
| Motion | Hover/focus/selection/expand có transition ngắn, không chặn thao tác và không chạy khi `disableAnimations` của test. |
| Icon | Icon cùng family, kích thước và baseline; tooltip cho icon-only action. |

Không chốt màu bằng cảm giác. Mỗi token phải được kiểm tra trên screenshot reference ở cả light/dark nếu target state có tồn tại.

### 4.2 Layout contract

- Sidebar desktop mục tiêu: `280dp` theo live Notion page đang đối chiếu ở `1280×720`; tài liệu trợ giúp ghi khoảng mặc định 240–264dp nhưng live reference hiện đo được 280px. Row cao tối thiểu `40–44dp`.
- Content page desktop: max width và gutter được đo từ reference; title, breadcrumb, first block và editor action bar phải có anchor ổn định.
- Notes list: selected row có nền nhẹ và text contrast; không dùng primary container quá đậm.
- Editor: title lớn, content borderless, block spacing rõ, scroll không làm trôi navigation shell.
- Dialog/menu: mở gần control nguồn, không vượt viewport, dismiss bằng Escape/back/outside tap đúng nền tảng.
- Safe area: Android gesture area, iOS home indicator, web browser inset và macOS title bar phải không che action/editor.

### 4.3 Interaction contract

- Sidebar toggle giữ trạng thái local trong presentation; không thay đổi route hoặc repository.
- Search dùng flow search hiện có; không thêm endpoint tìm kiếm mới.
- New note gọi đúng `onCreateNote`/`createNote`; không tạo note chỉ bằng cách đổi UI state.
- Select note giữ quy tắc chặn khi dirty và message unsaved hiện tại.
- Save giữ toàn bộ lifecycle: idle → dirty → saving → saved/error; label, progress và focus phải phản ánh state thật.
- Summarize giữ điều kiện không summarize khi đang dirty/busy và giữ provisioning status.
- Delete luôn qua confirmation hiện có.
- More menu chỉ hiển thị action có callback. Action unsupported không được giả vờ thành công.

### 4.4 Responsive contract theo platform đang có

Repo hiện có `android/`, `ios/`, `web/`, `macos/`; không có `windows/` hoặc `linux/`. Phải kiểm tra tối thiểu:

| Target | Kích thước/điều kiện | UI bắt buộc |
| --- | --- | --- |
| Android phone nhỏ | `360×800` | compact, drawer/sheet, bàn phím không che title/content, back gesture không mất dirty state. |
| Android phone phổ biến | `412×915` | compact page/editor, action bar chạm được bằng một tay. |
| iPhone SE | `375×667` | compact, safe area, text không overflow, scroll tới Summarize/action row; trạng thái autosave rõ và không thêm manual Save. |
| iPhone hiện đại | `393×852` | compact, dynamic text cỡ lớn không vỡ layout. |
| iPad portrait | `768×1024` | medium rail; Notes list hoặc editor dùng toàn vùng nội dung, detail có gutter. |
| iPad landscape | `1024×1366` | expanded sidebar + một Notes surface tại một thời điểm, menu không bị cắt. |
| Web Chrome | `1280×800`, `1440×900` | sidebar mở/thu gọn, hover/focus, keyboard shortcuts và resize liên tục. |
| Web narrow | `390×844` | cùng compact contract với phone. |
| macOS | `1440×900` | pointer/hover, menu keyboard, sidebar và dialog theo desktop. |

---

## 5. SOP triển khai từng step nhỏ

### Step 0 — Baseline và khóa hành vi

**Mục tiêu:** có baseline trước khi đổi UI.

Checklist:

- [ ] Xác nhận `git status --short --branch`, branch và HEAD.
- [ ] Chạy `flutter pub get`.
- [ ] Chạy `dart format --output=none --set-exit-if-changed lib test`.
- [ ] Chạy `flutter analyze`.
- [ ] Chạy `flutter test`.
- [ ] Ghi lại kết quả test hiện tại, các warning có sẵn và thiết bị có thể chạy.
- [ ] Ghi route/composition active từ `main.dart`; đánh dấu `NotesPage` và `NoteEditorPanel` là legacy nếu không nằm trên active path.
- [ ] Ghi snapshot save contract tại `NoteDetailPage._buildSurface`: `canSave`, `onSave`, autosave timer, save-on-focus-loss và dirty guard phải được kiểm chứng riêng.
- [ ] Chụp thêm splash/session-restore, email-verification banner, appearance settings và diagnostics/model-provisioning states.
- [ ] Nếu full `flutter analyze` bị chặn bởi package/test ngoài UI, chạy thêm `flutter analyze lib/main.dart lib/presentation` và ghi rõ hai kết quả, không sửa backend để làm sạch blocker đó.
- [ ] Chụp baseline của login, dashboard, notes empty/list/detail, dirty/save/error/summary và dark/light.
- [ ] Ghi snapshot của các key/semantics quan trọng trước khi chỉnh.

**Pass:** baseline chạy được hoặc mọi blocker được ghi rõ, không có thay đổi source.

**Không được tiếp tục:** nếu baseline fail vì lỗi behavior chưa được phân loại.

### Step 1 — Chuẩn hóa reference và bảng đo

**Mục tiêu:** biến reference Notion thành checklist đo được.

- [ ] Mở trang reference chính và các tài liệu chính thức trong mục 2.
- [ ] Ghi kích thước viewport, scroll position, theme và state cho từng ảnh.
- [ ] Đo anchor: sidebar width, header height, title baseline, page gutter, list width, divider, menu/dialog bounds.
- [ ] Lập bảng token tạm thời: color, typography, spacing, radius, elevation, icon size.
- [ ] Đánh dấu từng component `SUPPORTED`, `PRESENTATION_ONLY` hoặc `OUT_OF_SCOPE`.
- [ ] Không đưa Share/Publish, workspace collaboration, database block hay AI chat vào backend nếu repo chưa có contract.

**Output:** `notion-reference-matrix.md` hoặc mục tương đương trong task/PR, gồm ảnh/state/viewport/anchor/tolerance.

**Pass:** mọi state dự kiến implement có một reference và một tiêu chí đo.

### Step 2 — Tạo token và component primitives

**Mục tiêu:** mọi màn hình dùng cùng một ngôn ngữ thị giác.

- [ ] Tạo/chuẩn hóa `NoteFlowUiTokens` hoặc mở rộng `NoteFlowSemanticColors`.
- [ ] Đưa surface/text/divider/selected/focus/error/success vào token.
- [ ] Chuẩn hóa `ThemeData` trong `_buildNoteFlowTheme` cho light/dark.
- [ ] Chuẩn hóa `ButtonStyle`, `InputDecorationTheme`, `ListTileTheme`, `DialogTheme`, `BottomSheetTheme`, `TooltipTheme`.
- [ ] Tạo primitives presentation-only nếu cần: `NotionSurface`, `NotionSidebarRow`, `NotionPageHeader`, `NotionSectionLabel`, `NotionActionMenu`.
- [ ] Mỗi primitive phải có semantics, focus, hover/pressed/disabled và test widget tối thiểu.
- [ ] Không thay đổi public contract của feature widgets.

**Pass:** cùng một token cho cùng một visual role; không còn màu/radius/spacing literal trùng lặp trong các file đã chỉnh.

### Step 3 — Làm lại workspace shell và sidebar

**Mục tiêu:** đạt parity cho navigation frame của Notion.

Files chính: `workspace_shell.dart`, `workspace_localizations.dart`, token/theme files.

- [x] Giữ `WorkspaceDestination`, `showDestination`, IndexedStack và `onDestinationChanged` (18 shell widget tests pass).
- [x] Desktop: static workspace identity header, search affordance, section label, the existing Home/Notes rows, and labeled Settings/Diagnostics footer actions when their callbacks are supplied (captures 115–117, 121).
- [x] Do not add Favorites, profile identity, workspace switching, or Recents rows to the sidebar unless NoteFlow gains matching product contracts; existing Dashboard content may keep its real recent-note section.
- [x] Map chỉ Dashboard/Notes vào dữ liệu hiện có; không tạo page giả.
- [x] Active row có nền, icon và text weight rõ (Home/Notes active states in captures 115/116).
- [ ] Xác minh focus ring của active/sidebar row khớp reference và thấy rõ bằng keyboard.
- [x] Sidebar collapse/expand không làm mất page state (existing collapse and breakpoint-retention tests pass; capture 117 verifies collapsed geometry).
- [x] Medium rail giữ labels và selected state (capture 120; shell widget tests pass).
- [x] Compact dùng hamburger và bottom sheet cục bộ (capture 118; destination-switch test passes).
- [ ] Kiểm tra keyboard focus của rail và system back/gesture trên thiết bị.
- [x] Icon-only controls đang có tooltip/semantics; không thêm control tương tác mới.
- [ ] Kiểm tra sidebar ở light/dark, text dài EN/VI và dynamic text.

**Pass:** shell giống reference ở desktop; mobile không có navigation chrome thừa; route/state tests cũ vẫn pass.

### Step 4 — Làm lại Home/Dashboard theo Recents

**Mục tiêu:** dashboard nhìn như Home/Recents của Notion nhưng dùng dữ liệu NoteFlow thật.

Files chính: `dashboard_page.dart`, `dashboard_content.dart`, `dashboard_note_card.dart`,
`dashboard_state_views.dart`, dashboard localizations.

- [x] Giữ `DashboardController`, `NotesApplicationController`, `onOpenNote`, `onCreateNote`;
  không đổi sort/filter/create/open/reload data flow.
- [x] Giữ title, search toggle/field, New note, sort/layout controls, settings/diagnostics
  callbacks và mọi `ValueKey` hiện hữu.
- [x] Chỉ hiển thị phần Home có dữ liệu NoteFlow: note count, supported update date,
  sort theo `updatedAt`/`createdAt`, preview và hai layout List/Grid. `NoteDto` không có
  visit history nên section phải ghi `Recently updated`, không giả là `Recently visited`.
- [x] Desktop dùng top bar 44px và Dashboard content column tối đa 960px với inset trên
  64px; compact giữ inset trên 32px. 960px là target cho trang Recent rộng hơn editor,
  chưa phải anchor đo được từ ảnh Notion.
- [x] List row bỏ card elevation, giữ icon/title/preview/update date và selected/hover;
  row chạm được tối thiểu 56px. Grid giữ layout toggle hiện có và thêm page marker chung,
  không thêm icon field vào model.
- [x] Loading skeleton theo header, controls và note rows của loaded view; empty/error,
  Web storage limitation và filtered-empty giữ copy/callback/state semantics.
- [ ] Capture cùng viewport/theme cho loaded List/Grid, loading, empty, error, search và
  selected states; pair với Notion Home và chấm từng anchor. Không lấy widget-test fixture
  hoặc Web storage error làm bằng chứng runtime có note data.

**Pass:** create/open/search/sort/retry/empty/error/loading behavior tests pass; same-state
visual comparison đạt tối thiểu 95/100 trên từng viewport/target được hỗ trợ. Chưa đánh dấu
Pass khi chưa có cặp ảnh và rubric đã chấm.

### Step 5 — Làm lại Notes list và chuyển sang editor

**Mục tiêu:** Notes destination giống Notion page tree; khi chọn/tạo note, editor dùng cùng vùng nội dung như một trang tập trung.

Files chính: `notes_workspace_page.dart`, `notes_list_panel.dart`, `responsive_notes_workspace.dart`.

- [ ] Giữ `_loadNotesInternal`, `_selectNote`, `_startNewNote`, dirty guard và `_handleDetailExit`.
- [ ] List header gọn, New note là affordance rõ, search/section label chỉ dùng nếu map được callback hiện có.
- [ ] Row có icon/page marker, title, preview và selected background theo token.
- [ ] Loading dùng skeleton/progress phù hợp nhưng giữ `notes-workspace-loading` semantics.
- [ ] Empty, error, retry và no-selection state cùng visual language.
- [ ] Medium/desktop không dựng list/detail cạnh nhau; list và editor lần lượt dùng cùng vùng nội dung.
- [ ] Gutter, header và scroll ownership của từng page surface phải ổn định khi chuyển list/editor.
- [ ] Compact chỉ hiển thị list hoặc detail; back không mất dirty state.
- [ ] Kiểm tra `ResponsiveNotesWorkspace.onCompactBack`: active `NotesWorkspacePage` phải có đúng một back affordance (app bar hoặc wrapper), gọi cùng dirty/back-confirmation flow và không tạo hai nút back.
- [ ] Giữ `compactKey`, `mediumKey`, `expandedKey`, `listPaneKey`, `detailPaneKey`.

**Pass:** list/editor state transitions pass test; không có overflow ở width 360/375/390 hoặc medium/desktop.

### Step 6 — Làm lại Notion-like page editor

**Mục tiêu:** detail page đạt parity cao nhất vì đây là surface chính.

Files chính: `note_detail_page.dart`, `note_detail_surface.dart`, `note_detail_editor_form.dart`, `note_editor_panel.dart`, `note_detail_summary.dart`, `note_detail_action_bar.dart`.

- [ ] Header có back, breadcrumb/page title và more theo callback thật.
- [ ] Title field trở thành page title lớn, borderless, focus ring tinh tế.
- [ ] Content field trở thành editor surface sạch, multiline, gutter và line height giống reference.
- [ ] Nếu chưa có block model, chỉ mô phỏng spacing/heading/paragraph bằng content hiện có; không đổi `NoteDto` thành block database.
- [ ] Summary hiển thị dưới dạng callout/card nhẹ, giữ copy/regenerate và stale state nếu callback có.
- [ ] Provisioning/error/status là callout đồng nhất, giữ retry/cancel.
- [ ] Action bar theo toolbar grammar nhưng chỉ hiện Summarize/More khi callback hiện có cho phép; hiển thị dirty/saving/saved/error từ state autosave thật.
- [ ] Giữ `canSave: false`/`onSave: null` vì baseline và test xác nhận autosave-only; không đổi thành manual Save. Kiểm chứng create/update/error qua controller test seam và đánh dấu riêng việc Chrome chưa kết nối được backend.
- [ ] Dirty indicator hiển thị ở header/action bar nhưng không tự ý thay đổi autosave.
- [ ] Delete/back confirmation giữ dialog và route result hiện tại.
- [ ] Giữ toàn bộ keys: `note-detail-title-field`, `note-detail-content-field`, `note-detail-summary`, `note-detail-dirty`, `note-detail-more-delete`, `note-detail-delete`, `note-detail-back`, `note-detail-scroll`.

**Pass:** xác minh create/update/error qua controller test seam và persistence thật trên target native có hỗ trợ; Web phải hiện trạng thái storage unavailable từ baseline, không giả thành công; visual score page/editor tối thiểu 95.

### Step 7 — Actions, overlays và feedback states

**Mục tiêu:** menu/dialog có cùng behavior grammar với Notion mà không giả lập backend.

- [x] More menu dùng popup neo theo trigger ở màn hình từ 600dp; compact tiếp tục dùng bottom sheet. Delete giữ destructive color; kiểm tra geometry, Escape, barrier dismiss và system back ở widget tests.
- [x] Delete và dirty-back dùng chung elevated dialog surface theo token sáng/tối, viền nhẹ, radius 12dp và typography/padding đồng nhất. Widget tests kiểm tra hình học ở viewport 360×640 với 220dp keyboard inset; kết quả và callback của từng nút giữ nguyên.
- [x] Các transient message đang có ở Notes list/detail/workspace dùng chung floating toast theo token sáng/tối; Undo action được giữ nguyên callback.
- [x] Chỉ gắn Delete bằng callback hiện có; không đổi hành vi xác nhận/xóa note.
- [ ] Nếu có page width/theme/language là local presentation setting, hiển thị trong menu/sheet hiện có.
- [x] Không thêm Share/Publish/Invite call nếu chưa có service contract.
- [ ] Audit error/retry, saved/saving, summarizing, model provisioning và unsaved callouts trên đủ viewport/theme; giữ nguyên cách các trạng thái inline hoạt động.
- [ ] Dialog và bottom sheet tôn trọng safe area, keyboard, barrier color và focus trap.
- [x] More popup đóng bằng Escape; compact bottom sheet đóng bằng system back trong widget tests. Runtime keyboard/back QA trên từng target vẫn thuộc Step 10.

**Pass:** mọi overlay có open/close/focus/dismiss test; không có menu bị cắt ở viewport nhỏ.

### Step 8 — Auth UI theo Notion reference, chỉ dùng auth flow hiện có

Files chính: `lib/presentation/auth/auth_pages.dart`, `auth_localizations.dart`, theme tokens.

Reference visual: [Notion login](https://notion.com/login), [Notion sign up](https://app.notion.com/signup?from=marketing) và [Notion login methods](https://www.notion.com/en-gb/help/log-in-and-out). Đây là reference về layout, spacing, hierarchy, field treatment, provider grouping và feedback; không phải yêu cầu thêm provider hoặc auth capability vào NoteFlow.

- [ ] Style Login/Register/Forgot/Reset/Verify/Change Password cùng surface, type scale, field, CTA và error callout.
- [ ] Bao phủ riêng các màn hình Login và Sign up/Register, cùng các state initial, validation error, submit busy, provider/auth error, forgot password, reset code, email verification và change password.
- [ ] Đối chiếu Login/Sign up ở desktop và phone: panel width, logo/brand area nếu hiện có, email/password order, primary CTA, secondary link, divider/provider area chỉ khi NoteFlow đã có provider tương ứng.
- [ ] Không thêm Google/Apple/Microsoft/passkey/SSO chỉ vì Notion có; nếu backend NoteFlow không có callback thì control đó là `OUT_OF_SCOPE` và không được render.
- [ ] Giữ các key email/password/submit và toàn bộ validator/autofill/onFieldSubmitted.
- [ ] Giữ `AuthController` calls, busy state, safe mapped errors và `go_router` redirect.
- [ ] Bao phủ splash/session restore + retry và `EmailVerificationBanner` trong workspace; giữ các key resend/refresh/open verification và không đổi auth controller.
- [ ] Login compact có scroll, keyboard inset và CTA luôn tới được.
- [ ] Không đổi Cognito, session, token, logout hay refresh.

**Pass:** Login và Sign up/Register đạt visual score tối thiểu 95 ở desktop/mobile; auth tests và auth navigation integration tests pass; không gửi request thêm.

### Step 9 — Accessibility, localization và input parity

- [ ] Semantics label/value/hint cho sidebar row, page title, editor, save, summarize, more, delete, retry và status live region.
- [ ] Focus order: sidebar → header → title → content → action bar; focus visible ở light/dark.
- [ ] Hit target tối thiểu `44×44dp` cho touch; pointer hover không thay thế pressed state.
- [ ] Kiểm tra EN/VI, chuỗi dài, text scale 1.0/1.3/2.0 và screen reader labels.
- [ ] Kiểm tra keyboard: Tab/Shift+Tab, Enter/Space và Escape. Không thêm Ctrl/Cmd+S vì không có manual-save contract.
- [ ] Không đặt shortcut mới nếu nó đụng behavior hoặc không thể test cross-platform.

**Pass:** không overflow, semantics tree không mất node quan trọng, labels không lộ key nội bộ.

### Step 10 — Visual QA theo ma trận thiết bị

Chạy lại cùng một workflow trên tất cả target có trong repo:

1. Login và Sign up/Register: initial, validation, busy, auth error, provider area nếu được hỗ trợ, forgot/reset, verify email và change password.
2. Dashboard loading/empty/loaded/search/filtered-empty/error/retry.
3. Notes loading/empty/list/selected/new/dirty; kiểm tra saved/save-error trên target mà baseline hỗ trợ persistence. Web dùng trạng thái storage unavailable đã có trong baseline và phải được trình bày rõ.
4. Detail summary loading/ready/stale/error, model provisioning loading/failed/cancelled.
5. Sidebar open/closed, destination switch, More menu, delete/back confirmation, appearance settings.
6. Splash/session restore, email-verification banner và diagnostics/model provisioning: loading/ready/error/retry/cancel.
7. Dark/light và EN/VI.
8. Rotate/resize hoặc viewport tương đương mobile/tablet/desktop.

Mỗi state phải có screenshot baseline/reference, screenshot implementation và ghi chú sai lệch. Không chấp nhận screenshot chỉ khác vì đã scroll sai vị trí.

**Pass:** weighted score ở mục 6 đạt `>= 95`, không có critical fail.

### Step 11 — Regression, build và handoff

- [ ] `dart format --set-exit-if-changed lib test`.
- [ ] `flutter analyze`.
- [ ] Bắt buộc có thêm `flutter analyze lib/main.dart lib/presentation`; full-repo analyze chỉ được coi là pass khi package test dependency đã hợp lệ, còn nếu vẫn vướng `packages/local_llm_bridge/test` thì ghi blocker ngoài UI.
- [ ] `flutter test`.
- [ ] Chạy riêng nhóm test presentation/auth/routing.
- [ ] `flutter build web`.
- [ ] `flutter build macos` trên macOS nếu có runner.
- [ ] `flutter build apk --release` trên môi trường JDK 17+; lỗi JVM 11 phải xử lý ở môi trường build, không sửa Gradle/backend trong task UI.
- [ ] `flutter build ios --no-codesign` trên macOS nếu có runner.
- [ ] Kiểm tra `git diff --name-only` chỉ chứa UI/theme/test/docs được phép.
- [ ] Kiểm tra mọi control mới bằng bảng callback: control phải trỏ tới callback/state hiện có; control không có contract phải bị loại khỏi UI.
- [ ] Kiểm tra không có model/service/repository/API/route mới và không có thay đổi trong `lib/domain`, `lib/application`, `lib/infrastructure`, `packages/local_llm_bridge` hoặc auth controller.
- [ ] Chạy review "UI-only diff": mọi diff chỉ giải thích được bằng layout/style/UX/state presentation của chức năng hiện có.
- [ ] Ghi screenshot matrix, test command, commit hash và known limitation.
- [ ] Sau khi gate của từng tranche pass, commit và push tranche đó lên
  `origin/TuanKiet2`; giữ nguyên các thay đổi ngoài tranche. Chỉ công nhận Done
  toàn bộ khi các gate cuối cùng trong mục 9 đều pass.

---

## 6. Bộ tiêu chí chấm fidelity 100 điểm

Chấm ở từng viewport và lấy điểm thấp nhất của từng nhóm; không lấy trung bình để che một màn hình lỗi.

| Nhóm | Điểm | Cách chấm đạt |
| --- | ---: | --- |
| Cấu trúc và hierarchy | 25 | Sidebar/header/page/Notes list/editor đặt đúng vùng theo responsive contract, anchor lệch không quá ±2–4px theo viewport. |
| Màu và surface | 15 | Light/dark surface, text, selected, focus, error/success và divider khớp token/reference; không có màu ngẫu nhiên. |
| Typography | 15 | Font/fallback, size, weight, line height, truncation và baseline đồng nhất; không wrap sai ở viewport mục tiêu. |
| Spacing và geometry | 15 | Gutter, row height, block spacing, menu/dialog bounds và touch target khớp reference. |
| Component states | 10 | Hover, focus, pressed, selected, disabled, loading, dirty, saving, error, empty và summary có state rõ. |
| Responsive/platform | 10 | Android/iOS phone, iPad/tablet, web và macOS đạt layout contract; không overflow/keyboard overlap. |
| Accessibility/localization | 5 | Semantics, focus, contrast, EN/VI, text scale và keyboard pass. |
| Regression behavior | 5 | Save/delete/summarize/search/auth/route callback vẫn hoạt động đúng trên target mà baseline hỗ trợ; target vốn không hỗ trợ một capability phải thể hiện limitation rõ và không giả thành công. |
| **Tổng** | **100** | **Release chỉ khi `>= 95` và không có critical fail.** |

### 6.1 Critical fail — điểm tổng không được dùng để bỏ qua

Một trong các lỗi sau làm step fail dù tổng điểm cao:

- không login được do đổi auth flow;
- không tạo/lưu/sửa/xóa note được trên target mà baseline hỗ trợ thao tác đó;
- autosave status/callback không còn phản ánh đúng lifecycle đang có; không yêu cầu manual Save button vì `_buildSurface` truyền `onSave: null`;
- mất note khi đổi destination/resize/rotate;
- route/redirect thay đổi ngoài yêu cầu;
- backend/domain/application/infrastructure bị sửa;
- lỗi overflow/blocked CTA trên phone;
- semantics key hoặc test contract quan trọng bị xóa.

Web persistence là limitation có sẵn: `FileDatabaseContext` chọn stub không hỗ trợ file read/write khi chạy Web. Không thêm Web storage/backend trong task UI; đây không phải regression do redesign, nhưng UI không được báo saved hoặc che trạng thái không lưu được.

### 6.2 Visual diff protocol

- Dùng cùng device pixel ratio, viewport, theme, locale, seed data và scroll offset.
- So sánh overlay và pixel diff; bỏ qua sai khác antialiasing nhỏ do engine nhưng không bỏ qua geometry/color/text wrap.
- Tách sai lệch do font engine khỏi sai lệch do layout; không hạ threshold để “cho pass”.
- Mỗi lỗi ghi `screen/state/viewport/anchor/current/expected/fix`.
- Lặp lại sau mỗi step, không chờ đến cuối mới phát hiện layout sai.

---

## 7. Checklist theo dõi implementation

### Re-review 2026-09-23 — corrective audit

Execution checkout: branch `TuanKiet2`, committed base `926b590` before the auth email-first tranche.
The previous table's `DONE` labels for Steps 0–9 and its `95/100` claim are
withdrawn. The checklists in Sections 5 and 6 were still unchecked, the stored
captures were not paired with same-state Notion captures for every viewport,
and the current browser cannot load a persisted note. The old score therefore
does not prove the plan's `>=95` gate. Treat every step below as incomplete
until its stated evidence is captured against the active checkout.

This corrective UI pass now includes neutral Notion-matched theme tokens, a
720px title block with 708px body-text width, a 112px editor content inset, a
page header with the existing back/dirty-confirmation path, full-page
list/editor navigation on medium and wide layouts, and explicit load-error
states that do not claim the collection is empty. The collapsed desktop sidebar
now uses a 44×44px reopen overlay and reserves no permanent content column.
Current NoteFlow captures show the title anchor at x=280, y=168 for 1280px
width when the desktop sidebar is collapsed. A same-state live comparison at
1280×720 dark with both sidebars open measured the Notion title at x=420, y=170;
the current source preview after matching the sidebar width measured NoteFlow
at x=420, y=168. This is one paired anchor check, not a saved pixel-diff or a
full-page score. Captures 54–55 record the collapsed NoteFlow state only. The sidebar, list,
dashboard, auth, and other states still need paired review. Earlier targeted
analyzer, presentation tests, web release build, and Android release APK build
passed; the Android build used JDK 17. The latest targeted widget run after the
editor and collapsed-sidebar adjustments did not reach assertions because the
`local_llm_bridge` native-asset hook encountered a corrupt `.obj` file. The full
repository run with the test shim reports 600 passed and two AI infrastructure
tests unable to load; a direct test without the shim confirms native asset
compilation stops at `llama-kv-cache-dsv4.obj : fatal error LNK1136: invalid or
corrupt file`.
The current Web preview explicitly reports that it cannot load or save notes;
there is no persisted-note state to compare in the browser. Persistence and the
full visual score remain unverified; no score of 95 or higher is claimed.

Auth follow-up on 2026-09-23: captures 29–32 record the earlier Login/Register
layout and are historical. Captures 66–69 recorded Login and Register at
1280×800 and 390×844, paired by viewport with reference captures 24, 26, 20,
and 22. Login captures 66/69 remain current; Register captures 67/68 predate
the email-first and panel-top refinements. The side-by-side review finds the
brand/header placement,
form width, and core surfaces close, while the auth flows still differ in
hierarchy and content: NoteFlow keeps its supported password Login and
four-field registration; Notion's references show an email-first step and
provider controls. No auth provider or backend behavior is added to imitate
those unsupported controls. This is a qualitative visual review only, not a
rubric score: the four captures do not cover all auth states, accessibility,
or target platforms, so no auth or app-wide numeric score is assigned. The
available evidence does not establish the `>=95/100` gate.

Typography follow-up on 2026-09-23: the app theme requested the `Inter` family,
but the checkout contained no Inter font asset or pubspec font registration.
The UI-only asset pass bundles the Inter variable font and OFL license and
registers the family in `pubspec.yaml`; it adds no package and changes no auth,
note, route, or data flow. FontTools confirms the `opsz` 14–32 and `wght`
100–900 axes and Vietnamese glyph coverage (font SHA-256
`29160A80FF49DDCAB2C97711247E08B1FAB27A484A329CE8B813D820DC559031`).
`flutter analyze --no-pub lib` passes, and the current presentation suite passes
191/191 with the temporary test-only `local_llm_bridge` shim and restored
package-config hash below. The Web release build passes (Flutter 3.47.5,
399.1s); `FontManifest.json`, the font, and OFL file are present in its output.
The Android release APK also passes (92,217,544 bytes; 1,758.1s), and its
archive contains the same font and license. Capture 86 shows the bundled font
rendered in the 1280×720 light Web Home; this page displays the existing Web
storage limitation and contains no loaded or persisted note. The unfiltered
`flutter analyze --no-pub` still reports 42 existing issues in the unrelated
`local_llm_bridge` tests and temporary output shim; no files in those areas are
part of this asset change. iOS/macOS builds and device rendering remain
unverified because this Windows environment lists only Windows, Chrome, and
Edge in `flutter devices --machine`. These checks close the Web/Android font
packaging gap only; they do not establish full cross-platform typography or the
95-point visual gate.

Current Login uses 38px compact/72px desktop top padding. Register starts with
Email, followed by Display name, Password, and Confirm password; it uses 76px
compact/32px desktop top padding and a 496px desktop panel, with the existing
32px fallback for short viewports. `_AuthFormScaffold` now keeps its selected
page background painted through the available viewport while preserving scroll
when content is taller. The auth widget suite passes 11/11 with the temporary
test-only `local_llm_bridge` package-root shim. Coverage checks the background
at 360×800, 393×852, 768×1024, 1280×550, 1280×800, and 1440×900 for both Login
and Register, plus 200% text-scale submit reachability at 360×800.
`.dart_tool/package_config.json` was restored to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
Widget assertions cover the Email/Display name order and 393×852, 1280×800,
and 768×1024 layout bounds; the desktop registration panel top is constrained
to 28–36px around the 32px Notion reference anchor. Captures 67–68
predate these changes. Capture 85 shows the current source at 1280×800 in a
signed-out debug Web run; the Flutter debug ribbon is visible and excluded
from fidelity scoring. The local-auth release preview rendered Home after
navigation to `/register`; I did not override auth state. A
previous current-source presentation run passed 189/189 using a temporary
test-only package-root shim for the unrelated native `local_llm_bridge` hook.
After adding the text-scale and viewport-background checks, the full
current-source presentation suite passed 191/191 and the auth page suite passed
11/11. The package config was
restored byte-for-byte to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`. An
earlier run had hit a transient disk-full error and stalled; it is superseded
by this completed presentation-suite run.

Web warning follow-up on 2026-09-23: the editor keeps the explicit notice that
draft changes cannot be saved and will be lost when leaving, but uses a muted
cloud-off icon and neutral surface for unsupported storage. The page-header
status and Home limitation notice now use the same muted icon; ordinary
save/load errors remain errors. Captures 47–48 record the 1280×800 Web states.
Targeted `flutter analyze` and the Web release build pass. The focused
note-detail widget test stops before assertions because native linking reports
53 unresolved GGML/llama symbols in `local_llm_bridge.dll`. This remains a test
environment blocker; paired Notion comparisons and device visual QA are still
incomplete, so this does not establish the 95-point gate.

Responsive editor recheck on 2026-09-23: captures 49–50 from an earlier release
preview appeared to show the title resetting after resize. A fresh release
build from the current source, served from a distinct output directory and
port, retained the same title and body through 1280×800 → 390×844 → 768×1024 →
1280×800, including after the Web storage-unavailable notice appeared. Treat
49–50 as superseded observations; the original discrepancy is unresolved and
must not be described as a confirmed current regression. The fresh run exposed
a separate compact-width title clipping issue. `NoteDetailEditorForm` now lets
long titles wrap, keeping its existing controller, key, focus node, and
callbacks. The latest Web release build renders the title across multiple
lines at 390×844 and retains the dirty draft at 768×1024 and 1280×800 (captures
51–53). Targeted analyzer passes. The focused widget test remained in the
`local_llm_bridge` native-asset hook for 90 seconds and was interrupted before
assertions. This closes only the observed Web wrap/resize checks; it does not
verify successful persistence or the overall 95-point gate.

The Web dirty-back flow was also checked in the release browser at 390×844:
after entering a temporary title and navigating back, capture 56 shows the
existing unsaved-changes dialog with the explicit Web draft-loss message and
Cancel/Discard actions; it does not offer Save. This verifies the presentation
of that one limitation state only, not persistence, the remaining overlays, or
the overall 95-point gate.

The same browser flow revealed that discarding a Web draft cleared the notes
load error and displayed the empty collection state. The presentation state now
retains the load error on discard/cancel and clears it after save/delete;
capture 57 confirms the Web storage-unavailable state remains visible after
discard. The regression in
`test/presentation/notes/notes_workspace_page_test.dart` passed as part of the
37-test focused workspace suite using a temporary test-only
`local_llm_bridge` shim. The original `.dart_tool/package_config.json` was
restored byte-for-byte (SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`). This
checks state retention only; it does not verify Web persistence or the overall
95-point visual gate.

Auth email-first presentation follow-up on 2026-09-23: Login now presents Email
before the existing Password field; Register presents Email before the existing
Display name, Password, and Confirm password fields. Continue only advances
local presentation state; the final action still calls the existing controller
with the existing `LoginInput` or `RegisterInput`. No auth controller, route,
domain, application, infrastructure, or persistence file changed. The complete
presentation suite passed 193/193 using the temporary test-only
`local_llm_bridge` shim; `.dart_tool/package_config.json` was restored to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`. Targeted
`flutter analyze --no-pub` on the two auth sources and two auth test files found
no issues, and `git diff --check` passed. No release/browser capture of these
new auth steps has been made, so no auth or app-wide numeric visual score is
assigned and the `>=95/100` gate remains unproven.

Auth visual recheck on 2026-09-24: captured the live public Notion Login and
Sign up pages at 1280×800 and 390×844 (references 111–114), with no form
submission. PNG dimensions were checked; historical references 24 and 26 are
1280×720 despite their filenames and are not valid 1280×800 pairs. Current
NoteFlow release captures 104–110 cover Login/Register email, password/details,
and 768×1024 registration. Blue CTA pixel bounds show Register mobile matches
the live reference at x=20–369, y=375–414; Login differs by 3px vertically on
mobile and desktop. The desktop Register CTA was moved down to the same
reference row via presentation-only callout padding/spacing; release capture
106 now matches the live Sign up CTA at x=460–819, y=396–435 within 1px
horizontally and exactly vertically. No auth controller, route, DTO, service,
or persistence file was changed. A direct test invocation stopped before its
assertions in the unrelated native `local_llm_bridge` hook (`LNK1136`); the
test-only package-root shim then passed the full presentation suite 193/193 and
restored `.dart_tool/package_config.json` to its expected SHA-256. Targeted
analyzer and format checks pass. These auth comparisons do not score the full
app and do not establish the `>=95/100` release gate.

Shared navigation focus follow-up on 2026-09-24: `NoteFlowSidebarRow` now
renders the existing theme `focusRing` token as a 2dp outline while focused.
Keyboard Tab traversal, focus loss, and light/dark token colors are covered in
the primitive widget test; callbacks, selected semantics, labels, and hit area
remain unchanged. The full presentation suite passes 200/200 using a temporary
test-only `local_llm_bridge` package-root shim; direct test startup still hits
the unrelated `llama-vocab.obj` `LNK1136` hook failure. The package config was
restored to SHA-256
`BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`.
`flutter analyze --no-pub lib/main.dart lib/presentation` and
`dart format --output=none --set-exit-if-changed lib test` pass, as does
`git diff --check`. Web
release builds in 72.5s and Android release APK builds at 88.0 MB in 58.5s.
Runtime discovery still finds only Windows, Chrome, and Edge, with no Android
AVD; iOS/macOS runtime/build checks remain unavailable on this Windows host.
This verifies the focus treatment and current Web/Android compilation only; no
numeric app-wide score is assigned and the `>=95/100` gate remains unproven.

| Step | Evidence rechecked | Status | Remaining gate |
| --- | --- | --- | --- |
| 0. Baseline | Current checkout and browser load/error states inspected; saved browser note and complete runtime baseline not verified | `PARTIAL` | Record actual create/edit/save/delete/auth behavior against reachable backend, without changing it |
| 1. Reference matrix | Live workspace-page observations retained with their original dates; public Login/Sign up captures 111–114 are same-size 1280×800 and 390×844; old files 24/26 are actually 1280×720; one editor anchor is paired, but workspace surface states still lack complete same-state diffs | `PARTIAL` | Pair shell, Home, list/editor, menus and overlays at supported viewports; keep auth comparison limited to supported controls |
| 2. Tokens/primitives | Inter variable font/OFL are bundled; Web manifest and Android APK contain both; capture 86 shows Web rendering at 1280×720 light; shared sidebar focus outline uses the existing light/dark `focusRing` tokens and is verified by keyboard test; iOS/macOS remain unverified | `IN_PROGRESS` | Verify iOS/macOS font rendering; recheck light/dark screenshots, text contrast, and all shared components after final styling |
| 3. Shell/sidebar | Release Web captures 115–121 cover Home/Notes selected, expanded 280px sidebar, labeled Settings/Diagnostics footer, collapsed overlay, compact menu/header, 768px rail, and 1024px expanded layout. `workspace_shell_test.dart` passes 18/18; shared row Tab focus and blur render a 2dp token outline in both themes and preserve the selected semantics/callback tests; primitive suite passes 9/9. Current Web release build passes (72.5s). | `IN_PROGRESS` | Pair current shell screenshots with Notion references, verify dark/light screenshots and long localized labels visually, run Android runtime checks and Apple builds/device checks; no Favorites/profile/workspace-switching controls |
| 4. Dashboard/Recents | Current-source Web Home captures 70, 78 and 122 show the explicit storage-unavailable state at 1440×900, 390×844 and 1280×800; no loaded note data is available in this Web build | `PARTIAL` | Compare Home's supported states with Notion and verify controller-backed loaded data on a supported native target |
| 5. Notes list/detail frame | Current-source captures 71–76 cover 1280×800, 1024×768, 768×1024, 390×844, 360×800 and 1440×900 with the explicit Web storage limitation; capture 123 refreshes the 1280×800 state. Captures 56–57 verify dirty-back and retained load error. Notes suite passes 86/86 with a test-only bridge package root; `.dart_tool/package_config.json` restored to SHA-256 `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`; focused analyzer passes and targeted formatter reports 0 changed files. | `IN_PROGRESS` | Verify selection and return states with real native data; capture loaded/selected states and pair supported states against Notion |
| 6. Page editor | 720px title block, 708px body-text width, 112px content inset, `NoteFlow / New note` breadcrumb, captures 51–53 for long-title wrap/draft retention, captures 54–55 for collapsed-sidebar placement, and capture 56 for Web dirty-back warning with no Save action; captures 49–50 are superseded conflicting observations | `IN_PROGRESS` | Pair supported editor states with Notion, capture remaining error/summary states, verify native persistence where a compatible runner is available, and complete editor visual review |
| 7. Menus/overlays/status | More is an anchored popup at ≥600dp and remains a bottom sheet below 600dp. Delete and dirty-back confirmations share token-based elevated surfaces in light/dark themes; both are tested at 360×640 with a simulated 220dp keyboard inset. Existing transient Notes messages use a shared light/dark floating toast; its optional Undo action and callback are preserved and covered by tests. Existing tests also cover menu placement, 8px edge tolerance, Escape/system-back/barrier dismissal and Delete callback. Notes suite passes 86/86 with the test-only bridge package root. Current Web release and Android APK builds pass. Web cannot load a saved note, so runtime overlay captures and full state pairs remain unavailable. | `PARTIAL` | Review overlays on Android and Apple runners, test focus/semantics and remaining status states, and capture same-state visual pairs |
| 8. Auth UI | Release captures 104–110 cover the current email/password/details steps at desktop/phone/tablet; public same-size Notion refs 111–114; Register mobile CTA matches pixel rows and desktop CTA now matches after a presentation-only spacing adjustment; auth behavior contracts retained; full presentation suite passes 200/200 using the test-only bridge package root | `IN_PROGRESS` | Capture desktop Register details and supported validation/busy/error/success/change-password states; finish accessibility/localization checks; record only supported-control comparison and keep overall score unassigned |
| 9. Accessibility/localization | Login/Register test checks submit reachability at 200% text scale in a 360×800 viewport; page background fills six phone/tablet/desktop dimensions for both auth forms; existing semantics and locale tests cover only tested widgets; shared sidebar row Tab focus/blur is verified in light and dark themes | `PARTIAL` | Re-run focus, semantics, EN/VI, 1.0/1.3/2.0 scale, keyboard and touch-target gates across all final UI surfaces |
| 10. Device visual QA | Platform folders are Android/iOS/Web/macOS; no Windows runner folder. Runtime discovery lists Windows, Chrome and Edge only, with no Android device/emulator. Current shell Web captures 115–121 cover Home/Notes, expanded/collapsed sidebar, compact menu/header, tablet rail and 1024px expanded layout; the APK compiles, but no Android runtime session exists. No iOS/macOS runner is available on this Windows host; Home/list/editor/menus/overlays still lack complete same-state Notion pairs | `PARTIAL` | Run Android on a connected device/emulator; build and test iOS/macOS on an Apple runner; complete paired screenshots and responsive/accessibility checks for all supported UI states |
| 11. Regression/build/handoff | Full presentation suite passes 200/200 using a temporary test-only package-root shim; package config restored to SHA-256 `BB1F5D5C8F88BED214DF461A6D8B4B7F62CAB1F38829E65E05C4FEA9C9D73025`. `flutter analyze --no-pub lib/main.dart lib/presentation` reports no issues; `dart format --output=none --set-exit-if-changed lib test` reports 171 files, 0 changed; `git diff --check` passes. Current Web release build passes (72.5s); Android release APK passes (88.0 MB, 58.5s). Device discovery finds Windows/Chrome/Edge only and no Android emulator; iOS/macOS runtime/build checks remain unavailable on this Windows host. Direct native-hook tests still fail on unrelated `llama-vocab.obj` (`LNK1136`). | `IN_PROGRESS` | Continue UI tranches; run Android device/emulator QA and iOS/macOS checks on an Apple runner; complete paired visual review and audit the allowlisted diff before each push |

---

## 8. Rollback protocol

1. Dừng ngay ở step đang fail.
2. Lưu screenshot, test output và `git diff` của step đó.
3. Revert đúng commit của step hiện tại; không revert các step đã được duyệt.
4. Không apply hoặc drop stash cũ nếu không có yêu cầu riêng.
5. Nếu lỗi liên quan save/backend, trả về commit trước step UI đó và kiểm tra lại `canSave`, `onSave`, dirty state và controller call.
6. Chỉ tiếp tục sau khi baseline regression trở lại pass.

---

## 9. Definition of Done

Kế hoạch chỉ được đánh dấu hoàn tất khi tất cả điều kiện sau đúng:

- [ ] UI NoteFlow đạt `>= 95/100` ở mọi viewport bắt buộc; mục tiêu tốt nhất là 98–100.
- [ ] Sidebar, page header, list/detail, editor, action menu, overlays, auth và dark/light cùng một design system.
- [ ] Save note, create, edit, delete, summarize, search, auth và routing giữ đúng behavior trên từng target mà baseline hỗ trợ; Web giữ nguyên limitation persistence và hiển thị trạng thái không lưu được.
- [ ] Không có thay đổi trong domain/application/infrastructure/backend/persistence/auth controller.
- [ ] Không có critical fail, overflow, mất focus, mất dirty state hoặc CTA bị che.
- [ ] `dart format`, `flutter analyze`, presentation/auth tests và build target phù hợp đã chạy; output được ghi lại.
- [ ] Diff cuối cùng đã được review theo allowlist và từng step có thể rollback độc lập.
