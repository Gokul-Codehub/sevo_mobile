import json, sys, os, subprocess
from PIL import Image
from api_seller import call, tok
import make_db_helpers as H

adm = H.adm
s, tree = call('GET', 'categories/tree/')
by_slug = {}


def idx(n):
    by_slug[n['slug']] = n['id']
    for c in n.get('children') or []:
        idx(c)


for n in tree:
    idx(n)


def ensure(slug, name, parent, sort):
    return H.ensure_cat(by_slug, slug, name, parent, sort)


SD = ensure('snacks-drinks', 'Snacks & Drinks', None, 4)


def patch(cid, **body):
    s, d = adm('PATCH', f'seller-hub/categories/{cid}/', body)
    print('patch', cid, body, s, '' if s == 200 else json.dumps(d)[:200])
    return s


# move existing sub-categories (and the products inside them) under Snacks & Drinks
patch(5253, name='Chips & Namkeen', parent=SD, sort_order=1)
patch(5270, name='Drinks & Juices', parent=SD, sort_order=3)
patch(5274, parent=5270)   # Fruit Juices
patch(5276, parent=5270)   # Packaged Water
patch(5267, name='Tea, Coffee & Milk Drinks', parent=SD, sort_order=4)
patch(by_slug['db-flavoured-milk'], parent=5267)   # Flavoured Milk & Milkshakes (moved out of Dairy)
patch(5257, name='Instant Food', parent=SD, sort_order=5)
patch(5261, parent=5257)   # Ready Meals
patch(5262, parent=SD, sort_order=6)
patch(5281, name='Ice Creams & More', parent=SD, sort_order=8)
patch(5250, parent=SD, sort_order=7)   # Biscuits & Cookies becomes tile 7

# remove the now-empty shells
for cid in (5273, 5275, 5260, 5266, 5249):
    s, d = adm('DELETE', f'seller-hub/categories/{cid}/')
    if s not in (200, 204):
        print('delete failed', cid, s, json.dumps(d)[:200], '-> deactivating')
        patch(cid, is_active=False)
    else:
        print('deleted', cid)

# new sub-categories + leaves
SW = ensure('sd-sweets-chocolates', 'Sweets & Chocolates', SD, 2)
CAT = dict(choc=ensure('sd-chocolates', 'Chocolates', SW, 1), mithai=ensure('sd-indian-sweets', 'Indian Sweets', SW, 2),
           candy=ensure('sd-candies', 'Candies & Toffees', SW, 3), fresh=ensure('sd-mouth-fresheners', 'Mouth Fresheners', SW, 4))
json.dump(by_slug, open('backup/snack_categories.json', 'w'))

PH = 'backup/snack_photos.json'
ph = {int(k): v for k, v in json.load(open(PH)).items()} if os.path.exists(PH) else {}
MFG = dict(country_of_origin='IN', manufacturer_name='SEVO Fresh Foods Pvt Ltd', manufacturer_address='SIPCOT Industrial Park, Hosur, Tamil Nadu', manufacturer_pincode='635109')
P = []


def desc(a, pts): return '<p>' + a + '</p><ul>' + ''.join(f'<li>{p}</li>' for p in pts) + '</ul>'


def add(title, brand, c, hsn, shelf, su, generic, variants, photos, summary, points, specs, storage):
    P.append(dict(title=title, brand=brand, cat=CAT[c], hsn=hsn, shelf=shelf, su=su, generic=generic, variants=variants, photos=photos,
                  desc=desc(summary, points), specs=specs, storage=storage))


add('Creamy Milk Chocolate Bar', 'Cocoa Lane', 'choc', '1806', 12, 'months', 'Milk chocolate',
    [('50 g', 'g', '50 g', '55', '50', 'SD-CHOC-MLK-50', 12, 6, 1, 60, '50', 'g'), ('100 g', 'g', '100 g', '105', '95', 'SD-CHOC-MLK-100', 18, 8, 1, 115, '100', 'g')],
    [14456375, 14456366], 'Smooth, creamy milk chocolate made with real cocoa butter and fresh milk.',
    ['Real cocoa butter', 'Melts smoothly', 'Great for gifting and snacking'], [('Type', 'Milk chocolate'), ('Cocoa', '30%')], 'Store in a cool, dry place below 25 degrees C.')
