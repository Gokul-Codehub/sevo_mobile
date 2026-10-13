import json,re,subprocess,sys,os
from PIL import Image
from api_seller import call, tok

def slug(s): return re.sub(r'[^a-z0-9]+','-',s.lower().replace('&','and')).strip('-')
cats=json.load(open('backup/created_categories.json'))
ph={int(k):v for k,v in json.load(open('backup/uploaded_photos.json')).items()}
MFG=dict(country_of_origin='IN',manufacturer_name='SEVO Consumer Care Pvt Ltd',manufacturer_address='SIPCOT Industrial Park, Hosur, Tamil Nadu',manufacturer_pincode='635109')

def leaf(cat,lf): return cats['bpc-'+slug(cat)+'-'+slug(lf)]

def desc(summary,points): return '<p>'+summary+'</p><ul>'+''.join(f'<li>{p}</li>' for p in points)+'</ul>'

# V = (label, unit, pack, mrp, price, sku, L, W, H, gross_g)
P=[]
def add(key,title,brand,cat,lf,hsn,shelf,generic,variants,photos,summary,points,specs,storage):
    P.append(dict(key=key,title=title,brand=brand,cat=cat,leaf=lf,hsn=hsn,shelf=shelf,generic=generic,variants=variants,photos=photos,
                  desc=desc(summary,points),specs=specs,storage=storage))

HC='Hair Care'
add('ho1','Coconut & Amla Hair Oil','Kaveri Herbals',HC,'Hair Oils','3305',24,'Hair oil',
    [('100 ml','ml','100 ml','129','109','BPC-HO-COCO-100',5,5,13,170),('200 ml','ml','200 ml','229','199','BPC-HO-COCO-200',6,6,16,310)],[4408447,17307533,30595022],
    'Cold-pressed coconut oil infused with amla and bhringraj for stronger, shinier hair. Light, non-sticky and easy to wash off.',
    ['Coconut, amla and bhringraj blend','Reduces hair fall from breakage','Non-sticky, suitable for daily use'],
    [('Hair type','All hair types'),('Key ingredients','Coconut oil, Amla, Bhringraj'),('Form','Hair oil')],'Store in a cool, dry place away from sunlight.')
add('ho2','Rosemary Hair Growth Oil','Nilgiri Botanics',HC,'Hair Oils','3305',24,'Hair oil',
    [('100 ml','ml','100 ml','349','299','BPC-HO-ROSE-100',5,5,13,170)],[33731885,31401737,7796587],
    'Lightweight growth oil with rosemary, castor and pumpkin seed oil. Massage into the scalp to nourish roots.',
    ['Rosemary and castor oil blend','Dropper bottle for easy scalp application','Free from mineral oil'],
    [('Hair type','All hair types'),('Key ingredients','Rosemary, Castor oil, Pumpkin seed oil'),('Form','Hair oil')],'Store in a cool, dry place. Shake before use.')
add('sh1','Anti-Dandruff Shampoo','SEVO Care',HC,'Shampoos','3305',30,'Shampoo',
    [('200 ml','ml','200 ml','179','155','BPC-SH-ANTI-200',5,5,18,260),('400 ml','ml','400 ml','319','279','BPC-SH-ANTI-400',7,7,20,480)],[7440056,8467975,16749131],
    'Clinically tested anti-dandruff shampoo with zinc pyrithione and tea tree oil. Clears flakes and keeps the scalp fresh.',
    ['Visibly reduces dandruff from the first wash','Tea tree oil for an itch-free scalp','Suitable for regular use'],
    [('Hair type','All hair types'),('Concern','Dandruff'),('Form','Shampoo')],'Store in a cool, dry place. Avoid contact with eyes.')
