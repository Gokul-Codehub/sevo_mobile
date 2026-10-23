import json, urllib.request, urllib.error, time
import api
W = 'https://vendor.sevo.co.in/api/workforce/'
def adm(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(W + path, data=data, method=method, headers={'Authorization': 'Bearer ' + api.tok, 'Content-Type': 'application/json', 'User-Agent': 'curl/8.4.0', 'Accept': 'application/json'})
    for a in range(6):
        try:
            with urllib.request.urlopen(r, timeout=90) as resp:
                t = resp.read().decode('utf-8'); time.sleep(0.4); return resp.status, (json.loads(t) if t else None)
        except urllib.error.HTTPError as e:
            t = e.read().decode('utf-8', 'replace')
            if e.code in (429, 502, 503, 504) and a < 5: time.sleep(2 * (a + 1)); continue
            try: return e.code, json.loads(t)
            except Exception: return e.code, t
        except (ConnectionError, TimeoutError, OSError): time.sleep(2 * (a + 1))
    return 0, 'network failure'


# ---- category creation is broken (POST /seller-hub/categories/ -> 500) on the restored server, so new
# ---- categories are made by re-purposing unused, empty nodes of the legacy "Grocery" template tree.
import os as _os
_POOL = 'backup/pool_used.json'


def _load_pool_used():
    return set(json.load(open(_POOL))) if _os.path.exists(_POOL) else set()


NONFOOD_ROOTS = (511, 512, 514, 509, 508)   # empty template trees (non-grocery => blank listing_profile => NON_FOOD)


def ensure_cat(by_slug, slug, name, parent, sort, food=True):
    if slug in by_slug:
        return by_slug[slug]
    from api_seller import call
    s, t = call('GET', 'categories/tree/')
    prods = {}
    s2, pl = call('GET', 'products/?page_size=1000')
    for p in pl['results']:
        prods[p['category']] = True
    used = _load_pool_used()
    cand = []

    def walk(n, d=0):
        kids = n.get('children') or []
        if not kids and d >= 1 and n['id'] not in used and n['id'] not in prods:
            cand.append(n['id'])
        for c in kids:
            walk(c, d + 1)

    roots = [2] if food else list(NONFOOD_ROOTS)
    for rid in roots:
        for n in t:
            if n['id'] == rid:
                walk(n)
    cand.sort(reverse=True)
    for cid in cand:
        s, d = adm('PATCH', f'seller-hub/categories/{cid}/', {'name': name, 'slug': slug, 'parent': parent, 'sort_order': sort, 'is_active': True, 'image': '', 'image_url': ''})
        if s == 200:
            used.add(cid); json.dump(sorted(used), open(_POOL, 'w'))
            by_slug[slug] = cid
            print('repurposed', cid, '->', name, '(parent', parent, ', food' if food else ', non-food', ')')
            return cid
        print('repurpose failed', cid, s, str(d)[:150])
        used.add(cid)
    raise SystemExit('no pool category left for ' + name)
