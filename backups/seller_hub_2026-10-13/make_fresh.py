import json, sys, os, subprocess
from PIL import Image
from api_seller import call, tok

LEAF = dict(leafy=5206, root=5207, veg=5208, exo=5209, fruit=5211, season=5212, exofruit=5213, dry=5214)
PH = 'backup/fresh_photos.json'
ph = {int(k): v for k, v in json.load(open(PH)).items()} if os.path.exists(PH) else {}
MFG = dict(country_of_origin='IN', manufacturer_name='SEVO Fresh Farms', manufacturer_address='Krishnagiri Farm Cluster, Tamil Nadu', manufacturer_pincode='635001')
P = []


def desc(a, pts): return '<p>' + a + '</p><ul>' + ''.join(f'<li>{p}</li>' for p in pts) + '</ul>'


# V = (label, unit, pack, mrp, price, sku, net_value, net_unit, gross_g)
def add(title, leaf, sold, variety, grade, piece_g, hsn, gst, shelf, V, photos, summary, points):
    P.append(dict(title=title, cat=LEAF[leaf], sold=sold, variety=variety, grade=grade, piece=piece_g, hsn=hsn, gst=gst, shelf=shelf,
                  variants=V, photos=photos, desc=desc(summary, points)))


add('Fresh Mint Leaves (Pudina)', 'leafy', 'BUNCH', 'Country', 'Grade A', None, '07', 0, 3,
    [('1 bunch', 'piece', '1 bunch', '15', '12', 'FP-MINT-1', '1', 'piece', 120), ('2 bunches', 'piece', '2 bunches', '28', '22', 'FP-MINT-2', '2', 'piece', 230)],
    [9893128], 'Aromatic farm-fresh mint leaves for chutneys, raita, biryani and teas.', ['Freshly harvested', 'Strong natural aroma', 'Washed and trimmed'])
add('Fresh Curry Leaves (Karuveppilai)', 'leafy', 'PACK', 'Country', 'Grade A', None, '07', 0, 4,
    [('50 g', 'g', '50 g', '12', '10', 'FP-CURRYLF-50', '50', 'g', 70)], [37215213],
    'Fragrant curry leaves essential for tadka, sambar, chutneys and rasam.', ['Freshly plucked', 'Intense aroma', '50 g pack'])
add('Red Onion (Sambar Vengayam)', 'root', 'WEIGHT', 'Nashik Red', 'Grade A', 120, '07', 0, 20,
    [('1 kg', 'kg', '1kg', '48', '42', 'FP-ONION-1KG', '1', 'kg', 1050), ('2 kg', 'kg', '2kg', '92', '80', 'FP-ONION-2KG', '2', 'kg', 2080)],
    [38121427, 7129153], 'Firm, pungent red onions that are a base for every Indian kitchen.', ['Hand-sorted, firm bulbs', 'Strong flavour', 'Long shelf life'])
add('Fresh Potato (Aloo)', 'root', 'WEIGHT', 'Table Potato', 'Grade A', 150, '07', 0, 15,
    [('1 kg', 'kg', '1kg', '42', '38', 'FP-POTATO-1KG', '1', 'kg', 1050), ('2 kg', 'kg', '2kg', '80', '72', 'FP-POTATO-2KG', '2', 'kg', 2080)],
    [17617617, 37540986], 'All-purpose potatoes for curries, fries, parathas and tikkis.', ['Clean, firm potatoes', 'Great for frying and boiling', 'Farm sourced'])
add('Fresh Beetroot', 'root', 'WEIGHT', 'Red', 'Grade A', 140, '07', 0, 10,
    [('500 g', 'g', '500g', '32', '28', 'FP-BEET-500', '500', 'g', 550), ('1 kg', 'kg', '1kg', '58', '52', 'FP-BEET-1KG', '1', 'kg', 1050)],
    [20517382], 'Sweet, earthy beetroots rich in iron - for salads, juices and poriyal.', ['Deep red colour', 'Rich in iron and fibre', 'Cleaned and trimmed'])
add('Fresh Garlic (Poondu)', 'root', 'WEIGHT', 'Ooty', 'Grade A', None, '07', 0, 30,
    [('250 g', 'g', '250g', '65', '55', 'FP-GARLIC-250', '250', 'g', 300), ('500 g', 'g', '500g', '120', '105', 'FP-GARLIC-500', '500', 'g', 550)],
    [8618975, 10111494], 'Pungent, plump garlic bulbs with big cloves.', ['Large cloves', 'Strong aroma', 'Freshly harvested'])
