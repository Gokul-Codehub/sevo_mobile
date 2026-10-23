import json,urllib.request,urllib.error,time
tok=json.load(open('login_seller.json'))['access_token']
BASE='https://vendor.sevo.co.in/api/workforce/seller-hub/'
def call(method,path,body=None):
    data=json.dumps(body).encode() if body is not None else None
    r=urllib.request.Request(BASE+path,data=data,method=method,headers={'Authorization':'Bearer '+tok,'Content-Type':'application/json','User-Agent':'curl/8.4.0','Accept':'application/json'})
    for attempt in range(6):
        try:
            with urllib.request.urlopen(r,timeout=90) as resp:
                t=resp.read().decode('utf-8'); time.sleep(0.35); d=(json.loads(t) if t else None)
                if method=='GET' and path.startswith('products/') and isinstance(d,list): d={'results':d,'count':len(d)}
                return resp.status,d
        except urllib.error.HTTPError as e:
            t=e.read().decode('utf-8','replace')
            if e.code in (429,502,503,504) and attempt<5: time.sleep(2*(attempt+1)); continue
            try: return e.code,json.loads(t)
            except Exception: return e.code,t
        except (ConnectionError,TimeoutError,OSError):
            time.sleep(2*(attempt+1))
    return 0,'network failure'
