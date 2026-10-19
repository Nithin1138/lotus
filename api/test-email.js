/**
 * Diagnostic & Test Endpoint: Send Test License Email via Resend
 * GET or POST /api/test-email?email=you@example.com
 */

const { generateLicense, sendResendEmail } = require('./_utils');

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  try {
    const queryEmail = req.query?.email;
    const bodyEmail = req.body && typeof req.body === 'object' ? req.body.email : null;
    const email = (queryEmail || bodyEmail || 'veeranithin9@gmail.com').trim().toLowerCase();
    const name = (req.query?.name || req.body?.name || 'Nithin').trim();

    const resendApiKey = (process.env.RESEND_API_KEY || '').trim();
    const resendFromEmail = (process.env.RESEND_FROM_EMAIL || '').trim() || 'DropDial Pro <onboarding@resend.dev>';
    const privateKeyEnv = (process.env.LICENSE_PRIVATE_KEY || '').trim();

    const diagnostics = {
      timestamp: new Date().toISOString(),
      recipientEmail: email,
      recipientName: name,
      envCheck: {
        hasResendApiKey: Boolean(resendApiKey),
        resendApiKeyPrefix: resendApiKey ? `${resendApiKey.slice(0, 7)}...` : 'MISSING',
        resendFromEmail: resendFromEmail,
        hasLicensePrivateKey: Boolean(privateKeyEnv),
        licenseKeyLength: privateKeyEnv.length
      }
    };

    // 1. Generate test license key
    let licenseKey;
    try {
      licenseKey = generateLicense(email, name, 'pro');
      diagnostics.licenseKeyGeneration = {
        success: true,
        licenseKey
      };
    } catch (licErr) {
      diagnostics.licenseKeyGeneration = {
        success: false,
        error: licErr.message
      };
      return res.status(500).json({
        success: false,
        step: 'license_generation_failed',
        diagnostics
      });
    }

    // 2. Dispatch email via Resend
    const emailResult = await sendResendEmail({
      to: email,
      name,
      licenseKey,
      paymentId: `test_pay_${Date.now()}`,
      amount: '₹999'
    });

    diagnostics.emailResult = emailResult;

    if (!emailResult.success) {
      return res.status(400).json({
        success: false,
        step: 'resend_email_failed',
        error: emailResult.error || emailResult.warning,
        diagnostics
      });
    }

    return res.status(200).json({
      success: true,
      step: 'email_sent_successfully',
      message: `Test email with license key was successfully dispatched to ${email}! Check your inbox/spam folder.`,
      emailId: emailResult.id,
      licenseKey,
      diagnostics
    });
  } catch (err) {
    console.error('[test-email Error]', err);
    return res.status(500).json({
      success: false,
      error: err.message,
      stack: err.stack
    });
  }
};
