/**
 * Vercel Serverless Function: Create Razorpay Order
 * POST /api/create-order
 */

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
    const amountInSubunits = isIndia ? 99900 : 1900;

    const keyId = (process.env.RAZORPAY_KEY_ID || '').trim();
    const keySecret = (process.env.RAZORPAY_KEY_SECRET || '').trim();

    if (!keyId || !keySecret) {
      console.warn('[Razorpay] RAZORPAY_KEY_ID or RAZORPAY_KEY_SECRET is not configured. Running in sandbox test mode.');
      // Return sandbox test order so developer can preview full UI before adding live keys
      return res.status(200).json({
        orderId: `order_mock_${Date.now()}`,
        amount: amountInSubunits,
        currency,
        keyId: keyId || 'rzp_test_placeholder',
        sandbox: true,
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
          product: 'DropDial Pro Lifetime'
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
      notes: data.notes
    });
  } catch (err) {
    console.error('[create-order Error]', err);
    return res.status(500).json({ error: err.message || 'Internal Server Error' });
  }
};