add('Dark Chocolate 70% Cocoa', 'Cocoa Lane', 'choc', '1806', 12, 'months', 'Dark chocolate',
    [('50 g', 'g', '50 g', '75', '69', 'SD-CHOC-DRK-50', 12, 6, 1, 60, '50', 'g'), ('100 g', 'g', '100 g', '139', '125', 'SD-CHOC-DRK-100', 18, 8, 1, 115, '100', 'g')],
    [6167328, 6167332], 'Intense, slightly bitter dark chocolate with 70% cocoa solids.',
    ['70% cocoa', 'Rich, deep flavour', 'No artificial flavours'], [('Type', 'Dark chocolate'), ('Cocoa', '70%')], 'Store in a cool, dry place below 25 degrees C.')
add('Cocoa Dusted Chocolate Truffles', 'Cocoa Lane', 'choc', '1806', 3, 'months', 'Chocolate truffles',
    [('150 g', 'g', '150 g', '299', '269', 'SD-CHOC-TRF-150', 15, 12, 4, 190, '150', 'g')], [27850066, 31488472],
    'Melt-in-the-mouth truffles with a velvety ganache centre, dusted with fine cocoa.',
    ['Creamy ganache centre', 'Dusted with cocoa', 'Perfect gift box'], [('Quantity', 'About 12 pieces'), ('Type', 'Truffles')], 'Store in a cool, dry place. Refrigerate in hot weather.')
add('Kaju Katli (Cashew Fudge)', 'Annapurna Sweets', 'mithai', '2106', 15, 'days', 'Kaju katli',
    [('250 g', 'g', '250 g', '320', '295', 'SD-KAJU-250', 18, 12, 4, 300, '250', 'g'), ('500 g', 'g', '500 g', '620', '569', 'SD-KAJU-500', 24, 16, 4, 560, '500', 'g')],
    [10514163, 18488299], 'Classic diamond-shaped sweet made from finest cashews and pure sugar, finished with edible silver leaf.',
    ['Made from premium cashews', 'Freshly prepared', 'Ideal for festivals and gifting'], [('Main ingredient', 'Cashew'), ('Type', 'Indian sweet')], 'Store in a cool, dry place. Consume within 15 days.')
add('Motichoor Laddoo Box', 'Annapurna Sweets', 'mithai', '2106', 10, 'days', 'Motichoor laddoo',
    [('250 g', 'g', '250 g', '165', '149', 'SD-LADDO-250', 16, 12, 6, 300, '250', 'g'), ('500 g', 'g', '500 g', '315', '289', 'SD-LADDO-500', 22, 16, 6, 560, '500', 'g')],
    [19151506, 19151511], 'Soft, melt-in-the-mouth laddoos made from fine gram flour pearls soaked in saffron syrup and pure ghee.',
    ['Made with pure ghee', 'Soft, juicy pearls', 'Festival favourite'], [('Type', 'Laddoo'), ('Made with', 'Gram flour, ghee, sugar')], 'Store in a cool, dry place. Consume within 10 days.')
add('Gulab Jamun (Ready to Eat)', 'Annapurna Sweets', 'mithai', '2106', 9, 'months', 'Gulab jamun',
    [('500 g', 'g', '500 g', '210', '189', 'SD-GJAM-500', 12, 12, 10, 700, '500', 'g')], [15014918, 7406887],
    'Soft khoya dumplings soaked in sugar syrup - open the tin, warm and serve.',
    ['Ready to eat', 'Made with khoya', 'Serve warm or chilled'], [('Count', 'About 12 pieces'), ('Type', 'Indian sweet')], 'Store in a cool, dry place. Refrigerate once opened and consume in 3 days.')
