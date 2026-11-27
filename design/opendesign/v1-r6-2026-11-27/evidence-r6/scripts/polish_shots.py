"""Render current prototype across viewports and themes."""
from pathlib import Path
import asyncio, json, subprocess, time, urllib.request, base64
import websockets

HERE = Path(__file__).resolve()
OUT = HERE.parents[1] / 'screens'
URL = (HERE.parents[2] / 'dayspark-prototype.html').as_uri()
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
PORT = 9750
OUT.mkdir(parents=True, exist_ok=True)

subprocess.run(['rm', '-rf', f'/tmp/prof-{PORT}'])
p = subprocess.Popen([CHROME, '--headless=new', '--disable-gpu', f'--remote-debugging-port={PORT}',
                      f'--user-data-dir=/tmp/prof-{PORT}', '--window-size=1440,1000', URL],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
u = None
for _ in range(120):
    try:
        d = json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json'))
        pp = [t for t in d if t.get('type') == 'page']
        if pp:
            u = pp[0]['webSocketDebuggerUrl']; break
    except Exception:
        pass
    time.sleep(.25)

async def main():
    async with websockets.connect(u, max_size=2**28) as ws:
        i = 0
        async def call(m, params=None):
            nonlocal i
            i += 1; mid = i
            await ws.send(json.dumps({'id': mid, 'method': m, 'params': params or {}}))
            while True:
                x = json.loads(await ws.recv())
                if x.get('id') == mid:
                    return x
        async def ev(expr):
            r = await call('Runtime.evaluate', {'expression': expr, 'returnByValue': True})
            q = r.get('result', {})
            if q.get('exceptionDetails'):
                print('ERR', q['exceptionDetails'].get('exception', {}).get('description', '')[:160])
            return q.get('result', {}).get('value')
        async def shot(name):
            await asyncio.sleep(.5)
            r = await call('Page.captureScreenshot', {'format': 'png'})
            (OUT / name).write_bytes(base64.b64decode(r['result']['data']))
            print('shot', name)
        async def theme(t):
            await ev("Proto.data.prefs.theme='" + t + "';document.body.dataset.protoTheme='" + t + "';'x'")
            await asyncio.sleep(.3)
        async def view(w, h, mobile=False, scale=2):
            await call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h, 'deviceScaleFactor': scale, 'mobile': mobile})
            await asyncio.sleep(.5)
        async def reload():
            await call('Page.navigate', {'url': URL}); await asyncio.sleep(1.5)

        await call('Runtime.enable'); await call('Page.enable')
        await asyncio.sleep(1.6)
        await reload()

        # inject a multi-segment plan for the extreme-content pass
        await ev("""(function(){var t=todoById('report');
          DS3.addAllocation(t,{date:'2026-11-20',start:'09:00',end:'09:45',occurrenceDate:null});
          DS3.addAllocation(t,{date:'2026-11-20',start:'19:00',end:'20:00',occurrenceDate:null});})();'x'""")

        for t in ['light', 'warm', 'dark']:
            await theme(t)
            await ev("state.screen='today';state.variant='normal';state.drawer=null;render();Proto.enhance();'x'")
            await ev("document.querySelectorAll('.cal-main').forEach(function(m){m.scrollTop=360});'x'")
            await shot(f'polish-d-today-{t}.png')
            await ev("state.screen='todo-date';state.variant='normal';render();Proto.enhance();'x'")
            await shot(f'polish-d-date-{t}.png')
            await ev("state.screen='cal-week';state.variant='normal';render();Proto.enhance();'x'")
            await shot(f'polish-d-week-{t}.png')
            await ev("state.screen='cal-month';state.variant='normal';render();Proto.enhance();'x'")
            await shot(f'polish-d-month-{t}.png')
            await ev("state.screen='settings-home';state.variant='normal';render();Proto.enhance();'x'")
            await shot(f'polish-d-settings-{t}.png')

        await theme('light')
        await view(390, 844, True)
        await reload()
        await theme('light')
        await ev("state.screen='today';state.variant='normal';render();Proto.enhance();'x'")
        await shot('polish-m-today-light.png')
        await ev("state.screen='cal-day';state.variant='normal';state.selectedDate='2026-11-20';render();Proto.enhance();'x'")
        await shot('polish-m-day-light.png')
        await ev("state.screen='todo-date';state.variant='normal';render();Proto.enhance();'x'")
        await shot('polish-m-date-light.png')
        await ev("state.screen='detail-todo';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.3)
        await ev("document.querySelector('.m-detail-scroll').scrollTop=460;'x'")
        await shot('polish-m-detail-light.png')
        await theme('dark')
        await ev("state.screen='today';state.variant='normal';render();Proto.enhance();'x'")
        await shot('polish-m-today-dark.png')
        await ev("state.screen='cal-day';state.variant='normal';render();Proto.enhance();'x'")
        await shot('polish-m-day-dark.png')
        await ev("state.screen='detail-todo';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.3)
        await ev("document.querySelector('.m-detail-scroll').scrollTop=420;'x'")
        await shot('polish-m-detail-dark.png')

        # narrow phone + tablet + wide desktop
        await theme('light')
        await view(360, 780, True)
        await ev("state.screen='today';state.variant='normal';state.device='mobile';render();Proto.enhance();'x'")
        await shot('polish-360-today.png')
        await view(768, 1024, True)
        await ev("state.screen='cal-week';state.variant='normal';state.device='mobile';render();Proto.enhance();'x'")
        await shot('polish-768-week.png')
        await view(1920, 1080, False, 1)
        await ev("state.screen='today';state.variant='normal';state.device='desktop';render();Proto.enhance();'x'")
        await shot('polish-1920-today.png')

        await call('Emulation.clearDeviceMetricsOverride')
    p.terminate()

asyncio.run(main())
