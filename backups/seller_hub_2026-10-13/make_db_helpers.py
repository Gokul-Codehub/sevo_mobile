import json, urllib.request, urllib.error, time
import api
W = 'https://vendor.sevo.co.in/api/workforce/'
def adm(method, path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    r = urllib.request.Request(W + path, data=data, method=method, headers={'Authorization': 'Bearer ' + api.tok, 'Content-Type': 'application/json', 'User-Agent': 'curl/8.4.0', 'Accept': 'application/json'})
    for a in range(6):
        try:
            with urllib.request.urlopen(r, timeout=90) as resp:
                t = resp.read().decode('utf-8'); time.sleep(0.4); return resp.status, (json.loads(t) if t else None)
        except urllib.error.HTTPError as e:
            t = e.read().decode('utf-8', 'replace')
            if e.code in (429, 502, 503, 504) and a < 5: time.sleep(2 * (a + 1)); continue
            try: return e.code, json.loads(t)
            except Exception: return e.code, t
        except (ConnectionError, TimeoutError, OSError): time.sleep(2 * (a + 1))
    return 0, 'network failure'
