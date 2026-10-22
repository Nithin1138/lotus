/**
 * Vercel Serverless Function: Device License Activation & Enforcement
 * POST /api/activate
 *
 * Enforces per-plan device limits:
 * - Single Plan: 1 device strictly
 * - Universal Plan: up to 3 devices
 * - Team Plan: up to 10 devices
 */

const { verifyLicense } = require('./_utils');
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

    // 1. Verify cryptographic signature & decode payload
    const verification = verifyLicense(licenseKey);
    if (!verification.valid) {
      return res.status(400).json({
        error: 'INVALID_LICENSE',
        message: 'Invalid, expired, or counterfeit license key.'
      });
    }

    const payload = verification.payload;
    const tier = (payload.t || 'pro').toLowerCase();

    // Determine max device allowance based on tier
    let maxDevices = 3;
    let planDisplayName = 'Universal Pro';
    if (tier.includes('single') || tier === '1') {
      maxDevices = 1;
      planDisplayName = 'Single Pro';
    } else if (tier.includes('team') || tier === '10') {
      maxDevices = 10;
      planDisplayName = 'Team Pro';
    }

    // 2. Connect to Database & Enforce Device Limits
    const sql = getDb();
    if (!sql) {
      // In standalone/offline fallback, permit valid cryptographic signatures
      return res.status(200).json({
        success: true,
        activated: true,
        tier,
        maxDevices,
        currentDevices: 1,
        message: 'Offline license signature validated.'
      });
    }

    await ensureSchema();

    // Query active device registrations for this license key
    const cleanKey = licenseKey.trim();
    const cleanDeviceId = String(deviceId).trim();

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

      return res.status(200).json({
        success: true,
        activated: true,
        tier,
        planDisplayName,
        currentDevices: existingRows.length,
        maxDevices,
        message: 'Device already registered and verified.'
      });
    }

    // New device activation: check if device limit reached
    if (existingRows.length >= maxDevices) {
      const msg = maxDevices === 1
        ? 'This Single Plan license key is already activated on another device. Single licenses are valid for 1 device only. Deactivate your other device or upgrade to Universal (3 devices) to use it here.'
        : `This ${planDisplayName} license has reached its device limit (${existingRows.length}/${maxDevices} devices). Deactivate an existing device to use it on this machine.`;

      return res.status(403).json({
        success: false,
        error: 'DEVICE_LIMIT_EXCEEDED',
        message: msg,
        currentDevices: existingRows.length,
        maxDevices
      });
    }

    // Register this device under the license
    const actId = `act_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
    await sql`
      INSERT INTO license_activations (id, license_key, device_id, device_name, platform, activated_at, last_seen)
      VALUES (${actId}, ${cleanKey}, ${cleanDeviceId}, ${deviceName || 'Personal Device'}, ${platform || 'desktop'}, NOW(), NOW())
      ON CONFLICT (license_key, device_id) DO UPDATE SET last_seen = NOW();
    `;

    return res.status(200).json({
      success: true,
      activated: true,
      tier,
      planDisplayName,
      currentDevices: existingRows.length + 1,
      maxDevices,
      message: `DropDial Pro successfully activated on this device (${existingRows.length + 1}/${maxDevices} devices used).`
    });
  } catch (err) {
    console.error('[Activate License Error]:', err.message);
    return res.status(500).json({ error: 'Internal server error', message: err.message });
  }
};
