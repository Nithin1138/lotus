/**
 * DropDial Pro Coupon & Offers Management System
 * Vercel Serverless Function: /api/coupons
 * Validates, applies, and manages promotional discounts for DropDial Pro.
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Default active promotional coupons
let couponsStore = [
  {
    code: 'LAUNCH20',
    type: 'percent', // 'percent' or 'flat'
    value: 20, // 20% off
    valueInr: 200, // flat fallback in INR (paise: 20000)
    valueUsd: 4, // flat fallback in USD (cents: 400)
    active: true,
    uses: 0,
    maxUses: 500,
    expiry: '2026-12-31',
    description: 'Launch Special - 20% Off DropDial Pro'
  },
  {
    code: 'DROPDIAL50',
    type: 'percent',
    value: 50,
    valueInr: 500,
    valueUsd: 10,
    active: true,
    uses: 0,
    maxUses: 100,
    expiry: '2026-12-31',
    description: 'VIP Partner Special - 50% Off'
  },
  {
    code: 'PRO10',
    type: 'percent',
    value: 10,
    valueInr: 100,
    valueUsd: 2,
    active: true,
    uses: 0,
    maxUses: 1000,
    expiry: '2027-12-31',
    description: 'Community Welcome - 10% Off'
  },
  {
    code: 'FIRST24',
    type: 'percent',
    value: 10,
    valueInr: 100,
    valueUsd: 2,
    active: true,
    uses: 0,
    maxUses: 100000,
    expiry: '2028-12-31',
    description: 'First 24-Hours Early Bird - 10% Off'
  },
  {
    code: 'EARLY24',
    type: 'percent',
    value: 10,
    valueInr: 100,
    valueUsd: 2,
    active: true,
    uses: 0,
    maxUses: 100000,
    expiry: '2028-12-31',
    description: 'First 24-Hours Early Bird - 10% Off'
  }
];

const PERSIST_FILE = path.join('/tmp', 'dropdial_coupons.json');

function loadPersistedCoupons() {
  try {
    if (fs.existsSync(PERSIST_FILE)) {
      const raw = fs.readFileSync(PERSIST_FILE, 'utf8');
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed) && parsed.length > 0) {
        couponsStore = parsed;
      }
    }
  } catch (e) {}
  return couponsStore;
}

function savePersistedCoupons() {
  try {
    fs.writeFileSync(PERSIST_FILE, JSON.stringify(couponsStore, null, 2), 'utf8');
  } catch (e) {}
}

// Initial load on cold start
loadPersistedCoupons();

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
    return a.length === b.length && crypto.timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

/**
 * Validates a coupon code and calculates discounted prices in subunits (sync version)
 */
function evaluateCoupon(code, currency, baseSubunits) {
  if (!code || typeof code !== 'string') {
    return { valid: false, error: 'Coupon code is required.' };
  }

  loadPersistedCoupons();
  const normalized = code.trim().toUpperCase();
  const coupon = couponsStore.find(c => c.code.toUpperCase() === normalized);

  if (!coupon) {
    return { valid: false, error: 'Invalid coupon code.' };
  }

  if (!coupon.active) {
    return { valid: false, error: 'This coupon code is no longer active.' };
  }

  if (coupon.expiry) {
    const expDate = new Date(`${coupon.expiry}T23:59:59Z`);
    if (new Date() > expDate) {
      return { valid: false, error: 'This coupon code has expired.' };
    }
  }

  const currentUses = Number(coupon.uses) || 0;
  const maxUses = Number(coupon.maxUses || coupon.max_uses) || 0;
  if (maxUses > 0 && currentUses >= maxUses) {
    return { valid: false, error: 'This coupon has reached its maximum redemption limit.' };
  }

  let discountSubunits = 0;
  if (coupon.type === 'percent') {
    discountSubunits = Math.round(baseSubunits * (Number(coupon.value) / 100));
    if (currency === 'INR') {
      discountSubunits = Math.round(discountSubunits / 100) * 100;
    }
  } else if (coupon.type === 'flat') {
    if (currency === 'INR') {
      discountSubunits = (Number(coupon.valueInr || coupon.value_inr) || 200) * 100;
    } else {
      discountSubunits = (Number(coupon.valueUsd || coupon.value_usd) || 4) * 100;
    }
  }

  // Ensure minimum price of at least 1 unit (100 subunits = ₹1 or $1)
  const finalSubunits = Math.max(100, baseSubunits - discountSubunits);
  const finalDisplay = currency === 'INR' ? `₹${Math.round(finalSubunits / 100)}` : `$${Math.round(finalSubunits / 100)}`;
  const discountDisplay = currency === 'INR' ? `₹${Math.round(discountSubunits / 100)}` : `$${Math.round(discountSubunits / 100)}`;

  return {
    valid: true,
    code: coupon.code,
    type: coupon.type,
    value: Number(coupon.value),
    discountSubunits,
    finalSubunits,
    discountDisplay,
    finalDisplay,
    description: coupon.description || `${coupon.value}% discount applied`
  };
}

