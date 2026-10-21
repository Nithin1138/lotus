/**
 * Vercel Serverless Function: Verify Razorpay Payment & Deliver License
 * POST /api/verify-payment
 */

const { generateLicense, sendResendEmail, verifyRazorpayPaymentSignature, sanitizeEmail, sanitizeName } = require('./_utils');
const { incrementCouponUses } = require('./coupons');
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

  // Rate Limiting: Max 10 verification requests per minute per IP
  const rateLimit = checkRateLimit(req, 'verify-payment', 10, 60000);
  if (!rateLimit.allowed) {
    return res.status(429).json({
      error: 'Too many verification requests. Please wait a moment.',
      retryAfterSeconds: Math.ceil(rateLimit.resetMs / 1000)
    });
  }

  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
    const {
      razorpay_order_id,
      razorpay_payment_id,
      razorpay_signature,
      tier = 'pro'
    } = body;

    const email = sanitizeEmail(body.email);
    const name = sanitizeName(body.name);

    if (!email) {
      return res.status(400).json({ error: 'A valid customer email is required.' });
    }

    const keySecret = (process.env.RAZORPAY_KEY_SECRET || '').trim();

    // Strict Signature Verification
    if (keySecret) {
      if (typeof razorpay_order_id === 'string' && razorpay_order_id.startsWith('order_mock_')) {
        return res.status(403).json({ error: 'Mock orders are not allowed in production.' });
      }

      if (!razorpay_order_id || !razorpay_payment_id || !razorpay_signature) {
        return res.status(400).json({ error: 'Missing payment signature verification parameters.' });
      }

      let isValid = false;
      try {
        isValid = verifyRazorpayPaymentSignature({
          orderId: razorpay_order_id,
          paymentId: razorpay_payment_id,
          signature: razorpay_signature
        });
      } catch (sigErr) {
        console.error('[Razorpay] Signature error:', sigErr.message);
        return res.status(400).json({ error: 'Payment signature could not be verified.' });
      }

      if (!isValid) {
        console.error('[Razorpay] Invalid payment signature verification failed for:', razorpay_payment_id);
        return res.status(400).json({ error: 'Payment signature verification failed. Transaction rejected.' });
      }
    } else {
      if (process.env.NODE_ENV === 'production') {
        return res.status(500).json({ error: 'Payment gateway configuration error. Please contact support.' });
      }
      console.log('[Verify Payment] Simulated or sandbox payment confirmation for:', email);
    }

    // 1. Generate Cryptographically Signed License Key (ECDSA P-256)
    const licenseKey = generateLicense(email, name, tier);

    // 2. Persist to Neon DB (if configured)
    try {
      const { getDb, ensureSchema } = require('./_db');
      const sql = getDb();
      if (sql) {
        await ensureSchema();
        const licId = `lic_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
        await sql`
          INSERT INTO licenses (id, customer_name, email, license_key, tier, status, created_at)
          VALUES (${licId}, ${name}, ${email}, ${licenseKey}, ${tier || 'Pro Lifetime'}, 'active', NOW())
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