add('sh2','Argan Smooth Shampoo','Nilgiri Botanics',HC,'Shampoos','3305',30,'Shampoo',
    [('250 ml','ml','250 ml','299','259','BPC-SH-ARGA-250',6,6,19,320)],[28345529,33146411,3735627],
    'Sulphate-free shampoo enriched with argan oil. Gently cleanses while leaving hair soft, smooth and manageable.',
    ['Sulphate-free gentle cleansing','Argan oil for smooth, frizz-free hair','Colour-safe formula'],
    [('Hair type','Dry and frizzy'),('Key ingredients','Argan oil, Aloe vera'),('Form','Shampoo')],'Store in a cool, dry place.')
add('cn1','Smooth & Silky Conditioner','SEVO Care',HC,'Conditioners','3305',30,'Hair conditioner',
    [('200 ml','ml','200 ml','189','165','BPC-CN-SILK-200',5,5,18,260)],[16749131,19833253,28345529],
    'Daily conditioner that detangles, softens and adds shine. Use after shampoo for easy-to-comb hair.',
    ['Detangles instantly','Silk protein for shine','Suitable for all hair types'],
    [('Hair type','All hair types'),('Form','Conditioner')],'Store in a cool, dry place.')
add('hs1','Argan Hair Serum','Nilgiri Botanics',HC,'Hair Masks & Serums','3305',24,'Hair serum',
    [('50 ml','ml','50 ml','349','299','BPC-HS-ARGA-50',4,4,13,130)],[31401740,31401739,31401744],
    'Non-greasy hair serum with argan oil and vitamin E. Tames frizz and adds a glossy finish that lasts all day.',
    ['Controls frizz and flyaways','Heat protection while styling','Pump bottle, a little goes a long way'],
    [('Hair type','Dry and frizzy'),('Key ingredients','Argan oil, Vitamin E'),('Form','Serum')],'Store in a cool, dry place.')
add('hm1','Deep Repair Hair Mask','Kaveri Herbals',HC,'Hair Masks & Serums','3305',24,'Hair mask',
    [('200 g','g','200 g','399','349','BPC-HM-REPA-200',9,9,7,300)],[32435039,18509467,6167443],
    'Intensive weekly hair mask with shea butter and hibiscus. Repairs dryness and damage from styling and sun.',
    ['Deeply conditions in 5 minutes','Shea butter and hibiscus','Use once or twice a week'],
    [('Hair type','Dry and damaged'),('Key ingredients','Shea butter, Hibiscus'),('Form','Hair mask')],'Store in a cool, dry place. Keep the jar closed.')
add('hk1','Hair Colour Application Kit','SEVO Care',HC,'Hair Color','9603',60,'Hair colour application kit',
    [('Kit of 4','pack','Kit of 4','199','169','BPC-HK-KIT-4',22,16,5,180)],[8468142,8468158,8468141],
    'Everything you need to apply hair colour at home: mixing bowl, tint brush, comb and gloves.',
    ['Mixing bowl, brush, comb and gloves','Even, mess-free application','Reusable bowl and brush'],
    [('Contents','Mixing bowl, Tint brush, Comb, Gloves'),('Material','Plastic')],'Wash and dry after each use.')
add('cb1','Wooden Detangling Comb','Nilgiri Botanics',HC,'Combs & Accessories','9615',60,'Hair comb',
    [('Single','piece','1 piece','149','129','BPC-CB-WOOD-1',20,6,2,40)],[7428093,19572634,8468152],
    'Wide-tooth detangling comb in natural wood. Reduces breakage and static while combing wet or dry hair.',
    ['Wide teeth for easy detangling','Anti-static natural wood','Smooth, snag-free finish'],
    [('Material','Natural wood'),('Type','Wide-tooth comb')],'Wipe clean with a dry cloth.')
add('cb2','Hair Comb Set (Pack of 3)','SEVO Care',HC,'Combs & Accessories','9615',60,'Hair comb set',
    [('Pack of 3','pack','Pack of 3','129','99','BPC-CB-SET-3',22,8,3,110)],[3992852,8468177,7518708],
    'Set of three everyday combs: wide-tooth, fine-tooth and tail comb for parting and styling.',
    ['Three combs for every styling need','Durable, flexible plastic','Smooth teeth, gentle on the scalp'],
    [('Quantity','3 combs'),('Material','Plastic')],'Wash with mild soap and dry.')

