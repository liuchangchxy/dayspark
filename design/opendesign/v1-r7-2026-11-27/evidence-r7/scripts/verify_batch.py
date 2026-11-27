"""Browser verification for the deep-polish batch: mobile today, 24h calendar,
AI proposals, menus, filters, settings, drawer return."""
from pathlib import Path
import asyncio, json, subprocess, time, urllib.request, base64, sys
import websockets

HERE = Path(__file__).resolve()
OUT = HERE.parents[1] / 'screens'
URL = (HERE.parents[2] / 'dayspark-prototype.html').as_uri()
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
PORT = 9742
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

problems = []

async def main():
    async with websockets.connect(u, max_size=2**28) as ws:
        i = 0
        logs = []
        async def call(m, params=None):
            nonlocal i
            i += 1; mid = i
            await ws.send(json.dumps({'id': mid, 'method': m, 'params': params or {}}))
            while True:
                x = json.loads(await ws.recv())
                if x.get('method') == 'Runtime.exceptionThrown':
                    t = x['params']['exceptionDetails']
                    logs.append('EXC ' + json.dumps(t.get('exception', {}).get('description', t.get('text', '')))[:300])
                if x.get('method') == 'Runtime.consoleAPICalled' and x['params']['type'] in ('error', 'warning'):
                    logs.append('CONSOLE ' + str(x['params']['args'])[:200])
                if x.get('id') == mid:
                    return x
        async def ev(expr):
            r = await call('Runtime.evaluate', {'expression': expr, 'returnByValue': True, 'awaitPromise': True})
            q = r.get('result', {})
            if q.get('exceptionDetails'):
                problems.append('EVAL ' + str(q['exceptionDetails'].get('exception', {}).get('description', ''))[:250])
                return None
            return q.get('result', {}).get('value')
        async def shot(name):
            await asyncio.sleep(.35)
            r = await call('Page.captureScreenshot', {'format': 'png'})
            (OUT / name).write_bytes(base64.b64decode(r['result']['data']))
            print('shot', name)
        async def reload():
            await call('Page.navigate', {'url': URL}); await asyncio.sleep(1.6)
        async def mobile(on):
            await call('Emulation.setDeviceMetricsOverride',
                       {'width': 390, 'height': 844, 'deviceScaleFactor': 2, 'mobile': on})
        async def desktop():
            await call('Emulation.clearDeviceMetricsOverride')

        await call('Runtime.enable'); await call('Page.enable')
        await asyncio.sleep(1.8)

        def check(label, ok, detail=''):
            print(('PASS ' if ok else 'FAIL ') + label + (' :: ' + str(detail) if detail != '' else ''))
            if not ok:
                problems.append(label + ' :: ' + str(detail))

        # ---- desktop today ----
        await ev("state.screen='today';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.4)
        check('today sections', await ev("document.querySelectorAll('.today-section, .t-sec').length") >= 1, await ev("document.querySelectorAll('.today-section, .t-sec').length"))
        await shot('batch-desktop-today.png')

        # ---- desktop calendar: 24h axis + default scroll ----
        await ev("state.screen='cal-week';state.variant='normal';state.selectedDate='2026-11-20';render();Proto.enhance();'x'")
        await asyncio.sleep(.5)
        labels = await ev("[...document.querySelectorAll('.time-axis .hour, .time-axis > *')].map(e=>e.textContent.trim()).filter(Boolean)")
        body_h = await ev("(document.querySelector('.day-body')||{}).offsetHeight")
        scroll = await ev("(document.querySelector('.cal-main')||{}).scrollTop")
        check('hour labels include 00 and 22', bool(labels) and labels[0].startswith('0') and '22' in labels[-1], labels)
        check('day body tall (24h)', body_h and body_h >= 1200, body_h)
        check('default scroll near 07:00', scroll and 350 <= scroll <= 520, scroll)
        await shot('batch-desktop-week.png')

        # ---- parallel block geometry ----
        boxes = await ev("JSON.stringify([...document.querySelectorAll('.day-col .cal-block')].slice(0,8).map(b=>({t:b.style.top,h:b.style.height,cls:b.className})))")
        check('blocks have % geometry', bool(boxes) and 'top' in boxes, boxes[:120])

        # ---- AI proposals ----
        await ev("state.screen='ai-chat';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.4)
        nprop = await ev("document.querySelectorAll('.ai-proposal').length")
        nact = await ev("document.querySelectorAll('.ai-proposal .ai-action-primary').length")
        check('one proposal, one confirm', nprop == 1 and nact == 1, f'{nprop}/{nact}')
        await shot('batch-desktop-ai.png')
        await ev("[...document.querySelectorAll('.ai-proposal button')].find(b=>b.dataset.protoAction==='ai-cancel-proposal').click();'x'")
        await asyncio.sleep(.5)
        st = await ev("JSON.stringify(AI_THREAD.filter(m=>m.actions).map(m=>m.proposalState))")
        check('cancel marks state', 'cancelled' in (st or ''), st)
        await shot('batch-desktop-ai-cancelled.png')
        await reload()
        await ev("state.screen='ai-chat';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.4)
        await ev("document.querySelector('.ai-proposal .ai-action-primary').click();'x'")
        await asyncio.sleep(1.0)
        scr = await ev("state.screen")
        title = await ev("(document.querySelector('#new-title')||{}).value")
        check('confirm writes via editor', scr in ('new-todo', 'new-event'), f'{scr} title={title}')

        # ---- preview menu + row menu coexist ----
        await reload()
        await ev("document.body.dataset.device='desktop';state.screen='today';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.5)
        await ev("document.querySelector('.proto-bar .proto-bar-btn, .proto-bar button').click();'x'")
        await asyncio.sleep(.3)
        await ev("(document.querySelector('.task-row')||document.querySelector('.todo-row')).dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,clientX:400,clientY:300}));'x'")
        await asyncio.sleep(.3)
        bar_open = await ev("!!document.querySelector('.proto-menu.proto-bar-menu:not([hidden])')")
        row_open = await ev("!!document.querySelector('.proto-menu:not(.proto-bar-menu)')")
        check('bar menu survives row menu', bar_open and row_open, f'bar={bar_open} row={row_open}')
        await shot('batch-desktop-menus.png')
        # long-press row still covered by contextmenu
        await ev("document.querySelector('.proto-menu:not(.proto-bar-menu) button[data-m=\"open\"]').click();'x'")
        await asyncio.sleep(.5)
        check('row menu opens detail', await ev("!!document.querySelector('.drawer, .detail')"), await ev("state.drawer"))

        # ---- filters use real tags ----
        await reload()
        await ev("state.screen='todos';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.4)
        await ev("(document.querySelector('[data-action=\"open-filter\"]')||document.querySelector('.filter-btn')).click();'x'")
        await asyncio.sleep(.4)
        tags = await ev("JSON.stringify([...document.querySelectorAll('.filter-panel [data-action=\"filter-tag\"], .filter-panel .f-chip')].map(e=>e.textContent.trim()))")
        check('filter tags from data', bool(tags) and tags != '[]', (tags or '')[:160])

        # ---- settings: no duplicate heading ----
        await reload()
        await ev("state.screen='settings';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.4)
        h2 = await ev("[...document.querySelectorAll('.set-main h2, .settings-main h2, .set-col h2')].map(e=>e.textContent.trim())")
        check('no duplicate 设置 heading', not (h2 and h2[0] == '设置'), h2)

        # ---- mobile today single module ----
        await reload()
        await mobile(True)
        await asyncio.sleep(1.6)
        await ev("state.screen='today';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.5)
        now = await ev("document.querySelectorAll('.m-now-head').length")
        timesec = await ev("document.querySelectorAll('.m-time-sec, .m-ts').length")
        check('mobile one schedule module', now == 1 and timesec == 0, f'now={now} timeSec={timesec}')
        first = await ev("JSON.stringify([...document.querySelectorAll('.m-today .m-now-foot, .m-now-foot')].map(e=>e.textContent.trim()))")
        await shot('batch-mobile-today.png')
        # mobile calendar
        await ev("state.screen='cal-day';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.5)
        await shot('batch-mobile-cal.png')
        await call('Emulation.clearDeviceMetricsOverride')

        await asyncio.sleep(.3)
        err = await ev("window.Proto && Proto.lastEnhancerError ? String(Proto.lastEnhancerError) : null")
        check('enhancer clean', not err, err)
        check('console clean', not logs, logs[:4])

    p.terminate()
    print('\nPROBLEMS:', len(problems))
    for x in problems[:12]:
        print(' -', x)

asyncio.run(main())
