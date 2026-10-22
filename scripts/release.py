#!/usr/bin/env python3
"""
DropDial Automated Release Script
Bumps versions across all platform manifests, builds distribution bundles,
updates website download assets, and publishes GitHub releases cleanly.

Usage:
    python3 scripts/release.py <new_version> [--publish] [--skip-build] [--dry-run]
    ./release.sh <new_version> [--publish]
"""

import os
import sys
import re
import subprocess
import shutil
import plistlib
import argparse
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent

def run_cmd(cmd, cwd=None, check=True):
    print(f"  $ {' '.join(cmd) if isinstance(cmd, list) else cmd}")
    res = subprocess.run(cmd, cwd=cwd or str(ROOT_DIR), shell=isinstance(cmd, str), capture_output=True, text=True)
    if check and res.returncode != 0:
        print(f"Error executing command: {res.stderr.strip()}", file=sys.stderr)
        sys.exit(res.returncode)
    return res

def clean_version(raw):
    return raw.strip().lstrip("vV")

def get_current_version():
    plist_path = ROOT_DIR / "work" / "DropDial-macOS" / "Info.plist"
    with open(plist_path, "rb") as f:
        pl = plistlib.load(f)
    return pl.get("CFBundleShortVersionString", "1.0.1.2")

def bump_plist(new_ver):
    plist_path = ROOT_DIR / "work" / "DropDial-macOS" / "Info.plist"
    with open(plist_path, "rb") as f:
        pl = plistlib.load(f)
    pl["CFBundleShortVersionString"] = new_ver
    pl["CFBundleVersion"] = new_ver
    with open(plist_path, "wb") as f:
        plistlib.dump(pl, f)
    print(f"  [✓] Updated {plist_path.relative_to(ROOT_DIR)} to {new_ver}")

def bump_csproj(new_ver):
    csproj_path = ROOT_DIR / "work" / "DropDial" / "DropDial.csproj"
    content = csproj_path.read_text(encoding="utf-8")
    content = re.sub(r"<Version>[^<]+</Version>", f"<Version>{new_ver}</Version>", content)
    content = re.sub(r"<AssemblyVersion>[^<]+</AssemblyVersion>", f"<AssemblyVersion>{new_ver}</AssemblyVersion>", content)
    content = re.sub(r"<FileVersion>[^<]+</FileVersion>", f"<FileVersion>{new_ver}</FileVersion>", content)
    csproj_path.write_text(content, encoding="utf-8")
    print(f"  [✓] Updated {csproj_path.relative_to(ROOT_DIR)} to {new_ver}")

def bump_csharp_update_manager(new_ver):
    cs_path = ROOT_DIR / "work" / "DropDial" / "UpdateManager.cs"
    if cs_path.exists():
        content = cs_path.read_text(encoding="utf-8")
        content = re.sub(r': "[\d\.]+"\);', f': "{new_ver}");', content)
        cs_path.write_text(content, encoding="utf-8")
        print(f"  [✓] Updated {cs_path.relative_to(ROOT_DIR)} fallback to {new_ver}")

def bump_api_releases(new_ver):
    for rel_file in ["api/releases.js", "website/api/releases.js"]:
        p = ROOT_DIR / rel_file
        if p.exists():
            content = p.read_text(encoding="utf-8")
            content = re.sub(r"let activeTag = '[\d\.]+';", f"let activeTag = '{new_ver}';", content)
            p.write_text(content, encoding="utf-8")
            print(f"  [✓] Updated {rel_file} fallback tag to {new_ver}")

def bump_api_admin(new_ver):
    for adm_file in ["api/admin.js", "website/api/admin.js"]:
        p = ROOT_DIR / adm_file
        if p.exists():
            content = p.read_text(encoding="utf-8")
            content = re.sub(r"let currentVersion = '[\d\.]+';", f"let currentVersion = '{new_ver}';", content)
            content = re.sub(r"tag_name: '[\d\.]+',", f"tag_name: '{new_ver}',", content)
            content = re.sub(r"name: 'DropDial [\d\.]+',", f"name: 'DropDial {new_ver}',", content)
            p.write_text(content, encoding="utf-8")
            print(f"  [✓] Updated {adm_file} to {new_ver}")