BC='Beauty & Cosmetics'
add('fm1','Matte Liquid Foundation','SEVO Care',BC,'Face Makeup','3304',30,'Foundation',
    [('30 ml','ml','30 ml','599','499','BPC-FM-MATT-30',4,4,11,110)],[27676711,7256102,7256092],
    'Lightweight liquid foundation with a natural matte finish and medium coverage. Stays put through the day.',
    ['Natural matte finish','Buildable medium coverage','Blends easily, no cakiness'],
    [('Finish','Matte'),('Coverage','Medium'),('Skin type','Normal to oily')],'Store below 30 degrees C. Keep the cap closed.')
add('em1','Smudge-Proof Black Eyeliner','SEVO Care',BC,'Eye Makeup','3304',24,'Eyeliner',
    [('1.5 ml','ml','1.5 ml','299','249','BPC-EM-LINE-15',3,3,13,25)],[2697787,2697786,8558523],
    'Intense black liquid eyeliner with a fine felt tip for precise lines. Smudge-proof and waterproof for 12 hours.',
    ['Waterproof and smudge-proof','Fine tip for thin or bold lines','Quick-dry formula'],
    [('Shade','Jet black'),('Finish','Matte'),('Waterproof','Yes')],'Store at room temperature. Replace every 6 months.')
add('lp1','Creamy Matte Lipstick - Ruby Red','SEVO Care',BC,'Lips','3304',36,'Lipstick',
    [('4 g','g','4 g','399','349','BPC-LP-RUBY-4',3,3,9,30)],[7810641,7256082,7256093],
    'Rich, creamy matte lipstick in a classic ruby red. Comfortable, long-wearing colour enriched with vitamin E.',
    ['Creamy, comfortable matte finish','Vitamin E for soft lips','Long-lasting colour'],
    [('Shade','Ruby Red'),('Finish','Matte'),('Net weight','4 g')],'Store in a cool place away from heat.')
add('np1','Gel-Finish Nail Polish - Ocean Blue','SEVO Care',BC,'Nail Care','3304',36,'Nail polish',
    [('10 ml','ml','10 ml','149','129','BPC-NP-BLUE-10',3,3,7,45)],[1373747,29229021,29100941],
    'High-shine gel-finish nail colour in ocean blue. Chip-resistant formula that dries fast.',
    ['Gel-like high shine','Chip-resistant for up to 7 days','Quick-dry formula'],
    [('Shade','Ocean Blue'),('Finish','Glossy'),('Volume','10 ml')],'Store upright in a cool place. Keep away from heat and flame.')
add('fs1','Vitamin C Face Serum','Nilgiri Botanics',BC,'Skin Care','3304',24,'Face serum',
    [('30 ml','ml','30 ml','599','499','BPC-FS-VITC-30',4,4,12,100)],[8101534,8054400,8101511],
    'Brightening face serum with 10% vitamin C and hyaluronic acid. Evens skin tone and boosts radiance.',
    ['10% vitamin C for brighter skin','Hyaluronic acid for hydration','Lightweight, fast-absorbing'],
    [('Skin type','All skin types'),('Key ingredients','Vitamin C, Hyaluronic acid'),('Form','Serum')],'Store in a cool, dark place. Use within 6 months of opening.')
add('fc1','Hydrating Face Cream','Kaveri Herbals',BC,'Skin Care','3304',24,'Face cream',
    [('50 g','g','50 g','349','299','BPC-FC-HYDR-50',6,6,5,110)],[14473476,8015480,15930069],
    'Daily moisturising cream with aloe vera and shea butter. Keeps skin soft and hydrated for 24 hours.',
    ['24-hour hydration','Aloe vera and shea butter','Non-greasy finish'],
    [('Skin type','Normal to dry'),('Key ingredients','Aloe vera, Shea butter'),('Form','Cream')],'Store in a cool, dry place.')
