import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9473; PROFILE='/tmp/ds-repdetail'
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
    # Detail without an explicit instance: must ask, never use today/browse date.
    print('open',await ev("Proto.openTodo('recurring'); 'ok'")); await asyncio.sleep(.4)
    print('buttons',await ev("JSON.stringify([...document.querySelectorAll('.drawer [data-action=toggle-done]')].map(b=>[b.dataset.date,b.textContent.trim()]))"))
    print('click',await ev("(()=>{const b=document.querySelector('.drawer [data-action=toggle-done]'); if(!b)return 'MISSING'; b.click(); return 'ok'})()")); await asyncio.sleep(.4)
    print('after click',await ev("JSON.stringify({done:state.doneInstances,modal:!!document.querySelector('[data-occ]'),text:(document.querySelector('.proto-modal-scrim')||{}).innerText||''})"))
    # choose 11/27 in the ask dialog
    print('choose',await ev("(()=>{const b=document.querySelector('[data-occ=\"2026-11-27\"]'); if(!b)return 'MISSING'; b.click(); return 'ok'})()")); await asyncio.sleep(.5)
    print('done',await ev("JSON.stringify({done:state.doneInstances,occ:[state.occurId,state.occurDate]})"))
    # Undo only that instance
    print('undo click',await ev("(()=>{const b=document.querySelector('.drawer [data-action=toggle-done]'); if(!b)return 'MISSING'; b.click(); return 'ok'})()")); await asyncio.sleep(.4)
    print('undo dialog',await ev("(()=>{const b=document.querySelector('[data-occ=\"2026-11-27\"]'); if(!b)return 'MISSING'; b.click(); return 'ok'})()")); await asyncio.sleep(.5)
    print('after undo',await ev("JSON.stringify({done:state.doneInstances,occ:[state.occurId,state.occurDate]})"))
    print('errs', [e.get('method') for e in errs])
  p.terminate()
asyncio.run(main())
