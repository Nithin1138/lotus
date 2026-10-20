/**
 * Universal Auto-Detect Download Endpoint
 * GET /download or GET /api/download
 *
 * Inspects client User-Agent and Sec-CH-UA-Platform headers to identify
 * whether the visitor is on macOS or Windows, and immediately redirects (302)
 * to the correct installation binary.
 */

const MAC_DOWNLOAD_URL = 'https://dropdial.app/downloads/DropDial.dmg';
const WIN_DOWNLOAD_URL = 'https://github.com/Nithin1138/lotus/releases/download/0.0.0.0/DropDial-Setup.exe';

module.exports = function handler(req, res) {
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

  // Support JSON inspection via ?format=json
  if (query.format === 'json' || (req.headers.accept && req.headers.accept.includes('application/json'))) {
    return res.status(200).json({
      platform: isMac ? 'macOS' : 'Windows',
      url: targetUrl,
      fileName: fileName,
      command: isMac
        ? 'curl -fsSL https://dropdial.app/install.sh | bash'
        : 'powershell -c "irm https://dropdial.app/install.ps1 | iex"'
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