add('Assorted Fruit Candies', 'Candy Lane', 'candy', '1704', 12, 'months', 'Fruit candies',
    [('150 g', 'g', '150 g', '60', '55', 'SD-CANDY-FR-150', 14, 10, 6, 170, '150', 'g'), ('300 g', 'g', '300 g', '110', '99', 'SD-CANDY-FR-300', 18, 12, 8, 330, '300', 'g')],
    [1906435, 2350388], 'A colourful mix of fruity hard candies in assorted flavours.', ['Assorted fruit flavours', 'Individually wrapped', 'Fun for all ages'],
    [('Type', 'Hard candy'), ('Flavours', 'Assorted')], 'Store in a cool, dry place.')
add('Caramel Toffees', 'Candy Lane', 'candy', '1704', 12, 'months', 'Caramel toffees',
    [('200 g', 'g', '200 g', '80', '72', 'SD-TOFFEE-200', 16, 10, 6, 230, '200', 'g')], [12001952, 36595764],
    'Chewy golden caramel toffees with a rich buttery taste.', ['Real caramel flavour', 'Individually wrapped', 'Soft and chewy'],
    [('Flavour', 'Caramel'), ('Type', 'Toffee')], 'Store in a cool, dry place.')
add('Roasted Saunf Mouth Freshener', 'Mukhwas House', 'fresh', '0909', 12, 'months', 'Roasted fennel seeds',
    [('100 g', 'g', '100 g', '60', '55', 'SD-SAUNF-100', 11, 8, 3, 120, '100', 'g'), ('250 g', 'g', '250 g', '135', '125', 'SD-SAUNF-250', 15, 10, 4, 280, '250', 'g')],
    [16858849, 5988041], 'Lightly roasted fennel seeds - a classic after-meal freshener that aids digestion.',
    ['Lightly roasted', 'Natural digestive', 'No added colours'], [('Type', 'Mouth freshener'), ('Main ingredient', 'Fennel')], 'Store in an airtight container in a cool, dry place.')
add('Peppermint Mints', 'Candy Lane', 'fresh', '1704', 18, 'months', 'Peppermint candy',
    [('100 g', 'g', '100 g', '50', '45', 'SD-MINT-100', 12, 8, 4, 120, '100', 'g')], [4016539, 4016656],
    'Cool peppermint candies for instant fresh breath.', ['Cooling peppermint flavour', 'Individually wrapped', 'Sugar candy'],
    [('Flavour', 'Peppermint'), ('Type', 'Mints')], 'Store in a cool, dry place.')
GST = {'1806': 18, '2106': 5, '1704': 18, '0909': 5}
json.dump({p['title']: GST[p['hsn']] for p in P}, open('backup/snack_gst.json', 'w'))

need = sorted({i for p in P for i in p['photos']} - set(ph))
for i in need:
    im = Image.open(f'px5/{i}.jpg').convert('RGB'); im.thumbnail((1200, 1200)); out = f'px5/up_{i}.jpg'; im.save(out, 'JPEG', quality=90)
    r = subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Authorization: Bearer ' + tok, '-A', 'curl/8.4.0', '-F', f'image=@{out};type=image/jpeg',
                        'https://vendor.sevo.co.in/api/workforce/seller-hub/products/upload-image/'], capture_output=True, text=True)
    try: ph[i] = json.loads(r.stdout)['image_url']
    except Exception: print('UPLOAD FAIL', i, r.stdout[:200]); sys.exit(1)
json.dump(ph, open(PH, 'w')); print('uploaded', len(need))

existing = {}
for pg in (1,):
    s, d = call('GET', f'products/?page_size=100&page={pg}')
    for q in d['results']: existing[q['sku']] = q['id']
s, gl = call('GET', 'variant-groups/')
groups = {x['group_title']: x['id'] for x in (gl if isinstance(gl, list) else gl.get('results', []))}
log = json.load(open('backup/snack_created.json')) if os.path.exists('backup/snack_created.json') else {}
for p in P:
    gid = None
    if len(p['variants']) > 1:
        gid = groups.get(p['title'])
        if not gid:
            s, g = call('POST', 'variant-groups/', {'group_title': p['title'], 'variant_attribute_name': 'Size'})
            gid = (g.get('group') or g)['id']
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
json.dump(log, open('backup/snack_created.json', 'w')); print('total', len(log))
