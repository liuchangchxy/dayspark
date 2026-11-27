import asyncio, json, subprocess, time, urllib.request, base64, os, websockets
from pathlib import Path
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
URL = (Path(__file__).resolve().parents[2] / 'dayspark-prototype.html').as_uri()
OUT='/tmp/r6final'; PORT=9700
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
        async def ev(expr):
            r=await call('Runtime.evaluate',{'expression':expr,'returnByValue':True})
            q=r.get('result',{})
            if q.get('exceptionDetails'): print('ERR',q['exceptionDetails'].get('exception',{}).get('description','')[:120])
            return q.get('result',{}).get('value')
        async def shot(name,w,h,screen,extra="",theme='light'):
            await call('Emulation.clearDeviceMetricsOverride')
            await call('Emulation.setDeviceMetricsOverride',{'width':w,'height':h,'deviceScaleFactor':1,'mobile':w<700,'screenWidth':w,'screenHeight':h})
            await asyncio.sleep(.3)
            await ev(f"Proto.data.prefs.theme='{theme}';document.body.dataset.protoTheme='{theme}';state.device='{'mobile' if w<700 else 'desktop'}';state.screen='{screen}';state.drawer=null;state.capture='compact';state.variant='normal';{extra}render();Proto.enhance();document.querySelector('.proto-bar').style.display='none';'ok'")
            await asyncio.sleep(.9)
            r=await call('Page.captureScreenshot',{'format':'png'})
            open(os.path.join(OUT,name),'wb').write(base64.b64decode(r['result']['data']))
            print('shot',name,await ev('innerWidth'))
        await call('Runtime.enable'); await call('Page.enable'); await asyncio.sleep(1.5)
        await shot('d-settings.png',1440,1000,'settings-home')
        await shot('d-settings-data.png',1440,1000,'settings-data')
        await shot('m-detail.png',390,844,'today',"state.drawer={type:'todo',id:'report'};")
        await shot('t-detail.png',1024,768,'today',"state.drawer={type:'todo',id:'report'};")
        await shot('d-dark-today.png',1440,1000,'today',theme='dark')
        await shot('m-dark-today.png',390,844,'today',theme='dark')
        await shot('d-week.png',1440,1000,'cal-week')
        await shot('d-dark-week.png',1440,1000,'cal-week',theme='dark')
        await shot('m-cal.png',390,844,'cal-day')
        await shot('m-dark-cal.png',390,844,'cal-day',theme='dark')
    p.terminate()
asyncio.run(main())
