/**
 * Vercel Serverless Function: Payment Failed Email Dispatcher
 * POST /api/payment-failed
 *
 * Triggered by checkout when Razorpay payment.failed occurs,
 * sending an empathetic recovery notification to the customer.
 */

const { sendPaymentFailedEmail } = require('./_utils');

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method Not Allowed' });
  }

  try {
    const { email, name, reason, amount, currency } = req.body || {};

    if (!email || !email.includes('@')) {
      return res.status(400).json({ error: 'Valid email address is required' });
    }

    console.log(`[Payment Failed API] Sending notice to ${email} (Reason: ${reason || 'declined'})`);

    const result = await sendPaymentFailedEmail({
      to: email.trim().toLowerCase(),
      name: (name || 'DropDial Pro User').trim(),
      reason: reason || 'Transaction was declined by the bank or gateway',
      amount: amount || '',
      currency: currency || 'USD'
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
