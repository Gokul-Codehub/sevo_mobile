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


CAT = dict(bis=5251, wafer=ensure('sd-wafers-rolls', 'Wafers & Rolls', 5250, 3), healthy=ensure('sd-healthy-biscuits', 'Healthy Biscuits & Crackers', 5250, 4))

PH = 'backup/bi2_photos.json'
ph = {int(k): v for k, v in json.load(open(PH)).items()} if os.path.exists(PH) else {}
MFG = dict(country_of_origin='IN', manufacturer_name='SEVO Fresh Foods Pvt Ltd', manufacturer_address='SIPCOT Industrial Park, Hosur, Tamil Nadu', manufacturer_pincode='635109')
P = []


def desc(a, pts): return '<p>' + a + '</p><ul>' + ''.join(f'<li>{p}</li>' for p in pts) + '</ul>'


def add(title, brand, c, hsn, gst, shelf, su, generic, variants, photos, summary, points, specs, storage):
    P.append(dict(title=title, brand=brand, cat=CAT[c], hsn=hsn, gst=gst, shelf=shelf, su=su, generic=generic, variants=variants, photos=photos,
                  desc=desc(summary, points), specs=specs, storage=storage))


# variant = (label, unit, pack, mrp, price, sku, L, W, H, gross_g, net_value, net_unit)
add('Butter Biscuits', 'Crunchy Co', 'bis', '1905', 18, 6, 'months', 'Butter biscuits',
    [('100 g', 'g', '100 g', '25', '22', 'BI2-BUTTER-100', 16, 8, 3, 115, '100', 'g'), ('200 g', 'g', '200 g', '48', '42', 'BI2-BUTTER-200', 20, 10, 4, 220, '200', 'g')],
    [39852284, 574125], 'Golden, melt-in-the-mouth biscuits baked with real butter.', ['Real butter taste', 'Crisp and light', 'Perfect with tea'], [('Type', 'Butter biscuit')], 'Store in a cool, dry place in an airtight container.')
add('Milk Biscuits', 'Crunchy Co', 'bis', '1905', 18, 6, 'months', 'Milk biscuits',
    [('200 g', 'g', '200 g', '30', '27', 'BI2-MILK-200', 20, 10, 4, 220, '200', 'g'), ('400 g', 'g', '400 g', '56', '50', 'BI2-MILK-400', 24, 14, 5, 430, '400', 'g')],
    [28664618, 7855274], 'Light, crunchy milk biscuits made with fresh milk - a favourite with kids.', ['Made with fresh milk', 'Crisp and light', 'Great dipped in milk'], [('Type', 'Milk biscuit')], 'Store in a cool, dry place.')
add('Jam Heart Biscuits', 'Crumbly', 'bis', '1905', 18, 6, 'months', 'Jam biscuits',
    [('150 g', 'g', '150 g', '70', '62', 'BI2-JAMHEART-150', 18, 12, 4, 170, '150', 'g')], [30918627],
    'Shortbread hearts with a fruity jam centre.', ['Real fruit jam', 'Buttery shortbread', 'Gift-worthy'], [('Filling', 'Mixed fruit jam')], 'Store in a cool, dry place.')
add('Chocolate Vanilla Swirl Biscuits', 'Crumbly', 'bis', '1905', 18, 6, 'months', 'Swirl biscuits',
    [('150 g', 'g', '150 g', '65', '58', 'BI2-SWIRL-150', 18, 12, 4, 170, '150', 'g')], [35152904],
    'Crisp biscuits with a marbled chocolate and vanilla swirl.', ['Chocolate and vanilla swirl', 'Crunchy texture', 'Baked fresh'], [('Flavour', 'Chocolate vanilla')], 'Store in a cool, dry place.')
add('Chocolate Wafer Rolls', 'Waffle Lane', 'wafer', '1905', 18, 8, 'months', 'Wafer rolls',
    [('100 g', 'g', '100 g', '60', '54', 'BI2-WAFRLCH-100', 18, 8, 5, 120, '100', 'g'), ('200 g', 'g', '200 g', '115', '102', 'BI2-WAFRLCH-200', 22, 10, 6, 225, '200', 'g')],
    [31202922, 11763203], 'Crispy wafer rolls dipped in chocolate with a creamy filling.', ['Crispy wafer tubes', 'Chocolate-dipped ends', 'Creamy filling'], [('Flavour', 'Chocolate')], 'Store in a cool, dry place.')
