# Case Hạnh đã chốt — recalibration offline

Ngày 12/10/2026. Chỉ sửa gold và replay recordings, không gọi thêm API.

## Nhãn đúng
Câu hỏi: Chị Hạnh đã hoàn thành khóa đào tạo an toàn chưa?
Nguồn: Chị Hạnh chưa bao giờ tham gia khóa đào tạo và không có tên trong danh sách hoàn thành.
Kết luận: đủ dữ kiện để trả lời **chưa**. `answerable=true`, `conflict=false`.
ID sửa từ `fx-dev-vi-ins-03` thành `fx-dev-vi-ans-05`; giữ nguyên câu hỏi và evidence.
User chốt riêng case này; không coi toàn bộ dataset là human-reviewed.

## Kết quả
| Phần | Kết quả |
| --- | --- |
| Ngưỡng candidate chọn từ development | support >=0.85; conflict <=0.10 |
| Development sau sửa gold | 8/9 answerable =88,9%; 0/23 unsafe allow |
| Replay bộ đã xem | 7/8 answerable =87,5%; 0/24 unsafe allow |
| VI / EN trong regression | 3/4 / 4/4 |
| Approval/live generation | vẫn chặn; chưa có fresh confirmation |

Bộ development có9 answerable/23 unsafe, không ép gold vềquota8/24.
64 payload gửi JEV được dựng lại và so hash trước/sau: đều giống nhau.
Chỉ đổi gold/ID; probabilities, usage, model1.13.0 và wording rag-evidence.v2 giữ nguyên.
Recordings gốc giữ nguyên; ID remap và input proofs nằm trong ignoredoutput.

49 focused tests/0fail/0skip và typecheck PASS. Có tests cho câu trả lời phủ định,
payload thay đổi không đượcreuse, và regression dù đạtmetrics vẫn không đượcpromote.
Live runner từ chối datasetregression-only trước khi gọi AWS/model.

## Reproduce
```bash
node --import tsx tool/rag/recalibrate_hanh.ts
```
Runner dùng các bảnbackup/recordings cục bộ đã pin trong
`output/rag/phase4/recalibration-hanh`. Nếu thiếu recordings, nó dừng;
không tạo số liệu giả hoặc tự gọi model thay thế.

Source đã sửa nhưng không deploy AWS, publish approval hoặc đổi live threshold.
128/144 JEV là sốcounter đã xác nhận ở bước trước; không querycloud lại ở lượt này.
Không commit/push hoặc chạy toàn bộFlutter suite.

## Bước tiếp theo
Khóa32 confirmation case mới trước khi gọi API. Các bộv1/v2 đã xem chỉ làregression.
Chỉcòn16calls theo capđãduyệt, nên cầnchốtbudget trước32callsmới. Ngưỡng0.85/.10
làcandidate, chưa được coi làproductioncalibration hoặcPASSPhase4.
