import json, re, subprocess, sys, os
from PIL import Image
from api_seller import call, tok

PH = 'backup/groc_photos.json'
ph = {int(k): v for k, v in json.load(open(PH)).items()} if os.path.exists(PH) else {}
MFG = dict(country_of_origin='IN', manufacturer_name='SEVO Consumer Products Pvt Ltd',
           manufacturer_address='SIPCOT Industrial Park, Hosur, Tamil Nadu', manufacturer_pincode='635109')
FOOD = dict(food_type='VEG', fssai_license_number='10020043000123')


def desc(summary, points):
    return '<p>' + summary + '</p><ul>' + ''.join(f'<li>{p}</li>' for p in points) + '</ul>'


# variant = (label, unit, pack, mrp, price, sku, L, W, H, gross_g, net_value, net_unit)
P = []


def add(key, title, brand, cat, hsn, gst, shelf, shelf_unit, generic, variants, photos, summary, points, specs, storage, food=True):
    P.append(dict(key=key, title=title, brand=brand, cat=cat, hsn=hsn, gst=gst, shelf=shelf, shelf_unit=shelf_unit, generic=generic,
                  variants=variants, photos=photos, desc=desc(summary, points), specs=specs, storage=storage, food=food))


add('maida2', 'Super Fine Maida (All-Purpose Flour)', 'Annapurna', 5222, '1101', 5, 6, 'months', 'Refined wheat flour',
    [('500 g', 'g', '500 g', '32', '28', 'GRC-MAIDA-500', 15, 10, 5, 540, '500', 'g'),
     ('1 kg', 'kg', '1 kg', '58', '52', 'GRC-MAIDA-1KG', 18, 12, 6, 1060, '1', 'kg')],
    [17236203, 5441094],
    'Finely milled, bleach-free all-purpose flour for soft rotis, parottas, cakes, pastries and everyday baking.',
    ['Finely milled for a smooth dough', 'Ideal for parotta, naan, bakery items and sweets', 'Hygienically packed'],
    [('Type', 'All-purpose flour'), ('Shelf life', '6 months')], 'Store in a cool, dry place in an airtight container.')
add('buns1', 'Soft Burger Buns (Pack of 4)', 'Baker\'s Basket', 5247, '1905', 5, 4, 'days', 'Burger buns',
    [('Pack of 4', 'pack', 'Pack of 4', '60', '52', 'GRC-BUNS-4', 24, 16, 8, 260, '4', 'piece')],
    [28219383, 13424742],
    'Freshly baked, pillowy-soft buns that hold up to any filling. Perfect for veg burgers, sliders and breakfast sandwiches.',
    ['Soft, golden crust', 'Baked fresh every morning', 'Pack of 4 buns'],
    [('Quantity', '4 buns'), ('Type', 'Burger buns')], 'Store in a cool, dry place. Consume within 3 days of packing.')
add('butter2', 'Unsalted Table Butter', 'Gowri Dairy', 5243, '0405', 12, 6, 'months', 'Butter',
    [('100 g', 'g', '100 g', '58', '54', 'GRC-BUTU-100', 9, 5, 4, 120, '100', 'g'),
     ('500 g', 'g', '500 g', '275', '255', 'GRC-BUTU-500', 14, 9, 6, 540, '500', 'g')],
    [8188934, 12162627],
    'Rich, creamy unsalted butter made from fresh cream. Ideal for baking, cooking and spreading.',
    ['Made from fresh pasteurised cream', 'No added salt or preservatives', 'Smooth texture for baking and cooking'],
    [('Type', 'Unsalted butter'), ('Fat content', 'Min. 80%')], 'Keep refrigerated at 4 degrees C or below.')
add('ice2', 'Choco Chip Ice Cream Tub', 'Frostline', 5282, '2105', 18, 12, 'months', 'Ice cream',
    [('500 ml', 'ml', '500 ml', '210', '189', 'GRC-ICE-CHOC-500', 12, 12, 9, 560, '500', 'ml'),
     ('1 L', 'l', '1 L', '389', '349', 'GRC-ICE-CHOC-1L', 16, 16, 11, 1080, '1', 'l')],
    [11501480, 8713081],
    'Creamy chocolate ice cream loaded with crunchy chocolate chips. Serve straight from the tub or with your favourite dessert.',
    ['Real chocolate and chocolate chips', 'Smooth and creamy texture', 'Family-size tub'],
    [('Flavour', 'Choco chip'), ('Type', 'Ice cream')], 'Store at -18 degrees C. Do not refreeze once thawed.')
