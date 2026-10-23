import json, sys, os, subprocess
from PIL import Image
from api_seller import call, tok
import make_db_helpers as H

adm = H.adm
prods_all = []
for pg in (1,):
    s, d = call('GET', f'products/?page_size=100&page={pg}')
    prods_all += d['results']
prot = set(json.load(open('protected_ids.json')))
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


def patch(cid, **body):
    s, d = adm('PATCH', f'seller-hub/categories/{cid}/', body)
    print('patch', cid, body, s, '' if s == 200 else json.dumps(d)[:200])


HE = ensure('household-essentials', 'Household Essentials', None, 5)
HL = ensure('he-home-lifestyle', 'Home & Lifestyle', HE, 1)
CR = ensure('he-cleaners-repellents', 'Cleaners & Repellents', HE, 2)
SG = ensure('he-stationery-games', 'Stationery & Games', HE, 3)

# move existing leaves (with their products) in
for leaf, parent in [(5309, CR), (5315, CR), (5312, CR), (5322, HL)]:
    patch(leaf, parent=parent)

# delete the now-empty Home Care and Pooja & Other Essentials trees (children first); never touch products
_s, _t = call('GET', 'categories/tree/')
_by = {}


def _idx(n):
    _by[n['id']] = n
    for c in n.get('children') or []:
        _idx(c)


for n in _t:
    _idx(n)


def _post(n):
    r = []
    for c in n.get('children') or []:
        r += _post(c)
    return r + [n['id']]


_order = []
for root in (5307, 5319):
    if root in _by:
        _order += _post(_by[root])
_pc = {}
for p in prods_all:
    _pc[p['category']] = _pc.get(p['category'], 0) + 1
for cid in _order:
    assert not _pc.get(cid), ('products still inside category', cid)
    assert not any(p['id'] in prot for p in prods_all if p['category'] == cid)
    s, d = adm('DELETE', f'seller-hub/categories/{cid}/')
    print('deleted' if s in (200, 204) else f'delete failed {s}', cid)

CAT = dict(
    repel=ensure('he-insect-repellents', 'Insect Repellents', CR, 4),
    toilet=ensure('he-toilet-cleaners', 'Toilet & Bathroom Cleaners', CR, 5),
    candle=ensure('he-candles-diyas', 'Candles & Diyas', HL, 2),
    note=ensure('he-notebooks', 'Notebooks & Paper', SG, 1),
    pen=ensure('he-pens-pencils', 'Pens & Pencils', SG, 2),
    art=ensure('he-art-craft', 'Art & Craft', SG, 3),
    game=ensure('he-games-puzzles', 'Games & Puzzles', SG, 4),
)
json.dump(by_slug, open('backup/house_categories.json', 'w'))

PH = 'backup/house_photos.json'
ph = {int(k): v for k, v in json.load(open(PH)).items()} if os.path.exists(PH) else {}
MFG = dict(country_of_origin='IN', manufacturer_name='SEVO Consumer Products Pvt Ltd', manufacturer_address='SIPCOT Industrial Park, Hosur, Tamil Nadu', manufacturer_pincode='635109')
P = []


def desc(a, pts): return '<p>' + a + '</p><ul>' + ''.join(f'<li>{p}</li>' for p in pts) + '</ul>'


def add(title, brand, c, hsn, gst, shelf, su, generic, variants, photos, summary, points, specs, storage):
    P.append(dict(title=title, brand=brand, cat=CAT[c], hsn=hsn, gst=gst, shelf=shelf, su=su, generic=generic, variants=variants, photos=photos,
                  desc=desc(summary, points), specs=specs, storage=storage))


# variant = (label, unit, pack, mrp, price, sku, L, W, H, gross_g, net_value, net_unit)
add('Mosquito Repellent Coils', 'ShineHome', 'repel', '3808', 18, 36, 'months', 'Mosquito coil',
    [('Pack of 10', 'pack', 'Pack of 10', '55', '49', 'HE-COIL-10', 14, 14, 6, 260, '10', 'piece'), ('Pack of 20', 'pack', 'Pack of 20', '98', '89', 'HE-COIL-20', 14, 14, 12, 500, '20', 'piece')],
    [35523934], 'Slow-burning coils that keep mosquitoes away for up to 8 hours.', ['Protects up to 8 hours', 'Slow, even burn', 'Use with coil stand in ventilated rooms'],
    [('Type', 'Mosquito coil'), ('Burn time', 'Up to 8 hours')], 'Store in a cool, dry place away from children. Use in a ventilated room.')
