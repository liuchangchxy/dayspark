from pathlib import Path
import asyncio, json, subprocess, time, urllib.request, websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9765
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
        if x.get('method')=='Runtime.exceptionThrown': errs.append(((x['params']['exceptionDetails'].get('exception') or {}).get('description') or '')[:160])
        if x.get('id')==mid: return x
    async def ev(e):
      r=await call('Runtime.evaluate',{'expression':e,'returnByValue':True}); qq=r.get('result',{})
      if qq.get('exceptionDetails'): return 'ERR '+((qq['exceptionDetails'].get('exception') or {}).get('description') or '')[:160]
      return qq.get('result',{}).get('value')
    async def key(k,code,vk):
      await call('Input.dispatchKeyEvent',{'type':'keyDown','key':k,'code':code,'windowsVirtualKeyCode':vk,'nativeVirtualKeyCode':vk})
      await call('Input.dispatchKeyEvent',{'type':'keyUp','key':k,'code':code,'windowsVirtualKeyCode':vk,'nativeVirtualKeyCode':vk})
    await call('Runtime.enable'); await call('Page.enable'); await asyncio.sleep(1.8)

    # add subtask + tag from a read-only drawer, and verify it persisted through reload
    await ev("state.screen='todo-all';state.selectedDate='2026-11-20';render();Proto.enhance();document.querySelector('.product [data-action=open-todo]').click();'ok'")
    await asyncio.sleep(.7)
    print('ADDS', await ev("JSON.stringify({sub:[...document.querySelectorAll('.drawer .d-sec-head [data-proto-action=direct-subtask-add]')].length,tag:[...document.querySelectorAll('.drawer .d-sec-head [data-proto-action=direct-tags]')].length,row_add:[...document.querySelectorAll('.drawer .d-sec-head button')].map(b=>b.textContent.trim()+'|'+(b.dataset.protoAction||''))})"))
    await ev("(function(){var b=document.querySelector('.drawer .d-sec-head [data-proto-action=direct-subtask-add]');b.click();})()")
    await asyncio.sleep(.4)
    print('SUBTASK-PROMPT', await ev("JSON.stringify({modal:!!document.querySelector('.proto-modal-scrim'),title:(document.querySelector('.proto-modal-head')||{}).textContent})"))
    await ev("(function(){var i=document.querySelector('.proto-modal-body .proto-input');i.value='R7 新子任务';})()")
    await ev("(function(){var b=[...document.querySelectorAll('.proto-modal-foot .proto-btn')].find(x=>x.textContent==='确定'||x.textContent==='添加');b.click();})()")
    await asyncio.sleep(.5)
    n0 = await ev("JSON.stringify({subs:(todoById(state.drawer.id)||{}).subtasks.length,last:((todoById(state.drawer.id)||{}).subtasks||[]).slice(-1)[0]})")
    print('SUBTASK', n0)
    await ev("(function(){Proto.save();})()")
    await asyncio.sleep(.5)
    # keyboard escape from clean read-only drawer closes it
    await ev("document.querySelector('.drawer .drawer-close').click();'ok'")
    await asyncio.sleep(.4)
    print('CLOSE', await ev("JSON.stringify({drawer:state.drawer})"))
    # mobile create entry
    await ev("state.device='mobile';Proto.forcedDevice='mobile';state.screen='today';render();Proto.enhance();'ok'")
    await asyncio.sleep(.6)
    print('M-NEW', await ev("JSON.stringify({btn:!!document.querySelector('.m-top [data-proto-action=\"new-pick\"]'),title:(document.querySelector('.m-title')||{}).textContent})"))
    await ev("document.querySelector('.m-top [data-proto-action=\"new-pick\"]').click();'ok'")
    await asyncio.sleep(.4)
    print('M-PICK', await ev("JSON.stringify({modal:!!document.querySelector('.proto-modal-scrim'),rows:[...document.querySelectorAll('[data-new]')].map(b=>b.dataset.new)})"))
    await ev("(function(){var b=document.querySelector('[data-new=\"todo\"]');b.click();})()")
    await asyncio.sleep(.6)
    print('M-NEWTODO', await ev("JSON.stringify({screen:state.screen,draft:!!Proto.data.newDraft})"))
    # escape from new page with empty title → leaves without a confirm
    await key('Escape','Escape',27); await asyncio.sleep(.5)
    print('NEW-ESC', await ev("JSON.stringify({screen:state.screen,modal:!!document.querySelector('.proto-modal-scrim')})"))
    # typed title → escape asks first (phone form has no #new-title; use the
    # first input the open form actually draws)
    await ev("state.screen='new-todo';state.device='mobile';Proto.forcedDevice='mobile';Proto.data.newDraft=null;render();Proto.enhance();var t=document.querySelector('#new-title')||document.querySelector('.m-app input')||document.querySelector('.new-page .form-input');t.value='临时草稿';t.dispatchEvent(new Event('input'));'ok'")
    await asyncio.sleep(.5)
    await key('Escape','Escape',27); await asyncio.sleep(.4)
    print('DIRTY-ESC', await ev("JSON.stringify({modal:!!document.querySelector('.proto-modal-scrim'),title:(document.querySelector('.proto-modal-head')||{}).textContent})"))
    await ev("(function(){var b=[...document.querySelectorAll('.proto-modal-foot .proto-btn')].find(x=>x.textContent==='继续编辑');b.click();})()")
    await asyncio.sleep(.4)
    print('STAY', await ev("JSON.stringify({screen:state.screen,modal:!!document.querySelector('.proto-modal-scrim')})"))
    print('ERRORS', errs[:3] if errs else 'none')
  p.terminate()
asyncio.run(main())
