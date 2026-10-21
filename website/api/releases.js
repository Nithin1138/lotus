const https = require('https');

const GITHUB_OWNER = 'Nithin1138';
const GITHUB_REPO = 'lotus';

// In-memory cache for release metadata (60 seconds)
let cachedRelease = null;
let cacheTime = 0;
const CACHE_TTL_MS = 60 * 1000;

function getGitHubToken() {
  let token = (process.env.GITHUB_TOKEN || process.env.GH_TOKEN || '').trim();
  if ((token.startsWith('"') && token.endsWith('"')) || (token.startsWith("'") && token.endsWith("'"))) {
    token = token.slice(1, -1).trim();
  }
  if (token.startsWith('GITHUB_TOKEN=')) {
    token = token.slice(13).trim();
  } else if (token.startsWith('GH_TOKEN=')) {
    token = token.slice(9).trim();
  }
  if (token.startsWith('Bearer ')) {
    token = token.slice(7).trim();
  } else if (token.startsWith('token ')) {
    token = token.slice(6).trim();
  }
  return token;
}

function getAuthHeader(token) {
  if (!token) return null;
  if (token.startsWith('github_pat_')) {
    return `Bearer ${token}`;
  }
  return `token ${token}`;
}

function sanitizeReleaseBody(body) {
  if (!body) return '';
  let clean = body;
  // Rewrite raw GitHub script URLs to official dropdial.app endpoints
  clean = clean.replace(/https?:\/\/raw\.githubusercontent\.com\/[^\/]+\/[^\/]+\/[^\/]+\/install\.ps1/gi, 'https://dropdial.app/install.ps1');
  clean = clean.replace(/https?:\/\/raw\.githubusercontent\.com\/[^\/]+\/[^\/]+\/[^\/]+\/install\.sh/gi, 'https://dropdial.app/install.sh');
  clean = clean.replace(/https?:\/\/github\.com\/[^\/]+\/[^\/]+\/releases\/[^\s\)]+/gi, 'https://dropdial.app/#download');
  clean = clean.replace(/https?:\/\/github\.com\/[^\/]+\/[^\/]+/gi, 'https://dropdial.app');

  // Future-proof Apple Silicon naming to M-Series and onwards
  clean = clean.replace(/Apple Silicon\s*\((?:M1,\s*M2,\s*M3,\s*M4|M1–M4|M1-M4)\)/gi, 'Apple Silicon (M-Series and onwards)');
  clean = clean.replace(/Apple Silicon\s*\(M1,\s*M2,\s*M3,\s*M4\s*and onwards\)/gi, 'Apple Silicon (M-Series and onwards)');
  clean = clean.replace(/Apple Silicon\s*M1[–\-]M4/gi, 'Apple Silicon M-Series and onwards');
  clean = clean.replace(/Apple Silicon\s*M1,\s*M2,\s*M3,\s*M4/gi, 'Apple Silicon M-Series and onwards');

  return clean;
}

let activeOverrideTag = null;

function fetchRelease(token, targetTag = null) {
  return new Promise((resolve, reject) => {
    const effectiveTag = targetTag || activeOverrideTag;
    const now = Date.now();
    if (!effectiveTag && cachedRelease && now - cacheTime < CACHE_TTL_MS) {
      return resolve(cachedRelease);
    }

    const headers = {
      'User-Agent': 'DropDial-Release-Proxy',
      'Accept': 'application/vnd.github+json'
    };
    const auth = getAuthHeader(token);
    if (auth) {
      headers['Authorization'] = auth;
    }

    const apiPath = effectiveTag 
      ? `/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/tags/${encodeURIComponent(effectiveTag)}`
      : `/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`;

    const req = https.request({
      hostname: 'api.github.com',
      path: apiPath,
      method: 'GET',
      headers
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            const data = JSON.parse(body);
            if (!effectiveTag) {
              cachedRelease = data;
              cacheTime = Date.now();
            }
            resolve(data);
          } catch (err) {
            reject(new Error('Invalid JSON received from GitHub API'));
          }
        } else {
          // If tag lookup failed or latest 404, reject with message
          reject(new Error(`GitHub API returned status ${res.statusCode}: ${body.slice(0, 100)}`));
        }
      });
    });

    req.on('error', reject);
    req.setTimeout(10000, () => {
      req.destroy();
      reject(new Error('GitHub API request timed out'));
    });
    req.end();
  });
}

function fetchLatestRelease(token) {
  return fetchRelease(token, null);
}

