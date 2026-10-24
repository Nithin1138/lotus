/**
 * DropDial Unified Webhook Gateway
 * POST /api/webhooks
 *
 * Handles incoming webhooks from:
 * 1. Razorpay (/api/razorpay-webhook or ?provider=razorpay or x-razorpay-signature)
 * 2. Dodo Payments (/api/dodo-webhook or ?provider=dodo or webhook-signature)
 */

const dodoHandler = require('./_dodoWebhook');
const razorpayHandler = require('./_razorpayWebhook');

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method Not Allowed' });
  }

  const provider = (req.query?.provider || '').toLowerCase();
  const url = req.url || '';

  // 1. Explicit provider query or path route
  if (provider === 'dodo' || url.includes('dodo')) {
    return await dodoHandler(req, res);
  }
  if (provider === 'razorpay' || url.includes('razorpay')) {
    return await razorpayHandler(req, res);
  }

  // 2. Cryptographic signature header detection
  if (req.headers['x-razorpay-signature']) {
    return await razorpayHandler(req, res);
  }
  if (req.headers['webhook-id'] || req.headers['webhook-signature'] || req.headers['webhook-timestamp']) {
    return await dodoHandler(req, res);
  }

  // 3. Payload sniffing fallback
  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
    if (body.event && (body.event.startsWith('payment.') || body.event.startsWith('order.'))) {
      return await razorpayHandler(req, res);
    }
    if (body.type && (body.type.startsWith('payment.') || body.type.startsWith('checkout.'))) {
      return await dodoHandler(req, res);
    }
  } catch (_) {}

  // Default fallback
  console.warn('[Webhooks Dispatcher] Could not unequivocally determine provider; defaulting to Razorpay handler');
  return await razorpayHandler(req, res);
};
