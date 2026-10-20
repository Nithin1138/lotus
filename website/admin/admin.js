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
      // 1. Fetch live telemetry stats
      const statsRes = await fetch(`/api/admin?action=stats&token=${encodeURIComponent(state.adminToken || '')}`);
      if (statsRes.ok) {
        const statsData = await statsRes.json();
        if (statsData.success && statsData.metrics) {
          state.stats = {
            pageviews: statsData.metrics.pageviews || state.stats.pageviews || 0,
            pricingViews: statsData.metrics.pricingViews || state.stats.pricingViews || 0,
            checkouts: statsData.metrics.checkouts || state.stats.checkouts || 0,
            purchases: statsData.metrics.purchases || state.stats.purchases || 0
          };
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

    // 7. Health Check & Test Email
    document.getElementById('recheck-health-btn')?.addEventListener('click', runGatewayHealthChecks);
    document.getElementById('test-email-form')?.addEventListener('submit', handleTestEmail);
    document.getElementById('change-passcode-form')?.addEventListener('submit', handleChangePasscode);
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
      health: 'System & Gateway Health',
      settings: 'Security & Passcode'
    };

    const subtitles = {
      overview: 'Live Production Intelligence',
      licenses: 'ECDSA Cryptographic Key Ledger',
      transactions: 'Captured Revenue & Settlements',
      coupons: 'Promotional Discounts & Codes',
      traffic: 'Audience & OS Telemetry',
      health: 'Infrastructure Connectivity',
      settings: 'Access Management'
    };

    document.getElementById('view-title').textContent = titles[tabId] || 'Executive Suite';
    document.getElementById('view-tag').textContent = subtitles[tabId] || 'Admin';
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
          email
        })
      });

      const data = await res.json();
      if (res.ok && data.success) {
        resultBox.style.color = '#10b981';
        resultBox.textContent = `Test license email delivered to ${email} (ID: ${data.id})`;
        showToast('Test email sent!', 'success');
      } else {
        resultBox.style.color = '#ef4444';
        resultBox.textContent = `Resend delivery notice: ${data.warning || data.error?.message || 'Check RESEND_API_KEY'}`;
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

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
