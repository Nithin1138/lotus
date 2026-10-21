/**
 * DropDial Neon Postgres Database Connection & Schema Helper
 * Uses serverless HTTP connection pool - zero cold-start delay, 100% resilient.
 */

let neonSql = null;

function getDb() {
  const dbUrl = (process.env.DATABASE_URL || process.env.POSTGRES_URL || process.env.NEON_DATABASE_URL || '').trim();
  if (!dbUrl) {
    return null;
  }

  if (!neonSql) {
    try {
      const { neon } = require('@neondatabase/serverless');
      neonSql = neon(dbUrl);
    } catch (e) {
      console.warn('[Neon DB] Failed to initialize @neondatabase/serverless:', e.message);
      return null;
    }
  }

  return neonSql;
}

/**
 * Automatically creates required tables on first call if they don't exist
 */
let schemaInitialized = false;

async function ensureSchema() {
  if (schemaInitialized) return;
  const sql = getDb();
  if (!sql) return;

  try {
    // 1. Licenses Table
    await sql`
      CREATE TABLE IF NOT EXISTS licenses (
        id VARCHAR(64) PRIMARY KEY,
        customer_name VARCHAR(255) NOT NULL,
        email VARCHAR(255) NOT NULL,
        license_key TEXT NOT NULL,
        tier VARCHAR(50) DEFAULT 'Pro Lifetime',
        status VARCHAR(50) DEFAULT 'active',
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `;

    // 2. Transactions Table
    await sql`
      CREATE TABLE IF NOT EXISTS transactions (
        id VARCHAR(64) PRIMARY KEY,
        order_id VARCHAR(128),
        payment_id VARCHAR(128),
        amount INT NOT NULL,
        currency VARCHAR(10) NOT NULL,
        customer_name VARCHAR(255),
        email VARCHAR(255) NOT NULL,
        status VARCHAR(50) DEFAULT 'captured',
        coupon_code VARCHAR(64),
        country VARCHAR(10),
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `;

    // 3. Coupons Table
    await sql`
      CREATE TABLE IF NOT EXISTS coupons (
        code VARCHAR(64) PRIMARY KEY,
        type VARCHAR(20) DEFAULT 'percent',
        value INT NOT NULL,
        value_inr INT,
        value_usd INT,
        active BOOLEAN DEFAULT TRUE,
        uses INT DEFAULT 0,
        max_uses INT DEFAULT 500,
        expiry DATE,
        description TEXT,
        created_at TIMESTAMPTZ DEFAULT NOW()
      );
    `;

    // Automatically seed promotional coupons into Neon if not already present
    try {
      await sql`
        INSERT INTO coupons (code, type, value, value_inr, value_usd, active, uses, max_uses, expiry, description, created_at)
        VALUES 
          ('LAUNCH20', 'percent', 20, 200, 4, true, 0, 500, '2026-12-31', 'Launch Special - 20% Off DropDial Pro', NOW()),
          ('DROPDIAL50', 'percent', 50, 500, 10, true, 0, 100, '2026-12-31', 'VIP Partner Special - 50% Off', NOW()),
          ('PRO10', 'percent', 10, 100, 2, true, 0, 1000, '2027-12-31', 'Community Welcome - 10% Off', NOW()),
          ('FIRST24', 'percent', 10, 100, 2, true, 0, 100000, '2028-12-31', 'First 24-Hours Early Bird - 10% Off', NOW()),
          ('EARLY24', 'percent', 10, 100, 2, true, 0, 100000, '2028-12-31', 'First 24-Hours Early Bird - 10% Off', NOW())
        ON CONFLICT (code) DO NOTHING;
      `;
    } catch (seedErr) {
      console.warn('[Neon DB Seed Warning]:', seedErr.message);
    }

    // 4. App Settings / Live Pricing Table
    await sql`
      CREATE TABLE IF NOT EXISTS app_settings (
        key VARCHAR(64) PRIMARY KEY,
        value JSONB NOT NULL,
        updated_at TIMESTAMPTZ DEFAULT NOW()
      );
    `;

    schemaInitialized = true;
    console.log('[Neon DB] Schema verification and setup successful.');
  } catch (err) {
    console.error('[Neon DB Schema Init Error]:', err.message);
  }
}

module.exports = {
  getDb,
  ensureSchema
};
