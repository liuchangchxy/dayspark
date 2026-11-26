import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9474; PROFILE='/tmp/ds-repanchor'
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
    await send('Runtime.enable'); await send('Log.enable'); await asyncio.sleep(1)
    await ev("Proto.baseGo('new-todo'); render(); 'ok'"); await asyncio.sleep(.4)
    await ev("(()=>{const i=document.querySelector('#new-title'); i.value='重复锚点测试'; i.dispatchEvent(new Event('input',{bubbles:true})); const d=Proto.data.newDraft; d.repeat='每周五'; d.repeatEnd='永不结束'; d.plans=[{id:'draft-anchor-test',date:'2026-11-27',start:'09:00',end:'10:00',state:'active',occurrenceDate:'2026-11-27'}]; d.plan=d.plans[0]; render(); return 'ok'})()"); await asyncio.sleep(.3)
    print('click save',await ev("(()=>{const b=[...document.querySelectorAll('.new-page button')].find(x=>x.textContent.trim().includes('记下待办')); if(!b)return 'MISSING'; b.click(); return 'ok'})()")); await asyncio.sleep(.5)
    print('saved',await ev("(()=>{const t=TODOS.find(x=>x.title==='重复锚点测试'); return JSON.stringify(t&&{repeat:t.repeat,anchor:t.repeatAnchor,due:t.due,plans:DS3.allocations(t).map(p=>[p.date,p.start,p.end])})})()"))
    print('errs',[e.get('method') for e in errs])
  p.terminate()
asyncio.run(main())