add('Cream Wafer Rolls', 'Waffle Lane', 'wafer', '1905', 18, 8, 'months', 'Wafer rolls',
    [('100 g', 'g', '100 g', '55', '49', 'BI2-WAFRLCR-100', 18, 8, 5, 120, '100', 'g')], [18955560, 18955552],
    'Golden waffle rolls filled with sweet cream.', ['Crunchy golden shell', 'Sweet cream filling', 'Snack-size'], [('Flavour', 'Cream')], 'Store in a cool, dry place.')
add('Chocolate Wafer Bars', 'Waffle Lane', 'wafer', '1905', 18, 8, 'months', 'Wafer bars',
    [('Pack of 4', 'pack', 'Pack of 4', '60', '55', 'BI2-WAFBAR-4', 16, 8, 4, 120, '4', 'piece'), ('Pack of 8', 'pack', 'Pack of 8', '115', '102', 'BI2-WAFBAR-8', 20, 10, 5, 230, '8', 'piece')],
    [15911875, 8967889], 'Layered crisp wafers with rich chocolate cream.', ['Crisp layers', 'Rich chocolate cream', 'Individually wrapped'], [('Flavour', 'Chocolate')], 'Store in a cool, dry place.')
add('Oats & Honey Biscuits', 'NutriBake', 'healthy', '1905', 18, 6, 'months', 'Oats biscuits',
    [('150 g', 'g', '150 g', '55', '49', 'BI2-OATHON-150', 18, 10, 4, 170, '150', 'g'), ('300 g', 'g', '300 g', '100', '89', 'BI2-OATHON-300', 22, 12, 5, 330, '300', 'g')],
    [14527828, 11842165], 'Wholesome oat biscuits sweetened with honey - high in fibre.', ['Made with whole oats', 'Sweetened with honey', 'No maida'], [('Main ingredient', 'Oats')], 'Store in a cool, dry place.')
add('Multigrain Crackers', 'NutriBake', 'healthy', '1905', 18, 6, 'months', 'Crackers',
    [('150 g', 'g', '150 g', '70', '62', 'BI2-MGCRACK-150', 20, 10, 4, 170, '150', 'g')], [36040664, 691142],
    'Crisp multigrain crackers with seeds - a light, healthy snack.', ['Multigrain and seeds', 'Light and crisp', 'Baked, not fried'], [('Type', 'Multigrain crackers')], 'Store in a cool, dry place.')
add('Seeded Crispbread', 'NutriBake', 'healthy', '1905', 18, 6, 'months', 'Crispbread',
    [('200 g', 'g', '200 g', '95', '85', 'BI2-CRISPBR-200', 24, 12, 4, 230, '200', 'g')], [36040721, 6103122],
    'Wholegrain crispbread with seeds - great with spreads, cheese or soups.', ['Wholegrain', 'High in fibre', 'Baked crisp'], [('Type', 'Crispbread')], 'Store in a cool, dry place.')
json.dump({sku: p['gst'] for p in P for v in p['variants'] for sku in [v[5]]}, open('backup/bi2_gst.json', 'w'))

need = sorted({i for p in P for i in p['photos']} - set(ph))
for i in need:
    im = Image.open(f'px11/{i}.jpg').convert('RGB'); im.thumbnail((1200, 1200)); out = f'px11/up_{i}.jpg'; im.save(out, 'JPEG', quality=90)
    r = subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Authorization: Bearer ' + tok, '-A', 'curl/8.4.0', '-F', f'image=@{out};type=image/jpeg',
                        'https://vendor.sevo.co.in/api/workforce/seller-hub/products/upload-image/'], capture_output=True, text=True)
    try: ph[i] = json.loads(r.stdout)['image_url']
    except Exception: print('UPLOAD FAIL', i, r.stdout[:200]); sys.exit(1)
json.dump(ph, open(PH, 'w')); print('uploaded', len(need))

existing = {q['sku']: q['id'] for q in prods_all}
s, gl = call('GET', 'variant-groups/')
groups = {x['group_title']: x['id'] for x in (gl if isinstance(gl, list) else gl.get('results', []))}
log = json.load(open('backup/bi2_created.json')) if os.path.exists('backup/bi2_created.json') else {}
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
                    net_weight_unit=nu, food_type='VEG', fssai_license_number='10020043000123', **MFG)
        if gid: body['variant_group'] = gid
        s, d = call('POST', 'products/', body)
        if s != 201: print('CREATE FAIL', sku, s, json.dumps(d, ensure_ascii=False)[:300]); continue
        log[sku] = d['product']['id']; print('created', sku, d['product']['id'])
json.dump(log, open('backup/bi2_created.json', 'w')); print('total', len(log))
