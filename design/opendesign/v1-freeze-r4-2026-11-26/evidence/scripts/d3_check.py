import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9490; PROFILE='/tmp/ds-d3'
URL='file:///tmp/r4-final/dayspark-prototype.html'
subprocess.run(['rm','-rf',PROFILE])
p=subprocess.Popen([CHROME,'--headless=new','--disable-gpu',f'--remote-debugging-port={PORT}',f'--user-data-dir={PROFILE}','--window-size=1440,1000',URL],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
u=None
for _ in range(80):
  try:
    d=json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json')); pp=[t for t in d if t.get('type')=='page']
    if pp: u=pp[0]['webSocketDebuggerUrl']; break
  except: pass
  time.sleep(.25)
async def m():
  async with websockets.connect(u,max_size=2**24) as ws:
    i=0
    async def s(mm,**pa):
      nonlocal i;i+=1;mi=i;await ws.send(json.dumps({'id':mi,'method':mm,'params':pa}))
      while True:
        x=json.loads(await ws.recv())
        if x.get('id')==mi:return x
    async def e(x):
      r=await s('Runtime.evaluate',expression=x,returnByValue=True);q=r.get('result',{})
      return q.get('result',{}).get('value')
    await s('Runtime.enable'); await asyncio.sleep(1)
    # give it a plan with a date, to reproduce the old plan-date fallback
    await e("DS3.addAllocation(todoById('recurring'),{date:'2026-11-26',start:'09:00',end:'10:00',occurrenceDate:'2026-11-27'}); Proto.openTodo('recurring'); 'ok'"); await asyncio.sleep(.4)
    print('delete route',await e("(()=>{const b=document.querySelector('.drawer [data-action=delete]'); if(!b)return 'MISSING'; return JSON.stringify({action:b.dataset.action,proto:b.dataset.protoAction,text:b.textContent.trim()})})()"))
    await e("document.querySelector('.drawer [data-action=delete]').click(); 'ok'"); await asyncio.sleep(.3)
    print('after',await e("JSON.stringify({confirm:state.confirmDelete,occPicker:!!document.querySelector('[data-occ]'),text:(document.querySelector('.confirm-modal')||{}).innerText||''})"))
  p.terminate()
asyncio.run(m())
