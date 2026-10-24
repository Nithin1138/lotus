/**
 * DropDial Payment Gateway Routing & Configuration
 * Supports dynamic switching between Dodo Payments and Razorpay
 * for both Domestic (India / INR) and International (Worldwide / USD) buyers.
 *
 * Persisted in Neon PostgreSQL (app_settings) with /tmp and in-memory cache fallbacks.
 */

const fs = require('fs');
const path = require('path');

const SETTINGS_FILE = path.join('/tmp', 'dropdial_payment_settings.json');

// Default initial configuration:
// Dodo Payments handles all transactions initially while Razorpay account onboarding is in progress.
const DEFAULT_PAYMENT_SETTINGS = {
  mode: 'dodo_all', // 'dodo_all' | 'razorpay_all' | 'split' | 'custom'
  indiaGateway: 'dodo', // 'dodo' or 'razorpay'
  intlGateway: 'dodo', // 'dodo' or 'razorpay'
  dodoEnabled: true,
  razorpayEnabled: false,
  autoFallback: true, // Automatically fall back to configured gateway if selected has missing keys
  notes: 'Dodo Payments handles all transactions until Razorpay account is activated.',
  updatedAt: new Date().toISOString()
};

let cachedSettings = null;
let lastCacheTime = 0;
const CACHE_TTL_MS = 15000; // 15 seconds in-memory cache

/**
 * Checks environment variables for Dodo Payments and Razorpay configuration
 */
function getEnvStatus() {
  const dodoKey = (process.env.DODO_PAYMENTS_API_KEY || '').trim();
  const dodoWebhookKey = (process.env.DODO_PAYMENTS_WEBHOOK_KEY || process.env.DODO_WEBHOOK_SECRET || '').trim();
  const dodoProduct = (process.env.DODO_PRODUCT_UNIVERSAL || process.env.DODO_PRODUCT_ID || '').trim();
  const razorpayKey = (process.env.RAZORPAY_KEY_ID || '').trim();
  const razorpaySecret = (process.env.RAZORPAY_KEY_SECRET || '').trim();
  const razorpayWebhook = (process.env.RAZORPAY_WEBHOOK_SECRET || '').trim();

  return {
    dodoConfigured: Boolean(dodoKey && dodoProduct),
    dodoKeyPrefix: dodoKey ? dodoKey.slice(0, 8) + '...' : null,
    dodoMode: dodoKey.startsWith('test_') ? 'test' : dodoKey ? 'live' : 'unconfigured',
    dodoWebhookConfigured: Boolean(dodoWebhookKey),
    dodoProductConfigured: Boolean(dodoProduct),
    razorpayConfigured: Boolean(razorpayKey && razorpaySecret),
    razorpayKeyPrefix: razorpayKey ? razorpayKey.slice(0, 8) + '...' : null,
    razorpayWebhookConfigured: Boolean(razorpayWebhook)
  };
}

/**
 * Reads payment gateway settings from Neon DB, /tmp, or defaults
 */
async function getPaymentSettings(sql) {
  const now = Date.now();
  if (cachedSettings && (now - lastCacheTime < CACHE_TTL_MS)) {
    return { ...cachedSettings, envStatus: getEnvStatus() };
  }

  // 1. Try reading from filesystem cache
  let fileSettings = null;
  try {
    if (fs.existsSync(SETTINGS_FILE)) {
      const raw = fs.readFileSync(SETTINGS_FILE, 'utf8');
      fileSettings = JSON.parse(raw);
    }
  } catch (_) {}

  // 2. Try reading from Neon Postgres app_settings table
  let dbSettings = null;
  if (sql) {
    try {
      const rows = await sql`SELECT value FROM app_settings WHERE key = 'payment_settings' LIMIT 1;`;
      if (rows && rows.length > 0 && rows[0].value) {
        let val = rows[0].value;
        if (typeof val === 'string') {
          try { val = JSON.parse(val); } catch (_) {}
        }
        if (typeof val === 'object' && val !== null) {
          dbSettings = val;
        }
      }
    } catch (dbErr) {
      console.warn('[Payment Settings DB Read Warning]:', dbErr.message);
    }
  }

  // Combine defaults -> file -> db
  const merged = {
    ...DEFAULT_PAYMENT_SETTINGS,
    ...(fileSettings || {}),
    ...(dbSettings || {})
  };

  // Ensure validity
  if (!['dodo', 'razorpay'].includes(merged.indiaGateway)) merged.indiaGateway = 'dodo';
  if (!['dodo', 'razorpay'].includes(merged.intlGateway)) merged.intlGateway = 'dodo';
  if (!['dodo_all', 'razorpay_all', 'split', 'custom'].includes(merged.mode)) {
    if (merged.indiaGateway === 'dodo' && merged.intlGateway === 'dodo') merged.mode = 'dodo_all';
    else if (merged.indiaGateway === 'razorpay' && merged.intlGateway === 'razorpay') merged.mode = 'razorpay_all';
    else if (merged.indiaGateway === 'razorpay' && merged.intlGateway === 'dodo') merged.mode = 'split';
    else merged.mode = 'custom';
  }

  cachedSettings = merged;
  lastCacheTime = now;

  // Persist to /tmp if changed
  try {
    fs.writeFileSync(SETTINGS_FILE, JSON.stringify(merged, null, 2), 'utf8');
  } catch (_) {}

  return { ...merged, envStatus: getEnvStatus() };
}

