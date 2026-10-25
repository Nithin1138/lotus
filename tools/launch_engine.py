#!/usr/bin/env python3
"""
DropDial Automated Lead Engine
Searches real-time public tech discussions (Hacker News, public RSS feeds)
for high-intent keywords where users need offline file conversion, PDF OCR,
video trimming, or CloudConvert alternatives.
"""

import json
import ssl
import sys
import time
import urllib.request
import urllib.parse

# Bypass local SSL certificate verification on macOS if needed
ssl._create_default_https_context = ssl._create_unverified_context

KEYWORDS = [
    "cloudconvert alternative",
    "convert pdf to word offline",
    "bulk heic to jpg",
    "video compression offline discord",
    "macapps file converter",
    "offline converter windows",
    "convert audio bleep",
    "extract audio from video offline"
]

def search_hn(query, limit=10):
    url = f"https://hn.algolia.com/api/v1/search_by_date?query={urllib.parse.quote(query)}&tags=(story,comment)&hitsPerPage={limit}"
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0 (compatible; DropDialLeadEngine/1.0)'})
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode('utf-8'))
            return data.get('hits', [])
    except Exception as e:
        print(f"[!] Error fetching HN query '{query}': {e}", file=sys.stderr)
        return []

def format_lead(hit):
    title = hit.get('title') or hit.get('story_title') or 'Comment discussion'
    url = hit.get('url') or hit.get('story_url') or f"https://news.ycombinator.com/item?id={hit.get('objectID')}"
    author = hit.get('author', 'Anonymous')
    created_at = hit.get('created_at', '')[:10]
    comment_text = hit.get('comment_text') or ''
    # clean HTML tags from comment snippet
    import re
    clean_text = re.sub(r'<[^>]+>', ' ', comment_text).strip()
    snippet = clean_text[:200] + ('...' if len(clean_text) > 200 else '')
    
    return {
        "source": "Hacker News",
        "title": title,
        "author": author,
        "date": created_at,
        "url": url,
        "id": hit.get('objectID'),
        "snippet": snippet
    }

def main():
    print("=" * 70)
    print("  🚀 DropDial High-Intent Customer Lead Finder (Real-time)")
    print("=" * 70)
    print("Scanning active discussions for file conversion & offline privacy needs...\n")
    
    leads = []
    seen_ids = set()

    for kw in KEYWORDS:
        print(f"[*] Scanning: '{kw}'...")
        hits = search_hn(kw, limit=8)
        for h in hits:
            obj_id = h.get('objectID')
            if obj_id and obj_id not in seen_ids:
                seen_ids.add(obj_id)
                lead = format_lead(h)
                leads.append(lead)
        time.sleep(0.3)

    print(f"\n[+] Total live discussions found: {len(leads)}\n")
    print("-" * 70)

    for i, lead in enumerate(leads[:15], 1):
        print(f"[{i}] {lead['title']}")
        print(f"    Author: {lead['author']} | Date: {lead['date']}")
        print(f"    Link:   {lead['url']}")
        if lead['snippet']:
            print(f"    Quote:  \"{lead['snippet']}\"")
        print("-" * 70)

    print("\n💡 Suggested Reply Framework for High Conversion:")
    print('"""')
    print("Hey! If you deal with sensitive files or don't want to hit online upload limits,")
    print("we built DropDial (https://dropdial.app) — a native desktop dial for Mac & Windows")
    print("that runs 100% offline (no cloud uploads, sub-15ms wake).")
    print("Supports 333+ formats, batch HEIC/PDF/Word, and video trimming.")
    print("Use coupon code 'DROPDIAL50' for 50% off lifetime access ($9.50).")
    print('"""')

if __name__ == '__main__':
    main()
