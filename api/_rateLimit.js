/**
 * In-Memory Sliding Window Rate Limiter for DropDial API
 * Protects against brute-force attacks, card testing, spamming, and DoS.
 */

const ipHits = new Map();

// Periodic cleanup of stale IP entries every 5 minutes
const CLEANUP_INTERVAL_MS = 5 * 60 * 1000;
let lastCleanup = Date.now();

function cleanup() {
  const now = Date.now();
  if (now - lastCleanup < CLEANUP_INTERVAL_MS) return;
  lastCleanup = now;

  for (const [key, data] of ipHits.entries()) {
    if (now - data.resetTime > 0) {
      ipHits.delete(key);
    }
  }
}

/**
 * Gets client IP from various edge/proxy headers
 */
function getClientIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (forwarded) {
    const ips = forwarded.split(',').map(s => s.trim());
    if (ips.length > 0 && ips[0]) return ips[0];
  }
  return (
    req.headers['x-real-ip'] ||
    req.headers['cf-connecting-ip'] ||
    req.headers['true-client-ip'] ||
    req.connection?.remoteAddress ||
    req.socket?.remoteAddress ||
    '127.0.0.1'
  );
}

/**
 * Checks rate limit for a specific bucket and IP.
 * @param {object} req - HTTP request
 * @param {string} bucket - Unique identifier for the endpoint/action
 * @param {number} maxHits - Maximum permitted requests in window
 * @param {number} windowMs - Time window in milliseconds
 * @returns {{ allowed: boolean, remaining: number, resetMs: number, ip: string }}
 */
function checkRateLimit(req, bucket = 'default', maxHits = 30, windowMs = 60000) {
  cleanup();

  const ip = getClientIp(req);
  const key = `${bucket}:${ip}`;
  const now = Date.now();

  let record = ipHits.get(key);
  if (!record || now >= record.resetTime) {
    record = {
      count: 1,
      resetTime: now + windowMs
    };
    ipHits.set(key, record);
    return {
      allowed: true,
      remaining: maxHits - 1,
      resetMs: windowMs,
      ip
    };
  }

  record.count += 1;
  const remaining = Math.max(0, maxHits - record.count);
  const resetMs = Math.max(0, record.resetTime - now);

  if (record.count > maxHits) {
    return {
      allowed: false,
      remaining: 0,
      resetMs,
      ip
    };
  }

  return {
    allowed: true,
    remaining,
    resetMs,
    ip
  };
}

module.exports = {
  getClientIp,
  checkRateLimit
};
