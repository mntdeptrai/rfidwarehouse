-- ====================================================================
-- DATABASE SCHEMA: rfidwarehouse
-- Hệ thống Quản lý Kho Thông minh Ứng dụng Công nghệ RFID (WMS & UHF)
-- Host: 127.0.0.1:3306 | Engine: InnoDB | Charset: utf8mb4_unicode_ci
-- ====================================================================

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;
SET NAMES utf8mb4;
SET CHARACTER SET utf8mb4;

CREATE DATABASE IF NOT EXISTS `rfidwarehouse` 
CHARACTER SET utf8mb4 
COLLATE utf8mb4_unicode_ci;

USE `rfidwarehouse`;

SET NAMES utf8mb4;
SET CHARACTER_SET_CLIENT = utf8mb4;
SET CHARACTER_SET_RESULTS = utf8mb4;
SET CHARACTER_SET_CONNECTION = utf8mb4;

-- Tắt kiểm tra khóa ngoại tạm thời khi khởi tạo
SET FOREIGN_KEY_CHECKS = 0;

-- --------------------------------------------------------------------
-- 1. BẢNG NGƯỜI DÙNG & PHÂN QUYỀN (users)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `users`;
CREATE TABLE `users` (
    `user_id` VARCHAR(50) NOT NULL COMMENT 'Mã định danh người dùng',
    `username` VARCHAR(50) NOT NULL UNIQUE COMMENT 'Tên đăng nhập',
    `password_hash` VARCHAR(255) NOT NULL DEFAULT '123456' COMMENT 'Mật khẩu mã hóa',
    `full_name` VARCHAR(100) NOT NULL COMMENT 'Họ và tên',
    `email` VARCHAR(100) NULL COMMENT 'Email liên hệ',
    `role` ENUM('ADMIN', 'MANAGER', 'WAREHOUSE_STAFF', 'OPERATOR') NOT NULL DEFAULT 'WAREHOUSE_STAFF' COMMENT 'Vai trò hệ thống',
    `is_active` TINYINT(1) NOT NULL DEFAULT 1 COMMENT 'Trạng thái hoạt động (1: Hoạt động, 0: Khóa)',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Danh sách tài khoản nhân sự kho';

-- --------------------------------------------------------------------
-- 2. BẢNG DANH MỤC SẢN PHẨM / SKU (products)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `products`;
CREATE TABLE `products` (
    `product_id` VARCHAR(50) NOT NULL COMMENT 'Mã sản phẩm (ID)',
    `sku` VARCHAR(50) NOT NULL UNIQUE COMMENT 'Mã SKU sản phẩm',
    `product_name` VARCHAR(255) NOT NULL COMMENT 'Tên sản phẩm',
    `unit` VARCHAR(20) NOT NULL DEFAULT 'Cái' COMMENT 'Đơn vị tính (Cái, Thùng, Hộp, Kg)',
    `category` VARCHAR(100) NOT NULL COMMENT 'Nhóm danh mục',
    `description` TEXT NULL COMMENT 'Mô tả chi tiết',
    `min_stock` INT NOT NULL DEFAULT 10 COMMENT 'Mức tồn kho an toàn tối thiểu',
    `max_stock` INT NOT NULL DEFAULT 1000 COMMENT 'Mức tồn kho tối đa',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`product_id`),
    INDEX `idx_products_sku` (`sku`),
    INDEX `idx_products_category` (`category`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Danh mục sản phẩm & hàng hóa';

-- --------------------------------------------------------------------
-- 3. BẢNG VỊ TRÍ LƯU KHO (locations)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `locations`;
CREATE TABLE `locations` (
    `location_id` VARCHAR(50) NOT NULL COMMENT 'Mã định danh vị trí',
    `location_code` VARCHAR(50) NOT NULL UNIQUE COMMENT 'Mã vạch vị trí (VD: LOC-A1-01-01)',
    `zone` VARCHAR(20) NOT NULL COMMENT 'Khu vực (A, B, C, Gate, Buffer)',
    `shelf` VARCHAR(20) NOT NULL COMMENT 'Kệ / Dãy (01, 02...)',
    `level` VARCHAR(20) NOT NULL COMMENT 'Tầng / Ngăn (01, 02...)',
    `max_pallets` INT NOT NULL DEFAULT 2 COMMENT 'Sức chứa pallet tối đa',
    `current_pallets` INT NOT NULL DEFAULT 0 COMMENT 'Số lượng pallet hiện tại',
    `status` ENUM('AVAILABLE', 'OCCUPIED', 'FULL', 'MAINTENANCE') NOT NULL DEFAULT 'AVAILABLE' COMMENT 'Trạng thái vị trí',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`location_id`),
    INDEX `idx_locations_code` (`location_code`),
    INDEX `idx_locations_zone` (`zone`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Sơ đồ vị trí kệ kho (Zone - Shelf - Level)';

-- --------------------------------------------------------------------
-- 4. BẢNG PALLET LƯU KHO (pallets)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `pallets`;
CREATE TABLE `pallets` (
    `pallet_id` VARCHAR(50) NOT NULL COMMENT 'Mã định danh pallet',
    `pallet_code` VARCHAR(50) NOT NULL UNIQUE COMMENT 'Mã pallet (VD: PAL-001)',
    `location_id` VARCHAR(50) NULL COMMENT 'Vị trí kệ đang đặt pallet',
    `inbound_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Thời điểm tạo/nhập pallet',
    `is_multi_sku` TINYINT(1) NOT NULL DEFAULT 0 COMMENT 'Pallet chứa nhiều SKU hay 1 SKU',
    `status` ENUM('IN_STOCK', 'ALLOCATED', 'MOVING', 'SHIPPED', 'EMPTY') NOT NULL DEFAULT 'IN_STOCK',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`pallet_id`),
    INDEX `idx_pallets_code` (`pallet_code`),
    INDEX `idx_pallets_location` (`location_id`),
    CONSTRAINT `fk_pallets_location` FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Quản lý Pallet lưu trữ hàng hóa';

-- --------------------------------------------------------------------
-- 5. BẢNG SẢN PHẨM VẬT LÝ GẮN CHIP RFID (items)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `items`;
CREATE TABLE `items` (
    `item_id` VARCHAR(50) NOT NULL COMMENT 'Mã định danh cá thể sản phẩm',
    `product_id` VARCHAR(50) NOT NULL COMMENT 'Liên kết danh mục sản phẩm',
    `sku` VARCHAR(50) NOT NULL COMMENT 'Mã SKU',
    `product_name` VARCHAR(255) NOT NULL COMMENT 'Tên sản phẩm',
    `serial_number` VARCHAR(100) NOT NULL UNIQUE COMMENT 'Số Serial Number duy nhất của máy/sản phẩm',
    `epc` VARCHAR(64) NOT NULL UNIQUE COMMENT 'Mã chip RFID EPC (96-bit/128-bit Hex)',
    `tid` VARCHAR(64) NULL COMMENT 'Mã định danh phần cứng chip TID (Read Only)',
    `user_data` TEXT NULL COMMENT 'Dữ liệu bộ nhớ User Memory của chip',
    `status` ENUM('PENDING_INBOUND', 'IN_STOCK', 'ALLOCATED', 'PICKED', 'WAITING_SHIPMENT', 'OUT') NOT NULL DEFAULT 'IN_STOCK' COMMENT 'Trạng thái vòng đời sản phẩm',
    `order_no` VARCHAR(100) NULL COMMENT 'Mã đơn hàng / Số phiếu nhập liên kết',
    `pallet_id` VARCHAR(50) NULL COMMENT 'Pallet đang chứa',
    `location_id` VARCHAR(50) NULL COMMENT 'Vị trí kho hiện tại',
    `inbound_time` DATETIME NULL COMMENT 'Thời gian nhập kho thực tế',
    `allocated_time` DATETIME NULL COMMENT 'Thời gian giữ hàng cho đơn xuất',
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`item_id`),
    INDEX `idx_items_epc` (`epc`),
    INDEX `idx_items_order_no` (`order_no`),
    INDEX `idx_items_serial` (`serial_number`),
    INDEX `idx_items_sku` (`sku`),
    INDEX `idx_items_status` (`status`),
    INDEX `idx_items_pallet` (`pallet_id`),
    INDEX `idx_items_location` (`location_id`),
    CONSTRAINT `fk_items_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT `fk_items_pallet` FOREIGN KEY (`pallet_id`) REFERENCES `pallets` (`pallet_id`) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT `fk_items_location` FOREIGN KEY (`location_id`) REFERENCES `locations` (`location_id`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Chi tiết từng mặt hàng vật lý gắn chip RFID UHF';

-- --------------------------------------------------------------------
-- 6. BẢNG ĐƠN NHẬP KHO (inbound_orders)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `inbound_orders`;
CREATE TABLE `inbound_orders` (
    `inbound_order_id` VARCHAR(50) NOT NULL COMMENT 'Mã đơn nhập',
    `order_no` VARCHAR(50) NOT NULL UNIQUE COMMENT 'Số chứng từ nhập (VD: INB-2026-001)',
    `source_supplier` VARCHAR(255) NOT NULL COMMENT 'Nhà cung cấp / Nguồn nhập',
    `status` ENUM('NEW', 'PROCESSING', 'COMPLETED', 'CANCELLED') NOT NULL DEFAULT 'NEW' COMMENT 'Trạng thái đơn nhập',
    `total_required` INT NOT NULL DEFAULT 0 COMMENT 'Tổng số lượng yêu cầu nhập',
    `total_received` INT NOT NULL DEFAULT 0 COMMENT 'Tổng số lượng thực tế đã quét RFID nhập kho',
    `note` TEXT NULL COMMENT 'Ghi chú đơn hàng',
    `created_by` VARCHAR(50) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`inbound_order_id`),
    INDEX `idx_inbound_order_no` (`order_no`),
    INDEX `idx_inbound_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Phiếu yêu cầu nhập kho (Inbound Orders)';

-- --------------------------------------------------------------------
-- 7. BẢNG CHI TIẾT ĐƠN NHẬP KHO (inbound_order_details)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `inbound_order_details`;
CREATE TABLE `inbound_order_details` (
    `id` INT AUTO_INCREMENT NOT NULL,
    `order_id` VARCHAR(50) NOT NULL COMMENT 'Mã đơn nhập kho',
    `product_id` VARCHAR(50) NOT NULL COMMENT 'Mã sản phẩm',
    `sku` VARCHAR(50) NOT NULL COMMENT 'Mã SKU',
    `product_name` VARCHAR(255) NOT NULL COMMENT 'Tên sản phẩm',
    `required_qty` INT NOT NULL DEFAULT 0 COMMENT 'Số lượng cần nhập',
    `received_qty` INT NOT NULL DEFAULT 0 COMMENT 'Số lượng đã nhận (quét RFID thành công)',
    PRIMARY KEY (`id`),
    INDEX `idx_inbound_details_order` (`order_id`),
    INDEX `idx_inbound_details_sku` (`sku`),
    CONSTRAINT `fk_inbound_details_order` FOREIGN KEY (`order_id`) REFERENCES `inbound_orders` (`inbound_order_id`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_inbound_details_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Chi tiết danh mục hàng hóa trong đơn nhập';

-- --------------------------------------------------------------------
-- 8. BẢNG ĐƠN XUẤT KHO / PO (outbound_orders)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `outbound_orders`;
CREATE TABLE `outbound_orders` (
    `outbound_order_id` VARCHAR(50) NOT NULL COMMENT 'Mã đơn xuất',
    `po_no` VARCHAR(50) NOT NULL UNIQUE COMMENT 'Số Purchase Order / Lệnh xuất (VD: PO-2026-001)',
    `customer` VARCHAR(255) NOT NULL COMMENT 'Tên khách hàng / Điểm nhận hàng',
    `shipping_address` VARCHAR(255) NULL COMMENT 'Địa chỉ giao hàng',
    `status` ENUM('NEW', 'PROCESSING', 'PREPARED', 'WAITING_SHIPMENT', 'SHIPPED', 'CANCELLED') NOT NULL DEFAULT 'NEW' COMMENT 'Trạng thái đơn xuất',
    `total_required` INT NOT NULL DEFAULT 0 COMMENT 'Tổng số lượng yêu cầu xuất',
    `total_picked` INT NOT NULL DEFAULT 0 COMMENT 'Tổng số lượng đã lấy hàng (Picked)',
    `note` TEXT NULL,
    `created_by` VARCHAR(50) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`outbound_order_id`),
    INDEX `idx_outbound_po_no` (`po_no`),
    INDEX `idx_outbound_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Đơn đặt hàng xuất kho (Outbound Orders / PO)';

-- --------------------------------------------------------------------
-- 9. BẢNG CHI TIẾT ĐƠN XUẤT KHO (outbound_order_details)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `outbound_order_details`;
CREATE TABLE `outbound_order_details` (
    `id` INT AUTO_INCREMENT NOT NULL,
    `order_id` VARCHAR(50) NOT NULL COMMENT 'Mã đơn xuất',
    `product_id` VARCHAR(50) NOT NULL COMMENT 'Mã sản phẩm',
    `sku` VARCHAR(50) NOT NULL COMMENT 'Mã SKU',
    `product_name` VARCHAR(255) NOT NULL COMMENT 'Tên sản phẩm',
    `required_qty` INT NOT NULL DEFAULT 0 COMMENT 'Số lượng cần xuất',
    `picked_qty` INT NOT NULL DEFAULT 0 COMMENT 'Số lượng đã nhặt/quét thực tế',
    PRIMARY KEY (`id`),
    INDEX `idx_outbound_details_order` (`order_id`),
    INDEX `idx_outbound_details_sku` (`sku`),
    CONSTRAINT `fk_outbound_details_order` FOREIGN KEY (`order_id`) REFERENCES `outbound_orders` (`outbound_order_id`) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT `fk_outbound_details_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Chi tiết danh mục hàng hóa trong đơn xuất';

-- --------------------------------------------------------------------
-- 10. BẢNG PHIÊN KIỂM KÊ KHO (inventory_sessions)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `inventory_sessions`;
CREATE TABLE `inventory_sessions` (
    `session_id` VARCHAR(50) NOT NULL COMMENT 'Mã phiên kiểm kê',
    `session_code` VARCHAR(50) NOT NULL UNIQUE COMMENT 'Mã chứng từ kiểm kê (VD: AUD-2026-001)',
    `location_id` VARCHAR(50) NULL COMMENT 'Vị trí kiểm kê (nếu kiểm theo vị trí)',
    `total_expected` INT NOT NULL DEFAULT 0 COMMENT 'Tổng số lượng lý thuyết tồn sổ sách',
    `total_scanned` INT NOT NULL DEFAULT 0 COMMENT 'Tổng số lượng thẻ RFID quét được thực tế',
    `total_match` INT NOT NULL DEFAULT 0 COMMENT 'Số lượng khớp hoàn toàn',
    `total_missing` INT NOT NULL DEFAULT 0 COMMENT 'Số lượng thiếu thực tế',
    `total_wrong_loc` INT NOT NULL DEFAULT 0 COMMENT 'Số lượng sai vị trí lưu kho',
    `total_unknown` INT NOT NULL DEFAULT 0 COMMENT 'Số lượng thẻ chưa khai báo trong hệ thống',
    `status` ENUM('OPEN', 'IN_PROGRESS', 'COMPLETED', 'CANCELLED') NOT NULL DEFAULT 'OPEN',
    `start_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `end_time` DATETIME NULL,
    `created_by` VARCHAR(50) NULL,
    PRIMARY KEY (`session_id`),
    INDEX `idx_audit_session_code` (`session_code`),
    INDEX `idx_audit_location` (`location_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Phiên kiểm kê hàng tồn kho bằng thiết bị RFID';

-- --------------------------------------------------------------------
-- 11. BẢNG CHI TIẾT KIỂM KÊ (inventory_session_details)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `inventory_session_details`;
CREATE TABLE `inventory_session_details` (
    `id` INT AUTO_INCREMENT NOT NULL,
    `session_id` VARCHAR(50) NOT NULL,
    `epc` VARCHAR(64) NOT NULL COMMENT 'Mã EPC thẻ quét được',
    `item_id` VARCHAR(50) NULL,
    `sku` VARCHAR(50) NULL,
    `product_name` VARCHAR(255) NULL,
    `expected_location_id` VARCHAR(50) NULL COMMENT 'Vị trí lý thuyết trên hệ thống',
    `actual_location_id` VARCHAR(50) NULL COMMENT 'Vị trí thực tế vừa quét thấy',
    `variance_type` ENUM('MATCH', 'MISSING', 'WRONG_LOCATION', 'UNKNOWN_EPC') NOT NULL DEFAULT 'MATCH',
    `rssi` VARCHAR(10) NULL COMMENT 'Cường độ sóng RSSI khi kiểm kê (dBm)',
    `antenna` VARCHAR(10) NULL COMMENT 'Anten đọc được',
    `scan_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`id`),
    INDEX `idx_audit_details_session` (`session_id`),
    INDEX `idx_audit_details_epc` (`epc`),
    CONSTRAINT `fk_audit_details_session` FOREIGN KEY (`session_id`) REFERENCES `inventory_sessions` (`session_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Kết quả quét chi tiết từng chip RFID trong phiên kiểm kê';

-- --------------------------------------------------------------------
-- 12. BẢNG LỊCH SỬ BIẾN ĐỘNG KHO (inventory_transactions)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `inventory_transactions`;
CREATE TABLE `inventory_transactions` (
    `transaction_id` VARCHAR(50) NOT NULL,
    `transaction_type` ENUM('IN', 'OUT', 'MOVE', 'ADJUST') NOT NULL COMMENT 'Loại giao dịch (Nhập, Xuất, Chuyển, Điều chỉnh)',
    `item_id` VARCHAR(50) NOT NULL,
    `epc` VARCHAR(64) NOT NULL,
    `from_location_id` VARCHAR(50) NULL,
    `to_location_id` VARCHAR(50) NULL,
    `from_pallet_id` VARCHAR(50) NULL,
    `to_pallet_id` VARCHAR(50) NULL,
    `order_ref` VARCHAR(50) NULL COMMENT 'Mã tham chiếu đơn nhập/xuất',
    `performed_by` VARCHAR(50) NULL COMMENT 'Người thực hiện giao dịch',
    `note` TEXT NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`transaction_id`),
    INDEX `idx_trans_type` (`transaction_type`),
    INDEX `idx_trans_epc` (`epc`),
    INDEX `idx_trans_item` (`item_id`),
    INDEX `idx_trans_created` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Lịch sử vết biến động hàng hóa (Audit Log)';

-- --------------------------------------------------------------------
-- 13. BẢNG THIẾT BỊ PHẦN CỨNG RFID (rfid_devices)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `rfid_devices`;
CREATE TABLE `rfid_devices` (
    `device_id` VARCHAR(50) NOT NULL COMMENT 'Mã thiết bị',
    `device_name` VARCHAR(100) NOT NULL COMMENT 'Tên thiết bị (VD: RFID Gate 01 - Cửa Kho Chính)',
    `device_type` ENUM('GATE_READER', 'FIXED_READER', 'HANDHELD_PDA', 'DESKTOP_ENCODER', 'PRINTER_ENCODER') NOT NULL DEFAULT 'FIXED_READER',
    `ip_address` VARCHAR(50) NULL COMMENT 'Địa chỉ IP thiết bị',
    `port` INT NOT NULL DEFAULT 9090 COMMENT 'Cổng kết nối TCP/IP',
    `mac_address` VARCHAR(50) NULL COMMENT 'Địa chỉ MAC phần cứng',
    `work_mode` VARCHAR(20) NOT NULL DEFAULT 'SERVER' COMMENT 'SERVER hoặc CLIENT',
    `power_dbm` INT NOT NULL DEFAULT 30 COMMENT 'Công suất phát sóng RF (1 - 33 dBm)',
    `antenna_count` INT NOT NULL DEFAULT 4 COMMENT 'Số lượng anten hỗ trợ',
    `status` ENUM('ONLINE', 'OFFLINE', 'BUSY', 'ERROR') NOT NULL DEFAULT 'OFFLINE',
    `last_ping` DATETIME NULL COMMENT 'Thời gian giao tiếp gần nhất',
    `description` VARCHAR(255) NULL,
    `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (`device_id`),
    INDEX `idx_devices_ip` (`ip_address`),
    INDEX `idx_devices_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Danh mục đầu đọc RFID trong toàn hệ thống';

-- --------------------------------------------------------------------
-- 14. BẢNG NHẬT KÝ BẮT SÓNG CHIP RFID (rfid_scan_logs)
-- --------------------------------------------------------------------
DROP TABLE IF EXISTS `rfid_scan_logs`;
CREATE TABLE `rfid_scan_logs` (
    `log_id` BIGINT AUTO_INCREMENT NOT NULL,
    `device_id` VARCHAR(50) NULL COMMENT 'Đầu đọc bắt sóng',
    `epc` VARCHAR(64) NOT NULL COMMENT 'Mã EPC bắt được',
    `tid` VARCHAR(64) NULL COMMENT 'Mã TID (nếu có)',
    `rssi` VARCHAR(10) NOT NULL COMMENT 'Cường độ tín hiệu dBm',
    `antenna` VARCHAR(10) NOT NULL DEFAULT '1' COMMENT 'Cổng anten bắt được',
    `frequency` VARCHAR(20) NULL COMMENT 'Tần số làm việc (MHz)',
    `phase` VARCHAR(20) NULL COMMENT 'Góc pha sóng RF',
    `scan_time` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (`log_id`),
    INDEX `idx_scan_logs_epc` (`epc`),
    INDEX `idx_scan_logs_device` (`device_id`),
    INDEX `idx_scan_logs_time` (`scan_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Nhật ký ghi nhận đọc thẻ RFID thời gian thực';

-- --------------------------------------------------------------------
-- 15. CÁC VIEW BÁO CÁO THỐNG KÊ (VIEWS)
-- --------------------------------------------------------------------

-- View 1: Thống kê tổng quan tồn kho theo SKU
CREATE OR REPLACE VIEW `v_inventory_summary` AS
SELECT 
    p.product_id,
    p.sku,
    p.product_name,
    p.unit,
    p.category,
    p.min_stock,
    p.max_stock,
    COUNT(CASE WHEN i.status = 'IN_STOCK' THEN 1 END) AS qty_in_stock,
    COUNT(CASE WHEN i.status = 'ALLOCATED' THEN 1 END) AS qty_allocated,
    COUNT(CASE WHEN i.status = 'PENDING_INBOUND' THEN 1 END) AS qty_pending,
    COUNT(i.item_id) AS total_tracked_items
FROM `products` p
LEFT JOIN `items` i ON p.product_id = i.product_id
GROUP BY p.product_id, p.sku, p.product_name, p.unit, p.category, p.min_stock, p.max_stock;

-- View 2: Chi tiết thông tin mặt hàng kèm vị trí & Pallet
CREATE OR REPLACE VIEW `v_item_full_details` AS
SELECT 
    i.item_id,
    i.epc,
    i.tid,
    i.serial_number,
    i.status AS item_status,
    p.sku,
    p.product_name,
    p.unit,
    p.category,
    pal.pallet_code,
    loc.location_code,
    loc.zone,
    loc.shelf,
    loc.level,
    i.inbound_time,
    i.allocated_time,
    i.updated_at
FROM `items` i
JOIN `products` p ON i.product_id = p.product_id
LEFT JOIN `pallets` pal ON i.pallet_id = pal.pallet_id
LEFT JOIN `locations` loc ON i.location_id = loc.location_id;

-- --------------------------------------------------------------------
-- 16. DỮ LIỆU KHỞI TẠO BAN ĐẦU (SEED DATA)
-- --------------------------------------------------------------------

-- Chèn tài khoản quản trị mặc định (Mật khẩu mặc định: 123456)
INSERT INTO `users` (`user_id`, `username`, `password_hash`, `full_name`, `email`, `role`, `is_active`) VALUES
('USR-001', 'admin', '123456', 'Quản Trị Viên Hệ Thống', 'admin@rfidwarehouse.vn', 'ADMIN', 1),
('USR-002', 'manager01', '123456', 'Trưởng Kho Tổng', 'manager@rfidwarehouse.vn', 'MANAGER', 1),
('USR-003', 'operator01', '123456', 'Nhân Viên Vận Hành Cổng Gate', 'operator01@rfidwarehouse.vn', 'OPERATOR', 1);

-- Chèn sơ đồ vị trí kệ kho
INSERT INTO `locations` (`location_id`, `location_code`, `zone`, `shelf`, `level`, `max_pallets`, `current_pallets`, `status`) VALUES
('LOC-A1-01-01', 'LOC-A1-01-01', 'A', '01', '01', 2, 0, 'AVAILABLE'),
('LOC-A1-01-02', 'LOC-A1-01-02', 'A', '01', '02', 2, 0, 'AVAILABLE'),
('LOC-A1-02-01', 'LOC-A1-02-01', 'A', '02', '01', 2, 0, 'AVAILABLE'),
('LOC-A1-02-02', 'LOC-A1-02-02', 'A', '02', '02', 2, 0, 'AVAILABLE'),
('LOC-B1-01-01', 'LOC-B1-01-01', 'B', '01', '01', 2, 0, 'AVAILABLE'),
('LOC-B1-01-02', 'LOC-B1-01-02', 'B', '01', '02', 2, 0, 'AVAILABLE'),
('LOC-GATE-IN', 'LOC-GATE-IN', 'GATE', '00', '00', 10, 0, 'AVAILABLE'),
('LOC-GATE-OUT', 'LOC-GATE-OUT', 'GATE', '00', '00', 10, 0, 'AVAILABLE');

-- Bật lại kiểm tra khóa ngoại
SET FOREIGN_KEY_CHECKS = 1;

-- ====================================================================
-- KẾT THÚC SCRIPT KHỞI TẠO DATABASE rfidwarehouse
-- ====================================================================
