import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9425; PROFILE='/tmp/ds-plandraft'
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
    async def add_plan(start,end):
      print('open plan', await ev("(()=>{const b=[...document.querySelectorAll('[data-action=plan-todo]')].find(x=>x.closest('.drawer')); if(!b)return 'MISSING'; b.click(); return 'ok'})()"))
      await asyncio.sleep(.3)
      print('screen',await ev('state.screen'),'returnEdit',await ev('state.planReturnEdit'))
      await ev(f"document.querySelector('#plan-start').value='{start}'; document.querySelector('#plan-end').value='{end}'; 'ok'")
      print('submit',await ev("document.querySelector('[data-action=plan-submit]').click(); 'ok'")); await asyncio.sleep(.3)
    await send('Runtime.enable'); await asyncio.sleep(1)
    await ev("Proto.openTodo('report'); 'ok'"); await asyncio.sleep(.4)
    await ev("document.querySelector('[data-action=edit-detail]').click(); 'ok'"); await asyncio.sleep(.4)
    await add_plan('09:00','10:00')
    print('after 1',await ev("JSON.stringify({src:todoById('report').plans.length,draft:state.draft.plans.length,plan:state.draft.plan&&state.draft.plan.start,screen:state.screen,edit:state.drawerEdit})"))
    await add_plan('11:00','12:00')
    print('after 2',await ev("JSON.stringify({src:todoById('report').plans.length,draft:state.draft.plans.map(p=>[p.id,p.start]),plan:state.draft.plan&&state.draft.plan.start})"))
    print('cancel',await ev("document.querySelector('.d-foot [data-action=close-drawer]').click(); 'ok'")); await asyncio.sleep(.3)
    print('src after cancel',await ev("todoById('report').plans.length"))
    # redo and save
    await ev("Proto.openTodo('report'); 'ok'"); await asyncio.sleep(.3)
    await ev("document.querySelector('[data-action=edit-detail]').click(); 'ok'"); await asyncio.sleep(.3)
    await add_plan('09:00','10:00')
    print('src still',await ev("todoById('report').plans.length"),'draft',await ev("state.draft.plans.length"))
    print('save',await ev("document.querySelector('.d-foot [data-action=save-detail]').click(); 'ok'")); await asyncio.sleep(.4)
    print('src after save',await ev("JSON.stringify(todoById('report').plans.map(p=>[p.id,p.start,p.end,p.state]))"))
    print('plan derive',await ev("JSON.stringify(todoById('report').plan)"))
    print('cal blocks',await ev("JSON.stringify(plansOn('2026-11-20').filter(x=>x.todo.id==='report').map(x=>[x.allocId,x.start,x.end]))"))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
