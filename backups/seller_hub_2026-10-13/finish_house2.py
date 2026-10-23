import json, urllib.request, urllib.error, time, sys
import api_seller, api

W = 'https://vendor.sevo.co.in/api/workforce/'


def rq(tok, method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(W + path, data=data, method=method, headers={
        'Authorization': 'Bearer ' + tok, 'Content-Type': 'application/json', 'User-Agent': 'curl/8.4.0', 'Accept': 'application/json'})
    for a in range(6):
        try:
            with urllib.request.urlopen(r, timeout=90) as resp:
                t = resp.read().decode('utf-8'); time.sleep(0.4); return resp.status, (json.loads(t) if t else None)
        except urllib.error.HTTPError as e:
            t = e.read().decode('utf-8', 'replace')
            if e.code in (429, 502, 503, 504) and a < 5:
                time.sleep(2 * (a + 1)); continue
            try: return e.code, json.loads(t)
            except Exception: return e.code, t
        except (ConnectionError, TimeoutError, OSError):
            time.sleep(2 * (a + 1))
    return 0, 'network failure'


seller, admin = api_seller.tok, api.tok
created = json.load(open('backup/house2_created.json'))
GST = {'1101': 5, '1905': 5, '0405': 12, '2105': 18, '3402': 18, '1902': 12, '2106': 18, '2007': 12, '2001': 12, '2005': 12,
       '1904': 12, '2201': 18, '3307': 12}
GSTMAP = json.load(open('backup/house2_gst.json'))


def gst_for(sku):
    return GSTMAP[sku]


state = json.load(open('backup/groc_state.json')) if len(sys.argv) > 1 and sys.argv[1] == 'resume' else {}
for sku, pid in created.items():
    st = state.get(sku, {})
    s, d = rq(seller, 'GET', f'seller-hub/products/{pid}/')
    if s != 200:
        print('GET FAIL', sku, s); continue
    p = d.get('product', d)
    status = p['status']
    hsn = p.get('hsn_code')
    if status == 'DRAFT':
        s, d = rq(seller, 'POST', f'seller-hub/products/{pid}/submit/')
        if s not in (200, 201):
            print('SUBMIT FAIL', sku, s, json.dumps(d)[:300]); continue
        status = 'SUBMITTED'
    if status != 'APPROVED':
        s, d = rq(admin, 'PATCH', f'admin/seller-hub/products/{pid}/set-hsn-gst/', {'hsn_code': hsn, 'gst_rate': gst_for(sku)})
        if s != 200:
            print('GST FAIL', sku, s, json.dumps(d)[:300]); continue
        s, d = rq(admin, 'POST', f'admin/seller-hub/approval/products/{pid}/approve/', {})
        if s not in (200, 201):
            print('APPROVE FAIL', sku, s, json.dumps(d)[:300]); continue
    s, d = rq(seller, 'POST', 'seller-hub/inventory/initialize/', {'product_id': pid, 'on_hand_qty': '60', 'low_stock_threshold': '8', 'reorder_level': '15',
                                                                    'reason': 'Opening stock (pre-launch)'})
    if s in (200, 201):
        print('ok', sku, pid, 'stocked')
    elif s == 409 and 'already' in json.dumps(d):
        print('ok', sku, pid, 'already stocked')
    else:
        print('STOCK FAIL', sku, s, json.dumps(d)[:300])