add('Toilet Bowl Cleaner', 'ShineHome', 'toilet', '3808', 18, 24, 'months', 'Toilet cleaner',
    [('500 ml', 'ml', '500 ml', '99', '85', 'HE-TOILET-500', 7, 7, 22, 560, '500', 'ml'), ('1 L', 'l', '1 L', '175', '155', 'HE-TOILET-1L', 9, 9, 27, 1080, '1', 'l')],
    [5217885], 'Thick, power-clinging toilet cleaner that removes stains and kills 99.9% germs*.',
    ['Removes tough stains and limescale', 'Angled neck for under-rim cleaning', 'Fresh fragrance'], [('Type', 'Toilet cleaner'), ('Form', 'Liquid')],
    'Store in a cool, dry place. Keep out of reach of children. Do not mix with other cleaners.')
add('Tealight Candles (Pack of 50)', 'Glow Home', 'candle', '3406', 12, 60, 'months', 'Tealight candles',
    [('Pack of 50', 'pack', 'Pack of 50', '199', '179', 'HE-TEALITE-50', 20, 14, 8, 480, '50', 'piece')], [33447903],
    'Smokeless unscented tealights for diyas, aroma burners and festive decor. Each burns for about 4 hours.',
    ['About 4 hours burn time each', 'Smokeless and unscented', 'Pack of 50'], [('Quantity', '50 candles'), ('Burn time', '4 hours')], 'Store in a cool, dry place away from heat.')
add('Scented Jar Candle', 'Glow Home', 'candle', '3406', 12, 36, 'months', 'Scented candle',
    [('100 g', 'g', '100 g', '299', '269', 'HE-JARCAN-100', 8, 8, 8, 260, '100', 'g')], [6311829],
    'Hand-poured soy-blend candle in a reusable glass jar with a soothing fragrance.', ['Soy wax blend', 'Cotton wick', 'Reusable glass jar'],
    [('Burn time', 'About 25 hours'), ('Wax', 'Soy blend')], 'Trim the wick to 5 mm before lighting. Keep away from children.')
add('Terracotta Diyas (Pack of 12)', 'Aroma', 'candle', '6913', 12, 60, 'months', 'Clay diyas',
    [('Pack of 12', 'pack', 'Pack of 12', '120', '99', 'HE-DIYA-12', 18, 14, 6, 700, '12', 'piece')], [18979384],
    'Hand-finished terracotta diyas for daily puja, Diwali and festive decor.', ['Natural clay', 'Pack of 12', 'Fill with oil or ghee and a cotton wick'],
    [('Material', 'Terracotta'), ('Quantity', '12 diyas')], 'Handle with care. Soak in water before first use for longer-lasting diyas.')
add('Spiral Notebooks (Pack of 4)', 'Scholar', 'note', '4820', 12, 60, 'months', 'Notebook',
    [('Pack of 4', 'pack', 'Pack of 4', '280', '249', 'HE-NOTE-SP-4', 30, 22, 4, 1200, '4', 'piece')], [273034, 7054755],
    'Spiral-bound A4 ruled notebooks with 160 pages each and sturdy covers.', ['A4, 160 ruled pages', 'Smooth 70 GSM paper', 'Pack of 4 assorted covers'],
    [('Size', 'A4'), ('Pages', '160 each')], 'Store in a dry place.')
add('Sticky Notes Pad Set', 'Scholar', 'note', '4820', 18, 60, 'months', 'Sticky notes',
    [('Pack of 4 pads', 'pack', 'Pack of 4 pads', '120', '99', 'HE-STICKY-4', 8, 8, 4, 250, '4', 'piece')], [4586900, 6991385],
    'Bright repositionable sticky notes for reminders, planning and study. 100 sheets per pad.', ['Strong repositionable adhesive', 'Assorted bright colours', '100 sheets per pad'],
    [('Pads', '4'), ('Sheets', '100 each')], 'Store in a cool, dry place.')
add('Ball Pens (Pack of 10)', 'Scholar', 'pen', '9608', 18, 60, 'months', 'Ball pen',
    [('Blue, pack of 10', 'pack', 'Pack of 10', '100', '85', 'HE-PEN-BLUE-10', 15, 10, 2, 90, '10', 'piece')], [6969328, 6187592],
    'Smooth-writing ball pens with quick-dry ink and comfortable grip.', ['Smooth, smudge-free ink', 'Comfort grip', 'Pack of 10 blue pens'], [('Ink colour', 'Blue'), ('Tip', '0.7 mm')], 'Store with the cap closed.')
