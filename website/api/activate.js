/**
 * Vercel Serverless Function: Device License Activation & Enforcement
 * POST /api/activate
 *
 * Enforces per-plan device limits and dispatches activation security email:
 * - Single Plan: 1 device strictly
 * - Universal Plan: up to 3 devices (or dynamically configured)
 * - Team Plan: up to 10 devices
 */

const { verifyLicense, sendDeviceActivationEmail } = require('./_utils');
const { getDb, ensureSchema } = require('./_db');

module.exports = async function handler(req, res) {
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
    const { licenseKey, deviceId, deviceName, platform } = body;

    if (!licenseKey || !deviceId) {
      return res.status(400).json({ error: 'License key and device ID are required' });
    }

    // Check if this is a deactivation request (e.g. POST /api/deactivate)
    const isDeactivate = req.query?.action === 'deactivate' || body.action === 'deactivate' || (req.url && req.url.includes('deactivate'));
    if (isDeactivate) {
      const sql = getDb();
      if (sql) {
        await ensureSchema();
        await sql`
          DELETE FROM license_activations
          WHERE license_key = ${licenseKey.trim()} AND device_id = ${String(deviceId).trim()}
        `;
      }
      return res.status(200).json({
        success: true,
        message: 'Device registration successfully released.'
      });
    }

    // 1. Verify cryptographic signature & decode payload
    const verification = verifyLicense(licenseKey);
    if (!verification.valid) {
      return res.status(400).json({
        error: 'INVALID_LICENSE',
        message: 'Invalid, expired, or counterfeit license key.'
      });
    }

    const payload = verification.payload || {};
    const tier = String(payload.t || 'pro').toLowerCase();
    let customerEmail = payload.e || '';
    let customerName = payload.n || '';

    // Determine device limit based on license plan tier
    let maxDevices = 3;
    let planDisplayName = 'Universal Pro';
    if (tier.includes('single') || tier.includes('solo') || tier === '1') {
      maxDevices = 1;
      planDisplayName = 'Single Platform';
    } else if (tier.includes('team') || tier.includes('commercial') || tier.includes('studio') || tier === '10') {
      const match = tier.match(/\d+/);
      maxDevices = match ? parseInt(match[0], 10) : 10;
      planDisplayName = 'Team License';
    }

    // 2. Connect to Database & Enforce Device Limits
    const sql = getDb();
    if (!sql) {
      // In standalone/offline fallback, permit valid cryptographic signatures
      return res.status(200).json({
        success: true,
        activated: true,
        tier,
        planDisplayName,
        maxDevices,
        currentDevices: 1,
        remainingDevices: Math.max(0, maxDevices - 1),
        message: `Offline license signature validated (${planDisplayName}).`
      });
    }

    await ensureSchema();

    const cleanKey = licenseKey.trim();
    const cleanDeviceId = String(deviceId).trim();

    // Query custom device setting or license record override if available
    try {
      if (tier.includes('pro') || tier.includes('universal') || tier === 'pro') {
        const settingRows = await sql`SELECT value FROM app_settings WHERE key = 'pricing_devices' LIMIT 1`;
        if (settingRows && settingRows.length > 0 && settingRows[0].value) {
          const customDevices = parseInt(settingRows[0].value, 10);
          if (!isNaN(customDevices) && customDevices > 0) {
            maxDevices = customDevices;
          }
        }
      }

      const licRows = await sql`SELECT customer_name, email, tier FROM licenses WHERE license_key = ${cleanKey} LIMIT 1`;
      if (licRows && licRows.length > 0) {
        const dbLic = licRows[0];
        if (!customerEmail && dbLic.email) customerEmail = dbLic.email;
        if (!customerName && dbLic.customer_name) customerName = dbLic.customer_name;
        if (dbLic.tier) {
          const dbTier = dbLic.tier.toLowerCase();
          if (dbTier.includes('single')) {
            maxDevices = 1;
            planDisplayName = 'Single Platform';
          } else if (dbTier.includes('team')) {
            const match = dbTier.match(/\d+/);
            maxDevices = match ? parseInt(match[0], 10) : 10;
            planDisplayName = 'Team License';
          }
        }
      }
    } catch (_) {}

    // Query active device registrations for this license key
    const existingRows = await sql`
      SELECT device_id, device_name, platform, activated_at
      FROM license_activations
      WHERE license_key = ${cleanKey}
    `;

    const alreadyRegistered = existingRows.some(r => r.device_id === cleanDeviceId);

    if (alreadyRegistered) {
      await sql`
        UPDATE license_activations
        SET last_seen = NOW(),
            device_name = COALESCE(${deviceName || null}, device_name)
        WHERE license_key = ${cleanKey} AND device_id = ${cleanDeviceId}
      `;

      const currentDevices = existingRows.length;
      const remainingDevices = Math.max(0, maxDevices - currentDevices);

      return res.status(200).json({
        success: true,
        activated: true,
        tier,
        planDisplayName,
        currentDevices,
        maxDevices,
        remainingDevices,
        message: `Device already registered (${currentDevices}/${maxDevices} active, ${remainingDevices} remaining).`
      });
    }

    // New device activation: check if device limit reached
    if (existingRows.length >= maxDevices) {
      const msg = maxDevices === 1
        ? 'This Single Plan license key is already activated on another device. Single licenses are valid for 1 device only. Deactivate your other device or upgrade to Universal (3 devices) to use it here.'
        : `This ${planDisplayName} license has reached its device limit (${existingRows.length}/${maxDevices} devices active). Deactivate an existing device to use it on this machine.`;

      return res.status(403).json({
        success: false,
        error: 'DEVICE_LIMIT_EXCEEDED',
        message: msg,
        currentDevices: existingRows.length,
        maxDevices,
        remainingDevices: 0
      });
    }

    // Register this device under the license
    const actId = `act_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    await sql`
      INSERT INTO license_activations (id, license_key, device_id, device_name, platform, activated_at, last_seen)
      VALUES (${actId}, ${cleanKey}, ${cleanDeviceId}, ${deviceName || 'Personal Device'}, ${platform || 'desktop'}, NOW(), NOW())
      ON CONFLICT (license_key, device_id) DO UPDATE SET last_seen = NOW();
    `;

    const newActiveCount = existingRows.length + 1;
    const remainingDevices = Math.max(0, maxDevices - newActiveCount);

    // Send email alert to user detailing device name and remaining activations
    if (customerEmail) {
      sendDeviceActivationEmail({
        to: customerEmail,
        name: customerName,
        planDisplayName,
        deviceName: deviceName || 'Personal Device',
        platform: platform || 'Desktop',
        currentDevices: newActiveCount,
        maxDevices
      }).catch(mailErr => console.warn('[Activation Email Delivery Warning]:', mailErr.message));
    }

    return res.status(200).json({
      success: true,
      activated: true,
      tier,
      planDisplayName,
      currentDevices: newActiveCount,
      maxDevices,
      remainingDevices,
      message: `DropDial ${planDisplayName} successfully activated on this device (${newActiveCount}/${maxDevices} used, ${remainingDevices} remaining).`
    });
  } catch (err) {
    console.error('[Activate License Error]:', err.message);
    return res.status(500).json({ error: 'Internal server error', message: err.message });
  }
};