add('floor2', 'Pine Disinfectant Floor Cleaner', 'ShineHome', 5309, '3402', 18, 24, 'months', 'Floor cleaner',
    [('500 ml', 'ml', '500 ml', '115', '99', 'GRC-FLR-PN-500', 7, 7, 20, 560, '500', 'ml'),
     ('1 L', 'l', '1 L', '199', '175', 'GRC-FLR-PN-1L', 9, 9, 25, 1080, '1', 'l')],
    [7513188],
    'Disinfectant floor cleaner with a fresh pine fragrance. Removes dirt and germs for a spotless, shiny floor.',
    ['Kills 99.9% germs*', 'Long-lasting pine fragrance', 'Safe on tiles, marble and vitrified floors'],
    [('Fragrance', 'Pine'), ('Use', 'Floor cleaning')], 'Store in a cool, dry place. Keep out of reach of children.', food=False)
add('dish2', 'Lime Power Dishwash Gel', 'ShineHome', 5315, '3402', 18, 24, 'months', 'Dishwashing gel',
    [('500 ml', 'ml', '500 ml', '99', '85', 'GRC-DSH-LM-500', 7, 7, 20, 560, '500', 'ml'),
     ('1 L', 'l', '1 L', '179', '155', 'GRC-DISH-LIME-1L', 9, 9, 25, 1080, '1', 'l')],
    [7492919, 5904036],
    'Concentrated lime dishwashing gel that cuts grease fast, leaving utensils squeaky clean and sparkling.',
    ['Cuts tough grease in seconds', 'Fresh lime fragrance', 'Gentle on hands'],
    [('Fragrance', 'Lime'), ('Form', 'Gel')], 'Store in a cool, dry place.', food=False)
add('det2', 'Top Load Detergent Powder', 'FreshWash', 5312, '3402', 18, 24, 'months', 'Detergent powder',
    [('1 kg', 'kg', '1 kg', '125', '109', 'GRC-DET-TOP-1KG', 18, 11, 7, 1080, '1', 'kg'),
     ('2 kg', 'kg', '2 kg', '235', '209', 'GRC-DET-TOP-2KG', 24, 14, 8, 2120, '2', 'kg')],
    [4959880, 36346846],
    'Active-clean detergent powder that removes tough stains and keeps whites bright. Suitable for top-load machines and hand wash.',
    ['Removes tough stains', 'Long-lasting freshness', 'Suitable for top-load machines and hand wash'],
    [('Type', 'Detergent powder'), ('Suitable for', 'Top-load and hand wash')], 'Store in a cool, dry place. Keep away from children.', food=False)
add('cook2', 'Oatmeal Raisin Cookies', 'Crumbly', 5252, '1905', 18, 6, 'months', 'Cookies',
    [('150 g', 'g', '150 g', '70', '62', 'GRC-COOK-OAT-150', 18, 12, 4, 180, '150', 'g')],
    [15265270, 8837035],
    'Crunchy oatmeal cookies baked with plump raisins and wholesome oats. A tasty tea-time companion.',
    ['Made with rolled oats and raisins', 'No artificial colours', 'Crisp, golden bake'],
    [('Flavour', 'Oatmeal raisin'), ('Net weight', '150 g')], 'Store in a cool, dry place. Keep the pack sealed.')
add('pasta2', 'Fusilli Durum Wheat Pasta', 'Pasta Pronto', 5259, '1902', 12, 12, 'months', 'Pasta',
    [('250 g', 'g', '250 g', '65', '59', 'GRC-PAS-FUS-250', 20, 12, 5, 280, '250', 'g'),
     ('500 g', 'g', '500 g', '119', '105', 'GRC-PAS-FUS-500', 24, 14, 6, 540, '500', 'g')],
    [6287274, 4039710],
    'Spiral-shaped durum wheat pasta that holds sauces beautifully. Cooks in 8-10 minutes.',
    ['100% durum wheat semolina', 'Holds sauce well', 'Cooks in 8-10 minutes'],
    [('Type', 'Fusilli'), ('Main ingredient', 'Durum wheat semolina')], 'Store in a cool, dry place.')
