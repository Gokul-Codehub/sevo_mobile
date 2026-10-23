import json, sys, os, subprocess
from PIL import Image
from api_seller import call, tok
import make_db_helpers as H

adm = H.adm
prods_all = []
for pg in (1,):
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
    return H.ensure_cat(by_slug, slug, name, parent, sort, food=False)


HL = by_slug['he-home-lifestyle']
s, d = adm('PATCH', 'seller-hub/categories/5322/', {'name': 'Pooja Needs'})
print('rename 5322 -> Pooja Needs', s)
CAT = dict(
    pooja=5322,
    bath=ensure('he-bathroom-essentials', 'Bathroom Essentials', HL, 3),
    fresh=ensure('he-fresheners', 'Fresheners', HL, 4),
    plant=ensure('he-plants-bouquets', 'Plants & Bouquets', HL, 5),
    decor=ensure('he-home-decor', 'Home Decor', HL, 6),
    store=ensure('he-storage-organisers', 'Storage & Organisers', HL, 7),
    light=ensure('he-lighting', 'Lighting & Electricals', HL, 8),
)
json.dump(by_slug, open('backup/house2_categories.json', 'w'))

PH = 'backup/house2_photos.json'
ph = {int(k): v for k, v in json.load(open(PH)).items()} if os.path.exists(PH) else {}
MFG = dict(country_of_origin='IN', manufacturer_name='SEVO Consumer Products Pvt Ltd', manufacturer_address='SIPCOT Industrial Park, Hosur, Tamil Nadu', manufacturer_pincode='635109')
P = []


def desc(a, pts): return '<p>' + a + '</p><ul>' + ''.join(f'<li>{p}</li>' for p in pts) + '</ul>'


def add(title, brand, c, hsn, gst, shelf, su, generic, variants, photos, summary, points, specs, storage):
    P.append(dict(title=title, brand=brand, cat=CAT[c], hsn=hsn, gst=gst, shelf=shelf, su=su, generic=generic, variants=variants, photos=photos,
                  desc=desc(summary, points), specs=specs, storage=storage))


# variant = (label, unit, pack, mrp, price, sku, L, W, H, gross_g, net_value, net_unit)
add('Brass Pooja Thali Set', 'Aroma', 'pooja', '7419', 12, 120, 'months', 'Pooja thali set',
    [('7 pieces', 'pack', '7-piece set', '699', '599', 'HL-THALI-7', 30, 30, 8, 900, '7', 'piece')], [14855916],
    'Traditional brass pooja thali set for daily worship and festivals.', ['Brass, hand polished', '7-piece set', 'Ideal for festivals and gifting'],
    [('Material', 'Brass'), ('Pieces', '7')], 'Clean with tamarind or lemon and dry well.')
add('Cotton Bath Towel', 'Soft Home', 'bath', '6302', 5, 120, 'months', 'Bath towel',
    [('Standard 70 x 140 cm', 'piece', '1 towel (70 x 140 cm)', '499', '429', 'HL-TOWEL-BATH', 30, 25, 6, 520, '1', 'piece'),
     ('Large 90 x 180 cm', 'piece', '1 towel (90 x 180 cm)', '799', '699', 'HL-TOWEL-LRG', 34, 28, 8, 780, '1', 'piece')],
    [3872899], '100% combed cotton bath towel that is soft, thirsty and quick-drying.', ['100% cotton, 450 GSM', 'Highly absorbent', 'Machine washable'],
    [('Material', 'Cotton'), ('GSM', '450')], 'Wash separately before first use.')
add('Striped Hand Towels (Pack of 2)', 'Soft Home', 'bath', '6302', 5, 120, 'months', 'Hand towel',
    [('Pack of 2', 'pack', 'Pack of 2', '349', '299', 'HL-HANDTWL-2', 28, 20, 5, 300, '2', 'piece')], [4194705],
    'Soft striped cotton hand towels with a looped hanger.', ['Cotton terry', 'Looped hanger', 'Pack of 2'], [('Size', '40 x 60 cm')], 'Machine wash cold.')
