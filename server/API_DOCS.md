# 📡 TÀI LIỆU REST API HỆ THỐNG QUẢN LÝ KHO RFID (WMS)

Hệ thống REST API trung gian giao tiếp đa nền tảng giữa **Cơ sở dữ liệu MySQL**, **Ứng dụng Trạm Cổng Desktop (Windows)**, và **Ứng dụng Tay cầm PDA (Android C72e)**.

---

## 🏗️ KIẾN TRÚC KẾT NỐI (ARCHITECTURE)

```mermaid
graph TD
    subgraph "DATABASE"
        DB[(MySQL rfidwarehouse\n127.0.0.1:3306)]
    end

    subgraph "BACKEND REST API SERVER"
        API[Node.js Express REST API\nPort: 3000]
    end

    subgraph "DESKTOP CLIENTS (TRẠM CỔNG)"
        DesktopGate[Trạm Cổng Đọc RFID / Băng Chuyền]
        DesktopStudio[Trạm In Mã Vạch & Ghi Chip RFID]
    end

    subgraph "MOBILE CLIENTS (TAY CẦM PDA)"
        PDAPutaway[PDA: Xếp Hàng Lên Kệ (Putaway)]
        PDAInventory[PDA: Kiểm Kê Kho RFID]
        PDADelivery[PDA: Xuất Kho & Lấy Hàng]
    end

    DB <-->|Connection Pool| API
    API <-->|HTTP REST / JSON| DesktopGate
    API <-->|HTTP REST / JSON| DesktopStudio
    API <-->|Wi-Fi / LAN REST| PDAPutaway
    API <-->|Wi-Fi / LAN REST| PDAInventory
    API <-->|Wi-Fi / LAN REST| PDADelivery
```

---

## 🚀 HƯỚNG DẪN KHỞI CHẠY API SERVER

1. Di chuyển vào thư mục `server`:
   ```bash
   cd server
   ```
2. Cài đặt thư viện:
   ```bash
   npm install
   ```
3. Chạy API Server:
   ```bash
   npm start
   # Hoặc chế độ dev tự reload:
   npm run dev
   ```
4. Cổng mặc định: `http://localhost:3000` (hoặc `http://<IP-May-Tinh>:3000`).

---

## 📋 DANH SÁCH CÁC ENDPOINTS (API SPECIFICATION)

### 1. Kiểm tra trạng thái máy chủ (Health Check)
* **URL:** `GET /api/health`
* **Mô tả:** Kiểm tra kết nối API Server và Cơ sở dữ liệu MySQL `rfidwarehouse`.
* **Phản hồi mẫu (200 OK):**
```json
{
  "status": "ONLINE",
  "database": "CONNECTED",
  "serverTime": "2026-08-21T07:15:00.000Z",
  "localIps": ["192.168.1.100"],
  "port": 3000,
  "message": "Hệ thống RFID WMS REST API hoạt động bình thường"
}
```

---

### 2. Danh mục Vị trí Kệ kho (Locations)
* **URL:** `GET /api/locations`
* **Mô tả:** Lấy danh sách toàn bộ vị trí kệ kho (Zone, Shelf, Level, Số pallet hiện có).
* **Phản hồi mẫu (200 OK):**
```json
{
  "success": true,
  "count": 4,
  "data": [
    {
      "location_id": "LOC-A1-01-01",
      "location_code": "LOC-A1-01-01",
      "zone": "A",
      "shelf": "01",
      "level": "01",
      "max_pallets": 2,
      "current_pallets": 0,
      "status": "AVAILABLE"
    }
  ]
}
```

* **Thêm vị trí mới:** `POST /api/locations`
* **Request Body:**
```json
{
  "location_code": "LOC-B2-01-01",
  "zone": "B",
  "shelf": "01",
  "level": "01"
}
```

---

