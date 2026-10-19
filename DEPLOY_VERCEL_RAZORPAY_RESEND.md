# Deploying DropDial to Vercel with Razorpay & Resend

This guide walks you through deploying the **DropDial Website, Razorpay Payment Gateway, and Resend Automated License Delivery** to **Vercel** in under 5 minutes.

---

## 🏗️ Architecture Overview

```
Customer clicks "Buy Pro" on Website (Vercel)
               │
               ▼
Opens Razorpay Checkout Modal (UPI, Cards, NetBanking)
               │
               ▼
Payment Captured by Razorpay
               │
       ┌───────┴────────────────────────┐
       ▼                                ▼
Client Verification (/api/verify-payment)   Server Webhook (/api/razorpay-webhook)
       │                                │
       └───────┬────────────────────────┘
               │
       1. Verifies HMAC-SHA256 signature
       2. Generates ECDSA P-256 signed license key (`DD-...`)
       3. Sends branded delivery email via Resend API
               │
               ▼
Customer gets license key on screen + in their email inbox!
```

---

## 🚀 Step 1: Push Code to GitHub

Make sure your latest code is pushed to your GitHub repository:
```bash
git add .
git commit -m "feat: add Razorpay, Resend, and Vercel serverless licensing"
git push origin main
```

---

## ⚡ Step 2: Deploy on Vercel

1. Log in to [vercel.com](https://vercel.com) and click **"Add New..."** > **"Project"**.
2. Select your repository: `Nithin1138/lotus`.
3. Keep default settings:
   - **Framework Preset**: `Other` (detected automatically via `vercel.json`).
   - **Root Directory**: `./` (leave default).
4. Do not click Deploy yet — first add your **Environment Variables** (see Step 3 below).

---

## 🔑 Step 3: Configure Vercel Environment Variables

In your Vercel Project Settings (or during initial setup), add the following **5 Environment Variables**:

| Variable Name | Required | Description | Example / How to Get |
| :--- | :--- | :--- | :--- |
| `RAZORPAY_KEY_ID` | **Yes** | Razorpay Public Key | `rzp_live_...` (or `rzp_test_...` for testing) from [Razorpay API Keys](https://dashboard.razorpay.com/app/keys) |
| `RAZORPAY_KEY_SECRET` | **Yes** | Razorpay Secret Key | Found on the same Razorpay page when generating keys |
| `RAZORPAY_WEBHOOK_SECRET` | **Yes** | Secret for webhook verification | Any random secure string, e.g. `whsec_dropdial_987654` |
| `RESEND_API_KEY` | **Yes** | Resend API Key for sending emails | `re_...` from [Resend API Keys](https://resend.com/api-keys) |
| `RESEND_FROM_EMAIL` | Optional | Sender email address | `DropDial Pro <licenses@yourdomain.com>` or `onboarding@resend.dev` |
| `LICENSE_PRIVATE_KEY` | **Yes** | ECDSA P-256 Private PEM key | Content of `licensing/keys/private.pem` (see below) |

### How to get the `LICENSE_PRIVATE_KEY` value:
Run this in your terminal to copy your private key:
```bash
cat licensing/keys/private.pem
```
Copy the full output including `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` and paste it into the Vercel Environment Variable value.

5. Click **Deploy**. Vercel will deploy your site and live serverless functions in ~20 seconds!

---

## 💳 Step 4: Configure Razorpay Webhook (Optional but Recommended)

Setting up the webhook guarantees that even if a user closes their browser immediately after paying, their license is still generated and delivered to their inbox via Resend.

1. Go to your [Razorpay Dashboard > Settings > Webhooks](https://dashboard.razorpay.com/app/webhooks).
2. Click **"+ Add New Webhook"**.
3. Fill in:
   - **Webhook URL**: `https://your-domain.vercel.app/api/razorpay-webhook`
   - **Secret**: Enter the exact same secret you set for `RAZORPAY_WEBHOOK_SECRET` in Vercel.
   - **Active Events**: Check:
     - `payment.captured`
     - `order.paid`
4. Click **Save Webhook**.

---

## ✉️ Step 5: Configure Resend Domain

1. Go to [resend.com/domains](https://resend.com/domains).
2. Add your custom domain (e.g. `dropdial.com`).
3. Add the 3 DNS records (DKIM, SPF, DMARC) provided by Resend to your domain registrar (Cloudflare, GoDaddy, Namecheap, etc.).
4. Once verified, set `RESEND_FROM_EMAIL=DropDial Pro <licenses@dropdial.com>` in your Vercel Environment Variables.
> *Note: While testing, you can use `DropDial Pro <onboarding@resend.dev>` to send emails to your own registered Resend email address without adding a domain.*

---

## 🧪 Testing Your Setup

Once deployed on Vercel:

1. **Check System Health**:
   Visit `https://your-domain.vercel.app/api/status` in your browser. You should see:
   ```json
   {
     "service": "DropDial Licensing & Payment Gateway",
     "status": "operational",
     "config": {
       "razorpay": { "keyIdConfigured": true, "keySecretConfigured": true, "webhookSecretConfigured": true },
       "resend": { "apiKeyConfigured": true, "fromEmailConfigured": true },
       "licensing": { "privateKeyLoaded": true, "algorithm": "ECDSA P-256 (secp256r1) + SHA-256" }
     }
   }
   ```

2. **Test Buy Flow**:
   - Open your Vercel website URL: `https://your-domain.vercel.app`.
   - Click **Buy DropDial Pro ($19 / ₹999)**.
   - The sleek checkout modal will pop up.
   - Enter your name and test email, then proceed to payment.
   - Complete payment (using Razorpay test cards/UPI or live).
   - Upon completion:
     - Your personal lifetime license key (`DD-...`) displays on screen with a **Copy Key** button.
     - Resend sends the activation email to your inbox within seconds.
     - Open DropDial app > Menu > Activate DropDial Pro > Paste Key to verify!

---

## 🛠️ Local Development & Testing

You can also run the entire setup locally with Vercel CLI:
```bash
# Install Vercel CLI (if not already installed)
npm i -g vercel

# Run development server with live serverless functions
vercel dev
```
Open `http://localhost:3000` to preview the website and checkout flow.
