import json,sys
from api_seller import call

cats=json.load(open('backup/created_categories.json'))
ph={int(k):v for k,v in json.load(open('backup/uploaded_photos.json')).items()}
P='bpc-bath-body-and-oral-care-'
LEAF={'bw':cats[P+'bathing-bars-and-body-wash'],'hw':cats[P+'handwash-and-sanitizers'],'tp':cats[P+'toothpaste-and-mouthwash'],
      'tb':cats[P+'toothbrushes'],'fl':cats[P+'floss-and-tongue-cleaners'],'ba':cats[P+'bathing-accessories'],'sc':cats[P+'body-scrubs-and-exfoliants']}
MFG=dict(country_of_origin='IN',manufacturer_name='SEVO Consumer Care Pvt Ltd',manufacturer_address='SIPCOT Industrial Park, Hosur, Tamil Nadu',manufacturer_pincode='635109')

# (key, title, brand, leaf, hsn, shelf_months, [(label,unit,pack,mrp,price,sku)], photos, description_html, specs, storage)
PRODUCTS=[
 ('bw1','Aloe & Cucumber Body Wash','SEVO Care','bw','3401',24,
  [('250 ml','ml','250 ml','199','175','BPC-BW-ALOE-250'),('500 ml','ml','500 ml','349','299','BPC-BW-ALOE-500')],
  [8015698,8015784,8015781],
  '<p>A gentle, pH-balanced body wash enriched with aloe vera and cucumber extract. Creates a rich lather that cleans without stripping natural moisture.</p><ul><li>Soap-free, skin-friendly formula</li><li>Aloe vera and cucumber for a cool, fresh feel</li><li>Pump bottle for easy dispensing</li></ul>',
  [('Skin type','All skin types'),('Key ingredients','Aloe vera, Cucumber extract'),('Form','Liquid body wash'),('Fragrance','Fresh cucumber')],
  'Store in a cool, dry place. Keep the pump closed after use.'),
 ('bw2','Sandalwood Shower Gel','Nilgiri Botanics','bw','3401',24,
  [('250 ml','ml','250 ml','249','219','BPC-BW-SAND-250')],
  [7814719,32420129,8015781],
  '<p>A creamy shower gel with the warm, woody fragrance of sandalwood. Leaves skin soft, smooth and lightly scented.</p><ul><li>Rich, creamy lather</li><li>Sandalwood and almond oil blend</li><li>Dermatologically tested</li></ul>',
  [('Skin type','Normal to dry'),('Key ingredients','Sandalwood, Almond oil'),('Form','Shower gel'),('Fragrance','Sandalwood')],
  'Store below 30 degrees C. Keep away from direct sunlight.'),
 ('hw1','Lemon Liquid Hand Wash','SEVO Care','hw','3401',24,
  [('250 ml','ml','250 ml','99','89','BPC-HW-LEMON-250'),('500 ml','ml','500 ml','175','155','BPC-HW-LEMON-500')],
  [13516802,433624,8217476],
  '<p>Everyday liquid hand wash with lemon extract. Removes dirt and germs while keeping hands soft.</p><ul><li>Kills 99.9% of common germs*</li><li>Lemon fragrance, mild on skin</li><li>Easy pump dispenser</li></ul><p><small>*On hands when used as directed.</small></p>',
  [('Form','Liquid hand wash'),('Fragrance','Lemon'),('Suitable for','Whole family')],
  'Store in a cool, dry place.'),
 ('hw2','Neem Foaming Hand Wash','Kaveri Herbals','hw','3401',24,
  [('200 ml','ml','200 ml','129','115','BPC-HW-NEEM-200')],
  [4008464,13516802,8217476],
  '<p>Foaming hand wash with neem and tulsi. A little goes a long way: pump once for a soft, rich foam that rinses clean.</p><ul><li>Neem and tulsi extracts</li><li>Instant foam, less water used</li><li>Gentle for daily use</li></ul>',
  [('Form','Foaming hand wash'),('Key ingredients','Neem, Tulsi'),('Fragrance','Herbal')],
  'Store in a cool, dry place. Do not dilute.'),
 ('tp1','Fresh Mint Toothpaste','SEVO Care','tp','3306',36,
  [('100 g','g','100 g','75','68','BPC-TP-MINT-100'),('200 g','g','200 g','135','120','BPC-TP-MINT-200')],
  [12065623,216729,15694671],
  '<p>Everyday fluoride toothpaste with natural mint oil. Helps fight cavities, freshens breath and leaves teeth feeling clean for hours.</p><ul><li>Fluoride protection for strong enamel</li><li>Natural mint oil for long-lasting freshness</li><li>Suitable for the whole family</li></ul>',
  [('Type','Fluoride toothpaste'),('Flavour','Mint'),('Suitable for','Adults and children above 6 years')],
  'Store in a cool, dry place away from direct sunlight. Keep the cap closed.'),
 ('tp2','Charcoal & Clove Toothpaste','Kaveri Herbals','tp','3306',36,
  [('150 g','g','150 g','115','99','BPC-TP-CHAR-150')],
  [216729,12065623,15694671],
  '<p>Herbal toothpaste with activated charcoal and clove oil. Gently removes surface stains and soothes gums.</p><ul><li>Activated charcoal for whiter-looking teeth</li><li>Clove oil for fresh, tingling breath</li><li>Fluoride-free herbal formula</li></ul>',
  [('Type','Herbal toothpaste'),('Key ingredients','Activated charcoal, Clove oil'),('Fluoride','Free')],
  'Store in a cool, dry place.'),
 ('tp3','Alcohol-Free Mouthwash','SEVO Care','tp','3306',36,
  [('250 ml','ml','250 ml','145','129','BPC-MW-FRESH-250'),('500 ml','ml','500 ml','260','229','BPC-MW-FRESH-500')],
  [30551803,30551804],
  '<p>Alcohol-free antibacterial mouthwash for all-day fresh breath. Gentle on gums, with a cool mint taste.</p><ul><li>Alcohol-free, no burning sensation</li><li>Helps reduce plaque and bad-breath germs</li><li>Use twice daily after brushing</li></ul>',
  [('Type','Antibacterial mouthwash'),('Flavour','Cool mint'),('Alcohol','Free')],
  'Store in a cool, dry place. Not for swallowing; keep out of reach of children.'),
 ('tb1','Soft Bristle Toothbrush (Pack of 4)','SEVO Care','tb','9603',60,
  [('Pack of 4','pack','Pack of 4','120','99','BPC-TB-SOFT-4')],
  [4045554,13466251,4045552],
  '<p>Family pack of four soft-bristle toothbrushes in assorted colours. Ergonomic grip and rounded bristles for gentle, thorough cleaning.</p><ul><li>Soft rounded bristles, gentle on gums</li><li>Non-slip ergonomic handle</li><li>Assorted colours so everyone knows theirs</li></ul>',
  [('Bristle type','Soft'),('Quantity','4 toothbrushes'),('Handle','Ergonomic, non-slip')],
  'Rinse after use and store upright to air dry.'),
 ('tb2','Bamboo Toothbrush (Pack of 2)','Nilgiri Botanics','tb','9603',60,
  [('Pack of 2','pack','Pack of 2','149','129','BPC-TB-BAMB-2')],
  [7055289,7055278,6932597],
  '<p>Plastic-free bamboo toothbrushes with soft, charcoal-infused bristles. A biodegradable handle that feels natural in the hand.</p><ul><li>Sustainably sourced bamboo handle</li><li>Soft charcoal-infused bristles</li><li>Pack of 2</li></ul>',
  [('Bristle type','Soft'),('Handle material','Bamboo'),('Quantity','2 toothbrushes')],
  'Keep dry between uses; store upright.'),
 ('fl1','Mint Waxed Dental Floss','SEVO Care','fl','3306',36,
  [('50 m','piece','50 m','99','85','BPC-FL-MINT-50')],
  [30551803,30551804,5240333],
  '<p>Smooth waxed dental floss that glides easily between tight teeth to remove plaque and food particles. Light mint flavour.</p><ul><li>Shred-resistant waxed thread</li><li>50 m, enough for months of daily use</li><li>Compact dispenser with cutter</li></ul>',
  [('Length','50 m'),('Type','Waxed floss'),('Flavour','Mint')],
  'Store in a dry place.'),
 ('ba1','Natural Loofah Sponge (Pack of 2)','Nilgiri Botanics','ba','9603',60,
  [('Pack of 2','pack','Pack of 2','149','129','BPC-BA-LOOF-2')],
  [7262747,18516673],
  '<p>100% natural loofah sponges for gentle exfoliation in the bath. Soften in warm water, lather up and scrub away dead skin.</p><ul><li>Natural plant fibre, biodegradable</li><li>Gentle exfoliation for a smoother feel</li><li>Pack of 2</li></ul>',
  [('Material','Natural loofah fibre'),('Quantity','2 sponges'),('Use','Bath and shower')],
  'Rinse and hang to dry after each use.'),
 ('sc1','Coffee & Walnut Body Scrub','Kaveri Herbals','sc','3304',24,
  [('200 g','g','200 g','349','299','BPC-SC-COFF-200')],
  [27860845,6418017],
  '<p>Invigorating body scrub with ground coffee and walnut shell granules. Buffs away dead skin and leaves it smooth and glowing.</p><ul><li>Coffee and walnut exfoliating granules</li><li>Enriched with coconut oil for softness</li><li>Use 2-3 times a week</li></ul>',
  [('Type','Body scrub'),('Key ingredients','Coffee, Walnut shell, Coconut oil'),('Skin type','All skin types')],
  'Store in a cool, dry place. Keep water out of the jar.'),
]

