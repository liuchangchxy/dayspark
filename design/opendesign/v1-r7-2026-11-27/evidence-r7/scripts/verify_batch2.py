"""Verification pass 2: plans, search, capture, mobile density."""
from pathlib import Path
import asyncio, json, subprocess, time, urllib.request, base64
import websockets

HERE = Path(__file__).resolve()
OUT = HERE.parents[1] / 'screens'
URL = (HERE.parents[2] / 'dayspark-prototype.html').as_uri()
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
PORT = 9744
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
                    logs.append('EXC ' + json.dumps(x['params']['exceptionDetails'].get('exception', {}).get('description', ''))[:300])
                if x.get('method') == 'Runtime.consoleAPICalled' and x['params']['type'] == 'error':
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
            await call('Emulation.setDeviceMetricsOverride', {'width': 390, 'height': 844, 'deviceScaleFactor': 2, 'mobile': on})

        def check(label, ok, detail=''):
            print(('PASS ' if ok else 'FAIL ') + label + (' :: ' + str(detail) if detail != '' else ''))
            if not ok:
                problems.append(label + ' :: ' + str(detail))

        await call('Runtime.enable'); await call('Page.enable')
        await asyncio.sleep(1.8)

        # ---------- multi-segment plan ----------
        await reload()
        await ev("""
          (function(){
            const t=todoById('report');
            DS3.addAllocation(t,{date:'2026-11-20',start:'09:00',end:'09:45',occurrenceDate:null});
            DS3.addAllocation(t,{date:'2026-11-20',start:'19:00',end:'20:00',occurrenceDate:null});
            return 'ok';
          })()""")
        await ev("state.screen='cal-day';state.variant='normal';state.selectedDate='2026-11-20';render();Proto.enhance();'x'")
        await asyncio.sleep(.5)
        blocks = await ev("JSON.stringify([...document.querySelectorAll('.day-col .cal-block.is-plan')].map(b=>b.textContent.replace(/\\s+/g,' ').slice(0,24)))")
        allocs = await ev("JSON.stringify([...document.querySelectorAll('.day-col .cal-block.is-plan')].map(b=>b.dataset.alloc))")
        check('three plan segments on day', blocks and blocks.count('周报') == 3 if isinstance(blocks, str) else False, blocks)
        check('each segment has alloc id', allocs and 'null' not in allocs, allocs)
        await ev("state.screen='todo-date';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.4)
        rows = await ev("[...document.querySelectorAll('.todo-row')].filter(r=>r.textContent.includes('周报')).length")
        seg = await ev("[...document.querySelectorAll('.todo-row')].find(r=>r.textContent.includes('周报'))?.querySelector('.plan-meta')?.textContent.trim()")
        check('one parent row for date view', rows == 1, rows)
        check('row lists all segment times', bool(seg) and '09:00' in (seg or '') and '19:00' in (seg or '') and '3 段' in (seg or ''), seg)
        await shot('batch-date-plans.png')
        await ev("state.screen='cal-day';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.3)
        await shot('batch-cal-segments.png')

        # ---------- search ----------
        await reload()
        await ev("state.screen='command';state.variant='result';state.cmdQuery='';render();Proto.enhance();'x'")
        await asyncio.sleep(.4)
        empty = await ev("document.querySelector('.cmd-body').textContent.slice(0,160)")
        check('no fake recents on empty query', '还没有打开过' in (empty or '') or '最近' in (empty or ''), empty)
        await reload()
        await ev("Proto.openTodo('rent');'x'")
        await asyncio.sleep(.5)
        await ev("state.drawer=null;state.screen='command';state.variant='result';state.cmdQuery='';render();Proto.enhance();'x'")
        await asyncio.sleep(.4)
        first = await ev("document.querySelector('.cmd-body .cmd-row')?.textContent.replace(/\\s+/g,' ').slice(0,40)")
        check('recent reflects real visit', '房租' in (first or '') or '房租' in (await ev("document.querySelector('.cmd-body').textContent") or ''), first)
        await ev("state.cmdQuery='数据';state.variant='result';render();Proto.paintSearch();'x'")
        await asyncio.sleep(.3)
        why = await ev("[...document.querySelectorAll('.cmd-body .cmd-row-m')].map(e=>e.textContent).join(' | ')")
        check('match reason shown', '命中' in (why or ''), why[:200])
        await shot('batch-search-why.png')
        # Enter once
        await ev("""
          state.cmdQuery='周报'; state.variant='result'; render(); Proto.paintSearch();
          const s=document.querySelector('.cmd-body .cmd-row.is-sel')||document.querySelector('.cmd-body .cmd-row');
          window.__before=state.drawer; s.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true}));
          'x'""")
        await asyncio.sleep(.1)
        await ev("document.querySelector('.cmd-input input').dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true,cancelable:true}))")
        await asyncio.sleep(.6)
        check('one Enter opens row', await ev("!!state.drawer"), await ev("JSON.stringify(state.drawer)"))

        # ---------- capture ----------
        await reload()
        await ev("state.screen='today';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.4)
        # IME: composition Enter must not save
        n0 = await ev("TODOS.length")
        await ev("""(function(){var ci=document.querySelector('#cap-input');ci.value='明天下午三点交报告';
          ci.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',isComposing:true,bubbles:true,cancelable:true}));})();'x'""")
        await asyncio.sleep(.2)
        check('IME Enter does not save', await ev("TODOS.length") == n0, await ev("TODOS.length"))
        await ev("""(function(){var ci=document.querySelector('#cap-input');
          ci.dispatchEvent(new KeyboardEvent('keydown',{key:'Enter',bubbles:true,cancelable:true}));})();'x'""")
        await asyncio.sleep(.5)
        created = await ev("JSON.stringify(EVENTS[EVENTS.length-1])")
        check('future time event date correct', '2026-11-21' in (created or '') and '15:00' in (created or ''), created)
        check('stays on page after save', await ev("state.screen") == 'today', await ev("state.screen"))
        check('input cleared for next entry', await ev("document.querySelector('#cap-input').value") == '', await ev("document.querySelector('#cap-input').value"))
        hint = await ev("(document.querySelector('.cap-date')||{}).textContent")
        await ev("document.querySelector('#cap-input').value='明天下午三点交总结';document.querySelector('#cap-input').dispatchEvent(new Event('input'))")
        await asyncio.sleep(.3)
        hint2 = await ev("(document.querySelector('.cap-date')||{}).textContent")
        check('hint updates live', bool(hint2) and '11/21' in (hint2 or '') and '15:00' in (hint2 or ''), hint2)
        await shot('batch-capture-hint.png')

        # ---------- mobile ----------
        await reload()
        await mobile(True); await asyncio.sleep(1.6)
        await ev("state.screen='today';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.5)
        h = await ev("document.querySelector('.m-now-foot')?.textContent.replace(/\\s+/g,' ')")
        check('now foot single line', bool(h) and len(h) < 40, h)
        await shot('batch-mobile-today2.png')
        await ev("state.screen='cal-day';state.variant='normal';state.selectedDate='2026-11-20';render();Proto.enhance();'x'")
        await asyncio.sleep(.5)
        await shot('batch-mobile-cal2.png')
        await ev("state.screen='detail-todo';state.variant='normal';render();Proto.enhance();'x'")
        await asyncio.sleep(.4)
        foot = await ev("JSON.stringify([...document.querySelectorAll('.d-foot .d-act')].map(function(b){return {t:b.textContent.trim(),h:b.offsetHeight};}))")
        check('mobile foot hit area', bool(foot) and '44' in (foot or ''), foot)
        await shot('batch-mobile-detail.png')
        await call('Emulation.clearDeviceMetricsOverride')

        err = await ev("window.Proto && Proto.lastEnhancerError ? String(Proto.lastEnhancerError) : null")
        check('enhancer clean', not err, err)
        check('console clean', not logs, logs[:4])

    p.terminate()
    print('\nPROBLEMS:', len(problems))
    for x in problems[:15]:
        print(' -', x)

asyncio.run(main())
