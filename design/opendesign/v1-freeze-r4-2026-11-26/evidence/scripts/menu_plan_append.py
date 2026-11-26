import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9480; PROFILE='/tmp/ds-menuappend'
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
    i=0; errs=[]
    async def send(m,**pa):
      nonlocal i; i+=1; mid=i
      await ws.send(json.dumps({'id':mid,'method':m,'params':pa}))
      while True:
        x=json.loads(await ws.recv())
        if x.get('id')==mid: return x
        if x.get('method') in ('Runtime.exceptionThrown','Log.entryAdded'): errs.append(x)
    async def ev(x):
      r=await send('Runtime.evaluate',expression=x,returnByValue=True); res=r.get('result',{})
      if 'exceptionDetails' in res: return {'ERR':res['exceptionDetails'].get('text'),'d':res.get('result',{}).get('description')}
      return res.get('result',{}).get('value')
    await send('Runtime.enable'); await send('Log.enable'); await asyncio.sleep(1)
    print('rows',await ev("JSON.stringify([...document.querySelectorAll('.task-row')].map(x=>[x.dataset.id,x.dataset.action,x.textContent.trim().slice(0,12)]))"))
    print('menu',await ev("(()=>{const r=[...document.querySelectorAll('.task-row')][0]; if(!r)return JSON.stringify([...document.querySelectorAll('.task-row')].map(x=>x.outerHTML.slice(0,200))); r.dispatchEvent(new MouseEvent('contextmenu',{bubbles:true,clientX:400,clientY:300,button:2})); return 'ok';})()"))
    print('click plan',await ev("(()=>{const b=[...document.querySelectorAll('.proto-menu [data-m]')].find(x=>x.dataset.m==='plan'); if(!b)return 'MISSING'; b.click(); return 'ok';})()")); await asyncio.sleep(.35)
    print('state',await ev("JSON.stringify({screen:state.screen,todo:state.planTodoId,alloc:state.planAllocId,occ:state.planOccurrence,ret:state.planReturn,edit:state.planReturnEdit})"))
    await ev("document.querySelector('#plan-start').value='09:00'; document.querySelector('#plan-end').value='10:00'; 'ok'")
    print('submit',await ev("(()=>{const b=document.querySelector('[data-action=plan-submit]'); if(!b)return 'MISSING'; b.click(); return 'ok'})()")); await asyncio.sleep(.5)
    print('plans',await ev("JSON.stringify(DS3.allocations(todoById('rent')).map(p=>[p.id,p.start,p.end]))"))
    print('errs',[e.get('method') for e in errs])
  p.terminate()
asyncio.run(main())