/**
 * Asynchronously validates a coupon code against Neon DB,
 * checking active status, expiry, max_uses limits, and prior redemption by user email.
 */
async function evaluateCouponAsync(code, currency, baseSubunits, userEmail = '') {
  if (!code || typeof code !== 'string') {
    return { valid: false, error: 'Coupon code is required.' };
  }

  const cleanCode = code.trim().toUpperCase();
  const cleanEmail = (userEmail || '').trim().toLowerCase();

  let coupon = null;

  // 1. Query Neon DB if configured
  try {
    const { getDb, ensureSchema } = require('./_db');
    const sql = getDb();
    if (sql) {
      await ensureSchema();
      const rows = await sql`
        SELECT code, type, value, value_inr as "valueInr", value_usd as "valueUsd", active, uses, max_uses as "maxUses", TO_CHAR(expiry, 'YYYY-MM-DD') as expiry, description
        FROM coupons
        WHERE UPPER(code) = UPPER(${cleanCode})
        LIMIT 1;
      `;
      if (rows && rows.length > 0) {
        coupon = rows[0];
      }

      // Check if user has already redeemed this coupon in prior transaction
      if (coupon && cleanEmail && cleanEmail.includes('@')) {
        const txCheck = await sql`
          SELECT COUNT(*)::int as count
          FROM transactions
          WHERE LOWER(email) = LOWER(${cleanEmail})
            AND UPPER(coupon_code) = UPPER(${cleanCode})
            AND status = 'captured';
        `;
        if (txCheck && txCheck[0]?.count > 0) {
          return { valid: false, error: 'This coupon code has already been redeemed with your email address.' };
        }
      }
    }
  } catch (dbErr) {
    console.warn('[Coupons DB Lookup Warning]:', dbErr.message);
  }

  // 2. Fallback to persisted couponsStore if not in DB
  if (!coupon) {
    loadPersistedCoupons();
    coupon = couponsStore.find(c => c.code.toUpperCase() === cleanCode);
  }

  if (!coupon) {
    return { valid: false, error: 'Invalid coupon code.' };
  }

  if (!coupon.active) {
    return { valid: false, error: 'This coupon code is no longer active.' };
  }

  if (coupon.expiry) {
    const expDate = new Date(`${coupon.expiry}T23:59:59Z`);
    if (new Date() > expDate) {
      return { valid: false, error: 'This coupon code has expired.' };
    }
  }

  const currentUses = Number(coupon.uses) || 0;
  const maxUses = Number(coupon.maxUses || coupon.max_uses) || 0;
  if (maxUses > 0 && currentUses >= maxUses) {
    return { valid: false, error: 'This coupon has reached its maximum redemption limit.' };
  }

  let discountSubunits = 0;
  if (coupon.type === 'percent') {
    discountSubunits = Math.round(baseSubunits * (Number(coupon.value) / 100));
    // Round to whole rupees for INR so Razorpay displays ₹899 cleanly
    if (currency === 'INR') {
      discountSubunits = Math.round(discountSubunits / 100) * 100;
    }
  } else if (coupon.type === 'flat') {
    if (currency === 'INR') {
      discountSubunits = (Number(coupon.valueInr || coupon.value_inr) || 200) * 100;
    } else {
      discountSubunits = (Number(coupon.valueUsd || coupon.value_usd) || 4) * 100;
    }
  }

  const finalSubunits = Math.max(100, baseSubunits - discountSubunits);
  const finalDisplay = currency === 'INR' ? `₹${Math.round(finalSubunits / 100)}` : `$${Math.round(finalSubunits / 100)}`;
  const discountDisplay = currency === 'INR' ? `₹${Math.round(discountSubunits / 100)}` : `$${Math.round(discountSubunits / 100)}`;

  return {
    valid: true,
    code: coupon.code,
    type: coupon.type,
    value: Number(coupon.value),
    discountSubunits,
    finalSubunits,
    discountDisplay,
    finalDisplay,
    description: coupon.description || `${coupon.value}% discount applied`
  };
}

