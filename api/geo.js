/**
 * Vercel Serverless Function: Detect Client Country & Pricing
 * GET /api/geo
 */

module.exports = function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Cache-Control', 'public, max-age=3600');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  // Detect country from Vercel / Cloudflare edge headers
  const countryHeader = req.headers['x-vercel-ip-country'] ||
                        req.headers['cf-ipcountry'] ||
                        req.headers['x-country-code'] ||
                        '';

  let country = countryHeader.trim().toUpperCase();
  let isIndia = country === 'IN';

  // Fallback heuristic if edge country header is unavailable or local
  if (!isIndia && (!country || country === 'XX' || country === 'T1' || country === 'UNKNOWN' || country === 'US')) {
    const tz = (req.query?.tz || '').toLowerCase();
    const offset = req.query?.offset;
    const acceptLang = (req.headers['accept-language'] || '').toLowerCase();

    const tzIsIndia = tz.includes('kolkata') || tz.includes('calcutta') || offset === '-330' || offset === -330;
    const langIsIndia = acceptLang.includes('en-in') || acceptLang.includes('hi-in') || acceptLang.includes('hi,');

    // If client timezone or locale clearly denotes India, set isIndia to true
    if (tzIsIndia || langIsIndia) {
      isIndia = true;
      country = 'IN';
    }
  }

  let currentPricing = {
    INR: { amount: 999, symbol: '₹', display: '₹999', strikeAmount: 1499, strikeDisplay: '₹1,499' },
    USD: { amount: 19, symbol: '$', display: '$19', strikeAmount: 29, strikeDisplay: '$29' },
    strikethrough: { enabled: true, inrAmount: 1499, usdAmount: 29 },
    countdown: { enabled: true, value: 24, unit: 'hours', label: 'Special Launch Discount Ends In:' }
  };

  try {
    const { getActivePricing } = require('./pricing');
    if (typeof getActivePricing === 'function') {
      currentPricing = getActivePricing();
    }
  } catch (e) {}

  const activeConf = isIndia ? currentPricing.INR : currentPricing.USD;

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