/**
 * Saves updated payment gateway settings to Neon DB and /tmp cache
 */
async function savePaymentSettings(updates = {}, sql) {
  const current = await getPaymentSettings(sql);

  const rawIndia = updates.indiaGateway || updates.india;
  const rawIntl = updates.intlGateway || updates.intl || updates.international;

  const indiaGateway = rawIndia === 'razorpay' ? 'razorpay' : 'dodo';
  const intlGateway = rawIntl === 'razorpay' ? 'razorpay' : 'dodo';

  let mode = updates.mode;
  if (!mode) {
    if (indiaGateway === 'dodo' && intlGateway === 'dodo') mode = 'dodo_all';
    else if (indiaGateway === 'razorpay' && intlGateway === 'razorpay') mode = 'razorpay_all';
    else if (indiaGateway === 'razorpay' && intlGateway === 'dodo') mode = 'split';
    else mode = 'custom';
  }

  const merged = {
    ...current,
    ...updates,
    indiaGateway,
    intlGateway,
    mode,
    dodoEnabled: updates.dodoEnabled !== undefined ? Boolean(updates.dodoEnabled) : (indiaGateway === 'dodo' || intlGateway === 'dodo'),
    razorpayEnabled: updates.razorpayEnabled !== undefined ? Boolean(updates.razorpayEnabled) : (indiaGateway === 'razorpay' || intlGateway === 'razorpay'),
    autoFallback: updates.autoFallback !== undefined ? Boolean(updates.autoFallback) : true,
    updatedAt: new Date().toISOString()
  };

  // Remove envStatus from persistence payload
  delete merged.envStatus;

  // 1. Write to Neon DB
  if (sql) {
    try {
      await sql`
        INSERT INTO app_settings (key, value, updated_at)
        VALUES ('payment_settings', ${JSON.stringify(merged)}, NOW())
        ON CONFLICT (key) DO UPDATE
        SET value = EXCLUDED.value, updated_at = NOW();
      `;
    } catch (dbErr) {
      console.warn('[Payment Settings DB Save Warning]:', dbErr.message);
    }
  }

  // 2. Write to filesystem /tmp cache
  try {
    fs.writeFileSync(SETTINGS_FILE, JSON.stringify(merged, null, 2), 'utf8');
  } catch (_) {}

  // 3. Update memory cache
  cachedSettings = merged;
  lastCacheTime = Date.now();

  return { ...merged, envStatus: getEnvStatus() };
}

/**
 * Resolves the active gateway for a checkout session.
 * Handles auto-fallback if the chosen gateway lacks credentials.
 */
async function resolveActiveGateway({ isIndia = false, requestedGateway = null, sql = null } = {}) {
  const settings = await getPaymentSettings(sql);
  const env = settings.envStatus;

  // 1. Explicit request override if provided and allowed
  if (requestedGateway === 'dodo' || requestedGateway === 'razorpay') {
    return requestedGateway;
  }

  // 2. Gateway selected by region in Admin
  let target = isIndia ? settings.indiaGateway : settings.intlGateway;

  // 3. Auto-fallback logic:
  // If user selected Razorpay, but Razorpay is not configured (account pending)
  // and Dodo is configured, safely route to Dodo so orders never fail!
  if (settings.autoFallback) {
    if (target === 'razorpay' && !env.razorpayConfigured && env.dodoConfigured) {
      console.log(`[Payment Routing] Razorpay selected for ${isIndia ? 'India' : 'Intl'}, but credentials pending. Auto-falling back to Dodo Payments.`);
      return 'dodo';
    }
    if (target === 'dodo' && !env.dodoConfigured && env.razorpayConfigured) {
      console.log(`[Payment Routing] Dodo selected for ${isIndia ? 'India' : 'Intl'}, but credentials missing. Auto-falling back to Razorpay.`);
      return 'razorpay';
    }
  }

  return target;
}

module.exports = {
  DEFAULT_PAYMENT_SETTINGS,
  getEnvStatus,
  getPaymentSettings,
  savePaymentSettings,
  resolveActiveGateway
};
