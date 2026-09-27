# Kế hoạch SOP: hoàn thiện UI/UX NoteFlow theo Notion trên Android và Web

> **Trạng thái:** đang triển khai. Checkout đích là `D:\kiet\hk7\flutter\midterm\note_ai_app-note-ai-app` trên nhánh `TuanKiet2`; không thực hiện kế hoạch này trong thư mục `note_ai_app-note-ai-app-lite`. Lượt 2026-09-27 có capture Android editor portrait và Web editor ở compact/desktop; điểm platform vẫn chưa qua gate fidelity đầy đủ.
>
> **Cập nhật kế hoạch:** 2026-09-27. Bằng chứng mới nhất và điểm lower-bound nằm ở đầu [ui-audit-scorecard.md](ui-audit-scorecard.md); cặp ref/current, metadata và giới hạn capability nằm trong [docs/ui-qa/notion-reference-matrix.md](docs/ui-qa/notion-reference-matrix.md). Chỉ capture từ source hiện tại được tính cho lượt này.
>
> **Phạm vi của tài liệu:** giao diện Android portrait và Flutter Web trên Chrome, dựa trên chức năng và hợp đồng đang có trong NoteFlow. Mục tiêu tối thiểu là 95/100 cho từng cell UI áp dụng; không dùng điểm trung bình để che một màn hình hoặc viewport chưa đạt.
>
> **Tài liệu đi kèm:** nhật ký chấm điểm, ảnh kiểm thử và kết quả lịch sử nằm riêng trong [ui-audit-scorecard.md](ui-audit-scorecard.md). Các kết quả lịch sử phải được chạy lại nếu dùng làm bằng chứng cho source hiện tại.
>
> **Tham chiếu:** 218 ảnh Android trong hinhanh/UI_android_ref và 200 ảnh Web trong hinhanh/UI_web_ref. Đã xác nhận các thư mục này có trong checkout chính vào 2026-09-26.

---

## 0. Khóa checkout và nhánh triển khai

- **Repo duy nhất:** `D:\kiet\hk7\flutter\midterm\note_ai_app-note-ai-app`.
- **Repo không được dùng:** `D:\kiet\hk7\flutter\midterm\note_ai_app-note-ai-app-lite`.
- Trước mỗi M, chạy `git rev-parse --show-toplevel` và `git branch --show-current`. Nếu root không khớp repo duy nhất ở trên thì dừng, không sửa file và không chép plan từ Lite sang.
- Commit UI đã được duyệt lên `origin/TuanKiet2` theo từng M sau khi qua gate. Browser-local QA chỉ chạy trong profile/origin hiện tại; adapter và dữ liệu local không được đưa vào commit.
- Một M chỉ được tính là hoàn tất khi status, diff, test, runtime capture và scorecard đều được kiểm tra ở checkout này.

## 0.1 Vòng thực hiện bắt buộc cho mỗi milestone

1. Chốt một M và đọc lại file sở hữu, behavior contract, ref anchor cùng scorecard của M đó.
2. Ghi `git status --short`, HEAD, branch và file thay đổi trước M; không reset, stash, xóa hoặc format cả repo.
3. Chụp baseline cùng platform, viewport, orientation, DPR, theme, locale, dữ liệu, UI state và scroll position với ref đã chọn.
4. Sửa presentation trong allowlist của M. Giữ nguyên callback, controller, model, route, key, semantics key và data source.
5. Chạy format/analyze/test theo gate của M; chạy đúng Android emulator portrait hoặc Chrome viewport mà M yêu cầu.
6. Chụp current source, đo anchor theo cùng đơn vị và cập nhật điểm **bằng số** trong `ui-audit-scorecard.md` cùng trạng thái trong mục 8.
7. Thiếu cặp ảnh, thiếu runtime, lỗi chưa phân loại hoặc phép đo chưa đạt thì cell ghi `0/100 lower-bound — UNVERIFIED`; không dùng `N/C`. Chỉ capability đã chứng minh là ngoài hợp đồng mới nhận `100/100 scope-compliance`, tách khỏi điểm fidelity.
8. Đọc staged diff và file list; chỉ stage file của M. Chặn commit nếu diff chứa backend, browser-local adapter/data, output, ảnh QA hoặc auth ngoài ngoại lệ layout được giới hạn rõ trong M-13. Với file đang có thay đổi từ trước, stage riêng đúng hunk thuộc M; không stage validators, auth flow hoặc thay đổi khác.
9. Sau gate, tạo một commit riêng cho M rồi push lên `origin/TuanKiet2`; xác minh HEAD và remote cùng commit. Không force-push.

Nếu một bước không đạt, giữ bằng chứng, đánh dấu M `IN_PROGRESS`, ghi nguyên nhân và việc cần làm tiếp; không tuyên bố đạt 95% dựa trên estimate.

## 1. Quyết định phạm vi và các khóa bắt buộc

### 1.1 Chỉ sửa phần trình bày

Được phép sửa:

