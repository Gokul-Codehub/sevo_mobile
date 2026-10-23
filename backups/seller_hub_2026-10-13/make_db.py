import json, re, subprocess, sys, os, urllib.request, urllib.error, time
from PIL import Image
from api_seller import call, tok
import api

W = 'https://vendor.sevo.co.in/api/workforce/'


def adm(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(W + path, data=data, method=method, headers={
        'Authorization': 'Bearer ' + api.tok, 'Content-Type': 'application/json', 'User-Agent': 'curl/8.4.0', 'Accept': 'application/json'})
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


# ---------------------------------------------------------------- structure
DAIRY, BAKERY, EGGS = 5239, 5245, 5381
s, tree = call('GET', 'categories/tree/')
by_slug = {}


def idx(n):
    by_slug[n['slug']] = n['id']
    for c in n.get('children') or []:
        idx(c)


for n in tree:
    idx(n)

# renames (name only; slugs stay so nothing that points at them breaks)
for cid, new in [(5241, 'Curd & Yogurt'), (5247, 'Buns & Pav')]:
    s, d = adm('PATCH', f'seller-hub/categories/{cid}/', {'name': new})
    print('rename', cid, new, s)

NEW = [  # (slug, name, parent, sort)
    ('db-flavoured-milk', 'Flavoured Milk & Milkshakes', DAIRY, 6),
    ('db-lassi', 'Lassi & Buttermilk', DAIRY, 7),
    ('db-cream', 'Cream & Whipping Cream', DAIRY, 8),
    ('db-rusk', 'Rusks & Toasts', BAKERY, 4),
    ('db-croissant', 'Croissants & Pastries', BAKERY, 5),
    ('db-muffins', 'Muffins & Cupcakes', BAKERY, 6),
    ('db-hen-eggs', 'Hen Eggs', EGGS, 1),
]
cat = {}
for slug, name, parent, sort in NEW:
    if slug in by_slug:
        cat[slug] = by_slug[slug]; print('exists', slug); continue
    s, d = adm('POST', 'seller-hub/categories/', {'name': name, 'slug': slug, 'parent': parent, 'sort_order': sort, 'is_active': True})
    if s not in (200, 201):
        print('CAT FAIL', slug, s, json.dumps(d)[:300]); sys.exit(1)
    cat[slug] = (d.get('category') or d)['id']; print('created', slug, cat[slug])
json.dump(cat, open('backup/db_categories.json', 'w'))

CAT = dict(milk=5240, cheese=5244, bread=5246, cakes=5248, flav=cat['db-flavoured-milk'], lassi=cat['db-lassi'], cream=cat['db-cream'],
           rusk=cat['db-rusk'], crois=cat['db-croissant'], muff=cat['db-muffins'], eggs=cat['db-hen-eggs'])

# ---------------------------------------------------------------- products
PH = 'backup/db_photos.json'
ph = {int(k): v for k, v in json.load(open(PH)).items()} if os.path.exists(PH) else {}
MFG = dict(country_of_origin='IN', manufacturer_name='SEVO Fresh Foods Pvt Ltd',
           manufacturer_address='SIPCOT Industrial Park, Hosur, Tamil Nadu', manufacturer_pincode='635109')


def desc(summary, points):
    return '<p>' + summary + '</p><ul>' + ''.join(f'<li>{p}</li>' for p in points) + '</ul>'


P = []


def add(key, title, brand, cat_key, hsn, gst, shelf, shelf_unit, generic, variants, photos, summary, points, specs, storage, veg='VEG'):
    P.append(dict(key=key, title=title, brand=brand, cat=CAT[cat_key], hsn=hsn, gst=gst, shelf=shelf, shelf_unit=shelf_unit, generic=generic,
                  variants=variants, photos=photos, desc=desc(summary, points), specs=specs, storage=storage, veg=veg))


# variant = (label, unit, pack, mrp, price, sku, L, W, H, gross_g, net_value, net_unit)
add('flav1', 'Strawberry Flavoured Milk', 'Gowri Dairy', 'flav', '2202', 18, 6, 'months', 'Flavoured milk',
    [('180 ml', 'ml', '180 ml', '30', '28', 'DB-FLAV-STR-180', 6, 6, 14, 200, '180', 'ml'),
     ('450 ml', 'ml', '450 ml', '70', '65', 'DB-FLAV-STR-450', 7, 7, 20, 480, '450', 'ml')],
    [5947034, 10066814],
    'Chilled strawberry flavoured milk made with real milk. A delicious, protein-rich treat for kids and adults.',
    ['Made with fresh toned milk', 'Real strawberry flavour', 'Ready to drink, serve chilled'],
    [('Flavour', 'Strawberry'), ('Type', 'Flavoured milk')], 'Keep refrigerated at 4 degrees C. Shake well before drinking.')
add('lassi1', 'Sweet Lassi', 'Gowri Dairy', 'lassi', '0403', 5, 21, 'days', 'Sweet lassi',
    [('200 ml', 'ml', '200 ml', '25', '22', 'DB-LASSI-SW-200', 6, 6, 12, 220, '200', 'ml'),
     ('500 ml', 'ml', '500 ml', '55', '50', 'DB-LASSI-SW-500', 8, 8, 17, 530, '500', 'ml')],
    [18142603, 8917283],
    'Thick, creamy sweet lassi made from fresh curd. Cool, refreshing and a classic summer favourite.',
    ['Made from fresh set curd', 'Naturally cooling', 'Thick, creamy texture'],
    [('Flavour', 'Sweet'), ('Type', 'Lassi')], 'Keep refrigerated at 4 degrees C. Consume before the date on the pack.')
add('lassi2', 'Mango Lassi', 'Gowri Dairy', 'lassi', '0403', 5, 21, 'days', 'Mango lassi',
    [('200 ml', 'ml', '200 ml', '30', '27', 'DB-LASSI-MG-200', 6, 6, 12, 220, '200', 'ml'),
     ('500 ml', 'ml', '500 ml', '65', '59', 'DB-LASSI-MG-500', 8, 8, 17, 530, '500', 'ml')],
    [18142611, 14509267],
    'Rich mango lassi blended with ripe mango pulp and creamy curd.',
    ['Real mango pulp', 'Creamy and refreshing', 'No added preservatives'],
    [('Flavour', 'Mango'), ('Type', 'Lassi')], 'Keep refrigerated at 4 degrees C.')
add('cream1', 'Fresh Cooking Cream', 'Gowri Dairy', 'cream', '0401', 5, 90, 'days', 'Fresh cream',
    [('200 ml', 'ml', '200 ml', '65', '60', 'DB-CREAM-FR-200', 7, 7, 10, 230, '200', 'ml')],
    [5908003],
    'Smooth, pourable fresh cream for gravies, pastas, soups and desserts. Adds richness without overpowering flavour.',
    ['Rich and smooth', 'Perfect for gravies, pasta and desserts', 'UHT treated for longer shelf life'],
    [('Fat', 'Min. 25%'), ('Type', 'Fresh cream')], 'Store in a cool, dry place unopened. Refrigerate after opening and use in 3 days.')
add('cream2', 'Whipping Cream', 'Gowri Dairy', 'cream', '0401', 5, 90, 'days', 'Whipping cream',
    [('250 ml', 'ml', '250 ml', '110', '99', 'DB-CREAM-WH-250', 7, 7, 12, 280, '250', 'ml'),
     ('1 L', 'l', '1 L', '395', '365', 'DB-CREAM-WH-1L', 10, 10, 20, 1080, '1', 'l')],
    [34786516],
    'Whips up light, stable peaks for cakes, desserts, milkshakes and toppings.',
    ['Whips to stiff peaks', 'Neutral taste, lightly sweet', 'Ideal for cakes and desserts'],
    [('Fat', 'Min. 30%'), ('Type', 'Whipping cream')], 'Keep refrigerated at 2-6 degrees C. Shake well before use.')
add('milk4', 'A2 Desi Cow Milk (Glass Bottle)', 'Nilgiri Farms', 'milk', '0401', 0, 4, 'days', 'Cow milk',
    [('500 ml', 'ml', '500 ml', '60', '56', 'DB-MILK-A2-500', 7, 7, 22, 800, '500', 'ml'),
     ('1 L', 'l', '1 L', '110', '102', 'DB-MILK-A2-1L', 9, 9, 28, 1400, '1', 'l')],
    [5946755, 14127931],
    'Pure A2 milk from desi cows, bottled fresh in reusable glass. Rich, creamy and easy to digest.',
    ['A2 beta-casein milk from desi cows', 'Fresh, chilled glass bottle', 'No added preservatives'],
    [('Type', 'A2 cow milk'), ('Packaging', 'Glass bottle')], 'Keep refrigerated at 4 degrees C. Boil before use.')
add('cheese4', 'Cheddar Cheese Block', 'Amul Gold Style', 'cheese', '0406', 12, 8, 'months', 'Cheddar cheese',
    [('200 g', 'g', '200 g', '149', '135', 'DB-CHED-200', 11, 7, 4, 230, '200', 'g'),
     ('400 g', 'g', '400 g', '285', '259', 'DB-CHED-400', 15, 9, 5, 440, '400', 'g')],
    [6004145],
    'Rich, sharp cheddar block - slice, grate or melt it on sandwiches, pizzas and pastas.',
    ['Sharp, full-bodied flavour', 'Great for grating and melting', 'Hygienically vacuum packed'],
    [('Type', 'Cheddar'), ('Form', 'Block')], 'Keep refrigerated at 4 degrees C. Wrap tightly after opening.')
add('bread4', 'Soft Milk Bread', 'Baker\'s Basket', 'bread', '1905', 5, 4, 'days', 'Milk bread',
    [('400 g', 'g', '400 g', '48', '44', 'DB-BREAD-MLK-400', 24, 12, 11, 430, '400', 'g')],
    [10075983, 8599590],
    'Soft, fluffy milk bread baked fresh daily - made for toasts, sandwiches and breakfast.',
    ['Soft, fluffy crumb', 'Baked fresh daily', 'Ideal for sandwiches and toast'],
    [('Type', 'Milk bread'), ('Slices', '16')], 'Store in a cool, dry place. Consume within 3 days.')
add('bread5', 'Garlic Bread Loaf', 'Baker\'s Basket', 'bread', '1905', 5, 5, 'days', 'Garlic bread',
    [('200 g', 'g', '200 g', '65', '58', 'DB-BREAD-GAR-200', 22, 10, 6, 230, '200', 'g')],
    [13062441, 26838687],
    'Crusty loaf loaded with garlic-herb butter. Heat for 5 minutes for a golden, aromatic side.',
    ['Garlic and herb butter', 'Heat and serve in 5 minutes', 'Perfect with pasta and soups'],
    [('Type', 'Garlic bread'), ('Net weight', '200 g')], 'Store in a cool, dry place. Refrigerate for longer life.')
add('rusk1', 'Classic Bread Toast (Rusk)', 'Baker\'s Basket', 'rusk', '1905', 5, 4, 'months', 'Bread toast',
    [('200 g', 'g', '200 g', '45', '40', 'DB-RUSK-CLS-200', 20, 12, 6, 220, '200', 'g'),
     ('400 g', 'g', '400 g', '85', '75', 'DB-RUSK-CLS-400', 24, 14, 8, 430, '400', 'g')],
    [32368692, 1448665],
    'Crisp, twice-baked bread toast that is perfect dunked in tea or coffee.',
    ['Twice baked for extra crunch', 'Perfect with tea and coffee', 'No artificial colours'],
    [('Type', 'Bread toast'), ('Flavour', 'Classic')], 'Store in a cool, dry place in an airtight container.')
add('crois1', 'Butter Croissant (Pack of 2)', 'Baker\'s Basket', 'crois', '1905', 18, 3, 'days', 'Croissant',
    [('Pack of 2', 'pack', 'Pack of 2', '90', '82', 'DB-CROIS-BTR-2', 18, 12, 8, 160, '2', 'piece')],
    [20002837, 13425794],
    'Flaky, buttery croissants baked fresh each morning. Enjoy as is, or warm with jam.',
    ['Real butter layers', 'Baked fresh every morning', 'Pack of 2'],
    [('Quantity', '2 croissants'), ('Type', 'Croissant')], 'Store in a cool, dry place. Consume within 2 days.')
add('muff1', 'Double Chocolate Muffins (Pack of 2)', 'Baker\'s Basket', 'muff', '1905', 18, 4, 'days', 'Muffins',
    [('Pack of 2', 'pack', 'Pack of 2', '80', '72', 'DB-MUFF-CHO-2', 16, 10, 7, 170, '2', 'piece')],
    [3650437, 7190692],
    'Moist, rich muffins loaded with dark chocolate chunks.',
    ['Double chocolate', 'Soft and moist', 'Pack of 2'],
    [('Flavour', 'Double chocolate'), ('Quantity', '2 muffins')], 'Store in a cool, dry place. Consume within 3 days.')
add('muff2', 'Vanilla Cupcakes (Pack of 4)', 'Baker\'s Basket', 'muff', '1905', 18, 4, 'days', 'Cupcakes',
    [('Pack of 4', 'pack', 'Pack of 4', '140', '125', 'DB-CUP-VAN-4', 20, 14, 7, 320, '4', 'piece')],
    [7525116, 1099148],
    'Light vanilla cupcakes topped with swirls of buttercream frosting.',
    ['Soft vanilla sponge', 'Buttercream topping', 'Pack of 4'],
    [('Flavour', 'Vanilla'), ('Quantity', '4 cupcakes')], 'Store in a cool, dry place. Consume within 2 days.')
add('cake4', 'Black Forest Cake', 'Baker\'s Basket', 'cakes', '1905', 18, 3, 'days', 'Cake',
    [('250 g', 'g', '250 g', '165', '149', 'DB-CAKE-BF-250', 14, 14, 8, 300, '250', 'g'),
     ('500 g', 'g', '500 g', '299', '269', 'DB-CAKE-BF-500', 18, 18, 9, 560, '500', 'g')],
    [8802102, 36975011],
    'Classic black forest cake with chocolate sponge, whipped cream and cherries.',
    ['Chocolate sponge layers', 'Fresh cream and cherries', 'Baked fresh to order'],
    [('Flavour', 'Black forest'), ('Type', 'Cake')], 'Keep refrigerated. Consume within 2 days.')
add('egg1', 'Farm Fresh White Eggs', 'Nilgiri Farms', 'eggs', '0407', 0, 21, 'days', 'Hen eggs',
    [('6 pieces', 'piece', 'Pack of 6', '48', '45', 'DB-EGG-WH-6', 16, 11, 7, 340, '6', 'piece'),
     ('12 pieces', 'piece', 'Pack of 12', '92', '85', 'DB-EGG-WH-12', 20, 15, 7, 690, '12', 'piece')],
    [6827029, 6845644],
    'Farm fresh white eggs, graded for size and packed in protective trays.',
    ['Graded and sorted for size', 'Packed in protective trays', 'Rich in protein'],
    [('Type', 'White eggs'), ('Grade', 'Medium')], 'Store in a cool place or refrigerate. Wash before use.', veg='NON_VEG')
add('egg2', 'Country Brown Eggs', 'Nilgiri Farms', 'eggs', '0407', 0, 21, 'days', 'Hen eggs',
    [('6 pieces', 'piece', 'Pack of 6', '60', '55', 'DB-EGG-BR-6', 16, 11, 7, 360, '6', 'piece'),
     ('12 pieces', 'piece', 'Pack of 12', '115', '105', 'DB-EGG-BR-12', 20, 15, 7, 720, '12', 'piece')],
    [2642164, 4184073],
    'Naturally brown eggs from free-range hens - rich yolks and great taste.',
    ['Free-range hens', 'Rich, golden yolks', 'Graded and sorted'],
    [('Type', 'Brown eggs'), ('Grade', 'Medium')], 'Store in a cool place or refrigerate. Wash before use.', veg='NON_VEG')

need = sorted({i for p in P for i in p['photos']} - set(ph))
for i in need:
    im = Image.open(f'px4/{i}.jpg').convert('RGB'); im.thumbnail((1200, 1200)); out = f'px4/up_{i}.jpg'; im.save(out, 'JPEG', quality=90)
    r = subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Authorization: Bearer ' + tok, '-A', 'curl/8.4.0', '-F', f'image=@{out};type=image/jpeg',
                        'https://vendor.sevo.co.in/api/workforce/seller-hub/products/upload-image/'], capture_output=True, text=True)
    try: ph[i] = json.loads(r.stdout)['image_url']
    except Exception: print('UPLOAD FAIL', i, r.stdout[:200]); sys.exit(1)
