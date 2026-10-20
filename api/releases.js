const https = require('https');

const GITHUB_OWNER = 'Nithin1138';
const GITHUB_REPO = 'lotus';

// In-memory cache for release metadata (60 seconds)
let cachedRelease = null;
let cacheTime = 0;
const CACHE_TTL_MS = 60 * 1000;

function getGitHubToken() {
  return (process.env.GITHUB_TOKEN || process.env.GH_TOKEN || '').trim();
}

function fetchLatestRelease(token) {
  return new Promise((resolve, reject) => {
    const now = Date.now();
    if (cachedRelease && now - cacheTime < CACHE_TTL_MS) {
      return resolve(cachedRelease);
    }

    const headers = {
      'User-Agent': 'DropDial-Release-Proxy',
      'Accept': 'application/vnd.github+json'
    };
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    const req = https.request({
      hostname: 'api.github.com',
      path: `/repos/${GITHUB_OWNER}/${GITHUB_REPO}/releases/latest`,
      method: 'GET',
      headers
    }, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          try {
            const data = JSON.parse(body);
            cachedRelease = data;
            cacheTime = Date.now();
            resolve(data);
          } catch (err) {
            reject(new Error('Invalid JSON received from GitHub API'));
          }
        } else {
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

function getAssetRedirectUrl(assetId, token) {
  return new Promise((resolve, reject) => {
    const headers = {
      'User-Agent': 'DropDial-Release-Proxy',
      'Accept': 'application/octet-stream'
    };
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
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

  // Determine base URL (e.g. https://dropdial.app)
  const proto = req.headers['x-forwarded-proto'] || 'https';
  const host = req.headers['x-forwarded-host'] || req.headers.host || 'dropdial.app';
  const baseUrl = `${proto}://${host}`;

  try {
    const release = await fetchLatestRelease(token);

    // 1. Download Mode: ?download=DropDial-macOS.zip
    if (downloadTarget) {
      const asset = (release.assets || []).find(a => 
        a.name.toLowerCase() === downloadTarget.toLowerCase() ||
        a.name.toLowerCase().endsWith(downloadTarget.toLowerCase())
      );

      if (!asset) {
        return res.status(404).json({
          error: `Asset '${downloadTarget}' not found in release ${release.tag_name}.`,
          available: (release.assets || []).map(a => a.name)
        });
      }

      const redirectUrl = await getAssetRedirectUrl(asset.id, token);
      res.writeHead(302, {
        'Location': redirectUrl,
        'Cache-Control': 'no-cache, no-store, must-revalidate'
      });
      return res.end();
    }

    // 2. Metadata Mode: Return release payload with proxied download URLs
    const proxiedAssets = (release.assets || []).map(asset => ({
      id: asset.id,
      name: asset.name,
      size: asset.size,
      content_type: asset.content_type,
      browser_download_url: `${baseUrl}/api/releases?download=${encodeURIComponent(asset.name)}`
    }));

    return res.status(200).json({
      tag_name: release.tag_name,
      name: release.name || release.tag_name,
      body: release.body || '',
      published_at: release.published_at,
      html_url: `${baseUrl}/#download`,
      assets: proxiedAssets
    });

  } catch (error) {
    const isAuthOrNotFound = error.message.includes('404') || error.message.includes('401');
    return res.status(502).json({
      error: 'Unable to check for releases.',
      message: error.message,
      hint: !token ? 'GITHUB_TOKEN environment variable is missing. Please add GITHUB_TOKEN (Personal Access Token with repo read scope) to your Vercel project environment variables.' : (isAuthOrNotFound ? 'GitHub returned 404/401. Verify that GITHUB_TOKEN has access to the private repository Nithin1138/lotus.' : undefined)
    });
  }
};