add('mb1','Makeup Brush Set (Pack of 7)','SEVO Care',BC,'Makeup Tools & Brushes','9603',60,'Makeup brush set',
    [('Set of 7','pack','Set of 7','599','499','BPC-MB-SET-7',22,10,5,230)],[22481931,7290613,205923],
    'Seven-piece makeup brush set for face and eyes: foundation, powder, blush, contour, eyeshadow and blending brushes.',
    ['Soft, dense synthetic bristles','Seven brushes for every step','Easy to clean'],
    [('Quantity','7 brushes'),('Bristles','Synthetic')],'Wash with mild shampoo and dry flat.')

MG="Men's Grooming"
add('rz1','3-Blade Disposable Razor (Pack of 5)','SEVO Care',MG,'Shaving','8212',60,'Disposable razor',
    [('Pack of 5','pack','Pack of 5','149','129','BPC-RZ-3BLD-5',16,10,3,60)],[39058810,1319459],
    'Five disposable razors with three stainless-steel blades and a lubricating strip for a smooth, close shave.',
    ['Three blades for a close shave','Lubricating strip reduces irritation','Pack of 5'],
    [('Quantity','5 razors'),('Blades','3')],'Store in a dry place.')
add('bo1','Cedarwood Beard Oil','Nilgiri Botanics',MG,'Beard Care','3305',24,'Beard oil',
    [('30 ml','ml','30 ml','399','349','BPC-BO-CEDA-30',4,4,10,90)],[9379073,9379078],
    'Softens and conditions the beard, reduces itch and adds a healthy shine. Light cedarwood fragrance.',
    ['Softens coarse beard hair','Reduces itch and flaking','Dropper bottle for easy use'],
    [('Key ingredients','Argan oil, Jojoba oil, Cedarwood'),('Form','Beard oil')],'Store in a cool, dry place.')

FH='Feminine Hygiene'
add('sp1','Ultra Soft Sanitary Pads (Pack of 20)','SEVO Care',FH,'Sanitary Pads','9619',36,'Sanitary napkins',
    [('Pack of 20','pack','Pack of 20 (L)','199','175','BPC-SP-ULT-20',22,12,6,260)],[3958544,7692468,3958553],
    'Ultra-thin sanitary pads with a soft cotton-like top sheet and wings. Up to 8 hours of leak protection.',
    ['Ultra-thin and comfortable','Wings for leak protection','Pack of 20, size L'],
    [('Size','Large (280 mm)'),('Quantity','20 pads'),('Wings','Yes')],'Store in a clean, dry place.')
add('mc1','Reusable Menstrual Cup - Medium','SEVO Care',FH,'Tampons & Menstrual Cups','9619',60,'Menstrual cup',
    [('Medium','piece','1 piece (M)','599','499','BPC-MC-MED-1',8,6,6,70)],[7262758,4856505],
    'Medical-grade silicone menstrual cup that can be reused for up to 10 years. Comes with a cotton storage pouch.',
    ['100% medical-grade silicone','Reusable for up to 10 years','Up to 12 hours of protection'],
    [('Size','Medium'),('Material','Medical-grade silicone'),('Includes','Storage pouch')],'Sterilise before first use; store in the pouch.')
add('pl1','Daily Panty Liners (Pack of 40)','SEVO Care',FH,'Panty Liners','9619',36,'Panty liners',
    [('Pack of 40','pack','Pack of 40','149','129','BPC-PL-DAY-40',18,12,6,180)],[7692459,6590806,7692271],
    'Breathable, ultra-thin panty liners for everyday freshness and light flow protection.',
    ['Ultra-thin and breathable','Fresh, comfortable all day','Pack of 40'],
    [('Quantity','40 liners'),('Length','155 mm')],'Store in a clean, dry place.')

