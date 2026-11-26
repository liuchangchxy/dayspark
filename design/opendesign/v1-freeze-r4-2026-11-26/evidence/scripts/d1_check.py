import asyncio, json, subprocess, time, urllib.request
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9488; PROFILE='/tmp/ds-d1'
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
    await e("Proto.openTodo('recurring'); 'ok'"); await asyncio.sleep(.3)
    print('before',await e("JSON.stringify({btn:[...document.querySelectorAll('.drawer [data-action=toggle-done]')].map(b=>b.textContent.trim()),undo:!!document.querySelector('[data-action=undo-done]')})"))
    await e("document.querySelector('.drawer [data-action=toggle-done]').click(); 'ok'"); await asyncio.sleep(.3)
    await e("document.querySelector('[data-occ=\"2026-11-27\"]').click(); 'ok'"); await asyncio.sleep(.4)
    print('after',await e("JSON.stringify({done:state.doneInstances,btn:[...document.querySelectorAll('.drawer [data-action=toggle-done]')].map(b=>b.textContent.trim()),undo:!!document.querySelector('[data-action=undo-done]'),toast:(document.querySelector('.toast')||{}).textContent})"))
  p.terminate()
asyncio.run(m())
