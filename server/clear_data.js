const mysql = require('mysql2/promise');

const dbConfig = {
  host: process.env.DB_HOST || '127.0.0.1',
  port: parseInt(process.env.DB_PORT || '3306'),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_NAME || 'rfidwarehouse',
};

async function clearData() {
  console.log('Connecting to MySQL database:', dbConfig);
  let connection;
  try {
    connection = await mysql.createConnection(dbConfig);
    console.log('Connected to MySQL successfully!');

    // List of tables to clear
    const tables = [
      'inventory_transactions',
      'inventory_session_details',
      'inventory_sessions',
      'inbound_order_details',
      'inbound_orders',
      'outbound_order_details',
      'outbound_orders',
      'items',
      'pallets',
      'products',
      'rfid_scan_logs'
    ];

    for (const table of tables) {
      try {
        const [result] = await connection.query(`DELETE FROM ${table}`);
        console.log(`✓ Cleared table: ${table} (${result.affectedRows || 0} rows removed)`);
      } catch (err) {
        console.warn(`! Warning clearing table ${table}:`, err.message);
      }
    }

    console.log('\n🎉 Successfully cleared all test inventory & products from MySQL database!');
  } catch (error) {
    console.error('❌ Error connecting to MySQL:', error.message);
  } finally {
    if (connection) {
      await connection.end();
    }
  }
}

clearData();