- Widget, layout, typography, spacing, màu, icon presentation, animation, focus, semantics và responsive behavior trong lib/presentation/**.
- Token/theme và cách nối vào UI trong `lib/main.dart` chỉ khi style được scope riêng cho workspace/notes. Không sửa `ThemeData` toàn app theo cách có thể làm đổi Login/Register; không thay router, controller, service hay composition nghiệp vụ.
- UI assets cần thiết, widget/golden tests trực tiếp kiểm tra presentation và tài liệu QA.
- Chỉ dùng callback, state, model và dữ liệu hiện có để render control.

### 1.2 Những phần bị khóa

Không sửa, đổi chữ ký, đổi cách gọi, đổi payload hoặc thay nguồn dữ liệu của:

- lib/domain/**, lib/application/**, lib/infrastructure/**.
- Backend/API, database/schema, repository, Cognito, model provisioning và local AI service.
- lib/presentation/auth/controllers/**, session/token, authentication, authorization và refresh.
- Source trong `lib/presentation/auth/**` và `test/presentation/auth/**` chỉ được sửa trong M-13, đúng allowlist layout và test geometry của tranche đó. Mọi auth controller/service, validation rule, form field, callback, copy/localization và test ngoài M-13 vẫn khóa.
- Route, redirect và điều kiện truy cập trong lib/presentation/routing/**.
- Autosave, persistence, retry, delete, summarize, search, sorting hoặc data lifecycle.

**Login và Register — ngoại lệ M-13 có giới hạn:** M-13 được phép chỉnh căn giữa và bố cục responsive của các widget Login/Register hiện có để khớp phân cấp thị giác của ref. Không đổi logo, field, CTA, validator, copy, localization, callback, controller, route, auth flow hoặc thêm chức năng. Mọi tranche khác tiếp tục chỉ regression và không sửa auth.

### 1.3 Hợp đồng lưu note

- Editor tiếp tục autosave theo lifecycle hiện có. Không thêm nút Save, shortcut Save, endpoint hoặc callback mới.
- Trên TuanKiet2, giao diện phải phản ánh đúng capability lưu của source đang chạy; baseline lịch sử ghi Web báo storage unavailable.
- Ngoại lệ QA đã được yêu cầu: nhánh Test_Tuankiet có thể lưu note bằng localStorage trong đúng origin/profile của trình duyệt để kiểm tra UI workflow. Dữ liệu đó không gửi lên backend, không đồng bộ thiết bị, và adapter cùng test/factory wiring của nó tuyệt đối không được stage, commit, cherry-pick hoặc push lên TuanKiet2.
- Nếu adapter QA đang nằm trong working tree TuanKiet2, giữ nguyên để chủ sở hữu xử lý; không xóa, reset hoặc đưa vào commit UI.

### 1.4 Hợp đồng hành vi phải giữ

Mỗi milestone phải bảo toàn:

- NotesApplicationController và các callback create/open/rename/update/delete/summarize hiện có.
- canSave, onSave, isSaving, isDirty, actionBusy, summaryStale, provisioning status và thông báo lỗi/thành công đang dùng.
- Autosave timer, save-on-focus-loss, dirty/back guard, delete confirmation và kết quả điều hướng.
- ValueKey, Semantics, focus order, localization keys, route path và các test contract hiện có.
- Tạo note phải gọi luồng tạo thật; UI không được hiển thị note thành công nếu lưu thất bại.

### 1.5 Dùng Notion làm chuẩn trình bày, không làm chuẩn chức năng

Mỗi control trong ảnh tham chiếu phải được phân loại trước khi làm:

- **SUPPORTED:** chức năng và callback/state đã có trong NoteFlow; giữ nguyên behavior và thay presentation.
- **PRESENTATION_ONLY:** chỉ mượn hierarchy, typography, spacing, iconography hoặc surface; không tạo tương tác mới.
- **OUT_OF_SCOPE:** chưa có model/callback/route/service trong source hiện tại, hoặc người dùng đã khóa phạm vi; không render control giả, không giả dữ liệu, không giả trạng thái thành công.

final_project.md là bối cảnh rubric/tính năng dự kiến. Nó không tự cấp phép tạo callback, model hoặc UI điều khiển cho tính năng chưa có trong source. M-01 phải đối chiếu từng tính năng với source đang chạy. Mục không có capability hiện hành được ghi **DONE — OUT_OF_SCOPE** trong matrix để agent sau không tự triển khai; sau khi xác minh source, chấm **100/100 điểm tuân thủ phạm vi** cho mục đó vì UI không giả vờ cung cấp tính năng ngoài hợp đồng. Điểm tuân thủ phạm vi này tách biệt với điểm visual fidelity và không được gọi là tính năng đã hoạt động. Trước khi xác minh xong M-01, hàng audit đó nhận **0/100 lower-bound — UNVERIFIED**.

### 1.6 Avatar và logo

- Góc trên trái của Android Home là ảnh profile của tài khoản. Giữ avatar và thao tác hiện có; không thay bằng logo Notion.
- Logo Notion được người dùng cho phép dùng trong vùng nhận diện ứng dụng đã có nếu tranche đó yêu cầu. Không đặt logo vào vị trí avatar. M-13 không thay logo hoặc nội dung nhận diện Login/Register.

---

## 2. Nguồn tham chiếu và bản đồ sử dụng

### 2.1 Reference chính

- Notion live page: https://app.notion.com/p/mid-term-31af9c7a1aa080f1bc8eea495d613423
- Android: hinhanh/UI_android_ref
- Web: hinhanh/UI_web_ref
- Chỉ lấy reference của đúng viewport, theme, scroll position và state tương ứng. Ảnh chứa dữ liệu hoặc tính năng Notion ngoài NoteFlow chỉ là nguồn học visual pattern.

### 2.2 Các cụm ảnh cần ưu tiên

| Surface NoteFlow | Android reference ưu tiên | Web reference ưu tiên | Dùng để học |
| --- | --- | --- | --- |
| Home và danh sách gần đây | 001, 032–036, 049–054, 087, 154, 179, 181, 198, 209, 213–214 | 002–003 chỉ tham khảo sidebar/Recents; nội dung vẫn là trang note `Introduction`, chưa xác nhận là Home | Thứ bậc Home/Recents, khoảng cách section, row/card và scroll. Không dùng phần body của trang note làm cặp Home; chỉ hiển thị note thật, không tự thêm Favorites/Private. |
| Sidebar, workspace menu, Settings | 002–009, 039–040, 056, 061, 073, 085, 100–105, 122–130, 212 | 001–003, 033; 001–003 đang ở trang note, dùng cho sidebar/tab state | Navigation density, menu/sheet, Settings grouping, selected state. Chỉ map destinations có trong app. |
| Search | 013, 016–030, 094–095, 155–165, 180, 182–205, 215–218 | 008–009, 034 | Search overlay, filter/sort hierarchy, result title và context. Chỉ render filter/sort có callback thật. |
| Note/page view và editor surface | 014–015, 037, 057, 096–099, 131, 135, 166, 184, 191, 193, 195, 200, 205 | 007, 010, 016, 026 | Breadcrumb, title, content width, page spacing, action placement và scroll. |
| Page actions và overlays | 054–055, 074–076, 086, 093, 098–099, 132, 173–178 | 004–006, 012, 036 | Menu anchor, bottom sheet/dialog geometry, destructive action và dismiss. Chỉ giữ action NoteFlow hỗ trợ. |
| Login/Register | 077–083 | 058 | Dùng làm tham chiếu bố cục cho M-13; chỉ sửa căn chỉnh/surface của control hiện có. Không thêm provider, field hay auth behavior không được NoteFlow hỗ trợ. |
| Notion-only surfaces | Chat, Calendar, Inbox, database, share/publish, comments, tasks, AI chat và page-version-history trong các ảnh tương ứng | 011, 015, 027–028, 035–038 và các trang database | Chỉ đánh dấu OUT_OF_SCOPE trừ khi M-01 chứng minh NoteFlow đang có đúng capability và callback. Không tạo màn hình hoặc control giả. |

Danh sách trên là tập ảnh anchor để bắt đầu. M-02 phải lập matrix chứa đầy đủ tên file được chọn, không suy đoán nội dung từ số thứ tự; các ảnh chưa đọc trực tiếp không được ghi là reference đã xác nhận. 2026-09-27 kiểm tra trực tiếp `notion-web-001-home.jpg`, `notion-web-002-home-tab.jpg` và `notion-web-003-recents-expanded.jpg`: cả ba đang hiển thị page `Introduction`; 001–003 không phải cặp Home-content. Đánh giá matrix theo trạng thái thực tế của từng ảnh.

### 2.2.1 Các anchor đã mở trực tiếp trong lượt rà plan

| Ảnh đã xem | Quan sát trực tiếp | Cách dùng trong plan | Không được sao chép thành chức năng |
| --- | --- | --- | --- |
| Android `001_01_home_recents-favorites-private.png` | Avatar tài khoản ở góc trên trái; thanh Home/chat/calendar/inbox; Recent cards; các nhóm Favorites/Private; thanh tìm kiếm và tạo ở đáy. | Tham chiếu vị trí avatar, mật độ điều hướng, Recents và nhịp dọc của Home. | Chat, Calendar, Inbox, Favorites, Private hoặc AI composer nếu NoteFlow không có route/state/callback tương ứng. Avatar vẫn là ảnh tài khoản. |
| Android `014_06_recent-final-page.png` | Page title lớn, nút Back và More/Share, các trang con dạng hàng. | Tham chiếu page hierarchy, title, khoảng cách và vùng actions; ghép với ref editor phù hợp ở M-02 trước khi chấm editor. | Share hoặc child-page creation nếu NoteFlow không hỗ trợ. Đây là page có child rows, không mặc định coi là màn nhập title/content. |
| Android `018_07_search-aptis-results.png` | Search heading, query/AI prompt, result title, parent context, snippet và dock tìm kiếm. | Tham chiếu thứ bậc Search/results và khoảng cách giữa kết quả. | Ask AI, filter hoặc preview nếu không có callback NoteFlow. |
| Android `217_search-filters-sheet-portrait.png` | Bottom sheet Filters có Sort, Title only, Created by. | Chỉ tham chiếu hình thức sheet nếu app đã có sheet tương ứng. | Filter và sort trong Search nếu current NoteFlow không có state/callback cho chính các điều kiện đó. Sort Home không tự chứng minh Search filter được hỗ trợ. |
| Web `notion-web-007-page-view.jpg` | Sidebar khoảng 270 px, breadcrumb/actions trên top bar, page title và body trong content column. | Anchor desktop cho shell/page header, title baseline, content gutter và độ rộng vùng đọc. | Không dùng screenshot này làm Home; nội dung là page `Data mining`. |
| Web `notion-web-008-search-overlay.jpg` | Search overlay giữa màn hình, result list bên trái và preview pane bên phải. | Đo bounds, top offset, radius, hàng query và danh sách kết quả. | Preview pane và các filter không được dựng giả nếu NoteFlow chưa có dữ liệu/hành vi tương ứng. |
| Web `notion-web-010-lecture-page.jpg` | Page icon/title, callout và body có heading/list trong Notion page canvas. | Tham chiếu page typography và content rhythm khi có cùng loại block trong NoteFlow. | Không thêm icon, callout, rich-text block hoặc attachment chỉ để khớp ảnh. |

M-02 vẫn phải kiểm inventory và metadata toàn bộ ref được chọn. Bảng này là bằng chứng những anchor vừa được mở trực tiếp, không thay thế audit tất cả 218 ảnh Android/200 ảnh Web.

### 2.3 Output kiểm soát reference

Tạo hoặc cập nhật docs/ui-qa/notion-reference-matrix.md trong M-02. Mỗi dòng gồm:

- Tên file reference chính xác và đường dẫn.
- Platform, viewport, orientation, theme, locale, DPR và scroll position.
- NoteFlow screen/state tương ứng.
- Capability label ở mục 1.5.
- Anchor/measurement cần so.
- Ghi rõ lý do OUT_OF_SCOPE cho Notion-only screen.

---

## 3. Baseline giao diện và chức năng trong source

M-01 phải xác nhận các file dưới đây còn nằm trên active route trước khi sửa. Nếu source đã đổi, cập nhật map theo source; không suy luận chỉ từ tên file.

| Khu vực | File chính đã biết | Bất biến |
| --- | --- | --- |
| App shell và navigation | lib/presentation/workspace/workspace_shell.dart | Giữ destination, key, callback, selected state và navigation behavior. |
| Responsive Notes frame | lib/presentation/notes/responsive_notes_workspace.dart, notes_workspace_page.dart | Giữ list/detail transition, dirty guard, create/select/load lifecycle. |
| Home/Dashboard | lib/presentation/dashboard/dashboard_page.dart, dashboard_content.dart, dashboard_note_card.dart, dashboard_state_views.dart | Giữ create/open/search/sort/layout/retry và dữ liệu thật. Section nếu không có visit history phải gọi Recently updated, không giả là Recently visited. |
| Notes list | lib/presentation/notes/notes_list_panel.dart | Giữ title, preview, selection, empty/loading/error/retry, create action và keys. |
| Editor | lib/presentation/notes/note_detail_page.dart, note_detail_surface.dart, note_detail_editor_form.dart, note_detail_action_bar.dart | Giữ title/content lifecycle, autosave, focus, save status và callback; không thêm manual Save. |
| Summary và actions | lib/presentation/notes/note_detail_summary.dart, note_detail_more_actions.dart, model_provisioning_status_panel.dart | Giữ summarize/delete/more/provisioning state và confirmation. |
| Theme/localization | lib/presentation/notes/notes_theme_tokens.dart, các presentation localization files, phần theme trong lib/main.dart | Mở rộng token/label nếu cần, không đổi meaning/key/API của chuỗi đang được test. |
| Auth | lib/presentation/auth/** | Chỉ M-13 được sửa layout Login/Register trong allowlist hẹp; không sửa AuthController, validation, auth flow, route hay localization. Các file auth khác chỉ regression. |
| Diagnostics/Settings | lib/presentation/debug/** và UI Settings đang được shell gọi | Restyle chỉ khi route/callback hiện có; không thêm setting hoặc provisioning behavior. |

Feature map phải liệt kê capability có thật cho: Home, grid/list nếu source hỗ trợ, sort, search, create, edit, autosave, delete, summary, Settings/Appearance, diagnostics và provisioning. Các tính năng trong final_project.md như attachment, label, pin, khóa note, share, collaboration hoặc AI Q&A chỉ vào map SUPPORTED nếu source hiện tại có đầy đủ dữ liệu và callback phù hợp. Nếu không, ghi OUT_OF_SCOPE và ẩn control đó.

---

## 4. Design contract và ma trận đo

### 4.1 Quy tắc thiết kế

- Dùng một hệ token presentation cho light/dark: page/sidebar/menu surface, primary/secondary/muted text, divider, selected, hover/focus, error và success.
- Giữ font fallback của platform trừ khi reference và runtime chứng minh cần điều chỉnh; không thêm font package chỉ để ép một screenshot.
- Dùng spacing scale nhất quán 4/8/12/16/24/32/48; gom radius và elevation theo role; divider mảnh; icon cùng family/baseline.
- Desktop ưu tiên sidebar gọn, page canvas phẳng và content width có giới hạn; mobile ưu tiên một surface mỗi lần, drawer/sheet phù hợp và vùng chạm tối thiểu 44×44 logical px.
- Không biến mỗi note row hoặc đoạn editor thành card nổi. Không thêm border quanh mọi block.
- Tôn trọng system bars/safe area, bàn phím, pointer hover, keyboard focus và system Back.
- Xác nhận breakpoint hiện hành từ source và runtime trước khi thay đổi. Kế hoạch hiện tại là compact dưới 600dp, medium 600–839dp, expanded từ 840dp; chỉ thay presentation khi có bằng chứng overflow hoặc mismatch.

### 4.2 QA targets

| Target | Viewport bắt buộc | Điều kiện |
| --- | --- | --- |
| Android phone nhỏ | 360×800 portrait | Status/navigation bar, keyboard, scroll, dirty/back flow và hit targets. |
| Android phone tham chiếu | 412×915 portrait | Dùng Android emulator API 35 nếu khả dụng; kiểm tra Home, Notes và editor runtime. |
| Android tablet | 768×1024 portrait khi có emulator/device phù hợp | Rail/layout medium, gutter và state retention. Nếu không có target thật thì cell vẫn được tính 0 điểm trong lower-bound; không thay bằng ảnh browser rồi chấm Android. |
| Web Chrome compact | 390×844 | Sidebar chuyển responsive đúng thiết kế; keyboard/viewport; search và editor. |
| Web Chrome tablet | 768×1024 và 1024×768 | Kiểm tra thay đổi chiều rộng/cao, overlay và scroll. |
| Web Chrome desktop | 1280×800 và 1440×900 | Sidebar mở/thu gọn, pointer hover, keyboard focus, menu/dialog và page width. |

Ảnh Android đầu ra chỉ chụp portrait theo yêu cầu. Không tạo ảnh capture Android landscape. Kế hoạch này không yêu cầu chấm iOS, macOS hoặc Edge; không suy diễn điểm cho các target đó từ emulator Android hay Chrome.

### 4.3 Quy tắc đo Notion fidelity

Chấm từng cell platform × viewport × screen/state đang được NoteFlow hỗ trợ:

| Nhóm | Trọng số | Điều kiện chính |
| --- | ---: | --- |
| Structure và hierarchy | 27 | Sidebar/header/page/list/editor đúng vùng; anchor chính lệch tối đa ±4 logical px. |
| Surface và màu | 15 | Surface, text, selected, divider, error/success khớp reference; màu phẳng sai mỗi kênh RGB không quá 6. |
| Typography | 15 | Font fallback, size sai tối đa 1 px, line height tối đa 2 px, weight/baseline/wrap hợp lý. |
| Geometry và spacing | 17 | Control edge/khoảng cách lệch tối đa ±2 logical px; row, gutter, menu và dialog không bị cắt. |
| Component states | 10 | Focus, hover, pressed, selected, disabled, loading, empty, dirty, saving, saved/error hiển thị đúng state thật. |
| Responsive/platform | 11 | Không overflow, keyboard/system bar không che control; đúng touch/pointer/navigation behavior. |
| Accessibility/localization | 5 | Semantics, focus order, contrast, EN/VI và text scale trong vùng sửa. |
| **Tổng** | **100** | Mỗi platform chỉ đạt mục tiêu khi mọi cell áp dụng đã chấm và điểm thấp nhất đạt ít nhất 95. |

Cùng cặp ảnh phải dùng cùng viewport, DPR, theme, locale, dữ liệu, state và scroll offset. Mỗi item được ghi PASS/FAIL cùng measurement; không nới tolerance sau khi xem kết quả. Không để trống điểm: capability áp dụng nhưng thiếu evidence phải nhận **0/100 (lower-bound) — UNVERIFIED**. N/A chỉ cho capability thật sự không thuộc current contract; ghi lý do, loại khỏi mẫu số rồi chuẩn hóa. Capability được hỗ trợ nhưng chưa chạy hoặc chưa có ảnh ghép reference/current mang trạng thái UNVERIFIED và nhận 0 điểm cho trọng số tương ứng. Luôn công bố điểm lower-bound bằng số: `100 × tổng trọng số PASS / tổng trọng số áp dụng`; FAIL và UNVERIFIED đều nhận 0, N/A được loại có bằng chứng. Hàng `OUT_OF_SCOPE` đã được M-01 xác minh nhận thêm **100/100 scope-compliance** riêng, không cộng vào điểm fidelity và không được mô tả như capability hoạt động. Công bố thêm số cell đã kiểm tra/tổng cell và phần trăm coverage. Điểm này chưa đủ coverage thì không được diễn giải là đã đạt cổng 95. Không chấm hành vi tính năng bằng điểm visual fidelity.

---

## 5. Milestone triển khai

Mỗi M là một tranche nhỏ, có file sở hữu, test và screenshot riêng. Không gộp nhiều M vào một patch lớn. Sau khi một M qua gate, commit riêng và push tranche UI đã duyệt lên origin/TuanKiet2 như yêu cầu trước; chỉ stage file thuộc tranche. Không stage toàn bộ working tree.

### M-01 — Khóa source, branch, behavior và baseline

**Mục tiêu:** agent biết chính xác đang làm trong checkout nào và không làm mất local work.

**Làm:**

- Xác nhận root đúng tuyệt đối `D:\kiet\hk7\flutter\midterm\note_ai_app-note-ai-app`, branch `TuanKiet2`, HEAD, remote `origin` và `git status --short`; không thao tác trong `note_ai_app-note-ai-app-lite`.
- Ghi lại tất cả thay đổi sẵn có trước khi bắt đầu. Không reset, stash/pop, xóa, format hàng loạt hoặc stage file ngoài tranche.
- Xác định active route/composition từ main.dart; xác nhận file/widget nào thực sự đang render. Không chỉnh legacy duplicate chỉ vì tên file giống nhau.
- Với từng feature được dự kiến có UI, tìm model/state/callback hiện có và ghi SUPPORTED, PRESENTATION_ONLY hoặc OUT_OF_SCOPE.
- Ghi behavior snapshot cho note create/edit/autosave/save error/delete/dirty back/summary/search/theme và keys/semantics quan trọng.
- Chạy baseline test/analyze có thể chạy và chụp current-source Android portrait + Chrome. Tách lỗi sẵn có khỏi lỗi mới. Login/Register chỉ được smoke-test không sửa.
- Ghi branch sở hữu localStorage QA. Giữ nguyên mọi thay đổi infrastructure đã có trong working tree; không đưa chúng vào tranche UI. Browser test chỉ chứng minh lưu trong origin/profile hiện tại và không được trình bày là backend sync.

**Output:** bảng capability, bảng file active/locked, git baseline, test baseline, ảnh baseline và known blockers.

**Gate:** agent khác có thể chỉ ra chính xác root/branch, nơi render, callback được giữ và file bị cấm trước khi sửa. Baseline fail phải được phân loại trước khi qua M-02; source/backend/auth contract chưa xác minh thì M-01 chưa được đóng.

### M-02 — Lập reference/capability matrix theo ảnh thật

**Mục tiêu:** chốt ảnh anchor và loại bỏ Notion feature không thuộc app.

**Làm:**

- Mở ảnh Android/Web được chọn trực tiếp từ hinhanh; không lấy màn Chat/Calendar/Inbox/database/share làm feature yêu cầu.
- Chọn reference pair theo từng state có thật: Home empty/loaded/error, Notes list/grid nếu có, Search landing/results/no-results, editor empty/filled/dirty/saving/saved/error, Summary nếu có, More/delete confirmation và Settings/Appearance nếu có.
- Đo sidebar, top bar, page gutter, title baseline, row height, content width, dialog/menu bound và mobile bottom/safe-area offset.
- Ghi light/dark, EN/VI, viewport, orientation portrait và DPR của từng reference.
- Chụp thêm anchor từ live Notion chỉ khi ảnh trong folder chưa thể hiện state cần đối chiếu; không sửa nội dung của Notion.

**Output:** `docs/ui-qa/notion-reference-matrix.md` có tên ref/current chính xác, capability, viewport/theme/locale/data/state/scroll, anchors đo được, score số và lý do cho từng mục OUT_OF_SCOPE. Không ghi ref đã xem nếu chưa mở file ảnh.

**Gate:** mọi control định giữ hoặc thêm đều có callback/state liên kết; mọi Notion-only control bị loại trước implementation. Không có dữ liệu giả để làm ảnh trông đầy đủ.

### M-03 — Chuẩn hóa token và primitive UI dùng chung

**Files sở hữu:** `workspace_ui_tokens.dart` cho workspace shell, `notes_theme_tokens.dart` cho Notes/editor, `note_flow_primitives.dart` nếu cần shared primitive. `main.dart` chỉ được sửa phần theme/wiring scope riêng cho workspace/notes; không đổi màu/theme global đang áp vào Login/Register.

**Làm:**

- Chuẩn hóa palette light/dark, text roles, divider, selected/focus/error/success, spacing/radius/elevation/icon.
- Chỉ tạo primitive dùng lại khi ít nhất hai screen hiện có cùng pattern, ví dụ page header, sidebar row, section heading, popup surface hoặc status callout.
- Kiểm tra hover, focus, pressed, disabled, keyboard navigation và semantics của mỗi primitive.
- Chuyển component được sửa sang token; không mở một refactor toàn app không cần thiết. Kiểm tra riêng một màn Auth trước/sau để xác nhận token workspace không rò sang Login/Register.

**Tests/gate:** test token light/dark và widget states; không đổi public feature widget contracts; focused presentation tests pass; screenshot một Android portrait và Chrome desktop cho color/spacing anchor. Nếu token làm regress screen đã đạt, dừng và sửa trong chính M-03.

### M-04 — Android shell, avatar và navigation

**Files sở hữu:** workspace_shell.dart, UI localization/token phụ trợ khi cần.

**Làm:**

- Đối chiếu header/nav với Android refs `001`, `002`, `212`: giữ account avatar ở góc trái, vùng điều hướng hiện có, selected state và destination callbacks. Ref `001` có Chat/Calendar/Inbox/Favorites/Private; chỉ dùng bố cục, không dựng các destination/nhóm chưa có.
- Dùng drawer hoặc bottom sheet theo width hiện tại; menu phải giữ đúng destination Home/Notes và Settings/Diagnostics chỉ khi callback đang được nối.
- Làm rõ vùng thao tác, scroll ownership, safe area/status/navigation bars và system Back.
- Không tạo Workspace switcher, Chat, Calendar, Inbox, Favorites, Private, Invite hoặc profile identity giả.
- Giữ collapse/expand behavior/key; không làm mất state khi đổi destination.

**Tests/gate:** workspace shell tests, compact/responsive tests, semantics/keys; runtime captures 360×800 và 412×915 portrait; test mở/đóng sheet, đổi destination và Back. Sau gate, ghi điểm cell Android tương ứng vào scorecard.

### M-05 — Android Home, Notes list và Search

**Files sở hữu:** dashboard_page.dart, dashboard_content.dart, dashboard_note_card.dart, dashboard_state_views.dart, notes_list_panel.dart, notes_workspace_page.dart chỉ ở vùng composition/presentation.

**Làm:**

- Home dùng dữ liệu NoteFlow thật; đối chiếu Android `001`/`087`, tái tạo hierarchy, section spacing, page marker và preview của note hiện có. Ẩn hoặc bỏ các section Favorites/Private nếu không có state tương ứng.
- Nếu current source có grid/list toggle hoặc sort, style lại đúng control/state; nếu không có callback thì không thêm.
- Giữ search flow hiện có; dùng Android `215` cho landing/recent, `018` cho results, `162` cho no-results và `217`/`218` chỉ làm visual reference cho sheet/options nếu đúng callback đã tồn tại. Sort Home không được xem là bằng chứng Search có filter/sort.
- Có visual riêng cho loading, empty, filtered-empty, error, retry và loaded list/grid; loading không tạo note giả.
- Giữ selected row, title/preview, count/date nếu hiện có. Không gọi note list là Favorites/Private/Recently visited nếu data không chứng minh điều đó.
- Không thay đổi controller, query, ordering, model hoặc create/open callback.

**Tests/gate:** dashboard + Notes workspace/responsive suites; Android runtime tạo note bằng affordance hiện có, tìm note, mở note, Back và kiểm tra list state. So ảnh Home/Search cùng viewport với ref portrait. Mỗi unsupported filter/search option được đánh dấu OUT_OF_SCOPE.

### M-06 — Android editor, autosave feedback và overlays

**Files sở hữu:** note_detail_page.dart, note_detail_surface.dart, note_detail_editor_form.dart, note_detail_action_bar.dart, note_detail_more_actions.dart, note_detail_summary.dart, model_provisioning_status_panel.dart.

**Làm:**

- Biến detail thành page surface: back/breadcrumb/action area hiện có, title phân cấp rõ, content borderless, readable line height và gutter nhất quán. Android `014`/`015` chỉ là anchor page hierarchy; Web `007`/`010` chỉ là anchor desktop page/title/body, không mặc định là editor form cùng state.
- Giữ title/content fields, text controller, focus lifecycle, scroll key, dirty guard và autosave callback.
- Trình bày draft/dirty/saving/saved/save-error/Web storage unavailable theo state thật. Không thêm manual Save.
- Summary, busy/stale/error và model provisioning là callout/status theo data thật; không giả AI answer hoặc progress.
- More/delete menu chỉ chứa action có callback; Delete luôn dùng confirmation hiện có.
- Compact menus thành bottom sheet khi pattern hiện hữu yêu cầu; tôn trọng keyboard, safe area, barrier, focus và system Back.
- Trên phone portrait, keyboard không che title/content/action; khi quay lại list dirty note không được mất.

**Tests/gate:** note detail/page/surface/action-bar tests; Android 360×800 và 412×915 portrait cho empty, filled, dirty, saving/saved/error, summary nếu hỗ trợ, More, delete/back confirmation. Ghi rõ note QA được tạo và dọn; không đổi data source.

**Anchor kiểm:** action row top inset, title left/top baseline, title/body gap, body line-height và bottom Search inset. Không chấm share/action trong ảnh ref nếu NoteFlow không có callback. Ảnh editor hiện có `M-06_editor-existing-note_411x914_light_20260927-current-v5.png` là debug-emulator evidence; loại debug ribbon khỏi fidelity score, không xem nó là thiết kế của app.

### M-07 — Web Chrome shell, Home, Notes và Search

**Files sở hữu:** cùng các UI workspace/dashboard/notes files trong M-04/M-05; chỉ thay presentation và responsive layout.

**Làm:**

- Desktop: sidebar, workspace header, search affordance, selected row, page canvas và gutter theo Web `033`/`007`; 280 px là điểm đo lịch sử cần xác minh lại từ reference/current viewport trước khi chốt.
- Compact: navigation chuyển thành affordance/sheet phù hợp; không để sidebar hoặc toolbar đè content.
- Home/Notes/Search dùng chung visual grammar với Android nhưng điều khiển phù hợp pointer, hover, focus, Tab/Enter/Escape.
- Resize khi đang ở Home, list hoặc editor phải giữ selected note và state; overlay không tràn viewport.
- Dữ liệu/state vẫn lấy từ callback và store đang chạy; không fake recents, filters hay results.

**Tests/gate:** responsive/workspace/dashboard tests; Chrome captures 390×844, 768×1024, 1280×800 và 1440×900; verify không horizontal overflow, controls usable, drawer/sidebar open/closed, search open/result/empty. Login/Register chỉ smoke regression.

### M-08 — Web editor và browser-local QA save

**Files UI sở hữu:** editor/detail/surface files như M-06. Local QA adapter không thuộc tranche UI.

**Làm:**

- Áp dụng page header, title, content, summary/status, More và confirmation theo cùng reference matrix; desktop dùng Web `007`/`010` cho page hierarchy, compact chỉ chấm formal khi M-02 có viewport/state ref ghép phù hợp.
- Đo trước title/body container trong Notion và NoteFlow. Capture 1280×800 hiện có title bắt đầu gần x=420 px trong NoteFlow so với x≈465 px trong ref `007`; xử lý gutter/column alignment trong M-08 nếu sai lệch còn tồn tại ở cặp cùng viewport, không hard-code offset khi chưa đo lại.
- Trên TuanKiet2 không che giấu storage-unavailable/error bằng status Saved.
- Để chạy workflow create/edit/autosave/reload/reopen, dùng nhánh Test_Tuankiet và adapter localStorage đã được user yêu cầu. Chỉ lưu trong browser origin/profile hiện tại; không gọi backend và không đồng bộ.
- Tạo note QA rõ ràng, sửa title/content, chờ autosave thật, quay lại, mở lại, reload Chrome rồi xác nhận dữ liệu còn; kiểm tra dirty/back, delete và empty/error state.
- Trước khi kết thúc QA, xác định chính xác files adapter/factory/test liên quan để loại khỏi staging/cherry-pick/push sang TuanKiet2. Không xóa local data của người dùng.

**Tests/gate:** Chrome runtime chứng minh cùng-origin reload/reopen; UI báo đúng lifecycle; local adapter tests nếu runner cho phép; lưu cả kết quả pass và blocker. Chỉ presentation files được push trong M-08 UI tranche; không push adapter, local note fixtures/data hoặc test-only persistence.

**Anchor kiểm:** sidebar width/edge, top action row, page title x/y/size, content left edge/line width, body line-height, bottom Search placement ở compact và keyboard/focus ở desktop. Web compact hiện có screenshot `M-08_editor-existing-note_390x844_light_20260927-current-v1.png`; desktop có `M-08_editor-existing-note_1280x800_light_20260927-current-v1.png`. Hai capture là runtime QA; formal score vẫn 0 cho tới khi M-02 ghép cùng viewport/state reference.

### M-09 — Settings, diagnostics, localization và accessibility đang có

**Phạm vi:** chỉ các screen/control hiện hữu và được M-01 xác nhận.

**Làm:**

- Nếu appearance/theme, language, diagnostics hoặc model provisioning đang có route/callback, đưa style về cùng token và kiểm tra light/dark.
- Rà EN/VI và text dài trên Home/list/editor/menu; không đổi meaning của localization key.
- Rà semantics label/value/hint/live region, keyboard focus order, focus visibility, touch target và contrast AA.
- Không thêm Settings section, diagnostics action, keyboard shortcut hoặc provider auth không có behavior hiện tại.
- Trong M-09 không sửa source trong `lib/presentation/auth/**` hoặc test trong `test/presentation/auth/**`. Nếu token/global theme làm Login/Register đổi thì thu hẹp token/theme về workspace hoặc hoãn M-09; ngoại lệ layout M-13 chỉ áp dụng cho tranche M-13.

**Tests/gate:** localized/widget tests và keyboard/semantics checks cho các screen trong scope; Login/Register screenshot/route smoke chỉ xác nhận không regress, không cộng vào điểm fidelity tranche.

### M-10 — Android native QA và chấm fidelity

**Thiết bị:** Android emulator API 35; portrait only.

**Workflow tối thiểu:**

1. Mở app session hợp lệ; xác nhận Home/Notes shell.
2. Home empty/loading/error/loaded state tùy baseline data; mở note thật.
3. Tạo note bằng action hiện có; nhập title và content; chờ autosave/state thật.
4. Back về list; mở lại note; xác nhận dữ liệu/state còn theo capability của native store.
5. Search note và mở result; kiểm tra clear/no-results nếu hỗ trợ.
6. Chạy Summary nếu capability và môi trường model đang sẵn; nếu không, ghi UNVERIFIED hoặc OUT_OF_SCOPE đúng nguyên nhân.
7. Mở More/Delete, kiểm tra confirmation/cancel/confirm theo behavior hiện có.
8. Mở navigation/settings/diagnostics hiện có; kiểm tra Back, keyboard, system bars, text scale và EN/VI.

**Captures:** 360×800 và 412×915; 768×1024 portrait nếu thiết bị thật khả dụng. Tên ảnh: M-10_android_<screen>_<state>_<width>x<height>_<theme>.png. Mỗi ảnh phải là current-source native capture, portrait, không lấy Web viewport làm chứng cứ Android.

**Gate:** từng state có ref/current pair và item measurements; mọi cell áp dụng được chấm; điểm thấp nhất trên Android ít nhất 95/100. Cell thiếu current-source emulator capture nhận 0 điểm và phải được nêu trong coverage; không suy ra pass từ Web capture.

**Numeric rule:** ghi cả điểm ước lượng (nếu có) và điểm lower-bound. Chưa có cặp matched evidence thì ghi `0/100 lower-bound — UNVERIFIED`, không ghi `N/C`. Control được M-01 chứng minh không thuộc hợp đồng nhận `100/100 scope-compliance`, không cộng vào điểm giao diện.

### M-11 — Web Chrome QA và chấm fidelity

**Workflow:** tái chạy Home → Notes → create/edit → autosave → back/reopen → reload → search → summarize nếu hỗ trợ → delete confirmation. Chạy đúng nhánh cho localStorage QA; không dùng dữ liệu giả trong TuanKiet2.

**Captures:** 390×844, 768×1024, 1024×768, 1280×800 và 1440×900. Đổi viewport phải reload cùng origin/data/state; ghi browser profile, theme, locale, DPR và scroll offset. Tên ảnh: M-11_web-chrome_<screen>_<state>_<width>x<height>_<theme>.png.

**Gate:** không overflow hoặc keyboard/overlay che control; mọi state hiện đúng dữ liệu thật; score từng cell và Web Chrome platform score ít nhất 95/100. Nếu chỉ có browser-local QA trên Test_Tuankiet mà baseline TuanKiet2 chưa lưu được thì ghi riêng hai capability; không gộp hoặc trình bày local-only như backend sync.

**Numeric rule:** mỗi Web state × viewport áp dụng có điểm số. Cell chưa có ref/current cặp khớp ghi `0/100 lower-bound — UNVERIFIED`; không ghi `N/C`. Không dùng Web Android emulator, Edge hay ảnh tĩnh để cấp điểm native Android.

### M-12 — Regression cuối, commit/push và handoff

**Lệnh gate tham khảo:**

- dart format --output=none --set-exit-if-changed <danh-sách file Dart đã sửa>.
- flutter analyze lib/main.dart lib/presentation.
- flutter test <các test presentation liên quan>; chạy flutter test toàn repo nếu dependency/native hook cho phép và ghi riêng blocker nếu không.
- flutter build web --release --no-pub.
- flutter build apk --debug để cài lên emulator; flutter build apk --release chỉ trên môi trường JDK 17 trở lên. Không hạ Gradle hay sửa backend để né lỗi JDK.

**Gate trước commit của mỗi M:**

- Format chỉ các file Dart đã sửa; analyze lib/main.dart và lib/presentation; chạy test suites liên quan và regression workspace/notes/dashboard/routing/auth không bị tác động.
- Build Web release; cài/run Android emulator và tạo capture native cho tranche chạm Android.
- Đọc git diff và git diff --name-only; allowlist chỉ gồm presentation/theme, UI tests, kế hoạch/scorecard và reference matrix.
- Dừng nếu diff chạm domain, application, infrastructure, API, auth controller, routing hoặc backend. Kiểm tra riêng danh sách staged files trước mỗi commit.
- Không commit APK, output, browser profile, screenshot dữ liệu riêng tư, localStorage fixture, generated file, .dart_tool, cache hoặc thay đổi ngoài tranche.
- Sau gate: commit một M riêng, push UI-only commit lên origin/TuanKiet2; cập nhật scorecard sau mỗi tranche. Nếu remote/branch không khớp hoặc push chứa file local QA thì dừng và ghi blocker, không force-push.

**Kết quả bàn giao:** commit hash và remote branch; file list; commands/output test/build; Android/Chrome captures; scorecard có điểm lower-bound bằng số, coverage, N/A/UNVERIFIED và giới hạn còn lại.

---

## 6. Critical fail và dừng an toàn

Bất kỳ mục nào dưới đây làm tranche fail bất kể điểm:

- Thay đổi backend/domain/application/infrastructure hoặc data flow để đạt visual similarity.
- Sửa Login/Register ngoài bố cục được cho phép trong M-13; sửa auth validation, callback, controller, flow, copy, localization hoặc navigation ở bất kỳ tranche nào.
- Thêm nút Save hoặc làm UI báo Saved khi storage chưa lưu thành công.
- Mất note, dirty state, focus, route, selected item hoặc callback sau Back/resize/keyboard.
- Đổi avatar Android thành logo; tạo Workspace switcher/Favorites/Share/filter/action giả.
- Bỏ delete confirmation, làm CTA bị che, có overflow hoặc mất semantics/key quan trọng.
- Đưa localStorage adapter, local note data hoặc test-only persistence vào push TuanKiet2.
- Báo score >=95 khi cell còn UNVERIFIED, thiếu reference/current pair hoặc chấm một phần state.

**Dừng và khôi phục:** giữ log/screenshot/test/diff; dừng tại M đang lỗi; revert riêng commit M đó nếu đã commit, không revert tranche được duyệt trước. Không reset hard, không xóa thay đổi sẵn có, không stash/pop cũ. Nếu lỗi save xuất hiện, đưa UI về trạng thái phản ánh thật và khoanh vùng; không sửa backend trong SOP này.

---

## 7. Definition of Done

- [ ] Mỗi M trong phạm vi đã qua gate hoặc được ghi DONE — OUT_OF_SCOPE kèm bằng chứng capability/contract.
- [ ] Android portrait và Web Chrome đều có đủ cell đang áp dụng; điểm thấp nhất của từng platform đạt ít nhất 95/100.
- [ ] Mọi kết quả đều có điểm số bằng số; UNVERIFIED mang 0 điểm và không bị trình bày nhầm là pass; không có critical fail.
- [ ] M-13 chỉ thay bố cục Login/Register; auth behavior, fields, validators, routes và backend giữ nguyên, regression được ghi rõ.
- [ ] Tạo/sửa/autosave/search/delete/summary và responsive navigation giữ đúng capability hiện có; không có backend thay đổi.
- [ ] Web local save QA, nếu chạy, được chứng minh trong origin/profile browser-local và không xuất hiện trong push TuanKiet2.
- [ ] Scorecard, reference matrix, screenshots, test/build evidence, branch/commit hash và known limitations được lưu rõ.
- [ ] Final staged diff chỉ gồm file UI/test/docs đã duyệt; từng M có thể rollback độc lập.

## 8. Trạng thái thực thi hiện tại — 2026-09-27

| M | Trạng thái | Bằng chứng của lượt này | Việc còn lại trước khi đóng M |
| --- | --- | --- | --- |
| M-01 Source/scope/behavior lock | IN_PROGRESS | Checkout đúng `D:\kiet\hk7\flutter\midterm\note_ai_app-note-ai-app`, branch `TuanKiet2`; browser-local adapter, auth và editor diffs được nhận diện để không stage. Codebase-memory MCP (`list_projects`, `index_repository`) trả `Transport closed`; source fallback xác nhận một số UI contracts nhưng chưa hoàn tất feature audit. | Hoàn tất source → callback/state cho toàn bộ yêu cầu; xác minh từng capability trước khi gắn `DONE — OUT_OF_SCOPE` và scope score 100/100. Mục chưa xác minh nhận 0/100 lower-bound. Tuyệt đối không dùng `note_ai_app-note-ai-app-lite`. |
| M-02 Reference matrix | IN_PROGRESS | `docs/ui-qa/notion-reference-matrix.md` đang có 10 capture rows sau khi thêm Android editor portrait và Web editor compact/desktop. Đã mở trực tiếp 4 Android anchors (`001`, `014`, `018`, `217`) và 3 Web anchors (`007`, `008`, `010`); Web `001–003` vẫn là page view, không Home. | Kiểm tra inventory còn lại theo từng ảnh/platform; tìm ref Home Web đúng state hoặc giữ cell 0/100; hoàn tất danh sách screen/state/viewport áp dụng. |
| M-03 Shared UI tokens | IN_PROGRESS | Token workspace/dashboard nằm riêng trong `workspace_ui_tokens.dart`; Login/Register vẫn dùng palette ứng dụng hiện hữu. Workspace suite 22/22. Không stage thay đổi `notes_theme_tokens.dart` hoặc màu toàn app. | Kiểm tra đầy đủ light/dark, contrast, focus, semantics và 320–360dp; giữ Login/Register nguyên vẹn trong UI commit. |
| M-04 Android shell/navigation | IN_PROGRESS | Emulator Android 15/API 35, portrait 1080×2400 (411×914 logical), rotation 0. Capture mới Home/Search; workspace shell tests 22/22. Avatar góc trái vẫn là chữ K/profile, không bị thay bằng logo. | Hoàn tất các menu/Back/selected states, 360×800, theme tối, text scale, accessibility và ref measurements; điểm mọi cell áp dụng tối thiểu 95 trước khi đóng. |
| M-05 Android Home/Notes/Search | IN_PROGRESS | Dashboard suite 44/44; analyzer sạch. Home 411×914: 96/100 provisional estimate; Search 411×914: 97/100 provisional estimate. Hai formal cell đều 0/100 lower-bound cho tới khi ghép đủ cùng data/state và matrix. | Hoàn tất Notes/list/grid, empty/no-match/clear, sort, dark mode, 360×800 và đo anchor/pixel theo ref. Không gọi estimate là gate-pass. |
| M-06 Android editor | IN_PROGRESS | UI diff compact editor đang ở working tree; capture `output/playwright/20260927-android-native/M-06_editor-existing-note_411x914_light_20260927-current-v5.png` là Android API 35 portrait. Title/action hierarchy được so trực tiếp với ref `014`; score **94/100 provisional estimate; formal 0/100 lower-bound** vì ref là page có child rows, không phải same-state editable note, và chưa có dark/small-phone/matched autosave states. Focused editor/workspace tests được chạy trong lượt hiện tại theo scorecard. | Chốt cặp editor reference đúng state; capture 360×800 và dark/light; kiểm title/content/summary/status/More/delete/dirty-back/autosave, bỏ debug ribbon khỏi capture chấm điểm; đo anchors và đạt >=95 cho từng cell. |
| M-07 Web Chrome shell/Home/Search | IN_PROGRESS | Web release build pass 77.1s; Chrome hiển thị Flutter UI ở 390×844, 1280×800 và ref-sized 1363×936. Search overlay 1363×936: 96/100 provisional estimate, formal cell 0/100 lower-bound. Home cell 0/100 do nhóm ref 001–003 không cùng state. | Tìm Web Home ref đúng state; hoàn tất 768×1024, 1024×768, 1440×900, dark, focus, menu, empty/error và không tràn. |
| M-08 Web editor/browser-local QA | IN_PROGRESS | Editor desktop mở rộng theo viewport trên Web: tại 1920×906, cột editor tối đa 1200px và vùng content 1188px; Android và native vẫn dùng cột 720/708px. Hình học bố cục dự đoán title x≈500px với sidebar 280px, gần x≈526px trong ảnh người dùng. **95/100 provisional geometry estimate; formal 0/100 lower-bound**; capture sau sửa đang chờ đăng nhập lại vì browser reload chuyển về Login (phiên cũ chỉ còn trong bộ nhớ). `flutter build web --release` pass; `dart analyze` ba file UI pass; `flutter test test/presentation/notes/note_detail_surface_test.dart` bị dừng trước test do native `local_llm_bridge` `LNK1136`. UI-only commit `1056ef2` đã push `origin/TuanKiet2`. Không sửa auth, route hay backend. | Đăng nhập lại trong Chrome preview; chụp/đo editor ở 1920×906 và viewport 1280×800, kiểm tra mobile compact, light/dark, focus và autosave; xác nhận network không phát sinh request backend từ thay đổi này; giữ adapter/fixture khỏi TuanKiet2. |
| M-09 Settings/localization/accessibility | IN_PROGRESS | Settings/Diagnostics destinations hiện có; không sửa auth/settings/diagnostics trong lượt này. EN screenshot, workspace tests EN/VI pass. | Kiểm theme, language, text scale, contrast, semantics, keyboard/focus và từng destination hiện hữu; các cell chưa kiểm nhận 0/100. |
| M-10 Android native QA | IN_PROGRESS | Screenshot current-source Home/Search v6 ở 1080×2400 portrait; sampled estimate 96/100 và 97/100. Android platform lower-bound **0/100** vì coverage còn thiếu; không có landscape capture. | Chạy các state/viewport/theme trong plan; ghép ảnh đúng state; đạt từng cell >=95 và đủ coverage. |
| M-11 Web Chrome QA | IN_PROGRESS | Build release thành công; 0 console errors/0 warnings; network sample chỉ static app/assets, fonts, CanvasKit, không thấy API/backend request. Web Search estimate 96/100; Home/formal platform lower-bound **0/100**. | Chụp 768×1024, 1024×768, 1440×900 và mọi states/themes; xác minh local QA data trống và không stage persistence changes; đạt từng cell >=95. |
| M-12 Regression/commit/push | IN_PROGRESS | Dashboard 44/44, workspace 22/22, targeted analyzer sạch, format check, `git diff --check`, Web release build đều pass theo evidence của các tranche trước. UI-only commit `ac5e27b` và scorecard/docs commit `3fe9e9c` đã push lên `origin/TuanKiet2`; staged diff của hai commit không có backend/auth/local-save. | Hoàn tất các platform gate và M còn mở; giữ local-save/browser QA changes ngoài commit; ghi hash cho mỗi đợt tiếp theo. |
| M-13 Login/Register layout follow-up | IN_PROGRESS | Lát UI Login/Register đã push trong commit `9e00265` lên `origin/TuanKiet2`. Đã bỏ panel desktop của Login; Register desktop panel/footer được căn giữa. Auth fields, callback, controller, validation, route và backend không thuộc diff M-13. Computer Use đã xem Login/Register compact trên Web preview 397×675; desktop Login có release capture 1920×906. `flutter analyze` và Web release build pass; auth widget suite pass **23/23** qua test-only package-root shim, package config khôi phục đúng SHA-256. Điểm Android, Web Login và Web Register vẫn **0/100 lower-bound — UNVERIFIED** vì chưa đủ cặp ref/current theo platform, viewport và state. | Tiếp tục chụp current-source Register desktop ở 1280×800 và auth portrait trên Android emulator, rồi đo với ref matched state/viewport trước khi thay đổi điểm lower-bound. Không stage thay đổi auth/test có sẵn từ trước. |

**Giới hạn triển khai:** browser-local storage adapter và test/factory wiring đang có sẵn trong working tree để QA, nhưng nằm ngoài file allowlist của UI và không được đưa vào commit/push `TuanKiet2`. Không sửa `lib/domain`, `lib/application`, `lib/infrastructure`, backend/API, auth controller, route hoặc auth behavior. Login/Register chỉ được đổi bố cục theo M-13. Điểm platform hiện tại vẫn là 0/100 lower-bound; các estimate riêng của màn không chứng minh mức đạt 95/100.
