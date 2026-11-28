import asyncio, json, subprocess, time, urllib.request, os, glob
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9405; PROFILE='/tmp/ds-backupprobe'; DL='/tmp/ds-downloads'
URL='file:///tmp/r4-final/dayspark-prototype.html'
subprocess.run(['rm','-rf',PROFILE,DL]); os.makedirs(DL,exist_ok=True)
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
    await send('Runtime.enable'); await send('Log.enable'); await asyncio.sleep(1)
    print('dlb', await send('Browser.setDownloadBehavior',behavior='allow',downloadPath=DL,eventsEnabled=True))
    print('goto',await ev("Proto.goSection('backup'); 'ok'")); await asyncio.sleep(.6)
    print('screen',await ev('state.screen'),await ev('state.variant'))
    print('actions',await ev("JSON.stringify([...document.querySelectorAll('[data-proto-action^=backup], [data-action^=backup]')].map(e=>[e.dataset.protoAction,e.dataset.action,e.textContent.trim().slice(0,20)]))"))
    print('click',await ev("(()=>{const e=[...document.querySelectorAll('[data-proto-action=backup-export],[data-action=backup-export]')][0]; if(!e)return 'MISSING'; e.click(); return 'ok'})()"))
    await asyncio.sleep(1.4)
    print('variant',await ev('state.variant'))
    print('files',glob.glob(DL+'/*'))
    if glob.glob(DL+'/*'):
      j=json.load(open(glob.glob(DL+'/*')[0])); print('keys',j.keys(), 'statekeys',list(j.get('state',{}).keys())[:20], 'ai',j.get('data',{}).get('ai'))
    print('errs',json.dumps([e.get('method') for e in evs if e.get('method') in ('Runtime.exceptionThrown','Log.entryAdded')]))
  p.terminate()
asyncio.run(main())
