# DropDial Pricing Strategy & Recommendations

## 1. What Buyers Said (Van Westendorp Analysis)

From 100 simulated panel buyer interviews:

- **Point of Marginal Cheapness (PMC):** **$8.04** (below this, buyers assume low quality or spyware).
- **Optimal Price Point (OPP):** **$8.12** (minimum friction point).
- **Indifference Price Point (IPP):** **$16.07** (point where equal proportions perceive it as a bargain vs. expensive).
- **Point of Marginal Expensiveness (PME):** **$34.59** (above this, rejection spikes dramatically).
- **Acceptable Price Range:** **$8.04 to $34.59**.
- **Median Bargain Price:** **$12.85**.

---

## 2. What Competitors Charge

| Competitor | Platform | Pricing Model | Price | Drawback |
| :--- | :--- | :--- | :--- | :--- |
| **Tangerine** | macOS only | One-time | ~$15.00 – $20.00 | Bricks permanently after 20 files without paid upgrade. Mac only. |
| **ZestDrop** | Windows only | Free Open Source | $0.00 | Rudimentary tray script, zero OCR, no macOS client. |
| **Filee** | Mac/Win/Linux | Free Open Source | $0.00 | Hybrid Electron wrapper consuming 220MB RAM; slow Tesseract OCR. |
| **Cloud Converters** *(CloudConvert/Zamzar)* | Web Browser | Monthly Subscription | $9.00 – $25.00 / month | Uploads confidential files to remote servers; recurring subscription bills. |

---

## 3. What the Business Needs (Unit Economics)

- **Variable cost per license:** $1.40 (Stripe fees + auth CDN + support buffer).
- **Fixed monthly overhead:** $100/mo (Edge CDN + cert amortization + ops).
- **Contribution margin at $19:** $17.60 (93%).
- **Break-even:** Just **1 license per day** covers all server and administrative overheads.

---

## 4. Recommended Pricing Structure (Good / Better / Best)

| Tier | Price | Who It Is For | What It Includes |
| :--- | :--- | :--- | :--- |
| **Starter (Single OS)** | **$12.00** | Single-platform Mac or PC users | 1 seat (Mac or PC) · 333+ formats · 1 year updates |
| **Universal (Standard) ★** | **$19.00** (₹999) | Dual-platform pros, creators, devs | **3 seats across Mac & Windows** · Lifetime core usage · Staging shelf · Apple Vision OCR · 1 year updates |
| **Team / Studio** | **$59.00** | Agencies, design teams | **10 seats** · Centralized admin key · Priority format support |

---

## 5. Opening Launch Offer (First 14 Days)

- **Launch Deal:** **$14.00** for Universal (or **₹699** in India via UPI / Razorpay).
- **Free Model:** 3-day full trial + **3 free conversions every day forever** (prevents the harsh lock-out that damages Tangerine's reviews).
- **Guarantee:** 14-day unconditional money-back policy.
