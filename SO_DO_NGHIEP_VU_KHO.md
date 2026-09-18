# TÀI LIỆU QUY TRÌNH NGHIỆP VỤ KHO VẬN THÔNG MINH RFID (WMS BUSINESS PROCESS)
> **Dành cho:** Ban Giám Đốc, Trưởng Kho, Kế Toán Kho, Thủ Kho, Giảng Viên Hướng Dẫn & Ban Đánh Giá  
> **Hệ thống:** RFID Warehouse Management System (RFID WMS)  
> **Trang web xem & tải ảnh báo cáo (Chuẩn Word/PDF):** [Bao_Cao_Nghiep_Vu_Kho_RFID.html](Bao_Cao_Nghiep_Vu_Kho_RFID.html) (Khuyên dùng để lấy ảnh 300 DPI)  
> **Báo cáo kỹ thuật chi tiết (.md):** [BAO_CAO_NGHIEP_VU_KHO_RFID.md](BAO_CAO_NGHIEP_VU_KHO_RFID.md)  
> **Tệp đính kèm sơ đồ gốc:** [SO_DO_NGHIEP_VU_KHO.png](SO_DO_NGHIEP_VU_KHO.png) | [RFID_Warehouse_Workflow_Diagram.drawio](RFID_Warehouse_Workflow_Diagram.drawio)  

---

## 1. MA TRẬN PHÂN ĐỊNH TRÁCH NHIỆM (RACI MATRIX)

| Mã Phân Hệ | Bước Nghiệp Vụ Thực Tế | Đối Tác Ngoài | Phòng Mua Hàng / Kinh Doanh | Trưởng Kho / Kế Toán Kho | Thủ Kho & Xe Nâng | Hệ Thống RFID WMS |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: |
| **GIAI ĐOẠN 1** | **Mua Hàng & Tiếp Nhận Tại Bến** |
| 1.1 | Lập Đơn Mua Hàng (PO) gửi Nhà cung cấp & nạp WMS | - | **Chịu trách nhiệm (R)** | Phê duyệt (A) | - | Tự động nạp (I) |
| 1.2 | NCC giao hàng đến cửa kho kèm Packing List & Hóa đơn | **Thực hiện (R)** | Theo dõi (I) | Kiểm tra chứng từ (A) | Nhận bàn giao (C) | - |
| 1.3 | Bốc dỡ hàng, kiểm tra ngoại quan (móp méo, ướt rách) | - | - | Giám sát (A) | **Thực hiện (R)** | - |
| 1.4 | Dán tem / Kích hoạt chip RFID thông minh & Đóng Pallet | - | - | - | **Thực hiện (R)** | Gán mã chip (C) |
| **GIAI ĐOẠN 2** | **Nghiệm Thu Qua Cổng RFID Gate Tự Động** |
| 2.1 | Vận chuyển Pallet qua Cổng RFID Gate Hopeland | Lái xe (C) | - | - | **Lái xe nâng (R)** | Đọc chùm sóng (A) |
| 2.2 | Đối soát thời gian thực & Phản hồi đèn tháp tín hiệu | - | - | - | Quan sát đèn (I) | **Đối soát 100% (R)** |
| 2.3 | Xử lý ngoại lệ: Thẻ lạ / Thiếu hàng (Còi hú + Đèn đỏ) | - | - | Xử lý hợp đồng (C) | **Kiểm đếm lại (R)** | Khóa cổng (A) |
| 2.4 | Ký duyệt nghiệm thu nhập kho & Chuyển Chờ Cất Kệ | Ký nhận (C) | - | **Ký duyệt (A)** | Bàn giao (R) | Chuyển WAITING (R) |
| **GIAI ĐOẠN 3** | **Cất Kệ & Quản Lý Vị Trí Lưu Trữ (Putaway)** |
| 3.1 | Tiếp nhận thông báo nhiệm vụ `[CẦN CẤT KỆ]` trên PDA | - | - | - | **Mở PDA nhận (R)** | Tự động đẩy (A) |
| 3.2 | Quét Barcode Pallet & Xem gợi ý vị trí ô kệ trống (2D) | - | - | - | **Thao tác PDA (R)** | Gợi ý tối ưu (A) |
| 3.3 | Đưa hàng đến ô kệ, quét Barcode tem kệ & Xác nhận cất | - | - | - | **Thực hiện (R)** | Khóa vị trí (A) |
| 3.4 | Cập nhật sổ kho điện tử: Hàng chuyển thành `IN_STOCK` | - | - | Theo dõi sổ (I) | - | **Ghi CSDL & Log (R)** |
| **GIAI ĐOẠN 4** | **Quản Trị Kho Nội Bộ & Kiểm Kê Tài Sản** |
| 4.1 | Điều chuyển kệ (Transfer) & Dồn Pallet (Merge) | - | - | Phê duyệt (A) | **Thực hiện PDA (R)** | Cập nhật vị trí (R) |
| 4.2 | Bóp cò PDA quét RFID kiểm kê định kỳ 4 nhóm sai lệch | - | - | Giám sát (A) | **Cầm súng quét (R)** | Báo cáo chênh lệch (R)|
| 4.3 | Xử lý thừa/thiếu, cân chỉnh tồn kho (`ADJUST`) | - | - | **Phê duyệt (A)** | Ký biên bản (C) | Cân bằng sổ kho (R) |
| **GIAI ĐOẠN 5** | **Xuất Kho Chuẩn FIFO, Giải Phóng Kệ & Giao Hàng** |
| 5.1 | Tiếp nhận Đơn đặt hàng từ Khách hàng & Duyệt xuất | Khách gửi SO (R)| **Tạo đơn PO (R)** | Phê duyệt (A) | - | Khởi tạo đơn (I) |
| 5.2 | Áp dụng nguyên tắc FIFO: Bắt buộc xuất lô nhập cũ nhất | - | - | Kiểm soát hạn (A) | - | **Thuật toán FIFO (R)** |
| 5.3 | Soạn hàng theo Wizard chỉ đường qua 10 vị trí kệ | - | - | - | **Nhặt hàng (R)** | Dẫn đường tối ưu (A) |
| 5.4 | Xe hàng qua Cổng RFID Gate Xuất: Đối soát 2 pha | - | - | Giám sát (A) | **Lái xe nâng (R)** | Kiểm đếm 2 pha (R) |
| 5.5 | Giải phóng vị trí kệ lưu trữ: Trả kệ về CÒN CHỖ / TRỐNG | - | - | - | - | **locationId = null (R)**|
| 5.6 | In phiếu xuất kho (Delivery Note) & Bàn giao cho khách | **Nhận hàng (R)** | Theo dõi giao (I)| **Ký phiếu xuất (A)**| Bàn giao hàng (R) | Lưu vết hoàn tất (R)|

