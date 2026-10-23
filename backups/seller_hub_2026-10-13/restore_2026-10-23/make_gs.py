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


CAT = dict(basmati=5219, wheat=5221, sugar=5234, whole=5236,
           brown=ensure('gs-brown-red-rice', 'Brown & Red Rice', 5216, 4),
           masoor=ensure('gs-masoor-dal', 'Masoor Dal', 5224, 5),
           rajma=ensure('gs-rajma-chickpeas', 'Rajma & Chickpeas', 5224, 6),
           coco=ensure('gs-coconut-oil', 'Coconut Oil', 5229, 3),
           olive=ensure('gs-olive-oil', 'Olive Oil', 5229, 4),
           honey=ensure('gs-honey', 'Honey & Sweeteners', 5232, 3),
           blend=ensure('gs-masala-blends', 'Masala Blends', 5235, 3))

PH = 'backup/gs_photos.json'
ph = {int(k): v for k, v in json.load(open(PH)).items()} if os.path.exists(PH) else {}
MFG = dict(country_of_origin='IN', manufacturer_name='SEVO Foods Pvt Ltd', manufacturer_address='SIPCOT Industrial Park, Hosur, Tamil Nadu', manufacturer_pincode='635109')
P = []


def desc(a, pts): return '<p>' + a + '</p><ul>' + ''.join(f'<li>{p}</li>' for p in pts) + '</ul>'


# V = (label, unit, pack, mrp, price, sku, net_value, net_unit, gross_g, L, W, H)
def add(title, brand, c, hsn, shelf, su, V, photos, summary, points, specs=None, gst=5):
    P.append(dict(title=title, brand=brand, cat=CAT[c], hsn=hsn, shelf=shelf, su=su, variants=V, photos=photos, gst=gst,
                  desc=desc(summary, points), specs=specs or []))


add('Premium Long Grain Basmati Rice', 'Royal Kernel', 'basmati', '1006', 12, 'months',
    [('1 kg', 'kg', '1 kg', '145', '129', 'GS-BASM-PRM-1KG', '1', 'kg', 1060, 22, 14, 6), ('5 kg', 'kg', '5 kg', '690', '625', 'GS-BASM-PRM-5KG', '5', 'kg', 5150, 40, 26, 10)],
    [15879426, 7421207], 'Slender, aromatic long-grain basmati that cooks fluffy and separate - perfect for biryani and pulao.', ['Extra-long grains', 'Naturally aromatic', 'Aged for fluffier rice'], [('Type', 'Basmati'), ('Grain', 'Long')])
add('Aged Extra Long Basmati Rice (1121)', 'Royal Kernel', 'basmati', '1006', 12, 'months',
    [('1 kg', 'kg', '1 kg', '175', '159', 'GS-BASM-1121-1KG', '1', 'kg', 1060, 22, 14, 6), ('5 kg', 'kg', '5 kg', '840', '769', 'GS-BASM-1121-5KG', '5', 'kg', 5150, 40, 26, 10)],
    [7851798, 36346840], 'Aged 1121 basmati - the longest grain that elongates up to twice on cooking.', ['Extra-long, aged grains', 'Rich aroma', 'Ideal for biryani'], [('Type', 'Basmati 1121')])
add('Organic Brown Rice', 'Earth Harvest', 'brown', '1006', 9, 'months',
    [('1 kg', 'kg', '1 kg', '120', '105', 'GS-BROWN-1KG', '1', 'kg', 1060, 22, 14, 6), ('5 kg', 'kg', '5 kg', '570', '515', 'GS-BROWN-5KG', '5', 'kg', 5150, 40, 26, 10)],
    [5114289, 6103071], 'Unpolished whole-grain brown rice with bran intact - higher in fibre and nutrients.', ['Unpolished whole grain', 'High in fibre', 'Naturally nutty flavour'], [('Type', 'Brown rice')])
add('Red Matta Rice (Kerala)', 'Earth Harvest', 'brown', '1006', 9, 'months',
    [('1 kg', 'kg', '1 kg', '110', '98', 'GS-MATTA-1KG', '1', 'kg', 1060, 22, 14, 6)], [4110263],
    'Traditional Kerala red matta rice with a rustic taste, rich in fibre.', ['Earthy, nutty flavour', 'Rich in fibre', 'Traditional variety'], [('Type', 'Red rice')])
