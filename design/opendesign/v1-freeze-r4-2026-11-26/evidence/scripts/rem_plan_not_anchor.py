import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9472; PROFILE='/tmp/ds-remplan'
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
    async def click_text(sel,text):
      return await ev(f"(()=>{{const e=[...document.querySelectorAll({json.dumps(sel)})].find(x=>x.textContent.trim().includes({json.dumps(text)})); if(!e)return 'MISSING'; e.click(); return 'ok'}})()")
    await send('Runtime.enable'); await send('Log.enable'); await asyncio.sleep(1)
    await ev("Proto.baseGo('new-todo'); render(); 'ok'"); await asyncio.sleep(.4)
    await ev("(()=>{const i=document.querySelector('#new-title'); i.value='只有计划没有截止'; i.dispatchEvent(new Event('input',{bubbles:true})); return 'ok'})()")
    # add a plan segment through the real composer picker
    await ev("(()=>{const r=[...document.querySelectorAll('.cp-field')].find(x=>x.querySelector('.k')&&x.querySelector('.k').textContent.trim()==='计划执行'); if(!r)return 'MISSING'; r.click(); return 'ok'})()"); await asyncio.sleep(.3)
    await ev("document.querySelector('#nf-plan-start').value='09:00'; document.querySelector('#nf-plan-end').value='10:00'; 'ok'")
    print('add plan',await click_text('.proto-modal-scrim .proto-btn','加入草稿')); await asyncio.sleep(.3)
    print('draft plan',await ev("JSON.stringify({plans:Proto.data.newDraft.plans,plan:Proto.data.newDraft.plan&&Proto.data.newDraft.plan.start,due:Proto.data.newDraft.due})"))
    await ev("document.querySelector('[data-proto-action=remind-add]').click(); 'ok'"); await asyncio.sleep(.2)
    print('picker disabled with plan only',await ev("[...document.querySelectorAll('.proto-modal-scrim [data-remind]')].map(e=>e.disabled).join(',')"))
    print('picker note',await ev("(()=>{const n=document.querySelector('.proto-modal-scrim .proto-note');return n?n.textContent.trim():''})()"))
    await click_text('.proto-modal-scrim [data-remind]','不提醒'); await asyncio.sleep(.2)
    # save todo with plan but no due
    print('save',await ev("(()=>{const b=[...document.querySelectorAll('.new-page button')].find(x=>x.textContent.trim().includes('记下待办')); if(!b)return 'MISSING'; b.click(); return 'ok'})()")); await asyncio.sleep(.5)
    print('saved',await ev("(()=>{const t=TODOS[0];return JSON.stringify({due:t.due,time:t.dueTime,remind:t.remind,plans:DS3.allocations(t).map(p=>[p.start,p.end])})})()"))
    # existing todo with due time: add reminder, then change its plan time and confirm reminder identity/reference untouched
    await ev("Proto.baseGo('today'); render(); 'ok'"); await asyncio.sleep(.3)
    await ev("Proto.openTodo('report'); 'ok'"); await asyncio.sleep(.4)
    print('report remind before',await ev("JSON.stringify({r:todoById('report').remind,rs:todoById('report').reminders||[]})"))
    await ev("(()=>{const b=document.querySelector('[data-proto-action=remind-add]'); if(!b)return 'MISSING'; b.click(); return 'ok'})()"); await asyncio.sleep(.2)
    await click_text('.proto-modal-scrim [data-remind]','1 小时前'); await asyncio.sleep(.3)
    const_before=await ev("JSON.stringify({r:todoById('report').remind,rs:todoById('report').reminders||[]})")
    print('after add 1h',const_before)
    await ev("(()=>{const b=document.querySelector('[data-proto-action=alloc-open]'); if(!b)return 'MISSING'; b.click(); return 'ok'})()"); await asyncio.sleep(.3)
    await ev("(()=>{const e=document.querySelector('.proto-modal-scrim [data-edit]'); if(!e)return 'MISSING'; e.click(); return 'ok'})()"); await asyncio.sleep(.3)
    await ev("document.querySelector('#plan-start').value='10:30'; document.querySelector('#plan-end').value='11:30'; document.querySelector('[data-action=plan-submit]').click(); 'ok'"); await asyncio.sleep(.4)
    print('after plan move',await ev("JSON.stringify({r:todoById('report').remind,rs:todoById('report').reminders||[],plans:DS3.allocations(todoById('report')).map(p=>[p.start,p.end])})"))
    print('errs', [e.get('method') for e in errs])
  p.terminate()
asyncio.run(main())
