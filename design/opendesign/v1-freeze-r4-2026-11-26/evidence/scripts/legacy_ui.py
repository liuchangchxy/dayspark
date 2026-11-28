import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9449; PROFILE='/tmp/ds-legacyui'
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
    await ev("TODOS.push({id:'legacy1',title:'旧规则待办',cal:'work',legacyRrule:'FREQ=WEEKLY;BYDAY=FR',priority:5}); render(); Proto.openTodo('legacy1'); 'ok'"); await asyncio.sleep(.5)
    print('banner',await ev("document.body.textContent.includes('这条重复规则来自旧版本')"))
    print('migrate btn',await ev("!!document.querySelector('[data-proto-action=legacy-migrate]')"))
    print('click',await ev("document.querySelector('[data-proto-action=legacy-migrate]').click(); 'ok'")); await asyncio.sleep(.3)
    print('modal',await ev("document.querySelector('.proto-modal-scrim')&&document.querySelector('.proto-modal-scrim').textContent.replace(/\\s+/g,' ').slice(0,160)"))
    # cancel path
    print('cancel',await ctext('.proto-modal-scrim .proto-modal-foot .proto-btn','取消')); await asyncio.sleep(.2)
    print('after cancel',await ev("JSON.stringify({l:todoById('legacy1').legacyRrule,r:todoById('legacy1').repeat,a:todoById('legacy1').repeatAnchor,tz:todoById('legacy1').repeatTimezone})"))
    # reopen and set
    await ev("document.querySelector('[data-proto-action=legacy-migrate]').click(); 'ok'"); await asyncio.sleep(.2)
    print('tz opts',await ev("[...document.querySelectorAll('#legacy-tz option')].map(o=>o.value).join('|')"))
    await ev("(()=>{const s=document.querySelector('#legacy-tz'); s.value='Asia/Shanghai'; const a=document.querySelector('#legacy-anchor'); a.value='2026-11-06'; return 'ok'})()")
    print('rule click',await ev("document.querySelector('[data-legacy-rule]').click(); 'ok'")); await asyncio.sleep(.2)
    print('pick week',await ctext('.proto-modal-scrim [data-repeat]','每周')); await asyncio.sleep(.1)
    print('pick fri',await ctext('.proto-modal-scrim [data-day]','周五')); await asyncio.sleep(.1)
    print('apply rule',await ctext('.proto-modal-scrim .proto-modal-foot .proto-btn','应用')); await asyncio.sleep(.3)
    # top modal is legacy again; click write
    print('write',await ctext('.proto-modal-scrim .proto-modal-foot .proto-btn','写入新规则')); await asyncio.sleep(.3)
    print('after write',await ev("JSON.stringify({l:todoById('legacy1').legacyRrule,r:todoById('legacy1').repeat,a:todoById('legacy1').repeatAnchor,tz:todoById('legacy1').repeatTimezone})"))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