add('Black Rice (Forbidden Rice)', 'Earth Harvest', 'brown', '1006', 9, 'months',
    [('500 g', 'g', '500 g', '135', '119', 'GS-BLACKRICE-500', '500', 'g', 550, 20, 12, 5)], [30756211],
    'Antioxidant-rich black rice that turns deep purple on cooking.', ['Rich in anthocyanins', 'Nutty, slightly sweet', 'Great for kheer and pulao'], [('Type', 'Black rice')])
add('Multigrain Atta', 'Golden Mill', 'wheat', '1101', 4, 'months',
    [('1 kg', 'kg', '1 kg', '75', '68', 'GS-MULTI-1KG', '1', 'kg', 1060, 22, 14, 6), ('5 kg', 'kg', '5 kg', '350', '319', 'GS-MULTI-5KG', '5', 'kg', 5150, 40, 26, 10)],
    [11726089], 'Stone-ground blend of wheat, ragi, oats, jowar and chana for nutritious rotis.', ['Blend of 6 grains', 'Stone ground', 'High in fibre'], [('Blend', 'Wheat, ragi, oats, jowar, chana, soya')])
add('Masoor Dal (Red Lentils)', 'Annapurna', 'masoor', '0713', 12, 'months',
    [('500 g', 'g', '500 g', '62', '55', 'GS-MASOOR-500', '500', 'g', 550, 20, 12, 5), ('1 kg', 'kg', '1 kg', '118', '105', 'GS-MASOOR-1KG', '1', 'kg', 1060, 22, 14, 6)],
    [14177776, 11369845], 'Quick-cooking split red lentils with a mild, earthy taste.', ['Cooks in 15 minutes', 'Rich in protein', 'Cleaned and polished'], [('Type', 'Split red lentils')])
add('Red Kidney Beans (Rajma)', 'Annapurna', 'rajma', '0713', 12, 'months',
    [('500 g', 'g', '500 g', '95', '85', 'GS-RAJMA-500', '500', 'g', 550, 20, 12, 5), ('1 kg', 'kg', '1 kg', '180', '165', 'GS-RAJMA-1KG', '1', 'kg', 1060, 22, 14, 6)],
    [18233225, 7717469], 'Chitra rajma that cooks soft and creamy - the base of rajma chawal.', ['Soft, creamy texture', 'Rich in protein', 'Hand sorted'], [('Type', 'Red kidney beans')])
add('Kabuli Chana (White Chickpeas)', 'Annapurna', 'rajma', '0713', 12, 'months',
    [('500 g', 'g', '500 g', '88', '79', 'GS-KABULI-500', '500', 'g', 550, 20, 12, 5), ('1 kg', 'kg', '1 kg', '165', '149', 'GS-KABULI-1KG', '1', 'kg', 1060, 22, 14, 6)],
    [14440733, 5425012], 'Plump kabuli chana for chole, hummus and salads.', ['Large, plump chickpeas', 'Cooks soft', 'Rich in protein and fibre'], [('Type', 'Chickpeas')])
add('Dried Green Peas (Hari Vatana)', 'Annapurna', 'rajma', '0713', 12, 'months',
    [('500 g', 'g', '500 g', '70', '62', 'GS-GRPEAS-500', '500', 'g', 550, 20, 12, 5)], [8580713],
    'Dried green peas for matar kulcha, ragda and curries.', ['Soak overnight before cooking', 'Rich in protein', 'Cleaned and sorted'], [('Type', 'Dried peas')])
add('Cold Pressed Coconut Oil', 'Kera Gold', 'coco', '1513', 12, 'months',
    [('500 ml', 'ml', '500 ml', '260', '235', 'GS-COCOIL-500', '500', 'ml', 560, 7, 7, 22), ('1 L', 'l', '1 L', '499', '455', 'GS-COCOIL-1L', '1', 'l', 1080, 9, 9, 27)],
    [11809347], 'Traditionally extracted coconut oil for cooking and hair care.', ['Cold pressed', 'Natural coconut aroma', 'No additives'], [('Type', 'Coconut oil')])
