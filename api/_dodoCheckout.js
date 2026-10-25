/**
 * Vercel Serverless Function: Create Dodo Payments Checkout Session
 * POST /api/dodo-checkout
 *
 * Supports global Merchant of Record (MoR) checkout for DropDial:
 * - Automatic global sales tax / VAT calculation and remittance
 * - Apple Pay, Google Pay, Visa, Mastercard, AMEX, and global payment methods
 * - Preserves coupon discounts, customer name, email, and tier in session metadata
 */

const { evaluateCoupon, evaluateCouponAsync } = require('./coupons');
const { sanitizeEmail, sanitizeName } = require('./_utils');
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

  // Rate Limiting: Max 15 checkout sessions per minute per IP
  const rateLimit = checkRateLimit(req, 'dodo-checkout', 15, 60000);
  if (!rateLimit.allowed) {
    return res.status(429).json({
      error: 'Too many checkout requests. Please wait a moment before trying again.',
      retryAfterSeconds: Math.ceil(rateLimit.resetMs / 1000)
    });
  }

  try {
    const body = typeof req.body === 'string' ? JSON.parse(req.body) : (req.body || {});
    const email = sanitizeEmail(body.email);
    const name = sanitizeName(body.name);
    const rawCoupon = (body.couponCode || '').trim().slice(0, 32);
    const couponCode = /^[a-zA-Z0-9_\-]{2,32}$/.test(rawCoupon) ? rawCoupon.toUpperCase() : '';

    if (!email || !email.includes('@')) {
      return res.status(400).json({ error: 'A valid email address is required to receive your license key.' });
    }

    const tier = (['single', 'universal', 'team'].includes((body.tier || '').toLowerCase()))
      ? (body.tier || '').toLowerCase()
      : 'universal';

    const tierPricing = {
      single: { INR: 79900, USD: 1900 },
      universal: { INR: 99900, USD: 2900 },
      team: { INR: 299900, USD: 7900 }
    };

    try {
      const { getActivePricing } = require('./pricing');
      if (typeof getActivePricing === 'function') {
        const p = getActivePricing();
        if (p?.tiers) {
          if (p.tiers.single) tierPricing.single = { INR: (p.tiers.single.INR?.amount || 799) * 100, USD: (p.tiers.single.USD?.amount || 19) * 100 };
          if (p.tiers.universal) tierPricing.universal = { INR: (p.tiers.universal.INR?.amount || 999) * 100, USD: (p.tiers.universal.USD?.amount || 29) * 100 };
          if (p.tiers.team) tierPricing.team = { INR: (p.tiers.team.INR?.amount || 2999) * 100, USD: (p.tiers.team.USD?.amount || 79) * 100 };
        }
      }
    } catch (_) {}

    const requestedCurrency = (body.currency || '').toUpperCase();
    const country = (body.country || req.headers['x-vercel-ip-country'] || req.headers['cf-ipcountry'] || '').trim().toUpperCase();
    const isIndia = requestedCurrency ? (requestedCurrency === 'INR') : (country === 'IN');
    const currency = isIndia ? 'INR' : 'USD';

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
        console.warn('[Dodo Coupon Evaluation Warning]', couponErr);
        return res.status(400).json({ error: 'Failed to validate coupon code. Please verify and try again.' });
      }
    }

    const apiKey = (process.env.DODO_PAYMENTS_API_KEY || '').trim();
    const isTestMode = process.env.DODO_PAYMENTS_ENVIRONMENT === 'test_mode' ||
      apiKey.startsWith('test_') ||
      apiKey.includes('_test_');

    const baseUrl = isTestMode ? 'https://test.dodopayments.com' : 'https://api.dodopayments.com';

    // Map plan tier to Dodo Product ID (supports regional INR product overrides if configured)
    const productMap = isIndia ? {
      single: process.env.DODO_PRODUCT_INR_SINGLE || process.env.DODO_PRODUCT_SINGLE || process.env.DODO_PRODUCT_ID,
      universal: process.env.DODO_PRODUCT_INR_UNIVERSAL || process.env.DODO_PRODUCT_UNIVERSAL || process.env.DODO_PRODUCT_ID,
      team: process.env.DODO_PRODUCT_INR_TEAM || process.env.DODO_PRODUCT_TEAM || process.env.DODO_PRODUCT_ID
    } : {
      single: process.env.DODO_PRODUCT_SINGLE || process.env.DODO_PRODUCT_ID,
      universal: process.env.DODO_PRODUCT_UNIVERSAL || process.env.DODO_PRODUCT_ID,
      team: process.env.DODO_PRODUCT_TEAM || process.env.DODO_PRODUCT_ID
    };
    const productId = productMap[tier] || process.env.DODO_PRODUCT_ID;

    // Determine host return URL (avoid 307 apex redirects on return)
    const reqHost = req.headers['x-forwarded-host'] || req.headers.host || '';
    const isLocal = reqHost.includes('localhost') || reqHost.includes('127.0.0.1');
    const host = isLocal ? reqHost : 'www.dropdial.app';
    const protocol = isLocal ? 'http' : 'https';
    const returnUrl = `${protocol}://${host}/?payment_status=success&tier=${tier}&email=${encodeURIComponent(email)}`;

    // If API key is missing, return error in production or test sandbox response in development
    if (!apiKey || !productId) {
      const isProd = process.env.NODE_ENV === 'production' || process.env.VERCEL_ENV === 'production';
      if (isProd) {
        console.error('[Dodo Payments Error] DODO_PAYMENTS_API_KEY or Product ID missing in production');
        return res.status(503).json({ error: 'Payment gateway is currently unavailable. Please try again shortly or contact support.' });
      }
      console.warn('[Dodo Payments] DODO_PAYMENTS_API_KEY or Product ID is not configured. Returning sandbox session.');
      const mockSessionId = `cks_mock_${Date.now()}`;
      return res.status(200).json({
        success: true,
        gateway: 'dodo',
        sandbox: true,
        sessionId: mockSessionId,
        checkoutUrl: `${protocol}://${host}/?payment_status=success&session_id=${mockSessionId}&email=${encodeURIComponent(email)}&tier=${tier}`,
        amount: amountInSubunits,
        currency,
        tier,
        coupon: appliedCoupon,
        message: 'Sandbox mode active. Set DODO_PAYMENTS_API_KEY and DODO_PRODUCT_UNIVERSAL (or DODO_PRODUCT_ID) in Vercel to activate live payments.'
      });
    }

    // Call Dodo Payments Checkout API
    const dodoPayload = {
      product_cart: [
        {
          product_id: productId,
          quantity: 1
        }
      ],
      customer: {
        email,
        name: name || 'DropDial Customer'
      },
      billing_currency: currency,
      return_url: returnUrl,
      metadata: {
        email,
        name: name || 'DropDial Customer',
        tier,
        couponCode: appliedCoupon ? appliedCoupon.code : '',
        country: country || 'US'
      }
    };

    if (appliedCoupon && appliedCoupon.code) {
      dodoPayload.discount_codes = [appliedCoupon.code];
    }

    const response = await fetch(`${baseUrl}/checkouts`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(dodoPayload)
    });

    const data = await response.json();
    if (!response.ok) {
      console.error('[Dodo Payments Checkout Session Error]', data);
      return res.status(500).json({
        error: data.message || data.error?.description || 'Failed to create Dodo Payments checkout session.'
      });
    }

    return res.status(200).json({
      success: true,
      gateway: 'dodo',
      sessionId: data.session_id,
      checkoutUrl: data.checkout_url,
      amount: amountInSubunits,
      currency,
      tier,
      coupon: appliedCoupon
    });
  } catch (err) {
    console.error('[dodo-checkout Error]', err);
    return res.status(500).json({ error: err.message || 'Internal Server Error' });
  }
};
