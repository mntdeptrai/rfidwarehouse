-- ====================================================================
-- SCRIPT THIẾT LẬP TOÀN DIỆN KHÓA CHÍNH (PK) & KHÓA NGOẠI (FK) CHO CÁC BẢNG
-- HỆ THỐNG QUẢN LÝ KHO RFID (UHF RFID WMS - SUPABASE POSTGRESQL)
-- 
-- Tính năng an toàn 100%:
-- 1. Tự động kiểm tra và tạo Khóa Chính (Primary Keys) cho 16 bảng nếu còn thiếu.
-- 2. Tự động kiểm tra và tạo Ràng buộc Duy nhất (Unique Constraints) cho các cột nghiệp vụ.
-- 3. Tự động dọn dẹp và chuẩn hóa dữ liệu mồ côi (Orphan Cleanup) trước khi gán FK.
-- 4. Tự động kiểm tra và tạo 14 Khóa Ngoại (Foreign Keys) với quy tắc CASCADE phù hợp.
-- 5. Đánh B-Tree Index cho toàn bộ các cột Khóa Ngoại để tối ưu hiệu năng truy vấn.
-- ====================================================================

-- ====================================================================
-- BƯỚC 1: THIẾT LẬP KHÓA CHÍNH (PRIMARY KEYS - PK) CHO TOÀN BỘ 16 BẢNG
-- ====================================================================
DO $$
BEGIN
    -- 1.1. Bảng products (product_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.products'::regclass AND contype = 'p') THEN
        ALTER TABLE public.products ALTER COLUMN product_id SET NOT NULL;
        ALTER TABLE public.products ADD CONSTRAINT pk_products PRIMARY KEY (product_id);
    END IF;

    -- 1.2. Bảng locations (location_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.locations'::regclass AND contype = 'p') THEN
        ALTER TABLE public.locations ALTER COLUMN location_id SET NOT NULL;
        ALTER TABLE public.locations ADD CONSTRAINT pk_locations PRIMARY KEY (location_id);
    END IF;

    -- 1.3. Bảng pallets (pallet_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.pallets'::regclass AND contype = 'p') THEN
        ALTER TABLE public.pallets ALTER COLUMN pallet_id SET NOT NULL;
        ALTER TABLE public.pallets ADD CONSTRAINT pk_pallets PRIMARY KEY (pallet_id);
    END IF;

    -- 1.4. Bảng items (item_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.items'::regclass AND contype = 'p') THEN
        ALTER TABLE public.items ALTER COLUMN item_id SET NOT NULL;
        ALTER TABLE public.items ADD CONSTRAINT pk_items PRIMARY KEY (item_id);
    END IF;

    -- 1.5. Bảng customers (customer_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.customers'::regclass AND contype = 'p') THEN
        ALTER TABLE public.customers ALTER COLUMN customer_id SET NOT NULL;
        ALTER TABLE public.customers ADD CONSTRAINT pk_customers PRIMARY KEY (customer_id);
    END IF;

    -- 1.6. Bảng inbound_orders (inbound_order_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.inbound_orders'::regclass AND contype = 'p') THEN
        ALTER TABLE public.inbound_orders ALTER COLUMN inbound_order_id SET NOT NULL;
        ALTER TABLE public.inbound_orders ADD CONSTRAINT pk_inbound_orders PRIMARY KEY (inbound_order_id);
    END IF;

    -- 1.7. Bảng inbound_order_details (id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.inbound_order_details'::regclass AND contype = 'p') THEN
        ALTER TABLE public.inbound_order_details ALTER COLUMN id SET NOT NULL;
        ALTER TABLE public.inbound_order_details ADD CONSTRAINT pk_inbound_order_details PRIMARY KEY (id);
    END IF;

    -- 1.8. Bảng outbound_orders (outbound_order_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.outbound_orders'::regclass AND contype = 'p') THEN
        ALTER TABLE public.outbound_orders ALTER COLUMN outbound_order_id SET NOT NULL;
        ALTER TABLE public.outbound_orders ADD CONSTRAINT pk_outbound_orders PRIMARY KEY (outbound_order_id);
    END IF;

    -- 1.9. Bảng outbound_order_details (id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.outbound_order_details'::regclass AND contype = 'p') THEN
        ALTER TABLE public.outbound_order_details ALTER COLUMN id SET NOT NULL;
        ALTER TABLE public.outbound_order_details ADD CONSTRAINT pk_outbound_order_details PRIMARY KEY (id);
    END IF;

    -- 1.10. Bảng delivery_notes (delivery_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.delivery_notes'::regclass AND contype = 'p') THEN
        ALTER TABLE public.delivery_notes ALTER COLUMN delivery_id SET NOT NULL;
        ALTER TABLE public.delivery_notes ADD CONSTRAINT pk_delivery_notes PRIMARY KEY (delivery_id);
    END IF;

    -- 1.11. Bảng delivery_note_details (id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.delivery_note_details'::regclass AND contype = 'p') THEN
        ALTER TABLE public.delivery_note_details ALTER COLUMN id SET NOT NULL;
        ALTER TABLE public.delivery_note_details ADD CONSTRAINT pk_delivery_note_details PRIMARY KEY (id);
    END IF;

    -- 1.12. Bảng inventory_sessions (session_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.inventory_sessions'::regclass AND contype = 'p') THEN
        ALTER TABLE public.inventory_sessions ALTER COLUMN session_id SET NOT NULL;
        ALTER TABLE public.inventory_sessions ADD CONSTRAINT pk_inventory_sessions PRIMARY KEY (session_id);
    END IF;

    -- 1.13. Bảng inventory_session_details (id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.inventory_session_details'::regclass AND contype = 'p') THEN
        ALTER TABLE public.inventory_session_details ALTER COLUMN id SET NOT NULL;
        ALTER TABLE public.inventory_session_details ADD CONSTRAINT pk_inventory_session_details PRIMARY KEY (id);
    END IF;

    -- 1.14. Bảng users (user_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.users'::regclass AND contype = 'p') THEN
        ALTER TABLE public.users ALTER COLUMN user_id SET NOT NULL;
        ALTER TABLE public.users ADD CONSTRAINT pk_users PRIMARY KEY (user_id);
    END IF;

    -- 1.15. Bảng sync_logs (id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.sync_logs'::regclass AND contype = 'p') THEN
        ALTER TABLE public.sync_logs ALTER COLUMN id SET NOT NULL;
        ALTER TABLE public.sync_logs ADD CONSTRAINT pk_sync_logs PRIMARY KEY (id);
    END IF;

    -- 1.16. Bảng system_config (config_key)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conrelid = 'public.system_config'::regclass AND contype = 'p') THEN
        ALTER TABLE public.system_config ALTER COLUMN config_key SET NOT NULL;
        ALTER TABLE public.system_config ADD CONSTRAINT pk_system_config PRIMARY KEY (config_key);
    END IF;
END $$;

-- ====================================================================
-- BƯỚC 2: THIẾT LẬP RÀNG BUỘC DUY NHẤT (UNIQUE CONSTRAINTS - UK)
-- Đảm bảo các cột được tham chiếu bởi Khóa Ngoại có tính duy nhất
-- ====================================================================
DO $$
BEGIN
    -- 2.1. locations (location_code)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.locations'::regclass 
          AND c.contype IN ('u', 'p')
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey) AND a.attname = 'location_code')
    ) THEN
        ALTER TABLE public.locations ADD CONSTRAINT uq_locations_location_code UNIQUE (location_code);
    END IF;

    -- 2.2. outbound_orders (po_no)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.outbound_orders'::regclass 
          AND c.contype IN ('u', 'p')
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey) AND a.attname = 'po_no')
    ) THEN
        ALTER TABLE public.outbound_orders ADD CONSTRAINT uq_outbound_orders_po_no UNIQUE (po_no);
    END IF;

    -- 2.3. products (sku)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.products'::regclass 
          AND c.contype IN ('u', 'p')
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey) AND a.attname = 'sku')
    ) THEN
        ALTER TABLE public.products ADD CONSTRAINT uq_products_sku UNIQUE (sku);
    END IF;

    -- 2.4. pallets (pallet_code)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.pallets'::regclass 
          AND c.contype IN ('u', 'p')
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey) AND a.attname = 'pallet_code')
    ) THEN
        ALTER TABLE public.pallets ADD CONSTRAINT uq_pallets_pallet_code UNIQUE (pallet_code);
    END IF;

    -- 2.5. items (epc)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.items'::regclass 
          AND c.contype IN ('u', 'p')
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey) AND a.attname = 'epc')
    ) THEN
        ALTER TABLE public.items ADD CONSTRAINT uq_items_epc UNIQUE (epc);
    END IF;

    -- 2.6. customers (customer_code)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.customers'::regclass 
          AND c.contype IN ('u', 'p')
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey) AND a.attname = 'customer_code')
    ) THEN
        ALTER TABLE public.customers ADD CONSTRAINT uq_customers_customer_code UNIQUE (customer_code);
    END IF;

    -- 2.7. inbound_orders (order_no)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.inbound_orders'::regclass 
          AND c.contype IN ('u', 'p')
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey) AND a.attname = 'order_no')
    ) THEN
        ALTER TABLE public.inbound_orders ADD CONSTRAINT uq_inbound_orders_order_no UNIQUE (order_no);
    END IF;

    -- 2.8. delivery_notes (delivery_no)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.delivery_notes'::regclass 
          AND c.contype IN ('u', 'p')
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey) AND a.attname = 'delivery_no')
    ) THEN
        ALTER TABLE public.delivery_notes ADD CONSTRAINT uq_delivery_notes_delivery_no UNIQUE (delivery_no);
    END IF;

    -- 2.9. inventory_sessions (session_code)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.inventory_sessions'::regclass 
          AND c.contype IN ('u', 'p')
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey) AND a.attname = 'session_code')
    ) THEN
        ALTER TABLE public.inventory_sessions ADD CONSTRAINT uq_inventory_sessions_session_code UNIQUE (session_code);
    END IF;

    -- 2.10. users (username)
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        WHERE c.conrelid = 'public.users'::regclass 
          AND c.contype IN ('u', 'p')
          AND EXISTS (SELECT 1 FROM pg_attribute a WHERE a.attrelid = c.conrelid AND a.attnum = ANY(c.conkey) AND a.attname = 'username')
    ) THEN
        ALTER TABLE public.users ADD CONSTRAINT uq_users_username UNIQUE (username);
    END IF;
