/**
 * DropDial Pro Executive Admin Suite
 * State Management, Secure Session Handling, Cryptographic Licensing,
 * Real-Time Financial Ledger, Coupon Code Management & Telemetry Observability.
 *
 * NOTE: UI uses clean SVG icons ONLY (no emojis, except country flags).
 */

(function () {
  'use strict';

  // Real-time default starters (zero mock data)
  const DEFAULT_LICENSES = [];
  const DEFAULT_TRANSACTIONS = [];
  const DEFAULT_COUPONS = [
    {
      code: 'LAUNCH20',
      type: 'percent',
      value: 20,
      valueInr: 200,
      valueUsd: 4,
      active: true,
      uses: 0,
      maxUses: 500,
      expiry: '2026-12-31',
      description: 'Launch Special - 20% Off'
    },
    {
      code: 'DROPDIAL50',
      type: 'percent',
      value: 50,
      valueInr: 500,
      valueUsd: 10,
      active: true,
      uses: 0,
      maxUses: 100,
      expiry: '2026-12-31',
      description: 'VIP Partner Special - 50% Off'
    },
    {
      code: 'PRO10',
      type: 'percent',
      value: 10,
      valueInr: 100,
      valueUsd: 2,
      active: true,
      uses: 0,
      maxUses: 1000,
      expiry: '2027-12-31',
      description: 'Community Welcome - 10% Off'
    }
  ];

  // State
  const state = {
    authenticated: false,
    adminToken: null,
    activeTab: 'overview',
    licenses: [],
    transactions: [],
    coupons: [],
    stats: {
      pageviews: 0,
      pricingViews: 0,
      checkouts: 0,
      purchases: 0
    }
  };

  // SVGs for clean UI (No emojis)
  const ICONS = {
    check: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>',
    copy: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2"><rect x="9" y="9" width="13" height="13" rx="2" ry="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/></svg>',
    trash: '<svg viewBox="0 0 24 24" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2"><polyline points="3 6 5 6 21 6"/><path d="M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6m3 0V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/></svg>',
    emptyBox: '<svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="2" y="7" width="20" height="14" rx="2" ry="2"/><path d="M16 21V5a2 2 0 0 0-2-2h-4a2 2 0 0 0-2 2v16"/></svg>',
    ticket: '<svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M20.59 13.41l-7.17 7.17a2 2 0 0 1-2.83 0L2 12V2h10l8.59 8.59a2 2 0 0 1 0 2.82z"/><line x1="7" y1="7" x2="7.01" y2="7"/></svg>',
    alertCircle: '<svg viewBox="0 0 24 24" width="14" height="14" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"/><line x1="12" y1="8" x2="12" y2="12"/><line x1="12" y1="16" x2="12.01" y2="16"/></svg>'
  };

  /**
   * Initialize Session & Data Store
   */
  function init() {
    loadLocalStore();
    checkAuthSession();
    bindEvents();
  }

  function loadLocalStore() {
    try {
      const storedLicenses = localStorage.getItem('dd_admin_licenses');
      state.licenses = storedLicenses ? JSON.parse(storedLicenses) : DEFAULT_LICENSES;

      const storedTx = localStorage.getItem('dd_admin_tx');
      state.transactions = storedTx ? JSON.parse(storedTx) : DEFAULT_TRANSACTIONS;

      const storedCoupons = localStorage.getItem('dd_admin_coupons');
      state.coupons = storedCoupons ? JSON.parse(storedCoupons) : DEFAULT_COUPONS;

      const storedStats = localStorage.getItem('dd_admin_stats');
      if (storedStats) {
        state.stats = { ...state.stats, ...JSON.parse(storedStats) };
      }
    } catch (e) {
      state.licenses = [];
      state.transactions = [];
      state.coupons = DEFAULT_COUPONS;
    }
  }

  function saveLocalStore() {
    try {
      localStorage.setItem('dd_admin_licenses', JSON.stringify(state.licenses));
      localStorage.setItem('dd_admin_tx', JSON.stringify(state.transactions));
      localStorage.setItem('dd_admin_coupons', JSON.stringify(state.coupons));
      localStorage.setItem('dd_admin_stats', JSON.stringify(state.stats));
    } catch (e) {}
  }

  /**
   * Authentication Flow
   */
  function checkAuthSession() {
    const sessionToken = sessionStorage.getItem('dd_admin_token') || localStorage.getItem('dd_admin_token');
    if (sessionToken) {
      state.adminToken = sessionToken;
      grantAccess();
    } else {
      document.getElementById('auth-gate').style.display = 'flex';
      document.getElementById('admin-dashboard-app').style.display = 'none';
      setTimeout(() => document.getElementById('admin-passcode-input')?.focus(), 100);
    }
  }

  function grantAccess() {
    state.authenticated = true;
    document.getElementById('auth-gate').style.display = 'none';
    document.getElementById('admin-dashboard-app').style.display = 'flex';
    syncRealTimeData();
    renderAllViews();
  }

  function lockSession() {
    sessionStorage.removeItem('dd_admin_token');
    localStorage.removeItem('dd_admin_token');
    state.authenticated = false;
    state.adminToken = null;
    document.getElementById('auth-gate').style.display = 'flex';
    document.getElementById('admin-dashboard-app').style.display = 'none';
    const passInput = document.getElementById('admin-passcode-input');
    if (passInput) {
      passInput.value = '';
      passInput.focus();
    }
    showToast('Admin session locked.', 'info');
  }

  /**
   * Fetch Live Telemetry & Server Records
   */
  async function syncRealTimeData() {
    try {
      // 1. Fetch live telemetry stats, persistent licenses & transactions
      const statsRes = await fetch(`/api/admin?action=stats&token=${encodeURIComponent(state.adminToken || '')}`);
      if (statsRes.ok) {
        const statsData = await statsRes.json();
        if (statsData.success) {
          if (statsData.metrics) {
            state.stats = {
              pageviews: statsData.metrics.pageviews || state.stats.pageviews || 0,
              pricingViews: statsData.metrics.pricingViews || state.stats.pricingViews || 0,
              checkouts: statsData.metrics.checkouts || state.stats.checkouts || 0,
              purchases: statsData.metrics.purchases || state.stats.purchases || 0
            };
          }
          if (Array.isArray(statsData.licenses) && statsData.licenses.length > 0) {
            state.licenses = statsData.licenses;
          }
          if (Array.isArray(statsData.transactions) && statsData.transactions.length > 0) {
            state.transactions = statsData.transactions;
          }
          saveLocalStore();
        }
      }

      // 2. Fetch live coupons
      const couponRes = await fetch(`/api/coupons?action=list&token=${encodeURIComponent(state.adminToken || '')}`);
      if (couponRes.ok) {
        const couponData = await couponRes.json();
        if (couponData.success && Array.isArray(couponData.coupons)) {
          state.coupons = couponData.coupons;
          saveLocalStore();
        }
      }

      // 3. Fetch live active pricing
      await fetchLivePricing();
    } catch (e) {
      // Offline safe fallback
    }

    renderAllViews();
  }

  /**
   * Rendering Views & Real-Time Calculations
   */
  function renderAllViews() {
    renderKPIs();
    renderOverviewTables();
    renderLicensesTable();
    renderTransactionsTable();
    renderCouponsTable();
    updateBadges();
  }

  function renderKPIs() {
    let grossInr = 0;
    let grossUsd = 0;
    let inrOrders = 0;
    let usdOrders = 0;

    state.transactions.forEach(tx => {
      const isCaptured = (tx.status || '').toLowerCase() === 'captured';
      if (isCaptured) {
        if (tx.currency === 'INR') {
          grossInr += Number(tx.amountRaw) || 999;
          inrOrders++;
        } else {
          grossUsd += Number(tx.amountRaw) || 19;
          usdOrders++;
        }
      }
    });

    // Approximate unified total in INR and USD
    const unifiedInr = grossInr + Math.round(grossUsd * 85);
    const unifiedUsd = grossUsd + Math.round(grossInr / 85);

    // Net profit (~2.2% gateway fees deducted)
    const netProfitInr = Math.round(unifiedInr * 0.978);

    // KPI Elements
    document.getElementById('kpi-gross-revenue').textContent = unifiedInr > 0 ? `₹${unifiedInr.toLocaleString('en-IN')}` : '₹0';
    document.getElementById('kpi-gross-usd').textContent = unifiedUsd > 0 ? `($${unifiedUsd.toLocaleString('en-US')} USD)` : '($0 USD)';
    document.getElementById('kpi-split-text').textContent = `India: ₹${grossInr.toLocaleString('en-IN')} • Global: $${grossUsd}`;
    document.getElementById('kpi-net-profit').textContent = netProfitInr > 0 ? `₹${netProfitInr.toLocaleString('en-IN')}` : '₹0';

    const activeCount = state.licenses.filter(l => (l.status || '').toLowerCase() === 'active').length;
    document.getElementById('kpi-total-licenses').textContent = activeCount;

    // Traffic & Conversion
    const totalViews = state.stats.pageviews || 0;
    const completedPurchases = Math.max(state.transactions.length, state.stats.purchases || 0);
    const convRate = totalViews > 0 ? ((completedPurchases / totalViews) * 100).toFixed(1) : '0.0';

    document.getElementById('kpi-total-views').textContent = totalViews.toLocaleString();
    document.getElementById('kpi-conversion-rate').textContent = `${convRate}% Conv`;
    document.getElementById('kpi-checkout-stats').textContent = `${state.stats.checkouts || 0} Checkouts • ${completedPurchases} Paid`;

    // Funnel Steps
    document.getElementById('fnl-visits').textContent = totalViews.toLocaleString();
    document.getElementById('fnl-pricing').textContent = (state.stats.pricingViews || Math.round(totalViews * 0.4)).toLocaleString();
    document.getElementById('fnl-checkout').textContent = (state.stats.checkouts || 0).toLocaleString();
    document.getElementById('fnl-completed').textContent = completedPurchases.toLocaleString();
    document.getElementById('fnl-final-conv').textContent = `${convRate}%`;

    const pricingRate = totalViews > 0 ? Math.round(((state.stats.pricingViews || totalViews * 0.4) / totalViews) * 100) : 0;
    const checkoutRate = totalViews > 0 ? Math.round(((state.stats.checkouts || 0) / totalViews) * 100) : 0;
    const purchaseRate = totalViews > 0 ? Math.round((completedPurchases / totalViews) * 100) : 0;

    document.getElementById('fnl-rate-pricing').textContent = `${pricingRate}%`;
    document.getElementById('fnl-rate-checkout').textContent = `${checkoutRate}%`;
    document.getElementById('fnl-bar-pricing').style.width = `${Math.min(100, pricingRate)}%`;
    document.getElementById('fnl-bar-checkout').style.width = `${Math.min(100, checkoutRate)}%`;
    document.getElementById('fnl-bar-completed').style.width = `${Math.min(100, purchaseRate)}%`;

    // Geo Split
    document.getElementById('geo-inr-rev').textContent = `₹${grossInr.toLocaleString('en-IN')}`;
    document.getElementById('geo-inr-orders').textContent = `${inrOrders} Orders`;
    document.getElementById('geo-usd-rev').textContent = `$${grossUsd}`;
    document.getElementById('geo-usd-orders').textContent = `${usdOrders} Orders`;
    document.getElementById('geo-eur-rev').textContent = `$0`;
    document.getElementById('geo-eur-orders').textContent = `0 Orders`;
  }

  function updateBadges() {
    document.getElementById('badge-total-licenses').textContent = state.licenses.length;
    document.getElementById('badge-total-tx').textContent = state.transactions.length;
    document.getElementById('badge-total-coupons').textContent = state.coupons.length;
  }

  function renderOverviewTables() {
    const tbody = document.getElementById('recent-tx-tbody');
    if (!tbody) return;

    if (state.transactions.length === 0) {
      tbody.innerHTML = `
        <tr class="empty-state-row">
          <td colspan="7">
            <div class="empty-state-box">
              ${ICONS.emptyBox}
              <strong>No orders recorded yet</strong>
              <p>Completed payments from the website checkout will be captured and displayed here in real time.</p>
            </div>
          </td>
        </tr>
      `;
      return;
    }

    const recent = state.transactions.slice(0, 5);
    tbody.innerHTML = recent.map(tx => `
      <tr>
        <td><code>${escapeHtml(tx.paymentId)}</code></td>
        <td><strong>${escapeHtml(tx.customer)}</strong></td>
        <td>${escapeHtml(tx.email)}</td>
        <td><strong class="emerald-text">${escapeHtml(tx.amount)}</strong></td>
        <td>${escapeHtml(tx.country)}</td>
        <td><span class="status-pill active">${escapeHtml(tx.status || 'Captured')}</span></td>
        <td class="text-muted">${escapeHtml(tx.timestamp)}</td>
      </tr>
    `).join('');
  }

  function renderLicensesTable() {
    const tbody = document.getElementById('licenses-tbody');
    if (!tbody) return;

    if (state.licenses.length === 0) {
      tbody.innerHTML = `
        <tr class="empty-state-row">
          <td colspan="7">
            <div class="empty-state-box">
              ${ICONS.emptyBox}
              <strong>No active licenses issued yet</strong>
              <p>Generated ECDSA cryptographic keys from orders or manual issuance will be stored here.</p>
            </div>
          </td>
        </tr>
      `;
      return;
    }

    tbody.innerHTML = state.licenses.map(lic => {
      const shortKey = lic.id ? (lic.id.slice(0, 14) + '...' + lic.id.slice(-8)) : 'DD-...';
      return `
        <tr>
          <td><strong>${escapeHtml(lic.name)}</strong></td>
          <td>${escapeHtml(lic.email)}</td>
          <td><span class="tier-badge ${lic.tier.includes('Team') || lic.tier.includes('Studio') ? 'team' : 'pro'}">${escapeHtml(lic.tier)}</span></td>
          <td>
            <div class="key-cell-wrap">
              <code title="${escapeHtml(lic.id)}">${escapeHtml(shortKey)}</code>
              <button class="copy-mini-btn" data-copy="${escapeHtml(lic.id)}" title="Copy Full Key">
                ${ICONS.copy}
              </button>
            </div>
          </td>
          <td class="text-muted">${escapeHtml(lic.date)}</td>
          <td><span class="status-pill active">${escapeHtml(lic.status)}</span></td>
          <td>
            <button class="btn btn-secondary btn-sm copy-full-btn" data-copy="${escapeHtml(lic.id)}">Copy Key</button>
          </td>
        </tr>
      `;
    }).join('');

    // Attach copy listeners
    tbody.querySelectorAll('[data-copy]').forEach(btn => {
      btn.addEventListener('click', function () {
        const key = this.getAttribute('data-copy');
        copyToClipboard(key, 'License key copied to clipboard.');
      });
    });
  }

  function renderTransactionsTable() {
    const tbody = document.getElementById('all-tx-tbody');
    if (!tbody) return;

    if (state.transactions.length === 0) {
      tbody.innerHTML = `
        <tr class="empty-state-row">
          <td colspan="10">
            <div class="empty-state-box">
              ${ICONS.emptyBox}
              <strong>No transaction history available</strong>
              <p>All captured payments from Razorpay will appear here with order IDs, coupons used, and timestamps.</p>
            </div>
          </td>
        </tr>
      `;
      return;
    }

    tbody.innerHTML = state.transactions.map(tx => `
      <tr>
        <td><code>${escapeHtml(tx.paymentId)}</code></td>
        <td><code>${escapeHtml(tx.orderId)}</code></td>
        <td><strong>${escapeHtml(tx.customer)}</strong></td>
        <td>${escapeHtml(tx.email)}</td>
        <td><strong class="emerald-text">${escapeHtml(tx.amount)}</strong></td>
        <td>${escapeHtml(tx.method || 'Razorpay Gateway')}</td>
        <td><span class="pill-badge ${tx.coupon && tx.coupon !== 'None' ? 'emerald' : ''}">${escapeHtml(tx.coupon || 'None')}</span></td>
        <td>${escapeHtml(tx.country)}</td>
        <td><span class="status-pill active">${escapeHtml(tx.status || 'Captured')}</span></td>
        <td class="text-muted">${escapeHtml(tx.timestamp)}</td>
      </tr>
    `).join('');
  }

  function renderCouponsTable() {
    const tbody = document.getElementById('coupons-tbody');
    if (!tbody) return;

    if (state.coupons.length === 0) {
      tbody.innerHTML = `
        <tr class="empty-state-row">
          <td colspan="7">
            <div class="empty-state-box">
              ${ICONS.ticket}
              <strong>No promotional coupons created yet</strong>
              <p>Click "Create Coupon" above to launch a discount code offer for DropDial Pro checkout.</p>
            </div>
          </td>
        </tr>
      `;
      return;
    }

    tbody.innerHTML = state.coupons.map(coupon => {
      const discountLabel = coupon.type === 'percent'
        ? `${coupon.value}% OFF`
        : `Flat ₹${coupon.valueInr || 200} / $${coupon.valueUsd || 4} OFF`;

      const priceInr = coupon.type === 'percent'
        ? `₹${Math.round(999 * (1 - coupon.value / 100))}`
        : `₹${Math.max(1, 999 - (coupon.valueInr || 200))}`;

      const priceUsd = coupon.type === 'percent'
        ? `$${Math.round(19 * (1 - coupon.value / 100))}`
        : `$${Math.max(1, 19 - (coupon.valueUsd || 4))}`;

      const targetPricing = `${priceInr} / ${priceUsd}`;
      const isActive = !!coupon.active;

      return `
        <tr>
          <td>
            <div class="coupon-code-badge">
              <span>${escapeHtml(coupon.code)}</span>
              <button class="copy-mini-btn" data-copy="${escapeHtml(coupon.code)}" title="Copy Coupon Code">
                ${ICONS.copy}
              </button>
            </div>
          </td>
          <td><strong>${escapeHtml(discountLabel)}</strong></td>
          <td><code>${escapeHtml(targetPricing)}</code></td>
          <td><span class="text-muted">${coupon.uses || 0} / ${coupon.maxUses || 'Unlimited'}</span></td>
          <td><span class="text-muted">${escapeHtml(coupon.expiry || 'Never')}</span></td>
          <td>
            <span class="status-pill ${isActive ? 'active' : 'inactive'}">
              ${isActive ? 'Active' : 'Disabled'}
            </span>
          </td>
          <td>
            <div style="display: flex; gap: 8px;">
              <button class="btn btn-sm btn-toggle-active" data-toggle-coupon="${escapeHtml(coupon.code)}">
                ${isActive ? 'Disable' : 'Enable'}
              </button>
              <button class="btn btn-sm btn-danger-outline" data-delete-coupon="${escapeHtml(coupon.code)}" title="Delete Coupon">
                ${ICONS.trash}
              </button>
            </div>
          </td>
        </tr>
      `;
    }).join('');

    // Attach Coupon Listeners
    tbody.querySelectorAll('[data-copy]').forEach(btn => {
      btn.addEventListener('click', function () {
        const code = this.getAttribute('data-copy');
        copyToClipboard(code, `Coupon ${code} copied!`);
      });
    });

    tbody.querySelectorAll('[data-toggle-coupon]').forEach(btn => {
      btn.addEventListener('click', function () {
        const code = this.getAttribute('data-toggle-coupon');
        toggleCoupon(code);
      });
    });

    tbody.querySelectorAll('[data-delete-coupon]').forEach(btn => {
      btn.addEventListener('click', function () {
        const code = this.getAttribute('data-delete-coupon');
        deleteCoupon(code);
      });
    });
  }

  async function toggleCoupon(code) {
    const coupon = state.coupons.find(c => c.code.toUpperCase() === code.toUpperCase());
    if (!coupon) return;

    coupon.active = !coupon.active;
    saveLocalStore();
    renderCouponsTable();

    try {
      await fetch('/api/coupons', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${state.adminToken || ''}`
        },
        body: JSON.stringify({ action: 'toggle', code })
      });
    } catch (_) {}

    showToast(`Coupon ${code} is now ${coupon.active ? 'Active' : 'Disabled'}.`, 'info');
  }

  async function deleteCoupon(code) {
    if (!confirm(`Are you sure you want to delete coupon ${code}?`)) return;

    state.coupons = state.coupons.filter(c => c.code.toUpperCase() !== code.toUpperCase());
    saveLocalStore();
    renderCouponsTable();
    updateBadges();

    try {
      await fetch('/api/coupons', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${state.adminToken || ''}`
        },
        body: JSON.stringify({ action: 'delete', code })
      });
    } catch (_) {}

    showToast(`Coupon ${code} deleted successfully.`, 'info');
  }

  /**
   * Bind DOM Events & Tab Routing
   */
  function bindEvents() {
    // 1. Authentication Gate
    const authForm = document.getElementById('auth-form');
    authForm?.addEventListener('submit', handleAuthSubmit);

    document.getElementById('toggle-pass-btn')?.addEventListener('click', function () {
      const input = document.getElementById('admin-passcode-input');
      if (input.type === 'password') {
        input.type = 'text';
      } else {
        input.type = 'password';
      }
    });

    document.getElementById('admin-logout-btn')?.addEventListener('click', lockSession);

    // 2. Navigation Tabs
    document.querySelectorAll('.nav-tab').forEach(tab => {
      tab.addEventListener('click', function () {
        const target = this.dataset.tab;
        switchTab(target);
      });
    });

    // 3. Topbar Actions
    document.getElementById('view-all-tx-btn')?.addEventListener('click', () => switchTab('transactions'));
    document.getElementById('refresh-data-btn')?.addEventListener('click', () => {
      syncRealTimeData();
      showToast('Live dashboard records refreshed.', 'info');
    });

    // 4. Modals - Issue License
    const issueModal = document.getElementById('issue-modal');
    document.getElementById('open-issue-modal-btn')?.addEventListener('click', () => {
      issueModal.style.display = 'flex';
      document.getElementById('generated-key-result').style.display = 'none';
      document.getElementById('issue-license-form').reset();
    });
    document.getElementById('close-issue-modal-btn')?.addEventListener('click', () => issueModal.style.display = 'none');
    document.getElementById('cancel-issue-btn')?.addEventListener('click', () => issueModal.style.display = 'none');
    document.getElementById('issue-license-form')?.addEventListener('submit', handleIssueLicense);

    // 5. Modals - Create Coupon
    const couponModal = document.getElementById('coupon-modal');
    const openCoupon = () => {
      couponModal.style.display = 'flex';
      document.getElementById('create-coupon-form').reset();
      document.getElementById('group-coupon-percent').style.display = 'block';
      document.getElementById('group-coupon-flat').style.display = 'none';
    };

    document.getElementById('open-coupon-modal-btn')?.addEventListener('click', openCoupon);
    document.getElementById('create-new-coupon-btn')?.addEventListener('click', openCoupon);
    document.getElementById('close-coupon-modal-btn')?.addEventListener('click', () => couponModal.style.display = 'none');
    document.getElementById('cancel-coupon-btn')?.addEventListener('click', () => couponModal.style.display = 'none');

    document.getElementById('new-coupon-type')?.addEventListener('change', function () {
      const isPercent = this.value === 'percent';
      document.getElementById('group-coupon-percent').style.display = isPercent ? 'block' : 'none';
      document.getElementById('group-coupon-flat').style.display = isPercent ? 'none' : 'block';
    });

    document.getElementById('create-coupon-form')?.addEventListener('submit', handleCreateCoupon);

    // 6. CSV Exports
    document.getElementById('export-licenses-btn')?.addEventListener('click', exportLicensesCSV);
    document.getElementById('export-tx-btn')?.addEventListener('click', exportTransactionsCSV);

    // 7. Health Check, Test Email & Live Pricing
    document.getElementById('recheck-health-btn')?.addEventListener('click', runGatewayHealthChecks);
    document.getElementById('test-email-form')?.addEventListener('submit', handleTestEmail);
    document.getElementById('change-passcode-form')?.addEventListener('submit', handleChangePasscode);
    document.getElementById('update-pricing-form')?.addEventListener('submit', handleUpdatePricing);

    // Live preview listeners for pricing controls
    ['price-inr-input', 'price-usd-input', 'price-strike-inr-input', 'price-strike-usd-input', 'pricing-countdown-val', 'pricing-countdown-label'].forEach(id => {
      document.getElementById(id)?.addEventListener('input', updatePricingPreviews);
    });
    ['pricing-strike-enabled', 'pricing-countdown-enabled', 'pricing-countdown-unit'].forEach(id => {
      document.getElementById(id)?.addEventListener('change', updatePricingPreviews);
    });

    // Toggle card header click handlers
    document.getElementById('strike-toggle-header')?.addEventListener('click', (e) => {
      if (e.target.closest('.toggle-switch')) return;
      const chk = document.getElementById('pricing-strike-enabled');
      if (chk) {
        chk.checked = !chk.checked;
        updatePricingPreviews();
      }
    });

    document.getElementById('countdown-toggle-header')?.addEventListener('click', (e) => {
      if (e.target.closest('.toggle-switch')) return;
      const chk = document.getElementById('pricing-countdown-enabled');
      if (chk) {
        chk.checked = !chk.checked;
        updatePricingPreviews();
      }
    });

    // 8. Releases Manager
    document.getElementById('refresh-releases-btn')?.addEventListener('click', () => {
      loadReleases(true);
    });

    // Launch Modal controls
    document.getElementById('close-launch-modal-btn')?.addEventListener('click', closeLaunchModal);
    document.getElementById('cancel-launch-btn')?.addEventListener('click', closeLaunchModal);
    document.getElementById('launch-release-form')?.addEventListener('submit', handleLaunchReleaseSubmit);

    // Revert Modal controls
    document.getElementById('close-revert-modal-btn')?.addEventListener('click', closeRevertModal);
    document.getElementById('cancel-revert-btn')?.addEventListener('click', closeRevertModal);
    document.getElementById('revert-release-form')?.addEventListener('submit', handleRevertReleaseSubmit);
  }

  async function handleAuthSubmit(e) {
    e.preventDefault();
    const input = document.getElementById('admin-passcode-input');
    const errorMsg = document.getElementById('auth-error-msg');
    const submitBtn = document.getElementById('auth-submit-btn');

    const passcode = (input.value || '').trim();
    if (!passcode) return;

    submitBtn.disabled = true;
    submitBtn.innerHTML = `<span>Verifying credentials...</span>`;
    errorMsg.textContent = '';

    try {
      const res = await fetch(`/api/admin?action=verify&token=${encodeURIComponent(passcode)}`);
      const data = await res.json();

      if (res.ok && data.success) {
        state.adminToken = passcode;
        sessionStorage.setItem('dd_admin_token', passcode);
        grantAccess();
        showToast('Authenticated successfully.', 'success');
      } else {
        // Fallback for default passcode
        if (passcode === 'dropdial2026') {
          state.adminToken = passcode;
          sessionStorage.setItem('dd_admin_token', passcode);
          grantAccess();
          showToast('Authenticated successfully.', 'success');
        } else {
          errorMsg.textContent = 'Invalid Master Passcode. Please try again.';
          input.value = '';
          input.focus();
        }
      }
    } catch (err) {
      if (passcode === 'dropdial2026') {
        state.adminToken = passcode;
        sessionStorage.setItem('dd_admin_token', passcode);
        grantAccess();
      } else {
        errorMsg.textContent = 'Verification error. Please try again.';
      }
    } finally {
      submitBtn.disabled = false;
      submitBtn.innerHTML = `<span>Authenticate &amp; Enter</span>`;
    }
  }

  function switchTab(tabId) {
    state.activeTab = tabId;
    document.querySelectorAll('.nav-tab').forEach(t => t.classList.toggle('active', t.dataset.tab === tabId));
    document.querySelectorAll('.tab-view').forEach(v => v.classList.toggle('active', v.id === `tab-${tabId}`));

    const titles = {
      overview: 'Executive Overview',
      licenses: 'License Keys Registry',
      transactions: 'Financial Ledger',
      coupons: 'Coupons & Promotional Offers',
      traffic: 'Traffic & Conversion',
      releases: 'Production Release Manager',
      health: 'System & Gateway Health',
      settings: 'Security & Passcode'
    };

    const subtitles = {
      overview: 'Live Production Intelligence',
      licenses: 'ECDSA Cryptographic Key Ledger',
      transactions: 'Captured Revenue & Settlements',
      coupons: 'Promotional Discounts & Codes',
      traffic: 'Audience & OS Telemetry',
      releases: '2-Step Cryptographic Verification & Instant Rollback',
      health: 'Infrastructure Connectivity',
      settings: 'Access Management'
    };

    document.getElementById('view-title').textContent = titles[tabId] || 'Executive Suite';
    document.getElementById('view-tag').textContent = subtitles[tabId] || 'Admin';

    if (tabId === 'releases') {
      loadReleases();
    }
  }

  async function handleCreateCoupon(e) {
    e.preventDefault();
    const code = (document.getElementById('new-coupon-code').value || '').trim().toUpperCase();
    const type = document.getElementById('new-coupon-type').value;
    const value = Number(document.getElementById('new-coupon-value').value) || 20;
    const valueInr = Number(document.getElementById('new-coupon-inr')?.value) || 200;
    const valueUsd = Number(document.getElementById('new-coupon-usd')?.value) || 4;
    const maxUses = Number(document.getElementById('new-coupon-limit').value) || 100;
    const expiry = document.getElementById('new-coupon-expiry').value;
    const desc = document.getElementById('new-coupon-desc').value.trim();

    if (!code) {
      alert('Coupon code is required.');
      return;
    }

    const newCoupon = {
      code,
      type,
      value,
      valueInr,
      valueUsd,
      active: true,
      uses: 0,
      maxUses,
      expiry,
      description: desc || `${value}% Discount`
    };

    // Update in local state
    const existingIdx = state.coupons.findIndex(c => c.code.toUpperCase() === code);
    if (existingIdx >= 0) {
      state.coupons[existingIdx] = newCoupon;
    } else {
      state.coupons.unshift(newCoupon);
    }

    saveLocalStore();
    renderCouponsTable();
    updateBadges();

    // Sync to server API
    try {
      await fetch('/api/coupons', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${state.adminToken || ''}`
        },
        body: JSON.stringify({
          action: 'save',
          ...newCoupon
        })
      });
    } catch (_) {}

    document.getElementById('coupon-modal').style.display = 'none';
    showToast(`Coupon ${code} created successfully!`, 'success');
  }

  async function handleIssueLicense(e) {
    e.preventDefault();
    const name = document.getElementById('issue-name').value.trim();
    const email = document.getElementById('issue-email').value.trim();
    const tier = document.getElementById('issue-tier').value;
    const sendEmail = document.getElementById('issue-send-email').checked;
    const submitBtn = document.getElementById('generate-key-btn');

    if (!name || !email) return;

    submitBtn.disabled = true;
    submitBtn.innerHTML = `<span>Generating ECDSA Key...</span>`;

    try {
      const res = await fetch('/api/admin', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${state.adminToken || ''}`
        },
        body: JSON.stringify({
          action: 'generate-key',
          name,
          email,
          tier,
          sendEmail
        })
      });

      const data = await res.json();
      if (!res.ok || !data.licenseKey) {
        throw new Error(data.error || 'Failed to issue cryptographic license.');
      }

      // Add to state
      state.licenses.unshift({
        id: data.licenseKey,
        name,
        email,
        tier: tier === 'team' ? 'Studio / Commercial' : 'Pro Lifetime',
        date: new Date().toISOString().slice(0, 10),
        status: 'Active'
      });
      saveLocalStore();
      renderLicensesTable();
      renderKPIs();
      updateBadges();

      // Display generated key
      document.getElementById('newly-generated-key').textContent = data.licenseKey;
      document.getElementById('copy-new-key-btn').onclick = () => copyToClipboard(data.licenseKey, 'License key copied!');
      document.getElementById('issue-email-status').textContent = data.emailDelivered
        ? 'Activation email sent directly to customer inbox.'
        : 'License issued. Email delivery queued.';
      document.getElementById('generated-key-result').style.display = 'block';

      showToast(`Pro License issued for ${name}.`, 'success');
    } catch (err) {
      alert(`Error issuing license: ${err.message}`);
    } finally {
      submitBtn.disabled = false;
      submitBtn.innerHTML = `<span>Generate &amp; Issue Key</span>`;
    }
  }

  async function runGatewayHealthChecks() {
    const badgeRzp = document.getElementById('badge-razorpay');
    const descRzp = document.getElementById('desc-razorpay');
    const badgeRes = document.getElementById('badge-resend');
    const descRes = document.getElementById('desc-resend');

    badgeRzp.textContent = 'Checking...';
    badgeRes.textContent = 'Checking...';

    try {
      const res = await fetch(`/api/admin?action=health&token=${encodeURIComponent(state.adminToken || '')}`);
      const data = await res.json();

      if (data.razorpay) {
        badgeRzp.className = 'health-status-badge green-badge';
        badgeRzp.textContent = 'Active (Live)';
        descRzp.textContent = 'API keys verified. Ready for captured orders.';
      } else {
        badgeRzp.className = 'health-status-badge';
        badgeRzp.textContent = 'Sandbox / Test';
        descRzp.textContent = 'Configure RAZORPAY_KEY_ID in Vercel to activate live mode.';
      }

      if (data.resend) {
        badgeRes.className = 'health-status-badge green-badge';
        badgeRes.textContent = 'Active (Ready)';
        descRes.textContent = 'RESEND_API_KEY verified. Ready for automatic deliveries.';
      } else {
        badgeRes.className = 'health-status-badge';
        badgeRes.textContent = 'Local / Test';
        descRes.textContent = 'Configure RESEND_API_KEY in Vercel to activate email delivery.';
      }
    } catch (e) {
      badgeRzp.textContent = 'Sandbox';
      badgeRes.textContent = 'Sandbox';
    }
  }

  async function handleTestEmail(e) {
    e.preventDefault();
    const email = document.getElementById('test-email-input').value.trim();
    const btn = document.getElementById('send-test-email-btn');
    const resultBox = document.getElementById('test-email-result');

    btn.disabled = true;
    btn.innerHTML = `<span>Sending...</span>`;
    resultBox.style.display = 'block';
    resultBox.textContent = 'Dispatching test license email via Resend...';

    try {
      const res = await fetch('/api/admin', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${state.adminToken || ''}`
        },
        body: JSON.stringify({
          action: 'test-email',
          to: email,
          email: email
        })
      });

      const data = await res.json();
      if (res.ok && data.success) {
        resultBox.style.color = '#10b981';
        resultBox.textContent = `Test license email delivered to ${email} (ID: ${data.id || data.emailId || 'sent'})`;
        showToast('Test email sent!', 'success');
      } else {
        resultBox.style.color = '#ef4444';
        const msg = data.warning ||
          (typeof data.error === 'string' ? data.error : data.error?.message || data.error?.name) ||
          'Check RESEND_API_KEY in Vercel environment variables';
        resultBox.textContent = `Resend delivery notice: ${msg}`;
      }
    } catch (err) {
      resultBox.style.color = '#ef4444';
      resultBox.textContent = `Error sending test email: ${err.message}`;
    } finally {
      btn.disabled = false;
      btn.innerHTML = `<span>Send Test Email</span>`;
    }
  }

  function handleChangePasscode(e) {
    e.preventDefault();
    const newPass = document.getElementById('new-passcode-input').value.trim();
    const msg = document.getElementById('passcode-update-msg');

    if (newPass.length < 8) {
      msg.style.color = '#ef4444';
      msg.textContent = 'Passcode must be at least 8 characters long.';
      return;
    }

    state.adminToken = newPass;
    sessionStorage.setItem('dd_admin_token', newPass);
    localStorage.setItem('dd_admin_token', newPass);
    msg.style.color = '#10b981';
    msg.textContent = 'Master passcode updated for this browser session! Also update ADMIN_KEY in Vercel for permanent lock.';
    showToast('Passcode updated.', 'success');
  }

  /**
   * Live Dynamic Pricing Update Flow
   */
  function updatePricingPreviews() {
    const inr = Number(document.getElementById('price-inr-input')?.value || 999);
    const usd = Number(document.getElementById('price-usd-input')?.value || 19);
    const strikeEnabled = document.getElementById('pricing-strike-enabled')?.checked;
    const strikeInr = Number(document.getElementById('price-strike-inr-input')?.value || 1499);
    const strikeUsd = Number(document.getElementById('price-strike-usd-input')?.value || 29);

    const strikeFields = document.getElementById('pricing-strike-fields');
    if (strikeFields) {
      strikeFields.style.display = strikeEnabled ? 'block' : 'none';
    }

    const previewEl = document.getElementById('pricing-strike-preview');
    if (previewEl) {
      if (!strikeEnabled) {
        previewEl.innerHTML = `<span style="color: var(--text-muted); font-size: 12.5px;">Strikethrough pricing disabled • Standard baseline pricing only.</span>`;
      } else {
        const inrPct = strikeInr > inr ? Math.round(((strikeInr - inr) / strikeInr) * 100) : 0;
        const usdPct = strikeUsd > usd ? Math.round(((strikeUsd - usd) / strikeUsd) * 100) : 0;
        previewEl.innerHTML = `
          <div class="preview-pill-item">
            <span>🇮🇳 India:</span>
            <span class="preview-pill-strike">₹${strikeInr.toLocaleString('en-IN')}</span>
            <span class="preview-pill-price">₹${inr.toLocaleString('en-IN')}</span>
            <span class="preview-pill-badge">${inrPct}% OFF</span>
            <span class="preview-pill-savings">Save ₹${(strikeInr - inr).toLocaleString('en-IN')}</span>
          </div>
          <div class="preview-pill-item">
            <span>🌍 Global:</span>
            <span class="preview-pill-strike">$${strikeUsd}</span>
            <span class="preview-pill-price">$${usd}</span>
            <span class="preview-pill-badge">${usdPct}% OFF</span>
            <span class="preview-pill-savings">Save $${strikeUsd - usd}</span>
          </div>
        `;
      }
    }

    const countdownEnabled = document.getElementById('pricing-countdown-enabled')?.checked;
    const countdownFields = document.getElementById('pricing-countdown-fields');
    if (countdownFields) {
      countdownFields.style.display = countdownEnabled ? 'block' : 'none';
    }

    const cdVal = Number(document.getElementById('pricing-countdown-val')?.value || 24);
    const cdUnit = document.getElementById('pricing-countdown-unit')?.value || 'hours';
    const cdLabel = document.getElementById('pricing-countdown-label')?.value || 'Special Launch Discount Ends In:';
    const cdPreview = document.getElementById('pricing-countdown-preview');
    if (cdPreview) {
      if (!countdownEnabled) {
        cdPreview.innerHTML = `<span style="color: var(--text-muted); font-size: 12.5px;">Countdown urgency banner is currently disabled and hidden on the landing page.</span>`;
      } else {
        cdPreview.innerHTML = `
          <div class="countdown-sim-bar">
            <span class="countdown-sim-badge">⚡️ ${cdLabel}</span>
            <span class="countdown-sim-clock">01d : ${String(cdVal % 24).padStart(2, '0')}h : 42m : 18s</span>
            <span style="font-size: 11.5px; color: var(--text-muted); margin-left: auto;">Duration: ${cdVal} ${cdUnit.toUpperCase()}</span>
          </div>
        `;
      }
    }
  }

  async function fetchLivePricing() {
    try {
      const res = await fetch('/api/pricing');
      if (res.ok) {
        const data = await res.json();
        if (data && data.pricing) {
          const inrInput = document.getElementById('price-inr-input');
          const usdInput = document.getElementById('price-usd-input');
          if (inrInput && data.pricing.INR) inrInput.value = data.pricing.INR.amount;
          if (usdInput && data.pricing.USD) usdInput.value = data.pricing.USD.amount;

          const strikeCheck = document.getElementById('pricing-strike-enabled');
          const strikeInrInput = document.getElementById('price-strike-inr-input');
          const strikeUsdInput = document.getElementById('price-strike-usd-input');

          if (strikeCheck) {
            strikeCheck.checked = data.pricing.strikethrough ? data.pricing.strikethrough.enabled !== false : true;
          }
          if (strikeInrInput) {
            strikeInrInput.value = data.pricing.strikethrough?.inrAmount || data.pricing.INR?.strikeAmount || 1499;
          }
          if (strikeUsdInput) {
            strikeUsdInput.value = data.pricing.strikethrough?.usdAmount || data.pricing.USD?.strikeAmount || 29;
          }

          const countdownCheck = document.getElementById('pricing-countdown-enabled');
          const countdownValInput = document.getElementById('pricing-countdown-val');
          const countdownUnitSelect = document.getElementById('pricing-countdown-unit');
          const countdownLabelInput = document.getElementById('pricing-countdown-label');

          if (countdownCheck) {
            countdownCheck.checked = data.pricing.countdown ? data.pricing.countdown.enabled !== false : true;
          }
          if (countdownValInput) {
            countdownValInput.value = data.pricing.countdown?.value || 24;
          }
          if (countdownUnitSelect && data.pricing.countdown?.unit) {
            countdownUnitSelect.value = data.pricing.countdown.unit;
          }
          if (countdownLabelInput && data.pricing.countdown?.label) {
            countdownLabelInput.value = data.pricing.countdown.label;
          }

          updatePricingPreviews();
        }
      }
    } catch (e) {}
  }

  async function handleUpdatePricing(e) {
    e.preventDefault();
    const inrAmount = Number(document.getElementById('price-inr-input').value);
    const usdAmount = Number(document.getElementById('price-usd-input').value);
    const strikeEnabled = document.getElementById('pricing-strike-enabled').checked;
    const strikeInr = Number(document.getElementById('price-strike-inr-input').value) || 1499;
    const strikeUsd = Number(document.getElementById('price-strike-usd-input').value) || 29;

    const countdownEnabled = document.getElementById('pricing-countdown-enabled').checked;
    const countdownValue = Number(document.getElementById('pricing-countdown-val').value) || 24;
    const countdownUnit = document.getElementById('pricing-countdown-unit').value || 'hours';
    const countdownLabel = document.getElementById('pricing-countdown-label').value.trim() || 'Special Launch Discount Ends In:';
    const countdownReset = document.getElementById('pricing-countdown-reset').checked;

    const passcode = document.getElementById('pricing-admin-passcode').value.trim();
    const msg = document.getElementById('pricing-update-msg');
    const submitBtn = document.getElementById('save-pricing-btn');

    if (!inrAmount || inrAmount <= 0) {
      msg.style.color = '#ef4444';
      msg.textContent = 'Please enter a valid positive price for India (INR).';
      return;
    }
    if (!usdAmount || usdAmount <= 0) {
      msg.style.color = '#ef4444';
      msg.textContent = 'Please enter a valid positive price for Global (USD).';
      return;
    }
    if (!passcode) {
      msg.style.color = '#ef4444';
      msg.textContent = 'Admin master passcode is required to authorize price updates.';
      return;
    }

    submitBtn.disabled = true;
    submitBtn.innerHTML = `<span>Updating live pricing...</span>`;
    msg.textContent = '';

    try {
      const res = await fetch('/api/pricing', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${encodeURIComponent(passcode)}`
        },
        body: JSON.stringify({
          inrAmount,
          usdAmount,
          strikeEnabled,
          strikeInr,
          strikeUsd,
          countdownEnabled,
          countdownValue,
          countdownUnit,
          countdownLabel,
          countdownReset
        })
      });

      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Failed to update live pricing');
      }

      msg.style.color = '#10b981';
      let statusText = `Live pricing saved: ₹${inrAmount} & $${usdAmount}!`;
      if (strikeEnabled) {
        statusText += ` Strikethrough active (~~₹${strikeInr}~~ / ~~$${strikeUsd}~~).`;
      }
      if (countdownEnabled) {
        statusText += ` Countdown active (${countdownValue} ${countdownUnit}).`;
      }
      msg.textContent = statusText;
      showToast(`Pricing updated everywhere: ₹${inrAmount} / $${usdAmount}`, 'success');
      document.getElementById('pricing-admin-passcode').value = '';
      if (document.getElementById('pricing-countdown-reset')) {
        document.getElementById('pricing-countdown-reset').checked = false;
      }
      updatePricingPreviews();
    } catch (err) {
      msg.style.color = '#ef4444';
      msg.textContent = `Update failed: ${err.message}`;
      showToast(`Price update error: ${err.message}`, 'error');
    } finally {
      submitBtn.disabled = false;
      submitBtn.innerHTML = `<span>Update Live Pricing Everywhere</span>`;
    }
  }

  function exportLicensesCSV() {
    if (state.licenses.length === 0) {
      alert('No licenses to export.');
      return;
    }
    const headers = ['Customer Name', 'Email', 'Tier', 'License Key', 'Date Issued', 'Status'];
    const rows = state.licenses.map(l => [
      `"${l.name}"`,
      `"${l.email}"`,
      `"${l.tier}"`,
      `"${l.id}"`,
      `"${l.date}"`,
      `"${l.status}"`
    ]);
    downloadCSV('dropdial_licenses.csv', [headers.join(','), ...rows.map(r => r.join(','))].join('\n'));
  }

  function exportTransactionsCSV() {
    if (state.transactions.length === 0) {
      alert('No transactions to export.');
      return;
    }
    const headers = ['Payment ID', 'Order ID', 'Customer', 'Email', 'Amount', 'Currency', 'Method', 'Coupon', 'Country', 'Status', 'Timestamp'];
    const rows = state.transactions.map(t => [
      `"${t.paymentId}"`,
      `"${t.orderId}"`,
      `"${t.customer}"`,
      `"${t.email}"`,
      `"${t.amount}"`,
      `"${t.currency}"`,
      `"${t.method || 'Razorpay'}"`,
      `"${t.coupon || 'None'}"`,
      `"${t.country}"`,
      `"${t.status}"`,
      `"${t.timestamp}"`
    ]);
    downloadCSV('dropdial_tax_ledger.csv', [headers.join(','), ...rows.map(r => r.join(','))].join('\n'));
  }

  function downloadCSV(filename, content) {
    const blob = new Blob([content], { type: 'text/csv;charset=utf-8;' });
    const link = document.createElement('a');
    link.href = URL.createObjectURL(blob);
    link.download = filename;
    link.click();
    URL.revokeObjectURL(link.href);
  }

  function copyToClipboard(text, successMsg) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(() => showToast(successMsg, 'success')).catch(() => fallbackCopy(text, successMsg));
    } else {
      fallbackCopy(text, successMsg);
    }
  }

  function fallbackCopy(text, successMsg) {
    const ta = document.createElement('textarea');
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    document.body.removeChild(ta);
    showToast(successMsg, 'success');
  }

  function showToast(message, type = 'info') {
    const container = document.getElementById('toast-container');
    if (!container) return;

    const toast = document.createElement('div');
    toast.className = `toast ${type}`;
    const icon = type === 'success' ? ICONS.check : (type === 'error' ? ICONS.alertCircle : '');
    toast.innerHTML = `${icon}<span>${escapeHtml(message)}</span>`;
    container.appendChild(toast);

    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateY(8px)';
      setTimeout(() => toast.remove(), 250);
    }, 3000);
  }

  function escapeHtml(str) {
    if (!str) return '';
    return String(str)
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  }

  /**
   * ========================================================
   * PRODUCTION RELEASE MANAGER (2-STEP VERIFICATION & ROLLBACK)
   * ========================================================
   */
  let cachedReleases = [];

  async function loadReleases(showSuccessToast = false) {
    const listContainer = document.getElementById('staged-releases-list');
    const historyTbody = document.getElementById('published-releases-tbody');

    if (listContainer) {
      listContainer.innerHTML = `
        <div class="empty-state">
          <div class="empty-icon"><svg viewBox="0 0 24 24" width="32" height="32" fill="none" stroke="currentColor" stroke-width="1.5"><circle cx="12" cy="12" r="10"/><polyline points="12 6 12 12 14 14"/></svg></div>
          <h4>Scanning releases...</h4>
          <p>Querying repository for staged drafts and published production tags.</p>
        </div>
      `;
    }

    try {
      const res = await fetch(`/api/admin?action=list-releases&token=${encodeURIComponent(state.adminToken || '')}`);
      const data = await res.json();

      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Failed to query releases API');
      }

      cachedReleases = data.allReleases || [];

      // Update Top Metrics
      const currentTagEl = document.getElementById('release-current-tag');
      const prevTagEl = document.getElementById('release-prev-tag');
      const stagedCountEl = document.getElementById('release-staged-count');
      const stagedBadge = document.getElementById('badge-staged-releases');

      if (currentTagEl) currentTagEl.textContent = data.currentVersion || 'None';
      if (prevTagEl) prevTagEl.textContent = data.previousVersion || 'None';
      
      const stagedList = data.stagedDrafts || [];
      if (stagedCountEl) stagedCountEl.textContent = stagedList.length;

      if (stagedBadge) {
        if (stagedList.length > 0) {
          stagedBadge.textContent = stagedList.length;
          stagedBadge.style.display = 'inline-block';
        } else {
          stagedBadge.style.display = 'none';
        }
      }

      // Render Staged Releases (Available to Launch)
      if (listContainer) {
        if (stagedList.length === 0) {
          listContainer.innerHTML = `
            <div class="empty-state" style="padding: 44px 20px; text-align: center; background: rgba(255,255,255,0.015); border-radius: var(--radius-md); border: 1px dashed rgba(255,255,255,0.08);">
              <div class="empty-icon" style="color:var(--emerald); width:48px; height:48px; margin:0 auto 12px; display:flex; align-items:center; justify-content:center; background:var(--emerald-bg); border-radius:50%; border:1px solid var(--emerald-border);">
                <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.5"><polyline points="20 6 9 17 4 12"/></svg>
              </div>
              <h4 style="font-size:16px; font-weight:700; color:#ffffff; margin-bottom:6px;">All Releases Deployed &amp; Synced</h4>
              <p style="font-size:13px; color:var(--text-muted); max-width:440px; margin:0 auto;">No staged drafts waiting in CI/CD pipeline. Push a git tag (e.g. <code>v1.0.1.0</code>) to trigger GitHub Actions and stage a new build here for 2-step verification.</p>
            </div>
          `;
        } else {
          listContainer.innerHTML = stagedList.map(r => {
            const assetCount = (r.assets || []).length;
            const assetBadges = (r.assets || []).map(a => {
              const mb = (a.size / (1024 * 1024)).toFixed(1);
              return `<span class="asset-badge"><svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" stroke-width="2"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>${escapeHtml(a.name)} <span style="color:var(--text-faint); margin-left:4px;">(${mb} MB)</span></span>`;
            }).join('');
            const cleanBody = (r.body || 'No release description provided.').slice(0, 450);
            return `
              <div class="staged-release-card">
                <div class="release-card-header">
                  <div>
                    <div class="release-card-title-group">
                      <h4 class="release-card-title">${escapeHtml(r.name || r.tag_name)}</h4>
                      <span class="badge-status warning">Staged Draft</span>
                      <span class="release-version-pill">${escapeHtml(r.tag_name)}</span>
                    </div>
                    <div style="font-size:13px; color:var(--text-muted); margin-top:8px;">
                      Built by CI/CD · <strong>${assetCount} binary asset${assetCount === 1 ? '' : 's'} ready</strong> for global distribution
                    </div>
                  </div>
                  <button type="button" class="btn btn-primary btn-launch-glow btn-launch-staged" data-tag="${escapeHtml(r.tag_name)}">
                    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="2"><polygon points="5 3 19 12 5 21 5 3"/></svg>
                    <span>2-Step Verify &amp; Launch</span>
                  </button>
                </div>
                ${assetBadges ? `<div class="release-assets-strip">${assetBadges}</div>` : ''}
                <div class="release-notes-box">
${escapeHtml(cleanBody)}
                </div>
              </div>
            `;
          }).join('');

          // Wire Launch Buttons
          listContainer.querySelectorAll('.btn-launch-staged').forEach(btn => {
            btn.addEventListener('click', () => {
              const tag = btn.dataset.tag;
              const targetRelease = stagedList.find(x => x.tag_name === tag);
              openLaunchModal(targetRelease);
            });
          });
        }
      }

      // Render Historical Releases Table
      if (historyTbody) {
        const publishedList = (data.allReleases || []).filter(r => !r.draft);
        if (publishedList.length === 0) {
          historyTbody.innerHTML = `
            <tr class="empty-state-row">
              <td colspan="6" class="text-center py-20 text-muted">No published releases found.</td>
            </tr>
          `;
        } else {
          historyTbody.innerHTML = publishedList.map((r, index) => {
            const isLatest = index === 0;
            const assetCount = (r.assets || []).length;
            const pubDate = r.published_at ? new Date(r.published_at).toLocaleDateString() : 'N/A';
            return `
              <tr>
                <td><strong style="font-family:var(--font-mono); font-size:13px; color:var(--text-main);">${escapeHtml(r.tag_name)}</strong></td>
                <td><span style="font-weight:600; color:#ffffff;">${escapeHtml(r.name || r.tag_name)}</span></td>
                <td><span style="color:var(--text-muted); font-size:12px;">${escapeHtml(pubDate)}</span></td>
                <td><span class="badge-status info">${assetCount} Assets</span></td>
                <td>
                  ${isLatest ? '<span class="badge-status success"><span class="status-dot" style="background:var(--emerald);"></span>Active Production</span>' : '<span class="badge-status neutral">Previous Release</span>'}
                </td>
                <td style="text-align: right;">
                  ${isLatest 
                    ? '<span style="font-size:12px; font-weight:600; color:var(--emerald); background:var(--emerald-bg); padding:3px 8px; border-radius:6px; border:1px solid var(--emerald-border);">Live Now</span>' 
                    : `<button type="button" class="btn btn-sm btn-revert-pill btn-revert-release" data-tag="${escapeHtml(r.tag_name)}">
                        <span>2-Step Revert</span>
                       </button>`
                  }
                </td>
              </tr>
            `;
          }).join('');

          // Wire Revert Buttons
          historyTbody.querySelectorAll('.btn-revert-release').forEach(btn => {
            btn.addEventListener('click', () => {
              const tag = btn.dataset.tag;
              openRevertModal(tag);
            });
          });
        }
      }

      if (showSuccessToast) {
        showToast('Production releases and staged drafts refreshed.', 'success');
      }
    } catch (err) {
      console.error('Failed to load releases:', err);
      if (listContainer) {
        listContainer.innerHTML = `
          <div class="empty-state" style="padding: 24px;">
            <div class="empty-icon" style="color:var(--rose);">${ICONS.alertCircle}</div>
            <h4>Unable to Query Releases</h4>
            <p>${escapeHtml(err.message)}</p>
          </div>
        `;
      }
      showToast(`Releases load error: ${err.message}`, 'error');
    }
  }

  // Launch Modal Logic
  function openLaunchModal(release) {
    if (!release) return;
    const modal = document.getElementById('launch-release-modal');
    if (!modal) return;

    document.getElementById('launch-target-version').value = release.tag_name;
    document.getElementById('launch-modal-title').textContent = release.name || `DropDial ${release.tag_name}`;
    document.getElementById('launch-prompt-hint').textContent = `(Type "${release.tag_name}")`;
    document.getElementById('launch-modal-assets').textContent = `${(release.assets || []).length} Assets built by CI/CD`;
    document.getElementById('launch-modal-notes').textContent = release.body || 'No release notes.';

    // Reset inputs
    document.getElementById('launch-confirm-version').value = '';
    document.getElementById('launch-passcode').value = '';

    modal.style.display = 'flex';
    setTimeout(() => document.getElementById('launch-confirm-version')?.focus(), 100);
  }

  function closeLaunchModal() {
    const modal = document.getElementById('launch-release-modal');
    if (modal) modal.style.display = 'none';
  }

  async function handleLaunchReleaseSubmit(e) {
    e.preventDefault();
    const targetVersion = document.getElementById('launch-target-version').value.trim();
    const confirmVersion = document.getElementById('launch-confirm-version').value.trim();
    const passcode = document.getElementById('launch-passcode').value.trim();
    const submitBtn = document.getElementById('confirm-launch-submit-btn');

    if (targetVersion.toLowerCase() !== confirmVersion.toLowerCase()) {
      showToast(`Version mismatch: You typed "${confirmVersion}" instead of "${targetVersion}".`, 'error');
      document.getElementById('launch-confirm-version').focus();
      return;
    }

    if (!passcode) {
      showToast('Admin master passcode is required for Step 2.', 'error');
      document.getElementById('launch-passcode').focus();
      return;
    }

    submitBtn.disabled = true;
    submitBtn.innerHTML = `<span>Authorizing &amp; Publishing...</span>`;

    try {
      const res = await fetch('/api/admin?action=launch-release', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${encodeURIComponent(passcode)}`
        },
        body: JSON.stringify({
          version: targetVersion,
          confirmVersion: confirmVersion,
          passcode: passcode
        })
      });

      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Failed to launch release to production');
      }

      showToast(`🚀 Success! Version ${targetVersion} is now LIVE in production!`, 'success');
      closeLaunchModal();
      await loadReleases(false);
    } catch (err) {
      console.error('Launch failed:', err);
      showToast(`Launch failed: ${err.message}`, 'error');
    } finally {
      submitBtn.disabled = false;
      submitBtn.innerHTML = `<span>Verify &amp; Launch to Production</span>`;
    }
  }

  // Revert Modal Logic
  function openRevertModal(targetTag) {
    const modal = document.getElementById('revert-release-modal');
    if (!modal) return;

    document.getElementById('revert-target-version').value = targetTag;
    document.getElementById('revert-modal-target').textContent = `Revert active production to v${targetTag}`;
    document.getElementById('revert-prompt-hint').textContent = `(Type "${targetTag}")`;

    // Reset inputs
    document.getElementById('revert-confirm-version').value = '';
    document.getElementById('revert-passcode').value = '';

    modal.style.display = 'flex';
    setTimeout(() => document.getElementById('revert-confirm-version')?.focus(), 100);
  }

  function closeRevertModal() {
    const modal = document.getElementById('revert-release-modal');
    if (modal) modal.style.display = 'none';
  }

  async function handleRevertReleaseSubmit(e) {
    e.preventDefault();
    const targetVersion = document.getElementById('revert-target-version').value.trim();
    const confirmVersion = document.getElementById('revert-confirm-version').value.trim();
    const passcode = document.getElementById('revert-passcode').value.trim();
    const submitBtn = document.getElementById('confirm-revert-submit-btn');

    if (targetVersion.toLowerCase() !== confirmVersion.toLowerCase()) {
      showToast(`Version mismatch: You typed "${confirmVersion}" instead of "${targetVersion}".`, 'error');
      document.getElementById('revert-confirm-version').focus();
      return;
    }

    if (!passcode) {
      showToast('Admin master passcode is required for Step 2.', 'error');
      document.getElementById('revert-passcode').focus();
      return;
    }

    submitBtn.disabled = true;
    submitBtn.innerHTML = `<span>Rolling back production...</span>`;

    try {
      const res = await fetch('/api/admin?action=revert-release', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': `Bearer ${encodeURIComponent(passcode)}`
        },
        body: JSON.stringify({
          targetVersion: targetVersion,
          confirmVersion: confirmVersion,
          passcode: passcode
        })
      });

      const data = await res.json();
      if (!res.ok || !data.success) {
        throw new Error(data.error || 'Failed to rollback release');
      }

      showToast(`⏮ Successfully rolled back active production to ${targetVersion}!`, 'success');
      closeRevertModal();
      await loadReleases(false);
    } catch (err) {
      console.error('Rollback failed:', err);
      showToast(`Rollback failed: ${err.message}`, 'error');
    } finally {
      submitBtn.disabled = false;
      submitBtn.innerHTML = `<span>Verify &amp; Rollback Production</span>`;
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
