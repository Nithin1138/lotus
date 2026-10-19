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

const DEFAULT_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgXJSMnXVgvTWnUeK7
SBM//6uK8U1vXp8q3A7o3IIx48uhRANCAARjN6BpxvNhm7DHFgJZ7jJNpxfnPJQy
bN+3U5335MzRb48Fc4AtD8Msh1CHuy4GTjzzplhMiXkUxBogjghnBnck
-----END PRIVATE KEY-----`;

/**
  * Loads the ECDSA P-256 private key from environment variable or filesystem.
  */
function getPrivateKey() {
  // 1. Check environment variable (Vercel standard)
  let keyEnv = (process.env.LICENSE_PRIVATE_KEY || '').trim();
  if (keyEnv && keyEnv.includes('BEGIN')) {
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

  // 3. Fallback to built-in ECDSA P-256 private key (guarantees zero breakage)
  return DEFAULT_PRIVATE_KEY;
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
  const apiKey = (process.env.RESEND_API_KEY || '').trim();
  if (!apiKey) {
    console.warn(`[Resend] RESEND_API_KEY is not configured. Email to ${to} skipped.`);
    return { success: false, warning: 'RESEND_API_KEY not configured' };
  }

  let fromEmail = (process.env.RESEND_FROM_EMAIL || '').trim();
  if (!fromEmail || fromEmail.includes('atslift.app')) {
    fromEmail = 'DropDial Pro <onboarding@resend.dev>';
  }
  const customerName = name || 'DropDial Pro User';

  const htmlContent = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Your DropDial Pro License Key & Receipt</title>
  <!--[if mso]>
  <noscript>
    <xml>
      <o:OfficeDocumentSettings>
        <o:PixelsPerInch>96</o:PixelsPerInch>
      </o:OfficeDocumentSettings>
    </xml>
  </noscript>
  <![endif]-->
</head>
<body style="margin: 0; padding: 0; width: 100% !important; background-color: #08090d; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #e2e8f0; -webkit-font-smoothing: antialiased;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #08090d; padding: 24px 12px;">
    <tr>
      <td align="center">
        <!-- Main Email Container -->
        <table width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width: 580px; background-color: #11141c; border-radius: 14px; overflow: hidden; border: 1px solid #232938; box-shadow: 0 16px 40px rgba(0,0,0,0.65);">
          <!-- Top Orange Accent Stripe -->
          <tr>
            <td style="height: 4px; background: linear-gradient(90deg, #ff6500 0%, #ff8833 100%);"></td>
          </tr>

          <!-- Header / Brand Section -->
          <tr>
            <td style="padding: 32px 32px 20px 32px; text-align: center;">
              <table align="center" cellpadding="0" cellspacing="0" border="0" style="margin: 0 auto 14px auto;">
                <tr>
                  <td style="background-color: rgba(255, 101, 0, 0.12); border: 1px solid rgba(255, 101, 0, 0.35); padding: 5px 14px; border-radius: 20px;">
                    <span style="color: #ff6500; font-size: 11px; font-weight: 800; letter-spacing: 1.5px; text-transform: uppercase;">DROPDIAL PRO</span>
                  </td>
                </tr>
              </table>
              <h1 style="font-size: 24px; font-weight: 800; color: #ffffff; margin: 0 0 6px 0; letter-spacing: -0.02em;">Welcome to DropDial Pro!</h1>
              <p style="font-size: 14px; color: #94a3b8; margin: 0; line-height: 1.5;">Thank you for your purchase, <strong>${customerName}</strong>. Your lifetime license is active.</p>
            </td>
          </tr>

          <!-- Content Section -->
          <tr>
            <td style="padding: 0 32px 28px 32px;">

              <!-- Key Callout Box -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #090a0f; border: 1.5px solid #ff6500; border-radius: 10px; margin: 16px 0 22px 0; box-shadow: 0 4px 18px rgba(255, 101, 0, 0.12);">
                <tr>
                  <td style="padding: 18px 20px;">
                    <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-bottom: 10px;">
                      <tr>
                        <td align="left">
                          <span style="font-size: 10px; font-weight: 800; color: #ff6500; text-transform: uppercase; letter-spacing: 1.2px;">YOUR PERSONAL LIFETIME LICENSE KEY</span>
                        </td>
                        <td align="right">
                          <span style="font-size: 11px; font-weight: 700; color: #10b981; background: rgba(16, 185, 129, 0.12); padding: 2px 8px; border-radius: 10px; border: 1px solid rgba(16, 185, 129, 0.25);">● ACTIVE</span>
                        </td>
                      </tr>
                    </table>

                    <div style="font-family: 'SF Mono', Consolas, Monaco, monospace; font-size: 12px; color: #ffffff; background: #151821; padding: 12px 14px; border-radius: 6px; border: 1px solid #272f3e; word-break: break-all; line-height: 1.6; user-select: all; -webkit-user-select: all;">
                      ${licenseKey}
                    </div>

                    <div style="font-size: 11px; color: #7f8a9c; margin-top: 10px; line-height: 1.4;">
                      💡 <em>Click to select all, then copy. Valid for up to 3 personal devices across macOS and Windows.</em>
                    </div>
                  </td>
                </tr>
              </table>

              <!-- Order Summary Table -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #151922; border: 1px solid #252b38; border-radius: 10px; margin-bottom: 22px; overflow: hidden;">
                <tr>
                  <td style="padding: 12px 16px; font-size: 12px; color: #8893a4; border-bottom: 1px solid #212633; width: 40%;">Product</td>
                  <td style="padding: 12px 16px; font-size: 12px; color: #ffffff; font-weight: 600; border-bottom: 1px solid #212633; text-align: right;">DropDial Pro (All 188+ Tools)</td>
                </tr>
                <tr>
                  <td style="padding: 12px 16px; font-size: 12px; color: #8893a4; border-bottom: 1px solid #212633;">Licensed To</td>
                  <td style="padding: 12px 16px; font-size: 12px; color: #ffffff; font-weight: 600; border-bottom: 1px solid #212633; text-align: right;">${customerName} (${to})</td>
                </tr>
                <tr>
                  <td style="padding: 12px 16px; font-size: 12px; color: #8893a4; border-bottom: 1px solid #212633;">Platforms</td>
                  <td style="padding: 12px 16px; font-size: 12px; color: #ffffff; font-weight: 600; border-bottom: 1px solid #212633; text-align: right;">macOS (Universal) & Windows</td>
                </tr>
                <tr>
                  <td style="padding: 12px 16px; font-size: 12px; color: #8893a4;">Receipt / Order ID</td>
                  <td style="padding: 12px 16px; font-size: 11px; font-family: monospace; color: #94a3b8; font-weight: 600; text-align: right;">${paymentId || 'PAY-LIFETIME'}</td>
                </tr>
              </table>

              <!-- How to Activate (3 Compact Steps) -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: #151922; border: 1px solid #252b38; border-radius: 10px; margin-bottom: 22px;">
                <tr>
                  <td style="padding: 18px 20px;">
                    <div style="font-size: 13px; font-weight: 700; color: #ffffff; margin-bottom: 12px;">
                      ⚡ Quick 20-Second Activation:
                    </div>
                    <table width="100%" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td width="24" valign="top" style="padding-bottom: 10px;">
                          <div style="width: 20px; height: 20px; background: #ff6500; border-radius: 50%; color: #ffffff; font-size: 11px; font-weight: 800; text-align: center; line-height: 20px;">1</div>
                        </td>
                        <td style="padding-left: 10px; padding-bottom: 10px; font-size: 13px; color: #cbd5e1; line-height: 1.4;">
                          Launch <strong>DropDial</strong> on your Mac or Windows desktop.
                        </td>
                      </tr>
                      <tr>
                        <td width="24" valign="top" style="padding-bottom: 10px;">
                          <div style="width: 20px; height: 20px; background: #ff6500; border-radius: 50%; color: #ffffff; font-size: 11px; font-weight: 800; text-align: center; line-height: 20px;">2</div>
                        </td>
                        <td style="padding-left: 10px; padding-bottom: 10px; font-size: 13px; color: #cbd5e1; line-height: 1.4;">
                          Right-click the DropDial menu bar (macOS) or tray icon (Windows) and select <strong>Activate DropDial Pro…</strong>
                        </td>
                      </tr>
                      <tr>
                        <td width="24" valign="top">
                          <div style="width: 20px; height: 20px; background: #ff6500; border-radius: 50%; color: #ffffff; font-size: 11px; font-weight: 800; text-align: center; line-height: 20px;">3</div>
                        </td>
                        <td style="padding-left: 10px; font-size: 13px; color: #cbd5e1; line-height: 1.4;">
                          Click <strong>Paste Key</strong> and confirm. You are unlocked for life!
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              <!-- Download Links CTA -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-bottom: 22px;">
                <tr>
                  <td align="center">
                    <a href="https://dropdial.app/#download" style="display: inline-block; background-color: #ff6500; color: #ffffff; font-weight: 700; font-size: 13px; padding: 12px 22px; border-radius: 8px; text-decoration: none; margin: 4px; box-shadow: 0 4px 14px rgba(255, 101, 0, 0.35);">
                       Download for macOS
                    </a>
                    <a href="https://dropdial.app/#download" style="display: inline-block; background-color: #242935; border: 1px solid #363e4f; color: #ffffff; font-weight: 600; font-size: 13px; padding: 12px 22px; border-radius: 8px; text-decoration: none; margin: 4px;">
                      ⊞ Download for Windows
                    </a>
                  </td>
                </tr>
              </table>

              <!-- Privacy & Offline Reassurance -->
              <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color: rgba(16, 185, 129, 0.08); border: 1px solid rgba(16, 185, 129, 0.25); border-radius: 8px;">
                <tr>
                  <td style="padding: 12px 16px; font-size: 12px; color: #94a3b8; line-height: 1.5;">
                    <strong style="color: #34d399;">🔒 100% Offline & Private:</strong> DropDial uses local ECDSA P-256 cryptographic verification. Your files and license never touch any remote servers.
                  </td>
                </tr>
              </table>

            </td>
          </tr>

          <!-- Footer -->
          <tr>
            <td style="background-color: #0b0d12; padding: 22px 32px; text-align: center; font-size: 12px; color: #64748b; border-top: 1px solid #1e2430; line-height: 1.6;">
              DropDial • Offline Media & File Tools for macOS and Windows<br>
              Need assistance or lost your key? Reply to this email or visit <a href="https://dropdial.app" style="color: #ff6500; text-decoration: none;">dropdial.app</a>.
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
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
        subject: 'Your DropDial Pro License Key & Receipt 🚀',
        html: htmlContent,
        text: `Welcome to DropDial Pro!\n\nHi ${customerName},\n\nThank you for purchasing DropDial Pro. Here is your personal lifetime license key:\n\n${licenseKey}\n\nTo activate:\n1. Open DropDial on your Mac or Windows desktop.\n2. Right-click the menu bar / system tray icon and select "Activate DropDial Pro…"\n3. Click "Paste Key" and confirm activation.\n\nDownload installers anytime at https://dropdial.app/#download\n\nEnjoy lifetime private conversion!\nDropDial Team`
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
