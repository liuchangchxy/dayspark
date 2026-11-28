import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9419; PROFILE='/tmp/ds-qaprobe'
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
    await send('Runtime.enable'); await asyncio.sleep(1)
    async def qa(text, todo=False):
      await ev("Proto.quickAdd(); 'ok'"); await asyncio.sleep(.25)
      await ev(f"(()=>{{const i=document.querySelector('#qa-title'); i.value={json.dumps(text)}; i.dispatchEvent(new Event('input',{{bubbles:true}})); return 'ok'}})()")
      await asyncio.sleep(.2)
      if todo:
        await ev("window.__forceTodo=true; 'ok'")
        await ev("(()=>{const s=document.querySelector('#qa-type'); s.value='todo'; s.dispatchEvent(new Event('change',{bubbles:true})); return 'ok'})()")
        await asyncio.sleep(.2)
      sugg=await ev("document.querySelector('#qa-suggest').textContent.trim()")
      typ=await ev("document.querySelector('#qa-type').value")
      before_e=await ev('EVENTS.length'); before_t=await ev('TODOS.length')
      await ev("[...document.querySelectorAll('.proto-modal-foot .proto-btn')].find(b=>b.textContent.trim()===(window.__forceTodo?'添加待办':'保存')).click(); 'ok'")
      await asyncio.sleep(.4)
      after_e=await ev('EVENTS.length'); after_t=await ev('TODOS.length')
      last_e=await ev("JSON.stringify(EVENTS[EVENTS.length-1])") if after_e>before_e else ''
      last_t=await ev("JSON.stringify(TODOS[0])") if after_t>before_t else ''
      return {'sugg':sugg,'type':typ,'de':after_e-before_e,'dt':after_t-before_t,'event':last_e,'todo':last_t}
    await ev("window.__forceTodo=false; 'ok'"); print('case1',await qa('明天下午三点交报告'))
    print('case2',await qa('明天下午三点交报告', True))
    await ev("window.__forceTodo=false; 'ok'"); print('case3',await qa('明天交报告'))
    await ev("window.__forceTodo=false; 'ok'"); print('case4',await qa('今天23:30出发'))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
