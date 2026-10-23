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


CAT = dict(bis=5251, cook=5252, tub=5282, kulfi=5283, cone=ensure('sd-cones-bars-pops', 'Cones, Bars & Pops', 5281, 3))

PH = 'backup/bi_photos.json'
ph = {int(k): v for k, v in json.load(open(PH)).items()} if os.path.exists(PH) else {}
MFG = dict(country_of_origin='IN', manufacturer_name='SEVO Fresh Foods Pvt Ltd', manufacturer_address='SIPCOT Industrial Park, Hosur, Tamil Nadu', manufacturer_pincode='635109')
P = []


def desc(a, pts): return '<p>' + a + '</p><ul>' + ''.join(f'<li>{p}</li>' for p in pts) + '</ul>'


def add(title, brand, c, hsn, gst, shelf, su, generic, variants, photos, summary, points, specs, storage):
    P.append(dict(title=title, brand=brand, cat=CAT[c], hsn=hsn, gst=gst, shelf=shelf, su=su, generic=generic, variants=variants, photos=photos,
                  desc=desc(summary, points), specs=specs, storage=storage))


# variant = (label, unit, pack, mrp, price, sku, L, W, H, gross_g, net_value, net_unit)
add('Glucose Biscuits', 'Crunchy Co', 'bis', '1905', 18, 6, 'months', 'Glucose biscuits',
    [('100 g', 'g', '100 g', '10', '10', 'BI-GLUC-100', 14, 7, 3, 115, '100', 'g'), ('500 g', 'g', '500 g', '50', '45', 'BI-GLUC-500', 24, 14, 6, 540, '500', 'g')],
    [15290322, 7615020], 'Light, crisp glucose biscuits - a household favourite for tea time and kids.', ['Crisp and light', 'Perfect with tea or milk', 'No artificial colours'],
    [('Type', 'Glucose biscuit')], 'Store in a cool, dry place in an airtight container.')
add('Cream Cracker Biscuits', 'Crunchy Co', 'bis', '1905', 18, 6, 'months', 'Cream crackers',
    [('200 g', 'g', '200 g', '40', '35', 'BI-CRACK-200', 20, 8, 4, 220, '200', 'g'), ('400 g', 'g', '400 g', '75', '65', 'BI-CRACK-400', 24, 12, 5, 430, '400', 'g')],
    [37108654, 1359333], 'Crisp, flaky cream crackers - great plain or with cheese, butter and spreads.', ['Crisp and flaky', 'Lightly salted', 'Versatile snack'],
    [('Type', 'Cream crackers'), ('Flavour', 'Lightly salted')], 'Store in a cool, dry place. Keep the pack sealed.')
add('Vanilla Cream Filled Biscuits', 'Crunchy Co', 'bis', '1905', 18, 6, 'months', 'Cream biscuits',
    [('150 g', 'g', '150 g', '45', '40', 'BI-CREAM-150', 18, 10, 4, 170, '150', 'g')], [5822621],
    'Golden biscuits sandwiched with smooth vanilla cream.', ['Smooth vanilla cream', 'Crunchy golden biscuit', 'Kids favourite'], [('Flavour', 'Vanilla')], 'Store in a cool, dry place.')
add('Chocolate Chip Cookies', 'Crumbly', 'cook', '1905', 18, 6, 'months', 'Cookies',
    [('150 g', 'g', '150 g', '75', '65', 'BI-CHOCK-150', 18, 12, 4, 170, '150', 'g'), ('300 g', 'g', '300 g', '140', '125', 'BI-CHOCK-300', 24, 14, 5, 330, '300', 'g')],
    [8081573, 30759934], 'Chewy cookies loaded with real chocolate chips.', ['Real chocolate chips', 'Soft centre, crisp edge', 'No preservatives'], [('Flavour', 'Chocolate chip')], 'Store in a cool, dry place in an airtight container.')
add('Cashew Nut Cookies', 'Crumbly', 'cook', '1905', 18, 6, 'months', 'Cookies',
    [('200 g', 'g', '200 g', '120', '105', 'BI-CASHCK-200', 20, 12, 4, 230, '200', 'g')], [10255807, 8963968],
    'Buttery cookies studded with crunchy cashew pieces.', ['Real cashew nuts', 'Rich buttery taste', 'Baked fresh'], [('Flavour', 'Cashew')], 'Store in a cool, dry place.')
add('Coconut Cookies', 'Crumbly', 'cook', '1905', 18, 6, 'months', 'Cookies',
    [('200 g', 'g', '200 g', '90', '80', 'BI-COCOCK-200', 20, 12, 4, 230, '200', 'g')], [30984652, 39369906],
    'Crunchy cookies made with real desiccated coconut.', ['Real coconut', 'Crunchy texture', 'No artificial colours'], [('Flavour', 'Coconut')], 'Store in a cool, dry place.')
add('Vanilla Bean Ice Cream Tub', 'Frostline', 'tub', '2105', 18, 12, 'months', 'Ice cream',
    [('500 ml', 'ml', '500 ml', '190', '169', 'BI-VANTUB-500', 12, 12, 9, 560, '500', 'ml'), ('1 L', 'l', '1 L', '349', '319', 'BI-VANTUB-1L', 16, 16, 11, 1080, '1', 'l')],
    [9227978, 38987559], 'Classic vanilla bean ice cream - creamy, smooth and made with real vanilla.', ['Real vanilla flavour', 'Smooth and creamy', 'Family-size tub'],
    [('Flavour', 'Vanilla bean')], 'Store at -18 degrees C. Do not refreeze once thawed.')