add('rte2', 'Palak Paneer Ready to Eat', 'Rasoi Express', 5261, '2106', 18, 9, 'months', 'Ready to eat meal',
    [('300 g', 'g', '300 g', '129', '115', 'GRC-RTE-PLK-300', 16, 12, 3, 330, '300', 'g')],
    [31249589, 8625948],
    'Soft paneer cubes in a creamy spinach gravy. Heat for 3 minutes and serve with roti or rice.',
    ['Ready in 3 minutes', 'No added preservatives', 'Restaurant-style taste'],
    [('Serves', '2'), ('Net weight', '300 g')], 'Store in a cool, dry place. Consume immediately once opened.')
add('jam2', 'Strawberry Fruit Jam', 'Orchard Lane', 5265, '2007', 12, 12, 'months', 'Fruit jam',
    [('200 g', 'g', '200 g', '85', '75', 'GRC-JAM-STR-200', 7, 7, 10, 420, '200', 'g'),
     ('500 g', 'g', '500 g', '185', '165', 'GRC-JAM-STR-500', 9, 9, 13, 780, '500', 'g')],
    [26727863, 12369983],
    'Sweet-tart strawberry jam made with real fruit pulp. Spread on toast, rotis or use in desserts.',
    ['Made with real strawberry fruit', 'Thick, spreadable texture', 'Free from artificial colours'],
    [('Flavour', 'Strawberry'), ('Type', 'Fruit jam')], 'Store in a cool, dry place. Refrigerate after opening.')
add('pick2', 'Lemon Pickle (Nimbu Achar)', 'Grandma\'s Kitchen', 5264, '2001', 12, 12, 'months', 'Lemon pickle',
    [('300 g', 'g', '300 g', '110', '99', 'GRC-PICK-LEM-300', 8, 8, 10, 560, '300', 'g')],
    [32026595, 36901549],
    'Tangy, spicy lemon pickle prepared the traditional way with hand-picked lemons, spices and cold-pressed oil.',
    ['Traditional home-style recipe', 'No artificial preservatives', 'Perfect with rice, curd and parathas'],
    [('Type', 'Lemon pickle'), ('Net weight', '300 g')], 'Store in a cool, dry place. Use a dry spoon.')
add('chips2', 'Masala Potato Chips', 'Crunchy Co', 5254, '2005', 12, 4, 'months', 'Potato chips',
    [('52 g', 'g', '52 g', '20', '20', 'GRC-CHIP-MAS-52', 20, 14, 5, 60, '52', 'g'),
     ('150 g', 'g', '150 g', '60', '55', 'GRC-CHIP-MAS-150', 28, 18, 8, 170, '150', 'g')],
    [34466116, 39853175],
    'Thin, crispy potato chips seasoned with a bold masala blend. The perfect crunchy snack.',
    ['Crispy, thin-cut chips', 'Bold masala flavour', 'Cooked in sunflower oil'],
    [('Flavour', 'Masala'), ('Type', 'Potato chips')], 'Store in a cool, dry place away from sunlight.')
add('pop2', 'Caramel Popcorn', 'Pop Street', 5256, '1904', 12, 6, 'months', 'Caramel popcorn',
    [('100 g', 'g', '100 g', '70', '62', 'GRC-POP-CAR-100', 22, 14, 6, 120, '100', 'g')],
    [7676079, 30910216],
    'Light, crunchy popcorn coated in golden caramel. A sweet movie-night treat.',
    ['Golden caramel coating', 'Light and crunchy', 'Ready to eat'],
    [('Flavour', 'Caramel'), ('Net weight', '100 g')], 'Store in a cool, dry place. Keep the pack sealed.')
add('water2', 'Natural Mineral Water', 'Aqua Pure', 5276, '2201', 18, 12, 'months', 'Packaged drinking water',
    [('1 L', 'l', '1 L', '20', '20', 'GRC-WATER-1L', 7, 7, 26, 1040, '1', 'l'),
     ('5 L', 'l', '5 L', '85', '79', 'GRC-WATER-5L', 17, 17, 30, 5200, '5', 'l')],
    [11860562, 31699476],
    'Natural mineral water, naturally rich in minerals and sourced from protected springs. Crisp, clean taste.',
    ['Naturally rich in minerals', 'BIS certified packaged drinking water', 'Sealed, tamper-proof cap'],
    [('Type', 'Natural mineral water'), ('Volume', '1 L / 5 L')], 'Store in a cool place away from direct sunlight.')
