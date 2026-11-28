from pathlib import Path
import asyncio, json, subprocess, time, urllib.request, websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9734
URL = (Path(__file__).resolve().parents[2] / 'dayspark-prototype.html').as_uri()
subprocess.run(['rm','-rf',f'/tmp/prof-{PORT}'])
p=subprocess.Popen([CHROME,'--headless=new','--disable-gpu',f'--remote-debugging-port={PORT}','--user-data-dir=/tmp/prof-'+str(PORT),'--window-size=1440,1000',URL],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
u=None
for _ in range(100):
    try:
        d=json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json')); pp=[t for t in d if t.get('type')=='page']
        if pp: u=pp[0]['webSocketDebuggerUrl']; break
    except Exception: pass
    time.sleep(.25)
async def main():
    async with websockets.connect(u,max_size=2**27) as ws:
        i=0
        async def call(m,params=None):
            nonlocal i; i+=1; mid=i
            await ws.send(json.dumps({'id':mid,'method':m,'params':params or {}}))
            while True:
                x=json.loads(await ws.recv())
                if x.get('id')==mid: return x
        async def ev(e):
            r=await call('Runtime.evaluate',{'expression':e,'returnByValue':True})
            q=r.get('result',{})
            if q.get('exceptionDetails'): print('ERR',q['exceptionDetails'].get('exception',{}).get('description','')[:160])
            return q.get('result',{}).get('value')
        await call('Runtime.enable'); await call('Page.enable'); await asyncio.sleep(1.5)
        await ev("state.screen='capture';state.capture='parsed';state.variant='normal';render();Proto.enhance();'ok'")
        await asyncio.sleep(.4)
        print('parsed buttons', await ev("[...document.querySelectorAll('.cp-actions .btn')].map(b=>b.textContent.trim()).join(' | ')"))
        print('head', await ev("document.querySelector('.cp-title').textContent+' / '+document.querySelector('.cp-sub').textContent"))
        print('submit ->', await ev("(()=>{const n=EVENTS.length;document.querySelector('.cp-actions .btn.primary').click();return JSON.stringify({n:EVENTS.length,added:EVENTS.length>n,last:EVENTS[EVENTS.length-1],toast:state.toast})})()"))
        await asyncio.sleep(.5)
        await ev("state.screen='capture';state.capture='parsed';state.suggestionRemoved=true;render();Proto.enhance();'ok'")
        await asyncio.sleep(.3)
        print('removed copy', await ev("document.querySelector('.cp-title').textContent+' / '+document.querySelector('.cp-actions .btn.primary').textContent+' / '+document.querySelector('.cp-hint').textContent"))
        print('removed submit ->', await ev("(()=>{const n=allTodos().length;document.querySelector('.cp-actions .btn.primary').click();return JSON.stringify({added:allTodos().length>n,last:allTodos()[allTodos().length-1]&&allTodos()[allTodos().length-1].title})})()"))
    p.terminate()
asyncio.run(main())
