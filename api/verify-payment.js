/**
 * Vercel Serverless Function: Verify Razorpay Payment & Deliver License
 * POST /api/verify-payment
 */

const { generateLicense, sendResendEmail, verifyRazorpayPaymentSignature } = require('./_utils');

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
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
    const {
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature,
      email,
      name = 'DropDial Customer',
      tier = 'pro'
    } = body;

    if (!email || !email.includes('@')) {
      return res.status(400).json({ error: 'Customer email is required.' });
    }

    const keySecret = (process.env.RAZORPAY_KEY_SECRET || '').trim();

    // Signature Verification
    if (keySecret && !razorpay_order_id?.startsWith('order_mock_')) {
      if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
        return res.status(400).json({ error: 'Missing payment signature verification parameters.' });
      }

      const isValid = verifyRazorpayPaymentSignature({
        orderId: razorpay_order_id,
        paymentId: razorpay_payment_id,
        signature: razorpay_signature
      });

      if (!isValid) {
        console.error('[Razorpay] Invalid payment signature verification failed for:', razorpay_payment_id);
        return res.status(400).json({ error: 'Payment signature verification failed.' });
      }
    } else {
      console.log('[Verify Payment] Simulated or sandbox payment confirmation for:', email);
    }

    // 1. Generate Cryptographically Signed License Key (ECDSA P-256)
    const licenseKey = generateLicense(email, name, tier);

    // 2. Send Delivery Email via Resend
    let emailResult = { success: false };
    try {
      emailResult = await sendResendEmail({
        to: email,
        name,
        licenseKey,
        paymentId: razorpay_payment_id || 'manual'
      });
    } catch (emailErr) {
      console.error('[Verify Payment] Resend email delivery warning:', emailErr);
    }

    return res.status(200).json({
      success: true,
      licenseKey,
      email,
      name,
      emailSent: emailResult.success,
      emailId: emailResult.id || null,
      message: 'License key successfully generated and activated!'
    });
  } catch (err) {
    console.error('[verify-payment Error]', err);
    return res.status(500).json({ error: err.message || 'Failed to verify payment and issue license.' });
  }
};
