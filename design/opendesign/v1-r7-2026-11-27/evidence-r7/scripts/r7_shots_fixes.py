"""R7 follow-up visual pass: every screen this round changed, all themes.

Screens: create entry (desktop + phone × 3 pages), the slot pair, the repeat
picker, the hide-completed filter row, the snooze card. Writes to
evidence-r7/screens-fixes/ and verifies the theme actually applied by sampling
body luminance.
"""
import asyncio, json, subprocess, time, urllib.request, base64, os, pathlib, websockets
from PIL import Image

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
HERE = pathlib.Path(__file__).resolve().parents[2]
URL = (HERE / 'dayspark-prototype.html').as_uri()
OUT = HERE / 'evidence-r7' / 'screens-fixes'
PORT = 9701
subprocess.run(['rm', '-rf', f'/tmp/prof-{PORT}'])
OUT.mkdir(parents=True, exist_ok=True)
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

MISMATCH = []

async def main():
    async with websockets.connect(u, max_size=2**27) as ws:
        i = 0; errs = []
        async def call(m, params=None):
            nonlocal i; i += 1; mid = i
            await ws.send(json.dumps({'id': mid, 'method': m, 'params': params or {}}))
            while True:
                x = json.loads(await ws.recv())
                if x.get('exceptionDetails') or x.get('method') == 'Runtime.exceptionThrown':
                    pass
                if x.get('method') == 'Runtime.exceptionThrown':
                    errs.append(str(x['params']['exceptionDetails'].get('exception', {}).get('description', ''))[:120])
                if x.get('id') == mid: return x
        async def ev(expr):
            r = await call('Runtime.evaluate', {'expression': expr, 'returnByValue': True})
            q = r.get('result', {})
            if q.get('exceptionDetails'): print('ERR', (q['exceptionDetails'].get('exception') or {}).get('description', '')[:120])
            return q.get('result', {}).get('value')
        async def shot(name, w, h, screen, extra="", theme='light'):
            await call('Emulation.clearDeviceMetricsOverride')
            await call('Emulation.setDeviceMetricsOverride', {'width': w, 'height': h, 'deviceScaleFactor': 1,
                       'mobile': w < 700, 'screenWidth': w, 'screenHeight': h})
            await asyncio.sleep(.3)
            await ev(f"try{{Proto.forcedDevice=null}}catch(e){{}};Proto.data.prefs.theme='{theme}';document.body.dataset.protoTheme='{theme}';state.device='{'mobile' if w < 700 else 'desktop'}';state.screen='{screen}';state.drawer=null;state.drawerEdit=false;state.capture='compact';state.variant='normal';{extra}render();Proto.enhance();'ok'")
            await asyncio.sleep(.85)
            r = await call('Page.captureScreenshot', {'format': 'png'})
            path = OUT / name
            path.write_bytes(base64.b64decode(r['result']['data']))
            im = Image.open(path).convert('L')
            px = list(im.resize((40, 40)).getdata())
            lum = sum(px) / len(px)
            dark = lum < 110
            ok = dark if theme == 'dark' else not dark
            if not ok: MISMATCH.append(name)
            print('shot', name, 'lum', round(lum, 1), 'theme', theme)
        await call('Runtime.enable'); await call('Page.enable'); await asyncio.sleep(1.6)
        await ev("try{localStorage.removeItem('dayspark.prototype.v1')}catch(e){}")
        await call('Page.navigate', {'url': URL}); await asyncio.sleep(1.6)

        for theme in ('light', 'dark'):
            await shot(f'd-today-{theme}.png', 1440, 1000, 'today', theme=theme)
            await shot(f'd-todo-{theme}.png', 1440, 1000, 'todo-all', theme=theme)
            await shot(f'd-cal-week-{theme}.png', 1440, 1000, 'cal-week', "state.selectedDate='2026-11-20';", theme=theme)
            await shot(f'm-today-{theme}.png', 390, 844, 'today', theme=theme)
            await shot(f'm-todo-{theme}.png', 390, 844, 'todo-all', theme=theme)
            await shot(f'm-cal-{theme}.png', 390, 844, 'cal-week', "state.selectedDate='2026-11-20';", theme=theme)

        # the create sheet itself (both device widths)
        for w, h, tag in ((1440, 1000, 'd'), (390, 844, 'm')):
            await shot(f'{tag}-newsheet-open-light.png', w, h, 'today')
            await ev("document.querySelector('[data-proto-action=\"new-pick\"]').click();'ok'")
            await asyncio.sleep(.5)
            r = await call('Page.captureScreenshot', {'format': 'png'})
            (OUT / f'{tag}-newsheet-light.png').write_bytes(base64.b64decode(r['result']['data']))
            await ev("(function(){var a=[...document.querySelectorAll('.proto-modal-scrim')];a.forEach(x=>x.remove());})();'ok'")

        # slot pair + event dialog + plan picker
        await shot('d-slot-pair.png', 1440, 1000, 'cal-week', "state.selectedDate='2026-11-20';")
        await ev("""(function(){
          var col=[...document.querySelectorAll('.week-cols .day-col')].find(c=>c.dataset.date==='2026-11-19');
          var r=col.getBoundingClientRect();
          col.dispatchEvent(new MouseEvent('click',{bubbles:true,clientX:r.left+20,clientY:r.top+9*54+2}));
        })()""")
        await asyncio.sleep(.5)
        r = await call('Page.captureScreenshot', {'format': 'png'})
        (OUT / 'd-slot-sheet.png').write_bytes(base64.b64decode(r['result']['data']))
        await ev("(function(){var b=[...document.querySelectorAll('[data-slot=event]')][0];b.click();})()")
        await asyncio.sleep(.45)
        r = await call('Page.captureScreenshot', {'format': 'png'})
        (OUT / 'd-slot-event.png').write_bytes(base64.b64decode(r['result']['data']))
        await ev("(function(){var a=[...document.querySelectorAll('.proto-modal-scrim')];a.forEach(x=>x.remove());})();'ok'")

        await shot('d-plan-picker.png', 1440, 1000, 'cal-week', "state.selectedDate='2026-11-20';")
        await ev("""(function(){
          var col=[...document.querySelectorAll('.week-cols .day-col')].find(c=>c.dataset.date==='2026-11-19');
          var r=col.getBoundingClientRect();
          col.dispatchEvent(new MouseEvent('click',{bubbles:true,clientX:r.left+20,clientY:r.top+9*54+2}));
        })()""")
        await asyncio.sleep(.4)
        await ev("(function(){var b=[...document.querySelectorAll('[data-slot=plan]')][0];b.click();})()")
        await asyncio.sleep(.4)
        r = await call('Page.captureScreenshot', {'format': 'png'})
        (OUT / 'd-slot-todo-list.png').write_bytes(base64.b64decode(r['result']['data']))
        await ev("(function(){var b=[...document.querySelectorAll('[data-sched]')][0];b.click();})()")
        await asyncio.sleep(.5)
        r = await call('Page.captureScreenshot', {'format': 'png'})
        (OUT / 'd-slot-plan.png').write_bytes(base64.b64decode(r['result']['data']))
        await ev("state.screen='cal-week';state.variant='normal';state.drawer=null;render();'ok'")

        # repeat picker (read-only repeat -> edit -> picker)
        await shot('d-repeat-edit.png', 1440, 1000, 'todo-all')
        await ev("Proto.enhance()")
        await ev("(function(){var r=[...document.querySelectorAll('.todo-row, .task-row')].find(x=>x.dataset.id==='recurring');r.click();})()")
        await asyncio.sleep(.5)
        print('   drawer rows:', await ev("JSON.stringify([...document.querySelectorAll('.drawer .field-row')].map(function(x){return (x.querySelector('.f-label')||{}).textContent;}))"))
        await ev("(function(){var r=[...document.querySelectorAll('.drawer .field-row')].find(x=>(x.querySelector('.f-label')||{}).textContent==='重复');if(r)r.click();})()")
        await asyncio.sleep(.5)
        r = await call('Page.captureScreenshot', {'format': 'png'})
        (OUT / 'd-repeat-in-edit.png').write_bytes(base64.b64decode(r['result']['data']))
        await ev("(function(){var b=[...document.querySelectorAll('.drawer .v2-select-row .mini')][0];b.click();})()")
        await asyncio.sleep(.5)
        r = await call('Page.captureScreenshot', {'format': 'png'})
        (OUT / 'd-repeat-picker.png').write_bytes(base64.b64decode(r['result']['data']))
        await ev("""(function(){
          var b=[...document.querySelectorAll('[data-tunit=week]')][0];b.click();
          ['一','四','五'].forEach(function(ch){var d=[...document.querySelectorAll('[data-day]')].find(x=>x.dataset.day===ch);if(d)d.click();});
          var i=document.querySelector('#rp-interval');i.value='3';i.dispatchEvent(new Event('change',{bubbles:true}));
        })()""")
        await asyncio.sleep(.4)
        r = await call('Page.captureScreenshot', {'format': 'png'})
        (OUT / 'd-repeat-picker-3w.png').write_bytes(base64.b64decode(r['result']['data']))
        await ev("(function(){var a=[...document.querySelectorAll('.proto-modal-scrim')];a.forEach(x=>x.remove());})();state.drawer=null;state.drawerEdit=false;render();'ok'")

        # phone repeat picker
        await shot('m-repeat-open.png', 390, 844, 'todo-all')
        print('   phone rows:', await ev("document.querySelectorAll('.task-row').length"))
        await ev("(function(){var r=[...document.querySelectorAll('.task-row')].find(x=>x.dataset.id==='recurring');r.click();})()")
        await asyncio.sleep(.6)
        print('   phone drawer:', await ev("JSON.stringify({title:(document.querySelector('.m-title')||{}).textContent,mrows:document.querySelectorAll('.m-form-row').length})"))
        r = await call('Page.captureScreenshot', {'format': 'png'})
        (OUT / 'm-repeat-drawer.png').write_bytes(base64.b64decode(r['result']['data']))
        # The phone drawer opens straight into its editor (state.drawerEdit),
        # so 自定义… is already present; no extra edit step exists there.
        print('   phone edit mini buttons:', await ev("document.querySelectorAll('.v2-select-row .mini').length"))
        await ev("(function(){var b=document.querySelector('.v2-select-row .mini');if(b)b.click();})()")
        await asyncio.sleep(.5)
        r = await call('Page.captureScreenshot', {'format': 'png'})
        (OUT / 'm-repeat-picker.png').write_bytes(base64.b64decode(r['result']['data']))
        await ev("(function(){var a=[...document.querySelectorAll('.proto-modal-scrim')];a.forEach(x=>x.remove());})();state.drawer=null;state.drawerEdit=false;render();'ok'")

        # widget showcase under dark theme (the copy says widgets follow theme)
        await shot('d-widgets-light.png', 1440, 1000, 'widgets')
        await shot('d-widgets-dark.png', 1440, 1000, 'widgets', theme='dark')

        # hide-completed row in both filter surfaces + notification card
        await shot('d-filter-hide.png', 1440, 1000, 'todo-all', "state.variant='filter';")
        await shot('m-filter-hide.png', 390, 844, 'todo-all', "state.variant='filter';")
        await shot('m-filter-hide-dark.png', 390, 844, 'todo-all', "state.variant='filter';", theme='dark')
        await shot('d-settings-general.png', 1440, 1000, 'settings-general')
        await shot('d-notify-card.png', 1440, 1000, 'settings-notify')
        await ev("(function(){document.querySelector('[data-action=\"notify-test\"]').click();})()")
        await asyncio.sleep(.5)
        r = await call('Page.captureScreenshot', {'format': 'png'})
        (OUT / 'd-notify-snooze.png').write_bytes(base64.b64decode(r['result']['data']))
        await ev("(function(){var h=document.querySelector('#proto-notify-demo');if(h)h.remove();})();'ok'")

        # phone calendar 显示日历 sheet: calendar visibility only
        await shot('m-cal-filter.png', 390, 844, 'cal-week', "state.variant='calendars';state.selectedDate='2026-11-20';", mobile=True) if False else None
        await ev("state.device='mobile';state.screen='cal-week';state.variant='calendars';state.selectedDate='2026-11-20';render();Proto.enhance();'ok'")
        await asyncio.sleep(.5)
        print('   phone calendar sheet has hide-completed row:',
              await ev("(function(){var s=document.querySelector('.m-filter-sheet');return !!(s&&s.querySelector('[data-proto-action=pref-hide-completed]'));})()"))
        r = await call('Page.captureScreenshot', {'format': 'png'})
        (OUT / 'm-cal-filter-sheet.png').write_bytes(base64.b64decode(r['result']['data']))

        print('TOTAL', 'mismatched themes:', MISMATCH or 'none')
        print('ERRORS', errs[:3] or 'none')
    p.terminate()

asyncio.run(main())