add('Strawberry Ice Cream Tub', 'Frostline', 'tub', '2105', 18, 12, 'months', 'Ice cream',
    [('500 ml', 'ml', '500 ml', '190', '169', 'BI-STRTUB-500', 12, 12, 9, 560, '500', 'ml'), ('1 L', 'l', '1 L', '349', '319', 'BI-STRTUB-1L', 16, 16, 11, 1080, '1', 'l')],
    [32344628, 16526139], 'Fruity strawberry ice cream with real strawberry pieces.', ['Real strawberry pieces', 'Creamy texture', 'Family-size tub'],
    [('Flavour', 'Strawberry')], 'Store at -18 degrees C. Do not refreeze once thawed.')
add('Butterscotch Crunch Ice Cream Tub', 'Frostline', 'tub', '2105', 18, 12, 'months', 'Ice cream',
    [('500 ml', 'ml', '500 ml', '210', '189', 'BI-BUTTUB-500', 12, 12, 9, 560, '500', 'ml'), ('1 L', 'l', '1 L', '389', '349', 'BI-BUTTUB-1L', 16, 16, 11, 1080, '1', 'l')],
    [5060454, 5060468], 'Butterscotch ice cream swirled with caramel and crunchy praline nuts.', ['Caramel swirl', 'Crunchy praline bits', 'Rich and creamy'],
    [('Flavour', 'Butterscotch')], 'Store at -18 degrees C. Do not refreeze once thawed.')
add('Choco Vanilla Ice Cream Cone (Pack of 2)', 'Frostline', 'cone', '2105', 18, 12, 'months', 'Ice cream cone',
    [('Pack of 2', 'pack', 'Pack of 2', '90', '80', 'BI-CONE-2', 14, 12, 12, 200, '2', 'piece')], [7761650, 38987559],
    'Crispy wafer cones filled with vanilla and chocolate ice cream and a chocolate coating.', ['Crispy wafer cone', 'Vanilla and chocolate', 'Pack of 2'],
    [('Flavour', 'Choco vanilla')], 'Store at -18 degrees C. Do not refreeze once thawed.')
add('Mini Ice Cream Bars (Pack of 6)', 'Frostline', 'cone', '2105', 18, 12, 'months', 'Ice cream bars',
    [('Pack of 6', 'pack', 'Pack of 6', '150', '135', 'BI-MINIBAR-6', 16, 12, 6, 280, '6', 'piece')], [4725704, 4725713],
    'Bite-size ice cream bars in chocolate and vanilla coatings.', ['Chocolate and vanilla', 'Snack-size bars', 'Pack of 6'], [('Flavour', 'Chocolate and vanilla')], 'Store at -18 degrees C.')
add('Mango Fruit Popsicles (Pack of 4)', 'Frostline', 'cone', '2105', 18, 12, 'months', 'Ice lollies',
    [('Pack of 4', 'pack', 'Pack of 4', '99', '89', 'BI-MANGOPOP-4', 16, 12, 6, 280, '4', 'piece')], [39707021, 39455384],
    'Refreshing mango fruit popsicles made with real mango pulp.', ['Real mango pulp', 'Fat free', 'Pack of 4'], [('Flavour', 'Mango')], 'Store at -18 degrees C.')
add('Dry Fruit Kulfi Cups', 'Royal Dairy', 'kulfi', '2105', 18, 12, 'months', 'Kulfi',
    [('Pack of 4', 'pack', 'Pack of 4', '160', '145', 'BI-KULFICUP-4', 14, 12, 8, 440, '4', 'piece'), ('Pack of 6', 'pack', 'Pack of 6', '230', '209', 'BI-KULFICUP-6', 18, 12, 8, 650, '6', 'piece')],
    [12295184, 36576778], 'Traditional slow-cooked kulfi loaded with almonds, pista and cashews in handy cups.', ['Slow-cooked milk', 'Almonds, pista and cashew', 'Ready to serve cups'],
    [('Flavour', 'Dry fruit')], 'Store at -18 degrees C. Do not refreeze once thawed.')
add('Badam Pista Kulfi Bowl', 'Royal Dairy', 'kulfi', '2105', 18, 12, 'months', 'Kulfi',
    [('500 ml', 'ml', '500 ml', '249', '225', 'BI-KULFIBWL-500', 12, 12, 9, 580, '500', 'ml')], [36576772],
    'Creamy badam and pista kulfi in a family bowl - scoop and serve.', ['Creamy, dense texture', 'Real badam and pista', 'Scoop and serve'], [('Flavour', 'Badam pista')],
    'Store at -18 degrees C. Do not refreeze once thawed.')
json.dump({sku: p['gst'] for p in P for v in p['variants'] for sku in [v[5]]}, open('backup/bi_gst.json', 'w'))

need = sorted({i for p in P for i in p['photos']} - set(ph))
for i in need:
    im = Image.open(f'px8/{i}.jpg').convert('RGB'); im.thumbnail((1200, 1200)); out = f'px8/up_{i}.jpg'; im.save(out, 'JPEG', quality=90)
    r = subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Authorization: Bearer ' + tok, '-A', 'curl/8.4.0', '-F', f'image=@{out};type=image/jpeg',
                        'https://vendor.sevo.co.in/api/workforce/seller-hub/products/upload-image/'], capture_output=True, text=True)
    try: ph[i] = json.loads(r.stdout)['image_url']
    except Exception: print('UPLOAD FAIL', i, r.stdout[:200]); sys.exit(1)
json.dump(ph, open(PH, 'w')); print('uploaded', len(need))

existing = {q['sku']: q['id'] for q in prods_all}
s, gl = call('GET', 'variant-groups/')
groups = {x['group_title']: x['id'] for x in (gl if isinstance(gl, list) else gl.get('results', []))}
log = json.load(open('backup/bi_created.json')) if os.path.exists('backup/bi_created.json') else {}
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
json.dump(log, open('backup/bi_created.json', 'w')); print('total', len(log))
