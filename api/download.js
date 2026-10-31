/**
 * Universal Auto-Detect Download Endpoint
 * GET /download or GET /api/download
 *
 * Inspects client User-Agent and Sec-CH-UA-Platform headers to identify
 * whether the visitor is on macOS or Windows, and immediately redirects (302)
 * to the correct installation binary.
 */

module.exports = function handler(req, res) {
  const reqHost = (req.headers['x-forwarded-host'] || req.headers.host || '').toLowerCase();
  const baseUrl = reqHost.includes('www.dropdial.app') ? 'https://www.dropdial.app' : 'https://dropdial.app';
  const MAC_DOWNLOAD_URL = `${baseUrl}/downloads/DropDial.dmg`;
  const WIN_DOWNLOAD_URL = `${baseUrl}/downloads/DropDial-Setup.exe`;
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const query = req.query || {};
  const ua = (req.headers['user-agent'] || '').toLowerCase();
  const platformHeader = (req.headers['sec-ch-ua-platform'] || '').toLowerCase();

  let isMac = false;

  // Explicit override via query param ?os=mac or ?os=win or ?platform=mac
  const forcedPlatform = (query.os || query.platform || '').toLowerCase();
  if (forcedPlatform === 'mac' || forcedPlatform === 'macos' || forcedPlatform === 'darwin') {
    isMac = true;
  } else if (forcedPlatform === 'win' || forcedPlatform === 'windows') {
    isMac = false;
  } else if (platformHeader.includes('mac') || platformHeader.includes('darwin')) {
    isMac = true;
  } else if (platformHeader.includes('win')) {
    isMac = false;
  } else if (/macintosh|mac os x|darwin/i.test(ua)) {
    isMac = true;
  } else if (/windows|win32|win64/i.test(ua)) {
    isMac = false;
  } else {
    // Fallback: Check mobile Apple devices or default to macOS
    isMac = /iphone|ipad|ipod/i.test(ua);
  }

  const targetUrl = isMac ? MAC_DOWNLOAD_URL : WIN_DOWNLOAD_URL;
  const fileName = isMac ? 'DropDial.dmg' : 'DropDial-Setup.exe';

  // 100% Real Download Telemetry: log download execution to Neon PostgreSQL user_events
  try {
    const { getDb } = require('./_db');
    const sql = getDb();
    if (sql) {
      const evtId = 'evt_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7);
      const sessId = (query.session_id || 'session_' + Math.random().toString(36).substring(2, 11)).trim();
      const meta = {
        platform: isMac ? 'macOS' : 'Windows',
        fileName,
        targetUrl,
        userAgent: ua,
        ip: req.headers['x-forwarded-for'] || req.socket?.remoteAddress || 'unknown',
        referrer: req.headers['referer'] || 'direct'
      };
      sql`
        INSERT INTO user_events (id, session_id, event_type, page, metadata, created_at)
        VALUES (${evtId}, ${sessId}, 'DOWNLOAD_REDIRECT', 'download', ${JSON.stringify(meta)}::jsonb, NOW())
        ON CONFLICT (id) DO NOTHING;
      `.catch(() => {});
    }
  } catch (_) {}

  // Support JSON inspection via ?format=json
  if (query.format === 'json' || (req.headers.accept && req.headers.accept.includes('application/json'))) {
    return res.status(200).json({
      platform: isMac ? 'macOS' : 'Windows',
      url: targetUrl,
      fileName: fileName,
      command: isMac
        ? `curl -fsSL ${baseUrl}/install.sh | bash`
        : `irm ${baseUrl}/install.ps1 | iex`
    });
  }

  // HTTP 302 Redirect directly to the appropriate installer
  res.writeHead(302, {
    'Location': targetUrl,
    'Cache-Control': 'no-cache, no-store, must-revalidate',
    'X-Detected-Platform': isMac ? 'macOS' : 'Windows'
  });
  return res.end();
};
