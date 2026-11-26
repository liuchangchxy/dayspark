import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9421; PROFILE='/tmp/ds-remprobe'
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
    async def click_text(sel,text):
      return await ev(f"(()=>{{const e=[...document.querySelectorAll({json.dumps(sel)})].find(x=>x.textContent.trim().includes({json.dumps(text)})); if(!e)return 'MISSING'; e.click(); return 'ok'}})()")
    await send('Runtime.enable'); await asyncio.sleep(1)
    # detail todo
    await ev("Proto.openTodo('report'); 'ok'"); await asyncio.sleep(.5)
    print('addbtn',await ev("!!document.querySelector('[data-proto-action=remind-add]')"))
    print('clickadd',await ev("document.querySelector('[data-proto-action=remind-add]').click(); 'ok'")); await asyncio.sleep(.3)
    print('picker rows',await ev("[...document.querySelectorAll('.proto-modal-scrim [data-remind]')].map(e=>e.textContent.trim()).join('|')"))
    print('pick30',await click_text('.proto-modal-scrim [data-remind]','30 分钟前')); await asyncio.sleep(.4)
    print('todo rem',await ev("JSON.stringify({r:todoById('report').remind,rs:todoById('report').reminders})"))
    print('extras',await ev("document.querySelectorAll('[data-remind-extra]').length"))
    # new todo composer
    await ev("Proto.baseGo('new-todo'); render(); 'ok'"); await asyncio.sleep(.5)
    print('new add',await ev("!!document.querySelector('[data-proto-action=remind-add]')"), await ev("document.querySelector('.cp-field .k')&&document.querySelector('.cp-field .k').textContent"))
    print('new click',await ev("document.querySelector('[data-proto-action=remind-add]').click(); 'ok'")); await asyncio.sleep(.3)
    print('new picker',await ev("[...document.querySelectorAll('.proto-modal-scrim [data-remind]')].map(e=>[e.textContent.trim(),e.disabled]).join('|')"))
    print('pick abs?',await click_text('.proto-modal-scrim [data-remind]','不提醒')); await asyncio.sleep(.3)
    # new event
    await ev("Proto.baseGo('new-event'); render(); 'ok'"); await asyncio.sleep(.5)
    print('new event add',await ev("!!document.querySelector('[data-proto-action=remind-add]')"))
    print('new event click',await ev("document.querySelector('[data-proto-action=remind-add]').click(); 'ok'")); await asyncio.sleep(.3)
    print('event picker',await ev("[...document.querySelectorAll('.proto-modal-scrim [data-remind]')].map(e=>[e.textContent.trim(),e.disabled]).join('|')"))
    print('pick15',await click_text('.proto-modal-scrim [data-remind]','15 分钟前')); await asyncio.sleep(.4)
    print('draft',await ev("JSON.stringify({r:Proto.data.newDraft.remind,rs:Proto.data.newDraft.reminders})"))
    print('crets',await ev("document.querySelectorAll('.cp-remind-extra').length"))
    # detail event
    await ev("Proto.openEvent('weekly'); 'ok'"); await asyncio.sleep(.5)
    print('event detail add',await ev("!!document.querySelector('[data-proto-action=remind-add]')"))
    print('event detail click',await ev("document.querySelector('[data-proto-action=remind-add]').click(); 'ok'")); await asyncio.sleep(.3)
    print('event detail picker',await ev("[...document.querySelectorAll('.proto-modal-scrim [data-remind]')].map(e=>[e.textContent.trim(),e.disabled]).join('|')"))
    print('event pick30',await click_text('.proto-modal-scrim [data-remind]','30 分钟前')); await asyncio.sleep(.4)
    print('event rem',await ev("JSON.stringify({r:eventById('weekly').remind,rs:eventById('weekly').reminders})"))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
