/**
 * DropDial Pro Admin API Gateway
 * Vercel Serverless Function: /api/admin
 * Provides authenticated operational oversight, real cryptographic key generation,
 * transaction ledger, system status checks, and telemetry analytics.
 */

const crypto = require('crypto');
const { generateLicense, sendResendEmail, getPrivateKey } = require('./_utils');

// Default initial master pass phrase if ADMIN_KEY / ADMIN_PASSWORD is not set in environment
const DEFAULT_ADMIN_PASS = 'dropdial2026';

function getAdminSecret() {
  return (
    process.env.ADMIN_KEY ||
    process.env.ADMIN_PASSWORD ||
    process.env.LICENSE_SECRET ||
    DEFAULT_ADMIN_PASS
  ).trim();
}

function verifyToken(req) {
  const authHeader = req.headers['authorization'] || '';
  const queryToken = req.query?.token || '';
  const bodyToken = req.body?.token || '';
  const headerToken = req.headers['x-admin-key'] || '';

  let provided = '';
  if (authHeader.startsWith('Bearer ')) {
    provided = authHeader.slice(7).trim();
  } else if (headerToken) {
    provided = headerToken.trim();
  } else if (bodyToken) {
    provided = bodyToken.trim();
  } else if (queryToken) {
    provided = queryToken.trim();
  }

  const expected = getAdminSecret();
  if (!provided) return false;

  // Constant-time comparison
  try {
    const a = Buffer.from(provided, 'utf8');
    const b = Buffer.from(expected, 'utf8');
    if (a.length !== b.length) return false;
    return crypto.timingSafeEqual(a, b);
  } catch {
    return false;
  }
}

// In-memory buffer for tracking pageviews and conversions in serverless instance
let serverlessStats = {
  pageViews: 1420,
  pricingViews: 485,
  checkoutInitiated: 132,
  purchased: 28,
  lastUpdated: new Date().toISOString()
};

