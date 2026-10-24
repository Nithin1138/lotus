# DropDial Operations Manual & Standard Operating Procedures (SOPs)

## 1. The Daily Operational Cycle

DropDial is architected as an automated, zero-marginal-cost software operation:

```
[Customer buys on dropdial.app]
       ↓ (Automated via Stripe / Razorpay Webhook)
[API generates cryptographic license key in Neon Postgres]
       ↓ (Automated via Resend API)
[Customer receives instant email with 16-char key & download link]
       ↓ (User enters key in native app)
[Native app verifies signature locally via Ed25519 public key]
```

**Founder's Daily Routine (30–45 minutes total):**
1. **08:00 AM – Support Inbox Triage:** Check support inbox (`support@dropdial.app`) for activation questions or edge-case format errors.
2. **08:20 AM – Error Log Review:** Inspect automated crash/error telemetry (anonymized exception reports) from GitHub issues.
3. **08:35 AM – Financial & Analytics Pulse:** Check Stripe / Razorpay daily payouts, unit sales, and website conversion rate.
4. **08:45 AM – Daily Shipping Block:** Build and commit incremental optimizations or user-requested presets.

---

## 2. Standard Operating Procedures (SOPs)

### SOP 1: Customer Support & License Recovery
- **Trigger:** Customer emails saying: "I lost my license key", "Need to move to a new laptop", or "Activation failed".
- **Steps:**
  1. Search customer's email in database / Stripe dashboard.
  2. If found, click "Resend Activation Email" in admin console, or copy key directly into reply template:
     > *"Hi [Name], thanks for using DropDial! Here is your original license key: `XXXX-XXXX-XXXX-XXXX`. You can activate it on up to 3 devices simultaneously. If you ever need to reset activations, let me know anytime."*
  3. Respond within 4 hours maximum.

### SOP 2: Software Release & Automated Notarization
- **Trigger:** A new bug fix or feature update is ready for public deployment.
- **Steps:**
  1. Bump version string in `work/DropDial/DropDial.xcodeproj` and `work/DropDial/DropDial.csproj`.
  2. Build native macOS release:
     ```bash
     xcodebuild -project DropDial.xcodeproj -scheme DropDial -configuration Release archive
     xcrun notarytool submit DropDial.zip --keychain-profile "AC_PASSWORD" --wait
     xcrun stapler staple DropDial.app
     ```
  3. Build native Windows MSIX release signed with code signing certificate.
  4. Generate SHA256 checksums of binaries.
  5. Update `website/api/releases.js` or GitHub Release manifest with download URL and release notes.
  6. Existing user apps will detect the new version within 24 hours and offer a 1-click update.

### SOP 3: Refund Processing (No-Questions-Asked Guarantee)
- **Trigger:** Customer requests a refund within 14 days of purchase.
- **Steps:**
  1. Open Stripe / Razorpay dashboard, locate transaction by email or payment ID.
  2. Click "Issue Full Refund".
  3. Mark license key as deactivated in database.
  4. Send friendly closing note:
     > *"Your refund of $19 has been processed in full and will appear on your statement in 3–5 days. Thank you for giving DropDial a try! If you have any feedback on how we could improve in the future, I'd love to hear it."*

---

## 3. Operational Tool Stack & Costs

| Tool | Purpose | Monthly Cost | Free Tier / Threshold |
| :--- | :--- | :--- | :--- |
| **Vercel / Cloudflare** | Static website & serverless API hosting | $0.00 – $20.00 | Generous free hobby/pro limits |
| **Neon / Supabase** | Serverless PostgreSQL for license storage | $0.00 | Free tier covers 50,000+ licenses |
| **Resend** | Transactional license delivery emails | $0.00 – $20.00 | 3,000 emails/month free |
| **Stripe & Razorpay** | Global credit cards & India UPI payments | Pay-as-you-go | 2.9% + $0.30 per successful sale |
| **Apple Developer** | macOS Notarization & Developer ID cert | $8.25/mo ($99/yr) | Mandatory for Mac Gatekeeper |
| **Code Signing Cert** | Windows SmartScreen EV / OV cert | $20.80/mo ($250/yr) | Mandatory for Windows installer |
| **Total Baseline Ops** | | **~$30 – $60 / mo** | Covered by just 2–3 sales/month |

---

## 4. Legal, Tax, and Compliance Checklist

- [x] **Privacy Policy:** Explicit declaration that DropDial processes 100% of media files locally on the user's CPU/GPU and never transmits files, metadata, or filenames to remote servers.
- [x] **Terms of Service & EULA:** Standard software license agreement granting 3 personal/commercial seats per license with no warranty for data loss.
- [x] **Tax Compliance:** Sales tax / VAT handled through Stripe Tax automated calculation and remittance.
- [x] **Export Compliance:** Software uses standard, open-source AES and Ed25519 cryptography eligible for US EAR mass-market encryption classification.
