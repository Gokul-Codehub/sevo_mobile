import json, sys, os, subprocess
from PIL import Image
from api_seller import call, tok
import make_db_helpers as H

adm = H.adm
prods_all = []
for pg in (1, 2, 3, 4, 5, 6):
    s, d = call('GET', f'products/?page_size=100&page={pg}')
    prods_all += d['results']
s, tree = call('GET', 'categories/tree/')
by_slug = {}


def idx(n):
    by_slug[n['slug']] = n['id']
    for c in n.get('children') or []:
        idx(c)


for n in tree:
    idx(n)


def ensure(slug, name, parent, sort):
    if slug in by_slug:
        return by_slug[slug]
    s, d = adm('POST', 'seller-hub/categories/', {'name': name, 'slug': slug, 'parent': parent, 'sort_order': sort, 'is_active': True})
    if s not in (200, 201):
        print('CAT FAIL', slug, s, json.dumps(d)[:300]); sys.exit(1)
    cid = (d.get('category') or d)['id']; by_slug[slug] = cid; print('created', slug, cid); return cid


CAT = dict(wash=5295, cream=5348, mask=ensure('bpc-face-masks', 'Face Masks', 5424, 3), lipbody=ensure('bpc-lip-body-care', 'Lip & Body Care', 5424, 4))

PH = 'backup/skin_photos.json'
ph = {int(k): v for k, v in json.load(open(PH)).items()} if os.path.exists(PH) else {}
MFG = dict(country_of_origin='IN', manufacturer_name='SEVO Consumer Care Pvt Ltd', manufacturer_address='SIPCOT Industrial Park, Hosur, Tamil Nadu', manufacturer_pincode='635109')
P = []


def desc(a, pts): return '<p>' + a + '</p><ul>' + ''.join(f'<li>{p}</li>' for p in pts) + '</ul>'


def add(title, brand, c, hsn, gst, shelf, su, generic, variants, photos, summary, points, specs, storage):
    P.append(dict(title=title, brand=brand, cat=CAT[c], hsn=hsn, gst=gst, shelf=shelf, su=su, generic=generic, variants=variants, photos=photos,
                  desc=desc(summary, points), specs=specs, storage=storage))


# variant = (label, unit, pack, mrp, price, sku, L, W, H, gross_g, net_value, net_unit)
add('Gentle Foaming Face Wash', 'Dewdrop', 'wash', '3304', 18, 24, 'months', 'Face wash',
    [('100 ml', 'ml', '100 ml', '199', '175', 'SK-FWASH-100', 5, 5, 16, 130, '100', 'ml'), ('200 ml', 'ml', '200 ml', '349', '309', 'SK-FWASH-200', 6, 6, 20, 240, '200', 'ml')],
    [8054404, 7814991], 'Soap-free foaming cleanser that removes dirt and oil without drying the skin.', ['Soap-free formula', 'Dermatologically tested', 'Suitable for daily use'], [('Skin type', 'All skin types'), ('Form', 'Foaming cleanser')], 'Store in a cool, dry place.')
add('Pure Aloe Vera Gel', 'Dewdrop', 'cream', '3304', 18, 24, 'months', 'Aloe vera gel',
    [('150 g', 'g', '150 g', '179', '159', 'SK-ALOE-150', 6, 6, 14, 190, '150', 'g'), ('300 g', 'g', '300 g', '319', '285', 'SK-ALOE-300', 7, 7, 17, 350, '300', 'g')],
    [12304752], 'Cooling aloe vera gel that soothes, hydrates and calms sun-exposed or irritated skin.', ['98% pure aloe vera', 'Lightweight, non-sticky', 'Use on face, body and hair'], [('Key ingredient', 'Aloe vera'), ('Skin type', 'All skin types')], 'Store in a cool, dry place.')
add('Daily Hydrating Moisturiser', 'Dewdrop', 'cream', '3304', 18, 24, 'months', 'Face moisturiser',
    [('50 g', 'g', '50 g', '299', '265', 'SK-MOIST-50', 6, 6, 6, 100, '50', 'g'), ('100 g', 'g', '100 g', '499', '445', 'SK-MOIST-100', 8, 8, 7, 170, '100', 'g')],
    [8490112], 'Light, non-greasy moisturiser with hyaluronic acid and glycerin for 24-hour hydration.', ['Hyaluronic acid and glycerin', 'Non-greasy finish', 'Fragrance free'], [('Skin type', 'All skin types'), ('Key ingredients', 'Hyaluronic acid, glycerin')], 'Store in a cool, dry place.')
