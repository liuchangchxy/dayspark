import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9427; PROFILE='/tmp/ds-newremsave'
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
    await ev("Proto.baseGo('new-event'); render(); 'ok'"); await asyncio.sleep(.4)
    await ev("(()=>{const i=document.querySelector('#new-title'); i.value='多提醒日程'; i.dispatchEvent(new Event('input',{bubbles:true})); return 'ok'})()")
    # add 30 min (primary 15 already)
    await ev("document.querySelector('[data-proto-action=remind-add]').click(); 'ok'"); await asyncio.sleep(.2)
    await click_text('.proto-modal-scrim [data-remind]','30 分钟前'); await asyncio.sleep(.3)
    print('draft',await ev("JSON.stringify({r:Proto.data.newDraft.remind,rs:Proto.data.newDraft.reminders})"))
    print('btns',await ev("JSON.stringify([...document.querySelectorAll('.new-page button')].map(b=>[b.textContent.trim(),b.dataset.action,b.dataset.protoAction,b.className]))")); await ev("(()=>{const b=[...document.querySelectorAll('.new-page button')].find(x=>x.textContent.trim().includes('创建日程')); if(!b)return 'MISSING'; b.click(); return 'ok'})()"); await asyncio.sleep(.5)
    print('event',await ev("JSON.stringify(EVENTS[EVENTS.length-1])"))
    # new todo with due time
    await ev("Proto.baseGo('new-todo'); render(); 'ok'"); await asyncio.sleep(.4)
    await ev("(()=>{const i=document.querySelector('#new-title'); i.value='多提醒待办'; i.dispatchEvent(new Event('input',{bubbles:true})); return 'ok'})()")
    await ev("document.querySelector('[data-proto-action=remind-add]').click(); 'ok'"); await asyncio.sleep(.2)
    print('no anchor picker',await ev("[...document.querySelectorAll('.proto-modal-scrim [data-remind]')].map(e=>e.disabled).join(',')"))
    await click_text('.proto-modal-scrim [data-remind]','不提醒'); await asyncio.sleep(.2)
    # set due datetime via new-field 截止
    await ev("(()=>{const r=[...document.querySelectorAll('.cp-field')].find(x=>x.querySelector('.k')&&x.querySelector('.k').textContent.trim()==='截止'); r.click(); return 'ok'})()"); await asyncio.sleep(.3)
    await ev("(()=>{const b=[...document.querySelectorAll('.proto-modal-scrim [data-mode]')].find(x=>x.dataset.mode==='time'); b.click(); const t=document.querySelector('#nf-due-time'); t.value='18:00'; return 'ok'})()")
    await click_text('.proto-modal-scrim .proto-btn','应用'); await asyncio.sleep(.3)
    print('due',await ev("JSON.stringify({due:Proto.data.newDraft.due,time:Proto.data.newDraft.dueTime})"))
    await ev("document.querySelector('[data-proto-action=remind-add]').click(); 'ok'"); await asyncio.sleep(.2)
    print('anchor now',await ev("[...document.querySelectorAll('.proto-modal-scrim [data-remind]')].map(e=>e.disabled).join(',')"))
    await click_text('.proto-modal-scrim [data-remind]','30 分钟前'); await asyncio.sleep(.3)
    print('draft2',await ev("JSON.stringify({r:Proto.data.newDraft.remind,rs:Proto.data.newDraft.reminders})"))
    await ev("(()=>{const b=[...document.querySelectorAll('.new-page button')].find(x=>x.textContent.trim().includes('记下待办')); if(!b)return 'MISSING'; b.click(); return 'ok'})()"); await asyncio.sleep(.5)
    print('todo',await ev("JSON.stringify(TODOS[0])"))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
