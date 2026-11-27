from pathlib import Path
import asyncio, json, subprocess, time, urllib.request, websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'; PORT=9730
URL = (Path(__file__).resolve().parents[2] / 'dayspark-prototype.html').as_uri()
subprocess.run(['rm','-rf',f'/tmp/prof-{PORT}'])
p=subprocess.Popen([CHROME,'--headless=new','--disable-gpu',f'--remote-debugging-port={PORT}',f'--user-data-dir=/tmp/prof-{PORT}','--window-size=1440,1000',URL],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
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
            if q.get('exceptionDetails'): print('ERR',q['exceptionDetails'].get('exception',{}).get('description','')[:200])
            return q.get('result',{}).get('value')
        await call('Runtime.enable'); await call('Page.enable'); await asyncio.sleep(1.5)
        await ev("state.screen='ai-chat';state.variant='normal';render();Proto.enhance();'ok'")
        await asyncio.sleep(.4)
        print('buttons', await ev("[...document.querySelectorAll('.ai-proposal button')].map(b=>b.textContent.trim()+'/'+b.dataset.protoAction+'/'+b.dataset.msg).join(' | ')"))
        await ev("document.querySelector('.ai-action-primary').click();'ok'")
        await asyncio.sleep(1.2)
        print('primary ->', await ev("JSON.stringify({screen:state.screen,title:(document.querySelector('#new-title')||document.querySelector('.new-page input')||{}).value})"))
        await call('Page.navigate',{'url':URL}); await asyncio.sleep(1.5)
        await ev("state.screen='ai-chat';state.variant='normal';render();Proto.enhance();'ok'")
        await asyncio.sleep(.4)
        await ev("[...document.querySelectorAll('.ai-proposal button')].find(b=>b.textContent.includes('安排时间')).click();'ok'")
        await asyncio.sleep(.6)
        print('secondary ->', await ev("JSON.stringify({modal:(document.querySelector('.proto-modal')||{}).textContent?document.querySelector('.proto-modal').textContent.slice(0,80):null})"))
    p.terminate()
asyncio.run(main())