add('Hydrating Sheet Mask (Pack of 5)', 'Dewdrop', 'mask', '3307', 18, 24, 'months', 'Sheet mask',
    [('Pack of 5', 'pack', 'Pack of 5', '399', '349', 'SK-SHEET-5', 16, 12, 3, 150, '5', 'piece')], [3846109],
    'Single-use sheet masks soaked in hydrating essence for instantly plump, glowing skin.', ['Hyaluronic acid essence', 'Ready in 15 minutes', 'Pack of 5 masks'], [('Skin type', 'All skin types'), ('Quantity', '5 masks')], 'Store in a cool place away from sunlight.')
add('Nourishing Lip Balm', 'Dewdrop', 'lipbody', '3304', 18, 24, 'months', 'Lip balm',
    [('4.5 g', 'g', '4.5 g', '149', '129', 'SK-LIPBALM-45', 8, 2, 2, 12, '4.5', 'g')], [8129909, 374638],
    'Moisturising lip balm with shea butter and vitamin E for soft, protected lips.', ['Shea butter and vitamin E', 'Non-sticky', 'Gentle, subtle shine'], [('Flavour', 'Natural'), ('Net weight', '4.5 g')], 'Store in a cool, dry place.')
add('Shea Butter Body Lotion', 'Dewdrop', 'lipbody', '3304', 18, 24, 'months', 'Body lotion',
    [('200 ml', 'ml', '200 ml', '299', '265', 'SK-BLOTION-200', 6, 6, 18, 240, '200', 'ml'), ('400 ml', 'ml', '400 ml', '529', '469', 'SK-BLOTION-400', 7, 7, 22, 450, '400', 'ml')],
    [13516802, 5798000], 'Rich, fast-absorbing body lotion with shea butter for soft, smooth skin all day.', ['Shea butter and cocoa butter', '24-hour moisture', 'Non-greasy'], [('Skin type', 'Normal to dry'), ('Key ingredients', 'Shea butter')], 'Store in a cool, dry place.')
json.dump({sku: p['gst'] for p in P for v in p['variants'] for sku in [v[5]]}, open('backup/skin_gst.json', 'w'))

need = sorted({i for p in P for i in p['photos']} - set(ph))
for i in need:
    im = Image.open(f'px12/{i}.jpg').convert('RGB'); im.thumbnail((1200, 1200)); out = f'px12/up_{i}.jpg'; im.save(out, 'JPEG', quality=90)
    r = subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Authorization: Bearer ' + tok, '-A', 'curl/8.4.0', '-F', f'image=@{out};type=image/jpeg',
                        'https://vendor.sevo.co.in/api/workforce/seller-hub/products/upload-image/'], capture_output=True, text=True)
    try: ph[i] = json.loads(r.stdout)['image_url']
    except Exception: print('UPLOAD FAIL', i, r.stdout[:200]); sys.exit(1)
json.dump(ph, open(PH, 'w')); print('uploaded', len(need))

existing = {q['sku']: q['id'] for q in prods_all}
s, gl = call('GET', 'variant-groups/')
groups = {x['group_title']: x['id'] for x in (gl if isinstance(gl, list) else gl.get('results', []))}
log = json.load(open('backup/skin_created.json')) if os.path.exists('backup/skin_created.json') else {}
for p in P:
    gid = None
    if len(p['variants']) > 1:
        gid = groups.get(p['title'])
        if not gid:
            s, g = call('POST', 'variant-groups/', {'group_title': p['title'], 'variant_attribute_name': 'Size'}); gid = (g.get('group') or g)['id']
    for label, unit, pack, mrp, price, sku, L, Wd, Ht, G, nv, nu in p['variants']:
        if sku in existing: log[sku] = existing[sku]; print('exists', sku); continue
        body = dict(category=p['cat'], title=p['title'], brand=p['brand'], unit=unit, pack_size=pack, variant_label=label, mrp=mrp, selling_price=price,
                    hsn_code=p['hsn'], sku=sku, description=p['desc'], storage_info=p['storage'], shelf_life_value=p['shelf'], shelf_life_unit=p['su'],
                    images=[ph[i] for i in p['photos']], specs=[{'label': a, 'value': b} for a, b in p['specs']], package_length_cm=L, package_width_cm=Wd,
                    package_height_cm=Ht, gross_weight_g=G, generic_name=p['generic'], procurement_price=f"{float(price) * 0.78:.2f}", net_weight_value=nv,
                    net_weight_unit=nu, **MFG)
        if gid: body['variant_group'] = gid
        s, d = call('POST', 'products/', body)
        if s != 201: print('CREATE FAIL', sku, s, json.dumps(d, ensure_ascii=False)[:300]); continue
        log[sku] = d['product']['id']; print('created', sku, d['product']['id'])
json.dump(log, open('backup/skin_created.json', 'w')); print('total', len(log))
