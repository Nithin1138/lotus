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
    usdAmount: 29,
    single: {
      enabled: true,
      inrAmount: 1199,
      usdAmount: 24
    },
    universal: {
      enabled: true,
      inrAmount: 1499,
      usdAmount: 29
    },
    team: {
      enabled: true,
      inrAmount: 4999,
      usdAmount: 99
    }
  },
  countdown: {
    enabled: true,
    value: 24,
    unit: 'hours',
    label: 'Special Launch Discount Ends In:',
    expiresAt: new Date(Date.now() + 24 * 3600 * 1000).toISOString()
  },
  devicesPerLicense: 3,
  tiers: {
    single: {
      INR: { amount: 799, display: '₹799', strikeAmount: 1199, strikeDisplay: '₹1,199' },
      USD: { amount: 15, display: '$15', strikeAmount: 24, strikeDisplay: '$24' },
      strikeEnabled: true
    },
    universal: {
      INR: { amount: 999, display: '₹999', strikeAmount: 1499, strikeDisplay: '₹1,499' },
      USD: { amount: 19, display: '$19', strikeAmount: 29, strikeDisplay: '$29' },
      strikeEnabled: true
    },
    team: {
      INR: { amount: 3499, display: '₹3,499', strikeAmount: 4999, strikeDisplay: '₹4,999' },
      USD: { amount: 69, display: '$69', strikeAmount: 99, strikeDisplay: '$99' },
      strikeEnabled: true
    }
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
        strikethrough: {
          ...currentPricing.strikethrough,
          ...(parsed.strikethrough || {}),
          single: { ...currentPricing.strikethrough.single, ...(parsed.strikethrough?.single || {}) },
          universal: { ...currentPricing.strikethrough.universal, ...(parsed.strikethrough?.universal || {}) },
          team: { ...currentPricing.strikethrough.team, ...(parsed.strikethrough?.team || {}) }
        },
        countdown: { ...currentPricing.countdown, ...(parsed.countdown || {}) },
        devicesPerLicense: Number(parsed.devicesPerLicense || parsed.devices || currentPricing.devicesPerLicense || 3)
      };
    }
  }
} catch (e) {}

let cachedPasscode = null;

