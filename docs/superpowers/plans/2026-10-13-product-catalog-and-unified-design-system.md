# Kế Hoạch Triển Khai: Danh Mục Sản Phẩm & Đồng Bộ Màu Sắc Toàn Diện

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Xây dựng màn hình "Danh Mục Sản Phẩm" độc lập trên Desktop (quản lý SKU, tồn kho thực tế, Thêm/Sửa/Xóa, tìm kiếm & xuất Excel) và đồng bộ hóa triệt để ngôn ngữ thiết kế, màu sắc thương hiệu (Enterprise Royal Blue / RFID Cyan) trên toàn bộ các màn hình Desktop.

**Architecture:** Màn hình `DesktopProductManagementView` kết nối trực tiếp vào `WarehouseRepository` (CSDL Supabase / SQLite, tuyệt đối không dùng mock data). Tất cả màn hình Desktop sử dụng chung mẫu thiết kế Header Bar chuẩn mực và hệ màu token đồng nhất từ `EyeCareThemeService` (`c.rfidCyan`, `c.bgCard`, `c.bgDeep`, `c.border`, `c.textPrimary`).

**Tech Stack:** Flutter Desktop (Windows), Dart, Provider / ChangeNotifier (`WarehouseRepository`), Supabase PostgreSQL 17, `flutter_test`.

**Spec:** Yêu cầu người dùng ngày 13/10/2026: "thêm cho tôi phần danh mục sản phầm nữa, đồng bộ màu sắc đẹp của các màn hình đi tôi thấy mỗi màn hình 1 dạng màu khác nhau rồi". Lựa chọn: Tạo màn hình riêng trên Sidebar và đồng bộ tone màu Xanh Doanh Nghiệp (Enterprise Royal Blue / RFID Cyan).

## Global Constraints

- **RULE 1: Tuyệt đối không dùng Mock Data hay Static Seeding:** Toàn bộ sản phẩm và số lượng tồn kho lấy trực tiếp từ `WarehouseRepository.products` và `WarehouseRepository.items`. Nếu bảng rỗng, giữ nguyên trạng thái rỗng.
- **RULE 2: Clean Architecture & Dedicated Components:** Tách biệt rõ ràng màn hình `DesktopProductManagementView`, không nhồi nhét logic vào các view khác.
- **RULE 3: Bảo Toàn Kiểm Thử:** Đảm bảo toàn bộ test suite hồi quy (382+ tests) vượt qua 100% sau mỗi task.
- **RULE 4: Cập Nhật CODE_GRAPH.md:** Bổ sung kiến trúc màn hình mới và chuẩn hóa hệ thống màu vào `CODE_GRAPH.md`.

## Review Focus

1. **Phân quyền và bảo vệ thao tác xóa:** Không cho phép xóa sản phẩm nếu đang có sản phẩm thực tế tồn kho (`items` liên kết > 0) để bảo vệ toàn vẹn dữ liệu.
2. **Độ co giãn Responsive:** Màn hình co hẹp (< 900px hoặc < 1050px khi sidebar thu nhỏ) không được phát sinh lỗi `RenderFlex overflow`.
3. **Chỉ số Menu Sidebar:** Việc chèn thêm màn hình Danh Mục Sản Phẩm vào menu index không được làm sai lệch quyền truy cập vai trò (Admin, Kỹ thuật viên, Thủ kho).
4. **Đồng bộ hóa tức thì:** Sau khi Thêm/Sửa/Xóa sản phẩm, danh sách và tồn kho cập nhật ngay lập tức nhờ `notifyListeners()` từ `WarehouseRepository`.
5. **Độ tương phản màu sắc (WCAG AAA):** Tất cả nhãn chữ, icon và nút bấm phải đạt độ tương phản chuẩn trên nền `c.bgCard` và `c.bgDeep`.

---

### Task 1: Xây Dựng Màn Hình "Danh Mục Sản Phẩm" (`DesktopProductManagementView`)

**Files:**
- Create: `lib/screens/desktop/desktop_product_management_view.dart`
- Test: `test/desktop_product_management_view_test.dart`

**Interfaces:**
- Consumes: `WarehouseRepository.products`, `WarehouseRepository.items`, `WarehouseRepository.addProduct`, `WarehouseRepository.updateProduct`, `WarehouseRepository.deleteProduct`, `EyeCareThemeService`.
- Produces: `DesktopProductManagementView(key: ValueKey('desktop_product_management'))`.

