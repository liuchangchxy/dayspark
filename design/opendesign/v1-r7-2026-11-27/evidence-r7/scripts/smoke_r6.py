"""R6 real-interaction smoke test (desktop + phone), printing assertions."""
from pathlib import Path
import asyncio, json, subprocess, time, urllib.request, websockets
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
PORT = 9720
URL = (Path(__file__).resolve().parents[2] / 'dayspark-prototype.html').as_uri()
subprocess.run(['rm', '-rf', f'/tmp/prof-{PORT}'])
p = subprocess.Popen([CHROME, '--headless=new', '--disable-gpu', f'--remote-debugging-port={PORT}',
                      f'--user-data-dir=/tmp/prof-{PORT}', '--window-size=1440,1000', URL],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
u = None
for _ in range(100):
    try:
        d = json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json'))
        pp = [t for t in d if t.get('type') == 'page']
        if pp:
            u = pp[0]['webSocketDebuggerUrl']; break
    except Exception: pass
    time.sleep(.25)

async def main():
    async with websockets.connect(u, max_size=2**27) as ws:
        i = 0; errs = []
        async def call(m, params=None):
            nonlocal i; i += 1; mid = i
            await ws.send(json.dumps({'id': mid, 'method': m, 'params': params or {}}))
            while True:
                x = json.loads(await ws.recv())
                if x.get('method') == 'Runtime.exceptionThrown':
                    errs.append(x['params']['exceptionDetails'].get('text', '') + ' ' + str(x['params']['exceptionDetails'].get('exception', {}).get('description', ''))[:120])
                if x.get('id') == mid: return x
        async def ev(e):
            r = await call('Runtime.evaluate', {'expression': e, 'returnByValue': True})
            q = r.get('result', {})
            if q.get('exceptionDetails'):
                print('JSERR', q['exceptionDetails'].get('exception', {}).get('description', '')[:160])
            return q.get('result', {}).get('value')
        async def ok(name, expr):
            v = await ev(expr)
            print(('PASS' if v else 'FAIL'), name, '=>', v)
            return v
        await call('Runtime.enable'); await call('Page.enable'); await asyncio.sleep(1.6)
        await ev("try{localStorage.removeItem('dayspark.prototype.v1')}catch(e){}")
        await call('Page.navigate', {'url': URL}); await asyncio.sleep(1.6)
        print('--- desktop ---')
        await ok('today heading', "document.querySelector('.ph-title').textContent.trim()==='11 月 20 日'")
        await ok('nav -> 待办', "(()=>{const b=[...document.querySelectorAll('.p-nav button')].find(x=>x.textContent.trim()==='待办');b&&b.click();return state.screen})()")
        await asyncio.sleep(.4)
        await ok('todos list rendered', "document.querySelectorAll('.todo-row').length>0")
        await ok('open first todo drawer', "(()=>{const r=document.querySelector('.todo-row');r&&r.click();return state.drawer&&state.drawer.type})()")
        await asyncio.sleep(.4)
        await ok('drawer title non-empty', "!!(document.querySelector('.drawer .d-title')||{}).textContent")
        await ok('close drawer', "(()=>{const b=document.querySelector('.drawer-close');b&&b.click();return !state.drawer})()")
        await asyncio.sleep(.3)
        await ok('nav -> 日历', "(()=>{const b=[...document.querySelectorAll('.p-nav button')].find(x=>x.textContent.trim()==='日历');b&&b.click();return state.screen})()")
        await asyncio.sleep(.4)
        await ok('switch to 月', "(()=>{const b=[...document.querySelectorAll('.view-switch button, .mode-switch button')].find(x=>x.textContent.trim()==='月');b&&b.click();return state.screen})()")
        await asyncio.sleep(.4)
        await ok('month grid cells', "document.querySelectorAll('.mcell').length>=35")
        await ok('switch to 周', "(()=>{const b=[...document.querySelectorAll('.view-switch button, .mode-switch button')].find(x=>x.textContent.trim()==='周');b&&b.click();return state.screen})()")
        await asyncio.sleep(.4)
        await ok('week columns', "document.querySelectorAll('.day-col').length===7")
        await ok('back to 今天', "(()=>{const b=[...document.querySelectorAll('.p-nav button')].find(x=>x.textContent.trim()==='今天');b&&b.click();return state.screen})()")
        await asyncio.sleep(.4)
        await ok('capture add via send', """(()=>{
          const inp=document.querySelector('.cap-input'); if(!inp)return 'noinput';
          inp.value='R6 验收 · 买电池'; inp.dispatchEvent(new Event('input',{bubbles:true}));
          const before=allTodos().length;
          inp.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true,cancelable:true}));
          return allTodos().length>before && allTodos().some(t=>t.title.includes('买电池'));
        })()""")
        await asyncio.sleep(.5)
        print('--- phone ---')
        await call('Emulation.setDeviceMetricsOverride', {'width': 390, 'height': 844, 'deviceScaleFactor': 1, 'mobile': True, 'screenWidth': 390, 'screenHeight': 844})
        await call('Page.navigate', {'url': URL}); await asyncio.sleep(1.6)
        await ok('phone today title', "document.querySelector('.m-date').textContent.includes('11 月 20 日')")
        await ok('dock -> 待办', "(()=>{const b=[...document.querySelectorAll('.m-dock button')].find(x=>x.textContent.includes('待办'));b&&b.click();return state.screen})()")
        await asyncio.sleep(.4)
        await ok('phone task rows', "document.querySelectorAll('.task-row').length>0")
        await ok('open phone detail', "(()=>{const r=document.querySelector('.task-row');r&&r.click();return !!(state.drawer&&state.drawer.type==='todo')})()")
        await asyncio.sleep(.4)
        await ok('phone detail title input', "!!document.querySelector('input[data-mfield=title]')")
        await ok('phone back', "(()=>{const b=document.querySelector('.m-back');b&&b.click();return state.screen})()")
        await asyncio.sleep(.3)
        await ok('dock -> 日历', "(()=>{const b=[...document.querySelectorAll('.m-dock button')].find(x=>x.textContent.includes('日历'));b&&b.click();return state.screen})()")
        await asyncio.sleep(.4)
        await ok('phone day blocks', "document.querySelectorAll('.m-block').length>0")
        await ok('dock -> 我的', "(()=>{const b=[...document.querySelectorAll('.m-dock button')].find(x=>x.textContent.includes('我的'));b&&b.click();return state.screen})()")
        await asyncio.sleep(.4)
        await ok('settings groups', "document.querySelectorAll('.m-settings-group').length===6")
        print('console exceptions:', errs[:6])
    p.terminate()

asyncio.run(main())