add('dhoop2', 'Sandal Dhoop Cones', 'Aroma', 5322, '3307', 12, 36, 'months', 'Incense cones',
    [('Pack of 20', 'pack', 'Pack of 20', '60', '52', 'GRC-DHP-SAND-20', 8, 8, 4, 90, '20', 'piece')],
    [37271694, 39332739],
    'Natural sandalwood dhoop cones for daily puja and a calming home. Burn on a cone holder for rich, lasting fragrance.',
    ['Natural sandalwood fragrance', 'Long-lasting smoke', 'Pack of 20 cones'],
    [('Fragrance', 'Sandalwood'), ('Quantity', '20 cones')], 'Store in a cool, dry place.', food=False)

only = sys.argv[1:]  # optional keys to restrict
if only:
    P = [p for p in P if p['key'] in only]

# ---------- upload photos ----------
need = sorted({i for p in P for i in p['photos']} - set(ph))
for i in need:
    src = f'px3/{i}.jpg'
    im = Image.open(src).convert('RGB'); im.thumbnail((1200, 1200)); out = f'px3/up_{i}.jpg'; im.save(out, 'JPEG', quality=90)
    r = subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Authorization: Bearer ' + tok, '-A', 'curl/8.4.0', '-F', f'image=@{out};type=image/jpeg',
                        'https://vendor.sevo.co.in/api/workforce/seller-hub/products/upload-image/'], capture_output=True, text=True)
    try:
        ph[i] = json.loads(r.stdout)['image_url']
    except Exception:
        print('UPLOAD FAIL', i, r.stdout[:200]); sys.exit(1)
json.dump(ph, open(PH, 'w'))
print('uploaded', len(need))

# ---------- create ----------
s, d = call('GET', 'products/?page_size=100&page=1')
existing = {}
for pg in (1, 2, 3, 4):
    s, d = call('GET', f'products/?page_size=100&page={pg}')
    for q in d['results']:
        existing[q['sku']] = q['id']
log = json.load(open('backup/groc_created.json')) if os.path.exists('backup/groc_created.json') else {}
failed = []
s, gl = call('GET', 'variant-groups/')
groups_by_title = {x['group_title']: x['id'] for x in (gl if isinstance(gl, list) else gl.get('results', []))}
for p in P:
    group_id = None
    if len(p['variants']) > 1:
        if p['title'] in groups_by_title:
            group_id = groups_by_title[p['title']]
        else:
            s, g = call('POST', 'variant-groups/', {'group_title': p['title'], 'variant_attribute_name': 'Size'})
            if s not in (200, 201):
                print('GROUP FAIL', p['title'], s, g); failed.append(p['key']); continue
            group_id = (g.get('group') or g)['id']
    for label, unit, pack, mrp, price, sku, L, W, H, G, nv, nu in p['variants']:
        if sku in existing:
            print('exists', sku); log[sku] = existing[sku]; continue
        body = dict(category=p['cat'], title=p['title'], brand=p['brand'], unit=unit, pack_size=pack, variant_label=label, mrp=mrp,
                    selling_price=price, hsn_code=p['hsn'], sku=sku, description=p['desc'], storage_info=p['storage'],
                    shelf_life_value=p['shelf'], shelf_life_unit=p['shelf_unit'], images=[ph[i] for i in p['photos']],
                    specs=[{'label': a, 'value': b} for a, b in p['specs']], package_length_cm=L, package_width_cm=W,
                    package_height_cm=H, gross_weight_g=G, generic_name=p['generic'],
                    procurement_price=f"{float(price) * 0.78:.2f}", net_weight_value=nv, net_weight_unit=nu, **MFG)
        if p['food']:
            body.update(FOOD)
        if group_id:
            body['variant_group'] = group_id
        s, d = call('POST', 'products/', body)
        if s != 201:
            print('CREATE FAIL', sku, s, json.dumps(d, ensure_ascii=False)[:400]); failed.append(sku); continue
        log[sku] = d['product']['id']; print('created', sku, d['product']['id'])
json.dump(log, open('backup/groc_created.json', 'w'))
print('total', len(log), 'failed', failed)