add('Anti-Slip Bath Mat', 'Soft Home', 'bath', '5705', 12, 120, 'months', 'Bath mat',
    [('40 x 60 cm', 'piece', '1 mat', '399', '349', 'HL-BATHMAT-40', 40, 28, 3, 500, '1', 'piece')], [12273900],
    'Plush microfibre bath mat with an anti-slip rubber back.', ['Super soft microfibre', 'Anti-slip back', 'Quick drying'], [('Size', '40 x 60 cm')], 'Machine washable.')
add('Toilet Paper Rolls (Pack of 4)', 'Soft Home', 'bath', '4818', 12, 36, 'months', 'Toilet paper',
    [('Pack of 4', 'pack', 'Pack of 4', '120', '105', 'HL-TISSUE-4', 24, 12, 11, 480, '4', 'piece')], [3958179],
    'Soft, 2-ply toilet paper rolls with 200 pulls each.', ['2-ply soft tissue', '200 pulls per roll', 'Septic-safe'], [('Rolls', '4'), ('Ply', '2')], 'Store in a dry place.')
add('Lavender Reed Diffuser', 'Glow Home', 'fresh', '3307', 18, 24, 'months', 'Reed diffuser',
    [('50 ml', 'ml', '50 ml', '349', '299', 'HL-REED-LAV-50', 7, 7, 14, 180, '50', 'ml'),
     ('100 ml', 'ml', '100 ml', '599', '529', 'HL-REED-LAV-100', 8, 8, 18, 300, '100', 'ml')],
    [7795656, 18987029], 'Calming lavender fragrance diffused through natural rattan reeds - no flame, no electricity.',
    ['Lasts up to 8 weeks', 'Includes rattan reeds', 'Flame-free fragrance'], [('Fragrance', 'Lavender'), ('Includes', 'Reeds')], 'Keep upright and away from children and pets.')
add('Scented Potpourri', 'Glow Home', 'fresh', '3307', 12, 24, 'months', 'Potpourri',
    [('100 g', 'g', '100 g', '199', '179', 'HL-POTPOUR-100', 14, 14, 8, 130, '100', 'g')], [14367086, 710288],
    'A mix of dried flowers, leaves and spices that freshens wardrobes, rooms and bowls.', ['Natural dried flowers', 'Long-lasting aroma', 'Refresh with a few drops of oil'],
    [('Type', 'Potpourri')], 'Store in a cool, dry place.')
add('Chinese Money Plant in Pot', 'Green Nest', 'plant', '0602', 0, 30, 'days', 'Live plant',
    [('Small', 'piece', 'Small pot', '299', '249', 'HL-MONEYPL-S', 12, 12, 20, 600, '1', 'piece')], [7210780, 11421313],
    'Pilea peperomioides - the lucky coin plant, shipped in a ceramic pot.', ['Easy indoor plant', 'Bright indirect light', 'Comes in a pot'],
    [('Light', 'Bright indirect'), ('Watering', 'Weekly')], 'Keep in bright indirect light. Water when top soil is dry.')
add('Snake Plant in Ceramic Pot', 'Green Nest', 'plant', '0602', 0, 30, 'days', 'Live plant',
    [('Medium', 'piece', 'Medium pot', '449', '399', 'HL-SNAKEPL-M', 16, 16, 45, 1500, '1', 'piece')], [29218657, 10467813],
    'Hardy air-purifying snake plant (Sansevieria) in a decorative ceramic pot.', ['Thrives in low light', 'Purifies indoor air', 'Needs little water'],
    [('Light', 'Low to bright'), ('Watering', 'Fortnightly')], 'Water sparingly - let soil dry between waterings.')
