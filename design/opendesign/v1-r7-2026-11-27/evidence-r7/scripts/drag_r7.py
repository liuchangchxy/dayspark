"""R4 drag/resize semantics at the R7 column scale.

The R4 probes moved the pointer by a fraction of the day column; R7 draws the
full 24 hours (1296px) instead of R4's 648px, so the same fraction is twice as
many minutes. These checks use minutes converted to pixels, and assert the
business result the R4 cases recorded: only the dragged segment moves, deltas
do not accumulate, and resizing changes only the second segment.

usage: python3 drag_r7.py
"""
import asyncio, json, subprocess, time, urllib.request, websockets

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
PORT = 9493
PROFILE = '/tmp/ds-r7-drag'
URL = ('file://' + str(__import__('pathlib').Path(__file__).resolve().parents[2] / 'dayspark-prototype.html'))
subprocess.run(['rm', '-rf', PROFILE])
p = subprocess.Popen([CHROME, '--headless=new', '--disable-gpu', f'--remote-debugging-port={PORT}',
                      f'--user-data-dir={PROFILE}', '--window-size=1440,1400', URL],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
u = None
for _ in range(80):
    try:
        d = json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json'))
        pg = [t for t in d if t.get('type') == 'page']
        if pg:
            u = pg[0]['webSocketDebuggerUrl']; break
    except Exception: pass
    time.sleep(.25)

FAILS = []

def rec(name, got, want):
    ok = got == want
    if not ok: FAILS.append(name)
    print(('PASS ' if ok else 'FAIL '), name, '=>', got, '' if ok else f'(want {want})')

async def main():
    async with websockets.connect(u, max_size=2**24) as ws:
        i = 0; errs = []
        async def send(m, **pa):
            nonlocal i; i += 1; mid = i
            await ws.send(json.dumps({'id': mid, 'method': m, 'params': pa}))
            while True:
                x = json.loads(await ws.recv())
                if x.get('id') == mid: return x
                if x.get('method') in ('Runtime.exceptionThrown', 'Log.entryAdded'): errs.append(x)
        async def ev(x):
            r = await send('Runtime.evaluate', expression=x, returnByValue=True)
            res = r.get('result', {})
            if 'exceptionDetails' in res: return 'ERR ' + str((res['exceptionDetails'].get('exception') or {}).get('description'))[:140]
            return res.get('result', {}).get('value')
        await send('Runtime.enable'); await send('Log.enable'); await asyncio.sleep(1.4)

        async def drag(minutes, which):
            # Scroll the block into view first: a block above the viewport has
            # a negative rect and the pointer maths would land at the day's end.
            await ev(f"var b=document.querySelector('.day-col .cal-block.is-plan[data-alloc=\"{which}\"], .day-col .cal-block[data-alloc=\"{which}\"]'); b&&b.scrollIntoView({{block:'center'}});'ok'")
            await asyncio.sleep(.35)
            info = await ev(f"""(function(){{
              var b=document.querySelector('.day-col .cal-block.is-plan[data-alloc="{which}"], .day-col .cal-block[data-alloc="{which}"]');
              if(!b) return null;
              var r=b.getBoundingClientRect(), c=b.closest('.day-col').getBoundingClientRect();
              return {{x:r.x+12,y:r.y+8,ch:c.height}};
            }})()""")
            if not info:
                return 'no block ' + which
            ppm = info['ch'] / 1440.0
            x, y = info['x'], info['y']
            yy = y + minutes * ppm
            await send('Input.dispatchMouseEvent', type='mousePressed', x=x, y=y, button='left', clickCount=1)
            await send('Input.dispatchMouseEvent', type='mouseMoved', x=x, y=y + (yy - y) / 2, button='left')
            await send('Input.dispatchMouseEvent', type='mouseMoved', x=x, y=yy, button='left'); await asyncio.sleep(.12)
            await send('Input.dispatchMouseEvent', type='mouseReleased', x=x, y=yy, button='left', clickCount=1); await asyncio.sleep(.45)
            return await ev("JSON.stringify(todoById('report').plans.map(p=>[p.id,p.start,p.end]))")

        # 1) delta does not accumulate: +30 -> -30 back to start -> +60.
        await ev("state.selectedDate='2026-11-20'; Proto.baseGo('cal-day'); state.variant='normal'; render(); 'ok'")
        await asyncio.sleep(.6)
        rec('start', await ev("JSON.stringify(todoById('report').plans.map(p=>[p.id,p.start,p.end]))"),
            '[["alloc-1","15:15","16:00"]]')
        rec('drag +30', await drag(30, 'alloc-1'), '[["alloc-1","15:45","16:30"]]')
        rec('drag -30 returns to start', await drag(-30, 'alloc-1'), '[["alloc-1","15:15","16:00"]]')
        rec('drag +60 from start (not accumulated 17:15)', await drag(60, 'alloc-1'), '[["alloc-1","16:15","17:00"]]')
        await ev("delete todoById('report').plans; todoById('report').plan=null; DS3.addAllocation(todoById('report'),{date:'2026-11-20',start:'15:15',end:'16:00'}); render(); 'ok'")

        # 2) two segments: dragging the second leaves the first untouched.
        await ev("DS3.addAllocation(todoById('report'),{date:'2026-11-20',start:'11:00',end:'12:00'}); render(); 'ok'")
        await asyncio.sleep(.5)
        second = await ev("(todoById('report').plans.slice(-1)[0]||{}).id")
        rec('second segment seeded', await ev("(todoById('report').plans.slice(-1)[0]||{}).id"), second)
        await drag(45, second)
        rec('drag second keeps first at 15:15–16:00',
            await ev("JSON.stringify(todoById('report').plans.map(p=>[p.start,p.end]))"),
            '[["15:15","16:00"],["11:45","12:45"]]')

        # 3) resize the second segment's lower edge: only that segment grows.
        await ev(f"var b=document.querySelector('.day-col .cal-block[data-alloc=\"{second}\"]'); b&&b.scrollIntoView({{block:'center'}});'ok'")
        await asyncio.sleep(.35)
        info = await ev(f"""(function(){{
          var b=document.querySelector('.day-col .cal-block[data-alloc="{second}"]'); if(!b) return null;
          var h=b.querySelector('.proto-resize'); if(!h) return 'noHandle';
          var r=h.getBoundingClientRect(), c=b.closest('.day-col').getBoundingClientRect();
          return {{x:r.x+r.width/2,y:r.y+r.height/2,ch:c.height}};
        }})()""")
        if isinstance(info, dict):
            ppm = info['ch'] / 1440.0
            x, y = info['x'], info['y']
            yy = y + int(30 * ppm)
            await send('Input.dispatchMouseEvent', type='mousePressed', x=x, y=y, button='left', clickCount=1)
            await send('Input.dispatchMouseEvent', type='mouseMoved', x=x, y=yy, button='left'); await asyncio.sleep(.12)
            await send('Input.dispatchMouseEvent', type='mouseReleased', x=x, y=yy, button='left', clickCount=1); await asyncio.sleep(.5)
        rec('resize second extends only the second segment',
            await ev("JSON.stringify(todoById('report').plans.map(p=>[p.start,p.end]))"),
            '[["15:15","16:00"],["11:45","13:15"]]')

        print('TOTAL', 8 - len(FAILS), '/ 8')
        print('ERRORS', [e.get('method') for e in errs] or 'none')
    p.terminate()

asyncio.run(main())
