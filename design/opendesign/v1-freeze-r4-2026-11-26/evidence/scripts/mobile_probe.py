import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9447; PROFILE='/tmp/ds-mobile'
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
    async def ctext(sel,text):
      return await ev(f"(()=>{{const e=[...document.querySelectorAll({json.dumps(sel)})].find(x=>x.textContent.trim().includes({json.dumps(text)})); if(!e)return 'MISSING'; e.click(); return 'ok'}})()")
    await send('Runtime.enable'); await asyncio.sleep(1)
    await ev("state.device='mobile'; Proto.baseGo('today'); render(); 'ok'"); await asyncio.sleep(.5)
    print('frame',await ev("document.getElementById('frame').className"),'screen',await ev('state.screen'))
    # open a mobile task row for recurring? use open todo
    await ev("Proto.openTodo('recurring'); 'ok'"); await asyncio.sleep(.5)
    print('drawer mobile',await ev("!!document.querySelector('.m-detail-scroll')"))
    print('rem add',await ev("!!document.querySelector('.m-detail-scroll [data-proto-action=remind-add]')"))
    print('alloc',await ev("!!document.querySelector('.m-detail-scroll [data-proto-action=alloc-open]')"))
    print('history',await ev("!!document.querySelector('.m-detail-scroll [data-proto-action=occurrence-history]')"))
    print('click remind',await ev("document.querySelector('.m-detail-scroll [data-proto-action=remind-add]').click(); 'ok'")); await asyncio.sleep(.2)
    await ctext('.proto-modal-scrim [data-remind]','30 分钟前'); await asyncio.sleep(.3)
    print('rem',await ev("JSON.stringify({r:todoById('recurring').remind,rs:todoById('recurring').reminders})"))
    # plan from drawer edit
    await ev("(()=>{const b=[...document.querySelectorAll('.m-detail-scroll [data-action=edit-detail], .m-detail-scroll [data-action=plan-todo]')][0]; return b?b.dataset.action:'MISSING'})()")
    # new todo mobile
    await ev("Proto.baseGo('new-todo'); render(); 'ok'"); await asyncio.sleep(.4)
    print('new mobile',await ev("!!document.querySelector('.m-detail-scroll .cp-field')"),await ev("!!document.querySelector('.m-back')"))
    print('new rem add',await ev("!!document.querySelector('.m-detail-scroll [data-proto-action=remind-add]')"))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
