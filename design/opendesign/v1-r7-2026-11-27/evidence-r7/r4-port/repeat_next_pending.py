import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9477; PROFILE='/tmp/ds-repnext'
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
    i=0
    async def send(m,**pa):
      nonlocal i; i+=1; mid=i
      await ws.send(json.dumps({'id':mid,'method':m,'params':pa}))
      while True:
        x=json.loads(await ws.recv())
        if x.get('id')==mid: return x
    async def ev(x):
      r=await send('Runtime.evaluate',expression=x,returnByValue=True); res=r.get('result',{})
      if 'exceptionDetails' in res: return {'ERR':res['exceptionDetails'].get('text'),'d':res.get('result',{}).get('description')}
      return res.get('result',{}).get('value')
    await send('Runtime.enable'); await asyncio.sleep(1)
    print('instances',await ev("JSON.stringify(DS3.instanceList(todoById('recurring'),-30,90).filter(x=>['2026-11-20','2026-11-27','2026-12-04'].includes(x.date)).map(x=>[x.date,x.done]))"))
    print('done today',await ev("DS3.toggleDone('recurring','2026-11-20'); JSON.stringify(state.doneInstances)"))
    print('after',await ev("JSON.stringify(DS3.instanceList(todoById('recurring'),-30,90).filter(x=>['2026-11-20','2026-11-27','2026-12-04'].includes(x.date)).map(x=>[x.date,x.done]))"))
    print('isDone 20/27',await ev("[DS3.isInstanceDone(todoById('recurring'),'2026-11-20'),DS3.isInstanceDone(todoById('recurring'),'2026-11-27')]"))
  p.terminate()
asyncio.run(main())
