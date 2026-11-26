import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9433; PROFILE='/tmp/ds-repplandraft'
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
    async def ctext(sel,text):
      return await ev(f"(()=>{{const e=[...document.querySelectorAll({json.dumps(sel)})].find(x=>x.textContent.trim().includes({json.dumps(text)})); if(!e)return 'MISSING'; e.click(); return 'ok'}})()")
    await send('Runtime.enable'); await asyncio.sleep(1)
    await ev("Proto.openTodo('recurring'); 'ok'"); await asyncio.sleep(.4)
    await ev("document.querySelector('[data-action=edit-detail]').click(); 'ok'"); await asyncio.sleep(.4)
    print('click plan',await ev("(()=>{const b=[...document.querySelectorAll('[data-action=plan-todo]')].find(x=>x.closest('.drawer')); if(!b)return 'MISSING'; b.click(); return 'ok'})()")); await asyncio.sleep(.4)
    print('modals',await ev("JSON.stringify([...document.querySelectorAll('.proto-modal-scrim')].map(s=>s.querySelector('.proto-modal-head span')&&s.querySelector('.proto-modal-head span').textContent))"))
    print('pick27',await ctext('.proto-modal-scrim [data-occ]','2026-11-27')); await asyncio.sleep(.4)
    print('screen',await ev('state.screen'),'occ',await ev('state.planOccurrence'),'date',await ev('state.planDate'))
    await ev("(()=>{const s=document.querySelector('#plan-start'),e=document.querySelector('#plan-end'); s.value='09:00';e.value='10:00'; return 'ok'})()")
    print('submit',await ev("document.querySelector('[data-action=plan-submit]').click(); 'ok'")); await asyncio.sleep(.4)
    print('draft',await ev("JSON.stringify({src:todoById('recurring').plans.length,draft:state.draft.plans,edit:state.drawerEdit})"))
    print('cancel',await ev("document.querySelector('.d-foot [data-action=close-drawer]').click(); 'ok'")); await asyncio.sleep(.3)
    print('after cancel',await ev("todoById('recurring').plans.length"))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