HP='Health & Pharmacy'
add('vg1','Vitamin C Gummies (60 Gummies)','SEVO Care',HP,'Vitamins & Supplements','2106',18,'Dietary supplement',
    [('60 gummies','piece','60 gummies','499','399','BPC-VG-VITC-60',6,6,10,160)],[14029289,14029292,14433549],
    'Tasty orange-flavoured vitamin C gummies to support immunity. Two gummies a day.',
    ['250 mg vitamin C per gummy','Orange flavour, no artificial colours','60 gummies, one month supply'],
    [('Form','Gummies'),('Flavour','Orange'),('Quantity','60')],'Store in a cool, dry place. Keep out of reach of children.')
add('cp1','Omega-3 Fish Oil Capsules (60)','Kaveri Herbals',HP,'Vitamins & Supplements','2106',24,'Dietary supplement',
    [('60 capsules','piece','60 capsules','699','599','BPC-CP-OMEG-60',5,5,10,130)],[13787562,13779111,13779102],
    'Omega-3 fish oil softgels with EPA and DHA for heart, brain and joint health.',
    ['EPA and DHA for heart health','Odour-free softgels','One capsule daily'],
    [('Form','Softgel capsules'),('Quantity','60')],'Store below 25 degrees C. Keep out of reach of children.')
add('bm1','Herbal Pain Relief Balm','Kaveri Herbals',HP,'Pain Relief & Cold Care','3004',36,'Pain relief balm',
    [('25 g','g','25 g','129','109','BPC-BM-PAIN-25',5,5,3,60)],[7038158,7038147,7038152],
    'Fast-acting herbal balm with menthol, camphor and eucalyptus for headaches, body aches and blocked nose.',
    ['Menthol, camphor and eucalyptus','Relief from headache and body ache','Non-staining formula'],
    [('Form','Balm'),('Key ingredients','Menthol, Camphor, Eucalyptus oil')],'Store in a cool, dry place. For external use only.')
add('fa1','Home First Aid Kit (60 Pieces)','SEVO Care',HP,'First Aid','3005',60,'First aid kit',
    [('60 pieces','pack','60 pieces','599','499','BPC-FA-KIT-60',22,15,7,420)],[31852746,5673523,11894049],
    'Compact first aid kit with bandages, gauze, antiseptic wipes, tape, scissors and tweezers in a zip pouch.',
    ['60 essential first aid items','Compact, easy-to-carry pouch','Suitable for home, car and travel'],
    [('Contents','Bandages, Gauze, Wipes, Tape, Scissors, Tweezers'),('Pieces','60')],'Store in a dry place.')
add('th1','Digital Thermometer','SEVO Care',HP,'Health Monitors & Devices','9025',60,'Digital thermometer',
    [('Single','piece','1 piece','299','249','BPC-TH-DIG-1',16,5,3,45)],[5995227,7722669,7722675],
    'Fast and accurate digital thermometer with a flexible tip and large display. Beeps when the reading is ready.',
    ['Reading in about 30 seconds','Large LCD display','Fever alarm and memory recall'],
    [('Type','Digital'),('Range','32 to 42 degrees C'),('Battery','LR41 included')],'Clean the tip with alcohol after use. Store in the case.')
add('po1','Weekly Pill Organizer','SEVO Care',HP,'Elder Care','3926',60,'Pill organizer',
    [('7 days','piece','1 piece','149','129','BPC-PO-WEEK-7',18,6,3,70)],[11349878,12585201,14387794],
    'Seven-day pill organizer with easy-open compartments. Helps remember daily medicines.',
    ['Seven separate day compartments','Easy-open lids, large labels','Compact and portable'],
    [('Compartments','7'),('Material','BPA-free plastic')],'Keep dry. Wash with water only.')

BY='Baby Care'
add('fo1','Infant Formula Stage 1 (0-6 Months)','SEVO Care',BY,'Baby Food & Formula','1901',24,'Infant milk food',
    [('400 g','g','400 g','549','479','BPC-FO-ST1-400',10,10,12,480)],[11501481,10994727],
    'Nutritionally complete infant formula for babies from birth to 6 months when breast milk is not available.',
    ['Contains DHA and prebiotics','No added sugar or artificial flavours','Complete nutrition for 0-6 months'],
    [('Age','0-6 months'),('Net weight','400 g')],'Store in a cool, dry place. Use within 4 weeks of opening.')