add('Fresh Cucumber (Vellarikai)', 'veg', 'WEIGHT', 'Green', 'Grade A', 200, '07', 0, 5,
    [('500 g', 'g', '500g', '30', '26', 'FP-CUCUM-500', '500', 'g', 550), ('1 kg', 'kg', '1kg', '55', '48', 'FP-CUCUM-1KG', '1', 'kg', 1050)],
    [17975573, 39154015], 'Crisp, juicy cucumbers for salads, raita and snacking.', ['Crisp and cooling', 'Tender skin', 'Farm fresh'])
add('Purple Brinjal (Kathirikai)', 'veg', 'WEIGHT', 'Purple Round', 'Grade A', 100, '07', 0, 5,
    [('500 g', 'g', '500g', '34', '30', 'FP-BRINJ-500', '500', 'g', 550), ('1 kg', 'kg', '1kg', '62', '56', 'FP-BRINJ-1KG', '1', 'kg', 1050)],
    [38383099], 'Glossy purple brinjals for kuzhambu, bharta and fry.', ['Glossy, tender brinjal', 'Few seeds', 'Farm fresh'])
add('Fresh Okra (Ladies Finger)', 'veg', 'WEIGHT', 'Green', 'Grade A', 15, '07', 0, 4,
    [('250 g', 'g', '250g', '26', '22', 'FP-OKRA-250', '250', 'g', 300), ('500 g', 'g', '500g', '48', '42', 'FP-OKRA-500', '500', 'g', 550)],
    [39284004, 38272573], 'Tender, bright green okra pods for fry, sambar and masala.', ['Tender pods', 'Hand-picked', 'Great for fry and curries'])
add('Fresh Green Chilli', 'veg', 'WEIGHT', 'Green', 'Grade A', 8, '07', 0, 5,
    [('100 g', 'g', '100g', '14', '12', 'FP-CHILLI-100', '100', 'g', 130), ('250 g', 'g', '250g', '32', '28', 'FP-CHILLI-250', '250', 'g', 300)],
    [10899475], 'Spicy green chillies to add heat and freshness to your cooking.', ['Medium-hot', 'Freshly harvested', 'Hand-sorted'])
add('Fresh Lemon (Elumichai)', 'veg', 'PIECE', 'Kagzi', 'Grade A', 55, '08', 0, 10,
    [('4 pieces', 'piece', '4 pieces', '24', '20', 'FP-LEMON-4', '4', 'piece', 260), ('10 pieces', 'piece', '10 pieces', '52', '45', 'FP-LEMON-10', '10', 'piece', 600)],
    [6405144, 28698837], 'Juicy, thin-skinned lemons for juice, pickles and seasoning.', ['Juicy and tangy', 'Thin skin', 'Hand-picked'])
add('Fresh Cauliflower (Gobi)', 'veg', 'PIECE', 'White', 'Grade A', 500, '07', 0, 5,
    [('1 piece', 'piece', '1 piece (~500 g)', '42', '38', 'FP-CAULI-1', '1', 'piece', 600)], [32640196, 7572005],
    'Compact white cauliflower heads for gobi masala, paratha and fry.', ['Firm, compact curds', 'Freshly cut', 'About 500 g'])
add('Fresh Green Cabbage', 'veg', 'PIECE', 'Green', 'Grade A', 700, '07', 0, 7,
    [('1 piece', 'piece', '1 piece (~700 g)', '36', '32', 'FP-CABBAGE-1', '1', 'piece', 800)], [6316537],
    'Tight, crisp green cabbage for poriyal, salads and stir-fries.', ['Crisp and fresh', 'Firm heads', 'About 700 g'])
add('Fresh Zucchini', 'exo', 'WEIGHT', 'Green', 'Grade A', 200, '07', 0, 5,
    [('250 g', 'g', '250g', '49', '45', 'FP-ZUCCH-250', '250', 'g', 300), ('500 g', 'g', '500g', '92', '85', 'FP-ZUCCH-500', '500', 'g', 550)],
    [20180750, 12955936], 'Tender green zucchini for grills, pastas, stir-fries and salads.', ['Tender skin', 'Mild flavour', 'Hand-picked'])
add('Fresh Red Bell Pepper', 'exo', 'WEIGHT', 'Red', 'Grade A', 180, '07', 0, 7,
    [('250 g', 'g', '250g', '60', '55', 'FP-REDPEP-250', '250', 'g', 300), ('500 g', 'g', '500g', '115', '105', 'FP-REDPEP-500', '500', 'g', 550)],
    [18640811, 8950169], 'Sweet, crunchy red capsicum for salads, pizzas and stir-fries.', ['Sweet and crunchy', 'Rich in vitamin C', 'Vibrant colour'])
