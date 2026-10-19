const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

/**
 * Base64-URL encoder (RFC 4648 §5)
 */
function b64urlEncode(buf) {
  return buf.toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function sanitizePem(str) {
  if (!str) return '';
  let clean = str.trim();
  // Strip surrounding quotes
  if ((clean.startsWith('"') && clean.endsWith('"')) || (clean.startsWith("'") && clean.endsWith("'"))) {
    clean = clean.slice(1, -1);
  }
  // Replace literal \n or \\n
  clean = clean.replace(/\\n/g, '\n');

  // If no newlines remain (e.g. single-line string with spaces from dashboard copy-paste):
  if (!clean.includes('\n')) {
    const headerMatch = clean.match(/-----BEGIN [A-Z0-9 ]+-----/);
    const footerMatch = clean.match(/-----END [A-Z0-9 ]+-----/);
    if (headerMatch && footerMatch) {
      const header = headerMatch[0];
      const footer = footerMatch[0];
      const middle = clean
        .replace(header, '')
        .replace(footer, '')
        .replace(/\s+/g, '');
      const chunks = middle.match(/.{1,64}/g) || [];
      clean = [header, ...chunks, footer, ''].join('\n');
    }
  }
  return clean.trim();
}

/**
 * Loads the ECDSA P-256 private key from environment variable or filesystem.
 */
function getPrivateKey() {
  // 1. Check environment variable (Vercel standard)
  let keyEnv = process.env.LICENSE_PRIVATE_KEY;
  if (keyEnv) {
    return sanitizePem(keyEnv);
  }

  // 2. Check local filesystem paths (local dev / self-hosted)
  const candidatePaths = [
    path.join(__dirname, '../licensing/keys/private.pem'),
    path.join(process.cwd(), 'licensing/keys/private.pem'),
    path.join(__dirname, '../../licensing/keys/private.pem')
  ];

  for (const p of candidatePaths) {
    if (fs.existsSync(p)) {
      return sanitizePem(fs.readFileSync(p, 'utf8'));
    }
  }

  throw new Error('LICENSE_PRIVATE_KEY environment variable is not set and private.pem not found on disk.');
}

/**
 * Generates an ECDSA P-256 cryptographically signed DropDial license key.
 * Compatible with DropDial macOS (CryptoKit/Security.framework) and Windows (System.Security.Cryptography.ECDsa).
 *
 * Format: DD-<b64url(payload)>.<b64url(raw_signature_64_bytes)>
 */
function generateLicense(email, name, tier = 'pro') {
  const privateKeyPem = getPrivateKey();
  const dateStr = new Date().toISOString().slice(0, 10);

  // Exact JSON payload with sorted keys: d, e, n, t
  const payload = {
    d: dateStr,
    e: (email || '').trim().toLowerCase(),
    n: (name || 'DropDial Customer').trim(),
    t: tier
  };

  const sortedKeys = Object.keys(payload).sort();
  const payloadJson = JSON.stringify(payload, sortedKeys);
  const payloadBytes = Buffer.from(payloadJson, 'utf8');

  // Sign with ECDSA P-256 + SHA-256 using IEEE P1363 (raw r || s 64 bytes)
  const sign = crypto.createSign('SHA256');
  sign.update(payloadBytes);
  const rawSig = sign.sign({
    key: privateKeyPem,
    dsaEncoding: 'ieee-p1363'
  });

  return `DD-${b64urlEncode(payloadBytes)}.${b64urlEncode(rawSig)}`;
}

/**
 * Sends a branded, high-conversion license activation email using Resend API.
 */
async function sendResendEmail({ to, name, licenseKey, paymentId = '', amount = '' }) {
  const apiKey = process.env.RESEND_API_KEY;
  if (!apiKey) {
    console.warn(`[Resend] RESEND_API_KEY is not configured. Email to ${to} skipped.`);
    return { success: false, warning: 'RESEND_API_KEY not configured' };
  }

  const fromEmail = process.env.RESEND_FROM_EMAIL || 'DropDial Pro <onboarding@resend.dev>';
  const customerName = name || 'DropDial Pro User';

  const htmlContent = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Your DropDial Pro License Key</title>
  <style>
    body { margin: 0; padding: 0; background-color: #0d0f12; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #e6e8eb; }
    .wrapper { max-width: 580px; margin: 30px auto; background-color: #16181d; border: 1px solid #282c35; border-radius: 14px; overflow: hidden; box-shadow: 0 12px 30px rgba(0,0,0,0.5); }
    .header { background: linear-gradient(135deg, #1c1f26 0%, #16181d 100%); padding: 36px 32px 24px 32px; text-align: center; border-bottom: 1px solid #282c35; }
    .logo-badge { display: inline-block; background-color: #ff6500; color: #ffffff; font-weight: 800; font-size: 13px; letter-spacing: 1.5px; padding: 6px 14px; border-radius: 20px; text-transform: uppercase; margin-bottom: 14px; }
    .title { font-size: 24px; font-weight: 800; color: #ffffff; margin: 0 0 8px 0; }
    .subtitle { font-size: 14px; color: #9aa1ad; margin: 0; }
    .content { padding: 32px; }
    .greeting { font-size: 15px; color: #d0d5dd; line-height: 1.6; margin: 0 0 20px 0; }
    .key-box { background: #0b0c0f; border: 1px solid #ff6500; border-radius: 10px; padding: 20px; text-align: center; margin: 24px 0; }
    .key-label { font-size: 11px; font-weight: 700; color: #ff6500; text-transform: uppercase; letter-spacing: 1.2px; margin-bottom: 10px; }
    .license-code { font-family: 'SF Mono', Consolas, Monaco, monospace; font-size: 13px; color: #ffffff; background: #13161c; padding: 14px 12px; border-radius: 8px; border: 1px solid #232731; word-break: break-all; display: block; user-select: all; -webkit-user-select: all; }
    .instruction-card { background: #1a1d24; border-radius: 10px; padding: 20px; margin: 24px 0; border: 1px solid #2a2f3a; }
    .instruction-title { font-size: 14px; font-weight: 700; color: #ffffff; margin: 0 0 12px 0; }
    .instruction-list { margin: 0; padding-left: 20px; color: #b6bcc8; font-size: 13px; line-height: 1.7; }
    .instruction-list li { margin-bottom: 6px; }
    .feature-tags { display: flex; flex-wrap: wrap; gap: 8px; margin: 24px 0 12px 0; }
    .tag { background: #232731; color: #9aa1ad; font-size: 11px; padding: 5px 10px; border-radius: 6px; }
    .footer { background: #101216; padding: 24px 32px; text-align: center; font-size: 12px; color: #6e7685; border-top: 1px solid #20242d; line-height: 1.6; }
    .footer a { color: #ff6500; text-decoration: none; }
  </style>
</head>
<body>
  <div class="wrapper">
    <div class="header">
      <div class="logo-badge">DropDial Pro</div>
      <h1 class="title">Welcome to DropDial Pro!</h1>
      <p class="subtitle">Thank you for your purchase, ${customerName}.</p>
    </div>

    <div class="content">
      <p class="greeting">
        Your lifetime license key has been generated and activated. You now have unrestricted access to all 188+ offline conversion and media tools across macOS and Windows.
      </p>

      <div class="key-box">
        <div class="key-label">Your Personal Lifetime License Key</div>
        <div class="license-code">${licenseKey}</div>
      </div>

      <div class="instruction-card">
        <div class="instruction-title">How to Activate in 30 Seconds:</div>
        <ol class="instruction-list">
          <li>Launch <strong>DropDial</strong> on your Mac or Windows PC.</li>
          <li>Right-click the DropDial menu bar icon (macOS) or notification tray icon (Windows).</li>
          <li>Select <strong>Activate DropDial Pro…</strong> from the menu.</li>
          <li>Click the <strong>Paste Key</strong> button and click <strong>Activate DropDial Pro</strong>.</li>
        </ol>
      </div>

      <p style="font-size: 13px; color: #8e95a2; line-height: 1.6; margin-top: 18px;">
        🔒 <strong>100% Offline & Private:</strong> DropDial uses local ECDSA P-256 cryptographic verification. Your device never connects to the internet to validate your license.
      </p>
    </div>

    <div class="footer">
      DropDial • Fast, Private Desktop File Tools<br>
      Lifetime License for up to 3 personal devices.<br>
      Need assistance? Reply directly to this email or visit <a href="https://dropdial.app">dropdial.app</a>.
    </div>
  </div>
</body>
</html>
  `;

  try {
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        from: fromEmail,
        to: [to],
        subject: 'Your DropDial Pro License Key 🚀',
        html: htmlContent,
        text: `Welcome to DropDial Pro!\n\nHi ${customerName},\n\nThank you for purchasing DropDial Pro. Here is your lifetime license key:\n\n${licenseKey}\n\nTo activate:\n1. Open DropDial on your Mac or Windows PC.\n2. Click the DropDial icon in the menu bar / system tray.\n3. Click 'Activate DropDial Pro...'.\n4. Paste your key and click Activate.\n\nEnjoy lifetime offline conversion!\nDropDial Team`
      })
    });

    const data = await response.json();
    if (!response.ok) {
      console.error('[Resend Error]', data);
      return { success: false, error: data };
    }

    console.log(`[Resend Success] Email delivered to ${to}, ID: ${data.id}`);
    return { success: true, id: data.id };
  } catch (err) {
    console.error('[Resend Network Error]', err);
    return { success: false, error: err.message };
  }
}

/**
 * Validates Razorpay Payment Signature from Client Checkout:
 * HMAC_SHA256(order_id + "|" + payment_id, secret) == signature
 */
function verifyRazorpayPaymentSignature({ orderId, paymentId, signature }) {
  const secret = process.env.RAZORPAY_KEY_SECRET;
  if (!secret) {
    throw new Error('RAZORPAY_KEY_SECRET is not configured on server.');
  }

  const hmac = crypto.createHmac('sha256', secret);
  hmac.update(`${orderId}|${paymentId}`);
  const expectedSignature = hmac.digest('hex');

  return crypto.timingSafeEqual(
    Buffer.from(expectedSignature, 'utf8'),
    Buffer.from(signature, 'utf8')
  );
}

/**
 * Validates Razorpay Webhook Signature:
 * HMAC_SHA256(raw_body, webhook_secret) == x_razorpay_signature
 */
function verifyRazorpayWebhookSignature(rawBody, signature) {
  const secret = process.env.RAZORPAY_WEBHOOK_SECRET;
  if (!secret) {
    throw new Error('RAZORPAY_WEBHOOK_SECRET is not configured on server.');
  }

  const hmac = crypto.createHmac('sha256', secret);
  hmac.update(rawBody);
  const expectedSignature = hmac.digest('hex');

  return crypto.timingSafeEqual(
    Buffer.from(expectedSignature, 'utf8'),
    Buffer.from(signature, 'utf8')
  );
}

module.exports = {
  b64urlEncode,
  getPrivateKey,
  generateLicense,
  sendResendEmail,
  verifyRazorpayPaymentSignature,
  verifyRazorpayWebhookSignature
};