function incrementCouponUses(code) {
  if (!code) return;
  loadPersistedCoupons();
  const normalized = code.trim().toUpperCase();
  const c = couponsStore.find(x => x.code.toUpperCase() === normalized);
  if (c) {
    c.uses = (Number(c.uses) || 0) + 1;
    savePersistedCoupons();
  }
}

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, x-admin-key');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Parse body safely whether sent as raw string, object or stream
  let body = {};
  if (typeof req.body === 'string') {
    try {
      body = JSON.parse(req.body);
    } catch (_) {}
  } else if (req.body && typeof req.body === 'object') {
    body = req.body;
  }
  req.body = body;

  const action = req.query.action || body.action || (req.query.code ? 'validate' : 'list');

  // PUBLIC: Validate a coupon code for checkout
  if (action === 'validate') {
    const code = req.query.code || req.body?.code;
    const currency = (req.query.currency || req.body?.currency || 'USD').toUpperCase();
    const email = (req.query.email || req.body?.email || '').trim().toLowerCase();
    const baseSubunits = currency === 'INR' ? 99900 : 1900;

    const result = await evaluateCouponAsync(code, currency, baseSubunits, email);
    if (!result.valid) {
      return res.status(400).json(result);
    }
    return res.status(200).json(result);
  }

  // ADMIN OPERATIONS: Require authentication
  if (!verifyAdminToken(req)) {
    return res.status(401).json({ error: 'Unauthorized: Invalid admin credentials.' });
  }

  const { getDb, ensureSchema } = require('./_db');
  const sql = getDb();

  // 1. List all coupons
  if (action === 'list') {
    loadPersistedCoupons();
    if (sql) {
      try {
        await ensureSchema();
        const rows = await sql`SELECT code, type, value, value_inr as "valueInr", value_usd as "valueUsd", active, uses, max_uses as "maxUses", TO_CHAR(expiry, 'YYYY-MM-DD') as expiry, description FROM coupons ORDER BY created_at DESC;`;
        if (rows && rows.length > 0) {
          couponsStore = rows;
          savePersistedCoupons();
          return res.status(200).json({ success: true, coupons: rows });
        }
      } catch (dbErr) {
        console.warn('[Neon DB Coupons List Warning]:', dbErr.message);
      }
    }
    return res.status(200).json({ success: true, coupons: couponsStore });
  }

  // 2. Create or Update Coupon
  if (action === 'save') {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST required' });
    const { code, type = 'percent', value = 20, valueInr = 200, valueUsd = 4, maxUses = 100, expiry = '2026-12-31', description = '' } = body || {};

    if (!code || typeof code !== 'string') {
      return res.status(400).json({ error: 'Coupon code is required.' });
    }

    loadPersistedCoupons();
    const cleanCode = code.trim().toUpperCase();
    const existingIndex = couponsStore.findIndex(c => c.code.toUpperCase() === cleanCode);

    const couponObj = {
      code: cleanCode,
      type: type === 'flat' ? 'flat' : 'percent',
      value: Number(value) || 0,
      valueInr: Number(valueInr) || 200,
      valueUsd: Number(valueUsd) || 4,
      active: true,
      uses: existingIndex >= 0 ? (couponsStore[existingIndex].uses || 0) : 0,
      maxUses: Number(maxUses) || 500,
      expiry: expiry || '2026-12-31',
      description: (description || '').trim() || `${value}% Discount`
    };

    if (existingIndex >= 0) {
      couponsStore[existingIndex] = { ...couponsStore[existingIndex], ...couponObj };
    } else {
      couponsStore.unshift(couponObj);
    }

    savePersistedCoupons();

    if (sql) {
      try {
        await ensureSchema();
        await sql`
          INSERT INTO coupons (code, type, value, value_inr, value_usd, active, uses, max_uses, expiry, description, created_at)
          VALUES (${couponObj.code}, ${couponObj.type}, ${couponObj.value}, ${couponObj.valueInr}, ${couponObj.valueUsd}, ${couponObj.active}, ${couponObj.uses}, ${couponObj.maxUses}, ${couponObj.expiry ? couponObj.expiry : null}, ${couponObj.description}, NOW())
          ON CONFLICT (code) DO UPDATE SET
            type = EXCLUDED.type,
            value = EXCLUDED.value,
            value_inr = EXCLUDED.value_inr,
            value_usd = EXCLUDED.value_usd,
            active = EXCLUDED.active,
            max_uses = EXCLUDED.max_uses,
            expiry = EXCLUDED.expiry,
            description = EXCLUDED.description;
        `;
      } catch (dbErr) {
        console.warn('[Neon DB Coupon Save Warning]:', dbErr.message);
      }
    }

    return res.status(200).json({ success: true, coupon: couponObj, coupons: couponsStore });
  }

  // 3. Toggle Coupon Status (Active / Inactive)
  if (action === 'toggle') {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST required' });
    const { code } = body || {};
    loadPersistedCoupons();
    const coupon = couponsStore.find(c => c.code.toUpperCase() === (code || '').toUpperCase());
    if (!coupon) {
      return res.status(404).json({ error: 'Coupon not found.' });
    }

    coupon.active = !coupon.active;
    savePersistedCoupons();

    if (sql) {
      try {
        await ensureSchema();
        await sql`UPDATE coupons SET active = ${coupon.active} WHERE code = ${coupon.code};`;
      } catch (dbErr) {
        console.warn('[Neon DB Coupon Toggle Warning]:', dbErr.message);
      }
    }
    return res.status(200).json({ success: true, coupon, coupons: couponsStore });
  }

  // 4. Delete Coupon
  if (action === 'delete') {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST required' });
    const { code } = body || {};
    loadPersistedCoupons();
    const cleanCode = (code || '').trim().toUpperCase();
    couponsStore = couponsStore.filter(c => c.code.toUpperCase() !== cleanCode);
    savePersistedCoupons();

    if (sql) {
      try {
        await ensureSchema();
        await sql`DELETE FROM coupons WHERE code = ${cleanCode};`;
      } catch (dbErr) {
        console.warn('[Neon DB Coupon Delete Warning]:', dbErr.message);
      }
    }
    return res.status(200).json({ success: true, coupons: couponsStore });
  }

  return res.status(400).json({ error: `Unknown action: ${action}` });
};

// Export evaluation logic for internal server routes
module.exports.evaluateCoupon = evaluateCoupon;
module.exports.evaluateCouponAsync = evaluateCouponAsync;
module.exports.incrementCouponUses = incrementCouponUses;