- [ ] **Step 1: Viết test cho màn hình Danh Mục Sản Phẩm**
  Tạo `test/desktop_product_management_view_test.dart` kiểm chứng:
  - Khởi tạo widget và hiển thị thanh Header Bar chuẩn với tiêu đề "DANH MỤC SẢN PHẨM & SKU".
  - Hiển thị 4 thẻ KPI thống kê (Tổng số SKU, Tổng tồn kho thực tế, SKU có tồn kho, Nhóm danh mục).
  - Tìm kiếm sản phẩm theo Mã SKU hoặc Tên sản phẩm.
  - Mở hộp thoại "Thêm Sản Phẩm Mới".

- [ ] **Step 2: Chạy test để xác nhận test ban đầu fail**
  Chạy: `flutter test test/desktop_product_management_view_test.dart`
  Kết quả dự kiến: FAIL (chưa có file `desktop_product_management_view.dart`).

- [ ] **Step 3: Triển khai `DesktopProductManagementView`**
  Tạo `lib/screens/desktop/desktop_product_management_view.dart`:
  - Header Bar chuẩn mực với icon `Icons.category_rounded` / `Icons.inventory_2_rounded` trong khung xanh `c.rfidCyan`, tiêu đề `DANH MỤC SẢN PHẨM & QUẢN LÝ SKU`.
  - Bộ nút hành động: Tìm kiếm, Lọc danh mục, Nút `LÀM MỚI`, Nút `XUẤT EXCEL / CSV`, Nút `+ THÊM SẢN PHẨM`.
  - 4 thẻ KPI thống kê tổng hợp trực tiếp từ `_repo.products` và `_repo.items`.
  - Bảng dữ liệu sản phẩm chuẩn: STT, Mã SKU, Tên sản phẩm, Danh mục / Loại hàng, Đơn vị tính, Tồn kho thực tế (kèm chip badge màu xanh/vàng), Mô tả, Thao tác (Sửa, Xóa).
  - Hộp thoại Thêm/Sửa sản phẩm với form validation đầy đủ (Mã SKU, Tên, ĐVT, Danh mục, Mô tả).
  - Hộp thoại Xác nhận xóa sản phẩm: Kiểm tra nếu còn hàng tồn kho thì cảnh báo an toàn.

- [ ] **Step 4: Chạy test để xác nhận test pass**
  Chạy: `flutter test test/desktop_product_management_view_test.dart`
  Kết quả dự kiến: PASS.

---

### Task 2: Tích Hợp "Danh Mục Sản Phẩm" Vào Menu Sidebar & Điều Hướng Desktop

**Files:**
- Modify: `lib/screens/desktop/desktop_main_layout.dart`
- Test: `test/widget_test.dart`

**Interfaces:**
- Consumes: `DesktopProductManagementView`.
- Produces: `DesktopMainLayout` hỗ trợ điều hướng danh mục sản phẩm ở vị trí menu trực quan (index 2).

- [ ] **Step 1: Cập nhật danh sách View & Sidebar trong `desktop_main_layout.dart`**
  - Chèn `DesktopProductManagementView` vào danh sách `_buildViews()` ở index 2.
  - Cập nhật menu sidebar với icon `Icons.category_rounded` và nhãn `Danh Mục Sản Phẩm`.
  - Cập nhật ánh xạ chỉ mục phân quyền:
    - 0: Nhập Kho
    - 1: Xuất Kho
    - 2: Danh Mục Sản Phẩm
    - 3: Tìm Kiếm Hàng Hóa
    - 4: Sơ Đồ Kệ Kho
    - 5: Quản Lý Pallet
    - 6: Kiểm Kê Kho
    - 7: Báo Cáo Tồn Kho
    - 8: Báo Cáo Nhập Kho
    - 9: Báo Cáo Xuất Kho
    - 10: Đối Soát Tồn Kho
    - 11: Lịch Sử Nhập Xuất
    - 12: Cài Đặt (Kỹ thuật)
    - 13: Quản Lý Tài Khoản (Admin)
  - Cập nhật kiểm tra quyền truy cập `effectiveIndex` khi người dùng không đủ quyền.