module.exports = async function handler(req, res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization, x-admin-key');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  const action = req.query.action || req.body?.action || 'stats';

  // Public endpoint: lightweight event tracking from landing page (zero PII)
  if (action === 'track') {
    const event = req.body?.event || req.query?.event;
    if (event === 'pageview') serverlessStats.pageViews++;
    if (event === 'pricing') serverlessStats.pricingViews++;
    if (event === 'checkout') serverlessStats.checkoutInitiated++;
    if (event === 'purchase') serverlessStats.purchased++;
    return res.status(200).json({ ok: true });
  }

  // Public endpoint: verify login credentials
  if (action === 'login') {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST required' });
    const { password } = req.body || {};
    const expected = getAdminSecret();
    if (!password) {
      return res.status(400).json({ error: 'Passcode is required' });
    }

    try {
      const a = Buffer.from(password.trim(), 'utf8');
      const b = Buffer.from(expected, 'utf8');
      const valid = a.length === b.length && crypto.timingSafeEqual(a, b);

      if (!valid) {
        return res.status(401).json({ error: 'Invalid admin passcode' });
      }

      return res.status(200).json({
        success: true,
        token: expected,
        message: 'Authenticated successfully'
      });
    } catch (e) {
      return res.status(500).json({ error: e.message });
    }
  }

  // ALL OTHER ACTIONS REQUIRE AUTHENTICATION
  if (!verifyToken(req)) {
    return res.status(401).json({ error: 'Unauthorized: Invalid or missing admin credentials' });
  }

  // 1. STATS & SYSTEM HEALTH
  if (action === 'stats' || action === 'health') {
    const razorpayKey = (process.env.RAZORPAY_KEY_ID || '').trim();
    const razorpaySecret = (process.env.RAZORPAY_KEY_SECRET || '').trim();
    const resendKey = (process.env.RESEND_API_KEY || '').trim();
    const privateKey = getPrivateKey();

    const health = {
      razorpay: {
        configured: Boolean(razorpayKey && razorpaySecret),
        keyIdPrefix: razorpayKey ? razorpayKey.slice(0, 8) + '...' : 'Not set',
        mode: razorpayKey.startsWith('rzp_live') ? 'LIVE (Production)' : razorpayKey.startsWith('rzp_test') ? 'TEST (Sandbox)' : 'Mock / Unset'
      },
      resend: {
        configured: Boolean(resendKey),
        keyPrefix: resendKey ? resendKey.slice(0, 7) + '...' : 'Not set',
        fromEmail: process.env.RESEND_FROM_EMAIL || 'DropDial Pro <onboarding@resend.dev>'
      },
      crypto: {
        algorithm: 'ECDSA P-256 (prime256v1) + SHA-256 (IEEE P1363)',
        loaded: Boolean(privateKey && privateKey.includes('PRIVATE KEY'))
      },
      environment: {
        nodeEnv: process.env.NODE_ENV || 'production',
        isVercel: Boolean(process.env.VERCEL)
      }
    };

    let dbLicenses = [];
    let dbTransactions = [];
    let dbConfigured = false;

    try {
      const { getDb, ensureSchema } = require('./_db');
      const sql = getDb();
      if (sql) {
        dbConfigured = true;
        await ensureSchema();
        dbLicenses = await sql`SELECT id, customer_name as "name", email, license_key as "licenseKey", tier, status, TO_CHAR(created_at, 'YYYY-MM-DD') as "date" FROM licenses ORDER BY created_at DESC LIMIT 100;`;
        dbTransactions = await sql`SELECT id, order_id as "orderId", payment_id as "paymentId", amount as "amountRaw", currency, customer_name as "customerName", email, status, coupon_code as "coupon", country, TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI') as "timestamp" FROM transactions ORDER BY created_at DESC LIMIT 100;`;
      }
    } catch (dbErr) {
      console.warn('[Admin Stats Neon DB Warning]:', dbErr.message);
    }

    return res.status(200).json({
      success: true,
      razorpay: Boolean(razorpayKey && razorpaySecret),
      resend: Boolean(resendKey),
      neonDb: dbConfigured,
      health: {
        ...health,
        neonDb: {
          configured: dbConfigured,
          status: dbConfigured ? 'CONNECTED' : 'NOT_CONFIGURED'
        }
      },
      licenses: dbLicenses,
      transactions: dbTransactions,
      serverlessStats
    });
  }

  // 2. ISSUE PRO LICENSE MANUALLY
  if (action === 'issue-license') {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST required' });
    const { email, name, tier = 'pro', sendEmail = false } = req.body || {};

    if (!email || !email.includes('@')) {
      return res.status(400).json({ error: 'Valid customer email is required' });
    }

    const customerName = (name || 'DropDial Customer').trim();
    const licenseKey = generateLicense(email.trim().toLowerCase(), customerName, tier);

    let emailSent = false;
    let emailId = null;

    if (sendEmail) {
      try {
        const emailResult = await sendResendEmail({
          to: email.trim().toLowerCase(),
          name: customerName,
          licenseKey
        });
        emailSent = emailResult.success;
        emailId = emailResult.id || null;
      } catch (e) {
        console.error('[Admin Issue License] Email error:', e);
      }
    }

    try {
      const { getDb, ensureSchema } = require('./_db');
      const sql = getDb();
      if (sql) {
        await ensureSchema();
        const licId = `lic_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`;
        await sql`
          INSERT INTO licenses (id, customer_name, email, license_key, tier, status, created_at)
          VALUES (${licId}, ${customerName}, ${email.trim().toLowerCase()}, ${licenseKey}, ${tier || 'pro'}, 'active', NOW())
          ON CONFLICT (id) DO NOTHING;
        `;
      }
    } catch (dbErr) {
      console.warn('[Admin Issue License Neon DB Warning]:', dbErr.message);
    }

    return res.status(200).json({
      success: true,
      licenseKey,
      email: email.trim().toLowerCase(),
      name: customerName,
      tier,
      date: new Date().toISOString().slice(0, 10),
      emailSent,
      emailId
    });
  }

  // 3. SEND TEST EMAIL VIA RESEND
  if (action === 'test-email') {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST required' });
    const to = (req.body?.to || req.body?.email || req.query?.to || req.query?.email || '').trim().toLowerCase();
    if (!to || !to.includes('@')) {
      return res.status(400).json({ success: false, error: 'Valid recipient email required' });
    }

    const dummyKey = generateLicense(to, 'Admin Test User', 'pro');
    try {
      const emailResult = await sendResendEmail({
        to,
        name: 'Admin Test User',
        licenseKey: dummyKey
      });
      if (!emailResult.success) {
        return res.status(400).json(emailResult);
      }
      return res.status(200).json(emailResult);
    } catch (e) {
      return res.status(500).json({ success: false, error: e.message });
    }
  }

  // 4. LIST ALL RELEASES (STAGED/DRAFT, ACTIVE, PREVIOUS)
  if (action === 'list-releases') {
    const ghToken = (process.env.GITHUB_TOKEN || process.env.GH_TOKEN || '').trim();
    const owner = process.env.GITHUB_OWNER || 'Nithin1138';
    const repo = process.env.GITHUB_REPO || 'lotus';

    if (!ghToken) {
      let currentVersion = '1.0.0.0';
      try {
        const { getDb, ensureSchema } = require('./_db');
        const sql = getDb();
        if (sql) {
          await ensureSchema();
          const rows = await sql`SELECT value FROM app_settings WHERE key = 'latest_release' LIMIT 1;`;
          if (rows && rows.length > 0 && rows[0].value && rows[0].value.tag_name) {
            currentVersion = rows[0].value.tag_name;
          }
        }
      } catch (_) {}

      return res.status(200).json({
        success: true,
        currentVersion,
        previousVersion: '0.0.0.0',
        availableReleases: [],
        warning: 'GITHUB_TOKEN is not configured on Vercel.'
      });
    }

    try {
      const https = require('https');
      const fetchGH = (path) => new Promise((resolve, reject) => {
        let authHeader = ghToken.startsWith('github_pat_') ? `Bearer ${ghToken}` : `token ${ghToken}`;
        const req = https.request({
          hostname: 'api.github.com',
          path,
          headers: {
            'User-Agent': 'DropDial-Admin-Release',
            'Accept': 'application/vnd.github+json',
            'Authorization': authHeader
          }
        }, res => {
          let body = '';
          res.on('data', chunk => body += chunk);
          res.on('end', () => {
            try {
              resolve({ status: res.statusCode, data: JSON.parse(body) });
            } catch (err) {
              resolve({ status: res.statusCode, data: body });
            }
          });
        });
        req.on('error', reject);
        req.setTimeout(10000, () => { req.destroy(); reject(new Error('GitHub API timeout')); });
        req.end();
      });

      const { status, data } = await fetchGH(`/repos/${owner}/${repo}/releases?per_page=30`);
      if (status < 200 || status >= 300 || !Array.isArray(data)) {
        return res.status(502).json({ error: 'Failed to fetch releases from GitHub', details: data });
      }

      // Map releases with clean metadata
      const releases = data.map(r => ({
        id: r.id,
        tag_name: r.tag_name,
        name: r.name || r.tag_name,
        body: r.body || '',
        draft: Boolean(r.draft),
        prerelease: Boolean(r.prerelease),
        published_at: r.published_at || r.created_at,
        assets: (r.assets || []).map(a => ({
          name: a.name,
          size: a.size,
          download_count: a.download_count
        }))
      }));

      // Active release is the latest published non-draft
      const published = releases.filter(r => !r.draft);
      const current = published[0] || null;
      const previous = published[1] || null;
      
      // Only treat as staged draft if this tag is NOT already published as an active release
      const publishedTags = new Set(published.map(p => p.tag_name.toLowerCase()));
      const stagedDrafts = releases.filter(r => r.draft && !publishedTags.has(r.tag_name.toLowerCase()));

      return res.status(200).json({
        success: true,
        currentVersion: current ? current.tag_name : 'None',
        currentRelease: current,
        previousVersion: previous ? previous.tag_name : 'None',
        previousRelease: previous,
        stagedDrafts,
        allReleases: releases
      });
    } catch (err) {
      return res.status(500).json({ error: err.message });
    }
  }

  // 5. LAUNCH RELEASE (STEP 2: PASSWORD + VERSION CONFIRMATION)
  if (action === 'launch-release') {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST required' });
    const { version, passcode, confirmVersion } = req.body || {};
    const expectedPass = getAdminSecret();

    // Verification 1: Passcode
    if (!passcode) {
      return res.status(400).json({ error: 'Admin passcode is required to launch a release.' });
    }
    const a = Buffer.from(passcode.trim(), 'utf8');
    const b = Buffer.from(expectedPass, 'utf8');
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      return res.status(401).json({ error: 'Invalid admin passcode verification.' });
    }

    // Verification 2: Strict Version Match
    const targetTag = (version || '').trim();
    const typedTag = (confirmVersion || '').trim();
    if (!targetTag) {
      return res.status(400).json({ error: 'Target version tag is required.' });
    }
    if (targetTag.toLowerCase() !== typedTag.toLowerCase()) {
      return res.status(400).json({ error: `Version confirmation mismatch: typed "${typedTag}" does not match target "${targetTag}".` });
    }

    const ghToken = (process.env.GITHUB_TOKEN || process.env.GH_TOKEN || '').trim();
    const owner = process.env.GITHUB_OWNER || 'Nithin1138';
    const repo = process.env.GITHUB_REPO || 'lotus';

    if (!ghToken) {
      return res.status(500).json({ error: 'GITHUB_TOKEN environment variable is not configured.' });
    }

    try {
      const https = require('https');
      const apiReq = (method, path, bodyData = null) => new Promise((resolve, reject) => {
        let authHeader = ghToken.startsWith('github_pat_') ? `Bearer ${ghToken}` : `token ${ghToken}`;
        const reqOpts = {
          hostname: 'api.github.com',
          path,
          method,
          headers: {
            'User-Agent': 'DropDial-Admin-Release',
            'Accept': 'application/vnd.github+json',
            'Authorization': authHeader
          }
        };
        if (bodyData) {
          reqOpts.headers['Content-Type'] = 'application/json';
        }
        const r = https.request(reqOpts, res => {
          let resBody = '';
          res.on('data', chunk => resBody += chunk);
          res.on('end', () => {
            try {
              resolve({ status: res.statusCode, data: JSON.parse(resBody) });
            } catch {
              resolve({ status: res.statusCode, data: resBody });
            }
          });
        });
        r.on('error', reject);
        if (bodyData) r.write(JSON.stringify(bodyData));
        r.end();
      });

      // Find release by tag
      const { status: listStatus, data: listData } = await apiReq('GET', `/repos/${owner}/${repo}/releases?per_page=30`);
      if (listStatus < 200 || listStatus >= 300 || !Array.isArray(listData)) {
        return res.status(502).json({ error: 'Failed to query repository releases' });
      }

      const matched = listData.find(r => r.tag_name.toLowerCase() === targetTag.toLowerCase() || (r.name && r.name.toLowerCase().includes(targetTag.toLowerCase())));
      if (!matched) {
        return res.status(404).json({ error: `Release for version "${targetTag}" not found in repository.` });
      }

      // Publish draft: set draft = false, make_latest = "true"
      const patchPayload = {
        draft: false,
        make_latest: "true"
      };

      const { status: patchStatus, data: patchData } = await apiReq('PATCH', `/repos/${owner}/${repo}/releases/${matched.id}`, patchPayload);
      if (patchStatus < 200 || patchStatus >= 300) {
        return res.status(patchStatus).json({ error: 'Failed to publish release on GitHub', details: patchData });
      }

      // Save launched release to Neon DB app_settings for instant global consistency
      try {
        const { getDb, ensureSchema } = require('./_db');
        const sql = getDb();
        if (sql) {
          await ensureSchema();
          await sql`
            INSERT INTO app_settings (key, value, updated_at)
            VALUES ('latest_release', ${JSON.stringify({ tag_name: targetTag, name: patchData.name || targetTag, published_at: patchData.published_at || new Date().toISOString() })}, NOW())
            ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
          `;
        }
      } catch (dbErr) {
        console.warn('[Admin Launch Release DB Warning]:', dbErr.message);
      }

      return res.status(200).json({
        success: true,
        message: `Version ${targetTag} has been securely verified and launched to production!`,
        release: {
          id: patchData.id,
          tag_name: patchData.tag_name,
          name: patchData.name,
          draft: patchData.draft,
          published_at: patchData.published_at
        }
      });
    } catch (err) {
      return res.status(500).json({ error: err.message });
    }
  }

  // 6. REVERT RELEASE (STEP 2: PASSWORD + VERSION CONFIRMATION)
  if (action === 'revert-release') {
    if (req.method !== 'POST') return res.status(405).json({ error: 'POST required' });
    const { targetVersion, passcode, confirmVersion } = req.body || {};
    const expectedPass = getAdminSecret();

    // Verification 1: Passcode
    if (!passcode) {
      return res.status(400).json({ error: 'Admin passcode is required to revert a release.' });
    }
    const a = Buffer.from(passcode.trim(), 'utf8');
    const b = Buffer.from(expectedPass, 'utf8');
    if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      return res.status(401).json({ error: 'Invalid admin passcode verification.' });
    }

    // Verification 2: Strict Version Match
    const revertTag = (targetVersion || '').trim();
    const typedTag = (confirmVersion || '').trim();
    if (!revertTag) {
      return res.status(400).json({ error: 'Target rollback version is required.' });
    }
    if (revertTag.toLowerCase() !== typedTag.toLowerCase()) {
      return res.status(400).json({ error: `Revert confirmation mismatch: typed "${typedTag}" does not match target "${revertTag}".` });
    }

    const ghToken = (process.env.GITHUB_TOKEN || process.env.GH_TOKEN || '').trim();
    const owner = process.env.GITHUB_OWNER || 'Nithin1138';
    const repo = process.env.GITHUB_REPO || 'lotus';

    if (!ghToken) {
      return res.status(500).json({ error: 'GITHUB_TOKEN environment variable is not configured.' });
    }

    try {
      const https = require('https');
      const apiReq = (method, path, bodyData = null) => new Promise((resolve, reject) => {
        let authHeader = ghToken.startsWith('github_pat_') ? `Bearer ${ghToken}` : `token ${ghToken}`;
        const reqOpts = {
          hostname: 'api.github.com',
          path,
          method,
          headers: {
            'User-Agent': 'DropDial-Admin-Release',
            'Accept': 'application/vnd.github+json',
            'Authorization': authHeader
          }
        };
        if (bodyData) {
          reqOpts.headers['Content-Type'] = 'application/json';
        }
        const r = https.request(reqOpts, res => {
          let resBody = '';
          res.on('data', chunk => resBody += chunk);
          res.on('end', () => {
            try {
              resolve({ status: res.statusCode, data: JSON.parse(resBody) });
            } catch {
              resolve({ status: res.statusCode, data: resBody });
            }
          });
        });
        r.on('error', reject);
        if (bodyData) r.write(JSON.stringify(bodyData));
        r.end();
      });

      // Find release to revert to
      const { status: listStatus, data: listData } = await apiReq('GET', `/repos/${owner}/${repo}/releases?per_page=30`);
      if (listStatus < 200 || listStatus >= 300 || !Array.isArray(listData)) {
        return res.status(502).json({ error: 'Failed to query repository releases' });
      }

      const matched = listData.find(r => r.tag_name.toLowerCase() === revertTag.toLowerCase() || (r.name && r.name.toLowerCase().includes(revertTag.toLowerCase())));
      if (!matched) {
        return res.status(404).json({ error: `Target rollback version "${revertTag}" not found in repository releases.` });
      }

      // Promote this release as latest
      const patchPayload = {
        make_latest: "true"
      };

      const { status: patchStatus, data: patchData } = await apiReq('PATCH', `/repos/${owner}/${repo}/releases/${matched.id}`, patchPayload);
      if (patchStatus < 200 || patchStatus >= 300) {
        return res.status(patchStatus).json({ error: 'Failed to set release as latest on GitHub', details: patchData });
      }

      // Save reverted release to Neon DB app_settings
      try {
        const { getDb, ensureSchema } = require('./_db');
        const sql = getDb();
        if (sql) {
          await ensureSchema();
          await sql`
            INSERT INTO app_settings (key, value, updated_at)
            VALUES ('latest_release', ${JSON.stringify({ tag_name: revertTag, name: patchData.name || revertTag, published_at: patchData.published_at || new Date().toISOString() })}, NOW())
            ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW();
          `;
        }
      } catch (dbErr) {
        console.warn('[Admin Revert Release DB Warning]:', dbErr.message);
      }

      return res.status(200).json({
        success: true,
        message: `Successfully rolled back active production release to version ${revertTag}!`,
        release: {
          id: patchData.id,
          tag_name: patchData.tag_name,
          name: patchData.name,
          published_at: patchData.published_at
        }
      });
    } catch (err) {
      return res.status(500).json({ error: err.message });
    }
  }

  return res.status(400).json({ error: `Unknown action: ${action}` });
};