add('Extra Virgin Olive Oil', 'Olivia', 'olive', '1509', 18, 'months',
    [('250 ml', 'ml', '250 ml', '399', '359', 'GS-OLIVE-250', '250', 'ml', 480, 6, 6, 22), ('500 ml', 'ml', '500 ml', '749', '679', 'GS-OLIVE-500', '500', 'ml', 880, 7, 7, 28)],
    [7296399], 'First cold-pressed extra virgin olive oil for dressings, dips and light sauteing.', ['Cold pressed', 'Fruity, peppery flavour', 'Rich in antioxidants'], [('Type', 'Extra virgin olive oil')])
add('Raw Brown Sugar', 'Sweet Valley', 'sugar', '1701', 18, 'months',
    [('500 g', 'g', '500 g', '55', '49', 'GS-BRSUGAR-500', '500', 'g', 550, 20, 12, 5), ('1 kg', 'kg', '1 kg', '105', '95', 'GS-BRSUGAR-1KG', '1', 'kg', 1060, 22, 14, 6)],
    [6086210, 35783030], 'Unrefined raw brown sugar with a mild molasses taste.', ['Less processed', 'Rich caramel flavour', 'Great for tea and baking'], [('Type', 'Brown sugar')])
add('White Sugar Cubes', 'Sweet Valley', 'sugar', '1701', 24, 'months',
    [('500 g', 'g', '500 g', '75', '69', 'GS-CUBES-500', '500', 'g', 550, 20, 12, 5)], [5469035, 35793177],
    'Neat sugar cubes for tea, coffee and desserts.', ['Uniform cubes', 'Dissolves quickly', 'Hygienically packed'], [('Type', 'Sugar cubes')])
add('Pure Honey (Multiflora)', 'Hive Fresh', 'honey', '0409', 24, 'months',
    [('250 g', 'g', '250 g', '165', '149', 'GS-HONEY-250', '250', 'g', 400, 7, 7, 10), ('500 g', 'g', '500 g', '310', '279', 'GS-HONEY-500', '500', 'g', 700, 8, 8, 13)],
    [5865194, 13246534], '100% pure multiflora honey, unheated and unprocessed.', ['No added sugar', 'Raw and unheated', 'Natural sweetener'], [('Type', 'Multiflora honey')])
add('Whole Black Pepper (Kali Mirch)', 'Spice Route', 'whole', '0904', 18, 'months',
    [('50 g', 'g', '50 g', '75', '69', 'GS-PEPPER-50', '50', 'g', 70, 12, 8, 4), ('100 g', 'g', '100 g', '140', '129', 'GS-PEPPER-100', '100', 'g', 120, 14, 9, 5)],
    [8559086, 5988689], 'Bold, pungent Malabar black peppercorns.', ['Malabar peppercorns', 'Strong aroma', 'Freshly packed'], [('Type', 'Whole spice')])
add('Whole Cloves (Laung)', 'Spice Route', 'whole', '0907', 18, 'months',
    [('50 g', 'g', '50 g', '95', '85', 'GS-CLOVES-50', '50', 'g', 70, 12, 8, 4)], [12142752, 6087276],
    'Aromatic whole cloves for biryani, masala chai and curries.', ['Strong, sweet aroma', 'Hand sorted', 'Freshly packed'], [('Type', 'Whole spice')])
add('Cinnamon Sticks (Dalchini)', 'Spice Route', 'whole', '0906', 18, 'months',
    [('50 g', 'g', '50 g', '70', '62', 'GS-CINNAM-50', '50', 'g', 70, 16, 8, 4)], [31665263, 15388238],
    'True cinnamon quills with a delicate sweet fragrance.', ['Sweet, warm flavour', 'Natural bark quills', 'Great for desserts and tea'], [('Type', 'Whole spice')])
