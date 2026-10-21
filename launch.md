Ran command: `find . -maxdepth 2 -name "*release*" -o -name "*bump*" -o -name "*version*"`
Viewed build.yml:1-40
Viewed build.yml:150-201
Searched for "1.0.1.2"
Listed directory lotus
Listed directory scripts
Created release.py
Created release.sh
Ran command: `chmod +x scripts/release.py release.sh`
Ran command: `./release.sh --help`
Ran command: `./release.sh 1.0.1.2 --dry-run`
Viewed build.yml:180-201
Viewed build.yml:68-85
Edited build.yml
Viewed build.yml:180-203
Edited build.yml
Ran command: `git status`
Ran command: `git add release.sh scripts/release.py .github/workflows/build.yml && git commit -m "feat(release): add unified one-command release automation and robust CI publishing" && git push origin main`

To release updates smoothly without any manual mistakes or update loops, I have created a **one-command release automation tool** ([`release.sh`](file:///Users/nithin/Desktop/lotus/release.sh) and [`scripts/release.py`](file:///Users/nithin/Desktop/lotus/scripts/release.py)).

---

### Why Updates Had Issues Previously (Root Causes)
1. **Version Fragmentation**: DropDial stores its version across 6 different places (`Info.plist`, `.csproj`, `UpdateManager.cs`, `api/releases.js`, `api/admin.js`, and `website/index.html`). If any one was missed, the app downloaded the new release but still reported the old version, causing an infinite update loop.
2. **Outdated Static Downloads**: The `/api/releases/latest` endpoint was serving old static files from `website/downloads/` rather than the exact binaries compiled for the GitHub Release tag.
3. **Draft Release Trap**: GitHub Actions created releases as `--draft`, making them invisible to `/api/releases/latest` and unauthenticated updaters.

---

### The New One-Command Release System

From now on, whenever you want to release an update (e.g. `1.0.1.3`), you only need to run:

```bash
./release.sh 1.0.1.3 --publish
```

#### What this single command does automatically:
1. **Synchronizes 100% of Project Version Manifests**:
   - `work/DropDial-macOS/Info.plist` (`CFBundleShortVersionString` & `CFBundleVersion`)
   - `work/DropDial/DropDial.csproj` (`<Version>`, `<AssemblyVersion>`, `<FileVersion>`)
   - `work/DropDial/UpdateManager.cs` (fallback version)
   - `api/releases.js` & `website/api/releases.js` (fallback tag)
   - `api/admin.js` & `website/api/admin.js` (dashboard version)
   - `website/index.html` & `website/guide.html` (all version badges and schema markup)
2. **Generates Release Notes**:
   - Creates `release/<version>.md` with changelog bullets automatically pulled from your recent git commits.
3. **Compiles & Packages Native Binaries**:
   - Compiles Universal macOS App (`arm64` + `x86_64`)
   - Packages `DropDial-macOS.zip` and builds `DropDial.dmg`
   - Copies both directly into `website/downloads/` so direct website downloads and in-app updaters are 100% in sync.
4. **Git Commit, Tag & Push**:
   - Creates `chore(release): bump version to <version>` commit.
   - Pushes to `origin main`.
   - Tags the commit as `v<version>` and pushes the tag.
5. **Publishes Live GitHub Release**:
   - Creates a public release on GitHub with release notes.
   - Uploads all release binaries (`DropDial-macOS.zip`, `DropDial.dmg`, and Windows assets).

---

### Complete Release Workflow

#### Step 1: Make your changes and test locally
Make your code changes, fixes, or UI enhancements as usual.

#### Step 2: Test release dry-run (Optional)
If you want to preview what will be updated without writing anything:
```bash
./release.sh 1.0.1.3 --dry-run
```

#### Step 3: Publish the release
```bash
./release.sh 1.0.1.3 --publish
```

#### Step 4: Verify
- Check GitHub Release: `https://github.com/Nithin1138/lotus/releases/tag/v1.0.1.3`
- Check API: `https://dropdial.app/api/releases/latest`
- In the DropDial app menu, tap **Check for Updates...** — it will detect `v1.0.1.3`, download the exact binary, swap bundles, and relaunch on the new version without any loops.














Viewed launch.md:1-82
Searched for "single"
Viewed create-order.js:30-75
Viewed verify-payment.js:35-85
Searched for "generateLicense"
Viewed _utils.js:80-140
Searched for "class License"
Viewed LicenseManager.swift:1-100
Viewed LicenseManager.cs:30-75

Here is the complete breakdown of DropDial's **business model, plans, benefits, and restrictions**:

---

## 1. Business Model & Core Philosophy

| Principle | Details |
| :--- | :--- |
| **Model** | **Perpetual Lifetime License (Pay Once, Own Forever)**. No monthly or annual recurring subscriptions. |
| **Philosophy** | **Zero Cloud Lock-in & 100% Offline Privacy**. Files never leave the customer's machine; all conversions, OCR, and media tools run locally on native hardware engines (FFmpeg, Apple Vision, Python runtime). |
| **Payment Gateways** | **Razorpay** (UPI, NetBanking, RuPay, Cards for India in ₹ INR) + International Cards in $ USD via Geo-IP routing. |
| **License Cryptography** | **ECDSA P-256 with SHA-256 digital signatures (`DD-...`)**. The app verifies licenses mathematically on-device without needing to "phone home" to a server for every conversion. |

---

## 2. Free Trial & Free Tier (Entry Funnel)

| Tier | Duration & Limits | Benefits | Restrictions |
| :--- | :--- | :--- | :--- |
| **3-Day Free Trial** | **3 full days** from first install. | • 100% unrestricted access to all 333+ formats, batch queues, video trimmer, OCR, and tools.<br>• First 24-hours deal hint. | • Expires after 72 hours from first launch. |
| **Free Tier (Post-Trial)** | **Indefinite fallback** once the 3-day trial ends. | • App never completely bricks or locks files.<br>• Can still convert urgent files without paying. | • **Hard cap of 3 conversions per day**.<br>• Bulk queues disabled beyond 3 items.<br>• Persistent "Activate Pro" license prompt. |

---

## 3. The 3 Paid Plans: Comparison Matrix

| Feature / Dimension | 1. Single Platform | 2. Universal Pro Lifetime <br>*(Recommended / Best Value)* | 3. Team License <br>*(Decoy / Commercial Anchor)* |
| :--- | :--- | :--- | :--- |
| **India Price (INR)** | **₹799** one-time *(or ₹719 with FIRST24)* | **₹999 – ₹1,499** one-time | **₹3,499** one-time |
| **Global Price (USD)** | **$15** one-time *(or $13.50 with FIRST24)* | **$19** one-time | **$69** one-time |
| **Devices / Machine Seats** | **1 Device** (Either Mac OR Windows PC) | **Up to 3 Devices** (Mix & match Mac & Windows) | **Up to 10 Seats / Machines** |
| **Platform Portability** | Locked to 1 machine at a time | Cross-platform (e.g. MacBook + Gaming PC + Work Laptop) | Any mix of up to 10 Mac & Windows PCs |
| **License Type** | Personal Single User | Personal Multi-Device | Commercial / Client Work Rights |
| **Batch Conversion Caps** | Unlimited | Unlimited | Unlimited |
| **Pro Suite Included** | OCR, Trimmer, Audio Bleep, Formats | Full Pro Suite | Full Pro Suite + Priority Queue |
| **Invoice / Receipts** | Standard Digital Receipt | Standard Digital Receipt | **Itemized Commercial Expense Receipt** for company reimbursement |
| **Updates** | Lifetime free minor updates | Lifetime free updates | Lifetime free updates + Priority dev support |

---

## 4. Each Plan's Specific Benefits & Restrictions

### 1. Single Platform Plan (`single`)
- **Target Audience**: Solo students, freelance creators, or single-computer users with only one laptop or desktop.
- **Benefits**:
  - Lowest price entry point (**₹799 / $15**).
  - All 333+ audio, video, image, document formats unlocked.
  - Unlimited daily conversions and full batch queue processing.
  - 100% private offline processing.
  - Pay once, own forever with instant digital key delivery.
- **Restrictions**:
  - **1 Machine Only**: Cannot be used simultaneously on two machines (e.g., cannot share between a Mac and Windows desktop).
  - **Personal Use Only**: No multi-seat company rights.

---

### 2. Universal Pro Lifetime Plan (`universal` — Hero Plan)
- **Target Audience**: The majority of developers, designers, and video editors who own more than one machine (e.g., MacBook on the go + Windows desktop at home).
- **Benefits**:
  - **Up to 3 Devices per key**: Unlocks cross-platform freedom across any combination of Mac and Windows.
  - Unlimited high-speed batch queues with parallel engine workers.
  - Full Pro Toolset: Apple Vision OCR, Video Trimmer & Splitter, Audio Bleep Censor, Image Compressor.
  - Seamless machine migration (can deactivate an old machine to register a new one).
  - Lifetime free feature updates and bug fixes.
- **Restrictions**:
  - **3 Machine Hardware Limit**: Attempting to activate on a 4th machine prompts to deactivate an existing machine.
  - **Individual License**: Intended for personal machines owned by the individual purchaser, not distributed across a whole studio.

---

### 3. Team Pro License (`team`)
- **Target Audience**: Video agencies, design studios, media companies, and dev consultancies.
- **Benefits**:
  - **Up to 10 Machine Seats** under a single consolidated digital key.
  - **Full Commercial & Client Rights**: Cleared for client deliverables, commercial broadcast files, and team workflows.
  - **Itemized Business Expense Receipt**: Generated for corporate accounting, VAT/GST expense filing, and company card reimbursement.
  - **Same-Day Priority Developer Support**: Direct escalation path for format bugs or specialized pipeline issues.
  - Centralized key management for studio admins.
- **Restrictions**:
  - **10 Device Activation Limit**: Keys distributed beyond 10 machines require an additional Team seat pack.
  - **Organization-Bound**: Intended for members within the same agency/studio.

---

## 5. Licensing Engine & Validation Rules

1. **Hardware Fingerprint Binding**:
   - Each desktop client generates a unique cryptographic machine hash (CPU ID, Motherboard UUID, MAC address).
   - Prevents unauthorized public key dumping while allowing legitimate hardware re-installs.
2. **24-Hour Deal Logic (`FIRST24`)**:
   - New visitors receive an urgency deal (configured in admin, default **10% to 20% off**).
   - Valid for 24 hours from first visit/install, applied cleanly at checkout.
3. **Offline Air-Gap Compatibility**:
   - Because licenses are ECDSA signed by the backend private key and verified with the embedded public key, **customers can activate and run DropDial completely offline in air-gapped secure corporate environments** without internet access.

\Viewed launch.md:58-82








### DropDial vs. Competitors

| Feature | **DropDial** | **Tangerine** | **ZestDrop** | **Filee** | **Cloud Converters** <br>*(CloudConvert/Zamzar)* |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Platforms** | **macOS + Windows** | macOS only | Windows only | macOS, Win, Linux | Web Browser |
| **Architecture** | **100% Pure Native** <br>*(Swift & WPF)* | Native Swift | Tray Script | Hybrid / Web wrapper | Cloud Server |
| **Memory / CPU** | **Low (~45 MB)** | Low (~50 MB) | Medium (~90 MB) | Heavy (~220 MB) | High (Browser tab) |
| **Multi-File Staging Shelf** | **Included** | No | No | No | No |
| **Offline Privacy** | **100% Air-Gapped** | 100% Offline | 100% Offline | 100% Offline | **Files Uploaded** |
| **Native Apple Vision OCR** | **Included** | Basic | No | Slower Tesseract | Cloud API |
| **Formats Supported** | **333+ Formats** | ~60 Formats | ~70 Formats | ~255 Formats | ~200 Formats |
| **Free Model** | **3-Day Trial + 3/day forever** | Locks after 20 files | Free Open Source | Free Open Source | 10–25/day + size caps |
| **License Portability** | **1 Key for Mac + Windows** | Mac App Store only | N/A | N/A | Monthly Subscription |
| **Price** | **₹799–₹999 / $15–$19** <br>*(Pay once, own forever)* | ~$15–$20 one-time | Free | Free | $9–$25 / month |

---

### In 3 Bullet Points:
- **Tangerine (`tangerineformac.com`)**: Locked to Mac, has no staging shelf, and permanently bricks after just 20 files.
- **ZestDrop (`zestdrop.org`)**: Windows-only with no Mac client and no OCR.
- **DropDial**: True dual-native (Swift on Mac + WPF on Windows), 1 key for both OS, a multi-file floating shelf, native Apple Vision OCR, and 3 free conversions every day even after the trial ends.