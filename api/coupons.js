/**
 * DropDial Pro Coupon & Offers Management System
 * Vercel Serverless Function: /api/coupons
 * Validates, applies, and manages promotional discounts for DropDial Pro.
 */

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
  }
];

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
 * Validates a coupon code and calculates discounted prices in subunits
 */
function evaluateCoupon(code, currency, baseSubunits) {
  if (!code || typeof code !== 'string') {
    return { valid: false, error: 'Coupon code is required.' };
  }

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

  if (coupon.maxUses && coupon.uses >= coupon.maxUses) {
    return { valid: false, error: 'Coupon usage limit has been reached.' };
  }

  let discountSubunits = 0;
  if (coupon.type === 'percent') {
    discountSubunits = Math.round(baseSubunits * (coupon.value / 100));
  } else if (coupon.type === 'flat') {
    if (currency === 'INR') {
      discountSubunits = (coupon.valueInr || 200) * 100;
    } else {
      discountSubunits = (coupon.valueUsd || 4) * 100;
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
    value: coupon.value,
    discountSubunits,
    finalSubunits,
    discountDisplay,
    finalDisplay,
    description: coupon.description || `${coupon.value}% discount applied`
  };
}

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, x-admin-key');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const action = req.query.action || req.body?.action || (req.query.code ? 'validate' : 'list');

  // PUBLIC: Validate a coupon code for checkout
  if (action === 'validate') {
    const code = req.query.code || req.body?.code;
    const currency = (req.query.currency || req.body?.currency || 'USD').toUpperCase();
    const baseSubunits = currency === 'INR' ? 99900 : 1900;

    const result = evaluateCoupon(code, currency, baseSubunits);
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
    if (sql) {
      try {
        await ensureSchema();
        const rows = await sql`SELECT code, type, value, value_inr as "valueInr", value_usd as "valueUsd", active, uses, max_uses as "maxUses", TO_CHAR(expiry, 'YYYY-MM-DD') as expiry, description FROM coupons ORDER BY created_at DESC;`;
        if (rows && rows.length > 0) {
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
    const { code, type = 'percent', value = 20, valueInr = 200, valueUsd = 4, maxUses = 100, expiry = '2026-12-31', description = '' } = req.body || {};

    if (!code || typeof code !== 'string') {
      return res.status(400).json({ error: 'Coupon code is required.' });
    }

    const cleanCode = code.trim().toUpperCase();
    const existingIndex = couponsStore.findIndex(c => c.code.toUpperCase() === cleanCode);

    const couponObj = {
      code: cleanCode,
      type,
      value: Number(value) || 0,
      valueInr: Number(valueInr) || 0,
      valueUsd: Number(valueUsd) || 0,
      active: true,
      uses: existingIndex >= 0 ? couponsStore[existingIndex].uses : 0,
      maxUses: Number(maxUses) || 500,
      expiry,
      description: description.trim() || `${value}% Discount`
    };

    if (existingIndex >= 0) {
      couponsStore[existingIndex] = { ...couponsStore[existingIndex], ...couponObj };
    } else {
      couponsStore.unshift(couponObj);
    }

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
    const { code } = req.body || {};
    const coupon = couponsStore.find(c => c.code.toUpperCase() === (code || '').toUpperCase());
    if (!coupon) {
      return res.status(404).json({ error: 'Coupon not found.' });
    }

    coupon.active = !coupon.active;
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
    const { code } = req.body || {};
    couponsStore = couponsStore.filter(c => c.code.toUpperCase() !== (code || '').toUpperCase());
    if (sql) {
      try {
        await ensureSchema();
        await sql`DELETE FROM coupons WHERE code = ${(code || '').trim().toUpperCase()};`;
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
