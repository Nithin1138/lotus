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

  const country = countryHeader.trim().toUpperCase();
  const isIndia = country === 'IN';

  let currentPricing = { INR: { amount: 999, display: '₹999' }, USD: { amount: 19, display: '$19' } };
  try {
    const { getActivePricing } = require('./pricing');
    if (typeof getActivePricing === 'function') {
      currentPricing = getActivePricing();
    }
  } catch (e) {}

  const activeConf = isIndia ? currentPricing.INR : currentPricing.USD;

  return res.status(200).json({
    country: country || null,
    isIndia: isIndia,
    currency: isIndia ? 'INR' : 'USD',
    amount: activeConf.amount,
    symbol: isIndia ? '₹' : '$',
    displayPrice: activeConf.display
  });
};
