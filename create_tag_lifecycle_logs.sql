-- ==============================================================================
-- UHF RFID WMS - TẠO BẢNG NHẬT KÝ VÒNG ĐỜI THẺ RFID (tag_lifecycle_logs)
-- Mục đích: Quản lý toàn bộ lịch sử Audit Trail của thẻ RFID từ lúc khởi tạo,
-- nhập kho, xếp pallet, cất kệ, điều chuyển, kiểm kê đến xuất kho.
-- Sử dụng: Copy toàn bộ đoạn mã này và dán vào Supabase Dashboard -> SQL Editor -> Run
-- ==============================================================================

-- 1. Tạo bảng tag_lifecycle_logs nếu chưa tồn tại
CREATE TABLE IF NOT EXISTS public.tag_lifecycle_logs (
    log_id TEXT PRIMARY KEY,
    epc TEXT NOT NULL,
    item_id TEXT,
    sku TEXT,
    product_name TEXT,
    serial_number TEXT,
    action TEXT NOT NULL,
    action_label TEXT NOT NULL,
    previous_status TEXT,
    new_status TEXT NOT NULL,
    from_location TEXT,
    to_location TEXT,
    from_pallet TEXT,
    to_pallet TEXT,
    document_no TEXT,
    performed_by TEXT NOT NULL DEFAULT 'Hệ thống',
    device TEXT,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 2. Đánh Index tối ưu hóa truy vấn tốc độ cao (Tránh Full Table Scan)
CREATE INDEX IF NOT EXISTS idx_tag_lifecycle_epc ON public.tag_lifecycle_logs (epc);
CREATE INDEX IF NOT EXISTS idx_tag_lifecycle_timestamp ON public.tag_lifecycle_logs (timestamp DESC);
CREATE INDEX IF NOT EXISTS idx_tag_lifecycle_sku ON public.tag_lifecycle_logs (sku);
CREATE INDEX IF NOT EXISTS idx_tag_lifecycle_action ON public.tag_lifecycle_logs (action);
CREATE INDEX IF NOT EXISTS idx_tag_lifecycle_doc ON public.tag_lifecycle_logs (document_no);

-- 3. Cấu hình phân quyền RLS (Row Level Security) cho Flutter App
ALTER TABLE public.tag_lifecycle_logs DISABLE ROW LEVEL SECURITY;
GRANT ALL ON TABLE public.tag_lifecycle_logs TO anon, authenticated, service_role;

-- 4. Đăng ký Realtime (Supabase Realtime Publication)
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
    CREATE PUBLICATION supabase_realtime;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname = 'supabase_realtime' AND tablename = 'tag_lifecycle_logs') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.tag_lifecycle_logs;
  END IF;
END $$;

-- 5. Kiểm tra kết quả tạo bảng
SELECT 
    table_name, 
    column_name, 
    data_type, 
    is_nullable 
FROM information_schema.columns 
WHERE table_name = 'tag_lifecycle_logs'
ORDER BY ordinal_position;
