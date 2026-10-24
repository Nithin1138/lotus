# DropDial Launch Plan & Execution Run Sheet

## 1. Test Before You Spend (The Pre-Launch Validation)

Before spending any funds on ads or creator sponsorships, validate real willingness to pay with a live landing page test:
- **Test Asset:** Live landing page on `dropdial.app` with video demo, feature comparison, and an "Early Bird Pre-Order ($14)" checkout button powered by Stripe/Razorpay test/live mode.
- **The Success Benchmark:** 30 paid pre-orders within 10 days from organic social posts and early tester communities.
- **Decision Gate:** If 30 orders are met at $14, proceed immediately to public launch countdown. If <10 orders are received, review objections in `founder/panel/results.md` and refine the feature set before paying for code signing certificates.

---

## 2. The 3-Week Countdown to Launch Day

### Week -3: Core Technical & Legal Infrastructure (Critical Path)
- [ ] Confirm Apple Developer Program team enrollment & notarization keys (`Developer ID Application`).
- [ ] Sign Windows `.msix` / `.exe` installer with Sectigo / DigiCert standard code signing certificate.
- [ ] Finalize Razorpay & Stripe production API webhooks for automated license key generation via Resend email.
- [ ] Stress-test the offline fallback: verify app launches and converts 100% offline with Wi-Fi disabled.

### Week -2: Closed Beta & Creator Seeding
- [ ] Distribute DropDial v0.9.8 builds to 25 beta testers across macOS (Apple Silicon + Intel) and Windows 10/11.
- [ ] Fix edge-case issues reported by testers (e.g., path spaces, rare audio codecs, multi-monitor dial positioning).
- [ ] Ship review builds and personalized 30-second video walkthroughs to 10 Mac/Windows YouTube curators and newsletter writers.
- [ ] Finalize the Product Hunt maker page, screenshots, GIF gallery, and first comment.

### Week -1: Staging & Soft Launch
- [ ] Deploy production website build to Vercel/Cloudflare with live Razorpay UPI / Card payments enabled.
- [ ] Conduct end-to-end purchase test on both Mac and Windows: buy license -> receive email with key -> activate in app.
- [ ] Announce early-access soft launch to the 200+ email waitlist subscribers with secret launch discount.
- [ ] Prepare all social media copy, video clips, and Show HN draft markdown.

---

## 3. Launch Day: Hour-by-Hour Run Sheet (Target: Tuesday)

| Time (PST) | Owner | Action Item |
| :--- | :--- | :--- |
| **00:01** | Founder | **Product Hunt Goes Live:** Publish Product Hunt listing with thumbnail GIF, video demo, and maker comment. |
| **00:05** | Founder | Check server health, payment gateways (Stripe/Razorpay), and email delivery queue (Resend). |
| **00:15** | Founder | Send Launch Email to Waitlist: *"DropDial is officially live (+ exclusive $14 early bird pricing)"*. |
| **06:00** | Founder | **Hacker News Submission:** Post *"Show HN: DropDial – Fast, offline media utility for Mac & Windows (Zero cloud uploads)"*. |
| **06:30** | Founder | Post launch announcement video thread on X / Twitter and LinkedIn with interactive demo GIF. |
| **08:00 – 12:00** | Founder | Actively respond to every comment, question, bug report, and feedback on Product Hunt and Show HN within 5 minutes. |
| **12:00** | Founder | Post honest development story on Reddit (`r/macapps` and `r/software`): "Why we built an offline local converter to replace web uploaders". |
| **15:00** | Founder | First Mid-Day Review: Verify conversion rates, license activations, and resolve any user support emails immediately. |
| **18:00** | Founder | Thank-you update tweet on X highlighting day-one stats (sales, bug fixes shipped within 2 hours). |
| **23:59** | Founder | Close of Day 1: Log total revenue, unit volume, and list of top requested formats for v1.0.1. |

---

## 4. Emergency Contingency Plan (What If Something Breaks)

| Scenario | Immediate Action Plan |
| :--- | :--- |
| **Payment Webhook Fails** | In-app "Enter License" dialog includes an instant "Help / Resend Key" link; manual fallback admin tool ready to generate keys instantly. |
| **macOS Gatekeeper Warning** | Provide direct video guide on notarization and standard terminal command fallback (`xattr -cr /Applications/DropDial.app`). |
| **Conversion Error on Rare Format** | App captures local stdout/stderr and offers a 1-click "Report issue without sending file" button; fix shipped via GitHub auto-update within 24 hours. |
| **Server Crash on Website** | Static assets hosted on globally distributed Cloudflare Pages / Vercel Edge with 99.99% uptime guarantee. |

---

## 5. First 30 Days: Metrics & Review Gates

### Key Metrics to Track Weekly
- **Daily Unit Sales:** Target 10 licenses/day (Break-even is just 1/day; Plan is $5,700/mo).
- **Trial-to-Paid Conversion Rate:** Target >8% of free trial downloaders.
- **Refund Rate:** Target <2.5% (Benchmark is 4% for desktop utilities).
- **Crash-Free Session Rate:** Target >99.5%.

### Formal Review Schedule
- **Day 7 Review:** Review initial bug reports; ship v1.0.1 update addressing top 3 requested formats.
- **Day 14 Review:** Conclude early bird pricing ($14 -> $19); measure price elasticity and conversion impact.
- **Day 30 Review:** Calculate Month 1 net operating profit (target: $950+ after all costs); evaluate ROI on YouTube sponsorships for Month 2 expansion.
