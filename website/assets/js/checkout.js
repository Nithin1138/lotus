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

          <!-- Success View (Ultra-Compact Modern SaaS Design) -->
          <div class="checkout-success-view" id="checkout-success-view">
            <div class="success-celebration">
              <div class="success-icon-badge">
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"></polyline></svg>
              </div>
              <h3 class="success-title">Payment Successful!</h3>
              <p class="success-sub">DropDial Pro lifetime license activated</p>
            </div>

            <!-- Single-Row Compact License Key Pill -->
            <div class="success-key-box">
              <div class="key-box-top">
                <span class="key-box-label">LIFETIME LICENSE KEY</span>
                <span class="key-box-status"><span class="status-pulse"></span>ACTIVE</span>
              </div>
              <div class="key-input-wrapper">
                <input type="text" id="license-key-display" class="key-display-input" readonly value="DD-..." spellcheck="false" title="Click to select full key">
                <button type="button" class="key-inline-copy-btn" id="copy-license-btn" aria-label="Copy License Key">
                  <svg class="copy-svg" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path></svg>
                  <span class="copy-lbl">Copy</span>
                </button>
              </div>
            </div>

            <!-- Clean 1-Line Delivery Status -->
            <div class="email-delivery-pill">
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect width="20" height="16" x="2" y="4" rx="2"/><path d="m22 7-8.97 5.7a1.94 1.94 0 0 1-2.06 0L2 7"/></svg>
              <span>Key &amp; receipt sent to <strong id="success-email-notice">you@example.com</strong></span>
            </div>

            <!-- Sleek Horizontal 3-Step Activation Timeline -->
            <div class="activation-timeline">
              <div class="timeline-step">
                <span class="step-badge">1</span>
                <span class="step-text">Open DropDial</span>
              </div>
              <span class="timeline-sep">›</span>
              <div class="timeline-step">
                <span class="step-badge">2</span>
                <span class="step-text">Right-click tray</span>
              </div>
              <span class="timeline-sep">›</span>
              <div class="timeline-step">
                <span class="step-badge">3</span>
                <span class="step-text">Paste Key</span>
              </div>
            </div>

            <!-- Modal Action Buttons -->
            <div class="success-actions-row">
              <a href="#download" class="success-btn-download" id="download-now-btn">
                <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
                <span>Download App</span>
              </a>
              <button type="button" class="success-btn-done" id="success-done-btn">Done</button>
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

    // Copy License Key Button
    copyBtn.addEventListener('click', function () {
      const key = (licenseKeyDisplay.value || licenseKeyDisplay.getAttribute('data-full-key') || licenseKeyDisplay.textContent || '').trim();
      if (!key) return;

      const lbl = copyBtn.querySelector('.copy-lbl');
      navigator.clipboard.writeText(key).then(function () {
        copyBtn.classList.add('copied');
        if (lbl) lbl.textContent = 'Copied! ✓';
        setTimeout(function () {
          copyBtn.classList.remove('copied');
          if (lbl) lbl.textContent = 'Copy';
        }, 2500);
      }).catch(function () {
        // Fallback for older browsers
        licenseKeyDisplay.select();
        document.execCommand('copy');
        copyBtn.classList.add('copied');
        if (lbl) lbl.textContent = 'Copied! ✓';
        setTimeout(function () {
          copyBtn.classList.remove('copied');
          if (lbl) lbl.textContent = 'Copy';
        }, 2500);
      });
    });

    // Auto-select entire key on click
    licenseKeyDisplay.addEventListener('click', function () {
      this.select();
    });
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

            // 4. Record transaction in local admin ledger & track purchase
            try {
              fetch('/api/admin?action=track&event=purchase', { method: 'POST', keepalive: true }).catch(() => {});
              const txList = JSON.parse(localStorage.getItem('dd_admin_tx') || '[]');
              txList.unshift({
                paymentId: response.razorpay_payment_id,
                orderId: response.razorpay_order_id,
                customer: name,
                email: email,
                amount: PRICING[selectedCurrency].display,
                amountRaw: PRICING[selectedCurrency].amount,
                currency: selectedCurrency,
                method: 'Razorpay Gateway',
                country: isIndia ? 'IN 🇮🇳' : `${currentCountry} 🌐`,
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

        // Send payment failure recovery email to customer
        if (email) {
          fetch('/api/payment-failed', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              email: email,
              name: name,
              reason: errorDesc,
              amount: PRICING[selectedCurrency] ? PRICING[selectedCurrency].displayPrice : '',
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
    licenseKeyDisplay.value = licenseKey;
    licenseKeyDisplay.setAttribute('data-full-key', licenseKey);
    if (successEmailText) {
      successEmailText.textContent = email;
    }
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
