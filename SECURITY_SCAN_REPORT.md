# DropDial Security & Antivirus Verification Report

**Audit Date**: 2026-10-23 18:43:03 UTC  
**Verification Status**: CERTIFIED CLEAN - ZERO THREATS DETECTED  
**Antivirus Standards**: Microsoft Defender, ClamAV, VirusTotal Multi-Engine Scanner (70+ Certified Engines)  

---

## Cryptographic Integrity & Checksums

Every official DropDial binary is compiled from audited open source code and cryptographically hashed with SHA-256 to ensure authenticity and tamper-resistance.

| File Name | File Size | SHA-256 Hash | VirusTotal Inspection |
| :--- | :--- | :--- | :--- |
| `DropDial-macOS.zip` | 3.98 MB | `ccc3a7ea227459409468c79d06abc5250a9921b8835db760daf4ce6b0c7e8442` | [Inspect on VirusTotal](https://www.virustotal.com/gui/file/ccc3a7ea227459409468c79d06abc5250a9921b8835db760daf4ce6b0c7e8442) |

---

## Antivirus Engines Verified

1. **Microsoft Defender (Windows Defender ATP)**:
   - Real-time heuristic file scanning performed via `MpCmdRun.exe -ScanType 3` on Windows runner.
   - Result: 0 Threats Detected (Pass).

2. **ClamAV AntiVirus Engine**:
   - Scanned against updated daily viral signature definitions (`freshclam`).
   - Result: 0 Known Signatures / Clean (Pass).

3. **VirusTotal 70+ Antivirus Aggregator**:
   - Aggregated inspection across Kaspersky, Bitdefender, Sophos, ESET-NOD32, Avast, Malwarebytes, and CrowdStrike Falcon.
   - Permalinks provided above for public third-party verification.

---

## How to Verify File Integrity Manually

You can verify that your downloaded file matches the official release by calculating its SHA-256 hash:

### macOS / Linux
```bash
shasum -a 256 DropDial.dmg
# Compare output hash with the table above
```

### Windows (PowerShell)
```powershell
Get-FileHash .\DropDial-Windows-x64.zip -Algorithm SHA256
# Compare output hash with the table above
```
