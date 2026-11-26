import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9443; PROFILE='/tmp/ds-plancancel'
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
    await ev("(()=>{const t=todoById('report'); DS3.addAllocation(t,{date:'2026-11-20',start:'09:00',end:'10:00'}); render(); return 'ok'})()")
    await ev("Proto.openTodo('report'); 'ok'"); await asyncio.sleep(.4)
    await ev("document.querySelector('[data-proto-action=alloc-open]').click(); 'ok'"); await asyncio.sleep(.3)
    print('labels',await ev("JSON.stringify([...document.querySelectorAll('.proto-modal-scrim .proto-list-row')].map(r=>r.textContent.replace(/\\s+/g,' ').trim()))"))
    print('plans',await ev("JSON.stringify(todoById('report').plans.map(p=>[p.id,p.state]))"),'plan',await ev('JSON.stringify(todoById("report").plan)'))
    print('list text',await ev("document.querySelector('.proto-modal-scrim')&&document.querySelector('.proto-modal-scrim').textContent.replace(/\\s+/g,' ').slice(0,220)"))
    await ev("document.querySelector('.proto-modal-scrim .proto-modal-head button, .proto-modal-foot .proto-btn').click(); 'ok'"); await asyncio.sleep(.3)
    print('field',await ev("JSON.stringify([...document.querySelectorAll('.field-row')].map(r=>r.textContent.replace(/\\s+/g,' ').trim()).filter(x=>x.includes('计划执行')))"))
    print('btn',await ev("JSON.stringify([...document.querySelectorAll('[data-proto-action=alloc-open]')].map(b=>b.textContent.trim()))"))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
