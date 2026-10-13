"""Puts every product changed on 2026-10-13 back to its saved values.

Usage (token from the Seller Hub login, never stored in this file):
    set SELLERHUB_TOKEN=<access_token>
    python revert_changes.py            # dry run, prints what it would restore
    python revert_changes.py --apply    # really restores

Restores title, unit, pack_size, category and the image list of each product
listed in applied_log.json, from products_full_before.json (same folder).
"""
import json, os, sys, time, urllib.request, urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
TOKEN = os.environ.get("SELLERHUB_TOKEN", "")
BASE = "https://vendor.sevo.co.in/api/workforce/seller-hub/"
before = {int(k): v for k, v in json.load(open(os.path.join(HERE, "products_full_before.json"), encoding="utf-8")).items()}
log = json.load(open(os.path.join(HERE, "applied_log.json"), encoding="utf-8"))
ids = sorted({entry["id"] for entry in log})
apply = "--apply" in sys.argv

for pid in ids:
    old = before[pid]
    body = {
        "title": old["title"],
        "unit": old["unit"],
        "pack_size": old["pack_size"],
        "category": old["category"],
        "images": [im["image_url"] for im in old["images"]],
    }
    print(("RESTORE " if apply else "would restore ") + f"{pid}: {old['title']} | {old['category_path']}")
    if not apply:
        continue
    req = urllib.request.Request(BASE + f"products/{pid}/", data=json.dumps(body).encode(), method="PATCH",
                                 headers={"Authorization": "Bearer " + TOKEN, "Content-Type": "application/json", "User-Agent": "curl/8.4.0"})
    try:
        urllib.request.urlopen(req, timeout=90).read()
    except urllib.error.HTTPError as e:
        print("  FAILED", e.code, e.read()[:200])
    time.sleep(0.4)
