import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9476; PROFILE='/tmp/ds-dragsecond'
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
    print('seed second',await ev("DS3.addAllocation(todoById('report'),{date:'2026-11-20',start:'11:00',end:'12:00'}).id"))
    await ev("state.selectedDate='2026-11-20'; Proto.baseGo('cal-day'); render(); 'ok'"); await asyncio.sleep(.5)
    print('blocks',await ev("JSON.stringify([...document.querySelectorAll('.day-col .cal-block[data-alloc]')].map(b=>[b.dataset.alloc,b.dataset.id,b.textContent.trim().slice(0,8)]))"))
    info=await ev("(()=>{const b=document.querySelector('.day-col .cal-block[data-alloc]'); if(!b)return null; const r=b.getBoundingClientRect(); const c=b.closest('.day-col').getBoundingClientRect(); return {x:r.x+12,y:r.y+8,ch:c.height};})()")
    print('info',info)
    x,y=info['x'],info['y']; yy=y+info['ch']*0.06
    await send('Input.dispatchMouseEvent',type='mousePressed',x=x,y=y,button='left',clickCount=1)
    await send('Input.dispatchMouseEvent',type='mouseMoved',x=x,y=y+info['ch']*0.03,button='left')
    await send('Input.dispatchMouseEvent',type='mouseMoved',x=x,y=yy,button='left'); await asyncio.sleep(.1)
    await send('Input.dispatchMouseEvent',type='mouseReleased',x=x,y=yy,button='left',clickCount=1); await asyncio.sleep(.5)
    print('after',await ev("JSON.stringify(DS3.allocations(todoById('report')).map(p=>[p.id,p.start,p.end,p.date]))"))
    print('errs',[e.get('method') for e in errs])
  p.terminate()
asyncio.run(main())