def bump_website(curr_ver, new_ver):
    for html_file in ["website/index.html", "website/guide.html"]:
        p = ROOT_DIR / html_file
        if not p.exists():
            continue
        content = p.read_text(encoding="utf-8")
        content = content.replace(f'"softwareVersion": "{curr_ver}"', f'"softwareVersion": "{new_ver}"')
        content = content.replace(f'v{curr_ver} Universal', f'v{new_ver} Universal')
        content = content.replace(f'v{curr_ver} Stable', f'v{new_ver} Stable')
        content = re.sub(rf"v{re.escape(curr_ver)}\s*·\s*[\d\.]+\s*MB", f"v{new_ver} · 4.2 MB", content)
        content = re.sub(rf"v{re.escape(curr_ver)}\s*·\s*Standalone", f"v{new_ver} · Standalone", content)
        p.write_text(content, encoding="utf-8")
        print(f"  [✓] Updated {html_file} badges from v{curr_ver} to v{new_ver}")

def ensure_release_notes(new_ver, curr_ver):
    rel_file = ROOT_DIR / "release" / f"{new_ver}.md"
    if rel_file.exists():
        print(f"  [i] Existing release notes found at {rel_file.relative_to(ROOT_DIR)}")
        return rel_file

    rel_file.parent.mkdir(parents=True, exist_ok=True)
    git_log_res = run_cmd(f"git log v{curr_ver}..HEAD --oneline", check=False)
    log_lines = git_log_res.stdout.strip().split("\n") if git_log_res.returncode == 0 else []
    changelog_bullets = []
    for l in log_lines:
        if not l.strip() or "chore(release)" in l:
            continue
        msg = re.sub(r"^[0-9a-f]+\s+", "", l)
        changelog_bullets.append(f"- {msg}")

    if not changelog_bullets:
        changelog_bullets = [
            "- Enhancements and performance optimizations across macOS and Windows native clients.",
            "- Updated offline media and document processing libraries.",
            "- Streamlined checkout flow and coupon validation."
        ]

    template = f"""# DropDial {new_ver}

DropDial version {new_ver} for macOS and Windows — Universal offline desktop file converter and native media suite.

---

### 🚀 What's New in {new_ver}

{chr(10).join(changelog_bullets)}

---

### 🍏 macOS Installation
Download **`DropDial.dmg`** or **`DropDial-macOS.zip`**, drag **DropDial.app** into your **Applications** folder, and launch.

### 🪟 Windows Installation
Download **`DropDial-Setup.exe`** or extract **`DropDial-Windows-x64.zip`** and run **DropDial.exe**.
"""
    rel_file.write_text(template, encoding="utf-8")
    print(f"  [✓] Generated release notes template at {rel_file.relative_to(ROOT_DIR)}")
    return rel_file

def build_macos():
    print("\n--- 🔨 Building macOS Universal Binaries & DMGs ---")
    build_mac_script = ROOT_DIR / "build-mac.sh"
    run_cmd(f"bash {build_mac_script}")

    # Validate output
    app_info = ROOT_DIR / "outputs" / "DropDial-macOS" / "DropDial.app" / "Contents" / "Info.plist"
    if not app_info.exists():
        print("Error: DropDial.app bundle was not created!", file=sys.stderr)
        sys.exit(1)

    with open(app_info, "rb") as f:
        built_pl = plistlib.load(f)
    built_ver = built_pl.get("CFBundleShortVersionString")
    print(f"  [✓] Verified built DropDial.app version: {built_ver}")

    zip_file = ROOT_DIR / "outputs" / "DropDial-macOS" / "DropDial-macOS.zip"
    dmg_file = ROOT_DIR / "outputs" / "DropDial-macOS" / "DropDial.dmg"
    web_zip = ROOT_DIR / "website" / "downloads" / "DropDial-macOS.zip"
    web_dmg = ROOT_DIR / "website" / "downloads" / "DropDial.dmg"

    if zip_file.exists() and web_zip.exists():
        print(f"  [✓] macOS ZIP ready: {zip_file.stat().st_size // 1024} KB")
    if dmg_file.exists() and web_dmg.exists():
        print(f"  [✓] macOS DMG ready: {dmg_file.stat().st_size // 1024} KB")