### 3. Giai đoạn 1: Trạm Cổng RFID Tiếp nhận Kiện Hàng (Gate Receive)
* **URL:** `POST /api/gate/receive`
* **Mô tả:** Khi thùng hàng đi qua Cổng RFID Desktop, cổng đọc được tất cả chip RFID trong thùng. Gọi API này để chuyển trạng thái kiện hàng và toàn bộ chip bên trong sang **`CHỜ XẾP KHO (WAITING_PUTAWAY)`** tại vị trí cổng `LOC-GATE-IN`.
* **Request Body:**
```json
{
  "order_no": "CARTONTEST0001",
  "scanned_epcs": [
    "E28011223344556677889901",
    "E28011223344556677889902"
  ],
  "performed_by": "Cổng RFID Desktop Gate 01"
}
```
* **Phản hồi mẫu (200 OK):**
```json
{
  "success": true,
  "message": "Đã tiếp nhận kiện hàng CARTONTEST0001 (2 chip) -> Trạng thái: CHỜ XẾP KHO",
  "order_no": "CARTONTEST0001",
  "status": "WAITING_PUTAWAY",
  "location_id": "LOC-GATE-IN",
  "received_count": 2
}
```

---

### 4. Giai đoạn 2: Tay Cầm PDA Cất Hàng Lên Kệ (PDA Putaway Confirmation)
* **URL:** `POST /api/pda/putaway`
* **Mô tả:** Nhân viên kho cầm PDA đến kệ, chọn/quét vị trí kệ đích và bóp cò quét mã vạch dán trên thùng hàng. Gọi API này để gán vị trí kệ, chuyển toàn bộ sản phẩm sang **`TRONG KHO (IN_STOCK)`**, hoàn tất đơn hàng và ghi log giao dịch.
* **Request Body:**
```json
{
  "carton_barcode": "CARTONTEST0001",
  "location_id": "LOC-A1-01-01",
  "performed_by": "Thủ kho PDA"
}
```
* **Phản hồi mẫu (200 OK):**
```json
{
  "success": true,
  "message": "Đã cất thùng hàng CARTONTEST0001 vào vị trí LOC-A1-01-01 (10 sản phẩm đang TRONG KHO)",
  "carton_barcode": "CARTONTEST0001",
  "location_id": "LOC-A1-01-01",
  "location_code": "LOC-A1-01-01",
  "status": "IN_STOCK",
  "updated_items_count": 10
}
```

---

### 5. Danh sách Đơn Nhập Kho (Inbound Orders)
* **URL:** `GET /api/inbound-orders` (Hoặc lọc `GET /api/inbound-orders?status=WAITING_PUTAWAY`)
* **Mô tả:** Lấy danh sách các đơn nhập kho kèm chi tiết số lượng yêu cầu và số lượng đã nhận.

* **URL Chi tiết:** `GET /api/inbound-orders/:orderNo`
* **Mô tả:** Lấy thông tin chi tiết một đơn nhập kho cùng danh sách các chip RFID thuộc kiện hàng đó.

---

### 6. Tra cứu Thẻ Chip RFID & Mặt Hàng (Items)
* **URL:** `GET /api/items/epc/:epc`
* **Mô tả:** Tra cứu nhanh vị trí kệ hiện tại, mã sản phẩm, Serial Number và trạng thái lưu kho của thẻ chip RFID.
* **Phản hồi mẫu (200 OK):**
```json
{
  "success": true,
  "data": {
    "item_id": "ITEM-001",
    "epc": "E28011223344556677889901",
    "sku": "8930000000001",
    "product_name": "Product Test 01",
    "serial_number": "SN-001",
    "status": "IN_STOCK",
    "location_code": "LOC-A1-01-01",
    "zone": "A",
    "shelf": "01",
    "level": "01"
  }
}
```

---

### 7. Nhật ký Biến động Kho (Inventory Transactions)
* **URL:** `GET /api/transactions`
* **Mô tả:** Lấy lịch sử biến động kho (Audit log: Nhập cổng, Cất hàng Putaway, Chuyển kệ, Xuất hàng).