add('Cherry Tomatoes', 'exo', 'PACK', 'Red Cherry', 'Grade A', 15, '07', 0, 5,
    [('250 g', 'g', '250g', '55', '49', 'FP-CHERRYT-250', '250', 'g', 300), ('500 g', 'g', '500g', '102', '92', 'FP-CHERRYT-500', '500', 'g', 550)],
    [33499935], 'Sweet, bite-sized cherry tomatoes for salads and snacking.', ['Sweet and juicy', 'Perfect for salads', 'Hand-picked'])
add('Fresh Pomegranate (Madhulai)', 'fruit', 'WEIGHT', 'Bhagwa', 'Premium', 250, '08', 0, 7,
    [('500 g', 'g', '500g', '95', '85', 'FP-POMEG-500', '500', 'g', 550), ('1 kg', 'kg', '1kg', '180', '160', 'FP-POMEG-1KG', '1', 'kg', 1050)],
    [15835588, 18523341], 'Ruby-red pomegranates packed with sweet, juicy arils.', ['Deep red arils', 'Naturally sweet', 'Rich in antioxidants'])
add('Fresh Papaya', 'fruit', 'PIECE', 'Red Lady', 'Grade A', 900, '08', 0, 4,
    [('1 piece', 'piece', '1 piece (~900 g)', '65', '55', 'FP-PAPAYA-1', '1', 'piece', 1000)], [28613331],
    'Sweet, ripe papaya with soft orange flesh - great for breakfast and smoothies.', ['Ripe and sweet', 'Rich in vitamin A and C', 'About 900 g'])
add('Fresh Watermelon', 'fruit', 'PIECE', 'Kiran', 'Grade A', 3000, '08', 0, 5,
    [('1 piece', 'piece', '1 piece (~3 kg)', '110', '90', 'FP-WMELON-1', '1', 'piece', 3100)], [38786089, 3429784],
    'Cool, juicy watermelon with crisp red flesh.', ['Juicy and refreshing', 'Sweet red flesh', 'About 3 kg'])
add('Green Grapes (Seedless)', 'fruit', 'WEIGHT', 'Thompson Seedless', 'Premium', None, '08', 0, 5,
    [('500 g', 'g', '500g', '85', '75', 'FP-GRAPES-500', '500', 'g', 550), ('1 kg', 'kg', '1kg', '160', '140', 'FP-GRAPES-1KG', '1', 'kg', 1050)],
    [15834159, 39081548], 'Crisp, sweet seedless green grapes.', ['Seedless and sweet', 'Crisp bite', 'Washed and packed'])
add('Fresh Pineapple (Annasi)', 'season', 'PIECE', 'Queen', 'Grade A', 1200, '08', 0, 5,
    [('1 piece', 'piece', '1 piece (~1.2 kg)', '85', '70', 'FP-PINEAPL-1', '1', 'piece', 1400)], [7194817, 12471181],
    'Golden, sweet-tangy pineapples with juicy flesh.', ['Sweet and tangy', 'Juicy flesh', 'About 1.2 kg'])
add('Fresh Dragon Fruit', 'exofruit', 'PIECE', 'Red Flesh', 'Premium', 350, '08', 0, 5,
    [('2 pieces', 'piece', '2 pieces', '180', '150', 'FP-DRAGON-2', '2', 'piece', 750)], [11450660, 8813523],
    'Vibrant pink dragon fruit with mildly sweet, refreshing flesh.', ['Rich in fibre', 'Mildly sweet', 'Eye-catching colour'])
add('Fresh Strawberries', 'exofruit', 'PACK', 'Mahabaleshwar', 'Premium', 15, '08', 0, 3,
    [('200 g', 'g', '200g', '99', '89', 'FP-STRAWB-200', '200', 'g', 260), ('400 g', 'g', '400g', '185', '165', 'FP-STRAWB-400', '400', 'g', 480)],
    [38845215, 277262], 'Sweet, juicy strawberries with a lovely aroma.', ['Naturally sweet', 'Ripe and red', 'Hand-picked'])