add('Mustard Seeds (Rai)', 'Spice Route', 'whole', '1207', 18, 'months',
    [('100 g', 'g', '100 g', '28', '24', 'GS-MUSTARD-100', '100', 'g', 120, 14, 9, 5), ('200 g', 'g', '200 g', '52', '46', 'GS-MUSTARD-200', '200', 'g', 220, 16, 10, 6)],
    [5409832, 18346906], 'Small, sharp mustard seeds for tempering.', ['Cleaned seeds', 'Pungent flavour', 'Essential for tadka'], [('Type', 'Whole spice')])
add('Coriander Seeds (Dhania)', 'Spice Route', 'whole', '0909', 18, 'months',
    [('100 g', 'g', '100 g', '32', '28', 'GS-CORISD-100', '100', 'g', 120, 14, 9, 5), ('250 g', 'g', '250 g', '72', '65', 'GS-CORISD-250', '250', 'g', 270, 18, 11, 6)],
    [5988179, 10487771], 'Whole coriander seeds with a citrusy aroma - for masalas and pickles.', ['Citrusy aroma', 'Hand cleaned', 'Freshly packed'], [('Type', 'Whole spice')])
add('Garam Masala', 'Spice Route', 'blend', '0910', 12, 'months',
    [('100 g', 'g', '100 g', '95', '85', 'GS-GARAM-100', '100', 'g', 120, 14, 9, 5)], [672046, 32281706],
    'Classic aromatic blend of roasted whole spices for curries, rice and gravies.', ['Roasted and ground in small batches', 'Balanced aroma', 'No fillers'], [('Type', 'Spice blend')])
add('Sambar Powder', 'Spice Route', 'blend', '0910', 12, 'months',
    [('100 g', 'g', '100 g', '62', '55', 'GS-SAMBAR-100', '100', 'g', 120, 14, 9, 5), ('200 g', 'g', '200 g', '115', '102', 'GS-SAMBAR-200', '200', 'g', 220, 16, 10, 6)],
    [8649386], 'South Indian sambar masala made from roasted dals, chillies and spices.', ['Authentic South Indian blend', 'Freshly ground', 'Perfect for sambar and kuzhambu'], [('Type', 'Spice blend')])

json.dump({v[5]: p['gst'] for p in P for v in p['variants']}, open('backup/gs_gst.json', 'w'))
need = sorted({i for p in P for i in p['photos']} - set(ph))
for i in need:
    im = Image.open(f'px10/{i}.jpg').convert('RGB'); im.thumbnail((1200, 1200)); out = f'px10/up_{i}.jpg'; im.save(out, 'JPEG', quality=90)
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
log = json.load(open('backup/gs_created.json')) if os.path.exists('backup/gs_created.json') else {}
for p in P:
    gid = None
    if len(p['variants']) > 1:
        gid = groups.get(p['title'])
        if not gid:
            s, g = call('POST', 'variant-groups/', {'group_title': p['title'], 'variant_attribute_name': 'Size'}); gid = (g.get('group') or g)['id']
    for label, unit, pack, mrp, price, sku, nv, nu, G, L, Wd, Ht in p['variants']:
        if sku in existing: log[sku] = existing[sku]; print('exists', sku); continue
        body = dict(category=p['cat'], title=p['title'], brand=p['brand'], unit=unit, pack_size=pack, variant_label=label, mrp=mrp, selling_price=price,
                    hsn_code=p['hsn'], sku=sku, description=p['desc'], storage_info='Store in a cool, dry place away from sunlight. Keep the pack sealed.',
                    shelf_life_value=p['shelf'], shelf_life_unit=p['su'], images=[ph[i] for i in p['photos']], specs=[{'label': a, 'value': b} for a, b in p['specs']],
                    package_length_cm=L, package_width_cm=Wd, package_height_cm=Ht, gross_weight_g=G, generic_name=p['title'],
                    procurement_price=f"{float(price) * 0.78:.2f}", net_weight_value=nv, net_weight_unit=nu, food_type='VEG',
                    fssai_license_number='10020043000123', **MFG)
        if gid: body['variant_group'] = gid
        s, d = call('POST', 'products/', body)
        if s != 201: print('CREATE FAIL', sku, s, json.dumps(d, ensure_ascii=False)[:300]); continue
        log[sku] = d['product']['id']; print('created', sku, d['product']['id'])
json.dump(log, open('backup/gs_created.json', 'w')); print('total', len(log))
