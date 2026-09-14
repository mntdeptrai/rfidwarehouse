# Quy Tắc Phát Triển Ứng Dụng (AGENTS.md)

## 1. Tuyệt Đối Không Dùng Mock Data & Dữ Liệu Tạm (No Mock Data / No Static Seeding)

**Khi hệ thống đã kết nối với cơ sở dữ liệu thực tế (SQLite, Supabase, API...), tuyệt đối không sử dụng mock data, dữ liệu tạm thời hay logic tự động chèn dữ liệu mẫu vào file.**

- **Cấm tự ý seed/bù dữ liệu:** Không được tạo các danh sách/mảng tĩnh hardcode (ví dụ: kệ mẫu, sản phẩm mẫu, pallet mẫu, đơn hàng mẫu...) để tự động ghi/insert vào database hoặc RAM khi ứng dụng khởi động (`init`), tải lại (`loadFromSqlite`) hoặc bấm làm mới (`refresh`).
- **Dọn sạch code tĩnh dư thừa:** Khi chuyển sang hoặc đã có cơ sở dữ liệu, toàn bộ code tĩnh, dữ liệu mẫu, mock data hoặc biến giả lập trước đó phải được xóa sạch sẽ triệt để, không để lại code dư thừa hay các hàm fallback ngầm tự sinh dữ liệu.
- **Tôn trọng dữ liệu thực của người dùng:** Dữ liệu hoàn toàn do người dùng hoặc CSDL thực tế quản lý. Kể cả khi bảng dữ liệu hoàn toàn rỗng (0 bản ghi) hoặc người dùng chủ động xóa dữ liệu, ứng dụng phải giữ nguyên hiện trạng rỗng đó, tuyệt đối không được tự động bù thêm dữ liệu giả.

---

## 2. Think Before Coding & Simplicity First
- Không suy đoán, không bổ sung tính năng hay cấu trúc trừu tượng ngoài yêu cầu trực tiếp của người dùng.
- Giữ code tối giản, rõ ràng, dễ bảo trì.

## 3. Surgical Changes
- Chỉ chạm vào đúng những dòng code cần sửa. Không sửa lung tung các thành phần đang hoạt động ổn định.
- Khi loại bỏ logic cũ, dọn sạch triệt để các biến/hàm mồ côi liên quan trực tiếp đến thay đổi đó.

---

## 4. Duy Trì & Cập Nhật CODE_GRAPH.md
- [CODE_GRAPH.md](CODE_GRAPH.md) là bản đồ tổng thể kiến trúc, phân tầng và luồng dữ liệu của dự án.
- Khi thay đổi kiến trúc, thêm màn hình, sửa luồng nghiệp vụ hoặc refactor dịch vụ, Agent **bắt buộc** phải cập nhật lại `CODE_GRAPH.md`.

---

## 5. Đội Ngũ AI Chuyên Môn Hóa (Antigravity AI Team Squad)
Hệ thống được vận hành bởi một đội ngũ Agent chuyên biệt nằm trong `.agents/skills/`:

| Vai trò Agent | Skill Tương Ứng | Trách Nhiệm Chính |
| :--- | :--- | :--- |
| **Orchestrator / Team Lead** | `AGENTS.md` | Tiếp nhận yêu cầu, phân tích bài toán, phân rã công việc cho các specialist, kiểm duyệt chất lượng |
| **RFID Hardware Engineer** | `.agents/skills/rfid-hardware-engineer` | Hopeland CL7206C2 (TCP), SEUIC UTouch 2 (AAR / Kotlin reflection), Tower Light Modbus, RSSI |
| **Supabase DB Architect** | `.agents/skills/supabase-db-architect` | PostgreSQL 17, `supabase_schema.sql`, `create_foreign_keys.sql`, SQLite cache, No Mock Data |
| **Flutter UI/UX Specialist** | `.agents/skills/flutter-ui-taste` | Flutter Desktop & PDA, Agency-grade UI, Animation 160ms, Sơ đồ kho 2D Canvas, AAA contrast |
| **QA Test Engineer** | `.agents/skills/qa-test-engineer` | Chạy `flutter test`, kiểm tra hồi quy, duy trì 100% test pass (125/125) trước khi hoàn tất task |