created=json.load(open('backup/created_products.json')) if True else []
existing={}
s,mine=call('GET','products/?page_size=500')
for p in mine: existing[p['sku']]=p['id']

out={}
for key,title,brand,leaf,hsn,shelf,variants,photos,desc,specs,storage in PRODUCTS:
    group_id=None
    if len(variants)>1:
        s,d=call('POST','variant-groups/',{'group_title':title,'variant_attribute_name':'Size'})
        if s not in (200,201): print('GROUP FAIL',title,s,d); sys.exit(1)
        group_id=(d.get('group') or d).get('id') if isinstance(d,dict) else None
        if not group_id: print('no group id',d); sys.exit(1)
    ids=[]
    for label,unit,pack,mrp,price,sku in variants:
        if sku in existing:
            pid=existing[sku]
            if group_id:
                s,d=call('PATCH',f'products/{pid}/',{'variant_group':group_id,'variant_label':label})
                if s!=200: print('LINK FAIL',sku,s,d); sys.exit(1)
            ids.append(pid); print('exists',sku,pid); continue
        body=dict(category=LEAF[leaf],title=title,brand=brand,unit=unit,pack_size=pack,variant_label=label,mrp=mrp,selling_price=price,
                  hsn_code=hsn,sku=sku,description=desc,storage_info=storage,shelf_life_value=shelf,shelf_life_unit='months',
                  images=[ph[i] for i in photos],specs=[{'label':a,'value':b} for a,b in specs],**MFG)
        if group_id: body['variant_group']=group_id
        s,d=call('POST','products/',body)
        if s!=201: print('CREATE FAIL',sku,s,json.dumps(d,ensure_ascii=False)[:500]); sys.exit(1)
        pid=d['product']['id']; ids.append(pid); print('created',sku,pid)
    out[key]=ids
allids=sorted({i for v in out.values() for i in v})
json.dump(allids,open('backup/created_products.json','w'))
print('products in pilot:',len(allids))