END $$;

-- ====================================================================
-- BƯỚC 3: DỌN DẸP & CHUẨN HÓA DỮ LIỆU MỒ CÔI (ORPHAN DATA CLEANUP)
-- ====================================================================
DO $$
BEGIN
    -- 3.1. Pallets: Xóa location_id mồ côi nếu vị trí không tồn tại
    UPDATE public.pallets 
    SET location_id = NULL 
    WHERE location_id IS NOT NULL 
      AND location_id NOT IN (SELECT location_id FROM public.locations);

    -- 3.2. Items: Xóa pallet_id mồ côi nếu pallet không tồn tại
    UPDATE public.items 
    SET pallet_id = NULL 
    WHERE pallet_id IS NOT NULL 
      AND pallet_id NOT IN (SELECT pallet_id FROM public.pallets);

    -- 3.3. Items: Xóa location_id mồ côi nếu location không tồn tại
    UPDATE public.items 
    SET location_id = NULL 
    WHERE location_id IS NOT NULL 
      AND location_id NOT IN (SELECT location_id FROM public.locations);

    -- 3.4. Items: Đảm bảo toàn bộ product_id trong items đều có mặt trong bảng products
    INSERT INTO public.products (product_id, sku, product_name, unit, category, description)
    SELECT DISTINCT i.product_id, i.sku, i.product_name, 'Cái', 'Hàng hoá', 'Tự động tạo từ Item'
    FROM public.items i
    WHERE i.product_id IS NOT NULL 
      AND i.product_id NOT IN (SELECT product_id FROM public.products)
    ON CONFLICT (product_id) DO NOTHING;

    -- 3.5. Inbound Order Details: Dọn dẹp chi tiết đơn mồ côi nếu đơn không tồn tại
    DELETE FROM public.inbound_order_details
    WHERE order_id NOT IN (SELECT inbound_order_id FROM public.inbound_orders);

    INSERT INTO public.products (product_id, sku, product_name, unit, category, description)
    SELECT DISTINCT iod.product_id, iod.sku, iod.product_name, 'Cái', 'Hàng hoá', 'Tự động tạo từ Đơn Nhập'
    FROM public.inbound_order_details iod
    WHERE iod.product_id IS NOT NULL 
      AND iod.product_id NOT IN (SELECT product_id FROM public.products)
    ON CONFLICT (product_id) DO NOTHING;

    -- 3.6. Outbound Order Details: Dọn dẹp chi tiết PO xuất mồ côi nếu PO không tồn tại
    DELETE FROM public.outbound_order_details
    WHERE order_id NOT IN (SELECT outbound_order_id FROM public.outbound_orders);

    INSERT INTO public.products (product_id, sku, product_name, unit, category, description)
    SELECT DISTINCT ood.product_id, ood.sku, ood.product_name, 'Cái', 'Hàng hoá', 'Tự động tạo từ Đơn Xuất'
    FROM public.outbound_order_details ood
    WHERE ood.product_id IS NOT NULL 
      AND ood.product_id NOT IN (SELECT product_id FROM public.products)
    ON CONFLICT (product_id) DO NOTHING;

    -- 3.7. Delivery Notes: Xóa customer_id nếu khách hàng không tồn tại
    UPDATE public.delivery_notes 
    SET customer_id = NULL 
    WHERE customer_id IS NOT NULL 
      AND customer_id NOT IN (SELECT customer_id FROM public.customers);

    -- Delivery Notes: Xóa po_no nếu PO xuất không tồn tại
    UPDATE public.delivery_notes 
    SET po_no = NULL 
    WHERE po_no IS NOT NULL 
      AND po_no NOT IN (SELECT po_no FROM public.outbound_orders);

    -- 3.8. Delivery Note Details: Dọn dẹp chi tiết phiếu xuất mồ côi nếu phiếu không tồn tại
    DELETE FROM public.delivery_note_details
    WHERE delivery_id NOT IN (SELECT delivery_id FROM public.delivery_notes);

    INSERT INTO public.products (product_id, sku, product_name, unit, category, description)
    SELECT DISTINCT dnd.product_id, dnd.sku, dnd.product_name, 'Cái', 'Hàng hoá', 'Tự động tạo từ Phiếu Xuất'
    FROM public.delivery_note_details dnd
    WHERE dnd.product_id IS NOT NULL 
      AND dnd.product_id NOT IN (SELECT product_id FROM public.products)
    ON CONFLICT (product_id) DO NOTHING;

    -- 3.9. Inventory Sessions: Xóa location_code nếu vị trí không tồn tại
    UPDATE public.inventory_sessions 
    SET location_code = NULL 
    WHERE location_code IS NOT NULL 
      AND location_code NOT IN (SELECT location_code FROM public.locations);

    -- 3.10. Inventory Session Details: Dọn dẹp chi tiết kiểm kê mồ côi nếu phiên kiểm kê không tồn tại
    DELETE FROM public.inventory_session_details
    WHERE session_id NOT IN (SELECT session_id FROM public.inventory_sessions);