add('Mini Succulent Set (Pack of 3)', 'Green Nest', 'plant', '0602', 0, 30, 'days', 'Live plants',
    [('Pack of 3', 'pack', 'Pack of 3', '399', '349', 'HL-SUCC-3', 20, 8, 10, 600, '3', 'piece')], [773804, 36620948],
    'Three assorted succulents in small pots - perfect for desks and windowsills.', ['Assorted succulents', 'Low maintenance', 'Pots included'],
    [('Quantity', '3 plants')], 'Keep in bright light. Water once a week.')
add('Tulsi Plant with Pot', 'Green Nest', 'plant', '0602', 0, 30, 'days', 'Live plant',
    [('Medium', 'piece', 'Medium pot', '149', '129', 'HL-TULSI-M', 14, 14, 30, 900, '1', 'piece')], [38541130],
    'Holy basil (Rama Tulsi) plant with a terracotta pot, for puja and home use.', ['Sacred Rama Tulsi', 'Terracotta pot', 'Needs sunlight'], [('Type', 'Rama Tulsi')], 'Place in sunlight and water daily.')
add('Fresh Mixed Flower Bouquet', 'Petal Lane', 'plant', '0603', 0, 3, 'days', 'Fresh flowers',
    [('Medium', 'piece', 'Medium bouquet', '599', '549', 'HL-BOUQUET-M', 35, 25, 25, 500, '1', 'piece'),
     ('Large', 'piece', 'Large bouquet', '999', '899', 'HL-BOUQUET-L', 45, 35, 30, 900, '1', 'piece')],
    [37222812, 36739287], 'Hand-tied bouquet of seasonal roses, sunflowers and fillers in bright colours.', ['Seasonal fresh flowers', 'Hand-tied', 'Perfect for gifting'],
    [('Flowers', 'Seasonal mix')], 'Trim stems, use fresh water daily.')
add('Tulip Bouquet', 'Petal Lane', 'plant', '0603', 0, 3, 'days', 'Fresh flowers',
    [('10 stems', 'pack', '10 stems', '799', '699', 'HL-TULIP-10', 40, 20, 20, 400, '10', 'piece')], [36945270, 32027599],
    'Fresh tulips wrapped in kraft paper, in assorted colours.', ['10 fresh stems', 'Assorted colours', 'Paper wrapped'], [('Stems', '10')], 'Keep cool, trim stems, change water daily.')
add('Wooden Wall Clock', 'Decor House', 'decor', '9105', 18, 120, 'months', 'Wall clock',
    [('12 inch', 'piece', '12 inch', '799', '699', 'HL-CLOCK-12', 32, 32, 5, 700, '1', 'piece')], [20050353, 15797564],
    'Silent-sweep wall clock with a wooden frame and bold numerals.', ['Silent sweep movement', 'Wooden frame', 'Runs on 1 AA battery (not included)'], [('Size', '12 inch')], 'Wipe with a dry cloth.')
add('Ceramic Flower Vase', 'Decor House', 'decor', '6913', 12, 120, 'months', 'Vase',
    [('Set of 2', 'pack', 'Set of 2', '599', '529', 'HL-VASE-2', 20, 14, 18, 900, '2', 'piece')], [7119222, 33126633],
    'Textured ceramic vases that suit dried flowers and minimal home decor.', ['Handcrafted ceramic', 'Set of 2', 'Modern textured finish'], [('Material', 'Ceramic')], 'Hand wash only.')
add('Gallery Photo Frame Set', 'Decor House', 'decor', '3926', 18, 120, 'months', 'Photo frames',
    [('Set of 7', 'pack', 'Set of 7', '999', '849', 'HL-FRAME-7', 40, 30, 5, 1200, '7', 'piece')], [7305375],
    'Seven black frames in assorted sizes for a statement gallery wall.', ['Assorted sizes', 'Includes hanging hooks', 'Easy to arrange'], [('Frames', '7')], 'Wipe with a dry cloth.')
