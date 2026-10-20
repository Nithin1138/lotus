/**
 * DropDial Checkout & Licensing Client Integration
 * Handles Automatic Country-Based Pricing (₹999 in India, $19 Worldwide),
 * Coupon Code Discounts, Razorpay Checkout Modal, Order Creation,
 * Payment Verification, and Instant Delivery via Resend.
 *
 * NOTE: UI uses clean SVG icons ONLY (no emojis, except country flags).
 */

(function () {
  'use strict';

  // Currency configuration
  const PRICING = {
    INR: { code: 'INR', symbol: '₹', amount: 999, display: '₹999' },
    USD: { code: 'USD', symbol: '$', amount: 19, display: '$19' }
  };

  // State
  let currentCountry = 'US';
  let isIndia = false;
  let selectedCurrency = 'USD';
  let appliedCoupon = null;

  // Modal DOM Elements
  let overlay, formView, successView, errorBox, payBtn;
  let nameInput, emailInput, priceDisplay, copyBtn, licenseKeyDisplay, successEmailText;
  let couponToggleBtn, couponInputWrap, couponCodeInput, couponApplyBtn, couponFeedback;

  /**
   * Fast, zero-latency client-side heuristic detection
   * Detects Indian timezone / locale immediately before network calls
   */
  function detectFastLocation() {
    try {
      const tz = (Intl.DateTimeFormat().resolvedOptions().timeZone || '').toLowerCase();
      const offset = new Date().getTimezoneOffset(); // -330 is IST (UTC+5:30)
      const langs = (navigator.languages || [navigator.language || '']).map(l => (l || '').toLowerCase());

      const tzMatchesIndia = tz.includes('kolkata') || tz.includes('calcutta') || offset === -330;
      const langMatchesIndia = langs.some(l => l.endsWith('-in') || l.includes('hi-in') || l === 'en-in');

      if (tzMatchesIndia || langMatchesIndia) {
        return { isIndia: true, country: 'IN', currency: 'INR' };
      }
    } catch (e) {
      // Fallback safe
    }
    return { isIndia: false, country: 'US', currency: 'USD' };
  }

  /**
   * Calculates the active price considering any applied coupon
   */
  function getActivePriceConfig() {
    const base = PRICING[selectedCurrency];
    if (!appliedCoupon) {
      return {
        amount: base.amount,
        display: base.display,
        oldPrice: null,
        discountTag: null
      };
    }

    let discountAmount = 0;
    if (appliedCoupon.type === 'percent') {
      discountAmount = Math.round(base.amount * (appliedCoupon.value / 100));
    } else {
      discountAmount = isIndia ? (appliedCoupon.valueInr || 200) : (appliedCoupon.valueUsd || 4);
    }

    const finalAmount = Math.max(1, base.amount - discountAmount);
    const finalDisplay = `${base.symbol}${finalAmount}`;
    const discountTag = appliedCoupon.type === 'percent'
      ? `-${appliedCoupon.value}%`
      : `-${base.symbol}${discountAmount}`;

    return {
      amount: finalAmount,
      display: finalDisplay,
      oldPrice: base.display,
      discountTag: discountTag
    };
  }

  /**
   * Applies localized pricing to the checkout modal and the landing page
   */
  function applyPricing(indiaFlag, countryCode) {
    isIndia = !!indiaFlag;
    selectedCurrency = isIndia ? 'INR' : 'USD';
    currentCountry = countryCode || (isIndia ? 'IN' : 'US');
    const priceConfig = getActivePriceConfig();

    // 1. Modal Elements
    if (priceDisplay) {
      if (priceConfig.oldPrice) {
        priceDisplay.innerHTML = `
          <div class="cko-price-group">
            <span class="cko-price-old">${priceConfig.oldPrice}</span>
            <span class="cko-price-new">${priceConfig.display}</span>
            <span class="cko-price-badge">${priceConfig.discountTag} OFF</span>
          </div>
        `;
      } else {
        priceDisplay.innerHTML = `<span class="cko-price-standard">${priceConfig.display}</span>`;
      }
    }

    const payLabel = document.getElementById('checkout-pay-label');
    if (payLabel) {
      payLabel.textContent = `Proceed to Payment (${priceConfig.display})`;
    }

    // 2. Landing Page Buttons & Pricing Card (base pricing)
    const baseConfig = PRICING[selectedCurrency];
    const headerBuy = document.getElementById('nav-header-buy-btn');
    if (headerBuy) {
      headerBuy.textContent = `Buy Pro (${baseConfig.display})`;
    }

    const navBuy = document.getElementById('nav-buy-btn');
    if (navBuy) {
      navBuy.textContent = `Buy Pro (${baseConfig.display})`;
    }

    const pricingCardPrice = document.getElementById('pro-pricing-price');
    if (pricingCardPrice) {
      pricingCardPrice.innerHTML = `${baseConfig.display} <span>one-time</span>`;
    }

    const trialPricingPrice = document.getElementById('trial-pricing-price');
    if (trialPricingPrice) {
      trialPricingPrice.innerHTML = `${baseConfig.symbol}0 <span>/ 7 days</span>`;
    }

    const cardBuy = document.getElementById('card-buy-btn');
    if (cardBuy) {
      cardBuy.textContent = `Buy DropDial Pro (${baseConfig.display})`;
    }
  }

  /**
   * Async server-edge geolocation detection & dynamic live pricing
   */
  async function fetchCountryPricing() {
    // 1. Fetch live dynamic base pricing
    try {
      const pRes = await fetch('/api/pricing', { method: 'GET', cache: 'default' });
      if (pRes.ok) {
        const pData = await pRes.json();
        if (pData && pData.pricing) {
          if (pData.pricing.INR && pData.pricing.INR.amount) {
            PRICING.INR = {
              code: 'INR',
              symbol: pData.pricing.INR.symbol || '₹',
              amount: pData.pricing.INR.amount,
              display: pData.pricing.INR.display || `₹${pData.pricing.INR.amount}`
            };
          }
          if (pData.pricing.USD && pData.pricing.USD.amount) {
            PRICING.USD = {
              code: 'USD',
              symbol: pData.pricing.USD.symbol || '$',
              amount: pData.pricing.USD.amount,
              display: pData.pricing.USD.display || `$${pData.pricing.USD.amount}`
            };
          }
        }
      }
    } catch (e) {}

    // 2. Fetch Geo detection
    try {
      const res = await fetch('/api/geo', { method: 'GET', cache: 'default' });
      if (res.ok) {
        const data = await res.json();
        if (data && typeof data.isIndia === 'boolean') {
          applyPricing(data.isIndia, data.country);
          return;
        }
      }
    } catch (err) {
      try {
        const fallbackRes = await fetch('https://api.country.is/', { cache: 'default' });
        if (fallbackRes.ok) {
          const fallbackData = await fallbackRes.json();
          const country = (fallbackData.country || '').toUpperCase();
          applyPricing(country === 'IN', country);
          return;
        }
      } catch (e2) {
        // Retain heuristic
      }
    }
    applyPricing(isIndia, currentCountry);
  }

  function init() {
    // 1. Instant heuristic detection
    const initial = detectFastLocation();
    isIndia = initial.isIndia;
    selectedCurrency = initial.currency;
    currentCountry = initial.country;

    // 2. Build Modal DOM & bind listeners
    createModalDOM();
    bindEvents();

    // 3. Sync pricing with modal DOM
    applyPricing(isIndia, currentCountry);

    // 4. Edge geo refinement in background
    fetchCountryPricing();
  }

  function createModalDOM() {
    overlay = document.createElement('div');
    overlay.className = 'checkout-modal-overlay';
    overlay.id = 'dropdial-checkout-overlay';

    overlay.innerHTML = `
      <div class="checkout-modal" role="dialog" aria-modal="true" aria-labelledby="checkout-modal-heading">

        <!-- ── Header ── -->
        <div class="cko-header">
          <div class="cko-header-brand">
            <div class="cko-logo-wrap">
              <img src="/assets/img/logo.png" alt="DropDial" width="32" height="32">
            </div>
            <div class="cko-header-text">
              <span class="cko-title" id="checkout-modal-heading">DropDial Pro</span>
              <span class="cko-subtitle">Lifetime License</span>
            </div>
          </div>
          <button type="button" class="cko-close-btn" id="checkout-close" aria-label="Close checkout">
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
          </button>
        </div>

        <!-- ── Body ── -->
        <div class="cko-body">

          <!-- Form View -->
          <div id="checkout-form-view">

            <!-- Price Hero -->
            <div class="cko-price-hero">
              <div class="cko-price-left">
                <div class="cko-price-display-wrap" id="checkout-price-display">
                  <span class="cko-price-standard">₹999</span>
                </div>
                <div class="cko-one-time-label">One-time · No subscription</div>
              </div>
              <div class="cko-feature-pills">
                <span class="cko-pill">
                  <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
                  3 Devices
                </span>
                <span class="cko-pill">
                  <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
                  All Updates
                </span>
                <span class="cko-pill">
                  <svg width="11" height="11" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
                  Offline
                </span>
              </div>
            </div>

            <!-- Divider -->
            <div class="cko-divider"></div>

            <!-- Coupon Section — feedback is OUTSIDE input-wrap so Remove always works -->
            <div class="cko-coupon-wrap" id="checkout-coupon-section">
              <!-- State 0: Toggle link -->
              <button type="button" class="cko-coupon-toggle" id="coupon-toggle-btn">
                <svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2">
                  <path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z"/>
                  <line x1="7" y1="7" x2="7.01" y2="7"/>
                </svg>
                Have a coupon?
              </button>

              <!-- State 1: Input row (hidden until toggle clicked) -->
              <div class="cko-coupon-input-row" id="coupon-input-wrap" style="display:none;">
                <input type="text" id="coupon-code-input" class="cko-coupon-input" placeholder="COUPON CODE" autocomplete="off" autocapitalize="characters" spellcheck="false">
                <button type="button" id="coupon-apply-btn" class="cko-coupon-apply-btn">Apply</button>
                <button type="button" class="cko-coupon-cancel-btn" id="coupon-cancel-btn" title="Cancel">
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><line x1="18" y1="6" x2="6" y2="18"/><line x1="6" y1="6" x2="18" y2="18"/></svg>
                </button>
              </div>

              <!-- State 2: Error / Success feedback — OUTSIDE input-wrap, always accessible -->
              <div class="cko-coupon-feedback" id="coupon-feedback" style="display:none;"></div>
            </div>

            <!-- Error Banner -->
            <div class="cko-error-banner" id="checkout-error" style="display:none;"></div>

            <!-- Fields -->
            <div class="cko-field">
              <label class="cko-label" for="checkout-name">Full Name</label>
              <input type="text" id="checkout-name" class="cko-input" placeholder="e.g. Alex Smith" required autocomplete="name">
            </div>

            <div class="cko-field">
              <label class="cko-label" for="checkout-email">Email <span class="cko-label-note">(License key delivered here)</span></label>
              <input type="email" id="checkout-email" class="cko-input" placeholder="e.g. alex@example.com" required autocomplete="email">
            </div>

            <!-- Pay Button -->
            <button type="button" class="cko-pay-btn" id="checkout-pay-btn">
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
              <span id="checkout-pay-label">Proceed to Payment (₹999)</span>
            </button>

            <!-- Trust Row -->
            <div class="cko-trust-row">
              <span class="cko-trust-item">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/></svg>
                256-bit Secure
              </span>
              <span class="cko-trust-sep">·</span>
              <span class="cko-trust-item">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>
                Instant Delivery
              </span>
              <span class="cko-trust-sep">·</span>
              <span class="cko-trust-item">
                <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/></svg>
                Lifetime Guarantee
              </span>
            </div>
          </div>

          <!-- ── Success View ── -->
          <div class="cko-success-view" id="checkout-success-view" style="display:none;">
            <div class="cko-success-icon">
              <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
            </div>
            <h3 class="cko-success-title">Payment Successful!</h3>
            <p class="cko-success-sub">DropDial Pro lifetime license activated</p>

            <div class="cko-license-box">
              <div class="cko-license-header">
                <span class="cko-license-label">LIFETIME LICENSE KEY</span>
                <span class="cko-license-active"><span class="cko-active-dot"></span>ACTIVE</span>
              </div>
              <div class="cko-license-row">
                <input type="text" id="license-key-display" class="cko-license-input" readonly value="DD-..." spellcheck="false" title="Click to select">
                <button type="button" class="cko-copy-btn" id="copy-license-btn" aria-label="Copy License Key">
                  <svg class="copy-svg" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>
                  <span class="copy-lbl">Copy</span>
                </button>
              </div>
            </div>

            <div class="cko-success-note">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/><polyline points="22,6 12,13 2,6"/></svg>
              Backup copy sent to <strong id="success-email-text">your email</strong>
            </div>

            <div class="cko-success-actions">
              <a href="/downloads/DropDial.dmg" class="cko-btn-download" id="download-now-btn">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                Download App
              </a>
              <button type="button" class="cko-btn-done" id="success-done-btn">Done</button>
            </div>
          </div>

        </div>
      </div>
    `;

    document.body.appendChild(overlay);

    // Cache elements
    formView = document.getElementById('checkout-form-view');
    successView = document.getElementById('checkout-success-view');
    errorBox = document.getElementById('checkout-error');
    payBtn = document.getElementById('checkout-pay-btn');
    nameInput = document.getElementById('checkout-name');
    emailInput = document.getElementById('checkout-email');
    priceDisplay = document.getElementById('checkout-price-display');
    copyBtn = document.getElementById('copy-license-btn');
    licenseKeyDisplay = document.getElementById('license-key-display');
    successEmailText = document.getElementById('success-email-text');

    couponToggleBtn = document.getElementById('coupon-toggle-btn');
    couponInputWrap = document.getElementById('coupon-input-wrap');
    couponCodeInput = document.getElementById('coupon-code-input');
    couponApplyBtn = document.getElementById('coupon-apply-btn');
    couponFeedback = document.getElementById('coupon-feedback');
  }


  function bindEvents() {
    // Close modal
    document.getElementById('checkout-close').addEventListener('click', closeModal);
    overlay.addEventListener('click', function (e) {
      if (e.target === overlay) {
        closeModal();
      }
    });

    document.getElementById('success-done-btn').addEventListener('click', closeModal);
    document.getElementById('download-now-btn').addEventListener('click', function () {
      closeModal();
    });

    // ESC key closes modal
    document.addEventListener('keydown', function (e) {
      if (e.key === 'Escape' && overlay.classList.contains('active')) {
        closeModal();
      }
    });

    // Coupon Toggle
    couponToggleBtn?.addEventListener('click', function () {
      couponToggleBtn.style.display = 'none';
      couponInputWrap.style.display = 'flex';
      couponCodeInput.focus();
    });

    // Coupon Cancel (X button in input row)
    document.getElementById('coupon-cancel-btn')?.addEventListener('click', function () {
      couponInputWrap.style.display = 'none';
      couponCodeInput.value = '';
      couponFeedback.style.display = 'none';
      couponToggleBtn.style.display = 'inline-flex';
    });

    // Coupon Apply
    couponApplyBtn?.addEventListener('click', handleCouponApply);
    couponCodeInput?.addEventListener('keydown', function (e) {
      if (e.key === 'Enter') {
        e.preventDefault();
        handleCouponApply();
      }
    });

    // Triggers across the page
    const triggers = [
      '#nav-buy-btn',
      '#nav-header-buy-btn',
      '#card-buy-btn',
      '#hero-buy-btn',
      '[data-open-checkout]'
    ];

    triggers.forEach(function (sel) {
      document.querySelectorAll(sel).forEach(function (el) {
        el.addEventListener('click', function (e) {
          e.preventDefault();
          openModal();
        });
      });
    });

    // Pay Button Click
    payBtn.addEventListener('click', handlePaymentInitiation);

    // Copy License Key Button
    copyBtn.addEventListener('click', function () {
      const key = (licenseKeyDisplay.value || licenseKeyDisplay.getAttribute('data-full-key') || licenseKeyDisplay.textContent || '').trim();
      if (!key) return;

      const lbl = copyBtn.querySelector('.copy-lbl');
      const setCopied = () => {
        copyBtn.classList.add('copied');
        if (lbl) lbl.textContent = 'Copied!';
        setTimeout(function () {
          copyBtn.classList.remove('copied');
          if (lbl) lbl.textContent = 'Copy';
        }, 2500);
      };

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(key).then(setCopied).catch(setCopied);
      } else {
        licenseKeyDisplay.select();
        document.execCommand('copy');
        setCopied();
      }
    });

    licenseKeyDisplay.addEventListener('click', function () {
      this.select();
    });
  }

  function resetCouponUI() {
    appliedCoupon = null;
    couponCodeInput.disabled = false;
    couponCodeInput.value = '';
    couponFeedback.style.display = 'none';
    couponFeedback.innerHTML = '';
    couponInputWrap.style.display = 'none';
    couponApplyBtn.disabled = false;
    couponApplyBtn.textContent = 'Apply';
    if (couponToggleBtn) couponToggleBtn.style.display = 'inline-flex';
    applyPricing(isIndia, currentCountry);
  }

  function showCouponSuccess(code, discountDisplay) {
    couponFeedback.className = 'cko-coupon-feedback success';
    couponFeedback.innerHTML = `
      <div class="cko-coupon-pill">
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#10b981" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
        <span><strong>${code}</strong> — ${discountDisplay} off applied</span>
      </div>
      <button type="button" class="cko-coupon-remove" id="coupon-remove-btn">Remove</button>
    `;
    couponFeedback.style.display = 'flex';
    couponInputWrap.style.display = 'none';
    if (couponToggleBtn) couponToggleBtn.style.display = 'none';

    document.getElementById('coupon-remove-btn')?.addEventListener('click', resetCouponUI);
  }

  function showCouponError(msg) {
    couponFeedback.className = 'cko-coupon-feedback error';
    couponFeedback.innerHTML = `
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>
      <span>${msg}</span>
    `;
    couponFeedback.style.display = 'flex';
  }

  async function handleCouponApply() {
    const code = (couponCodeInput.value || '').trim().toUpperCase();
    if (!code) {
      showCouponError('Please enter a coupon code.');
      return;
    }

    couponApplyBtn.disabled = true;
    couponApplyBtn.textContent = '…';

    try {
      const res = await fetch(`/api/coupons?code=${encodeURIComponent(code)}&currency=${selectedCurrency}`);
      const data = await res.json();

      if (res.ok && data.valid) {
        appliedCoupon = data;
        showCouponSuccess(data.code, data.discountDisplay);
        applyPricing(isIndia, currentCountry);
      } else {
        appliedCoupon = null;
        showCouponError(data.error || 'Invalid or expired coupon code.');
        applyPricing(isIndia, currentCountry);
      }
    } catch (err) {
      // Local offline fallback for known test codes
      if (code === 'LAUNCH20' || code === 'DROPDIAL50' || code === 'PRO10') {
        const val = code === 'DROPDIAL50' ? 50 : (code === 'LAUNCH20' ? 20 : 10);
        appliedCoupon = { code, type: 'percent', value: val, discountDisplay: `${val}%` };
        showCouponSuccess(code, `${val}%`);
        applyPricing(isIndia, currentCountry);
      } else {
        showCouponError('Invalid coupon code.');
      }
    } finally {
      couponApplyBtn.disabled = false;
      couponApplyBtn.textContent = 'Apply';
    }
  }

  function openModal() {
    hideError();
    formView.style.display = 'block';
    successView.style.display = 'none';
    overlay.classList.add('active');
    setTimeout(() => nameInput.focus(), 150);
    try {
      fetch('/api/admin?action=track&event=checkout', { method: 'POST', keepalive: true }).catch(() => {});
    } catch (_) {}
  }

  function closeModal() {
    overlay.classList.remove('active');
  }

  function showError(msg) {
    errorBox.textContent = msg;
    errorBox.style.display = 'block';
  }

  function hideError() {
    errorBox.style.display = 'none';
    errorBox.textContent = '';
  }

  async function handlePaymentInitiation() {
    hideError();

    const name = nameInput.value.trim();
    const email = emailInput.value.trim();

    if (!name) {
      showError('Please enter your full name.');
      nameInput.focus();
      return;
    }

    if (!email || !email.includes('@') || !email.includes('.')) {
      showError('Please enter a valid email address to receive your license key.');
      emailInput.focus();
      return;
    }

    payBtn.disabled = true;
    const originalBtnText = payBtn.innerHTML;
    payBtn.innerHTML = `<span>Connecting to Secure Gateway…</span>`;

    try {
      // 1. Create order on server with locked country, currency, and optional coupon
      const orderRes = await fetch('/api/create-order', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: name,
          email: email,
          country: currentCountry,
          currency: selectedCurrency,
          amount: PRICING[selectedCurrency].amount,
          couponCode: appliedCoupon ? appliedCoupon.code : ''
        })
      });

      const orderData = await orderRes.json();
      if (!orderRes.ok || orderData.error) {
        throw new Error(orderData.error || 'Unable to initiate order with Razorpay.');
      }

      if (typeof Razorpay === 'undefined') {
        throw new Error('Razorpay SDK failed to load. Please check your internet connection or ad-blocker.');
      }

      // 2. Open Razorpay Standard Checkout
      const rzpOptions = {
        key: orderData.keyId,
        amount: orderData.amount,
        currency: orderData.currency,
        name: 'DropDial Pro',
        description: 'Lifetime License (macOS & Windows)',
        image: '/assets/img/logo.png',
        order_id: orderData.orderId,
        prefill: {
          name: name,
          email: email
        },
        theme: {
          color: '#ff6500'
        },
        modal: {
          ondismiss: function () {
            payBtn.disabled = false;
            payBtn.innerHTML = originalBtnText;
          }
        },
        handler: async function (response) {
          payBtn.innerHTML = `<span>Verifying Payment & Generating License…</span>`;

          try {
            // 3. Verify payment signature and deliver license via Resend
            const verifyRes = await fetch('/api/verify-payment', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({
                razorpay_order_id: response.razorpay_order_id,
                razorpay_payment_id: response.razorpay_payment_id,
                razorpay_signature: response.razorpay_signature,
                email: email,
                name: name
              })
            });

            const verifyData = await verifyRes.json();
            if (!verifyRes.ok || !verifyData.success) {
              throw new Error(verifyData.error || 'Payment verification failed.');
            }

            // 4. Record transaction in local admin ledger & track purchase
            try {
              fetch('/api/admin?action=track&event=purchase', { method: 'POST', keepalive: true }).catch(() => {});
              const activePrice = getActivePriceConfig();
              const txList = JSON.parse(localStorage.getItem('dd_admin_tx') || '[]');
              txList.unshift({
                paymentId: response.razorpay_payment_id,
                orderId: response.razorpay_order_id,
                customer: name,
                email: email,
                amount: activePrice.display,
                amountRaw: activePrice.amount,
                currency: selectedCurrency,
                method: 'Razorpay Gateway',
                country: isIndia ? 'IN 🇮🇳' : `${currentCountry}`,
                coupon: appliedCoupon ? appliedCoupon.code : 'None',
                status: 'Captured',
                timestamp: new Date().toISOString().replace('T', ' ').slice(0, 19)
              });
              localStorage.setItem('dd_admin_tx', JSON.stringify(txList));

              const licList = JSON.parse(localStorage.getItem('dd_admin_licenses') || '[]');
              licList.unshift({
                id: verifyData.licenseKey,
                name: name,
                email: email,
                tier: 'Pro Lifetime',
                date: new Date().toISOString().slice(0, 10),
                status: 'Active'
              });
              localStorage.setItem('dd_admin_licenses', JSON.stringify(licList));
            } catch (_) {}

            // 5. Show success screen
            showSuccess(verifyData.licenseKey, email);
          } catch (verifyErr) {
            showError(verifyErr.message || 'Payment received, but error generating license key. Please contact support@dropdial.app with your payment ID.');
            payBtn.disabled = false;
            payBtn.innerHTML = originalBtnText;
          }
        }
      };

      const rzp = new Razorpay(rzpOptions);
      rzp.on('payment.failed', function (failResp) {
        const errorDesc = failResp.error && (failResp.error.description || failResp.error.reason)
          ? (failResp.error.description || failResp.error.reason)
          : 'Transaction was declined by bank or card issuer.';

        showError(`Payment failed: ${errorDesc}`);
        payBtn.disabled = false;
        payBtn.innerHTML = originalBtnText;

        if (email) {
          fetch('/api/payment-failed', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              email: email,
              name: name,
              reason: errorDesc,
              amount: getActivePriceConfig().display,
              currency: selectedCurrency,
              orderId: orderData.orderId
            })
          }).catch(function (reportErr) {
            console.warn('[Checkout] Failed to trigger payment failure email:', reportErr);
          });
        }
      });

      rzp.open();
    } catch (err) {
      showError(err.message || 'An unexpected error occurred. Please try again.');
      payBtn.disabled = false;
      payBtn.innerHTML = originalBtnText;
    }
  }

  function showSuccess(licenseKey, email) {
    formView.style.display = 'none';
    successView.style.display = 'block';

    if (licenseKeyDisplay) {
      licenseKeyDisplay.value = licenseKey;
      licenseKeyDisplay.setAttribute('data-full-key', licenseKey);
    }

    if (successEmailText) {
      successEmailText.textContent = email;
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }

  window.DropDialCheckout = {
    open: openModal,
    close: closeModal,
    applyCoupon: handleCouponApply
  };
})();