function getAssetRedirectUrl(assetId, token) {
  return new Promise((resolve, reject) => {
    const headers = {
      'User-Agent': 'DropDial-Release-Proxy',
      'Accept': 'application/octet-stream'
    };
    const auth = getAuthHeader(token);
    if (auth) {
      headers['Authorization'] = auth;
    }

    const req = https.request({
      hostname: 'api.github.com',
      path: `/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/assets/${assetId}`,
      method: 'GET',
      headers
    }, (res) => {
      // GitHub redirects (302) to pre-signed S3 / Azure blob URL
      if (res.statusCode === 302 && res.headers.location) {
        resolve(res.headers.location);
      } else {
        reject(new Error(`Failed to get asset download URL (status ${res.statusCode})`));
      }
    });

    req.on('error', reject);
    req.setTimeout(10000, () => {
      req.destroy();
      reject(new Error('Asset request timed out'));
    });
    req.end();
  });
}

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const token = getGitHubToken();
  const query = req.query || {};
  const downloadTarget = (query.download || query.asset || '').trim();

  // Determine base URL (defaulting to https://dropdial.app)
  const proto = req.headers['x-forwarded-proto'] || 'https';
  const host = req.headers['x-forwarded-host'] || req.headers.host || 'dropdial.app';
  const baseUrl = `${proto}://${host}`;

  // 1. Download Mode: prioritize dropdial.app direct hosted assets for 100% uptime
  if (downloadTarget) {
    const lower = downloadTarget.toLowerCase();
    if (lower.includes('.dmg')) {
      res.writeHead(302, { 'Location': `${baseUrl}/downloads/DropDial.dmg` });
      return res.end();
    }
    if (lower.includes('macos.zip') || lower.includes('mac.zip')) {
      res.writeHead(302, { 'Location': `${baseUrl}/downloads/DropDial-macOS.zip` });
      return res.end();
    }
    if (lower.includes('setup.exe')) {
      res.writeHead(302, { 'Location': `${baseUrl}/downloads/DropDial-Setup.exe` });
      return res.end();
    }
    if (lower.includes('windows') || lower.includes('win')) {
      res.writeHead(302, { 'Location': `${baseUrl}/downloads/DropDial-Windows-x64.zip` });
      return res.end();
    }
    if (lower.endsWith('.exe')) {
      res.writeHead(302, { 'Location': `${baseUrl}/downloads/DropDial.exe` });
      return res.end();
    }
  }

  // Canonical DropDial self-hosted assets list (zero GitHub dependency)
  const canonicalAssets = [
    {
      id: 1,
      name: 'DropDial-Setup.exe',
      size: 69321891,
      content_type: 'application/x-msdownload',
      browser_download_url: `${baseUrl}/downloads/DropDial-Setup.exe`
    },
    {
      id: 2,
      name: 'DropDial.dmg',
      size: 4387115,
      content_type: 'application/x-apple-diskimage',
      browser_download_url: `${baseUrl}/downloads/DropDial.dmg`
    },
    {
      id: 3,
      name: 'DropDial-macOS.zip',
      size: 4115971,
      content_type: 'application/zip',
      browser_download_url: `${baseUrl}/downloads/DropDial-macOS.zip`
    },
    {
      id: 4,
      name: 'DropDial-Windows-x64.zip',
      size: 96049041,
      content_type: 'application/zip',
      browser_download_url: `${baseUrl}/downloads/DropDial-Windows-x64.zip`
    },
    {
      id: 5,
      name: 'DropDial.exe',
      size: 208896,
      content_type: 'application/x-msdownload',
      browser_download_url: `${baseUrl}/downloads/DropDial.exe`
    }
  ];

  try {
    if (token) {
      const release = await fetchLatestRelease(token);
      if (release && release.tag_name) {
        const effectiveTag = (release.tag_name === 'v1.0.1.0' || release.tag_name === '1.0.1.0') ? '1.0.1.1' : release.tag_name;
        return res.status(200).json({
          tag_name: effectiveTag,
          version: effectiveTag,
          latest_version: effectiveTag,
          name: release.name ? release.name.replace('1.0.1.0', '1.0.1.1') : `DropDial ${effectiveTag}`,
          body: sanitizeReleaseBody(release.body),
          published_at: release.published_at,
          html_url: `${baseUrl}/#download`,
          assets: canonicalAssets
        });
      }
    }
  } catch (error) {
    console.warn('[DropDial Release Service] Serving canonical release assets:', error.message);
  }

  // Check if Neon DB has a latest_release saved by admin via 2-step verification
  let activeTag = '1.0.1.2';
  try {
    const { getDb, ensureSchema } = require('./_db');
    const sql = getDb();
    if (sql) {
      await ensureSchema();
      const rows = await sql`SELECT value FROM app_settings WHERE key = 'latest_release' LIMIT 1;`;
      if (rows && rows.length > 0 && rows[0].value && rows[0].value.tag_name) {
        activeTag = rows[0].value.tag_name;
      }
    }
  } catch (_) {}

  return res.status(200).json({
    tag_name: activeTag,
    version: activeTag,
    latest_version: activeTag,
    name: `DropDial ${activeTag}`,
    body: 'High-performance offline conversions, Actions Dial, and media tools for macOS and Windows.',
    published_at: new Date().toISOString(),
    html_url: `${baseUrl}/#download`,
    assets: canonicalAssets
  });
};
