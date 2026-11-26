import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9445; PROFILE='/tmp/ds-plaindone'
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
    await ev("(()=>{const t=todoById('report'); DS3.addAllocation(t,{date:'2026-11-20',start:'09:00',end:'10:00'}); render(); return 'ok'})()")
    print('before',await ev("JSON.stringify({done:Array.from(state.done),plans:todoById('report').plans.map(p=>[p.start,p.state])})"))
    await ev("window.__v3ToggleDone('report',null); render(); 'ok'"); await asyncio.sleep(.2)
    print('done',await ev("JSON.stringify({done:Array.from(state.done),status:todoById('report').status,plans:todoById('report').plans.map(p=>[p.start,p.state]),undo:state.undoKind})"))
    await ev("window.__v3UndoDone(); render(); 'ok'"); await asyncio.sleep(.2)
    print('undo',await ev("JSON.stringify({done:Array.from(state.done),plans:todoById('report').plans.map(p=>[p.start,p.state])})"))
    # raw status done
    await ev("window.__v3ToggleDone('plant',null); render(); 'ok'")
    print('plant un',await ev("JSON.stringify({status:todoById('plant').status,done:Array.from(state.done),isDone:window.isDone(todoById('plant'))})"))
    await ev("window.__v3ToggleDone('plant',null); render(); 'ok'")
    print('plant re',await ev("JSON.stringify({status:todoById('plant').status,done:Array.from(state.done),isDone:window.isDone(todoById('plant'))})"))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