json.dump(ph, open(PH, 'w')); print('uploaded', len(need))

existing = {}
for pg in (1, 2, 3, 4):
    s, d = call('GET', f'products/?page_size=100&page={pg}')
    for q in d['results']:
        existing[q['sku']] = q['id']
s, gl = call('GET', 'variant-groups/')
groups = {x['group_title']: x['id'] for x in (gl if isinstance(gl, list) else gl.get('results', []))}
log = json.load(open('backup/db_created.json')) if os.path.exists('backup/db_created.json') else {}
failed = []
for p in P:
    gid = None
    if len(p['variants']) > 1:
        if p['title'] in groups:
            gid = groups[p['title']]
        else:
            s, g = call('POST', 'variant-groups/', {'group_title': p['title'], 'variant_attribute_name': 'Size'})
            if s not in (200, 201):
                print('GROUP FAIL', p['title'], s, g); failed.append(p['key']); continue
            gid = (g.get('group') or g)['id']
    for label, unit, pack, mrp, price, sku, L, Wd, H, G, nv, nu in p['variants']:
        if sku in existing:
            print('exists', sku); log[sku] = existing[sku]; continue
        body = dict(category=p['cat'], title=p['title'], brand=p['brand'], unit=unit, pack_size=pack, variant_label=label, mrp=mrp,
                    selling_price=price, hsn_code=p['hsn'], sku=sku, description=p['desc'], storage_info=p['storage'],
                    shelf_life_value=p['shelf'], shelf_life_unit=p['shelf_unit'], images=[ph[i] for i in p['photos']],
                    specs=[{'label': a, 'value': b} for a, b in p['specs']], package_length_cm=L, package_width_cm=Wd,
                    package_height_cm=H, gross_weight_g=G, generic_name=p['generic'], procurement_price=f"{float(price) * 0.78:.2f}",
                    net_weight_value=nv, net_weight_unit=nu, food_type=p['veg'], fssai_license_number='10020043000123', **MFG)
        if gid: body['variant_group'] = gid
        s, d = call('POST', 'products/', body)
        if s != 201:
            print('CREATE FAIL', sku, s, json.dumps(d, ensure_ascii=False)[:400]); failed.append(sku); continue
        log[sku] = d['product']['id']; print('created', sku, d['product']['id'])
json.dump(log, open('backup/db_created.json', 'w'))
json.dump({p['key']: p['gst'] for p in P}, open('backup/db_gst.json', 'w'))
print('total', len(log), 'failed', failed)
