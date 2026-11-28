"""R4 #14b on the R7 artifact: a repeating target cannot be written when its
occurrence picker was cancelled.

Product path: 确认写入 → plan modal → choose the repeating target → the
instance picker opens automatically → cancel it → press 写入 anyway → the
write must be blocked with a real toast and zero new allocations.
"""
import asyncio, json, pathlib, subprocess, time, urllib.request, websockets

CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
PORT = 9485
PROFILE = '/tmp/ds-aiocc'
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
    for _ in range(80):
      if await ev("document.readyState==='complete' && !!window.state && !!window.Proto"): break
      await asyncio.sleep(.15)
    await ev("localStorage.removeItem('dayspark.prototype.v1'); 'ok'")
    await send('Page.reload'); await asyncio.sleep(1.3)
    await ev("state.screen='ai-chat'; state.variant='normal'; render(); Proto.enhance(); 'ok'")
    await asyncio.sleep(.5)

    await ev("""(function(){
      document.querySelector('#ai-input').value='安排一下整理周会纪要并群发';
      document.querySelector('#ai-input').dispatchEvent(new Event('input',{bubbles:true}));
      var b=document.querySelector('[data-proto-action="ai-send-proto"]')||document.querySelector('.ai-send');
      b.click();
    })()""")
    await asyncio.sleep(1.2)
    await ev("(function(){var a=[...document.querySelectorAll('.ai-action-primary')].filter(x=>x.dataset.protoAction==='ai-apply');a[a.length-1].click();})()")
    await asyncio.sleep(.5)

    # The proposal targets the repeating todo directly; its own instance picker
    # must open without an extra target step.
    assert await ev("""(function(){var s=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>x.querySelector('[data-occ]'));return !!s;})()""") is True
    # Cancel the picker: the plan modal must stay open with the field unfilled.
    await ev("""(function(){var s=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>x.querySelector('[data-occ]'));s.querySelector('.proto-btn').click();})()""")
    await asyncio.sleep(.3)
    txt = await ev("""(function(){var m=document.querySelector('.proto-modal');return m?m.textContent.replace(/\\s+/g,' ').slice(0,200):'';})()""")
    print('plan modal after cancel:', txt)
    assert '选择这一次实例' in txt

    before = await ev("(todoById('recurring').plans||[]).length")
    await ev("""(function(){
      var s=[...document.querySelectorAll('.proto-modal-scrim')].find(x=>/写入计划/.test(x.textContent));
      s.querySelector('.proto-btn.primary').click();
    })()""")
    await asyncio.sleep(.4)
    after = await ev("(todoById('recurring').plans||[]).length")
    toast = await ev("(document.querySelector('.toast')||{}).textContent||''")
    print('plans before/after blocked write:', before, after, 'toast', toast)
    assert before == after == 0
    assert '要先选这一次实例' in toast
    assert await ev("Proto.lastEnhancerError || null") is None
    errs = [e for e in errs if 'favicon' not in json.dumps(e)]
    print('errors', [e.get('method') for e in errs])
    print('TEST8 PASS')
  p.terminate()

asyncio.run(main())