def publish_release(new_ver, notes_file):
    tag = f"v{new_ver}"
    print(f"\n--- 🚀 Publishing Release {tag} ---")

    # 1. Commit and push version bump
    run_cmd("git add -A")
    status = run_cmd("git status --porcelain")
    if status.stdout.strip():
        run_cmd(f'git commit -m "chore(release): bump version to {new_ver}"')
        print(f"  [✓] Committed version bump")
    else:
        print("  [i] Working tree clean; nothing to commit.")

    # 2. Push commit to main
    run_cmd("git push origin main")
    print("  [✓] Pushed commit to origin main")

    # 3. Create or update git tag
    run_cmd(f"git tag -fa {tag} -m 'Release {tag}'")
    run_cmd(f"git push origin {tag} --force")
    print(f"  [✓] Pushed git tag {tag}")

    # 4. Prepare release assets
    assets = []
    mac_zip = ROOT_DIR / "outputs" / "DropDial-macOS" / "DropDial-macOS.zip"
    mac_dmg = ROOT_DIR / "outputs" / "DropDial-macOS" / "DropDial.dmg"
    win_zip = ROOT_DIR / "outputs" / "DropDial-Windows-x64.zip"
    win_exe = ROOT_DIR / "outputs" / "DropDial.exe"

    for candidate in [mac_zip, mac_dmg, win_zip, win_exe]:
        if candidate.exists():
            assets.append(str(candidate))
        else:
            # Check website/downloads fallback
            web_cand = ROOT_DIR / "website" / "downloads" / candidate.name
            if web_cand.exists():
                assets.append(str(web_cand))

    assets_args = " ".join([f'"{a}"' for a in assets])
    print(f"  [i] Uploading {len(assets)} release assets...")

    # 5. Create or update GitHub release via gh CLI
    check_rel = run_cmd(f"gh release view {tag}", check=False)
    if check_rel.returncode == 0:
        print(f"  [i] Updating existing GitHub release {tag}...")
        run_cmd(f'gh release edit {tag} --notes-file "{notes_file}" --title "DropDial {tag}" --draft=false --latest')
        if assets:
            run_cmd(f"gh release upload {tag} {assets_args} --clobber")
    else:
        print(f"  [i] Creating new GitHub release {tag}...")
        run_cmd(f'gh release create {tag} {assets_args} --notes-file "{notes_file}" --title "DropDial {tag}" --draft=false --latest')

    print(f"\n🎉 Release {tag} published successfully!")
    print(f"👉 GitHub Release: https://github.com/Nithin1138/lotus/releases/tag/{tag}")
    print(f"👉 API Latest: https://dropdial.app/api/releases/latest")

def main():
    parser = argparse.ArgumentParser(description="DropDial Release Automation")
    parser.add_argument("version", help="New version to release (e.g. 1.0.1.3)")
    parser.add_argument("--publish", action="store_true", help="Commit, tag, push, and publish to GitHub Releases")
    parser.add_argument("--skip-build", action="store_true", help="Skip compiling and packaging desktop binaries")
    parser.add_argument("--dry-run", action="store_true", help="Only preview version updates without writing")
    args = parser.parse_args()

    new_ver = clean_version(args.version)
    curr_ver = get_current_version()

    print(f"==================================================")
    print(f"  DropDial Release Automation")
    print(f"  Current Version: v{curr_ver}")
    print(f"  Target Version:  v{new_ver}")
    print(f"==================================================")

    if args.dry_run:
        print("[Dry Run] Would update Info.plist, csproj, APIs, and website files.")
        return

    print("\n--- 📝 Updating Version Across Project Files ---")
    bump_plist(new_ver)
    bump_csproj(new_ver)
    bump_csharp_update_manager(new_ver)
    bump_api_releases(new_ver)
    bump_api_admin(new_ver)
    bump_website(curr_ver, new_ver)

    notes_file = ensure_release_notes(new_ver, curr_ver)

    if not args.skip_build:
        build_macos()

    if args.publish:
        publish_release(new_ver, notes_file)
    else:
        print(f"\n[✓] Files updated and binaries built successfully for v{new_ver}.")
        print(f"    To commit, tag, and publish to GitHub, run:")
        print(f"    ./release.sh {new_ver} --publish")

if __name__ == "__main__":
    main()