add('Whole Walnuts (Akhrot)', 'dry', '', '', '', None, '0802', 5, 180,
    [('250 g', 'g', '250g', '320', '290', 'FP-WALNUT-250', '250', 'g', 300), ('500 g', 'g', '500g', '620', '560', 'FP-WALNUT-500', '500', 'g', 550)],
    [20305380, 7333072], 'Crunchy, omega-3-rich walnuts in shell.', ['Rich in omega-3', 'Crisp, fresh kernel', 'Natural, unprocessed'])
add('Premium Raisins (Kishmish)', 'dry', '', '', '', None, '0806', 5, 180,
    [('250 g', 'g', '250g', '105', '95', 'FP-RAISIN-250', '250', 'g', 300), ('500 g', 'g', '500g', '195', '180', 'FP-RAISIN-500', '500', 'g', 550)],
    [35166629, 12945019], 'Plump, naturally sweet seedless raisins.', ['Naturally sweet', 'Seedless', 'Great for sweets and snacking'])
add('Roasted Pistachios (Pista)', 'dry', '', '', '', None, '0802', 5, 180,
    [('250 g', 'g', '250g', '450', '420', 'FP-PISTA-250', '250', 'g', 300), ('500 g', 'g', '500g', '880', '820', 'FP-PISTA-500', '500', 'g', 550)],
    [1799307, 7421516], 'Lightly salted, roasted pistachios - crunchy and flavourful.', ['Lightly salted', 'Crunchy', 'Rich in protein'])

json.dump({v[5]: p['gst'] for p in P for v in p['variants']}, open('backup/fresh_gst.json', 'w'))
need = sorted({i for p in P for i in p['photos']} - set(ph))
for i in need:
    im = Image.open(f'px9/{i}.jpg').convert('RGB'); im.thumbnail((1200, 1200)); out = f'px9/up_{i}.jpg'; im.save(out, 'JPEG', quality=90)
    r = subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Authorization: Bearer ' + tok, '-A', 'curl/8.4.0', '-F', f'image=@{out};type=image/jpeg',
                        'https://vendor.sevo.co.in/api/workforce/seller-hub/products/upload-image/'], capture_output=True, text=True)
    try: ph[i] = json.loads(r.stdout)['image_url']
    except Exception: print('UPLOAD FAIL', i, r.stdout[:200]); sys.exit(1)
json.dump(ph, open(PH, 'w')); print('uploaded', len(need))

existing = {}
for pg in (1, 2, 3, 4, 5, 6):
    s, d = call('GET', f'products/?page_size=100&page={pg}')
    for q in d['results']: existing[q['sku']] = q['id']
s, gl = call('GET', 'variant-groups/')
groups = {x['group_title']: x['id'] for x in (gl if isinstance(gl, list) else gl.get('results', []))}
log = json.load(open('backup/fresh_created.json')) if os.path.exists('backup/fresh_created.json') else {}
for p in P:
    gid = None
    if len(p['variants']) > 1:
        gid = groups.get(p['title'])
        if not gid:
            s, g = call('POST', 'variant-groups/', {'group_title': p['title'], 'variant_attribute_name': 'Size'}); gid = (g.get('group') or g)['id']
    for label, unit, pack, mrp, price, sku, nv, nu, G in p['variants']:
        if sku in existing: log[sku] = existing[sku]; print('exists', sku); continue
        body = dict(category=p['cat'], title=p['title'], brand='SEVO Fresh', unit=unit, pack_size=pack, variant_label=label, mrp=mrp, selling_price=price,
                    hsn_code=p['hsn'], sku=sku, description=p['desc'], storage_info='Store in a cool, dry place. Refrigerate leafy items.',
                    shelf_life_value=p['shelf'], shelf_life_unit='days', images=[ph[i] for i in p['photos']], specs=[],
                    package_length_cm=20, package_width_cm=15, package_height_cm=10, gross_weight_g=G, generic_name=p['title'],
                    procurement_price=f"{float(price) * 0.75:.2f}", net_weight_value=nv, net_weight_unit=nu, food_type='VEG',
                    fssai_license_number='10020043000123', **MFG)
        if p['sold']:
            body.update(produce_variety=p['variety'], sold_by=p['sold'], produce_grade=p['grade'])
            if p['piece']: body['approx_piece_weight_g'] = p['piece']
        if gid: body['variant_group'] = gid
        s, d = call('POST', 'products/', body)
        if s != 201: print('CREATE FAIL', sku, s, json.dumps(d, ensure_ascii=False)[:300]); continue
        log[sku] = d['product']['id']; print('created', sku, d['product']['id'])
json.dump(log, open('backup/fresh_created.json', 'w')); print('total', len(log))
