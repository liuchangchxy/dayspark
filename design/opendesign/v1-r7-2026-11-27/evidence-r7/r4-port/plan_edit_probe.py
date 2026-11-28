import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9441; PROFILE='/tmp/ds-planedit'
URL='file:///tmp/r4-final/dayspark-prototype.html'
subprocess.run(['rm','-rf',PROFILE])
p=subprocess.Popen([CHROME,'--headless=new','--disable-gpu',f'--remote-debugging-port={PORT}',f'--user-data-dir={PROFILE}','--window-size=1440,1000',URL],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
wsurl=None
for _ in range(80):
    try:
        d=json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json')); pg=[t for t in d if t.get('type')=='page']
        if pg: wsurl=pg[0]['webSocketDebuggerUrl']; break
    except Exception: pass
    time.sleep(.25)
async def main():
  async with websockets.connect(wsurl,max_size=2**24) as ws:
    i=0; evs=[]
    async def send(m,**pa):
      nonlocal i; i+=1; mid=i
      await ws.send(json.dumps({'id':mid,'method':m,'params':pa}))
      while True:
        x=json.loads(await ws.recv())
        if x.get('id')==mid: return x
        evs.append(x)
    async def ev(x):
      r=await send('Runtime.evaluate',expression=x,returnByValue=True); res=r.get('result',{})
      if 'exceptionDetails' in res: return {'ERR':res['exceptionDetails'].get('text'),'d':res.get('result',{}).get('description')}
      return res.get('result',{}).get('value')
    await send('Runtime.enable'); await asyncio.sleep(1)
    print('add',await ev("(()=>{const t=todoById('report'); const a=DS3.addAllocation(t,{date:'2026-11-20',start:'09:00',end:'10:00'}); render(); return JSON.stringify([a.id,t.plans.map(p=>p.id)])})()"))
    await ev("Proto.openTodo('report'); 'ok'"); await asyncio.sleep(.5)
    print('allocbtn',await ev("JSON.stringify([...document.querySelectorAll('[data-proto-action=alloc-open]')].map(b=>b.textContent.trim()))"))
    print('open list',await ev("document.querySelector('[data-proto-action=alloc-open]').click(); 'ok'")); await asyncio.sleep(.3)
    print('rows',await ev("JSON.stringify([...document.querySelectorAll('.proto-modal-scrim [data-edit]')].map(b=>b.dataset.edit))"))
    ids=await ev("JSON.stringify([...document.querySelectorAll('.proto-modal-scrim [data-edit]')].map(b=>b.dataset.edit))")
    ids=json.loads(ids)
    target=ids[-1]
    print('edit second',await ev(f"document.querySelector('[data-edit=\"{target}\"]').click(); 'ok'")); await asyncio.sleep(.3)
    print('picker',await ev('state.planAllocId'),await ev('state.planReturnEdit'))
    await ev("document.querySelector('#plan-start').value='11:00'; document.querySelector('#plan-end').value='12:00'; 'ok'")
    await ev("document.querySelector('[data-action=plan-submit]').click(); 'ok'"); await asyncio.sleep(.4)
    print('plans',await ev("JSON.stringify(todoById('report').plans.map(p=>[p.id,p.start,p.end,p.state]))"))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
