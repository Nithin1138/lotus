/**
 * Vercel Serverless Function: Create Razorpay Order
 * POST /api/create-order
 * Enforces server-side country pricing and coupon code discounts.
 */

const { evaluateCoupon, evaluateCouponAsync } = require('./coupons');
const { sanitizeEmail, sanitizeName } = require('./_utils');
const { checkRateLimit } = require('./_rateLimit');

module.exports = async function handler(req, res) {
  // Security & Cache Control Headers
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

  // Rate Limiting: Max 15 order creations per minute per IP
  const rateLimit = checkRateLimit(req, 'create-order', 15, 60000);
  if (!rateLimit.allowed) {
    return res.status(429).json({
      error: 'Too many order requests. Please wait a moment before trying again.',
      retryAfterSeconds: Math.ceil(rateLimit.resetMs / 1000)
    });
  }

  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
    const email = sanitizeEmail(body.email);
    const name = sanitizeName(body.name);
    const rawCoupon = (body.couponCode || '').trim().slice(0, 32);
    const couponCode = /^[a-zA-Z0-9_\-]{2,32}$/.test(rawCoupon) ? rawCoupon.toUpperCase() : '';

    if (!email) {
      return res.status(400).json({ error: 'A valid email address is required to receive your license key.' });
    }

    const tier = (['single', 'universal', 'team'].includes((body.tier || '').toLowerCase()))
      ? (body.tier || '').toLowerCase()
      : 'universal';
    const tierPricing = {
      single: { INR: 79900, USD: 1500 },
      universal: { INR: 99900, USD: 1900 },
      team: { INR: 349900, USD: 6900 }
    };

    const country = (body.country || req.headers['x-vercel-ip-country'] || req.headers['cf-ipcountry'] || '').trim().toUpperCase();
    const isIndia = country === 'IN' || (body.currency || '').toUpperCase() === 'INR';
    const currency = isIndia ? 'INR' : 'USD';

    try {
      const { getActivePricing } = require('./pricing');
      if (typeof getActivePricing === 'function') {
        const p = getActivePricing();
        if (p?.tiers) {
          if (p.tiers.single) tierPricing.single = { INR: (p.tiers.single.INR?.amount || 799) * 100, USD: (p.tiers.single.USD?.amount || 15) * 100 };
          if (p.tiers.universal) tierPricing.universal = { INR: (p.tiers.universal.INR?.amount || 999) * 100, USD: (p.tiers.universal.USD?.amount || 19) * 100 };
          if (p.tiers.team) tierPricing.team = { INR: (p.tiers.team.INR?.amount || 3499) * 100, USD: (p.tiers.team.USD?.amount || 69) * 100 };
        }
      }
    } catch (e) {}

    let amountInSubunits = isIndia ? tierPricing[tier].INR : tierPricing[tier].USD;
    let appliedCoupon = null;

    // Apply coupon discount if provided
    if (couponCode) {
      try {
        const evalFn = evaluateCouponAsync || evaluateCoupon;
        const evalResult = await evalFn(couponCode, currency, amountInSubunits, email);
        if (!evalResult.valid) {
          return res.status(400).json({ error: evalResult.error || 'The coupon code is invalid or has expired.' });
        }
        amountInSubunits = evalResult.finalSubunits;
        appliedCoupon = {
          code: evalResult.code,
          discountSubunits: evalResult.discountSubunits,
          discountDisplay: evalResult.discountDisplay,
          finalDisplay: evalResult.finalDisplay
        };
      } catch (couponErr) {
        console.warn('[Coupon Evaluation Warning]', couponErr);
        return res.status(400).json({ error: 'Failed to validate coupon code. Please verify and try again.' });
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
          tier,
          product: `DropDial ${tier === 'single' ? 'Single' : tier === 'team' ? 'Team' : 'Universal'} Plan`,
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
