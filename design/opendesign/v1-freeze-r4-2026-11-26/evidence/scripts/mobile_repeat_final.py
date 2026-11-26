import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9451; PROFILE='/tmp/ds-mobrepeat'
URL='file:///tmp/r4-final/dayspark-prototype.html'
subprocess.run(['rm','-rf',PROFILE])
p=subprocess.Popen([CHROME,'--headless=new','--disable-gpu',f'--remote-debugging-port={PORT}',f'--user-data-dir={PROFILE}','--window-size=390,844',URL],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
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
    await ev("state.device='mobile'; (()=>{const t=todoById('recurring'); DS3.addAllocation(t,{date:'2026-11-26',start:'09:00',end:'10:00',occurrenceDate:'2026-11-27'}); Proto.baseGo('cal-day'); state.selectedDate='2026-11-26'; render(); return 'ok'})()"); await asyncio.sleep(.6)
    print('plansOn',await ev("JSON.stringify(plansOn('2026-11-26').map(x=>[x.todo.id,x.allocId,x.start]))")); print('all',await ev("JSON.stringify(todoById('recurring').plans)")); print('mblocks',await ev("JSON.stringify([...document.querySelectorAll('.m-block[data-alloc]')].map(b=>[b.dataset.id,b.dataset.alloc,b.textContent.replace(/\\s+/g,' ').trim().slice(0,40)]))"))
    print('click block',await ev("(()=>{const b=document.querySelector('.m-block.is-plan[data-alloc]'); if(!b)return 'MISSING'; b.click(); return 'ok'})()")); await asyncio.sleep(.4)
    print('occ',await ev('JSON.stringify([state.occurId,state.occurDate])'),'drawer',await ev('JSON.stringify(state.drawer)'))
    print('done btn',await ev("JSON.stringify([...document.querySelectorAll('.m-detail-scroll [data-action=toggle-done]')].map(b=>[b.dataset.date,b.textContent.trim()]))"))
    print('click done',await ev("document.querySelector('.m-detail-scroll [data-action=toggle-done]').click(); 'ok'")); await asyncio.sleep(.3)
    print('done',await ev('JSON.stringify(state.doneInstances)'))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
