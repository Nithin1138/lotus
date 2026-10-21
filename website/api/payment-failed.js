/**
 * Vercel Serverless Function: Payment Failed Email Dispatcher
 * POST /api/payment-failed
 *
 * Triggered by checkout when Razorpay payment.failed occurs,
 * sending an empathetic recovery notification to the customer.
 */

const { sendPaymentFailedEmail, sanitizeEmail, sanitizeName } = require('./_utils');
const { checkRateLimit } = require('./_rateLimit');

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method Not Allowed' });
  }

  // Rate Limiting: Max 5 failure notices per minute per IP
  const rateLimit = checkRateLimit(req, 'payment-failed', 5, 60000);
  if (!rateLimit.allowed) {
    return res.status(429).json({
      error: 'Too many requests. Please wait.',
      retryAfterSeconds: Math.ceil(rateLimit.resetMs / 1000)
    });
  }

  try {
    const { reason, amount, currency } = req.body || {};
    const email = sanitizeEmail(req.body?.email);
    const name = sanitizeName(req.body?.name);

    if (!email) {
      return res.status(400).json({ error: 'Valid email address is required' });
    }

    const cleanReason = String(reason || 'Transaction was declined by the bank or gateway')
      .replace(/[<>]/g, '')
      .slice(0, 200);

    console.log(`[Payment Failed API] Sending notice to ${email} (Reason: ${cleanReason})`);

    const result = await sendPaymentFailedEmail({
      to: email,
      name: name,
      reason: cleanReason,
      amount: String(amount || '').replace(/[^0-9.,₹$]/g, '').slice(0, 20),
      currency: ['INR', 'USD'].includes((currency || '').toUpperCase()) ? (currency || '').toUpperCase() : 'USD'
    });

    return res.status(200).json({
      success: result.success !== false,
      message: 'Payment failed email dispatched',
      id: result.id
    });
  } catch (err) {
    console.error('[Payment Failed Endpoint Error]', err);
    return res.status(500).json({ error: err.message || 'Internal Server Error' });
  }
};
