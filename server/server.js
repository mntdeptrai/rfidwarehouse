/**
 * ====================================================================
 * RFID WMS REST API SERVER
 * Backend trung gian giao tiếp Database MySQL, App Desktop và App Mobile PDA
 * ====================================================================
 */

const express = require('express');
const cors = require('cors');
const mysql = require('mysql2/promise');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// MySQL Database Connection Pool
const dbConfig = {
  host: process.env.DB_HOST || '127.0.0.1',
  port: parseInt(process.env.DB_PORT || '3306'),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'rfidwarehouse',
  waitForConnections: true,
  connectionLimit: 20,
  queueLimit: 0,
};

const pool = mysql.createPool(dbConfig);

// Helper function to get local IP addresses for easy PDA connection
function getLocalIpAddresses() {
  const interfaces = os.networkInterfaces();
  const addresses = [];
  for (const name of Object.keys(interfaces)) {
    for (const net of interfaces[name]) {
      if (net.family === 'IPv4' && !net.internal) {
        addresses.push(net.address);
      }
    }
  }
  return addresses;
}

// --------------------------------------------------------------------
// 0. HEALTH CHECK & SERVER INFO
// --------------------------------------------------------------------
app.get('/api/health', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT 1 as connected, NOW() as server_time');
    res.json({
      status: 'ONLINE',
      database: 'CONNECTED',
      serverTime: rows[0].server_time,
      localIps: getLocalIpAddresses(),
      port: PORT,
      message: 'Hệ thống RFID WMS REST API hoạt động bình thường'
    });
  } catch (error) {
    res.status(500).json({
      status: 'ERROR',
      database: 'DISCONNECTED',
      error: error.message
    });
  }
});

