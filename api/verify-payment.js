/**
 * Vercel Serverless Function: Verify Razorpay Payment & Deliver License
 * POST /api/verify-payment
 */

const { generateLicense, sendResendEmail, sendPaymentFailedEmail, verifyRazorpayPaymentSignature } = require('./_utils');
const { incrementCouponUses } = require('./coupons');

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

    // Handle payment-failed notifications (e.g. POST /api/payment-failed)
    const isPaymentFailed = req.query?.action === 'payment-failed' || body.action === 'payment-failed' || (req.url && req.url.includes('payment-failed'));
    if (isPaymentFailed) {
      const { email: failEmail, name: failName, reason, amount, currency } = body;
      if (!failEmail || !failEmail.includes('@')) {
        return res.status(400).json({ error: 'Valid email address is required' });
      }
      const result = await sendPaymentFailedEmail({
        to: failEmail.trim().toLowerCase(),
        name: (failName || 'DropDial Pro User').trim(),
        reason: reason || 'Transaction was declined by the bank or gateway',
        amount: amount || '',
        currency: currency || 'USD'
      });
      return res.status(200).json({
        success: result.success !== false,
        message: 'Payment failed email dispatched',
        id: result.id
      });
    }
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

    const rawTier = (body.tier || 'universal').toLowerCase();
    const cleanTier = rawTier.includes('single') ? 'single'
      : rawTier.includes('team') ? 'team'
      : 'universal';

    // 1. Generate Cryptographically Signed License Key (ECDSA P-256)
    const licenseKey = generateLicense(email, name, cleanTier);

    // 2. Persist to Neon DB (if configured)
    try {
      const { getDb, ensureSchema } = require('./_db');
      const sql = getDb();
      if (sql) {
        await ensureSchema();
        const licId = `lic_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
        await sql`
          INSERT INTO licenses (id, customer_name, email, license_key, tier, status, created_at)
          VALUES (${licId}, ${name}, ${email}, ${licenseKey}, ${cleanTier}, 'active', NOW())
          ON CONFLICT (id) DO NOTHING;
        `;
        const txAmount = Number(body.amount) || (body.currency === 'USD' ? 19 : 999);
        const txCurrency = (body.currency || (txAmount > 100 ? 'INR' : 'USD')).toUpperCase();
        const txCountry = body.country || (txCurrency === 'INR' ? 'IN' : 'US');
        const txCoupon = body.couponCode || null;

        if (razorpay_payment_id) {
          const txId = `tx_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
          await sql`
            INSERT INTO transactions (id, order_id, payment_id, amount, currency, customer_name, email, status, coupon_code, country, created_at)
            VALUES (${txId}, ${razorpay_order_id || 'manual'}, ${razorpay_payment_id}, ${txAmount}, ${txCurrency}, ${name}, ${email}, 'captured', ${txCoupon}, ${txCountry}, NOW())
            ON CONFLICT (id) DO NOTHING;
          `;

          if (txCoupon) {
            try {
              await sql`
                UPDATE coupons
                SET uses = COALESCE(uses, 0) + 1
                WHERE UPPER(code) = UPPER(${txCoupon});
              `;
            } catch (cErr) {
              console.warn('[Coupon DB Increment Warning]:', cErr.message);
            }
          }
        }
      }
    } catch (dbErr) {
      console.warn('[Verify Payment Neon DB Warning]:', dbErr.message);
    }

    if (body.couponCode && typeof incrementCouponUses === 'function') {
      try {
        incrementCouponUses(body.couponCode);
      } catch (_) {}
    }

    // 3. Send Delivery Email via Resend
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
