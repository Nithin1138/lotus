/**
 * Vercel Serverless Function: System Health & Configuration Status
 * GET /api/status
 */

const fs = require('fs');
const path = require('path');

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');

  let privateKeyFound = Boolean(process.env.LICENSE_PRIVATE_KEY);
  if (!privateKeyFound) {
    const candidatePaths = [
      path.join(__dirname, '../licensing/keys/private.pem'),
      path.join(process.cwd(), 'licensing/keys/private.pem'),
      path.join(__dirname, '../../licensing/keys/private.pem')
    ];
    privateKeyFound = candidatePaths.some(p => fs.existsSync(p));
  }

  const status = {
    service: 'DropDial Licensing & Payment Gateway',
    status: 'operational',
    timestamp: new Date().toISOString(),
    config: {
      razorpay: {
        keyIdConfigured: Boolean(process.env.RAZORPAY_KEY_ID),
        keySecretConfigured: Boolean(process.env.RAZORPAY_KEY_SECRET),
        webhookSecretConfigured: Boolean(process.env.RAZORPAY_WEBHOOK_SECRET)
      },
      resend: {
        apiKeyConfigured: Boolean(process.env.RESEND_API_KEY),
        fromEmailConfigured: Boolean(process.env.RESEND_FROM_EMAIL)
      },
      licensing: {
        privateKeyLoaded: privateKeyFound,
        algorithm: 'ECDSA P-256 (secp256r1) + SHA-256'
      }
    }
  };

  return res.status(200).json(status);
};
