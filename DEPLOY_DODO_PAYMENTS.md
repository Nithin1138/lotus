# 💳 DropDial Payment Routing Deployment Guide (Dodo Payments + Razorpay)

DropDial supports smart dual-gateway payment routing:
* **International Buyers (USD / EUR / Global)**: Routed to **Dodo Payments** for Merchant of Record (MoR) automated global VAT/tax compliance, Apple Pay, Google Pay, and international card processing.
* **Domestic Indian Buyers (INR / UPI)**:
  * If Razorpay credentials (`RAZORPAY_KEY_ID`, `RAZORPAY_KEY_SECRET`) are active: Routes to Razorpay for high-conversion UPI (GPay, PhonePe, Paytm, RuPay) at low domestic transaction fees.
  * If Razorpay credentials are not yet configured: Safely auto-routes through Dodo Payments so checkouts never fail.

All routing behaviors can be toggled in real-time from the **Admin Dashboard** (`/admin.html` -> Payment Gateways).

---

## 🧪 Testing the Integration

### In Test Mode (Sandbox):
1. In your [Dodo Payments Dashboard](https://app.dodopayments.com), switch to **Test Mode**.
2. Grab your test API key (`test_...`) and webhook secret (`whsec_...`).
3. Set `DODO_PAYMENTS_ENVIRONMENT=test_mode` in Vercel or local `.env`.
4. Run a test checkout with Dodo's test card numbers.
5. Verify that:
   - The Dodo checkout overlay opens smoothly.
   - The webhook arrives at `/api/dodo-webhook`.
   - The license key is generated (`DD-...`) and displayed in the email/admin dashboard.

---

## 🚀 Next Steps to Go Live

1. **Create Products in Dodo Payments Dashboard**:
   - **Universal Pro Lifetime**: `$19.00 USD`, One-Time, Digital Goods. Copy the Product ID (`pdt_...`).
   - *(Optional)* **Single Pro** (`$15.00 USD`) and **Team Pro** (`$69.00 USD`).
2. **Configure Webhook**:
   - **URL**: `https://dropdial.app/api/dodo-webhook`
   - **Event**: `payment.succeeded`
   - Copy the Webhook Secret (`whsec_...`).
3. **Add Environment Variables in Vercel**:
   - `DODO_PAYMENTS_API_KEY`: Your live API key (`dodo_sk_...` or test key)
   - `DODO_PAYMENTS_WEBHOOK_KEY`: Your webhook secret (`whsec_...`)
   - `DODO_PRODUCT_UNIVERSAL`: Product ID (`pdt_...`)
   - `DODO_PAYMENTS_ENVIRONMENT`: `live_mode` (or `test_mode` for sandbox testing)
4. **Deploy**:
   - Push to `main` branch to trigger Vercel deployment.