END $$;

-- ====================================================================
-- BƯỚC 4: THIẾT LẬP TOÀN BỘ 14 KHÓA NGOẠI (FOREIGN KEY CONSTRAINTS)
-- ====================================================================
DO $$
BEGIN
    -- [FK 1] pallets -> locations (location_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_pallets_location') THEN
        ALTER TABLE public.pallets
        ADD CONSTRAINT fk_pallets_location
        FOREIGN KEY (location_id) REFERENCES public.locations (location_id)
        ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;

    -- [FK 2] items -> products (product_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_items_product') THEN
        ALTER TABLE public.items
        ADD CONSTRAINT fk_items_product
        FOREIGN KEY (product_id) REFERENCES public.products (product_id)
        ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;

    -- [FK 3] items -> pallets (pallet_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_items_pallet') THEN
        ALTER TABLE public.items
        ADD CONSTRAINT fk_items_pallet
        FOREIGN KEY (pallet_id) REFERENCES public.pallets (pallet_id)
        ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;

    -- [FK 4] items -> locations (location_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_items_location') THEN
        ALTER TABLE public.items
        ADD CONSTRAINT fk_items_location
        FOREIGN KEY (location_id) REFERENCES public.locations (location_id)
        ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;

    -- [FK 5] inbound_order_details -> inbound_orders (order_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_inbound_order_details_order') THEN
        ALTER TABLE public.inbound_order_details
        ADD CONSTRAINT fk_inbound_order_details_order
        FOREIGN KEY (order_id) REFERENCES public.inbound_orders (inbound_order_id)
        ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;

    -- [FK 6] inbound_order_details -> products (product_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_inbound_order_details_product') THEN
        ALTER TABLE public.inbound_order_details
        ADD CONSTRAINT fk_inbound_order_details_product
        FOREIGN KEY (product_id) REFERENCES public.products (product_id)
        ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;

    -- [FK 7] outbound_order_details -> outbound_orders (order_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_outbound_order_details_order') THEN
        ALTER TABLE public.outbound_order_details
        ADD CONSTRAINT fk_outbound_order_details_order
        FOREIGN KEY (order_id) REFERENCES public.outbound_orders (outbound_order_id)
        ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;

    -- [FK 8] outbound_order_details -> products (product_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_outbound_order_details_product') THEN
        ALTER TABLE public.outbound_order_details
        ADD CONSTRAINT fk_outbound_order_details_product
        FOREIGN KEY (product_id) REFERENCES public.products (product_id)
        ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;

    -- [FK 9] delivery_notes -> customers (customer_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_delivery_notes_customer') THEN
        ALTER TABLE public.delivery_notes
        ADD CONSTRAINT fk_delivery_notes_customer
        FOREIGN KEY (customer_id) REFERENCES public.customers (customer_id)
        ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;

    -- [FK 10] delivery_notes -> outbound_orders (po_no)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_delivery_notes_po') THEN
        ALTER TABLE public.delivery_notes
        ADD CONSTRAINT fk_delivery_notes_po
        FOREIGN KEY (po_no) REFERENCES public.outbound_orders (po_no)
        ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;

    -- [FK 11] delivery_note_details -> delivery_notes (delivery_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_delivery_note_details_delivery') THEN
        ALTER TABLE public.delivery_note_details
        ADD CONSTRAINT fk_delivery_note_details_delivery
        FOREIGN KEY (delivery_id) REFERENCES public.delivery_notes (delivery_id)
        ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;

    -- [FK 12] delivery_note_details -> products (product_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_delivery_note_details_product') THEN
        ALTER TABLE public.delivery_note_details
        ADD CONSTRAINT fk_delivery_note_details_product
        FOREIGN KEY (product_id) REFERENCES public.products (product_id)
        ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;

    -- [FK 13] inventory_sessions -> locations (location_code)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_inventory_sessions_location') THEN
        ALTER TABLE public.inventory_sessions
        ADD CONSTRAINT fk_inventory_sessions_location
        FOREIGN KEY (location_code) REFERENCES public.locations (location_code)
        ON DELETE SET NULL ON UPDATE CASCADE;
    END IF;

    -- [FK 14] inventory_session_details -> inventory_sessions (session_id)
    IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'fk_inventory_session_details_session') THEN
        ALTER TABLE public.inventory_session_details
        ADD CONSTRAINT fk_inventory_session_details_session
        FOREIGN KEY (session_id) REFERENCES public.inventory_sessions (session_id)
        ON DELETE CASCADE ON UPDATE CASCADE;
    END IF;
END $$;

-- ====================================================================
-- BƯỚC 5: TẠO INDEXES HỖ TRỢ HIỆU NĂNG CHO TOÀN BỘ CÁC CỘT KHÓA NGOẠI
-- ====================================================================
CREATE INDEX IF NOT EXISTS idx_pallets_location_id ON public.pallets (location_id);
CREATE INDEX IF NOT EXISTS idx_items_product_id ON public.items (product_id);
CREATE INDEX IF NOT EXISTS idx_items_pallet_id ON public.items (pallet_id);
CREATE INDEX IF NOT EXISTS idx_items_location_id ON public.items (location_id);
CREATE INDEX IF NOT EXISTS idx_inbound_order_details_order_id ON public.inbound_order_details (order_id);
CREATE INDEX IF NOT EXISTS idx_inbound_order_details_product_id ON public.inbound_order_details (product_id);
CREATE INDEX IF NOT EXISTS idx_outbound_order_details_order_id ON public.outbound_order_details (order_id);
CREATE INDEX IF NOT EXISTS idx_outbound_order_details_product_id ON public.outbound_order_details (product_id);
CREATE INDEX IF NOT EXISTS idx_delivery_notes_customer_id ON public.delivery_notes (customer_id);
CREATE INDEX IF NOT EXISTS idx_delivery_notes_po_no ON public.delivery_notes (po_no);
CREATE INDEX IF NOT EXISTS idx_delivery_note_details_delivery_id ON public.delivery_note_details (delivery_id);
CREATE INDEX IF NOT EXISTS idx_delivery_note_details_product_id ON public.delivery_note_details (product_id);
CREATE INDEX IF NOT EXISTS idx_inventory_sessions_location_code ON public.inventory_sessions (location_code);
CREATE INDEX IF NOT EXISTS idx_inventory_session_details_session_id ON public.inventory_session_details (session_id);