add('Classic Table Lamp', 'Decor House', 'decor', '9405', 18, 120, 'months', 'Table lamp',
    [('Standard', 'piece', '1 lamp', '1299', '1099', 'HL-LAMP-STD', 28, 28, 45, 1400, '1', 'piece')], [18280834, 35392792],
    'Warm, classic table lamp with a fabric shade for bedrooms and living rooms.', ['Fabric shade', 'E27 holder (bulb not included)', 'Inline switch'], [('Height', '45 cm')], 'Use bulbs up to 15W.')
add('Glass Storage Jars Set', 'Home Cart', 'store', '7013', 18, 120, 'months', 'Storage jars',
    [('Set of 3', 'pack', 'Set of 3', '599', '529', 'HL-JARS-3', 24, 12, 18, 1200, '3', 'piece'),
     ('Set of 6', 'pack', 'Set of 6', '1099', '949', 'HL-JARS-6', 30, 22, 18, 2400, '6', 'piece')],
    [10568352, 4856504], 'Airtight glass jars for grains, pulses, snacks and spices.', ['Airtight lids', 'Clear glass', 'Dishwasher safe'], [('Material', 'Glass')], 'Hand wash lids.')
add('Wicker Storage Basket', 'Home Cart', 'store', '4602', 12, 120, 'months', 'Storage basket',
    [('Medium', 'piece', 'Medium', '499', '429', 'HL-BASKET-M', 30, 30, 25, 600, '1', 'piece')], [21550127, 9695849],
    'Handwoven storage basket with a cloth liner for laundry, toys or decor.', ['Handwoven', 'Cloth liner', 'Sturdy handles'], [('Material', 'Wicker')], 'Wipe with a dry cloth.')
add('LED Bulb 9W (Pack of 2)', 'BrightEdge', 'light', '8539', 12, 36, 'months', 'LED bulb',
    [('Cool white', 'pack', 'Pack of 2', '199', '169', 'HL-LED-9W-2', 12, 7, 7, 120, '2', 'piece'),
     ('Warm white', 'pack', 'Pack of 2 (warm)', '199', '169', 'HL-LED-9W-W2', 12, 7, 7, 120, '2', 'piece')],
    [3946250, 5853954], 'Energy-efficient 9W LED bulbs with a B22 base - 2-year warranty.', ['9W, 810 lumens', 'B22 base', 'Saves up to 80% energy'], [('Wattage', '9W'), ('Base', 'B22')], 'Switch off before fitting.')

need = sorted({i for p in P for i in p['photos']} - set(ph))
for i in need:
    im = Image.open(f'px7/{i}.jpg').convert('RGB'); im.thumbnail((1200, 1200)); out = f'px7/up_{i}.jpg'; im.save(out, 'JPEG', quality=90)
    r = subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Authorization: Bearer ' + tok, '-A', 'curl/8.4.0', '-F', f'image=@{out};type=image/jpeg',
                        'https://vendor.sevo.co.in/api/workforce/seller-hub/products/upload-image/'], capture_output=True, text=True)
    try: ph[i] = json.loads(r.stdout)['image_url']
    except Exception: print('UPLOAD FAIL', i, r.stdout[:200]); sys.exit(1)
json.dump(ph, open(PH, 'w')); print('uploaded', len(need))

existing = {q['sku']: q['id'] for q in prods_all}
s, gl = call('GET', 'variant-groups/')
groups = {x['group_title']: x['id'] for x in (gl if isinstance(gl, list) else gl.get('results', []))}
log = json.load(open('backup/house2_created.json')) if os.path.exists('backup/house2_created.json') else {}
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
json.dump(log, open('backup/house2_created.json', 'w')); print('total', len(log))
json.dump({sku: next(p['gst'] for p in P if any(v[5] == sku for v in p['variants'])) for sku in log}, open('backup/house2_gst.json', 'w'))
