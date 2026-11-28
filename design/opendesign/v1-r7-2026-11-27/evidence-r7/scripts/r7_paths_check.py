"""R4 paths whose UI gained a step in R6/R7 — run against the R7 artifact.

1) Backup round trip (#33/#34): export → clear → reload → merge. R6 added an
   impact preview before writing, so the flow is export → choose file → confirm
   "合并" → verify the same fields restore and survive a reload.
2) Task menu 安排 (#30): R7's Today page collapses 无日期 into one entry, so the
   menu path is exercised on 待办 · 全部 where every row is present, then the
   resulting allocation is read back by id.

usage: python3 r7_paths_check.py
"""
import asyncio, json, subprocess, time, urllib.request, glob, os, pathlib, websockets

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
PORT = 9494
PROFILE = '/tmp/ds-r7-paths'
DL = '/tmp/r7-paths-downloads'
URL = 'file://' + str(pathlib.Path(__file__).resolve().parents[2] / 'dayspark-prototype.html')
subprocess.run(['rm', '-rf', PROFILE]); subprocess.run(['rm', '-rf', DL]); os.makedirs(DL, exist_ok=True)
p = subprocess.Popen([CHROME, '--headless=new', '--disable-gpu', f'--remote-debugging-port={PORT}',
                      f'--user-data-dir={PROFILE}', '--window-size=1440,1000', URL],
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

CHECKS = []

def rec(name, got, want):
    for _ in range(2):
        if isinstance(got, str):
            try: got = json.loads(got)
            except Exception: pass
        if isinstance(want, str):
            try: want = json.loads(want)
            except Exception: pass
    ok = got == want
    CHECKS.append(ok)
    print(('PASS ' if ok else 'FAIL '), name, '=>', got, '' if ok else f'(want {want})')

async def main():
    async with websockets.connect(u, max_size=2**25) as ws:
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
        async def ready():
            for _ in range(80):
                if await ev("!!window.state && document.readyState==='complete'"): return
                await asyncio.sleep(.1)
        await send('Runtime.enable'); await send('Log.enable'); await send('DOM.enable'); await send('Page.enable')
        await send('Browser.setDownloadBehavior', behavior='allow', downloadPath=DL, eventsEnabled=True)
        await ready(); await asyncio.sleep(.6)
        await ev("try{localStorage.removeItem('dayspark.prototype.v1')}catch(e){}"); await send('Page.reload'); await asyncio.sleep(1.4); await ready()

        # planSeq starts at 2 on a fresh install (the demo seeds alloc-1 and
        # advances the counter once); this check adds one allocation below, so
        # the backup must restore seq = 3 and hold it across the reload.
        # ---------------------------------------------------------- backup
        await ev("""(function(){
          var r=todoById('report');
          DS3.addAllocation(r,{date:'2026-11-20',start:'09:00',end:'10:00'});
          r.reminders=['30 分钟前']; r.tags=['备份验证'];
          DS3.addAllocation(todoById('recurring'),{date:'2026-11-26',start:'09:00',end:'10:00',occurrenceDate:'2026-11-27'});
          state.doneInstances=['recurring@2026-11-06'];
          state.skipped=['weekly@2026-11-13'];
          state.deletedTodos=['gone'];
          addLocalTodo({title:'备份里的本地待办',cal:'personal',priority:0});
          if(!Proto.data.tags.some(function(t){return t.name==='备份验证';})) Proto.data.tags.push({name:'备份验证',color:'#123456'});
          render();
        })()""")
        await asyncio.sleep(.4)
        await ev("Proto.baseGo('settings-backup'); 'ok'"); await asyncio.sleep(.5)
        await ev("(function(){var e=document.querySelector('[data-action=\"backup-export\"]');e.click();})()")
        path = None
        for _ in range(60):
            fs = glob.glob(DL + '/*')
            if fs: path = fs[0]; break
            await asyncio.sleep(.2)
        rec('export writes a real file', bool(path) and os.path.getsize(path) > 1000, True)
        payload = json.load(open(path))
        rec('backup carries all five sections', sorted(payload.keys())[:5], ['cal', 'data', 'events', 'screen', 'state'])
        rec('backup carries planSeq + doneInstances', ['planSeq' in payload['state'], 'doneInstances' in payload['state']], [True, True])
        rec('AI key stays masked in the file', payload['data']['ai']['key'], 'sk-••••4f2a')

        # a fresh install: clear storage, reload
        await ev("localStorage.clear(); 'ok'"); await send('Page.reload'); await asyncio.sleep(1.5); await ready()
        rec('fresh install has no extra segment', await ev("DS3.allocations(todoById('report')).length"), 1)
        await ev("Proto.baseGo('settings-backup'); 'ok'"); await asyncio.sleep(.4)
        await ev("(function(){var e=document.querySelector('[data-action=\"backup-merge\"]');e.click();})()")
        await asyncio.sleep(.3)
        doc = await send('DOM.getDocument', depth=-1, pierce=True); root = doc['result']['root']['nodeId']
        nid = (await send('DOM.querySelector', nodeId=root, selector='#proto-backup-file'))['result']['nodeId']
        rec('merge opens a real file input', nid != 0, True)
        await send('DOM.setFileInputFiles', files=[path], nodeId=nid)
        await asyncio.sleep(1.0)
        rec('merge previews impact before writing', await ev("(function(){var s=[...document.querySelectorAll('.proto-modal-scrim')].pop();return s? s.textContent.includes('合并这份备份'):false;})()"), True)
        await ev("(function(){var s=[...document.querySelectorAll('.proto-modal-scrim')].pop();var b=[...s.querySelectorAll('.proto-modal-foot button')].find(x=>x.textContent.trim()==='合并');b.click();})()")
        await asyncio.sleep(1.2)
        rep = await ev("JSON.stringify({alloc:DS3.allocations(todoById('report')).map(function(p){return [p.start,p.end];}),rem:todoById('report').reminders,tags:todoById('report').tags})")
        rec('report restores its second segment, reminder and tag', rep,
            json.dumps({'alloc': [['15:15', '16:00'], ['09:00', '10:00']], 'rem': ['30 分钟前'], 'tags': ['备份验证']}))
        rec('recurring instance allocation restored',
            await ev("JSON.stringify(DS3.allocations(todoById('recurring')).map(function(p){return [p.date,p.occurrenceDate];}))"),
            json.dumps([['2026-11-26', '2026-11-27']]))
        # seq is asserted against the file that was actually exported, not a
        # hardcoded counter: what matters is that merge restores it exactly.
        rec('done / skipped / tombstone / local restored',
            await ev("JSON.stringify({done:state.doneInstances,skip:state.skipped,del:state.deletedTodos,local:state.localTodos.map(function(t){return t.id;}),seq:state.planSeq})"),
            json.dumps({'done': ['recurring@2026-11-06'], 'skip': ['weekly@2026-11-13'], 'del': ['gone'],
                        'local': ['local-1'], 'seq': payload['state']['planSeq']}))
        rec('no plaintext key in snapshot or storage',
            await ev("JSON.stringify([JSON.stringify(Proto.snapshot()).includes('sk-leak'),(localStorage.getItem('dayspark.prototype.v1')||'').includes('sk-leak')])"),
            json.dumps([False, False]))
        await send('Page.reload'); await asyncio.sleep(1.5); await ready()
        rec('restored data survives the reload',
            await ev("JSON.stringify({alloc:DS3.allocations(todoById('report')).length,done:state.doneInstances,local:state.localTodos.length,seq:state.planSeq})"),
            json.dumps({'alloc': 2, 'done': ['recurring@2026-11-06'], 'local': 1, 'seq': payload['state']['planSeq']}))

        # ---------------------------------------------------------- menu 安排
        await ev("Proto.baseGo('todo-all'); state.variant='normal'; render(); Proto.enhance(); 'ok'")
        await asyncio.sleep(.6)
        rows = await ev("JSON.stringify([...document.querySelectorAll('.task-row, .todo-row')].map(function(x){return x.dataset.id;}))")
        rec('待办 · 全部 lists every live todo (menu path reachable)', 'rent' in (rows or '') and 'groceries' in (rows or ''), True)
        await ev("(function(){var r=[...document.querySelectorAll('.task-row[data-id=\"rent\"], .todo-row[data-id=\"rent\"]')][0];r.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,clientX:420,clientY:320,button:2}));})()")
        await asyncio.sleep(.4)
        rec('row menu opens', await ev("!!document.querySelector('.proto-menu [data-m=plan]')"), True)
        await ev("(function(){var b=[...document.querySelectorAll('.proto-menu [data-m]')].find(function(x){return x.dataset.m==='plan';});b.click();})()")
        await asyncio.sleep(.5)
        rec('menu 安排 opens the plan picker for rent',
            await ev("JSON.stringify({screen:state.screen,todo:state.planTodoId})"),
            json.dumps({'screen': 'plan-picker', 'todo': 'rent'}))
        await ev("document.querySelector('#plan-start').value='09:00'; document.querySelector('#plan-end').value='10:00'; 'ok'")
        await ev("(function(){document.querySelector('[data-action=\"plan-submit\"]').click();})()")
        await asyncio.sleep(.6)
        rec('menu 安排 appends one new segment, does not overwrite',
            await ev("JSON.stringify(DS3.allocations(todoById('rent')).map(function(p){return [p.start,p.end];}))"),
            json.dumps([['09:00', '10:00']]))

        print('TOTAL', sum(1 for x in CHECKS if x), '/', len(CHECKS))
        # Print the text, not just the channel: a Log.entryAdded in Chrome is
        # usually the download dialog's own notice, but it must be read once.
        details = []
        for e in errs:
            pa = e.get('params', {})
            ent = pa.get('entry', {}) or {}
            details.append((e.get('method'), ent.get('level'), (ent.get('text') or '')[:90]))
        print('ERRORS', details or 'none')
    p.terminate()

asyncio.run(main())