add('HB Pencils (Pack of 10)', 'Scholar', 'pen', '9609', 12, 60, 'months', 'Pencils',
    [('Pack of 10', 'pack', 'Pack of 10', '60', '52', 'HE-PENCIL-HB-10', 18, 8, 2, 100, '10', 'piece')], [39799168, 8478404],
    'Pre-sharpened HB pencils with dark, smooth lead and break-resistant cores.', ['Dark, smooth writing', 'Break-resistant lead', 'Pack of 10'], [('Grade', 'HB'), ('Quantity', '10')], 'Store in a dry place.')
add('Wax Crayons (24 Shades)', 'Little Artist', 'art', '9609', 12, 60, 'months', 'Wax crayons',
    [('24 shades', 'pack', '24 shades', '120', '105', 'HE-CRAYON-24', 14, 10, 4, 200, '24', 'piece')], [284082],
    'Bright, non-toxic wax crayons that colour smoothly on paper.', ['24 vibrant shades', 'Non-toxic', 'Smooth, even colouring'], [('Shades', '24'), ('Age', '3 years and above')], 'Keep away from heat.')
add('Watercolour Paint Set', 'Little Artist', 'art', '3213', 18, 60, 'months', 'Watercolour paint',
    [('12 colours', 'pack', '12 colours + brush', '199', '175', 'HE-WCOLOR-12', 22, 10, 3, 280, '12', 'piece')], [5435078, 34334768],
    'Pan watercolours with a brush - vivid colours that blend beautifully.', ['12 rich colours', 'Includes brush', 'Non-toxic'], [('Colours', '12'), ('Includes', 'Brush')], 'Keep away from heat and moisture.')
add('Wooden Chess Set', 'Play Zone', 'game', '9504', 12, 60, 'months', 'Chess set',
    [('Standard', 'piece', 'Standard board', '599', '529', 'HE-CHESS-STD', 38, 38, 5, 900, '1', 'piece')], [34657183, 17768376],
    'Folding board with weighted chess pieces - perfect for learners and club players.', ['Folding board with storage', 'Weighted pieces', 'Includes extra queens'],
    [('Board size', '12 inch'), ('Pieces', '32')], 'Store in a dry place.')
add('Jigsaw Puzzle (500 Pieces)', 'Play Zone', 'game', '9503', 12, 60, 'months', 'Jigsaw puzzle',
    [('500 pieces', 'piece', '500 pieces', '349', '299', 'HE-JIGSAW-500', 36, 26, 5, 650, '1', 'piece')], [9227507, 27837160],
    'Colourful 500-piece jigsaw puzzle printed on thick board with a perfect fit.', ['500 pieces', 'Thick, glare-free board', 'Great family activity'],
    [('Pieces', '500'), ('Age', '8 years and above')], 'Store flat in a dry place.')
json.dump({p['title']: p['gst'] for p in P}, open('backup/house_gst.json', 'w'))

need = sorted({i for p in P for i in p['photos']} - set(ph))
for i in need:
    im = Image.open(f'px6/{i}.jpg').convert('RGB'); im.thumbnail((1200, 1200)); out = f'px6/up_{i}.jpg'; im.save(out, 'JPEG', quality=90)
    r = subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Authorization: Bearer ' + tok, '-A', 'curl/8.4.0', '-F', f'image=@{out};type=image/jpeg',
                        'https://vendor.sevo.co.in/api/workforce/seller-hub/products/upload-image/'], capture_output=True, text=True)
    try: ph[i] = json.loads(r.stdout)['image_url']
    except Exception: print('UPLOAD FAIL', i, r.stdout[:200]); sys.exit(1)
json.dump(ph, open(PH, 'w')); print('uploaded', len(need))

existing = {q['sku']: q['id'] for q in prods_all}
s, gl = call('GET', 'variant-groups/')
groups = {x['group_title']: x['id'] for x in (gl if isinstance(gl, list) else gl.get('results', []))}
log = json.load(open('backup/house_created.json')) if os.path.exists('backup/house_created.json') else {}
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
json.dump(log, open('backup/house_created.json', 'w')); print('total', len(log))
