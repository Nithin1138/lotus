/**
 * DropDial Dynamic Pricing Gateway
 * GET /api/pricing - Returns active pricing for India and Worldwide
 * POST /api/pricing - Updates live pricing in memory & local storage (Admin authenticated)
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Default Base Pricing
let currentPricing = {
  INR: {
    amount: 999,
    subunits: 99900,
    symbol: '₹',
    display: '₹999',
    strikeAmount: 1499,
    strikeDisplay: '₹1,499',
    label: 'India Standard'
  },
  USD: {
    amount: 19,
    subunits: 1900,
    symbol: '$',
    display: '$19',
    strikeAmount: 29,
    strikeDisplay: '$29',
    label: 'Global Standard'
  },
  strikethrough: {
    enabled: true,
    inrAmount: 1499,
    usdAmount: 29
  },
  countdown: {
    enabled: true,
    value: 24,
    unit: 'hours',
    label: 'Special Launch Discount Ends In:',
    expiresAt: new Date(Date.now() + 24 * 3600 * 1000).toISOString()
  },
  lastUpdated: new Date().toISOString()
};

// Check for file-based persistence if scratch/temp directory exists
const PERSIST_FILE = path.join('/tmp', 'dropdial_pricing.json');
try {
  if (fs.existsSync(PERSIST_FILE)) {
    const raw = fs.readFileSync(PERSIST_FILE, 'utf8');
    const parsed = JSON.parse(raw);
    if (parsed && parsed.INR && parsed.USD) {
      currentPricing = {
        ...currentPricing,
        ...parsed,
        INR: { ...currentPricing.INR, ...(parsed.INR || {}) },
        USD: { ...currentPricing.USD, ...(parsed.USD || {}) },
        strikethrough: { ...currentPricing.strikethrough, ...(parsed.strikethrough || {}) },
        countdown: { ...currentPricing.countdown, ...(parsed.countdown || {}) }
      };
    }
  }
} catch (e) {}

function getAdminSecret() {
  return (
    process.env.ADMIN_KEY ||
    process.env.ADMIN_PASSWORD ||
    process.env.LICENSE_SECRET ||
    'dropdial2026'
  ).trim();
}

function verifyAdminToken(req) {
  const authHeader = req.headers['authorization'] || '';
  const queryToken = req.query?.token || '';
  const bodyToken = req.body?.token || '';
  const headerToken = req.headers['x-admin-key'] || '';

  let provided = '';
  if (authHeader.startsWith('Bearer ')) {
    provided = authHeader.slice(7).trim();
  } else if (headerToken) {
    provided = headerToken.trim();
  } else if (bodyToken) {
    provided = bodyToken.trim();
  } else if (queryToken) {
    provided = queryToken.trim();
  }

  const expected = getAdminSecret();
  if (!provided) return false;

  try {
    const a = Buffer.from(provided, 'utf8');
    const b = Buffer.from(expected, 'utf8');
    if (a.length !== b.length) return false;
    return crypto.timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

function getActivePricing() {
  return currentPricing;
}

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const { getDb, ensureSchema } = require('./_db');
  const sql = getDb();
  if (sql) {
    try {
      await ensureSchema();
      // Try to load latest pricing from Neon
      const rows = await sql`SELECT value FROM app_settings WHERE key = 'pricing' LIMIT 1;`;
      if (rows && rows.length > 0 && rows[0].value) {
        let val = rows[0].value;
        if (typeof val === 'string') {
          try { val = JSON.parse(val); } catch (e) {}
        }
        if (val && typeof val === 'object') {
          currentPricing = {
            ...currentPricing,
            ...val,
            INR: { ...currentPricing.INR, ...(val.INR || {}) },
            USD: { ...currentPricing.USD, ...(val.USD || {}) },
            strikethrough: { ...currentPricing.strikethrough, ...(val.strikethrough || {}) },
            countdown: {
              ...currentPricing.countdown,
              ...(val.countdown || {}),
              enabled: val.countdown ? (val.countdown.enabled === true) : currentPricing.countdown.enabled
            }
          };
        }
      }
    } catch (dbErr) {
      console.warn('[Neon DB Pricing Read Warning]:', dbErr.message);
    }
  }

  // GET: Public fetch of active pricing (no-cache for instant admin synchronization)
  if (req.method === 'GET') {
    res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
    res.setHeader('Pragma', 'no-cache');
    res.setHeader('Expires', '0');
    return res.status(200).json({
      success: true,
      pricing: currentPricing
    });
  }

  // POST: Admin update live pricing
  if (req.method === 'POST') {
    if (!verifyAdminToken(req)) {
      return res.status(401).json({ error: 'Unauthorized: Invalid admin credentials' });
    }

    try {
      const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
      const inrAmount = Number(body.inrAmount);
      const usdAmount = Number(body.usdAmount);
      const strikeEnabled = body.strikeEnabled !== undefined ? !!body.strikeEnabled : (currentPricing.strikethrough?.enabled ?? true);
      const strikeInr = Number(body.strikeInr) > 0 ? Number(body.strikeInr) : (currentPricing.strikethrough?.inrAmount || 1499);
      const strikeUsd = Number(body.strikeUsd) > 0 ? Number(body.strikeUsd) : (currentPricing.strikethrough?.usdAmount || 29);

      const countdownEnabled = body.countdownEnabled !== undefined ? (body.countdownEnabled === true || body.countdownEnabled === 'true') : false;
      const countdownValue = Number(body.countdownValue) > 0 ? Number(body.countdownValue) : (currentPricing.countdown?.value || 24);
      const countdownUnit = (body.countdownUnit === 'days') ? 'days' : 'hours';
      const countdownLabel = (body.countdownLabel || currentPricing.countdown?.label || 'Special Launch Discount Ends In:').trim();
      const countdownReset = !!body.countdownReset;

      if (!inrAmount || inrAmount <= 0) {
        return res.status(400).json({ error: 'Valid positive INR price is required (e.g. 999).' });
      }
      if (!usdAmount || usdAmount <= 0) {
        return res.status(400).json({ error: 'Valid positive USD price is required (e.g. 19).' });
      }

      // Calculate countdown expiration
      const durationHours = countdownUnit === 'days' ? (countdownValue * 24) : countdownValue;
      const durationMs = durationHours * 3600 * 1000;
      let expiresAt = currentPricing.countdown?.expiresAt;
      const now = Date.now();

      if (countdownReset || !expiresAt || new Date(expiresAt).getTime() <= now) {
        expiresAt = new Date(now + durationMs).toISOString();
      }

      currentPricing = {
        INR: {
          amount: inrAmount,
          subunits: Math.round(inrAmount * 100),
          symbol: '₹',
          display: `₹${inrAmount.toLocaleString('en-IN')}`,
          strikeAmount: strikeInr,
          strikeDisplay: `₹${strikeInr.toLocaleString('en-IN')}`,
          label: 'India Standard'
        },
        USD: {
          amount: usdAmount,
          subunits: Math.round(usdAmount * 100),
          symbol: '$',
          display: `$${usdAmount}`,
          strikeAmount: strikeUsd,
          strikeDisplay: `$${strikeUsd}`,
          label: 'Global Standard'
        },
        strikethrough: {
          enabled: strikeEnabled,
          inrAmount: strikeInr,
          usdAmount: strikeUsd
        },
        countdown: {
          enabled: countdownEnabled,
          value: countdownValue,
          unit: countdownUnit,
          label: countdownLabel,
          expiresAt: expiresAt
        },
        lastUpdated: new Date().toISOString()
      };

      if (sql) {
        try {
          await ensureSchema();
          const pricingJson = JSON.stringify(currentPricing);
          await sql`
            INSERT INTO app_settings (key, value, updated_at)
            VALUES ('pricing', ${pricingJson}::jsonb, NOW())
            ON CONFLICT (key) DO UPDATE SET value = ${pricingJson}::jsonb, updated_at = NOW();
          `;
        } catch (dbErr) {
          console.warn('[Neon DB Pricing Write Warning]:', dbErr.message);
        }
      }

      try {
        fs.writeFileSync(PERSIST_FILE, JSON.stringify(currentPricing), 'utf8');
      } catch (e) {}

      return res.status(200).json({
        success: true,
        message: 'Live prices, strikethrough, and countdown timer updated across checkout and landing page!',
        pricing: currentPricing
      });
    } catch (err) {
      return res.status(500).json({ error: err.message });
    }
  }

  return res.status(405).json({ error: 'Method Not Allowed' });
};

module.exports.getActivePricing = getActivePricing;
