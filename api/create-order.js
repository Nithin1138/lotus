/**
 * Vercel Serverless Function: Create Razorpay Order
 * POST /api/create-order
 * Enforces server-side country pricing and coupon code discounts.
 */

const { evaluateCoupon } = require('./coupons');

module.exports = async function handler(req, res) {
  // CORS & Methods
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
    const email = (body.email || '').trim().toLowerCase();
    const name = (body.name || 'DropDial Customer').trim();
    const couponCode = (body.couponCode || '').trim();

    // Determine country & strictly lock price according to location:
    // India: ₹999 (99900 paise INR)
    // Any other country: $19 (1900 cents USD)
    const vercelCountry = (req.headers['x-vercel-ip-country'] || req.headers['cf-ipcountry'] || req.headers['x-country-code'] || '').toUpperCase();
    const clientCountry = (body.country || '').toUpperCase();
    const country = vercelCountry || clientCountry;

    if (!email || !email.includes('@')) {
      return res.status(400).json({ error: 'A valid email address is required to receive your license key.' });
    }

    const isIndia = country === 'IN' || (!country && (body.currency || '').toUpperCase() === 'INR');
    const currency = isIndia ? 'INR' : 'USD';
    let amountInSubunits = isIndia ? 99900 : 1900;
    let appliedCoupon = null;

    // Apply coupon discount if provided
    if (couponCode) {
      try {
        const evalResult = evaluateCoupon(couponCode, currency, amountInSubunits);
        if (evalResult.valid) {
          amountInSubunits = evalResult.finalSubunits;
          appliedCoupon = {
            code: evalResult.code,
            discountSubunits: evalResult.discountSubunits,
            discountDisplay: evalResult.discountDisplay,
            finalDisplay: evalResult.finalDisplay
          };
        }
      } catch (couponErr) {
        console.warn('[Coupon Evaluation Warning]', couponErr);
      }
    }

    const keyId = (process.env.RAZORPAY_KEY_ID || '').trim();
    const keySecret = (process.env.RAZORPAY_KEY_SECRET || '').trim();

    if (!keyId || !keySecret) {
      console.warn('[Razorpay] RAZORPAY_KEY_ID or RAZORPAY_KEY_SECRET is not configured. Running in sandbox test mode.');
      return res.status(200).json({
        orderId: `order_mock_${Date.now()}`,
        amount: amountInSubunits,
        currency,
        keyId: keyId || 'rzp_test_placeholder',
        sandbox: true,
        coupon: appliedCoupon,
        message: 'Running in sandbox mode. Set RAZORPAY_KEY_ID and RAZORPAY_KEY_SECRET in Vercel to activate live payments.'
      });
    }

    const auth = Buffer.from(`${keyId}:${keySecret}`).toString('base64');
    const response = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        'Authorization': `Basic ${auth}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        amount: amountInSubunits,
        currency,
        receipt: `dd_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`,
        notes: {
          email,
          name,
          product: 'DropDial Pro Lifetime',
          coupon: appliedCoupon ? appliedCoupon.code : 'none',
          discount: appliedCoupon ? appliedCoupon.discountDisplay : 'none'
        }
      })
    });

    const data = await response.json();
    if (!response.ok) {
      console.error('[Razorpay Order Creation Failed]', data);
      return res.status(500).json({ error: data.error?.description || 'Failed to create payment order.' });
    }

    return res.status(200).json({
      orderId: data.id,
      amount: data.amount,
      currency: data.currency,
      keyId,
      notes: data.notes,
      coupon: appliedCoupon
    });
  } catch (err) {
    console.error('[create-order Error]', err);
    return res.status(500).json({ error: err.message || 'Internal Server Error' });
  }
};
