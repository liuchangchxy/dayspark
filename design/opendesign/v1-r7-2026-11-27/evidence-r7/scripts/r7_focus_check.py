from pathlib import Path
import asyncio, json, subprocess, time, urllib.request, websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9779
HERE=Path(__file__).resolve().parents[2]
URL=(HERE/'dayspark-prototype.html').as_uri()
subprocess.run(['rm','-rf',f'/tmp/prof-{PORT}'])
p=subprocess.Popen([CHROME,'--headless=new','--disable-gpu',f'--remote-debugging-port={PORT}',f'--user-data-dir=/tmp/prof-{PORT}','--window-size=1440,1000',URL],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
u=None
for _ in range(120):
    try:
        d=json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json')); pp=[t for t in d if t.get('type')=='page']
        if pp: u=pp[0]['webSocketDebuggerUrl']; break
    except Exception: pass
    time.sleep(.25)
async def main():
  async with websockets.connect(u, max_size=2**27) as ws:
    i=0; errs=[]
    async def call(m,params=None):
      nonlocal i; i+=1; mid=i
      await ws.send(json.dumps({'id':mid,'method':m,'params':params or {}}))
      while True:
        x=json.loads(await ws.recv())
        if x.get('method')=='Runtime.exceptionThrown': errs.append(((x['params']['exceptionDetails'].get('exception') or {}).get('description') or '')[:120])
        if x.get('id')==mid: return x
    async def ev(e):
      r=await call('Runtime.evaluate',{'expression':e,'returnByValue':True}); qq=r.get('result',{})
      if qq.get('exceptionDetails'): return 'ERR '+((qq['exceptionDetails'].get('exception') or {}).get('description') or '')[:140]
      return qq.get('result',{}).get('value')
    async def key(k,code,vk):
      await call('Input.dispatchKeyEvent',{'type':'keyDown','key':k,'code':code,'windowsVirtualKeyCode':vk,'nativeVirtualKeyCode':vk})
      await call('Input.dispatchKeyEvent',{'type':'keyUp','key':k,'code':code,'windowsVirtualKeyCode':vk,'nativeVirtualKeyCode':vk})
    async def fresh():
      await call('Page.navigate',{'url':URL}); await asyncio.sleep(1.9)
    await call('Runtime.enable'); await call('Page.enable'); await asyncio.sleep(1.8)

    # A. today reset on the calendar view (its own 今天 button)
    await ev("state.screen='cal-day';state.selectedDate='2026-11-21';render();Proto.enhance();'ok'"); await asyncio.sleep(.5)
    await ev("(function(){var b=[...document.querySelectorAll('.ph-right .tool')].find(x=>x.textContent.trim()==='今天');b.click();})()"); await asyncio.sleep(.5)
    print('A calendar 今天 ->', await ev("JSON.stringify({date:state.selectedDate,screen:state.screen})"))

    # B. direct rows, fresh
    await fresh()
    await ev("state.screen='todo-all';render();Proto.enhance();'ok'"); await asyncio.sleep(.6)
    await ev("document.querySelector('.product [data-action=open-todo]').click();'ok'"); await asyncio.sleep(.8)
    print('B rows ->', await ev("JSON.stringify({id:state.drawer&&state.drawer.id,err:(Proto.lastEnhancerError||'').slice(0,120),acts:[...document.querySelectorAll('.drawer .field-row')].map(r=>(r.querySelector('.f-label')||{}).textContent+'|'+r.dataset.protoAction)})"))
    await ev("(function(){var r=[...document.querySelectorAll('.drawer .field-row')].find(x=>x.querySelector('.f-label').textContent==='优先级');r.click();})()"); await asyncio.sleep(.5)
    print('B picker ->', await ev("JSON.stringify({modal:!!document.querySelector('.proto-modal-scrim'),title:(document.querySelector('.proto-modal-head')||{}).textContent,opts:[...document.querySelectorAll('[data-pri]')].map(x=>x.textContent.trim().slice(0,6))})"))
    await ev("(function(){var b=[...document.querySelectorAll('[data-pri]')].find(x=>x.dataset.pri==='9');b.click();})()"); await asyncio.sleep(.5)
    print('B write ->', await ev("JSON.stringify({prio:(todoById(state.drawer.id)||{}).priority,drawer:state.drawer&&state.drawer.id})"))
    await ev("(function(){var r=[...document.querySelectorAll('.drawer .field-row')].find(x=>x.querySelector('.f-label').textContent==='日历');r.click();})()"); await asyncio.sleep(.5)
    print('B cal picker ->', await ev("JSON.stringify({title:(document.querySelector('.proto-modal-head')||{}).textContent,n:document.querySelectorAll('[data-cal]').length})"))
    await ev("(function(){var b=[...document.querySelectorAll('.proto-modal-scrim [data-cal]')].find(x=>x.dataset.cal==='home');b.click();})()"); await asyncio.sleep(.5)
    print('B cal write ->', await ev("JSON.stringify({cal:(todoById(state.drawer.id)||{}).cal})"))
    await ev("(function(){var r=[...document.querySelectorAll('.drawer .field-row')].find(x=>x.querySelector('.f-label').textContent==='计划执行');r.click();})()"); await asyncio.sleep(.6)
    print('B plan ->', await ev("JSON.stringify({screen:state.screen,planTodo:state.planTodoId,returnScreen:state.planReturn})"))
    await key('Escape','Escape',27); await asyncio.sleep(.6)
    print('B plan exit ->', await ev("JSON.stringify({screen:state.screen,drawer:state.drawer&&state.drawer.id,variant:state.variant})"))

    # C. hide completed across reload, fresh
    await fresh()
    await ev("Proto.setHideCompleted(true);'ok'"); await asyncio.sleep(.5)
    print('C before reload ->', await ev("JSON.stringify({pref:Proto.data.prefs.hideCompleted,ls:(JSON.parse(localStorage.getItem('dayspark.prototype.v1')||'{}').data||{}).prefs})"))
    await asyncio.sleep(.6)
    await fresh()
    print('C after reload ->', await ev("JSON.stringify({pref:Proto.data.prefs.hideCompleted})"))
    await ev("state.screen='todo-all';render();Proto.enhance();'ok'"); await asyncio.sleep(.6)
    print('C hidden ->', await ev("JSON.stringify({groups:[...document.querySelectorAll('.completed-group,.more-row')].map(e=>({t:e.textContent.trim().slice(0,10),d:e.style.display})),rows:document.querySelectorAll('.todo-row').length})"))
  p.terminate()
asyncio.run(main())
