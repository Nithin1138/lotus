/**
 * DropDial Checkout & Licensing Client Integration
 * Handles Automatic Country-Based Pricing (₹999 in India, $19 Worldwide),
 * Razorpay Checkout Modal, Order Creation, Payment Verification,
 * and Instant Delivery via Resend.
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

  // Modal DOM Elements
  let overlay, formView, successView, errorBox, payBtn;
  let nameInput, emailInput, priceDisplay, copyBtn, licenseKeyDisplay, successEmailText;

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
   * Applies localized pricing to the checkout modal and the landing page
   */
  function applyPricing(indiaFlag, countryCode) {
    isIndia = !!indiaFlag;
    selectedCurrency = isIndia ? 'INR' : 'USD';
    currentCountry = countryCode || (isIndia ? 'IN' : 'US');
    const config = PRICING[selectedCurrency];

    // 1. Modal Elements
    if (priceDisplay) {
      priceDisplay.textContent = config.display;
    }
    const payLabel = document.getElementById('checkout-pay-label');
    if (payLabel) {
      payLabel.textContent = `Proceed to Payment (${config.display})`;
    }

    // 2. Landing Page Buttons & Pricing Card
    const headerBuy = document.getElementById('nav-header-buy-btn');
    if (headerBuy) {
      headerBuy.textContent = `Buy Pro (${config.display})`;
    }

    const navBuy = document.getElementById('nav-buy-btn');
    if (navBuy) {
      navBuy.textContent = `Buy Pro (${config.display})`;
    }

    const pricingCardPrice = document.getElementById('pro-pricing-price');
    if (pricingCardPrice) {
      pricingCardPrice.innerHTML = `${config.display} <span>one-time</span>`;
    }

    const trialPricingPrice = document.getElementById('trial-pricing-price');
    if (trialPricingPrice) {
      trialPricingPrice.innerHTML = `${config.symbol}0 <span>/ 7 days</span>`;
    }

    const cardBuy = document.getElementById('card-buy-btn');
    if (cardBuy) {
      cardBuy.textContent = `Buy DropDial Pro (${config.display})`;
    }
  }

  /**
   * Async server-edge geolocation detection
   */
  async function fetchCountryPricing() {
    try {
      // 1. Check primary Vercel edge endpoint
      const res = await fetch('/api/geo', { method: 'GET', cache: 'default' });
      if (res.ok) {
        const data = await res.json();
        if (data && typeof data.isIndia === 'boolean') {
          applyPricing(data.isIndia, data.country);
          return;
        }
      }
    } catch (err) {
      // Fallback for local testing or static preview environments
      try {
        const fallbackRes = await fetch('https://api.country.is/', { cache: 'default' });
        if (fallbackRes.ok) {
          const fallbackData = await fallbackRes.json();
          const country = (fallbackData.country || '').toUpperCase();
          applyPricing(country === 'IN', country);
          return;
        }
      } catch (e2) {
        // Retain fast heuristic result
      }
    }
  }

  function initCheckout() {
    // 1. Zero-latency instant detection
    const fastGeo = detectFastLocation();
    applyPricing(fastGeo.isIndia, fastGeo.country);

    // 2. Build DOM & bind events
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
        <div class="checkout-modal-header">
          <h3 class="checkout-modal-title" id="checkout-modal-heading">
            <img src="/assets/img/logo.png" alt="DropDial" width="28" height="28">
            DropDial Pro Lifetime
          </h3>
          <button type="button" class="checkout-close-btn" id="checkout-close" aria-label="Close">
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><line x1="18" y1="6" x2="6" y2="18"></line><line x1="6" y1="6" x2="18" y2="18"></line></svg>
          </button>
        </div>

        <div class="checkout-modal-body">
          <!-- Form View -->
          <div id="checkout-form-view">
            <!-- Plan Summary -->
            <div class="checkout-plan-summary">
              <div class="checkout-plan-row">
                <span class="checkout-plan-name">Lifetime License</span>
                <span class="checkout-plan-price" id="checkout-price-display">₹999</span>
              </div>
              <div class="checkout-plan-details">
                • Valid for up to 3 personal Macs &amp; PCs<br>
                • All 188+ offline tools &amp; all future updates included<br>
                • 100% private: local cryptographic activation
              </div>
            </div>

            <!-- Error Banner -->
            <div class="checkout-error" id="checkout-error"></div>

            <!-- Fields -->
            <div class="checkout-field">
              <label class="checkout-label" for="checkout-name">Your Full Name</label>
              <input type="text" id="checkout-name" class="checkout-input" placeholder="e.g. Alex Smith" required autocomplete="name">
            </div>

            <div class="checkout-field">
              <label class="checkout-label" for="checkout-email">Email Address (for License Key Delivery)</label>
              <input type="email" id="checkout-email" class="checkout-input" placeholder="e.g. alex@example.com" required autocomplete="email">
            </div>

            <!-- Pay Button -->
            <button type="button" class="checkout-pay-btn" id="checkout-pay-btn">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="11" width="18" height="11" rx="2" ry="2"></rect><path d="M7 11V7a5 5 0 0 1 10 0v4"></path></svg>
              <span id="checkout-pay-label">Proceed to Payment (₹999)</span>
            </button>

            <!-- Badges -->
            <div class="checkout-footer-badges">
              <span>🔒 256-bit Secure via Razorpay</span>
              <span>⚡ Instant Delivery via Resend</span>
            </div>
          </div>

          <!-- Success View (Compact & Modern) -->
          <div class="checkout-success-view" id="checkout-success-view">
            <div class="success-header-row">
              <div class="success-icon-wrap">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"></polyline></svg>
              </div>
              <div class="success-header-meta">
                <h3 class="success-title">Payment Successful!</h3>
                <p class="success-sub">DropDial Pro Lifetime is now active for your account.</p>
              </div>
            </div>

            <div class="license-compact-card">
              <div class="license-card-header">
                <span class="license-card-label">Personal License Key</span>
                <span class="license-status-tag">● Lifetime Active</span>
              </div>
              <div class="license-key-row">
                <input type="text" readonly class="license-key-field" id="license-key-display" value="DD-..." spellcheck="false" autocomplete="off" />
                <button type="button" class="copy-key-btn-compact" id="copy-license-btn" title="Copy to clipboard">
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
                  <span>Copy Key</span>
                </button>
              </div>
            </div>

            <div class="activation-hint-pill">
              <span class="hint-icon">⚡</span>
              <span class="hint-text"><strong>To Activate:</strong> Right-click DropDial icon ➔ <strong>Activate Pro…</strong> ➔ Paste Key</span>
            </div>

            <p class="success-email-notice" id="success-email-notice">
              A backup copy has also been sent to your email.
            </p>

            <div class="success-actions-row">
              <a href="#download" class="btn btn-ghost" id="download-now-btn">Download App</a>
              <button type="button" class="btn btn-primary" id="success-done-btn">Done</button>
            </div>
          </div>
        </div>
      </div>
    `;

    document.body.appendChild(overlay);

    formView = document.getElementById('checkout-form-view');
    successView = document.getElementById('checkout-success-view');
    errorBox = document.getElementById('checkout-error');
    payBtn = document.getElementById('checkout-pay-btn');
    nameInput = document.getElementById('checkout-name');
    emailInput = document.getElementById('checkout-email');
    priceDisplay = document.getElementById('checkout-price-display');
    copyBtn = document.getElementById('copy-license-btn');
    licenseKeyDisplay = document.getElementById('license-key-display');
    successEmailText = document.getElementById('success-email-notice');
  }

  function bindEvents() {
    // Open modal on click of any element with [data-open-checkout] or link matching pricing buy buttons
    document.addEventListener('click', function (e) {
      const target = e.target.closest('[data-open-checkout], a[href*="dropdial.app/buy"], a[href*="dropdial.com/buy"], .pricing-card.featured a.btn, a[href="#pricing"].btn');
      if (target) {
        // If clicking buy button, open checkout modal directly
        if (target.getAttribute('href') === 'https://dropdial.app/buy' || target.getAttribute('href') === 'https://dropdial.com/buy' || target.hasAttribute('data-open-checkout') || target.textContent.includes('Buy')) {
          e.preventDefault();
          openModal();
        }
      }
    });

    // Close button & clicking overlay background
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

    // Pay Button Click
    payBtn.addEventListener('click', handlePaymentInitiation);

    // Auto-select key on input focus/click
    licenseKeyDisplay.addEventListener('click', function () {
      if (typeof this.select === 'function') {
        this.select();
      }
    });

    // Copy License Key Button
    copyBtn.addEventListener('click', function () {
      const key = (licenseKeyDisplay.value || licenseKeyDisplay.textContent || '').trim();
      if (!key) return;

      const setCopiedUI = () => {
        copyBtn.classList.add('copied');
        const textSpan = copyBtn.querySelector('span');
        if (textSpan) textSpan.textContent = 'Copied! ✓';
        setTimeout(function () {
          copyBtn.classList.remove('copied');
          if (textSpan) textSpan.textContent = 'Copy Key';
        }, 3000);
      };

      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(key).then(setCopiedUI).catch(() => {
          fallbackCopy(key, setCopiedUI);
        });
      } else {
        fallbackCopy(key, setCopiedUI);
      }
    });

    function fallbackCopy(text, cb) {
      const textarea = document.createElement('textarea');
      textarea.value = text;
      textarea.style.position = 'fixed';
      textarea.style.opacity = '0';
      document.body.appendChild(textarea);
      textarea.select();
      try {
        document.execCommand('copy');
        cb();
      } catch (e) {}
      document.body.removeChild(textarea);
    }
  }

  function openModal() {
    hideError();
    formView.style.display = 'block';
    successView.style.display = 'none';
    overlay.classList.add('active');
    setTimeout(() => nameInput.focus(), 150);
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
    payBtn.innerHTML = `<span>Connecting to Razorpay…</span>`;

    try {
      // 1. Create order on server with locked country & currency
      const orderRes = await fetch('/api/create-order', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: name,
          email: email,
          country: currentCountry,
          currency: selectedCurrency,
          amount: PRICING[selectedCurrency].amount
        })
      });

      const orderData = await orderRes.json();
      if (!orderRes.ok || orderData.error) {
        throw new Error(orderData.error || 'Unable to initiate order with Razorpay.');
      }

      // Check if Razorpay SDK script is loaded
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

            // 4. Show success screen
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
        showError(`Payment failed: ${failResp.error.description || 'Transaction was declined.'}`);
        payBtn.disabled = false;
        payBtn.innerHTML = originalBtnText;
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
    if (licenseKeyDisplay.tagName === 'INPUT') {
      licenseKeyDisplay.value = licenseKey;
    } else {
      licenseKeyDisplay.textContent = licenseKey;
    }
    successEmailText.innerHTML = `A backup copy of this license has also been emailed to <strong>${email}</strong>.`;
  }

  // Self-initialize on DOM ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initCheckout);
  } else {
    initCheckout();
  }

  // Export to window for manual triggering
  window.DropDialCheckout = {
    open: openModal,
    close: closeModal,
    setPricing: applyPricing
  };
})();
