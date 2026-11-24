# Sharing & Real-time Collaboration: test cases

Nguồn: [Notion 06](https://app.notion.com/p/3dc25edc9a25815fae95c4f9ed5e476c), đọc ngày 2026-11-10. Phạm vi: backend và frontend Sharing/Realtime. Các case dưới đây là tiêu chí kiểm thử; **chưa đánh dấu pass cho luồng live** nếu chưa chạy trên môi trường đó.

## Dữ liệu chuẩn bị

Dùng dữ liệu giả: owner O, editor E, viewer V, tài khoản không được share X và note N của O. Các tài khoản phải khác nhau; đồng hồ hai client và môi trường backend được ghi lại. Với live, dùng môi trường test được phép, không ghi token, password hoặc nội dung riêng tư vào bằng chứng.

## Test cases

| ID | Yêu cầu | Thao tác | Kết quả mong đợi |
| --- | --- | --- | --- |
| S01 | FR-01, 02, 10 | O mời E bằng email với quyền edit và V với quyền read-only; mở quản lý share. | Hai recipient đúng tài khoản và quyền; danh sách quản lý hiển thị rõ từng người. |
| S02 | FR-01, 09 | O mời email không đăng ký, email của O, rồi mời trùng E. | Từng lời mời bị từ chối; không tạo recipient hoặc thay đổi quyền hiện tại. |
| S03 | FR-03, NFR-03 | O đổi E từ edit sang read-only khi E đang mở N. | Quyền mới hiện trên client E; E không thể submit thay đổi sau khi quyền có hiệu lực. |
| S04 | FR-03, 08, NFR-03 | O revoke V khi V đang mở N; V thử mở lại và gửi thay đổi. | Truy cập và ghi bị từ chối; nội dung không còn hiển thị sau khi client nhận thay đổi quyền. |
| S05 | FR-04, 08, NFR-01 | V và X gửi trực tiếp request sửa N, kể cả request cũ sau downgrade/revoke. | Server từ chối; nội dung và revision của N không đổi. |
| S06 | FR-03, NFR-01 | E, V và X thử trực tiếp tạo share, đổi quyền và revoke thay O. | Server từ chối; danh sách và quyền không đổi. |
| S07 | FR-05, 06 | Đăng nhập V, mở Shared With Me và tìm N. | N xuất hiện trong khu vực riêng, hiển thị quyền, người share và thời điểm share. |
| S08 | FR-06, 10, NFR-05 | Ghi nhận thời điểm share, đổi quyền rồi mở lại thông tin share. | `sharedAt` phản ánh thời điểm tạo share, vẫn đúng sau đổi quyền; timestamp cập nhật chỉ kiểm tra nếu được hỗ trợ. |
| S09 | FR-07 | O và E mở N trên hai client. O lưu thay đổi; quan sát E, rồi E lưu thay đổi và quan sát O. | Mỗi client thấy thay đổi đã lưu của client kia mà không refresh hoặc mở lại. |
| S10 | NFR-02 | Ngắt kết nối client E, O lưu thay đổi, sau đó kết nối lại E mà không reload. | E tự reconnect, bắt kịp thay đổi đã lưu, không cần thao tác refresh. |
| S11 | NFR-02, 03 | Trong lúc E mất kết nối, O revoke E; kết nối lại rồi E thử gửi thay đổi chờ. | Client nhận trạng thái revoke; server từ chối thay đổi cũ; bản nháp cục bộ không bị âm thầm mất. |
| S12 | NFR-04 | O và E cùng sửa N từ cùng một revision, sau đó lần lượt lưu. | Có xử lý xung đột rõ ràng; không âm thầm ghi đè làm mất bản sửa chưa được giải quyết. |
| S13 | NFR-01 | X thử đọc N trực tiếp; V thử các endpoint đọc và ghi liên quan. | X bị từ chối; V chỉ được đọc theo quyền, các thao tác ghi bị từ chối ở server. |
| S14 | NFR-02 | Trong môi trường test, làm rớt notification hoặc publish sau khi commit; khôi phục kết nối/relay. | Client bắt kịp revision đã commit; retry/notification lặp không tạo thay đổi nội dung trùng. |
| S15 | FR-04, NFR-01 | Client E thử subscribe kênh realtime của O hoặc X, và thử publish trực tiếp. | Subscribe sai danh tính và publish từ client bị từ chối; kênh của E vẫn hoạt động. |

## Bằng chứng lần chạy này

- `amplify/sharing/notion_collaboration_contract.test.ts`: 4/4 pass với `TestDynamo` và fake resolver; kiểm tra owner-only, `sharedAt`, invite tự thân/trùng/không tồn tại.
- `amplify/sharing/sharing.test.ts` và `amplify/realtime/{realtime,relay_recovery,relay_budget}.test.ts`: 53/53 pass; đây là test fixture/CDK, không phải deployed AWS.
- `test/presentation/ui43/sharing_notion_contract_test.dart`: 1/1 pass với `sharerLabel` giả được cung cấp; chưa chứng minh backend trả tên người share.
- `test/sharing/realtime_{protocol,cursor}_test.dart`, `test/application/sync/shared_coordinator_test.dart` và `sync_conflict_resolver_test.dart`: 29/29 pass với fixture.
- S07 có khoảng trống: đường tạo share hiện không gán `sharerLabel`; UI dùng `ownerId` khi thiếu trường này. Cần kiểm tra trên dữ liệu thật liệu ID đó đủ để người nhận nhận ra người share hay cần một nhãn dễ đọc. Test UI phía trên cố ý cấp nhãn giả nên không kiểm chứng đường dữ liệu này.
- S09–S15 là kịch bản acceptance cần kết quả môi trường phù hợp; test socket hoặc database giả không thay thế xác minh hai client và AWS thật. Xem [LIVE_GATE.md](../../docs/m06/LIVE_GATE.md).
