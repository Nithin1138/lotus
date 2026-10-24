/**
 * Vercel Serverless Function: Dodo Payments Webhook Handler
 * POST /api/dodo-webhook
 *
 * Configured in Dodo Payments Dashboard > Developers > Webhooks
 * Secret: DODO_PAYMENTS_WEBHOOK_KEY (or DODO_WEBHOOK_SECRET)
 * Events: payment.succeeded, payment.failed
 */

const {
  generateLicense,
  sendResendEmail,
  sendPaymentFailedEmail,
  verifyDodoWebhookSignature,
  sanitizeEmail,
  sanitizeName
} = require('./_utils');

// Helper to buffer raw request body for standard webhook HMAC verification
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
    const webhookSecret = (process.env.DODO_PAYMENTS_WEBHOOK_KEY || process.env.DODO_WEBHOOK_SECRET || '').trim();

    // Verify Standard Webhook Signature
    if (webhookSecret) {
      const isValid = verifyDodoWebhookSignature(rawBody, req.headers, webhookSecret);
      if (!isValid) {
        console.error('[Dodo Webhook] Cryptographic signature mismatch or invalid headers.');
        return res.status(401).json({ error: 'Invalid webhook signature' });
      }
    } else {
      if (process.env.NODE_ENV === 'production') {
        console.error('[Dodo Webhook] DODO_PAYMENTS_WEBHOOK_KEY must be set in production.');
        return res.status(500).json({ error: 'Webhook secret is not configured' });
      }
      console.warn('[Dodo Webhook] DODO_PAYMENTS_WEBHOOK_KEY not set. Skipping signature verification (DEV mode).');
    }

    const event = JSON.parse(rawBody);
    const eventType = event.type;
    console.log(`[Dodo Webhook] Received verified event: ${eventType}`);

    // 1. Process payment.succeeded
    if (eventType === 'payment.succeeded') {
      const paymentData = event.data || {};
      const customer = paymentData.customer || {};
      const metadata = paymentData.metadata || {};

      const rawEmail = (customer.email || metadata.email || '').trim().toLowerCase();
      const email = sanitizeEmail(rawEmail);
      const name = sanitizeName(customer.name || metadata.name || 'DropDial Customer');
      const paymentId = paymentData.payment_id || `dodo_${Date.now()}`;
      const amountSubunits = Number(paymentData.total_amount) || 1900;
      const amount = (amountSubunits / 100).toFixed(2);
      const currency = (paymentData.currency || 'USD').toUpperCase();
      const country = (metadata.country || 'US').toUpperCase();
      const couponCode = metadata.couponCode || null;

      if (!email || !email.includes('@')) {
        console.warn('[Dodo Webhook] No valid email in payload. Skipping license generation.', paymentId);
        return res.status(200).json({ status: 'ignored_no_email' });
      }

      // Check DB for Idempotency
      try {
        const { getDb, ensureSchema } = require('./_db');
        const sql = getDb();
        if (sql) {
          await ensureSchema();
          const existingTx = await sql`
            SELECT id FROM transactions WHERE payment_id = ${paymentId} LIMIT 1
          `;
          if (existingTx && existingTx.length > 0) {
            console.log(`[Dodo Webhook] Payment ${paymentId} already fulfilled. Skipping duplicate.`);
            return res.status(200).json({ status: 'already_fulfilled', paymentId });
          }
        }
      } catch (dbCheckErr) {
        console.warn('[Dodo Webhook DB Check Warning]:', dbCheckErr.message);
      }

      // Determine Plan Tier & Generate Signed License Key
      const rawTier = (metadata.tier || paymentData.product_name || 'universal').toLowerCase();
      const tier = rawTier.includes('single') ? 'single'
        : rawTier.includes('team') ? 'team'
        : 'universal';

      const licenseKey = generateLicense(email, name, tier);
      console.log(`[Dodo Webhook] Issued ${tier} license for: ${email} -> ${licenseKey.slice(0, 25)}...`);

      // Persist to Neon PostgreSQL Database
      try {
        const { getDb, ensureSchema } = require('./_db');
        const sql = getDb();
        if (sql) {
          await ensureSchema();
          const licId = `lic_dodo_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
          await sql`
            INSERT INTO licenses (id, customer_name, email, license_key, tier, status, created_at)
            VALUES (${licId}, ${name}, ${email}, ${licenseKey}, ${tier}, 'active', NOW())
            ON CONFLICT (id) DO NOTHING;
          `;

          const txId = `tx_dodo_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
          await sql`
            INSERT INTO transactions (id, order_id, payment_id, amount, currency, customer_name, email, status, coupon_code, country, created_at)
            VALUES (${txId}, ${paymentData.session_id || 'dodo_checkout'}, ${paymentId}, ${amountSubunits}, ${currency}, ${name}, ${email}, 'captured', ${couponCode}, ${country}, NOW())
            ON CONFLICT (id) DO NOTHING;
          `;

          if (couponCode) {
            try {
              await sql`
                UPDATE coupons
                SET uses = COALESCE(uses, 0) + 1
                WHERE UPPER(code) = UPPER(${couponCode});
              `;
            } catch (cErr) {
              console.warn('[Dodo Coupon DB Increment Warning]:', cErr.message);
            }
          }
        }
      } catch (dbErr) {
        console.warn('[Dodo Webhook DB Insert Warning]:', dbErr.message);
      }

      // Dispatch Delivery Email via Resend
      const emailResult = await sendResendEmail({
        to: email,
        name,
        licenseKey,
        tier,
        paymentId,
        amount
      });

      return res.status(200).json({
        status: 'ok',
        event: eventType,
        paymentId,
        email,
        licenseIssued: true,
        emailDelivered: emailResult.success
      });
    }

    // 2. Process payment.failed
    if (eventType === 'payment.failed') {
      const paymentData = event.data || {};
      const customer = paymentData.customer || {};
      const metadata = paymentData.metadata || {};

      const email = sanitizeEmail(customer.email || metadata.email);
      const name = sanitizeName(customer.name || metadata.name || 'DropDial Customer');
      const reason = paymentData.error_message || paymentData.failure_reason || 'Transaction was declined by card issuer or bank.';
      const amount = paymentData.total_amount ? (paymentData.total_amount / 100).toFixed(2) : '';
      const currency = paymentData.currency || 'USD';

      if (email && email.includes('@')) {
        console.log(`[Dodo Webhook] Payment failed for: ${email} -> Sending notice email`);
        const failEmailResult = await sendPaymentFailedEmail({
          to: email,
          name,
          reason,
          amount,
          currency
        });

        return res.status(200).json({
          status: 'ok',
          event: eventType,
          email,
          paymentFailedNoticeSent: failEmailResult.success
        });
      }

      return res.status(200).json({ status: 'ignored_no_email', event: eventType });
    }

    // Acknowledge other event types (e.g. refund.succeeded, subscription events)
    return res.status(200).json({ status: 'ignored', event: eventType });
  } catch (err) {
    console.error('[Dodo Webhook Error]', err);
    return res.status(500).json({ error: err.message || 'Internal Server Error' });
  }
};