- [ ] **Step 2: Cập nhật các test case liên quan đến chỉ mục menu trong `test/widget_test.dart`**
  - Chạy `flutter test test/widget_test.dart` và cập nhật chỉ mục nếu có test click theo số thứ tự menu.

- [ ] **Step 3: Chạy test xác nhận tất cả pass**
  Chạy: `flutter test test/widget_test.dart`
  Kết quả dự kiến: PASS.

---

### Task 3: Đồng Bộ Hóa Hệ Thống Màu & Chuẩn Hóa Header Bar Trên Tất Cả Màn Hình

**Files:**
- Modify: `lib/screens/desktop/desktop_location_management_view.dart`
- Modify: `lib/screens/desktop/desktop_lookup_view.dart`
- Modify: `lib/screens/desktop/desktop_report_view.dart`
- Modify: `lib/screens/desktop/desktop_stock_reconciliation_view.dart`
- Modify: `lib/screens/desktop/desktop_inventory_view.dart`
- Modify: `lib/screens/desktop/desktop_warehouse_management_view.dart`

**Interfaces:**
- Consumes: `EyeCareColors` (`c.rfidCyan`, `c.bgCard`, `c.bgDeep`, `c.border`, `c.textPrimary`).
- Produces: Chuẩn hóa 100% giao diện với tone màu Xanh Doanh Nghiệp đồng nhất, triệt tiêu các màu sắc phân mảnh lẻ loi.

- [ ] **Step 1: Chuẩn hóa `desktop_location_management_view.dart`**
  - Thay thế phần tiêu đề trần trụi bằng Header Bar chuẩn: Khung `c.bgCard`, viền dưới `c.border`, icon `Icons.grid_view_rounded` trong box `c.rfidCyan.withValues(alpha: 0.15)`, tiêu đề `SƠ ĐỒ VỊ TRÍ KỆ KHO (RACK GRID)`.
  - Nút bấm `LÀM MỚI` và các bộ lọc đồng bộ màu xanh thương hiệu `c.rfidCyan`.

- [ ] **Step 2: Chuẩn hóa `desktop_lookup_view.dart`**
  - Bổ sung Header Bar chuẩn trên cùng: Icon `Icons.search_rounded` trong box `c.rfidCyan.withValues(alpha: 0.15)`, tiêu đề `TÌM KIẾM HÀNG HÓA & TRUY VẾT RFID`.
  - Đồng bộ khung tìm kiếm và thanh nút chế độ hiển thị với viền và điểm nhấn `c.rfidCyan`.

- [ ] **Step 3: Chuẩn hóa `desktop_report_view.dart`**
  - Loại bỏ các màu sắc rực rỡ phân mảnh theo từng tab báo cáo (`0xFF0284C7`, `0xFFEA580C`, `0xFF10B981`, `0xFF8B5CF6`).
  - Thống nhất toàn bộ thanh tiêu đề và các tab báo cáo theo chuẩn màu `c.rfidCyan` và `c.bgCard`.

- [ ] **Step 4: Kiểm tra và tinh chỉnh các màn hình còn lại**
  - Rà soát `desktop_inventory_view.dart`, `desktop_stock_reconciliation_view.dart`, `desktop_warehouse_management_view.dart`, `desktop_user_management_view.dart`.
  - Đảm bảo tất cả Header Bar có cùng padding, cùng chiều cao, cùng kiểu khung icon và kiểu chữ.

---

### Task 4: Kiểm Thử Toàn Diện & Cập Nhật Tài Liệu Kiến Trúc

**Files:**
- Modify: `CODE_GRAPH.md`
- Run: `flutter test`

- [ ] **Step 1: Chạy toàn bộ test suite hệ thống**
  Chạy: `flutter test`
  Kết quả dự kiến: Tất cả các test cases vượt qua 100% (All tests passed, không có lỗi lùi).

- [ ] **Step 2: Cập nhật `CODE_GRAPH.md`**
  - Bổ sung mục **40. Danh Mục Sản Phẩm & Đồng Bộ Ngôn Ngữ Thiết Kế Toàn Diện (Unified Product Catalog & Design System)**.
  - Cập nhật sơ đồ phân tầng Desktop Layout và điều hướng Sidebar Menu.