// --------------------------------------------------------------------
// 1. LOCATIONS API (Vị trí kệ kho)
// --------------------------------------------------------------------
// Lấy toàn bộ danh sách vị trí kệ
app.get('/api/locations', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM locations ORDER BY zone ASC, shelf ASC, level ASC');
    res.json({
      success: true,
      count: rows.length,
      data: rows
    });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Thêm mới vị trí kệ
app.post('/api/locations', async (req, res) => {
  const { location_id, location_code, zone, shelf, level, max_pallets = 2 } = req.body;
  if (!location_code || !zone) {
    return res.status(400).json({ success: false, message: 'location_code và zone là bắt buộc' });
  }
  const locId = location_id || `LOC-${location_code.toUpperCase()}`;

  try {
    await pool.query(
      `INSERT INTO locations (location_id, location_code, zone, shelf, level, max_pallets, status) 
       VALUES (?, ?, ?, ?, ?, ?, 'AVAILABLE') 
       ON DUPLICATE KEY UPDATE zone = VALUES(zone), shelf = VALUES(shelf), level = VALUES(level)`,
      [locId, location_code, zone, shelf || '01', level || '01', max_pallets]
    );
    res.json({ success: true, message: 'Thêm/Cập nhật vị trí thành công', location_id: locId });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --------------------------------------------------------------------
// 2. PRODUCTS API (Danh mục sản phẩm)
// --------------------------------------------------------------------
app.get('/api/products', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM products ORDER BY product_name ASC');
    res.json({ success: true, count: rows.length, data: rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

app.post('/api/products', async (req, res) => {
  const { product_id, sku, product_name, unit = 'Cái', category = 'Chung', description } = req.body;
  if (!sku || !product_name) {
    return res.status(400).json({ success: false, message: 'sku và product_name là bắt buộc' });
  }
  const prodId = product_id || `PROD-${sku}`;

  try {
    await pool.query(
      `INSERT INTO products (product_id, sku, product_name, unit, category, description) 
       VALUES (?, ?, ?, ?, ?, ?) 
       ON DUPLICATE KEY UPDATE product_name = VALUES(product_name), unit = VALUES(unit), category = VALUES(category)`,
      [prodId, sku, product_name, unit, category, description || '']
    );
    res.json({ success: true, message: 'Thêm/Cập nhật sản phẩm thành công', product_id: prodId });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --------------------------------------------------------------------
// 3. INBOUND ORDERS API (Đơn Nhập Kho)
// --------------------------------------------------------------------
// Lấy danh sách đơn nhập kho (có thể lọc theo status)
app.get('/api/inbound-orders', async (req, res) => {
  try {
    const { status } = req.query;
    let query = 'SELECT * FROM inbound_orders';
    const params = [];

    if (status) {
      query += ' WHERE status = ?';
      params.push(status);
    }
    query += ' ORDER BY created_at DESC';

    const [orders] = await pool.query(query, params);

    // Gắn kèm chi tiết sản phẩm cho từng đơn
    for (const order of orders) {
      const [details] = await pool.query(
        'SELECT * FROM inbound_order_details WHERE order_id = ?',
        [order.inbound_order_id]
      );
      order.details = details;
    }

    res.json({ success: true, count: orders.length, data: orders });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Lấy chi tiết 1 đơn hàng theo Order No
app.get('/api/inbound-orders/:orderNo', async (req, res) => {
  const { orderNo } = req.params;
  try {
    const [orders] = await pool.query(
      'SELECT * FROM inbound_orders WHERE order_no = ? OR inbound_order_id = ?',
      [orderNo, orderNo]
    );
    if (orders.length === 0) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy đơn nhập kho' });
    }

    const order = orders[0];
    const [details] = await pool.query(
      'SELECT * FROM inbound_order_details WHERE order_id = ?',
      [order.inbound_order_id]
    );
    order.details = details;

    const [items] = await pool.query(
      'SELECT * FROM items WHERE order_no = ?',
      [order.order_no]
    );
    order.items = items;

    res.json({ success: true, data: order });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Tạo đơn nhập kho mới (kèm chi tiết items & chip EPC)
app.post('/api/inbound-orders', async (req, res) => {
  const { order_no, source_supplier, details = [] } = req.body;
  if (!order_no || !source_supplier) {
    return res.status(400).json({ success: false, message: 'order_no và source_supplier là bắt buộc' });
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();

    const orderId = `INB-${order_no}`;
    const totalRequired = details.reduce((sum, d) => sum + (parseInt(d.required_qty) || 0), 0);

    // 1. Thêm đơn nhập kho
    await connection.query(
      `INSERT INTO inbound_orders (inbound_order_id, order_no, source_supplier, status, total_required, total_received, created_at)
       VALUES (?, ?, ?, 'NEW', ?, 0, NOW())
       ON DUPLICATE KEY UPDATE source_supplier = VALUES(source_supplier), total_required = VALUES(total_required)`,
      [orderId, order_no, source_supplier, totalRequired]
    );

    // 2. Thêm chi tiết đơn
    for (const d of details) {
      await connection.query(
        `INSERT INTO inbound_order_details (order_id, product_id, sku, product_name, required_qty, received_qty)
         VALUES (?, ?, ?, ?, ?, 0)`,
        [orderId, d.product_id || `PROD-${d.sku}`, d.sku, d.product_name, d.required_qty]
      );
    }

    await connection.commit();
    res.json({ success: true, message: 'Tạo đơn nhập kho thành công', inbound_order_id: orderId });
  } catch (error) {
    await connection.rollback();
    res.status(500).json({ success: false, error: error.message });
  } finally {
    connection.release();
  }
});

// --------------------------------------------------------------------
// 4. GIAI ĐOẠN 1: CỔNG RFID GATE TIẾP NHẬN (Gate Receive)
// --------------------------------------------------------------------
app.post('/api/gate/receive', async (req, res) => {
  const { order_no, scanned_epcs = [], performed_by = 'Cổng RFID Desktop' } = req.body;
  if (!order_no || scanned_epcs.length === 0) {
    return res.status(400).json({ success: false, message: 'order_no và danh sách scanned_epcs là bắt buộc' });
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();

    // 1. Cập nhật các Items trong kiện/thùng sang WAITING_PUTAWAY (Chờ xếp kho) và vị trí LOC-GATE-IN
    for (const epc of scanned_epcs) {
      await connection.query(
        `UPDATE items 
         SET status = 'WAITING_PUTAWAY', location_id = 'LOC-GATE-IN', order_no = ?, inbound_time = NOW() 
         WHERE epc = ?`,
        [order_no, epc]
      );
    }

    // 2. Cập nhật trạng thái đơn hàng sang WAITING_PUTAWAY
    await connection.query(
      `UPDATE inbound_orders 
       SET status = 'WAITING_PUTAWAY', total_received = ?, updated_at = NOW() 
       WHERE order_no = ?`,
      [scanned_epcs.length, order_no]
    );

    // 3. Ghi log giao dịch
    await connection.query(
      `INSERT INTO inventory_transactions (transaction_id, transaction_type, item_id, epc, to_location_id, order_ref, performed_by, note, created_at)
       VALUES (?, 'IN', ?, ?, 'LOC-GATE-IN', ?, ?, 'Cổng RFID quét tiếp nhận - Chờ xếp kho', NOW())`,
      [`TX-GATE-${Date.now()}`, `BATCH-${order_no}`, scanned_epcs[0], order_no, performed_by]
    );

    await connection.commit();
    res.json({
      success: true,
      message: `Đã tiếp nhận kiện hàng ${order_no} (${scanned_epcs.length} chip) -> Trạng thái: CHỜ XẾP KHO`,
      order_no,
      status: 'WAITING_PUTAWAY',
      location_id: 'LOC-GATE-IN',
      received_count: scanned_epcs.length
    });
  } catch (error) {
    await connection.rollback();
    res.status(500).json({ success: false, error: error.message });
  } finally {
    connection.release();
  }
});

// --------------------------------------------------------------------
// 5. GIAI ĐOẠN 2: TAY CẦM PDA CẤT HÀNG LÊN KỆ (PDA Putaway Confirmation)
// --------------------------------------------------------------------
app.post('/api/pda/putaway', async (req, res) => {
  const { carton_barcode, location_id, performed_by = 'Thủ kho PDA' } = req.body;
  if (!carton_barcode || !location_id) {
    return res.status(400).json({ success: false, message: 'carton_barcode và location_id là bắt buộc' });
  }

  const connection = await pool.getConnection();
  try {
    await connection.beginTransaction();

    // 1. Kiểm tra vị trí kệ có tồn tại không
    const [locs] = await connection.query(
      'SELECT * FROM locations WHERE location_id = ? OR location_code = ?',
      [location_id, location_id]
    );
    const targetLocId = locs.length > 0 ? locs[0].location_id : location_id;
    const targetLocCode = locs.length > 0 ? locs[0].location_code : location_id;

    // 2. Tìm và cập nhật tất cả items thuộc mã thùng / đơn hàng này
    const [updateResult] = await connection.query(
      `UPDATE items 
       SET status = 'IN_STOCK', location_id = ?, inbound_time = IFNULL(inbound_time, NOW()), updated_at = NOW() 
       WHERE order_no = ? OR pallet_id = ? OR epc = ? OR serial_number = ?`,
      [targetLocId, carton_barcode, carton_barcode, carton_barcode, carton_barcode]
    );

    const affectedItems = updateResult.affectedRows;

    // 3. Cập nhật trạng thái đơn hàng sang COMPLETED (Hoàn tất nhập kho)
    await connection.query(
      `UPDATE inbound_orders 
       SET status = 'COMPLETED', updated_at = NOW() 
       WHERE order_no = ? OR inbound_order_id = ?`,
      [carton_barcode, carton_barcode]
    );

    // 4. Ghi log lịch sử Putaway
    await connection.query(
      `INSERT INTO inventory_transactions (transaction_id, transaction_type, item_id, epc, from_location_id, to_location_id, order_ref, performed_by, note, created_at)
       VALUES (?, 'MOVE', ?, ?, 'LOC-GATE-IN', ?, ?, ?, 'PDA xác nhận Barcode cất thùng lên kệ', NOW())`,
      [`TX-PUTAWAY-${Date.now()}`, `BATCH-${carton_barcode}`, carton_barcode, targetLocId, carton_barcode, performed_by]
    );

    await connection.commit();

    res.json({
      success: true,
      message: `Đã cất thùng hàng ${carton_barcode} vào vị trí ${targetLocCode} (${affectedItems} sản phẩm đang TRONG KHO)`,
      carton_barcode,
      location_id: targetLocId,
      location_code: targetLocCode,
      status: 'IN_STOCK',
      updated_items_count: affectedItems
    });
  } catch (error) {
    await connection.rollback();
    res.status(500).json({ success: false, error: error.message });
  } finally {
    connection.release();
  }
});

// --------------------------------------------------------------------
// 6. RFID ITEMS API (Tra cứu cá thể sản phẩm & Thẻ chip)
// --------------------------------------------------------------------
app.get('/api/items', async (req, res) => {
  try {
    const { status, location_id, order_no } = req.query;
    let query = 'SELECT i.*, p.product_name, p.category, loc.location_code, loc.zone FROM items i JOIN products p ON i.product_id = p.product_id LEFT JOIN locations loc ON i.location_id = loc.location_id WHERE 1=1';
    const params = [];

    if (status) {
      query += ' AND i.status = ?';
      params.push(status);
    }
    if (location_id) {
      query += ' AND i.location_id = ?';
      params.push(location_id);
    }
    if (order_no) {
      query += ' AND i.order_no = ?';
      params.push(order_no);
    }

    query += ' ORDER BY i.inbound_time DESC LIMIT 500';
    const [rows] = await pool.query(query, params);
    res.json({ success: true, count: rows.length, data: rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// Tra cứu theo mã chip EPC
app.get('/api/items/epc/:epc', async (req, res) => {
  const { epc } = req.params;
  try {
    const [rows] = await pool.query(
      `SELECT i.*, p.product_name, p.sku, p.unit, loc.location_code, loc.zone, loc.shelf, loc.level 
       FROM items i 
       JOIN products p ON i.product_id = p.product_id 
       LEFT JOIN locations loc ON i.location_id = loc.location_id 
       WHERE i.epc = ?`,
      [epc]
    );

    if (rows.length === 0) {
      return res.status(404).json({ success: false, message: 'Không tìm thấy thẻ chip RFID' });
    }
    res.json({ success: true, data: rows[0] });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --------------------------------------------------------------------
// 7. TRANSACTIONS & AUDIT LOGS API
// --------------------------------------------------------------------
app.get('/api/transactions', async (req, res) => {
  try {
    const [rows] = await pool.query('SELECT * FROM inventory_transactions ORDER BY created_at DESC LIMIT 100');
    res.json({ success: true, count: rows.length, data: rows });
  } catch (error) {
    res.status(500).json({ success: false, error: error.message });
  }
});

// --------------------------------------------------------------------
// START HTTP SERVER
// --------------------------------------------------------------------
app.listen(PORT, '0.0.0.0', () => {
  console.log('====================================================================');
  console.log(`🚀 RFID WMS REST API SERVER ĐANG CHẠY TẠI PORT: ${PORT}`);
  console.log(`📡 Kết nối cơ sở dữ liệu: ${dbConfig.user}@${dbConfig.host}:${dbConfig.port}/${dbConfig.database}`);
  console.log('🌐 Địa chỉ truy cập trong mạng LAN (dành cho PDA & Desktop):');
  getLocalIpAddresses().forEach(ip => {
    console.log(`   👉 http://${ip}:${PORT}/api/health`);
  });
  console.log('====================================================================');
});
