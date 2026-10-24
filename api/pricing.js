/**
 * DropDial Dynamic Pricing Gateway
 * GET /api/pricing - Returns active pricing for India and Worldwide
 * POST /api/pricing - Updates live pricing in memory & Neon DB (Admin authenticated)
 */

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// Default Base Pricing with 3-tier individual strikethroughs
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
    label: 'First 24-Hours Deal: 10% Off All Plans with code FIRST24',
    discountPercent: 10,
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
          enabled: parsed.strikethrough?.enabled !== undefined ? !!parsed.strikethrough.enabled : currentPricing.strikethrough.enabled,
          single: {
            ...currentPricing.strikethrough.single,
            ...(parsed.strikethrough?.single || {}),
            enabled: parsed.strikethrough?.single?.enabled !== undefined ? !!parsed.strikethrough.single.enabled : currentPricing.strikethrough.single.enabled
          },
          universal: {
            ...currentPricing.strikethrough.universal,
            ...(parsed.strikethrough?.universal || {}),
            enabled: parsed.strikethrough?.universal?.enabled !== undefined ? !!parsed.strikethrough.universal.enabled : currentPricing.strikethrough.universal.enabled
          },
          team: {
            ...currentPricing.strikethrough.team,
            ...(parsed.strikethrough?.team || {}),
            enabled: parsed.strikethrough?.team?.enabled !== undefined ? !!parsed.strikethrough.team.enabled : currentPricing.strikethrough.team.enabled
          }
        },
        countdown: { ...currentPricing.countdown, ...(parsed.countdown || {}) },
        devicesPerLicense: Number(parsed.devicesPerLicense || parsed.devices || currentPricing.devicesPerLicense || 3)
      };
    }
  }
} catch (e) {}

let cachedPasscode = null;

async function getAdminSecret(sql) {
  if (cachedPasscode) return cachedPasscode;
  try {
    const tmpPass = path.join('/tmp', 'dropdial_admin_pass.txt');
    if (fs.existsSync(tmpPass)) {
      const p = fs.readFileSync(tmpPass, 'utf8').trim();
      if (p) { cachedPasscode = p; return p; }
    }
  } catch (_) {}

  if (sql) {
    try {
      const rows = await sql`SELECT value FROM app_settings WHERE key = 'admin_passcode' LIMIT 1;`;
      if (rows && rows.length > 0 && rows[0].value) {
        let val = rows[0].value;
        if (typeof val === 'string') {
          try { val = JSON.parse(val); } catch (_) {}
        }
        if (typeof val === 'string' && val.trim()) {
          cachedPasscode = val.trim();
          return cachedPasscode;
        }
      }
    } catch (e) {}
  }

  return (
    process.env.ADMIN_KEY ||
    process.env.ADMIN_PASSWORD ||
    process.env.LICENSE_SECRET ||
    'dropdial2026'
  ).trim();
}

