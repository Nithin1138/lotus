/**
 * DropDial Public Payment Configuration Gateway
 * GET /api/payment-config
 * Returns active gateway configuration (India vs International) for checkout clients.
 */

const { getPaymentSettings } = require('./_paymentSettings');
const { getDb } = require('./_db');

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Cache-Control', 'public, s-maxage=30, stale-while-revalidate=120');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  try {
    const sql = getDb();
    const settings = await getPaymentSettings(sql);

    // Detect user country if headers present
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
};
