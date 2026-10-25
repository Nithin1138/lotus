/**
 * Vercel Serverless Function: Razorpay Webhook Handler
 * POST /api/razorpay-webhook
 *
 * Configured in Razorpay Dashboard > Settings > Webhooks
 * Secret: RAZORPAY_WEBHOOK_SECRET
 * Events: payment.captured, order.paid
 */

const { generateLicense, sendResendEmail, sendPaymentFailedEmail, verifyRazorpayWebhookSignature, sanitizeEmail, sanitizeName } = require('./_utils');

// Helper to buffer request body for HMAC verification
function getRawBody(req) {
  return new Promise((resolve, reject) => {
    if (typeof req.body === 'string') {
      return resolve(req.body);
    }
    if (Buffer.isBuffer(req.body)) {
      return resolve(req.body.toString('utf8'));
    }
    if (typeof req.body === 'object' && req.body !== null) {
      return resolve(JSON.stringify(req.body));
    }

    let chunks = [];
    req.on('data', chunk => chunks.push(chunk));
    req.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    req.on('error', err => reject(err));
  });
}

module.exports = async function handler(req, res) {
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate');

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method Not Allowed' });
  }

  try {
    const rawBody = await getRawBody(req);
    const signature = req.headers['x-razorpay-signature'];
    const webhookSecret = (process.env.RAZORPAY_WEBHOOK_SECRET || '').trim();

    if (webhookSecret) {
      if (!signature) {
        console.error('[Razorpay Webhook] Missing x-razorpay-signature header.');
        return res.status(400).json({ error: 'Missing webhook signature' });
      }

      let isValid = false;
      try {
        isValid = verifyRazorpayWebhookSignature(rawBody, signature);
      } catch (err) {
        console.error('[Razorpay Webhook] Signature verification error:', err.message);
        return res.status(400).json({ error: 'Invalid webhook signature' });
      }

      if (!isValid) {
        console.error('[Razorpay Webhook] Signature mismatch.');
        return res.status(400).json({ error: 'Invalid webhook signature' });
      }
    } else {
      if (process.env.NODE_ENV === 'production') {
        console.error('[Razorpay Webhook] RAZORPAY_WEBHOOK_SECRET must be configured in production.');
        return res.status(500).json({ error: 'Webhook secret is not configured' });
      }
      console.warn('[Razorpay Webhook] RAZORPAY_WEBHOOK_SECRET not set. Skipping signature validation (DEV mode only).');
    }

    const eventData = JSON.parse(rawBody);
    const event = eventData.event;
    console.log(`[Razorpay Webhook] Received event: ${event}`);

    // Process payment.captured or order.paid
    if (event === 'payment.captured' || event === 'order.paid') {
      const payment = eventData.payload?.payment?.entity || {};
      const notes = payment.notes || {};

      const email = (payment.email || notes.email || '').trim().toLowerCase();
      const name = (notes.name || payment.contact || 'DropDial Customer').trim();
      const paymentId = payment.id || 'wh_pay';
      const amount = payment.amount ? (payment.amount / 100).toFixed(2) : '19.00';

      if (!email || !email.includes('@')) {
        console.warn('[Razorpay Webhook] No valid email found in payment payload. Skipping auto-email.', payment.id);
        return res.status(200).json({ status: 'ignored_no_email' });
      }

      // Check DB for Idempotency
      try {
        const { getDb, ensureSchema } = require('./_db');
        const sql = getDb();
        if (sql) {
          await ensureSchema();
          const existingTx = await sql`
            SELECT id FROM transactions WHERE payment_id = ${paymentId} LIMIT 1;
          `;
          if (existingTx && existingTx.length > 0) {
            console.log(`[Razorpay Webhook] Payment ${paymentId} already recorded in DB. Skipping duplicate.`);
            return res.status(200).json({ status: 'ok', already_processed: true });
          }
        }
      } catch (dbErr) {
        console.warn('[Razorpay Webhook DB Idempotency Check Warning]:', dbErr.message);
      }

      // 1. Determine Plan Tier & Generate Signed License Key
      const rawTier = (notes.tier || notes.product || '').toLowerCase();
      const tier = rawTier.includes('single') ? 'single'
        : rawTier.includes('team') ? 'team'
        : 'universal';
      const licenseKey = generateLicense(email, name, tier);
      console.log(`[Razorpay Webhook] Issued ${tier} license for: ${email} -> ${licenseKey.slice(0, 20)}...`);

      // 2. Persist to Neon DB
      try {
        const { getDb, ensureSchema } = require('./_db');
        const sql = getDb();
        if (sql) {
          await ensureSchema();
          const licId = `lic_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
          await sql`
            INSERT INTO licenses (id, customer_name, email, license_key, tier, status, created_at)
            VALUES (${licId}, ${name}, ${email}, ${licenseKey}, ${tier}, 'active', NOW())
            ON CONFLICT (id) DO NOTHING;
          `;
          const txId = `tx_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
          const txAmount = Math.round(Number(amount)) || (tier === 'single' ? 799 : tier === 'team' ? 3499 : 999);
          const orderId = payment.order_id || 'wh_order';
          await sql`
            INSERT INTO transactions (id, order_id, payment_id, amount, currency, customer_name, email, status, coupon_code, country, created_at)
            VALUES (${txId}, ${orderId}, ${paymentId}, ${txAmount}, ${payment.currency || 'INR'}, ${name}, ${email}, 'captured', ${notes.coupon || null}, ${notes.country || 'IN'}, NOW())
            ON CONFLICT (id) DO NOTHING;
          `;
        }
      } catch (saveErr) {
        console.warn('[Razorpay Webhook DB Save Warning]:', saveErr.message);
      }

      // 3. Dispatch Email via Resend
      const emailResult = await sendResendEmail({
        to: email,
        name,
        licenseKey,
        paymentId,
        amount
      });

      return res.status(200).json({
        status: 'ok',
        event,
        email,
        licenseIssued: true,
        emailDelivered: emailResult.success
      });
    }

    // Process payment.failed event
    if (event === 'payment.failed') {
      const payment = eventData.payload?.payment?.entity || {};
      const notes = payment.notes || {};

      const email = (payment.email || notes.email || '').trim().toLowerCase();
      const name = (notes.name || payment.contact || 'DropDial Customer').trim();
      const reason = payment.error_description || payment.error_reason || 'Transaction was declined by bank or gateway';
      const amount = payment.amount ? (payment.amount / 100).toFixed(2) : '';
      const currency = payment.currency || 'USD';

      if (email && email.includes('@')) {
        console.log(`[Razorpay Webhook] Payment failed for: ${email} -> Sending failure notification email`);
        const failEmailResult = await sendPaymentFailedEmail({
          to: email,
          name,
          reason,
          amount,
          currency
        });

        return res.status(200).json({
          status: 'ok',
          event,
          email,
          paymentFailedNoticeSent: failEmailResult.success
        });
      }

      return res.status(200).json({ status: 'ignored_no_email', event });
    }

    // Acknowledge other events
    return res.status(200).json({ status: 'ignored', event });
  } catch (err) {
    console.error('[Razorpay Webhook Error]', err);
    return res.status(500).json({ error: err.message || 'Webhook processing failed' });
  }
};