function safeCompare(aStr, bStr) {
  if (!aStr || !bStr) return false;
  try {
    const a = Buffer.from(aStr, 'utf8');
    const b = Buffer.from(bStr, 'utf8');
    if (a.length !== b.length) return false;
    return crypto.timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

async function verifyAdminToken(req, sql) {
  const authHeader = req.headers['authorization'] || '';
  const queryToken = req.query?.token || '';
  const bodyToken = req.body?.token || '';
  const bodyPasscode = req.body?.passcode || req.body?.adminPasscode || '';
  const headerToken = req.headers['x-admin-key'] || '';

  let provided = '';
  if (authHeader.startsWith('Bearer ')) {
    provided = authHeader.slice(7).trim();
  } else if (headerToken) {
    provided = headerToken.trim();
  } else if (bodyToken) {
    provided = bodyToken.trim();
  } else if (bodyPasscode) {
    provided = bodyPasscode.trim();
  } else if (queryToken) {
    provided = queryToken.trim();
  }

  try {
    provided = decodeURIComponent(provided);
  } catch (_) {}

  if (!provided) return false;

  const expected = await getAdminSecret(sql);
  const fallback = (process.env.ADMIN_KEY || process.env.ADMIN_PASSWORD || process.env.LICENSE_SECRET || 'dropdial2026').trim();

  // Accept if it matches active dynamic passcode OR default environment fallback
  return safeCompare(provided, expected) || safeCompare(provided, fallback);
}

function getActivePricing() {
  return currentPricing;
}

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, x-admin-key');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const queryAction = ((req.query && req.query.action) || '').toLowerCase();
  const reqUrl = req.url || '';
  if (queryAction === 'payment-config' || reqUrl.includes('payment-config')) {
    const { getPaymentSettings } = require('./_paymentSettings');
    const { getDb } = require('./_db');
    try {
      const sql = getDb();
      const settings = await getPaymentSettings(sql);
      const country = (req.headers['x-vercel-ip-country'] || req.headers['cf-ipcountry'] || '').trim().toUpperCase();
      const isIndia = country === 'IN';
      const activeGatewayForVisitor = isIndia ? settings.indiaGateway : settings.intlGateway;

      return res.status(200).json({
        success: true,
        mode: settings.mode,
        indiaGateway: settings.indiaGateway,
        intlGateway: settings.intlGateway,
        activeGateway: activeGatewayForVisitor,
        detectedCountry: country || null,
        isIndia,
        dodoConfigured: settings.envStatus.dodoConfigured,
        dodoMode: settings.envStatus.dodoMode,
        razorpayConfigured: settings.envStatus.razorpayConfigured,
        timestamp: new Date().toISOString()
      });
    } catch (err) {
      console.error('[Payment Config API Error]', err);
      return res.status(500).json({
        error: 'Failed to retrieve payment gateway configuration',
        indiaGateway: 'dodo',
        intlGateway: 'dodo'
      });
    }
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
          const rawStrike = val.strikethrough || {};
          const rawTiers = val.tiers || {};

          const singleStrikeOn = rawStrike.single?.enabled !== undefined
            ? (rawStrike.single.enabled === true)
            : (rawTiers.single?.strikeEnabled !== undefined ? (rawTiers.single.strikeEnabled === true) : currentPricing.strikethrough.single.enabled);

          const universalStrikeOn = rawStrike.universal?.enabled !== undefined
            ? (rawStrike.universal.enabled === true)
            : (rawStrike.enabled !== undefined ? (rawStrike.enabled === true) : currentPricing.strikethrough.universal.enabled);

          const teamStrikeOn = rawStrike.team?.enabled !== undefined
            ? (rawStrike.team.enabled === true)
            : (rawTiers.team?.strikeEnabled !== undefined ? (rawTiers.team.strikeEnabled === true) : currentPricing.strikethrough.team.enabled);

          currentPricing = {
            ...currentPricing,
            ...val,
            INR: { ...currentPricing.INR, ...(val.INR || {}) },
            USD: { ...currentPricing.USD, ...(val.USD || {}) },
            strikethrough: {
              ...currentPricing.strikethrough,
              ...rawStrike,
              enabled: universalStrikeOn,
              inrAmount: Number(rawStrike.inrAmount || rawStrike.universal?.inrAmount || currentPricing.strikethrough.inrAmount),
              usdAmount: Number(rawStrike.usdAmount || rawStrike.universal?.usdAmount || currentPricing.strikethrough.usdAmount),
              single: {
                ...currentPricing.strikethrough.single,
                ...(rawStrike.single || {}),
                enabled: singleStrikeOn,
                inrAmount: Number(rawStrike.single?.inrAmount || rawTiers.single?.INR?.strikeAmount || currentPricing.strikethrough.single.inrAmount),
                usdAmount: Number(rawStrike.single?.usdAmount || rawTiers.single?.USD?.strikeAmount || currentPricing.strikethrough.single.usdAmount)
              },
              universal: {
                ...currentPricing.strikethrough.universal,
                ...(rawStrike.universal || {}),
                enabled: universalStrikeOn,
                inrAmount: Number(rawStrike.universal?.inrAmount || rawStrike.inrAmount || currentPricing.strikethrough.universal.inrAmount),
                usdAmount: Number(rawStrike.universal?.usdAmount || rawStrike.usdAmount || currentPricing.strikethrough.universal.usdAmount)
              },
              team: {
                ...currentPricing.strikethrough.team,
                ...(rawStrike.team || {}),
                enabled: teamStrikeOn,
                inrAmount: Number(rawStrike.team?.inrAmount || rawTiers.team?.INR?.strikeAmount || currentPricing.strikethrough.team.inrAmount),
                usdAmount: Number(rawStrike.team?.usdAmount || rawTiers.team?.USD?.strikeAmount || currentPricing.strikethrough.team.usdAmount)
              }
            },
            tiers: {
              single: {
                ...currentPricing.tiers.single,
                ...(rawTiers.single || {}),
                strikeEnabled: singleStrikeOn
              },
              universal: {
                ...currentPricing.tiers.universal,
                ...(rawTiers.universal || {}),
                strikeEnabled: universalStrikeOn
              },
              team: {
                ...currentPricing.tiers.team,
                ...(rawTiers.team || {}),
                strikeEnabled: teamStrikeOn
              }
            },
            countdown: {
              ...currentPricing.countdown,
              ...(val.countdown || {}),
              enabled: val.countdown ? (val.countdown.enabled === true) : currentPricing.countdown.enabled,
              discountPercent: Number(val.countdown?.discountPercent || currentPricing.countdown.discountPercent || 10)
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
    const isAuthed = await verifyAdminToken(req, sql);
    if (!isAuthed) {
      return res.status(401).json({ error: 'Unauthorized: Invalid admin credentials' });
    }

    try {
      const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
      const inrAmount = Number(body.inrAmount);
      const usdAmount = Number(body.usdAmount);

      const strikeEnabled = body.strikeEnabled !== undefined
        ? (body.strikeEnabled === true || body.strikeEnabled === 'true')
        : (currentPricing.strikethrough?.enabled ?? true);
      const strikeInr = Number(body.strikeInr) > 0 ? Number(body.strikeInr) : (currentPricing.strikethrough?.inrAmount || 1499);
      const strikeUsd = Number(body.strikeUsd) > 0 ? Number(body.strikeUsd) : (currentPricing.strikethrough?.usdAmount || 29);

      const strikeSingleEnabled = body.strikeSingleEnabled !== undefined
        ? (body.strikeSingleEnabled === true || body.strikeSingleEnabled === 'true')
        : (currentPricing.strikethrough?.single?.enabled ?? true);
      const strikeSingleInr = Number(body.strikeSingleInr) > 0 ? Number(body.strikeSingleInr) : (currentPricing.strikethrough?.single?.inrAmount || 1199);
      const strikeSingleUsd = Number(body.strikeSingleUsd) > 0 ? Number(body.strikeSingleUsd) : (currentPricing.strikethrough?.single?.usdAmount || 24);

      const strikeTeamEnabled = body.strikeTeamEnabled !== undefined
        ? (body.strikeTeamEnabled === true || body.strikeTeamEnabled === 'true')
        : (currentPricing.strikethrough?.team?.enabled ?? true);
      const strikeTeamInr = Number(body.strikeTeamInr) > 0 ? Number(body.strikeTeamInr) : (currentPricing.strikethrough?.team?.inrAmount || 4999);
      const strikeTeamUsd = Number(body.strikeTeamUsd) > 0 ? Number(body.strikeTeamUsd) : (currentPricing.strikethrough?.team?.usdAmount || 99);

      const countdownEnabled = body.countdownEnabled !== undefined ? (body.countdownEnabled === true || body.countdownEnabled === 'true') : false;
      const countdownValue = Number(body.countdownValue) > 0 ? Number(body.countdownValue) : (currentPricing.countdown?.value || 24);
      const countdownUnit = (body.countdownUnit === 'days') ? 'days' : 'hours';
      const countdownDiscount = Math.max(1, Math.min(90, Number(body.countdownDiscount || body.discountPercent || currentPricing.countdown?.discountPercent || 10)));
      const countdownLabel = (body.countdownLabel || currentPricing.countdown?.label || `First 24-Hours Deal: ${countdownDiscount}% Off All Plans with code FIRST24`).trim();
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
          discountPercent: countdownDiscount,
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
          await sql`
            UPDATE coupons
            SET value = ${countdownDiscount}, description = ${`First 24-Hours Early Bird - ${countdownDiscount}% Off`}
            WHERE UPPER(code) IN ('FIRST24', 'EARLY24');
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
        message: `Live pricing updated! Strikethroughs: Single ${strikeSingleEnabled ? 'ON' : 'OFF'} • Universal ${strikeEnabled ? 'ON' : 'OFF'} • Team ${strikeTeamEnabled ? 'ON' : 'OFF'} (${devicesPerLicense} devices per key).`,
        pricing: currentPricing
      });
    } catch (err) {
      return res.status(500).json({ error: err.message });
    }
  }

  return res.status(405).json({ error: 'Method Not Allowed' });
};

module.exports.getActivePricing = getActivePricing;
