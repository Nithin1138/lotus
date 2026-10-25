/**
 * Vercel Serverless Function: Detect Client Country & Pricing
 * GET /api/geo
 */

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Cache-Control', 'public, max-age=3600');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // 1. Check for manual testing or explicit query parameters (?currency=USD or ?country=US)
  const qCountry = (req.query?.country || '').trim().toUpperCase();
  const qCurrency = (req.query?.currency || '').trim().toUpperCase();

  // 2. Detect country from Vercel / Cloudflare edge headers
  const countryHeader = (req.headers['x-vercel-ip-country'] ||
                        req.headers['cf-ipcountry'] ||
                        req.headers['x-country-code'] ||
                        '').trim().toUpperCase();

  let country = qCountry || countryHeader;
  let isIndia = false;

  if (qCurrency === 'USD' || (qCountry && qCountry !== 'IN')) {
    isIndia = false;
    country = qCountry || (countryHeader && countryHeader !== 'IN' ? countryHeader : 'US');
  } else if (qCurrency === 'INR' || qCountry === 'IN') {
    isIndia = true;
    country = 'IN';
  } else if (countryHeader && countryHeader !== 'XX' && countryHeader !== 'T1' && countryHeader !== 'UNKNOWN') {
    // Authoritative edge detection from Vercel / Cloudflare
    // If the edge header is IN, user is in India.
    // If edge header is ANY other country (US, GB, CA, DE, AU, etc.), user is OUTSIDE India!
    isIndia = (countryHeader === 'IN');
    country = countryHeader;
  } else {
    // Only if edge header is completely absent (e.g. localhost dev)
    const tz = (req.query?.tz || '').toLowerCase();
    const offset = req.query?.offset;
    const acceptLang = (req.headers['accept-language'] || '').toLowerCase();

    const tzIsIndia = tz.includes('kolkata') || tz.includes('calcutta') || offset === '-330' || offset === -330;
    const langIsIndia = acceptLang.includes('en-in') || acceptLang.includes('hi-in') || acceptLang.includes('hi,');

    if (tzIsIndia || langIsIndia) {
      isIndia = true;
      country = 'IN';
    } else {
      isIndia = false;
      country = 'US';
    }
  }

  let currentPricing = {
    INR: { amount: 999, symbol: '₹', display: '₹999', strikeAmount: 1499, strikeDisplay: '₹1,499' },
    USD: { amount: 29, symbol: '$', display: '$29', strikeAmount: 39, strikeDisplay: '$39' },
    strikethrough: { enabled: true, inrAmount: 1499, usdAmount: 39 },
    countdown: { enabled: true, value: 24, unit: 'hours', discountPercent: 10, label: 'First 24-Hours Deal: 10% Off All Plans with code FIRST24' }
  };

  try {
    const { getDb } = require('./_db');
    const sql = getDb();
    if (sql) {
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
              enabled: val.countdown ? (val.countdown.enabled === true) : false,
              discountPercent: Number(val.countdown?.discountPercent || currentPricing.countdown.discountPercent || 10)
            }
          };
        }
      }
    }
  } catch (e) {}

  const activeConf = isIndia ? currentPricing.INR : currentPricing.USD;

  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  return res.status(200).json({
    country: country || (isIndia ? 'IN' : 'US'),
    isIndia: isIndia,
    currency: isIndia ? 'INR' : 'USD',
    amount: activeConf.amount,
    symbol: activeConf.symbol || (isIndia ? '₹' : '$'),
    displayPrice: activeConf.display,
    strikeAmount: activeConf.strikeAmount,
    strikeDisplayPrice: activeConf.strikeDisplay,
    strikethrough: currentPricing.strikethrough,
    countdown: currentPricing.countdown
  });
};