add('bw1','Gentle Baby Wash & Shampoo','SEVO Care',BY,'Bath & Hygiene','3401',30,'Baby wash',
    [('200 ml','ml','200 ml','199','175','BPC-BW-BABY-200',5,5,18,250)],[8054407,8015894,8015837],
    'Tear-free, pH-balanced head-to-toe wash for babies. Mild formula with chamomile and aloe.',
    ['Tear-free formula','Dermatologically tested','Free from parabens and dyes'],
    [('Age','0 months and above'),('Key ingredients','Chamomile, Aloe vera')],'Store in a cool, dry place.')
add('on1','Cotton Baby Onesie Set (Pack of 3)','SEVO Care',BY,'Kids Apparel','6111',60,'Baby clothing',
    [('0-3 months','pack','Pack of 3 (0-3 M)','599','499','BPC-ON-SET3-03',25,20,4,180)],[3875082,34121887,4858394],
    'Soft 100% combed-cotton onesies with snap closures. Gentle on newborn skin.',
    ['100% combed cotton','Snap buttons for easy changing','Pack of 3, 0-3 months'],
    [('Material','100% cotton'),('Age','0-3 months'),('Quantity','3 pieces')],'Machine wash cold. Do not bleach.')

# ---------- upload any photo not uploaded yet ----------
need=sorted({i for p in P for i in p['photos']}-set(ph))
for i in need:
    src=f'px2/{i}.jpg'
    im=Image.open(src).convert('RGB'); im.thumbnail((1200,1200)); out=f'px2/up_{i}.jpg'; im.save(out,'JPEG',quality=90)
    r=subprocess.run(['curl','-s','-X','POST','-H','Authorization: Bearer '+tok,'-A','curl/8.4.0','-F',f'image=@{out};type=image/jpeg','https://vendor.sevo.co.in/api/workforce/seller-hub/products/upload-image/'],capture_output=True,text=True)
    ph[i]=json.loads(r.stdout)['image_url']
json.dump(ph,open('backup/uploaded_photos.json','w'))
print('uploaded',len(need),'new photos')

# ---------- create ----------
s,mine=call('GET','products/?page_size=500'); existing={p['sku']:p['id'] for p in mine}
made=json.load(open('backup/created_products.json'))
failed=[]
for p in P:
    group_id=None
    if len(p['variants'])>1:
        s,d=call('POST','variant-groups/',{'group_title':p['title'],'variant_attribute_name':'Size'})
        if s not in (200,201): print('GROUP FAIL',p['title'],s,d); failed.append(p['key']); continue
        group_id=(d.get('group') or d)['id']
    for label,unit,pack,mrp,price,sku,L,W,H,G in p['variants']:
        if sku in existing: print('exists',sku); made.append(existing[sku]); continue
        body=dict(category=leaf(p['cat'],p['leaf']),title=p['title'],brand=p['brand'],unit=unit,pack_size=pack,variant_label=label,mrp=mrp,selling_price=price,
                  hsn_code=p['hsn'],sku=sku,description=p['desc'],storage_info=p['storage'],shelf_life_value=p['shelf'],shelf_life_unit='months',
                  images=[ph[i] for i in p['photos']],specs=[{'label':a,'value':b} for a,b in p['specs']],
                  package_length_cm=L,package_width_cm=W,package_height_cm=H,gross_weight_g=G,generic_name=p['generic'],
                  procurement_price=f"{float(price)*0.62:.2f}",**MFG)
        if group_id: body['variant_group']=group_id
        s,d=call('POST','products/',body)
        if s!=201: print('CREATE FAIL',sku,s,json.dumps(d,ensure_ascii=False)[:300]); failed.append(sku); continue
        made.append(d['product']['id']); print('created',sku,d['product']['id'])
json.dump(sorted(set(made)),open('backup/created_products.json','w'))
print('total created so far',len(set(made)),'failed',failed)
