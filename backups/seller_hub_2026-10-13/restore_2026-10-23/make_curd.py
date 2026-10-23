import json, subprocess, sys
from api_seller import call, tok

up = subprocess.run(['curl', '-s', '-X', 'POST', '-H', 'Authorization: Bearer ' + tok, '-A', 'curl/8.4.0', '-F', 'image=@px4/curd_bowl.jpg;type=image/jpeg',
                     'https://vendor.sevo.co.in/api/workforce/seller-hub/products/upload-image/'], capture_output=True, text=True)
img = json.loads(up.stdout)['image_url']
print('image', img)
s, g = call('POST', 'variant-groups/', {'group_title': 'Farm Fresh Set Curd (Dahi)', 'variant_attribute_name': 'Size'})
gid = (g.get('group') or g)['id']
desc = ('<p>Thick, creamy set curd made from fresh toned milk and set naturally. Mild and smooth - perfect with rice, in raita, lassi and everyday cooking.</p>'
        '<ul><li>Set naturally from fresh toned milk</li><li>Thick, creamy and mildly sour</li><li>No added preservatives</li></ul>')
MFG = dict(country_of_origin='IN', manufacturer_name='SEVO Fresh Foods Pvt Ltd', manufacturer_address='SIPCOT Industrial Park, Hosur, Tamil Nadu', manufacturer_pincode='635109')
log = json.load(open('backup/db_created.json'))
for label, unit, pack, mrp, price, sku, L, W, H, G, nv, nu in [
        ('400 g', 'g', '400 g', '38', '34', 'DB-CURD-SET-400', 10, 10, 8, 430, '400', 'g'),
        ('1 kg', 'kg', '1 kg', '90', '82', 'DB-CURD-SET-1KG', 14, 14, 10, 1060, '1', 'kg')]:
    body = dict(category=5241, title='Farm Fresh Set Curd (Dahi)', brand='Gowri Dairy', unit=unit, pack_size=pack, variant_label=label, mrp=mrp, selling_price=price,
                hsn_code='0403', sku=sku, description=desc, storage_info='Keep refrigerated at 4 degrees C.', shelf_life_value=7, shelf_life_unit='days',
                images=[img], specs=[{'label': 'Type', 'value': 'Set curd'}, {'label': 'Fat', 'value': 'Toned'}], package_length_cm=L, package_width_cm=W,
                package_height_cm=H, gross_weight_g=G, generic_name='Curd', procurement_price=f"{float(price) * 0.78:.2f}", net_weight_value=nv,
                net_weight_unit=nu, food_type='VEG', fssai_license_number='10020043000123', variant_group=gid, **MFG)
    s, d = call('POST', 'products/', body)
    if s != 201:
        print('FAIL', sku, s, json.dumps(d)[:300]); sys.exit(1)
    log[sku] = d['product']['id']; print('created', sku, d['product']['id'])
json.dump(log, open('backup/db_created.json', 'w'))
