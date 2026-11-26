import asyncio,json,subprocess,time,urllib.request,base64,os
import websockets
CHROME='/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';PORT=9574;PROFILE='/tmp/ds-r5-ev';URL='file:///tmp/ds-r5/dayspark-prototype.html';OUT='/tmp/r5-evidence'
subprocess.run(['rm','-rf',PROFILE]);p=subprocess.Popen([CHROME,'--headless=new','--disable-gpu',f'--remote-debugging-port={PORT}',f'--user-data-dir={PROFILE}','--window-size=1440,1000',URL],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
u=None
for _ in range(100):
 try:
  d=json.load(urllib.request.urlopen(f'http://127.0.0.1:{PORT}/json'));pp=[t for t in d if t.get('type')=='page']
  if pp:u=pp[0]['webSocketDebuggerUrl'];break
 except:pass
 time.sleep(.25)
async def m():
 async with websockets.connect(u,max_size=2**25) as ws:
  i=0; errs=[]
  async def s(mm,**pa):
   nonlocal i;i+=1;mi=i;await ws.send(json.dumps({'id':mi,'method':mm,'params':pa}))
   while 1:
    x=json.loads(await ws.recv())
    if x.get('method')=='Runtime.exceptionThrown':errs.append(str(x.get('params',{}).get('exceptionDetails',{}).get('text')))
    if x.get('id')==mi:return x
  async def e(x):
   r=await s('Runtime.evaluate',expression=x,returnByValue=True,awaitPromise=True);q=r.get('result',{});return q.get('result',{}).get('value') if not q.get('exceptionDetails') else {'ERR':q['exceptionDetails'].get('text')}
  async def shot(name,w=1440,h=1000,expr=None,wait=1.2):
   await s('Emulation.setDeviceMetricsOverride',width=w,height=h,deviceScaleFactor=1,mobile=False)
   if expr: await e(expr)
   await asyncio.sleep(wait)
   r=await s('Page.captureScreenshot',format='png');open(os.path.join(OUT,name),'wb').write(base64.b64decode(r['result']['data']));print('shot',name)
  async def reload_clean():
   await e("localStorage.clear();location.reload();'ok'");await asyncio.sleep(1.8)
  await s('Runtime.enable');await s('Page.enable');await asyncio.sleep(1.2)
  await shot('desktop-today.png',expr="Proto.data.prefs.theme='light';state.device='desktop';state.screen='today';state.drawer=null;render();'ok'")
  await shot('desktop-todos.png',expr="state.screen='todo-all';state.drawer=null;render();'ok'")
  await shot('desktop-calendar.png',expr="state.screen='cal-week';render();'ok'")
  await shot('desktop-settings-home.png',expr="state.screen='settings-home';render();'ok'")
  await shot('desktop-settings.png',expr="state.screen='settings-account';render();'ok'")
  await shot('desktop-mcp.png',expr="state.screen='settings-mcp';render();'ok'")
  await shot('desktop-widgets.png',expr="state.screen='widgets';render();'ok'")
  # history
  await shot('desktop-calendar-history.png',expr="(()=>{DS3.toggleDone('report');state.screen='cal-week';render();return 'ok'})()")
  # legacy banner
  await reload_clean()
  await shot('desktop-calendar-legacy.png',expr="(()=>{state.localTodos.push({id:'legacy-ev',title:'旧版重复计划',cal:'work',repeat:'每周五',legacyRrule:'FREQ=WEEKLY;BYDAY=FR',legacyConfirmed:false,plan:{date:TODAY,start:'11:00',end:'12:00'}});state.screen='cal-week';render();return 'ok'})()")
  # mobile
  await reload_clean()
  await shot('mobile-today.png',390,844,"Proto.data.prefs.theme='light';state.device='mobile';state.screen='today';state.drawer=null;state.mobileDueOpen=false;render();'ok'")
  await shot('mobile-deadline-expanded.png',390,844,"(()=>{for(let i=0;i<4;i++)state.localTodos.push({id:'due-ev'+i,title:'截止测试 '+i,cal:'personal',due:TODAY});state.mobileDueOpen=false;render();return 'ok'})()")
  await e("(()=>{const b=document.querySelector('[data-action=toggle-mobile-due]');if(b)b.click();return 'ok'})()"); await asyncio.sleep(.5)
  await shot('mobile-deadline-expanded-2.png',390,844,"(()=>{const g=[...document.querySelectorAll('.m-group')].find(x=>x.textContent.includes('今天截止'));if(g)g.scrollIntoView({block:'start'});return 'ok'})()")
  await shot('mobile-todos.png',390,844,"state.screen='todo-all';state.drawer=null;render();'ok'")
  await shot('mobile-calendar.png',390,844,"state.screen='cal-day';state.drawer=null;render();'ok'")
  await shot('mobile-settings.png',390,844,"state.screen='settings-home';render();'ok'")
  await shot('mobile-mcp.png',390,844,"state.screen='settings-mcp';render();'ok'")
  # tablet
  await reload_clean()
  await shot('tablet-today.png',1024,768,"state.device='desktop';state.screen='today';state.drawer=null;render();'ok'")
  await shot('tablet-calendar.png',1024,768,"state.screen='cal-week';render();'ok'")
  # themes
  await reload_clean()
  await shot('dark-today.png',1440,1000,"Proto.data.prefs.theme='dark';state.screen='today';render();'ok'")
  await shot('dark-calendar.png',1440,1000,"state.screen='cal-week';render();'ok'")
  await shot('dark-settings.png',1440,1000,"state.screen='settings-mcp';render();'ok'")
  await shot('warm-today.png',1440,1000,"Proto.data.prefs.theme='warm';state.screen='today';render();'ok'")
  print('errors',errs[:5])
  print('lastEnhancer',await e("Proto.lastEnhancerError"))
 p.terminate()
asyncio.run(m())
