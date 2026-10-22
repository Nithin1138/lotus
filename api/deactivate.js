/**
 * Vercel Serverless Function: Device License Deactivation
 * POST /api/deactivate
 *
 * Removes a device registration, freeing up the seat for transfer.
 */

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
    const { licenseKey, deviceId } = body;

    if (!licenseKey || !deviceId) {
      return res.status(400).json({ error: 'License key and device ID are required' });
    }

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
  } catch (err) {
    console.error('[Deactivate License Error]:', err.message);
    return res.status(500).json({ error: 'Internal server error', message: err.message });
  }
};
