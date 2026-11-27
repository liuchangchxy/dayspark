"""Final R6 evidence shots against the built package (or the R4 baseline).

usage: python3 final_shots.py <port> <outdir> <file-url> <mode:r6|r4>
"""
import asyncio, json, subprocess, time, urllib.request, base64, os, sys, websockets

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
PORT = int(sys.argv[1]); OUT = sys.argv[2]; URL = sys.argv[3]; MODE = sys.argv[4]
subprocess.run(['rm', '-rf', f'/tmp/prof-{PORT}'])
p = subprocess.Popen([CHROME, '--headless=new', '--disable-gpu', f'--remote-debugging-port={PORT}',
                      f'--user-data-dir=/tmp/prof-{PORT}', '--window-size=1440,1000', URL],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
u = None
for _ in range(100):
    try:
        d = json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json'))
        pp = [t for t in d if t.get('type') == 'page']
        if pp: u = pp[0]['webSocketDebuggerUrl']; break
    except Exception: pass
    time.sleep(.25)

async def main():
    async with websockets.connect(u, max_size=2**26) as ws:
        i = 0; errs = []
        async def call(m, params=None):
            nonlocal i; i += 1; mid = i
            await ws.send(json.dumps({'id': mid, 'method': m, 'params': params or {}}))
            while True:
                x = json.loads(await ws.recv())
                if x.get('method') == 'Runtime.exceptionThrown':
                    errs.append(x.get('params', {}).get('exceptionDetails', {}).get('exception', {}).get('description', ''))
                if x.get('id') == mid: return x
        async def ev(expr):
            r = await call('Runtime.evaluate', {'expression': expr, 'returnByValue': True})
            q = r.get('result', {})
            if q.get('exceptionDetails'):
                print('ERR', q['exceptionDetails'].get('exception', {}).get('description', '')[:120])
            return q.get('result', {}).get('value')
        async def shot(name, w, h, screen, extra="", theme='light', reload=False):
            if reload:
                await call('Page.navigate', {'url': URL}); await asyncio.sleep(1.6)
            await call('Emulation.clearDeviceMetricsOverride')
            await call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h, 'deviceScaleFactor': 1,
                                                              'mobile': w < 700, 'screenWidth': w, 'screenHeight': h})
            await asyncio.sleep(.3)
            if MODE == 'r6':
                await ev(f"state.capture='compact';state.variant='normal';state.cmdQuery='';try{{Proto.forcedDevice=null}}catch(e){{}}")
            await ev(f"Proto.data.prefs.theme='{theme}';document.body.dataset.protoTheme='{theme}';state.device='{'mobile' if w<700 else 'desktop'}';state.screen='{screen}';state.drawer=null;state.capture='compact';{extra}render();Proto.enhance();document.querySelector('.proto-bar').style.display='none';'ok'")
            await asyncio.sleep(1.0)
            r = await call('Page.captureScreenshot', {'format': 'png'})
            open(os.path.join(OUT, name), 'wb').write(base64.b64decode(r['result']['data']))
            print('shot', name, await ev('innerWidth'), await ev("document.body.dataset.protoTheme"), 'errs', len(errs))
        await call('Runtime.enable'); await call('Page.enable'); await asyncio.sleep(1.5)
        os.makedirs(OUT, exist_ok=True)
        if MODE == 'r6':
            await shot('d-today.png', 1440, 1000, 'today', reload=True)
            await shot('d-todos.png', 1440, 1000, 'todo-all')
            await shot('d-todo-inbox.png', 1440, 1000, 'todo-inbox')
            await shot('d-todo-date.png', 1440, 1000, 'todo-date')
            await shot('d-month.png', 1440, 1000, 'cal-month')
            await shot('d-week.png', 1440, 1000, 'cal-week')
            await shot('d-day.png', 1440, 1000, 'cal-day')
            await shot('d-settings.png', 1440, 1000, 'settings-home')
            await shot('d-settings-data.png', 1440, 1000, 'settings-data')
            await shot('d-detail.png', 1440, 1000, 'today', "state.drawer={type:'todo',id:'report'};")
            await shot('d-event-detail.png', 1440, 1000, 'cal-day', "state.drawer={type:'event',id:'dentist'};")
            await shot('d-capture.png', 1440, 1000, 'capture', "state.capture='parsed';")
            await shot('d-capture-expanded.png', 1440, 1000, 'capture', "state.capture='expanded';")
            await shot('d-search.png', 1440, 1000, 'command', "state.cmdQuery='周报';")
            await shot('d-new.png', 1440, 1000, 'new-todo')
            await shot('d-widgets.png', 1440, 1000, 'widgets')
            await shot('d-ai.png', 1440, 1000, 'ai-chat')
            await shot('t-today.png', 1024, 768, 'today')
            await shot('t-todos.png', 1024, 768, 'todo-all')
            await shot('t-week.png', 1024, 768, 'cal-week')
            await shot('t-detail.png', 1024, 768, 'today', "state.drawer={type:'todo',id:'report'};")
            await shot('n-today-768.png', 768, 900, 'today')
            await shot('n-cal-768.png', 768, 900, 'cal-week')
            await shot('n-detail-768.png', 768, 900, 'today', "state.drawer={type:'todo',id:'report'};")
            await shot('m-today.png', 390, 844, 'today', reload=True)
            await shot('m-todo.png', 390, 844, 'todo-inbox')
            await shot('m-todo-all.png', 390, 844, 'todo-all')
            await shot('m-date.png', 390, 844, 'todo-date')
            await shot('m-cal.png', 390, 844, 'cal-day')
            await shot('m-cal-month.png', 390, 844, 'cal-month')
            await shot('m-week.png', 390, 844, 'cal-week')
            await shot('m-settings.png', 390, 844, 'settings-home')
            await shot('m-detail.png', 390, 844, 'today', "state.drawer={type:'todo',id:'report'};")
            await shot('m-event-detail.png', 390, 844, 'cal-day', "state.drawer={type:'event',id:'dentist'};")
            await shot('m-capture.png', 390, 844, 'capture', "state.capture='parsed';")
            await shot('m-search.png', 390, 844, 'command', "state.cmdQuery='周报';")
            await shot('m-new.png', 390, 844, 'new-todo')
            await shot('m-widgets.png', 390, 844, 'widgets')
            await shot('m-ai.png', 390, 844, 'ai-chat')
            await shot('d-warm-today.png', 1440, 1000, 'today', theme='warm')
            await shot('m-warm-today.png', 390, 844, 'today', theme='warm')
            await shot('d-dark-today.png', 1440, 1000, 'today', theme='dark')
            await shot('d-dark-todos.png', 1440, 1000, 'todo-all', theme='dark')
            await shot('d-dark-month.png', 1440, 1000, 'cal-month', theme='dark')
            await shot('d-dark-week.png', 1440, 1000, 'cal-week', theme='dark')
            await shot('d-dark-settings.png', 1440, 1000, 'settings-home', theme='dark')
            await shot('d-dark-detail.png', 1440, 1000, 'today', "state.drawer={type:'todo',id:'report'};", theme='dark')
            await shot('m-dark-today.png', 390, 844, 'today', theme='dark')
            await shot('m-dark-cal.png', 390, 844, 'cal-day', theme='dark')
            await shot('m-dark-settings.png', 390, 844, 'settings-home', theme='dark')
            await shot('m-dark-detail.png', 390, 844, 'today', "state.drawer={type:'todo',id:'report'};", theme='dark')
        else:
            await shot('d-today.png', 1440, 1000, 'today', reload=True)
            await shot('d-todos.png', 1440, 1000, 'todo-all')
            await shot('d-month.png', 1440, 1000, 'cal-month')
            await shot('d-week.png', 1440, 1000, 'cal-week')
            await shot('d-settings.png', 1440, 1000, 'settings-home')
            await shot('d-detail.png', 1440, 1000, 'today', "state.drawer={type:'todo',id:'report'};")
            await shot('d-dark-today.png', 1440, 1000, 'today', theme='dark')
            await shot('d-dark-month.png', 1440, 1000, 'cal-month', theme='dark')
            await shot('m-today.png', 390, 844, 'today', reload=True)
            await shot('m-cal.png', 390, 844, 'cal-day')
            await shot('m-settings.png', 390, 844, 'settings-home')
            await shot('m-detail.png', 390, 844, 'today', "state.drawer={type:'todo',id:'report'};")
            await shot('m-dark-today.png', 390, 844, 'today', theme='dark')
        print('errors', errs[:5])
    p.terminate()

asyncio.run(main())