function getAdminSecret() {
  if (cachedPasscode) return cachedPasscode;
  try {
    const tmpPass = path.join('/tmp', 'dropdial_admin_pass.txt');
    if (fs.existsSync(tmpPass)) {
      const p = fs.readFileSync(tmpPass, 'utf8').trim();
      if (p) { cachedPasscode = p; return p; }
    }
  } catch (_) {}

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
            },
            devicesPerLicense: Math.max(1, Math.min(100, Number(val.devicesPerLicense || val.devices || currentPricing.devicesPerLicense || 3)))
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

      const strikeSingleEnabled = body.strikeSingleEnabled !== undefined ? !!body.strikeSingleEnabled : (currentPricing.strikethrough?.single?.enabled ?? true);
      const strikeSingleInr = Number(body.strikeSingleInr) > 0 ? Number(body.strikeSingleInr) : (currentPricing.strikethrough?.single?.inrAmount || 1199);
      const strikeSingleUsd = Number(body.strikeSingleUsd) > 0 ? Number(body.strikeSingleUsd) : (currentPricing.strikethrough?.single?.usdAmount || 24);

      const strikeTeamEnabled = body.strikeTeamEnabled !== undefined ? !!body.strikeTeamEnabled : (currentPricing.strikethrough?.team?.enabled ?? true);
      const strikeTeamInr = Number(body.strikeTeamInr) > 0 ? Number(body.strikeTeamInr) : (currentPricing.strikethrough?.team?.inrAmount || 4999);
      const strikeTeamUsd = Number(body.strikeTeamUsd) > 0 ? Number(body.strikeTeamUsd) : (currentPricing.strikethrough?.team?.usdAmount || 99);

      const countdownEnabled = body.countdownEnabled !== undefined ? (body.countdownEnabled === true || body.countdownEnabled === 'true') : false;
      const countdownValue = Number(body.countdownValue) > 0 ? Number(body.countdownValue) : (currentPricing.countdown?.value || 24);
      const countdownUnit = (body.countdownUnit === 'days') ? 'days' : 'hours';
      const countdownLabel = (body.countdownLabel || currentPricing.countdown?.label || 'Special Launch Discount Ends In:').trim();
      const countdownReset = !!body.countdownReset;

      const devicesPerLicense = Math.max(1, Math.min(100, Number(body.devicesPerLicense || body.devices || currentPricing.devicesPerLicense || 3)));

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

      const singleInr = Number(body.singleInr || body.tiers?.single?.INR?.amount || 799);
      const singleUsd = Number(body.singleUsd || body.tiers?.single?.USD?.amount || 15);
      const universalInr = inrAmount || Number(body.universalInr || body.tiers?.universal?.INR?.amount || 999);
      const universalUsd = usdAmount || Number(body.universalUsd || body.tiers?.universal?.USD?.amount || 19);
      const teamInr = Number(body.teamInr || body.tiers?.team?.INR?.amount || 3499);
      const teamUsd = Number(body.teamUsd || body.tiers?.team?.USD?.amount || 69);

      const tiersConfig = {
        single: {
          INR: {
            amount: singleInr,
            display: `₹${singleInr.toLocaleString('en-IN')}`,
            strikeAmount: strikeSingleInr,
            strikeDisplay: `₹${strikeSingleInr.toLocaleString('en-IN')}`
          },
          USD: {
            amount: singleUsd,
            display: `$${singleUsd}`,
            strikeAmount: strikeSingleUsd,
            strikeDisplay: `$${strikeSingleUsd}`
          },
          strikeEnabled: strikeSingleEnabled
        },
        universal: {
          INR: {
            amount: universalInr,
            display: `₹${universalInr.toLocaleString('en-IN')}`,
            strikeAmount: strikeInr,
            strikeDisplay: `₹${strikeInr.toLocaleString('en-IN')}`
          },
          USD: {
            amount: universalUsd,
            display: `$${universalUsd}`,
            strikeAmount: strikeUsd,
            strikeDisplay: `$${strikeUsd}`
          },
          strikeEnabled: strikeEnabled
        },
        team: {
          INR: {
            amount: teamInr,
            display: `₹${teamInr.toLocaleString('en-IN')}`,
            strikeAmount: strikeTeamInr,
            strikeDisplay: `₹${strikeTeamInr.toLocaleString('en-IN')}`
          },
          USD: {
            amount: teamUsd,
            display: `$${teamUsd}`,
            strikeAmount: strikeTeamUsd,
            strikeDisplay: `$${strikeTeamUsd}`
          },
          strikeEnabled: strikeTeamEnabled
        }
      };

      currentPricing = {
        INR: {
          amount: universalInr,
          subunits: Math.round(universalInr * 100),
          symbol: '₹',
          display: `₹${universalInr.toLocaleString('en-IN')}`,
          strikeAmount: strikeInr,
          strikeDisplay: `₹${strikeInr.toLocaleString('en-IN')}`,
          label: 'India Standard'
        },
        USD: {
          amount: universalUsd,
          subunits: Math.round(universalUsd * 100),
          symbol: '$',
          display: `$${universalUsd}`,
          strikeAmount: strikeUsd,
          strikeDisplay: `$${strikeUsd}`,
          label: 'Global Standard'
        },
        strikethrough: {
          enabled: strikeEnabled,
          inrAmount: strikeInr,
          usdAmount: strikeUsd,
          single: {
            enabled: strikeSingleEnabled,
            inrAmount: strikeSingleInr,
            usdAmount: strikeSingleUsd
          },
          universal: {
            enabled: strikeEnabled,
            inrAmount: strikeInr,
            usdAmount: strikeUsd
          },
          team: {
            enabled: strikeTeamEnabled,
            inrAmount: strikeTeamInr,
            usdAmount: strikeTeamUsd
          }
        },
        countdown: {
          enabled: countdownEnabled,
          value: countdownValue,
          unit: countdownUnit,
          label: countdownLabel,
          expiresAt: expiresAt
        },
        devicesPerLicense: devicesPerLicense,
        tiers: tiersConfig,
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
        message: `Live prices, device limit (${devicesPerLicense} devices), strikethrough, and countdown timer updated across checkout and landing page!`,
        pricing: currentPricing
      });
    } catch (err) {
      return res.status(500).json({ error: err.message });
    }
  }

  return res.status(405).json({ error: 'Method Not Allowed' });
};

module.exports.getActivePricing = getActivePricing;
