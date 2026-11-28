"""R4 #14 on the R7 artifact: a repeating todo scheduled from AI.

R7 replaced the master's per-message 安排时间 chip row with one proposal card
per reply (确认写入 / 不用了), so the R4 script's chip no longer exists. The
product path is now: ask in the input → the reply carries a plan proposal →
确认写入 opens the plan modal → the repeating target must first resolve a
concrete occurrence → write.

Run: python3 -I ai_repeat_plan.py
"""
import asyncio, json, pathlib, subprocess, time, urllib.request, websockets

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
PORT = 9483
PROFILE = '/tmp/ds-airepeat'
URL = (pathlib.Path(__file__).resolve().parents[2] / 'dayspark-prototype.html').as_uri()
subprocess.run(['rm', '-rf', PROFILE])
p = subprocess.Popen([CHROME, '--headless=new', '--disable-gpu', f'--remote-debugging-port={PORT}',
                      f'--user-data-dir={PROFILE}', '--window-size=1440,1000', URL],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
wsurl = None
for _ in range(80):
    try:
        d = json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json'))
        pg = [t for t in d if t.get('type') == 'page']
        if pg: wsurl = pg[0]['webSocketDebuggerUrl']; break
    except Exception: pass
    time.sleep(.25)


async def main():
  async with websockets.connect(wsurl, max_size=2**24) as ws:
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
      if 'exceptionDetails' in res:
        raise RuntimeError('JS: ' + str((res['exceptionDetails'].get('exception') or {}).get('description'))[:400])
      return res.get('result', {}).get('value')

    await send('Runtime.enable'); await send('Log.enable')
    # The debugger attaches to the startup tab before the file:// document is
    # committed; localStorage is unreadable until then.
    for _ in range(80):
      if await ev("document.readyState==='complete' && !!window.state && !!window.Proto"): break
      await asyncio.sleep(.15)
    await ev("localStorage.removeItem('dayspark.prototype.v1'); 'ok'")
    await send('Page.reload'); await asyncio.sleep(1.4)
    await ev("state.screen='ai-chat'; state.variant='normal'; render(); Proto.enhance(); 'ok'")
    await asyncio.sleep(.5)

    await ev("""(function(){
      document.querySelector('#ai-input').value='安排一下整理周会纪要并群发';
      document.querySelector('#ai-input').dispatchEvent(new Event('input',{bubbles:true}));
    })()""")
    await ev("(function(){var b=document.querySelector('[data-proto-action=\"ai-send-proto\"]')||document.querySelector('.ai-send');b.click();})()")
    await asyncio.sleep(1.2)
    print('reply', await ev("(function(){var a=[...document.querySelectorAll('.ai-msg')].filter(x=>/AI 助手/.test((x.querySelector('.ai-msg-head')||{}).textContent||''));var b=a[a.length-1];return b?b.textContent.replace(/\\s+/g,' ').slice(0,160):'none';})()"))

    card = await ev("""(function(){
      var a=[...document.querySelectorAll('.ai-action-primary')].filter(x=>x.dataset.protoAction==='ai-apply');
      return {count:a.length, kind:(function(){var m=(typeof AI_THREAD!=='undefined'?AI_THREAD:[]).filter(x=>x.role==='ai'&&x.act);return m.length?m[m.length-1].act.kind:null;})(), todo:(function(){var m=(typeof AI_THREAD!=='undefined'?AI_THREAD:[]).filter(x=>x.role==='ai'&&x.act);return m.length?m[m.length-1].act.todoId:null;})()};
    })()""")
    print('proposal card', card)
    assert card['count'] >= 1 and card['kind'] == 'plan' and card['todo'] == 'recurring', card
    await asyncio.sleep(.3)
    await ev("(function(){var a=[...document.querySelectorAll('.ai-action-primary')].filter(x=>x.dataset.protoAction==='ai-apply');a[a.length-1].click();})()")
    await asyncio.sleep(.5)

    occ_modal = await ev("""(function(){
      var s=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>x.querySelector('[data-occ]'));
      if(!s) return {found:false, modals:[...document.querySelectorAll('.proto-modal-scrim')].map(x=>x.textContent.slice(0,60))};
      return {found:true, title:(s.querySelector('.proto-modal-head')||{}).textContent||'', days:[...s.querySelectorAll('[data-occ]')].map(b=>b.dataset.occ), note:s.textContent};
    })()""")
    print('occ modal', json.dumps({k: (v if k != 'days' else v[:6]) for k, v in occ_modal.items()}, ensure_ascii=False)[:400])
    assert occ_modal['found'] is True
    assert '2026-11-27' in occ_modal['days']
    assert '不会默认' in occ_modal['note']
    await ev("document.querySelector('[data-occ=\"2026-11-27\"]').click()")
    await asyncio.sleep(.4)

    plan_state = await ev("""(function(){
      var s=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>/写入计划/.test(x.textContent));
      return {planOpen:!!s, text:s?s.textContent.replace(/\\s+/g,' ').slice(0,300):''};
    })()""")
    print('after pick', json.dumps(plan_state, ensure_ascii=False))
    assert plan_state['planOpen'] is True and '2026-11-27' in plan_state['text']
    await ev("""(function(){
      var s=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>/写入计划/.test(x.textContent));
      s.querySelector('.proto-btn.primary').click();
    })()""")
    await asyncio.sleep(.8)

    res = await ev("""(function(){
      var t=todoById('recurring');
      var allocs=(t.plans||[]).filter(p=>p&&p.state==='active');
      var nov27=plansOn('2026-11-27').filter(x=>x.todo.id==='recurring');
      var nov20=plansOn('2026-11-20').filter(x=>x.todo.id==='recurring');
      var nov06=plansOn('2026-11-06').filter(x=>x.todo.id==='recurring');
      return {
        allocs:allocs.map(p=>({date:p.date,start:p.start,end:p.end,occ:p.occurrenceDate,state:p.state})),
        nov27:nov27.map(x=>({allocId:x.allocId,start:x.start,end:x.end})),
        nov20Count:nov20.length, nov06Count:nov06.length,
        directPlanDate:t.plan&&t.plan.date,
        proposal:(function(){var m=(typeof AI_THREAD!=='undefined'?AI_THREAD:[]).filter(x=>x.role==='ai'&&x.act);return m.length?(m[m.length-1].proposalState||null):null;})(),
        toast:(document.querySelector('.toast')||{}).textContent||''
      };
    })()""")
    print('repeat result', json.dumps(res, ensure_ascii=False, indent=2))
    assert len(res['allocs']) == 1, res['allocs']
    a = res['allocs'][0]
    assert a['occ'] == '2026-11-27' and a['date'] == '2026-11-27', a
    assert len(res['nov27']) == 1 and res['nov20Count'] == 0 and res['nov06Count'] == 0
    assert res['directPlanDate'] == '2026-11-27'
    assert res['proposal'] == 'done', res['proposal']
    errs = [e.get('method') for e in errs if 'favicon' not in json.dumps(e)]
    print('errors', errs)
    print('TEST5 PASS')
  p.terminate()

asyncio.run(main())
