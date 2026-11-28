import json, time, urllib.request, sys
from websockets.sync.client import connect

DEBUG = 'http://127.0.0.1:9333'

def new_page(url):
    req = urllib.request.Request(DEBUG + '/json/new?' + url, method='PUT')
    with urllib.request.urlopen(req) as r:
        return json.load(r)

class CDP:
    def __init__(self, ws_url):
        self.ws = connect(ws_url, max_size=None)
        self.i = 0
        self.events = []
        self.send('Runtime.enable')
        self.send('Page.enable')
        self.send('Log.enable')
    def send(self, method, params=None, timeout=30):
        self.i += 1
        mid = self.i
        self.ws.send(json.dumps({'id': mid, 'method': method, 'params': params or {}}))
        end = time.time() + timeout
        while time.time() < end:
            msg = json.loads(self.ws.recv(timeout=max(0.1, end - time.time())))
            if msg.get('id') == mid:
                if 'error' in msg:
                    raise RuntimeError(f"{method} error: {msg['error']}")
                return msg.get('result', {})
            self.events.append(msg)
        raise TimeoutError(method)
    def ev(self, expr, timeout=20):
        r = self.send('Runtime.evaluate', {'expression': expr, 'returnByValue': True, 'awaitPromise': True, 'userGesture': True}, timeout=timeout)
        if r.get('exceptionDetails'):
            det = r['exceptionDetails']
            raise RuntimeError('JS exception: ' + json.dumps(det)[:1000])
        return r.get('result', {}).get('value')
    def wait(self, expr, timeout=10, label=None):
        end = time.time() + timeout
        last = None
        while time.time() < end:
            try:
                last = self.ev(expr)
                if last:
                    return last
            except Exception as e:
                last = f'EXC {e}'
            time.sleep(0.05)
        raise TimeoutError(f'wait failed: {label or expr} last={last!r}')
    def errors(self):
        out = []
        for m in self.events:
            if m.get('method') == 'Runtime.exceptionThrown':
                out.append(m['params'].get('exceptionDetails', {}).get('text', 'exception'))
            elif m.get('method') == 'Runtime.consoleAPICalled' and m['params'].get('type') == 'error':
                out.append('console.error: ' + ' '.join(str(a.get('value', a.get('description',''))) for a in m['params'].get('args', [])))
            elif m.get('method') == 'Log.entryAdded' and m['params'].get('entry', {}).get('level') == 'error':
                out.append('log: ' + str(m['params']['entry'].get('text','')))
        return out

def open_app(cdp, url='http://127.0.0.1:8765/index.html?v=r4final'):
    cdp.send('Page.navigate', {'url': url})
    cdp.wait("document.readyState==='complete' && !!window.Proto && !!document.querySelector('.proto-bar')", 15, 'app boot')
    # wait for enhancers
    time.sleep(0.3)

def reload(cdp):
    cdp.send('Page.reload', {'ignoreCache': True})
    cdp.wait("document.readyState==='complete' && !!window.Proto && !!document.querySelector('.proto-bar')", 15, 'app reload')
    time.sleep(0.4)
