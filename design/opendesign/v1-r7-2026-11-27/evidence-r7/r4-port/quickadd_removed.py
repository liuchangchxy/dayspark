import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9479; PROFILE='/tmp/ds-qarem'
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
    await ev("Proto.quickAdd(); 'ok'"); await asyncio.sleep(.25)
    await ev("(()=>{const i=document.querySelector('#qa-title'); i.value='明天下午三点交报告'; i.dispatchEvent(new Event('input',{bubbles:true})); return 'ok'})()"); await asyncio.sleep(.3)
    print('before',await ev("JSON.stringify({type:document.querySelector('#qa-type').value,sugg:document.querySelector('#qa-suggest').textContent.trim()})"))
    print('remove',await ev("(()=>{const b=document.querySelector('[data-qa-remove]'); if(!b)return 'MISSING'; b.click(); return 'ok'})()")); await asyncio.sleep(.25)
    print('after remove',await ev("JSON.stringify({type:document.querySelector('#qa-type').value,sugg:document.querySelector('#qa-suggest').textContent.trim()})"))
    print('save',await ev("(()=>{const b=[...document.querySelectorAll('.proto-modal-foot .proto-btn')].find(x=>x.textContent.trim()==='保存'); if(!b)return 'MISSING'; b.click(); return 'ok'})()")); await asyncio.sleep(.4)
    print('todo',await ev("JSON.stringify(TODOS[0])"))
    print('errs',[e.get('method') for e in errs])
  p.terminate()
asyncio.run(main())