*(Chú thích RACI: R = Responsible - Người trực tiếp làm; A = Accountable - Người duyệt & chịu trách nhiệm; C = Consulted - Người phối hợp/tham khảo; I = Informed - Người nhận thông báo)*

---

## 2. NGUYÊN TẮC VẬN HÀNH BẤT DI BẤT DỊCH (OPERATIONAL RULES)

1. **Nguyên Tắc Không Chạm Khi Qua Cổng (Touchless RFID Gate Verification):**
   - Không kiểm đếm thủ công từng cái khi xe hàng đi qua cổng. Toàn bộ quá trình đối soát dựa trên chùm sóng RFID tần số UHF (Hopeland CL7206C2) quét đồng thời hàng trăm thẻ trong vài giây.
   - Xe hàng chỉ được phép rời bến nhập khi tháp đèn báo **ĐÈN XANH** (`GPO 2 ON`). Bất kỳ tín hiệu **ĐÈN ĐỎ + CÒI BÁO** nào đều buộc lái xe dừng lại để thủ kho kiểm tra kiện lạ.

2. **Nguyên Tắc Cất Kệ 2 Hộp (Two-Step PDA Putaway):**
   - Hàng hóa sau khi qua cổng phải được quét cất kệ ngay, không được để tồn đọng tại khu vực đệm (Receiving Staging Area).
   - Thủ kho bắt buộc phải quét đúng mã Barcode dán trên kệ vật lý để hệ thống khóa tọa độ lưu trữ. Tuyệt đối không tự ý để hàng sai vị trí mà không quét xác nhận.

3. **Nguyên Tắc Xuất Hàng FIFO Nghiêm Ngặt (First-In, First-Out):**
   - Thuật toán WMS tự động chọn các lô hàng có ngày nhập `created_at` xa nhất để xuất trước.
   - Nếu nhân viên nhặt nhầm lô hàng mới hơn, hệ thống sẽ **báo động đỏ và từ chối thông qua tại cổng xuất**, yêu cầu trả hàng về đúng vị trí và nhặt lại đúng lô cũ.

4. **Nguyên Tắc Giải Phóng Vị Trí Kệ Tức Thì (Instant Location Release):**
   - Ngay khi kiện hàng được xác nhận qua cổng xuất, hệ thống lập tức xóa liên kết vị trí (`item.locationId = null`), đưa sức chứa của ô kệ trở lại trạng thái `CÒN CHỖ / TRỐNG` để sẵn sàng đón đợt hàng nhập tiếp theo.
