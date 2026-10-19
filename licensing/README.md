# DropDial Commercial Licensing System

A complete, self-hosted, cryptographically secure licensing infrastructure for **DropDial** (macOS and Windows).

---

## 🎯 Architecture Overview

```
                      [Customer Buys Pro ($19 / ₹999)]
                                     │
                     ┌───────────────┴───────────────┐
                     ▼                               ▼
       Razorpay Payment Link / Button         Manual Purchase (Direct UPI/Cash)
                     │                               │
         (Webhook payment.captured)                  ▼
                     │                       Run keygen.py script
                     ▼                               │
        licensing/server/app.py ◄────────────────────┘
                     │
         ECDSA P-256 Cryptographic Sign
                     │
       Sends Branded Email to Customer
        "Your DropDial Pro License:
         DD-eyJkIjoiMjAy...VT4gtC..."
                     │
                     ▼
         Customer Pastes Key into DropDial
     (Mac Menu Bar or Windows System Tray)
                     │
                     ▼
        100% Offline Cryptographic Verification
               (Zero Internet Required!)
                     │
                     ▼
             ✓ DropDial Pro Activated!
```

---

## 🔑 Key Concepts

1. **ECDSA P-256 (secp256r1) Digital Signatures**:
   - The license key contains customer data signed with your private key (`keys/private.pem`).
   - The app embeds ONLY the public key (`keys/public.b64`).
   - It is mathematically impossible for anyone to generate a valid license key without your private key.
   - **Zero phoning home / 100% offline**: The app never connects to a server to verify keys. Customers love this for privacy and speed.

2. **7-Day Free Trial**:
   - New users get full access to DropDial for 7 days.
   - Built-in anti-rollback clock check prevents resetting system time.
   - When trial expires, conversion actions display the Pro activation window.

---

## 🛠️ 1. Managing License Keys via CLI

The key generator is in `licensing/keygen.py`.

### Generate a license key for a buyer:
```bash
python3 licensing/keygen.py --email buyer@example.com --name "Jane Doe"
```
**Output:**
```
============================================================
✅ License Key Generated!
============================================================
  Customer: Jane Doe <buyer@example.com>
  Tier:     pro
  Date:     2026-10-19

  License Key:
  DD-eyJkIjoiMjAyNi0xMC0xOSIsImUiOiJidXllckBleGFtcGxlLmNvbSIsIm4iOiJKYW5lIERvZSIsInQiOiJwcm8ifQ.Kj91...
============================================================
```

### Verify an existing license key:
```bash
python3 licensing/keygen.py --verify "DD-eyJ..."
```

---

## 💳 2. Setting Up Razorpay for Automated Sales

You can sell DropDial in India and internationally using Razorpay without writing complex payment code:

### Step 1: Create a Payment Button or Payment Link
1. Log in to your [Razorpay Dashboard](https://dashboard.razorpay.com/).
2. Go to **Payment Buttons** (or **Payment Links**).
3. Create a new button:
   - **Title**: DropDial Pro Lifetime License
   - **Amount**: Fixed (e.g. ₹999 for India or $19 international)
   - Enable mandatory fields: **Email** and **Full Name**.
4. Copy the Payment Button embed code or Payment Link URL and place it on your website / checkout button.

### Step 2: Configure the Webhook for Instant Delivery
1. In Razorpay Dashboard, go to **Settings** → **Webhooks**.
2. Click **+ Add New Webhook**.
3. **Webhook URL**: `https://your-server-url.com/webhook/razorpay`
4. **Secret**: Enter a secret string (e.g., `my_secret_token_2026`).
5. **Active Events**: Check `payment.captured` and `order.paid`.
6. Click **Save**.

### Step 3: Run the Webhook Server
1. Copy `licensing/server/env.example` to `.env` or set environment variables:
   ```bash
   export RAZORPAY_WEBHOOK_SECRET="my_secret_token_2026"
   export SMTP_HOST="smtp.gmail.com"
   export SMTP_PORT=587
   export SMTP_USER="your-email@gmail.com"
   export SMTP_PASS="your-16-char-gmail-app-password"
   export FROM_EMAIL="support@dropdial.com"
   ```
2. Run the server:
   ```bash
   python3 licensing/server/app.py
   ```
3. When a customer pays, Razorpay notifies the server, which immediately:
   - Generates an authentic ECDSA signed license key.
   - Emails a beautiful HTML activation receipt with their key.
   - Logs the sale to `licensing/server/licenses.csv`.

---

## 🔒 Security Best Practices

1. **Private Key Protection**:
   - `licensing/keys/private.pem` is listed in `.gitignore`.
   - **Never** commit `private.pem` to a public or private git repository.
   - Keep a secure backup on an encrypted drive or password manager (1Password, Bitwarden).

2. **Public Key**:
   - Embedded safely in:
     - macOS: `work/DropDial-macOS/LicenseManager.swift`
     - Windows: `work/DropDial/LicenseManager.cs`
   - Even if decompiled, an attacker can only verify existing keys; they cannot sign new ones.
